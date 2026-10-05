-- Probe_GateWords.lua
-- Standing probe, kept for the next time a measurement has to be held against a macro conditional
-- (owner, 2026-10-05): for each macro conditional word that `trimming-the-tail-key-beat.md` §3-2
-- maps to a restricted-environment API, does the word's answer move exactly when that API's does?
--
-- A computed switch is re-parsed only when a column its expression reads moves (§3-1). A word whose
-- macro answer can flip while the column stays put freezes the switch on its last answer, so the
-- mapping has to hold in both directions. Only the client can say.
--
-- **Runs on every login with no command**, so nobody has to remember to start it before the scene
-- that answers a question (owner, 2026-10-05: the same pairs had been run by hand three times in one
-- day). Each frame every pair is sampled once, the macro side through `SecureCmdOptionParse` and the
-- API side through the same call the restricted environment makes (`RestrictedEnvironment.lua`; the
-- ENV wrappers are copied as written). Every roster unit (party1-4, raid1-40, their pets, player,
-- pet) is looked at once after each roster, pet or world change.
--
-- Kept in `DebindDevDB.gateWordsStanding`, across sessions until `VERSION` changes:
--   stats   per pair, how often each side moved (so "never disagreed" can be told from "never
--           moved"), disagreements, the longest in frames, moves on one side only
--   misses  each disagreement once it closes, with its context: a loading screen, a world event
--           in the last two seconds, a unit that is the player, a unit that is a ghost
--   seen    how often each of those contexts came up at all
--
--   /debgw          the tallies
--   /debgw reset    start the store over
--   /debgw time     what one `IsSubmerged()` and one `[swimming]` parse cost (out of combat)
--   /debgw bench    the wider survey: table reads, APIs, parses of every shape. Every run is kept
--                   with the situation it ran in; in combat only the insecure column is measured
--
-- A pair that disagrees for one frame at a change is a lag; one that disagrees for longer, or moves
-- on one side only, is a mapping that does not hold.

local TAG = "|cffff9900[GW]|r ";

--- The cap on kept misses, against a pair that flaps every frame for a whole session.
local LIMIT = 8000;

local function Mark(value)
    if (issecretvalue and issecretvalue(value)) then
        return "S";
    end
    if (value == nil) then
        return "-";
    end
    if (value == true) then
        return "T";
    elseif (value == false) then
        return "F";
    end
    return tostring(value);
end

local function Bool(value)
    if (issecretvalue and issecretvalue(value)) then
        return "S";
    end
    return value and "T" or "F";
end

--- The macro side: "T" or "F" for one condition group.
local function Macro(conditions)
    return SecureCmdOptionParse(conditions .. " T; F") or "-";
end

--- The macro side for a word that takes a number: the first `n` in `0..max` whose clause matches.
local function MacroNumber(word, max)
    local parts = {};
    for n = 0, max do
        parts[#parts + 1] = format("[%s:%d] %d", word, n, n);
    end
    parts[#parts + 1] = "none";
    return SecureCmdOptionParse(table.concat(parts, "; ")) or "-";
end

-- The ENV wrappers of `RestrictedEnvironment.lua`, as written there.
local function PlayerIsChanneling()
    return (UnitChannelInfo("player") ~= nil);
end
local function PlayerInCombat()
    return UnitAffectingCombat("player") or UnitAffectingCombat("pet");
end
local function PlayerInGroup()
    return (IsInRaid() and "raid") or (IsInGroup() and "party");
end
local function EnvUnitHasVehicleUI(unit)
    unit = tostring(unit);
    return UnitHasVehicleUI(unit) and
        (UnitCanAssist("player", unit:gsub("(%D+)(%d*)", "%1pet%2")) and true) or
        (UnitCanAssist("player", unit) and false);
end

local PAIRS = {
    { "combat", function() return Macro("[combat]") end, function() return Bool(PlayerInCombat()) end },
    { "advflyable", function() return Macro("[advflyable]") end, function() return Bool(IsAdvancedFlyableArea()) end },
    { "flyable", function() return Macro("[flyable]") end, function() return Bool(IsFlyableArea()) end },
    { "flying", function() return Macro("[flying]") end, function() return Bool(IsFlying()) end },
    { "indoors", function() return Macro("[indoors]") end, function() return Bool(IsIndoors()) end },
    { "outdoors", function() return Macro("[outdoors]") end, function() return Bool(IsOutdoors()) end },
    { "mounted", function() return Macro("[mounted]") end, function() return Bool(IsMounted()) end },
    { "stealth", function() return Macro("[stealth]") end, function() return Bool(IsStealthed()) end },
    { "swimming", function() return Macro("[swimming]") end, function() return Bool(IsSwimming()) end },
    -- `IsSwimming()` leaves the water 13-14 frames ahead of `[swimming]` (measured 2026-10-05). The
    -- restricted environment has `IsSubmerged` as well.
    { "swimming~submerged", function() return Macro("[swimming]") end, function() return Bool(IsSubmerged()) end },
    { "swimming~either", function() return Macro("[swimming]") end,
        function() return Bool(IsSwimming() or IsSubmerged()) end },
    { "canexitvehicle", function() return Macro("[canexitvehicle]") end, function() return Bool(CanExitVehicle()) end },
    { "channeling", function() return Macro("[channeling]") end, function() return Bool(PlayerIsChanneling()) end },
    { "form", function() return MacroNumber("form", 10) end, function() return Mark(GetShapeshiftForm()) end },
    { "bar", function() return MacroNumber("bar", 10) end, function() return Mark(C_ActionBar.GetActionBarPage()) end },
    -- No bonus bar is offset 0. `[bonusbar:0]` does not match it and bare `[nobonusbar]` is always
    -- true; `[nobonusbar:1/2/3/4/5]` answered right (owner, 2026-10-05).
    { "bonusbar", function()
        return SecureCmdOptionParse("[nobonusbar:1/2/3/4/5] 0") or MacroNumber("bonusbar", 10);
    end,
        function() return Mark(C_ActionBar.GetBonusBarOffset()) end },
    { "group", function()
        return SecureCmdOptionParse("[group:raid] raid; [group:party] party; none") or "-";
    end, function() return PlayerInGroup() or "none" end },
    { "extrabar", function() return Macro("[extrabar]") end, function() return Bool(C_ActionBar.HasExtraActionBar()) end },
    { "overridebar", function() return Macro("[overridebar]") end,
        function() return Bool(C_ActionBar.HasOverrideActionBar()) end },
    { "shapeshift", function() return Macro("[shapeshift]") end,
        function() return Bool(C_ActionBar.HasTempShapeshiftActionBar()) end },
    -- The `specialbar` column's measurement against the words Keys Given Back already reads
    -- (`GIVE_BACK_REPLACED_BAR`, `GIVE_BACK_PET_BATTLE`).
    { "specialbar", function() return Macro("[vehicleui][possessbar][overridebar][shapeshift][petbattle]") end,
        function()
            return Bool(C_ActionBar.HasVehicleActionBar() or C_ActionBar.HasOverrideActionBar()
                or C_ActionBar.HasTempShapeshiftActionBar() or SecureCmdOptionParse("[petbattle]"));
        end },
    -- No API was named for these two. The right side is every candidate at once, to read off later.
    { "vehicleui", function() return Macro("[vehicleui]") end, function()
        return format("env=%s vehicleBar=%s", Bool(EnvUnitHasVehicleUI("player")),
            Bool(C_ActionBar.HasVehicleActionBar()));
    end },
    { "possessbar", function() return Macro("[possessbar]") end, function()
        return format("bonusBar=%s bonusIndex=%s override=%s vehicleBar=%s",
            Bool(C_ActionBar.HasBonusActionBar()), Mark(C_ActionBar.GetBonusBarIndex()),
            Bool(C_ActionBar.HasOverrideActionBar()), Bool(C_ActionBar.HasVehicleActionBar()));
    end },
    { "mod", function() return Macro("[mod]") end, function() return Bool(IsModifierKeyDown()) end },
    { "mod:shift", function() return Macro("[mod:shift]") end, function() return Bool(IsShiftKeyDown()) end },
    { "mod:ctrl", function() return Macro("[mod:ctrl]") end, function() return Bool(IsControlKeyDown()) end },
    { "mod:alt", function() return Macro("[mod:alt]") end, function() return Bool(IsAltKeyDown()) end },
    -- What a beat with no press answers. Nothing to compare it with.
    { "btn", function()
        return SecureCmdOptionParse("[btn:1] 1; [btn:2] 2; [btn:3] 3; [btn:4] 4; [btn:5] 5; none") or "-";
    end, nil },
    -- `[pet:<x>]` asked with what the summary answers now, so a swap shows on both sides.
    { "pet", function()
        local family, name = UnitCreatureFamily("pet"), UnitName("pet");
        local byFamily = family and Macro("[pet:" .. family .. "]") or "-";
        local byName = name and Macro("[pet:" .. name .. "]") or "-";
        return format("[pet]=%s family=%s name=%s", Macro("[pet]"), byFamily, byName);
    end, function()
        local family, name = UnitCreatureFamily("pet"), UnitName("pet");
        local summary = (family ~= nil or name ~= nil) and "T" or "F";
        return format("summary=%s family=%s name=%s", summary, Mark(family), Mark(name));
    end },
};

local UNIT_WORDS = {
    { "exists", function(u) return Bool(UnitExists(u)) end },
    { "help", function(u) return Bool(UnitCanAssist("player", u)) end },
    { "harm", function(u) return Bool(UnitCanAttack("player", u)) end },
    { "dead", function(u) return Bool(UnitIsDead(u) or UnitIsGhost(u)) end },
    { "party", function(u) return Bool(UnitPlayerOrPetInParty(u)) end },
    { "raid", function(u) return Bool(UnitPlayerOrPetInRaid(u)) end },
    { "unithasvehicleui", function(u) return Bool(EnvUnitHasVehicleUI(u)) end },
};
-- `player` is here for how long its words stay apart in a vehicle; the roster look only catches
-- one moment a second after the change. In a vehicle `[@player,exists]` does not match the whole
-- ride while `[@vehicle,exists]` does (owner, 2026-10-05), so `vehicle` is watched beside it.
for _, unit in ipairs({ "target", "focus", "mouseover", "pet", "player", "vehicle" }) do
    for _, word in ipairs(UNIT_WORDS) do
        local conditions = format("[@%s,%s]", unit, word[1]);
        local api = word[2];
        PAIRS[#PAIRS + 1] = { unit .. "," .. word[1], function() return Macro(conditions) end,
            function() return api(unit) end };
    end
end

--- Bumped whenever the pairs change, so a store written by another set of pairs is started over
--- rather than read as this one's, and so a result can be told from a stale client.
local VERSION = "gw-standing-1";

local frameIndex = 0;
local store;
local lastMacro, lastApi = {}, {};
--- Per pair: whether the two sides disagree now, since which frame, and with which context.
local apart, apartSince, apartContext = {}, {}, {};
local loading = false;
--- The last world event and when it came. A disagreement within `WORLD_WINDOW` seconds of one
--- carries its name, so a zone change can be told from a mapping that does not hold.
local worldEvent, worldEventAt;
local WORLD_WINDOW = 2;

--- What a disagreement needs beside its two answers to be read later: a loading screen or a world
--- event just before, a unit that is the player (the `[@u,party]` / `[@u,help]` cases), a unit that
--- is a ghost.
local function Context()
    local parts = {};
    if (loading) then
        parts[#parts + 1] = "loading";
    end
    local okVehicle, inVehicle = pcall(function() return UnitInVehicle("player") == true end);
    if (okVehicle and inVehicle) then
        parts[#parts + 1] = "vehicle";
    end
    if (worldEvent and GetTime() - worldEventAt <= WORLD_WINDOW) then
        parts[#parts + 1] = format("after:%s+%.1fs", worldEvent, GetTime() - worldEventAt);
    end
    for _, unit in ipairs({ "target", "focus", "mouseover" }) do
        local okSelf, isSelf = pcall(function() return UnitIsUnit(unit, "player") == true end);
        if (okSelf and isSelf) then
            parts[#parts + 1] = unit .. "=player";
        end
        local okGhost, isGhost = pcall(function() return UnitIsGhost(unit) == true end);
        if (okGhost and isGhost) then
            parts[#parts + 1] = unit .. "=ghost";
        end
    end
    return table.concat(parts, " ");
end

local function Stat(name)
    local s = store.stats[name];
    if (not s) then
        s = { macroMoves = 0, apiMoves = 0, runs = 0, longest = 0, macroOnly = 0, apiOnly = 0 };
        store.stats[name] = s;
    end
    return s;
end

--- Kept, capped, for every disagreement once it closes. The tallies keep counting past the cap.
local function Miss(name, macro, api, frames, context)
    if (#store.misses >= LIMIT) then
        return;
    end
    store.misses[#store.misses + 1] = format("%s %s %-26s macro=%s api=%s frames=%d %s",
        date("%m-%d %H:%M:%S"), select(2, UnitClass("player")), name, macro, api, frames, context);
end

--- How often a context was seen at all, so "never disagreed" can be told from "never happened".
local function Seen(what)
    store.seen[what] = (store.seen[what] or 0) + 1;
end

--- `btn` and the candidate lists have no single answer to agree with; they are only logged.
local function Comparable(pair)
    return pair[3] ~= nil and pair[1] ~= "vehicleui" and pair[1] ~= "possessbar";
end

local function Agree(name, macro, api)
    if (name == "pet") then
        -- `[pet]` against whether the summary has anything; the family and name columns are read
        -- by eye.
        return strmatch(macro, "^%[pet%]=(%a)") == strmatch(api, "^summary=(%a)");
    end
    return macro == api;
end

local probe = CreateFrame("Frame");
probe:Hide();

probe:SetScript("OnUpdate", function()
    frameIndex = frameIndex + 1;
    local context = Context();
    if (context ~= "") then
        for what in context:gmatch("%S+") do
            Seen((what:gsub("%+[%d.]+s$", "")));
        end
    end
    for i = 1, #PAIRS do
        local pair = PAIRS[i];
        local name = pair[1];
        -- A secret value raises on a truth test (12.x), and that is itself an answer worth a line.
        local ok, macro = pcall(pair[2]);
        if (not ok) then
            macro = "E";
        end
        local api = "";
        if (pair[3]) then
            ok, api = pcall(pair[3]);
            if (not ok) then
                api = "E";
            end
        end
        if (macro ~= lastMacro[name] or api ~= lastApi[name]) then
            local macroMoved = lastMacro[name] ~= nil and macro ~= lastMacro[name];
            local apiMoved = lastApi[name] ~= nil and api ~= lastApi[name];
            lastMacro[name], lastApi[name] = macro, api;
            local s = Stat(name);
            -- The value each side held, so a pair that never moves still says what it answered.
            s.values = s.values or {};
            s.values[tostring(macro) .. "/" .. tostring(api)] = true;
            if (macroMoved) then
                s.macroMoves = s.macroMoves + 1;
            end
            if (apiMoved) then
                s.apiMoves = s.apiMoves + 1;
            end
            if (macroMoved and not apiMoved) then
                s.macroOnly = s.macroOnly + 1;
            elseif (apiMoved and not macroMoved) then
                s.apiOnly = s.apiOnly + 1;
            end
        end
        if (Comparable(pair)) then
            local disagree = not Agree(name, macro, api);
            if (disagree and not apart[name]) then
                apart[name] = { macro, api };
                apartSince[name] = frameIndex;
                apartContext[name] = context;
                Stat(name).runs = Stat(name).runs + 1;
            elseif (not disagree and apart[name]) then
                local s = Stat(name);
                local length = frameIndex - apartSince[name];
                if (length > s.longest) then
                    s.longest = length;
                end
                Miss(name, apart[name][1], apart[name][2], length, apartContext[name]);
                apart[name] = nil;
            end
        end
    end
end);

--- One look at every unit the roster can name, with each `UNIT_WORDS` pair. The per-frame pairs
--- only watch target, focus, mouseover and pet, and a roster unit nobody targets never shows there.
--- Runs on its own whenever the roster or a pet changes.
local function Roster()
    local function look(unit)
        if (not UnitExists(unit)) then
            return;
        end
        local okSelf, isSelf = pcall(function() return UnitIsUnit(unit, "player") == true end);
        local context = Context() .. ((okSelf and isSelf) and (" " .. unit .. "=player") or "");
        for _, word in ipairs(UNIT_WORDS) do
            local name = "roster," .. word[1];
            local ok, macro = pcall(Macro, format("[@%s,%s]", unit, word[1]));
            if (not ok) then
                macro = "E";
            end
            local api;
            ok, api = pcall(word[2], unit);
            if (not ok) then
                api = "E";
            end
            local s = Stat(name);
            s.looks = (s.looks or 0) + 1;
            if (macro ~= api) then
                s.runs = s.runs + 1;
                Miss(name, macro, api, 0, unit .. " " .. context);
            end
        end
    end
    Seen("roster:" .. (PlayerInGroup() or "solo"));
    for _, unit in ipairs({ "player", "pet" }) do
        look(unit);
    end
    for _, prefix in ipairs({ "party", "partypet", "raid", "raidpet" }) do
        for i = 1, 40 do
            look(prefix .. i);
        end
    end
end

local function Summary()
    print(TAG .. format("%s since %s, %d misses kept", store.version, store.since, #store.misses));
    for _, pair in ipairs(PAIRS) do
        local s = store.stats[pair[1]];
        if (s and (s.runs > 0 or s.macroOnly > 0 or s.apiOnly > 0)) then
            print(TAG .. format("%-26s disagreements=%d longest=%d macroOnly=%d apiOnly=%d", pair[1], s.runs,
                s.longest, s.macroOnly, s.apiOnly));
        end
    end
    for _, word in ipairs(UNIT_WORDS) do
        local s = store.stats["roster," .. word[1]];
        if (s and s.runs > 0) then
            print(TAG .. format("roster,%-19s apart=%d of %d", word[1], s.runs, s.looks or 0));
        end
    end
end

local function Begin()
    DebindDevDB = DebindDevDB or {};
    -- The per-run log the earlier form of this probe saved.
    DebindDevDB.gateWords = nil;
    store = DebindDevDB.gateWordsStanding;
    if (not store or store.version ~= VERSION) then
        store = { version = VERSION, since = date("%Y-%m-%d %H:%M:%S"), stats = {}, misses = {}, seen = {} };
        DebindDevDB.gateWordsStanding = store;
    end
    store.builds = store.builds or {};
    store.builds[tostring(select(4, GetBuildInfo()))] = true;
    probe:Show();
    print(TAG .. format("%s running, %d misses kept (/debgw for the tallies)", VERSION, #store.misses));
end

local events = CreateFrame("Frame");
events:RegisterEvent("ADDON_LOADED");
events:RegisterEvent("LOADING_SCREEN_ENABLED");
events:RegisterEvent("LOADING_SCREEN_DISABLED");
events:RegisterEvent("GROUP_ROSTER_UPDATE");
events:RegisterEvent("PLAYER_ENTERING_WORLD");
events:RegisterEvent("ZONE_CHANGED");
events:RegisterEvent("ZONE_CHANGED_INDOORS");
events:RegisterEvent("ZONE_CHANGED_NEW_AREA");
events:RegisterUnitEvent("UNIT_PET", "player");
events:RegisterEvent("PLAYER_LOGOUT");
local WORLD_EVENTS = {
    LOADING_SCREEN_ENABLED = true, LOADING_SCREEN_DISABLED = true, PLAYER_ENTERING_WORLD = true,
    ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true,
};
local rosterPending = false;
events:SetScript("OnEvent", function(_, event, arg1)
    if (event == "ADDON_LOADED") then
        if (arg1 == "DebindDev") then
            Begin();
        end
        return;
    end
    -- A disagreement is kept when it closes; one still open at logout would otherwise be lost.
    if (event == "PLAYER_LOGOUT") then
        for name, answers in pairs(apart) do
            Miss(name, answers[1], answers[2], frameIndex - apartSince[name], apartContext[name] .. " open-at-logout");
        end
        return;
    end
    if (WORLD_EVENTS[event]) then
        worldEvent, worldEventAt = event, GetTime();
        if (store) then
            Seen(event);
        end
    end
    if (event == "LOADING_SCREEN_ENABLED") then
        loading = true;
        return;
    elseif (event == "LOADING_SCREEN_DISABLED") then
        loading = false;
        return;
    elseif (event ~= "PLAYER_ENTERING_WORLD" and event ~= "GROUP_ROSTER_UPDATE" and event ~= "UNIT_PET") then
        return;
    end
    -- The roster settles over a few events; one look a second after the last is enough.
    if (store and not rosterPending) then
        rosterPending = true;
        C_Timer.After(1, function()
            rosterPending = false;
            Roster();
        end);
    end
end);

--- What one call costs, `IsSubmerged()` against `SecureCmdOptionParse("[swimming]")`, each `COUNT`
--- times in a loop, less the same loop with nothing in it. Twice: in the insecure environment, and
--- in the restricted one through `SecureHandlerExecute`, which is where the beat runs; the second
--- carries the environment's own lookups. `ROUNDS` rounds, and the median is what to read.
local COUNT, ROUNDS = 1000, 21;

local timingHeader;

local INSECURE = {
    empty = function()
        for _ = 1, COUNT do
        end
    end,
    submerged = function()
        local x;
        for _ = 1, COUNT do
            x = IsSubmerged();
        end
        return x;
    end,
    swimming = function()
        local x;
        for _ = 1, COUNT do
            x = SecureCmdOptionParse("[swimming]");
        end
        return x;
    end,
};

local RESTRICTED = {
    empty = format("local x for i = 1, %d do end", COUNT),
    submerged = format("local x for i = 1, %d do x = IsSubmerged() end", COUNT),
    swimming = format([[local x for i = 1, %d do x = SecureCmdOptionParse("[swimming]") end]], COUNT),
};

local function Median(list)
    table.sort(list);
    return list[(#list + 1) / 2];
end

local function Time()
    if (InCombatLockdown()) then
        print(TAG .. "out of combat only: SecureHandlerExecute is refused in combat");
        return;
    end
    if (not timingHeader) then
        timingHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate");
    end
    local samples = {};
    for _, side in ipairs({ "insecure", "restricted" }) do
        for _, name in ipairs({ "empty", "submerged", "swimming" }) do
            samples[side .. "." .. name] = {};
        end
    end
    -- Interleaved by round, so a hitch in one round lands on every case alike.
    for _ = 1, ROUNDS do
        for _, name in ipairs({ "empty", "submerged", "swimming" }) do
            local start = debugprofilestop();
            INSECURE[name]();
            local list = samples["insecure." .. name];
            list[#list + 1] = debugprofilestop() - start;

            start = debugprofilestop();
            SecureHandlerExecute(timingHeader, RESTRICTED[name]);
            list = samples["restricted." .. name];
            list[#list + 1] = debugprofilestop() - start;
        end
    end
    local lines = {};
    for _, side in ipairs({ "insecure", "restricted" }) do
        local empty = Median(samples[side .. ".empty"]);
        for _, name in ipairs({ "submerged", "swimming" }) do
            local median = Median(samples[side .. "." .. name]);
            lines[#lines + 1] = format("%-10s %-9s %d calls: median %.3f ms, less the empty loop %.3f ms = %.2f us a call",
                side, name, COUNT, median, median - empty, (median - empty) * 1000 / COUNT);
        end
        lines[#lines + 1] = format("%-10s empty loop median %.3f ms", side, empty);
    end
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.gateWordsTiming = { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()),
        swimming = IsSubmerged() and true or false, lines = lines };
    for _, line in ipairs(lines) do
        print(TAG .. line);
    end
end

--- The wider survey: what each piece a beat could be built from costs in the restricted environment,
--- a call at a time. Table reads and mask arithmetic (what a gate is made of), the measuring APIs,
--- and `SecureCmdOptionParse` on expressions of every shape a switch or a record carries, the
--- composition a computed switch goes through before its parse, and `RunAttribute` for scale.
---
--- Each case is `prelude` once and `stmt` `COUNT` times, less the empty loop.
local function BenchCases()
    local knownName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(686))
        or (GetSpellInfo and GetSpellInfo(686)) or "Shadow Bolt";
    local function parse(expr)
        return { stmt = format("x = SecureCmdOptionParse(%q)", expr) };
    end
    return {
        { "empty", { stmt = "" } },
        { "mask arithmetic on locals", { prelude = "local c, m = 2, 6", stmt = "x = (m % (c + c)) >= c" } },
        { "global table field read", { stmt = "x = BenchColumn.cell" } },
        { "global table, index, field read", { stmt = "x = BenchColumns[3].cell" } },
        { "local table field read", { prelude = "local t = BenchColumn", stmt = "x = t.cell" } },
        { "local table field write", { prelude = "local t = BenchColumn", stmt = "t.stamp = i" } },
        { "read + mask (one gate term)", { prelude = "local m = 6",
            stmt = "local c = BenchColumns[3].cell x = (m % (c + c)) >= c" } },
        { "IsSubmerged()", { stmt = "x = IsSubmerged()" } },
        { "IsMounted()", { stmt = "x = IsMounted()" } },
        { "GetShapeshiftForm()", { stmt = "x = GetShapeshiftForm()" } },
        { "PlayerInCombat() (ENV wrapper)", { stmt = "x = PlayerInCombat()" } },
        { "PlayerPetSummary() (ENV wrapper)", { stmt = "x = PlayerPetSummary()" } },
        { "HasExtraActionBar() (ENV)", { stmt = "x = HasExtraActionBar()" } },
        { "UnitExists(target)", { stmt = [[x = UnitExists("target")]] } },
        { "PlayerCanAssist(target) (ENV)", { stmt = [[x = PlayerCanAssist("target")]] } },
        { "UnitIsDead(target)", { stmt = [[x = UnitIsDead("target")]] } },
        { "FindSpellBookSlotBySpellID(686)", { stmt = "x = FindSpellBookSlotBySpellID(686)" } },
        { "parse [swimming]", parse("[swimming]") },
        { "parse [combat]", parse("[combat]") },
        { "parse [@target,help,nodead]", parse("[@target,help,nodead]") },
        { "parse 6 tokens in one group", parse("[combat,mounted,nostealth,flying,form:1,group:raid]") },
        { "parse 4 groups [a][b][c][d]", parse("[combat][mounted][swimming][flying]") },
        { "parse 3 clauses with values", parse("[combat] a; [mounted] b; c") },
        { "parse [pet:Imp]", parse("[pet:Imp]") },
        { "parse [known:686]", parse("[known:686]") },
        { "parse [known:<name of 686>]", parse("[known:" .. knownName .. "]") },
        { "parse [known:1] (no such spell)", parse("[known:1]") },
        { "compose only (one switch arg)", { prelude = "local e = BenchEntry", stmt = [==[
local a = e.args[1] local v = BenchStates[a.switch] v = v and true or false
v = v and "" or "known:0" e.fragments[2] = v x = table.concat(e.fragments)]==] } },
        { "compose + parse", { prelude = "local e = BenchEntry", stmt = [==[
local a = e.args[1] local v = BenchStates[a.switch] v = v and true or false
v = v and "" or "known:0" e.fragments[2] = v x = SecureCmdOptionParse(table.concat(e.fragments))]==] } },
        { "RunAttribute (one-line body)", { stmt = [[self:RunAttribute("BenchNoop")]] } },
    }, knownName;
end

local BENCH_SETUP = [==[
BenchColumn = newtable()
BenchColumn.cell = 2
BenchColumns = newtable()
BenchColumns[3] = BenchColumn
BenchStates = newtable()
BenchStates["$x"] = true
BenchEntry = newtable()
BenchEntry.fragments = newtable()
BenchEntry.fragments[1] = "["
BenchEntry.fragments[2] = ""
BenchEntry.fragments[3] = ",combat]"
BenchEntry.args = newtable()
local a = newtable()
a.switch = "$x"
BenchEntry.args[1] = a
]==];

--- The same bodies in the insecure environment, which is the only one reachable in combat:
--- `SecureHandlerExecute` is refused there. The ENV wrappers are copied from
--- `RestrictedEnvironment.lua`; tables are plain here, so the table rows read low against the
--- restricted column, and the API and parse rows are what to compare across situations.
local insecureEnv = setmetatable({
    PlayerInCombat = function() return UnitAffectingCombat("player") or UnitAffectingCombat("pet") end,
    PlayerCanAssist = function(unit) return UnitCanAssist("player", unit) end,
    PlayerPetSummary = function() return UnitCreatureFamily("pet"), (UnitName("pet")) end,
    HasExtraActionBar = function() return C_ActionBar.HasExtraActionBar() end,
    newtable = function(...) return { ... } end,
}, { __index = _G });

local function Situation()
    local function b(v)
        if (issecretvalue and issecretvalue(v)) then
            return "S";
        end
        return v and "T" or "F";
    end
    local target = "none";
    if (UnitExists("target")) then
        target = (UnitCanAttack("player", "target") and "harm") or (UnitCanAssist("player", "target") and "help")
            or "other";
        if (UnitIsDead("target") or UnitIsGhost("target")) then
            target = target .. ",dead";
        end
    end
    return format("combat=%s mounted=%s flying=%s submerged=%s form=%s stealth=%s group=%s target=%s pet=%s",
        b(UnitAffectingCombat("player")), b(IsMounted()), b(IsFlying()), b(IsSubmerged()),
        tostring(GetShapeshiftForm()), b(IsStealthed()), (IsInRaid() and "raid") or (IsInGroup() and "party") or "none",
        -- With no pet the call returns nothing at all, and `tostring()` refuses no argument.
        target, tostring((UnitCreatureFamily("pet"))));
end

local function Bench()
    local restricted = not InCombatLockdown();
    if (restricted) then
        if (not timingHeader) then
            timingHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate");
        end
        timingHeader:SetAttribute("BenchNoop", "local y = 1");
        SecureHandlerExecute(timingHeader, BENCH_SETUP);
    end
    local setup = loadstring(BENCH_SETUP);
    setfenv(setup, insecureEnv);
    setup();

    local cases, knownName = BenchCases();
    local bodies, funcs, rSamples, iSamples = {}, {}, {}, {};
    for n, case in ipairs(cases) do
        local spec = case[2];
        bodies[n] = format("local x %s for i = 1, %d do %s end", spec.prelude or "", COUNT, spec.stmt);
        if (not strfind(spec.stmt, "self:", 1, true)) then
            funcs[n] = loadstring(bodies[n]);
            setfenv(funcs[n], insecureEnv);
        end
        rSamples[n], iSamples[n] = {}, {};
    end
    -- Interleaved by round, so a hitch in one round lands on every case alike.
    for _ = 1, ROUNDS do
        for n = 1, #cases do
            local start;
            if (restricted) then
                start = debugprofilestop();
                SecureHandlerExecute(timingHeader, bodies[n]);
                local list = rSamples[n];
                list[#list + 1] = debugprofilestop() - start;
            end
            if (funcs[n]) then
                start = debugprofilestop();
                funcs[n]();
                local list = iSamples[n];
                list[#list + 1] = debugprofilestop() - start;
            end
        end
    end

    local rEmpty = restricted and Median(rSamples[1]);
    local iEmpty = Median(iSamples[1]);
    local lines = {
        format("us a call, %d calls a body, median of %d rounds, less the empty loop", COUNT, ROUNDS),
        Situation(),
        format("known(686 %q)=%s", knownName, tostring(SecureCmdOptionParse("[known:686]") ~= nil)),
        "restricted  insecure",
    };
    for n = 2, #cases do
        local r = restricted and format("%9.3f", (Median(rSamples[n]) - rEmpty) * 1000 / COUNT) or "        -";
        local i = funcs[n] and format("%9.3f", (Median(iSamples[n]) - iEmpty) * 1000 / COUNT) or "        -";
        lines[#lines + 1] = format("%s %s  %s", r, i, cases[n][1]);
    end

    DebindDevDB = DebindDevDB or {};
    -- One run per situation, kept side by side. An older single run is dropped.
    if (type(DebindDevDB.gateWordsBench) ~= "table" or DebindDevDB.gateWordsBench.lines) then
        DebindDevDB.gateWordsBench = {};
    end
    local runs = DebindDevDB.gateWordsBench;
    runs[#runs + 1] = { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()), lines = lines };
    for _, line in ipairs(lines) do
        print(TAG .. line);
    end
    print(TAG .. format("run %d saved", #runs));
end

SLASH_DEBINDGW1 = "/debgw";
SlashCmdList.DEBINDGW = function(msg)
    msg = strlower(strtrim(msg or ""));
    if (msg == "time") then
        Time();
    elseif (msg == "bench") then
        Bench();
    elseif (msg == "reset") then
        DebindDevDB.gateWordsStanding = nil;
        Begin();
    else
        Summary();
    end
end;
