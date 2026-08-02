-- 순서 비교 함수 테스트. 와우 클라이언트 불필요.
--
-- 두 층으로 되어 있음:
--   1. 단계별 테스트 - CompareActionOrder의 5단계(priority > hover > isConditional >
--      layerRank > index)와 CompareKeys의 규칙을 하나씩 고정한다
--   2. 무차별 대조 테스트 - (layerRank, index)로 쪼개기 전의 통짜 ordinal 비교자를
--      그대로 옮겨와서, 작은 조건 공간의 모든 쌍에 대해 두 비교자가 같은 답을 내는지 본다.
--      "정렬 결과가 리팩터 전과 완전히 동일하다"를 직접 확인하는 게 이쪽이다.

return function(DebouncePrivate)
    local CompareActionOrder = DebouncePrivate.CompareActionOrder;
    local CompareKeys = DebouncePrivate.CompareKeys;

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

    ---------------------------------------------------------------------------
    -- 1. CompareActionOrder - 단계별
    ---------------------------------------------------------------------------

    --- layerRank/index 기본값을 채운 레코드. hover는 nil/false/true가 전부 다른 뜻이라
    --- 넘어온 값을 그대로 둔다.
    local function rec(t)
        t.layerRank = t.layerRank or 1;
        t.index = t.index or 1;
        return t;
    end

    --- a가 b보다 먼저이고, 뒤집으면 반대여야 한다(순서가 실제로 갈렸다는 뜻).
    local function expectBefore(a, b, msg)
        check(CompareActionOrder(a, b) == true, (msg or "") .. ": a가 b보다 먼저여야 함");
        check(CompareActionOrder(b, a) == false, (msg or "") .. ": b는 a보다 먼저면 안 됨");
    end

    --- 양방향 모두 false = 이 단계에서 순서가 안 갈림.
    local function expectTie(a, b, msg)
        check(CompareActionOrder(a, b) == false and CompareActionOrder(b, a) == false,
            (msg or "") .. ": 순서가 갈리면 안 됨");
    end

    test("1단계 priority - 작은 값이 먼저", function()
        expectBefore(rec({ priority = 1 }), rec({ priority = 5 }), "priority");
    end);

    test("1단계 priority - nil은 기본값 3", function()
        expectBefore(rec({ priority = 2 }), rec({}), "nil은 3");
        expectBefore(rec({}), rec({ priority = 4 }), "nil은 3");
        expectTie(rec({ priority = 3 }), rec({}), "3과 nil은 동률");
    end);

    test("2단계 hover - hover가 있는 쪽이 먼저", function()
        expectBefore(rec({ hover = true }), rec({}), "hover");
    end);

    test("2단계 hover - false도 '있는' 것이다", function()
        -- action.hover = false는 "hover 아님"을 명시한 조건이라 nil과 다르다.
        -- 불리언으로 접어 넘기면 여기가 깨진다.
        expectBefore(rec({ hover = false }), rec({}), "hover=false");
        expectTie(rec({ hover = false }), rec({ hover = true }), "false와 true는 동률");
    end);

    test("2단계 hover - priority가 먼저 갈리면 hover는 안 본다", function()
        expectBefore(rec({ priority = 1 }), rec({ priority = 2, hover = true }), "priority 우선");
    end);

    test("3단계 isConditional - 조건부가 먼저", function()
        expectBefore(rec({ isConditional = true }), rec({ isConditional = false }), "isConditional");
        expectBefore(rec({ isConditional = true }), rec({}), "nil은 비조건부");
        expectTie(rec({ isConditional = false }), rec({}), "false와 nil은 동률");
    end);

    test("3단계 isConditional - hover가 먼저 갈리면 안 본다", function()
        expectBefore(rec({ hover = true }), rec({ isConditional = true }), "hover 우선");
    end);

    test("4단계 layerRank - 작은 값(구체적인 레이어)이 먼저", function()
        expectBefore(rec({ layerRank = 1, index = 99 }), rec({ layerRank = 2, index = 1 }), "layerRank");
    end);

    test("4단계 layerRank - isConditional이 먼저 갈리면 안 본다", function()
        expectBefore(rec({ layerRank = 5, isConditional = true }), rec({ layerRank = 1 }), "isConditional 우선");
    end);

    test("5단계 index - 같은 레이어 안에서는 배열 순서", function()
        expectBefore(rec({ index = 1 }), rec({ index = 2 }), "index");
    end);

    test("전부 같으면 동률", function()
        expectTie(rec({ priority = 2, hover = true, isConditional = true, layerRank = 3, index = 4 }),
            rec({ priority = 2, hover = true, isConditional = true, layerRank = 3, index = 4 }), "동일 레코드");
    end);

    test("sort 통합 - 5단계가 순서대로 적용된다", function()
        local arr = {
            rec({ index = 2 }),
            rec({ index = 1 }),
            rec({ isConditional = true, index = 3 }),
            rec({ hover = true, index = 4 }),
            rec({ priority = 1, index = 5 }),
            rec({ layerRank = 0, index = 6 }),
        };
        sort(arr, CompareActionOrder);

        local expected = { 5, 4, 3, 6, 1, 2 };
        for i = 1, #expected do
            check(arr[i].index == expected[i],
                ("%d번째가 index=%d, 기대값 %d"):format(i, arr[i].index, expected[i]));
        end
    end);

    ---------------------------------------------------------------------------
    -- 2. CompareActionOrder - 리팩터 전 비교자와 무차별 대조
    ---------------------------------------------------------------------------

    -- Debounce.lua의 BindingSortComparison을 (layerRank, index)로 쪼개기 전 모습 그대로.
    -- ordinal은 활성 레이어를 훑으며 매기던 통짜 일련번호였다.
    local function LegacyCompare(lhs, rhs)
        if ((lhs.priority or 3) ~= (rhs.priority or 3)) then
            return (lhs.priority or 3) < (rhs.priority or 3);
        end

        if (lhs.hover ~= nil and rhs.hover == nil) then
            return true;
        elseif (lhs.hover == nil and rhs.hover ~= nil) then
            return false;
        end

        if (lhs.isConditional and not rhs.isConditional) then
            return true;
        elseif (not lhs.isConditional and rhs.isConditional) then
            return false;
        end

        return lhs.ordinal < rhs.ordinal;
    end

    test("무차별 대조 - 모든 쌍에서 옛 비교자와 답이 같다", function()
        local PRIORITIES = { 1, 3, 5, "nil" };
        local HOVERS = { "nil", false, true };
        local CONDITIONALS = { "nil", false, true };
        local INDICES_PER_LAYER = 3;

        local records = {};
        for _, p in ipairs(PRIORITIES) do
            for _, h in ipairs(HOVERS) do
                for _, c in ipairs(CONDITIONALS) do
                    for layerRank = 1, 2 do
                        for index = 1, INDICES_PER_LAYER do
                            records[#records + 1] = {
                                priority = p ~= "nil" and p or nil,
                                hover = h ~= "nil" and h or nil,
                                isConditional = c ~= "nil" and c or nil,
                                layerRank = layerRank,
                                index = index,
                                -- 레이어를 순서대로 훑으면 나오는 통짜 일련번호.
                                ordinal = (layerRank - 1) * INDICES_PER_LAYER + index,
                            };
                        end
                    end
                end
            end
        end

        for i = 1, #records do
            for j = 1, #records do
                local a, b = records[i], records[j];
                local new = CompareActionOrder(a, b) and true or false;
                local old = LegacyCompare(a, b) and true or false;
                check(new == old, ("불일치: [%d] vs [%d] - 새 비교자 %s, 옛 비교자 %s")
                    :format(i, j, tostring(new), tostring(old)));
            end
        end
    end);

    ---------------------------------------------------------------------------
    -- 3. CompareKeys
    ---------------------------------------------------------------------------

    local function expectKeyBefore(a, b)
        check(CompareKeys(a, b) == true, ("'%s'이(가) '%s'보다 먼저여야 함"):format(a, b));
        check((CompareKeys(b, a) or false) == false, ("'%s'이(가) '%s'보다 먼저면 안 됨"):format(b, a));
    end

    test("실제 키를 먼저 본다 - SORT_KEYS 순서", function()
        expectKeyBefore("BUTTON1", "F1");
        expectKeyBefore("F1", "F2");
        expectKeyBefore("SHIFT-BUTTON1", "F1");
    end);

    test("SORT_KEYS에 없는 키는 있는 키보다 뒤", function()
        expectKeyBefore("F12", "A");
        expectKeyBefore("NUMPADPLUS", "`");
    end);

    test("둘 다 SORT_KEYS에 없으면 사전순", function()
        expectKeyBefore("A", "B");
    end);

    test("같은 키면 수식키가 적은 쪽이 먼저", function()
        expectKeyBefore("F1", "SHIFT-F1");
        expectKeyBefore("SHIFT-F1", "ALT-SHIFT-F1");
    end);

    test("수식키 개수가 같으면 앞에서부터 SORT_KEYS 순서로 비교", function()
        expectKeyBefore("ALT-F1", "CTRL-F1");
        expectKeyBefore("CTRL-F1", "SHIFT-F1");
        expectKeyBefore("ALT-SHIFT-F1", "CTRL-SHIFT-F1");
    end);

    test("같은 키는 동률", function()
        check((CompareKeys("SHIFT-F1", "SHIFT-F1") or false) == false, "같은 키가 순서를 가름");
    end);

    test("파싱 - 마지막 조각이 실제 키다 (strsplit 동작 보존)", function()
        -- "-"(마이너스) 자체가 키인 경우. strsplit("-", "SHIFT--")는 "SHIFT", "", ""를 돌려주고
        -- 마지막이 lastKey가 되므로 lastKey는 ""이고 수식키는 두 개다. 그 quirk를 그대로 둔다.
        check((CompareKeys("SHIFT--", "SHIFT--") or false) == false, "같은 키가 순서를 가름");
        -- 수식키가 둘("SHIFT", "")이므로 하나짜리보다 뒤로 간다.
        expectKeyBefore("SHIFT-", "SHIFT--");
    end);

    test("sort 통합", function()
        local arr = { "F2", "A", "SHIFT-F1", "F1", "ALT-CTRL-F1", "BUTTON1", "CTRL-F1" };
        sort(arr, CompareKeys);

        local expected = { "BUTTON1", "F1", "CTRL-F1", "SHIFT-F1", "ALT-CTRL-F1", "F2", "A" };
        for i = 1, #expected do
            check(arr[i] == expected[i],
                ("%d번째가 '%s', 기대값 '%s'"):format(i, tostring(arr[i]), expected[i]));
        end
    end);

    return T;
end
