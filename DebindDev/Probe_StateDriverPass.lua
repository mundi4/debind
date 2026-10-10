-- Probe_StateDriverPass.lua
-- What a tick of SecureStateDriverManager costs, and how much of it is our beat.
--
--   /debsdp [n]     out of combat: n passes of the manager's OnUpdate (default 10), one a frame.
--                   Every addon's attribute drivers and unit watches together, our beat within it,
--                   and our share. Written to DebindDevDB.stateDriverPass. /reload after.
--   /debbeat [n]    the next n runs of our beat branch (default 100), in combat or out, as the game
--                   delivers them. Written to DebindDevDB.beatHandler.
--   /debbeat stop   finish early with what was taken.
--
-- /debsdp takes the pass back with GetScript and calls it with an elapsed of math.huge, so its
-- throttle timer runs out on that call whatever `updatetime` is. Called from here it runs in our
-- execution, so the `timer` it writes is ours until an event on the manager's list zeroes it again.
-- One call goes first and is not timed, so a value that moved since the manager's last pass is
-- written there and every timed pass is one where nothing changes.
--
-- Our part is what `DebindPrivate.OnBeatTimed` reports, which a development build's beat calls with
-- each beat's time (`DebindBeatStart`, `DebindBeatEnd` in `Debind.lua`). It holds one `RunAttribute`
-- a shipped build does not pay, and leaves out the manager parsing our driver's one-letter value,
-- which is counted as the rest.

local TAG = "|cff66ccff[SDP]|r ";
local DEFAULT_RUNS = 10;
local DEFAULT_BEATS = 100;

local runner = CreateFrame("Frame");

--- Our beat time inside the pass being timed, nil while no pass is.
local passOurs;

local beat = {
    wanted = nil,
    samples = {},
    inCombat = {},
};

local FinishBeats;

local function OnBeatTimed(ms)
    if (passOurs) then
        passOurs = passOurs + ms;
    end
    if (beat.wanted) then
        local n = #beat.samples + 1;
        beat.samples[n] = ms;
        beat.inCombat[n] = InCombatLockdown();
        if (n >= beat.wanted) then
            FinishBeats();
        end
    end
end

local function Listen()
    local private = _G.DebindPrivate;
    if (not private) then
        print(TAG .. "Debind is not a development build");
        return nil;
    end
    private.OnBeatTimed = OnBeatTimed;
    return private;
end

local function LoadedAddOns()
    local list = {};
    for i = 1, C_AddOns.GetNumAddOns() do
        if (C_AddOns.IsAddOnLoaded(i)) then
            list[#list + 1] = (C_AddOns.GetAddOnInfo(i));
        end
    end
    return list;
end

local function Stats(samples)
    local sorted, total = {}, 0;
    for i, ms in ipairs(samples) do
        sorted[i] = ms;
        total = total + ms;
    end
    sort(sorted);
    local n = #sorted;
    return {
        min = sorted[1],
        median = (n % 2 == 1) and sorted[(n + 1) / 2] or (sorted[n / 2] + sorted[n / 2 + 1]) / 2,
        mean = total / n,
        max = sorted[n],
    };
end

local function Line(label, s)
    return format("%s median %.1f us, mean %.1f, min %.1f, max %.1f", label,
        s.median * 1000, s.mean * 1000, s.min * 1000, s.max * 1000);
end

local function Record(key, extra)
    local record = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        inRaid = IsInRaid(),
        groupSize = GetNumGroupMembers(),
        updatetime = SecureStateDriverManager:GetAttribute("updatetime"),
        signal = _G.DebindPrivate.BeatSignal.comes and "visibility" or "attribute",
        addOns = LoadedAddOns(),
    };
    for k, v in pairs(extra) do
        record[k] = v;
    end
    DebindDevDB = DebindDevDB or {};
    DebindDevDB[key] = record;
end

local function StartPasses(runs)
    if (InCombatLockdown()) then
        print(TAG .. "out of combat only");
        return;
    end
    if (runner:GetScript("OnUpdate")) then
        print(TAG .. "already running");
        return;
    end
    if (not Listen()) then
        return;
    end

    local pass = SecureStateDriverManager:GetScript("OnUpdate");
    local manager = SecureStateDriverManager;
    local totals, ours, shares = {}, {}, {};

    local function Finish(aborted)
        runner:SetScript("OnUpdate", nil);
        passOurs = nil;
        if (#totals == 0) then
            print(TAG .. "no pass timed" .. (aborted and (": " .. aborted) or ""));
            return;
        end
        local t, o = Stats(totals), Stats(ours);
        Record("stateDriverPass", {
            aborted = aborted,
            totalMs = totals,
            oursMs = ours,
            oursShare = shares,
            total = t,
            ours = o,
        });
        print(TAG .. format("%d passes%s", #totals, aborted and (" (" .. aborted .. ")") or ""));
        print(TAG .. Line("all:", t));
        print(TAG .. Line("ours:", o));
        print(TAG .. format("our share: %.1f%% of the mean", o.mean / t.mean * 100));
        if (o.max == 0) then
            print(TAG .. "no beat ran in any pass: this profile has nothing on the beat");
        end
        print(TAG .. "saved to DebindDevDB.stateDriverPass. /reload now.");
    end

    pass(manager, math.huge);

    runner:SetScript("OnUpdate", function()
        if (InCombatLockdown()) then
            Finish("combat started");
            return;
        end
        passOurs = 0;
        local start = debugprofilestop();
        local ok, err = pcall(pass, manager, math.huge);
        local spent = debugprofilestop() - start;
        local mine = passOurs;
        passOurs = nil;
        if (not ok) then
            Finish("error: " .. tostring(err));
            return;
        end
        local n = #totals + 1;
        totals[n], ours[n] = spent, mine;
        shares[n] = spent > 0 and mine / spent or 0;
        if (n >= runs) then
            Finish();
        end
    end);
end

function FinishBeats(aborted)
    local wanted = beat.wanted;
    beat.wanted = nil;
    if (not wanted) then
        print(TAG .. "not running");
        return;
    end
    if (#beat.samples == 0) then
        print(TAG .. "no beat timed" .. (aborted and (": " .. aborted) or ""));
        return;
    end
    local s = Stats(beat.samples);
    Record("beatHandler", {
        aborted = aborted,
        samplesMs = beat.samples,
        sampleInCombat = beat.inCombat,
        stats = s,
    });
    print(TAG .. Line(format("%d beats%s:", #beat.samples, aborted and (" (" .. aborted .. ")") or ""), s));
    print(TAG .. "saved to DebindDevDB.beatHandler.");
end

local function StartBeats(wanted)
    if (beat.wanted) then
        print(TAG .. "already running");
        return;
    end
    local private = Listen();
    if (not private) then
        return;
    end
    beat.samples, beat.inCombat = {}, {};
    beat.wanted = wanted;
    print(TAG .. format("waiting for %d beats (%s). /debbeat stop to finish early.", wanted,
        private.BeatSignal.comes and "visibility" or "attribute"));
end

SLASH_DEBSDP1 = "/debsdp";
SlashCmdList["DEBSDP"] = function(msg)
    local runs = tonumber(strtrim(msg or "")) or DEFAULT_RUNS;
    StartPasses(math.max(1, math.floor(runs)));
end

SLASH_DEBBEAT1 = "/debbeat";
SlashCmdList["DEBBEAT"] = function(msg)
    msg = strlower(strtrim(msg or ""));
    if (msg == "stop") then
        FinishBeats("stopped");
        return;
    end
    local wanted = tonumber(msg) or DEFAULT_BEATS;
    StartBeats(math.max(1, math.floor(wanted)));
end
