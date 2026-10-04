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

Judgment.TRUE = 1;
Judgment.FALSE = 2;
local BOOL_ALL = 3;

--- A switch nobody has written answers neither value at the press (`States[name] ~= v`).
Judgment.SWITCH_UNSET = 4;
local SWITCH_ALL = 7;

--- Off a party or raid frame, or with no role map up, the press does not test a role at all.
Judgment.ROLE_UNMEASURED = 2 ^ 4;
local ROLE_ALL = Constants.ROLE_ALL + Judgment.ROLE_UNMEASURED;

--- With nothing pointed at, or a frame whose unit is gone, `t.frameTypes` fails whatever it holds.
Judgment.FRAMETYPE_NOFRAME = 2 ^ 7;
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

local function constrain(out, key, kind, arg, all, mask)
    out[#out + 1] = { key = key, kind = kind, arg = arg, all = all, mask = band(mask, all) };
end

--- What one record tests, as `(column, mask)` pairs. `record` is `BuildKeyRecord`'s.
---
--- **`known` is one column per baked question.** The press asks the conditional and then the book
--- for `knownID`, and the two travel together: the same string always comes with the same id.
local function RecordConstraints(record)
    local out = {};
    local names, values = record.fieldNames, record.fieldValues;
    for i = 1, record.fieldCount do
        local name, value = names[i], values[i];
        if (BOOL_FIELDS[name]) then
            constrain(out, name, name, nil, BOOL_ALL, value and Judgment.TRUE or Judgment.FALSE);
        elseif (MASK_FIELDS[name]) then
            constrain(out, name, name, nil, MASK_FIELDS[name], value);
        elseif (name == "known") then
            constrain(out, "known " .. value, "known", value, BOOL_ALL, Judgment.TRUE);
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

--- A key's item from its entries. **The list has to end in a record that holds everywhere**, the
--- BLOCK closing the tier, so that some outcome is always answered.
---
--- Each outcome's region is the records that give it, less every record ahead of them, cut into
--- disjoint boxes and joined back where a pair differs in one column. The costliest region is left
--- unwritten as `rest` (2-2, 3-2): the press is answered by the others, and failing them by `rest`.
---
--- `base` is the bare key a chord was made from, and only a chord has one.
function Judgment.Build(entries, base)
    local columns, index = {}, {};
    for _, entry in ipairs(entries) do
        for _, c in ipairs(entry.constraints) do
            if (not index[c.key]) then
                index[c.key] = true;
                columns[#columns + 1] = { key = c.key, kind = c.kind, arg = c.arg, all = c.all };
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

    local item = { columns = columns, entries = {}, base = base };

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
        for i, box in ipairs(boxes) do
            local owner = owners[i];
            if (IsFull(box, columns) or i == #boxes) then
                item.rest = { outcome = owner.outcome, command = owner.command };
                break;
            end
            item.entries[#item.entries + 1] = {
                checks = Checks(box, columns), outcome = owner.outcome, command = owner.command,
            };
        end
        return item;
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
    return item;
end

--- What an item answers where `point[column]` is the one cell measured in each column. A chord's
--- `BASE` is its caller's to resolve against the base key's own answer.
function Judgment.Judge(item, point)
    for _, entry in ipairs(item.entries) do
        local match = true;
        for _, check in ipairs(entry.checks) do
            if (band(check.mask, point[check.column]) == 0) then
                match = false;
                break;
            end
        end
        if (match) then
            return entry.outcome, entry.command;
        end
    end
    return item.rest.outcome, item.rest.command;
end
