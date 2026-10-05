-- Probe_GateWords.lua
-- One-shot probe: for each macro conditional word that `trimming-the-tail-key-beat.md` §3-2 maps to a
-- restricted-environment API, does the word's answer move exactly when that API's answer does?
--
-- A computed switch is re-parsed only when a column its expression reads moves (§3-1). A word whose
-- macro answer can flip while the column stays put freezes the switch on its last answer, so the
-- mapping has to hold in both directions. Only the client can say.
--
-- Each frame every pair is sampled once, the macro side through `SecureCmdOptionParse` and the API
-- side through the same call the restricted environment makes (`RestrictedEnvironment.lua`; the ENV
-- wrappers are copied as written). A line is kept when either side changes.
--
--   /debgw          start (wipes the previous log)
--   /debgw stop     stop, and print each pair's disagreements
--   /debgw show     print the saved log
--   /debgw time     what one `IsSubmerged()` and one `[swimming]` parse cost (out of combat)
--   /debgw bench    the wider survey: table reads, APIs, parses of every shape. Every run is kept
--                   with the situation it ran in; in combat only the insecure column is measured
--
-- What to do while it runs: target and focus friends, enemies, corpses, party and raid members, a
-- vehicle; mouse over units; mount, fly, swim, go indoors and out, stealth, shift forms, change bar
-- pages, take a vehicle and a possession and an extra button, summon, swap and dismiss pets, hold
-- the modifiers, channel a spell, join and leave a group. The answer is in the summary: a pair that
-- disagrees for one frame at a change is a lag; one that disagrees for longer, or flips on one side
-- only, is a mapping that does not hold.
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cffff9900[GW]|r ";

--- Lines are kept only on a change, so this is a guard against something flapping every frame.
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
    -- No bonus bar is offset 0, and `[bonusbar:0]` does not match it; `[nobonusbar]` does.
    { "bonusbar", function()
        return SecureCmdOptionParse("[nobonusbar] 0") or MacroNumber("bonusbar", 10);
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
for _, unit in ipairs({ "target", "focus", "mouseover", "pet" }) do
    for _, word in ipairs(UNIT_WORDS) do
        local conditions = format("[@%s,%s]", unit, word[1]);
        local api = word[2];
        PAIRS[#PAIRS + 1] = { unit .. "," .. word[1], function() return Macro(conditions) end,
            function() return api(unit) end };
    end
end

local frameIndex = 0;
local log;
local running = false;
local lastMacro, lastApi = {}, {};
--- Per pair: whether the two sides disagree now, since which frame, and the tallies.
local apart, apartSince, stats = {}, {}, {};

local function Record(line)
    if (#log >= LIMIT) then
        return;
    end
    line = format("%6d %10.3f %s", frameIndex, GetTime(), line);
    log[#log + 1] = line;
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
            local s = stats[name];
            if (macroMoved and not apiMoved) then
                s.macroOnly = s.macroOnly + 1;
            elseif (apiMoved and not macroMoved) then
                s.apiOnly = s.apiOnly + 1;
            end
            Record(format("%-26s macro=%s api=%s%s", name, macro, api,
                (macroMoved and not apiMoved and "  <macro only>")
                or (apiMoved and not macroMoved and "  <api only>") or ""));
        end
        if (Comparable(pair)) then
            local s = stats[name];
            local disagree = not Agree(name, macro, api);
            if (disagree and not apart[name]) then
                apart[name] = true;
                apartSince[name] = frameIndex;
                s.runs = s.runs + 1;
                Record(format("%-26s DISAGREE", name));
            elseif (not disagree and apart[name]) then
                apart[name] = nil;
                local length = frameIndex - apartSince[name];
                if (length > s.longest) then
                    s.longest = length;
                end
                Record(format("%-26s agree again after %d frame(s)", name, length));
            end
        end
    end
end);

local function Summary()
    local lines = {};
    for _, pair in ipairs(PAIRS) do
        local name = pair[1];
        local s = stats[name];
        if (s and (s.runs > 0 or s.macroOnly > 0 or s.apiOnly > 0)) then
            local open = apart[name] and format(" (apart since frame %d)", apartSince[name]) or "";
            lines[#lines + 1] = format("%-26s disagreements=%d longest=%d frames macroOnly=%d apiOnly=%d%s",
                name, s.runs, s.longest, s.macroOnly, s.apiOnly, open);
        end
    end
    if (#lines == 0) then
        lines[1] = "no pair ever moved on one side alone or disagreed";
    end
    return lines;
end

local function Start()
    DebindDevDB = DebindDevDB or {};
    log = {};
    DebindDevDB.gateWords = { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()), lines = log };
    frameIndex = 0;
    wipe(lastMacro);
    wipe(lastApi);
    wipe(apart);
    wipe(apartSince);
    for _, pair in ipairs(PAIRS) do
        stats[pair[1]] = { runs = 0, longest = 0, macroOnly = 0, apiOnly = 0 };
    end
    running = true;
    probe:Show();
    print(TAG .. "started");
end

local function Stop()
    probe:Hide();
    running = false;
    local summary = Summary();
    if (DebindDevDB and DebindDevDB.gateWords) then
        DebindDevDB.gateWords.summary = summary;
    end
    print(TAG .. format("stopped, %d lines in DebindDevDB.gateWords", log and #log or 0));
    for _, line in ipairs(summary) do
        print(TAG .. line);
    end
end

local function Show()
    local saved = DebindDevDB and DebindDevDB.gateWords;
    if (not saved or not saved.lines or #saved.lines == 0) then
        print(TAG .. "no log");
        return;
    end
    print(TAG .. format("%s build %s, %d lines%s", saved.at or "?", tostring(saved.build), #saved.lines,
        running and " (running)" or ""));
    for i = 1, #saved.lines do
        print(saved.lines[i]);
    end
    for _, line in ipairs(saved.summary or {}) do
        print(TAG .. line);
    end
end

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
    elseif (msg == "stop") then
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
