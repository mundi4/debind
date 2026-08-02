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
    -- 3. ComputeIndexMove
    --
    -- 순서 UI의 ↑↓는 **index만** 만진다. priority/hover/조건부/레이어는 각자 뜻이 있는
    -- 속성이고 각자의 자리에서 바뀌므로, 그 단계에서 갈렸으면 버튼은 손을 뗀다.
    -- 여기서 고정하는 건 두 가지다: 어느 단계에서 막혔는지, 그리고 움직였을 때 정확히
    -- 한 칸만 움직이고 ↑ 다음 ↓면 원래대로 돌아오는지.
    ---------------------------------------------------------------------------

    local ComputeIndexMove = DebouncePrivate.ComputeIndexMove;
    local UP, DOWN = -1, 1;

    --- rows를 실제 발동 순서로 정렬해 돌려준다. 레코드는 원본 그대로(같은 테이블).
    local function sorted(rows)
        local arr = {};
        for i = 1, #rows do
            arr[i] = rows[i];
        end
        sort(arr, CompareActionOrder);
        return arr;
    end

    local function indexOf(arr, rec)
        for i = 1, #arr do
            if (arr[i] == rec) then
                return i;
            end
        end
    end

    --- 레이어 배열을 흉내낸다. 레코드를 index 순으로 늘어놓은 것이 곧 배열이다.
    local function makeLayer(...)
        local layer = { ... };
        for i, r in ipairs(layer) do
            r.index = i;
        end
        return layer;
    end

    --- UI가 실제로 하는 일: 배열에서 빼서 insertIndex에 다시 넣고 index를 재부여한다.
    local function applyMove(layer, target, insertIndex)
        tremove(layer, indexOf(layer, target));
        tinsert(layer, insertIndex, target);
        for i, r in ipairs(layer) do
            r.index = i;
        end
    end

    --- 배열을 발동 순서로 정렬했을 때의 자리들. 비교용 문자열.
    local function orderOf(layer)
        local arr = sorted(layer);
        local names = {};
        for i = 1, #arr do
            names[i] = arr[i].name;
        end
        return table.concat(names, ",");
    end

    test("index 이동 - 같은 조건이면 이웃과 한 칸 맞바꾼다", function()
        local a = rec({ name = "a" });
        local b = rec({ name = "b" });
        local layer = makeLayer(a, b);
        check(orderOf(layer) == "a,b", "준비: a,b");

        local rows = sorted(layer);
        local insertIndex, reason = ComputeIndexMove(rows, 2, UP);
        check(reason == nil, "막히면 안 됨: " .. tostring(reason));
        check(insertIndex == 1, "이웃의 배열 자리(1)여야 함, 받은 값: " .. tostring(insertIndex));

        applyMove(layer, b, insertIndex);
        check(orderOf(layer) == "b,a", "b가 앞으로 와야 함, 실제: " .. orderOf(layer));
    end);

    test("index 이동 - ↑ 다음 ↓면 원래대로 돌아온다", function()
        -- 밴드를 태우던 옛 방식이 못 하던 것이 정확히 이거다. index는 뜻이 없으므로
        -- 왕복이 완전히 대칭이어야 한다.
        local a = rec({ name = "a" });
        local b = rec({ name = "b" });
        local c = rec({ name = "c" });
        local layer = makeLayer(a, b, c);
        check(orderOf(layer) == "a,b,c", "준비: a,b,c");

        applyMove(layer, c, (ComputeIndexMove(sorted(layer), 3, UP)));
        check(orderOf(layer) == "a,c,b", "↑ 후: a,c,b, 실제: " .. orderOf(layer));

        local rows = sorted(layer);
        applyMove(layer, c, (ComputeIndexMove(rows, indexOf(rows, c), DOWN)));
        check(orderOf(layer) == "a,b,c", "↓ 후 원상복귀여야 함, 실제: " .. orderOf(layer));
    end);

    test("index 이동 - 여러 번 왕복해도 priority가 하나도 안 생긴다", function()
        local a = rec({ name = "a" });
        local b = rec({ name = "b" });
        local layer = makeLayer(a, b);

        for _ = 1, 10 do
            local rows = sorted(layer);
            local target = rows[2];
            applyMove(layer, target, (ComputeIndexMove(rows, 2, UP)));
        end

        check(a.priority == nil and b.priority == nil,
            "밴드가 생기면 안 됨: a=" .. tostring(a.priority) .. " b=" .. tostring(b.priority));
    end);

    test("index 이동 - 세 개짜리에서 딱 한 칸만 움직인다", function()
        local a = rec({ name = "a" });
        local b = rec({ name = "b" });
        local c = rec({ name = "c" });
        local layer = makeLayer(a, b, c);

        applyMove(layer, c, (ComputeIndexMove(sorted(layer), 3, UP)));
        check(orderOf(layer) == "a,c,b", "a는 안 넘어야 함, 실제: " .. orderOf(layer));
    end);

    test("index 이동 - 끝에서는 움직일 데가 없다", function()
        local rows = sorted(makeLayer(rec({ name = "a" }), rec({ name = "b" })));

        local moved, reason = ComputeIndexMove(rows, 1, UP);
        check(moved == nil and reason == "ALREADY_FIRST", "ALREADY_FIRST여야 함");

        moved, reason = ComputeIndexMove(rows, 2, DOWN);
        check(moved == nil and reason == "ALREADY_LAST", "ALREADY_LAST여야 함");
    end);

    ---------------------------------------------------------------------------
    -- 막히는 네 축. 각 축은 뜻이 있는 속성이므로 버튼이 아니라 그 속성의 편집기에서
    -- 바뀌어야 한다. 여기서는 "어느 축에서 갈렸는지"를 정확히 집어내는지만 본다.
    ---------------------------------------------------------------------------

    local function expectBlocked(target, neighbor, axis)
        -- neighbor가 먼저, target이 나중이 되도록 놓고 target을 위로 올려본다.
        local layer = makeLayer(neighbor, target);
        local rows = sorted(layer);
        check(rows[2] == target, axis .. ": 준비 - target이 두 번째여야 함");

        local moved, reason = ComputeIndexMove(rows, 2, UP);
        check(moved == nil, axis .. ": 움직이면 안 됨");
        check(reason == axis, axis .. ": 이유가 " .. axis .. "여야 함, 받은 값: " .. tostring(reason));
    end

    test("막힘 - 밴드가 다르면 PRIORITY", function()
        expectBlocked(rec({ name = "t" }), rec({ name = "n", priority = 2 }), "PRIORITY");
    end);

    test("막힘 - hover 여부가 다르면 HOVER", function()
        expectBlocked(rec({ name = "t" }), rec({ name = "n", hover = true }), "HOVER");
    end);

    test("막힘 - hover=false도 '있는' 것이라 HOVER로 갈린다", function()
        expectBlocked(rec({ name = "t" }), rec({ name = "n", hover = false }), "HOVER");
    end);

    test("막힘 - 조건부 여부가 다르면 CONDITIONAL", function()
        expectBlocked(rec({ name = "t" }), rec({ name = "n", isConditional = true }), "CONDITIONAL");
    end);

    test("막힘 - 레이어가 다르면 LAYER", function()
        expectBlocked(rec({ name = "t", layerRank = 2 }), rec({ name = "n", layerRank = 1 }), "LAYER");
    end);

    test("막힘 - 앞선 단계가 우선한다 (밴드와 레이어가 둘 다 다르면 PRIORITY)", function()
        expectBlocked(rec({ name = "t", layerRank = 2 }), rec({ name = "n", priority = 2, layerRank = 1 }), "PRIORITY");
    end);

    test("GetDecidingOrderAxis - 전부 같으면 nil", function()
        local axis = DebouncePrivate.GetDecidingOrderAxis(rec({ index = 1 }), rec({ index = 2 }));
        check(axis == nil, "nil이어야 함, 받은 값: " .. tostring(axis));
    end);

    test("PriorityToStored - 기본값은 저장하지 않는다", function()
        check(DebouncePrivate.PriorityToStored(3) == nil, "3은 nil로");
        check(DebouncePrivate.PriorityToStored(nil) == nil, "nil은 nil로");
        check(DebouncePrivate.PriorityToStored(1) == 1, "1은 그대로");
        check(DebouncePrivate.PriorityToStored(5) == 5, "5는 그대로");
    end);

    ---------------------------------------------------------------------------
    -- 4. CompareKeys
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
