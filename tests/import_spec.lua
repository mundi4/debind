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

    --- A payload holding one general layer. **The path is the address** -- there is no descriptor
    --- to write, so a test that is not about addressing says nothing about it at all.
    local function General(actions)
        return { v = 1, class = CLASS, shared = { GENERAL = actions } };
    end

    --- Plans a payload holding exactly one action and hands it back.
    local function PlanOne(payload, batchID)
        local placements = DebindShare.PlanImport(payload, batchID or 1);
        check(#placements == 1, "액션 수 " .. #placements);
        return placements[1].action, placements[1];
    end

    ResetProfile();

    ---------------------------------------------------------------------------
    -- Quarantine and keys
    ---------------------------------------------------------------------------

    test("들어오는 것은 전부 배지를 달고 온다", function()
        local placements = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 2, key = "F", seq = 2 },
        }), 9);

        check(#placements == 2, "액션 수");
        for _, placement in ipairs(placements) do
            check(placement.action.imported == 9,
                "배지가 없다 - 이 액션은 들어가는 순간 키에 걸린다");
        end
    end);

    -- The key is on the action and it **is** the group: two actions carrying one key are one set,
    -- and nothing anywhere has to declare that.
    test("실키는 그대로 들어온다", function()
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 774, key = "SHIFT-G", seq = 1 } }));
        check(action.key == "SHIFT-G", "키 " .. tostring(action.key));
    end);

    test("키 없이 온 액션은 키 없이 들어간다", function()
        local action = PlanOne(General({ { type = Constants.SPELL, value = 774 } }));
        check(action.key == nil, "없던 키가 생겼다");
    end);

    ---------------------------------------------------------------------------
    -- Synthetic keys
    ---------------------------------------------------------------------------

    -- **A number on the wire is a key group whose key was not sent.** It has to be renumbered here:
    -- the number is unique inside its own string and nowhere else, so two strings waiting at once
    -- would both open at 1 and the overview would head two unrelated sets with the same words.
    test("숫자 키는 프로필 안에서 다시 매긴다", function()
        ResetProfile();

        local first = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 1, key = 1, seq = 1 },
            { type = Constants.SPELL, value = 2, key = 2, seq = 1 },
        }), 1);
        DebindPrivate.PlaceImportedActions(first);

        -- A second string, whose own numbering starts over at 1.
        local second = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 3, key = 1, seq = 1 } }), 2);

        local taken = {};
        for _, placement in ipairs(first) do
            check(type(placement.action.key) == "number", "숫자 키가 아니다");
            taken[placement.action.key] = true;
        end
        check(not taken[second[1].action.key],
            "두 번째 배치가 첫 배치의 번호를 다시 썼다: " .. tostring(second[1].action.key));
    end);

    test("같은 숫자 키였던 것들은 같이 남는다", function()
        ResetProfile();

        local placements = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 1, key = 4, seq = 1 },
            { type = Constants.SPELL, value = 2, key = 7, seq = 1 },
            { type = Constants.SPELL, value = 3, key = 4, seq = 2 },
        }), 1);

        local byValue = {};
        for _, placement in ipairs(placements) do
            byValue[placement.action.value] = placement.action.key;
        end
        check(byValue[1] == byValue[3], "한 묶음이 갈렸다");
        check(byValue[1] ~= byValue[2], "다른 묶음이 합쳐졌다");
    end);

    -- **The reused number would be one this session cannot see.** `LayerArray` is the view of the
    -- eleven layers this character has; another class's layers are stored all the same and are not
    -- in it. Counting the view would reissue a number that is alive over there, and the two would
    -- meet - both headed `키를 모름 #3` - the day the reader logs that class.
    test("안 보이는 레이어의 숫자 키도 세어 넣는다", function()
        ResetProfile();

        local mage = DebindShare.PlanImport({
            v = 1, class = CLASS,
            shared = { classes = { MAGE = { [2] = {
                { type = Constants.SPELL, value = 1, key = 1, seq = 1 } } } } },
        }, 1);
        DebindPrivate.PlaceImportedActions(mage);

        -- The premise: it really did land somewhere the layer view does not reach.
        local seen = 0;
        for layerID = 1, 11 do
            local layer = DebindPrivate.GetProfileLayer(layerID);
            if (layer) then
                for _, action in layer:Enumerate() do
                    if (type(action.key) == "number") then
                        seen = seen + 1;
                    end
                end
            end
        end
        check(seen == 0, "전제가 틀렸다 - 이 캐릭터의 레이어에서 " .. seen .. "개가 보인다");

        local next2 = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 2, key = 1, seq = 1 } }), 2);
        check(next2[1].action.key ~= mage[1].action.key,
            "안 보이는 번호를 재사용했다: " .. tostring(next2[1].action.key));
    end);

    -- **The receiving end of "leave the keys out".** Quarantine says nothing changes until the
    -- reader accepts; this says their keys are not touched even then. Wanting somebody's actions
    -- without their keybinds is ordinary, and until now it could only be had by asking the sender
    -- to tick the box.
    --
    -- **The grouping has to survive it.** Renaming the key rather than dropping it is what does
    -- that - a key split across conditional actions still has to arrive as one thing to give a key
    -- to.
    test("키를 빼고 가져오면 숫자 키로 바뀌고 묶음은 남는다", function()
        ResetProfile();

        local placements = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 2, key = "F", seq = 2 },
            { type = Constants.SPELL, value = 3, key = "G", seq = 1 },
        }), 1, { stripKeys = true });

        local byValue = {};
        for _, placement in ipairs(placements) do
            check(type(placement.action.key) == "number",
                "실키가 남았다: " .. tostring(placement.action.key));
            byValue[placement.action.value] = placement.action.key;
        end
        check(byValue[1] == byValue[2], "한 키였던 둘이 갈렸다");
        check(byValue[1] ~= byValue[3], "다른 키였던 것이 합쳐졌다");
    end);

    test("키 없이 온 것은 키를 빼도 여전히 키가 없다", function()
        ResetProfile();
        local action = PlanOne(General({ { type = Constants.SPELL, value = 1 } }));
        check(action.key == nil, "안 묶였던 것에 키가 붙었다: " .. tostring(action.key));
        check(action.imported ~= nil, "배지는 그대로 있어야 한다");
    end);

    ---------------------------------------------------------------------------
    -- The order inside a group
    ---------------------------------------------------------------------------

    -- **Which of a key's actions goes first is design, not decoration.** It travels as `seq` under
    -- its own name: the number means nothing in the layer that receives it, and what makes that
    -- harmless is that `PlaceImportedActions` overwrites every one of them on the way in.
    test("실려온 seq가 액션에 남는다", function()
        ResetProfile();
        local placements = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 11, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 22, key = "F", seq = 2 },
            { type = Constants.SPELL, value = 33, key = "F", seq = 3 },
        }), 1);

        check(#placements == 3, "액션 수 " .. #placements);
        for i, placement in ipairs(placements) do
            check(placement.action.seq == i,
                i .. "번째 액션의 seq가 " .. tostring(placement.action.seq));
        end
    end);

    -- **No key, no number** is an invariant of the profile (`ClearActionKey`), and a hand-made
    -- string is exactly the input that would walk one past it.
    test("키 없이 온 액션의 seq는 버린다", function()
        ResetProfile();
        local action = PlanOne(General({ { type = Constants.SPELL, value = 1, seq = 4 } }));
        check(action.seq == nil, "키 없는 액션이 번호를 들고 들어왔다: " .. tostring(action.seq));
    end);

    -- **Both ends read one whitelist now** (`ACTION_FIELDS`). It used to be a blacklist here, so a
    -- wire field nobody had named rode straight into the profile - which is what forced the ranking
    -- to travel under a name other than `seq` in the first place.
    test("명단에 없는 선의 필드는 액션에 안 남는다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 774, key = "F", seq = 1,
              somethingANewerSchemaAdded = true } }));
        check(action.somethingANewerSchemaAdded == nil,
            "모르는 선 필드가 프로필까지 들어왔다");
        check(action.value == 774 and action.key == "F", "명단에 있는 것은 들어와야 한다");
    end);

    test("$상태 조건은 명단에 없어도 통과한다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SPELL, value = 1, key = "F", seq = 1, ["$state3"] = true } }));
        check(action["$state3"] == true, "$상태 조건이 걸러졌다");
    end);

    ---------------------------------------------------------------------------
    -- Hand-made strings
    --
    -- **A pasted string is untrusted input and none of this may error.** The schema check turns
    -- away anything from a version we do not know, so what is left is a string somebody built by
    -- hand - which is exactly what that rule exists for. An error here goes off inside
    -- `CommitBatch`, after part of a batch has already been placed.
    ---------------------------------------------------------------------------

    test("액션 자리에 액션이 아닌 것이 있어도 안 터진다", function()
        ResetProfile();
        local placements = DebindShare.PlanImport(General({
            5,
            { type = Constants.SPELL, value = 1, key = "F", seq = 1 },
            "쓰레기",
        }), 1);
        check(#placements == 1, "액션 수 " .. #placements);
        check(placements[1].action.value == 1, "엉뚱한 것이 들어왔다");
    end);

    -- `MacroMatches`는 테이블이 아니면 false를 내는데, 그 뒤에서 같은 값을 그대로 인덱싱하고
    -- 있었다. 타입을 물어놓고 답을 안 쓰는 꼴이라 그 갈래가 곧바로 터졌다.
    test("macro 스냅샷이 테이블이 아니어도 안 터진다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.MACRO, value = "이름", key = "F", seq = 1, macro = 5 } }));
        check(action.type == Constants.MACRO, "타입이 바뀌었다");
        check(action.value == "이름", "값이 바뀌었다");
    end);

    test("setstate가 테이블이 아니어도 안 터진다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SETSTATE, key = "F", seq = 1, setstate = 5 } }));
        check(action.type == Constants.SETSTATE, "타입이 바뀌었다");
        check(action.setstate == nil, "포맷 필드가 액션에 남았다");
    end);

    ---------------------------------------------------------------------------
    -- Where each action lands
    ---------------------------------------------------------------------------

    -- **한 키는 레이어를 넘어도 한 묶음이다.** The key is on the action and the layer is the path it
    -- sits under, so one set routinely has two addresses. Splitting it would undo the one thing a
    -- keyless string still says: the reader would be handed two headings for what was one key and
    -- would give them two keys - and then both fire.
    test("한 키가 레이어 여럿에 걸쳐도 묶음 하나로 들어온다", function()
        ResetProfile();

        local placements = DebindShare.PlanImport({
            v = 1, class = CLASS,
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 1, key = "F", seq = 1 } },
                classes = { [CLASS] = { [0] = {
                    { type = Constants.SPELL, value = 2, key = "F", seq = 1 } } } },
            },
        }, 1);

        check(#placements == 2, "액션 수 " .. #placements);
        local scopes = {};
        for _, placement in ipairs(placements) do
            check(placement.action.key == "F", "키가 갈렸다");
            scopes[placement.scope] = placement;
        end
        check(scopes.general, "일반 자리에 안 갔다");
        check(scopes.class and scopes.class.class == CLASS and scopes.class.spec == 0,
            "직업 공용 자리에 안 갔다");
    end);

    -- **A layer is a coordinate, not something to translate.** Both profiles use the same one, so
    -- another class's layer keeps its class *and* its spec: a mage's spec 2 is a mage's spec 2 on
    -- every account. `workbench_spec` measures the addressing in detail; here it just has to be
    -- what the placement actually uses.
    test("목적지는 보낸 쪽 좌표 그대로다", function()
        ResetProfile();
        local _, general = PlanOne(General({ { type = Constants.SPELL, value = 1 } }));
        check(general.scope == "general", "일반이 아니다: " .. tostring(general.scope));

        local _, foreign = PlanOne({
            v = 1, class = CLASS,
            shared = { classes = { MAGE = { [2] = { { type = Constants.SPELL, value = 1 } } } } },
        });
        check(foreign.scope == "class" and foreign.class == "MAGE" and foreign.spec == 2,
            "남의 직업 좌표를 내 것으로 바꿨다: " .. tostring(foreign.class)
                .. "/" .. tostring(foreign.spec));
    end);

    -- A class name no client has. Counted rather than dropped in silence: the window says how many
    -- did not land.
    test("갈 데 없는 주소는 세어서 빠진다", function()
        ResetProfile();
        local placements, skipped = DebindShare.PlanImport({
            v = 1, class = CLASS,
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 2 } },
                classes = { NOSUCHCLASS = { [0] = { { type = Constants.SPELL, value = 1 } } } },
            },
        }, 1);
        check(#placements == 1, "빠뜨릴 것을 안 빠뜨렸다");
        check(skipped == 1, "안 센다 - 조용히 사라진다");
    end);

    -- **A line the reader unticked is not a skip.** Both leave the actions out, but one of them is
    -- the answer they gave and the other is this version having nowhere to put it. Counting the
    -- first would put "%d came from a layer this version does not know" on screen for a layer they
    -- themselves declined.
    test("안 고른 줄은 빠지되 세지 않는다", function()
        ResetProfile();
        local placements, skipped = DebindShare.PlanImport({
            v = 1, class = CLASS,
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 1 } },
                classes = { [CLASS] = { [0] = { { type = Constants.SPELL, value = 2 } } } },
            },
        }, 1, { lines = { ["shared.general"] = true } });

        check(#placements == 1, "고른 줄만 들어와야 한다: " .. #placements);
        check(placements[1].scope == "general", "엉뚱한 줄이 들어왔다");
        check(skipped == 0, "안 고른 것을 못 놓은 것으로 세었다: " .. skipped);
    end);

    -- **갈 데 없는 것은 고르는 중에도 세어야 한다.** 줄은 놓일 수 있는 것으로만 세우므로
    -- (`CollectImportLines`), 놓을 데가 없는 액션은 애초에 물어본 적이 없고 따라서 읽는 사람이
    -- 뺀 것일 수가 없다. 필터를 먼저 보면 그것들이 조용히 사라진다 - 창은 "2개를 가져왔습니다"라
    -- 말하고 못 넣은 다섯은 입에 올리지 않는다. 그리고 창은 언제나 필터를 켜고 부른다.
    test("고르는 중이어도 갈 데 없는 것은 세어서 뺀다", function()
        ResetProfile();
        local placements, skipped = DebindShare.PlanImport({
            v = 1, class = CLASS,
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 2 } },
                classes = { NOSUCHCLASS = { [0] = { { type = Constants.SPELL, value = 1 } } } },
            },
        }, 1, { lines = { ["shared.general"] = true } });

        check(#placements == 1, "액션 수 " .. #placements);
        check(skipped == 1, "안 센다 - 조용히 사라진다: " .. skipped);
    end);

    -- 줄이 안 선 쪽도 마찬가지다. 4특성 캐릭터의 캐릭터 레이어를 3특성 직업이 받으면 그 줄은
    -- 아예 안 서고(`CollectImportLines`), 그래서 `lines`에도 없다. 그것이 "안 골랐다"로 읽히면
    -- 안 된다.
    test("줄조차 안 선 것도 세어서 뺀다", function()
        ResetProfile();
        local placements, skipped = DebindShare.PlanImport({
            v = 1, class = CLASS,
            shared = { GENERAL = { { type = Constants.SPELL, value = 3 } } },
            char = { [5] = { { type = Constants.SPELL, value = 1 },
                             { type = Constants.SPELL, value = 2 } } },
        }, 1, { lines = { ["shared.general"] = true } });

        check(#placements == 1, "액션 수 " .. #placements);
        check(skipped == 2, "못 놓은 둘을 안 세었다: " .. skipped);
    end);

    ---------------------------------------------------------------------------
    -- SETSTATE: name axis back to the bitpack
    ---------------------------------------------------------------------------

    test("상태 이름이 비트팩으로 돌아온다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SETSTATE, key = "F", seq = 1,
              setstate = { mode = "toggle", state = "$state3" } } }));

        local mode, index = DebindPrivate.GetSetCustomStateModeAndIndex(action.value);
        check(mode == "toggle", "모드 " .. tostring(mode));
        check(index == 3, "상태 번호 " .. tostring(index));
        check(action.setstate == nil, "포맷 필드가 액션에 남았다");
    end);

    test("세 모드가 다 돌아온다", function()
        ResetProfile();
        for _, mode in ipairs({ "on", "off", "toggle" }) do
            local action = PlanOne(General({
                { type = Constants.SETSTATE, key = "F", seq = 1,
                  setstate = { mode = mode, state = "$state1" } } }));
            check(DebindPrivate.GetSetCustomStateModeAndIndex(action.value) == mode,
                "모드가 안 돌아옴: " .. mode);
        end
    end);

    -- **A name this version does not know must not become a number.** Any number resolves, and it
    -- would resolve to some other state - the key would quietly set the wrong one.
    test("모르는 상태 이름은 값이 안 생긴다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.SETSTATE, key = "F", seq = 1,
              setstate = { mode = "toggle", state = "$nosuchstate" } } }));
        check(action.value == nil, "엉뚱한 상태를 가리키는 값이 생겼다: " .. tostring(action.value));
        check(action.type == Constants.SETSTATE, "타입은 그대로여야 한다");
    end);

    ---------------------------------------------------------------------------
    -- MACRO: the reference comes back only on a three-way match
    ---------------------------------------------------------------------------

    local SNAPSHOT = { name = "내매크로", body = "/cast 재생", icon = 9, scope = "account" };

    local function MacroPayload()
        return General({ { type = Constants.MACRO, value = "내매크로", key = "F", seq = 1,
            macro = SNAPSHOT } });
    end

    test("이름·스코프·내용이 다 맞으면 참조가 살아 돌아온다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 재생", index = 3 } };

        local action = PlanOne(MacroPayload());
        check(action.type == Constants.MACRO, "MACROTEXT로 떨어졌다");
        check(action.value == "내매크로", "이름 " .. tostring(action.value));
    end);

    -- **The case the snapshot exists for.** A macro of the same name with different contents is
    -- somebody else's macro, and firing it would be silent and wrong.
    test("이름은 같은데 내용이 다르면 본문으로 떨어진다", function()
        ResetProfile();
        MACROS = { ["내매크로"] = { name = "내매크로", icon = 9, body = "/cast 다른것", index = 3 } };

        local action = PlanOne(MacroPayload());
        check(action.type == Constants.MACROTEXT, "남의 매크로를 그대로 가리킨다");
        check(action.value == "/cast 재생", "본문 " .. tostring(action.value));
        check(action.name == "내매크로", "이름을 안 들고 왔다");
    end);

    test("같은 이름이 아예 없으면 본문으로 떨어진다", function()
        ResetProfile();
        local action = PlanOne(MacroPayload());
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

        local action = PlanOne(MacroPayload());
        check(action.type == Constants.MACROTEXT, "스코프를 안 본다");
    end);

    -- Dangling when it was sent: no snapshot travelled, so there is nothing to fall back to and the
    -- action stays what it was. Red text is what says so on this side
    -- (`BINDING_ISSUE_MISSING_MACRO`).
    test("스냅샷 없이 온 매크로는 그대로 둔다", function()
        ResetProfile();
        local action = PlanOne(General({
            { type = Constants.MACRO, value = "없는것", key = "F", seq = 1 } }));
        check(action.type == Constants.MACRO, "타입이 바뀌었다");
        check(action.value == "없는것", "이름이 바뀌었다");
    end);

    ---------------------------------------------------------------------------
    -- Placing them
    ---------------------------------------------------------------------------

    test("놓으면 그 레이어에 서고 순서 번호를 받는다", function()
        ResetProfile();
        local placements = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 774, key = "F", seq = 1 } }), 5);

        DebindPrivate.PlaceImportedActions(placements);

        local layer = DebindPrivate.GetProfileLayer(1);
        check(layer:GetNumActions() == 1, "레이어에 안 들어감");
        local action = layer:GetAction(1);
        check(action.imported == 5, "배지가 없다");
        -- **The sender's number does not survive landing.** It is a place inside their layer; this
        -- one hands out its own, which is what makes carrying it on the wire harmless.
        check(action.seq == 1, "이 그룹의 번호가 아니다: " .. tostring(action.seq));
    end);

    -- **보낸 쪽 차례가 그대로 선다.** 도착 번호가 실려온 `seq`를 더하므로, 배치 안의 차례는
    -- 저장 배열 순서가 아니라 보낸 사람이 정한 것이 된다. 아래는 그 둘을 일부러 어긋나게
    -- 세운다 - 배열 순서대로 매기는 구현에서는 3 1 2가 나온다.
    test("한 그룹은 실려온 seq 차례로 번호를 받는다", function()
        ResetProfile();
        local placements = DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 30, key = "F", seq = 3 },
            { type = Constants.SPELL, value = 10, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 20, key = "F", seq = 2 },
        }), 1);
        DebindPrivate.PlaceImportedActions(placements);

        local layer = DebindPrivate.GetProfileLayer(1);
        for _, action in layer:Enumerate() do
            check(action.seq == action.value / 10,
                "값 " .. action.value .. "의 번호가 " .. tostring(action.seq));
        end
    end);

    -- **The arrival number is what keeps them behind what was already there.** Renumbering alone
    -- cannot say which of a set is new, so a batch landing on an occupied key has to stand behind
    -- the reader's own without being told which those are.
    test("이미 있던 것 뒤에 선다", function()
        ResetProfile();
        DebindPrivate.GetProfileLayer(1):Insert(
            { type = Constants.SPELL, value = 99, key = "F", seq = 1 });

        DebindPrivate.PlaceImportedActions(DebindShare.PlanImport(General({
            { type = Constants.SPELL, value = 10, key = "F", seq = 1 },
            { type = Constants.SPELL, value = 20, key = "F", seq = 2 },
        }), 1));

        local order = {};
        for _, row in ipairs(DebindPrivate.CollectActionsForKey("F")) do
            order[#order + 1] = row.action.value;
        end
        check(#order == 3 and order[1] == 99 and order[2] == 10 and order[3] == 20,
            "차례: " .. table.concat(order, " "));
    end);

    -- **A class this account has never played still has a place.** The address is the store's, not
    -- the eleven layers this character happens to see, so it goes in and waits there - invisible in
    -- this session and reaching no key, which is what quarantine already promises.
    test("이 세션에 없는 직업 레이어도 저장에는 들어간다", function()
        ResetProfile();
        DebindPrivate.PlaceImportedActions({
            { scope = "class", class = "MAGE", spec = 2,
              action = { type = Constants.SPELL, value = 1, key = "F", imported = 3 } },
        });

        local stored = _G.DebindVars.shared.classes.MAGE;
        check(stored and stored[2] and #stored[2] == 1,
            "마법사 특성2 자리에 안 들어갔다");
        check(stored[2][1].seq ~= nil, "순서 번호를 안 받았다");
    end);

    test("자리가 없는 주소를 가리키면 아무것도 안 놓는다", function()
        ResetProfile();
        -- A scope nothing answers to. `PlaceImportedActions` skips rather than erroring: what it is
        -- handed came off the wire.
        DebindPrivate.PlaceImportedActions({
            { scope = "raid", action = { type = Constants.SPELL } },
        });
        check(DebindPrivate.GetProfileLayer(1):GetNumActions() == 0, "엉뚱한 데 들어갔다");
    end);

    ---------------------------------------------------------------------------
    -- Finding them again
    ---------------------------------------------------------------------------

    -- **What [Accept all] hands to the approver.** The count on that button and the set it
    -- clears both come from here, so the failure this guards is one number being smaller than the
    -- other - and the leftovers would sit badged in a layer that has no screen of its own until
    -- the reader happens to change specialization.
    test("배지 찾기는 지금 특성 밖의 레이어까지 훑는다", function()
        ResetProfile();
        -- Layer 4 is the class layer of spec 2, and the shim's player is spec 1. A batch lands
        -- there routinely: an action is placed by the scope it was sent with, not by the
        -- specialization the reader happens to be in.
        DebindPrivate.PlaceImportedActions({
            { scope = "general",
              action = { type = Constants.SPELL, value = 774, key = "F", imported = 3 } },
            { scope = "class", class = CLASS, spec = 2,
              action = { type = Constants.SPELL, value = 774, key = "G", imported = 3 } },
        });

        -- The premise: the layer that walk is not allowed to use really does leave one out.
        local live = 0;
        for _, layer in DebindPrivate.EnumerateProfileLayers() do
            for _, action in layer:Enumerate() do
                if (action.imported) then
                    live = live + 1;
                end
            end
        end
        check(live == 1, "전제가 틀렸다 - 활성 레이어 훑기가 " .. live .. "개를 봤다");

        check(#DebindPrivate.CollectImportedActions() == 2,
            "오프스펙 레이어의 배지를 놓쳤다");
    end);

    test("배지가 없는 액션은 안 따라온다", function()
        ResetProfile();
        DebindPrivate.PlaceImportedActions({
            { scope = "general",
              action = { type = Constants.SPELL, value = 774, key = "F", imported = 3 } },
        });
        -- The reader's own, placed the ordinary way. Approving must not reach it.
        DebindPrivate.GetProfileLayer(1):Insert({ type = Constants.SPELL, value = 585, key = "H" });

        local badged = DebindPrivate.CollectImportedActions();
        check(#badged == 1, "배지 없는 것까지 세었다: " .. #badged);
        check(badged[1].value == 774, "엉뚱한 액션이 나왔다");
    end);

    return T;
end
