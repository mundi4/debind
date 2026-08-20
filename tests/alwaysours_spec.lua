-- "이 키는 상태가 뭐가 되든 우리 것인가" 판정. 와우 클라이언트 불필요.
--
-- 정렬된 배열 끝에 무조건 레코드(센티넬)를 하나 붙이고 도달 가능성을 물으면, 그 자리에서
-- 묻는 질문이 정확히 "앞의 것들이 조건 공간을 다 덮는가"가 된다. 참이면 아무것도 안 맞는 때가
-- 없고, 키를 게임에 돌려줄 일도 없다.
--
-- **한쪽으로만 틀려야 한다.** 거짓 부정(놓침)은 성능만 잃지만, 거짓 긍정은 놓아줘야 할 키를
-- 잡고 있는 것이라 동작이 틀린다. 아래 테스트 절반이 그 방향을 지킨다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local IsKeyAlwaysOurs = DebindPrivate.IsKeyAlwaysOurs;
    local BuildUnitStates = DebindPrivate.BuildUnitStates;

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

    --- 손으로 쓴 레코드는 `Misc.lua`의 파생을 안 거쳤으므로 여기서 돌린다. solver가 읽는 것은
    --- 그 파생 결과다.
    local function ask(bindings)
        for i = 1, #bindings do
            bindings[i].holdsKey = true;
            BuildUnitStates(bindings[i]);
        end
        return IsKeyAlwaysOurs(bindings);
    end

    local function spell(t)
        t.type = t.type or Constants.SPELL;
        t.value = t.value or 585;
        return t;
    end

    ---------------------------------------------------------------------------
    -- 참이어야 하는 것
    ---------------------------------------------------------------------------

    -- 옛 구문적 술어가 잡던 것: 무조건 액션이 하나 있다.
    test("무조건 액션 하나면 참", function()
        check(ask({
            spell({ name = "conditional", combat = true }),
            spell({ name = "fallback" }),
        }) == true, "무조건 폴백이 있는데 거짓이 나왔다");
    end);

    -- 옛 술어가 **못 잡던 것.** 무조건 액션이 하나도 없는데 축을 다 덮었다.
    test("한 축을 다 덮으면 참 (무조건 액션 없이)", function()
        check(ask({
            spell({ name = "inCombat", combat = true }),
            spell({ name = "atPeace", combat = false }),
        }) == true, "combat 축을 다 덮었는데 거짓이 나왔다");
    end);

    -- 덮고 난 뒤의 UNUSED는 도달할 수 없으므로 키를 돌려주지 않는다.
    test("덮인 뒤의 UNUSED는 참을 안 깨뜨린다", function()
        check(ask({
            spell({ name = "inCombat", combat = true }),
            spell({ name = "atPeace", combat = false }),
            { name = "dead code", type = Constants.UNUSED, holdsKey = true },
        }) == true, "도달 못 하는 UNUSED가 판정을 깨뜨렸다");
    end);

    ---------------------------------------------------------------------------
    -- 거짓이어야 하는 것 — 이쪽이 틀리면 동작이 틀린다
    ---------------------------------------------------------------------------

    test("조건부만 있으면 거짓", function()
        check(ask({
            spell({ name = "onlyInCombat", combat = true }),
        }) == false, "안 맞는 때가 있는데 참이 나왔다");
    end);

    test("축을 반만 덮으면 거짓", function()
        check(ask({
            spell({ name = "inCombat", combat = true }),
            spell({ name = "stealthed", stealth = true }),
        }) == false, "다른 축 둘로는 공간이 안 덮인다");
    end);

    -- 무조건 액션보다 **앞에** 있는 UNUSED는 도달한다. 그때 키는 게임으로 돌아간다.
    test("도달 가능한 UNUSED가 있으면 거짓", function()
        check(ask({
            { name = "release", type = Constants.UNUSED, combat = true, holdsKey = true },
            spell({ name = "fallback" }),
        }) == false, "도달 가능한 UNUSED인데 참이 나왔다");
    end);

    -- COMMAND는 `SetBinding`이라 클릭이 아니다. 배선이 고정이라고 말할 수 없다.
    test("도달 가능한 COMMAND가 있으면 거짓", function()
        check(ask({
            { name = "cmd", type = Constants.COMMAND, value = "TOGGLEWORLDMAP",
              combat = true, holdsKey = true },
            spell({ name = "fallback" }),
        }) == false, "도달 가능한 COMMAND인데 참이 나왔다");
    end);

    test("빈 목록은 거짓", function()
        check(IsKeyAlwaysOurs({}) == false, "빈 목록에 참이 나왔다");
    end);

    ---------------------------------------------------------------------------
    -- 상수 컬럼 잘라내기가 구멍을 못 보게 만들면 안 된다
    ---------------------------------------------------------------------------

    -- 모든 레코드가 `combat=true`면 그 컬럼은 상수라 잘려나간다. 잘리고 나면 combat=false
    -- 구멍이 안 보이고 판정이 "덮였다"로 뒤집힌다 -- 거짓 긍정이고, 놓아줘야 할 키를 잡는다.
    -- 센티넬이 배열에 같이 들어가 있으면 그 컬럼이 상수가 아니게 되어 구멍이 그대로 보인다.
    test("모든 레코드가 같은 조건이면 그 축의 구멍이 보여야 한다", function()
        check(ask({
            spell({ name = "a", combat = true, stealth = true }),
            spell({ name = "b", combat = true, stealth = false }),
        }) == false, "combat=false 구멍을 못 봤다 - 상수 컬럼이 잘려나갔다");
    end);

    return T;
end
