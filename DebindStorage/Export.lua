local _, DebindStorage = ...;

local DebindPrivate      = DebindStorage.DebindPrivate;
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
--- **The rule is live from 3.2, the release that carries sharing.** Before it this stayed 1 through
--- two shape changes on purpose (`layer` moved from the group down to the action, and the group
--- layer went): nothing had left the repository, so a number spent on a shape nobody was holding
--- was a number wasted. **That window is shut.** A string made by 3.2 sits in somebody's notes and
--- somebody's guide, so a bump from here is a bump under readers holding one written by 1.
---
--- **Which is why a bump owes v1 a way forward rather than a refusal** (2026-08-19, owner's
--- decision; `devdocs/building-export-import.md`). `BringPayloadForward` is where that step goes,
--- and both doors into a payload run it.
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
--- on, and a batch exists only on **the receiving side**. It is the one field that means nothing
--- anywhere else.
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
--- **The value is the type the field may arrive as**, `|`-separated where more than one is real.
--- The export only ever reads this as a set, but the import reads the type: a whitelist of names
--- is not a whitelist of values, and every one of these reaches code that computes on it. `seq` is
--- added to an arrival number, `priority` is compared inside `table.sort`, `checkedUnits` is walked
--- with `pairs`, the masks go through `band`. A pasted string carrying `seq = {}` raised **inside**
--- `PlaceImportedActions`, leaving the actions before it in the profile and skipping the renumber
--- that follows - so the survivors kept the internal arrival band, which `CleanUpDB` does not clamp
--- and a logout therefore writes to disk.
---
--- Kept to one line each. `tools/check-export-fields.js` reads this table by matching `name =` per
--- line, so a value spread over several lines would have its inner keys read as field names.
local ACTION_FIELDS      = {
    type = "string",
    -- A spell or item id, or a macro name, or a macro body.
    value = "number|string",
    -- A binding string, or the number a key group the sender never bound travels under.
    key = "string|number",
    seq = "number",
    name = "string",
    -- A file id, or a path for the ones that still carry one.
    icon = "number|string",
    unit = "string",
    priority = "number",
    keepInBindingContext = "boolean",
    ignoreHoverUnit = "boolean",
    -- **Every condition rides inside this one.** The names and their types are `CONDITION_TYPES`
    -- below, and `check:export-fields` holds that list against `Profile.lua`'s.
    conditions = "table",
};

--- What may sit inside `conditions`, by name and type. **The wire is untrusted**, so the
--- receiving side filters one level deeper than it used to (`Import.lua`'s `FieldAllowed`).
---
--- `known` is asked-or-not-asked, which is `true` or absent -- not the third value the booleans
--- around it have, because the condition is about the action's own spell and a `false` would say
--- "cast it only while it is unlearned". The type stays `boolean` because this list filters by
--- name and type and has no way to say which of the two, and a sender on some other build can put
--- a `false` on the wire; `GetBindingInfoForAction` is where it dies.
---
--- **A `$`-prefixed name passes unlisted, as a boolean.** Custom state conditions are stored
--- under their own name and the redesign turns the five slots into arbitrary ones
--- (`devdocs/redesigning-custom-states.md`); listing five and stopping there would drop every
--- named state the day it lands.
local CONDITION_TYPES    = {
    -- Bit masks.
    frameTypes = "number",
    groups = "number",
    forms = "number",
    bonusbars = "number",
    known = "boolean",
    combat = "boolean",
    stealth = "boolean",
    specialbar = "boolean",
    extrabar = "boolean",
    pet = "boolean",
    petbattle = "boolean",
    checkedUnits = "table",
    ["$state1"] = "boolean",
    ["$state2"] = "boolean",
    ["$state3"] = "boolean",
    ["$state4"] = "boolean",
    ["$state5"] = "boolean",
};

--- Read by `Import.lua`, which filters the incoming table through the **same** list. One side a
--- whitelist and the other a blacklist is what let a wire field nobody named ride into the profile.
DebindStorage.ACTION_FIELDS = ACTION_FIELDS;
DebindStorage.CONDITION_TYPES = CONDITION_TYPES;

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
        -- The `$` escape that used to sit here is one level down now, in `CONDITION_TYPES`.
        -- Custom state conditions are stored under their own name, and those names live inside
        -- `conditions` -- nothing at the top of an action starts with `$` any more, so an escape
        -- here would only let through whatever else happened to.
        if (allowed[k]) then
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

--- Rewrites the parts of an action whose stored form is an **index into the sender's setup**.
---
--- `SETSTATE` packs mode and state index into one number (`SETCUSTOM_MODE_*` over the low
--- nibble). An index always resolves on the far side, and resolves to the wrong state, which
--- puts it outside what red text can see.
---
--- So it goes out on the **name** axis instead: `$state3` rather than 3. `$state1..5` stay valid
--- names after the custom-state rename (`devdocs/redesigning-custom-states.md` step 1), so this shape
--- survives that change without a schema bump, and it commits nothing about how the profile
--- stores the value -- that decision is still §9-1's to make.
---
--- **`MACRO` needs nothing here, and that is a property of the action rather than of the format.**
--- A macro reference is a name and only ever a name (`GetMissingMacroName` in `Misc.lua` is where
--- that rule is written down), so what is stored is already the shape that means the same thing on
--- the far side -- or means nothing, which is what `BINDING_ISSUE_MISSING_MACRO` is for.
---
--- **The body does not travel, and it is not an omission** (2026-08-18,
--- `devdocs/building-export-import.md`). It is text the user wrote freely, we do not know what is
--- in it, and the sender knows only that this action calls their macro named X -- not that its
--- contents ride along. `MACROTEXT` is the opposite case and is untouched: that text was written
--- inside this addon, to be this action.
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
    end
end


-- ---------------------------------------------------------------------------------------------
-- Custom states referenced by what is being sent
-- ---------------------------------------------------------------------------------------------

--- Every custom state the exported actions name, by name.
---
--- Four places hold a reference (`devdocs/redesigning-custom-states.md` §3-4) and three of them are
--- reachable from an action: the condition fields on the action itself, a `SETSTATE` value, and
--- names typed into macro text. The fourth is a state's own `expr` naming another state, which
--- is why this closes transitively rather than doing one pass.
local function CollectStateNames(actions, found)
    for i = 1, #actions do
        local action = actions[i];

        -- 조건 표 안이다. 액션 최상단을 훑던 자리인데, `dbver <= 5`가 조건을 한 겹
        -- 내리면서 거기엔 `$` 이름이 하나도 안 남는다.
        if (action.conditions) then
            for k in pairs(action.conditions) do
                if (strsub(k, 1, 1) == "$") then
                    found[k] = true;
                end
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
-- What can be sent at all
-- ---------------------------------------------------------------------------------------------

--- Is this action the sender's to send?
---
--- **A badged action is not.** What an export claims is "this is my setup", and something received
--- and not yet decided on is someone else's, sitting quarantined and doing nothing. Passing it on
--- would spread an undecided thing from person to person: it lands badged on the far side too, and
--- that reader has no more to go on than this one did.
---
--- **The window asks the same question about its own list** (`BuildLayers` in `ExportUI.lua`). Every
--- number that window prints comes out of that list -- the layer headers, the [select all] total,
--- which rows can be ticked -- so the two answering differently is the window saying "12" and
--- sending 9. One function, asked twice, is what makes them the same answer rather than the same
--- idea written down twice.
---
--- **A synthetic key is not this.** No badge means the set is the sender's, and "a key group I have
--- not given a key to" is a fact about their setup worth carrying.
function DebindStorage.IsExportable(action)
    return action.imported == nil;
end



-- ---------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------

DebindStorage.EXPORT_SCHEMA_VERSION = SCHEMA_VERSION;

--- The table that becomes the string.
---
--- `selection` is a set of the action tables to send, or nil for everything stored. The export
--- window checks actions, so a set of actions is what it has; layers are walked here rather than
--- asked for, which is what puts the payload in storage shape and leaves the window a filter.
---
--- **`IsExportable` is asked before the selection is**, so a badged action does not go out even if
--- it is ticked. The window drops those from its own list, but it outlives the window that takes
--- badges off - a badge can come off, or land, while this one stands open holding a stale set.
--- A key can therefore go out half, and that is right: the badged one is not part of the setting yet.
---
--- **The sender's keys go out as they are.** There used to be an option to replace them with
--- synthetic ones, and nothing was left for it to do: the receiving side renames every arriving key
--- anyway, so ticking it only withheld which key the sender had it on. Somebody who hands their
--- setup to another player is showing it off, and the keys are the part worth showing -- they are
--- not a name, a realm, or anything else a string pasted into a public channel should not carry.
---
--- A number still travels: that is a key group the sender has not given a key to, which is a fact
--- about their setup rather than something withheld.
---
--- **Emitted in storage order, one layer at a time.** Which of a key's actions goes first travels as
--- `seq`, so the array is not carrying that and does not have to be sorted to say it; and storage
--- order is stable for a profile nobody has edited, which is what re-exporting has to be able to
--- show. Whether a layer's actions are clumped by key is deliberately left open until there is a
--- preview to read them (`devdocs/building-export-import.md`).
---
--- **Nothing is validated.** A broken action exports exactly as it sits. The receiving side shows
--- it in red and the user deletes it, and that one rule is what removes a whole class of
--- questions about spells the reader does not have. What `NormalizeAction` rewrites is not an
--- exception to it: a state index is a reference that would arrive **unbroken and wrong**, which
--- red text cannot see at all.
function DebindStorage.BuildExportPayload(selection)

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
            if (DebindStorage.IsExportable(action) and (selection == nil or selection[action])) then
                bucket = bucket or BucketForLayer(payload, layer);

                local copy = CopyFields(action, ACTION_FIELDS);
                NormalizeAction(action, copy);

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
function DebindStorage.EncodeExportPayload(payload)
    local LibSerialize, LibDeflate = GetLibs();
    if (not LibSerialize or not LibDeflate) then
        return nil, "LIBS_MISSING";
    end

    local compressed = LibDeflate:CompressDeflate(LibSerialize:Serialize(payload), { level = 9 });
    return ENVELOPE_PREFIX .. ENVELOPE_VERSION .. ENVELOPE_SEPARATOR
        .. LibDeflate:EncodeForPrint(compressed);
end

--- Raises a payload to the schema this version reads, or says why it cannot. Returns the payload,
--- or nil plus a reason.
---
--- **There are no steps yet and this is where the first one goes.** `SCHEMA_VERSION` is 1 and
--- nothing has ever written a 0, so today the whole function is the two refusals below. The shape
--- is the one `MigrateLayer` has in `Profile.lua`: a step per version, opened with `<=` so a
--- payload two versions back walks through all of them.
---
--- **Both doors ask this, and that is the point of it being a function.** A string is asked at the
--- moment it is pasted (`DecodeExportString`, below) and a stored batch is asked when the drawer
--- opens it (`GetBatchPayload` in `Import.lua`). The drawer used to ask nothing: it kept the
--- payload it was handed and gave it straight back. That is invisible while there is one schema
--- and it stops being invisible the day one is added, because the batches already sitting in the
--- drawer are exactly the ones that would go into the new code unasked. Whoever writes the first
--- migration writes it here and both doors have it.
---
--- **Two directions, and opposite advice.** These were one reason and one sentence, "made by a
--- newer version, update and try again", which is true one way and useless the other: on the first
--- schema bump every batch already received would fail with it, told to update by the version they
--- just updated to.
---
--- Both are refusals **until a step is written**. A bump means a field changed meaning
--- (`SCHEMA_VERSION`'s own note), so an old payload cannot be read by guessing, and guessing is how
--- a condition silently changes sides.
---
--- **"Is it a payload at all" is asked here and nowhere else.** Both doors hand over something they
--- did not make: one has just deserialized bytes somebody else wrote, the other has read a table
--- out of SavedVariables. Neither may error, and the answer is the same refusal, so asking twice
--- would be the same question in two places. It caught a real one: a batch with no payload draws in
--- the drawer perfectly well, because the two that draw the row guard it (`CountBatch`,
--- `BatchClassText`), and then threw the moment the row was opened.
function DebindStorage.BringPayloadForward(payload)
    if (luatype(payload) ~= "table") then
        return nil, "BAD_PAYLOAD";
    end
    if (luatype(payload.v) ~= "number" or payload.v > SCHEMA_VERSION) then
        return nil, "UNSUPPORTED_SCHEMA";
    end
    if (payload.v < SCHEMA_VERSION) then
        return nil, "SCHEMA_TOO_OLD";
    end

    return payload;
end

--- The inverse, and **only** the inverse. It answers "what was in the string"; it does not touch
--- the profile and does not produce actions. Deciding what to do with the result is `Import.lua`'s.
---
--- Returns nil plus a reason for anything malformed. A pasted string is user input from an
--- untrusted place, so every step here is allowed to fail and none of them may error.
function DebindStorage.DecodeExportString(str)
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
    if (not ok) then
        return nil, "BAD_PAYLOAD";
    end

    -- Whether what came back is a table at all is asked below, with the same answer, on the door a
    -- stored batch uses too.
    return DebindStorage.BringPayloadForward(payload);
end

--- What the window calls: selection in, string out.
function DebindStorage.ExportSelection(selection)
    return DebindStorage.EncodeExportPayload(DebindStorage.BuildExportPayload(selection));
end
