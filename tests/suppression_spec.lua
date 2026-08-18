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

    test("억제는 조건 갈래에 안 닿는다", function()
        local action = { type = Constants.SPELL, value = 585, key = "T", groups = 0 };
        check(GetBindingIssue(action, nil, "unreachable") == Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED,
            "도달 불가를 끄면서 groups 검사까지 같이 껐다");
    end);

    return T;
end
