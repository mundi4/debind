-- Probe_CombatPush.lua
-- Standing probe: if the insecure side pushed `[combat]` to the secure side by the rule
-- `trimming-the-tail-key-beat.md` 3-3 sets out, would the secure side ever hold the wrong value?
-- **One frame where it would and the answer is no**, so this runs on every login with no command.
--
-- The rule, as simulated here (a push is a real `SecureHandlerExecute`, read back):
--   - `PLAYER_REGEN_DISABLED` pushes true by the event's name, without asking `[combat]`.
--   - `PLAYER_REGEN_ENABLED`, `UNIT_FLAGS` (player, pet) and `UNIT_PET` push what `[combat]` answers
--     at that moment.
--   - Every frame the lockdown is off, the OnUpdate pushes `[combat]` if it differs from what was
--     last pushed. This is what carries a pet's fight, which the REGEN events do not announce.
--   - The load pushes a first value; until a push lands the beat would keep parsing, so nothing is
--     judged before it.
--
-- **The verdict is what the secure side would hold, not whether a push went through.** An event
-- that lands in the flip's frame ahead of the flip pushes the old value; counting that push as
-- covering the flip would pass the one case the rule exists to catch.
--
-- Misses, each kept with the events just before it (`DebindDevDB.combatPush.misses`):
--   held     the secure side would hold a value other than `[combat]`'s, and for how many frames
--   locked   a locked frame where `[combat]` is false (the lockdown follows the player, `[combat]`
--            is player or pet, so this should never happen)
--   regen    a `PLAYER_REGEN_DISABLED` push that did not go through
--   early    a `PLAYER_REGEN_DISABLED` that came with `[combat]` still false: the push is right by
--            the event's name, so this tests that the window is where Blizzard means it to be
--   load     a load that came up locked with no push anywhere in it (the fallback covers it; this
--            says per client whether the fallback is ever used)
-- `seen` counts how often each situation came up, so "never missed" can be told from "never
-- happened".
--
--   /debcpu          the counts and every saved miss
--   /debcpu reset    start over

local TAG = "|cffff9900[CPU]|r ";
--- Bumped when what a miss means changes, so an older store is started over rather than read.
local VERSION = "cpu-2";
--- Events kept in memory for the moment a miss is saved, the ones just before it.
local CONTEXT = 12;
local LIMIT = 500;

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

local store;
local recent = {};
--- What the secure side would hold now: nil until the first push lands.
local held;
local heldApartSince, heldApartMiss;
local lockedApart = false;
local frameIndex = 0;

local function Remember(line)
    recent[#recent + 1] = format("%10.3f %s", GetTime(), line);
    if (#recent > CONTEXT) then
        table.remove(recent, 1);
    end
end

local function Sample()
    return format("[combat]=%s held=%s player=%s pet=%s petExists=%s lockdown=%s", B(MacroCombat()),
        held == nil and "-" or B(held), B(UnitAffectingCombat("player")), B(UnitAffectingCombat("pet")),
        B(UnitExists("pet")), B(InCombatLockdown()));
end

local function Seen(what)
    if (store) then
        store.seen[what] = (store.seen[what] or 0) + 1;
    end
end

local function Miss(kind, what)
    if (not store or #store.misses >= LIMIT) then
        return nil;
    end
    local context = {};
    for i = 1, #recent do
        context[i] = recent[i];
    end
    local miss = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        class = select(2, UnitClass("player")),
        kind = kind,
        what = what,
        sample = Sample(),
        context = context,
    };
    store.misses[#store.misses + 1] = miss;
    print(TAG .. "|cnRED_FONT_COLOR:MISS " .. kind .. ": " .. what .. "|r");
    return miss;
end

--- Pushes `value` once, out of lockdown only (in it the call would be blocked and blamed), and reads
--- the counter back to see that the body ran. A landed push is what the secure side now holds.
local function Push(value)
    if (InCombatLockdown()) then
        return "locked";
    end
    local before = header:GetAttribute("pushed") or 0;
    local ok = pcall(SecureHandlerExecute, header, PUSH);
    local after = header:GetAttribute("pushed") or 0;
    if (ok and after == before + 1) then
        held = value;
        Seen("push landed");
        return "pushed";
    end
    return ok and "ran-no-effect" or "error";
end

local probe = CreateFrame("Frame");
probe:Hide();

probe:SetScript("OnEvent", function(_, event, unit)
    if (event == "UNIT_FLAGS" and unit ~= "player" and unit ~= "pet") then
        return;
    end
    local kind = unit and format("%s(%s)", event, unit) or event;
    local result;
    if (event == "PLAYER_REGEN_DISABLED") then
        Seen("PLAYER_REGEN_DISABLED");
        local combat = MacroCombat();
        result = Push(true);
        Remember(format("%-26s push=%-13s %s", kind, result, Sample()));
        if (result ~= "pushed") then
            Miss("regen", "PLAYER_REGEN_DISABLED push " .. result);
        end
        if (not combat) then
            Miss("early", "PLAYER_REGEN_DISABLED came with [combat] still false");
        end
        return;
    end
    result = Push(MacroCombat());
    Remember(format("%-26s push=%-13s %s", kind, result, Sample()));
end);

probe:SetScript("OnUpdate", function()
    frameIndex = frameIndex + 1;
    local combat = MacroCombat();
    local locked = InCombatLockdown();
    if (not locked and held ~= nil and combat ~= held) then
        local result = Push(combat);
        Remember(format("%-26s push=%-13s %s", "OnUpdate", result, Sample()));
    end
    if (locked) then
        Seen("locked frame");
        if (not combat and not lockedApart) then
            lockedApart = true;
            Miss("locked", "a locked frame with [combat] false");
        elseif (combat) then
            lockedApart = false;
        end
    else
        lockedApart = false;
    end
    if (held ~= nil) then
        if (held ~= combat) then
            if (not heldApartSince) then
                heldApartSince = frameIndex;
                heldApartMiss = Miss("held", format("the secure side would hold %s while [combat] is %s",
                    B(held), B(combat)));
            end
        elseif (heldApartSince) then
            if (heldApartMiss) then
                heldApartMiss.frames = frameIndex - heldApartSince;
            end
            heldApartSince, heldApartMiss = nil, nil;
        end
    end
end);

--- **The load, watched on its own.** A reload in combat brings the addon up in combat. If no push
--- goes through anywhere in the load, the secure side has no first value and the beat keeps parsing.
local loadFrame = CreateFrame("Frame");
local loadUpdates = 0;
local loadPushed, loadLocked = false, false;

local function LoadStep(step)
    local result = Push(MacroCombat());
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
loadFrame:RegisterEvent("PLAYER_LOGOUT");
loadFrame:SetScript("OnEvent", function(_, event, arg1)
    if (event == "ADDON_LOADED") then
        if (arg1 ~= "DebindDev") then
            return;
        end
        DebindDevDB = DebindDevDB or {};
        -- What the earlier forms of this probe saved.
        DebindDevDB.combatPushMisses = nil;
        DebindDevDB.combatPushLoad = nil;
        store = DebindDevDB.combatPush;
        if (type(store) ~= "table" or store.version ~= VERSION) then
            store = { version = VERSION, since = date("%Y-%m-%d %H:%M:%S"), misses = {}, seen = {} };
            DebindDevDB.combatPush = store;
        end
        probe:RegisterEvent("PLAYER_REGEN_DISABLED");
        probe:RegisterEvent("PLAYER_REGEN_ENABLED");
        probe:RegisterUnitEvent("UNIT_FLAGS", "player", "pet");
        probe:RegisterUnitEvent("UNIT_PET", "player");
        probe:Show();
    elseif (event == "PLAYER_LOGOUT") then
        -- A held-apart run still open at logout would otherwise keep no length.
        if (heldApartMiss) then
            heldApartMiss.frames = frameIndex - heldApartSince;
            heldApartMiss.openAtLogout = true;
        end
        return;
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
        Seen(loadLocked and "load came up locked" or "load came up unlocked");
        if (loadLocked and not loadPushed) then
            Miss("load", "this load came up locked and no push went through anywhere in it");
        end
    end
end);

SLASH_DEBINDCPU1 = "/debcpu";
SlashCmdList.DEBINDCPU = function(msg)
    msg = strlower(strtrim(msg or ""));
    if (msg == "reset") then
        DebindDevDB.combatPush = nil;
        store = { version = VERSION, since = date("%Y-%m-%d %H:%M:%S"), misses = {}, seen = {} };
        DebindDevDB.combatPush = store;
        print(TAG .. "started over");
        return;
    end
    if (not store) then
        print(TAG .. "not started");
        return;
    end
    print(TAG .. format("%s since %s, %d misses", store.version, store.since, #store.misses));
    for what, n in pairs(store.seen) do
        print(TAG .. format("  seen %s: %d", what, n));
    end
    for i, miss in ipairs(store.misses) do
        print(TAG .. format("miss %d  %s  %s  %s  %s%s", i, miss.at, miss.class, miss.kind, miss.what,
            miss.frames and format(" (%d frames)", miss.frames) or ""));
    end
end
