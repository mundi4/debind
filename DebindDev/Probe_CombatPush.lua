-- Probe_CombatPush.lua
-- Standing probe: is there always a moment, at every flip of `[combat]`, where the insecure side
-- can still push a value to the secure side, so the tail-key beat never has to ask it
-- (`trimming-the-tail-key-beat.md`)? **One flip without that moment and the answer is no**, so this
-- runs on every login with no command.
--
-- Two things have to hold:
--   1. At the moment of each event below, `SecureHandlerExecute` goes through, so a value written
--      then reaches the secure side. The lockdown is known to lag `PLAYER_REGEN_DISABLED`; this
--      checks that a body actually runs there.
--   2. Every frame where `[combat]` flips has one of those events in it while the lockdown is off.
--      `[combat]` also counts a pet fighting alone (`handing-the-rest-of-a-key-to-the-game.md`
--      6-4), which the REGEN events do not announce; `UNIT_FLAGS` on the pet may.
--
-- Nothing is saved while it holds. A flip with no push in its frame is a **miss**: it is said in red
-- in chat the moment it happens and that one moment goes into `DebindDevDB.combatPushMisses`. A load
-- that came up locked with no push anywhere in it is a miss too: the secure side then has no first
-- value until the fight ends.
--
--   /debcpu          this session's count and every saved miss
--   /debcpu reset    clear the saved misses
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cffff9900[CPU]|r ";
--- Events kept in memory for the moment a miss is saved, the ones just before it.
local CONTEXT = 12;

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

local recent = {};
local covered = 0;
local lastCombat;
--- Events seen in the current frame: whether one came with the lockdown off and the push went
--- through. `GetTime()` holds one value for a whole frame.
local frameTime, framePushed, frameEvents;

local function Remember(line)
    recent[#recent + 1] = format("%10.3f %s", GetTime(), line);
    if (#recent > CONTEXT) then
        table.remove(recent, 1);
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

--- The one record a miss leaves, and the chat line that says it.
local function Miss(what)
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.combatPushMisses = DebindDevDB.combatPushMisses or {};
    local misses = DebindDevDB.combatPushMisses;
    local context = {};
    for i = 1, #recent do
        context[i] = recent[i];
    end
    misses[#misses + 1] = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        class = select(2, UnitClass("player")),
        what = what,
        sample = Sample(),
        coveredBefore = covered,
        context = context,
    };
    print(TAG .. "|cnRED_FONT_COLOR:MISS: " .. what .. "|r");
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
    Remember(format("%-26s push=%-13s %s", kind, result, Sample()));
end);

probe:SetScript("OnUpdate", function()
    local combat = MacroCombat();
    if (combat == lastCombat) then
        return;
    end
    if (lastCombat ~= nil) then
        -- The flip shows here, after this frame's events; the ones that share its `GetTime()` are
        -- the ones that could have carried it.
        local sameFrame = frameTime == GetTime();
        local events = (sameFrame and frameEvents and #frameEvents > 0)
            and table.concat(frameEvents, ", ") or "none";
        Remember(format("[combat] %s -> %s  events this frame: %s", B(lastCombat), B(combat), events));
        if (sameFrame and framePushed) then
            covered = covered + 1;
        else
            Miss(format("[combat] %s -> %s with no push in its frame (events: %s)",
                B(lastCombat), B(combat), events));
        end
    end
    lastCombat = combat;
end);

--- **The load, watched on its own.** A reload in combat brings the addon up in combat. If no push
--- goes through anywhere in the load, the secure side has no first value for `[combat]` and no event
--- comes until the fight ends.
local loadFrame = CreateFrame("Frame");
local loadUpdates = 0;
local loadPushed, loadLocked = false, false;

local function LoadStep(step)
    local result = TryPush();
    if (result == "pushed") then
        loadPushed = true;
    elseif (result == "locked") then
        loadLocked = true;
    end
    Remember(format("load %-24s push=%-13s %s", step, result, Sample()));
end

LoadStep("file body");
loadFrame:RegisterEvent("ADDON_LOADED");
loadFrame:RegisterEvent("PLAYER_LOGIN");
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
loadFrame:SetScript("OnEvent", function(_, event, arg1)
    if (event == "ADDON_LOADED") then
        if (arg1 ~= "DebindDev") then
            return;
        end
        -- The whole-session logs the earlier form of this probe saved.
        if (DebindDevDB) then
            DebindDevDB.combatPush = nil;
            DebindDevDB.combatPushLoad = nil;
        end
        for _, watched in ipairs(EVENTS) do
            if (watched == "UNIT_FLAGS") then
                probe:RegisterUnitEvent(watched, "player", "pet");
            elseif (watched == "UNIT_PET") then
                probe:RegisterUnitEvent(watched, "player");
            else
                probe:RegisterEvent(watched);
            end
        end
        probe:Show();
    end
    LoadStep(event);
end);
-- The first frames after the load, until the lockdown has been seen either way for a while.
loadFrame:SetScript("OnUpdate", function()
    loadUpdates = loadUpdates + 1;
    if (loadUpdates <= 3 or loadUpdates == 30 or loadUpdates == 300) then
        LoadStep("OnUpdate " .. loadUpdates);
    end
    if (loadUpdates >= 300) then
        loadFrame:SetScript("OnUpdate", nil);
        if (loadLocked and not loadPushed) then
            Miss("this load came up locked and no push went through anywhere in it");
        end
    end
end);

SLASH_DEBINDCPU1 = "/debcpu";
SlashCmdList.DEBINDCPU = function(msg)
    msg = strlower(strtrim(msg or ""));
    local misses = DebindDevDB and DebindDevDB.combatPushMisses or {};
    if (msg == "reset") then
        if (DebindDevDB) then
            DebindDevDB.combatPushMisses = nil;
        end
        print(TAG .. "saved misses cleared");
        return;
    end
    print(TAG .. format("this session: %d flips covered. saved misses: %d", covered, #misses));
    for i, miss in ipairs(misses) do
        print(TAG .. format("miss %d  %s  %s  %s", i, miss.at, miss.class, miss.what));
    end
end;
