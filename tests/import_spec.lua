-- Turning a received payload back into actions. `DebindShare/Import.lua`.
--
-- **This is the half of the round trip that can be wrong without anyone noticing.** The export side
-- is checked against the format; here the output is an action that goes straight into someone's
-- profile, and a field read back wrongly produces an action that looks fine in a list and does
-- something else when pressed.
--
-- Two of those are the whole reason the format is shaped the way it is:
--
--   * a `SETSTATE` value is `mode | index`, and the wire carries a **name**. Rebuild it against the
--     wrong index and the key sets some other state - silently, because an index always resolves.
--   * a `MACRO` carries a name, and a name is the one broken reference red text cannot see. The
--     snapshot is what turns "your macro of the same name, silently" into a fallback.
--
-- Everything built here also has to arrive quarantined. An action that landed without `imported`
-- is bound the moment it lands, which is the one thing this whole path promises not to do.

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

    ---------------------------------------------------------------------------
    -- The macro store, stubbed. Same shape as the real API, which is what makes
    -- the three-way match actually run.
    ---------------------------------------------------------------------------

    local MACROS = {};

    _G.GetMacroInfo = function(nameOrIndex)
        local macro = MACROS[nameOrIndex];
        if (not macro) then
            return nil;
        end
        return macro.name, macro.icon, macro.body;
    end

    _G.GetMacroIndexByName = function(name)
        local macro = MACROS[name];
        return macro and macro.index or 0;
    end

    local function ResetProfile()
        MACROS = {};
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {}, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    local function Payload(groups)
        return { v = 1, class = CLASS, groups = groups };
    end

    --- Plans one group and hands back the single action in it.
    local function PlanOne(group, batchID)
        local placements = DebindShare.PlanImport(Payload({ group }), batchID or 1);
        check(#placements == 1, "액션 수 " .. #placements);
        return placements[1].action, placements[1].layerID;
    end

    ResetProfile();

    ---------------------------------------------------------------------------
    -- Quarantine and placement
    ---------------------------------------------------------------------------

    test("들어오는 것은 전부 배지를 달고 온다", function()
        local placements = DebindShare.PlanImport(Payload({
            { id = 4, key = "F", layer = { scope = "general" },
              actions = { { type = Constants.SPELL, value = 1 },
                          { type = Constants.SPELL, value = 2 } } },
        }), 9);

        check(#placements == 2, "액션 수");
        for _, placement in ipairs(placements) do
            check(placement.action.imported == 9,
                "배지가 없다 - 이 액션은 들어가는 순간 키에 걸린다");
            check(placement.action.importGroup == 4, "그룹 번호가 없다");
        end
    end);

    -- The key lives on the group, because one group is one key and that is what has to stay
    -- together. Reading it off the action would find nothing at all.
    test("키는 그룹에서 온다", function()
        local action = PlanOne({ id = 1, key = "SHIFT-G", layer = { scope = "general" },
            actions = { { type = Constants.SPELL, value = 774 } } });
        check(action.key == "SHIFT-G", "키 " .. tostring(action.key));
    end);

    test("키 없이 온 그룹은 키 없이 들어간다", function()
        local action = PlanOne({ id = 1, layer = { scope = "general" },
            actions = { { type = Constants.SPELL, value = 774 } } });
        check(action.key == nil, "없던 키가 생겼다");
    end);

    -- Layer to layer. Another class's spec number means something else entirely, so it keeps the
    -- scope and drops the spec (`workbench_spec` measures that in detail; here it just has to be
    -- the thing the placement actually uses).
    test("목적지는 기본 매핑이 낸다", function()
        local _, general = PlanOne({ id = 1, layer = { scope = "general" },
            actions = { { type = Constants.SPELL, value = 1 } } });
        check(general == 1, "일반 레이어가 아니다: " .. tostring(general));

        local _, foreign = PlanOne({ id = 2, layer = { scope = "class", class = "MAGE", spec = 2 },
            actions = { { type = Constants.SPELL, value = 1 } } });
        check(foreign == 2, "남의 특성 번호를 따라갔다: " .. tostring(foreign));
    end);

    -- A scope invented by a newer schema. Counted rather than dropped in silence: the window says
    -- how many did not land.
    test("모르는 레이어는 세어서 빠진다", function()
        local placements, skipped = DebindShare.PlanImport(Payload({
            { id = 1, layer = { scope = "raid" }, actions = { { type = Constants.SPELL, value = 1 } } },
            { id = 2, layer = { scope = "general" }, actions = { { type = Constants.SPELL, value = 2 } } },
        }), 1);
        check(#placements == 1, "빠뜨릴 것을 안 빠뜨렸다");
        check(skipped == 1, "안 센다 - 조용히 사라진다");
    end);

    ---------------------------------------------------------------------------
    -- SETSTATE: name axis back to the bitpack
    ---------------------------------------------------------------------------

    test("상태 이름이 비트팩으로 돌아온다", function()
        local action = PlanOne({ id = 1, key = "F", layer = { scope = "general" },
            actions = { { type = Constants.SETSTATE,
                          setstate = { mode = "toggle", state = "$state3" } } } });

        local mode, index = DebindPrivate.GetSetCustomStateModeAndIndex(action.value);
        check(mode == "toggle", "모드 " .. tostring(mode));
        check(index == 3, "상태 번호 " .. tostring(index));
        check(action.setstate == nil, "포맷 필드가 액션에 남았다");
    end);

    test("세 모드가 다 돌아온다", function()
        for _, mode in ipairs({ "on", "off", "toggle" }) do
            local action = PlanOne({ id = 1, key = "F", layer = { scope = "general" },
                actions = { { type = Constants.SETSTATE,
                              setstate = { mode = mode, state = "$state1" } } } });
            check(DebindPrivate.GetSetCustomStateModeAndIndex(action.value) == mode,
                "모드가 안 돌아옴: " .. mode);
        end
    end);

    -- **A name this version does not know must not become a number.** Any number resolves, and it
    -- would resolve to some other state - the key would quietly set the wrong one.
    test("모르는 상태 이름은 값이 안 생긴다", function()
        local action = PlanOne({ id = 1, key = "F", layer = { scope = "general" },
            actions = { { type = Constants.SETSTATE,
                          setstate = { mode = "toggle", state = "$nosuchstate" } } } });
        check(action.value == nil, "엉뚱한 상태를 가리키는 값이 생겼다: " .. tostring(action.value));
        check(action.type == Constants.SETSTATE, "타입은 그대로여야 한다");
    end);

    ---------------------------------------------------------------------------
    -- MACRO: the reference comes back only on a three-way match
    ---------------------------------------------------------------------------

    local SNAPSHOT = { name = "내매크로", body = "/cast 재생", icon = 9, scope = "account" };

    local function MacroGroup()
        return { id = 1, key = "F", layer = { scope = "general" },
            actions = { { type = Constants.MACRO, value = "내매크로", macro = SNAPSHOT } } };
    end

    test("이름·스코프·내용이 다 맞으면 참조가 살아 돌아온다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생", index = 3 } };

        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACRO, "MACROTEXT로 떨어졌다");
        check(action.value == "내매크로", "이름 " .. tostring(action.value));
    end);

    -- **The case the snapshot exists for.** A macro of the same name with different contents is
    -- somebody else's macro, and firing it would be silent and wrong.
    test("이름은 같은데 내용이 다르면 본문으로 떨어진다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 다른것", index = 3 } };

        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACROTEXT, "남의 매크로를 그대로 가리킨다");
        check(action.value == "/cast 재생", "본문 " .. tostring(action.value));
        check(action.name == "내매크로", "이름을 안 들고 왔다");
    end);

    test("같은 이름이 아예 없으면 본문으로 떨어진다", function()
        ResetProfile();
        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACROTEXT, "없는 매크로를 가리킨다");
        check(action.value == "/cast 재생", "본문");
    end);

    -- Scope is the third leg. An account macro and a character macro of the same name and body are
    -- still two macros, and the sender meant one of them.
    test("스코프가 다르면 본문으로 떨어진다", function()
        ResetProfile();
        local accountLimit = DebindPrivate.GetMacroSlotLimits();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생",
            index = accountLimit + 1 } };

        local action = PlanOne(MacroGroup());
        check(action.type == Constants.MACROTEXT, "스코프를 안 본다");
    end);

    -- Dangling when it was sent: no snapshot travelled, so there is nothing to fall back to and the
    -- action stays what it was. Red text is what says so on this side
    -- (`BINDING_ISSUE_MISSING_MACRO`).
    test("스냅샷 없이 온 매크로는 그대로 둔다", function()
        ResetProfile();
        local action = PlanOne({ id = 1, key = "F", layer = { scope = "general" },
            actions = { { type = Constants.MACRO, value = "없는것" } } });
        check(action.type == Constants.MACRO, "타입이 바뀌었다");
        check(action.value == "없는것", "이름이 바뀌었다");
    end);

    ---------------------------------------------------------------------------
    -- Placing them
    ---------------------------------------------------------------------------

    test("놓으면 그 레이어에 서고 순서 번호를 받는다", function()
        ResetProfile();
        local placements = DebindShare.PlanImport(Payload({
            { id = 1, key = "F", layer = { scope = "general" },
              actions = { { type = Constants.SPELL, value = 774 } } },
        }), 5);

        DebindPrivate.PlaceImportedActions(placements);

        local layer = DebindPrivate.GetProfileLayer(1);
        check(layer:GetNumActions() == 1, "레이어에 안 들어감");
        local action = layer:GetAction(1);
        check(action.imported == 5, "배지가 없다");
        -- **The sender's number stays home.** It would collide with the ones this layer already
        -- handed out, so the receiving layer gives its own (`Export.lua` leaves `seq` behind).
        check(action.seq ~= nil, "순서 번호를 안 받았다");
    end);

    test("빈 자리 없는 레이어를 가리키면 아무것도 안 놓는다", function()
        ResetProfile();
        -- A layer id nothing answers to. `PlaceImportedActions` skips rather than erroring: the
        -- caller is data that came off the wire.
        DebindPrivate.PlaceImportedActions({ { layerID = 99, action = { type = Constants.SPELL } } });
        check(DebindPrivate.GetProfileLayer(1):GetNumActions() == 0, "엉뚱한 데 들어갔다");
    end);

    return T;
end
