-- `GetBindingIssue`의 유닛 조건 갈래 테스트. 와우 클라이언트 불필요.
--
-- 이 갈래가 왜 위험한가: 이슈가 붙은 액션은 `Debind.lua`에서 `KeyMap`에 아예
-- 안 들어간다. 즉 여기서 나는 **오탐은 표시 버그가 아니라 키가 안 먹는 것**이다.
-- 반대로 놓친 모순은 조용히 아무것도 안 하는 바인딩이 된다.
--
-- `checkedUnits`의 `"@"`는 그 액션 자신의 대상 유닛을 가리키므로, 같은 유닛에
-- 명시 조건이 같이 걸리면 둘이 한 축에서 만난다. 그 조합표가 여기 있다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local GetBindingIssue = DebindPrivate.GetBindingIssue;
    local NEVER = Constants.BINDING_ISSUE_CONDITIONS_NEVER;

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

    --- `"@"`와 명시 유닛 조건을 같이 건 액션의 이슈를 본다.
    local function issueFor(atValue, unitValue)
        local action = {
            type = Constants.SPELL,
            value = 100,
            unit = "target",
            checkedUnits = { ["@"] = atValue, target = unitValue },
        };
        return GetBindingIssue(action, "checkedUnits");
    end

    ---------------------------------------------------------------------------
    -- 진짜 모순 - 이슈가 나야 한다
    ---------------------------------------------------------------------------

    test("존재 x 부재는 모순", function()
        check(issueFor(true, false) == NEVER, "이슈가 안 남");
    end);

    test("부재 x 존재는 모순", function()
        check(issueFor(false, true) == NEVER, "이슈가 안 남");
    end);

    test("부재 x 우호는 모순", function()
        check(issueFor(false, "help") == NEVER, "이슈가 안 남");
    end);

    test("우호 x 부재는 모순", function()
        check(issueFor("help", false) == NEVER, "이슈가 안 남");
    end);

    -- 유닛 하나는 한 값이다. 런타임의 `unitStateExpression`도, 블리자드의
    -- `SecureTemplates.lua`(`helpbutton`/`harmbutton` 치환)도 if/elseif로 푼다.
    -- 한때 "결투 상대는 둘 다"라고 보고 이 조합을 예외로 뺐다가 되돌렸다 --
    -- 결투 상대는 적대로만 잡힌다(유닛 프레임도 적대색이고 힐도 안 들어간다).
    test("우호 x 적대는 모순", function()
        check(issueFor("help", "harm") == NEVER, "이슈가 안 남");
        check(issueFor("harm", "help") == NEVER, "이슈가 안 남");
    end);

    ---------------------------------------------------------------------------
    -- 모순이 아닌 것 - 이슈가 나면 안 된다
    ---------------------------------------------------------------------------

    -- 아래 둘은 `GetBindingInfoForAction`의 정규화가 `"@"`를 흡수해서 여기 오기 전에
    -- 사라진다. 그래도 이슈가 나면 안 되는 건 같다.
    test("같은 값은 모순이 아님", function()
        check(issueFor("help", "help") == nil, "오탐");
        check(issueFor(false, false) == nil, "오탐");
    end);

    test("존재 x 우호는 포섭 관계라 모순이 아님", function()
        check(issueFor(true, "help") == nil, "오탐");
        check(issueFor("help", true) == nil, "오탐");
    end);

    -- 개별 유닛 조건이 없으면 nil이 "다른 값"으로 읽혀서 `"@"`만 걸어둔 액션
    -- ("대상이 존재할 때만")이 곧바로 모순으로 잡혔던 자리.
    test("\"@\"만 걸린 액션은 모순이 아님", function()
        local action = {
            type = Constants.SPELL, value = 100, unit = "target",
            checkedUnits = { ["@"] = true },
        };
        check(GetBindingIssue(action, "checkedUnits") == nil, "오탐 - 비교 상대가 없다");
    end);

    return T;
end
