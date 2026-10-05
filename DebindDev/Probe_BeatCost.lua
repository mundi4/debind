-- Probe_BeatCost.lua
-- One-shot probe: what every piece the tail-key beat could be built from costs, in one run
-- (`trimming-the-tail-key-beat.md`).
--
--   /debbc      run it out of combat (a second or two of frozen frames), then /reload
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
--
-- Answer found, delete the file and its TOC line.

local TAG = "|cffff9900[BC]|r ";
local COUNT, ROUNDS = 1000, 15;

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

local function Cases()
    local cases = {};
    local function add(group, name, stmt, prelude)
        cases[#cases + 1] = { group = group, name = name, stmt = stmt, prelude = prelude };
    end

    -- A
    add("A", "empty", "");
    add("A", "mask arithmetic on locals", "x = (m % (c + c)) >= c", "local c, m = 2, 6");
    add("A", "global read", "x = BenchColumn");
    add("A", "global table field read", "x = BenchColumn.cell");
    add("A", "global table, index, field read", "x = BenchColumns[3].cell");
    add("A", "local table field read", "x = t.cell", "local t = BenchColumn");
    add("A", "local table field write", "t.stamp = i", "local t = BenchColumn");
    add("A", "read + compare, unchanged (one column's mark)",
        "local cc = BenchCols[1] if (cc.cell ~= false) then cc.cell = false end");
    add("A", "read + mask (one gate term)", "local cc = BenchColumns[3].cell x = (m % (cc + cc)) >= cc", "local m = 6");
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
    return format("combat=%s mounted=%s flying=%s submerged=%s form=%s group=%s target=%s pet=%s",
        b(UnitAffectingCombat("player")), b(IsMounted()), b(IsFlying()), b(IsSubmerged()),
        tostring(GetShapeshiftForm()), (IsInRaid() and "raid") or (IsInGroup() and "party") or "none",
        target, tostring((UnitCreatureFamily("pet"))));
end

local function Run()
    local restricted = not InCombatLockdown();
    if (restricted) then
        if (not header) then
            header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate");
        end
        header:SetAttribute("BenchNoop", "local y = 1");
        SecureHandlerExecute(header, SETUP);
    end
    local setup = loadstring(SETUP);
    setfenv(setup, insecureEnv);
    setup();

    local cases, usable = Cases();
    local bodies, funcs, rS, iS = {}, {}, {}, {};
    for n, case in ipairs(cases) do
        bodies[n] = format("local x %s\nfor i = 1, %d do\n%s\nend", case.prelude or "", COUNT, case.stmt);
        assert(not strfind(bodies[n], "function", 1, true), case.name);
        if (not strfind(case.stmt, "self:", 1, true)) then
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
            if (restricted and not failed[n]) then
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

    local rEmpty = restricted and Median(rS[1]);
    local iEmpty = Median(iS[1]);
    local lines = {
        format("us a call: %d calls a body, median of %d rounds, less the empty loop (restricted %s ms, insecure %.4f ms)",
            COUNT, ROUNDS, rEmpty and format("%.4f", rEmpty) or "-", iEmpty),
        Situation(),
        format("words usable for D-F (macro and call agree now): %d", usable),
        "group  restricted   insecure  case",
    };
    for n = 2, #cases do
        local r = (restricted and #rS[n] > 0) and format("%10.3f", (Median(rS[n]) - rEmpty) * 1000 / COUNT)
            or (failed[n] and "    failed" or "         -");
        local i = (#iS[n] > 0) and format("%10.3f", (Median(iS[n]) - iEmpty) * 1000 / COUNT) or "         -";
        lines[#lines + 1] = format("%-5s %s %s  %s", cases[n].group, r, i, cases[n].name);
    end

    DebindDevDB = DebindDevDB or {};
    DebindDevDB.beatCost = DebindDevDB.beatCost or {};
    local runs = DebindDevDB.beatCost;
    runs[#runs + 1] = { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()), lines = lines };
    print(TAG .. format("done: %d cases, run %d saved in DebindDevDB.beatCost. /reload to write it out.",
        #cases - 1, #runs));
end

SLASH_DEBINDBC1 = "/debbc";
SlashCmdList.DEBINDBC = function()
    Run();
end;
