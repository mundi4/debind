local _, DebindShare = ...;

local DebindPrivate      = DebindShare.DebindPrivate;
local Constants          = DebindPrivate.Constants;
local luatype            = type;

--- Turning a selection of profile actions into one shareable string.
---
--- Nothing in here reads or writes the profile. `BuildExportPayload` walks layers and copies
--- fields out; `EncodeExportPayload` turns the copy into text. `DecodeExportString` is the inverse
--- of that last step and nothing more -- it hands back a plain table, never an action. Turning one
--- into actions is `Import.lua`.
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
--- This is `KEYS_TO_SAVE` (`Profile.lua`) minus one: `imported` says which batch an action arrived
--- on **in this drawer**, which is the one field that means nothing anywhere else.
---
--- `key` and `seq` are on the list. They used to be the two exceptions -- `key` moved up to a group
--- layer and `seq` was replaced by a computed `order` -- and both reasons are gone: a key **is** the
--- group now, so there is nothing above the action to hold it, and the collision `seq` was renamed
--- to avoid was never there. `PlaceImportedActions` is the only way these reach the profile and it
--- overwrites `seq` on every one of them with an arrival number before renumbering the group, so a
--- sender's number cannot survive landing. `devdocs/building-export-import.md`.
---
--- `KEYS_TO_SAVE` is not reachable from here (it is a local, and this file stays off Profile.lua
--- deliberately), so the list is restated. **`tools/check-export-fields.js` fails the build when
--- the two drift** -- a field added to one and not the other is otherwise silent: the action
--- saves fine and simply never exports.
local ACTION_FIELDS      = {
    type = true,
    value = true,
    key = true,
    seq = true,
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

--- Read by `Import.lua`, which filters the incoming table through the **same** list. One side a
--- whitelist and the other a blacklist is what let a wire field nobody named ride into the profile.
DebindShare.ACTION_FIELDS = ACTION_FIELDS;

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

--- The list in `payload` this layer's actions go into, built on the way down.
---
--- **The path is the address.** It is the shape the profile stores under
--- (`shared.GENERAL`, `shared.classes[class][spec]`, `char[spec]`), so nothing describes a layer and
--- nothing translates one -- the two profiles use the same coordinate system and what differs is
--- only *which class*, which is a value of the coordinate. Which is also what lets the drawing code
--- be reused on a payload later without a translation step in front of it
--- (`devdocs/building-export-import.md`).
---
--- Layer **IDs** are what cannot travel: 2..6 are "my class", and the sender's class is not the
--- reader's. The character block drops the guid for the same reason -- "their character" means
--- nothing here, so it says *this* character at that spec.
local function BucketForLayer(payload, layer)
    local specTbl;

    if (layer.isCharacterSpecific) then
        specTbl = payload.char;
        if (not specTbl) then
            specTbl = {};
            payload.char = specTbl;
        end
    else
        local shared = payload.shared;
        if (not shared) then
            shared = {};
            payload.shared = shared;
        end

        if (layer.layerID == 1) then
            local general = shared.GENERAL;
            if (not general) then
                general = {};
                shared.GENERAL = general;
            end
            return general;
        end

        local classes = shared.classes;
        if (not classes) then
            classes = {};
            shared.classes = classes;
        end
        specTbl = classes[Constants.PLAYER_CLASS];
        if (not specTbl) then
            specTbl = {};
            classes[Constants.PLAYER_CLASS] = specTbl;
        end
    end

    local spec = layer.spec or 0;
    local tbl = specTbl[spec];
    if (not tbl) then
        tbl = {};
        specTbl[spec] = tbl;
    end
    return tbl;
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
-- Leaving the keys out
-- ---------------------------------------------------------------------------------------------

--- Hands out the synthetic keys "export without the keys" replaces the real ones with.
---
--- **The option renames a key, it does not remove one.** A conditional binding is several actions
--- that only mean anything as a set, and dropping the key outright is what turns that set into a
--- loose pile the reader cannot put back together. Same key in, same key out, so the grouping needs
--- nothing declared anywhere: it *is* the key.
---
--- **A number, and the type is the whole test.** A string prefix (`export#1`) would be a key that
--- looks like a key -- one guard missed and it is drawn as though the reader had bound it -- while
--- a number cannot be a binding string at all, so the same slip is loud: `GetBindingText` and
--- `SetBindingClick` have nothing to do with one. `devdocs/building-export-import.md`.
---
--- Numbered in the order the walk meets them, which is stable for an unedited profile. The value
--- means nothing outside this one string -- the reader hands out their own on the way in, because
--- two strings waiting at once would both start at 1.
local function KeyRenamer()
    local renamed, next = {}, 1;
    return function(key)
        if (key == nil) then
            -- **An action that never had a key goes out without one**, and the rule "a set nobody
            -- bound gets no group" stops being a rule and becomes the shape: with no key it is in
            -- nobody's key group.
            return nil;
        end
        local synthetic = renamed[key];
        if (not synthetic) then
            synthetic = next;
            renamed[key] = synthetic;
            next = next + 1;
        end
        return synthetic;
    end
end


-- ---------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------

DebindShare.EXPORT_SCHEMA_VERSION = SCHEMA_VERSION;

--- The table that becomes the string.
---
--- `selection` is a set of the action tables to send, or nil for everything stored. The export
--- window checks actions, so a set of actions is what it has; layers are walked here rather than
--- asked for, which is what puts the payload in storage shape and leaves the window a filter.
---
--- `options.stripKeys` is "send the actions, not my keybinds": every key is replaced by a synthetic
--- one (`KeyRenamer`), so nothing is lost but the key itself.
---
--- **Emitted in storage order, one layer at a time.** Which of a key's actions goes first travels as
--- `seq`, so the array is not carrying that and does not have to be sorted to say it; and storage
--- order is stable for a profile nobody has edited, which is what re-exporting has to be able to
--- show. Whether a layer's actions are clumped by key is deliberately left open until there is a
--- preview to read them (`devdocs/building-export-import.md`).
---
--- **Nothing is validated.** A broken action exports exactly as it sits. The receiving side shows
--- it in red and the user deletes it, and that one rule is what removes a whole class of
--- questions about spells the reader does not have. Where the red text cannot in fact see the
--- breakage, the format carries the answer instead -- see `SnapshotMacro` and `NormalizeAction`.
function DebindShare.BuildExportPayload(selection, options)
    local renameKey = (options and options.stripKeys) and KeyRenamer() or nil;

    local payload = {
        v = SCHEMA_VERSION,
        -- The sender's class, because `shared.classes` cannot be read without knowing whose it is.
        -- Nothing else about the sender travels: a string meant to be pasted into a public channel
        -- should not carry a character name the user did not choose to type.
        class = Constants.PLAYER_CLASS,
    };
    local exported = {};

    for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
        -- Made on the first action that is actually taken, so an empty layer -- or one the reader
        -- unticked whole -- leaves no empty table behind for the far side to walk.
        local bucket;

        for _, action in layer:Enumerate() do
            if (selection == nil or selection[action]) then
                bucket = bucket or BucketForLayer(payload, layer);

                local copy = CopyFields(action, ACTION_FIELDS);
                NormalizeAction(action, copy);
                if (renameKey) then
                    copy.key = renameKey(action.key);
                end

                bucket[#bucket + 1] = copy;
                exported[#exported + 1] = copy;
            end
        end
    end

    payload.states = BuildStateManifest(exported);
    return payload;
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
--- the profile and does not produce actions. Deciding what to do with the result is `Import.lua`'s.
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
