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

    ---------------------------------------------------------------------------
    -- hover 조건 x 유닛 조건
    --
    -- 대상이 `@hover`면 hover 조건과 `"@"` 조건이 같은 유닛을 두고 말한다. 값이 서로
    -- 다른 필드에 앉아 있어서(`reactions` 대 `checkedUnits`) 조합을 손으로 나열하던
    -- 시절에는 비교 대상조차 아니었다. 두 조건이 한 축에 접히면서 따로가 아니게 됐다.
    ---------------------------------------------------------------------------

    local function hoverAction(reactions, atValue)
        return {
            type = Constants.SPELL, value = 100, unit = "hover",
            hover = true, reactions = reactions,
            checkedUnits = { ["@"] = atValue },
        };
    end

    test("hover 반응 x @ 조건이 어긋나면 모순", function()
        check(GetBindingIssue(hoverAction(Constants.REACTION_HELP, "harm")) == NEVER,
            "우호만 걸린 hover에 @=적대인데 이슈가 안 남");
        check(GetBindingIssue(hoverAction(Constants.REACTION_HARM, "help")) == NEVER,
            "적대만 걸린 hover에 @=우호인데 이슈가 안 남");
    end);

    test("hover 반응 x @ 조건이 맞으면 모순이 아님", function()
        check(GetBindingIssue(hoverAction(Constants.REACTION_HELP, "help")) == nil, "오탐");
        check(GetBindingIssue(hoverAction(Constants.REACTION_HELP, true)) == nil,
            "오탐 - 존재는 우호를 포섭한다");
        check(GetBindingIssue(hoverAction(Constants.REACTION_HELP + Constants.REACTION_HARM, "harm")) == nil,
            "오탐 - 적대도 허용된 마스크다");
    end);

    -- hover가 걸린 액션은 마우스오버 중일 때만 발동한다. 그 유닛이 "없을 때"를 같이
    -- 요구하면 남는 상태가 없다.
    test("hover x @=부재는 모순", function()
        check(GetBindingIssue(hoverAction(nil, false)) == NEVER, "이슈가 안 남");
    end);

    ---------------------------------------------------------------------------
    -- 마우스 왼/오른 버튼은 호버 조건이 있어야 쓸 수 있다
    --
    -- 이 판정이 오탐이면 **클릭캐스팅이 통째로 죽는다.** 이슈가 붙은 액션은 `KeyMap`에
    -- 안 들어가고(`Debind.lua`), BUTTON1/BUTTON2에 걸린 것은 거의 전부 클릭캐스팅이다.
    --
    -- 호버 조건이 `checkedUnits["hover"]`로 옮겨간 뒤 이 검사가 `action.hover`를 계속 읽고
    -- 있었다. 그 필드는 이제 저장에 없으므로 **모든** 왼/오른 버튼 바인딩이 지워졌다.
    -- 어느 층도 못 봤다 - 헤드리스에 이 검사의 스펙이 없었고, 화면에는 키가 안 먹는 것으로만
    -- 나타난다.
    ---------------------------------------------------------------------------

    local MOUSE_ISSUE = Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON;

    local function mouseKeyIssue(fields)
        local action = { type = Constants.SPELL, value = 100, key = "BUTTON1" };
        for k, v in pairs(fields or {}) do
            action[k] = v;
        end
        return DebindPrivate.IsKeyInvalidForAction(action, "BUTTON1");
    end

    test("호버 조건이 없는 왼쪽 버튼은 못 쓴다", function()
        check(mouseKeyIssue() == MOUSE_ISSUE, "이슈가 안 남");
    end);

    test("저장된 호버 조건이 있으면 왼쪽 버튼을 쓸 수 있다", function()
        check(mouseKeyIssue({ checkedUnits = { hover = {} } }) == nil, "오탐 - 키가 통째로 죽는다");
        check(mouseKeyIssue({ checkedUnits = { hover = { reaction = Constants.REACTION_HELP } } }) == nil,
            "오탐 - 반응이 걸려도 호버 조건이다");
    end);

    -- "호버 중이 **아닐** 때"는 호버 조건이 켜진 것이 아니다. 마우스 버튼은 커서가 있는
    -- 자리에서 발동하므로 그 조건으로는 유닛 프레임 클릭을 못 받는다.
    test("호버가 false면 왼쪽 버튼을 못 쓴다", function()
        check(mouseKeyIssue({ checkedUnits = { hover = false } }) == MOUSE_ISSUE, "이슈가 안 남");
    end);

    test("마이그레이션이 안 닿은 옛 hover도 같은 답을 낸다", function()
        check(mouseKeyIssue({ hover = true }) == nil, "옛 모양이 안 읽힘");
        check(mouseKeyIssue({ hover = false }) == MOUSE_ISSUE, "옛 false가 안 읽힘");
    end);

    -- 정규화 자체(`"@"`가 언제 지워지는가, 대상이 언제 채워지는가)는 `normalize_spec.lua`가
    -- 본다. 여기는 그 결과에 이슈가 붙는지만 본다.

    return T;
end
