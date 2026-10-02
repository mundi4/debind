-- The switches an arrival brings, settled when its actions are accepted
-- (`resolving-switches-on-accept.md`).
--
-- Adding an entry keeps the sender's rows for the switches its actions name, already moved to this
-- profile's addresses, in the arrival's record (`arrivals[guid][arrivalID]`). Nothing is written to
-- the reader's switches then. When the actions are accepted or given a key, what they name is
-- compared with the profile as it is at that moment: a name the profile lacks is made from the kept
-- rows, a name whose kept rows all match is left alone, and the rest go to the window
-- (`ArrivalSwitchesUI.lua`). The window's answers are held in an `answers` table and written only
-- where the badge comes off (`TakeBadgesOff`), so cancelling anywhere before that changes nothing.
local _, DebindPrivate = ...;
local Constants        = DebindPrivate.Constants;
local luatype          = type;

local MANUAL           = Constants.SWITCH_MODES.MANUAL;
local EXPR             = Constants.SWITCH_MODES.EXPR;
local GENERAL_LAYER_ID = 1;

--------------------------------------------------------------------------------
-- The record
--------------------------------------------------------------------------------

--- This character's record of one arrival, or nil.
function DebindPrivate.GetArrivalRecord(arrivalID)
    local all = DebindPrivate.db.global.arrivals;
    local mine = all and all[DebindPrivate.playerGUID];
    return mine and mine[arrivalID];
end

--- Keeps an arrival's switch rows. `switches` is `{ [name] = cells }`, the cells being
--- `{ general = row, class = { [spec] = row }, character = { [spec] = row } }` at this character's
--- addresses (`DebindStorage.ArrivalSwitchRows`). An arrival with no rows keeps no record.
function DebindPrivate.RecordArrival(arrivalID, switches)
    if (arrivalID == nil or switches == nil or next(switches) == nil) then
        return;
    end
    local db = DebindPrivate.db.global;
    local guid = DebindPrivate.playerGUID;
    db.arrivals = db.arrivals or {};
    db.arrivals[guid] = db.arrivals[guid] or {};
    db.arrivals[guid][arrivalID] = { switches = switches };
end

--- Every kept row of one name, `fn(layerID, row)`. A spec this character has no layer for is
--- passed over rather than handed to `GetLayerID`, which asserts on it.
local function EachCell(cells, fn)
    if (cells.general) then
        fn(GENERAL_LAYER_ID, cells.general);
    end
    for _, scope in ipairs({ "class", "character" }) do
        for spec, row in pairs(cells[scope] or {}) do
            local layerID = luatype(spec) == "number" and DebindPrivate.LayerIDAt(spec, scope == "character");
            if (layerID and DebindPrivate.GetProfileLayer(layerID)) then
                fn(layerID, row);
            end
        end
    end
end

--- The other switches a row's expression names.
local function EachNameInExpr(row, fn)
    if (row.mode ~= EXPR or luatype(row.expr) ~= "string") then
        return;
    end
    local _, args = DebindPrivate.ParseMacroText(row.expr);
    for i = 1, (args and #args or 0) do
        if (args[i].type == Constants.MACROTEXT_ARG_SWITCH) then
            fn(args[i].name);
        end
    end
end

--------------------------------------------------------------------------------
-- Comparing
--------------------------------------------------------------------------------

--- **`expr` is compared only where the mode is the expression answer.** Choosing another answer
--- leaves the words behind on the row (`SetSwitchAnswer`), and they decide nothing there; compared
--- anyway, two rows that behave the same would be put to the reader as a conflict.
---
--- The remembered value is not compared: it is one character's on/off, not a setting, and a
--- payload does not carry it.
local function SameRow(lhs, rhs)
    local mode = lhs.mode or MANUAL;
    if (mode ~= (rhs.mode or MANUAL) or lhs.resetValue ~= rhs.resetValue) then
        return false;
    end
    return mode ~= EXPR or lhs.expr == rhs.expr;
end

local function SameCells(lhs, rhs)
    local count, same = 0, true;
    local rows = {};
    EachCell(lhs, function(layerID, row)
        rows[layerID] = row;
        count = count + 1;
    end);
    EachCell(rhs, function(layerID, row)
        count = count - 1;
        if (not rows[layerID] or not SameRow(rows[layerID], row)) then
            same = false;
        end
    end);
    return same and count == 0;
end

local function CopyRow(row)
    return { mode = row.mode, resetValue = row.resetValue, expr = row.expr };
end

--- One name's entry in `answers.creates` or `answers.writes`: rows by layer, and which arrivals
--- each row came from. Copied from `cells` when given.
local function NewEntry(cells, arrivalIDs)
    local entry = { cells = {}, origins = {} };
    if (cells) then
        EachCell(cells, function(layerID, row)
            entry.cells[layerID] = CopyRow(row);
            entry.origins[layerID] = arrivalIDs;
        end);
    end
    return entry;
end

--- A fresh table for one flow's answers.
---
--- * `creates[name]` -- switches the profile does not have, made from the kept rows (`NewEntry`).
---   Names the reader renamed to are here too
--- * `writes[name]` -- same shape, the rows the reader ticked
--- * `renames` -- `{ arrivalIDs, from, to }`
--- * `resolved` -- `{ arrivalIDs, name }`: answered, so the next acceptance from the same arrival is
---   not asked again
---
--- **The profile seen through it is what the next window compares with** (`MyRow`), since nothing
--- is written until the badge comes off (6-1, 6-4).
function DebindPrivate.NewArrivalAnswers()
    return { creates = {}, writes = {}, renames = {}, resolved = {} };
end

local function LayerKeyOf(layerID)
    if (layerID == GENERAL_LAYER_ID) then
        return nil;
    end
    return DebindPrivate.GetSwitchLayerKey(layerID);
end

--- The reader's row at one layer as the profile would stand with `answers` written. Nil where the
--- layer has none.
local function MyRow(name, layerID, answers)
    local created = answers.creates[name];
    if (created) then
        return created.cells[layerID];
    end
    local written = answers.writes[name];
    if (written and written.cells[layerID]) then
        return written.cells[layerID];
    end
    local mode, resetValue, expr = DebindPrivate.GetSwitchAnswerAt(name, LayerKeyOf(layerID));
    if (mode == nil) then
        return nil;
    end
    return { mode = mode, resetValue = resetValue, expr = expr };
end

--- What a layer with no row of its own answers with now: the next row down the cascade
--- `ResolveSwitchAnswer` walks (character+spec, character, class+spec, class, then the root). For
--- the window's fill tooltip. A spec-0 layer falls to the specialization the character is in.
function DebindPrivate.ArrivalRowBelow(name, layerID, answers)
    local spec = C_SpecializationInfo.GetSpecialization() or 0;
    local below;
    local charSpecs, classSpecs = DebindPrivate.GetLayerID(0, true), DebindPrivate.GetLayerID(0, false);
    if (layerID > charSpecs) then
        below = { charSpecs, layerID - charSpecs + classSpecs, classSpecs };
    elseif (layerID == charSpecs) then
        local live = spec > 0 and DebindPrivate.GetProfileLayer(classSpecs + spec) and classSpecs + spec;
        below = live and { live, classSpecs } or { classSpecs };
    elseif (layerID > classSpecs) then
        below = { classSpecs };
    else
        below = {};
    end
    below[#below + 1] = GENERAL_LAYER_ID;
    for _, other in ipairs(below) do
        local row = MyRow(name, other, answers);
        if (row) then
            return row;
        end
    end
    return nil;
end

local function SwitchExists(name, answers)
    return DebindPrivate.Switches[name] ~= nil or answers.creates[name] ~= nil;
end
DebindPrivate.ArrivalSwitchExists = SwitchExists;

--------------------------------------------------------------------------------
-- What to ask
--------------------------------------------------------------------------------

--- Which of `actions` are waiting, and on which arrival, at the moment the window opens.
function DebindPrivate.SnapshotArrivalBadges(actions)
    local snapshot = {};
    for _, action in ipairs(actions) do
        if (action.arrivalID) then
            snapshot[action] = action.arrivalID;
        end
    end
    return snapshot;
end

--- Are they all still waiting on the same arrival, and still in the profile?
---
--- **The window does not hold the rest of the screen**, so between opening and [OK] the reader can
--- reject, delete or accept those very actions some other way. An answer given for a set that is
--- no longer there must write nothing: no badge comes off a table no layer holds, and no switch is
--- written for an arrival the reader turned down.
function DebindPrivate.ArrivalBadgesHold(snapshot)
    for action, arrivalID in pairs(snapshot) do
        if (action.arrivalID ~= arrivalID or not DebindPrivate.FindLayerID(action)) then
            return false;
        end
    end
    return true;
end

--- The switches `actions` name that `cellsByName` has rows for, closed over those rows'
--- expressions, into `names` as `name -> cells`.
---
--- **The one rule for which switches an arrival depends on**, read where its rows are kept
--- (`DebindStorage.ArrivalSwitchRows`) and where they are asked about (`NamesByArrival`). Two
--- copies would let the window ask about rows that were never kept, or miss ones that were.
function DebindPrivate.CollectArrivalSwitches(actions, cellsByName, names)
    names = names or {};
    local queue = {};
    for _, action in ipairs(actions) do
        DebindPrivate.ForEachSwitchInAction(action, function(name)
            queue[#queue + 1] = name;
        end);
    end
    while (#queue > 0) do
        local name = table.remove(queue);
        local cells = cellsByName[name];
        if (names[name] == nil and cells) then
            names[name] = cells;
            EachCell(cells, function(_, row)
                EachNameInExpr(row, function(other)
                    queue[#queue + 1] = other;
                end);
            end);
        end
    end
    return names;
end

--- Per arrival, the names these actions call that its record keeps rows for and has not answered.
--- `{ [arrivalID] = { [name] = cells } }`.
local function NamesByArrival(actions)
    local byArrival = {};
    for _, action in ipairs(actions) do
        local arrivalID = action.arrivalID;
        local record = arrivalID and DebindPrivate.GetArrivalRecord(arrivalID);
        if (record and record.switches) then
            local names = byArrival[arrivalID] or {};
            byArrival[arrivalID] = names;
            DebindPrivate.CollectArrivalSwitches({ action }, record.switches, names);
            for name in pairs(names) do
                if (record.resolved and record.resolved[name]) then
                    names[name] = nil;
                end
            end
        end
    end
    for arrivalID, names in pairs(byArrival) do
        if (next(names) == nil) then
            byArrival[arrivalID] = nil;
        end
    end
    return byArrival;
end

local function SortedKeys(tbl)
    local keys = {};
    for key in pairs(tbl) do
        keys[#keys + 1] = key;
    end
    table.sort(keys);
    return keys;
end

--- The windows these actions need, in the order to ask them: a list of arrival ID lists.
---
--- **One, unless two arrivals hold the same name with different rows.** Then each arrival is asked
--- in turn, in `arrivalID` order, each against the profile with the earlier answers laid over it,
--- so one window never has two sources for one switch (6-1).
function DebindPrivate.ArrivalSwitchSteps(actions)
    local byArrival = NamesByArrival(actions);
    local ids = SortedKeys(byArrival);
    local seen, clash = {}, false;
    for _, arrivalID in ipairs(ids) do
        for name, cells in pairs(byArrival[arrivalID]) do
            if (seen[name] and not SameCells(seen[name], cells)) then
                clash = true;
            end
            seen[name] = seen[name] or cells;
        end
    end
    if (#ids == 0) then
        return {}, byArrival;
    end
    if (not clash) then
        return { ids }, byArrival;
    end
    local steps = {};
    for i, arrivalID in ipairs(ids) do
        steps[i] = { arrivalID };
    end
    return steps, byArrival;
end

--- One step's questions. A name the profile (seen through `answers`) lacks goes straight into
--- `answers.creates`; one whose kept rows all match is nothing to do; the rest come back as items,
--- sorted by name:
---
--- `{ name, arrivalIDs = { [id] = true }, cells, rows = { { layerID, incoming, mine } } }`, where
--- `mine` is nil for a layer the reader has no row on (filling) and a row otherwise (overwriting).
--- Only the rows that would change something are listed (6-2).
function DebindPrivate.ClassifyArrivalSwitches(byArrival, arrivalIDs, answers)
    local merged = {};
    for _, arrivalID in ipairs(arrivalIDs) do
        for name, cells in pairs(byArrival[arrivalID] or {}) do
            local entry = merged[name];
            if (not entry) then
                entry = { name = name, cells = cells, arrivalIDs = {} };
                merged[name] = entry;
            end
            entry.arrivalIDs[arrivalID] = true;
        end
    end

    local items = {};
    for _, name in ipairs(SortedKeys(merged)) do
        local entry = merged[name];
        if (not SwitchExists(name, answers)) then
            -- **Only a folded name is made.** `CreateSwitch` files `$Burst` as `$burst`, so the
            -- actions would go on calling a name nothing defines -- and where the reader has
            -- `$burst` the make is refused and the conflict was never asked. Left alone, the name
            -- goes red as any undefined one does.
            if (name == strlower(name)) then
                answers.creates[name] = NewEntry(entry.cells, entry.arrivalIDs);
            end
        else
            local rows = {};
            EachCell(entry.cells, function(layerID, row)
                local mine = MyRow(name, layerID, answers);
                if (mine == nil or not SameRow(mine, row)) then
                    rows[#rows + 1] = { layerID = layerID, incoming = row, mine = mine };
                end
            end);
            if (#rows > 0) then
                table.sort(rows, function(lhs, rhs) return lhs.layerID < rhs.layerID; end);
                entry.rows = rows;
                items[#items + 1] = entry;
            end
        end
    end
    return items;
end

--- Is this name free to rename an item to: not in the profile, not about to be made, not already
--- another item's new name, and not one the item's own arrivals keep rows for -- the rename moves
--- the kept rows under the new name, and would put them over that switch's. Answers the folded
--- name, or nil and the locale key.
function DebindPrivate.CheckArrivalRename(typed, answers, takenNow, arrivalIDs)
    if (not Constants.IsValidSwitchName(typed)) then
        return nil, "SWITCH_NAME_ERROR_INVALID";
    end
    local name = strlower(typed);
    if (SwitchExists(name, answers) or (takenNow and takenNow[name])) then
        return nil, "SWITCH_NAME_ERROR_TAKEN";
    end
    for arrivalID in pairs(arrivalIDs or {}) do
        local record = DebindPrivate.GetArrivalRecord(arrivalID);
        if (record and record.switches and record.switches[name]) then
            return nil, "SWITCH_NAME_ERROR_TAKEN";
        end
    end
    return name;
end

--- A rename reaches the rows that came from its arrivals, wherever they were written. **By each
--- row's own origin**, since one name's entry can hold rows from more than one window.
local function RenameInExprs(answers, arrivalIDs, from, to)
    for _, tbl in ipairs({ answers.creates, answers.writes }) do
        for _, entry in pairs(tbl) do
            for layerID, row in pairs(entry.cells) do
                local fromThese = false;
                for id in pairs(entry.origins[layerID]) do
                    fromThese = fromThese or arrivalIDs[id] == true;
                end
                if (fromThese and luatype(row.expr) == "string") then
                    row.expr = DebindPrivate.RenameSwitchInMacroText(row.expr, from, to);
                end
            end
        end
    end
end

--- Takes one window's answers into `answers`. `choices[item] = { rename = name }` or
--- `{ checked = { [layerID] = true } }`.
---
--- **A renamed switch comes in whole under its new name**, every kept row, and every name it is
--- called by in the same arrival follows -- the arrival's pending actions and the other kept rows'
--- expressions (6-3).
function DebindPrivate.AnswerArrivalSwitches(answers, items, choices)
    for _, item in ipairs(items) do
        local choice = choices[item] or {};
        local name = item.name;
        if (choice.rename) then
            answers.creates[choice.rename] = NewEntry(item.cells, item.arrivalIDs);
            answers.renames[#answers.renames + 1] = { arrivalIDs = item.arrivalIDs, from = name, to = choice.rename };
            name = choice.rename;
        else
            for _, row in ipairs(item.rows) do
                if (choice.checked and choice.checked[row.layerID]) then
                    -- **Onto a switch an earlier window is making, the row goes into that make**,
                    -- which is what the next window compares with (`MyRow`).
                    local target = answers.creates[name] or answers.writes[name];
                    if (not target) then
                        target = NewEntry(nil, nil);
                        answers.writes[name] = target;
                    end
                    target.cells[row.layerID] = CopyRow(row.incoming);
                    target.origins[row.layerID] = item.arrivalIDs;
                end
            end
        end
        answers.resolved[#answers.resolved + 1] = { arrivalIDs = item.arrivalIDs, name = name };
    end
    for _, rename in ipairs(answers.renames) do
        if (not rename.carried) then
            rename.carried = true;
            RenameInExprs(answers, rename.arrivalIDs, rename.from, rename.to);
        end
    end
end

--------------------------------------------------------------------------------
-- Writing
--------------------------------------------------------------------------------

local function WriteRow(name, layerID, row, undo)
    local layerKey = LayerKeyOf(layerID);
    if (undo) then
        local mode, resetValue, expr = DebindPrivate.GetSwitchAnswerAt(name, layerKey);
        undo[#undo + 1] = function()
            if (mode == nil) then
                DebindPrivate.RemoveSwitchOverride(name, layerKey);
            else
                DebindPrivate.SetSwitchAnswer(name, layerKey, mode, resetValue);
                DebindPrivate.SetSwitchExpression(name, layerKey, expr);
            end
        end;
    end
    DebindPrivate.SetSwitchAnswer(name, layerKey, row.mode, row.resetValue);
    DebindPrivate.SetSwitchExpression(name, layerKey, row.expr);
end

local function SnapshotRecord(arrivalID, undo)
    local mine = DebindPrivate.db.global.arrivals and DebindPrivate.db.global.arrivals[DebindPrivate.playerGUID];
    local record = mine and mine[arrivalID];
    if (undo and record and not undo.records[arrivalID]) then
        undo.records[arrivalID] = true;
        local copy = CopyTable(record);
        undo[#undo + 1] = function()
            mine[arrivalID] = copy;
        end;
    end
    return record;
end

local function ApplyAnswers(answers, undo)
    if (undo) then
        undo.records = undo.records or {};
    end

    for _, name in ipairs(SortedKeys(answers.creates)) do
        local created = answers.creates[name];
        if (not DebindPrivate.Switches[name]) then
            local ok, filed = DebindPrivate.CreateSwitch(name);
            if (ok) then
                if (undo) then
                    undo[#undo + 1] = function() DebindPrivate.DeleteSwitch(filed); end;
                end
                -- The root first: a layer row written before it would stand under a definition
                -- still holding the defaults.
                local layerIDs = SortedKeys(created.cells);
                for _, layerID in ipairs(layerIDs) do
                    WriteRow(filed, layerID, created.cells[layerID]);
                end
            end
        end
    end

    for name, written in pairs(answers.writes) do
        if (DebindPrivate.Switches[name]) then
            for layerID, row in pairs(written.cells) do
                WriteRow(name, layerID, row, undo);
            end
        end
    end

    for _, rename in ipairs(answers.renames) do
        for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
            for _, action in layer:Enumerate() do
                if (action.arrivalID and rename.arrivalIDs[action.arrivalID]) then
                    if (undo) then
                        local conditions = action.conditions and CopyTable(action.conditions);
                        local value = action.value;
                        undo[#undo + 1] = function()
                            action.conditions = conditions;
                            action.value = value;
                        end;
                    end
                    DebindPrivate.RenameSwitchInAction(action, rename.from, rename.to);
                end
            end
        end
        for arrivalID in pairs(rename.arrivalIDs) do
            local record = SnapshotRecord(arrivalID, undo);
            if (record and record.switches) then
                record.switches[rename.to] = record.switches[rename.from];
                record.switches[rename.from] = nil;
                for _, cells in pairs(record.switches) do
                    EachCell(cells, function(_, row)
                        if (luatype(row.expr) == "string") then
                            row.expr = DebindPrivate.RenameSwitchInMacroText(row.expr, rename.from, rename.to);
                        end
                    end);
                end
            end
        end
    end

    for _, resolved in ipairs(answers.resolved) do
        for arrivalID in pairs(resolved.arrivalIDs) do
            local record = SnapshotRecord(arrivalID, undo);
            if (record) then
                record.resolved = record.resolved or {};
                record.resolved[resolved.name] = true;
            end
        end
    end

    -- A make announces itself (`CreateSwitch`); rows written over existing switches do not.
    if (next(answers.writes) or #answers.renames > 0) then
        DebindPrivate.OnSwitchesChanged();
    end
end

--- **The one door a badge comes off through.** Every path that accepts an arrival -- accepting it,
--- giving it a key, [Unbind key] in the key window -- ends here, so the answers the switch window
--- held are written at the end of that flow and nowhere earlier, and a new way to accept cannot
--- leave its switches behind (6-1).
---
--- `answers` is written once however many times a flow passes through (`SetKeyForActions` calls
--- this per action), and before the badges go: a rename has to find the arrival's pending actions
--- by their badge. `undo`, when given, collects what puts it all back (bind mode's cancel,
--- `CancelBindMode`).
function DebindPrivate.TakeBadgesOff(actions, answers, undo)
    if (answers and not answers.applied) then
        answers.applied = true;
        ApplyAnswers(answers, undo);
    end
    for i = 1, #actions do
        actions[i].arrivalID = nil;
    end
end

--- Runs an `undo` list collected by `TakeBadgesOff`, newest first.
function DebindPrivate.RunArrivalUndo(undo)
    for i = #undo, 1, -1 do
        undo[i]();
    end
    if (#undo > 0) then
        DebindPrivate.OnSwitchesChanged();
    end
end
