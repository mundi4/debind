local _, DebindShare = ...;

local DebindPrivate = DebindShare.DebindPrivate;
local Constants     = DebindPrivate.Constants;
local luatype       = type;

--- The drawer received strings pile up in, and the work done on them before they become actions.
---
--- **Nothing here touches the profile.** A batch sits outside it until it is committed, which is
--- the decision the design turns on (`devdocs/building-export-import.md`): once actions are in the profile they
--- scatter -- the overview sorts by name, layers split them, and the group identity the string
--- arrived with is held nowhere. So the keys have to be decided while the grouping is still alive,
--- and this is the place that holds it while that happens.
---
--- Which makes this a workbench rather than a shelf. A batch can be opened, half-decided, closed,
--- and picked up again after a `/reload`, so what is stored is not only the string but every
--- decision made about it so far.


--- Bump when a stored batch changes shape. Separate from the string's own two versions
--- (`Export.lua`): those describe someone else's bytes, this describes our drawer.
local STORE_VERSION           = 1;

--- Layer IDs run 1..11 (`LAYER_INFOS` in `Profile.lua`). Holes are normal -- `GetProfileLayer`
--- answers nil for a spec this class does not have.
local MAX_LAYER_ID            = 11;

--- How long a batch sits before it is offered up for deletion. **Not a rule, a default**: the list
--- shows the date it arrived and warns before this runs out, and a batch can be pinned out of it
--- entirely. Nothing is ever removed without having said so first.
local DEFAULT_EXPIRY_SECONDS  = 30 * 24 * 60 * 60;

--- The window in which an expiring batch is called out in the list.
local EXPIRY_WARNING_SECONDS  = 3 * 24 * 60 * 60;


-- ---------------------------------------------------------------------------------------------
-- Source layers
-- ---------------------------------------------------------------------------------------------

--- A payload's layer descriptor, as one string that can be used as a table key.
---
--- The descriptor arrives as a table (`{scope="class", class="DRUID", spec=2}`) and the sender's
--- own copy is **shared between the groups of one layer** -- but only in the sender's memory.
--- Serializing and deserializing is free to hand back a separate table per group, so identity
--- cannot be what says "these two groups came from the same layer". Value has to be.
function DebindShare.LayerKey(descriptor)
    if (luatype(descriptor) ~= "table") then
        return nil;
    end

    local scope = descriptor.scope;
    if (scope == "general") then
        return "general";
    elseif (scope == "class") then
        return "class:" .. tostring(descriptor.class) .. ":" .. tostring(descriptor.spec or 0);
    elseif (scope == "character") then
        return "character:" .. tostring(descriptor.spec or 0);
    end
    return nil;
end

--- The layer in this profile whose scope is `(isCharacterSpecific, spec)`, or nil if this
--- character has no such layer.
---
--- Asked by walking the layers rather than by computing the ID. `GetLayerID` would compute it, but
--- it **asserts** on a spec beyond this class's count -- and a spec beyond this class's count is
--- exactly the ordinary case here, since the string may come from a class with more specs than
--- ours. Reading the layers back also means the arithmetic that maps a scope to an ID lives in one
--- place (`LAYER_INFOS`) rather than being restated here.
local function FindLayerID(isCharacterSpecific, spec)
    for layerID = 1, MAX_LAYER_ID do
        local layer = DebindPrivate.GetProfileLayer(layerID);
        if (layer and (layer.isCharacterSpecific == true) == isCharacterSpecific
                and layer.spec == spec) then
            return layerID;
        end
    end
    return nil;
end

--- Where a source layer lands unless the user says otherwise.
---
--- **The mapping is layer to layer**, not group to layer (`devdocs/building-export-import.md`, the second half
--- of open question 1). One row per source layer decides the destination and every group from that
--- layer follows it. Pulling a single group out to somewhere else is done after committing, in the
--- main window -- the same line the workbench draws around splitting a group.
---
--- Returns nil when nothing can hold it, which the mapping row shows as a destination the user has
--- to choose. Two cases reach that: a spec layer from a class with more specs than ours, and any
--- descriptor a newer schema might invent.
function DebindShare.DefaultDestinationLayerID(descriptor)
    if (luatype(descriptor) ~= "table") then
        return nil;
    end

    local scope = descriptor.scope;
    if (scope == "general") then
        -- The one layer that means the same thing on every account.
        return FindLayerID(false, nil);
    end

    if (scope == "character") then
        -- Character-specific to character-specific. Not "my character is not their character" --
        -- the layer is a scope, and the sender scoped this to one character on purpose.
        return FindLayerID(true, descriptor.spec or 0)
            -- A spec we do not have. Falling back to the character's general layer keeps the
            -- scope and drops only the part of it we cannot represent.
            or FindLayerID(true, 0);
    end

    if (scope == "class") then
        -- **Another class's layer keeps its scope, not its spec.** Spec numbers do not mean the
        -- same thing across classes -- spec 1 is Balance for a druid and Arcane for a mage -- so
        -- carrying the number over would be a guess dressed up as a mapping. The class layer with
        -- no spec is the nearest thing that is actually true: still class-scoped, saying nothing
        -- about which spec.
        if (descriptor.class ~= Constants.PLAYER_CLASS) then
            return FindLayerID(false, 0);
        end
        return FindLayerID(false, descriptor.spec or 0) or FindLayerID(false, 0);
    end

    return nil;
end

--- Order for the mapping rows: general, then class, then character, and by spec inside each. The
--- same order the profile's own layers stand in, so the block reads like the tab strip.
local SCOPE_RANK = { general = 1, class = 2, character = 3 };

--- Every distinct layer the payload's groups came from, in that order.
---
--- One entry per **source** layer, because that is what the user is deciding about. The counts ride
--- along so the row can say how much is behind it -- a mapping decision with no idea of its own
--- size is one the user has to open something else to make.
function DebindShare.CollectSourceLayers(payload)
    local byKey, layers = {}, {};

    for _, group in ipairs(payload.groups or {}) do
        local key = DebindShare.LayerKey(group.layer);
        if (key) then
            local entry = byKey[key];
            if (not entry) then
                entry = {
                    key = key,
                    descriptor = group.layer,
                    groupCount = 0,
                    actionCount = 0,
                };
                byKey[key] = entry;
                layers[#layers + 1] = entry;
            end
            entry.groupCount = entry.groupCount + 1;
            entry.actionCount = entry.actionCount + #(group.actions or {});
        end
    end

    sort(layers, function(lhs, rhs)
        local lhsRank = SCOPE_RANK[lhs.descriptor.scope] or 4;
        local rhsRank = SCOPE_RANK[rhs.descriptor.scope] or 4;
        if (lhsRank ~= rhsRank) then
            return lhsRank < rhsRank;
        end
        -- Own class first among class layers. It is the one with a real mapping; the rest are
        -- someone else's and need a decision.
        local lhsMine = lhs.descriptor.class == Constants.PLAYER_CLASS;
        local rhsMine = rhs.descriptor.class == Constants.PLAYER_CLASS;
        if (lhsMine ~= rhsMine) then
            return lhsMine;
        end
        if (lhs.descriptor.class ~= rhs.descriptor.class) then
            return tostring(lhs.descriptor.class) < tostring(rhs.descriptor.class);
        end
        return (lhs.descriptor.spec or 0) < (rhs.descriptor.spec or 0);
    end);

    return layers;
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

        -- The work. Empty means "nothing decided yet", which is not the same as "decided to leave
        -- it alone" only for keys -- see `Import.lua` when it exists.
        layers = {},
        keys = {},
        excluded = {},
        states = {},
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
