-- Probe_CooldownBeat.lua
-- Can a Cooldown widget carry a beat? Blizzard says a Cooldown shows and hides itself
-- (`Blizzard_UIWidgetTemplateBase.lua`, `UIWidgetBaseButtonTemplateMixin:UpdateCooldown`). If the
-- hide at the end of a cooldown reaches a snippet wrapped on OnHide as secure execution, the insecure
-- side could arm a short cooldown every frame and get a secure entry back each time, in combat too,
-- without the shared `updatetime`.
--
-- What has to hold, each answered here:
--   - a Cooldown can inherit `SecureFrameTemplate` and come out protected (`IsWrapEligible` in combat
--     takes only a protected frame)
--   - `SetCooldown` from the insecure side goes through on it inside the lockdown, with the show it
--     brings (an `ADDON_ACTION_BLOCKED` says it does not)
--   - the hide when the cooldown runs out runs the wrapped snippet (`CallRestrictedClosure` refuses an
--     insecure caller, so a hide with no run behind it is the answer "insecure", and comes with a Lua
--     error "Cannot call restricted closure from insecure code")
--   - how many frames from an arm to the hide
--
-- Two Cooldowns, each with the same counting snippet on OnHide: `secure` inherits
-- `SecureFrameTemplate`, `plain` inherits nothing. `plain` is the control: out of the lockdown it
-- says whether the mechanism works at all, inside it the snippet must not run (not wrap-eligible).
-- Both are made and wrapped at load, so a load inside the lockdown is recorded and not retried.
--
-- A variant stops arming in a lockdown state after STOP_AFTER hides with no run behind them, or
-- STOP_AFTER arms in a row that never showed, or a blocked action while arming it, so a failure
-- leaves a few errors and not one a frame.
--
--   /debcd [duration]   start arming every frame (duration of each cooldown, default 0.001 s).
--                       Finishes by itself once SECONDS have passed both out of and inside the
--                       lockdown. Written to DebindDevDB.cooldownBeat.
--   /debcd stop         finish with what was taken.

local TAG = "|cff33ff99[CDB]|r ";
local DEFAULT_DURATION = 0.001;
local SECONDS = 5;
local STOP_AFTER = 5;
--- How long past its duration an arm waits for the hide before it is counted as never coming.
local GRACE = 1;

local SNIPPET = [[
self:SetAttribute("runs", (self:GetAttribute("runs") or 0) + 1)
if (PlayerInCombat()) then
    self:SetAttribute("runsInCombat", (self:GetAttribute("runsInCombat") or 0) + 1)
end
]];

local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate");

local setup = {
    lockdownAtLoad = InCombatLockdown(),
    variants = {},
};
local variants = {};

local function Make(key, template)
    local v = { key = key };
    local record = { key = key, template = template or false };
    setup.variants[#setup.variants + 1] = record;
    variants[#variants + 1] = v;
    v.record = record;

    local ok, frame = pcall(CreateFrame, "Cooldown", nil, UIParent, template);
    record.createOk = ok;
    if (not ok) then
        record.createError = tostring(frame);
        return;
    end
    v.frame = frame;
    local p1, p2 = frame:IsProtected();
    record.isProtected = { p1 and true or false, p2 and true or false };
    record.objectType = frame:GetObjectType();
    record.shownAtCreate = frame:IsShown();

    record.layout = {
        size = pcall(frame.SetSize, frame, 1, 1),
        point = pcall(frame.SetPoint, frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0),
        swipe = pcall(frame.SetDrawSwipe, frame, false),
        edge = pcall(frame.SetDrawEdge, frame, false),
        bling = pcall(frame.SetDrawBling, frame, false),
        numbers = pcall(frame.SetHideCountdownNumbers, frame, true),
    };

    local okWrap, err = pcall(SecureHandlerWrapScript, frame, "OnHide", header, SNIPPET);
    record.wrapOk = okWrap;
    if (not okWrap) then
        record.wrapError = tostring(err);
    end
    record.shownAfterSetup = frame:IsShown();
    record.runsBeforeStart = frame:GetAttribute("runs") or 0;
end

Make("secure", "SecureFrameTemplate");
Make("plain", nil);

local function NewStats()
    return {
        frames = 0,
        arms = 0,
        armErrors = {},
        notVisibleAtArm = 0,
        shownRightAfterArm = 0,
        shownLater = 0,
        neverShown = 0,
        hides = 0,
        noHide = 0,
        runs = 0,
        runsInCombat = 0,
        silentHides = 0,
        framesToHide = {},
        secondsToHide = {},
        blocked = 0,
        stopped = false,
    };
end

local runner = CreateFrame("Frame");
local run;
--- The variant whose `SetCooldown` is on the stack, for a blocked action raised inside it.
local arming;

local function StateKey()
    return InCombatLockdown() and "locked" or "unlocked";
end

local function Arm(v, s)
    if (not v.frame:IsVisible()) then
        s.notVisibleAtArm = s.notVisibleAtArm + 1;
    end
    arming = v;
    local ok, err = pcall(v.frame.SetCooldown, v.frame, GetTime(), run.duration);
    arming = nil;
    s.arms = s.arms + 1;
    if (not ok) then
        if (#s.armErrors < STOP_AFTER) then
            s.armErrors[#s.armErrors + 1] = tostring(err);
        end
        v.missedShows = v.missedShows + 1;
        if (v.missedShows >= STOP_AFTER) then
            s.stopped = "arm errors";
        end
        return;
    end
    v.armedFrame = run.frame;
    v.armedTime = GetTime();
    v.seenShown = v.frame:IsShown();
    if (v.seenShown) then
        s.shownRightAfterArm = s.shownRightAfterArm + 1;
        v.missedShows = 0;
    end
end

local function Step(v, s)
    local runs = v.frame:GetAttribute("runs") or 0;
    local inCombat = v.frame:GetAttribute("runsInCombat") or 0;
    local newRuns = runs - v.lastRuns;
    s.runs = s.runs + newRuns;
    s.runsInCombat = s.runsInCombat + (inCombat - v.lastInCombat);
    v.lastRuns, v.lastInCombat = runs, inCombat;

    local shown = v.frame:IsShown();
    if (v.armedFrame) then
        if (shown and not v.seenShown) then
            v.seenShown = true;
            v.missedShows = 0;
            s.shownLater = s.shownLater + 1;
        end
        if (v.seenShown and not shown) then
            s.hides = s.hides + 1;
            local frames = run.frame - v.armedFrame;
            s.framesToHide[frames] = (s.framesToHide[frames] or 0) + 1;
            local seconds = GetTime() - v.armedTime;
            local t = s.secondsToHide;
            t.min = math.min(t.min or seconds, seconds);
            t.max = math.max(t.max or seconds, seconds);
            t.sum = (t.sum or 0) + seconds;
            if (newRuns == 0) then
                s.silentHides = s.silentHides + 1;
                v.silentInRow = v.silentInRow + 1;
                if (v.silentInRow >= STOP_AFTER) then
                    s.stopped = "hides without a run";
                end
            else
                v.silentInRow = 0;
            end
            v.armedFrame = nil;
        elseif (GetTime() - v.armedTime > run.duration + GRACE) then
            if (v.seenShown) then
                s.noHide = s.noHide + 1;
            else
                s.neverShown = s.neverShown + 1;
                v.missedShows = v.missedShows + 1;
                if (v.missedShows >= STOP_AFTER) then
                    s.stopped = "arms that never showed";
                end
            end
            v.armedFrame = nil;
        end
    end
    if (not v.armedFrame and not s.stopped) then
        Arm(v, s);
    end
end

local function Finish(reason)
    runner:SetScript("OnUpdate", nil);
    runner:UnregisterAllEvents();
    if (not run) then
        return;
    end
    local out = {
        when = date("%Y-%m-%d %H:%M:%S"),
        build = { GetBuildInfo() },
        class = select(2, UnitClass("player")),
        reason = reason or "both states held",
        duration = run.duration,
        frames = run.frame,
        seconds = run.seconds,
        setup = setup,
        blockedEvents = run.blockedEvents,
        stats = {},
    };
    for _, v in ipairs(variants) do
        if (v.frame) then
            out.stats[v.key] = v.stats;
            for _, state in ipairs({ "unlocked", "locked" }) do
                local s = v.stats[state];
                local mode, modeN = nil, 0;
                for frames, n in pairs(s.framesToHide) do
                    if (n > modeN) then
                        mode, modeN = frames, n;
                    end
                end
                print(TAG .. format("%s %s: arms %d, hides %d, runs %d (in combat %d), silent %d, blocked %d, "
                    .. "never shown %d, no hide %d, frames to hide mostly %s%s",
                    v.key, state, s.arms, s.hides, s.runs, s.runsInCombat, s.silentHides, s.blocked,
                    s.neverShown, s.noHide, tostring(mode), s.stopped and (", stopped: " .. s.stopped) or ""));
            end
        else
            print(TAG .. format("%s: not made (%s)", v.key, tostring(v.record.createError)));
        end
    end
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.cooldownBeat = out;
    run = nil;
    print(TAG .. "saved to DebindDevDB.cooldownBeat. /reload to write it out.");
end

local function Start(duration)
    if (run) then
        print(TAG .. "already running");
        return;
    end
    run = {
        duration = duration,
        frame = 0,
        seconds = { unlocked = 0, locked = 0 },
        blockedEvents = {},
    };
    for _, v in ipairs(variants) do
        if (v.frame) then
            v.stats = { unlocked = NewStats(), locked = NewStats() };
            v.lastRuns = v.frame:GetAttribute("runs") or 0;
            v.lastInCombat = v.frame:GetAttribute("runsInCombat") or 0;
            v.armedFrame = nil;
            v.missedShows = 0;
            v.silentInRow = 0;
        end
    end
    runner:RegisterEvent("ADDON_ACTION_BLOCKED");
    runner:RegisterEvent("ADDON_ACTION_FORBIDDEN");
    runner:SetScript("OnUpdate", function(_, elapsed)
        run.frame = run.frame + 1;
        local state = StateKey();
        run.seconds[state] = run.seconds[state] + elapsed;
        for _, v in ipairs(variants) do
            if (v.frame) then
                local s = v.stats[state];
                s.frames = s.frames + 1;
                Step(v, s);
            end
        end
        if (run.seconds.unlocked >= SECONDS and run.seconds.locked >= SECONDS) then
            Finish();
        end
    end);
    print(TAG .. format("arming every %.3f s. Stand %d s out of combat and %d s in it.", duration, SECONDS,
        SECONDS));
end

runner:SetScript("OnEvent", function(_, event, addon, func)
    if (not run or addon ~= "DebindDev") then
        return;
    end
    local state = StateKey();
    local entry = {
        event = event,
        func = tostring(func),
        frame = run.frame,
        state = state,
        arming = arming and arming.key or false,
    };
    if (#run.blockedEvents < 50) then
        run.blockedEvents[#run.blockedEvents + 1] = entry;
    end
    -- Raised outside a `SetCooldown` it cannot be pinned on one variant, so both stop in this state.
    for _, v in ipairs(variants) do
        if (v.frame and (not arming or arming == v)) then
            local s = v.stats[state];
            s.blocked = s.blocked + 1;
            s.stopped = "blocked";
        end
    end
end);

SLASH_DEBINDDEVCD1 = "/debcd";
SlashCmdList.DEBINDDEVCD = function(msg)
    msg = strtrim(msg or "");
    if (msg == "stop") then
        Finish("stopped");
        return;
    end
    Start(tonumber(msg) or DEFAULT_DURATION);
end
