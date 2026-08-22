-- 액션 정체 비교 테스트. 와우 클라이언트 불필요.
--
-- 두 액션이 "완전히 같은가"를 재는 서명과, 그 위에 얹힌 두 입구를 고정한다.
-- 규칙은 `devdocs/building-export-import.md` 12절의 "중복은 액션 대 액션으로 본다".
--
--   * 서명은 **필드 + 키**다. 주소(레이어)는 안 들어간다 - 가져오기가 from 레이어와 to
--     레이어를 짝지어 대므로 부르는 쪽이 이미 안다.
--   * `seq`와 `arrivalID`는 빠진다. 앞엣것은 그룹 안 차례라 같은 키 위의 둘이 정의상
--     다르고, 뒤엣것은 arrival마다 달라서 같은 것을 다시 가져와도 새것이 된다.
--   * 키는 nil이든 실키든 값으로 센다.

return function(DebindPrivate)
    local ActionSignature = DebindPrivate.ActionSignature;
    local ActionsAreEqual = DebindPrivate.ActionsAreEqual;
    local MatchActionsAgainst = DebindPrivate.MatchActionsAgainst;
    local FindRepeatedActions = DebindPrivate.FindRepeatedActions;

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

    --- 비교에 쓰이는 필드를 다 든 액션. 테스트마다 여기서 한 칸만 바꿔 든다.
    local function action(overrides)
        local a = {
            type = "spell",
            value = 100,
            key = "CTRL-1",
            name = "Frostbolt",
            icon = 135846,
            unit = "target",
            priority = 2,
            keepInBindingContext = true,
            ignoreHoverUnit = false,
            conditions = { combat = true, forms = 3, units = { hover = 1 } },
            seq = 1,
        };
        for k, v in pairs(overrides or {}) do
            if (v == "\0nil") then
                a[k] = nil;
            else
                a[k] = v;
            end
        end
        return a;
    end

    ---------------------------------------------------------------------------
    -- 서명과 같음
    ---------------------------------------------------------------------------

    test("같은 내용이면 같다", function()
        check(ActionsAreEqual(action(), action()), "두 벌이 같아야 한다");
        check(ActionSignature(action()) == ActionSignature(action()), "서명이 같아야 한다");
    end);

    test("비교 대상 필드가 하나라도 다르면 다르다", function()
        local fields = {
            { type = "item" },
            { value = 101 },
            { name = "Fireball" },
            { icon = 1 },
            { unit = "focus" },
            { priority = 3 },
            { keepInBindingContext = false },
            { ignoreHoverUnit = true },
        };
        for i = 1, #fields do
            local name = next(fields[i]);
            check(not ActionsAreEqual(action(), action(fields[i])),
                name .. "만 달라도 달라야 한다");
        end
    end);

    test("값의 타입이 다르면 다르다", function()
        check(not ActionsAreEqual(action({ value = 1 }), action({ value = "1" })),
            "숫자 1과 문자열 '1'은 다른 값이다");
    end);

    ---------------------------------------------------------------------------
    -- 키
    ---------------------------------------------------------------------------

    test("키가 다르면 다르다", function()
        check(not ActionsAreEqual(action(), action({ key = "CTRL-2" })), "키가 정체에 든다");
    end);

    test("둘 다 키가 없으면 같다", function()
        check(ActionsAreEqual(action({ key = "\0nil" }), action({ key = "\0nil" })),
            "키 없음끼리는 같다");
    end);

    test("한쪽만 키가 없으면 다르다", function()
        check(not ActionsAreEqual(action(), action({ key = "\0nil" })),
            "키 없음과 키 있음은 다르다");
    end);

    ---------------------------------------------------------------------------
    -- 빠지는 필드 둘
    ---------------------------------------------------------------------------

    test("seq만 다르면 같다", function()
        check(ActionsAreEqual(action({ seq = 1 }), action({ seq = 7 })),
            "그룹 안 차례는 정체가 아니다");
    end);

    test("arrivalID만 다르면 같다", function()
        check(ActionsAreEqual(action({ arrivalID = 1 }), action({ arrivalID = 9 })),
            "arrival 번호는 정체가 아니다");
        check(ActionsAreEqual(action(), action({ arrivalID = 3 })),
            "배지가 붙은 것과 안 붙은 것도 액션으로는 같다");
    end);

    ---------------------------------------------------------------------------
    -- conditions
    ---------------------------------------------------------------------------

    test("조건 값이 다르면 다르다", function()
        check(not ActionsAreEqual(action(), action({ conditions = { combat = false, forms = 3, units = { hover = 1 } } })),
            "combat이 다르다");
        check(not ActionsAreEqual(action(), action({ conditions = { combat = true, forms = 4, units = { hover = 1 } } })),
            "forms가 다르다");
    end);

    test("조건이 하나 더 있거나 없으면 다르다", function()
        check(not ActionsAreEqual(action(), action({ conditions = { combat = true, forms = 3, units = { hover = 1 }, stealth = true } })),
            "하나 더 있으면 다르다");
        check(not ActionsAreEqual(action(), action({ conditions = { forms = 3, units = { hover = 1 } } })),
            "하나 빠지면 다르다");
    end);

    test("중첩 표의 내용이 다르면 다르다", function()
        check(not ActionsAreEqual(action(), action({ conditions = { combat = true, forms = 3, units = { hover = 2 } } })),
            "units의 값이 다르다");
        check(not ActionsAreEqual(action(), action({ conditions = { combat = true, forms = 3, units = { hover = 1, mouseover = 1 } } })),
            "units에 하나 더 있다");
        check(not ActionsAreEqual(action(), action({ conditions = { combat = true, forms = 3 } })),
            "units 자체가 없다");
    end);

    test("조건을 넣은 차례가 달라도 같다", function()
        local one = action({ conditions = {} });
        one.conditions.combat = true;
        one.conditions.forms = 3;
        one.conditions.units = {};
        one.conditions.units.hover = 1;
        one.conditions.units.mouseover = 2;

        local other = action({ conditions = {} });
        other.conditions.units = {};
        other.conditions.units.mouseover = 2;
        other.conditions.units.hover = 1;
        other.conditions.forms = 3;
        other.conditions.combat = true;

        check(ActionsAreEqual(one, other), "표를 채운 차례는 정체가 아니다");
    end);

    test("빈 조건 표는 조건 없음과 같다", function()
        check(ActionsAreEqual(action({ conditions = {} }), action({ conditions = "\0nil" })),
            "남는 조건이 없으면 표를 안 만드는 자리가 있다 (`Misc.lua`)");
        check(ActionsAreEqual(action({ conditions = { units = {} } }), action({ conditions = "\0nil" })),
            "빈 중첩 표도 마찬가지다");
    end);

    ---------------------------------------------------------------------------
    -- 배열 둘 대보기
    ---------------------------------------------------------------------------

    test("이미 있는 것만 골라낸다", function()
        local mine = { action(), action({ value = 200, key = "CTRL-2" }) };
        local incoming = { action(), action({ value = 300, key = "CTRL-3" }) };

        local found = MatchActionsAgainst(incoming, mine);
        check(found[incoming[1]] == mine[1], "첫째는 이미 있고 내 쪽 것을 가리켜야 한다");
        check(found[incoming[2]] == nil, "둘째는 새것이다");
    end);

    test("빈 쪽이 있어도 선다", function()
        check(next(MatchActionsAgainst({}, { action() })) == nil, "댈 것이 없으면 빈 표");
        check(next(MatchActionsAgainst({ action() }, {})) == nil, "가진 것이 없으면 빈 표");
    end);

    test("키가 다르면 같은 액션이라도 안 걸린다", function()
        local mine = { action() };
        local incoming = { action({ key = "CTRL-9" }) };
        check(next(MatchActionsAgainst(incoming, mine)) == nil, "키가 정체에 들어 있다");
    end);

    ---------------------------------------------------------------------------
    -- 한 배열 안의 중복
    ---------------------------------------------------------------------------

    test("한 배열 안에서 뒤엣것을 집는다", function()
        local first = action();
        local repeated = action({ arrivalID = 5 });
        local other = action({ value = 999, key = "CTRL-8" });

        local found = FindRepeatedActions({ first, repeated, other });
        check(found[first] == nil, "먼저 온 것은 남는다");
        check(found[repeated] == first, "뒤엣것이 집히고 먼저 온 것을 가리킨다");
        check(found[other] == nil, "안 겹치는 것은 안 집힌다");
    end);

    test("셋이 겹치면 둘이 집힌다", function()
        local list = { action(), action({ seq = 2 }), action({ seq = 3 }) };
        local found = FindRepeatedActions(list);
        local n = 0;
        for _ in pairs(found) do n = n + 1; end
        check(n == 2, "셋 중 둘이 집혀야 하는데 " .. n .. "개다");
        check(found[list[1]] == nil, "첫째는 남는다");
    end);

    return T;
end
