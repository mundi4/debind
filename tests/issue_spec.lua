-- `GetBindingIssue`의 유닛 조건 갈래 테스트. 와우 클라이언트 불필요.
--
-- 이 갈래가 왜 위험한가: 이슈가 붙은 액션은 `Debind.lua`에서 `KeyMap`에 아예
-- 안 들어간다. 즉 여기서 나는 **오탐은 표시 버그가 아니라 키가 안 먹는 것**이다.
-- 반대로 놓친 모순은 조용히 아무것도 안 하는 바인딩이 된다.
--
-- `units`의 `"@"`는 그 액션 자신의 대상 유닛을 가리키므로, 같은 유닛에
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
    local function issueFor(atValue, unitValue)
        local action = {
            type = Constants.SPELL,
            value = 100,
            unit = "target",
            units = { ["@"] = atValue, target = unitValue },
        };
        return GetBindingIssue(nest(action), "units");
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
        local action = nest({
            type = Constants.SPELL, value = 100, unit = "target",
            units = { ["@"] = true },
        });
        check(GetBindingIssue(action, "units") == nil, "오탐 - 비교 상대가 없다");
    end);

    ---------------------------------------------------------------------------
    -- hover 조건 x 유닛 조건
    --
    -- 대상이 `@hover`면 hover 조건과 `"@"` 조건이 같은 유닛을 두고 말한다. 값이 서로
    -- 다른 필드에 앉아 있어서(`reactions` 대 `units`) 조합을 손으로 나열하던
    -- 시절에는 비교 대상조차 아니었다. 두 조건이 한 축에 접히면서 따로가 아니게 됐다.
    ---------------------------------------------------------------------------

    --- `hover`/`reactions`는 최상단 그대로 둔다. `dbver <= 4`가 저장에서 없앤 짝이고,
    --- 지금 모양으로 접는 것은 `GetBindingInfoForAction`이 한다. 조건 이름만 `nest`가 내린다.
    local function hoverAction(reactions, atValue)
        return nest({
            type = Constants.SPELL, value = 100, unit = "hover",
            hover = true, reactions = reactions,
            units = { ["@"] = atValue },
        });
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
    -- 모순은 **고칠 수 있는 모든 묶음**이 빨개져야 한다
    --
    -- 한 유닛의 마스크가 0이 되는 데는 여러 메뉴가 같이 관여한다. 대상이 `hover`인 액션에
    -- hover 조건을 [안 올렸을 때]로 걸면 겨눌 유닛이 놓일 자리가 없는데, hover 메뉴에서
    -- 풀 수도 있고 대상 메뉴에서 다른 유닛을 골라 풀 수도 있다.
    --
    -- 한쪽만 칠하면 나머지를 연 사람은 멀쩡한 화면을 본다. 더 나쁜 것은 그 묶음이 **하늘색
    -- (활성)으로 뜬다**는 것이다 - "조건이 걸려 있음"과 "조건이 깨져 있음"이 같은 화면에서
    -- 반대로 읽힌다.
    ---------------------------------------------------------------------------

    --- 대상이 hover인데 hover 조건이 "안 올렸을 때"다. 겹치는 상태가 없다.
    local function hoverTargetConflict()
        return nest({
            type = Constants.SPELL, value = 100, key = "F1", unit = "hover",
            units = { ["@"] = {}, hover = { exists = false } },
        });
    end

    test("hover x 대상 모순은 액션 전체에서 잡힌다", function()
        check(GetBindingIssue(hoverTargetConflict()) == NEVER, "이슈가 안 남");
    end);

    test("hover x 대상 모순은 hover 묶음을 칠한다", function()
        check(GetBindingIssue(hoverTargetConflict(), "hover") == NEVER,
            "hover 메뉴가 안 빨개진다 - 거기서 고칠 수 있는 문제다");
    end);

    test("hover x 대상 모순은 대상 묶음도 칠한다", function()
        check(GetBindingIssue(hoverTargetConflict(), "unit") == NEVER,
            "대상 메뉴가 안 빨개진다 - 하늘색으로 떠서 정상으로 읽힌다");
    end);

    test("hover x 대상 모순은 그 대상의 서브메뉴도 칠한다", function()
        check(GetBindingIssue(hoverTargetConflict(), "units", nil, "@") == NEVER,
            "\"@\" 서브메뉴가 안 빨개진다");
    end);

    -- `Units` 묶음은 `"hover"`를 줄로 안 갖는다. 안 보여주는 조건으로 칠하면 어디를 고쳐야
    -- 하는지가 오히려 안 보인다.
    test("hover x 대상 모순으로 Units 묶음은 안 칠한다", function()
        check(GetBindingIssue(hoverTargetConflict(), "units") == nil, "오탐");
    end);

    --- `"@"`와 같은 유닛의 명시 조건이 어긋난다. 대상 메뉴와 Units 메뉴 둘 다 고칠 수 있다.
    local function targetUnitConflict()
        return nest({
            type = Constants.SPELL, value = 100, key = "F1", unit = "focus",
            units = {
                ["@"] = { reaction = Constants.REACTION_HELP },
                focus = { reaction = Constants.REACTION_HARM },
            },
        });
    end

    -- **안 거든 묶음은 안 칠한다.** hover에서 반응을 하나도 안 고른 것은 hover 메뉴의 문제이고
    -- 제 이름(`HOVER_NONE_SELECTED`)이 있다. 대상 메뉴는 아무것도 안 골랐는데 빨개지면
    -- 어디를 봐야 하는지가 오히려 안 보인다.
    test("hover의 빈 반응만으로 대상 묶음이 빨개지지 않는다", function()
        local action = nest({ type = Constants.SPELL, value = 100, key = "F1", unit = "hover",
            units = { hover = { reaction = 0 } } });
        check(GetBindingIssue(action, "unit") == nil, "안 거든 묶음을 칠했다");
        check(GetBindingIssue(action, "hover") ~= nil, "hover 묶음은 잡아야 한다");
    end);

    -- 겨눌 대상이 없으면 `"@"`가 가리킬 유닛도 없다. 그때 이 서브메뉴는 **아무것도 안 묻는
    -- 것**이지 "전부 묻는 것"이 아니다.
    test("대상이 없으면 \"@\" 서브메뉴가 남의 모순을 안 보여준다", function()
        local action = nest({ type = Constants.SPELL, value = 100, key = "F1",
            units = {
                focus = { reaction = 0 },
            } });
        check(GetBindingIssue(action, "units", nil, "@") == nil,
            "\"@\"가 가리킬 유닛이 없는데 남의 유닛 모순이 떴다");
    end);

    test("\"@\" x 유닛 조건 모순은 양쪽 묶음을 다 칠한다", function()
        check(GetBindingIssue(targetUnitConflict(), "unit") == NEVER,
            "대상 메뉴가 안 빨개진다");
        check(GetBindingIssue(targetUnitConflict(), "units") == NEVER,
            "Units 묶음이 안 빨개진다");
        check(GetBindingIssue(targetUnitConflict(), "units", nil, "focus") == NEVER,
            "그 유닛의 서브메뉴가 안 빨개진다");
    end);

    ---------------------------------------------------------------------------
    -- 마우스 왼/오른 버튼은 호버 조건이 있어야 쓸 수 있다
    --
    -- 이 판정이 오탐이면 **클릭캐스팅이 통째로 죽는다.** 이슈가 붙은 액션은 `KeyMap`에
    -- 안 들어가고(`Debind.lua`), BUTTON1/BUTTON2에 걸린 것은 거의 전부 클릭캐스팅이다.
    --
    -- 호버 조건이 `units["hover"]`로 옮겨간 뒤 이 검사가 `action.hover`를 계속 읽고
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
        return DebindPrivate.IsKeyInvalidForAction(nest(action), "BUTTON1");
    end

    test("호버 조건이 없는 왼쪽 버튼은 못 쓴다", function()
        check(mouseKeyIssue() == MOUSE_ISSUE, "이슈가 안 남");
    end);

    test("저장된 호버 조건이 있으면 왼쪽 버튼을 쓸 수 있다", function()
        check(mouseKeyIssue({ units = { hover = {} } }) == nil, "오탐 - 키가 통째로 죽는다");
        check(mouseKeyIssue({ units = { hover = { reaction = Constants.REACTION_HELP } } }) == nil,
            "오탐 - 반응이 걸려도 호버 조건이다");
    end);

    -- "호버 중이 **아닐** 때"는 호버 조건이 켜진 것이 아니다. 마우스 버튼은 커서가 있는
    -- 자리에서 발동하므로 그 조건으로는 유닛 프레임 클릭을 못 받는다.
    test("호버가 false면 왼쪽 버튼을 못 쓴다", function()
        check(mouseKeyIssue({ units = { hover = false } }) == MOUSE_ISSUE, "이슈가 안 남");
    end);

    -- 저장에는 끈 조건이 표로 남는다. 표라는 이유만으로 "켜짐"이라고 읽으면 이 판정이
    -- 뒤집혀서, 걸리지 말아야 할 왼쪽 버튼이 통과하고 걸릴 것이 안 걸린다.
    test("끈 호버 조건은 왼쪽 버튼을 못 쓰게 한다", function()
        check(mouseKeyIssue({ units = { hover = { exists = false } } }) == MOUSE_ISSUE,
            "\"없을 때\"를 켜진 것으로 읽었다");
        check(mouseKeyIssue({ units = { hover = { off = true,
            reaction = Constants.REACTION_HELP } } }) == MOUSE_ISSUE,
            "기억만 하는 값을 켜진 것으로 읽었다");
    end);

    -- 같은 값이 반대 방향으로도 샌다: 꺼진 조건을 켜진 것으로 읽으면 hover + COMMAND 검사가
    -- 걸려서 멀쩡한 액션이 `KeyMap`에서 빠진다.
    test("끈 호버 조건은 명령 액션을 막지 않는다", function()
        local HOVER_COMMAND = Constants.BINDING_ISSUE_NOT_SUPPORTED_HOVER_CLICK_COMMAND;
        local function commandIssue(hoverCondition)
            return DebindPrivate.IsKeyInvalidForAction(nest({
                type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "BUTTON3",
                units = { hover = hoverCondition },
            }), "BUTTON3");
        end

        -- 켜져 있으면 걸리는 것이 맞다. 이 줄이 없으면 아래가 "아무것도 안 걸리는" 것과
        -- 구분되지 않는다.
        check(commandIssue({}) == HOVER_COMMAND, "전제가 깨졌다 - 켜진 호버는 걸려야 한다");

        check(commandIssue({ off = true, reaction = Constants.REACTION_HELP }) ~= HOVER_COMMAND,
            "기억만 하는 값으로 호버-명령 검사가 걸렸다");
        check(commandIssue({ exists = false }) ~= HOVER_COMMAND,
            "\"없을 때\"로 호버-명령 검사가 걸렸다");
    end);

    test("마이그레이션이 안 닿은 옛 hover도 같은 답을 낸다", function()
        check(mouseKeyIssue({ hover = true }) == nil, "옛 모양이 안 읽힘");
        check(mouseKeyIssue({ hover = false }) == MOUSE_ISSUE, "옛 false가 안 읽힘");
    end);

    ---------------------------------------------------------------------------
    -- 매크로 본문의 정의되지 않은 `[$상태]`
    --
    -- 파서는 `[a-zA-Z0-9_]+`면 무엇이든 상태 인자로 통과시킨다. 정의를 못 찾으면 코드젠이
    -- 그 자리를 `""`로 구웠고, `[$typo]`가 `[]`가 되어 **항상 참**이 됐다 - 오타 하나가
    -- 바인딩을 덜 나가게 하는 게 아니라 **더** 나가게 만든다. 키바인딩 애드온에서 가장
    -- 나쁜 실패 방향이라 마커로 앞을 막고 코드젠에서 뒤를 막는다.
    --
    -- 이 마커가 오탐이면 멀쩡한 매크로 바인딩이 `KeyMap`에서 통째로 빠진다. 그래서 아래
    -- "이슈가 나면 안 되는" 절반이 나는 쪽만큼 중요하다.
    ---------------------------------------------------------------------------

    local UNDEFINED = Constants.BINDING_ISSUE_UNDEFINED_STATE;

    local function macroAction(body)
        return { type = Constants.MACROTEXT, value = body, key = "F1" };
    end

    --- **정의는 이 스펙이 세운다.** 예전엔 이름이 `$state1`~`$state5`이기만 하면 정의된 것으로
    --- 쳤고, 그 다섯은 로드마다 심겼으니 아무 데도 안 세워도 답이 나왔다. 이제 판정은
    --- "정의가 있느냐"이고 정의는 누가 만들어야 있다 - 세우지 않으면 이 절의 절반이 앞서 돈
    --- 다른 스펙이 프로필에 남긴 것을 읽게 된다.
    DebindPrivate.Switches = {
        ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL, value = false },
        ["$state5"] = { mode = Constants.SWITCH_MODES.MANUAL, value = false },
        -- 다섯 밖의 이름도 정의될 수 있다는 것이 이 단계에서 바뀐 것이다. 아래 "정의되지 않은"
        -- 절반이 **이름의 생김새가 아니라 정의의 유무**를 보는지가 이 한 줄에 걸린다.
        ["$burst"] = { mode = Constants.SWITCH_MODES.MANUAL, value = false },
    };

    test("정의된 상태 이름은 이슈가 아니다", function()
        check(GetBindingIssue(macroAction("/cast [$state1] Foo")) == nil, "오탐 - 키가 죽는다");
        check(GetBindingIssue(macroAction("/cast [no$state5] Foo")) == nil, "오탐 - 키가 죽는다");
        check(GetBindingIssue(macroAction("/cast [@focus,harm] Foo")) == nil,
            "오탐 - 상태를 안 쓰는 매크로다");
    end);

    -- 판정이 이름의 생김새였을 때는 `$state`로 시작하지 않는 이름이 무조건 미정의였다.
    test("다섯 밖의 이름도 정의돼 있으면 이슈가 아니다", function()
        check(GetBindingIssue(macroAction("/cast [$burst] Foo")) == nil,
            "정의해둔 이름을 미정의로 읽었다 - 키가 죽는다");
        check(GetBindingIssue(macroAction("/cast [no$burst] Foo")) == nil,
            "부정형에서 정의해둔 이름을 미정의로 읽었다");
    end);

    -- 그 반대편. 다섯 안의 이름이어도 정의가 없으면 미정의다 - 다섯을 미리 안 만들면서
    -- 실제로 생기는 경우고, 코드젠도 그 이름을 `known:0`으로 굽는다.
    test("다섯 안의 이름도 정의가 없으면 이슈가 난다", function()
        check(GetBindingIssue(macroAction("/cast [$state3] Foo")) == UNDEFINED,
            "정의가 없는데 이름 생김새로 통과시켰다 - 매크로가 조건을 잃은 채 나간다");
    end);

    test("정의되지 않은 이름은 이슈가 난다", function()
        check(GetBindingIssue(macroAction("/cast [$typo] Foo")) == UNDEFINED, "이슈가 안 남");
    end);

    -- 부정형은 지금도 `known:0`으로 구워져 거짓으로 떨어진다 - 위험하지는 않다. 그래도
    -- 오타인 것은 똑같고, 한쪽만 말해주면 사용자는 고친 뒤에도 왜 안 되는지 모른다.
    test("부정형 오타도 이슈가 난다", function()
        check(GetBindingIssue(macroAction("/cast [no$typo] Foo")) == UNDEFINED, "이슈가 안 남");
    end);

    -- `States[]`도 정의 표도 정확히 일치한다. 대소문자가 다르면 런타임에 그냥 미정의고,
    -- 눈으로는 맞아 보이는 것이 이 검사가 있어야 하는 이유다.
    test("대소문자가 다르면 미정의다", function()
        check(GetBindingIssue(macroAction("/cast [$State1] Foo")) == UNDEFINED, "이슈가 안 남");
    end);

    -- 여러 개면 첫 번째를 말한다. 툴팁이 이름을 적는 자리라 "무엇을" 고칠지가 하나여야 한다.
    test("틀린 이름을 그대로 돌려준다", function()
        check(DebindPrivate.GetUndefinedSwitch(macroAction("/cast [$state1,no$typo] Foo")) == "$typo",
            "이름을 못 돌려주면 툴팁이 무엇을 고칠지 말할 수 없다");
        check(DebindPrivate.GetUndefinedSwitch(macroAction("/cast [$state1] Foo")) == nil, "오탐");
    end);

    -- 본문을 파싱하는 타입만 본다. 다른 타입의 `value`는 매크로 본문이 아니라서 같은
    -- 글자가 들어 있어도 조건이 아니다.
    test("매크로 본문이 아닌 타입은 안 본다", function()
        local action = { type = Constants.COMMAND, value = "/cast [$typo] Foo", key = "F1" };
        check(GetBindingIssue(action) == nil, "오탐 - 본문으로 읽었다");
    end);

    -- 조건 메뉴가 없는 갈래라 짚어 묻는 호출자는 없지만, 갈래 이름은 있어야 다른 갈래를
    -- 짚어 묻는 자리(단축키 칸, 서브메뉴)가 이 이슈를 자기 것으로 착각하지 않는다.
    test("다른 갈래를 물으면 안 나온다", function()
        check(GetBindingIssue(macroAction("/cast [$typo] Foo"), "key") == nil, "단축키 칸이 빨개진다");
        check(GetBindingIssue(macroAction("/cast [$typo] Foo"), "unit") == nil, "대상 메뉴가 빨개진다");
        check(GetBindingIssue(macroAction("/cast [$typo] Foo"), nil, "states") == nil,
            "갈래를 껐는데도 나온다");
    end);

    ---------------------------------------------------------------------------
    -- A condition on a switch nothing defines
    --
    -- **The third place a switch is named, and the last one to be marked.** It could not dangle
    -- while the five always had definitions planted for them, and the `dbver` 6 step keeps every
    -- definition a condition still names -- so nothing in a migrated profile reaches this. What
    -- reaches it is the two things that arrived with §6-B: a switch **deleted** from the list, and
    -- an imported string naming one this profile never had.
    --
    -- **The mark changes nothing about what fires.** Codegen bakes the condition whether or not
    -- anything defines the name, and the restricted side compares `States[name] ~= v` against a
    -- `nil` -- so the binding already never matched, on `true` or on `false` alike. What the mark
    -- adds is the reason, on the row and in the tooltip, instead of a binding that looks ordinary
    -- and quietly does nothing.
    ---------------------------------------------------------------------------

    local function conditionAction(conditions)
        return { type = Constants.SPELL, value = 1, key = "F1", conditions = conditions };
    end

    test("정의 없는 스위치를 조건으로 건 액션은 이슈가 난다", function()
        check(GetBindingIssue(conditionAction({ ["$typo"] = true })) == UNDEFINED,
            "켜짐 조건이 멀쩡한 줄로 그려진다 - 눌러도 아무 일이 없는데 이유가 화면에 없다");
        -- 꺼짐 조건도 같이 죽는다. `States[이름]`이 nil이라 `nil ~= false`가 참이 되어
        -- 안 맞는 쪽으로 떨어진다 - 여기만 빠뜨리면 절반이 조용한 채로 남는다.
        check(GetBindingIssue(conditionAction({ ["$typo"] = false })) == UNDEFINED,
            "꺼짐 조건은 안 잡는다");
    end);

    test("정의된 스위치를 조건으로 건 액션은 이슈가 아니다", function()
        check(GetBindingIssue(conditionAction({ ["$state1"] = true })) == nil,
            "오탐 - 멀쩡한 조건부 바인딩이 통째로 죽는다");
        check(GetBindingIssue(conditionAction({ ["$burst"] = false })) == nil,
            "다섯 밖의 이름을 정의해둔 채로 미정의로 읽었다");
    end);

    -- 액션의 `value`를 안 보는 타입에도 조건은 걸린다. 본문이나 대상만 보던 시절의 가드가
    -- 남아 있으면 주문 액션의 조건은 통째로 안 읽힌다.
    test("본문도 대상도 없는 타입의 조건까지 본다", function()
        check(GetBindingIssue({ type = Constants.SPELL, value = 585, key = "F1",
            conditions = { ["$typo"] = true } }) == UNDEFINED, "값이 문자열이 아니면 안 본다");
    end);

    -- **조건만 보는 문이 따로 있는 이유.** 조건 메뉴의 스위치 칸이 이 답으로 빨개지는데
    -- (`CreateSwitchConditionMenu`), 셋을 다 보는 쪽을 쓰면 **본문 오타 하나에 조건 칸이
    -- 빨개진다** - 조건은 멀쩡한데 고칠 데를 엉뚱한 곳으로 가리키는 표시다.
    test("조건만 보는 문은 본문과 대상을 안 본다", function()
        local body = macroAction("/cast [$typo] Foo");
        check(DebindPrivate.GetUndefinedSwitch(body) == "$typo", "전제가 깨졌다");
        check(DebindPrivate.GetUndefinedSwitchCondition(body) == nil,
            "본문 오타에 조건 칸이 빨개진다");

        local target = { type = Constants.SETSTATE_ON, value = "$typo", key = "F1" };
        check(DebindPrivate.GetUndefinedSwitchCondition(target) == nil,
            "대상 오타에 조건 칸이 빨개진다");

        check(DebindPrivate.GetUndefinedSwitchCondition(conditionAction({ ["$typo"] = true }))
            == "$typo", "조건은 잡아야 한다");
    end);

    -- 이름을 문장에 찍어 넣는 자리가 있으므로(메뉴), 여러 개일 때 **매번 같은 이름**이 나와야
    -- 한다. `pairs` 순서를 그대로 쓰면 열 때마다 다른 이름이 나온다.
    test("정의 없는 조건이 여럿이면 늘 같은 이름을 낸다", function()
        local action = conditionAction({ ["$zzz"] = true, ["$aaa"] = true, ["$mmm"] = false });
        for _ = 1, 5 do
            check(DebindPrivate.GetUndefinedSwitchCondition(action) == "$aaa",
                "열 때마다 다른 이름이 나온다");
        end
    end);

    ---------------------------------------------------------------------------
    -- An on/off/toggle action naming a switch nothing defines
    --
    -- **A switch is named in two places and only one of them is a macro body.** The other is
    -- `action.value` on the three setting types, where no parser runs, no condition row draws it,
    -- and until now nothing looked: the row drew clean and the press set a name that exists
    -- nowhere. The switch never came on, and nothing on screen said why.
    --
    -- **The mark is the whole warning.** An imported string plants no definitions on purpose
    -- (`devdocs/building-export-import.md`), so a shared action pointing at a switch the reader
    -- has never made arrives with nothing else to announce it.
    --
    -- Marked means dropped from `KeyMap`, which is what the missing-macro branch below already
    -- does and for the same reason: a key that did nothing on press loses nothing by not binding.
    ---------------------------------------------------------------------------

    local function setSwitchAction(actionType, name)
        return { type = actionType, value = name, key = "F1" };
    end

    test("정의 없는 이름을 가리키는 스위치 액션은 이슈가 난다", function()
        check(GetBindingIssue(setSwitchAction(Constants.SETSTATE_ON, "$typo")) == UNDEFINED,
            "켜기가 아무 데도 없는 이름을 가리킨 채 멀쩡한 줄로 그려진다");
        check(GetBindingIssue(setSwitchAction(Constants.SETSTATE_OFF, "$typo")) == UNDEFINED,
            "끄기가 아무 데도 없는 이름을 가리킨 채 멀쩡한 줄로 그려진다");
        check(GetBindingIssue(setSwitchAction(Constants.SETSTATE_TOGGLE, "$typo")) == UNDEFINED,
            "전환이 아무 데도 없는 이름을 가리킨 채 멀쩡한 줄로 그려진다");
    end);

    -- The other half, and it is the expensive one to get wrong: a false positive here takes a
    -- working switch action out of `KeyMap`.
    test("정의된 이름을 가리키는 스위치 액션은 이슈가 아니다", function()
        check(GetBindingIssue(setSwitchAction(Constants.SETSTATE_ON, "$state1")) == nil,
            "오탐 - 키가 죽는다");
        check(GetBindingIssue(setSwitchAction(Constants.SETSTATE_TOGGLE, "$burst")) == nil,
            "다섯 밖의 이름을 정의해둔 채로 미정의로 읽었다");
    end);

    -- 같은 갈래다. 갈래를 끈 호출에서도 같이 꺼져야 둘이 한 갈래로 산다.
    test("스위치 액션도 states 갈래다", function()
        check(GetBindingIssue(setSwitchAction(Constants.SETSTATE_ON, "$typo"), nil, "states") == nil,
            "갈래를 껐는데도 나온다");
    end);

    -- 정규화 자체(`"@"`가 언제 지워지는가, 대상이 언제 채워지는가)는 `normalize_spec.lua`가
    -- 본다. 여기는 그 결과에 이슈가 붙는지만 본다.

    ---------------------------------------------------------------------------
    -- 계산식이 부르는 이름
    --
    -- **이름이 적히는 다섯 번째 자리이고, 유일하게 액션 안이 아니다.** 위 넷은 전부 액션을
    -- 물어서 답이 나오는데 계산식은 정의에 산다 - 건네줄 액션이 없어서 `GetBindingIssue`가
    -- 아예 못 본다. 그래서 문이 따로 있고, 그 문을 읽는 곳도 `Switches` 탭 하나다.
    --
    -- 여기가 비어 있으면 어떻게 되는가: 지운 이름이 코드젠에서 `known:0`으로 구워져
    -- (`EmitMacroTextArg`) 그 스위치가 영영 거짓이 되는데, 계산식은 화면에 그대로 맞게
    -- 보인다. 삭제가 참조를 일부러 남기는 것이 설계이므로(`DeleteSwitch`), 빨간 것이
    -- 없으면 그 설계가 성립하지 않는다.
    ---------------------------------------------------------------------------

    local GetUndefinedSwitchInExpr = DebindPrivate.GetUndefinedSwitchInExpr;

    test("계산식이 부르는 정의 없는 이름을 돌려준다", function()
        check(GetUndefinedSwitchInExpr("[$typo]", "$derived") == "$typo", "안 잡는다");
        check(GetUndefinedSwitchInExpr("[$state1,$typo]", "$derived") == "$typo",
            "멀쩡한 이름 뒤에 오면 못 잡는다");
    end);

    -- 오탐 쪽. 여기가 틀리면 멀쩡한 계산식 스위치가 빨간 채로 앉아 있고, 읽는 사람은 고칠 것이
    -- 없는 것을 고치러 간다.
    test("정의된 이름만 부르는 계산식은 깨끗하다", function()
        check(GetUndefinedSwitchInExpr("[$state1]", "$derived") == nil, "오탐");
        check(GetUndefinedSwitchInExpr("[combat,nostealth]", "$derived") == nil,
            "스위치를 안 부르는 계산식인데 뭔가 돌려준다");
        -- **`@hover`이지 `@focus`가 아니다.** 파서가 인자로 적어두는 것은 값을 갈아끼워야 하는
        -- 별칭뿐이고, 맨 유닛 토큰은 글자 그대로 남아 인자 목록에 아예 안 들어온다 - 그것으로는
        -- 인자 종류를 안 보는 판까지 통과한다.
        check(GetUndefinedSwitchInExpr("[@hover,harm]", "$derived") == nil, "유닛을 스위치로 읽었다");
    end);

    -- **자기 참조는 미정의가 아니다.** 코드젠이 그 자리를 지워서 굽지(`EmitMacroTextArg`) 죽은
    -- 이름으로 치지 않는다. 여기서 갈라주지 않으면 `[$a]`를 품은 `$a`가 영원히 빨갛고, 읽는
    -- 사람에게는 만들 수 없는 이름을 만들라는 말이 된다.
    test("자기 자신을 부르는 것은 미정의가 아니다", function()
        check(GetUndefinedSwitchInExpr("[$a]", "$a") == nil, "자기 참조를 죽은 이름으로 읽었다");
        check(GetUndefinedSwitchInExpr("[$a,$typo]", "$a") == "$typo",
            "자기 참조를 건너뛰면서 뒤의 오타까지 놓쳤다");
    end);

    -- 부정형도 같이 본다. 매크로 본문 쪽과 같은 이유다 - 지금도 거짓으로 떨어져 위험하지는
    -- 않지만 오타인 것은 똑같고, 한쪽만 말해주면 고쳐도 왜 안 되는지 알 수 없다.
    test("부정형 오타도 잡는다", function()
        check(GetUndefinedSwitchInExpr("[no$typo]", "$derived") == "$typo", "안 잡는다");
    end);

    -- 답이 `[식]`이 아닌 행은 계산식을 안 읽는데 글자는 들고 있다(`SetSwitchAnswer`가 일부러
    -- 안 지운다). 그 nil이 여기까지 오므로 문이 스스로 답해야 한다.
    test("계산식이 없으면 nil이다", function()
        check(GetUndefinedSwitchInExpr(nil, "$derived") == nil, "nil에 터진다");
        check(GetUndefinedSwitchInExpr("", "$derived") == nil, "빈 문자열에 뭔가 돌려준다");
    end);

    ---------------------------------------------------------------------------
    -- A `MACRO` naming a macro that is not here
    --
    -- The one issue branch about what an action **points at**. Before it existed such an action
    -- bound normally and did nothing on press -- no error, no mark -- which is the failure the
    -- sharing format's "send broken things too, the reader sees red" rule leans on
    -- (`devdocs/building-export-import.md`).
    --
    -- Both halves matter as much as they do above: a false positive here does not grey a row, it
    -- takes a working macro binding out of `KeyMap` entirely.
    ---------------------------------------------------------------------------

    local MISSING_MACRO = Constants.BINDING_ISSUE_MISSING_MACRO;

    -- `export_spec` installs its own `GetMacroInfo` on the same global, so this spec stands up the
    -- store it wants rather than borrowing whatever ran last.
    local MACROS = {};
    _G.GetMacroInfo = function(nameOrIndex)
        local macro = MACROS[nameOrIndex];
        if (not macro) then
            return nil;
        end
        return macro.name, macro.icon, macro.body;
    end

    MACROS = {
        ["Kick+Pet"] = { name = "Kick+Pet", icon = 1, body = "/cast Kick" },
        [3] = { name = "By index", icon = 1, body = "/cast Kick" },
    };

    local function macroValueAction(value)
        return { type = Constants.MACRO, value = value, key = "F1" };
    end

    test("있는 매크로는 이슈가 아니다", function()
        check(GetBindingIssue(macroValueAction("Kick+Pet")) == nil, "오탐 - 멀쩡한 키가 죽는다");
    end);

    test("없는 매크로는 이슈가 난다", function()
        check(GetBindingIssue(macroValueAction("Kick+Pet2")) == MISSING_MACRO, "이슈가 안 남");
    end);

    -- The store is keyed by exactly what the game answers to. A name that only differs in case is
    -- a different macro to `GetMacroInfo`, and the row shows the two spelled the same way.
    test("대소문자가 다르면 없는 매크로다", function()
        check(GetBindingIssue(macroValueAction("kick+pet")) == MISSING_MACRO, "이슈가 안 남");
    end);

    -- **A macro reference is a name, at every moment.** `GetMacroInfo` answering to a slot number
    -- as well is the trap: a number is a position in a name-ordered list, so it still resolves the
    -- day after a macro sorting ahead of it is created or deleted, and what it resolves to is a
    -- different macro. Nothing goes red, because nothing broke. This is not about one install
    -- reading another's string; it is one account on its own.
    --
    -- Nor is there a way back to a name. Asking what slot 3 holds answers for the store as it is
    -- right now, which guesses at what was meant.
    --
    -- So this branch is the last gate. A number is not asked about, it is reported. Reporting drops
    -- the action out of `KeyMap` (`BuildKeyMap`), which is what leaves a number no path to a
    -- binding.
    test("슬롯 번호는 물어보지도 않고 이슈다", function()
        check(GetBindingIssue(macroValueAction(3)) == MISSING_MACRO,
            "풀리는 번호라고 통과시키면 그 자리 매크로가 조용히 눌린다");
        check(GetBindingIssue(macroValueAction(4)) == MISSING_MACRO, "없는 번호가 안 걸림");
    end);

    -- The rest of the same gate. Letting a valueless `MACRO` through leaves a key that does nothing
    -- when pressed sitting in the list wearing an ordinary face.
    test("이름이 아니면 무엇이든 이슈다", function()
        check(GetBindingIssue(macroValueAction(nil)) == MISSING_MACRO, "값 없는 매크로가 안 걸림");
        check(GetBindingIssue(macroValueAction({})) == MISSING_MACRO, "테이블이 안 걸림");
    end);

    -- The tooltip takes this through `%s`, so the case with no name to print must not put the word
    -- "nil" in front of the user.
    test("적을 이름이 없으면 빈 문자열이지 nil이라는 글자가 아니다", function()
        check(DebindPrivate.GetMissingMacroName(macroValueAction(nil)) == "",
            "값 " .. tostring(DebindPrivate.GetMissingMacroName(macroValueAction(nil))));
        check(DebindPrivate.GetMissingMacroName(macroValueAction(3)) == "3", "번호는 그대로 보인다");
    end);

    -- Every other type stores something that resolves the same way on every install, so nothing
    -- else may be reported here. `MACROTEXT` matters most: its body travels whole, and a body that
    -- happens to hold a macro's name is not a reference to it.
    test("다른 타입은 안 본다", function()
        check(GetBindingIssue({ type = Constants.MACROTEXT, value = "/cast Kick+Pet2", key = "F1" })
            ~= MISSING_MACRO, "오탐 - 본문을 이름으로 읽었다");
        check(GetBindingIssue({ type = Constants.COMMAND, value = "Kick+Pet2", key = "F1" })
            ~= MISSING_MACRO, "오탐 - 명령 이름을 매크로로 읽었다");
    end);

    test("틀린 이름을 그대로 돌려준다", function()
        check(DebindPrivate.GetMissingMacroName(macroValueAction("Kick+Pet2")) == "Kick+Pet2",
            "이름을 못 돌려주면 툴팁이 무엇을 고칠지 말할 수 없다");
        check(DebindPrivate.GetMissingMacroName(macroValueAction("Kick+Pet")) == nil, "오탐");
    end);

    --- **없는 갈래로 물으면 DEBUG에서 걸린다.**
    ---
    --- 없는 이름은 모든 `if`를 비켜가 nil을 낸다. 그건 "문제 없음"과 생김새가 같아서, 목록
    --- 행이 그렇게 죽은 갈래 넷을 묻는 동안 아무 신호도 없었다. 배포본에서는 안 세운다 -
    --- 잘못 물어 잃는 것은 경고 하나뿐이고, 그걸로 키를 죽일 이유가 없다.
    test("없는 갈래로 물으면 DEBUG에서 걸린다", function()
        if (not Constants.DEBUG) then
            return;
        end
        local action = nest({ type = Constants.SPELL, value = 100, key = "F", combat = true });
        check(pcall(GetBindingIssue, action, "combat") == false,
            "`combat`은 갈래가 없는데 조용히 nil이 나온다");
        check(pcall(GetBindingIssue, action, "groups") == true, "있는 갈래가 걸렸다");
    end);

    test("다른 갈래를 물으면 안 나온다", function()
        check(GetBindingIssue(macroValueAction("Kick+Pet2"), "key") == nil, "단축키 칸이 빨개진다");
        check(GetBindingIssue(macroValueAction("Kick+Pet2"), "unit") == nil, "대상 메뉴가 빨개진다");
        check(GetBindingIssue(macroValueAction("Kick+Pet2"), nil, "macro") == nil,
            "갈래를 껐는데도 나온다");
    end);

    ---------------------------------------------------------------------------
    -- An axis with every value turned off
    ---------------------------------------------------------------------------

    -- **A mask of zero is not "no restriction", it is "nothing".** The two read alike in the
    -- window -- a group of checkboxes with none ticked looks much like one nobody has opened --
    -- and they are opposite answers: the first fires everywhere and the second can never fire at
    -- all. The reader has to be told, and telling them is the whole of what this branch does.
    --
    -- Each of the three carries its own code, so the window can redden the group it belongs to.
    test("an axis with nothing selected is reported, per axis", function()
        local CASES = {
            { field = "groups", code = Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED },
            { field = "forms", code = Constants.BINDING_ISSUE_FORMS_NONE_SELECTED },
            { field = "bonusbars", code = Constants.BINDING_ISSUE_BONUSBARS_NONE_SELECTED },
        };

        for i = 1, #CASES do
            local case = CASES[i];
            local action = { type = Constants.SPELL, value = 585, key = "T",
                conditions = { [case.field] = 0 } };
            check(GetBindingIssue(action) == case.code,
                case.field .. ": " .. tostring(GetBindingIssue(action)));
        end
    end);

    -- The other direction, which is the half that makes the test mean anything: an axis with
    -- **some** of its values selected is an ordinary condition and must not be reported.
    test("an axis with something selected is not reported", function()
        local action = { type = Constants.SPELL, value = 585, key = "T", conditions = {
            groups = Constants.GROUP_PARTY, forms = 3, bonusbars = 5,
        } };
        check(GetBindingIssue(action) == nil, "issue: " .. tostring(GetBindingIssue(action)));
    end);

    return T;
end
