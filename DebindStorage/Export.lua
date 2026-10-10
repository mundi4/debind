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
--- Design notes and the open questions this file does **not** answer: `building-export-import.md`.


--- The version of `payload` itself, carried as `payload.v`. Bump when a field changes meaning, not when one is added -- a reader
--- that skips fields it does not know survives additions on its own.
---
--- **The rule is live from 3.2, the release that carries sharing.** Before it this stayed 1 through
--- two shape changes on purpose (`layer` moved from the group down to the action, and the group
--- layer went): nothing had left the repository, so a number spent on a shape nobody was holding
--- was a number wasted. **That window is shut.** A string made by 3.2 sits in somebody's notes and
--- somebody's guide, so a bump from here is a bump under readers holding one written by 1.
---
--- **Which is why a bump owes v1 a way forward rather than a refusal** (2026-08-19, owner's
--- decision; `building-export-import.md`). `BringPayloadForward` is where that step goes,
--- and both doors into a payload run it.
---
--- **2 (2026-08-21): the conditions moved into `action.conditions`.** v1 carried their names at the
--- top of the action. Without the bump, a v1 string and every entry stacked in the drawer walk
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
--- payload around the actions and the shape of an action. It went up when only the addressing moved and the actions
--- did not, and it would have to go up the other way round as well. The profile already versions
--- the action shape and calls that number `dbver`, so the payload carries the same one
--- (`unifying-action-migration.md` §3-3) -- which is what lets the two ladders be
--- one.
---
--- **That rides on 2 as well.** v3.2 sent 1, and 2 had not gone out when this was decided.
--- Splitting a number nothing was holding would have made a step for a version that never existed,
--- and that step stays forever without ever meeting a string.
---
--- **3.4 added three condition names and one action type, and did not bump (2026-08-27, owner).**
--- The case for bumping was that a 3.3 reader drops an unknown condition in silence, which is the
--- failure the v1 to v2 bump was cut for. What that missed is that this number has no granularity.
--- A 3.3 reader already turns away a code carrying `equipslot` on its own, because an unknown
--- action type refuses the whole string. So the bump would buy only the codes that use a new
--- condition and no equipment slot, and it would cost every code that uses neither, which is most
--- of them. And 2 is out in the field now, unlike when v1 was raised, so a bump is no longer free.
--- `0-DECISION-LOG.md` 2026-08-27.
---
--- So there are two versions, and what separates them is **whether the payload carries its own
--- `dbver`**. v1 does not: its version number is the answer, and the branch below stamps 5.
---
--- **3 (2026-09-27) carries the saved shape**: `layers[owner][class][spec]`, `switches` in the same
--- cells, and `characters` for who a character cell is (`reshaping-stored-layers.md` 1-1). v2's
--- character layer named no class of its own and leaned on `payload.class`, so a mage's character
--- layer went into a druid's spec of the same number; every cell carries its class as a key now.
local PAYLOAD_VERSION    = 3;

--- The lowest `dbver` a payload can carry.
---
--- **5 is the version sharing shipped on.** v1 came out of 3.2, whose `DB_VERSION` was 5, so no
--- string this addon ever made holds an action shape older than that.
---
--- **A lower one is refused rather than carried up the steps below 5.** A string carrying one
--- was written by a hand, and no string this addon made needs those steps.
local OLDEST_PAYLOAD_DBVER = 5;

--- How the bytes are packed, which is a **separate** number from `PAYLOAD_VERSION` on purpose. Swapping
--- the compressor later has to invalidate old strings; adding a payload field must not. One
--- number for both would force every reader to treat those two as the same event.
---
--- **2 is the client's own packing** (`C_EncodingUtil`: CBOR, deflate, base64). CBOR and not the
--- client's JSON, which turns every table key into a string and so the spec cells `[0]`..`[5]` into
--- `"0"`..`"5"`. Both clients were measured handing every key back with its type
--- (`reshaping-stored-layers.md` 1-2).
local ENVELOPE_VERSION   = 2;
--- 1 was LibSerialize and LibDeflate. **It is still read** until the two libraries leave the addon,
--- and then it cannot be (`reshaping-stored-layers.md` 1-2).
local ENVELOPE_LIBS      = 1;
local ENVELOPE_PREFIX    = "DEB";
local ENVELOPE_SEPARATOR = ":";

--- Action fields that go out on the wire: **every field the profile saves** (`KEYS_TO_SAVE`), with the
--- same types, **but `arrivalID`, and with `untranslated`**.
---
---   * `arrivalID` counts the arrivals **this store** has taken in, and that count exists nowhere
---     else. It is the one saved field that means nothing on another machine.
---   * `untranslated` is what another addon stored that cannot be translated until the payload is
---     added, kept as that addon wrote it (`importing-clique-profiles.md` §2). `Build` drops it, so it
---     is never saved.
---
--- **Read off the saved list rather than restated.** Restated, a field saved and never exported was
--- caught only by a check of the names, and nothing compared the types.
---
--- A few of them travel for a reason worth keeping:
---   * `key` and `seq`. A key **is** the group, so there is nothing above the action to hold it, and
---     `PlaceArrivedActions` turns the sender's `seq` into a place in the receiving group
---     (`building-export-import.md`).
---   * `disabled`. **An action the sender had turned off arrives turned off.** Dropping it would hand
---     the reader a running action the sender had stopped.
---   * `resolvedSpellID`. A reader in another locale cannot resolve the spell's name at all.
---   * `formerly`. A row the sender's load could not read arrives saying what it was. **A build from
---     before `INVALID` refuses a string carrying one**: nothing is promised to an older build.
local ACTION_FIELDS      = {};
for name, kind in pairs(DebindPrivate.KEYS_TO_SAVE) do
    if (name ~= "arrivalID") then
        ACTION_FIELDS[name] = kind;
    end
end
ACTION_FIELDS.untranslated = "table";

--- What may sit inside `conditions` and `casting`, by name and type: **Debind's own tables**, the ones
--- `SanitizeAction` reads at load. Kept apart they were two lists, and a condition named in one
--- only was dropped on the way out or on the way in with nothing said.
local CONDITION_TYPES    = Constants.CONDITION_FIELDS;
local CASTING_TYPES      = Constants.CASTING_FIELDS;

--- For the headless specs, which hold their fixtures to the same lists (`tests/canonical.lua`).
DebindStorage.ACTION_FIELDS = ACTION_FIELDS;
DebindStorage.CONDITION_TYPES = CONDITION_TYPES;
DebindStorage.CASTING_TYPES = CASTING_TYPES;

--- Which fields of a switch definition describe the switch, as opposed to what it happens
--- to be doing right now. The value in effect is not stored at all (`GetSwitchValue`), and a v1
--- payload's `value` is a runtime reading nothing takes as a setting.
---
--- **The remembered value is not on this list and does not belong on it.** It lives on the
--- character now (`redesigning-custom-states.md` §5), and it is one character's on or off
--- rather than a setting: the person reading the string is not that character. A v1 payload
--- carries a `savedValue` and nothing reads it.
---
--- An override row has the same three fields, so this list copies both.
---
--- ⚠ **Nothing checks this table.** `check:export-fields` compares the options and never looks
--- here, so a definition field added without a line here simply does not go out - no error on
--- either side and no check to catch it.
---
--- **These names are the wire's, and 3.2 wrote the older ones.** A v1 payload carries a numeric
--- `mode` and `initialValue`, so the step that raises v1 renames them (`BringPayloadForward`).
local SWITCH_FIELDS      = {
    mode = true,
    resetValue = true,
    expr = true,
};

--- What `characters` says about a character cell: who it is, for a reader who has to pick where
--- it goes. `firstSeen` and `lastSeen` stay home: they are this install's record of
--- seeing the character and mean nothing on another one.
local IDENTITY_FIELDS    = {
    name = true,
    realm = true,
    class = true,
    race = true,
    sex = true,
    level = true,
    faction = true,
};

--- The settings tab's options, by name and the type each is stored as. **Only an entry made from
--- the whole account carries them** (`BuildAccountPayload`): most of these change what an action
--- does, so a backup without them is not the setup it was taken from, while a reader adding someone
--- else's actions keeps their own.
---
--- **Not part of the account backup**: `DebindUIVars` (window positions, filters, `tipsSeen`), and
--- the remembered switch values and `CustomTargets`, which are one character's state rather than a
--- setting (`reshaping-stored-layers.md` 1-1).
---
--- **What sits inside the two tables is not filtered**: `excludePlayer` is read by unit name and
--- `frameBlacklist` by frame type or addon folder, so a name nothing knows is never asked for.
---
--- `check:export-fields` holds this list against what the settings tab's Defaults resets.
local OPTION_FIELDS      = {
    selfCast = "boolean",
    focusCast = "boolean",
    hoverCastMode = "string",
    switchMessages = "boolean",
    excludePlayer = "table",
    unitframeUseMouseDown = "boolean",
    giveBackOnReplacedBar = "boolean",
    giveBackInPetBattle = "boolean",
    giveBackInBindingContext = "boolean",
    giveBackWhenNoActionRuns = "boolean",
    frameBlacklist = "table",
};
DebindStorage.OPTION_FIELDS = OPTION_FIELDS;

--- The owner key of the account's cells, beside one per character.
local ACCOUNT_OWNER      = "account";
DebindStorage.ACCOUNT_OWNER = ACCOUNT_OWNER;


-- ---------------------------------------------------------------------------------------------
-- Copying out
-- ---------------------------------------------------------------------------------------------

--- A field-by-field copy, tables included. Copying by reference here would put live profile
--- tables inside the payload, and `LibSerialize` would happily write them out -- but anything
--- that edited the payload afterwards (stripping keys, renaming a switch) would be editing the
--- user's profile.
local function CopyFields(source, allowed)
    local copy = {};
    for k, v in pairs(source) do
        -- The `$` escape that used to sit here is one level down now, in `CONDITION_TYPES`.
        -- Switch conditions are stored under their own name, and those names live inside
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

--- `tbl[owner][class][spec]`, built on the way down. `tbl` is `payload.layers` or
--- `payload.switches`, which share their cells.
---
--- **The path is the address, and it is the one the profile stores under**
--- (`layers[owner][class][spec]`), so nothing describes a layer and nothing translates one. Layer
--- **IDs** are what cannot travel: 2..6 are "my class", and the sender's class is not the reader's.
local function CellAt(tbl, owner, class, spec)
    local classes = tbl[owner];
    if (not classes) then
        classes = {};
        tbl[owner] = classes;
    end
    local specTbl = classes[class];
    if (not specTbl) then
        specTbl = {};
        classes[class] = specTbl;
    end
    local cell = specTbl[spec];
    if (not cell) then
        cell = {};
        specTbl[spec] = cell;
    end
    return cell;
end

--- The cell one of this character's layers sits at: `owner, class, spec`.
local function LayerCell(layer)
    if (layer.isCharacterSpecific) then
        return DebindPrivate.playerGUID, Constants.PLAYER_CLASS, layer.spec or 0;
    end
    if (layer.layerID == 1) then
        return ACCOUNT_OWNER, "GENERAL", 0;
    end
    return ACCOUNT_OWNER, Constants.PLAYER_CLASS, layer.spec or 0;
end

--- The character keys a payload names, in `layers` or in `switches`, as a set.
local function CharacterOwners(payload)
    local out = {};
    for _, tbl in ipairs({ payload.layers, payload.switches }) do
        if (luatype(tbl) == "table") then
            for owner in pairs(tbl) do
                if (owner ~= ACCOUNT_OWNER) then
                    out[owner] = true;
                end
            end
        end
    end
    return out;
end

--- **An action goes out in the shape it is stored in. Nothing here rewrites one.**
---
--- `NormalizeAction` stood in this spot and rewrote exactly one type. It cleared `setstate`'s
--- bitpacked `value` and hung a `setstate = { mode, state }` subtable off the copy -- a field that
--- is not in `ACTION_FIELDS`, so no list the export and the import share named it. The
--- same action existed in two shapes, in the profile and on the wire, and the migration for it was
--- about to exist in two copies for the same reason.
---
--- **§9-1 took the reason away.** With the stored form itself a `type` and a name, what goes on the
--- wire is not a bitpack any more, and both fields are ordinary whitelisted ones that `CopyFields`
--- passes through. The whole argument is `unifying-action-migration.md`, sections 1
--- to 3.
---
--- The other types never needed anything here, and why still holds.
---
--- **`MACRO`** carries a name and only ever a name (`GetMissingMacroName` in `Issues.lua`), so what
--- is stored already means the same thing on the far side -- or means nothing, which is what
--- `BINDING_ISSUE_MISSING_MACRO` is for. **The body does not travel**: it is text the user wrote
--- freely, and the sender knows only that this action calls their macro named X, not that its
--- contents ride along (2026-08-18, `building-export-import.md`). `MACROTEXT` is the
--- opposite case and travels whole -- that text was written inside this addon, to be this action.
---
--- **`SETCUSTOM` is not a switch despite the name.** It sets a custom *target* -- a unit slot, like
--- focus -- and its index is structural, meaning the same thing in every install.


-- ---------------------------------------------------------------------------------------------
-- Switches referenced by what is being sent
-- ---------------------------------------------------------------------------------------------

--- Every switch the exported actions name, by name.
---
--- Four places hold a reference (`redesigning-custom-states.md` §3-4) and three of them are
--- reachable from an action: the condition fields on the action itself, an on/off/toggle action's
--- `value`, and names typed into macro text. The fourth is a switch's own `expr` naming another
--- switch; this does not follow it, `BuildSwitchCells` closes over it.
local function CollectSwitchNames(actions, found)
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

        if (Constants.SETSWITCH_MODES[action.type] and luatype(action.value) == "string") then
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

--- `payload.switches`: every referenced switch, keyed by name, in the cells it has rows in. The
--- definition is the row at `account.GENERAL[0]`, and a layer's override is the row at that layer's
--- own cell.
---
--- Names, not indices, because the receiving side has to be able to *ask* about a collision, and
--- `$state3` on two machines is two different switches that an index can never tell apart. A name
--- nothing defines is also the one broken switch reference the issue mark already catches
--- (`BINDING_ISSUE_UNDEFINED_SWITCH`), so the reader is not left guessing.
---
--- A referenced switch with no rows is left out rather than sent empty. The sender has nothing to
--- say about it, and an empty definition would read as "defined, and blank".
---
--- **Where the rows come from is the caller's to say.** `RowsOf(name)` hands back a list of
--- `{ owner, class, spec, row }`. Building a payload out of the profile asks the profile; narrowing
--- a payload that is already made asks that payload's own cells (`FilterPayload`), and must not ask
--- the profile -- an entry that arrived in a string carries somebody else's definitions, and
--- resolving those names here would quietly swap them for this reader's. Everything else about the
--- walk is the same, transitive close included, so it is one function taking a resolver rather than
--- two that drift.
local function BuildSwitchCells(actions, RowsOf)
    local referenced = {};
    CollectSwitchNames(actions, referenced);

    local switches, seen, any = {}, {}, false;
    local pending = referenced;

    while (pending) do
        local nextPending;

        for name in pairs(pending) do
            if (not seen[name]) then
                seen[name] = true;
                for _, found in ipairs(RowsOf(name)) do
                    local row = found.row;
                    CellAt(switches, found.owner, found.class, found.spec)[name] =
                        CopyFields(row, SWITCH_FIELDS);
                    any = true;

                    -- A computed row's expression can name other switches, and those have to
                    -- travel too or the row arrives referring to nothing.
                    if (row.mode == Constants.SWITCH_MODES.EXPR and luatype(row.expr) == "string") then
                        local _, args = DebindPrivate.ParseMacroText(row.expr);
                        for j = 1, (args and #args or 0) do
                            local arg = args[j];
                            if (arg.type == Constants.MACROTEXT_ARG_SWITCH and not seen[arg.name]) then
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
    return switches;
end

--- Hands every row of a payload's `switches` to `fn(row, name, owner, class, spec)`, skipping what
--- is not a table. **The cells are v3's**, and every step that reaches for a definition goes
--- through here: `payload.v` is raised before any `dbver` step runs (`BringPayloadForward`).
local function ForEachPayloadSwitchRow(payload, fn)
    local switches = payload.switches;
    if (luatype(switches) ~= "table") then
        return;
    end
    for owner, classes in pairs(switches) do
        if (luatype(classes) == "table") then
            for class, specTbl in pairs(classes) do
                if (luatype(specTbl) == "table") then
                    for spec, cell in pairs(specTbl) do
                        if (luatype(cell) == "table") then
                            for name, row in pairs(cell) do
                                if (luatype(row) == "table") then
                                    fn(row, name, owner, class, spec);
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
DebindStorage.ForEachPayloadSwitchRow = ForEachPayloadSwitchRow;

--- `payload.characters` for the character keys `payload.layers` and `payload.switches` name,
--- each answered by `IdentityOf(owner)`. Nil where there are none.
local function BuildCharacters(payload, IdentityOf)
    local owners = CharacterOwners(payload);
    local characters;
    for owner in pairs(owners) do
        local identity = IdentityOf(owner);
        if (luatype(identity) == "table") then
            characters = characters or {};
            characters[owner] = CopyFields(identity, IDENTITY_FIELDS);
        end
    end
    return characters;
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
--- **Nothing asks this twice any more.** The export window used to build its own list and ask this
--- of every action on the way, which meant the window's numbers and the payload's contents were two
--- walks that had to agree -- and disagreeing looked like the window saying "12" and sending 9.
---
--- A payload is made once (`CreateEntry`) and the panel draws that payload, so there is no second
--- walk to be wrong: a badged action is not in the entry, therefore not in the preview, therefore
--- not in the count and not in the string (`building-export-import.md` 12절).
---
--- **A keyless action is not this.** No badge means the action is the sender's, and "something I
--- have not given a key to" is a fact about their setup worth carrying.
function DebindStorage.IsExportable(action)
    return action.arrivalID == nil;
end



-- ---------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------

DebindStorage.PAYLOAD_VERSION = PAYLOAD_VERSION;

local function NewPayload()
    return {
        v = PAYLOAD_VERSION,
        -- **The shape of the actions below, which is not the same question as `v`.** The profile is
        -- already at `Constants.DB_VERSION` by the time anything can be exported -- `MigrateDB` runs
        -- at login -- so this says what these actions are, and the reading side raises them with the
        -- same ladder the profile uses (`BringPayloadForward`).
        dbver = Constants.DB_VERSION,
        -- **When and where the setting was made, which the string carries and the row cannot.** A
        -- row's `received` is when it reached that list, and a pasted string reaches it long after.
        created = time(),
        gameType = Constants.GAME_TYPE,
        layers = {},
    };
end

--- The fields about the payload as a whole, carried by every copy made of one (`FilterPayload`), and
--- the type each has to be. **`name` and `description` are free text a sender wrote**: whoever
--- draws them owes them `PlainText`.
---
--- **`fromAddon` names the addon whose data this is**, nil for ours. It is not how the payload
--- reached a reader; that is the stored row's `receivedFrom`, and it does not travel.
local META_FIELDS = {
    fromAddon = "string",
    created = "number",
    gameType = "string",
    name = "string",
    description = "string",
};

--- `META_FIELDS` of `from`, copied onto `to`.
local function CopyMeta(from, to)
    for field in pairs(META_FIELDS) do
        to[field] = from[field];
    end
    return to;
end

--- The payload's `fromAddon` for a Clique profile. Read when the payload is added, which is where
--- the layer is chosen and `untranslated` is resolved (`importing-clique-profiles.md` §3).
DebindStorage.FROM_ADDON_CLIQUE = "clique";

--- The values `fromAddon` may hold: the addons this version converts. **Any other is dropped on the
--- way in** (`DropBadMeta`), so everything that asks "is this another addon's" gets the same answer:
--- a name nothing here can read would otherwise grey the share button while the add went on as
--- though the payload were ours.
local KNOWN_ADDONS = {
    [DebindStorage.FROM_ADDON_CLIQUE] = true,
};

--- Whether `payload` is another addon's data. **The one place that asks**, for the share button and
--- `ExportEntry` alike.
function DebindStorage.IsForeignPayload(payload)
    return luatype(payload) == "table" and payload.fromAddon ~= nil;
end

--- Drops a `META_FIELDS` value of the wrong type, in place. **The field goes and the string stays**:
--- none of these says anything about the actions, so a bad one is no reason to refuse them. NaN and
--- the infinities are not a time.
local function DropBadMeta(payload)
    for field, want in pairs(META_FIELDS) do
        local value = payload[field];
        if (value ~= nil and (luatype(value) ~= want
                or (want == "number" and (value ~= value or value == math.huge or value == -math.huge)))) then
            payload[field] = nil;
        end
    end
    if (payload.fromAddon ~= nil and not KNOWN_ADDONS[payload.fromAddon]) then
        payload.fromAddon = nil;
    end
end

--- Drops an option this version does not have, or one of the wrong type, in place - for the reason
--- `DropBadMeta` gives. An `options` that is not a table goes whole.
local function DropBadOptions(payload)
    local options = payload.options;
    if (options == nil) then
        return;
    end
    if (luatype(options) ~= "table") then
        payload.options = nil;
        return;
    end
    for name, value in pairs(options) do
        if (OPTION_FIELDS[name] ~= luatype(value)) then
            options[name] = nil;
        end
    end
end

--- Copies `action` into its cell of `payload` and onto `exported`. The cell is made by the first
--- action actually taken, so an empty layer -- or one the reader unticked whole -- leaves no empty
--- table behind for the far side to walk.
---
--- **The copy is sanitized, never the stored action** (`sanitizing-actions-with-one-function.md`
--- §2-2). Another character's cells are as they were stored until that character logs in, and the
--- switch walk below reads what is copied.
local function TakeAction(payload, exported, action, owner, class, spec)
    local copy = CopyFields(action, ACTION_FIELDS);
    if (not DebindPrivate.SanitizeAction(copy)) then
        return;
    end
    local cell = CellAt(payload.layers, owner, class, spec);
    cell[#cell + 1] = copy;
    exported[#exported + 1] = copy;
end

--- One of `BuildSwitchCells`'s rows: an answer and the cell it is given at.
local function AnswerRow(owner, class, spec, mode, resetValue, expr)
    return { owner = owner, class = class, spec = spec,
             row = { mode = mode, resetValue = resetValue, expr = expr } };
end

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
--- numbers, and it withheld nothing worth withholding: somebody who hands their setup to another
--- player is showing it off, and the keys are the part worth showing. The receiving side keeps them
--- and holds the actions back with a badge instead (`building-export-import.md` 12절).
---
--- A number still travels: that is a key group the sender has not given a key to, which is a fact
--- about their setup rather than something withheld.
---
--- **Emitted in storage order, one layer at a time.** Which of a key's actions goes first travels as
--- `seq`, so the array is not carrying that and does not have to be sorted to say it; and storage
--- order is stable for a profile nobody has edited, which is what re-exporting has to be able to
--- show. Whether a layer's actions are clumped by key is deliberately left open until there is a
--- preview to read them (`building-export-import.md`).
---
--- **Nothing about the client is asked.** A spell the reader does not have goes out as it sits, the
--- receiving side shows it marked, and the user deletes it; that one rule removes a whole class of
--- questions. What a copy does go through is `SanitizeAction` (`TakeAction`), which reads nothing
--- about the client either: a broken action goes out as `INVALID`, the shape a load would give it.
function DebindStorage.BuildExportPayload(selection)
    local payload, exported, layers = NewPayload(), {}, {};

    for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
        layers[#layers + 1] = layer;
        for _, action in layer:Enumerate() do
            if (DebindStorage.IsExportable(action) and (selection == nil or selection[action])) then
                TakeAction(payload, exported, action, LayerCell(layer));
            end
        end
    end

    -- **Every layer this character resolves a switch through**, not only the ones an action was
    -- taken from: an override on the class layer changes the switch for an action in general.
    payload.switches = BuildSwitchCells(exported, function(name)
        local rows = {};
        for _, layer in ipairs(layers) do
            local layerKey = layer.layerID ~= 1 and DebindPrivate.GetSwitchLayerKey(layer.layerID) or nil;
            if (layer.layerID == 1 or layerKey) then
                local mode, resetValue, expr = DebindPrivate.GetSwitchAnswerAt(name, layerKey);
                if (mode ~= nil) then
                    local owner, class, spec = LayerCell(layer);
                    rows[#rows + 1] = AnswerRow(owner, class, spec, mode, resetValue, expr);
                end
            end
        end
        return rows;
    end);

    payload.characters = BuildCharacters(payload, function(owner)
        return owner == DebindPrivate.playerGUID and DebindPrivate.GetPlayerIdentity() or nil;
    end);
    return payload;
end

--- `BuildExportPayload` for every cell the account holds rather than the layers this character
--- reaches: other classes' account cells and every character's own.
function DebindStorage.BuildAccountPayload()
    local payload, exported = NewPayload(), {};

    DebindPrivate.ForEachAccountLayer(function(list, owner, class, spec)
        for i = 1, #list do
            -- What is no table is no action, and no load has taken it out of another character's list.
            if (luatype(list[i]) == "table" and DebindStorage.IsExportable(list[i])) then
                TakeAction(payload, exported, list[i], owner, class, spec);
            end
        end
    end);

    payload.switches = BuildSwitchCells(exported, function(name)
        local rows = {};
        local mode, resetValue, expr = DebindPrivate.GetSwitchAnswerAt(name, nil);
        if (mode ~= nil) then
            rows[1] = AnswerRow(ACCOUNT_OWNER, "GENERAL", 0, mode, resetValue, expr);
        end
        DebindPrivate.ForEachSwitchOverride(function(row, rowName, owner, class, spec)
            if (rowName == name) then
                rows[#rows + 1] = AnswerRow(owner, class, spec, row.mode, row.resetValue, row.expr);
            end
        end);
        return rows;
    end);

    payload.characters = BuildCharacters(payload, DebindPrivate.GetCharacterIdentity);
    payload.options = CopyFields(DebindPrivate.Options or {}, OPTION_FIELDS);
    return payload;
end

--- The same payload with only `selection`'s actions in it. `nil` selection hands the payload back
--- as it is.
---
--- **What travels is decided here rather than when an entry is made.** An entry is a whole thing
--- somebody keeps; which part of it to hand out is a different answer every time, worth exactly one
--- press, and so it is never written down (`building-export-import.md`). Deleting from the
--- entry is the other verb and it is permanent -- one narrows a copy, the other narrows the thing.
---
--- **The fields an entry carries about the row do not travel, and nothing here has to drop them.**
--- They sit on the row, outside the payload. Who a character cell is travels in `characters`,
--- which is the payload's, and only the cells still in it keep theirs. What is about the payload as
--- a whole travels whole (`META_FIELDS`): a narrower copy was still made then, there, under that
--- name.
---
--- The actions are carried over by reference. Nothing downstream writes to one -- this table is
--- built to be encoded and dropped -- and copying them would only make the entry's own copies
--- (`CopyFields`, when it was built) into copies of copies.
function DebindStorage.FilterPayload(payload, selection)
    if (selection == nil) then
        return payload;
    end

    -- `options` travels with the actions it was taken beside, narrowed or not: they are the same
    -- account's settings either way.
    local out = CopyMeta(payload, { v = payload.v, dbver = payload.dbver, layers = {},
                                    options = payload.options });
    local kept = {};

    DebindStorage.ForEachPayloadLayer(payload, function(list, owner, class, spec)
        local bucket;
        for _, action in ipairs(list) do
            if (selection[action]) then
                bucket = bucket or CellAt(out.layers, owner, class, spec);
                bucket[#bucket + 1] = action;
                kept[#kept + 1] = action;
            end
        end
    end);

    out.switches = BuildSwitchCells(kept, function(name)
        local rows = {};
        ForEachPayloadSwitchRow(payload, function(row, rowName, owner, class, spec)
            if (rowName == name) then
                rows[#rows + 1] = { owner = owner, class = class, spec = spec, row = row };
            end
        end);
        return rows;
    end);

    local characters = luatype(payload.characters) == "table" and payload.characters or {};
    out.characters = BuildCharacters(out, function(owner)
        return characters[owner];
    end);

    return out;
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
    local util = C_EncodingUtil;
    if (not util) then
        return nil, "LIBS_MISSING";
    end

    local compressed = util.CompressString(util.SerializeCBOR(payload),
        Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize);
    return ENVELOPE_PREFIX .. ENVELOPE_VERSION .. ENVELOPE_SEPARATOR .. util.EncodeBase64(compressed);
end

--- A `DEB2:` body back into a table, or nil and the step that failed. The client's calls raise on
--- input they cannot read, and a pasted string is anything at all, so each is asked under `pcall`.
local function DecodeClientBody(encoded)
    local util = C_EncodingUtil;
    if (not util) then
        return nil, "LIBS_MISSING";
    end

    local ok, compressed = pcall(util.DecodeBase64, encoded);
    if (not ok or luatype(compressed) ~= "string" or compressed == "") then
        return nil, "BAD_ENCODING";
    end

    local serialized;
    ok, serialized = pcall(util.DecompressString, compressed, Enum.CompressionMethod.Deflate);
    if (not ok or luatype(serialized) ~= "string") then
        return nil, "BAD_COMPRESSION";
    end

    local payload;
    ok, payload = pcall(util.DeserializeCBOR, serialized);
    if (not ok) then
        return nil, "BAD_PAYLOAD";
    end
    return payload;
end

--- A `DEB1:` body, through the two libraries.
local function DecodeLibsBody(encoded)
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
    return payload;
end

--- `dbver` 6, the manifest side. A switch definition's `mode` goes from a number to a string and
--- `initialValue` becomes `resetValue` -- the same transformation `MigrateSwitches` makes in
--- `Migration.lua`, which is why it hangs off `dbver` rather than off `payload.v`: a definition is
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
--- The step holds its own literals, the old numbers and version 6's names alike, for the reason
--- every step in `Migration.lua` does (`MigrateLayer`'s header).
local function RenameManifestSwitchFields(definition)
    if (luatype(definition.mode) == "number") then
        if (definition.mode == 3) then
            definition.mode = "expr";
        else
            definition.mode = "manual";
        end
    end
    if (definition.initialValue ~= nil) then
        if (definition.resetValue == nil) then
            definition.resetValue = definition.initialValue;
        end
        definition.initialValue = nil;
    end
end

--- Every action list of a v1 or v2 payload, `fn(list)`: `shared.GENERAL`,
--- `shared.classes[class][spec]` and `char[spec]`, the addresses those two versions shared. Only
--- the steps that raise those versions call it.
local function ForEachV2List(payload, fn)
    local shared = luatype(payload.shared) == "table" and payload.shared or nil;
    local lists = {};
    if (shared) then
        lists[#lists + 1] = shared.GENERAL;
        if (luatype(shared.classes) == "table") then
            for _, specTbl in pairs(shared.classes) do
                if (luatype(specTbl) == "table") then
                    for _, list in pairs(specTbl) do
                        lists[#lists + 1] = list;
                    end
                end
            end
        end
    end
    if (luatype(payload.char) == "table") then
        for _, list in pairs(payload.char) do
            lists[#lists + 1] = list;
        end
    end
    for _, list in ipairs(lists) do
        if (luatype(list) == "table") then
            fn(list);
        end
    end
end

--- v1 -> v2, the action side. The wire spelled a `setstate` as a `setstate = { mode, state }`
--- subtable with no `value`; it is opened out into the `type` and the name the profile stores
--- (`unifying-action-migration.md` §3-2).
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
--- here and take down a commit with half an entry already placed. A mode or a name this build cannot
--- read leaves the action under the old type, which is a type nothing knows: it arrives as an action
--- nothing can run (`SanitizeAction`), which is the right end for a `setstate` with nothing to set.
---
--- **The three types are literals, the ones the `dbver <= 5` step writes**, and the `dbver <= 7`
--- step renames them the way it renames a stored one.
local V1_SETSTATE_TYPES = {
    on     = "setstate_on",
    off    = "setstate_off",
    toggle = "setstate_toggle",
};

local function OpenV1Setstate(payload)
    ForEachV2List(payload, function(actions)
        for i = 1, #actions do
            local action = actions[i];
            if (luatype(action) == "table" and luatype(action.setstate) == "table") then
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

--- v2 -> v3: the v2 addresses into the saved shape (`reshaping-stored-layers.md` 1-1).
---
--- **v2 carried no identity**, so its character layer lands under `"1"`, a key no `characters`
--- entry names, keyed by the class `payload.class` named. **Without a class it is dropped.** Every
--- string since 3.2 carries one (9b57dc4), so a v2 without it was edited by hand, and a hand-edited
--- file is not read for what it meant (`reshaping-stored-layers.md` 1절).
---
--- `shared.classes.GENERAL` is dropped for the same reason: no class is called that, and in v3 the
--- name is the general layer's.
---
--- v2 sent no override rows, so the definitions are the whole of `switches`.
---
--- v2 called `fromAddon` `source`. 4.1 wrote it on a Clique payload, and such a payload is in 4.1
--- strings and in 4.1 drawers alike.
local function RaiseV2(payload)
    local account = {};
    local shared = luatype(payload.shared) == "table" and payload.shared or nil;
    if (shared) then
        if (luatype(shared.classes) == "table") then
            for class, specTbl in pairs(shared.classes) do
                if (class ~= "GENERAL") then
                    account[class] = specTbl;
                end
            end
        end
        if (shared.GENERAL ~= nil) then
            account.GENERAL = { [0] = shared.GENERAL };
        end
    end

    local layers = {};
    if (next(account) ~= nil) then
        layers[ACCOUNT_OWNER] = account;
    end
    if (luatype(payload.char) == "table" and luatype(payload.class) == "string") then
        layers["1"] = { [payload.class] = payload.char };
    end
    payload.layers = layers;

    if (luatype(payload.states) == "table") then
        payload.switches = { [ACCOUNT_OWNER] = { GENERAL = { [0] = payload.states } } };
    end

    payload.fromAddon = payload.source;

    payload.shared = nil;
    payload.char = nil;
    payload.states = nil;
    payload.class = nil;
    payload.source = nil;
    payload.v = 3;
end

--- Raises a payload's **contents** to this build's `dbver`, action arrays and manifest alike.
---
--- **The actions go up the profile's own ladder.** `MigrateLayer` walks an array of actions and
--- touches nothing above one, and a payload's layer is an array of actions, so it goes across as it
--- is. Writing the same transformation twice is what this replaces: condition nesting stood here in
--- full, in a second copy of the `dbver <= 5` step
--- (`unifying-action-migration.md` §3-4).
---
--- **What is walked is still each side's own.** Layer addresses and key mapping are different
--- things in a profile and in a payload; only the per-action ladder is shared.
---
--- **`payload.v` is already current here** (`BringPayloadForward`), so the definitions are found
--- in v3's cells whatever version the payload came in as.
local function BringPayloadDataForward(payload)
    local dbver = payload.dbver;

    if (dbver <= 5) then
        ForEachPayloadSwitchRow(payload, RenameManifestSwitchFields);
    end

    if (dbver <= 6) then
        -- The unit rename, on the manifest. A computed switch's expression is macro text and can
        -- name the pointed frame's unit, which is called `unitframe` from `dbver` 7 on
        -- (`Profile.lua`'s step says why a body has to move and not only a field). The actions in
        -- the payload ride the profile's own ladder below and are already covered.
        ForEachPayloadSwitchRow(payload, function(definition)
            if (luatype(definition.expr) == "string") then
                definition.expr = DebindPrivate.RenameUnitInMacroTextAt7(
                    definition.expr, "hover", "unitframe");
            end
        end);
    end

    DebindStorage.ForEachPayloadLayer(payload, function(actions)
        DebindPrivate.MigrateLayer(actions, dbver);
        -- **Its spells go on their first rank, every time one arrives**
        -- (`keeping-a-pinned-rank-apart-from-the-spell.md` §5): a string an older version made would
        -- otherwise bring every rank's id back in. The profile's own did this once, in its
        -- migration; that step is not the shared ladder's because a payload does it here.
        for i = 1, #actions do
            local action = actions[i];
            if (luatype(action) == "table" and action.type == Constants.SPELL) then
                action.value = DebindPrivate.CanonicalSpellID(action.value);
            end
        end
    end);

    payload.dbver = Constants.DB_VERSION;
end

--- Raises a payload to what this version reads, or says why it cannot. Returns the payload, or nil
--- plus a reason.
---
--- **Two ladders, and they are asked in this order.** `payload.v` describes the payload around the
--- actions -- the `layers` and `switches` cells, `characters`, what `seq` means -- and
--- `payload.dbver` describes the actions inside it. `payload.v` has to be raised first, because v1
--- does not carry a `dbver` and the step that raises it is what stamps one on
--- (`unifying-action-migration.md` §3-3). The envelope is a third number and not asked here: it is
--- the packing around the whole payload (`ENVELOPE_VERSION`), and `DecodeExportString` has already
--- unpacked it.
---
--- **A `payload.v` step names the exact version it raises (`== 1`), not `<=`.** A payload two
--- versions back then walks every step in turn, and a number nothing ever wrote falls through to
--- the refusal instead of being guessed at. The `dbver` ladder is the opposite and opens with
--- `<=`, because that one is the profile's and every version between the ends of it is real.
---
--- **Both doors ask this, and that is the point of it being a function.** A string is asked at the
--- moment it is pasted (`DecodeExportString`, below) and a stored entry is asked when the drawer
--- opens it (`GetEntryPayload` in `Import.lua`). The drawer used to ask nothing: it kept the
--- payload it was handed and gave it straight back. That is invisible while there is one payload
--- version and it stops being invisible the day one is added, because the entries already sitting in the
--- drawer are exactly the ones that would go into the new code unasked.
---
--- **Two directions, and opposite advice.** These were one reason and one sentence, "made by a
--- newer version, update and try again", which is true one way and useless the other: on the first
--- `PAYLOAD_VERSION` bump every entry already received would fail with it, told to update by the
--- version they just updated to.
---
--- `PAYLOAD_TOO_OLD` is the answer for a version **no step covers**, on either ladder. A bump
--- means a field changed meaning (`PAYLOAD_VERSION`'s own note), so such a payload cannot be read
--- by guessing, and guessing is how a condition silently changes sides.
---
--- **"Is it a payload at all" is asked here and nowhere else.** Both doors hand over something they
--- did not make: one has just deserialized bytes somebody else wrote, the other has read a table
--- out of SavedVariables. Neither may error, and the answer is the same refusal, so asking twice
--- would be the same question in two places. It caught one a development build had left (2026-08-20;
--- every released version stores a table here): an entry with no payload draws in the drawer
--- perfectly well, because the two that draw the row guard it (`CountEntry`, `EntryClassText`), and
--- then threw the moment the row was opened. So what it guards against is a hand-edited file.
function DebindStorage.BringPayloadForward(payload)
    if (luatype(payload) ~= "table") then
        return nil, "BAD_PAYLOAD";
    end
    if (luatype(payload.v) ~= "number" or payload.v > PAYLOAD_VERSION) then
        return nil, "PAYLOAD_TOO_NEW";
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

    if (payload.v ~= 2 and payload.v ~= PAYLOAD_VERSION) then
        return nil, "PAYLOAD_TOO_OLD";
    end

    -- **Asked before the v2 step**, so a payload refused here is left in the shape it came in. The
    -- drawer raises its entries in place (`Import.lua`'s `Vars`), and a refused one moved halfway
    -- would be stored in a shape no version wrote.
    --
    -- **NaN passes every comparison below**, and a payload claiming it would walk through the range
    -- check and reach `MigrateLayer` with a version no step can match. It is asked about the same
    -- way a NaN key is (`PayloadIsImpossible`).
    local dbver = payload.dbver;
    if (luatype(dbver) ~= "number" or dbver ~= dbver) then
        return nil, "BAD_PAYLOAD";
    end
    if (dbver > Constants.DB_VERSION) then
        return nil, "PAYLOAD_TOO_NEW";
    end
    if (dbver < OLDEST_PAYLOAD_DBVER) then
        return nil, "PAYLOAD_TOO_OLD";
    end

    if (payload.v == 2) then
        RaiseV2(payload);
    end

    BringPayloadDataForward(payload);
    DropBadMeta(payload);
    DropBadOptions(payload);

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

    local payload, reason;
    if (tonumber(version) == ENVELOPE_VERSION) then
        payload, reason = DecodeClientBody(encoded);
    elseif (tonumber(version) == ENVELOPE_LIBS) then
        payload, reason = DecodeLibsBody(encoded);
    else
        return nil, "UNSUPPORTED_ENVELOPE";
    end
    if (reason) then
        return nil, reason;
    end

    -- Whether what came back is a table at all is asked below, with the same answer, on the door a
    -- stored entry uses too.
    --
    -- **Under `pcall`, because the bytes are somebody else's.** A step written for what our builds
    -- stored can meet a shape none of them wrote, and the paste box has to answer rather than raise.
    -- The raise is still reported: a step that raises is ours to fix, whatever it was handed.
    local ok, raised, refusal = pcall(DebindStorage.BringPayloadForward, payload);
    if (not ok) then
        geterrorhandler()(raised);
        return nil, "BAD_PAYLOAD";
    end
    return raised, refusal;
end

--- What the window calls: an entry and what is ticked in it, string out.
---
--- **Another addon's data does not go out** (`FOREIGN_PAYLOAD`, owner, 2026-10-03). Nobody has
--- checked it yet: what it holds is a conversion, part of it still in that addon's own shape
--- (`untranslated`), and what makes it ours is the reader adding it and seeing where it lands. A
--- string made from it would hand that unchecked conversion on, person to person. Once added, a
--- payload made from the profile carries what the reader saw.
---
--- **The profile is not read here.** It was, while the export window built a string straight out of
--- the layers, and the entry is what stands between them now: making one is the moment the profile
--- is read (`CreateEntry`), and everything after that -- deleting from it, ticking part of it,
--- handing it out -- is about the entry. So an entry that arrived in somebody else's string goes
--- back out through this same call, which is what makes passing one on cost nothing to build.
function DebindStorage.ExportEntry(entry, selection)
    local payload, reason = DebindStorage.GetEntryPayload(entry);
    if (not payload) then
        return nil, reason;
    end
    if (DebindStorage.IsForeignPayload(payload)) then
        return nil, "FOREIGN_PAYLOAD";
    end
    return DebindStorage.EncodeExportPayload(DebindStorage.FilterPayload(payload, selection));
end
