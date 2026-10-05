-- Probe_BeatCost.lua
-- One-shot probe: what every piece the tail-key beat could be built from costs, in one run
-- (`trimming-the-tail-key-beat.md`).
--
--   /debbc      run it out of combat (a few seconds of frozen frames), wait two seconds for the
--               state-visibility line it prints last, then /reload
--
-- Every case is a body run `COUNT` times in a loop, `ROUNDS` rounds interleaved, median less the
-- empty loop, as microseconds a call. In the restricted environment through `SecureHandlerExecute`
-- (where the beat runs) and in the insecure one with the same text. The insecure column is the only
-- one reachable in combat, where `SecureHandlerExecute` is refused.
--
-- The groups:
--   A  restricted primitives: table reads and writes, `newtable`, concat, attributes, `RunAttribute`
--   B  every measurement the beat makes now, as `Constants.STATE_EVAL_EXPRESSIONS` spells it, and
--      the unit cell as `BuildJudgeSnippet` writes it
--   C  every gateable word parsed alone
--   D  one group of N conditions parsed once, against the same N functions joined with `and`: all
--      true, the first false, the last false. Which way a word answers now is read at the start,
--      so one run covers both paths whatever the situation
--   E  N groups `[a][b]...` against `or`: all false, the first true
--   F  a bundle written as one expression `[a,b,c] ours; [d,e,f] release; ...; ours`, parsed once,
--      against measuring the same columns the way the beat does now and the judging loop over
--      restricted tables
--   G  a computed switch's composition, with and without the parse
--   N  one long OR `[a][b]...` of 4 to 256 groups, the shape of a watch over every column: what a
--      false group costs as the text grows, whether the parse reads a text that long to its end,
--      and whether a state word answers the same beside an `@unit`, wherever in the group it sits.
--      That last one is answered for `combat` only by a run with a unit whose combat is not the
--      player's (in combat with an idle target works: those lines need no restricted environment)
--   P  a bundle's answer read out of a table baked at rebuild instead of walked out of its entries:
--      the pieces (a bit asked of a large number, `2 ^ n`, `ldexp`, `strbyte`, `strsub`, an array
--      read, the joint index) and then the same three-column bundle judged by the loop and by a
--      table kept as two numbers, as a string and as an array
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cffff9900[BC]|r ";
local COUNT, ROUNDS = 1000, 15;
--- Group N's texts cost tens of microseconds a parse, so a tenth of the calls times them as well
--- and keeps the frozen frames short. They are held against an empty loop of the same count.
local LONG_COUNT = 100;

--- Words a gate could read, each with the restricted call that answers it. Only the ones whose
--- macro answer and call agree right now are used in D-F, so a chain is false where its parse is.
local WORDS = {
    { "combat", "PlayerInCombat()" },
    { "mounted", "IsMounted()" },
    { "flying", "IsFlying()" },
    { "swimming", "IsSubmerged()" },
    { "indoors", "IsIndoors()" },
    { "outdoors", "IsOutdoors()" },
    { "stealth", "IsStealthed()" },
    { "flyable", "IsFlyableArea()" },
    { "advflyable", "IsAdvancedFlyableArea()" },
    { "extrabar", "HasExtraActionBar()" },
    { "overridebar", "HasOverrideActionBar()" },
    { "shapeshift", "HasTempShapeshiftActionBar()" },
    { "canexitvehicle", "CanExitVehicle()" },
    { "channeling", "PlayerIsChanneling()" },
    { "mod:shift", "IsShiftKeyDown()" },
    { "mod:ctrl", "IsControlKeyDown()" },
    { "pet", "PlayerPetSummary()" },
    { "group", "PlayerInGroup()" },
};

--- The ENV wrappers as `RestrictedEnvironment.lua` writes them, for the insecure column.
local insecureEnv = setmetatable({
    PlayerInCombat = function() return UnitAffectingCombat("player") or UnitAffectingCombat("pet") end,
    PlayerCanAssist = function(unit) return UnitCanAssist("player", unit) end,
    PlayerCanAttack = function(unit) return UnitCanAttack("player", unit) end,
    PlayerIsChanneling = function() return (UnitChannelInfo("player") ~= nil) end,
    PlayerPetSummary = function() return UnitCreatureFamily("pet"), (UnitName("pet")) end,
    PlayerInGroup = function() return (IsInRaid() and "raid") or (IsInGroup() and "party") end,
    HasExtraActionBar = function() return C_ActionBar.HasExtraActionBar() end,
    HasOverrideActionBar = function() return C_ActionBar.HasOverrideActionBar() end,
    HasVehicleActionBar = function() return C_ActionBar.HasVehicleActionBar() end,
    HasTempShapeshiftActionBar = function() return C_ActionBar.HasTempShapeshiftActionBar() end,
    GetBonusBarOffset = function() return C_ActionBar.GetBonusBarOffset() end,
    newtable = function(...) return { ... } end,
}, { __index = _G });

local SETUP = [==[
BenchColumn = newtable()
BenchColumn.cell = 2
BenchColumns = newtable()
BenchColumns[3] = BenchColumn
BenchCols = newtable()
for j = 1, 24 do
    local c = newtable()
    c.cell = false
    BenchCols[j] = c
end
BenchStates = newtable()
BenchStates["$x"] = true
BenchStates["$y"] = false
BenchEntry1 = newtable()
BenchEntry1.fragments = newtable()
BenchEntry1.fragments[1] = "["
BenchEntry1.fragments[2] = ""
BenchEntry1.fragments[3] = ",combat]"
BenchEntry1.args = newtable()
local a = newtable()
a.switch = "$x"
BenchEntry1.args[1] = a
BenchEntry3 = newtable()
BenchEntry3.fragments = newtable()
BenchEntry3.fragments[1] = "["
BenchEntry3.fragments[2] = ""
BenchEntry3.fragments[3] = ","
BenchEntry3.fragments[4] = ""
BenchEntry3.fragments[5] = ",@"
BenchEntry3.fragments[6] = ""
BenchEntry3.fragments[7] = ",help]"
BenchEntry3.args = newtable()
local s1 = newtable()
s1.switch = "$x"
local s2 = newtable()
s2.switch = "$y"
s2.reverse = true
local u = newtable()
u.unit = "focus"
BenchEntry3.args[1] = s1
BenchEntry3.args[2] = s2
BenchEntry3.args[3] = u
BenchAliasMap = newtable()
BenchAliasMap.focus = "focus"
BenchJudgeCol = newtable()
BenchJudgeCol.cell = 2
BenchBundle = newtable()
for e = 1, 4 do
    local entry = newtable()
    entry[1] = BenchJudgeCol
    entry[2] = 1
    entry[3] = BenchJudgeCol
    entry[4] = 1
    BenchBundle[e] = entry
end
BenchList = newtable()
BenchCellA = newtable()
BenchCellA.cell = 2
BenchCellB = newtable()
BenchCellB.cell = 4
BenchCellC = newtable()
BenchCellC.cell = 1
BenchLoopBundle = newtable()
for e = 1, 4 do
    local entry = newtable()
    entry[1] = BenchCellA
    entry[2] = 6
    entry[3] = (e % 2 == 0) and BenchCellC or BenchCellB
    entry[4] = (e == 4) and 1 or 2
    BenchLoopBundle[e] = entry
end
BenchIndex = newtable()
BenchIndex[1] = 1
BenchIndex[2] = 2
BenchIndex[3] = 0
BenchTable = newtable()
BenchTable.ours = 2 ^ 3 + 2 ^ 20
BenchTable.release = 2 ^ 7 + 2 ^ 11
BenchTable.answers = "ccccccc" .. "r" .. "ccccccccccccccccccc"
BenchTable.list = newtable()
for j = 1, 27 do
    BenchTable.list[j] = 3
end
BenchTable.list[8] = 2
]==];

--- The composition loop of `COMPOSE_MACROTEXT_SNIPPET` for switch and unit arguments, then the
--- concat. `%s` is the entry.
local COMPOSE = [==[
local e = %s
for k = 1, #e.args do
    local arg = e.args[k]
    local value
    if (arg.unit) then
        value = BenchAliasMap[arg.unit]
        value = value or "raid41"
    elseif (arg.switch) then
        value = BenchStates[arg.switch]
        value = value and true or false
        if (arg.reverse) then
            value = not value
        end
        value = value and "" or "known:0"
    end
    e.fragments[k * 2] = value
end
local s = table.concat(e.fragments)
]==];

local UNIT_CELL = [==[
local unit = "target"
local exists = UnitExists(unit) and true or false
local cell
if (not exists) then
    cell = 0
else
    local dead = (UnitIsDead(unit) or UnitIsGhost(unit)) and true or false
    if (PlayerCanAssist(unit)) then
        cell = dead and 2 or 1
    elseif (PlayerCanAttack(unit)) then
        cell = dead and 4 or 3
    else
        cell = dead and 6 or 5
    end
end
x = cell
]==];

local function q(s)
    return format("%q", s);
end

--- The two-clause bundle of group F, kept for group J's driver tick.
local BENCH_BUNDLE_EXPR;

--- Group N's texts, kept for `WatchChecks`: `{ n, kind, allFalse, lastTrue }`.
local watchChecks = {};

--- The units group N's unit groups cycle through. `nameplate` is left to group L: it costs twice
--- the rest and would hide the slope.
local WATCH_UNITS = {
    "target", "focus", "mouseover", "pet", "party1", "party2", "raid1", "raid2", "boss1", "targettarget",
};

--- The frames group J writes to. Made once, out of combat; their refs go on the header.
local benchFrames;

local function MakeBenchFrames(header)
    if (benchFrames) then
        return benchFrames;
    end
    benchFrames = {
        tPlain = CreateFrame("Frame", nil, UIParent, "SecureFrameTemplate"),
        tAttr = CreateFrame("Frame", nil, UIParent, "SecureHandlerAttributeTemplate"),
        tState = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate"),
        tBeat = CreateFrame("Frame", nil, UIParent, "SecureHandlerAttributeTemplate"),
        tDrv = CreateFrame("Frame", nil, UIParent, "SecureFrameTemplate"),
    };
    benchFrames.tAttr:SetAttribute("_onattributechanged", "return");
    benchFrames.tState:SetAttribute("_onstate-beat", "return");
    -- The current beat's first lines (`BuildJudgeSnippet`), with the measuring left out.
    benchFrames.tBeat:SetAttribute("_onattributechanged", [[
if (name == "state-beat") then
    if (value == 0) then
        return
    end
    self:SetAttribute("state-beat", 0)
end
]]);
    for name, frame in pairs(benchFrames) do
        SecureHandlerSetFrameRef(header, name, frame);
    end
    -- Counts the times its handler is entered for `statehidden`, which is what the manager's
    -- `state-visibility` branch writes on every tick without comparing (`VisibilityChecks`).
    benchFrames.tCount = CreateFrame("Frame", nil, UIParent, "SecureHandlerAttributeTemplate");
    benchFrames.tCount:SetAttribute("_onattributechanged", [[
if (name == "statehidden") then
    self:SetAttribute("ticks", (self:GetAttribute("ticks") or 0) + 1)
end
]]);
    insecureEnv.BenchBeatFrame = benchFrames.tBeat;
    insecureEnv.BenchAttrFrame = benchFrames.tAttr;
    insecureEnv.BenchPlainFrame = benchFrames.tPlain;
    return benchFrames;
end

--- What the insecure copies of the manager's tick read. Unprotected, so it never needs combat
--- to be over.
local simFrame = CreateFrame("Frame");
simFrame:SetAttribute("unit", "player");
insecureEnv.BenchSimFrame = simFrame;

local function Cases()
    local cases = {};
    local function add(group, name, stmt, prelude)
        cases[#cases + 1] = { group = group, name = name, stmt = stmt, prelude = prelude };
    end

    -- A
    add("A", "empty", "");
    add("A", "empty, at group N's count", "");
    cases[#cases].count = LONG_COUNT;
    add("A", "mask arithmetic on locals", "x = (m % (c + c)) >= c", "local c, m = 2, 6");
    add("A", "global read", "x = BenchColumn");
    add("A", "global table field read", "x = BenchColumn.cell");
    add("A", "global table, index, field read", "x = BenchColumns[3].cell");
    add("A", "local table field read", "x = t.cell", "local t = BenchColumn");
    add("A", "local table field write", "t.stamp = i", "local t = BenchColumn");
    add("A", "read + compare, unchanged (one column's mark)",
        "local cc = BenchCols[1] if (cc.cell ~= false) then cc.cell = false end");
    add("A", "read + mask (one gate term)", "local cc = BenchColumns[3].cell x = (m % (cc + cc)) >= cc", "local m = 6");
    -- Where a bundle keeps its last result across beats (`trimming-the-tail-key-beat.md` 8-2): an
    -- environment global or a table field, on a quiet beat. A beat where it changed adds one write,
    -- measured on its own.
    add("A", "env global write", "BenchGlobal = i");
    add("A", "parse vs last in an env global, unchanged",
        [[local r = SecureCmdOptionParse("[combat] release; ours") if (r ~= BenchLast) then BenchLast = r end]]);
    add("A", "parse vs last in a table field, unchanged",
        [[local r = SecureCmdOptionParse("[combat] release; ours") if (r ~= t.last) then t.last = r end]],
        "local t = BenchColumn");
    add("A", "parse alone (for the two above)", [[local r = SecureCmdOptionParse("[combat] release; ours")]]);
    add("A", "newtable()", "x = newtable()");
    add("A", "wipe(list)", "wipe(BenchList)");
    add("A", "string .. string", [[x = "abc" .. i]]);
    add("A", "table.concat 3 fragments", "x = table.concat(BenchEntry1.fragments)");
    add("A", "self:GetAttribute", [[x = self:GetAttribute("BenchNoop")]]);
    add("A", "self:SetAttribute same value", [[self:SetAttribute("benchvalue", 1)]]);
    add("A", "RunAttribute one-line body", [[self:RunAttribute("BenchNoop")]]);

    -- B
    add("B", "group (raid, party chain on player)",
        [[x = (UnitPlayerOrPetInRaid("player") and 4) or (UnitPlayerOrPetInParty("player") and 2) or 1]]);
    for _, e in ipairs({
        { "combat", "PlayerInCombat()" }, { "stealth", "IsStealthed()" }, { "mounted", "IsMounted()" },
        { "indoors", "IsIndoors()" }, { "flyable", "IsFlyableArea()" }, { "advflyable", "IsAdvancedFlyableArea()" },
        { "flying", "IsFlying()" }, { "form", "GetShapeshiftForm()" }, { "bonusbar", "GetBonusBarOffset()" },
        { "skyriding", "GetBonusBarOffset() == 5" },
        { "specialbar", "HasVehicleActionBar() or HasOverrideActionBar() or HasTempShapeshiftActionBar() or false" },
        { "extrabar", "HasExtraActionBar()" },
        { "petbattle", [[SecureCmdOptionParse("[petbattle]") and true or false]] },
    }) do
        add("B", e[1] .. " = " .. e[2], "x = " .. e[2]);
    end
    add("B", "unit cell for target (exists, dead, reaction)", UNIT_CELL);
    add("B", "known: parse [known:686]", [[x = SecureCmdOptionParse("[known:686]")]]);
    add("B", "known: FindSpellBookSlotBySpellID(686)", "x = FindSpellBookSlotBySpellID(686)");
    add("B", "UnitExists(mouseover)", [[x = UnitExists("mouseover")]]);
    add("B", "PlayerPetSummary()", "x = PlayerPetSummary()");

    -- C
    for _, w in ipairs(WORDS) do
        add("C", "parse [" .. w[1] .. "]", "x = SecureCmdOptionParse(" .. q("[" .. w[1] .. "]") .. ")");
    end
    add("C", "parse [@target,help,nodead]", [[x = SecureCmdOptionParse("[@target,help,nodead]")]]);
    add("C", "parse [@focus,harm]", [[x = SecureCmdOptionParse("[@focus,harm]")]]);
    add("C", "parse [pet:Imp]", [[x = SecureCmdOptionParse("[pet:Imp]")]]);
    add("C", "parse [form:1]", [[x = SecureCmdOptionParse("[form:1]")]]);
    add("C", "parse [bonusbar:5]", [[x = SecureCmdOptionParse("[bonusbar:5]")]]);
    add("C", "parse [group:raid]", [[x = SecureCmdOptionParse("[group:raid]")]]);

    -- Which way each word answers now, by both sides; a word the two sides disagree on is left out.
    local usable = {};
    for _, w in ipairs(WORDS) do
        local macro = SecureCmdOptionParse("[" .. w[1] .. "]") ~= nil;
        local f = loadstring("return (" .. w[2] .. ") and true or false");
        setfenv(f, insecureEnv);
        local ok, fn = pcall(f);
        if (ok and fn == macro) then
            usable[#usable + 1] = {
                tTok = macro and w[1] or ("no" .. w[1]), fTok = macro and ("no" .. w[1]) or w[1],
                tFn = macro and w[2] or ("not " .. w[2]), fFn = macro and ("not " .. w[2]) or w[2],
                fn = w[2],
            };
        end
    end

    local function tokens(n, falseAt)
        local list, fns = {}, {};
        for k = 1, n do
            local w = usable[k];
            list[k] = (k == falseAt) and w.fTok or w.tTok;
            fns[k] = (k == falseAt) and w.fFn or w.tFn;
        end
        return list, fns;
    end

    -- D
    for _, n in ipairs({ 1, 2, 4, 8 }) do
        if (n <= #usable) then
            for _, shape in ipairs({ { "all true", nil }, { "first false", 1 }, { "last false", n } }) do
                if (not (n == 1 and shape[2] == n and shape[1] == "last false")) then
                    local toks, fns = tokens(n, shape[2]);
                    add("D", format("AND of %d, %s: one parse", n, shape[1]),
                        "x = SecureCmdOptionParse(" .. q("[" .. table.concat(toks, ",") .. "]") .. ")");
                    add("D", format("AND of %d, %s: functions joined", n, shape[1]),
                        "x = " .. table.concat(fns, " and "));
                end
            end
        end
    end

    -- E
    for _, n in ipairs({ 2, 4, 8 }) do
        if (n <= #usable) then
            local allFalse, allFalseFns, firstTrue, firstTrueFns = {}, {}, {}, {};
            for k = 1, n do
                local w = usable[k];
                allFalse[k] = "[" .. w.fTok .. "]";
                allFalseFns[k] = w.fFn;
                firstTrue[k] = "[" .. ((k == 1) and w.tTok or w.fTok) .. "]";
                firstTrueFns[k] = (k == 1) and w.tFn or w.fFn;
            end
            add("E", format("OR of %d groups, all false: one parse", n),
                "x = SecureCmdOptionParse(" .. q(table.concat(allFalse)) .. ")");
            add("E", format("OR of %d, all false: functions joined", n), "x = " .. table.concat(allFalseFns, " or "));
            add("E", format("OR of %d groups, first true: one parse", n),
                "x = SecureCmdOptionParse(" .. q(table.concat(firstTrue)) .. ")");
            add("E", format("OR of %d, first true: functions joined", n), "x = " .. table.concat(firstTrueFns, " or "));
        end
    end

    -- F
    for _, k in ipairs({ 2, 4 }) do
        local m = 3 * k;
        if (m <= #usable) then
            local none, first, measure = {}, {}, {};
            for j = 1, k do
                local a, b, c = usable[3 * j - 2], usable[3 * j - 1], usable[3 * j];
                local outcome = (j % 2 == 1) and "ours" or "release";
                none[j] = format("[%s,%s,%s] %s", a.tTok, b.tTok, c.fTok, outcome);
                first[j] = format("[%s,%s,%s] %s", a.tTok, b.tTok, (j == 1) and c.tTok or c.fTok, outcome);
            end
            none[k + 1], first[k + 1] = "ours", "ours";
            if (k == 2) then
                BENCH_BUNDLE_EXPR = table.concat(none, "; ");
            end
            add("F", format("bundle of %d clauses x 3, none matches: one parse", k),
                "x = SecureCmdOptionParse(" .. q(table.concat(none, "; ")) .. ")");
            add("F", format("bundle of %d clauses x 3, first matches: one parse", k),
                "x = SecureCmdOptionParse(" .. q(table.concat(first, "; ")) .. ")");
            for j = 1, m do
                measure[j] = format("do local v = (%s) and true or false local cc = BenchCols[%d] "
                    .. "if (cc.cell ~= v) then cc.cell = v end end", usable[j].fn, j);
            end
            add("F", format("the same %d columns measured and compared, unchanged", m), table.concat(measure, "\n"));
        end
    end
    add("F", "judging loop: 4 entries x 2 checks, all fail on the first", [==[
local b = BenchBundle
for e = 1, #b do
    local entry = b[e]
    local match = true
    for c = 1, #entry, 2 do
        local cell = entry[c].cell
        if ((entry[c + 1] % (cell + cell)) < cell) then
            match = false
            break
        end
    end
    if (match) then
        break
    end
end]==]);

    -- H: splitting one expression into several parses, and pulling a shared part out of several
    -- keys. `cheap` skips `flyable` and `advflyable`, which cost twenty times the rest.
    local cheap = {};
    for _, w in ipairs(usable) do
        if (not strfind(w.fn, "Flyable", 1, true)) then
            cheap[#cheap + 1] = w;
        end
    end
    local function group(from, to, falseAt)
        local list = {};
        for k = from, to do
            list[#list + 1] = (k == falseAt) and cheap[k].fTok or cheap[k].tTok;
        end
        return "[" .. table.concat(list, ",") .. "]";
    end
    local function p(expr)
        return "SecureCmdOptionParse(" .. q(expr) .. ")";
    end
    if (#cheap >= 12) then
        for _, shape in ipairs({ { "all true", nil }, { "first false", 1 }, { "last false", 6 } }) do
            local f = shape[2];
            add("H", format("[a,b,c] and [d,e,f], %s: two parses", shape[1]),
                "x = " .. p(group(1, 3, f)) .. " and " .. p(group(4, 6, f)));
            add("H", format("[a,b,c,d,e,f], %s: one parse", shape[1]), "x = " .. p(group(1, 6, f)));
        end

        -- K keys, each `[common,own]`: three common tokens and two of its own. Separately, every key
        -- parses all five; pulled out, the common three are parsed once and each key parses its own
        -- two only while the common part holds.
        for _, keys in ipairs({ 2, 4, 8 }) do
            for _, commonTrue in ipairs({ true, false }) do
                local common = group(1, 3, (not commonTrue) and 1 or nil);
                local separate, pulled = {}, {};
                for k = 1, keys do
                    local a = 4 + ((k - 1) % 4) * 2;
                    a = (a + 1 <= #cheap) and a or 4;
                    local own = group(a, a + 1);
                    local both = "[" .. strsub(common, 2, -2) .. "," .. strsub(own, 2, -2) .. "]";
                    separate[k] = "x = " .. p(both);
                    pulled[k] = "x = " .. p(own);
                end
                local label = commonTrue and "common part true" or "common part false";
                add("H", format("%d keys, %s: each parses common + own", keys, label), table.concat(separate, "\n"));
                add("H", format("%d keys, %s: common once, then own", keys, label),
                    "if (" .. p(common) .. ") then\n" .. table.concat(pulled, "\n") .. "\nend");
            end
        end
    end

    -- Where the costly word sits: behind a false token the parse stops before reaching it.
    if (#cheap >= 1) then
        add("H", "[<false>,flyable]: stops before flyable", "x = " .. p("[" .. cheap[1].fTok .. ",flyable]"));
        add("H", "[flyable,<false>]: flyable first", "x = " .. p("[flyable," .. cheap[1].fTok .. "]"));
        add("H", "[<false>,advflyable]", "x = " .. p("[" .. cheap[1].fTok .. ",advflyable]"));
    end
    -- An alias written straight into the expression by a wake, so the beat needs no composition.
    add("H", "bundle with a baked @unit: [@focus,help,nodead] ours; [combat] release; ours",
        "x = " .. p("[@focus,help,nodead] ours; [combat] release; ours"));
    -- A value out of the parse, used to pick the binding.
    add("H", "parse result compared to the last one (local)", "local r = " .. p("[combat] release; ours")
        .. " if (r ~= last) then last = r end", "local last");
    add("H", "parse result compared to the last one (table field)", "local r = " .. p("[combat] release; ours")
        .. " if (r ~= BenchColumn.last) then BenchColumn.last = r end");

    -- I: what `no` costs. `[w]` and `[now]` also answer opposite ways, so each pair is logged with
    -- which one is true, and the same comparison is made again behind a true token, where both
    -- forms are read to the end.
    local lead = cheap[1];
    for k = 2, #cheap do
        local w = cheap[k];
        local bare = strmatch(w.tTok, "^no(.+)$") or w.tTok;
        local bareTrue = (bare == w.tTok);
        add("I", format("parse [%s] (%s)", bare, bareTrue and "true" or "false"), "x = " .. p("[" .. bare .. "]"));
        add("I", format("parse [no%s] (%s)", bare, bareTrue and "false" or "true"), "x = " .. p("[no" .. bare .. "]"));
        add("I", format("parse [<true>,%s]", bare), "x = " .. p("[" .. lead.tTok .. "," .. bare .. "]"));
        add("I", format("parse [<true>,no%s]", bare), "x = " .. p("[" .. lead.tTok .. ",no" .. bare .. "]"));
    end
    -- Four tokens, all true either way, written once with as few `no` as the answers allow and once
    -- with as many.
    local fewNo, manyNo, fewCount, manyCount = {}, {}, 0, 0;
    for k = 1, #cheap do
        local w = cheap[k];
        if (strsub(w.tTok, 1, 2) == "no") then
            if (manyCount < 4) then
                manyCount = manyCount + 1;
                manyNo[manyCount] = w.tTok;
            end
        elseif (fewCount < 4) then
            fewCount = fewCount + 1;
            fewNo[fewCount] = w.tTok;
        end
    end
    if (fewCount == 4) then
        add("I", "4 true tokens with no `no`", "x = " .. p("[" .. table.concat(fewNo, ",") .. "]"));
    end
    if (manyCount == 4) then
        add("I", "4 true tokens, all `no`", "x = " .. p("[" .. table.concat(manyNo, ",") .. "]"));
    end

    -- J: what a beat costs before it measures anything, and what a driver costs. Restricted cases
    -- write another frame's attribute through a frame ref, so its handler runs the way a beat's
    -- does: from secure code (`CallRestrictedClosure` refuses an insecure caller). Insecure cases
    -- copy what Blizzard's manager does per tick for one driver and for one unit watch.
    local function r(name, stmt, prelude)
        add("J", name, stmt, prelude);
        cases[#cases].only = "r";
    end
    local function i(name, stmt, prelude)
        add("J", name, stmt, prelude);
        cases[#cases].only = "i";
    end
    r("SetAttribute on a frame with no handler", [[t:SetAttribute("v", i)]], [[local t = self:GetFrameRef("tPlain")]]);
    r("SetAttribute into an empty _onattributechanged", [[t:SetAttribute("v", i)]],
        [[local t = self:GetFrameRef("tAttr")]]);
    r("SetAttribute into an empty _onstate-beat", [[t:SetAttribute("state-beat", i)]],
        [[local t = self:GetFrameRef("tState")]]);
    r("the whole fixed beat: write \"a\", handler resets to 0, handler again", [[t:SetAttribute("state-beat", "a")]],
        [[local t = self:GetFrameRef("tBeat")]]);
    r("RegisterAttributeDriver, same expression (no change)",
        [[RegisterAttributeDriver(t, "state-x", "[combat] a; b")]], [[local t = self:GetFrameRef("tDrv")]]);
    r("RegisterAttributeDriver, value flips each call (frame with no handler)",
        [[RegisterAttributeDriver(t, "state-x", (i % 2 == 0) and "[combat] a; b" or "[nocombat] a; b")]],
        [[local t = self:GetFrameRef("tDrv")]]);
    r("RegisterAttributeDriver, value flips each call (frame with an empty handler)",
        [[RegisterAttributeDriver(t, "state-x", (i % 2 == 0) and "[combat] a; b" or "[nocombat] a; b")]],
        [[local t = self:GetFrameRef("tAttr")]]);
    i("manager tick, one driver \"a\" (parse, tonumber, GetAttribute, compare)",
        [[local v = SecureCmdOptionParse("a") v = tonumber(v) or v x = (v ~= f:GetAttribute("state-x"))]],
        "local f = BenchSimFrame");
    i("manager tick, one bundle driver (2 clauses x 3)",
        "local v = SecureCmdOptionParse(" .. q(BENCH_BUNDLE_EXPR or "[combat] a; b") .. ") v = tonumber(v) or v "
        .. [[x = (v ~= f:GetAttribute("state-x"))]], "local f = BenchSimFrame");
    i("manager tick, one unit watch on player (GetUnit, cache, GetAttribute)",
        [[local u = SecureButton_GetUnit(f) local e = cache[u] if (e == nil) then e = UnitExists(u) or UnitIsVisible(u) cache[u] = e end ]]
        .. [[x = (f:GetAttribute("state-unitexists") ~= (e or false)) wipe(cache)]],
        "local f = BenchSimFrame local cache = {}");
    i("GetAttribute on a plain frame", [[x = f:GetAttribute("state-x")]], "local f = BenchSimFrame");
    i("SetAttribute on a plain frame", [[f:SetAttribute("v", i)]], "local f = BenchSimFrame");

    -- The beat carried by `state-visibility` instead of a driver that is put back to 0. A write of
    -- the value already there either reaches the handler (about the 4.4 of a changing write) or
    -- does not (about the 1.2 of a frame with no handler); the two insecure cases below copy the
    -- manager's tick whole, handler included, for the beat as it is and as it would be. They need
    -- the frames `MakeBenchFrames` made, so a run in combat leaves them blank.
    r("SetAttribute, the same value, into an empty _onattributechanged", [[t:SetAttribute("v", 1)]],
        [[local t = self:GetFrameRef("tAttr")]]);
    r("SetAttribute, nil over nil, into an empty _onattributechanged", [[t:SetAttribute("statehidden", nil)]],
        [[local t = self:GetFrameRef("tAttr")]]);
    i("Show() on a frame already shown", "f:Show()", "local f = BenchSimFrame");
    i("manager tick as the beat is now: parse \"a\", GetAttribute, write, handler resets to 0, handler again",
        [[local v = SecureCmdOptionParse("a") v = tonumber(v) or v ]]
        .. [[if (v ~= f:GetAttribute("state-beat")) then f:SetAttribute("state-beat", v) end]],
        "local f = BenchBeatFrame");
    i("manager tick through state-visibility: parse \"show\", Show, write statehidden nil, an empty handler",
        [[local v = SecureCmdOptionParse("show") if (v == "show") then f:Show() f:SetAttribute("statehidden", nil) end]],
        "local f = BenchAttrFrame");
    i("the same tick with no handler behind it",
        [[local v = SecureCmdOptionParse("show") if (v == "show") then f:Show() f:SetAttribute("statehidden", nil) end]],
        "local f = BenchPlainFrame");

    -- L: the unit tokens an alias (`@custom1`, `@tank`, `@hover`, ...) is written into an expression
    -- as at a wake (`trimming-the-tail-key-beat.md` 8-2, D5). `raid41` is what an alias with nobody
    -- behind it becomes (`COMPOSE_MACROTEXT_SNIPPET`). Each with the usual tail and with `exists`
    -- alone, since a missing unit may end the clause before the rest is read.
    for _, unit in ipairs({
        "player", "target", "focus", "mouseover", "pet", "party1", "party4", "raid1", "raid25", "raid40",
        "raid41", "nameplate1", "nameplate40", "boss1", "arena1", "targettarget", "focustarget",
        "party1target", "raid1target", "none",
    }) do
        add("L", format("parse [@%s,help,nodead]", unit), "x = " .. p(format("[@%s,help,nodead]", unit)));
        add("L", format("parse [@%s,exists]", unit), "x = " .. p(format("[@%s,exists]", unit)));
    end

    -- M: tokens that could stand in for `known:0`, the always-false token a false switch reference
    -- is composed into (`COMPOSE_MACROTEXT_SNIPPET`). Alone, and leading a group so the rest is
    -- never judged.
    for _, token in ipairs({ "known:0", "bar:99", "form:99", "spec:9", "btn:99", "mod,nomod", "bonusbar:99" }) do
        add("M", format("parse [%s]", token), "x = " .. p(format("[%s]", token)));
        add("M", format("parse [%s,combat]", token), "x = " .. p(format("[%s,combat]", token)));
    end

    -- N: every group is written the way it is false now, so the parse reads the whole text. The
    -- "last true" text ends in one group that holds: a parse that stopped short answers nil there.
    --
    -- **Which way a group answers cannot move between writing it here and parsing it**: the whole
    -- run, `WatchChecks` included, is one script execution inside one frame, the cursor's unit with
    -- it.
    --
    -- Four kinds of group, since a watch holds all of them: one state word; two state words that
    -- hold ahead of one that does not, which is what a group led by a reach condition judges; a
    -- unit asked only whether it is there; and a unit that is there asked a reaction that holds and
    -- then the death that does not, read to its last word.
    wipe(watchChecks);
    if (#cheap >= 3) then
        local pools = { state = {}, state3 = {}, unit = {}, present = {} };
        for k, w in ipairs(cheap) do
            pools.state[k] = "[" .. w.fTok .. "]";
            pools.state3[k] = format("[%s,%s,%s]", w.tTok, cheap[k % #cheap + 1].tTok,
                cheap[(k + 1) % #cheap + 1].fTok);
        end
        for k, unit in ipairs(WATCH_UNITS) do
            local exists = SecureCmdOptionParse(format("[@%s,exists]", unit)) ~= nil;
            pools.unit[k] = format("[@%s,%s]", unit, exists and "noexists" or "exists");
        end
        local there = {};
        for _, unit in ipairs({ "player", "target", "focus", "pet" }) do
            if (SecureCmdOptionParse(format("[@%s,exists]", unit))) then
                local reaction = SecureCmdOptionParse(format("[@%s,help]", unit)) and "help" or "nohelp";
                local death = SecureCmdOptionParse(format("[@%s,dead]", unit)) and "nodead" or "dead";
                pools.present[#pools.present + 1] = format("[@%s,%s,%s]", unit, reaction, death);
                there[#there + 1] = unit;
            end
        end
        local tail = "[" .. cheap[1].tTok .. "]";
        for _, kind in ipairs({
            { "state", "groups of one state word" },
            { "state3", "groups of three state words, false at the last" },
            { "unit", "groups of @unit,exists" },
            { "present", "groups of @unit,reaction,death false at the last, on " .. table.concat(there, " ") },
        }) do
            local pool = pools[kind[1]];
            for _, n in ipairs({ 4, 16, 64, 128, 256 }) do
                if (#pool > 0) then
                    local list = {};
                    for k = 1, n do
                        list[k] = pool[(k - 1) % #pool + 1];
                    end
                    local allFalse = table.concat(list);
                    list[n] = tail;
                    watchChecks[#watchChecks + 1] = {
                        n = n, kind = kind[2], allFalse = allFalse, lastTrue = table.concat(list),
                    };
                    add("N", format("watch of %d %s, all false (%d chars)", n, kind[2], #allFalse),
                        "x = " .. p(allFalse));
                    cases[#cases].count = LONG_COUNT;
                end
            end
        end

        -- A watch asks "left the default cell" of a mask column as one token with a slash list where
        -- it would otherwise be a group for every value. What the list costs a value is not in the
        -- bench: it prices the token as one word. Which way the list answers now rides on the label.
        local TEN = "form:1/2/3/4/5/6/7/8/9/10";
        local inForm = SecureCmdOptionParse("[" .. TEN .. "]") ~= nil;
        local now = inForm and "true now" or "false now";
        add("N", "one token [form:1] (" .. now .. " for the ten-value list)", "x = " .. p("[form:1]"));
        add("N", "one token [form:1/2/3/4/5]", "x = " .. p("[form:1/2/3/4/5]"));
        add("N", "one token [" .. TEN .. "] (" .. now .. ")", "x = " .. p("[" .. TEN .. "]"));
        add("N", "one token [no" .. TEN .. "]", "x = " .. p("[no" .. TEN .. "]"));
        add("N", "one token [bonusbar:1/2/3/4/5]", "x = " .. p("[bonusbar:1/2/3/4/5]"));
        local tenGroups = {};
        for k = 1, 10 do
            tenGroups[k] = "[form:" .. k .. "]";
        end
        add("N", "ten groups [form:1]...[form:10]", "x = " .. p(table.concat(tenGroups)));
        local sixteen = {};
        for k = 1, 16 do
            sixteen[k] = pools.state[(k - 1) % #pools.state + 1];
        end
        add("N", "16 false state groups alone", "x = " .. p(table.concat(sixteen)));
        add("N", "16 false state groups + the ten-value token", "x = " .. p(table.concat(sixteen) .. "[" .. TEN .. "]"));
        add("N", "16 false state groups + the ten groups",
            "x = " .. p(table.concat(sixteen) .. table.concat(tenGroups)));

        -- A watch that names the column that moved writes each column's groups as a clause with the
        -- column's number for its text. What a clause with a value costs over a bare group is the one
        -- price that step is computed on and never measured.
        local bare, numbered, lastHolds = {}, {}, {};
        for k = 1, 13 do
            local falseGroup = pools.state[(k - 1) % #pools.state + 1];
            bare[k] = falseGroup;
            numbered[k] = falseGroup .. " " .. k;
            lastHolds[k] = ((k == 13) and tail or falseGroup) .. " " .. k;
        end
        add("N", "13 false groups, bare", "x = " .. p(table.concat(bare)));
        add("N", "13 false clauses, a number each", "x = " .. p(table.concat(numbered, "; ")));
        add("N", "13 clauses, a number each, the last holds", "x = " .. p(table.concat(lastHolds, "; ")));
    end

    -- P: three columns of three cells each, so 27 joint states, and the state measured is number 7
    -- (`BenchIndex`: 1 + 3 * 2 + 9 * 0). Its answer is "release", which the number form reaches on
    -- its second question and the loop on its fourth entry, after three entries that pass their
    -- first check and fail their second. The operands are locals read from tables, never literals:
    -- a literal `2 ^ 7` is folded when the body is compiled and would time nothing.
    add("P", "a bit asked of a small number (locals)", "x = (T % (p + p)) >= p", "local T, p = 6, 2");
    add("P", "a bit asked of a number near 2^53 (locals)", "x = (T % (p + p)) >= p",
        "local n = BenchIndex[1] local p = 2 ^ (n + 49) local T = 2 ^ (n + 51) + p + 12345");
    add("P", "2 ^ n", "x = 2 ^ n", "local n = BenchIndex[1] + 36");
    add("P", "ldexp(1, n)", "x = ldexp(1, n)", "local n = BenchIndex[1] + 36");
    add("P", "strbyte(s, n)", "x = strbyte(s, n)", "local s, n = BenchTable.answers, BenchIndex[1] + 7");
    add("P", "s:byte(n)", "x = s:byte(n)", "local s, n = BenchTable.answers, BenchIndex[1] + 7");
    add("P", "strsub(s, n, n)", "x = strsub(s, n, n)", "local s, n = BenchTable.answers, BenchIndex[1] + 7");
    add("P", "array read t[n] (local table)", "x = t[n]", "local t, n = BenchTable.list, BenchIndex[1] + 7");
    add("P", "joint index of 3 columns from a local table", "x = c[1] + 3 * c[2] + 9 * c[3]", "local c = BenchIndex");
    add("P", "judging loop: 4 entries x 2 checks, the fourth matches", [==[
local b = BenchLoopBundle
for e = 1, #b do
    local entry = b[e]
    local match = true
    for c = 1, #entry, 2 do
        local cell = entry[c].cell
        if ((entry[c + 1] % (cell + cell)) < cell) then
            match = false
            break
        end
    end
    if (match) then
        x = e
        break
    end
end]==]);
    local JOINT = "local b = BenchTable\nlocal c = BenchIndex\nlocal n = c[1] + 3 * c[2] + 9 * c[3]\n";
    add("P", "table as two numbers, 2 ^ n, answered by the second", JOINT .. [==[
local p = 2 ^ n
local T = b.ours
if ((T % (p + p)) >= p) then
    x = 1
else
    T = b.release
    if ((T % (p + p)) >= p) then
        x = 2
    else
        x = 3
    end
end]==]);
    add("P", "table as two numbers, ldexp, answered by the second", JOINT .. [==[
local p = ldexp(1, n)
local T = b.ours
if ((T % (p + p)) >= p) then
    x = 1
else
    T = b.release
    if ((T % (p + p)) >= p) then
        x = 2
    else
        x = 3
    end
end]==]);
    add("P", "table as a string, strbyte", JOINT .. "x = strbyte(b.answers, n + 1)");
    add("P", "table as an array", JOINT .. "x = b.list[n + 1]");

    -- A numbered column's parse answers digits as text. `tonumber` is a function of the environment,
    -- so its name is a global read like `strbyte`'s above; `text + 0` asks the VM for the same number
    -- with no name to find. The text comes out of a parse so nothing here is a compile-time constant.
    local DIGIT = [[local s = SecureCmdOptionParse("[known:0] 2; 4")]];
    local DIGITS = [[local s = SecureCmdOptionParse("[known:0] 2; 1024")]];
    add("P", "tonumber(s), one digit", "x = tonumber(s)", DIGIT);
    add("P", "s + 0, one digit", "x = s + 0", DIGIT);
    add("P", "tonumber(s), four digits", "x = tonumber(s)", DIGITS);
    add("P", "s + 0, four digits", "x = s + 0", DIGITS);
    add("P", "a numbered parse alone", [[x = SecureCmdOptionParse("[known:0] 2; 4")]]);
    add("P", "a numbered parse through tonumber", [[x = tonumber(SecureCmdOptionParse("[known:0] 2; 4"))]]);
    add("P", "a numbered parse + 0", [[x = SecureCmdOptionParse("[known:0] 2; 4") + 0]]);

    -- The form asked by its clauses and by one call, as the whole lines a body would carry and not
    -- as their parts added up: mixing a call and a bit test into what was one parse has costs of
    -- its own (the call's name, the record's mask read, a parse that still has to be made for the
    -- record's other words). What `form` costs depends on the class, so the run's class is logged
    -- (`Situation`), and the comparison is only worth reading beside it.
    local formClauses = {};
    for n = 1, 10 do
        formClauses[n] = format("[form:%d] %d; ", n, 2 ^ n);
    end
    add("P", "forms cell, ten clauses + 0 (the loop today)",
        "x = SecureCmdOptionParse(" .. q(table.concat(formClauses) .. "1") .. ") + 0");
    add("P", "forms cell, one call, clamp, 2 ^ n",
        "local n = GetShapeshiftForm() if (n > 10) then n = 0 end x = 2 ^ n");
    if (#cheap >= 1) then
        local held = cheap[1].tTok;
        local withForm = "x = " .. p("[" .. held .. ",form:1/2]");
        local withoutForm = "x = " .. p("[" .. held .. "]") .. " and ((m % (c + c)) >= c)";
        local onlyForm = "x = " .. p("[form:1/2]");
        local CALL = "local n = GetShapeshiftForm() if (n > 10) then n = 0 end local c = 2 ^ n local m = BenchIndex[2] + 4\n";
        add("P", "press, 1 record: one parse of [<held>,form:1/2]", withForm);
        add("P", "press, 1 record: one call, then [<held>] parsed and a bit test", CALL .. withoutForm);
        add("P", "press, 4 records: four parses of [<held>,form:1/2]", strrep(withForm .. "\n", 4));
        add("P", "press, 4 records: one call, then four of [<held>] parsed and a bit test",
            CALL .. strrep(withoutForm .. "\n", 4));
        add("P", "press, 4 records with form alone: four parses of [form:1/2]", strrep(onlyForm .. "\n", 4));
        add("P", "press, 4 records with form alone: one call and four bit tests",
            CALL .. strrep("x = (m % (c + c)) >= c\n", 4));
    end

    -- G
    add("G", "compose, 1 switch arg", format(COMPOSE, "BenchEntry1") .. "x = s");
    add("G", "compose, 1 switch arg + parse", format(COMPOSE, "BenchEntry1") .. "x = SecureCmdOptionParse(s)");
    add("G", "compose, 2 switches + 1 alias", format(COMPOSE, "BenchEntry3") .. "x = s");
    add("G", "compose, 2 switches + 1 alias + parse", format(COMPOSE, "BenchEntry3") .. "x = SecureCmdOptionParse(s)");

    return cases, #usable;
end

local header;

local function Median(list)
    table.sort(list);
    return list[(#list + 1) / 2];
end

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
    end
    -- The class and how many forms it has: what `form` costs depends on them (0.14 on a warlock,
    -- 1.14 on a druid), and a run that does not say which it was cannot be read later.
    return format("class=%s forms=%d combat=%s mounted=%s flying=%s submerged=%s form=%s group=%s target=%s pet=%s",
        tostring((select(2, UnitClass("player")))), GetNumShapeshiftForms(),
        b(UnitAffectingCombat("player")), b(IsMounted()), b(IsFlying()), b(IsSubmerged()),
        tostring(GetShapeshiftForm()), (IsInRaid() and "raid") or (IsInGroup() and "party") or "none",
        target, tostring((UnitCreatureFamily("pet"))));
end

--- Group N's answers that are not timings, appended to `lines`.
---
--- A column whose cell is "its reach condition and itself" parses a state word and a unit's words
--- in one group (`[combat,@target,help]`). That is only right if the state word still asks about
--- the player there and the unit's words still ask about the unit, whatever the order.
local function WatchChecks(lines)
    for _, check in ipairs(watchChecks) do
        local quiet = SecureCmdOptionParse(check.allFalse);
        local hit = SecureCmdOptionParse(check.lastTrue);
        lines[#lines + 1] = format("N     watch of %d %s groups, %d chars: all false -> %s; last true -> %s",
            check.n, check.kind, #check.allFalse,
            (quiet == nil) and "nil, as it should" or ("WRONG, answered " .. tostring(quiet)),
            (hit ~= nil) and "read to the end" or "WRONG, nil: the tail was not read");
    end

    local units = { "target", "focus", "mouseover", "player" };
    -- `WORDS`, and the words of the mask columns and `known`, which a reach condition carries too.
    local words = { "form:1", "form:2", "bonusbar:5", "group:raid", "group:party", "known:686" };
    for _, w in ipairs(WORDS) do
        words[#words + 1] = w[1];
    end

    local function plain(v)
        if (issecretvalue and issecretvalue(v)) then
            return nil;
        end
        return v and true or false;
    end

    local compared, differ = 0, 0;
    local function same(label, text, expected)
        compared = compared + 1;
        local answer = SecureCmdOptionParse(text) ~= nil;
        if (answer ~= expected) then
            differ = differ + 1;
            lines[#lines + 1] = format("N     DIFFERS (%s): %s is %s", label, text, tostring(answer));
        end
    end

    -- **Agreeing proves nothing where both readings give the same answer**, so the comparisons that
    -- could have told them apart are counted on their own. An `@unit` that fails its group when
    -- nobody is there shows only with the unit absent and the word holding. A word that follows the
    -- unit shows only where the unit's answer is not the player's, and `combat` is the one word with
    -- a call that reads a unit's.
    local absentTelling, combatTelling = 0, 0;
    local playerCombat = SecureCmdOptionParse("[combat]") ~= nil;
    for _, word in ipairs(words) do
        for _, token in ipairs({ word, "no" .. word }) do
            local alone = SecureCmdOptionParse("[" .. token .. "]") ~= nil;
            for _, unit in ipairs(units) do
                local exists = plain(UnitExists(unit));
                if (exists == false and alone) then
                    absentTelling = absentTelling + 1;
                end
                if (word == "combat" and exists) then
                    local unitCombat = plain(UnitAffectingCombat(unit));
                    if (unitCombat ~= nil and unitCombat ~= playerCombat) then
                        combatTelling = combatTelling + 1;
                    end
                end
                same("state word beside @unit", format("[@%s,%s]", unit, token), alone);
                same("state word ahead of @unit", format("[%s,@%s]", token, unit), alone);
                -- With the state word holding, the group is the unit's own answer in every order.
                if (alone) then
                    for _, asked in ipairs({ "exists", "help", "harm", "dead" }) do
                        for _, unitWord in ipairs({ asked, "no" .. asked }) do
                            local own = SecureCmdOptionParse(format("[@%s,%s]", unit, unitWord)) ~= nil;
                            same("unit word after a state word", format("[%s,@%s,%s]", token, unit, unitWord), own);
                            same("state word between", format("[@%s,%s,%s]", unit, token, unitWord), own);
                            same("state word last", format("[@%s,%s,%s]", unit, unitWord, token), own);
                        end
                    end
                end
            end
        end
    end
    local there = {};
    for k, unit in ipairs(units) do
        there[k] = unit .. "=" .. ((plain(UnitExists(unit)) and "T") or "F");
    end
    lines[#lines + 1] = format("N     state words mixed with @unit: %d texts compared, %d differ (exists: %s)",
        compared, differ, table.concat(there, " "));
    lines[#lines + 1] = format("N     able to tell an absent @unit failing its group: %d%s", absentTelling,
        (absentTelling == 0) and " -- NONE, unanswered by this run" or "");
    lines[#lines + 1] = format("N     able to tell `combat` following the unit: %d%s", combatTelling,
        (combatTelling == 0) and " -- NONE, unanswered by this run: it takes a unit whose combat is not the player's"
            or "");
end

--- **Does a write that changes nothing still reach the handler, and does the manager make one on
--- every tick of a `state-visibility` driver?** Asked of this client and not of the reference
--- source: the handler counts its own entries. The driver's count arrives two seconds later, as a
--- line added to the saved run, so the reload has to wait for it.
local function VisibilityChecks(lines)
    local frame = benchFrames and benchFrames.tCount;
    if (not frame or InCombatLockdown()) then
        lines[#lines + 1] = "J     state-visibility: not asked (in combat)";
        return;
    end
    local function entries(write)
        frame:SetAttribute("ticks", 0);
        for _ = 1, 10 do
            write();
        end
        return frame:GetAttribute("ticks");
    end
    lines[#lines + 1] = format("J     10 writes of statehidden = nil over nil: the handler ran %d times",
        entries(function() frame:SetAttribute("statehidden", nil) end));
    frame:SetAttribute("statehidden", true);
    lines[#lines + 1] = format("J     10 writes of statehidden = true over true: the handler ran %d times",
        entries(function() frame:SetAttribute("statehidden", true) end));
    frame:SetAttribute("statehidden", nil);

    -- **The window opens on a later frame, never here.** This run freezes the client for seconds and
    -- the frame after it carries all of that as its elapsed time, so a timer set now fires on that
    -- very frame: the first version did, counted the one write registration makes, and read as "the
    -- manager does not write every tick" over a window of no frames at all. The frames are counted
    -- for the same reason, so the line shows what the window really held.
    local function report(line)
        local run = DebindDevDB and DebindDevDB.beatCost and DebindDevDB.beatCost[1];
        if (run) then
            run.lines[#run.lines + 1] = line;
        end
        print(TAG .. line .. ". /reload now.");
    end
    C_Timer.After(0.5, function()
        if (InCombatLockdown()) then
            report("J     a state-visibility \"show\" driver: not asked (combat began)");
            return;
        end
        local frames = 0;
        local counter = CreateFrame("Frame");
        counter:SetScript("OnUpdate", function() frames = frames + 1; end);
        frame:SetAttribute("ticks", 0);
        local started = GetTime();
        RegisterAttributeDriver(frame, "state-visibility", "show");
        local atRegistration = frame:GetAttribute("ticks");
        C_Timer.After(2, function()
            local ticks = frame:GetAttribute("ticks");
            counter:SetScript("OnUpdate", nil);
            if (not InCombatLockdown()) then
                UnregisterAttributeDriver(frame, "state-visibility");
            end
            report(format("J     a state-visibility \"show\" driver: the handler ran %d times at registration and %d more "
                .. "over %.2f s and %d frames (shown=%s)", atRegistration, ticks - atRegistration,
                GetTime() - started, frames, tostring(frame:IsShown())));
        end);
    end);
end

local function Run()
    local restricted = not InCombatLockdown();
    if (restricted) then
        if (not header) then
            header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate");
        end
        header:SetAttribute("BenchNoop", "local y = 1");
        MakeBenchFrames(header);
        SecureHandlerExecute(header, SETUP);
    end
    local setup = loadstring(SETUP);
    setfenv(setup, insecureEnv);
    setup();

    local cases, usable = Cases();
    local bodies, funcs, rS, iS = {}, {}, {}, {};
    for n, case in ipairs(cases) do
        bodies[n] = format("local x %s\nfor i = 1, %d do\n%s\nend", case.prelude or "", case.count or COUNT,
            case.stmt);
        assert(not strfind(bodies[n], "function", 1, true), case.name);
        if (case.only ~= "r" and not strfind(case.stmt, "self:", 1, true)) then
            local f, err = loadstring(bodies[n]);
            if (f) then
                setfenv(f, insecureEnv);
                funcs[n] = f;
            else
                print(TAG .. "insecure compile failed: " .. case.name .. ": " .. tostring(err));
            end
        end
        rS[n], iS[n] = {}, {};
    end

    local failed = {};
    for _ = 1, ROUNDS do
        for n = 1, #cases do
            local start;
            if (restricted and not failed[n] and cases[n].only ~= "i") then
                start = debugprofilestop();
                local ok = pcall(SecureHandlerExecute, header, bodies[n]);
                local spent = debugprofilestop() - start;
                if (ok) then
                    rS[n][#rS[n] + 1] = spent;
                else
                    failed[n] = true;
                end
            end
            if (funcs[n]) then
                start = debugprofilestop();
                local ok = pcall(funcs[n]);
                local spent = debugprofilestop() - start;
                if (ok) then
                    iS[n][#iS[n] + 1] = spent;
                end
            end
        end
    end

    -- Group J left drivers on two of its frames; take them off so the manager stops ticking them.
    if (benchFrames) then
        UnregisterAttributeDriver(benchFrames.tDrv, "state-x");
        UnregisterAttributeDriver(benchFrames.tAttr, "state-x");
    end

    local rEmpty = restricted and Median(rS[1]);
    local iEmpty = Median(iS[1]);
    local lines = {
        format("us a call: %d calls a body, median of %d rounds, less the empty loop (restricted %s ms, insecure %.4f ms)",
            COUNT, ROUNDS, rEmpty and format("%.4f", rEmpty) or "-", iEmpty),
        Situation(),
        format("words usable for D-F (macro and call agree now): %d", usable),
        "group  restricted   insecure  case",
    };
    -- The two empty loops are cases 1 and 2.
    local rEmptyLong = restricted and Median(rS[2]);
    local iEmptyLong = Median(iS[2]);
    for n = 3, #cases do
        local count, rBase, iBase = COUNT, rEmpty, iEmpty;
        if (cases[n].count) then
            count, rBase, iBase = cases[n].count, rEmptyLong, iEmptyLong;
        end
        local r = (restricted and #rS[n] > 0) and format("%10.3f", (Median(rS[n]) - rBase) * 1000 / count)
            or (failed[n] and "    failed" or "         -");
        local i = (#iS[n] > 0) and format("%10.3f", (Median(iS[n]) - iBase) * 1000 / count) or "         -";
        lines[#lines + 1] = format("%-5s %s %s  %s", cases[n].group, r, i, cases[n].name);
    end
    WatchChecks(lines);
    VisibilityChecks(lines);

    -- The last run only. Earlier ones are copied into the plan doc's 7-1 once read, and kept here
    -- they only grow the file.
    DebindDevDB = DebindDevDB or {};
    DebindDevDB.beatCost = { { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()), lines = lines } };
    print(TAG .. format("done: %d cases, saved in DebindDevDB.beatCost (earlier runs dropped). "
        .. "One more line follows in two seconds; /reload after it.", #cases - 1));
end

SLASH_DEBINDBC1 = "/debbc";
SlashCmdList.DEBINDBC = function()
    Run();
end;
