-- 도달불가 바인딩 solver 테스트. 와우 클라이언트 불필요.
--
-- 두 층으로 되어 있음:
--   1. 이름 붙은 회귀 테스트 - 각 버그가 무엇이었는지 문서화
--   2. 무차별 대조 테스트 - 작은 조건 공간의 모든 점을 열거해서 정답을 직접
--      계산하고 solver 결과와 비교. §1-3(축 접기), §1-4(배열 압축) 같은
--      부류의 버그는 이쪽이 잡는다.

return function(DebouncePrivate)
    local Constants = DebouncePrivate.Constants;
    local CheckUnreachableBindings = DebouncePrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebouncePrivate.ClearUnreachableBindingCache;

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

    --- 바인딩 목록을 solver에 넣고 살아남은 것들의 name 집합을 돌려준다.
    local function survivors(bindings)
        ClearUnreachableBindingCache();
        CheckUnreachableBindings(bindings);
        local names = {};
        for i = 1, #bindings do
            names[bindings[i].name] = true;
        end
        return names;
    end

    local function expectSurvives(bindings, name)
        local s = survivors(bindings);
        check(s[name], "'" .. name .. "'이(가) 도달불가로 잘못 제거됨");
    end

    local function expectRemoved(bindings, name)
        local s = survivors(bindings);
        check(not s[name], "'" .. name .. "'이(가) 제거됐어야 하는데 남음");
    end

    ---------------------------------------------------------------------------
    -- 1. 이름 붙은 회귀 테스트
    ---------------------------------------------------------------------------

    -- §1-2: known descriptor가 조건 없을 때 0(공집합)을 돌려줘서 마지막 컬럼에서
    -- 항상 조기 종료 -> removeConditions가 아무것도 못 뺌 -> solver 전체가 죽음.
    test("조건 없는 중복 바인딩 - 아래쪽이 제거됨", function()
        expectRemoved({
            { name = "a" },
            { name = "b" },
        }, "b");
    end);

    test("무조건 바인딩이 조건부 바인딩을 덮음", function()
        expectRemoved({
            { name = "always" },
            { name = "incombat", combat = true },
        }, "incombat");
    end);

    test("조건부 바인딩은 무조건 바인딩을 못 덮음", function()
        expectSurvives({
            { name = "incombat", combat = true },
            { name = "always" },
        }, "always");
    end);

    test("둘로 쪼갠 조건이 합쳐서 전체를 덮음", function()
        expectRemoved({
            { name = "incombat",   combat = true },
            { name = "outcombat",  combat = false },
            { name = "always" },
        }, "always");
    end);

    -- §1-3: 커스텀 상태 5개를 한 워드에 니블로 접어놨었음.
    -- A=$state1 on, B=$state2 on 은 서로 독립인데 패킹된 band가 겹친다고 봄.
    test("독립된 커스텀 상태는 서로를 못 덮음", function()
        expectSurvives({
            { name = "s1", ["$state1"] = true },
            { name = "s2", ["$state2"] = true },
        }, "s2");
    end);

    test("커스텀 상태 - 더 좁은 조건은 덮임", function()
        expectRemoved({
            { name = "s1",    ["$state1"] = true },
            { name = "s1s2",  ["$state1"] = true, ["$state2"] = true },
        }, "s1s2");
    end);

    -- §1-3: basicunits/specialunits도 같은 문제. 게다가 checkedUnits에 언급되지
    -- 않은 유닛의 니블이 0이 되어 상자가 퇴화했음.
    test("서로 다른 유닛 조건은 독립", function()
        expectSurvives({
            { name = "t", checkedUnits = { target = true } },
            { name = "f", checkedUnits = { focus = true } },
        }, "f");
    end);

    test("같은 유닛의 더 좁은 조건은 덮임", function()
        expectRemoved({
            { name = "exists", checkedUnits = { target = true } },
            { name = "help",   checkedUnits = { target = "help" } },
        }, "help");
    end);

    test("우호 조건은 존재 조건을 못 덮음", function()
        expectSurvives({
            { name = "help",   checkedUnits = { target = "help" } },
            { name = "exists", checkedUnits = { target = true } },
        }, "exists");
    end);

    test("유닛 조건 두 개를 합치면 하나를 덮음", function()
        expectRemoved({
            { name = "t",   checkedUnits = { target = true } },
            { name = "tf",  checkedUnits = { target = true, focus = true } },
        }, "tf");
    end);

    -- §1-2 연혁: 5e0565f는 모든 known을 flags=1로 묶어서 서로 다른 주문끼리
    -- 같은 조건으로 오판했음 (false positive).
    test("서로 다른 주문의 known 조건은 독립", function()
        expectSurvives({
            { name = "spellA", type = Constants.SPELL, value = 100, known = true },
            { name = "spellB", type = Constants.SPELL, value = 200, known = true },
        }, "spellB");
    end);

    test("같은 주문의 known 조건은 중복", function()
        expectRemoved({
            { name = "first",  type = Constants.SPELL, value = 100, known = true },
            { name = "second", type = Constants.SPELL, value = 100, known = true },
        }, "second");
    end);

    test("known 조건은 무조건 바인딩을 못 덮음", function()
        expectSurvives({
            { name = "known",  type = Constants.SPELL, value = 100, known = true },
            { name = "always", type = Constants.SPELL, value = 100 },
        }, "always");
    end);

    -- §1-5: _nextSpellFlags가 lshift로 증가해서 32개 넘으면 0으로 오버플로했음.
    -- 이제 주문마다 컬럼 하나이므로 개수 제한이 없다.
    test("known 조건 주문 40개 - 오버플로 없음", function()
        local bindings = {};
        for i = 1, 40 do
            bindings[i] = { name = "s" .. i, type = Constants.SPELL, value = 1000 + i, known = true };
        end
        local s = survivors(bindings);
        for i = 1, 40 do
            check(s["s" .. i], "s" .. i .. "이(가) 잘못 제거됨");
        end
    end);

    -- 모델링할 수 없는 조건이 있으면 그 바인딩은 판정에서 빠져야 함.
    -- (조건을 무시하면 실제보다 넓어 보여서 남을 잘못 덮는다)
    test("해석 불가능한 @ 조건은 판정에서 제외", function()
        local s = survivors({
            { name = "at",     checkedUnits = { ["@"] = true } },
            { name = "always" },
        });
        check(s["at"] and s["always"], "opaque 바인딩이 관여한 판정이 일어남");
    end);

    test("바인딩이 하나뿐이면 아무것도 안 함", function()
        expectSurvives({ { name = "only" } }, "only");
    end);

    ---------------------------------------------------------------------------
    -- 2. 무차별 대조
    ---------------------------------------------------------------------------

    -- 열거 가능한 작은 조건 공간. 아래 축들만 쓰는 바인딩을 만든다.
    local POINTS = {};
    do
        local TARGET_VALUES = { false, "help", "harm", true };
        for _, combat in ipairs({ true, false }) do
            for _, stealth in ipairs({ true, false }) do
                for _, pet in ipairs({ true, false }) do
                    for _, s1 in ipairs({ true, false }) do
                        for _, s2 in ipairs({ true, false }) do
                            for _, target in ipairs(TARGET_VALUES) do
                                for _, k100 in ipairs({ true, false }) do
                                    for _, k200 in ipairs({ true, false }) do
                                        POINTS[#POINTS + 1] = {
                                            combat = combat, stealth = stealth, pet = pet,
                                            s1 = s1, s2 = s2, target = target,
                                            k100 = k100, k200 = k200,
                                        };
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local function matchesPoint(b, p)
        if (b.combat ~= nil and b.combat ~= p.combat) then return false; end
        if (b.stealth ~= nil and b.stealth ~= p.stealth) then return false; end
        if (b.pet ~= nil and b.pet ~= p.pet) then return false; end
        if (b["$state1"] ~= nil and (b["$state1"] and true or false) ~= p.s1) then return false; end
        if (b["$state2"] ~= nil and (b["$state2"] and true or false) ~= p.s2) then return false; end

        local cond = b.checkedUnits and b.checkedUnits.target;
        if (cond ~= nil) then
            if (cond == true) then
                if (p.target == false) then return false; end
            elseif (cond == "help") then
                if (p.target ~= "help") then return false; end
            elseif (cond == "harm") then
                if (p.target ~= "harm") then return false; end
            else
                if (p.target ~= false) then return false; end
            end
        end

        if (b.known ~= nil) then
            local isKnown;
            if (b.value == 100) then
                isKnown = p.k100;
            else
                isKnown = p.k200;
            end
            if ((b.known and true or false) ~= isKnown) then return false; end
        end

        return true;
    end

    --- 정답: i번 바인딩이 발동할 수 있는 점이 하나라도 있는가.
    local function referenceSurvivors(bindings)
        local names = {};
        for i = 1, #bindings do
            for _, p in ipairs(POINTS) do
                if (matchesPoint(bindings[i], p)) then
                    local covered = false;
                    for j = 1, i - 1 do
                        if (matchesPoint(bindings[j], p)) then
                            covered = true;
                            break;
                        end
                    end
                    if (not covered) then
                        names[bindings[i].name] = true;
                        break;
                    end
                end
            end
        end
        -- 첫 바인딩은 solver가 절대 검사하지 않으므로 정답도 항상 생존 처리
        names[bindings[1].name] = true;
        return names;
    end

    local function describe(b)
        local parts = {};
        for _, key in ipairs({ "combat", "stealth", "pet", "$state1", "$state2" }) do
            if (b[key] ~= nil) then
                parts[#parts + 1] = key .. "=" .. tostring(b[key]);
            end
        end
        if (b.checkedUnits and b.checkedUnits.target ~= nil) then
            parts[#parts + 1] = "target=" .. tostring(b.checkedUnits.target);
        end
        if (b.known ~= nil) then
            parts[#parts + 1] = "known(" .. tostring(b.value) .. ")=" .. tostring(b.known);
        end
        if (#parts == 0) then
            return b.name .. "{}";
        end
        return b.name .. "{" .. table.concat(parts, ",") .. "}";
    end

    local function compareAgainstReference(bindings, label)
        local expected = referenceSurvivors(bindings);
        local snapshot = {};
        for i = 1, #bindings do
            snapshot[i] = describe(bindings[i]);
        end

        local actual = survivors(bindings);

        for i = 1, #snapshot do
            local name = snapshot[i]:match("^[^{]+");
            local shouldSurvive = expected[name] and true or false;
            local didSurvive = actual[name] and true or false;
            if (shouldSurvive ~= didSurvive) then
                local verdict = shouldSurvive and "생존해야 하는데 제거됨" or "제거돼야 하는데 생존";
                error(label .. " | " .. table.concat(snapshot, "  ") .. " | " .. name .. ": " .. verdict, 0);
            end
        end
    end

    -- MINSTD. 5.1/5.3 어디서든 같은 수열이 나오도록 직접 구현.
    local rngState = 42;
    local function nextRandom()
        rngState = (rngState * 16807) % 2147483647;
        return rngState / 2147483647;
    end
    local function pick(list)
        return list[math.floor(nextRandom() * #list) + 1];
    end

    local TRI = { "nil", true, false };
    local TARGET_CONDS = { "nil", true, false, "help", "harm" };
    local KNOWN_SPELLS = { 100, 200 };

    local function randomBinding(name)
        local b = { name = name, type = Constants.SPELL, value = pick(KNOWN_SPELLS) };
        for _, key in ipairs({ "combat", "stealth", "pet", "$state1", "$state2" }) do
            local v = pick(TRI);
            if (v ~= "nil") then b[key] = v; end
        end
        local target = pick(TARGET_CONDS);
        if (target ~= "nil") then
            b.checkedUnits = { target = target };
        end
        local known = pick(TRI);
        if (known ~= "nil") then b.known = known; end
        return b;
    end

    test("무작위 바인딩 집합 2000개 - 무차별 대조와 일치", function()
        for case = 1, 2000 do
            local count = math.floor(nextRandom() * 5) + 2;
            local bindings = {};
            for i = 1, count do
                bindings[i] = randomBinding("b" .. i);
            end
            compareAgainstReference(bindings, "case " .. case);
        end
    end);

    -- §1-4를 정면으로 겨냥: 잔여 상자가 여러 개로 쪼개진 상태에서 중간 행이
    -- 제거될 때, 옛 코드는 뒤쪽 행을 덮어써서 잔여 집합을 너무 작게 만들었다.
    -- (잔여가 작아짐 = 멀쩡한 바인딩을 도달불가로 오판 = 조용한 삭제)
    test("3축 격자 - 7칸만 덮으면 반드시 생존", function()
        local cells = {};
        for _, combat in ipairs({ true, false }) do
            for _, stealth in ipairs({ true, false }) do
                for _, pet in ipairs({ true, false }) do
                    cells[#cells + 1] = { combat = combat, stealth = stealth, pet = pet };
                end
            end
        end

        for omit = 1, 8 do
            for trial = 1, 30 do
                local covers = {};
                for i = 1, 8 do
                    if (i ~= omit) then
                        covers[#covers + 1] = {
                            name = "c" .. i,
                            combat = cells[i].combat,
                            stealth = cells[i].stealth,
                            pet = cells[i].pet,
                        };
                    end
                end
                -- 순서를 섞는다 (Fisher-Yates)
                for i = #covers, 2, -1 do
                    local j = math.floor(nextRandom() * i) + 1;
                    covers[i], covers[j] = covers[j], covers[i];
                end
                covers[#covers + 1] = { name = "target" };
                local s = survivors(covers);
                check(s["target"],
                    ("7칸만 덮였는데 target이 제거됨 (omit=%d, trial=%d)"):format(omit, trial));
            end
        end
    end);

    -- §1-4의 구체적 증거. §1-2만 고친 구버전에서 fuzz로 찾은 실제 false positive.
    -- (combat=false, stealth=false, pet=false) 칸이 아무에게도 안 덮이는데도
    -- 배열 압축 누락 때문에 잔여 집합이 비어버려 b7이 조용히 삭제됐다.
    test("§1-4 회귀 - 안 덮인 칸이 남아있으면 삭제되면 안 됨", function()
        expectSurvives({
            { name = "b1", combat = false, stealth = true },
            { name = "b2", combat = true,  stealth = true,  pet = false },
            { name = "b3", combat = true },
            { name = "b4", combat = false, stealth = false, pet = true },
            { name = "b5", combat = true,  stealth = true,  pet = false },
            { name = "b6", combat = true,  pet = false },
            { name = "b7", pet = false },
        }, "b7");
    end);

    test("3축 격자 - 8칸 전부 덮으면 반드시 제거", function()
        local covers = {};
        for _, combat in ipairs({ true, false }) do
            for _, stealth in ipairs({ true, false }) do
                for _, pet in ipairs({ true, false }) do
                    covers[#covers + 1] = {
                        name = "c" .. #covers,
                        combat = combat, stealth = stealth, pet = pet,
                    };
                end
            end
        end
        covers[#covers + 1] = { name = "target" };
        expectRemoved(covers, "target");
    end);

    ---------------------------------------------------------------------------
    -- 3. 잔여 상자 폭발 방지
    ---------------------------------------------------------------------------

    -- 조각을 앞쪽 교집합으로 누르지 않으면(= 겹치는 합집합으로 만들면) 같은 영역이
    -- 중복 표현되면서 잔여 집합에 상한이 사라진다. 아래 입력에서 상자가 1,500개를
    -- 넘겼었고, 조건이 더 겹치면 OOM까지 간다. BuildKeyMap은 바인딩을 편집할 때마다
    -- 불리므로 게임이 멈춘다.
    --
    -- 서로소 분해에서는 잔여 상자가 축들이 만드는 격자의 칸 수를 못 넘는다.
    local Stats = DebouncePrivate.SolverStats;

    local function adversarialSet(count)
        local UNITS = { "target", "focus", "mouseover", "tank", "healer" };
        local OVERLAP = { true, "help", "harm" };
        local bindings = {};
        for i = 1, count do
            local b = { name = "c" .. i, checkedUnits = {} };
            for u = 1, #UNITS do
                -- 값이 항상 서로 겹치게 해서 조기 종료가 안 걸리도록 한다
                b.checkedUnits[UNITS[u]] = OVERLAP[(i + u) % 3 + 1];
            end
            for s = 1, 5 do
                b["$state" .. s] = ((i + s) % 2 == 0);
            end
            bindings[i] = b;
        end
        bindings[count + 1] = { name = "subject" };
        return bindings;
    end

    test("겹치는 조건이 많아도 잔여 상자가 상한 안에 머묾", function()
        for _, count in ipairs({ 8, 16, 30 }) do
            local bindings = adversarialSet(count);
            survivors(bindings);
            check(not Stats.gaveUp,
                ("바인딩 %d개에서 상자 상한 초과로 판정을 포기함 (maxBoxes=%d)")
                :format(count, Stats.maxBoxes));
            check(Stats.maxBoxes < 512,
                ("바인딩 %d개에서 잔여 상자가 %d개 -- 서로소 분해가 깨졌는지 확인")
                :format(count, Stats.maxBoxes));
        end
    end);

    -- 컬럼 쳐내기가 결과를 바꾸면 안 된다. 모든 바인딩이 같은 값을 갖는 컬럼은
    -- 버려지는데, 그게 판정에 영향을 주면 여기서 드러난다.
    test("아무도 안 건드리는 축이 있어도 결과가 같다", function()
        expectRemoved({
            { name = "a", combat = true, forms = 3, groups = 1 },
            { name = "b", combat = true, forms = 3, groups = 1, stealth = true },
        }, "b");

        expectSurvives({
            { name = "a", combat = true, forms = 3, groups = 1 },
            { name = "b", combat = false, forms = 3, groups = 1 },
        }, "b");
    end);

    return T;
end
