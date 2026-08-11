-- solver 성능/한계 측정. `lua tests/run.lua --bench`
--
-- 이 알고리즘의 유일한 실패 모드는 탐색 노드 수가 조용히 커지는 것이다.
-- 커지면 느려지고, MAX_NODES를 넘으면 그 바인딩의 판정을 포기한다
-- (= 조건을 복잡하게 쓰는 유저에게만 기능이 꺼진다). 그래서 시간과 노드 수를 같이 잰다.
--
-- CI는 진짜 Lua 5.1로 돌린다. 와우 애드온이 도는 것과 같은 버전이므로
-- 여기 나오는 숫자가 인게임 비용의 현실적인 근사치다.

return function(DebindPrivate)
    local CheckUnreachableBindings = DebindPrivate.CheckUnreachableBindings;
    local ClearUnreachableBindingCache = DebindPrivate.ClearUnreachableBindingCache;
    local Stats = DebindPrivate.SolverStats;

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
                b.checkedUnits = b.checkedUnits or {};
                b.checkedUnits[u] = pick(UNIT_VALS);
            end
        end
        if (rnd() < density * 0.5) then
            b.type = "spell";
            b.value = 100 + math.floor(rnd() * 4);
            b.known = true;
        end
        if (rnd() < density * 0.4) then
            b.hover = rnd() < 0.5;
            if (b.hover) then
                -- masks ride on hover bindings only -- Misc.lua strips them off the
                -- rest, so putting them anywhere else would price a shape the solver
                -- never sees. ALL is excluded for the same reason: it normalizes to nil.
                if (rnd() < 0.6) then b.reactions = math.floor(rnd() * 6) + 1; end
                if (rnd() < 0.6) then b.frameTypes = math.floor(rnd() * 126) + 1; end
            end
        end
        if (rnd() < density * 0.3) then b.forms = math.floor(rnd() * 2048); end
        if (rnd() < density * 0.3) then b.groups = math.floor(rnd() * 8); end
        return b;
    end

    local worstMs, worstNodes, gaveUpTotal = 0, 0, 0;

    io.write("\n한 키에 걸린 바인딩 수 / 조건 밀도별 (시행 100회씩)\n");
    io.write(("%-7s %-6s %10s %10s %10s %9s\n")
        :format("바인딩", "밀도", "평균ms", "최대ms", "최대노드", "포기율"));

    for _, count in ipairs({ 5, 10, 20, 27, 40 }) do
        for _, density in ipairs({ 0.2, 0.4, 0.7 }) do
            local trials = 100;
            local totalMs, maxMs, maxNodes, gaveUp = 0, 0, 0, 0;

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
                if (Stats.gaveUp) then gaveUp = gaveUp + 1; end
            end

            io.write(("%-7d %-6.1f %10.2f %10.2f %10d %8.0f%%\n")
                :format(count, density, totalMs / trials, maxMs, maxNodes, gaveUp / trials * 100));

            if (maxMs > worstMs) then worstMs = maxMs; end
            if (maxNodes > worstNodes) then worstNodes = maxNodes; end
            gaveUpTotal = gaveUpTotal + gaveUp;
        end
    end

    io.write(("\n최악: %.2f ms / 상자 %d개 / 캡 초과 %d회\n")
        :format(worstMs, worstNodes, gaveUpTotal));

    -- CheckUnreachableBindings는 키 하나에 대해 돈다. 한 키에 40개는 이미 비현실적이고,
    -- 여기서 포기가 나오기 시작하면 MAX_NODES를 다시 봐야 한다.
    return { worstMs = worstMs, worstNodes = worstNodes, gaveUp = gaveUpTotal };
end
