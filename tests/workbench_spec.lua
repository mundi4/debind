-- The import workbench. `DebindShare/Workbench.lua`.
--
-- Two things live here and they fail differently.
--
-- **Layer mapping** decides where a batch's actions end up. Getting it wrong is not a display bug:
-- the same actions on the same keys behave differently one layer over, with nothing missing and
-- nothing overwritten, which is the failure mode this whole design is built around. The cases that
-- matter are the ones a single-class test cannot produce - a string from a class with more specs
-- than ours, or from a class whose spec numbers mean something else entirely.
--
-- **The drawer** holds work across a `/reload`, so what it stores has to survive being written to
-- SavedVariables and read back. That is why the string is stored rather than the payload.

return function(DebindPrivate, DebindShare)
    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "assertion failed", 2);
        end
    end

    local Constants = DebindPrivate.Constants;
    local CLASS = Constants.PLAYER_CLASS;
    local GUID = "Player-1-TESTGUID";

    -- The shim's class is a druid, which has four specs. That is what makes "a spec we do not
    -- have" reachable below: a class with five would be needed otherwise.
    check(CLASS == "DRUID", "이 스펙은 드루이드(4특성) 전제로 쓰였다: " .. tostring(CLASS));

    --- A profile with every layer stood up. The layers themselves are what mapping asks about, so
    --- they have to exist even though nothing here reads an action out of them.
    local function ResetProfile()
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {}, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    ResetProfile();

    ---------------------------------------------------------------------------
    -- Layer keys
    --
    -- The key is what says "these two groups came from the same layer". It has to come from the
    -- descriptor's **value**: the sender shares one descriptor table between the groups of a layer,
    -- but a serialize/deserialize round trip is free to hand back a separate table per group, and
    -- then identity says every group came from a layer of its own.
    ---------------------------------------------------------------------------

    local LayerKey = DebindShare.LayerKey;

    test("같은 뜻의 서로 다른 테이블은 같은 키다", function()
        check(LayerKey({ scope = "general" }) == LayerKey({ scope = "general" }), "일반");
        check(LayerKey({ scope = "class", class = "DRUID", spec = 2 })
            == LayerKey({ scope = "class", class = "DRUID", spec = 2 }), "직업/특성");
        check(LayerKey({ scope = "character", spec = 0 })
            == LayerKey({ scope = "character", spec = 0 }), "캐릭터");
    end);

    test("다른 뜻은 다른 키다", function()
        local keys = {
            LayerKey({ scope = "general" }),
            LayerKey({ scope = "class", class = "DRUID", spec = 0 }),
            LayerKey({ scope = "class", class = "DRUID", spec = 2 }),
            LayerKey({ scope = "class", class = "MAGE", spec = 2 }),
            LayerKey({ scope = "character", spec = 0 }),
            LayerKey({ scope = "character", spec = 2 }),
        };
        local seen = {};
        for _, key in ipairs(keys) do
            check(key ~= nil, "키가 안 나옴");
            check(not seen[key], "두 레이어가 한 키로 접혔다: " .. tostring(key));
            seen[key] = true;
        end
    end);

    -- `spec` absent and `spec = 0` are the same layer. The format leaves out what it does not need
    -- to say, so both spellings arrive.
    test("빠진 spec은 0과 같은 레이어다", function()
        check(LayerKey({ scope = "class", class = "DRUID" })
            == LayerKey({ scope = "class", class = "DRUID", spec = 0 }), "직업");
        check(LayerKey({ scope = "character" }) == LayerKey({ scope = "character", spec = 0 }),
            "캐릭터");
    end);

    -- A scope from a schema this version does not know. Answering nil is what makes the caller
    -- leave those groups out rather than fold them into some other layer.
    test("모르는 scope는 키가 없다", function()
        check(LayerKey({ scope = "raid" }) == nil, "모르는 scope를 받아들였다");
        check(LayerKey(nil) == nil, "nil");
        check(LayerKey("general") == nil, "테이블이 아닌 것");
    end);

    ---------------------------------------------------------------------------
    -- Default destinations
    --
    -- Layer to layer: one decision per source layer, every group from it follows.
    ---------------------------------------------------------------------------

    local Destination = DebindShare.DefaultDestinationLayerID;

    --- What `LAYER_INFOS` (Profile.lua) numbers them: 1 general, 2..6 class spec 0..4,
    --- 7..11 character spec 0..4. Spelled out so a failure names a layer rather than a number.
    local GENERAL, CLASS_ALL, CLASS_SPEC2 = 1, 2, 4;
    local CHAR_ALL, CHAR_SPEC2 = 7, 9;

    test("일반은 일반으로", function()
        check(Destination({ scope = "general" }) == GENERAL, "일반이 아니다");
    end);

    test("내 직업 레이어는 그 자리 그대로", function()
        check(Destination({ scope = "class", class = CLASS, spec = 0 }) == CLASS_ALL, "직업 공용");
        check(Destination({ scope = "class", class = CLASS, spec = 2 }) == CLASS_SPEC2, "특성 2");
    end);

    test("캐릭터 레이어는 캐릭터로", function()
        check(Destination({ scope = "character", spec = 0 }) == CHAR_ALL, "캐릭터 공용");
        check(Destination({ scope = "character", spec = 2 }) == CHAR_SPEC2, "특성 2");
    end);

    -- **The case a same-class test cannot reach.** Spec 2 is Feral for a druid and Fire for a
    -- mage, so carrying the number across would put a mage's fire bindings in a druid's Feral
    -- layer and call it a mapping. Keeping the scope and dropping the spec is the part that is
    -- actually true.
    test("남의 직업 레이어는 특성을 안 가져온다", function()
        check(Destination({ scope = "class", class = "MAGE", spec = 2 }) == CLASS_ALL,
            "남의 특성 번호를 내 특성으로 읽었다");
        check(Destination({ scope = "class", class = "MAGE", spec = 0 }) == CLASS_ALL, "직업 공용");
    end);

    -- A class with more specs than ours. A druid has four, so spec 5 has no layer here at all -
    -- and `GetLayerID` would have asserted rather than answered, which is why the lookup walks
    -- the layers instead.
    test("우리에게 없는 특성은 공용으로 떨어진다", function()
        check(Destination({ scope = "class", class = CLASS, spec = 5 }) == CLASS_ALL, "직업");
        check(Destination({ scope = "character", spec = 5 }) == CHAR_ALL, "캐릭터");
    end);

    test("모르는 scope는 목적지가 없다", function()
        check(Destination({ scope = "raid" }) == nil, "목적지를 지어냈다");
        check(Destination(nil) == nil, "nil");
    end);

    ---------------------------------------------------------------------------
    -- Collecting source layers
    ---------------------------------------------------------------------------

    local function Payload(groups)
        return { v = 1, class = CLASS, groups = groups };
    end

    local function Group(layer, key, actionCount)
        local actions = {};
        for i = 1, (actionCount or 1) do
            actions[i] = { type = Constants.SPELL, value = i };
        end
        return { id = 1, key = key, layer = layer, actions = actions };
    end

    test("같은 레이어의 그룹들이 한 줄로 접힌다", function()
        -- Separate tables with the same meaning, which is what a decoded payload looks like.
        local layers = DebindShare.CollectSourceLayers(Payload({
            Group({ scope = "class", class = CLASS, spec = 2 }, "F", 2),
            Group({ scope = "class", class = CLASS, spec = 2 }, "G", 3),
            Group({ scope = "general" }, "H", 1),
        }));

        check(#layers == 2, "줄 수 " .. #layers);
        check(layers[1].key == LayerKey({ scope = "general" }), "일반이 먼저다");
        check(layers[1].groupCount == 1 and layers[1].actionCount == 1, "일반 개수");
        check(layers[2].groupCount == 2 and layers[2].actionCount == 5,
            "특성 개수 " .. layers[2].groupCount .. "/" .. layers[2].actionCount);
    end);

    -- The mapping block reads like the tab strip, and inside the class layers our own class comes
    -- first: it is the one with a real mapping, the rest need a decision.
    test("일반 -> 직업 -> 캐릭터 차례이고 내 직업이 앞선다", function()
        local layers = DebindShare.CollectSourceLayers(Payload({
            Group({ scope = "character", spec = 0 }),
            Group({ scope = "class", class = "MAGE", spec = 1 }),
            Group({ scope = "general" }),
            Group({ scope = "class", class = CLASS, spec = 1 }),
        }));

        local order = {};
        for i, entry in ipairs(layers) do
            order[i] = entry.descriptor.scope .. "/" .. tostring(entry.descriptor.class);
        end
        check(table.concat(order, " ")
            == "general/nil class/" .. CLASS .. " class/MAGE character/nil",
            "차례: " .. table.concat(order, " "));
    end);

    test("모르는 scope의 그룹은 줄을 안 만든다", function()
        local layers = DebindShare.CollectSourceLayers(Payload({
            Group({ scope = "raid" }),
            Group({ scope = "general" }),
        }));
        check(#layers == 1, "줄 수 " .. #layers);
        check(layers[1].descriptor.scope == "general", "일반이 아니다");
    end);

    ---------------------------------------------------------------------------
    -- The drawer
    --
    -- **The decoder is stubbed here on purpose.** Whether a real string survives the trip is
    -- `export_spec`'s question and it answers it against the real libraries; this file's question
    -- is what the drawer does with an answer once it has one. Stubbing also keeps these cases
    -- running under fengari, where LibDeflate cannot decompress - gated on the real decoder they
    -- would be skipped by `npm test` and only ever run by hand.
    ---------------------------------------------------------------------------

    local realDecode = DebindShare.DecodeExportString;
    local STORED = {};

    DebindShare.DecodeExportString = function(str)
        local payload = type(str) == "string" and STORED[strtrim(str)] or nil;
        if (not payload) then
            return nil, "BAD_PAYLOAD";
        end
        return payload;
    end

    local function ResetDrawer()
        _G.DebindShareVars = nil;
        STORED = {};
    end

    local GOOD = "DEB1:good";
    local GOOD_PAYLOAD = Payload({ Group({ scope = "general" }, "F", 1) });

    test("받아들인 문자열이 배치가 된다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local batch = DebindShare.AddBatch(GOOD, "친구");
        check(batch, "배치가 안 만들어짐");
        check(batch.source == "친구", "출처");
        check(#DebindShare.GetBatches() == 1, "서랍에 안 들어감");
        check(DebindShare.GetBatch(batch.id) == batch, "id로 못 찾음");
    end);

    -- Refused where the user is looking at it, rather than becoming a row that fails every time it
    -- is opened.
    test("못 읽는 문자열은 서랍에 안 들어간다", function()
        ResetDrawer();

        local batch, reason = DebindShare.AddBatch("DEB1:쓰레기");
        check(batch == nil, "받아들였다");
        check(reason == "BAD_PAYLOAD", "이유 " .. tostring(reason));
        check(#DebindShare.GetBatches() == 0, "서랍에 들어갔다");
    end);

    -- What SavedVariables holds is the string. The payload is the same data spelled out in full,
    -- and keeping it would undo the reason this addon is loaded on demand at all.
    test("서랍에 남는 것은 문자열이지 페이로드가 아니다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local batch = DebindShare.AddBatch("  " .. GOOD .. "\n");
        check(batch.text == GOOD, "다듬어서 저장하지 않았다: " .. tostring(batch.text));
        check(batch.payload == nil, "페이로드를 저장했다");
        check(DebindShare.GetBatchPayload(batch) == GOOD_PAYLOAD, "다시 못 읽음");
    end);

    test("id는 지워도 다시 안 쓰인다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;

        local first = DebindShare.AddBatch(GOOD);
        DebindShare.DeleteBatch(first.id);
        local second = DebindShare.AddBatch(GOOD);

        check(second.id ~= first.id, "지운 id가 재활용됐다 - 그 배치에 붙은 배지가 남의 것이 된다");
        check(#DebindShare.GetBatches() == 1, "배치 수");
        check(DebindShare.GetBatch(first.id) == nil, "지운 것이 남아 있다");
    end);

    test("없는 것을 지우면 아무 일도 안 난다", function()
        ResetDrawer();
        check(DebindShare.DeleteBatch(999) == false, "지웠다고 답했다");
    end);

    -- A batch has to be openable after a `/reload`, and a reload is exactly what SavedVariables
    -- being a plain table has to survive. Nothing here may be a closure, a metatable, or a
    -- reference to a live profile table.
    test("배치는 저장 가능한 값만 들고 있다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local batch = DebindShare.AddBatch(GOOD);

        check(getmetatable(batch) == nil, "메타테이블이 붙어 있다");
        for k, v in pairs(batch) do
            local vt = type(v);
            check(vt == "string" or vt == "number" or vt == "boolean" or vt == "table",
                "저장 못 하는 값: " .. tostring(k) .. " = " .. vt);
        end
    end);

    ---------------------------------------------------------------------------
    -- Expiry
    --
    -- Never acted on here - the list shows it. A batch that vanished without the user having been
    -- told it was going to is the one outcome the drawer is not allowed to produce.
    ---------------------------------------------------------------------------

    local DAY = 24 * 60 * 60;
    local realTime = _G.time;

    local function AtDaysLater(days, fn)
        local base = realTime();
        _G.time = function() return base + days * DAY; end
        local ok, err = pcall(fn);
        _G.time = realTime;
        if (not ok) then
            error(err, 0);
        end
    end

    test("갓 받은 배치는 만료가 멀다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local batch = DebindShare.AddBatch(GOOD);

        check(DebindShare.GetSecondsUntilExpiry(batch) > 0, "이미 만료");
        check(DebindShare.IsExpiringSoon(batch) == false, "바로 만료 임박이라고 한다");
    end);

    test("한 달이 다 되면 임박이라고 말한다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local batch = DebindShare.AddBatch(GOOD);

        AtDaysLater(28, function()
            check(DebindShare.IsExpiringSoon(batch), "임박이라고 안 한다");
            check(DebindShare.GetSecondsUntilExpiry(batch) > 0, "아직 지나지는 않았다");
        end);
        AtDaysLater(31, function()
            check(DebindShare.GetSecondsUntilExpiry(batch) < 0, "지났는데 안 지났다고 한다");
        end);
    end);

    -- Pinning is what takes a batch out of the sweep entirely, so it must not merely push the date
    -- out - there is no date it could be pushed to that is far enough.
    test("핀을 꽂으면 만료가 아예 없다", function()
        ResetDrawer();
        STORED[GOOD] = GOOD_PAYLOAD;
        local batch = DebindShare.AddBatch(GOOD);
        batch.pinned = true;

        check(DebindShare.GetSecondsUntilExpiry(batch) == nil, "핀인데 만료가 있다");
        AtDaysLater(365, function()
            check(DebindShare.IsExpiringSoon(batch) == false, "일 년 뒤에 임박이라고 한다");
        end);
    end);

    DebindShare.DecodeExportString = realDecode;

    return T;
end
