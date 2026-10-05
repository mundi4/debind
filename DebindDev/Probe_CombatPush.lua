-- Probe_CombatPush.lua
-- One-shot probe: can the insecure side keep `[combat]` current on the secure side by events, so
-- the tail-key beat never has to ask it (`trimming-the-tail-key-beat.md`)?
--
-- Two things have to hold:
--   1. At the moment of each event below, `SecureHandlerExecute` goes through, so a value written
--      then reaches the secure side. The lockdown is known to lag `PLAYER_REGEN_DISABLED`; this
--      checks that a body actually runs there.
--   2. Every frame where `[combat]` flips has one of those events in it while the lockdown is off.
--      `[combat]` also counts a pet fighting alone (`handing-the-rest-of-a-key-to-the-game.md`
--      6-4), which the REGEN events do not announce; `UNIT_FLAGS` on the pet may.
--
--   /debcpu          start (wipes the previous log)
--   /debcpu stop     stop, print the summary
--   /debcpu show     print the saved log
--
-- What to do while it runs, on a pet class: fight a dummy with the player; stop and let the pet
-- keep fighting a while; `/petattack` with the player idle so the pet fights alone first, then
-- join; dismiss the pet while it fights; summon it again. Then /debcpu stop and /reload.
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cffff9900[CPU]|r ";
local LIMIT = 4000;

local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_FLAGS", "UNIT_PET" };

local header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate");
local PUSH = [[self:SetAttribute("pushed", (self:GetAttribute("pushed") or 0) + 1)]];

local function B(v)
    if (issecretvalue and issecretvalue(v)) then
        return "S";
    end
    return v and "T" or "F";
end

local function MacroCombat()
    return SecureCmdOptionParse("[combat]") ~= nil;
end

local log, running;
local frameIndex = 0;
local lastCombat;
--- Events seen in the current frame: whether one came with the lockdown off and the push went
--- through. `GetTime()` holds one value for a whole frame.
local frameTime, framePushed, frameEvents;
local stats;

local function Record(line)
    if (#log < LIMIT) then
        log[#log + 1] = format("%6d %10.3f %s", frameIndex, GetTime(), line);
    end
end

--- Pushes once, out of lockdown only (in it the call would be blocked and blamed), and reads the
--- counter back to see that the body ran.
local function TryPush()
    if (InCombatLockdown()) then
        return "locked";
    end
    local before = header:GetAttribute("pushed") or 0;
    local ok = pcall(SecureHandlerExecute, header, PUSH);
    local after = header:GetAttribute("pushed") or 0;
    if (ok and after == before + 1) then
        return "pushed";
    end
    return ok and "ran-no-effect" or "error";
end

local function Sample()
    return format("[combat]=%s player=%s pet=%s petExists=%s lockdown=%s", B(MacroCombat()),
        B(UnitAffectingCombat("player")), B(UnitAffectingCombat("pet")), B(UnitExists("pet")),
        B(InCombatLockdown()));
end

local probe = CreateFrame("Frame");
probe:Hide();

probe:SetScript("OnEvent", function(_, event, unit)
    if (event == "UNIT_FLAGS" and unit ~= "player" and unit ~= "pet") then
        return;
    end
    if (frameTime ~= GetTime()) then
        frameTime, framePushed, frameEvents = GetTime(), false, {};
    end
    local result = TryPush();
    if (result == "pushed") then
        framePushed = true;
    end
    local kind = unit and format("%s(%s)", event, unit) or event;
    frameEvents[#frameEvents + 1] = kind .. ":" .. result;
    stats.push[result] = (stats.push[result] or 0) + 1;
    stats.byEvent[kind .. ":" .. result] = (stats.byEvent[kind .. ":" .. result] or 0) + 1;
    Record(format("%-26s push=%-13s %s", kind, result, Sample()));
end);

probe:SetScript("OnUpdate", function()
    frameIndex = frameIndex + 1;
    local combat = MacroCombat();
    if (combat ~= lastCombat) then
        if (lastCombat ~= nil) then
            -- The flip shows here, after this frame's events; the ones that share its `GetTime()`
            -- are the ones that could have carried it.
            local covered = frameTime == GetTime() and framePushed;
            local events = (frameTime == GetTime() and frameEvents and #frameEvents > 0)
                and table.concat(frameEvents, ", ") or "none";
            if (covered) then
                stats.covered = stats.covered + 1;
            else
                stats.uncovered = stats.uncovered + 1;
            end
            Record(format("[combat] %s -> %s  %s  events this frame: %s", B(lastCombat), B(combat),
                covered and "COVERED" or "NOT COVERED", events));
        end
        lastCombat = combat;
    end
end);

local function Summary()
    local lines = {
        format("[combat] flips: %d covered by a push in the same frame, %d not", stats.covered, stats.uncovered),
    };
    for result, n in pairs(stats.push) do
        lines[#lines + 1] = format("push %s: %d", result, n);
    end
    for key, n in pairs(stats.byEvent) do
        lines[#lines + 1] = format("  %s: %d", key, n);
    end
    return lines;
end

local function Start()
    DebindDevDB = DebindDevDB or {};
    log = {};
    stats = { covered = 0, uncovered = 0, push = {}, byEvent = {} };
    DebindDevDB.combatPush = { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()),
        class = select(2, UnitClass("player")), lines = log };
    frameIndex, lastCombat, frameTime = 0, nil, nil;
    running = true;
    for _, event in ipairs(EVENTS) do
        if (event == "UNIT_FLAGS") then
            probe:RegisterUnitEvent(event, "player", "pet");
        elseif (event == "UNIT_PET") then
            probe:RegisterUnitEvent(event, "player");
        else
            probe:RegisterEvent(event);
        end
    end
    probe:Show();
    Record("start  " .. Sample());
    print(TAG .. "started");
end

local function Stop()
    probe:UnregisterAllEvents();
    probe:Hide();
    running = false;
    local summary = Summary();
    DebindDevDB.combatPush.summary = summary;
    for _, line in ipairs(summary) do
        print(TAG .. line);
    end
    print(TAG .. "stopped. /reload to write it out.");
end

local function Show()
    local saved = DebindDevDB and DebindDevDB.combatPush;
    if (not saved or not saved.lines) then
        print(TAG .. "no log");
        return;
    end
    for _, line in ipairs(saved.lines) do
        print(line);
    end
    for _, line in ipairs(saved.summary or {}) do
        print(TAG .. line);
    end
end

--- **The load after a reload, recorded on its own, without the slash command.** A reload in combat
--- brings the addon up in combat. If no push goes through anywhere in the load, the secure side has
--- no first value for `[combat]` and no event comes until the fight ends. Each load step logs the
--- lockdown, `[combat]` and whether a push went through, into `DebindDevDB.combatPushLoad`.
local loadLines = {};
local loadFrame = CreateFrame("Frame");
local loadUpdates = 0;

local function LoadRecord(step)
    loadLines[#loadLines + 1] = format("%10.3f %-24s push=%-13s %s", GetTime(), step, TryPush(), Sample());
end

LoadRecord("file body");
loadFrame:RegisterEvent("ADDON_LOADED");
loadFrame:RegisterEvent("PLAYER_LOGIN");
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
loadFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
loadFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
loadFrame:SetScript("OnEvent", function(_, event, arg1)
    if (event == "ADDON_LOADED") then
        if (arg1 ~= "DebindDev") then
            return;
        end
        -- The saved table is in place from here on; this load's lines replace the last load's.
        DebindDevDB = DebindDevDB or {};
        DebindDevDB.combatPushLoad = { at = date("%Y-%m-%d %H:%M:%S"), lines = loadLines };
    end
    LoadRecord(event);
end);
-- The first frames after the load, until the lockdown has been seen either way for a while.
loadFrame:SetScript("OnUpdate", function()
    loadUpdates = loadUpdates + 1;
    if (loadUpdates <= 3 or loadUpdates == 30 or loadUpdates == 300) then
        LoadRecord("OnUpdate " .. loadUpdates);
    end
    if (loadUpdates >= 300) then
        loadFrame:SetScript("OnUpdate", nil);
    end
end);

SLASH_DEBINDCPU1 = "/debcpu";
SlashCmdList.DEBINDCPU = function(msg)
    msg = strlower(strtrim(msg or ""));
    if (msg == "stop") then
        Stop();
    elseif (msg == "show") then
        Show();
    else
        if (running) then
            Stop();
        end
        Start();
    end
end;
