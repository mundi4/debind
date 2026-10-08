-- Probe_UnitCell.lua
-- One-shot probe. Questions:
--   1. A unit's cell: the classifying text composed and parsed (`ClassifyPieces`), against the
--      same cell out of the functions (`PlayerCanAssist` once, `PlayerCanAttack` at most once,
--      dead once). For every cell a unit around stands on now, since the parse's price moves with
--      the clause that matches.
--   2. Does one parse ask the same unit word again in each clause? N clauses of a unit word that
--      is false, against N clauses of `known:0`: the slope a clause.
--   3. What composing the text costs: a token rotated through 40 (a cursor swept over a raid) and
--      the same token again, with the plain write as its baseline.
--   4. What the watch saves a quiet beat for one unit column: its fragment's share of the one
--      parse, against the column measured on its own (1).
--   5. What a frame boundary costs in strings: `rejoin`'s join on a leave, and on an enter the
--      classifying text, the fragment and the join together.
--   6. What 3 and 5 leave for the collector, in KB a call.
--
--   /debuc    out of combat, in a raid or a party (a member's `raidN` / `partyN` is the cell a raid
--             frame stands on), with a hostile target. Stands still for a few seconds. Saved in
--             DebindDevDB.unitCell, /reload after.
--
-- Delete the file and its TOC line once answered.

local TAG = "|cffff9900[UC]|r ";
local COUNT, ROUNDS = 1000, 15;
local GC_COUNT = 10000;

local CELLS = {
    { 4, "help dead" }, { 2, "help alive" }, { 16, "harm dead" }, { 8, "harm alive" },
    { 64, "other dead" }, { 32, "other alive" },
};

local CANDIDATES = { "target", "focus", "mouseover", "pet" };
for k = 1, 4 do
    CANDIDATES[#CANDIDATES + 1] = "party" .. k;
end
for k = 1, 40 do
    CANDIDATES[#CANDIDATES + 1] = "raid" .. k;
end
-- No nameplates: a nameplate token's unit words cost twice another unit's (7-1 of
-- `trimming-the-tail-key-beat.md`), and no binding of ours points at one.
CANDIDATES[#CANDIDATES + 1] = "player";

local function plain(v)
    if (issecretvalue and issecretvalue(v)) then
        return nil;
    end
    return v;
end

--- The cell the client says `unit` stands on, nil where it is not there or an answer is secret.
local function CellOf(unit)
    if (not plain(UnitExists(unit))) then
        return nil;
    end
    local dead, assist, attack = plain(UnitIsDeadOrGhost(unit)), plain(UnitCanAssist("player", unit)),
        plain(UnitCanAttack("player", unit));
    if (dead == nil or assist == nil or attack == nil) then
        return nil;
    end
    if (assist) then
        return dead and 4 or 2;
    elseif (attack) then
        return dead and 16 or 8;
    end
    return dead and 64 or 32;
end

--- `ClassifyPieces`' unmerged text, with the `noexists` clause where `exists` is asked.
local function ClassifyText(unit, asksExists)
    local t = asksExists and format("[@%s,noexists] 1; ", unit) or "";
    return t .. format("[@%s,help,dead] 4; [@%s,help] 2; [@%s,harm,dead] 16; [@%s,harm] 8; [@%s,dead] 64; 32",
        unit, unit, unit, unit, unit);
end

local API_CELL = [[
local dead = UnitIsDead(u) or UnitIsGhost(u)
if (PlayerCanAssist(u)) then
    x = dead and 4 or 2
elseif (PlayerCanAttack(u)) then
    x = dead and 16 or 8
else
    x = dead and 64 or 32
end]];

local API_CELL_EXISTS = "if (not UnitExists(u)) then\nx = 1\nelse\n" .. API_CELL .. "\nend";

--- The composition as `TemplateExpression` bakes it, into a field the way `J.classify[unit]` is.
local COMPOSE = [[C.t = "[@" .. token .. ",help,dead] 4; [@" .. token .. ",help] 2; [@" .. token ]]
    .. [[.. ",harm,dead] 16; [@" .. token .. ",harm] 8; [@" .. token .. ",dead] 64; 32"]];
--- `n` tokens for a body to cycle through as `T[i % N + 1]`. 40 for the timings, a raid swept over.
--- **The garbage count takes one per call instead**: with the collector stopped, Lua 5.1 hands back
--- a dead string not yet swept when the same text is built again, so 40 tokens would count 40
--- allocations however many calls, where a running collector sweeps between crossings.
---
--- `prefix` keeps one run's texts apart from another's: a text equal to one an earlier run left
--- unswept, or to a prebuilt fragment still alive, is handed back and allocates nothing (the enter
--- line of the first run counted 0.05 KB that way).
local function TOKENS(n, prefix)
    return format([[local N = %d local T = newtable() for k = 1, N do T[k] = %q .. k end local C = newtable()]], n,
        prefix or "raid");
end

--- `rejoin`'s `table.concat(frags)`, which an enter and a leave both run. The fragments are the
--- emit golden's (ten places before the pointed frame's), the last place cycling through `n`
--- fragments prebuilt, so only the join is timed.
local function FRAGS(n, prefix)
    return format([[local N = %d
local R = newtable() for k = 1, N do R[k] = "[@" .. %q .. k .. ",nohelp] 11; " end
]], n, prefix or "raid") .. [[local F = newtable()
F[1] = "[bonusbar:1/2/3/4/5,nobonusbar:2] 1; "
F[2] = "[nocombat] 2; "
F[3] = "[noextrabar] 3; "
F[4] = "[noform:1] 4; "
F[5] = "[known:Regrowth] 5; "
F[6] = "[novehicleui,nopossessbar,nooverridebar,noshapeshift] 6; "
F[7] = "[nostealth] 7; "
F[8] = "[@focus,exists] 8; "
F[9] = "[@pet,exists] 9; "
F[10] = "[@target,exists] 10; "
F[11] = ""
local C = newtable()]];
end

--- The enter as the wake writes it: the classifying text, the fragment, the join.
local ENTER = [[local token = T[i % N + 1]
C.c = "[@" .. token .. ",help] 2; 8"
F[11] = "[@" .. token .. ",nohelp] 11; "
C.t = table.concat(F)]];
local ENTER_BASE = "local token = T[i % N + 1] C.c = token F[11] = token C.t = token";
local JOIN = "F[11] = R[i % N + 1] C.t = table.concat(F)";
local JOIN_BASE = "F[11] = R[i % N + 1] C.t = F[11]";

local function q(s)
    return format("%q", s);
end

local function Cases(picked)
    local cases = {};
    local function add(name, stmt, prelude)
        cases[#cases + 1] = { name = name, stmt = stmt, prelude = prelude };
    end
    add("empty", "");

    for _, c in ipairs(picked) do
        local u, label = c.unit, c.label;
        local unitLocal = "local u = " .. q(u);
        add(format("%s on %s: parse the classifying text + 0", label, u), "x = SecureCmdOptionParse(C.t) + 0",
            "local C = newtable() C.t = " .. q(ClassifyText(u, false)));
        add(format("%s on %s: the functions", label, u), API_CELL, unitLocal);
        add(format("%s on %s: parse with noexists + 0", label, u), "x = SecureCmdOptionParse(C.t) + 0",
            "local C = newtable() C.t = " .. q(ClassifyText(u, true)));
        add(format("%s on %s: the functions with UnitExists", label, u), API_CELL_EXISTS, unitLocal);
    end

    -- Questions 2 and 4 on one unit: a group member where there is one, since that is the token a
    -- raid frame carries, else any but `player`, whose words cost less than another unit's
    -- (`trimming-the-tail-key-beat.md` 7-1).
    local representative = picked[1];
    local rank = { raid = 1, party = 2 };
    for _, c in ipairs(picked) do
        local r = rank[c.unit:match("^%a+")] or (c.unit ~= "player" and 3) or 4;
        local best = rank[representative.unit:match("^%a+")] or (representative.unit ~= "player" and 3) or 4;
        if (r < best) then
            representative = c;
        end
    end
    local one = { representative };

    for _, c in ipairs(one) do
        local word = (c.cell == 2 or c.cell == 4) and "harm" or "help";
        for _, n in ipairs({ 1, 2, 4, 8 }) do
            local unitClauses, knownClauses = {}, {};
            for k = 1, n do
                unitClauses[k] = format("[@%s,%s] %d; ", c.unit, word, k);
                knownClauses[k] = format("[known:0] %d; ", k);
            end
            add(format("%d clauses of a false [@%s,%s]", n, c.unit, word),
                "x = SecureCmdOptionParse(" .. q(table.concat(unitClauses) .. "99") .. ")");
            add(format("%d clauses of [known:0]", n),
                "x = SecureCmdOptionParse(" .. q(table.concat(knownClauses) .. "99") .. ")");
        end
        break;
    end

    add("compose baseline: the token alone into the field, rotated", "local token = T[i % N + 1] C.t = token", TOKENS(40));
    add("compose, the token rotated through 40", "local token = T[i % N + 1] " .. COMPOSE, TOKENS(40));
    add("compose, the same token each time", "local token = T[1] " .. COMPOSE, TOKENS(40));

    -- What the watch saves a quiet beat for one unit column: its fragment's share of the one parse,
    -- against measuring the column on its own (the classifying-text lines above). The ten other
    -- places are `known:0`, false whatever the state, and the unit's fragment is the one that
    -- holds only once it has moved.
    for _, c in ipairs(one) do
        local quiet = {};
        for k = 1, 10 do
            quiet[k] = format("[known:0] %d; ", k);
        end
        local word = (c.cell == 2 or c.cell == 4) and "nohelp" or "help";
        local ten = table.concat(quiet);
        add("quiet watch of 10 places", "x = SecureCmdOptionParse(" .. q(ten) .. ")");
        add(format("quiet watch of 10 places + [@%s,%s] 11", c.unit, word),
            "x = SecureCmdOptionParse(" .. q(ten .. format("[@%s,%s] 11; ", c.unit, word)) .. ")");
        -- The same fragment taken out of the joined text and parsed on its own, which spares the
        -- join on every frame boundary and adds one parse to every beat.
        add(format("the fragment [@%s,%s] 11 parsed alone", c.unit, word),
            "x = SecureCmdOptionParse(" .. q(format("[@%s,%s] 11; ", c.unit, word)) .. ")");
        break;
    end

    add("rejoin baseline: the last fragment written, no join", JOIN_BASE, FRAGS(40));
    add("rejoin: table.concat of 11 fragments, the last rotated", JOIN, FRAGS(40));
    add("rejoin on a leave: the last fragment emptied", [[F[11] = "" C.t = table.concat(F)]], FRAGS(40));
    add("enter baseline: the token read and written, no strings built", ENTER_BASE, FRAGS(40) .. " " .. TOKENS(40));
    add("enter: classifying text + fragment + join, the token rotated", ENTER, FRAGS(40) .. " " .. TOKENS(40));
    return cases;
end

local function Median(list)
    table.sort(list);
    return list[(#list + 1) / 2];
end

local header;

--- KB `body` leaves a call, in the insecure environment, with the collector stopped where the
--- client lets it be.
local function Garbage(stmt, prelude)
    -- The prelude runs before the count is taken, so the tokens it builds are not counted.
    local body = format("local x local newtable = function() return {} end %s\n"
        .. "return function() for i = 1, %d do\n%s\nend end", prelude or "", GC_COUNT, stmt);
    local f = assert(loadstring(body))();
    local stopped = pcall(collectgarbage, "stop");
    local before = collectgarbage("count");
    f();
    local after = collectgarbage("count");
    if (stopped) then
        pcall(collectgarbage, "restart");
    end
    return (after - before) / GC_COUNT, stopped;
end

--- **What a KB of garbage costs the collector, amortized**: one full cycle marks the live heap and
--- sweeps it, and the incremental collector of Lua 5.1 starts the next cycle once the heap has grown
--- by `(pause - 100)%` of what survived. So a cycle's time spread over the KB allocated between
--- cycles is the price of each KB. Timing an allocating loop with the collector running against it
--- stopped does not give this: stopped, the heap grows onto fresh memory and the loop slows for
--- that, which came out as a negative cost when tried.
local function FullCollect()
    local times = {};
    for r = 1, 3 do
        local start = debugprofilestop();
        collectgarbage("collect");
        times[r] = debugprofilestop() - start;
    end
    return Median(times), collectgarbage("count");
end

--- KB one handler entry leaves, written from the insecure side the way the manager writes a beat.
--- A quiet beat at a zero period is this, every frame.
local entryFrames = {};
local function EntryGarbage(name, body)
    local frame = entryFrames[name];
    if (not frame) then
        frame = CreateFrame("Frame", nil, UIParent, "SecureHandlerAttributeTemplate");
        frame:SetAttribute("_onattributechanged", body);
        entryFrames[name] = frame;
    end
    local stopped = pcall(collectgarbage, "stop");
    local before = collectgarbage("count");
    for i = 1, GC_COUNT do
        frame:SetAttribute("v", i);
    end
    local after = collectgarbage("count");
    if (stopped) then
        pcall(collectgarbage, "restart");
    end
    return (after - before) / GC_COUNT;
end

local function GcLines(lines)
    local okPause, pause = pcall(collectgarbage, "setpause", 100);
    local okMul, stepmul = pcall(collectgarbage, "setstepmul", 200);
    if (okMul) then
        collectgarbage("setstepmul", stepmul);
    end
    if (okPause) then
        collectgarbage("setpause", pause);
    end
    local ms, heap = FullCollect();
    local grow = okPause and (pause - 100) / 100 or nil;
    lines[#lines + 1] = format("collector: live heap %.0f KB after a full collect, which took %.2f ms; "
        .. "client pause %s, stepmul %s; so %s us a KB of garbage",
        heap, ms, okPause and tostring(pause) or "unreadable", okMul and tostring(stepmul) or "unreadable",
        (grow and grow > 0) and format("%.4f", ms * 1000 / (heap * grow)) or "-");

    local quiet = {};
    for k = 1, 10 do
        quiet[k] = format("[known:0] %d; ", k);
    end
    lines[#lines + 1] = format("garbage KB a handler entry: empty %.4f, a quiet watch parsed %.4f",
        EntryGarbage("empty", "return"),
        EntryGarbage("quiet", "local h = SecureCmdOptionParse(" .. q(table.concat(quiet)) .. ")"));
end

local function Run()
    if (InCombatLockdown()) then
        print(TAG .. "전투 중에는 돌리지 않는다.");
        return;
    end
    header = header or CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate");

    -- **One unit for each cell and kind of token**, not one for each cell: a friendly target took
    -- the friendly cell ahead of `party1` in the second run, and the party member was what the run
    -- was set up for.
    local picked, seen, taken = {}, {}, {};
    for _, unit in ipairs(CANDIDATES) do
        local cell = CellOf(unit);
        local key = cell and (cell .. ":" .. unit:match("^%a+"));
        if (cell and not taken[key]) then
            taken[key] = true;
            seen[cell] = true;
            for _, c in ipairs(CELLS) do
                if (c[1] == cell) then
                    picked[#picked + 1] = { unit = unit, cell = cell, label = c[2] };
                end
            end
        end
    end
    table.sort(picked, function(a, b)
        if (a.cell ~= b.cell) then
            return a.cell < b.cell;
        end
        return a.unit < b.unit;
    end);

    local lines = {};
    local missing = {};
    for _, c in ipairs(CELLS) do
        if (not seen[c[1]]) then
            missing[#missing + 1] = c[2];
        end
    end
    lines[#lines + 1] = format("units measured: %d; no unit around for: %s", #picked,
        (#missing > 0) and table.concat(missing, ", ") or "-");

    -- A check on this probe's two bodies, that they work out the same cell.
    for _, c in ipairs(picked) do
        SecureHandlerExecute(header, format([[
local u = %s
local x
%s
self:SetAttribute("api", x)
self:SetAttribute("parsed", SecureCmdOptionParse(%s) + 0)]], q(c.unit), API_CELL, q(ClassifyText(c.unit, false))));
        local api, parsed = header:GetAttribute("api"), header:GetAttribute("parsed");
        lines[#lines + 1] = format("agree   %-12s %-11s parse %s, functions %s%s", c.unit, c.label, tostring(parsed),
            tostring(api), (api == parsed and api == c.cell) and "" or "  -- DIFFERS");
    end

    local cases = Cases(picked);
    local bodies, times = {}, {};
    for n, case in ipairs(cases) do
        bodies[n] = format("local x %s\nfor i = 1, %d do\n%s\nend", case.prelude or "", COUNT, case.stmt);
        times[n] = {};
    end
    local failed = {};
    for _ = 1, ROUNDS do
        for n = 1, #cases do
            if (not failed[n]) then
                local start = debugprofilestop();
                local ok, err = pcall(SecureHandlerExecute, header, bodies[n]);
                local spent = debugprofilestop() - start;
                if (ok) then
                    times[n][#times[n] + 1] = spent;
                else
                    failed[n] = tostring(err);
                end
            end
        end
    end
    local empty = Median(times[1]);
    lines[#lines + 1] = format("restricted, us a call: %d calls, median of %d rounds, less the empty loop", COUNT, ROUNDS);
    for n = 2, #cases do
        local value = failed[n] and ("failed: " .. failed[n])
            or format("%8.3f", (Median(times[n]) - empty) * 1000 / COUNT);
        lines[#lines + 1] = format("time    %s  %s", value, cases[n].name);
    end

    -- Every call builds a text never built before, which is what a sweep leaves once the collector
    -- has run between crossings: the bytes each crossing hands it. Each run has its own prefix.
    local base, stopped = Garbage("local token = T[i % N + 1] C.t = token", TOKENS(GC_COUNT, "ga"));
    local composed = Garbage("local token = T[i % N + 1] " .. COMPOSE, TOKENS(GC_COUNT, "gb"));
    local joinBase = Garbage(JOIN_BASE, FRAGS(GC_COUNT, "gc"));
    local join = Garbage(JOIN, FRAGS(GC_COUNT, "gd"));
    local enterBase = Garbage(ENTER_BASE, FRAGS(GC_COUNT, "ge") .. " " .. TOKENS(GC_COUNT, "gf"));
    local enter = Garbage(ENTER, FRAGS(GC_COUNT, "gg") .. " " .. TOKENS(GC_COUNT, "gh"));
    lines[#lines + 1] = format("garbage KB a call, insecure, collector %s, a new text every call: "
        .. "6-clause classify %.4f (baseline %.4f), rejoin %.4f (baseline %.4f), enter %.4f (baseline %.4f)",
        stopped and "stopped" or "NOT stopped (counts may include a collection)",
        composed, base, join, joinBase, enter, enterBase);

    GcLines(lines);

    DebindDevDB = DebindDevDB or {};
    DebindDevDB.unitCell = { at = date("%Y-%m-%d %H:%M:%S"), build = select(4, GetBuildInfo()), lines = lines };
    for _, line in ipairs(lines) do
        print(TAG .. line);
    end
    print(TAG .. "DebindDevDB.unitCell에 저장했다. /reload 하면 파일로 남는다.");
end

SLASH_DEBINDUC1 = "/debuc";
SlashCmdList.DEBINDUC = function()
    local ok, err = pcall(Run);
    if (not ok) then
        print(TAG .. "실패: " .. tostring(err));
    end
end;
