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
---
--- **2 (2026-08-21): the conditions moved into `action.conditions`.** v1 carried their names at the
--- top of the action. Without the bump, a v1 string and every batch stacked in the drawer walk
--- through the gate as they are and `BuildAction`'s whitelist **drops every condition in silence**
--- -- they land as unconditional actions, stand where no conditional band belongs, and fire on a
--- key in states the writer had ruled out. It closes the other direction too: a 3.2 reader turns a
--- v2 away rather than shedding the fields it cannot read.
---
--- **The same version moves the manifest.** A switch definition's `mode` went from a number to a
--- string and `initialValue` became `resetValue`. The number is not split for it, because 2 has not
--- gone out -- the `dbver` 6 on the profile side sits in the same place for the same reason.
---
--- **And 2 carries a `dbver` alongside.** This one number was counting two things: the shape of the
--- envelope and the shape of an action. It went up when only the addressing moved and the actions
--- did not, and it would have to go up the other way round as well. The profile already versions
--- the action shape and calls that number `dbver`, so the payload carries the same one
--- (`devdocs/legacy/unifying-action-migration.md` §3-3) -- which is what lets the two ladders be
--- one.
---
--- **That rides on 2 as well.** v3.2 sent 1; 2 has not gone out. Splitting a number nothing is
--- holding makes a step for a version that never existed, and that step stays forever without ever
--- meeting a string.
---
--- So there are two versions, and what separates them is **whether the payload carries its own
--- `dbver`**. v1 does not: its version number is the answer, and the branch below stamps 5.
local SCHEMA_VERSION     = 2;

--- The lowest `dbver` a payload can carry.
---
--- **5 is the version sharing shipped on.** v1 came out of 3.2, whose `DB_VERSION` was 5, so no
--- string this addon ever made holds an action shape older than that.
---
--- **The floor is what lets `MigrateLayer` be called as it stands.** That ladder's steps at 4 and
--- below were written while only the profile came through them and take their fields to be the
--- type they should be. A hand-written `dbver = 1` reaching them raises, and a paste is not a place
--- that may raise.
local OLDEST_PAYLOAD_DBVER = 5;

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
--- added to an arrival number, `priority` is compared inside `table.sort`, `units` is walked
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
    units = "table",
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

--- Which fields of a switch definition describe the switch, as opposed to what it happens
--- to be doing right now. `value` is deliberately absent: `BindDerivedTables` recomputes it on
--- every login from `resetValue` and what the character remembers, so sending it would ship a
--- runtime reading as if it were a setting.
---
--- **The remembered value is not on this list and does not belong on it.** It lives on the
--- character now (`devdocs/redesigning-custom-states.md` §5), and it is one character's on or off
--- rather than a setting: the person reading the string is not that character. A v1 payload
--- carries a `savedValue` and nothing reads it.
---
--- **These names are the wire's, and 3.2 wrote the older ones.** A v1 payload carries a numeric
--- `mode` and `initialValue`, so the step that raises v1 renames them (`BringPayloadForward`).
local STATE_FIELDS       = {
    mode = true,
    resetValue = true,
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

--- **An action goes out in the shape it is stored in. Nothing here rewrites one.**
---
--- `NormalizeAction` stood in this spot and rewrote exactly one type. It cleared `SETSTATE`'s
--- bitpacked `value` and hung a `setstate = { mode, state }` subtable off the copy -- a field that
--- is not in `ACTION_FIELDS` and therefore outside the contract `check-export-fields.js` holds. The
--- same action existed in two shapes, in the profile and on the wire, and the migration for it was
--- about to exist in two copies for the same reason.
---
--- **§9-1 took the reason away.** With the stored form itself a `type` and a name, what goes on the
--- wire is not a bitpack any more, and both fields are ordinary whitelisted ones that `CopyFields`
--- passes through. The whole argument is `devdocs/legacy/unifying-action-migration.md`, sections 1
--- to 3.
---
--- The other types never needed anything here, and why still holds.
---
--- **`MACRO`** carries a name and only ever a name (`GetMissingMacroName` in `Misc.lua`), so what
--- is stored already means the same thing on the far side -- or means nothing, which is what
--- `BINDING_ISSUE_MISSING_MACRO` is for. **The body does not travel**: it is text the user wrote
--- freely, and the sender knows only that this action calls their macro named X, not that its
--- contents ride along (2026-08-18, `devdocs/building-export-import.md`). `MACROTEXT` is the
--- opposite case and travels whole -- that text was written inside this addon, to be this action.
---
--- **`SETCUSTOM` is not a switch despite the name.** It sets a custom *target* -- a unit slot, like
--- focus -- and its index is structural, meaning the same thing in every install.


-- ---------------------------------------------------------------------------------------------
-- Custom states referenced by what is being sent
-- ---------------------------------------------------------------------------------------------

--- Every custom state the exported actions name, by name.
---
--- Four places hold a reference (`devdocs/redesigning-custom-states.md` §3-4) and three of them are
--- reachable from an action: the condition fields on the action itself, an on/off/toggle action's
--- `value`, and names typed into macro text. The fourth is a state's own `expr` naming another
--- state, which is why this closes transitively rather than doing one pass.
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

        if (Constants.SETSTATE_MODES[action.type] and luatype(action.value) == "string") then
            found[action.value] = true;
        end

        if (action.type == Constants.MACROTEXT and luatype(action.value) == "string") then
            local _, args = DebindPrivate.ParseMacroText(action.value);
            if (args) then
                for j = 1, #args do
                    local arg = args[j];
                    if (arg.type == Constants.MACROTEXT_ARG_SWITCH) then
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
                local definition = DebindPrivate.ResolveSwitchDefinition(name);
                if (definition) then
                    manifest[name] = CopyFields(definition, STATE_FIELDS);
                    any = true;

                    -- A conditional state's expression can name other states, and those have to
                    -- travel too or the definition arrives referring to nothing.
                    if (definition.mode == Constants.SWITCH_MODES.EXPR
                            and luatype(definition.expr) == "string") then
                        local _, args = DebindPrivate.ParseMacroText(definition.expr);
                        for j = 1, (args and #args or 0) do
                            local arg = args[j];
                            if (arg.type == Constants.MACROTEXT_ARG_SWITCH
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
--- **Nothing is validated, and nothing is rewritten.** A broken action exports exactly as it sits.
--- The receiving side shows it in red and the user deletes it, and that one rule is what removes a
--- whole class of questions about spells the reader does not have. The one standing exception was
--- `SETSTATE`, whose stored index would have arrived **unbroken and wrong** where red text cannot
--- see it; §9-1 made the stored form a name, so there is nothing left to rewrite.
function DebindStorage.BuildExportPayload(selection)

    local payload = {
        v = SCHEMA_VERSION,
        -- **The shape of the actions below, which is not the same question as `v`.** The profile is
        -- already at `Constants.DB_VERSION` by the time anything can be exported -- `MigrateDB` runs
        -- at login -- so this says what these actions are, and the reading side raises them with the
        -- same ladder the profile uses (`BringPayloadForward`).
        dbver = Constants.DB_VERSION,
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

--- `dbver` 6, the manifest side. A switch definition's `mode` goes from a number to a string and
--- `initialValue` becomes `resetValue` -- the same transformation `MigrateSwitches` makes in
--- `Profile.lua`, which is why it hangs off `dbver` rather than off the envelope: a definition is
--- profile data and `dbver` is what versions that. Every payload it actually meets is a v1 one, as
--- v2 can only have come from a profile already at 6.
---
--- **It cannot share the profile's function.** `MigrateSwitches` takes the whole account table,
--- because the rest of what it does at this step is hand remembered values out to the characters
--- and throw away the definitions nothing names. A manifest has no characters, no layers to be
--- named by, and nothing to prune. What is left over is the rename, and that is written here.
---
--- **Written before anything reads a manifest at all.** 3.2 sent this table, so v1 strings sit in
--- other people's notes in the old shape, and by the day something reads one this step is long
--- frozen. Adding it then would mean a later step correcting a field whose meaning moved here --
--- a ladder that lies about which version changed what.
---
--- The step holds its own literals, for the reason the SETSTATE step in `Profile.lua` does.
local function RenameManifestSwitchFields(states)
    if (luatype(states) ~= "table") then
        return;
    end
    for _, definition in pairs(states) do
        if (luatype(definition) == "table") then
            if (luatype(definition.mode) == "number") then
                if (definition.mode == 3) then
                    definition.mode = Constants.SWITCH_MODES.EXPR;
                else
                    definition.mode = Constants.SWITCH_MODES.MANUAL;
                end
            end
            if (definition.initialValue ~= nil) then
                if (definition.resetValue == nil) then
                    definition.resetValue = definition.initialValue;
                end
                definition.initialValue = nil;
            end
        end
    end
end

--- v1 -> v2, the action side. The wire spelled a `SETSTATE` as a `setstate = { mode, state }`
--- subtable with no `value`; it is opened out into the `type` and the name the profile stores
--- (`devdocs/legacy/unifying-action-migration.md` §3-2).
---
--- **This adapter is permanent.** The door to dropping v1 shut when 3.2 shipped: those strings are
--- in other people's hands and the reading side has to be able to read them. It can stay because
--- there is so little of it -- the ladder does not get longer, one short rung stands at the bottom
--- of it for good, and it is the same rung however many format changes come after.
---
--- **It does not go through the bitpack**, even though `dbver` 5 is what the payload is then
--- stamped as. The wire already holds both halves the new shape needs -- a verb in `mode` and a name in
--- `state` -- so three strings become three types and that is the whole of it. Packing them into a
--- number for the very next step to unpack is work that cancels itself, which is why the old mode
--- flags are nowhere in here (2026-08-21, owner's decision).
---
--- **The ladder is still one ladder.** The shared step keys on the old single type `"setstate"`,
--- so an action that arrives already carrying `setstate_toggle` walks past it. That is not a
--- special case, it is the idempotence that block is written to have anyway.
---
--- **Asked whether it is a table, not whether it is there.** A hand-made `setstate = 5` would raise
--- here and take down a commit with half a batch already placed. A mode or a name this build cannot
--- read leaves the action under the old type, which is a type nothing knows -- `IsUsableAction`
--- turns it down and the whole string with it, and that is the right end for a `SETSTATE` with
--- nothing to set.
local V1_SETSTATE_TYPES = {
    on     = Constants.SETSTATE_ON,
    off    = Constants.SETSTATE_OFF,
    toggle = Constants.SETSTATE_TOGGLE,
};

local function OpenV1Setstate(payload)
    DebindStorage.ForEachPayloadLayer(payload, function(actions)
        for i = 1, #actions do
            local action = actions[i];
            if (luatype(action.setstate) == "table") then
                local newType = V1_SETSTATE_TYPES[action.setstate.mode];
                local name = action.setstate.state;
                if (newType and luatype(name) == "string") then
                    action.type = newType;
                    action.value = name;
                end
                action.setstate = nil;
            end
        end
    end);
end

--- Raises a payload's **contents** to this build's `dbver`, action arrays and manifest alike.
---
--- **The actions go up the profile's own ladder.** `MigrateLayer` walks an array of actions and
--- touches nothing above one, and a payload's layer is an array of actions, so it goes across as it
--- is. Writing the same transformation twice is what this replaces: condition nesting stood here in
--- full, in a second copy of the `dbver <= 5` step
--- (`devdocs/legacy/unifying-action-migration.md` §3-4).
---
--- **What is walked is still each side's own.** Layer addresses and key mapping are different
--- things in a profile and in a payload; only the per-action ladder is shared.
local function BringPayloadDataForward(payload)
    local dbver = payload.dbver;

    if (dbver <= 5) then
        RenameManifestSwitchFields(payload.states);
    end

    DebindStorage.ForEachPayloadLayer(payload, function(actions)
        DebindPrivate.MigrateLayer(actions, dbver);
    end);

    payload.dbver = Constants.DB_VERSION;
end

--- Raises a payload to what this version reads, or says why it cannot. Returns the payload, or nil
--- plus a reason.
---
--- **Two ladders, and they are asked in this order.** `payload.v` describes the envelope -- the
--- `shared` / `classes` / `char` addresses, the `states` manifest, what `seq` means -- and
--- `payload.dbver` describes the actions inside it. The envelope has to be raised first, because
--- v1 does not carry a `dbver` and the step that raises it is what stamps one on
--- (`devdocs/legacy/unifying-action-migration.md` §3-3).
---
--- **An envelope step names the exact version it raises (`== 1`), not `<=`.** A payload two
--- versions back then walks every step in turn, and a number nothing ever wrote falls through to
--- the refusal instead of being guessed at. The `dbver` ladder is the opposite and opens with
--- `<=`, because that one is the profile's and every version between the ends of it is real.
---
--- **Both doors ask this, and that is the point of it being a function.** A string is asked at the
--- moment it is pasted (`DecodeExportString`, below) and a stored batch is asked when the drawer
--- opens it (`GetBatchPayload` in `Import.lua`). The drawer used to ask nothing: it kept the
--- payload it was handed and gave it straight back. That is invisible while there is one schema
--- and it stops being invisible the day one is added, because the batches already sitting in the
--- drawer are exactly the ones that would go into the new code unasked.
---
--- **Two directions, and opposite advice.** These were one reason and one sentence, "made by a
--- newer version, update and try again", which is true one way and useless the other: on the first
--- schema bump every batch already received would fail with it, told to update by the version they
--- just updated to.
---
--- `SCHEMA_TOO_OLD` is the answer for a version **no step covers**, on either ladder. A bump
--- means a field changed meaning (`SCHEMA_VERSION`'s own note), so such a payload cannot be read
--- by guessing, and guessing is how a condition silently changes sides.
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
    if (payload.v == 1) then
        OpenV1Setstate(payload);
        -- **The version number is the answer.** v1 came out of 3.2 and 3.2 stored `dbver` 5, so
        -- these actions are that shape whatever the payload says -- a hand-written `dbver` on a
        -- v1 string is overwritten rather than believed. Conditions are still flat at this point
        -- and the shared `dbver <= 5` step is what nests them.
        payload.dbver = OLDEST_PAYLOAD_DBVER;
        payload.v = 2;
    end

    if (payload.v < SCHEMA_VERSION) then
        return nil, "SCHEMA_TOO_OLD";
    end

    -- **NaN passes every comparison below**, and a payload claiming it would walk through the range
    -- check and reach `MigrateLayer` with a version no step can match. It is asked about the same
    -- way a NaN key is (`PayloadIsImpossible`).
    local dbver = payload.dbver;
    if (luatype(dbver) ~= "number" or dbver ~= dbver) then
        return nil, "BAD_PAYLOAD";
    end
    if (dbver > Constants.DB_VERSION) then
        return nil, "UNSUPPORTED_SCHEMA";
    end
    if (dbver < OLDEST_PAYLOAD_DBVER) then
        return nil, "SCHEMA_TOO_OLD";
    end

    BringPayloadDataForward(payload);

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
