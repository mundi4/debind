local _, DebindPrivate      = ...;
local Constants             = DebindPrivate.Constants;
local LLL                   = DebindPrivate.L;
local Spells                = DebindPrivate.Spells;

local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;

local ActionMenu            = DebindPrivate.ActionMenu;
local ActionMenus           = ActionMenu.ActionMenus;

--- A condition drawn on screen with nothing behind it.
---
--- **Nothing reads what this menu stores.** It exists to be opened and clicked through, because
--- what a shape costs a reader cannot be argued about on paper. This one is the row shape the
--- name-valued `known` would have: one row per spell that shares a root with the one the action
--- holds (`.zzz/known-as-a-spell-name.md`).
---
--- The picks live for as long as the session and are keyed by the action table itself, so a
--- reload, a layer move and a copy each lose them. That is fine for what this is for, and it is
--- why no storage key and no `/debtest` case belongs to it yet.

--- Picks made this session: `action -> key -> value`. Weak keys, so a deleted action does not hold
--- its table.
local picks = setmetatable({}, { __mode = "k" });

local function PickOf(action, key)
    local forAction = picks[action];
    if (forAction == nil) then
        return nil;
    end
    return forAction[key];
end

local function SetPick(action, key, value)
    local forAction = picks[action];
    if (forAction == nil) then
        if (value == nil) then
            return;
        end
        forAction = {};
        picks[action] = forAction;
    end
    forAction[key] = value;
end

--- The id this row is, beside the name. **Only because this menu is a probe**: reading one off the
--- screen is how a row gets matched against a `/dump` of the same walk.
local function WithID(name, id)
    return format("%s |cff808080%d|r", name, id);
end

--- One row per spell that shares a root with the one this action holds.
---
--- A talent that replaces a spell is what the reader is really picking between -- Celestial
--- Alignment and the Incarnation that overrides it are one chain -- so the chain is the list, root
--- first and the ones that cover it under it (`Spells.BuildBranches`).
---
--- **Rows are names and not ids.** A combination of talents can stand up an id that no walk sees
--- (390414), and what places it is that it shares its name with one that is in there.
local function BranchRows(action)
    local root = DebindPrivate.ResolveBaseSpell(action.value);
    -- nil where the stored id belongs to another specialization: its root is in no walk this
    -- character can make, and the one row left to offer is the id itself.
    local family = (root and Spells.GetBranches()[root]) or { action.value };

    local seen, rows = {}, {};
    for i = 1, #family do
        local name = GetSpellNameAndIconID(family[i]);
        if (name and not seen[name]) then
            seen[name] = true;
            rows[#rows + 1] = { name = name, spellID = family[i] };
        end
    end
    return rows;
end

ActionMenus:Define("KNOWN2", {
    label = "CONDITION_KNOWN2",
    shown = function(ctx)
        return ctx.action.type == Constants.SPELL;
    end,
    isActive = function(ctx)
        return PickOf(ctx.action, "known2") ~= nil;
    end,
    build = function(kit)
        local ctx = kit.ctx;

        kit.description:CreateRadio(LLL["DISABLE"],
            function()
                return PickOf(ctx.action, "known2") == nil;
            end,
            function()
                SetPick(ctx.action, "known2", nil);
                return MenuResponse.Refresh;
            end);

        -- **Walked once per open.** `GetBranches` walks the spellbook and every tree each call.
        local rows = BranchRows(ctx.action);
        for i = 1, #rows do
            local spellID = rows[i].spellID;
            kit.description:CreateRadio(WithID(rows[i].name, spellID),
                function()
                    return PickOf(ctx.action, "known2") == spellID;
                end,
                function()
                    SetPick(ctx.action, "known2", spellID);
                    return MenuResponse.Refresh;
                end);
        end
    end,
});
