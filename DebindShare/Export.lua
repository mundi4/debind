local _, DebindShare = ...;

local DebindPrivate      = DebindShare.DebindPrivate;
local Constants          = DebindPrivate.Constants;
local luatype            = type;

--- Turning a selection of profile actions into one shareable string.
---
--- Nothing in here reads or writes the profile. `BuildExportPayload` walks layers and copies
--- fields out; `EncodeExportPayload` turns the copy into text. Import is a separate slice and
--- lives nowhere yet -- `DecodeExportString` exists only so the round trip is testable, and it
--- hands back a plain table, never an action.
---
--- Design notes and the open questions this file does **not** answer: `devdocs/building-export-import.md`.


--- The schema of `payload`. Bump when a field changes meaning, not when one is added -- a reader
--- that skips fields it does not know survives additions on its own.
---
--- **That rule starts at the first release that carries sharing. Until then this stays 1 whatever
--- happens to the shape.** Sharing did not ship with 3.1.6, so no v1 string has ever left this
--- repository and there is nothing out there to be read wrongly; burning version numbers on shapes
--- nobody has would only spend them. `layer` has already moved from the group to the action under
--- this same 1, and more of the shape is expected to move (`devdocs/building-export-import.md`).
local SCHEMA_VERSION     = 1;

--- How the bytes are packed, which is a **separate** number from the schema on purpose. Swapping
--- the compressor later has to invalidate old strings; adding a payload field must not. One
--- number for both would force every reader to treat those two as the same event.
local ENVELOPE_VERSION   = 1;
local ENVELOPE_PREFIX    = "DEB";
local ENVELOPE_SEPARATOR = ":";

--- Action fields that go out on the wire.
---
--- This is `KEYS_TO_SAVE` (`Profile.lua`) minus two, and the two are dropped for the same
--- reason: they describe **where the action sits in this profile**, not what it does.
---
---   `key` -- moves up to the group, which is the whole point of the group (see below)
---   `seq` -- an ordering number scoped to one layer, so it means nothing in the layer that
---            receives it. What the ranking means travels instead: actions are emitted in `seq`
---            order and each carries `order`, its 1..n place in the group, which the far side turns
---            into `importOrder`.
---
---            **It is not kept off the wire to prevent a collision**, which is what stood here.
---            Sent under its own name it would land on the action (`BuildAction` is a blacklist) and
---            then be cleared: `PlaceLast` opens with `action.seq = nil` and every imported action
---            goes through it. Whether `order` earns its own name is reopened in
---            `devdocs/building-export-import.md`.
---
--- `KEYS_TO_SAVE` is not reachable from here (it is a local, and this file stays off Profile.lua
--- deliberately), so the list is restated. **`tools/check-export-fields.js` fails the build when
--- the two drift** -- a field added to one and not the other is otherwise silent: the action
--- saves fine and simply never exports.
local ACTION_FIELDS      = {
    type = true,
    value = true,
    name = true,
    icon = true,
    unit = true,
    frameTypes = true,
    groups = true,
    known = true,
    combat = true,
    stealth = true,
    forms = true,
    bonusbars = true,
    specialbar = true,
    extrabar = true,
    pet = true,
    petbattle = true,
    priority = true,
    keepInBindingContext = true,
    ignoreHoverUnit = true,
    checkedUnits = true,
    ["$state1"] = true,
    ["$state2"] = true,
    ["$state3"] = true,
    ["$state4"] = true,
    ["$state5"] = true,
};

--- Which fields of a custom state definition describe the state, as opposed to what it happens
--- to be doing right now. `value` is deliberately absent: `BindDerivedTables` recomputes it from
--- `initialValue`/`savedValue` on every login, so sending it would ship a runtime reading as if
--- it were a setting.
local STATE_FIELDS       = {
    mode = true,
    initialValue = true,
    savedValue = true,
    displayMessage = true,
    expr = true,
};


-- ---------------------------------------------------------------------------------------------
-- Copying out
-- ---------------------------------------------------------------------------------------------

--- A field-by-field copy, tables included. Copying by reference here would put live profile
--- tables inside the payload, and `LibSerialize` would happily write them out -- but anything
--- that edited the payload afterwards (stripping keys, renaming a state) would be editing the
--- user's profile.
local function CopyFields(source, allowed)
    local copy = {};
    for k, v in pairs(source) do
        -- `$`-prefixed keys pass whether or not they are listed. That is the same escape hatch
        -- `CleanUpDB` uses (`Profile.lua`) -- custom state conditions are stored under their own
        -- name, and the redesign turns `$state1..5` into arbitrary names (`.zzz/custom-states-redesign.md`).
        -- Listing five and stopping there would silently drop every named state the day it lands.
        if (allowed[k] or strsub(k, 1, 1) == "$") then
            if (luatype(v) == "table") then
                copy[k] = CopyTable(v);
            else
                copy[k] = v;
            end
        end
    end
    return copy;
end

--- Where a layer sits, said in terms the receiving side can resolve. Layer **IDs** are not
--- portable: 2..6 are "my class", and the sender's class is not the reader's.
local function DescribeLayer(layer)
    if (layer.isCharacterSpecific) then
        return { scope = "character", spec = layer.spec };
    elseif (layer.layerID == 1) then
        return { scope = "general" };
    end
    return { scope = "class", class = Constants.PLAYER_CLASS, spec = layer.spec };
end

--- The macro body, so the reference does not have to survive the trip.
---
--- `MACRO` actions store a **name** and read the body out of the sender's macro store at build
--- time (`ConvertToMacroText` in `Misc.lua`). A name is the one kind of broken reference the
--- red-text safety net cannot catch, because it does not break: a reader who happens to have a
--- macro by that name gets **their** macro, silently. So the body travels alongside, and the
--- decision of whether to restore a live reference or fall back to `MACROTEXT` is the reader's.
---
--- Returns nil when the sender's own reference is already dangling. That case ships as-is under
--- the "send broken things too" rule -- but note that rule is currently unbacked for macros:
--- `GetBindingIssue` has no branch that checks whether an action's target exists, so a `MACRO`
--- naming nothing does **not** go red on the far side. `devdocs/building-export-import.md`, open question 7.
local function SnapshotMacro(macroName)
    local name, icon, body = GetMacroInfo(macroName);
    if (not name) then
        return nil;
    end

    -- Account macros occupy the first block of slots and character macros follow, so the index
    -- is what separates them -- `GetMacroInfo` itself does not say which store answered.
    local scope;
    local index = GetMacroIndexByName(macroName);
    if (index and index > 0) then
        local accountLimit = DebindPrivate.GetMacroSlotLimits();
        if (index > accountLimit) then
            scope = "character";
        else
            scope = "account";
        end
    end

    return { name = name, body = body, icon = icon, scope = scope };
end

--- Rewrites the parts of an action whose stored form is an **index into the sender's setup**.
---
--- `SETSTATE` packs mode and state index into one number (`SETCUSTOM_MODE_*` over the low
--- nibble). An index always resolves on the far side, and resolves to the wrong state, which
--- puts it outside what red text can see for the same reason a macro name is.
---
--- So it goes out on the **name** axis instead: `$state3` rather than 3. `$state1..5` stay valid
--- names after the custom-state rename (`.zzz/custom-states-redesign.md` step 1), so this shape
--- survives that change without a schema bump, and it commits nothing about how the profile
--- stores the value -- that decision is still §9-1's to make.
---
--- **`SETCUSTOM` is not this.** Despite the name it sets a custom *target* -- a unit slot, like
--- focus -- and its index is structural, meaning the same thing in every install. It travels
--- as-is.
local function NormalizeAction(action, out)
    if (action.type == Constants.SETSTATE) then
        local mode, stateIndex = DebindPrivate.GetSetCustomStateModeAndIndex(action.value);
        if (mode) then
            out.value = nil;
            out.setstate = { mode = mode, state = "$state" .. stateIndex };
        end
    elseif (action.type == Constants.MACRO and luatype(action.value) == "string") then
        out.macro = SnapshotMacro(action.value);
    end
end


-- ---------------------------------------------------------------------------------------------
-- Custom states referenced by what is being sent
-- ---------------------------------------------------------------------------------------------

--- Every custom state the exported actions name, by name.
---
--- Four places hold a reference (`.zzz/custom-states-redesign.md` §3-4) and three of them are
--- reachable from an action: the condition fields on the action itself, a `SETSTATE` value, and
--- names typed into macro text. The fourth is a state's own `expr` naming another state, which
--- is why this closes transitively rather than doing one pass.
local function CollectStateNames(actions, found)
    for i = 1, #actions do
        local action = actions[i];

        for k in pairs(action) do
            if (strsub(k, 1, 1) == "$") then
                found[k] = true;
            end
        end

        if (action.setstate) then
            found[action.setstate.state] = true;
        end

        if (action.type == Constants.MACROTEXT and luatype(action.value) == "string") then
            local _, args = DebindPrivate.ParseMacroText(action.value);
            if (args) then
                for j = 1, #args do
                    local arg = args[j];
                    if (arg.type == Constants.MACROTEXT_ARG_CUSTOM_STATE) then
                        found[arg.name] = true;
                    end
                end
            end
        end
    end
end

--- The manifest: every referenced state, definition included, keyed by name.
---
--- Names, not indices, because the receiving side has to be able to *ask* about a collision, and
--- `$state3` on two machines is two different states that an index can never tell apart. A name
--- nothing defines is also the one broken state reference red text already catches
--- (`BINDING_ISSUE_UNDEFINED_STATE`), so the reader is not left guessing.
---
--- A referenced state with no definition is left out rather than sent empty. The sender has
--- nothing to say about it, and an empty definition would read as "defined, and blank".
local function BuildStateManifest(actions)
    local referenced = {};
    CollectStateNames(actions, referenced);

    local manifest, any = {}, false;
    local pending = referenced;

    while (pending) do
        local nextPending;

        for name in pairs(pending) do
            if (manifest[name] == nil) then
                local index = Constants.CUSTOM_STATE_INDICES[name];
                local definition = index and DebindPrivate.CustomStates[index];
                if (definition) then
                    manifest[name] = CopyFields(definition, STATE_FIELDS);
                    any = true;

                    -- A conditional state's expression can name other states, and those have to
                    -- travel too or the definition arrives referring to nothing.
                    if (definition.mode == Constants.CUSTOM_STATE_MODES.MACRO_CONDITIONAL
                            and luatype(definition.expr) == "string") then
                        local _, args = DebindPrivate.ParseMacroText(definition.expr);
                        for j = 1, (args and #args or 0) do
                            local arg = args[j];
                            if (arg.type == Constants.MACROTEXT_ARG_CUSTOM_STATE
                                    and manifest[arg.name] == nil) then
                                nextPending = nextPending or {};
                                nextPending[arg.name] = true;
                            end
                        end
                    end
                end
            end
        end

        pending = nextPending;
    end

    if (not any) then
        return nil;
    end
    return manifest;
end


-- ---------------------------------------------------------------------------------------------
-- Grouping
-- ---------------------------------------------------------------------------------------------

--- Everything selected, split into groups.
---
--- A **group** is one key. It is the unit that has to stay together when the key is dropped: a
--- conditional binding is several actions that only mean something as a set, and "export without
--- keys" turns that set into loose actions unless something else holds it. The `id` is what holds
--- it -- identity lives there and not on `key`, which may be nil, may repeat, and is exactly the
--- field the option removes.
---
--- **A group spans layers, and the layer is written on each action.** It used to be a group field,
--- one group per (layer, key), and a key whose actions lived in two layers left as two groups. The
--- reason that was wrong shows up at the other end: with the keys stripped, the reader is handed
--- two headings for what the sender built as one key, gives them two keys, and both fire. There is
--- nothing in the string by then that could have told them otherwise.
---
--- Ranking inside a group therefore has to cross layers too, and it is `CompareActionOrder` that
--- does it -- the one place in this addon that says what runs first, so a string cannot be ordered
--- differently from the list the reader will see it in.
---
--- **Sent as if no specialization were active.** With one active its layers would rank ahead of the
--- rest, and then the same profile would produce a different string depending on which
--- specialization the sender happened to be in. With none, every spec layer is ranked by its own
--- number and the output is the sender's profile rather than the sender's afternoon. What the
--- reader sees is theirs to arrange anyway: the badge lands, and the overview sorts it against
--- *their* active specialization.
---
--- Keyless actions are singletons. In a profile nothing binds two keyless actions to each other
--- -- whatever group they arrived in was dissolved when they were placed.
local function GroupSelectedActions(isSelected)
    local byKey, keyOrder, keyless = {}, {}, {};
    -- Where this action turned up in the walk. The last tiebreak, and it exists because `sort` is
    -- not stable and two actions in one layer can carry the same `seq`. `CleanUpDB` is what usually
    -- keeps them apart, and it runs at login and at logout rather than after every edit -- so the
    -- promise this holds up is the export's own: the same profile has to give the same string.
    local ordinal = 0;

    for _, layer, scopeRank, specRank in DebindPrivate.EnumerateAllProfileLayers(0) do
        -- Built once per layer and shared by that layer's actions. The far side reads it and never
        -- keeps it (`BuildAction` drops it), so one table serving many actions is safe.
        local descriptor;

        for _, action in layer:Enumerate() do
            if (isSelected == nil or isSelected[action]) then
                descriptor = descriptor or DescribeLayer(layer);
                ordinal = ordinal + 1;
                -- The fields `CompareActionOrder` reads, and nothing else. `MakeRow` builds the
                -- same shape for the screen but pays for red text and reachability along the way,
                -- neither of which a string has any use for.
                local entry = {
                    action = action,
                    layer = descriptor,
                    ordinal = ordinal,
                    priority = action.priority,
                    hover = DebindPrivate.GetBindingInfoForAction(action).hover,
                    isConditional = DebindPrivate.IsConditionalAction(action),
                    layerRank = scopeRank,
                    specRank = specRank,
                    -- Read only while there is a key, the same way `MakeRow` reads it: a stored
                    -- number outlives the key it was issued for, and using it here would let a
                    -- keyless action that was briefly bound outrank its own `importOrder`.
                    seq = action.key ~= nil and action.seq or nil,
                    importOrder = action.importOrder,
                };

                if (action.key == nil) then
                    keyless[#keyless + 1] = entry;
                else
                    local bucket = byKey[action.key];
                    if (not bucket) then
                        bucket = {};
                        byKey[action.key] = bucket;
                        keyOrder[#keyOrder + 1] = action.key;
                    end
                    bucket[#bucket + 1] = entry;
                end
            end
        end
    end

    -- Sorted so the same profile always produces the same string. Re-exporting after touching
    -- nothing has to be a no-op the user can see is a no-op, and storage order is not stable
    -- across an edit. `CompareKeys` is the order the UI already shows keys in.
    sort(keyOrder, DebindPrivate.CompareKeys);

    local groups = {};
    for i = 1, #keyOrder do
        local bucket = byKey[keyOrder[i]];
        sort(bucket, function(lhs, rhs)
            if (DebindPrivate.CompareActionOrder(lhs, rhs)) then
                return true;
            elseif (DebindPrivate.CompareActionOrder(rhs, lhs)) then
                return false;
            end
            return lhs.ordinal < rhs.ordinal;
        end);
        groups[#groups + 1] = { key = keyOrder[i], entries = bucket };
    end
    for i = 1, #keyless do
        groups[#groups + 1] = { key = nil, entries = { keyless[i] } };
    end

    return groups;
end


-- ---------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------

DebindShare.EXPORT_SCHEMA_VERSION = SCHEMA_VERSION;

--- The table that becomes the string.
---
--- `selection` is a set of the action tables to send, or nil for everything stored. The export
--- window checks actions, so a set of actions is what it has; layers are walked here rather than
--- asked for, which is what makes the output ordered and the window's job a filter.
---
--- `options.stripKeys` drops every group's `key` and keeps every group's `id` -- the "send the
--- actions, not my keybinds" option, without the loose-pile failure it usually comes with.
---
--- **Nothing is validated.** A broken action exports exactly as it sits. The receiving side shows
--- it in red and the user deletes it, and that one rule is what removes a whole class of
--- questions about spells the reader does not have. Where the red text cannot in fact see the
--- breakage, the format carries the answer instead -- see `SnapshotMacro` and `NormalizeAction`.
function DebindShare.BuildExportPayload(selection, options)
    local stripKeys = options and options.stripKeys;

    local groups, exported = {}, {};
    local sourceGroups = GroupSelectedActions(selection);

    for i = 1, #sourceGroups do
        local source = sourceGroups[i];
        local actions = {};

        for j = 1, #source.entries do
            local entry = source.entries[j];
            local copy = CopyFields(entry.action, ACTION_FIELDS);
            NormalizeAction(entry.action, copy);
            -- **Where this action lived, said in terms the far side can resolve.** On the action
            -- rather than the group because a group is a key and a key crosses layers.
            copy.layer = entry.layer;
            -- **Which of this key's actions goes first, said out loud.** The bucket is already
            -- sorted, so the position is the answer; what it must not be called is `seq`, because
            -- the far side copies wire fields by name and that one would land on the action and
            -- collide with the numbers the receiving layer has handed out. Computed here rather
            -- than copied, which is why neither this nor `layer` is in `ACTION_FIELDS` at either
            -- end (`tools/check-export-fields.js`).
            copy.order = j;
            actions[#actions + 1] = copy;
            exported[#exported + 1] = copy;
        end

        groups[#groups + 1] = {
            -- **Only a group that was on a key gets identity**, and the reason is what the far side
            -- is asked to think about.
            --
            -- A sender exports whole layers, so actions they built and never bound go out with the
            -- rest. Given identity, one of those arrives headed as a set whose key was withheld -
            -- which says *this was part of the design, decide what key it deserves*. It was not.
            -- The reader is left working out what it is for and whether they are supposed to use
            -- it, over something the sender does not use either.
            --
            -- Without the distinction the far side cannot make it. Once keys are stripped a
            -- one-action key and a never-bound action arrive as the same table, so this is the only
            -- end that still knows.
            --
            -- The number stays local to this string. The far side takes its own (`PlanImport`),
            -- because ids repeat across strings and two can be waiting.
            id = source.key ~= nil and (#groups + 1) or nil,
            key = (not stripKeys) and source.key or nil,
            actions = actions,
        };
    end

    return {
        v = SCHEMA_VERSION,
        -- The sender's class, because `scope = "class"` layers cannot be read without it. Nothing
        -- else about the sender travels: a string meant to be pasted into a public channel should
        -- not carry a character name the user did not choose to type.
        class = Constants.PLAYER_CLASS,
        states = BuildStateManifest(exported),
        groups = groups,
    };
end

--- LibStub is asked at call time, not at load. This file is loaded by the headless specs, which
--- test the payload without standing the libraries up.
local function GetLibs()
    if (not LibStub) then
        return nil, nil;
    end
    return LibStub("LibSerialize", true), LibStub("LibDeflate", true);
end

--- `DEB<envelope>:<printable>`. The version is outside the compressed blob so a reader can turn
--- down a string it cannot decode without first trying to decompress it.
function DebindShare.EncodeExportPayload(payload)
    local LibSerialize, LibDeflate = GetLibs();
    if (not LibSerialize or not LibDeflate) then
        return nil, "LIBS_MISSING";
    end

    local compressed = LibDeflate:CompressDeflate(LibSerialize:Serialize(payload), { level = 9 });
    return ENVELOPE_PREFIX .. ENVELOPE_VERSION .. ENVELOPE_SEPARATOR
        .. LibDeflate:EncodeForPrint(compressed);
end

--- The inverse, and **only** the inverse. It answers "what was in the string"; it does not touch
--- the profile and does not produce actions. Deciding what to do with the result is import's job
--- and import does not exist yet.
---
--- Returns nil plus a reason for anything malformed. A pasted string is user input from an
--- untrusted place, so every step here is allowed to fail and none of them may error.
function DebindShare.DecodeExportString(str)
    if (luatype(str) ~= "string") then
        return nil, "NOT_A_STRING";
    end

    local version, encoded = strmatch(strtrim(str), "^" .. ENVELOPE_PREFIX .. "(%d+)"
        .. ENVELOPE_SEPARATOR .. "(.+)$");
    if (not version) then
        return nil, "NOT_A_DEBIND_STRING";
    end
    if (tonumber(version) ~= ENVELOPE_VERSION) then
        return nil, "UNSUPPORTED_ENVELOPE";
    end

    local LibSerialize, LibDeflate = GetLibs();
    if (not LibSerialize or not LibDeflate) then
        return nil, "LIBS_MISSING";
    end

    local compressed = LibDeflate:DecodeForPrint(encoded);
    if (not compressed) then
        return nil, "BAD_ENCODING";
    end

    local serialized = LibDeflate:DecompressDeflate(compressed);
    if (not serialized) then
        return nil, "BAD_COMPRESSION";
    end

    local ok, payload = LibSerialize:Deserialize(serialized);
    if (not ok or luatype(payload) ~= "table") then
        return nil, "BAD_PAYLOAD";
    end
    if (payload.v ~= SCHEMA_VERSION) then
        return nil, "UNSUPPORTED_SCHEMA";
    end

    return payload;
end

--- What the window calls: selection in, string out.
function DebindShare.ExportSelection(selection, options)
    return DebindShare.EncodeExportPayload(DebindShare.BuildExportPayload(selection, options));
end
