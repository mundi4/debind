local _, DebindStorage = ...;

local luatype   = type;

--- How many specializations this character's class has. Read here rather than asked of
--- `GetLayerID`, which **asserts** on a spec beyond that count -- and a spec beyond that count is
--- ordinary input, since the string may come from a class with more specs than ours.
local NUM_SPECS = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));

--- The drawer received strings pile up in, and what has to be known about one before it becomes
--- actions: where each of its layers lands, and which of them the reader is offered.
---
--- **Nothing here touches the profile.** A batch sits outside it until it is brought in, which is
--- the decision the design turns on (`devdocs/building-export-import.md`): once actions are in the
--- profile they scatter -- the overview sorts by name, layers split them -- so what arrived
--- together has to keep saying so, and the key is what carries it across.


--- Bump when a stored batch changes shape. Separate from the string's own two versions
--- (`Export.lua`): those describe someone else's bytes, this describes our drawer.
local STORE_VERSION           = 1;

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
--- **The design is not rejected, it is unbuilt.** A drawer of received strings does grow, and the
--- one thing it may not do is let one vanish without having said so - which is why the answer is a
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
-- The lines the reader is offered
-- ---------------------------------------------------------------------------------------------

--- What the bring dialog puts a checkbox on, in the order the window's own tab strip stands in.
---
--- **Four lines, not one per layer.** The spec layers ride along on the line above them rather than
--- standing on their own: a string from a four-spec class would otherwise open with ten rows, and
--- ticking spec 3 but not spec 2 is a decision nobody arrives wanting to make. What is worth
--- separating is the two things that differ in *who they reach* -- everything on this account
--- versus this one character.
DebindStorage.IMPORT_LINES      = {
    "shared.general",
    "shared.class",
    "character.general",
    "character.spec",
};

--- Which line an address belongs to, or nil for one no line covers.
function DebindStorage.ImportLineFor(scope, spec)
    if (scope == "general") then
        return "shared.general";
    elseif (scope == "class") then
        return "shared.class";
    elseif (scope == "character") then
        return (spec or 0) > 0 and "character.spec" or "character.general";
    end
    return nil;
end

--- Which of the four lines this payload actually has something on, in `IMPORT_LINES` order.
---
--- **Only what can land counts.** A line the string does not carry, and a line whose every action
--- has nowhere to go, are the same thing to the reader: a checkbox that reads as a choice and does
--- nothing either way. A payload with no line at all is one there is no question to ask about.
---
--- **Counted over actions, not groups.** A group is a key now and a key crosses layers, so one
--- group can put actions on two lines and there is no number of groups a line owns.
---
--- `class` rides along on the class line, taken from the descriptors rather than from
--- `payload.class`: the label has to name the class the actions are actually going to. It is absent
--- when the line holds more than one, which the export cannot produce and a hand-made string can.
function DebindStorage.CollectImportLines(payload)
    local counts, classLine = {}, nil;

    DebindStorage.ForEachPayloadLayer(payload, function(list, scope, class, spec)
        -- **The address is vetted first**, the same order `PlanImport` reads them in. `ImportAddress`
        -- is the only place `spec` is checked for being a number at all, and the line function
        -- compares it against 0 -- asked the other way round, a payload keyed `char = { ["2"] = … }`
        -- raises where the reader can only see a dead button.
        if (DebindStorage.ImportAddress(scope, class, spec)) then
            local line = DebindStorage.ImportLineFor(scope, spec);
            if (line) then
                counts[line] = (counts[line] or 0) + #list;
                if (line == "shared.class") then
                    if (classLine == nil) then
                        classLine = class;
                    elseif (classLine ~= class) then
                        classLine = false;
                    end
                end
            end
        end
    end);

    local lines = {};
    for _, line in ipairs(DebindStorage.IMPORT_LINES) do
        -- **Zero is not "some".** An empty layer list adds nothing to the count, and `if (count)`
        -- would stand the checkbox up anyway -- 0 is true in Lua. The reader would tick a line that
        -- places nothing and be answered with an error by the dialog that just offered it.
        if ((counts[line] or 0) > 0) then
            lines[#lines + 1] = {
                line = line,
                actionCount = counts[line],
                class = line == "shared.class" and classLine or nil,
            };
        end
    end
    return lines;
end


-- ---------------------------------------------------------------------------------------------
-- The drawer
-- ---------------------------------------------------------------------------------------------

--- `DebindStorageVars`, made if it is not there yet.
---
--- Built on demand rather than from an `ADDON_LOADED` handler. Nothing in this addon runs before
--- the window is opened -- that is the whole reason it is `LoadOnDemand` -- so there is no earlier
--- moment for a handler to be the right answer to.
local function Vars()
    local vars = _G.DebindStorageVars;
    if (not vars) then
        vars = {};
        _G.DebindStorageVars = vars;
    end
    vars.version = vars.version or STORE_VERSION;
    vars.batches = vars.batches or {};
    vars.nextID = vars.nextID or 1;
    return vars;
end

--- **The string is what is stored, not the payload it decodes to.** The string is already
--- compressed -- three hundred actions is about 1.4 KB -- while the table it becomes is the same
--- data spelled out in full. Keeping the table would undo the reason this addon was split off, and
--- it would also throw away the one thing worth keeping if a future version cannot read the string
--- any more: the string itself, which the user can still copy back out.
---
--- Decoding is done when a batch is opened and the result is kept in memory only.
local decoded = {};

--- The payload of a stored batch, or nil plus the reason `DecodeExportString` gave.
function DebindStorage.GetBatchPayload(batch)
    local cached = decoded[batch.id];
    if (cached) then
        return cached;
    end

    local payload, reason = DebindStorage.DecodeExportString(batch.text);
    if (not payload) then
        return nil, reason;
    end

    decoded[batch.id] = payload;
    return payload;
end

--- Takes a pasted string into the drawer.
---
--- **Decoded before it is stored**, so a string that cannot be read is refused where the user is
--- looking at it rather than becoming a row in the drawer that fails every time it is opened.
--- Returns the batch, or nil plus the same reason codes `DecodeExportString` uses.
function DebindStorage.AddBatch(text, source)
    local payload, reason = DebindStorage.DecodeExportString(text);
    if (not payload) then
        return nil, reason;
    end

    -- **Counted once, here.** Drawing the drawer needs to say how much is in each row, and
    -- decoding every stored string to answer that would undo storing strings in the first place.
    -- They are known at this moment for free, and a batch's contents never change afterwards.
    --
    -- **A key is a group**, so counting the distinct keys is counting the groups. An action with no
    -- key at all is in nobody's, and adds to neither count but the total.
    local groupCount, actionCount = 0, 0;
    -- **Whether there is a key in here at all**, counted at the same moment for the same reason.
    -- The drawer offers to leave the keys out on the way in, and that control has nothing to switch
    -- off for a string the sender already sent without them. Answering it later would mean decoding
    -- the string to draw a row.
    --
    -- **A real key is a string; a synthetic one is a number** (`Export.lua`), so the type is the
    -- whole question -- a string sent with the keys left out carries a key on every action and
    -- still has none to offer.
    local hasKeys, seenKeys = false, {};
    DebindStorage.ForEachPayloadLayer(payload, function(list)
        for _, action in ipairs(list) do
            actionCount = actionCount + 1;
            local key = action.key;
            if (key ~= nil and not seenKeys[key]) then
                seenKeys[key] = true;
                groupCount = groupCount + 1;
            end
            if (luatype(key) == "string") then
                hasKeys = true;
            end
        end
    end);

    local vars = Vars();
    local batch = {
        id = vars.nextID,
        received = time(),
        -- Stored trimmed: a paste out of a chat window can carry whitespace, and the stored copy
        -- is the one the user may later copy back out.
        text = strtrim(text),
        -- Whoever it came from, when the paste knows. Free text and purely for the list -- nothing
        -- reads it back.
        source = source,
        -- The sender's class, which is the only thing about them the string itself carries.
        class = payload.class,
        groupCount = groupCount,
        actionCount = actionCount,
        -- **Stored as `false`, not folded to nil.** The drawer tells three states apart: it has
        -- keys, it has none, and it was stored before this field existed. Only `false` means the
        -- second, so `or nil` here would make a keyless batch look like an old one and put a
        -- control on it with nothing to switch off.
        hasKeys = hasKeys,

        -- **No decisions are kept here.** There used to be four empty tables in this spot
        -- (`layers`, `keys`, `excluded`, `states`), waiting for a workbench that was folded, and
        -- `stripKeys` did get written for a while. It outlived the moment it was ticked: a reader
        -- who came back a week later pressed [Bring it in] and got something they had not asked
        -- for. Everything that is decided now is decided in the dialog that press opens and is
        -- over when the press is (`WorkbenchUI.lua`).
        --
        -- Batches saved before this still carry those fields. Nothing reads them and nothing has
        -- to: dropping a stale field would mean a store version and a migration for values that
        -- were never anything but empty.
    };

    vars.nextID = vars.nextID + 1;
    vars.batches[#vars.batches + 1] = batch;
    decoded[batch.id] = payload;

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
            decoded[id] = nil;
            return true;
        end
    end
    return false;
end

