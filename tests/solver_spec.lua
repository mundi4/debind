-- 도달불가 바인딩 solver 테스트. 와우 클라이언트 불필요.
--
-- 두 층으로 되어 있음:
--   1. 이름 붙은 회귀 테스트 - 각 버그가 무엇이었는지 문서화
--   2. 무차별 대조 테스트 - 작은 조건 공간의 모든 점을 열거해서 정답을 직접
--      계산하고 solver 결과와 비교. §1-3(축 접기), §1-4(배열 압축) 같은
--      부류의 버그는 이쪽이 잡는다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local CheckUnreachableBindings = DebindPrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebindPrivate.ClearUnreachableBindingCache;

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

    --- Puts a list of bindings through the solver and answers the set of names that survive.
    -- The solver reads binding.unitStates, which `BuildUnitStates` derives while building a binding.
    -- These bindings are hand-written tables that never went through it, so the derivation runs
    -- here -- which also puts it under test, since it is the half that turns hover and
    -- units into one mask per unit.
    local BuildUnitStates = DebindPrivate.BuildUnitStates;

    --- Stands a hand-written binding up in **the shape production gives it**: conditions live in
    --- `binding.conditions` (`GetBindingInfoForAction`).
    ---
    --- The spec literals are written flat. With `conditions = { ... }` typed by hand on eighty lines,
    --- one line left out drops its condition in silence, and **a binding that lost a condition is
    --- wider and wrongly covers others**: the very kind of mistake the spec is there to catch,
    --- made inside the spec.
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

    local function survivors(bindings)
        for i = 1, #bindings do
            BuildUnitStates(nest(bindings[i]));
        end
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

    -- **컬럼은 번호가 아니라 이름마다 선다.** 다섯 번호를 돌며 `$state1`~`$state5`만 컬럼을
    -- 만들었고, 그래서 그 밖의 이름이 걸린 조건은 솔버에게 **안 보였다** - 상자가 조건 공간
    -- 전체가 되어 아래 바인딩을 전부 덮는다. 위 두 줄이 왜 컬럼이 하나씩이어야 하는지를
    -- 말하는 자리고, 여기는 그 컬럼이 이름 하나마다 서는지를 말한다.
    --
    -- 조건이 안 보인다는 것은 **더 넓어 보인다**는 뜻이라, 잘못은 위쪽에서 나타난다: 위가
    -- 아래를 덮어 지운다.
    test("다섯 밖의 이름도 자기 컬럼을 받는다", function()
        expectSurvives({
            { name = "burst", ["$burst"] = true },
            { name = "always" },
        }, "always");
    end);

    test("다섯 밖의 독립된 이름끼리도 서로를 못 덮는다", function()
        expectSurvives({
            { name = "burst",    ["$burst"] = true },
            { name = "tankmode", ["$tankmode"] = true },
        }, "tankmode");
    end);

    -- The unit group axis. **Storage is three overlapping boxes and the column is four exclusive
    -- cells**, so `UnitGroupToCells`, which spreads one into the other, alone decides whether this
    -- column is a partition.
    --
    -- [party] and [raid] both cover one cell (in a raid and in my subgroup). Counting that cell
    -- twice overflows the mask past the axis and **turns that very cell's bit off**, which is what
    -- `+` in place of `bor` does on an overlapping axis. The three below then fail to cover the
    -- whole and `always` is left standing.
    local UNITGROUP_PARTY = Constants.UNITGROUP_PARTY;
    local UNITGROUP_RAID = Constants.UNITGROUP_RAID;
    local UNITGROUP_NONE = Constants.UNITGROUP_NONE;

    test("소속 세 상자가 합쳐서 유닛 축 전체를 덮는다", function()
        expectRemoved({
            { name = "grouped", units = { target = { group = UNITGROUP_PARTY + UNITGROUP_RAID } } },
            { name = "alone",   units = { target = { group = UNITGROUP_NONE } } },
            { name = "always",  units = { target = {} } },
        }, "always");
    end);

    -- 겹치는 두 상자가 **서로를 못 덮는다.** [파티]는 공대의 다른 소그룹을 안 담고 [공대]는
    -- 공대가 아닌 파티를 안 담는다. 칸으로 안 펴고 상자 비트를 그대로 컬럼에 넣으면 두 상자가
    -- 분리로 보여서 이쪽은 통과하지만, 위 테스트가 그때 깨진다.
    test("소속 [파티]와 [공대]는 서로를 못 덮는다", function()
        expectSurvives({
            { name = "party", units = { target = { group = UNITGROUP_PARTY } } },
            { name = "raid",  units = { target = { group = UNITGROUP_RAID } } },
        }, "raid");
    end);

    test("소속 상자 둘을 켠 조건이 하나만 켠 조건을 덮는다", function()
        expectRemoved({
            { name = "grouped", units = { target = { group = UNITGROUP_PARTY + UNITGROUP_RAID } } },
            { name = "party",   units = { target = { group = UNITGROUP_PARTY } } },
        }, "party");
    end);

    -- **개수 제한이 풀린 뒤에도 컬럼이 이름마다 선다** (3c). 위 둘은 다섯 밖의 이름 **하나**를
    -- 보고, 여기는 그 이름이 **몇 개든** 저마다 축을 받는지를 본다. 컬럼이 어딘가에서 워드
    -- 하나나 다섯 칸으로 접히면 여섯째부터 남의 축에 얹혀서 서로를 덮기 시작한다.
    --
    -- 하나만 켜진 상자 열둘은 서로 겹치는 데가 없다. 열둘을 다 합쳐도 조건 공간을 못 채우므로
    -- 무조건 바인딩도 그대로 남아야 한다.
    test("스위치가 열둘이어도 저마다 컬럼을 받는다", function()
        local bindings = {};
        for i = 1, 12 do
            bindings[i] = { name = "s" .. i, ["$sw" .. i] = true };
        end
        bindings[#bindings + 1] = { name = "always" };

        local s = survivors(bindings);
        for i = 1, 12 do
            check(s["s" .. i], "s" .. i .. "이(가) 사라졌다. 그 이름이 남의 컬럼에 얹혔다");
        end
        check(s["always"], "무조건 바인딩이 사라졌다. 상자 열둘이 조건 공간을 다 덮었다");
    end);

    -- §1-3: basicunits/specialunits도 같은 문제. 게다가 units에 언급되지
    -- 않은 유닛의 니블이 0이 되어 상자가 퇴화했음.
    test("서로 다른 유닛 조건은 독립", function()
        expectSurvives({
            { name = "t", units = { target = true } },
            { name = "f", units = { focus = true } },
        }, "f");
    end);

    test("같은 유닛의 더 좁은 조건은 덮임", function()
        expectRemoved({
            { name = "exists", units = { target = true } },
            { name = "help",   units = { target = "help" } },
        }, "help");
    end);

    test("우호 조건은 존재 조건을 못 덮음", function()
        expectSurvives({
            { name = "help",   units = { target = "help" } },
            { name = "exists", units = { target = true } },
        }, "exists");
    end);

    test("우호 조건은 적대 조건을 못 덮음", function()
        expectSurvives({
            { name = "help", units = { target = "help" } },
            { name = "harm", units = { target = "harm" } },
        }, "harm");
    end);

    test("유닛 조건 두 개를 합치면 하나를 덮음", function()
        expectRemoved({
            { name = "t",   units = { target = true } },
            { name = "tf",  units = { target = true, focus = true } },
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

    -- **컬럼을 가르는 것은 액션의 주문이 아니라 물어보는 주문이다**
    -- (`making-known-a-spell-name.md`). 같은 주문에 걸린 두 액션이 서로 다른 특성을
    -- 물으면 두 축이고, 한 축으로 묶으면 뒤엣것이 앞엣것에 덮인 것으로 잘못 판정된다.
    test("같은 주문이어도 묻는 주문이 다르면 독립", function()
        expectSurvives({
            { name = "first",  type = Constants.SPELL, value = 100, known = "천체의 정렬" },
            { name = "second", type = Constants.SPELL, value = 100, known = "화신" },
        }, "second");
    end);

    test("묻는 주문이 같으면 중복", function()
        expectRemoved({
            { name = "first",  type = Constants.SPELL, value = 100, known = "천체의 정렬" },
            { name = "second", type = Constants.SPELL, value = 200, known = "천체의 정렬" },
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
            { name = "at",     units = { ["@"] = true } },
            { name = "always" },
        });
        check(s["at"] and s["always"], "opaque 바인딩이 관여한 판정이 일어남");
    end);

    test("바인딩이 하나뿐이면 아무것도 안 함", function()
        expectSurvives({ { name = "only" } }, "only");
    end);

    ---------------------------------------------------------------------------
    -- hover 컬럼 -- 1번 컬럼이고 모든 바인딩에 대해 돈다.
    -- action.key가 마우스 버튼이면 hover가 명시되지 않아도 "마우스오버 아님"이 된다
    -- (마우스 버튼 바인딩은 프레임 위에 올린 상태에서 눌리는 것이므로).
    -- 여기서 쓰는 GetMouseButtonAndPrefix는 Constants.lua의 진짜 구현이다.
    ---------------------------------------------------------------------------

    check(DebindPrivate.GetMouseButtonAndPrefix ~= nil,
        "GetMouseButtonAndPrefix가 로드 안 됨 -- hover 컬럼을 검증할 수 없음");

    test("마우스버튼 키는 hover 축이 좁아진다", function()
        -- 키보드 키: hover 미지정 = 마우스오버 + 아님 전부
        -- 마우스버튼 키: hover 미지정 = 마우스오버 아님, 뿐
        -- 따라서 마우스버튼 쪽이 키보드 쪽을 못 덮는다
        expectSurvives({
            { name = "mouse",    key = "BUTTON4" },
            { name = "keyboard", key = "SHIFT-Q" },
        }, "keyboard");

        -- 반대 방향은 덮인다
        expectRemoved({
            { name = "keyboard", key = "SHIFT-Q" },
            { name = "mouse",    key = "BUTTON4" },
        }, "mouse");
    end);

    test("수식어 붙은 마우스버튼도 마우스버튼으로 인식", function()
        expectRemoved({
            { name = "plain", key = "SHIFT-Q" },
            { name = "mod",   key = "CTRL-SHIFT-BUTTON5" },
        }, "mod");
    end);

    test("마우스버튼 키에 hover=true를 주면 다시 마우스오버 축", function()
        expectSurvives({
            { name = "nohover", key = "BUTTON4" },
            { name = "hover",   key = "BUTTON4", units = { unitframe = {} } },
        }, "hover");
    end);

    test("마우스버튼처럼 생긴 키가 아니면 좁아지지 않는다", function()
        expectSurvives({
            { name = "mouse", key = "BUTTON4" },
            { name = "fake",  key = "SHIFT-BUTTON9" },
        }, "fake");
    end);

    -- The cursor being on a frame is the client's `mouseover` standing on that frame's unit, so a
    -- `mouseover` action covers a hover one. `makeMouseoverFlags` is what folds that in, and a key
    -- carrying both a hover cast and a mouseover cast is the shape it was written for.
    test("mouseover=있음이 hover 조건을 덮는다", function()
        expectRemoved({
            { name = "mouseover", key = "SHIFT-Q", units = { mouseover = {} } },
            { name = "hover",     key = "SHIFT-Q", units = { unitframe = {} } },
        }, "hover");
    end);

    test("mouseover=있음이 hover=아군을 덮는다", function()
        expectRemoved({
            { name = "mouseover", key = "SHIFT-Q", units = { mouseover = {} } },
            { name = "hover",     key = "SHIFT-Q",
              units = { unitframe = { reaction = Constants.REACTION_HELP } } },
        }, "hover");
    end);

    -- **Where that fold lives is decided by this case.** Folded into the mask `Units.lua` builds,
    -- the column stands on a key where nobody named `mouseover`, and then two bindings splitting
    -- the hover axis between them stop covering an unconditional one -- the phantom point is
    -- theirs to cover and neither reaches it. Measured against that placement, this went red.
    test("hover 축을 쪼갠 둘은 여전히 무조건 바인딩을 덮는다", function()
        expectRemoved({
            { name = "nohover",  key = "SHIFT-Q", units = { unitframe = false } },
            { name = "hovering", key = "SHIFT-Q", units = { unitframe = {} } },
            { name = "always",   key = "SHIFT-Q" },
        }, "always");
    end);

    -- Not the other way round: mousing over something in the world sets the token with no frame
    -- anywhere.
    test("hover 조건은 mouseover=있음을 못 덮는다", function()
        expectSurvives({
            { name = "hover",     key = "SHIFT-Q", units = { unitframe = {} } },
            { name = "mouseover", key = "SHIFT-Q", units = { mouseover = {} } },
        }, "mouseover");
    end);

    ---------------------------------------------------------------------------
    -- 2. 무차별 대조
    ---------------------------------------------------------------------------

    -- 열거 가능한 작은 조건 공간. 아래 축들만 쓰는 바인딩을 만든다.
    local POINTS = {};
    do
        -- 유닛이 실제로 놓일 수 있는 상태. true는 "존재하지만 우호도 적대도 아님".
        -- 유닛 하나는 한 값이다 -- 런타임도 블리자드도 if/elseif로 푼다.
        local TARGET_VALUES = { false, "help", "harm", true };
        for _, combat in ipairs({ true, false }) do
            for _, stealth in ipairs({ true, false }) do
                for _, mounted in ipairs({ true, false }) do
                    for _, s1 in ipairs({ true, false }) do
                        for _, s2 in ipairs({ true, false }) do
                            for _, target in ipairs(TARGET_VALUES) do
                                for _, k100 in ipairs({ true, false }) do
                                    for _, k200 in ipairs({ true, false }) do
                                        POINTS[#POINTS + 1] = {
                                            combat = combat, stealth = stealth, mounted = mounted,
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
        if (b.mounted ~= nil and b.mounted ~= p.mounted) then return false; end
        if (b["$state1"] ~= nil and (b["$state1"] and true or false) ~= p.s1) then return false; end
        if (b["$state2"] ~= nil and (b["$state2"] and true or false) ~= p.s2) then return false; end

        local cond = b.units and b.units.target;
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
    local function referenceSurvivors(bindings, points, matcher)
        local names = {};
        for i = 1, #bindings do
            for _, p in ipairs(points) do
                if (matcher(bindings[i], p)) then
                    local covered = false;
                    for j = 1, i - 1 do
                        if (matcher(bindings[j], p)) then
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
        for _, key in ipairs({ "combat", "stealth", "mounted", "$state1", "$state2" }) do
            if (b[key] ~= nil) then
                parts[#parts + 1] = key .. "=" .. tostring(b[key]);
            end
        end
        if (b.units and b.units.target ~= nil) then
            parts[#parts + 1] = "target=" .. tostring(b.units.target);
        end
        if (b.known ~= nil) then
            parts[#parts + 1] = "known(" .. tostring(b.value) .. ")=" .. tostring(b.known);
        end
        if (#parts == 0) then
            return b.name .. "{}";
        end
        return b.name .. "{" .. table.concat(parts, ",") .. "}";
    end

    local function compareAgainstReference(bindings, label, points, matcher, describer)
        points = points or POINTS;
        matcher = matcher or matchesPoint;
        describer = describer or describe;

        local expected = referenceSurvivors(bindings, points, matcher);
        local snapshot = {};
        for i = 1, #bindings do
            snapshot[i] = describer(bindings[i]);
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
        for _, key in ipairs({ "combat", "stealth", "mounted", "$state1", "$state2" }) do
            local v = pick(TRI);
            if (v ~= "nil") then b[key] = v; end
        end
        local target = pick(TARGET_CONDS);
        if (target ~= "nil") then
            b.units = { target = target };
        end
        local known = pick(TRI);
        if (known ~= "nil") then b.known = known; end
        return b;
    end

    test("무작위 바인딩 집합 2000개 - 무차별 대조와 일치", function()
        for case = 1, 2000 do
            local count = math.floor(nextRandom() * 11) + 2;
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
                for _, mounted in ipairs({ true, false }) do
                    cells[#cells + 1] = { combat = combat, stealth = stealth, mounted = mounted };
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
                            mounted = cells[i].mounted,
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
    -- (combat=false, stealth=false, mounted=false) 칸이 아무에게도 안 덮이는데도
    -- 배열 압축 누락 때문에 잔여 집합이 비어버려 b7이 조용히 삭제됐다.
    test("§1-4 회귀 - 안 덮인 칸이 남아있으면 삭제되면 안 됨", function()
        expectSurvives({
            { name = "b1", combat = false, stealth = true },
            { name = "b2", combat = true,  stealth = true,  mounted = false },
            { name = "b3", combat = true },
            { name = "b4", combat = false, stealth = false, mounted = true },
            { name = "b5", combat = true,  stealth = true,  mounted = false },
            { name = "b6", combat = true,  mounted = false },
            { name = "b7", mounted = false },
        }, "b7");
    end);

    test("3축 격자 - 8칸 전부 덮으면 반드시 제거", function()
        local covers = {};
        for _, combat in ipairs({ true, false }) do
            for _, stealth in ipairs({ true, false }) do
                for _, mounted in ipairs({ true, false }) do
                    covers[#covers + 1] = {
                        name = "c" .. #covers,
                        combat = combat, stealth = stealth, mounted = mounted,
                    };
                end
            end
        end
        covers[#covers + 1] = { name = "target" };
        expectRemoved(covers, "target");
    end);

    ---------------------------------------------------------------------------
    -- 2-b. hover axis brute force
    --
    -- Folding hover into §2's space multiplies the point count by 22 and the
    -- reference stops being runnable, so the hover axis gets its own small space.
    --
    -- Bindings here skip normalization -- survivors() hands raw tables straight to
    -- CheckUnreachableBindings, with `BuildUnitStates` run over them so the masks exist.
    ---------------------------------------------------------------------------

    local band = bit.band;

    local REACTION_VALUES = {
        Constants.REACTION_HELP, Constants.REACTION_HARM, Constants.REACTION_OTHER,
    };
    local FRAMETYPE_VALUES = {
        Constants.FRAMETYPE_UNKNOWN, Constants.FRAMETYPE_PLAYER, Constants.FRAMETYPE_PET,
        Constants.FRAMETYPE_GROUP, Constants.FRAMETYPE_TARGET, Constants.FRAMETYPE_BOSS,
        Constants.FRAMETYPE_ARENA,
    };

    -- One point per state the hover slot can hold, times combat so covers have a
    -- second axis to split on. Nothing hovered means no frame at all, so that is a
    -- single point rather than one per frame type.
    local HOVER_POINTS = {};
    do
        for _, combat in ipairs({ true, false }) do
            HOVER_POINTS[#HOVER_POINTS + 1] = { hovering = false, combat = combat };
            for _, reaction in ipairs(REACTION_VALUES) do
                for _, frameType in ipairs(FRAMETYPE_VALUES) do
                    HOVER_POINTS[#HOVER_POINTS + 1] = {
                        hovering = true, reaction = reaction, frameType = frameType,
                        combat = combat,
                    };
                end
            end
        end
    end

    -- The condition is `units["unitframe"]` now -- the pointed frame's unit is a unit -- and the
    -- frame type mask is one of its axes. It describes the **frame** rather than the unit on it,
    -- so it is a record field of its own downstream, but there is no place left to store one off
    -- the hover path: the absent point is `false`, which carries no axes.
    local function hoverConditionOf(b)
        return b.units and b.units.unitframe;
    end

    local function matchesHoverPoint(b, p)
        local cond = hoverConditionOf(b);
        if (cond == false) then
            if (p.hovering) then return false; end
        elseif (cond) then
            if (not p.hovering) then return false; end
            if (cond.reaction and band(cond.reaction, p.reaction) == 0) then return false; end
            if (cond.frameTypes and band(cond.frameTypes, p.frameType) == 0) then return false; end
        elseif (b.key and DebindPrivate.GetMouseButtonAndPrefix(b.key)) then
            -- a mouse button fires wherever the cursor already is, so it can only
            -- answer for the not-hovering point
            if (p.hovering) then return false; end
        end
        if (b.combat ~= nil and b.combat ~= p.combat) then return false; end
        return true;
    end

    local function describeHover(b)
        local parts = {};
        local cond = hoverConditionOf(b);
        if (cond ~= nil) then
            parts[#parts + 1] = "hover=" .. (cond == false and "false" or "exists");
            if (cond and cond.reaction) then
                parts[#parts + 1] = ("reaction=%d"):format(cond.reaction);
            end
            if (cond and cond.frameTypes) then
                parts[#parts + 1] = ("frameTypes=%d"):format(cond.frameTypes);
            end
        end
        if (b.combat ~= nil) then parts[#parts + 1] = "combat=" .. tostring(b.combat); end
        parts[#parts + 1] = "key=" .. b.key;
        return b.name .. "{" .. table.concat(parts, ",") .. "}";
    end

    local function randomMask(values)
        local mask = 0;
        for _, v in ipairs(values) do
            if (nextRandom() < 0.5) then mask = mask + v; end
        end
        return mask;
    end

    local function randomHoverBinding(name)
        local b = { name = name, key = pick({ "SHIFT-Q", "BUTTON4" }) };

        -- Reactions are rolled **inside** the condition, because that is the only place they can
        -- be stored now. A mask on a binding that is not hovering is no longer a reachable input.
        local hover = pick({ "nil", "exists", false });
        if (hover == false) then
            b.units = { unitframe = false };
        elseif (hover == "exists") then
            local reaction = randomMask(REACTION_VALUES);
            local frameTypes = randomMask(FRAMETYPE_VALUES);
            b.units = { unitframe = {
                reaction = reaction ~= 0 and reaction or nil,
                frameTypes = frameTypes ~= 0 and frameTypes or nil,
            } };
        end

        local combat = pick({ "nil", true, false });
        if (combat ~= "nil") then b.combat = combat; end

        return b;
    end

    test("hover 축 무작위 바인딩 집합 2000개 - 무차별 대조와 일치", function()
        for case = 1, 2000 do
            local count = math.floor(nextRandom() * 6) + 2;
            local bindings = {};
            for i = 1, count do
                bindings[i] = randomHoverBinding("b" .. i);
            end
            compareAgainstReference(bindings, "hover case " .. case,
                HOVER_POINTS, matchesHoverPoint, describeHover);
        end
    end);

    -- A frame type mask narrows only the hovering half. The cover below asks for a group frame,
    -- so it does not reach the not-hovering point and the subject standing on exactly that point
    -- has to survive -- reading the mask off the whole binding is what deletes it.
    test("frameTypes는 가리키는 쪽만 좁힌다", function()
        expectSurvives({
            { name = "cover",   units = { unitframe = { frameTypes = Constants.FRAMETYPE_GROUP } } },
            { name = "subject", units = { unitframe = false } },
        }, "subject");
    end);

    -- Reactions and frame types cannot sit off the hover path at all -- they live **inside** the
    -- hover condition, so "not hovering" has no field to carry one. What is left to pin is that
    -- the two shapes still order the same way: "not hovering" covers itself.
    test("hover가 아니면 반응을 말할 자리가 없다", function()
        expectRemoved({
            { name = "cover",   units = { unitframe = false } },
            { name = "subject", units = { unitframe = false } },
        }, "subject");
    end);

    -- What folding the hover condition onto the unit axis buys. Both of these say the same
    -- thing -- hovering a friendly unit -- through two different menus, and the second is
    -- therefore unreachable.
    --
    -- While they were two columns the solver could not see it. The cover's reaction mask did
    -- not contain the subject's, and the subject's unit mask did not contain the cover's, so
    -- points like (hover=hostile, @=friendly) stayed uncovered -- points that cannot happen,
    -- because they are two readings of one unit.
    test("hover 반응과 @ 유닛 조건이 같은 축에 얹힌다", function()
        expectRemoved({
            { name = "byReaction", units = { unitframe = { reaction = Constants.REACTION_HELP } } },
            { name = "byUnit",     unit = "unitframe", units = { unitframe = {}, ["@"] = "help" } },
        }, "byUnit");

        -- and the other way round, so this is an identity rather than one side widening
        expectRemoved({
            { name = "byUnit",     unit = "unitframe", units = { unitframe = {}, ["@"] = "help" } },
            { name = "byReaction", units = { unitframe = { reaction = Constants.REACTION_HELP } } },
        }, "byReaction");
    end);

    ---------------------------------------------------------------------------
    -- 2-c. mask column brute force
    --
    -- Section 2 generates booleans and single-valued axes only. A `flagsToConditionFlags`
    -- column is neither: the condition is a **subset** of the axis, so a cover can overlap a
    -- region without containing it and the split has real work to do. Not one of those columns
    -- had brute-force coverage -- the same hole that was hiding the frameTypes guard.
    --
    -- groups (3 values) and forms (11) are the small and large end of that shape, and
    -- specialbar rides along so a boolean is in the mix. 66 points, enumerated whole.
    ---------------------------------------------------------------------------

    -- The point space states the axis widths on its own instead of deriving them, so that the
    -- three places that have to agree are pinned pairwise: Constants against this literal here,
    -- and `Solver.lua`'s `max` argument against the fuzzer below. Derive it and Constants could
    -- move without the fuzzer noticing.
    check(Constants.GROUP_ALL == 2 ^ 3 - 1, "GROUP_ALL이 3비트가 아님 -- 아래 점 공간을 고칠 것");
    check(Constants.FORM_ALL == 2 ^ 11 - 1, "FORM_ALL이 11비트가 아님 -- 아래 점 공간을 고칠 것");

    local MASK_POINTS = {};
    do
        local GROUPS = { Constants.GROUP_NONE, Constants.GROUP_PARTY, Constants.GROUP_RAID };
        for _, group in ipairs(GROUPS) do
            for formIndex = 0, 10 do
                for _, specialbar in ipairs({ true, false }) do
                    MASK_POINTS[#MASK_POINTS + 1] = {
                        group = group, form = 2 ^ formIndex, specialbar = specialbar,
                    };
                end
            end
        end
    end

    local function matchesMaskPoint(b, p)
        if (b.groups and band(b.groups, p.group) == 0) then return false; end
        if (b.forms and band(b.forms, p.form) == 0) then return false; end
        if (b.specialbar ~= nil and b.specialbar ~= p.specialbar) then return false; end
        return true;
    end

    local function describeMask(b)
        local parts = {};
        if (b.groups) then parts[#parts + 1] = ("groups=%d"):format(b.groups); end
        if (b.forms) then parts[#parts + 1] = ("forms=%d"):format(b.forms); end
        if (b.specialbar ~= nil) then parts[#parts + 1] = "specialbar=" .. tostring(b.specialbar); end
        if (#parts == 0) then
            return b.name .. "{}";
        end
        return b.name .. "{" .. table.concat(parts, ",") .. "}";
    end

    -- Masks are never rolled as 0. An empty mask means the condition can never hold, and the
    -- solver keeps such a binding rather than deleting it (see isCovered) -- which is the right
    -- answer but not the one the reference computes, since the reference asks "is there a point
    -- where this fires" and there is none. That case gets its own test below.
    local function randomMaskBinding(name)
        local b = { name = name };

        if (nextRandom() < 0.7) then
            b.groups = math.floor(nextRandom() * Constants.GROUP_ALL) + 1;
        end
        if (nextRandom() < 0.7) then
            b.forms = math.floor(nextRandom() * Constants.FORM_ALL) + 1;
        end

        local specialbar = pick({ "nil", true, false });
        if (specialbar ~= "nil") then b.specialbar = specialbar; end

        return b;
    end

    test("마스크 컬럼 무작위 바인딩 집합 2000개 - 무차별 대조와 일치", function()
        for case = 1, 2000 do
            local count = math.floor(nextRandom() * 6) + 2;
            local bindings = {};
            for i = 1, count do
                bindings[i] = randomMaskBinding("b" .. i);
            end
            compareAgainstReference(bindings, "mask case " .. case,
                MASK_POINTS, matchesMaskPoint, describeMask);
        end
    end);

    -- 0 is a condition no state satisfies. `flagsToConditionFlags` passes it through rather
    -- than reading it as "unset" -- 0 is truthy in Lua -- and the solver then finds the box
    -- disjoint from every cover, so it survives instead of being deleted. Deleting it would be
    -- defensible; warning about it is the issue check's job, and keeping it off the key is
    -- `BuildKeyMap`'s. That is the split we chose.
    test("마스크가 0이면 지워지지 않는다", function()
        expectSurvives({
            { name = "cover",   groups = Constants.GROUP_ALL },
            { name = "subject", groups = 0 },
        }, "subject");
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
    local Stats = DebindPrivate.SolverStats;

    local function adversarialSet(count)
        local UNITS = { "target", "focus", "mouseover", "tank", "healer" };
        local OVERLAP = { true, "help", "harm" };
        local bindings = {};
        for i = 1, count do
            local b = { name = "c" .. i, units = {} };
            for u = 1, #UNITS do
                -- 값이 항상 서로 겹치게 해서 조기 종료가 안 걸리도록 한다
                b.units[UNITS[u]] = OVERLAP[(i + u) % 3 + 1];
            end
            for s = 1, 5 do
                b["$state" .. s] = ((i + s) % 2 == 0);
            end
            bindings[i] = b;
        end
        bindings[count + 1] = { name = "subject" };
        return bindings;
    end

    test("겹치는 조건이 많아도 탐색이 예산 안에서 끝난다", function()
        for _, count in ipairs({ 8, 16, 30 }) do
            local bindings = adversarialSet(count);
            survivors(bindings);
            check(not Stats.gaveUp,
                ("바인딩 %d개에서 탐색 예산 초과로 판정을 포기함 (nodes=%d)")
                :format(count, Stats.nodes));
            check(Stats.nodes < count * 200,
                ("바인딩 %d개에서 노드 %d개 -- 가지치기가 깨졌는지 확인")
                :format(count, Stats.nodes));
            -- 예산이 걸린 단위로도 본다. 노드 수는 컬럼이 넓어지는 것을 못 보므로, 노드가
            -- 그대로인데 비용만 뛰는 회귀는 위 검사를 통과한다.
            check(Stats.maxWork < count * 500,
                ("바인딩 %d개에서 한 바인딩이 비용 %d -- 상한(30000)에 얼마나 가까운지 확인")
                :format(count, Stats.maxWork));
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


    ---------------------------------------------------------------------------
    -- 2-d. bonusbar 축의 폭
    --
    -- `flagsToConditionFlags` 컬럼은 넷인데 폭까지 잡히는 것은 셋뿐이다. groups와 forms는
    -- 2-c가, frameTypes는 2-b가 일곱 값을 전부 열거해서 잡는다. **bonusbars는 이 파일 어디에도
    -- 없었다.**
    --
    -- 그리고 이 축만 `Constants` 쪽이 파생값이다 -- `BONUSBAR_ALL`이 `MAX_BONUSBAR_OFFSET`에서
    -- 나온다. `Solver.lua`는 같은 수를 리터럴로 들고 있어서 그 상수를 올리면 둘이 갈리고,
    -- 갈리면 "조건 없음"이 축 전체를 뜻하지 않게 된다. 그 파일 머리말이 적어둔 결과가 그대로
    -- 따라온다: 상자가 조건보다 좁게 나오고 **아직 발동할 수 있는 바인딩이 지워진다.**
    --
    -- 두 방향을 다 본다. 앞엣것은 solver의 폭이 좁을 때만, 뒤엣것은 넓을 때만 걸린다.
    ---------------------------------------------------------------------------

    test("bonusbar 축: 조건 없음과 전체 마스크가 같은 상자다", function()
        expectRemoved({
            { name = "open" },
            { name = "full", bonusbars = Constants.BONUSBAR_ALL },
        }, "full");

        expectRemoved({
            { name = "full", bonusbars = Constants.BONUSBAR_ALL },
            { name = "open" },
        }, "open");
    end);

    --- **A unit condition this build cannot read must not delete the binding under it.**
    ---
    --- The value arrives from a payload built by a newer version: `Import.lua` checks that `units`
    --- is a table and copies what is inside it as it stands, and `CleanUpDB` sweeps the condition
    --- **keys** without looking at their values. So a name we do not know sits in a real profile.
    ---
    --- Reading it as the absent point is not a narrow answer, it is a **different** one: the absent
    --- point is smaller than "exists" but it is not inside it. A higher-priority binding carrying
    --- that reading covers the binding that really is [when there is none], and the solver deletes
    --- a condition the reader set, with nothing on screen to say so -- the mask is
    --- `UNITSTATE_NONE` rather than 0, so the binding is not `dead` and no issue fires either.
    ---
    --- `Solver.lua`'s header wrote the answer down before the case turned up: a condition that
    --- cannot be placed on an axis makes the binding opaque, out of both roles, rather than being
    --- ignored.
    test("이 빌드가 못 읽는 유닛 조건은 아래 바인딩을 안 지운다", function()
        local built = {};
        for _, spec in ipairs({
            { name = "unreadable", units = { target = "from-a-newer-build" } },
            { name = "absent",     units = { target = false } },
        }) do
            local binding = DebindPrivate.GetBindingInfoForAction(
                { type = Constants.SPELL, value = 585, key = "T",
                  conditions = { units = spec.units } });
            built[#built + 1] = { name = spec.name, binding = binding };
        end

        check(built[1].binding.unitStatesOpaque,
            "못 읽는 값이 두 역할에서 안 빠졌다 - 전제가 깨졌다");

        -- **순서가 곧 우선순위다.** 못 읽는 값이 위, [없을 때]가 아래 - 항목이 적어둔 그 배치다.
        local bindings = {};
        for i = 1, #built do
            local b = built[i].binding;
            b.name = built[i].name;
            bindings[i] = b;
        end

        ClearUnreachableBindingCache();
        CheckUnreachableBindings(bindings);

        -- 살아남은 것만 배열에 남는다(`survivors`와 같은 읽기).
        local survived = {};
        for i = 1, #bindings do
            survived[bindings[i].name] = true;
        end

        check(survived["absent"],
            "[없을 때] 바인딩이 못 읽는 값에 덮여 지워졌다");
    end);

    return T;
end
