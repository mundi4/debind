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

SLASH_DEBINDGW1 = "/debgw";
SlashCmdList.DEBINDGW = function(msg)
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
