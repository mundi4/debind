local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

local band      = bit.band;
local format    = string.format;
local gmatch    = string.gmatch;
local sort      = table.sort;
local luatype   = type;

local KEYS_TO_SAVE          = DebindPrivate.KEYS_TO_SAVE;
local VALUE_SHAPES          = Constants.VALUE_SHAPES;
local CONDITION_FIELDS      = Constants.CONDITION_FIELDS;
local CONDITION_MASKS       = Constants.CONDITION_MASKS;
local CASTING_FIELDS        = Constants.CASTING_FIELDS;
local UNIT_CONDITION_FIELDS = Constants.UNIT_CONDITION_FIELDS;
local UNIT_CONDITION_MASKS  = Constants.UNIT_CONDITION_MASKS;

--- **A field a payload carries and a profile does not, kept on both.** The function reads the two
--- alike and takes no argument saying which it has (`sanitizing-actions-with-one-function.md` §2-2,
--- the owner's call against a second answer per value). On the way in it is dropped before the
--- action lands (`Import.lua`'s `Build`), so a stored one was put there by hand, and the one reader
--- (`CliqueSpecMask`) asks it for `true` and nothing else: left, it costs a few bytes and an export
--- line, which is less than a rule that answers two ways.
local WIRE_ONLY = { untranslated = "table" };

--- `"number|string"` read once into a set.
local typeSets = {};

--- Is `value` one of the Lua types `expected` lists? **NaN is no number here**: it is the one value
--- that is not equal to itself, and as a key, a mask or a sort key it raises or answers nonsense.
local function Fits(expected, value)
    if (value ~= value) then
        return false;
    end
    local set = typeSets[expected];
    if (set == nil) then
        set = {};
        for kind in gmatch(expected, "[^|]+") do
            set[kind] = true;
        end
        typeSets[expected] = set;
    end
    return set[luatype(value)] == true;
end

local function IsScalar(value)
    return luatype(value) == "string" or (luatype(value) == "number" and value == value);
end

--- A mask cut to the bits it can hold. **What is no mask at all reads as nothing picked**, 0, which
--- the issue check marks on the menu and keeps off the key (`GetBindingIssue`). A negative number is
--- no mask either: `band` would read -1 as every bit on.
local function Mask(value, all)
    if (luatype(value) ~= "number" or value ~= value or value < 0 or value % 1 ~= 0) then
        return 0;
    end
    return band(value, all);
end

--- The names a row of `conditions.units` may be filed under: what the condition menu lists, and
--- `"@"`, the unit the press aims at. `none` is in that list as a target and is no unit a condition
--- can hang on (`ActionMenuNodes.lua`'s `BuildUnitConditionMenu`). Built on first use, since the
--- list is the window's file and loads after this one.
local listedUnits;
local function ListedUnits()
    if (listedUnits == nil) then
        listedUnits = { ["@"] = true };
        for _, unit in ipairs(DebindPrivate.DebindUI.SORTED_UNIT_LIST) do
            if (unit ~= "none") then
                listedUnits[unit] = true;
            end
        end
    end
    return listedUnits;
end

--- The names a talent entry's lists go under, as a set (`Talents.LIST_NAMES`).
local talentListNames;
local function TalentListNames()
    if (talentListNames == nil) then
        talentListNames = {};
        for _, listName in ipairs(DebindPrivate.Talents.LIST_NAMES) do
            talentListNames[listName] = true;
        end
    end
    return talentListNames;
end

--- The four scalars a unit row was before `dbver` 4, as the row each became.
local OLD_SCALAR_ROWS = {
    [true]   = { exists = true },
    [false]  = { exists = false },
    ["help"] = { exists = true, reaction = Constants.REACTION_HELP },
    ["harm"] = { exists = true, reaction = Constants.REACTION_HARM },
};

--- The numbers of a talent list, in order. Anything else goes, holes included.
local function KeepNumbers(list)
    local kept = {};
    for i = 1, #list do
        local id = list[i];
        if (luatype(id) == "number" and id == id) then
            kept[#kept + 1] = id;
        end
    end
    wipe(list);
    for i = 1, #kept do
        list[i] = kept[i];
    end
end

local function SanitizeUnitRow(units, unit, row)
    for name, value in pairs(row) do
        local expected = luatype(name) == "string" and UNIT_CONDITION_FIELDS[name];
        local all = expected and UNIT_CONDITION_MASKS[name];
        if (all) then
            -- **All-on is stored as none in a row** (`ToggleUnitConditionMask`).
            local mask = Mask(value, all);
            row[name] = mask ~= all and mask or nil;
        elseif (not expected or not Fits(expected, value)) then
            row[name] = nil;
        end
    end

    if (row.disabled == false) then
        row.disabled = nil;
    end
    if (row.disabled) then
        row.exists = nil;
        if (not DebindPrivate.UnitConditionRemembersAxis(row)) then
            units[unit] = nil;
        end
    elseif (row.exists == nil) then
        -- **A row with no mode reads as [when there is one]** (`UnitConditionForBinding`). Dropped,
        -- the condition would be gone and the action would take keys it was kept off.
        row.exists = true;
    end
end

local function SanitizeConditions(action, conditions)
    for name, value in pairs(conditions) do
        local expected;
        if (luatype(name) == "string") then
            expected = CONDITION_FIELDS[name] or (Constants.IsSwitchName(name) and "boolean");
        end
        local all = expected and CONDITION_MASKS[name];
        if (all) then
            conditions[name] = Mask(value, all);
        elseif (expected and Fits(expected, value)) then
            -- Kept. What is inside the tables is asked below.
        elseif (name == "specs") then
            -- **Nothing picked rather than no condition**, the way a mask reads (`SPECS_NONE_SELECTED`).
            conditions.specs = {};
        else
            conditions[name] = nil;
        end
    end

    if (conditions.known == false) then
        conditions.known = nil;
    end

    local specs = conditions.specs;
    if (specs) then
        for classID, mask in pairs(specs) do
            -- A class is not asked about: classes arrive with patches, and one this client does not
            -- know is never the one being played. **The bits are**, against every bit any client has.
            local bits = luatype(classID) == "number" and Mask(mask, Constants.SPEC_INDEX_ALL) or 0;
            -- A class at 0 is the class missing, the shape the menu writes (`NormalizeSpecCondition`).
            -- The set itself stays, even empty, where it reads as nothing picked.
            specs[classID] = bits ~= 0 and bits or nil;
        end
    end

    local talents = conditions.talents;
    if (talents) then
        local listNames = TalentListNames();
        for specID, entry in pairs(talents) do
            if (luatype(specID) ~= "number" or luatype(entry) ~= "table") then
                talents[specID] = nil;
            else
                for listName, list in pairs(entry) do
                    if (not listNames[listName] or luatype(list) ~= "table") then
                        entry[listName] = nil;
                    else
                        KeepNumbers(list);
                    end
                end
            end
        end
        DebindPrivate.Talents.Prune(action);
    end

    local units = conditions.units;
    if (units) then
        -- **Old shapes the readers still read are moved, not dropped**: dropped, the condition goes
        -- and the action takes keys it was kept off. The moves are the `dbver <= 4` and `<= 6` steps'
        -- (`Migration.lua`), which every stored profile has been through; what still carries one is a
        -- hand-made value or a spec's fixture, and `UnitConditionForBinding` reads it the same way.
        if (units.hover ~= nil) then
            if (units.unitframe == nil) then
                units.unitframe = units.hover;
            end
            units.hover = nil;
        end
        for unit, row in pairs(units) do
            local raised = OLD_SCALAR_ROWS[row];
            if (raised) then
                units[unit] = { exists = raised.exists, reaction = raised.reaction };
            end
        end

        local listed = ListedUnits();
        for unit, row in pairs(units) do
            if (not listed[unit] or luatype(row) ~= "table") then
                units[unit] = nil;
            else
                SanitizeUnitRow(units, unit, row);
            end
        end
        if (next(units) == nil) then
            conditions.units = nil;
        end
    end
end

--- Brings one action into the shape the profile stores, **in place**, from anything at all: a
--- hand-edited SavedVariables, a pasted string, a writer's slip. What can be repaired is; what
--- cannot loses the field it was in (`sanitizing-actions-with-one-function.md` §6 is the table this
--- follows, row by row).
---
--- **Returns false only for "remove this action"**: it is not a table, or its arrival number is
--- broken, where kept it would land on a key the reader never accepted. The caller removes it; there
--- is nothing else to choose.
---
--- **It reads nothing about the client**, so a string sanitized here keeps the same meaning on the
--- client it goes to next. Whether a spell or a talent exists is not its question.
function DebindPrivate.SanitizeAction(action)
    if (luatype(action) ~= "table") then
        return false;
    end

    for name, value in pairs(action) do
        if (name ~= "type" and name ~= "value") then
            local expected = luatype(name) == "string" and (KEYS_TO_SAVE[name] or WIRE_ONLY[name]);
            if (not expected or not Fits(expected, value)) then
                if (name == "arrivalID") then
                    return false;
                end
                action[name] = nil;
            end
        end
    end

    -- **Type and value are asked together**, since which value fits is the type's to say. An action
    -- nothing can run on is kept as `INVALID` with what it held in `formerly`, so [Replace] brings
    -- the row back with its key, place and conditions (§6-6 item 2).
    local shape;
    if (luatype(action.type) == "string") then
        shape = VALUE_SHAPES[action.type];
    end
    if (shape == false) then
        action.value = nil;
    elseif (shape == nil or not Fits(shape, action.value)) then
        local formerly = {};
        formerly.type = IsScalar(action.type) and action.type or nil;
        formerly.value = IsScalar(action.value) and action.value or nil;
        action.type = Constants.INVALID;
        action.value = nil;
        action.formerly = next(formerly) ~= nil and formerly or nil;
    end

    local formerly = action.formerly;
    if (formerly) then
        for name, value in pairs(formerly) do
            if ((name ~= "type" and name ~= "value") or not IsScalar(value)) then
                formerly[name] = nil;
            end
        end
        if (next(formerly) == nil) then
            action.formerly = nil;
        end
    end

    -- **An invalid action keeps its target**: what it was may have taken one, and [Replace] with a
    -- type that does keeps it there.
    if (action.unit ~= nil and action.type ~= Constants.INVALID
            and not DebindPrivate.ActionTakesUnit(action)) then
        action.unit = nil;
    end

    -- No window puts an action on Escape, and the key is the one that closes them.
    if (action.key == "ESCAPE") then
        action.key = nil;
    end

    action.priority = DebindPrivate.ImportanceToStored(action.priority);
    if (action.disabled == false) then
        action.disabled = nil;
    end
    if (action.skipWhenUnusable == false) then
        action.skipWhenUnusable = nil;
    end

    local casting = action.casting;
    if (casting) then
        for name, value in pairs(casting) do
            local expected = luatype(name) == "string" and CASTING_FIELDS[name];
            if (not expected or not Fits(expected, value)) then
                casting[name] = nil;
            end
        end
        -- `false` is the one value it is stored as; `true` is the default.
        if (casting.normalCast ~= false) then
            casting.normalCast = nil;
        end
        DebindPrivate.PruneCasting(action);
    end

    local conditions = action.conditions;
    if (conditions) then
        SanitizeConditions(action, conditions);
    end

    -- Last among the fields, since it also takes `conditions` off once nothing is left in it.
    DebindPrivate.DropFieldsTheTypeCannotHold(action);

    -- **A keyless action has no place to hold** (`ClearActionKey`). A keyed one with a broken number
    -- gets one where it enters a layer (§2-3), since only the layer knows the rest of its group.
    if (action.key == nil) then
        action.seq = nil;
    end

    return true;
end

--- Every action in `list` through `SanitizeAction`, and out of the list what it says to remove.
--- **Positions 1..n are the list**: `#` and `ipairs` are all that ever walk one, so an element in a
--- hole or under a name is in no list anyone reads, and a hole leaves `#` free to answer either side
--- of it. The list closes up in place, in the order the positions had.
---
--- A payload's numbers stay as they came: an arrival renumbers where it lands (`PlaceArrivedActions`).
function DebindPrivate.SanitizeActionList(list)
    local positions = {};
    for position in pairs(list) do
        if (luatype(position) == "number" and position >= 1 and position % 1 == 0) then
            positions[#positions + 1] = position;
        end
    end
    sort(positions);

    local kept = {};
    for i = 1, #positions do
        local action = list[positions[i]];
        if (DebindPrivate.SanitizeAction(action)) then
            kept[#kept + 1] = action;
        end
    end
    wipe(list);
    for i = 1, #kept do
        list[i] = kept[i];
    end
end

local function ByStoredNumber(lhs, rhs)
    if (lhs.seq ~= rhs.seq) then
        -- **No number goes to the back.** Where it belonged cannot be known, and the back is the
        -- less startling end: in front it would take the press from whatever fired first.
        if (lhs.seq == nil) then
            return false;
        elseif (rhs.seq == nil) then
            return true;
        end
        return lhs.seq < rhs.seq;
    end
    return lhs.index < rhs.index;
end

--- `SanitizeActionList` for a layer's list, which then numbers each group `(key, arrivalID)` 1..n
--- (`RenumberKeyGroup` says why that is the group).
---
--- **Ranked by the stored number alone, not by `RenumberKeyGroup`'s comparator** (2026-10-09,
--- `sanitizing-actions-with-one-function.md` §2-3). `seq` is the comparator's last step, so the
--- firing order comes out exactly as it went in. What this leaves is a group whose numbers disagree
--- with its importance or conditions, and only a hand edit makes one: every edit renumbers through
--- the comparator. Its one cost is that a later move across a band lands at the other end. The
--- comparator reads the binding (`MakeOrderRecord`, `FillBinding`), and this runs at ADDON_LOADED
--- and at logout, where one raise stops the load or the save.
---
--- **Two equal numbers are taken in stored order**, and said under DEBUG: which of them went first
--- was never decided, since the comparator ties them and `sort` puts them either way.
function DebindPrivate.SanitizeLayerActions(list)
    DebindPrivate.SanitizeActionList(list);

    -- By key, then by `arrivalID`, with `false` for the reader's own set.
    local groups, order = {}, {};
    for index = 1, #list do
        local action = list[index];
        if (action.key ~= nil) then
            local byArrival = groups[action.key];
            if (byArrival == nil) then
                byArrival = {};
                groups[action.key] = byArrival;
            end
            local arrival = action.arrivalID or false;
            local group = byArrival[arrival];
            if (group == nil) then
                group = {};
                byArrival[arrival] = group;
                order[#order + 1] = group;
            end
            group[#group + 1] = { action = action, seq = action.seq, index = index };
        end
    end

    for _, group in ipairs(order) do
        sort(group, ByStoredNumber);
        local tied;
        for i = 1, #group do
            local record = group[i];
            if (i > 1 and record.seq ~= nil and record.seq == group[i - 1].seq
                    and (tied == nil or tied[#tied] ~= record.seq)) then
                tied = tied or {};
                tied[#tied + 1] = record.seq;
            end
            record.action.seq = i;
        end
        if (tied and Constants.DEBUG) then
            local action = group[1].action;
            DebindPrivate.DisplayMessage(format("Actions on %s%s shared seq %s; numbered in stored order.",
                action.key, action.arrivalID and (" (arrival " .. action.arrivalID .. ")") or "",
                table.concat(tied, ", ")));
        end
    end
end
