-- 문제 코드의 등급(`Constants.BINDING_ISSUE_GRADES`).
-- 와우 클라이언트 불필요.
--
-- **등급이 틀리면 화면이 조용히 거짓말한다.** 빨강이어야 할 것이 주황이 되면 키가 안 도는데도
-- "눌리기는 한다"로 그려지고, 사용자는 고칠 것이 있다는 말을 어디서도 못 듣는다. 반대 방향은
-- 시끄럽기만 하다. `npm run check`가 색은 못 보므로 색을 정하는 값을 여기서 잡는다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local GetIssueColor = DebindPrivate.GetIssueColor;

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

    --- 모든 문제 코드를 훑는다. `BINDING_ISSUE_GRADES`는 표라서 걸러진다 - 이름이 같은 접두사로
    --- 시작하지만 값이 문자열이 아니다.
    local function ForEachIssueCode(fn)
        local seen = 0;
        for name, code in pairs(Constants) do
            if (type(name) == "string" and name:match("^BINDING_ISSUE_")
                    and type(code) == "string") then
                seen = seen + 1;
                fn(name, code);
            end
        end
        check(seen > 0, "문제 코드를 하나도 못 찾았다 - 접두사가 바뀌었나");
    end

    ---------------------------------------------------------------------------
    -- 등급
    ---------------------------------------------------------------------------

    --- 주황: 키는 도는데 시킨 것 하나가 안 된다.
    ---
    --- **이 표에 안 나가는 사유는 없다** (2026-09-06, 소유자). 이웃에 덮인 것도 다른 전문화의
    --- 것도 문제 코드가 아니라 다른 축이고, 답을 내는 자리가 따로 있다.
    --- A saved type that now binds as a block, and as an ERROR it would leave the key and let the
    --- action after it fire (`devdocs/legacy/dropping-the-game-fallback.md` §3). The first orange,
    --- "Clique took the hover twin", went when Blizzard's unit frames became ours whether or not
    --- Clique is there (code review, 2026-09-08). An action with every press turned off was orange
    --- until it stopped being an issue at all (`devdocs/reorganizing-binding-issues.md` §3-3).
    local WARNING = {
        [Constants.BINDING_ISSUE_TYPE_RETIRED] = true,
    };

    test("도는데 하나가 빠진 것은 주황이다", function()
        for code in pairs(WARNING) do
            check(GetIssueColor(code) == _G.ORANGE_FONT_COLOR,
                tostring(code) .. "가 주황이 아니다");
            check(DebindPrivate.IsIssueWarning(code), tostring(code) .. "가 경고로 안 답한다");
            check(DebindPrivate.IssueKeepsKey(code), tostring(code) .. "가 키를 뺏는다");
        end
    end);

    -- 나머지가 하나라도 빨강을 벗으면 고칠 것이 있는 키가 조용히 넘어간다.
    test("나머지 코드는 전부 빨강이다", function()
        ForEachIssueCode(function(name, code)
            if (not WARNING[code]) then
                check(GetIssueColor(code) == _G.ERROR_COLOR, name .. "이 빨강이 아니다");
                check(not DebindPrivate.IsIssueWarning(code), name .. "이 경고로도 답한다");
                check(not DebindPrivate.IssueKeepsKey(code), name .. "이 키를 그대로 건다");
            end
        end);
    end);

    -- **표에 없는 코드는 빨강으로 떨어져야 한다.** 주황이 기본값이면 등급을 안 적은 새 코드가
    -- 조용히 넘어간다 - 시끄러운 쪽으로 틀리는 것이 이 애드온에서 안전한 방향이다.
    test("모르는 코드는 빨강이고, nil은 색이 없다", function()
        check(GetIssueColor("NO_SUCH_ISSUE_CODE") == _G.ERROR_COLOR, "모르는 코드가 빨강이 아니다");
        check(not DebindPrivate.IsIssueWarning("NO_SUCH_ISSUE_CODE"), "모르는 코드가 경고다");
        -- **이것도 같은 기본값이어야 한다.** 같은 표를 읽는데 위 둘은 없으면 ERROR로 읽고
        -- 이쪽만 없으면 "키를 지킨다"로 읽으면, 등급을 안 붙인 코드가 생기는 날 그 액션은
        -- `BuildKeyMap`의 게이트를 통과해 솔버까지 가면서 화면에는 아무 표시도 안 뜬다.
        check(not DebindPrivate.IssueKeepsKey("NO_SUCH_ISSUE_CODE"),
            "모르는 코드가 키를 지킨다");
        -- 문제가 없으면 칠할 색도 없다. 부르는 쪽이 `if (color)`로 가른다.
        check(GetIssueColor(nil) == nil, "문제가 없는데 색이 나온다");
        check(not DebindPrivate.IsIssueWarning(nil), "nil이 경고다");
    end);

    -- 위 기본값은 안전하지만 **의도한 등급인지는 아무에게도 안 물어본다.** 코드를 늘리면서
    -- 표의 한 줄을 빠뜨리는 자리를 여기서 막는다.
    test("모든 코드에 등급이 적혀 있다", function()
        ForEachIssueCode(function(name, code)
            check(Constants.BINDING_ISSUE_GRADES[code] ~= nil, name .. "에 등급이 없다");
        end);
    end);

    return T;
end
