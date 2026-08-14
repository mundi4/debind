local _, DebindShare = ...;

local DebindPrivate = DebindShare.DebindPrivate;
local Constants     = DebindPrivate.Constants;
local luatype       = type;

--- Turning a received payload into actions in the profile.
---
--- **Everything that lands here is quarantined.** Each action carries `imported`, and while that is
--- set `BuildKeyMap` skips it: the string is in the profile, drawn and editable, and reaches no key
--- until the reader takes the badge off. So this function never changes what any key does, which is
--- what lets it run without asking anything first.
---
--- The reverse of `Export.lua`, and only that. Deciding *which* batch to commit, and what to do
--- with the result afterwards, belongs to the window and to the main window's Overview.

--- The wire says `{mode = "toggle", state = "$state3"}`; the profile stores one number with the
--- mode in the high bits and the state index in the low nibble. Names travel because an index is a
--- reference that always resolves and resolves to the wrong state (`Export.lua`).
local SETSTATE_MODE_FLAGS = {
    on = Constants.SETCUSTOM_MODE_ON,
    off = Constants.SETCUSTOM_MODE_OFF,
    toggle = Constants.SETCUSTOM_MODE_TOGGLE,
};


-- ---------------------------------------------------------------------------------------------
-- One action
-- ---------------------------------------------------------------------------------------------

--- Does this account or character have the very macro this action was pointing at?
---
--- **All three have to match: name, scope and body.** Name alone is what makes a macro reference
--- the one kind of breakage red text cannot see - a reader with a different macro of the same name
--- gets theirs, silently, and nothing anywhere says so. Comparing the body is what turns that from
--- a silent wrong answer into a fallback.
---
--- Matching means the reference comes back alive, which is what makes re-importing your own backup
--- give you back a `MACRO` rather than a flattened copy of its text.
local function MacroMatches(snapshot)
    if (luatype(snapshot) ~= "table" or not snapshot.name) then
        return false;
    end

    local name, _, body = GetMacroInfo(snapshot.name);
    if (not name or body ~= snapshot.body) then
        return false;
    end

    -- Scope is read the way the export read it: account macros hold the first block of slots.
    local index = GetMacroIndexByName(snapshot.name);
    if (not index or index <= 0) then
        return false;
    end
    local accountLimit = DebindPrivate.GetMacroSlotLimits();
    local scope = index > accountLimit and "character" or "account";
    return scope == snapshot.scope;
end

--- A wire action turned into a profile action.
---
--- Fields arrive already filtered by the export's whitelist, so they are copied as they come. What
--- needs undoing is the two things the format deliberately said differently, plus the macro
--- decision above.
local function BuildAction(source)
    local action = {};
    for k, v in pairs(source) do
        -- `macro`, `setstate` and `order` are the format's, not the profile's. They are read below
        -- and do not travel any further; `CleanUpDB` would drop them anyway, but leaving them for
        -- it to find would mean the action is briefly a shape nothing else expects.
        --
        -- **This loop is a blacklist**, so a wire field nobody names here rides straight into the
        -- profile. That is why the order is not sent as `seq`: under that name it would land on the
        -- action and collide with the numbers the receiving layer has already handed out, with
        -- nothing in the way.
        if (k ~= "macro" and k ~= "setstate" and k ~= "order") then
            if (luatype(v) == "table") then
                action[k] = CopyTable(v);
            else
                action[k] = v;
            end
        end
    end

    if (source.setstate) then
        local flag = SETSTATE_MODE_FLAGS[source.setstate.mode];
        local index = Constants.CUSTOM_STATE_INDICES[source.setstate.state];
        if (flag and index) then
            action.value = flag + index;
        else
            -- A mode or a state name this version does not know. The action keeps its type and
            -- loses its value, which is the shape red text already has something to say about -
            -- better than guessing at a number that would set some other state.
            action.value = nil;
        end
    end

    -- **The macro decision, made once, here.** After this the action is a `MACRO` pointing at a
    -- macro that exists, or a `MACROTEXT` carrying the body it was sent with. It is not remade
    -- later: a reader who creates the macro afterwards keeps the `MACROTEXT`, which is not wrong,
    -- only flatter.
    if (action.type == Constants.MACRO and source.macro) then
        if (not MacroMatches(source.macro)) then
            action.type = Constants.MACROTEXT;
            action.value = source.macro.body;
            action.name = source.macro.name;
            action.icon = source.macro.icon;
        end
    end

    -- **Where the sender's ordering ends up.** `seq` is not on the wire and must not be: it is
    -- scoped to one layer and the receiving layer has its own numbers. `order` is the group-local
    -- 1..n, and it stays on the action as `importOrder` until the group is given a key -- at which
    -- point `seq` is issued in this order and all three import fields go together.
    --
    -- Not folded into `seq` here, because `seq` means "which of this key's actions goes first" and
    -- these have no key. `PlaceLast` keeps that invariant; this field is what makes keeping it
    -- affordable.
    action.importOrder = source.order;

    return action;
end


-- ---------------------------------------------------------------------------------------------
-- The whole batch
-- ---------------------------------------------------------------------------------------------

--- Where each group of `payload` lands, and what it becomes.
---
--- Returns a flat list of `{ layerID, action }`. **Nothing is written here** - building the list
--- and putting it in the profile are separate so the caller can find out that a payload has
--- nowhere to go before any of it has gone there.
---
--- Groups whose layer this version cannot place are left out, and the count comes back so the
--- caller can say so. That happens for a scope a newer schema invented; every scope v1 knows has
--- a destination (`DefaultDestinationLayerID`).
---
--- `options.stripKeys` drops every key on the way in, the mirror of the export's own option. What
--- quarantine promises is that nothing changes until the reader accepts; this promises that their
--- keys are not touched even then, which is a different thing and an ordinary thing to want.
---
--- **The grouping survives it.** Dropping the key while keeping the set is the entire point: a key
--- split across conditional actions still has to arrive as one thing to give a key to. Only `key`
--- goes - `importGroup` and `importOrder` are untouched.
function DebindShare.PlanImport(payload, batchID, options)
    local placements, skipped = {}, 0;
    local stripKeys = options and options.stripKeys;

    -- **The payload's `id` is not the number that gets stored.** It is unique inside its own
    -- string and nowhere else, so two strings waiting at once would both carry a group 1. Numbers
    -- are taken from the receiving profile instead, once here rather than per group: nothing is
    -- written until `PlaceImportedActions`, so asking again mid-loop would answer the same thing
    -- every time.
    local nextGroupID = DebindPrivate.NextImportGroupID();

    for _, group in ipairs(payload.groups or {}) do
        local layerID = DebindShare.DefaultDestinationLayerID(group.layer);
        if (not layerID) then
            skipped = skipped + 1;
        else
            -- **A group with no `id` was never a group.** The export gives identity only to actions
            -- that were on a key together (`Export.lua`); one the sender built and never bound
            -- arrives as a group of one with nothing to hold, because the format is made of groups.
            -- Numbering it here would head it in the overview as a set whose key was withheld, and
            -- ask the reader what key something the sender does not use deserves.
            local groupID;
            if (group.id ~= nil) then
                groupID = nextGroupID;
                nextGroupID = nextGroupID + 1;
            end

            for _, source in ipairs(group.actions or {}) do
                local action = BuildAction(source);
                -- **The key comes from the group**, which is where the format keeps it: one group
                -- is one key, and that is what has to stay together.
                action.key = (not stripKeys) and group.key or nil;
                action.imported = batchID;
                action.importGroup = groupID;
                placements[#placements + 1] = { layerID = layerID, action = action };
            end
        end
    end

    return placements, skipped;
end

--- Commits a batch into the profile, badged.
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
function DebindShare.CommitBatch(batch)
    local payload, reason = DebindShare.GetBatchPayload(batch);
    if (not payload) then
        return nil, reason;
    end

    local placements, skipped = DebindShare.PlanImport(payload, batch.id,
        batch.stripKeys and { stripKeys = true } or nil);
    if (#placements == 0) then
        return nil, "NOTHING_TO_PLACE";
    end

    DebindPrivate.PlaceImportedActions(placements);

    -- The row says so from now on. Re-committing is allowed and makes a second copy, which is the
    -- same thing importing the same string twice has always done.
    batch.committed = time();

    return #placements, skipped;
end
