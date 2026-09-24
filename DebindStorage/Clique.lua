local _, DebindStorage = ...;

local DebindPrivate = DebindStorage.DebindPrivate;
local Constants     = DebindPrivate.Constants;
local luatype       = type;

--- Turning a Clique profile into a payload (`importing-clique-profiles.md`). What Clique stores and
--- what each combination of its sets means is `.zzz/clique-savedvars.md`; the Clique code that
--- decides it is `core/attributes.lua` and `core/bindings.lua`.
---
--- **Nothing here asks the client.** A binding table goes in and a payload comes out, so the whole
--- of §6's table is a headless spec. Spell and item names stay names (§4); what the client makes
--- of them is the rebuild's business.

--- The payload's `source` for a Clique profile. Read when the payload is added, which is where the
--- layer is chosen and `untranslated` is resolved (§3).
DebindStorage.SOURCE_CLIQUE = "clique";

local SPEC_KEYS = { "spec1", "spec2", "spec3", "spec4", "spec5" };

--- Our modifier order, the one the capture dialog writes (`DebindUI.lua`'s chord builder). Clique
--- writes `META-ALT-CTRL-SHIFT-`.
local MODIFIER_ORDER = { "ALT", "CTRL", "SHIFT", "META" };

--- The key in our spelling, and whether it is a mouse button and whether META is held.
local function TranslateKey(key)
    local modifiers = {};
    local rest = key;
    while (true) do
        local modifier, after = rest:match("^(%u+)%-(.+)$");
        if (not modifier or not (modifier == "ALT" or modifier == "CTRL" or modifier == "SHIFT"
                or modifier == "META")) then
            break;
        end
        modifiers[modifier] = true;
        rest = after;
    end

    local prefix = "";
    for _, modifier in ipairs(MODIFIER_ORDER) do
        if (modifiers[modifier]) then
            prefix = prefix .. modifier .. "-";
        end
    end
    return prefix .. rest, rest:match("^BUTTON%d+$") ~= nil, modifiers.META == true, prefix == "";
end

--- Clique's two starting bindings, which every new profile gets (`OnNewProfile`). Ours does the
--- same with no action at all: a click with nothing bound goes to the frame, which targets on the
--- left button and opens the menu on the right.
local function IsCliqueDefault(binding, sets)
    local only = next(sets);
    if (only ~= "default" or next(sets, only) ~= nil) then
        return false;
    end
    return (binding.key == "BUTTON1" and binding.type == "target")
        or (binding.key == "BUTTON2" and binding.type == "menu");
end

--- Which of Clique's places a binding is applied in (`shouldApply`). A set other than `global` and
--- `hovercast` puts it on the frames -- `ooc`, `friend` or a spec on its own does too -- and those two
--- put it on the global button.
local function Placement(sets)
    local onFrames = false;
    for name in pairs(sets) do
        if (name ~= "global" and name ~= "hovercast") then
            onFrames = true;
        end
    end
    return onFrames, sets.hovercast == true, sets.global == true;
end

--- The action's type and value, or nil for one Clique would not run either.
local function TranslateAction(binding)
    local kind = binding.type;
    if (kind == "target") then
        return Constants.TARGET;
    elseif (kind == "menu") then
        return Constants.TOGGLEMENU;
    elseif (kind == "spell") then
        -- **`spellSubName` is dropped.** On this client it is a specialization's label rather than
        -- a rank, and the name alone resolves per specialization the way Clique's button did.
        if (luatype(binding.spell) == "string" and binding.spell ~= "") then
            return Constants.SPELL, binding.spell;
        end
    elseif (kind == "macro") then
        if (luatype(binding.macrotext) == "string" and binding.macrotext ~= "") then
            return Constants.MACROTEXT, binding.macrotext;
        elseif (luatype(binding.macro) == "string" and binding.macro ~= "") then
            return Constants.MACRO, binding.macro;
        end
    elseif (kind == "item") then
        local item = binding.item;
        -- **A string of digits is an equipment slot.** Clique hands it to `*item-` as it is, which
        -- reads one number as a slot; it has never meant an item id there.
        local slot = luatype(item) == "string" and item:match("^%d+$") and tonumber(item);
        if (slot) then
            if (slot >= INVSLOT_FIRST_EQUIPPED and slot <= INVSLOT_LAST_EQUIPPED) then
                return Constants.USESLOT, slot;
            end
        elseif (luatype(item) == "string" and item ~= "") then
            return Constants.ITEM, item;
        end
    end
    return nil;
end

--- One Clique binding as one of our actions, or nil where Clique would not have bound it either.
--- `combatOnly` is what the `ooc` masking decides for it (below).
local function TranslateBinding(binding, combatOnly)
    local sets = luatype(binding.sets) == "table" and binding.sets or { default = true };
    if (luatype(binding.key) ~= "string" or IsCliqueDefault(binding, sets)) then
        return nil;
    end

    local actionType, value = TranslateAction(binding);
    if (not actionType) then
        return nil;
    end

    local key, isMouse, hasMeta, bare = TranslateKey(binding.key);
    local onFrames, hover, global = Placement(sets);

    -- **A META click never reached a frame in Clique**: the secure button builds its prefix from
    -- Shift, Ctrl and Alt alone (`SecureButton_GetModifierPrefix`). Ours refuses it outright there
    -- (`BINDING_ISSUE_NOT_SUPPORTED_META_CLICK`).
    if (isMouse and hasMeta) then
        onFrames, hover = false, false;
    end
    -- **The global button leaves the bare left and right click alone** (`GetBindingAttributes`).
    if (bare and (key == "BUTTON1" or key == "BUTTON2")) then
        hover, global = false, false;
    end
    if (not (onFrames or hover or global)) then
        return nil;
    end

    local action = { type = actionType, value = value, key = key };
    if (actionType == Constants.MACROTEXT) then
        action.icon = binding.icon;
    end

    -- **The frames and `hovercast` both become Hover Cast, in the account's mode** (§5). `global` is
    -- the press away from them, which is what `normalCast` is.
    if (onFrames or hover) then
        action.casting = { hoverCast = "cast" };
        if (not global) then
            action.casting.normalCast = false;
        end
        -- **The one mode an import sets.** A menu opened on mouseover acts on whatever is under the
        -- cursor next, which is the menu (`UNIT_INFO.mouseover.togglemenu`).
        if (actionType == Constants.TOGGLEMENU) then
            action.casting.hoverCastMode = "unitframe";
        end
    end

    local conditions = {};
    if (sets.ooc) then
        conditions.combat = false;
    elseif (combatOnly) then
        conditions.combat = true;
    end
    -- **`friend` wins over `enemy`**, the way Clique reads the pair (`GetClickAttributes`).
    if (sets.friend) then
        conditions.units = { ["@"] = { exists = true, reaction = Constants.REACTION_HELP } };
    elseif (sets.enemy) then
        conditions.units = { ["@"] = { exists = true, reaction = Constants.REACTION_HARM } };
    end
    if (next(conditions)) then
        action.conditions = conditions;
    end

    -- **The specialization numbers wait as Clique wrote them**, because nothing here knows the class
    -- they belong to. Adding is where that is known (§2, §3).
    local specs;
    for _, name in ipairs(SPEC_KEYS) do
        if (sets[name]) then
            specs = specs or {};
            specs[name] = true;
        end
    end
    if (specs) then
        action.untranslated = specs;
    end

    return action;
end

--- A Clique binding list as a payload, everything in General (§3). **Returns the payload and how
--- many actions it holds**, which is what the profile list shows.
---
--- **An `ooc` binding takes its key out of combat and the others on it into it.** Clique clears a
--- non-`ooc` binding sharing an `ooc` key whenever the player is out of combat (`oocKeys`), where
--- ours would fall through to the next action once the first one's condition failed.
function DebindStorage.PayloadFromCliqueBindings(bindings)
    local oocKeys = {};
    for _, binding in ipairs(bindings) do
        if (luatype(binding) == "table" and luatype(binding.sets) == "table" and binding.sets.ooc
                and luatype(binding.key) == "string") then
            oocKeys[binding.key] = true;
        end
    end

    local actions = {};
    local seqByKey = {};
    for _, binding in ipairs(bindings) do
        if (luatype(binding) == "table") then
            local ooc = luatype(binding.sets) == "table" and binding.sets.ooc;
            local action = TranslateBinding(binding, not ooc and oocKeys[binding.key]);
            if (action) then
                seqByKey[action.key] = (seqByKey[action.key] or 0) + 1;
                action.seq = seqByKey[action.key];
                actions[#actions + 1] = action;
            end
        end
    end

    local payload = {
        v = DebindStorage.EXPORT_SCHEMA_VERSION,
        dbver = Constants.DB_VERSION,
        source = DebindStorage.SOURCE_CLIQUE,
        shared = { GENERAL = actions },
    };
    return payload, #actions;
end

--- The profiles in a `CliqueDB3`, sorted by name: `{ name, characters, bindings }`. `characters` are
--- the `profileKeys` that point at it, as Clique spells them ("Name - Realm").
function DebindStorage.CliqueProfiles(db)
    local list = {};
    if (luatype(db) ~= "table" or luatype(db.profiles) ~= "table") then
        return list;
    end

    local users = {};
    if (luatype(db.profileKeys) == "table") then
        for character, profile in pairs(db.profileKeys) do
            users[profile] = users[profile] or {};
            table.insert(users[profile], character);
        end
    end

    for name, profile in pairs(db.profiles) do
        if (luatype(name) == "string" and luatype(profile) == "table"
                and luatype(profile.bindings) == "table") then
            local characters = users[name] or {};
            table.sort(characters);
            list[#list + 1] = { name = name, characters = characters, bindings = profile.bindings };
        end
    end
    table.sort(list, function(a, b) return a.name < b.name; end);
    return list;
end
