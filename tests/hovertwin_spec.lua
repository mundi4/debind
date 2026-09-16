-- 계정 스위치 Hover Cast와 Mouseover Cast가 만드는 **쌍둥이 바인딩**. 와우 클라이언트 불필요.
--
-- 액션 하나가 바인딩 둘일 수 있다는 것이 여기서 재는 전부다: 둘 다 덮여야 도달 불가이고,
-- 쌍둥이가 아예 안 만들어지는 대상들이 있고, Clique가 있어도 만들어진다.
--
-- 툴팁이 이 답을 실제로 그리는지는 여기서 못 본다. 그건 `GameTooltip`의 줄이라
-- `tests/display_spec.lua`와 `/debtest`의 `Tooltip:` 둘이 본다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local GetBindingIssue = DebindPrivate.GetBindingIssue;
    local CheckUnreachableBindings = DebindPrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebindPrivate.ClearUnreachableBindingCache;

    local T = { passed = 0, failures = {} };

    --- 스위치가 계정 값이라 프로필이 있어야 읽힌다. 이 파일은 액션을 직접 만들어 쓰므로
    --- 레이어는 비어 있어도 되고, 필요한 것은 `Options`가 서 있는 것뿐이다.
    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
        characters = {},
        migrated = {},
        switches = {},
    };
    DebindPrivate.InitDB();

    --- 이 파일 대부분이 Hover Cast가 켜진 계정을 잰다.
    DebindPrivate.Options.hoverCast = true;

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local castmod = require("castmod");

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

    ---------------------------------------------------------------------------
    -- 1. 바인딩이 둘인 액션은 둘 다 죽어야 도달 불가다
    -- (`devdocs/splitting-an-action-into-bindings.md` §3-1)
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
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "T",
            conditions = { units = { unitframe = {} } } });
        check(not DebindPrivate.IsUnreachableAction(subject), "원본이 살아 있는데 액션이 죽었다");
        check(GetBindingIssue(subject) == nil, "나온 것: " .. tostring(GetBindingIssue(subject)));
    end);

    --- 원본만 죽는 것은 마우스 버튼에서만 생긴다. 키보드 키에서는 원본이 제일 넓은 상자라
    --- 그걸 덮는 것은 쌍둥이도 덮는다. 마우스 버튼은 hover 없는 원본이 "hover 없음"으로 좁혀져
    --- 있어서(`BuildUnitStates`), 같은 버튼의 hover 없는 이웃이 원본만 덮는다.
    test("원본만 덮인 액션도 도달 불가가 아니다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "BUTTON3" });
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

    --- **쌍둥이는 꺼진 hover 조건이 기억하고 있는 개체창 마스크를 안 물려받는다** (2026-09-06).
    --- 조건을 꺼도 고른 값은 남고(끄는 것과 지우는 것은 다르다), 조건이 꺼져 있으니 쌍둥이는
    --- 자기 조건을 스스로 세운다(`UNIT_IS_THERE`). 마스크가 거기까지 따라가면 쌍둥이만 죽은
    --- 조건의 값으로 좁혀진다.
    ---
    --- 마스크가 0이면 더 조용하다. 쌍둥이가 어떤 개체창에도 안 걸리는데 그 0은 사용자가 이미
    --- 끈 조건의 것이라 이슈로도 안 나온다.
    test("쌍둥이는 꺼진 hover 조건이 남긴 frameTypes를 안 가져온다", function()
        for _, mask in ipairs({ Constants.FRAMETYPE_GROUP, 0 }) do
            local action = { type = Constants.SPELL, value = 585, key = "T", unit = "focus",
                conditions = { units = { unitframe = { disabled = true, frameTypes = mask } } } };
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
    -- 개체창은 우리 행에서, Clique가 쥔 프레임은 Clique의 hover 버튼에서. 옵션을 켰다고 주황
    -- 문장을 달던 것은 블리자드 개체창을 통째로 내려놓던 시절의 말이다.
    test("Clique가 있어도 옵션 켠 액션은 쌍둥이를 갖고 문장이 없다", function()
        withClique(function()
            local action = { type = Constants.SPELL, value = 585, key = "T" };
            check(GetBindingIssue(action) == nil, "나온 것: " .. tostring(GetBindingIssue(action)));
            local bindings = bindingsOf(action);
            check(bindings[2] ~= nil and bindings[2].unit == "unitframe",
                "Clique가 있다고 쌍둥이를 안 만들었다");
        end);
    end);

    -- **An action with a unit picked gets a twin too, and the twin goes out at that unit**
    -- (2026-09-13, owner; 2026-09-15, owner). The twin is there to take its turn in the tier a pointed
    -- press is decided in, and Hover Cast does not move a unit the reader picked. **`none` is not a
    -- picked unit**: it settles nothing before the press, so its twin is aimed at the pointed unit like
    -- an action with no target and only the cast goes out asking.
    test("고른 대상의 쌍둥이는 그 대상으로, none의 쌍둥이는 가리킨 유닛으로 겨눈다", function()
        for _, unit in ipairs({ "unitframe", "focus", "target", "player", "tank", "custom1" }) do
            local action = { type = Constants.SPELL, value = 585, key = "T",
                unit = unit };
            local twin = bindingsOf(action)[2];
            check(twin ~= nil and twin.unit == unit,
                "대상 " .. unit .. "의 쌍둥이가 겨누는 것: " .. tostring(twin and twin.unit));
        end

        local twin = bindingsOf({ type = Constants.SPELL, value = 585, key = "T", unit = "none" })[2];
        check(twin ~= nil and twin.unit == "unitframe",
            "대상 none의 쌍둥이가 겨누는 것: " .. tostring(twin and twin.unit));
        check(DebindPrivate.CastUnitOf and DebindPrivate.CastUnitOf(twin) == "none",
            "대상 none의 쌍둥이가 나가는 곳: " .. tostring(DebindPrivate.CastUnitOf and DebindPrivate.CastUnitOf(twin)));

        -- Clique가 있어도 둘 다 할 말이 없다. 대상 `unitframe`은 물러난 상태에서도 `GetUnitFrameUnit`이
        -- 답하는 겨눔이라 빨강이 아니다 (코드 리뷰, 2026-09-08).
        withClique(function()
            for _, unit in ipairs({ "none", "unitframe" }) do
                local action = { type = Constants.SPELL, value = 585, key = "T",
                    unit = unit };
                check(GetBindingIssue(action) == nil,
                    "대상 " .. unit .. "에 문장이 붙었다: " .. tostring(GetBindingIssue(action)));
            end
        end);
    end);

    -- **hover 조건이 [안 올렸을 때]여도 쌍둥이는 없다** (2026-09-06, 소유자). 그 액션은 개체창
    -- 위에서 아예 발동하지 않으므로 개체창의 개체로 나갈 가능성이 0이다. 메뉴도 같은 이유로
    -- 상자를 잠근다 - 여기서 재는 것은 그 짝의 실행 쪽이고, 잠금 자체는 화면에서만 보인다.
    test("hover 조건이 안 올렸을 때여도 쌍둥이가 없다", function()
        local action = { type = Constants.SPELL, value = 585, key = "T",
            unit = "focus",
            conditions = { units = { unitframe = false } } };
        check(bindingsOf(action)[2] == nil,
            "개체창 위에서 안 도는 액션에 쌍둥이가 생겼다");
    end);

    -- **An Always Ask action on a mouse button gets no hover twin in Unit Frames mode** (§3-4). With no
    -- hover condition the original stands on [not pointing], and a twin that casts where the original
    -- does could only be a frame click record: the click would open the targeting cursor instead of
    -- doing the frame's own action. On a keyboard key the twin stays, since there it is what asks
    -- `@` of the pointed unit.
    test("마우스 버튼의 대상 none에는 hover 쌍둥이가 없다", function()
        check(bindingsOf({ type = Constants.SPELL, value = 585, key = "BUTTON2", unit = "none" })[2] == nil,
            "개체창 클릭을 가져가는 쌍둥이가 생겼다");
        check(bindingsOf({ type = Constants.SPELL, value = 585, key = "T", unit = "none" })[2] ~= nil,
            "키보드 키의 쌍둥이까지 사라졌다");
    end);

    -- 반대쪽. 없으면 위 테스트는 "언제나 쌍둥이가 없다"로도 통과한다.
    test("평범한 대상에는 쌍둥이가 생긴다", function()
        local action = { type = Constants.SPELL, value = 585, key = "T",
            unit = "focus" };
        local bindings = bindingsOf(action);
        check(bindings[2] ~= nil, "대상 focus인데 쌍둥이가 없다");
        check(bindings[2].unit == "focus", "쌍둥이가 겨누는 것: " .. tostring(bindings[2].unit));
    end);

    -- hover 조건은 우리가 등록한 프레임 위에서 도는 것이고, 블리자드 개체창은 Clique가 있어도
    -- 우리가 등록한다. 그러니 Clique가 있다는 것만으로 붙는 문장은 없다.
    test("Clique가 있어도 hover 조건이 켜진 액션에 Clique 때문에 붙는 문장은 없다", function()
        withClique(function()
            local action = { type = Constants.SPELL, value = 585, key = "T",
                conditions = { units = { unitframe = {} } } };
            check(GetBindingIssue(action) == nil, "나온 것: " .. tostring(GetBindingIssue(action)));
        end);
    end);

    test("Clique가 있어도 옵션을 못 받는 타입은 아무 말이 없다", function()
        withClique(function()
            local action = { type = Constants.MACROTEXT, value = "/cast x", key = "T" };
            check(GetBindingIssue(action) == nil, "나온 것: " .. tostring(GetBindingIssue(action)));
        end);
    end);

    ---------------------------------------------------------------------------
    -- 3. 스위치 둘, 그리고 쌍둥이가 딛고 서는 조건
    ---------------------------------------------------------------------------

    --- 스위치를 잠깐 이 값으로 놓고 돈다. 파일 전체가 Hover Cast 켜진 상태로 서 있으므로,
    --- 끄는 쪽을 재려면 되돌려 놓을 자리가 있어야 한다.
    local function withSwitches(hoverCast, hoverCastMode, fn)
        local options = DebindPrivate.Options;
        local wasHover, wasMode = options.hoverCast, options.hoverCastMode;
        options.hoverCast, options.hoverCastMode = hoverCast, hoverCastMode;
        local ok, err = pcall(fn);
        options.hoverCast, options.hoverCastMode = wasHover, wasMode;
        if (not ok) then error(err, 0); end
    end

    local function spell(fields)
        local action = { type = Constants.SPELL, value = 585, key = "T" };
        for k, v in pairs(fields or {}) do
            action[k] = v;
        end
        return action;
    end

    test("Hover Cast가 꺼져 있으면 쌍둥이가 없다", function()
        withSwitches(nil, nil, function()
            check(bindingsOf(spell())[2] == nil, "꺼졌는데 쌍둥이가 생겼다");
        end);
    end);

    --- 끄면 설정 탭이 모드를 남겨 두므로, 꺼진 상자 아래 `mouseover`가 서 있는 것이 흔한 모양이다.
    test("꺼진 Hover Cast는 모드가 남아 있어도 쌍둥이를 안 낸다", function()
        withSwitches(nil, "mouseover", function()
            check(bindingsOf(spell())[2] == nil, "꺼졌는데 쌍둥이가 생겼다");
        end);
    end);

    test("Mouseover 모드는 mouseover를 겨누는 쌍둥이 하나를 낸다", function()
        withSwitches(true, "mouseover", function()
            local list = bindingsOf(spell());
            check(list[2] ~= nil and list[2].unit == "mouseover",
                "겨누는 것: " .. tostring(list[2] and list[2].unit));
            check(list[3] == nil, "쌍둥이가 둘 생겼다");
        end);
    end);

    --- **쌍둥이는 자기가 겨누는 유닛의 축에서 좁아져야 한다.** 겨누는 유닛의 이름 아래
    --- [그 개체가 있을 때]를 들고 서므로(`FillBinding`의 `UNIT_IS_THERE`), 상자가 그 축의
    --- 절반이고 본체가 나머지를 받는다.
    ---
    --- 조건이 `hover`라는 이름에 박혀 있으면 `mouseover` 쌍둥이가 엉뚱한 축에서 좁아진다.
    --- `mouseover`를 겨누면서 **개체창 위에서만** 서게 되고, Mouseover Cast가 개체창 밖에서
    --- 아무 일도 안 한다.
    test("쌍둥이의 조건은 자기가 겨누는 유닛 아래 선다", function()
        for _, case in ipairs({ { "unitframe", true, nil }, { "mouseover", true, "mouseover" } }) do
            local unit = case[1];
            withSwitches(case[2], case[3], function()
                local list = bindingsOf(spell());
                local twin = list[2];
                check(twin ~= nil, unit .. ": 쌍둥이가 없다");
                check(twin.conditions.units and twin.conditions.units[unit] ~= nil,
                    unit .. ": 조건이 자기 유닛 아래 없다");
                check(twin.unitStates and twin.unitStates[unit] == Constants.UNITSTATE_EXISTS,
                    unit .. ": 좁혀진 상태가 " .. tostring(twin.unitStates and twin.unitStates[unit]));
            end);
        end
    end);

    --- **겨누려는 유닛에 걸린 조건은 좁혀 들어가지 덮어쓰지 않는다** (2026-09-12, 소유자).
    --- 쌍둥이가 드는 것은 [그 개체가 있을 때]이고 사용자가 건 것이 [적대일 때]면 만나는 자리가
    --- [적대일 때]다. 덮어쓰면 쌍둥이가 그 축에서 24(적대) 대신 126(있기만 하면)이 되어 원본보다
    --- 넓어지고, 솔버가 원본을 지워서 그 키가 커서 밑이 아군이든 적이든 그쪽으로 나갔다
    --- (2026-09-12에 잼).
    test("겨누려는 유닛에 걸린 조건이 쌍둥이로 좁혀 들어간다", function()
        for _, case in ipairs({ { "unitframe", true, nil }, { "mouseover", true, "mouseover" } }) do
            local unit = case[1];
            withSwitches(case[2], case[3], function()
                local action = spell({ conditions = { units = {
                    [unit] = { reaction = Constants.REACTION_HARM } } } });
                local list = bindingsOf(action);
                check(list[2] ~= nil, unit .. ": 쌍둥이가 없다");
                check(list[2].unit == unit, unit .. ": 겨누는 것이 " .. tostring(list[2].unit));
                check(list[2].unitStates[unit] == Constants.UNITSTATE_HARM,
                    unit .. ": 쌍둥이의 조건이 " .. tostring(list[2].unitStates[unit]));
                check(list[1].unitStates[unit] == Constants.UNITSTATE_HARM,
                    unit .. ": 원본의 조건이 " .. tostring(list[1].unitStates[unit]));
            end);
        end
    end);

    --- **만나는 자리가 없으면 안 세운다.** [없을 때]를 건 유닛은 쌍둥이가 서는 순간과 겹치는
    --- 때가 없다. 솔버가 빈 상자로 떨구기는 하지만 안 만드는 쪽이 싸다.
    test("겨누려는 유닛에 [없을 때]가 걸려 있으면 쌍둥이가 없다", function()
        for _, case in ipairs({ { "unitframe", true, nil }, { "mouseover", true, "mouseover" } }) do
            local unit = case[1];
            withSwitches(case[2], case[3], function()
                local action = spell({ unit = "target",
                    conditions = { units = { [unit] = false } } });
                check(bindingsOf(action)[2] == nil,
                    unit .. ": 모순인데 쌍둥이가 생겼다");
            end);
        end
    end);

    --- **다른** 유닛에 걸린 조건은 쌍둥이를 막지도 좁히지도 않고 그대로 따라간다.
    test("다른 유닛에 걸린 조건은 쌍둥이를 안 막는다", function()
        withSwitches(true, nil, function()
            local action = spell({ unit = "target", conditions = { units = {
                mouseover = { reaction = Constants.REACTION_HARM } } } });
            local twin = bindingsOf(action)[2];
            check(twin ~= nil, "hover 쌍둥이가 없다");
            check(twin.unitStates.mouseover == Constants.UNITSTATE_HARM,
                "mouseover 조건이 쌍둥이에서 " .. tostring(twin.unitStates.mouseover));
            check(twin.unitStates.unitframe == Constants.UNITSTATE_EXISTS,
                "쌍둥이가 hover 축에 안 섰다");
        end);
    end);

    --- **사용자가 건 hover 조건을 물려받은 쌍둥이는 그 개체창 마스크도 물려받는다.** 마스크는
    --- 그 조건의 축이라 조건과 함께 움직이고, 조건을 안 건 액션의 쌍둥이는 `UNIT_IS_THERE`를
    --- 세우므로 실을 마스크 자체가 없다.
    test("살아 있는 hover 조건의 개체창 마스크는 쌍둥이로 따라간다", function()
        withSwitches(true, nil, function()
            local mask = Constants.FRAMETYPE_GROUP;
            local action = spell({ unit = "target",
                conditions = { units = { unitframe = { frameTypes = mask } } } });
            local twin = bindingsOf(action)[2];
            check(twin ~= nil, "쌍둥이가 없다");
            check(twin.unitFrameTypes == mask,
                "쌍둥이의 마스크가 " .. tostring(twin.unitFrameTypes));
        end);
    end);

    --- **`ignoreHoverUnit`은 쌍둥이를 막지 않고, 쌍둥이를 원본의 대상으로 내보낸다** (2026-09-13,
    --- 소유자). 쌍둥이가 없으면 그 액션은 마지막 층에만 서서, 앞에 두었어도 가리킨 유닛이 있는
    --- 누름을 뒤의 Hover Cast 액션에 넘긴다. hover 조건이 켜진 액션에서는 원본의 겨눔이 `""`이고
    --- 쌍둥이도 그렇다.
    test("ignoreHoverUnit을 켠 액션의 쌍둥이는 원본의 대상으로 나간다", function()
        for _, case in ipairs({ { true, nil }, { true, "mouseover" } }) do
            withSwitches(case[1], case[2], function()
                local list = bindingsOf(spell({ ignoreHoverUnit = true, unit = "focus" }));
                check(list[2] ~= nil and list[2].unit == "focus",
                    "쌍둥이가 겨누는 것: " .. tostring(list[2] and list[2].unit));
            end);
        end

        local list = bindingsOf(spell({ ignoreHoverUnit = true, conditions = { units = { unitframe = {} } } }));
        check(list[1].unit == "", "원본의 겨눔이 안 비었다: " .. tostring(list[1].unit));
        check(list[2] ~= nil and list[2].unit == "",
            "hover 조건 있는 액션의 쌍둥이가 겨누는 것: " .. tostring(list[2] and list[2].unit));
    end);



    return T;
end
