-- Probe_PetSwap.lua
-- One-shot probe: when a summoned pet appears, is `UnitCreatureFamily("pet")` already there, or
-- does it come later, and on which event? Two summons disagreed: an Imp appeared with `family=nil`
-- on its `UNIT_PET` and got its family 0.155s later with `UNIT_NAME_UPDATE(pet)`,
-- `UNIT_CLASSIFICATION_CHANGED(pet)`, `PET_BAR_UPDATE` and `PET_UI_UPDATE`; a Voidwalker had its
-- family on `UNIT_PET` and none of those four came. The guess under test is that the first summon
-- of a family after login has nothing cached.
--
-- No slash command. It records from load to logout into `DebindDevDB.petSwap`, one entry per
-- session, the last `KEEP` sessions kept. Each line is
--   <frame> <GetTime> <event(args) or (sample)> | <values>
-- and a `(sample)` line is written only on a frame where a value moved.
--
-- Answer found, delete the file and its TOC line.

local KEEP = 5;

--- Per session. Lines are kept only on a change, so this guards against something flapping every
--- frame rather than budgeting an ordinary session.
local LIMIT = 20000;

local EVENTS = {
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PET_BAR_UPDATE",
    "PET_UI_UPDATE",
    "PET_INFO_UPDATE",
    "PET_DISMISS_START",
    "PET_SPECIALIZATION_CHANGED",
    "PET_SPELL_POWER_UPDATE",
    "PET_BAR_UPDATE_USABLE",
    "LOCALPLAYER_PET_RENAMED",
    "SPELLS_CHANGED",
};

local PET_UNIT_EVENTS = {
    "UNIT_NAME_UPDATE",
    "UNIT_MODEL_CHANGED",
    "UNIT_PORTRAIT_UPDATE",
    "UNIT_DISPLAYPOWER",
    "UNIT_FLAGS",
    "UNIT_CLASSIFICATION_CHANGED",
};

--- The summon's own cast, so the log shows where each summon starts.
local PLAYER_UNIT_EVENTS = {
    "UNIT_PET",
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
};

local CONDITIONALS = { "[pet]", "[pet:imp]", "[pet:voidwalker]", "[pet:succubus]" };

local function Show(value)
    if (issecretvalue and issecretvalue(value)) then
        return "S";
    end
    return tostring(value);
end

--- `SecureCmdOptionParse` answers the option text (`""` here) when a clause matched and nil when
--- none did, so its truthiness is the conditional's answer.
local function Sample()
    local parts = { format("exists=%s family=%s name=%s",
        Show(UnitExists("pet")), Show(UnitCreatureFamily("pet")), Show(UnitName("pet"))) };
    for i = 1, #CONDITIONALS do
        parts[#parts + 1] = format("%s=%s", CONDITIONALS[i],
            SecureCmdOptionParse(CONDITIONALS[i]) ~= nil and "T" or "F");
    end
    return table.concat(parts, " ");
end

--- Bumped once per `OnUpdate`, which runs exactly once a frame, so an event line carrying N arrived
--- after sample N. Whether it shares a frame with sample N or N+1 is read off `GetTime()`, which
--- holds one value for a whole frame.
local frameIndex = 0;

--- Filled from load, before `DebindDevDB` exists; `ADDON_LOADED` hands it to the saved table.
local lines = {};
local last;

local function Record(kind, sample)
    if (#lines >= LIMIT) then
        return;
    end
    lines[#lines + 1] = format("%d %.3f %s | %s", frameIndex, GetTime(), kind, sample);
end

local probe = CreateFrame("Frame");

probe:SetScript("OnUpdate", function()
    frameIndex = frameIndex + 1;
    local sample = Sample();
    if (sample ~= last) then
        last = sample;
        Record("(sample)", sample);
    end
end);

probe:SetScript("OnEvent", function(_, event, ...)
    if (event == "ADDON_LOADED") then
        if (... ~= "DebindDev") then
            return;
        end
        probe:UnregisterEvent("ADDON_LOADED");
        DebindDevDB = DebindDevDB or {};
        local sessions = DebindDevDB.petSwap;
        -- The slash-command version of this probe saved a single log here, not a list of sessions.
        if (type(sessions) ~= "table" or sessions.lines ~= nil) then
            sessions = {};
            DebindDevDB.petSwap = sessions;
        end
        sessions[#sessions + 1] = { at = date("%Y-%m-%d %H:%M:%S"), lines = lines };
        while (#sessions > KEEP) do
            table.remove(sessions, 1);
        end
        return;
    end
    local kind = event;
    local n = select("#", ...);
    if (n > 0) then
        local args = {};
        for i = 1, math.min(n, 3) do
            args[i] = Show((select(i, ...)));
        end
        kind = format("%s(%s)", event, table.concat(args, ","));
    end
    Record(kind, Sample());
end);

probe:RegisterEvent("ADDON_LOADED");
for _, event in ipairs(EVENTS) do
    probe:RegisterEvent(event);
end
for _, event in ipairs(PET_UNIT_EVENTS) do
    probe:RegisterUnitEvent(event, "pet");
end
for _, event in ipairs(PLAYER_UNIT_EVENTS) do
    probe:RegisterUnitEvent(event, "player");
end
