local _, DebindShare = ...;

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
--- together has to keep saying so, and `importGroup` is what carries it across.


--- Bump when a stored batch changes shape. Separate from the string's own two versions
--- (`Export.lua`): those describe someone else's bytes, this describes our drawer.
local STORE_VERSION           = 1;

--- The highest spec number the profile has a place for (`LAYER_INFOS` in `Profile.lua` runs each
--- block from 0 to 4). A descriptor naming a spec past this is not a spec we cannot represent, it
--- is a number no client produces -- so it is refused rather than folded to something nearby.
local MAX_SPEC                = 4;

--- How long a batch sits before it is offered up for deletion. **Not a rule, a default**: the list
--- shows the date it arrived and warns before this runs out, and a batch can be pinned out of it
--- entirely. Nothing is ever removed without having said so first.
local DEFAULT_EXPIRY_SECONDS  = 30 * 24 * 60 * 60;

--- The window in which an expiring batch is called out in the list.
local EXPIRY_WARNING_SECONDS  = 3 * 24 * 60 * 60;


-- ---------------------------------------------------------------------------------------------
-- Source layers
-- ---------------------------------------------------------------------------------------------

--- Where a source layer lands, as the address the profile actually stores things under.
---
--- Returns `scope, class, spec` -- the same three the profile is keyed by (`shared.GENERAL`,
--- `shared.classes[class][spec]`, `characters[guid].layers[spec]`) -- or nil.
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
function DebindShare.ImportAddress(descriptor)
    if (luatype(descriptor) ~= "table") then
        return nil;
    end

    local scope = descriptor.scope;
    if (scope == "general") then
        return "general";
    end

    local spec = descriptor.spec or 0;
    if (luatype(spec) ~= "number" or spec < 0 or spec > MAX_SPEC) then
        return nil;
    end

    if (scope == "class") then
        if (luatype(descriptor.class) ~= "string") then
            return nil;
        end
        return "class", descriptor.class, spec;
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
DebindShare.IMPORT_LINES      = {
    "shared.general",
    "shared.class",
    "character.general",
    "character.spec",
};

--- Which line a layer descriptor belongs to, or nil for one no line covers.
---
--- **Derived from the descriptor's value, never its identity.** The sender shares one descriptor
--- table between the actions of a layer, but that is only true in the sender's memory --
--- serializing and deserializing is free to hand back a separate table per action, and then
--- identity says every action came from a layer of its own.
function DebindShare.ImportLineFor(descriptor)
    if (luatype(descriptor) ~= "table") then
        return nil;
    end

    local scope = descriptor.scope;
    if (scope == "general") then
        return "shared.general";
    elseif (scope == "class") then
        return "shared.class";
    elseif (scope == "character") then
        return (descriptor.spec or 0) > 0 and "character.spec" or "character.general";
    end
    return nil;
end

--- Which of the four lines this payload actually has something on, in `IMPORT_LINES` order.
---
--- Lines with nothing behind them are left out. A checkbox for a layer the string does not carry
--- reads as a choice, and unticking it would do exactly nothing.
---
--- **Counted over actions, not groups.** A group is a key now and a key crosses layers, so one
--- group can put actions on two lines and there is no number of groups a line owns.
function DebindShare.CollectImportLines(payload)
    local counts = {};

    for _, group in ipairs(payload.groups or {}) do
        for _, action in ipairs(group.actions or {}) do
            local line = DebindShare.ImportLineFor(action.layer);
            if (line) then
                counts[line] = (counts[line] or 0) + 1;
            end
        end
    end

    local lines = {};
    for _, line in ipairs(DebindShare.IMPORT_LINES) do
        if (counts[line]) then
            lines[#lines + 1] = { line = line, actionCount = counts[line] };
        end
    end
    return lines;
end


-- ---------------------------------------------------------------------------------------------
-- The drawer
-- ---------------------------------------------------------------------------------------------

--- `DebindShareVars`, made if it is not there yet.
---
--- Built on demand rather than from an `ADDON_LOADED` handler. Nothing in this addon runs before
--- the window is opened -- that is the whole reason it is `LoadOnDemand` -- so there is no earlier
--- moment for a handler to be the right answer to.
local function Vars()
    local vars = _G.DebindShareVars;
    if (not vars) then
        vars = {};
        _G.DebindShareVars = vars;
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
function DebindShare.GetBatchPayload(batch)
    local cached = decoded[batch.id];
    if (cached) then
        return cached;
    end

    local payload, reason = DebindShare.DecodeExportString(batch.text);
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
function DebindShare.AddBatch(text, source)
    local payload, reason = DebindShare.DecodeExportString(text);
    if (not payload) then
        return nil, reason;
    end

    -- **Counted once, here.** Drawing the drawer needs to say how much is in each row, and
    -- decoding every stored string to answer that would undo storing strings in the first place.
    -- They are known at this moment for free, and a batch's contents never change afterwards.
    local groupCount, actionCount = #(payload.groups or {}), 0;
    -- **Whether there is a key in here at all**, counted at the same moment for the same reason.
    -- The drawer offers to leave the keys out on the way in, and that control has nothing to switch
    -- off for a string the sender already sent without them. Answering it later would mean decoding
    -- the string to draw a row.
    local hasKeys = false;
    for _, group in ipairs(payload.groups or {}) do
        actionCount = actionCount + #(group.actions or {});
        if (group.key ~= nil) then
            hasKeys = true;
        end
    end

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

function DebindShare.GetBatches()
    return Vars().batches;
end

function DebindShare.GetBatch(id)
    local batches = Vars().batches;
    for i = 1, #batches do
        if (batches[i].id == id) then
            return batches[i];
        end
    end
    return nil;
end

function DebindShare.DeleteBatch(id)
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

--- Seconds until this batch is old enough to be swept, or nil if it is pinned.
---
--- Negative means it is already past. The list shows this rather than acting on it: a batch that
--- disappeared without the user having been told it was going to is the one outcome the drawer is
--- not allowed to produce.
function DebindShare.GetSecondsUntilExpiry(batch)
    if (batch.pinned) then
        return nil;
    end
    return (batch.received + DEFAULT_EXPIRY_SECONDS) - time();
end

function DebindShare.IsExpiringSoon(batch)
    local remaining = DebindShare.GetSecondsUntilExpiry(batch);
    return remaining ~= nil and remaining <= EXPIRY_WARNING_SECONDS;
end
