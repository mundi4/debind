-- `GetBindingIssue`의 `notCategory = "unreachable"` 갈래. 와우 클라이언트 불필요.
--
-- 다른 전문화의 순서를 보고 있으면 도달 불가는 참이 아니다 - 그 판정은 지금 이 전문화로
-- 만들어진 키 맵에서 나온다. 그래서 그 한 갈래만 끈다.
--
-- **위험한 것은 너무 많이 끄는 쪽이다.** 한때 `notCategory = "key"`로 갈래째 껐는데, 그
-- 갈래에는 전문화와 무관한 키 유효성 검사도 같이 있어서 진짜 못 쓰는 키에도 경고가 안 떴다.
-- 여기 둘째 묶음이 그것을 잡는다. 첫째 묶음만 있으면 "key"로 끈 코드도 초록으로 지나간다.
--
-- 툴팁이 이 답을 실제로 그리는지는 여기서 못 본다. 그건 `GameTooltip`의 줄이라
-- `/debtest`의 `Tooltip:` 둘이 본다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local GetBindingIssue = DebindPrivate.GetBindingIssue;
    local GetBindingInfoForAction = DebindPrivate.GetBindingInfoForAction;
    local CheckUnreachableBindings = DebindPrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebindPrivate.ClearUnreachableBindingCache;

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

    --- 같은 말을 하는 두 액션을 솔버에 통과시키고 **덮인 쪽**을 돌려준다.
    ---
    --- 액션에서 바인딩을 얻는 통로가 `GetBindingInfoForAction`이고 `IsUnreachableAction`도
    --- 같은 통로로 캐시를 조회하므로, 솔버에 넣는 테이블과 조회되는 테이블이 같은 것이다.
    local function coveredAction()
        local cover = { type = Constants.SPELL, value = 585, key = "T", combat = true };
        local subject = { type = Constants.SPELL, value = 586, key = "T", combat = true };

        local bindings = { GetBindingInfoForAction(cover), GetBindingInfoForAction(subject) };
        ClearUnreachableBindingCache();
        CheckUnreachableBindings(bindings);

        check(DebindPrivate.IsUnreachableAction(subject), "솔버가 덮인 쪽을 안 떨궜다");
        check(not DebindPrivate.IsUnreachableAction(cover), "덮는 쪽까지 떨어졌다");
        return subject, cover;
    end

    ---------------------------------------------------------------------------
    -- 1. 끄면 도달 불가가 사라진다
    ---------------------------------------------------------------------------

    test("도달 불가는 안 끄면 나온다", function()
        local subject = coveredAction();
        check(GetBindingIssue(subject) == Constants.BINDING_ISSUE_UNREACHABLE,
            "덮인 액션인데 도달 불가가 안 나온다");
    end);

    test("unreachable을 끄면 도달 불가가 안 나온다", function()
        local subject = coveredAction();
        check(GetBindingIssue(subject, nil, "unreachable") == nil,
            "껐는데 도달 불가가 그대로 나온다");
    end);

    test("키 갈래를 짚어 물어도 마찬가지다", function()
        local subject = coveredAction();
        check(GetBindingIssue(subject, "key") == Constants.BINDING_ISSUE_UNREACHABLE,
            "키 갈래에 도달 불가가 안 실렸다");
        check(GetBindingIssue(subject, "key", "unreachable") == nil,
            "키 갈래를 짚어 물으니 억제가 안 걸렸다");
    end);

    ---------------------------------------------------------------------------
    -- 2. 꺼도 키 유효성은 산다
    --
    -- 마우스 버튼 검사를 고른 이유: 전문화와 무관하고, 테스터의 바인딩과도 무관하다.
    -- 게임 메뉴 키 검사는 같은 갈래에 있지만 그 사람이 무엇을 걸어뒀는지에 달려 있다.
    ---------------------------------------------------------------------------

    local function badKeyAction()
        return { type = Constants.SPELL, value = 585, key = "BUTTON1" };
    end

    test("호버 없는 BUTTON1은 억제 중에도 잘못된 키다", function()
        local action = badKeyAction();
        check(GetBindingIssue(action) == Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON,
            "억제 없이도 마우스 버튼 문제가 안 나온다");
        check(GetBindingIssue(action, nil, "unreachable") == Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON,
            "도달 불가를 끄면서 키 유효성 검사까지 같이 껐다");
    end);

    test("키 갈래를 짚어 물어도 산다", function()
        local action = badKeyAction();
        check(GetBindingIssue(action, "key", "unreachable") == Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON,
            "키 갈래를 짚어 물었더니 억제가 유효성 검사까지 먹었다");
    end);

    ---------------------------------------------------------------------------
    -- 3. 다른 갈래는 건드리지 않는다
    ---------------------------------------------------------------------------

    --- 스펙 리터럴을 **프로덕션과 같은 모양**으로 세운다: 조건은 `conditions` 안에 산다
    --- (`Profile.lua`의 `KEYS_TO_SAVE`, `Misc.GetBindingInfoForAction`).
    ---
    --- 리터럴은 평평하게 쓴다. 자리마다 `conditions = { ... }`를 손으로 적으면 한 줄
    --- 빠뜨렸을 때 그 조건이 조용히 사라지고, **조건이 빠진 액션은 넓어진다** - 스펙이 잡아야
    --- 할 바로 그 종류의 잘못이 스펙 안에서 난다.
    ---
    --- **무엇이 조건인지는 여기서 안 정한다.** `Constants.IsConditionField`를 그대로 부르므로
    --- 축이 하나 늘어도 이 함수는 안 바뀌고, 프로덕션과 갈릴 자리가 없다.
    local function nest(action)
        local conditions = action.conditions;
        for k, v in pairs(action) do
            if (Constants.IsConditionField(k)) then
                conditions = conditions or {};
                conditions[k] = v;
                action[k] = nil;
            end
        end
        action.conditions = conditions;
        return action;
    end
    test("억제는 조건 갈래에 안 닿는다", function()
        local action = nest({ type = Constants.SPELL, value = 585, key = "T", groups = 0 });
        check(GetBindingIssue(action, nil, "unreachable") == Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED,
            "도달 불가를 끄면서 groups 검사까지 같이 껐다");
    end);

    ---------------------------------------------------------------------------
    -- 4. 바인딩이 둘인 액션은 둘 다 죽어야 도달 불가다
    -- (`devdocs/splitting-an-action-into-bindings.md` §3-1)
    ---------------------------------------------------------------------------

    --- 옵션 켠 액션을 `cover` 뒤에 세운다. `KeyMap`과 같은 순서로(쌍둥이가 원본 앞).
    local function coveredPair(cover)
        local subject = { type = Constants.SPELL, value = 586, key = cover.key, preferHoverUnit = true };
        local list = DebindPrivate.GetBindingsForAction(subject);
        check(#list == 2, "쌍둥이가 안 생겼다");
        local bindings = { GetBindingInfoForAction(cover), list[2], list[1] };
        ClearUnreachableBindingCache();
        CheckUnreachableBindings(bindings);
        return subject;
    end

    --- 반은 죽은 액션은 빨갛지 않다. 원본이든 쌍둥이든 하나는 나가므로 이웃 탓의 회색 문장
    --- 하나가 남고, 어느 쪽이 죽었느냐로 문장이 갈린다.
    test("쌍둥이만 덮인 액션은 도달 불가가 아니라 개체창 위 문장이다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "T",
            conditions = { units = { hover = {} } } });
        check(not DebindPrivate.IsUnreachableAction(subject), "원본이 살아 있는데 액션이 죽었다");
        local issue = GetBindingIssue(subject);
        check(issue == Constants.BINDING_ISSUE_UNREACHABLE_OVER_FRAMES, "나온 것: " .. tostring(issue));
        check(DebindPrivate.IsIssueMinor(issue), "회색이 아니다");
        check(GetBindingIssue(subject, nil, "unreachable") == nil, "억제했는데 나왔다");
    end);

    --- 원본만 죽는 것은 마우스 버튼에서만 생긴다. 키보드 키에서는 원본이 제일 넓은 상자라
    --- 그걸 덮는 것은 쌍둥이도 덮는다. 마우스 버튼은 hover 없는 원본이 "hover 없음"으로 좁혀져
    --- 있어서(`BuildUnitStates`), 같은 버튼의 hover 없는 이웃이 원본만 덮는다.
    test("원본만 덮인 액션은 개체창 밖 문장이다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "BUTTON3" });
        check(not DebindPrivate.IsUnreachableAction(subject), "쌍둥이가 살아 있는데 액션이 죽었다");
        local issue = GetBindingIssue(subject);
        check(issue == Constants.BINDING_ISSUE_UNREACHABLE_OFF_FRAMES, "나온 것: " .. tostring(issue));
        check(DebindPrivate.IsIssueMinor(issue), "회색이 아니다");
    end);

    test("둘 다 덮이면 도달 불가다", function()
        local subject = coveredPair({ type = Constants.SPELL, value = 585, key = "T" });
        check(DebindPrivate.IsUnreachableAction(subject), "둘 다 덮였는데 액션이 살아 있다");
        check(GetBindingIssue(subject) == Constants.BINDING_ISSUE_UNREACHABLE, "도달 불가가 안 나왔다");
    end);

    ---------------------------------------------------------------------------
    -- 5. Clique가 있으면 옵션은 잠기고, 액션은 빨갛지 않다
    ---------------------------------------------------------------------------

    local function withClique(fn)
        local was = DebindPrivate.CliqueDetected;
        DebindPrivate.CliqueDetected = true;
        local ok, err = pcall(fn);
        DebindPrivate.CliqueDetected = was;
        if (not ok) then error(err, 0); end
    end

    test("Clique가 있으면 옵션 켠 액션은 회색 문장 하나다", function()
        withClique(function()
            local action = { type = Constants.SPELL, value = 585, key = "T", preferHoverUnit = true };
            local issue = GetBindingIssue(action);
            check(issue == Constants.BINDING_ISSUE_HOVER_UNIT_WITH_CLIQUE, "나온 것: " .. tostring(issue));
            check(DebindPrivate.IsIssueMinor(issue), "회색이 아니다");
            check(GetBindingIssue(action, "hover") == issue, "hover 갈래로 물으니 안 나온다");
        end);
    end);

    test("Clique가 있어도 hover 조건이 켜진 액션의 답은 그대로 빨강이다", function()
        withClique(function()
            local action = { type = Constants.SPELL, value = 585, key = "T", preferHoverUnit = true,
                conditions = { units = { hover = {} } } };
            check(GetBindingIssue(action) == Constants.BINDING_ISSUE_CANNOT_USE_HOVER_WITH_CLIQUE,
                "hover 조건의 빨강이 옵션의 회색에 밀렸다");
        end);
    end);

    test("Clique가 있어도 옵션을 못 받는 타입은 아무 말이 없다", function()
        withClique(function()
            local action = { type = Constants.MACROTEXT, value = "/cast x", key = "T", preferHoverUnit = true };
            check(GetBindingIssue(action) == nil, "나온 것: " .. tostring(GetBindingIssue(action)));
        end);
    end);

    return T;
end
