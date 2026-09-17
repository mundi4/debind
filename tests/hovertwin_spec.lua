-- **The hover twin, one rule and no special cases** (`devdocs/which-action-a-key-runs.md` §4, §5).
-- No WoW client needed.
--
-- The twin inherits every condition the reader wrote, adds [the pointed unit is there] on the unit
-- the action's Hover Cast mode names, and goes out at that unit unless the reader picked one. §4's
-- table is that rule written out per condition and per mode, and §5's is where each binding aims;
-- both are walked here.
--
-- Which record then wins at a press is `tests/eval_spec.lua`, and whether the tooltip draws any of
-- it is `tests/display_spec.lua`.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local GetBindingIssue = DebindPrivate.GetBindingIssue;
    local CheckUnreachableBindings = DebindPrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebindPrivate.ClearUnreachableBindingCache;

    local T = { passed = 0, failures = {} };

    --- 계정 모드가 프로필 값이라 프로필이 있어야 읽힌다. 이 파일은 액션을 직접 만들어 쓰므로
    --- 레이어는 비어 있어도 되고, 필요한 것은 `Options`가 서 있는 것뿐이다.
    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
        characters = {},
        migrated = {},
        switches = {},
    };
    DebindPrivate.InitDB();

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local castmod = require("castmod");
    local casting = require("casting");

    --- The action's bindings without the self and focus twins, which every action has and which
    --- this file is not about: `[1]` the original, `[2]` the hover twin where there is one.
    local function bindingsOf(action)
        return castmod.without(Constants, DebindPrivate.GetBindingsForAction(action));
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "assertion failed", 2);
        end
    end

    --- One spell on one key, with whatever the case adds. **No `casting`**, so it follows the
    --- account's mode, which is what a newly made action does (§6).
    local function spell(fields)
        local action = { type = Constants.SPELL, value = 585, key = "T" };
        for k, v in pairs(fields or {}) do
            action[k] = v;
        end
        return action;
    end

    --- The same with the action's Hover Cast mode named, which is how one action runs in a mode of
    --- its own (§6).
    local function inMode(mode, fields)
        local action = spell(fields);
        action.casting = { hoverCast = { mode = mode } };
        return action;
    end

    ---------------------------------------------------------------------------
    -- 1. 바인딩이 둘인 액션은 둘 다 죽어야 도달 불가다
    -- (`devdocs/legacy/splitting-an-action-into-bindings.md` §3-1)
    ---------------------------------------------------------------------------

    --- Puts every binding of `cover` ahead of every binding of the subject. **Not the key's tier
    --- order** (`BuildKeyMap`): what is measured is that an action is unreachable only where all of
    --- its bindings were dropped, and a cover standing wholly in front is what can drop them.
    ---
    --- The tables handed to the solver are the ones `IsUnreachableAction` looks up, since both come
    --- from `GetBindingsForAction`'s cache.
    local function coveredPair(cover)
        local subject = { type = Constants.SPELL, value = 586, key = cover.key };
        check(#bindingsOf(subject) == 2, "쌍둥이가 안 생겼다");
        -- **The self and focus twins of both are in**, since the subject is unreachable only where
        -- all of its bindings were dropped. The cover keeps no hover twin of its own: it is the one
        -- binding the case names, and its twin would cover the subject's.
        local bindings = {};
        for _, action in ipairs({ cover, subject }) do
            local list = DebindPrivate.GetBindingsForAction(action);
            for i = #list, 1, -1 do
                if (action == subject or i == 1 or castmod.isTwin(Constants, list[i])) then
                    bindings[#bindings + 1] = list[i];
                end
            end
        end
        ClearUnreachableBindingCache();
        CheckUnreachableBindings(bindings);
        return subject;
    end

    --- 반만 죽은 액션은 도달 불가가 아니다. 원본이든 쌍둥이든 하나는 여전히 나가므로, 그 키는
    --- 개체창 위에서든 밖에서든 한쪽에서 그대로 발동한다.
    ---
    --- **어느 쪽이 죽었는지는 이제 아무 데도 안 적힌다** (2026-09-06, 소유자). 조건이 다른
    --- 액션을 한 키에 여럿 두면 일부가 겹치는 것이 이 애드온의 정상 동작이라, 겹친 자리를
    --- 문제라고 부를 자리가 없다.
    test("쌍둥이만 덮인 액션은 도달 불가가 아니다", function()
        local subject = coveredPair(casting.skipHover({ type = Constants.SPELL, value = 585, key = "T",
            conditions = { units = { unitframe = {} } } }));
        check(not DebindPrivate.IsUnreachableAction(subject), "원본이 살아 있는데 액션이 죽었다");
        check(GetBindingIssue(subject) == nil, "나온 것: " .. tostring(GetBindingIssue(subject)));
    end);

    --- 원본만 죽는 것은 마우스 버튼에서만 생긴다. 키보드 키에서는 원본이 제일 넓은 상자라
    --- 그걸 덮는 것은 쌍둥이도 덮는다. 마우스 버튼은 개체창 조건 없는 원본이 [가리키지 않음]으로
    --- 좁혀져 있어서(`BuildUnitStates`), 같은 버튼의 이웃이 원본만 덮는다.
    test("원본만 덮인 액션도 도달 불가가 아니다", function()
        local subject = coveredPair(casting.skipHover(
            { type = Constants.SPELL, value = 585, key = "BUTTON3" }));
        check(not DebindPrivate.IsUnreachableAction(subject), "쌍둥이가 살아 있는데 액션이 죽었다");
        check(GetBindingIssue(subject) == nil, "나온 것: " .. tostring(GetBindingIssue(subject)));
    end);

    --- **도달 불가는 문제 코드가 아니다** (2026-09-06, 소유자). 액션 자신의 잘못이 아니라 같은
    --- 키의 이웃과의 관계라, `GetBindingIssue`가 아니라 이쪽이 답한다. 한 칸에 같이 있던 동안에는
    --- 덮인 액션이 자기 경고 대신 도달 불가를 냈고, 경고가 화면에서 사라졌다.
    test("둘 다 덮이면 도달 불가고, 그래도 문제 코드는 안 난다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "T" });
        check(DebindPrivate.IsUnreachableAction(subject), "둘 다 덮였는데 액션이 살아 있다");
        check(GetBindingIssue(subject) == nil, "나온 것: " .. tostring(GetBindingIssue(subject)));
    end);

    --- **쌍둥이는 꺼진 개체창 조건이 기억하고 있는 마스크를 안 물려받는다** (2026-09-06).
    --- 조건을 꺼도 고른 값은 남고(끄는 것과 지우는 것은 다르다), 조건이 꺼져 있으니 쌍둥이는
    --- 자기 조건을 스스로 세운다(`UNIT_IS_THERE`). 마스크가 거기까지 따라가면 쌍둥이만 죽은
    --- 조건의 값으로 좁혀진다.
    test("쌍둥이는 꺼진 조건이 남긴 frameTypes를 안 가져온다", function()
        for _, mask in ipairs({ Constants.FRAMETYPE_GROUP, 0 }) do
            local action = spell({ unit = "focus",
                conditions = { units = { unitframe = { disabled = true, frameTypes = mask } } } });
            local list = bindingsOf(action);
            check(list[1].unitFrameTypes == nil,
                "원본이 안 지워졌다: " .. tostring(list[1].unitFrameTypes));
            check(list[2] ~= nil, "쌍둥이가 안 생겼다");
            check(list[2].unitFrameTypes == nil,
                "마스크 " .. mask .. "가 쌍둥이에 남았다: " .. tostring(list[2].unitFrameTypes));
        end
    end);

    ---------------------------------------------------------------------------
    -- 2. Clique가 있어도 옵션은 그대로 돌고, 액션은 빨갛지 않다
    ---------------------------------------------------------------------------

    local function withClique(fn)
        local was = DebindPrivate.CliqueDetected;
        DebindPrivate.CliqueDetected = true;
        local ok, err = pcall(fn);
        DebindPrivate.CliqueDetected = was;
        if (not ok) then error(err, 0); end
    end

    -- **Clique가 있어도 쌍둥이는 그대로 만들어진다** (코드 리뷰, 2026-09-08). 쌍둥이에게 필요한
    -- 것은 마우스 올린 개체 하나뿐이고, 물러난 상태에서도 `GetUnitFrameUnit`은 답한다. 블리자드
    -- 개체창은 우리 행에서, Clique가 쥔 프레임은 Clique의 hover 버튼에서.
    test("Clique가 있어도 액션은 쌍둥이를 갖고 문장이 없다", function()
        withClique(function()
            local action = spell();
            check(GetBindingIssue(action) == nil, "나온 것: " .. tostring(GetBindingIssue(action)));
            local bindings = bindingsOf(action);
            check(bindings[2] ~= nil and bindings[2].unit == "unitframe",
                "Clique가 있다고 쌍둥이를 안 만들었다");
        end);
    end);

    ---------------------------------------------------------------------------
    -- 3. §4의 표: 조건마다, 모드마다
    ---------------------------------------------------------------------------

    local EXISTS = Constants.UNITSTATE_EXISTS;
    local HARM = Constants.UNITSTATE_HARM;
    local NONE = Constants.UNITSTATE_NONE;

    --- 이 액션의 쌍둥이가 어느 유닛을 겨누고 두 유닛 축에서 어떤 상자인지.
    local function twinOf(action)
        return bindingsOf(action)[2];
    end

    local function states(binding, unit)
        return binding.unitStates and binding.unitStates[unit];
    end

    -- 조건이 없으면 쌍둥이는 자기 모드의 유닛에 [있을 때]로 서고 그 유닛으로 나간다.
    test("조건 없는 액션의 쌍둥이는 모드의 유닛에 선다", function()
        for _, mode in ipairs({ "unitframe", "mouseover" }) do
            local twin = twinOf(inMode(mode));
            check(twin ~= nil, mode .. ": 쌍둥이가 없다");
            check(twin.unit == mode, mode .. ": 겨누는 것이 " .. tostring(twin.unit));
            check(states(twin, mode) == EXISTS,
                mode .. ": 상자가 " .. tostring(states(twin, mode)));
        end
    end);

    -- `unitframe`에 건 조건. Unit Frames 모드에서는 그 조건 그대로라 원본과 같은 상자이고,
    -- Mouseover 모드에서는 거기에 [`mouseover` 있음]이 더해져 개체창 위에서만 선다.
    test("unitframe에 건 조건은 모드가 무엇이든 그 유닛에 그대로 선다", function()
        local conditions = { units = { unitframe = { reaction = Constants.REACTION_HARM } } };

        local frames = twinOf(inMode("unitframe", { conditions = conditions }));
        check(frames ~= nil and frames.unit == "unitframe",
            "Unit Frames: 겨누는 것이 " .. tostring(frames and frames.unit));
        check(states(frames, "unitframe") == HARM,
            "Unit Frames: 상자가 " .. tostring(states(frames, "unitframe")));

        local over = twinOf(inMode("mouseover", { conditions = conditions }));
        check(over ~= nil and over.unit == "mouseover",
            "Mouseover: 겨누는 것이 " .. tostring(over and over.unit));
        check(states(over, "unitframe") == HARM,
            "Mouseover: 개체창 조건이 " .. tostring(states(over, "unitframe")));
        check(states(over, "mouseover") == EXISTS,
            "Mouseover: mouseover 축이 " .. tostring(states(over, "mouseover")));
    end);

    -- `mouseover`에 건 조건은 반대 방향으로 같은 일을 한다.
    test("mouseover에 건 조건도 그 유닛에 그대로 선다", function()
        local conditions = { units = { mouseover = { reaction = Constants.REACTION_HARM } } };

        local frames = twinOf(inMode("unitframe", { conditions = conditions }));
        check(frames ~= nil and frames.unit == "unitframe",
            "Unit Frames: 겨누는 것이 " .. tostring(frames and frames.unit));
        check(states(frames, "mouseover") == HARM,
            "Unit Frames: mouseover 조건이 " .. tostring(states(frames, "mouseover")));
        check(states(frames, "unitframe") == EXISTS,
            "Unit Frames: 개체창 축이 " .. tostring(states(frames, "unitframe")));

        local over = twinOf(inMode("mouseover", { conditions = conditions }));
        check(over ~= nil and over.unit == "mouseover",
            "Mouseover: 겨누는 것이 " .. tostring(over and over.unit));
        check(states(over, "mouseover") == HARM,
            "Mouseover: 상자가 " .. tostring(states(over, "mouseover")));
    end);

    --- **만나는 자리가 없으면 안 세운다.** 겨눌 유닛에 [없을 때]를 건 액션은 쌍둥이가 서는 순간과
    --- 겹치는 때가 없다. 솔버가 빈 상자로 떨구기는 하지만 안 만드는 쪽이 싸다.
    test("겨누려는 유닛에 [없을 때]가 걸려 있으면 쌍둥이가 없다", function()
        for _, mode in ipairs({ "unitframe", "mouseover" }) do
            local action = inMode(mode, { unit = "target",
                conditions = { units = { [mode] = false } } });
            check(twinOf(action) == nil, mode .. ": 모순인데 쌍둥이가 생겼다");
        end
    end);

    --- **[없을 때]를 건 것이 겨누지 않는 유닛이면 쌍둥이는 서고, 그 조건을 그대로 들고 간다.**
    --- `unitframe` [없을 때] + Mouseover 모드가 §4 표의 그 줄이다: 개체창 위에서는 안 나가고
    --- 월드 유닛과 명판 위에서는 나간다.
    test("개체창에 [없을 때]를 건 액션도 Mouseover 모드에서는 쌍둥이가 있다", function()
        local twin = twinOf(inMode("mouseover", { unit = "target",
            conditions = { units = { unitframe = false } } }));
        check(twin ~= nil, "쌍둥이가 없다");
        check(states(twin, "unitframe") == NONE,
            "개체창 축이 " .. tostring(states(twin, "unitframe")));
        check(states(twin, "mouseover") == EXISTS,
            "mouseover 축이 " .. tostring(states(twin, "mouseover")));
    end);

    --- **다른** 유닛에 걸린 조건은 쌍둥이를 막지도 좁히지도 않고 그대로 따라간다.
    test("다른 유닛에 걸린 조건은 쌍둥이를 안 막는다", function()
        local twin = twinOf(inMode("unitframe", { unit = "target", conditions = { units = {
            focus = { reaction = Constants.REACTION_HARM } } } }));
        check(twin ~= nil, "쌍둥이가 없다");
        check(states(twin, "focus") == HARM,
            "focus 조건이 쌍둥이에서 " .. tostring(states(twin, "focus")));
        check(states(twin, "unitframe") == EXISTS, "쌍둥이가 개체창 축에 안 섰다");
    end);

    --- **겨누려는 유닛에 걸린 조건이 좁혀 들어가지 덮어쓰지 않는다** (2026-09-12, 소유자).
    --- 덮어쓰면 쌍둥이가 그 축에서 원본보다 넓어지고, 솔버가 원본을 지워서 그 키가 커서 밑이
    --- 아군이든 적이든 그쪽으로 나갔다 (2026-09-12에 잼).
    test("겨누려는 유닛에 걸린 조건이 쌍둥이로 좁혀 들어간다", function()
        for _, mode in ipairs({ "unitframe", "mouseover" }) do
            local action = inMode(mode, { conditions = { units = {
                [mode] = { reaction = Constants.REACTION_HARM } } } });
            local list = bindingsOf(action);
            check(list[2] ~= nil, mode .. ": 쌍둥이가 없다");
            check(states(list[2], mode) == HARM,
                mode .. ": 쌍둥이의 조건이 " .. tostring(states(list[2], mode)));
            check(states(list[1], mode) == HARM,
                mode .. ": 원본의 조건이 " .. tostring(states(list[1], mode)));
        end
    end);

    --- **사용자가 건 개체창 조건의 마스크는 쌍둥이로 따라간다.** 마스크는 그 조건의 축이라
    --- 조건과 함께 움직이고, 조건을 안 건 액션의 쌍둥이는 `UNIT_IS_THERE`를 세우므로 실을
    --- 마스크 자체가 없다.
    test("살아 있는 개체창 조건의 마스크는 쌍둥이로 따라간다", function()
        local mask = Constants.FRAMETYPE_GROUP;
        local twin = twinOf(inMode("unitframe", { unit = "target",
            conditions = { units = { unitframe = { frameTypes = mask } } } }));
        check(twin ~= nil, "쌍둥이가 없다");
        check(twin.unitFrameTypes == mask, "쌍둥이의 마스크가 " .. tostring(twin.unitFrameTypes));
    end);

    ---------------------------------------------------------------------------
    -- 4. §5의 표: 어디로 나가나
    ---------------------------------------------------------------------------

    -- **고른 유닛은 고정이다.** 조합키를 쥐어도 유닛을 가리켜도 그 유닛이고, 그러면서 쌍둥이는
    -- 있으므로 그 액션은 세 누름 모두에서 제 차례를 지킨다. **`none`은 고른 유닛이 아니다**:
    -- 누르기 전에 아무것도 안 정하므로 쌍둥이는 가리킨 유닛을 겨누고 시전만 `none`으로 나간다.
    test("고른 대상의 쌍둥이는 그 대상으로, none의 쌍둥이는 가리킨 유닛으로 겨눈다", function()
        for _, unit in ipairs({ "unitframe", "mouseover", "focus", "target", "player", "tank", "custom1" }) do
            local twin = twinOf(spell({ unit = unit }));
            check(twin ~= nil and twin.unit == unit,
                "대상 " .. unit .. "의 쌍둥이가 겨누는 것: " .. tostring(twin and twin.unit));
        end

        local twin = twinOf(spell({ unit = "none" }));
        check(twin ~= nil and twin.unit == "unitframe",
            "대상 none의 쌍둥이가 겨누는 것: " .. tostring(twin and twin.unit));
        check(DebindPrivate.CastUnitOf(twin) == "none",
            "대상 none의 쌍둥이가 나가는 곳: " .. tostring(DebindPrivate.CastUnitOf(twin)));
    end);

    -- **대상을 못 싣는 타입도 쌍둥이를 받고, 그 쌍둥이도 유닛을 싣는다** (§3). 유닛을 실어 주되
    -- 그것을 쓸 수 있는지는 그 액션의 몫이다.
    test("대상을 못 싣는 타입의 쌍둥이도 가리킨 유닛을 겨눈다", function()
        local twin = twinOf({ type = Constants.MACROTEXT, value = "/cast x", key = "T" });
        check(twin ~= nil and twin.unit == "unitframe",
            "매크로 쌍둥이가 겨누는 것: " .. tostring(twin and twin.unit));
    end);

    -- **Cast as usual은 쌍둥이를 막지 않고, 쌍둥이를 원본이 가는 곳으로 내보낸다** (§6). 쌍둥이가
    -- 없으면 그 액션은 마지막 층에만 서서, 앞에 두었어도 가리킨 누름을 뒤의 액션에 넘긴다.
    test("Cast as usual인 액션의 쌍둥이는 원본이 가는 곳으로 나간다", function()
        for _, mode in ipairs({ "unitframe", "mouseover" }) do
            local action = spell({ unit = "focus" });
            action.casting = { hoverCast = { mode = mode, aim = "usual" } };
            local twin = twinOf(action);
            check(twin ~= nil and twin.unit == "focus",
                mode .. ": 쌍둥이가 겨누는 것: " .. tostring(twin and twin.unit));
        end

        -- 대상이 없는 액션에서는 원본도 비어 있으므로 쌍둥이도 비고, 게임이 대상을 놓는다.
        local action = spell();
        action.casting = { hoverCast = { mode = "unitframe", aim = "usual" } };
        local twin = twinOf(action);
        check(twin ~= nil, "대상 없는 액션의 쌍둥이가 없다");
        check(twin.unit == nil, "쌍둥이가 겨누는 것: " .. tostring(twin.unit));
    end);

    ---------------------------------------------------------------------------
    -- 5. Casting의 네 값이 바인딩을 넣고 뺀다 (§6)
    ---------------------------------------------------------------------------

    --- **Skip takes the action out of the pointed press** (§6): no twin, and the original stands only
    --- while the mode's unit is not there. The mouse button's implicit [no unit frame] is not what
    --- measures it, so the key here is a keyboard one.
    test("Skip this action이면 쌍둥이가 없고 원본은 모드의 유닛이 없을 때만 선다", function()
        for _, mode in ipairs({ "unitframe", "mouseover" }) do
            local action = spell();
            action.casting = { hoverCast = { mode = mode, aim = "skip" } };
            local list = bindingsOf(action);
            check(list[2] == nil, mode .. ": 쌍둥이가 생겼다");
            check(states(list[1], mode) == NONE,
                mode .. ": 원본의 상자가 " .. tostring(states(list[1], mode)));
        end
    end);

    --- **A condition on another unit does not stop it.** The `"@"` check there is absent, not
    --- [none], or a skipped action with [the target is hostile] runs over a unit frame.
    test("Skip은 다른 유닛에 조건이 있어도 원본을 모드의 유닛이 없을 때로 좁힌다", function()
        for _, units in ipairs({
            { target = { reaction = Constants.REACTION_HARM } },
            { focus = {} },
            { ["@"] = { reaction = Constants.REACTION_HELP } },
        }) do
            local action = spell({ conditions = { units = units } });
            action.casting = { hoverCast = { mode = "unitframe", aim = "skip" } };
            local original = bindingsOf(action)[1];
            check(states(original, "unitframe") == NONE,
                next(units) .. ": 원본의 상자가 " .. tostring(states(original, "unitframe")));
        end
    end);

    --- **Skip is a Cast Options value, not a condition the reader set**, so it moves nothing in the
    --- order. Written into the condition table it would make every skipped action a conditional one.
    test("Skip은 원본의 조건 표와 순서 레코드를 안 바꾼다", function()
        local plain, skipped = spell(), spell();
        skipped.casting = { hoverCast = { aim = "skip" } };
        local list = bindingsOf(skipped);
        check(list[1].conditions.units == nil, "조건 표에 유닛 조건이 섰다");
        check(DebindPrivate.MakeOrderRecord(skipped, 1, 1).isConditional
                == DebindPrivate.MakeOrderRecord(plain, 1, 1).isConditional,
            "Skip이 조건 유무를 바꿨다");
    end);

    --- **A condition on that very unit leaves the original nowhere to stand**, so only the original
    --- goes, the way Normal Cast off takes it. Read as a unit contradiction it would be the reader's
    --- ERROR where all they chose was Skip, and with the cast keys off too it would stay one.
    test("Skip과 그 유닛의 조건이 안 만나면 원본만 빠지고 조합키 쌍둥이는 남는다", function()
        for _, condition in ipairs({ {}, { reaction = Constants.REACTION_HARM } }) do
            local action = spell({ conditions = { units = { unitframe = condition } } });
            action.casting = { hoverCast = { mode = "unitframe", aim = "skip" } };
            local all = DebindPrivate.GetBindingsForAction(action);
            local list = castmod.without(Constants, all);
            check(list[1] ~= nil and list[1].normalCast == false,
                "원본의 표시가 " .. tostring(list[1] and list[1].normalCast));
            check(#all > #list, "조합키 쌍둥이가 없다");
            local issue = GetBindingIssue(action);
            check(issue == nil, "나온 것: " .. tostring(issue));
        end
    end);

    --- 액션의 모드가 없으면 설정 탭의 모드를 따른다. 새로 만든 액션이 그 모양이다.
    test("모드를 안 적은 액션은 설정 탭의 모드를 따른다", function()
        local options = DebindPrivate.Options;
        local was = options.hoverCastMode;
        options.hoverCastMode = "mouseover";
        local ok, err = pcall(function()
            local twin = twinOf(spell());
            check(twin ~= nil and twin.unit == "mouseover",
                "겨누는 것: " .. tostring(twin and twin.unit));
        end);
        options.hoverCastMode = was;
        if (not ok) then error(err, 0); end

        local twin = twinOf(spell());
        check(twin ~= nil and twin.unit == "unitframe",
            "기본 모드에서 겨누는 것: " .. tostring(twin and twin.unit));
    end);

    --- **Normal Cast를 끈 액션의 원본은 만들어지되 마지막 층에서 빠진다** (§6). 표시는 바인딩에
    --- 서고 (`BuildKeyMap`이 읽는다), 그래서 키의 다른 액션이 그 누름을 받는다.
    test("Normal Cast를 끄면 원본에 표시가 선다", function()
        local action = spell();
        action.casting = { normalCast = false };
        local list = bindingsOf(action);
        check(list[1] ~= nil and list[1].normalCast == false,
            "원본의 표시가 " .. tostring(list[1] and list[1].normalCast));
        check(list[2] ~= nil and list[2].normalCast == nil, "쌍둥이에까지 표시가 섰다");
    end);

    --- **Every press turned off makes no binding at all**, and it is said as a reason the row does
    --- not run rather than as an issue. Nothing blocks it (2026-09-16, owner;
    --- `devdocs/legacy/reorganizing-binding-issues.md` §3-3).
    test("an action with every press off has no binding and gives a reason, not an issue", function()
        local action = spell();
        action.casting = {
            normalCast = false,
            hoverCast = { aim = "skip" },
            selfCastKey = { aim = "skip" },
            focusCastKey = { aim = "skip" },
        };
        check(#DebindPrivate.GetBindingsForAction(action) == 0,
            "바인딩이 " .. #DebindPrivate.GetBindingsForAction(action) .. "개 나왔다");
        local issue = GetBindingIssue(action);
        check(issue == nil, "reported: " .. tostring(issue));
        check(DebindPrivate.GetCastingOffReason(action) == "NONE_LEFT",
            "reason: " .. tostring(DebindPrivate.GetCastingOffReason(action)));
        -- An empty list has no binding a neighbour could have covered.
        check(not DebindPrivate.IsUnreachableAction(action), "바인딩이 없는 액션이 이웃에 덮였다고 나온다");
    end);

    --- **A mode that stands and a twin that does not is a contradiction, not a choice.** An action with
    --- [when there is none] on the unit it points at has no twin even with Hover Cast on Unit Frames
    --- (`TwinUnitFor`). The reader skipped nothing, so it is not a reason to give; asked only about the
    --- mode, it would pass with nothing said and the row would claim a neighbour covered it.
    test("an action whose twin has nowhere to stand is a contradiction", function()
        local action = spell({ conditions = { units = { unitframe = false } } });
        action.casting = {
            normalCast = false,
            hoverCast = { mode = "unitframe" },
            selfCastKey = { aim = "skip" },
            focusCastKey = { aim = "skip" },
        };
        check(#DebindPrivate.GetBindingsForAction(action) == 0,
            "바인딩이 " .. #DebindPrivate.GetBindingsForAction(action) .. "개 나왔다");
        check(GetBindingIssue(action) == Constants.BINDING_ISSUE_CONDITIONS_NEVER,
            "나온 것: " .. tostring(GetBindingIssue(action)));
        check(DebindPrivate.GetCastingOffReason(action) == nil, "also given as a reason");
    end);

    --- 셋만 끈 액션은 남은 하나로 여전히 선다. 이것이 없으면 위 테스트는 "언제나 경고"로도
    --- 통과한다.
    test("하나라도 남아 있으면 경고가 없다", function()
        local action = spell();
        action.casting = {
            normalCast = false,
            hoverCast = { aim = "skip" },
            selfCastKey = { aim = "skip" },
        };
        check(#DebindPrivate.GetBindingsForAction(action) > 0, "바인딩이 하나도 안 나왔다");
        check(GetBindingIssue(action) == nil, "나온 것: " .. tostring(GetBindingIssue(action)));
    end);

    return T;
end
