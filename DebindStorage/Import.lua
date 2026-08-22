local _, DebindStorage = ...;

local DebindPrivate = DebindStorage.DebindPrivate;
local Constants     = DebindPrivate.Constants;
local luatype       = type;

--- How many specializations this character's class has. Read here rather than asked of
--- `GetLayerID`, which **asserts** on a spec beyond that count -- and a spec beyond that count is
--- ordinary input, since the string may come from a class with more specs than ours.
local NUM_SPECS = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));

--- The receiving end: a pasted string waits until the reader says to bring it in, and then becomes
--- actions in the profile. The reverse of `Export.lua`, and only that. Deciding *which* entry to
--- commit, and what to do with the result afterwards, belongs to the window and to the main
--- window's Overview.
---
--- **An entry is outside the profile until it is committed**, which is the decision the design turns
--- on (`devdocs/building-export-import.md`): once actions are in the profile they scatter -- the
--- overview sorts by name, layers split them -- so what arrived together has to keep saying so, and
--- the key is what carries it across.
---
--- **Everything that lands is quarantined.** Each action carries `arrivalID`, and while that is set
--- `BuildKeyMap` skips it: the actions are in the profile, drawn and editable, and reach no key
--- until the reader takes the badge off. So committing never changes what any key does, which is
--- what lets it run without asking anything first - **even though each of them keeps the key it was
--- sent on**, which is routinely one the reader already uses
--- (`devdocs/building-export-import.md` 12절).


--- The shape of a stored **entry** -- the record below, not the payload inside it.
---
--- **Two shapes sit in one row and each has its own number.** `payload.v` says what the payload is,
--- and that number belongs to the wire: it moves when a string's shape moves, and the reader it
--- answers to is somebody holding a string an older version wrote (`Export.lua`). This one says
--- what the row around that payload is, and nothing outside this addon ever sees it.
---
--- **Keeping them apart is what lets either move alone.** Folded into one, a change to the record
--- here would have to move the wire number, and every string sitting in somebody else's notes would
--- be turned away for a change that never left this disk.
---
--- **A field added is not a bump** - the rule `SCHEMA_VERSION` states, for the same reason: a reader
--- that skips what it does not know survives an addition on its own. That is what the three an
--- entry made from a profile carries are. A row without them is a row that came from a string,
--- which is exactly what their absence should mean.
---
--- It was called `STORE_VERSION` and its comment said "bump when a stored entry changes shape",
--- which is why it got bumped for something that is not a shape change at all: keeping the payload
--- instead of the string it arrived in. **The same payload either way** - compressed in a `text`
--- field or sitting there decoded - so nothing about the serialized shape moved. What moved was
--- where it lived.
local ENTRY_VERSION             = 1;

--- The highest spec number the profile has a place for (`LAYER_INFOS` in `Profile.lua` runs each
--- block from 0 to 4). A descriptor naming a spec past this is not a spec we cannot represent, it
--- is a number no client produces -- so it is refused rather than folded to something nearby.
local MAX_SPEC                = 4;

--- The class names this client has (`Constants.CLASS_IDS`, keyed by `classFile`).
---
--- **A descriptor's class is a key straight into storage** (`shared.classes[class]`), so one that
--- names no class would stand up a table no screen can reach and nothing ever clears -- `CleanUpDB`
--- walks the eleven loaded layers and would never see it. Every paste of a made-up name would grow
--- the account file by another one.
---
--- Only presence is read here. The value is the class id, which is what a caller that has to
--- **name** something needs (`LayerDisplay.lua`) -- the same table answering both is why the loop
--- that built it is not written out here any more.
local KNOWN_CLASSES           = Constants.CLASS_IDS;

--- **There is no expiry.** Two constants and two functions stood here, and a pin on the row to
--- opt out of them: an entry was judged old after a month and called out three days before, and
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
---
--- **The stored list comes last, and only one caller takes it.** Everything that reads a payload
--- wants the filtered copy; the one that *edits* one has to reach the table the payload actually
--- holds (`RemoveEntryAction`). Handing it over here rather than walking the three addresses again
--- is what keeps the shape of a payload written down once.
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
        fn(actions, scope, class, spec, list);
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
    -- through placing an entry. `spec ~= floor(spec)` is false for both a fraction and an infinity,
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
--- raised halfway through `PlaceArrivedActions`, `priority = {}` raised inside the `table.sort`
--- that follows, `units = "x"` was walked with `pairs`. Every one of those went off after
--- part of the entry was already in the profile. The types are `ACTION_FIELDS`' values.
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
--- exported from -- and `ImportEntry` turns the **whole string** away on it
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
---   * a `key` of NaN raises the moment it is used as a table index, which the count below does.
---     `ImportAddress` turns the same value away for `spec` and says why.
---
--- Neither needs its own guard downstream now, because nothing downstream runs on a payload this
--- refuses -- `ImportEntry` asks before it stores, and an entry is the only way in.
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
-- Stored entries
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
    vars.version = vars.version or ENTRY_VERSION;
    vars.entries = vars.entries or {};
    vars.nextID = vars.nextID or 1;

    return vars;
end

--- The payload of a stored entry, or nil plus the reason it could not be read.
---
--- **The payload is what is stored, not the string it came in.** Four reasons for keeping the
--- string were written down and all four turned out to be true of both shapes
--- (`devdocs/building-export-import.md`). What decided it points the other way: `DecodeExportString`
--- refuses a string outright once its schema has moved, so stored strings are stored values nothing
--- can bring forward, while a payload can be walked the way `Profile.lua` walks `dbver`. What is
--- left over is disk size, and holding a smaller thing we cannot read is the worse end of that
--- trade.
---
--- **The gate `ImportEntry` stands is stood again here.** An entry that got in before the gate existed
--- is closed by this one, which is why the gate needs nothing rewritten behind it -- there is only
--- something to refuse. **Everything that reads a payload for its contents comes through here**, so
--- past this line it is one of ours.
---
--- Two callers read `entry.payload` without asking: `CountEntry` and `EntryClassText`
--- (`StorageUI.lua`). Both draw the row rather than act on it, and a row has to be drawable for a
--- entry that this refuses -- deleting it is the only thing left to do with it, and the delete
--- button is on the row. So they guard the one field they touch and read nothing else.
---
--- **The schema is asked first, and it is asked for the same reason.** `ImportEntry` asks it of a
--- string through `DecodeExportString`; this asks it of a payload that has been sitting in
--- SavedVariables since some earlier version. The two questions used to be one door apart: what is
--- pasted was asked and what is stored was not, so the entries most likely to be old were the ones
--- nothing asked. It answers the same thing on every payload there is today, and stops doing so the
--- day a schema step is written -- which is what `BringPayloadForward` is for, and why it comes
--- before the check below rather than after. `PayloadIsImpossible` reads fields whose meaning the
--- schema decides, so asking it about a payload of an unknown schema is asking the wrong question.
function DebindStorage.GetEntryPayload(entry)
    local payload, reason = DebindStorage.BringPayloadForward(entry.payload);
    if (not payload) then
        return nil, reason;
    end

    if (DebindStorage.PayloadIsImpossible(payload)) then
        return nil, "IMPOSSIBLE_PAYLOAD";
    end

    return payload;
end

--- How many groups and how many actions an entry holds.
---
--- **Counted on the spot rather than written down when the entry was made.** Both numbers were
--- fields on the record while the string was what got stored, because answering them any other way
--- meant decoding every row of the list to draw it. The payload is right there now, so a stored
--- copy would only be a second place for the same fact to live.
---
--- **A key is a group**, so counting the distinct keys is counting the groups. An action with no
--- key at all is in nobody's, and adds to the total but to no group.
function DebindStorage.CountEntry(entry)
    local groupCount, actionCount = 0, 0;
    if (not entry.payload) then
        return groupCount, actionCount;
    end

    local seenKeys = {};
    DebindStorage.ForEachPayloadLayer(entry.payload, function(list)
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

--- Seats a payload in the store and hands back the row it became.
---
--- **Both ways in end here**, so an entry made from this profile and one pasted out of a string are
--- the same kind of thing from the moment they exist. What separates them is what `extra` carries,
--- and that is three fields about where it came from.
---
--- **The automatic backup is why this is one door rather than two.** A backup is an entry made from
--- the profile and restoring one is pressing the same button any other row has, so there is nothing
--- for it to have of its own (`devdocs/building-export-import.md`). A branch built for backups
--- would be code no ordinary press ever walks, and code nothing walks is code nothing has checked.
local function StoreEntry(payload, extra)
    local vars = Vars();
    local entry = extra or {};

    entry.id = vars.nextID;
    -- **When this row appeared here**, which is what the list sorts and dates by. For a pasted
    -- string that is when it was pasted; for one made here it is when it was made. What it is not
    -- is when the setting it holds was *exported* -- a string carries nothing about its sender but
    -- their class, so that is a second question with no answer on the wire yet
    -- (`devdocs/building-export-import.md`).
    entry.received = time();
    -- **What arrived, not the string it arrived in.** The string is not kept: nothing reads it
    -- back, and a copy of the same contents in a form we may one day be unable to decode is worth
    -- less than the payload beside it (`GetEntryPayload`).
    entry.payload = payload;

    vars.nextID = vars.nextID + 1;
    vars.entries[#vars.entries + 1] = entry;

    return entry;
end

--- Takes a pasted string in and keeps it as an entry.
---
--- **Decoded before it is stored**, so a string that cannot be read is refused where the user is
--- looking at it rather than becoming an entry that fails every time it is opened.
--- Returns the entry, or nil plus the same reason codes `DecodeExportString` uses, plus
--- `IMPOSSIBLE_PAYLOAD` for the check below.
---
--- **`name` is what the reader chose to call it.** Free text, optional, purely for the list --
--- nothing reads it back. It asked who the string came from once: nothing *sends* a string, it is
--- copied off a page or out of a notes file, and the reader restoring their own backup had no
--- answer to give, so the field stayed empty exactly where a name would have been most use.
---
--- **Nothing about the sender lands here.** A row made from a profile carries three fields saying
--- whose it is (`CreateEntry`), and a pasted one has none of them -- deliberately, since a string
--- meant for a public channel does not carry a character name. Their absence is what says this came
--- from somebody else.
function DebindStorage.ImportEntry(text, name)
    local payload, reason = DebindStorage.DecodeExportString(text);
    if (not payload) then
        return nil, reason;
    end

    -- **Asked before anything is stored, and before anything below reads a value.** Everything
    -- from here on treats the payload as one of ours.
    if (DebindStorage.PayloadIsImpossible(payload)) then
        return nil, "IMPOSSIBLE_PAYLOAD";
    end

    return StoreEntry(payload, { name = name });
end

--- Makes an entry out of this character's profile and keeps it.
---
--- `selection` is a set of action tables, or nil for the whole profile. **The button that makes one
--- passes nil**: there is no screen for picking first, because everything a profile holds is
--- already the answer and asking would put a step in front of the one press. Narrowing is what the
--- entry itself is for afterwards -- a row can have actions deleted out of it, and what gets handed
--- out is ticked at the moment it is handed out (`FilterPayload`). The one caller that does pass a
--- set is the key group shortcut, which has a range in its hand already.
---
--- **Badged actions are left out**, by `BuildExportPayload` asking `IsExportable`. So a fresh entry
--- never shows a blue row: what is in it is what this reader has approved, which is also what makes
--- it worth anything as a backup -- the thing a key group operation can take away is an approved
--- action, and a badged one still has its own entry sitting in the list to be added again.
---
--- **The three fields are only on rows made here**, and they answer three questions: which
--- character a row in the list belongs to, what to call an automatic backup, and whether this is
--- the reader's own backup rather than somebody else's setting. That last one is the axis the
--- custom-state question could never be decided on, because nothing on the wire tells the two apart
--- (`devdocs/building-export-import.md`).
---
--- **They are outside the payload**, which is what keeps them off the wire. A string is made by
--- encoding `entry.payload`, so there is no step that has to remember to drop them and no way for a
--- later edit to forget.
function DebindStorage.CreateEntry(selection)
    return StoreEntry(DebindStorage.BuildExportPayload(selection), {
        character = UnitName("player"),
        realm = GetRealmName(),
        guid = DebindPrivate.playerGUID,
    });
end

--- Takes a set of actions out of an entry, for good. Answers how many it found.
---
--- **The one edit an entry has** (`devdocs/building-export-import.md` 12절). Adding, reordering and
--- changing an action are all absent and each for its own reason; what is left is throwing part of
--- it away, and that exists because making an entry takes the whole profile -- eleven layers of it,
--- with no screen in front to pick from -- so a reader who wants to hand over one part has to be
--- able to cut the rest out of the copy.
---
--- **A set rather than one action, because the panel already has a set.** The ticks are a
--- multi-selection the reader made for the other two verbs, and a second selection state alongside
--- it is the thing the overview turned down once already for having no answer to when it clears.
---
--- **It does not come back.** Unlike a tick, which is a different answer every time the entry is
--- used, this is the entry changing: the profile is still there and the string was already made, so
--- the way back is another entry rather than an undo of this one.
---
--- **The stored lists, not the copies `ForEachPayloadLayer` hands out.** Removing from a copy would
--- report success and change nothing.
---
--- An emptied list goes with its actions. A payload carrying `char = { [0] = {} }` claims a layer
--- it has nothing for, and everything downstream would have to know an address can be empty -- the
--- preview would draw a header over nothing and `PlanArrival` would offer somewhere to put it.
---
--- **The manifest is left alone.** It says which switches the entry referred to when it was made,
--- and a definition nothing points at costs a reader nothing: `FilterPayload` narrows it to what is
--- actually going out at the moment a string is made, which is the only moment it matters.
function DebindStorage.RemoveEntryActions(entry, actions)
    local payload = entry and entry.payload;
    if (luatype(payload) ~= "table" or luatype(actions) ~= "table") then
        return 0;
    end

    local removed = 0;

    DebindStorage.ForEachPayloadLayer(payload, function(_, scope, class, spec, list)
        local took = 0;
        -- Backwards, because removing shifts everything above the index down.
        for i = #list, 1, -1 do
            if (actions[list[i]]) then
                tremove(list, i);
                took = took + 1;
            end
        end
        removed = removed + took;

        -- **Only a layer this emptied.** A payload that arrived holding an empty list is left as it
        -- arrived: tidying one nobody touched would make an untouched entry change on a press that
        -- did nothing to it.
        if (took == 0 or #list > 0) then
            return;
        end

        if (scope == "general") then
            payload.shared.GENERAL = nil;
        elseif (scope == "class") then
            payload.shared.classes[class][spec] = nil;
            if (next(payload.shared.classes[class]) == nil) then
                payload.shared.classes[class] = nil;
            end
        else
            payload.char[spec] = nil;
        end
    end);

    return removed;
end

function DebindStorage.GetEntries()
    return Vars().entries;
end

function DebindStorage.GetEntry(id)
    local entries = Vars().entries;
    for i = 1, #entries do
        if (entries[i].id == id) then
            return entries[i];
        end
    end
    return nil;
end

function DebindStorage.DeleteEntry(id)
    local entries = Vars().entries;
    for i = 1, #entries do
        if (entries[i].id == id) then
            tremove(entries, i);
            return true;
        end
    end
    return false;
end

-- ---------------------------------------------------------------------------------------------
-- The whole entry
-- ---------------------------------------------------------------------------------------------

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
--- **Every action keeps the key it was sent on, and the badge is what holds it back.** The badge is
--- `arrivalID`, one number for this whole call, and while it is set the action is in the profile and
--- reaches no key (`BuildKeyMap`). With `key` it is also which group the action lands in, so an
--- arrival that came in on a key the reader already uses stands under its own heading rather than
--- merging into theirs (`devdocs/building-export-import.md` 12절).
---
--- There used to be a rename here instead: the key was replaced with a number of ours, so that
--- landing on a key the reader used could not become a merge they cannot undo. The pair does that
--- job now without taking the key away, and what the rename cost is in the same 12절.
---
--- `options.keepKeys` leaves the badge off, which is the accepted-on-arrival verb: the actions land
--- live, on the keys they were sent on.
---
--- `options.selection` is a set of the payload's action tables to take, or nil for all of them.
--- **Unticked is not skipped** -- that is an answer the reader gave, where `skipped` counts what
--- this version had nowhere to put. Both end up absent and only one of them is worth saying out
--- loud.
---
--- **The tick is on an action because that is where the preview puts it.** It used to be on a line
--- -- four of them, one per place a payload could land, offered by a dialog the press opened. The
--- preview column replaced both: a reader looking at the actions themselves has no reason to be
--- asked about the layers first, and the answer is no longer worth a window of its own
--- (`devdocs/building-export-import.md` 12절).
function DebindStorage.PlanArrival(payload, options)
    local placements, skipped = {}, 0;
    local selection = options and options.selection;
    local keepKeys = options and options.keepKeys;
    -- **One number for the whole call**, because one call is one arrival. Every action of it lands
    -- badged with the same value, which is what keeps a set that spans four layers one set.
    --
    -- **Asked for lazily.** A plan that places nothing spends no number, and `keepKeys` never asks
    -- at all. The counter only ever counts up, so a plan that is built and then thrown away costs
    -- nothing but a gap.
    local arrivalID;

    DebindStorage.ForEachPayloadLayer(payload, function(list, listScope, listClass, listSpec)
        -- **Asked for an address first, and the reader's answer second.** Every action with nowhere
        -- to go is counted whatever the tick says: what has no address was never drawn for them to
        -- turn down, so reading the filter first would make those vanish silently - the window
        -- saying "brought in 2" and never mentioning the five that did not fit.
        local scope, class, spec = DebindStorage.ImportAddress(listScope, listClass, listSpec);
        if (not scope) then
            skipped = skipped + #list;
            return;
        end

        for _, source in ipairs(list) do
            -- Unticked is offered and turned down, which is an answer rather than a failure, so it
            -- is passed over rather than counted.
            if (not selection or selection[source]) then
                local action = BuildAction(source);

                -- **The badge, unless the reader asked for these live.** Nothing else is done to the
                -- key: it is the sender's, it is a real key, and it is half of the group this action
                -- lands in.
                if (not keepKeys) then
                    arrivalID = arrivalID or DebindPrivate.NextArrivalID();
                    action.arrivalID = arrivalID;
                end

                -- **No key, no number.** The invariant the profile keeps (`ClearActionKey`), held
                -- here as well so a hand-made string cannot walk one in: a number is a place among
                -- the actions sharing a key, and there is no key to be a place in.
                if (action.key == nil) then
                    action.seq = nil;
                end

                placements[#placements + 1] = {
                    scope = scope, class = class, spec = spec, action = action,
                };
            end
        end
    end);

    return placements, skipped;
end

--- Commits an entry into the profile, badged.
---
--- `options` is `PlanArrival`'s, and comes from the dialog the press opened rather than from the
--- entry. **Which lines to take is not stored**: that answer is worth exactly one press. Stored on
--- the entry, an answer outlives the moment it was ticked and a reader who came back a week later
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
function DebindStorage.CommitEntry(entry, options)
    local payload, reason = DebindStorage.GetEntryPayload(entry);
    if (not payload) then
        return nil, reason;
    end

    local placements, skipped = DebindStorage.PlanArrival(payload, options);
    if (#placements == 0) then
        return nil, "NOTHING_TO_PLACE";
    end

    DebindPrivate.PlaceArrivedActions(placements);

    return #placements, skipped;
end
