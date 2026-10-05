-- Probe_CombatPet.lua
-- One-shot probe: does the macro conditional `[combat]` read the player alone, or the player or the
-- pet the way the restricted `PlayerInCombat()` does (`UnitAffectingCombat("player") or
-- UnitAffectingCombat("pet")`)?
--
-- The `combat` axis is measured with `PlayerInCombat()`, and the binding loop of
-- `handing-the-rest-of-a-key-to-the-game.md` §2-5 re-parses a computed switch only when an axis its
-- expression reads has moved. If `[combat]` is player-only, a pet that enters combat first and a
-- player who follows flips `[combat]` without moving the axis. What `[combat]` reads is decided in
-- C, so only the client can say.
--
--   /debcp          start (wipes the previous log)
--   /debcp stop     stop
--   /debcp show     print the log, this session's or the one saved before a reload
--
-- The run: on a pet class, `/petattack` a dummy while the player does nothing; then the player
-- joins; then the player drops combat while the pet keeps fighting, if that can be arranged; then
-- dismiss the pet mid-fight. The answer is in the lines where `pet=T player=F`.
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cffff9900[CP]|r ";

--- Lines are kept only on a change, so this is a guard against something flapping every frame, not
--- a budget for an ordinary run.
local LIMIT = 4000;

local function Mark(value)
    if (issecretvalue and issecretvalue(value)) then
        return "S";
    end
    if (value == nil) then
        return "-";
    end
    return value and "T" or "F";
end

--- `SecureCmdOptionParse` answers the option text (`""` here) when a clause matched and nil when
--- none did, so its truthiness is the conditional's answer.
local function Sample()
    return format("player=%s pet=%s petExists=%s [combat]=%s lockdown=%s",
        Mark(UnitAffectingCombat("player")),
        Mark(UnitAffectingCombat("pet")),
        Mark(UnitExists("pet")),
        Mark(SecureCmdOptionParse("[combat]") ~= nil),
        Mark(InCombatLockdown()));
end

--- Bumped once per `OnUpdate`, which runs exactly once a frame, so an event line carrying N arrived
--- after sample N. Whether it shares a frame with sample N or N+1 is read off `GetTime()`, which
--- holds one value for a whole frame. Each event line carries its own sample, taken in the handler.
local frameIndex = 0;

local log;
local last;
local running = false;

local function Record(kind, sample)
    if (#log >= LIMIT) then
        return;
    end
    local line = format("%5d %10.3f %-28s %s", frameIndex, GetTime(), kind, sample);
    log[#log + 1] = line;
    print(TAG .. line);
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
probe:Hide();

probe:SetScript("OnEvent", function(_, event, unit)
    local kind = event;
    if (unit ~= nil) then
        kind = format("%s(%s)", event, tostring(unit));
    end
    Record(kind, Sample());
end);

local function Start()
    -- Not before login: `DebindDevDB` is replaced by the saved table on ADDON_LOADED. A slash
    -- command cannot run that early, so writing straight into it is safe here.
    DebindDevDB = DebindDevDB or {};
    log = {};
    DebindDevDB.combatPet = { at = date("%Y-%m-%d %H:%M:%S"), class = select(2, UnitClass("player")), lines = log };
    frameIndex = 0;
    last = nil;
    running = true;

    probe:RegisterEvent("PLAYER_REGEN_DISABLED");
    probe:RegisterEvent("PLAYER_REGEN_ENABLED");
    probe:RegisterUnitEvent("UNIT_FLAGS", "player", "pet");
    -- Not asked for, but it dates the dismissal: the step where `petExists` goes false mid-fight.
    probe:RegisterUnitEvent("UNIT_PET", "player");
    probe:Show();
    print(TAG .. "started. columns: frame  GetTime  event  values");
end

local function Stop()
    probe:UnregisterAllEvents();
    probe:Hide();
    running = false;
    print(TAG .. format("stopped, %d lines in DebindDevDB.combatPet", log and #log or 0));
end

local function Show()
    local saved = DebindDevDB and DebindDevDB.combatPet;
    if (not saved or not saved.lines or #saved.lines == 0) then
        print(TAG .. "no log");
        return;
    end
    print(TAG .. format("%s %s, %d lines%s", saved.at or "?", saved.class or "?", #saved.lines,
        running and " (running)" or ""));
    for i = 1, #saved.lines do
        print(saved.lines[i]);
    end
end

SLASH_DEBINDCP1 = "/debcp";
SlashCmdList.DEBINDCP = function(msg)
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
