-- IsKeyAlwaysOurs 테스트. 와우 클라이언트 불필요.
--
-- 이 술어가 답하는 것은 **"이 키의 배선이 고정인가"** 하나다 - 즉 SetBindingClick 한 번으로
-- 끝나고 상태에 따라 ClearBinding/SetBinding으로 갈아탈 일이 없는가.
--
-- **"어느 액션인가를 클릭 시점에 정하는가"가 아니다.** 그쪽은 키를 잡는 레코드가 하나라도
-- 있으면 참이고(`hasKeyRecord`), 이 술어가 거짓인 키도 해당된다 - 그런 키는 "잡느냐 놓느냐"만
-- 상태 루프가 계속 정한다. 두 결정이 분리돼 있다(`click-time-eval.md` §6).
--
-- 틀리는 방향이 비대칭이다. 거짓 쪽으로 틀리면 그 키의 배선 판정이 상태 루프에 남을 뿐이라
-- 손해가 재바인딩 몇 번이다. **참 쪽으로 틀리면 키가 조용히 죽는다** - 해제됐어야 할 키가
-- 계속 걸려 있거나, SetBinding으로 나갔어야 할 명령이 클릭 프레임으로 가서 아무 일도 안
-- 한다. 그래서 거짓이어야 하는 경우를 더 촘촘히 본다.
--
-- 입력은 UpdateBindingsMap의 전처리 루프를 지난 뒤의 bindingArray다. 즉 holdsKey가 이미
-- 채워져 있다.

return function(DebindPrivate)
    local IsKeyAlwaysOurs = DebindPrivate.IsKeyAlwaysOurs;
    local Constants = DebindPrivate.Constants;

    local T = { passed = 0, failures = {} };

    local function fail(name, msg)
        T.failures[#T.failures + 1] = name .. ": " .. msg;
    end

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            fail(name, tostring(err));
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "assertion failed", 2);
        end
    end

    --- 기본은 "키를 잡는 무조건 주문 액션". 각 테스트가 필요한 것만 덮어쓴다.
    ---
    --- `isConditional`은 **이 스펙의 어휘일 뿐 바인딩 필드가 아니다.** 판정이 읽는 것은 진짜
    --- 조건이므로(`IsKeyAlwaysOurs` -> 솔버 컬럼), 이 플래그는 조건을 하나 세우는 것으로만
    --- 옮겨진다. 어느 축이든 상관없고 "덮이지 않은 데가 있다"는 것만 있으면 된다.
    ---
    --- 플래그를 그대로 레코드에 남겨두면 아무도 안 읽으므로, 조건 없이 "조건부"라고 적힌
    --- 표현할 수 없는 모양을 시험하게 된다.
    local function b(t)
        t = t or {};
        if (t.holdsKey == nil) then t.holdsKey = true; end
        if (t.isConditional and t.combat == nil) then t.combat = true; end
        t.isConditional = nil;
        t.type = t.type or Constants.SPELL;
        return t;
    end

    --- 손으로 쓴 바인딩을 **프로덕션과 같은 모양**으로 세운다: 조건은 `binding.conditions`
    --- 안에 산다(`Misc.GetBindingInfoForAction`).
    ---
    --- 스펙 리터럴은 평평하게 쓴다. 여든 줄에 `conditions = { ... }`를 손으로 적으면 한 줄
    --- 빠뜨렸을 때 그 조건이 조용히 사라지고, **조건이 사라진 바인딩은 넓어져서** 남을 잘못
    --- 덮는다 - 스펙이 잡아야 할 바로 그 종류의 잘못이 스펙 안에서 난다.
    ---
    --- **무엇이 조건인지는 여기서 안 정한다.** `Constants.IsConditionField`를 그대로 부르므로
    --- 축이 하나 늘어도 이 함수는 안 바뀌고, 프로덕션과 갈릴 자리가 없다.
    local function nest(binding)
        local conditions = binding.conditions or {};
        for k, v in pairs(binding) do
            if (Constants.IsConditionField(k)) then
                conditions[k] = v;
                binding[k] = nil;
            end
        end
        binding.conditions = conditions;
        return binding;
    end

    local function nestAll(bindings)
        for i = 1, #bindings do nest(bindings[i]); end
        return bindings;
    end

    local function expectTrue(bindings, msg)
        check(IsKeyAlwaysOurs(nestAll(bindings)) == true, msg);
    end

    local function expectFalse(bindings, msg)
        check(IsKeyAlwaysOurs(nestAll(bindings)) == false, msg);
    end

    ---------------------------------------------------------------------------
    -- 통과하는 경우
    ---------------------------------------------------------------------------

    test("무조건 액션 하나", function()
        expectTrue({ b() }, "무조건 주문 하나면 항상 클릭으로 걸린다");
    end);

    test("조건부들 뒤에 무조건 폴백", function()
        expectTrue({
            b({ isConditional = true }),
            b({ isConditional = true }),
            b(),
        }, "A가 끝에 있으면 참");
    end);

    test("A 뒤의 UNUSED는 도달하지 않으므로 무시된다", function()
        expectTrue({
            b({ isConditional = true }),
            b(),
            b({ type = Constants.UNUSED }),
        }, "A 아래는 볼 필요가 없다");
    end);

    test("A 뒤의 COMMAND도 마찬가지", function()
        expectTrue({
            b(),
            b({ type = Constants.COMMAND }),
        }, "A 아래는 볼 필요가 없다");
    end);

    ---------------------------------------------------------------------------
    -- 거짓이어야 하는 경우 - §6-1의 세 가지
    ---------------------------------------------------------------------------

    test("6-1-1 실행 순서의 끝이 conditional", function()
        expectFalse({
            b({ isConditional = true }),
            b({ isConditional = true }),
        }, "아무것도 안 맞는 때가 생기므로 해제해야 한다");
    end);

    test("6-1-1 빈 배열", function()
        expectFalse({}, "걸 것이 없다");
    end);

    test("6-1-2 조건부 UNUSED가 A보다 앞", function()
        expectFalse({
            b({ type = Constants.UNUSED, isConditional = true }),
            b(),
        }, "그 조건이 맞으면 키를 놓아줘야 한다");
    end);

    test("6-1-3 조건부 COMMAND가 A보다 앞", function()
        expectFalse({
            b({ type = Constants.COMMAND, isConditional = true }),
            b(),
        }, "SetBinding이냐 SetBindingClick이냐가 갈린다");
    end);

    test("무조건 UNUSED 하나 - A 자신이 비클릭", function()
        expectFalse({ b({ type = Constants.UNUSED }) }, "ClearBinding으로 나간다");
    end);

    test("무조건 COMMAND 하나 - A 자신이 비클릭", function()
        expectFalse({ b({ type = Constants.COMMAND }) }, "SetBinding으로 나간다");
    end);

    ---------------------------------------------------------------------------
    -- 건너뛰어야 하는 항목
    ---------------------------------------------------------------------------

    test("클릭캐스팅 전용 레코드는 키 판정과 무관하다", function()
        expectTrue({
            b({ holdsKey = false, type = Constants.UNUSED, isConditional = true }),
            b(),
        }, "holdsKey가 아닌 UNUSED는 키를 놓아주지 않는다");
    end);

    test("떨궈진 레코드도 건너뛴다", function()
        -- 걸 수단이 없어 UpdateBindingsMap이 isClickCast/holdsKey를 둘 다 false로 만든 것.
        expectTrue({
            b({ holdsKey = false, isConditional = true }),
            b(),
        }, "떨궈진 항목은 아무것도 걸지 않는다");
    end);

    test("전부 클릭캐스팅 전용이면 거짓", function()
        expectFalse({
            b({ holdsKey = false }),
            b({ holdsKey = false }),
        }, "키를 잡는 레코드가 하나도 없다");
    end);

    test("A를 찾기 전의 클릭캐스팅 UNUSED는 A를 막지 않는다", function()
        expectTrue({
            b({ isConditional = true }),
            b({ holdsKey = false, type = Constants.UNUSED }),
            b(),
        }, "중간의 클릭 전용 항목은 투명하다");
    end);

    return T;
end
