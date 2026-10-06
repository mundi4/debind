local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

local band = bit.band;
local ipairs, pairs, sort = ipairs, pairs, table.sort;

local UnitConditionToState = DebindPrivate.UnitConditionToState;

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

local function IsFull(box, columns)
    for i = 1, #columns do
        if (box[i] ~= columns[i].all) then
            return false;
        end
    end
    return true;
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

--- **The order an entry reads its checks in**: the states, then the units and the
--- pointed frame's columns, then `known` and the switches. The loop stops at the first that fails, so
--- the ones most often failing and cheapest to have read go first; a states column is also the one a
--- gate is made of (`WatchGates`).
local CHECK_RANK = { unit = 2, unitgroup = 2, role = 2, frameType = 2, known = 3, switch = 3 };

--- The two words whose parse costs a tenth of a beat on its own (7-1: 5.15 and 23.98), which
--- `WatchGates` in `UpdateBindings.lua` puts behind a gate.
Judgment.EXPENSIVE = { flyable = true, advflyable = true };

--- The records themselves as entries, in the press's order, and the first box that holds everywhere
--- the `rest`. **Exact without cutting the boxes apart**: the loop answers the first entry that
--- matches, which is the press's own first winner. Entries just ahead of the `rest` that answer what
--- it does are left out: reaching them or not, the answer is the same.
local function RecordsItem(boxes, owners, columns, base)
    local item = { columns = columns, entries = {}, base = base };
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

--- A key's item from its entries. **The list has to end in a record that holds everywhere**, the
--- BLOCK closing the tier, so that some outcome is always answered.
---
--- **The records as they are, not cut apart** (`keeping-only-the-records-form.md`). Each outcome's
--- region less every record ahead of it, cut into disjoint boxes, came to a median of 170 boxes from
--- ten records of five conditions on the owner's shape, and building them took 30 s of a rebuild.
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

    -- A box with an empty column is a record no state picks, so it never answers.
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

    local item = RecordsItem(boxes, owners, columns, base);

    -- **Only the columns the entries kept read**: every column is measured and watched on every beat
    -- (`CollectJudgmentColumns`) whether a bundle reads it or not, and a record left out above would
    -- otherwise leave its columns behind.
    local read = {};
    for _, entry in ipairs(item.entries) do
        for _, check in ipairs(entry.checks) do
            read[check.column] = true;
        end
    end
    local kept, place = {}, {};
    for i, column in ipairs(columns) do
        if (read[i]) then
            kept[#kept + 1] = column;
            place[i] = #kept;
        end
    end
    if (#kept < n) then
        for _, entry in ipairs(item.entries) do
            for _, check in ipairs(entry.checks) do
                check.column = place[check.column];
            end
        end
        item.columns = kept;
    end
    return item;
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
