-- Probe_PeriodEquivalence.lua
-- Which `updatetime` behaves exactly like 0 at a given frame rate
-- (`zeroing-the-beat-period-where-it-is-needed.md` 2-1).
--
--   /debfps [seconds]   steps the foreground frame cap through CAPS, holds each for `seconds`
--                       (default 10) after a settle, records every frame's `elapsed`, then puts
--                       `maxFPS` and `useMaxFPS` back. Written to DebindDevDB.periodEquivalence.
--   /debfps stop        finish early with what was taken, and put the cap back.
--
-- The manager runs a pass on a frame where `timer - elapsed <= 0` and then sets `timer` to the
-- period, dropping what was left over (`SecureStateDriver.lua`). So a period T passes on every frame
-- exactly while no frame's `elapsed` is below T. The recorded series is run through that same
-- arithmetic for every candidate T, which answers without touching the manager.
--
-- **Assumed, not measured here:** every frame's OnUpdate is handed the same `elapsed`, so ours is
-- the manager's. Events are left out of the replay: one zeroes the timer and only ever adds a pass.

local TAG = "|cff66ccff[FPS]|r ";
local DEFAULT_SECONDS = 10;
local SETTLE = 1.5;
--- 0 is the uncapped segment.
local CAPS = { 60, 120, 144, 165, 200, 240, 0 };

--- 0, then 0.5 ms steps to 20 ms.
local CANDIDATES = { 0 };
for i = 1, 40 do
    CANDIDATES[#CANDIDATES + 1] = i * 0.0005;
end

local runner = CreateFrame("Frame");
local run;

local function Replay(series, period)
    local timer, passes, skipped, gap, longest = 0, 0, 0, 0, 0;
    for i = 1, #series do
        timer = timer - series[i];
        if (timer <= 0) then
            timer = period;
            passes = passes + 1;
            gap = 0;
        else
            skipped = skipped + 1;
            gap = gap + 1;
            if (gap > longest) then
                longest = gap;
            end
        end
    end
    return passes, skipped, longest;
end

local function Percentile(sorted, p)
    if (#sorted == 0) then
        return nil;
    end
    local i = math.max(1, math.min(#sorted, math.floor(#sorted * p + 0.5)));
    return sorted[i];
end

local function Summarize(segment)
    local series = segment.elapsed;
    local sorted = {};
    local total = 0;
    for i = 1, #series do
        sorted[i] = series[i];
        total = total + series[i];
    end
    table.sort(sorted);
    segment.frames = #series;
    segment.seconds = total;
    segment.fps = total > 0 and #series / total or nil;
    segment.elapsedMs = {
        min = sorted[1] and sorted[1] * 1000,
        p001 = Percentile(sorted, 0.001) and Percentile(sorted, 0.001) * 1000,
        p01 = Percentile(sorted, 0.01) and Percentile(sorted, 0.01) * 1000,
        p50 = Percentile(sorted, 0.5) and Percentile(sorted, 0.5) * 1000,
        p99 = Percentile(sorted, 0.99) and Percentile(sorted, 0.99) * 1000,
        max = sorted[#sorted] and sorted[#sorted] * 1000,
    };

    local periods = {};
    if (segment.cap > 0) then
        periods[#periods + 1] = 1 / segment.cap;
    end
    for _, period in ipairs(CANDIDATES) do
        periods[#periods + 1] = period;
    end
    segment.replay = {};
    segment.largestLikeZero = 0;
    for _, period in ipairs(periods) do
        local passes, skipped, longest = Replay(series, period);
        segment.replay[#segment.replay + 1] = {
            periodMs = period * 1000,
            passes = passes,
            passesPerSecond = total > 0 and passes / total or nil,
            skippedFrames = skipped,
            longestSkipRun = longest,
        };
        if (skipped == 0 and period > segment.largestLikeZero) then
            segment.largestLikeZero = period;
        end
    end
end

local function ReadCap()
    return {
        maxFPS = C_CVar.GetCVar("maxFPS"),
        useMaxFPS = C_CVar.GetCVar("useMaxFPS"),
        targetFPS = C_CVar.GetCVar("targetFPS"),
        useTargetFPS = C_CVar.GetCVar("useTargetFPS"),
        vsync = C_CVar.GetCVar("vsync"),
    };
end

local function SetCap(cap)
    local ok1, err1, ok2, err2;
    if (cap > 0) then
        ok1, err1 = pcall(C_CVar.SetCVar, "maxFPS", tostring(cap));
        ok2, err2 = pcall(C_CVar.SetCVar, "useMaxFPS", "1");
    else
        ok1, ok2 = true, true;
        ok2, err2 = pcall(C_CVar.SetCVar, "useMaxFPS", "0");
    end
    if (ok1 and ok2) then
        return nil;
    end
    return tostring(err1 or err2);
end

local function Finish(reason)
    runner:SetScript("OnUpdate", nil);
    if (not run) then
        return;
    end
    local saved = run.savedCap;
    pcall(C_CVar.SetCVar, "maxFPS", saved.maxFPS);
    pcall(C_CVar.SetCVar, "useMaxFPS", saved.useMaxFPS);

    for _, segment in ipairs(run.segments) do
        Summarize(segment);
        print(TAG .. format("cap %s: %.1f fps, elapsed min %.2f ms p0.1 %.2f p1 %.2f p50 %.2f, like 0 up to %.1f ms",
            segment.cap > 0 and tostring(segment.cap) or "off", segment.fps or 0,
            segment.elapsedMs.min or 0, segment.elapsedMs.p001 or 0, segment.elapsedMs.p01 or 0,
            segment.elapsedMs.p50 or 0, segment.largestLikeZero * 1000));
    end

    DebindDevDB = DebindDevDB or {};
    DebindDevDB.periodEquivalence = {
        when = date("%Y-%m-%d %H:%M:%S"),
        build = { GetBuildInfo() },
        reason = reason,
        savedCap = saved,
        updatetime = SecureStateDriverManager:GetAttribute("updatetime"),
        segments = run.segments,
    };
    run = nil;
    print(TAG .. "cap put back. saved to DebindDevDB.periodEquivalence. /reload now.");
end

local function Start(seconds)
    if (run) then
        print(TAG .. "already running");
        return;
    end
    run = {
        seconds = seconds,
        savedCap = ReadCap(),
        segments = {},
        index = 0,
    };
    local segment, clock;

    local function Next()
        run.index = run.index + 1;
        local cap = CAPS[run.index];
        if (not cap) then
            Finish();
            return false;
        end
        local err = SetCap(cap);
        segment = {
            cap = cap,
            setError = err,
            capAfterSet = ReadCap(),
            elapsed = {},
            inCombat = {},
        };
        run.segments[#run.segments + 1] = segment;
        clock = -SETTLE;
        print(TAG .. format("cap %s for %d s", cap > 0 and tostring(cap) or "off", seconds));
        return true;
    end

    if (not Next()) then
        return;
    end
    runner:SetScript("OnUpdate", function(_, elapsed)
        clock = clock + elapsed;
        if (clock <= 0) then
            return;
        end
        local n = #segment.elapsed + 1;
        segment.elapsed[n] = elapsed;
        segment.inCombat[n] = InCombatLockdown() or nil;
        if (clock >= seconds) then
            Next();
        end
    end);
end

SLASH_DEBINDDEVFPS1 = "/debfps";
SlashCmdList.DEBINDDEVFPS = function(msg)
    msg = strtrim(msg or "");
    if (msg == "stop") then
        Finish("stopped");
        return;
    end
    Start(tonumber(msg) or DEFAULT_SECONDS);
end
