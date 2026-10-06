local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

local band, bor = bit.band, bit.bor;
local ipairs, pairs, tremove, sort = ipairs, pairs, tremove, table.sort;

local UnitConditionToState = DebindPrivate.UnitConditionToState;
local SubtractBoxes = DebindPrivate.SubtractBoxes;

--[[
    A key's judgment item (`handing-the-rest-of-a-key-to-the-game.md` 2-2): which of ours, a
    command or released the key is in the state measured now, as boxes with an outcome each.

    **The boxes are built from the records that go out, not from the solver's boxes.** A solver box
    is allowed to be wrong in the direction that keeps a binding: a mouse button key narrows
    `unitframe` to absent where its record says nothing, `mouseover` folds a correlation in, an
    empty role picked beside other frame types is an empty box, and a condition it cannot place
    leaves the binding out of both roles. An item binds the key on its answer, so it has no safe
    direction, and the record is the one description of what the press actually tests.

    One column per thing the press measures, each a partition of what it can measure. Where the
    press skips a test -- a role off a party or raid frame, a frame type with no frame -- the column
    gets a cell of its own for that, which every mask holds.
]]

local Judgment = {};
DebindPrivate.Judgment = Judgment;

Judgment.OURS = "ours";
Judgment.RELEASE = "release";
Judgment.COMMAND = "command";
--- A chord's own tier had no winner: the chord is ours only while its base key is (2-3).
Judgment.BASE = "base";

Judgment.TRUE = Constants.JUDGMENT_TRUE;
Judgment.FALSE = Constants.JUDGMENT_FALSE;
local BOOL_ALL = Judgment.TRUE + Judgment.FALSE;

Judgment.SWITCH_UNSET = Constants.JUDGMENT_SWITCH_UNSET;
local SWITCH_ALL = BOOL_ALL + Judgment.SWITCH_UNSET;

Judgment.ROLE_UNMEASURED = Constants.JUDGMENT_ROLE_UNMEASURED;
local ROLE_ALL = Constants.ROLE_ALL + Judgment.ROLE_UNMEASURED;

Judgment.FRAMETYPE_NOFRAME = Constants.JUDGMENT_FRAMETYPE_NOFRAME;
local FRAMETYPE_ALL = Constants.FRAMETYPE_ALL + Judgment.FRAMETYPE_NOFRAME;

local BOOL_FIELDS = {
    combat = true, stealth = true, mounted = true, indoors = true, flyable = true,
    advflyable = true, flying = true, skyriding = true, extrabar = true, petbattle = true,
    specialbar = true,
};

local MASK_FIELDS = {
    groups = Constants.GROUP_ALL,
    forms = Constants.FORM_ALL,
    bonusbars = Constants.BONUSBAR_ALL,
};

local function constrain(out, key, kind, arg, all, mask, knownID)
    out[#out + 1] = {
        key = key, kind = kind, arg = arg, all = all, mask = band(mask, all), knownID = knownID,
    };
end

--- What one record tests, as `(column, mask)` pairs. `record` is `BuildKeyRecord`'s.
---
--- **`known` is one column per baked question.** The press asks the conditional and then the book
--- for `knownID`, and the two travel together: the same string always comes with the same id. The
--- id rides on the column because the loop asks both too.
local function RecordConstraints(record)
    local out = {};
    local names, values = record.fieldNames, record.fieldValues;
    local knownID;
    for i = 1, record.fieldCount do
        if (names[i] == "knownID") then
            knownID = values[i];
        end
    end
    for i = 1, record.fieldCount do
        local name, value = names[i], values[i];
        if (BOOL_FIELDS[name]) then
            constrain(out, name, name, nil, BOOL_ALL, value and Judgment.TRUE or Judgment.FALSE);
        elseif (MASK_FIELDS[name]) then
            constrain(out, name, name, nil, MASK_FIELDS[name], value);
        elseif (name == "known") then
            constrain(out, "known " .. value, "known", value, BOOL_ALL, Judgment.TRUE, knownID);
        elseif (name == "frameTypes") then
            constrain(out, "frameType", "frameType", nil, FRAMETYPE_ALL, value);
        end
    end
    for unit, condition in pairs(record.units) do
        constrain(out, "unit " .. unit, "unit", unit, Constants.UNITSTATE_ALL,
            UnitConditionToState(condition));
        if (type(condition) == "table") then
            if (condition.group) then
                constrain(out, "unitgroup " .. unit, "unitgroup", unit, Constants.UNITGROUPCELL_ALL,
                    condition.group);
            end
            -- `EmitRecord` sends a role for this unit only.
            if (unit == "unitframe" and condition.role) then
                constrain(out, "role", "role", nil, ROLE_ALL,
                    band(condition.role, Constants.ROLE_ALL) + Judgment.ROLE_UNMEASURED);
            end
        end
    end
    for name, value in pairs(record.switches) do
        constrain(out, "switch " .. name, "switch", name, SWITCH_ALL,
            value and Judgment.TRUE or Judgment.FALSE);
    end
    return out;
end

--- One record of a key, in the order the press walks them, with what its winning means.
function Judgment.Entry(record, outcome, command)
    return { constraints = RecordConstraints(record), outcome = outcome, command = command };
end

local function OutcomeKey(outcome, command)
    if (command) then
        return outcome .. " " .. command;
    end
    return outcome;
end

local function IsFull(box, columns)
    for i = 1, #columns do
        if (box[i] ~= columns[i].all) then
            return false;
        end
    end
    return true;
end

--- Joins two boxes that differ in one column, until no pair does. **Exact as a union**: two boxes
--- equal everywhere but one column are together the box with that column's two masks joined.
local function MergeBoxes(list, n)
    local merged = true;
    while (merged) do
        merged = false;
        for i = 1, #list - 1 do
            local a = list[i];
            for j = i + 1, #list do
                local b = list[j];
                local diff;
                for col = 1, n do
                    if (a[col] ~= b[col]) then
                        if (diff) then
                            diff = false;
                            break;
                        end
                        diff = col;
                    end
                end
                if (diff ~= false) then
                    if (diff) then
                        a[diff] = bor(a[diff], b[diff]);
                    end
                    tremove(list, j);
                    merged = true;
                    break;
                end
            end
            if (merged) then
                break;
            end
        end
    end
end

--- The tests a box makes: only its columns that rule something out.
local function Checks(box, columns)
    local checks = {};
    for i = 1, #columns do
        if (box[i] ~= columns[i].all) then
            checks[#checks + 1] = { column = i, mask = box[i] };
        end
    end
    return checks;
end

local function Cost(list, columns)
    local cost = 0;
    for _, box in ipairs(list) do
        cost = cost + #Checks(box, columns);
    end
    return cost;
end

--- Past this the item is kept as the records' own order, which is exact and only longer. The same
--- unit as the solver's (`node x covers x columns`).
local MAX_WORK = 30000;

--- **What the judging loop pays to walk an entry and to read a check**, in µs (7-1's P). A check read
--- is a quarter of the difference between four entries of two checks matching at the fourth (2.966)
--- and four failing at their first (2.020); an entry walked is the rest of a quarter of 2.020. One
--- copy: `BundleAnswers` in `UpdateBindings.lua` weighs a table against these.
Judgment.LOOP_CHECK = (2.966 - 2.020) / 4;
Judgment.LOOP_ENTRY = 2.020 / 4 - Judgment.LOOP_CHECK;

--- **The order a records-form entry reads its checks in**: the states, then the units and the
--- pointed frame's columns, then `known` and the switches. The loop stops at the first that fails, so
--- the ones most often failing and cheapest to have read go first; a states column is also the one a
--- gate is made of (`WatchGates`).
local CHECK_RANK = { unit = 2, unitgroup = 2, role = 2, frameType = 2, known = 3, switch = 3 };

--- The two words whose parse costs a tenth of a beat on its own (7-1: 5.15 and 23.98).
local EXPENSIVE = { flyable = true, advflyable = true };

--- An item as the records themselves (R6 of `cutting-the-beat-under-a-zero-period.md`): each
--- record's box one entry, in the press's order, and the first box that holds everywhere the `rest`.
--- **Exact without cutting the boxes apart**: the loop answers the first entry that matches, which is
--- the press's own first winner. A box no state picks was dropped before (`boxes`). Entries just ahead
--- of the `rest` that answer what it does are left out: reaching them or not, the answer is the same.
local function RecordsItem(boxes, owners, columns, base)
    local item = { columns = columns, entries = {}, base = base, form = "records" };
    for i, box in ipairs(boxes) do
        local owner = owners[i];
        if (IsFull(box, columns) or i == #boxes) then
            item.rest = { outcome = owner.outcome, command = owner.command };
            break;
        end
        local checks = Checks(box, columns);
        sort(checks, function(a, b)
            local ra, rb = CHECK_RANK[columns[a.column].kind] or 1, CHECK_RANK[columns[b.column].kind] or 1;
            if (ra ~= rb) then
                return ra < rb;
            end
            return a.column < b.column;
        end);
        item.entries[#item.entries + 1] = { checks = checks, outcome = owner.outcome, command = owner.command };
    end
    local entries = item.entries;
    while (#entries > 0 and entries[#entries].outcome == item.rest.outcome
            and entries[#entries].command == item.rest.command) do
        entries[#entries] = nil;
    end
    return item;
end

--- **The points the two forms are priced over**: each column's cells, one per group of cells that no
--- mask either form checks tells apart, which is what `BundleAnswers` walks by (`ColumnGroups`). nil
--- past `JudgeTableCap` points.
local function PricePoints(columns, items)
    local masks = {};
    for i = 1, #columns do
        masks[i] = {};
    end
    for _, item in ipairs(items) do
        for _, entry in ipairs(item.entries) do
            for _, check in ipairs(entry.checks) do
                masks[check.column][check.mask] = true;
            end
        end
    end
    local cells, points = {}, 1;
    for i, column in ipairs(columns) do
        local reps, seen = {}, {};
        for b = 0, 30 do
            local p = 2 ^ b;
            if (p > column.all) then
                break;
            end
            if (band(column.all, p) ~= 0) then
                local signature = {};
                for mask in pairs(masks[i]) do
                    signature[#signature + 1] = (band(mask, p) ~= 0) and mask or -mask;
                end
                sort(signature);
                local key = table.concat(signature, ",");
                if (not seen[key]) then
                    seen[key] = true;
                    reps[#reps + 1] = p;
                end
            end
        end
        cells[i] = reps;
        points = points * #reps;
        if (points > (DebindPrivate.JudgeTableCap or 1024)) then
            return nil;
        end
    end
    return cells, points;
end

--- **What the loop pays to answer an item**, averaged over `PricePoints` with each weighted alike, as
--- `BundleAnswers` averages it. With no points (past the cap), every entry and check the item holds:
--- more than the loop reads, since it stops at an entry's first failing check, but alike for both
--- forms.
local function LoopPrice(item, cells, points)
    if (not cells) then
        local checks = 0;
        for _, entry in ipairs(item.entries) do
            checks = checks + #entry.checks;
        end
        return #item.entries * Judgment.LOOP_ENTRY + checks * Judgment.LOOP_CHECK;
    end
    local point, total = {}, 0;
    for n = 0, points - 1 do
        local rest = n;
        for i, list in ipairs(cells) do
            local index = rest % #list;
            point[i] = list[index + 1];
            rest = (rest - index) / #list;
        end
        local _, _, entries, checks = Judgment.Judge(item, point);
        total = total + entries * Judgment.LOOP_ENTRY + checks * Judgment.LOOP_CHECK;
    end
    return total / points;
end

--- A key's item from its entries. **The list has to end in a record that holds everywhere**, the
--- BLOCK closing the tier, so that some outcome is always answered.
---
--- **Two forms, and the one the loop answers cheaper is kept** (R6 of
--- `cutting-the-beat-under-a-zero-period.md`), recorded as `item.form`:
---
---   `regions`  each outcome's region is the records that give it, less every record ahead of them,
---              cut into disjoint boxes and joined back where a pair differs in one column. The
---              costliest region is left unwritten as `rest` (2-2, 3-2). Few, short entries where
---              records overlap little
---   `records`  the records themselves (`RecordsItem`). Ten records of five conditions cut apart
---              came to a median of 170 boxes on the owner's shape; as records they stay ten
---
--- Both answer every point alike. `DebindPrivate.JudgmentForm` holds one for a spec. Past
--- `MAX_WORK` only the records are built.
---
--- `base` is the bare key a chord was made from, and only a chord has one.
function Judgment.Build(entries, base)
    local columns, index = {}, {};
    for _, entry in ipairs(entries) do
        for _, c in ipairs(entry.constraints) do
            if (not index[c.key]) then
                index[c.key] = true;
                columns[#columns + 1] = {
                    key = c.key, kind = c.kind, arg = c.arg, all = c.all, knownID = c.knownID,
                };
            end
        end
    end
    sort(columns, function(a, b) return a.key < b.key; end);
    for i, column in ipairs(columns) do
        index[column.key] = i;
    end
    local n = #columns;

    -- A box with an empty column is a record no state picks, so it neither answers nor covers.
    local boxes, owners = {}, {};
    for _, entry in ipairs(entries) do
        local box = {};
        for i = 1, n do
            box[i] = columns[i].all;
        end
        local empty = false;
        for _, c in ipairs(entry.constraints) do
            local i = index[c.key];
            box[i] = band(box[i], c.mask);
            empty = empty or box[i] == 0;
        end
        if (not empty) then
            boxes[#boxes + 1] = box;
            owners[#owners + 1] = entry;
        end
    end

    local records = RecordsItem(boxes, owners, columns, base);
    local form = DebindPrivate.JudgmentForm;
    if (form == "records") then
        return records;
    end

    local item = { columns = columns, entries = {}, base = base, form = "regions" };

    local regions, order, first = {}, {}, {};
    local covers = {};
    local budget = { work = MAX_WORK };
    local complete = true;
    for i, box in ipairs(boxes) do
        local owner = owners[i];
        local key = OutcomeKey(owner.outcome, owner.command);
        local list = regions[key];
        if (not list) then
            list = {};
            regions[key] = list;
            order[#order + 1] = key;
            first[key] = owner;
        end
        if (not SubtractBoxes(box, covers, #covers, n, list, budget)) then
            complete = false;
            break;
        end
        covers[#covers + 1] = box;
        if (IsFull(box, columns)) then
            break;
        end
    end

    if (not complete) then
        return records;
    end

    local restKey, restCost;
    for _, key in ipairs(order) do
        local list = regions[key];
        MergeBoxes(list, n);
        if (#list > 0) then
            local cost = Cost(list, columns);
            if (restKey == nil or cost > restCost) then
                restKey, restCost = key, cost;
            end
        end
    end

    item.rest = { outcome = first[restKey].outcome, command = first[restKey].command };
    for _, key in ipairs(order) do
        if (key ~= restKey) then
            local owner = first[key];
            for _, box in ipairs(regions[key]) do
                item.entries[#item.entries + 1] = {
                    checks = Checks(box, columns), outcome = owner.outcome, command = owner.command,
                };
            end
        end
    end
    if (form == "regions") then
        return item;
    end
    -- **An expensive word keeps the regions.** A records entry has lost the negations of the records
    -- ahead of it, so `[combat] A; [flyable] B` asks a bare `[flyable]`, and the watch's gate
    -- (`WatchGates`) that `[nocombat,flyable]` would have closed in combat stays open: a parse of 5
    -- (24 for `advflyable`) on every beat, which no loop price sees.
    for _, column in ipairs(columns) do
        if (EXPENSIVE[column.kind]) then
            return item;
        end
    end
    local cells, points = PricePoints(columns, { item, records });
    if (LoopPrice(item, cells, points) <= LoopPrice(records, cells, points)) then
        return item;
    end
    return records;
end

--- What an item answers where `point[column]` is the one cell measured in each column. A chord's
--- `BASE` is its caller's to resolve against the base key's own answer.
---
--- Then how many entries and checks it read to get there, which is what the judging loop reads at
--- that point (`BundleAnswers` in `UpdateBindings.lua` prices a bundle by them).
function Judgment.Judge(item, point)
    local checks = 0;
    for e, entry in ipairs(item.entries) do
        local match = true;
        for _, check in ipairs(entry.checks) do
            checks = checks + 1;
            if (band(check.mask, point[check.column]) == 0) then
                match = false;
                break;
            end
        end
        if (match) then
            return entry.outcome, entry.command, e, checks;
        end
    end
    return item.rest.outcome, item.rest.command, #item.entries, checks;
end
