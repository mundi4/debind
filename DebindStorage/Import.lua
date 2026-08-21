local _, DebindStorage = ...;

local DebindPrivate = DebindStorage.DebindPrivate;
local Constants     = DebindPrivate.Constants;
local luatype       = type;

--- How many specializations this character's class has. Read here rather than asked of
--- `GetLayerID`, which **asserts** on a spec beyond that count -- and a spec beyond that count is
--- ordinary input, since the string may come from a class with more specs than ours.
local NUM_SPECS = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));

--- The receiving end: a pasted string waits until the reader says to bring it in, and then becomes
--- actions in the profile. The reverse of `Export.lua`, and only that. Deciding *which* batch to
--- commit, and what to do with the result afterwards, belongs to the window and to the main
--- window's Overview.
---
--- **A batch is outside the profile until it is committed**, which is the decision the design turns
--- on (`devdocs/building-export-import.md`): once actions are in the profile they scatter -- the
--- overview sorts by name, layers split them -- so what arrived together has to keep saying so, and
--- the key is what carries it across.
---
--- **Everything that lands is quarantined.** Each action carries `imported`, and while that is set
--- `BuildKeyMap` skips it: the string is in the profile, drawn and editable, and reaches no key
--- until the reader takes the badge off. So committing never changes what any key does, which is
--- what lets it run without asking anything first.


--- What gets serialized is the payload, so this versions the payload's shape. Bump it when that
--- shape changes under a reader holding one written by an older version.
---
--- It was called `STORE_VERSION` and its comment said "bump when a stored batch changes shape",
--- which is why it got bumped for something that is not a shape change at all: keeping the payload
--- instead of the string it arrived in. **The same payload either way** - compressed in a `text`
--- field or sitting there decoded - so nothing about the serialized shape moved. What moved was
--- where it lived.
---
--- The two versions on the string itself (`Export.lua`) are a different question: those describe
--- bytes that came from somewhere else, and this one describes what we wrote ourselves.
local PAYLOAD_VERSION           = 1;

--- The highest spec number the profile has a place for (`LAYER_INFOS` in `Profile.lua` runs each
--- block from 0 to 4). A descriptor naming a spec past this is not a spec we cannot represent, it
--- is a number no client produces -- so it is refused rather than folded to something nearby.
local MAX_SPEC                = 4;

--- The class names this client has, enumerated the way the pre-rename import does it
--- (`Legacy.lua`).
---
--- **A descriptor's class is a key straight into storage** (`shared.classes[class]`), so one that
--- names no class would stand up a table no screen can reach and nothing ever clears -- `CleanUpDB`
--- walks the eleven loaded layers and would never see it. Every paste of a made-up name would grow
--- the account file by another one.
local KNOWN_CLASSES           = {};
for classID = 1, 20 do
    local classInfo = C_CreatureInfo.GetClassInfo(classID);
    if (classInfo and classInfo.classFile) then
        KNOWN_CLASSES[classInfo.classFile] = true;
    end
end

--- **There is no expiry.** Two constants and two functions stood here, and a pin on the row to
--- opt out of them: a batch was judged old after a month and called out three days before, and
--- nothing ever removed one. So the row showed a date on which nothing happens and the pin
--- exempted the reader from a sweep that does not exist.
---
--- **The design is not rejected, it is unbuilt.** Received strings do pile up, and the one thing
--- that may not happen is one of them vanishing without having said so - which is why the answer is a
--- clear-out that **asks**, not a sweep, and why nothing here should judge anything until there is
--- something to ask with (`devdocs/building-export-import.md`). Judgement with no action is worse
--- than neither: it puts a promise on screen.


-- ---------------------------------------------------------------------------------------------
-- Source layers
-- ---------------------------------------------------------------------------------------------

--- Every layer list in a payload, handed its address: `fn(list, scope, class, spec)`.
---
--- **The path is the address.** The payload nests the way storage does -- `shared.GENERAL`,
--- `shared.classes[class][spec]`, `char[spec]` -- so there is no descriptor to read and nothing to
--- translate; walking the string and walking the profile are the same walk
--- (`devdocs/building-export-import.md`).
---
--- The address is only where it *claims* to be. `ImportAddress` is what says whether it is one this
--- profile has a place for, and the two are separate so a caller can count what it turned down.
---
--- Every branch is type-checked on the way down, because a pasted string is untrusted input and
--- none of this may error. A branch that is not a table is not walked, which is the same answer as
--- a branch that is not there.
---
--- **The elements are checked too, and that is not the same check.** This walk used to stop at the
--- lists and hand them over whole, so one number sitting where an action belongs raised in whatever
--- read it next -- and every caller reads them: counting on paste, planning, building. Filtering
--- here is what lets each of them say `ipairs` and stop worrying.
function DebindStorage.ForEachPayloadLayer(payload, fn)
    --- The list handed on, with anything that is not an action table left out. A copy, because the
    --- callers walk it with `ipairs` and one hole would stop them early -- and because what is
    --- dropped has to be dropped for every caller alike, not per caller.
    local function Visit(list, scope, class, spec)
        if (luatype(list) ~= "table") then
            return;
        end
        local actions = {};
        for i = 1, #list do
            if (luatype(list[i]) == "table") then
                actions[#actions + 1] = list[i];
            end
        end
        fn(actions, scope, class, spec);
    end

    local shared = luatype(payload.shared) == "table" and payload.shared or nil;

    if (shared) then
        Visit(shared.GENERAL, "general", nil, 0);
        if (luatype(shared.classes) == "table") then
            for class, specTbl in pairs(shared.classes) do
                if (luatype(specTbl) == "table") then
                    for spec, list in pairs(specTbl) do
                        Visit(list, "class", class, spec);
                    end
                end
            end
        end
    end

    if (luatype(payload.char) == "table") then
        for spec, list in pairs(payload.char) do
            Visit(list, "character", nil, spec);
        end
    end
end

--- Does this profile have a place for that address? Returns `scope, class, spec` -- the three the
--- profile is keyed by (`shared.GENERAL`, `shared.classes[class][spec]`,
--- `characters[guid].layers[spec]`) -- or nil.
---
--- **A layer is not something to translate.** Both profiles use the same coordinate system: one
--- general layer, then class by spec, then character by spec. What differs between two accounts is
--- *which class*, and that is a value of the coordinate, not a coordinate of its own. A mage's
--- spec 2 layer is a mage's spec 2 layer on every account, so it goes there verbatim -- no falling
--- back, no dropping the spec, no swapping the class for the reader's. `devdocs/building-export-import.md`.
---
--- The cost is that a mage's string read by a druid lands somewhere this session cannot see: the
--- druid's `LayerArray` has no `classes.MAGE` in it, so nothing about it is on screen until they
--- log the mage. That is the answer, not a gap. The two alternatives were putting a mage's spells
--- in "all my druids" -- where the reader is asked a question they cannot answer, every line red
--- because they cannot learn any of it -- and refusing the string outright.
---
--- **The one real translation is the character.** "Their character" has no meaning here, so a
--- character-scoped layer means *this* character at that spec. A spec this character does not have
--- is the only address with nowhere to go: `characters[guid].layers[4]` on a three-spec class is a
--- table nothing will ever read and nothing will ever clean up. Answering nil is what gets it
--- counted and said out loud instead.
function DebindStorage.ImportAddress(scope, class, spec)
    if (scope == "general") then
        return "general";
    end

    -- **A slot number, not just a number in range.** `1.5` passes all three comparisons and becomes
    -- `shared.classes.DRUID[1.5]` - a table no `GetProfileLayer` reads and `CleanUpDB` never walks,
    -- so every paste of such a string leaves one more behind in the account file. That is precisely
    -- the outcome this function exists to refuse. NaN is worse: **every** comparison against it is
    -- false, so it passes the range check and raises where the value is used as an index, halfway
    -- through placing a batch. `spec ~= floor(spec)` is false for both a fraction and an infinity,
    -- and `spec ~= spec` is the only thing that catches NaN.
    spec = spec or 0;
    if (luatype(spec) ~= "number" or spec ~= spec or spec ~= floor(spec)
        or spec < 0 or spec > MAX_SPEC) then
        return nil;
    end

    if (scope == "class") then
        if (not KNOWN_CLASSES[class]) then
            return nil;
        end
        return "class", class, spec;
    end

    if (scope == "character") then
        if (spec > NUM_SPECS) then
            return nil;
        end
        return "character", nil, spec;
    end

    return nil;
end

-- ---------------------------------------------------------------------------------------------
-- One action
-- ---------------------------------------------------------------------------------------------

--- Whether one wire field may be copied, **by name and by type**.
---
--- A name filter alone let a field arrive as anything: `seq = {}` reached `ARRIVAL_SEQ + seq` and
--- raised halfway through `PlaceImportedActions`, `priority = {}` raised inside the `table.sort`
--- that follows, `units = "x"` was walked with `pairs`. Every one of those went off after
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
        return false;
    end
    return strfind(expected, luatype(value), 1, true) ~= nil;
end

--- The same filter, one level down, for what may sit inside `conditions`.
---
--- **The nesting made this necessary rather than optional.** While the conditions were spread
--- across the action, the whitelist above saw each of them by name; folded into one table they
--- would arrive as a single `conditions = "table"` that nothing looked inside, and a hand-made
--- string could put anything in there. `CleanUpDB` sweeps it at the next logout, which is a whole
--- session of an unknown key riding on a real action.
---
--- `$`-prefixed names pass unlisted as booleans, the same escape the export copies out through:
--- a switch condition is stored under its own name. They still have to be booleans -- `$state1..5`
--- are declared as such and an arbitrary name does not make the value freer.
---
--- **A name this install has nothing defined for arrives all the same, and that is now the whole
--- rule.** `IsUsableAction` used to refuse the string over one, back when the runtime read no name
--- but the five: the solver gave any other name no column, so the box became the whole condition
--- space and the arriving action covered every binding under it on that key. The solver builds a
--- column per name it finds now (`Solver.lua`), so such a condition is what it looks like -- a
--- reference to a switch that is not here, which is red text and a binding that does not fire,
--- exactly like the spell the reader never learnt.
local function ConditionAllowed(name, value)
    local expected = DebindStorage.CONDITION_TYPES[name];
    if (not expected) then
        return strsub(name, 1, 1) == "$" and luatype(value) == "boolean";
    end
    return strfind(expected, luatype(value), 1, true) ~= nil;
end

--- What `value` is, per action type. `nil` in this table is not "unlisted", it is **"this type has
--- no value"** -- the four that need none are spelled out so that an unknown type is unlisted and
--- an unusable one is not.
---
--- The whitelist above cannot say any of this. It reads one field at a time, and `value` is
--- `number|string` there because a spell id is a number and a macro reference is a name. Which of
--- the two applies is the **action's type**, and the table has no column for that.
---
--- Read by `IsUsableAction`, which is the whole use. Every entry was taken from what the binding
--- builder does with the value (`UpdateBindings.lua`): `item` goes through `format("item:%d", …)`,
--- `worldmarker` through `_G["WORLD_MARKER" .. value]`, `petaction` through
--- `_G["SLASH_" .. value .. "1"]`, `macro` straight into the `*macro-` attribute.
local VALUE_SHAPES = {
    [Constants.SPELL]       = "number",
    [Constants.ITEM]        = "number",
    [Constants.MOUNT]       = "number",
    [Constants.FLYOUT]      = "number",
    [Constants.WORLDMARKER] = "number",
    [Constants.SETCUSTOM]   = "number",
    -- A switch name. It reaches `SetAttribute` as the name of the attribute to set
    -- (`UpdateBindings.lua`), where a number would name an attribute nothing reads.
    --
    -- **Or nothing at all**, which is a shape this addon started producing at stage 3c: the picker
    -- adds one row with no target and the switch is picked in the action's own menu afterwards
    -- (`devdocs/redesigning-custom-states.md` §6-C). A reader can export a layer before getting
    -- round to that, and this table is asked whether the addon *could* have made the action. So
    -- refusing it here would turn away the whole string over a half-finished row, which is the one
    -- thing the receiving side is built not to do. It lands, it is red
    -- (`BINDING_ISSUE_SWITCH_NONE_SELECTED`), and it does not bind.
    [Constants.SETSTATE_ON]     = "string|nil",
    [Constants.SETSTATE_OFF]    = "string|nil",
    [Constants.SETSTATE_TOGGLE] = "string|nil",
    [Constants.MACRO]       = "string",
    [Constants.MACROTEXT]   = "string",
    [Constants.COMMAND]     = "string",
    [Constants.PETACTION]   = "string",
    [Constants.TARGET]      = false,
    [Constants.FOCUS]       = false,
    [Constants.TOGGLEMENU]  = false,
    [Constants.UNUSED]      = false,
};

--- Is this a shape **this addon could have produced**? Asked of the built action, not of the wire
--- table, so it answers about what would land rather than about how the format spells it.
---
--- **This is not "is it broken".** A spell the reader never learnt, a macro name nothing answers
--- to: those are ordinary and the whole receiving side is built to show them in red. This asks
--- whether the action is one the addon can represent at all -- a `macro` holding a number, a
--- `worldmarker` holding nothing. **Nothing this addon writes builds one of those**, so a string
--- carrying one was touched by hand somewhere -- the string itself, or the SavedVariables it was
--- exported from -- and `AddBatch` turns the **whole string** away on it
--- (`devdocs/building-export-import.md`).
---
--- A type nobody knows is the same answer. It cannot be drawn, cannot be bound, and cannot be
--- repaired into anything.
local function IsUsableAction(action)
    local shape = VALUE_SHAPES[action.type];
    if (shape == nil) then
        return false;
    end

    if (shape == false) then
        return true;
    end
    -- `|`-separated, read the way `ConditionAllowed` reads `CONDITION_TYPES`. One type needs it so
    -- far and `"nil"` is the alternative it needs, which `luatype` answers with like any other.
    return strfind(shape, luatype(action.value), 1, true) ~= nil;
end

--- A wire action turned into a profile action.
---
--- **Filtered through the same whitelist the export copies out by** (`ACTION_FIELDS`). This used to
--- be a blacklist naming the format's own fields, and being the opposite of the other end is what
--- made it a hazard: a wire field nobody had thought to name rode straight into the profile, and
--- avoiding that was the last reason left for the ranking to travel under a name other than its own.
--- With both ends reading one list there is no name to dodge (`devdocs/building-export-import.md`).
---
--- **The whitelist is the last thing this does, and it is the only writer of `action`.** Grep
--- `action[` in here and there is one line. Everything decided above it writes to `fields`, which
--- is still the untrusted table, so whoever adds the next rule cannot help but hand it to the
--- whitelist. Those blocks used to run **after** the loop and assign to `action`, which held only
--- as long as everyone remembered that writing there put a value in the profile unread.
---
--- **Nothing is rebuilt on the way in any more, and the whitelist is the whole of it.** A
--- `SETSTATE` used to arrive as a `setstate = { mode, state }` subtable with no value, and this is
--- where it was turned back into the bitpack the profile stored. §9-1 made the stored form a `type`
--- and a name, so what arrives is what lands and the loop below just copies it
--- (`devdocs/legacy/unifying-action-migration.md` §3-1). Reading the old subtable is
--- `BringPayloadForward`'s now, one door earlier, where every other version step lives.
local function BuildAction(source)
    local fields = CopyTable(source);

    local action = {};
    for k, v in pairs(fields) do
        -- **The key is asked about as well as the value.** A hand-made table brings numbers here,
        -- and `FieldAllowed` reads the name with `strsub`.
        --
        -- A table is copied again rather than handed over. How far `fields` already stands from
        -- `source` is `CopyTable`'s business, and this line is what makes the profile's table its
        -- own whatever that answer is. `CopyTable` returns a table, so the `and`/`or` here cannot
        -- fall through to `v`.
        if (luatype(k) == "string" and FieldAllowed(k, v)) then
            action[k] = luatype(v) == "table" and CopyTable(v) or v;
        end
    end

    -- **The conditions table is filtered after it is copied, not instead.** The loop above is
    -- still the only writer of `action`; this walks what it just put there.
    local conditions = action.conditions;
    if (conditions) then
        for k, v in pairs(conditions) do
            if (luatype(k) ~= "string" or not ConditionAllowed(k, v)) then
                conditions[k] = nil;
            end
        end
        -- An empty table is not "no conditions" downstream, it is an action that reads as
        -- conditional with nothing on it (`IsConditionalBinding`).
        if (next(conditions) == nil) then
            action.conditions = nil;
        end
    end

    return action;
end

--- Does this payload hold something **this addon could not have made**?
---
--- One is enough, and one refuses the whole string (2026-08-18, owner's decision,
--- `devdocs/building-export-import.md`). Not that one part on its own: our export cannot produce
--- the shape, so the string was edited after it was made, and **the rest of it is not warranted
--- either**. It is also the only answer the reader can act on. Nothing in this addon repoints an
--- existing action, so a bad row left in their profile could only be deleted -- refusing the string
--- puts the repair back where they can reach it, which is asking for it again.
---
--- **Actions are asked of the built one**, not of the wire table, which is why `BuildAction` stands
--- above this section. The two differ by what the whitelist drops, and asking about the wire table
--- would be asking about fields that never land.
---
--- The other two are the values that are **used as something before anything checks them**, and
--- both crash rather than misbehave:
---
---   * `class` reaches `format("%s", …)` in the caller, and WoW's Lua 5.1 throws on a table
---     there. Refusing it here is what keeps a payload on disk from being one nobody can open.
---   * a `key` of NaN raises the moment it is used as a table index, which the count below does and
---     `KeyMapper` does again. `ImportAddress` turns the same value away for `spec` and says why.
---
--- Neither needs its own guard downstream now, because nothing downstream runs on a payload this
--- refuses -- `AddBatch` asks before it stores, and a batch is the only way in.
function DebindStorage.PayloadIsImpossible(payload)
    if (payload.class ~= nil and not KNOWN_CLASSES[payload.class]) then
        return true;
    end

    local found = false;
    DebindStorage.ForEachPayloadLayer(payload, function(list)
        for _, source in ipairs(list) do
            if (not IsUsableAction(BuildAction(source))) then
                found = true;
            elseif (source.key ~= nil and source.key ~= source.key) then
                found = true;
            end
        end
    end);
    return found;
end


-- ---------------------------------------------------------------------------------------------
-- Stored batches
-- ---------------------------------------------------------------------------------------------

--- `DebindStorageVars`, made if it is not there yet.
---
--- Built on demand rather than from an `ADDON_LOADED` handler. Nothing in this addon runs before
--- the window is opened -- that is the whole reason it is `LoadOnDemand` -- so there is no earlier
--- moment for a handler to be the right answer to.
---
--- **Which makes this the only moment a migration could run**, for the same reason: there is no
--- earlier one. There is nothing to migrate yet and there cannot be until this addon ships, so the
--- version is stamped and nothing reads it back.
local function Vars()
    local vars = _G.DebindStorageVars;
    if (not vars) then
        vars = {};
        _G.DebindStorageVars = vars;
    end
    vars.version = vars.version or PAYLOAD_VERSION;
    vars.batches = vars.batches or {};
    vars.nextID = vars.nextID or 1;

    return vars;
end

--- The payload of a stored batch, or nil plus the reason it could not be read.
---
--- **The payload is what is stored, not the string it came in.** Four reasons for keeping the
--- string were written down and all four turned out to be true of both shapes
--- (`devdocs/building-export-import.md`). What decided it points the other way: `DecodeExportString`
--- refuses a string outright once its schema has moved, so stored strings are stored values nothing
--- can bring forward, while a payload can be walked the way `Profile.lua` walks `dbver`. What is
--- left over is disk size, and holding a smaller thing we cannot read is the worse end of that
--- trade.
---
--- **The gate `AddBatch` stands is stood again here.** A batch that got in before the gate existed
--- is closed by this one, which is why the gate needs nothing rewritten behind it -- there is only
--- something to refuse. **Everything that reads a payload for its contents comes through here**, so
--- past this line it is one of ours.
---
--- Two callers read `batch.payload` without asking: `CountBatch` and `BatchClassText`
--- (`ImportUI.lua`). Both draw the row rather than act on it, and a row has to be drawable for a
--- batch that this refuses -- deleting it is the only thing left to do with it, and the delete
--- button is on the row. So they guard the one field they touch and read nothing else.
---
--- **The schema is asked first, and it is asked for the same reason.** `AddBatch` asks it of a
--- string through `DecodeExportString`; this asks it of a payload that has been sitting in
--- SavedVariables since some earlier version. The two questions used to be one door apart: what is
--- pasted was asked and what is stored was not, so the batches most likely to be old were the ones
--- nothing asked. It answers the same thing on every payload there is today, and stops doing so the
--- day a schema step is written -- which is what `BringPayloadForward` is for, and why it comes
--- before the check below rather than after. `PayloadIsImpossible` reads fields whose meaning the
--- schema decides, so asking it about a payload of an unknown schema is asking the wrong question.
function DebindStorage.GetBatchPayload(batch)
    local payload, reason = DebindStorage.BringPayloadForward(batch.payload);
    if (not payload) then
        return nil, reason;
    end

    if (DebindStorage.PayloadIsImpossible(payload)) then
        return nil, "IMPOSSIBLE_PAYLOAD";
    end

    return payload;
end

--- How many groups and how many actions a batch holds.
---
--- **Counted on the spot rather than written down when the batch was made.** Both numbers were
--- fields on the record while the string was what got stored, because answering them any other way
--- meant decoding every row of the list to draw it. The payload is right there now, so a stored
--- copy would only be a second place for the same fact to live.
---
--- **A key is a group**, so counting the distinct keys is counting the groups. An action with no
--- key at all is in nobody's, and adds to the total but to no group.
function DebindStorage.CountBatch(batch)
    local groupCount, actionCount = 0, 0;
    if (not batch.payload) then
        return groupCount, actionCount;
    end

    local seenKeys = {};
    DebindStorage.ForEachPayloadLayer(batch.payload, function(list)
        for _, action in ipairs(list) do
            actionCount = actionCount + 1;
            local key = action.key;
            if (key ~= nil and not seenKeys[key]) then
                seenKeys[key] = true;
                groupCount = groupCount + 1;
            end
        end
    end);

    return groupCount, actionCount;
end

--- Takes a pasted string in and keeps it as a batch.
---
--- **Decoded before it is stored**, so a string that cannot be read is refused where the user is
--- looking at it rather than becoming a batch that fails every time it is opened.
--- Returns the batch, or nil plus the same reason codes `DecodeExportString` uses, plus
--- `IMPOSSIBLE_PAYLOAD` for the check below.
function DebindStorage.AddBatch(text, name)
    local payload, reason = DebindStorage.DecodeExportString(text);
    if (not payload) then
        return nil, reason;
    end

    -- **Asked before anything is stored, and before anything below reads a value.** Everything
    -- from here on treats the payload as one of ours.
    if (DebindStorage.PayloadIsImpossible(payload)) then
        return nil, "IMPOSSIBLE_PAYLOAD";
    end

    local vars = Vars();
    local batch = {
        id = vars.nextID,
        received = time(),
        -- **What arrived, not the string it arrived in.** The string is not kept: nothing reads it
        -- back, and a copy of the same contents in a form we may one day be unable to decode is
        -- worth less than the payload beside it (`GetBatchPayload`).
        payload = payload,
        -- What the reader chose to call it. Free text, optional, purely for the list -- nothing
        -- reads it back.
        --
        -- **It asked who the string came from.** Nothing sends a string: it is copied off a page or
        -- out of a notes file, and the reader restoring their own backup had no answer to give - so
        -- the field stayed empty exactly where a name would have been most use.
        name = name,

        -- **Nothing else.** A record held five more fields at various points -- four empty tables
        -- and a `stripKeys` flag -- and every one of them was an answer to a question the caller
        -- asks at the moment it acts. A stored answer to a question nobody has asked yet is one
        -- that goes stale between the two.
    };

    vars.nextID = vars.nextID + 1;
    vars.batches[#vars.batches + 1] = batch;

    return batch;
end

function DebindStorage.GetBatches()
    return Vars().batches;
end

function DebindStorage.GetBatch(id)
    local batches = Vars().batches;
    for i = 1, #batches do
        if (batches[i].id == id) then
            return batches[i];
        end
    end
    return nil;
end

function DebindStorage.DeleteBatch(id)
    local batches = Vars().batches;
    for i = 1, #batches do
        if (batches[i].id == id) then
            tremove(batches, i);
            return true;
        end
    end
    return false;
end

-- ---------------------------------------------------------------------------------------------
-- The whole batch
-- ---------------------------------------------------------------------------------------------

--- Turns the keys a string arrived with into the keys they will be stored under.
---
--- **Every key is renamed, the sender's real ones included.** A key *is* its group here, so landing
--- on one the reader already uses is not a merge they can undo later: the two sets become one set,
--- and nothing records which member came from where. Their own group is left alone and the arrival
--- stays whole, which is what leaves the decision theirs to make (`devdocs/building-export-import.md`).
---
--- **Renaming rather than dropping** is what keeps a set a set. Losing the key would leave a
--- conditional binding as a pile of loose actions, and a wrong guess at which of them belonged
--- together is silent -- two that were meant to share a key end up on two, and both fire. The
--- number says, in the one way the profile can hold, that the key is still to be decided.
---
--- The number is unique across the whole store rather than the layers this session can see:
--- reusing one that is alive in a class the reader has not logged puts the collision a login away
--- instead of removing it. The sender's own numbers are no help -- they are unique inside that one
--- string and nowhere else, so two strings waiting at once would both open at 1 and the reader
--- would be shown two unrelated sets under one heading.
---
--- **One call per group, and nothing counts alongside it.** This used to ask once and then walk its
--- own number up, because the answer was the highest key in the store plus one -- and nothing is
--- written until `PlaceImportedActions`, so asking twice mid-walk would have answered the same
--- thing twice. `NextSyntheticKey` is a counter now and hands out a fresh number every time it is
--- asked, which makes the local one a second place keeping the same tally: this batch would take
--- three numbers while the counter moved by one, and the next string to arrive would open on top of
--- it.
---
--- `mapped` is what still has to be remembered here, and it is a different question -- which of the
--- sender's keys have already been given one of ours, so a set that spans four layers stays one set.
local function KeyMapper()
    local mapped = {};

    return function(key)
        local keyType = luatype(key);
        if (keyType ~= "string" and keyType ~= "number") then
            -- No key, or something a key cannot be. Either way it joins no group.
            return nil;
        end

        local synthetic = mapped[key];
        if (not synthetic) then
            synthetic = DebindPrivate.NextSyntheticKey();
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
--- **A line is the dialog's unit and not ours**, so both the list of them and which one an address
--- falls on are read back out of Debind (`ImportUI.lua`), where the words that name them are.
function DebindStorage.PlanImport(payload, options)
    local placements, skipped = {}, 0;
    local lines = options and options.lines;
    local MapKey = KeyMapper();

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
            local line = DebindPrivate.ImportLineFor(listScope, listSpec);
            if (not (line and lines[line])) then
                -- Offered and unticked. That is an answer, not a failure, so it is not counted.
                return;
            end
        end

        for _, source in ipairs(list) do
            local action = BuildAction(source);

            -- **The badge is the key it arrived on**, and `true` when it arrived on none.
            --
            -- **Only its presence is read.** Everything looking at this field asks whether it is set:
            -- the blue name and dot, the [Pending] filter, whether accepting has anything to take off.
            -- The string itself is not printed anywhere yet. `GetKeyDisplayText` takes it as `from`
            -- and does not read it, and what names an unbound set on screen today is its first
            -- action and how many follow (`DebindKeyHeaderMixin:UpdateSummary`).
            --
            -- **Read before the rename, and it is the only chance.** `MapKey` replaces the key with
            -- a number of ours, so after this line the sender's key exists nowhere else.
            --
            -- A number on the wire is the sender's own placeholder, not a key they had, so it
            -- leaves no hint behind - `true` is "arrived, on nothing you can be told about".
            local arrived = action.key;
            action.imported = luatype(arrived) == "string" and arrived or true;

            action.key = MapKey(action.key);
            -- **No key, no number.** The invariant the profile keeps (`ClearActionKey`), held here
            -- as well so a hand-made string cannot walk one in: a number is a place among the
            -- actions sharing a key, and there is no key to be a place in.
            if (action.key == nil) then
                action.seq = nil;
            end
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
--- batch. **Which lines to take is not stored**: that answer is worth exactly one press. Stored on
--- the batch, an answer outlives the moment it was ticked and a reader who came back a week later
--- gets something other than what they asked for -- "leave the keys out" was one of these, before
--- it stopped being a question at all.
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

    local placements, skipped = DebindStorage.PlanImport(payload, options);
    if (#placements == 0) then
        return nil, "NOTHING_TO_PLACE";
    end

    DebindPrivate.PlaceImportedActions(placements);

    return #placements, skipped;
end
