local _, DebindStorage = ...;

local DebindPrivate = DebindStorage.DebindPrivate;
local Constants     = DebindPrivate.Constants;
local luatype       = type;

--- Turning a received payload into actions in the profile.
---
--- **Everything that lands here is quarantined.** Each action carries `imported`, and while that is
--- set `BuildKeyMap` skips it: the string is in the profile, drawn and editable, and reaches no key
--- until the reader takes the badge off. So this function never changes what any key does, which is
--- what lets it run without asking anything first.
---
--- The reverse of `Export.lua`, and only that. Deciding *which* batch to commit, and what to do
--- with the result afterwards, belongs to the window and to the main window's Overview.

--- The wire says `{mode = "toggle", state = "$state3"}`; the profile stores one number with the
--- mode in the high bits and the state index in the low nibble. Names travel because an index is a
--- reference that always resolves and resolves to the wrong state (`Export.lua`).
local SETSTATE_MODE_FLAGS = {
    on = Constants.SETCUSTOM_MODE_ON,
    off = Constants.SETCUSTOM_MODE_OFF,
    toggle = Constants.SETCUSTOM_MODE_TOGGLE,
};


-- ---------------------------------------------------------------------------------------------
-- One action
-- ---------------------------------------------------------------------------------------------

--- Does this account or character have the very macro this action was pointing at?
---
--- **All three have to match: name, scope and body.** Name alone is what makes a macro reference
--- the one kind of breakage red text cannot see - a reader with a different macro of the same name
--- gets theirs, silently, and nothing anywhere says so. Comparing the body is what turns that from
--- a silent wrong answer into a fallback.
---
--- Matching means the reference comes back alive, which is what makes re-importing your own backup
--- give you back a `MACRO` rather than a flattened copy of its text.
local function MacroMatches(snapshot)
    if (luatype(snapshot) ~= "table" or not snapshot.name) then
        return false;
    end

    local name, _, body = GetMacroInfo(snapshot.name);
    if (not name or body ~= snapshot.body) then
        return false;
    end

    -- Scope is read the way the export read it: account macros hold the first block of slots.
    local index = GetMacroIndexByName(snapshot.name);
    if (not index or index <= 0) then
        return false;
    end
    local accountLimit = DebindPrivate.GetMacroSlotLimits();
    local scope = index > accountLimit and "character" or "account";
    return scope == snapshot.scope;
end

--- A wire action turned into a profile action.
---
--- **Filtered through the same whitelist the export copies out by** (`ACTION_FIELDS`). This used to
--- be a blacklist naming the format's own fields, and being the opposite of the other end is what
--- made it a hazard: a wire field nobody had thought to name rode straight into the profile, and
--- avoiding that was the last reason left for the ranking to travel under a name other than its own.
--- With both ends reading one list there is no name to dodge (`devdocs/building-export-import.md`).
---
--- `macro` and `setstate` stay out by being what they are -- the format's words, not the profile's.
--- Both are read below and neither travels further; `CleanUpDB` would drop them anyway, but leaving
--- them for it to find would mean the action is briefly a shape nothing else expects.
--- Whether one wire field may be copied, **by name and by type**.
---
--- A name filter alone let a field arrive as anything: `seq = {}` reached `ARRIVAL_SEQ + seq` and
--- raised halfway through `PlaceImportedActions`, `priority = {}` raised inside the `table.sort`
--- that follows, `checkedUnits = "x"` was walked with `pairs`. Every one of those went off after
--- part of the batch was already in the profile. The types are `ACTION_FIELDS`' values.
---
--- **A field of the wrong type is dropped, not corrected.** What it should have been is not
--- knowable, and an action missing a condition is a shape the rest of the addon already handles -
--- red text included - while a guessed one is a binding that fires when it should not.
---
--- `$`-prefixed names pass unlisted, the same escape hatch the export copies out through
--- (`CopyFields`) and `CleanUpDB` keeps: a custom state condition is stored under its own name, and
--- the redesign turns those into arbitrary names. They still have to be booleans - `$state1..5` are
--- declared as such and an arbitrary name does not make the value freer.
local function FieldAllowed(name, value)
    local expected = DebindStorage.ACTION_FIELDS[name];
    if (not expected) then
        return strsub(name, 1, 1) == "$" and luatype(value) == "boolean";
    end
    return strfind(expected, luatype(value), 1, true) ~= nil;
end

local function BuildAction(source)
    local action = {};
    for k, v in pairs(source) do
        if (luatype(k) == "string" and FieldAllowed(k, v)) then
            if (luatype(v) == "table") then
                action[k] = CopyTable(v);
            else
                action[k] = v;
            end
        end
    end

    -- **Asked whether it is a table, not whether it is there.** Everything below reads fields off
    -- these two, and a pasted string is untrusted input that none of this may error on -- a
    -- hand-made `setstate = 5` would raise here and take the whole commit down with it, halfway
    -- through placing a batch.
    if (luatype(source.setstate) == "table") then
        local flag = SETSTATE_MODE_FLAGS[source.setstate.mode];
        local index = Constants.CUSTOM_STATE_INDICES[source.setstate.state];
        if (flag and index) then
            action.value = flag + index;
        else
            -- A mode or a state name this version does not know. The action keeps its type and
            -- loses its value, which is the shape red text already has something to say about -
            -- better than guessing at a number that would set some other state.
            action.value = nil;
        end
    end

    -- **The macro decision, made once, here.** After this the action is a `MACRO` pointing at a
    -- macro that exists, or a `MACROTEXT` carrying the body it was sent with. It is not remade
    -- later: a reader who creates the macro afterwards keeps the `MACROTEXT`, which is not wrong,
    -- only flatter.
    if (action.type == Constants.MACRO and luatype(source.macro) == "table") then
        if (MacroMatches(source.macro)) then
            -- **Kept as a live reference, and pointed at the name.** The match was made on the
            -- name, but the value may be a slot index (old data on the sender's side), and that
            -- index means the reader's fourth macro rather than the one just matched. A `MACRO`
            -- stores a name anyway (`ActionCatalog.lua`), so this is also where the legacy shape
            -- stops being carried forward.
            action.value = source.macro.name;
        else
            action.type = Constants.MACROTEXT;
            action.value = source.macro.body;
            action.name = source.macro.name;
            action.icon = source.macro.icon;
        end
    end

    return action;
end


-- ---------------------------------------------------------------------------------------------
-- The whole batch
-- ---------------------------------------------------------------------------------------------

--- Turns the keys a string arrived with into the keys they will be stored under.
---
--- **A synthetic key is renumbered, a real one is kept.** The number in the string is unique inside
--- that string and nowhere else, so two strings waiting at once would both open at 1 and the reader
--- would be shown two unrelated sets under one heading. The reach is the whole store rather than
--- the layers this session can see: reusing a number that is alive in a class the reader has not
--- logged puts the collision a login away instead of removing it.
---
--- **`stripKeys` renames instead of removing.** Dropping the key would leave a conditional binding
--- as a pile of loose actions, and a wrong guess at which of them belonged together is silent --
--- two that were meant to share a key end up on two, and both fire. Renaming keeps the set intact
--- and says, in the one way the profile can hold, that its key is still to be decided.
---
--- Asked for lazily, and once: nothing is written until `PlaceImportedActions`, so asking again
--- mid-walk would answer the same thing every time; and a string that needs no synthetic key at all
--- does not pay for the walk.
local function KeyMapper(stripKeys)
    local mapped, nextKey = {}, nil;

    return function(key)
        local keyType = luatype(key);
        if (keyType ~= "string" and keyType ~= "number") then
            -- No key, or something a key cannot be. Either way it joins no group.
            return nil;
        end
        if (keyType == "string" and not stripKeys) then
            return key;
        end

        local synthetic = mapped[key];
        if (not synthetic) then
            nextKey = nextKey or DebindPrivate.NextSyntheticKey();
            synthetic, nextKey = nextKey, nextKey + 1;
            mapped[key] = synthetic;
        end
        return synthetic;
    end
end

--- Where each action of `payload` lands, and what it becomes.
---
--- Returns a flat list of `{ scope, class, spec, action }`. **Nothing is written here** - building
--- the list and putting it in the profile are separate so the caller can find out that a payload
--- has nowhere to go before any of it has gone there.
---
--- **The address is the path it was found at**, and it is a **storage** address rather than a layer
--- ID: layer IDs are this character's view of the profile, and a mage's layer has no ID in a
--- druid's session at all (`ImportAddress`). A key group is not an address and never was -- a key
--- crosses layers, so one group routinely lands in two places while staying one group.
---
--- Actions this version has no address for are left out, and the count comes back so the caller can
--- say so. What reaches that: a class name no client has, a spec number past the end of the store,
--- and a character-scoped spec this character does not have.
---
--- `options.lines` is a set of `IMPORT_LINES` entries to take, or nil for all of them. A line the
--- reader unticked is **not** counted as skipped -- they said no to it, which is not the same as
--- this version having nowhere to put it.
---
--- `options.stripKeys` is the mirror of the export's own option. What quarantine promises is that
--- nothing changes until the reader accepts; this promises that their keys are not touched even
--- then, which is a different thing and an ordinary thing to want.
function DebindStorage.PlanImport(payload, batchID, options)
    local placements, skipped = {}, 0;
    local lines = options and options.lines;
    local MapKey = KeyMapper(options and options.stripKeys);

    DebindStorage.ForEachPayloadLayer(payload, function(list, listScope, listClass, listSpec)
        -- **Asked for an address first, and the reader's answer second.** Every action with nowhere
        -- to go is counted, whatever the filter says: the lines are built out of what can land
        -- (`CollectImportLines`), so an unplaceable one was never offered and cannot have been
        -- turned down. Reading the filter first made those vanish silently - the window said
        -- "brought in 2" and never mentioned the five that did not fit.
        local scope, class, spec = DebindStorage.ImportAddress(listScope, listClass, listSpec);
        if (not scope) then
            skipped = skipped + #list;
            return;
        end

        if (lines) then
            local line = DebindStorage.ImportLineFor(listScope, listSpec);
            if (not (line and lines[line])) then
                -- Offered and unticked. That is an answer, not a failure, so it is not counted.
                return;
            end
        end

        for _, source in ipairs(list) do
            local action = BuildAction(source);
            action.key = MapKey(action.key);
            -- **No key, no number.** The invariant the profile keeps (`ClearActionKey`), held here
            -- as well so a hand-made string cannot walk one in: a number is a place among the
            -- actions sharing a key, and there is no key to be a place in.
            if (action.key == nil) then
                action.seq = nil;
            end
            action.imported = batchID;
            placements[#placements + 1] = {
                scope = scope, class = class, spec = spec, action = action,
            };
        end
    end);

    return placements, skipped;
end

--- Commits a batch into the profile, badged.
---
--- `options` is `PlanImport`'s, and comes from the dialog the press opened rather than from the
--- batch. **Nothing about which lines or whether to keep the keys is stored**: those answers are
--- worth exactly one press. Stored on the batch, "leave the keys out" outlived the moment it was
--- ticked and a reader who came back a week later got something other than what they asked for.
---
--- **Custom state definitions are not touched.** A state is shared by everything in the profile, so
--- writing one would change what the reader's *existing* actions do - before they approved
--- anything, and past the one thing quarantine is for. So an imported action that names `$state3`
--- uses the reader's `$state3`, which is the "keep mine" answer, and a name nothing defines is
--- already something red text says out loud (`BINDING_ISSUE_UNDEFINED_STATE`).
---
--- Asking instead - keep mine, take theirs, rename - is the one question this path is supposed to
--- put to the reader, and it is not built yet (`devdocs/building-export-import.md`). Until it is, the answer is
--- the one that cannot change anything they already had.
function DebindStorage.CommitBatch(batch, options)
    local payload, reason = DebindStorage.GetBatchPayload(batch);
    if (not payload) then
        return nil, reason;
    end

    local placements, skipped = DebindStorage.PlanImport(payload, batch.id, options);
    if (#placements == 0) then
        return nil, "NOTHING_TO_PLACE";
    end

    DebindPrivate.PlaceImportedActions(placements);

    -- The row says so from now on. Re-committing is allowed and makes a second copy, which is the
    -- same thing importing the same string twice has always done.
    batch.committed = time();

    return #placements, skipped;
end
