-- solver 성능/한계 측정. `lua tests/run.lua --bench`
--
-- 이 알고리즘의 유일한 실패 모드는 탐색 비용이 조용히 커지는 것이다. 커지면 느려지고,
-- 상한을 넘으면 그 바인딩의 판정을 포기한다. 그래서 시간과 비용을 같이 잰다.
--
-- Which user that lands on is the opposite of what this file used to claim. Cost falls as
-- conditions pile on -- 40 bindings at density 0.2 take 2.5ms, the same 40 at 0.4 take 6.5ms
-- and at 0.7 take 2.7ms. Tight conditions make small boxes that fall out on the disjointness
-- test; sparse ones make large boxes that overlap and drive the recursion deep. The expensive
-- key is a pile of barely-conditioned bindings, not a carefully conditioned one.
--
-- **`Solver.lua`의 상한을 여기서 잡는다.** 세 열이 그래서 있다:
--   최대노드      깊이. 가지치기가 깨졌는지 본다.
--   바인딩당최대  `MAX_WORK`가 걸리는 단위. 한 바인딩이 쓴 비용의 최대.
--   (합)          아래 요약의 "비용". `MAX_CALL_WORK`가 걸리는 단위.
--
-- 노드와 비용은 일부러 따로 본다. 노드가 그대로인데 비용만 뛰는 회귀가 있다 -- 컬럼이
-- 넓어지거나 커버가 늘면 그렇게 된다. 예전에 342노드가 21ms였던 것이 그 모양이었다.
--
-- CI는 진짜 Lua 5.1로 돌린다. 와우 애드온이 도는 것과 같은 버전이므로
-- 여기 나오는 숫자가 인게임 비용의 현실적인 근사치다.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local CheckUnreachableBindings = DebindPrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebindPrivate.ClearUnreachableBindingCache;
    local BuildUnitStates = DebindPrivate.BuildUnitStates;
    local Stats = DebindPrivate.SolverStats;

    --- 손으로 쓴 바인딩을 프로덕션과 같은 모양으로 세운다. `solver_spec`의 같은 이름과 같은
    --- 것이고, 같은 이유로 리터럴을 평평하게 쓴다.
    ---
    --- **이 파일에는 이것이 없었다.** 조건이 `binding.conditions`로 내려간 날(`2b8e87d`) 스펙
    --- 쪽만 따라갔고, 벤치는 평평한 표를 그대로 넘겨서 `buildLayout`이 nil을 인덱싱하며
    --- 죽었다. CI가 도는데도 그랬던 이유는 그 단계가 스펙 뒤에 따로 서 있어서다.
    local function nest(binding)
        local conditions = binding.conditions or {};
        for k, v in pairs(binding) do
            if (Constants.IsConditionField(k)) then
                conditions[k] = v;
                binding[k] = nil;
            end
        end
        binding.conditions = conditions;
        BuildUnitStates(binding);
        return binding;
    end

    local rng = 991;
    local function rnd()
        rng = (rng * 16807) % 2147483647;
        return rng / 2147483647;
    end
    local function pick(t)
        return t[math.floor(rnd() * #t) + 1];
    end

    local BOOLS = { "combat", "stealth", "pet", "petbattle", "specialbar", "extrabar" };
    local STATES = { "$state1", "$state2", "$state3", "$state4", "$state5" };
    local UNITS = { "mouseover", "player", "pet", "target", "focus", "none",
                    "tank", "healer", "maintank", "mainassist", "custom1", "custom2", "hover" };
    local UNIT_VALS = { true, false, "help", "harm" };
    local KEYS = { "SHIFT-Q", "BUTTON4", "CTRL-BUTTON5", "ALT-F" };

    --- density = 각 조건이 걸릴 확률. 0.2이 평범한 프로필, 0.7이면 거의 모든 축을 씀.
    local function makeBinding(name, density)
        local b = { name = name, key = pick(KEYS) };
        for _, k in ipairs(BOOLS) do
            if (rnd() < density) then b[k] = rnd() < 0.5; end
        end
        for _, s in ipairs(STATES) do
            if (rnd() < density) then b[s] = rnd() < 0.5; end
        end
        for _, u in ipairs(UNITS) do
            if (rnd() < density * 0.6) then
                b.units = b.units or {};
                b.units[u] = pick(UNIT_VALS);
            end
        end
        if (rnd() < density * 0.5) then
            b.type = "spell";
            b.value = 100 + math.floor(rnd() * 4);
            b.known = true;
        end
        if (rnd() < density * 0.4) then
            -- 호버 조건은 `units["hover"]`다 - 호버한 프레임의 유닛도 유닛이다.
            -- 반응은 그 안의 한 축이고, `frameTypes`는 프레임을 말하는 값이라 밖에 남는다.
            -- ALL은 안 넣는다: nil로 정규화되므로 없는 것과 같은 모양을 두 번 재게 된다.
            if (rnd() < 0.5) then
                local condition = {};
                if (rnd() < 0.6) then condition.reaction = math.floor(rnd() * 6) + 1; end
                b.units = { hover = condition };
                if (rnd() < 0.6) then b.frameTypes = math.floor(rnd() * 126) + 1; end
            else
                b.units = { hover = false };
            end
        end
        if (rnd() < density * 0.3) then b.forms = math.floor(rnd() * 2048); end
        if (rnd() < density * 0.3) then b.groups = math.floor(rnd() * 8); end
        return nest(b);
    end

    local worstMs, worstNodes, worstWork, gaveUpTotal = 0, 0, 0, 0;

    io.write("\n한 키에 걸린 바인딩 수 / 조건 밀도별 (시행 100회씩)\n");
    io.write(("%-7s %-6s %10s %10s %10s %12s %9s\n")
        :format("바인딩", "밀도", "평균ms", "최대ms", "최대노드", "바인딩당최대", "포기율"));

    for _, count in ipairs({ 5, 10, 20, 27, 40 }) do
        for _, density in ipairs({ 0.2, 0.4, 0.7 }) do
            local trials = 100;
            local totalMs, maxMs, maxNodes, maxWork, gaveUp = 0, 0, 0, 0, 0;

            for _ = 1, trials do
                local bindings = {};
                for i = 1, count do bindings[i] = makeBinding("b" .. i, density); end

                ClearUnreachableBindingCache();
                local t0 = os.clock();
                CheckUnreachableBindings(bindings);
                local ms = (os.clock() - t0) * 1000;

                totalMs = totalMs + ms;
                if (ms > maxMs) then maxMs = ms; end
                if (Stats.nodes > maxNodes) then maxNodes = Stats.nodes; end
                if (Stats.maxWork > maxWork) then maxWork = Stats.maxWork; end
                if (Stats.gaveUp) then gaveUp = gaveUp + 1; end
            end

            io.write(("%-7d %-6.1f %10.2f %10.2f %10d %12d %8.0f%%\n")
                :format(count, density, totalMs / trials, maxMs, maxNodes, maxWork,
                    gaveUp / trials * 100));

            if (maxMs > worstMs) then worstMs = maxMs; end
            if (maxNodes > worstNodes) then worstNodes = maxNodes; end
            if (maxWork > worstWork) then worstWork = maxWork; end
            gaveUpTotal = gaveUpTotal + gaveUp;
        end
    end

    io.write(("\n최악: %.2f ms / 노드 %d / 비용 %d / 캡 초과 %d회\n")
        :format(worstMs, worstNodes, worstWork, gaveUpTotal));

    -- CheckUnreachableBindings는 키 하나에 대해 돈다. 한 키에 40개는 이미 비현실적이고,
    -- 여기서 포기가 나오기 시작하면 MAX_WORK를 다시 봐야 한다. 예산은 **바인딩마다**
    -- 리셋되므로 위의 "최대비용"은 한 바인딩이 쓴 값이 아니라 그 호출 전체의 합이다.
    return { worstMs = worstMs, worstNodes = worstNodes, worstWork = worstWork, gaveUp = gaveUpTotal };
end
