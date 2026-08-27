-- 게임 없이 애드온 파일을 로드하기 위한 최소 WoW 환경.
-- Plain Lua 5.1, which is what the client and CI run. `run.lua` refuses anything newer.

local M = {};

local frames = require("wow_frames");
M.frames = frames;

--- The client facts the value-returning stand-ins answer from. A spec fills in what it needs and
--- everything else stays absent, which is not the same as a default -- see the comment on
--- `C_Spell` in `install`.
M.world = {
    cvars = {},
    spells = {},
    baseSpells = {},
    overrideSpells = {},
    mounts = {},
    callPetSlots = {},
    flyouts = {},
    inCombat = false,
    bindings = {},
    units = {},
    bindingContexts = {},
    activeBindingContexts = {},
    macros = {},
    equipped = {},
};

--- Puts the world back to empty and reinstalls every stand-in over it.
---
--- **A spec that overwrites a global keeps it for the whole run otherwise**, and the next spec
--- inherits a client somebody else configured. That was not theoretical: `emit_fixture` never
--- installed a macro store and passed anyway, on whichever `_G.GetMacroInfo` the spec before it
--- had left behind, and reversing the spec list was what said so (§10-1).
function M.resetWorld()
    for key, value in pairs(M.world) do
        if (type(value) == "table") then
            for k in pairs(value) do value[k] = nil; end
        end
    end
    M.world.inCombat = false;
    M.install();
end

local MASK32 = 4294967296;

local function norm(x)
    x = x % MASK32;
    return x - x % 1;
end

local function band(a, b)
    a, b = norm(a), norm(b);
    local res, bitval = 0, 1;
    while a > 0 and b > 0 do
        if (a % 2 == 1 and b % 2 == 1) then
            res = res + bitval;
        end
        a = (a - a % 2) / 2;
        b = (b - b % 2) / 2;
        bitval = bitval * 2;
    end
    return res;
end

local function bor(a, b)
    a, b = norm(a), norm(b);
    local res, bitval = 0, 1;
    while a > 0 or b > 0 do
        if (a % 2 == 1 or b % 2 == 1) then
            res = res + bitval;
        end
        a = (a - a % 2) / 2;
        b = (b - b % 2) / 2;
        bitval = bitval * 2;
    end
    return res;
end

-- WoW의 bit.bnot은 부호 있는 32비트를 돌려주지만, 이 코드베이스에서 bnot은
-- 항상 band의 인자로만 쓰이므로 부호 없는 보수로 동치.
local function bnot(a)
    return MASK32 - 1 - norm(a);
end

local function lshift(a, n)
    return norm(norm(a) * 2 ^ n);
end

local function rshift(a, n)
    local v = norm(a) / 2 ^ n;
    return v - v % 1;
end

--- `Blizzard_SharedXMLBase/TableUtil.lua`의 `CopyTable(settings, shallow)`와 같은 서명이다.
--- **두 번째 인자를 무시하면 안 된다** - 게임에서는 얕은 복사가 되는 자리가 여기서는 깊은
--- 복사가 되어, "원본을 안 건드린다"를 검사하는 테스트가 통과해버린다. 그 테스트는 옛
--- SavedVariables를 지키는 것이 전부라 통과하면 안 될 때 통과하는 것이 제일 나쁘다.
local function copyTable(src, shallow)
    local dest = {};
    for k, v in pairs(src) do
        if (type(v) == "table" and not shallow) then
            dest[k] = copyTable(v);
        else
            dest[k] = v;
        end
    end
    return dest;
end

-- Captured before `install()` swaps `string.format` out, and named so this function does not
-- depend on the WoW aliases it is itself installing.
local rawformat, strfind, strsub, strmatch = string.format, string.find, string.sub, string.match;

--- The client's `format` keeps Lua 4.0's **argument selection** (`%N$`), which 5.0 dropped. A
--- stock interpreter raises `invalid option '%$'` on a string the game formats fine, so this is
--- not a difference that quietly changes an answer: a spec that reaches one of those strings dies
--- on the format call rather than on what it measures. There are 122 of them across `Debind/`,
--- `DebindStorage/` and `DebindDev/`, and every locale file carries some.
---
--- **A positional specifier moves the implicit counter.** The client's own documentation
--- (`https://wowpedia.fandom.com/wiki/API_format`) is
---
---     format("%2$d, %1$d, %d", 1, 2) == "2, 1, 2"
---
--- The trailing plain `%d` answers 2, not 1. `UpdateBindings.lua` rests on that reading: the
--- `SetSwitch` line names its first argument and lets the second follow as a plain `%s`.
---
--- **Only `%s`, `%d` and `%q` are covered**, which is every conversion this repo pairs with a
--- positional specifier (85, 18 and 19 of them). Anything else raises. A width or a float
--- formatted by guesswork would be a wrong answer coming out of the harness, and the harness
--- answering wrongly is the one failure this file exists to prevent.
---
--- Strings with no `%N$` in them never enter this path at all; they go to the real
--- `string.format` untouched, so everything else it can do still works.
local function positionalFormat(fmt, ...)
    if (type(fmt) ~= "string" or not strfind(fmt, "%%%d+%$")) then
        return rawformat(fmt, ...);
    end

    local args = { ... };
    local out, ordered, count = {}, {}, 0;
    local nextArg, i = 1, 1;

    while (true) do
        local at = strfind(fmt, "%", i, true);
        if (not at) then
            out[#out + 1] = strsub(fmt, i);
            break;
        end
        out[#out + 1] = strsub(fmt, i, at - 1);

        local pos, conv, after = strmatch(fmt, "^%%(%d+)%$([sdq])()", at);
        if (not pos) then
            conv, after = strmatch(fmt, "^%%([sdq%%])()", at);
        end
        if (not conv) then
            error("wow_shim: " .. strsub(fmt, at, at + 4)
                .. " is outside what the positional format stand-in covers (%s, %d, %q): " .. fmt, 2);
        end

        if (conv == "%") then
            out[#out + 1] = "%%";
        else
            local idx = pos and tonumber(pos) or nextArg;
            nextArg = idx + 1;
            count = count + 1;
            ordered[count] = args[idx];
            out[#out + 1] = "%" .. conv;
        end
        i = after;
    end

    return rawformat(table.concat(out), unpack(ordered, 1, count));
end

function M.install()
    _G.bit = { band = band, bor = bor, bnot = bnot, lshift = lshift, rshift = rshift };

    _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil; end
        return t;
    end
    _G.tinsert = table.insert;
    _G.tremove = table.remove;
    _G.tContains = function(t, v)
        for i = 1, #t do if (t[i] == v) then return true; end end
        return false;
    end
    _G.CopyTable = copyTable;

    -- Copied verbatim from `Blizzard_SharedXMLBase/TableUtil.lua`. **Returns the stateless
    -- iterator triple, and stops at the first nil rather than at the upper bound** - a stand-in
    -- that differs from the real thing makes the tests lie.
    _G.CreateTableEnumerator = function(tbl, minIndex, maxIndex)
        minIndex = minIndex and (minIndex - 1) or 0;
        maxIndex = maxIndex or math.huge;

        local function Enumerator(t, index)
            index = index + 1;
            if (index <= maxIndex) then
                local value = t[index];
                if (value ~= nil) then
                    return index, value;
                end
            end
        end

        return Enumerator, tbl, minIndex;
    end

    _G.format = positionalFormat;
    -- **The method form has to take the same path.** The client's own strings arrive as globals
    -- and are formatted with `SOME_GLOBAL:format(...)`, and a localized one carries `%N$` where
    -- the English one does not. In the game the C function itself is the one that knows about
    -- argument selection, so patching only the `format` global would leave those call sites on
    -- stock Lua.
    string.format = positionalFormat;
    _G.strmatch = string.match;
    _G.strsub = string.sub;
    _G.strfind = string.find;
    _G.strlower = string.lower;
    _G.strupper = string.upper;
    _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")); end
    -- 와우의 strsplit: 첫 인자의 **각 문자**가 개별 구분자. 빈 필드도 그대로 남는다.
    _G.strsplit = function(delims, s)
        local out, cur = {}, {};
        for i = 1, #s do
            local c = s:sub(i, i);
            if (delims:find(c, 1, true)) then
                out[#out + 1] = table.concat(cur);
                cur = {};
            else
                cur[#cur + 1] = c;
            end
        end
        out[#out + 1] = table.concat(cur);
        return unpack(out, 1, #out);
    end
    _G.securecall = function(fn, ...) return fn(...); end
    _G.securecallfunction = function(fn, ...) return fn(...); end
    _G.floor = math.floor;
    _G.abs = math.abs;
    _G.max = math.max;
    _G.min = math.min;
    _G.sort = table.sort;

    _G.MAX_PARTY_MEMBERS = 4;
    _G.MAX_RAID_MEMBERS = 40;
    _G.MAX_ARENA_ENEMIES = 5;

    _G.GetTime = function() return 0; end
    _G.GetLocale = function() return "enUS"; end
    _G.UnitClass = function() return "Druid", "DRUID", 11; end
    --- **The units that exist, and which of them are the same unit.** `M.world.units` is
    --- `[token] = { id = , raidIndex = , inParty = }`, and `id` is the identity two tokens share
    --- when `UnitIsUnit` says they are one unit -- which is the whole of what resolving a custom
    --- target rests on. It starts empty, which is a client where nothing exists.
    --- The macro store, answering out of the world like everything else here.
    ---
    --- **It starts empty, which is a character with no macros**, and that is a real answer rather
    --- than an absent function: `ConvertToMacroText` and `GetBindingIssue` both ask, and a nil
    --- global made them raise in whichever spec had not been handed someone else's stub. Three
    --- specs stand up richer stores of their own over this one (`export`, `import`, `issue`).
    _G.GetMacroInfo = function(nameOrIndex)
        local macro = M.world.macros[nameOrIndex];
        if (not macro) then return nil; end
        return macro.name or nameOrIndex, macro.icon, macro.body;
    end
    _G.GetMacroIndexByName = function(name)
        return M.world.macros[name] and 1 or 0;
    end
    _G.GetNumMacros = function() return 0, 0; end
    --- Making and deleting one, so the store can move under a profile that names a macro.
    ---
    --- **Neither sends the event.** In the client `UPDATE_MACROS` follows, and what the addon has to
    --- get right is that it listens -- so a stand-in that fired it here would be answering the very
    --- question (`Events.lua`, `UPDATE_MACROS`). A spec sends it with `frames.fireEvent`.
    _G.CreateMacro = function(name, icon, body)
        M.world.macros[name] = { name = name, icon = icon, body = body };
        return 1;
    end
    _G.DeleteMacro = function(nameOrIndex)
        M.world.macros[nameOrIndex] = nil;
    end

    _G.UnitExists = function(token) return M.world.units[token] ~= nil; end
    _G.UnitIsUnit = function(a, b)
        local left, right = M.world.units[a], M.world.units[b];
        return left ~= nil and right ~= nil and left.id == right.id;
    end
    _G.UnitInRaid = function(token)
        local unit = M.world.units[token];
        return unit and unit.raidIndex;
    end
    _G.UnitInParty = function(token)
        local unit = M.world.units[token];
        return (unit and unit.inParty) and true or false;
    end

    --- The world the non-secure side asks about while it rebuilds. Every one of these is a value
    --- returning query, the cheap side to mock (§4 of
    --- `devdocs/legacy/going-headless-outside-the-ui.md`), and the answers come out of `M.world` so a
    --- spec can put the client in a state rather than swapping the function out.
    _G.InCombatLockdown = function() return M.world.inCombat and true or false; end
    --- **Life and reaction are answered here and nowhere else.** The restricted environment gets
    --- the same four functions (`RestrictedEnvironment.lua`), so a unit that is dead to the poll
    --- cannot be alive to the press -- which is the one disagreement the two sides could have that
    --- nothing below them would notice.
    _G.UnitIsDead = function(token)
        local unit = M.world.units[token];
        return (unit and unit.dead) and true or false;
    end
    _G.UnitIsGhost = function(token)
        local unit = M.world.units[token];
        return (unit and unit.ghost) and true or false;
    end
    _G.PlayerCanAssist = function(token)
        local unit = M.world.units[token];
        return (unit and unit.reaction == "help") and true or false;
    end
    _G.PlayerCanAttack = function(token)
        local unit = M.world.units[token];
        return (unit and unit.reaction == "harm") and true or false;
    end
    _G.GetShapeshiftForm = function() return 0; end
    _G.GetBonusBarOffset = function() return 0; end
    _G.IsStealthed = function() return false; end
    _G.IsMounted = function() return false; end
    _G.IsInGroup = function() return false; end
    _G.IsInRaid = function() return false; end
    _G.GetNumGroupMembers = function() return 0; end
    _G.SecureCmdOptionParse = function() return ""; end

    --- The game's own binding table, which the addon reads and never writes: `RefreshGameMenuKeys`
    --- asks what `TOGGLEGAMEMENU` sits on, and `BindingContexts.lua` walks the whole table to find
    --- the keys an open editor has claimed. `M.world.bindings` is a list of
    --- `{ action = , context = , keys = { ... } }` and starts empty, which is a client with
    --- nothing bound rather than a client that refuses to answer.
    _G.GetNumBindings = function() return #M.world.bindings; end
    _G.GetBinding = function(index)
        local entry = M.world.bindings[index];
        if (not entry) then return; end
        return entry.action, entry.category,
            unpack(entry.keys or {}, 1, #(entry.keys or {}));
    end
    _G.GetBindingKey = function(action)
        for i = 1, #M.world.bindings do
            local entry = M.world.bindings[i];
            if (entry.action == action) then
                return unpack(entry.keys or {}, 1, #(entry.keys or {}));
            end
        end
    end
    _G.GetBindingText = function(key) return key; end
    --- **`checkOverride` is the whole of what this addon asks about.** Debind never touches the
    --- saved binding set; everything it does is an override on the driver, so a reader that
    --- ignored the second argument could only ever answer for the client's own bindings and the
    --- addon's own work was invisible to it (`wow_frames.lua`, `overrides`).
    ---
    --- An override wins outright where there is one, which is what the flag means: the client
    --- looks past the saved set while the key is held.
    _G.GetBindingAction = function(key, checkOverride)
        if (checkOverride) then
            local action = frames.overrideAction(key);
            if (action) then return action; end
        end
        for i = 1, #M.world.bindings do
            local entry = M.world.bindings[i];
            for _, bound in ipairs(entry.keys or {}) do
                if (bound == key) then return entry.action; end
            end
        end
        return "";
    end

    --- **12.0's binding contexts, and the shim answers "this client has none".** `Enum` carries
    --- the table so a value can be named, and `IsBindingContextActive` answers from
    --- `M.world.activeBindingContexts`, which is empty until a spec opens one. With none active,
    --- `BindingContexts.lua` yields nothing -- the state every client is in outside the housing
    --- editor.
    _G.Enum = {
        BindingContext = { None = 0, Housing = 1, HousingDecor = 2 },
        SpellBookSpellBank = { Player = 0, Pet = 1 },
        SpellBookItemType = { Spell = 1, Flyout = 2, PetAction = 3, FutureSpell = 4 },
        SpellBookSkillLineIndex = { Class = 2, General = 1 },
    };
    _G.C_KeyBindings = {
        GetBindingContextForAction = function(action)
            return M.world.bindingContexts[action];
        end,
        IsBindingContextActive = function(context)
            return M.world.activeBindingContexts[context] and true or false;
        end,
    };

    -- What Profile.lua and Legacy.lua (the pre-rename SavedVariables import) need in order to
    -- load and run. The values are not arbitrary, they are **what the tests expect**: migration_spec
    -- uses `UnitGUID` as a key, and `GetClassInfo` mirrors how the import builds class names.
    _G.UnitGUID = function() return "Player-1-TESTGUID"; end
    _G.UnitLevel = function() return 80; end
    _G.UnitName = function() return "Tester"; end
    _G.UnitRace = function() return "Human", "Human", 1; end
    _G.UnitSex = function() return 2; end
    _G.UnitFactionGroup = function() return "Alliance"; end
    _G.GetNormalizedRealmName = function() return "TestRealm"; end
    -- **Not the normalized one.** An entry made from a profile keeps the realm to say whose it is,
    -- and that is read by a person rather than matched against anything, so it is the name with its
    -- spaces in (`CreateEntry`).
    _G.GetRealmName = function() return "Test Realm"; end
    _G.time = function() return 1770000000; end

    _G.C_SpecializationInfo = {
        GetNumSpecializationsForClassID = function() return 4; end,
        GetSpecialization = function() return 1; end,
    };

    -- `MAGE` is here because the sharing specs need **a class that is not ours**: a string from one
    -- keeps its own class and spec on the way in, and the import refuses a class name no client
    -- has (`ImportAddress`). Without it those cases would measure the refusal instead.
    local CLASS_FILES = { [1] = "WARRIOR", [2] = "PALADIN", [8] = "MAGE", [11] = "DRUID" };
    _G.C_CreatureInfo = {
        GetClassInfo = function(classId)
            local classFile = CLASS_FILES[classId];
            return classFile and { classFile = classFile } or nil;
        end,
    };

    -- Loading the dummy addon. Succeeds by default; `migration_spec` swaps this out when it
    -- exercises the disabled path.
    --- **The one CVar the addon reads for itself.** `ApplyOptions` folds the click edge option's
    --- third answer -- the reader leaving it to the game -- onto this, and the restricted side
    --- cannot ask for it. Off by default, which is the client's default and the release edge.
    --- **The header globals, as things to hook rather than things that work.** The addon hooks
    --- these to find a group header's children, and `hooksecurefunc` needs something standing
    --- there to wrap. What they do is Blizzard's and out of reach headless; a spec drives the
    --- hook by calling one, which is what the game does on every roster change.
    _G.SecureGroupHeader_OnLoad = function() end
    _G.SecureGroupHeader_Update = function() end
    _G.SecureGroupPetHeader_OnLoad = function() end
    _G.SecureGroupPetHeader_Update = function() end

    _G.GetCVarBool = function(name)
        return M.world.cvars[name] and true or false;
    end

    _G.ACTION_BUTTON_USE_KEY_DOWN = "Cast action keybinds on key down";

    _G.C_AddOns = {
        LoadAddOn = function() return true; end,
        IsAddOnLoaded = function() return false; end,
        --- **Nothing installed, which is what a headless run has.** `CollectOUFFrames` walks this
        --- list asking every addon for its `X-oUF` global, so a spec that wants the walk to find
        --- something puts an addon here itself.
        GetNumAddOns = function() return 0; end,
        --- **`nil` is the answer a working tree gives.** The packager stamps `## Version:` from the
        --- tag, so a checkout has the literal `@project-version@` there or nothing at all, and
        --- `GetVersionLabel` is written around exactly that -- it falls back when the metadata has
        --- an `@` in it or is missing. Answering with a made-up version would take that branch out
        --- of reach of every spec.
        GetAddOnMetadata = function() return nil; end,
    };

    -- Misc.lua가 파일 스코프에서 건드리는 것들. 매크로텍스트 파서와는 무관하지만
    -- 파일이 로드되려면 있어야 한다.
    --
    -- **They answer out of `M.world`, and it starts empty.** Every one of these is a query
    -- returning a value, which is the cheap side to mock (§4 of
    -- `devdocs/legacy/going-headless-outside-the-ui.md`), but nothing here invents an answer for an id
    -- the spec did not put there: a made-up spell name reads exactly like a real one, and the
    -- caller's other branch -- binding by id because the name did not resolve -- is a path a spec
    -- has to be able to reach on purpose.
    _G.C_MountJournal = {
        GetMountInfoByID = function(mountID)
            local mount = M.world.mounts[mountID];
            if (not mount) then return; end
            return mount.name, mount.spellID;
        end,
    };

    --- 착용 칸. `EquipSlotFacts`가 이 셋을 같이 읽는다 - 칸 번호 범위, 칸마다의 프레임 이름,
    --- 그리고 그 이름을 대문자로 올린 전역이 드는 사람이 읽을 말.
    ---
    --- **장신구 둘과 손가락 둘이 같은 말을 쓰는 것이 요점이다.** 겹치는 이름에만 번호를 붙이는
    --- 갈래가 그 넷에서만 돌고, 겹침을 안 만든 표는 그 갈래를 통째로 못 밟는다.
    _G.INVSLOT_FIRST_EQUIPPED = 1;
    _G.INVSLOT_LAST_EQUIPPED = 19;
    local SLOT_FRAME_NAMES = {
        "HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot",
        "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot",
        "Trinket0Slot", "Trinket1Slot", "BackSlot", "MainHandSlot", "SecondaryHandSlot",
        "RangedSlot", "TabardSlot",
    };
    for slot = 1, #SLOT_FRAME_NAMES do
        local key = string.upper(SLOT_FRAME_NAMES[slot]);
        if (key == "FINGER0SLOT" or key == "FINGER1SLOT") then
            _G[key] = "Finger";
        elseif (key == "TRINKET0SLOT" or key == "TRINKET1SLOT") then
            _G[key] = "Trinket";
        else
            _G[key] = SLOT_FRAME_NAMES[slot]:gsub("Slot$", "");
        end
    end
    _G.C_PaperDollInfo = {
        GetInventorySlotInfoForInvSlot = function(slot)
            local frameName = SLOT_FRAME_NAMES[slot];
            if (not frameName) then return; end
            return slot, 1000 + slot, false, frameName;
        end,
    };
    --- 그 칸에 지금 차고 있는 것의 그림. **비어 있는 것이 기본**이고, 그리는 쪽은 그때 칸
    --- 자체의 그림으로 물러선다(`ActionDisplay.lua`).
    _G.GetInventoryItemTexture = function(_, slot)
        local worn = M.world.equipped[slot];
        return worn and worn.texture or nil;
    end;
    _G.C_Spell = {
        GetSpellInfo = function(spellID) return M.world.spells[spellID]; end,
        GetSpellSubtext = function(spellID)
            local spell = M.world.spells[spellID];
            return spell and spell.subtext;
        end,
        IsPressHoldReleaseSpell = function(spellID)
            local spell = M.world.spells[spellID];
            return (spell and spell.pressAndHold) and true or false;
        end,
    };
    _G.C_SpellBook = {
        --- The id an override points back at. Absent from the table means "this id is its own
        --- base", which is what the client answers for every spell that is not overridden.
        FindBaseSpellByID = function(spellID) return M.world.baseSpells[spellID]; end,
        --- The other direction: what this spell has *become*. A talent or a form replaces a spell
        --- while it holds, and the name a reader is shown is the replacement's -- so a stand-in
        --- that always answered the id back would hide the whole branch.
        ---
        --- `M.world.overrideSpells[id]` is the replacement; absent means nothing is overriding it,
        --- which the client answers as the id itself.
        FindSpellOverrideByID = function(spellID)
            return M.world.overrideSpells[spellID] or spellID;
        end,
    };
    --- A flyout and its slots. `M.world.flyouts[id]` is `{ name =, slots = { spellID… } }`; a
    --- flyout the world does not name answers with no slot count at all, which is the "not
    --- learned" case and the one that makes `SetBindingAttributes` refuse to bind the key.
    _G.GetFlyoutInfo = function(flyoutID)
        local flyout = M.world.flyouts[flyoutID];
        if (not flyout) then return; end
        return flyout.name, flyout.description, #flyout.slots, true;
    end
    _G.GetFlyoutSlotInfo = function(flyoutID, slot)
        local flyout = M.world.flyouts[flyoutID];
        local spellID = flyout and flyout.slots[slot];
        if (not spellID) then return; end
        local spell = M.world.spells[spellID];
        return spellID, nil, true, spell and spell.name;
    end
    _G.GetCallPetSpellInfo = function(spellID)
        local slot = M.world.callPetSlots[spellID];
        if (not slot) then return; end
        return slot.index, slot.petName;
    end
    -- Frames, and everything that crosses to the secure side. Split into its own file because the
    -- emission golden reads the recorder back (`wow_frames.lua`), and because a shell that records
    -- what it was handed is a different kind of stand-in from the value-returning ones above
    -- (`devdocs/legacy/going-headless-outside-the-ui.md` §4).
    frames.install();
    -- The unit right-click menu. `UnitWatch.lua` adds the "set as custom target" entries to it at
    -- load; what it hands over is a function the client calls back, and nothing headless calls it.
    _G.SetClampedTextureRotation = function() end
    -- The chat frame every message the addon prints goes to. It says nothing here; what matters
    -- is that printing one does not die, since some of them are the only report a refusal makes.
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end };
    _G.ChatTypeInfo = { SYSTEM = { r = 1, g = 1, b = 0 } };
    _G.Menu = { ModifyMenu = function() end };
    _G.MenuResponse = { Close = 1, Refresh = 2, Open = 3 };

    --- The client's colour objects, down to the one method the addon uses on them. The wrap is the
    --- real escape sequence rather than a passthrough, so a spec reading a tooltip line back sees
    --- what a reader would -- including a colour that swallowed the text it was meant to wrap.
    local function color(code)
        return {
            WrapTextInColorCode = function(_, text) return "|c" .. code .. text .. "|r"; end,
        };
    end
    _G.DISABLED_FONT_COLOR = color("ff808080");
    _G.ERROR_COLOR = color("ffff2020");
    _G.INACTIVE_COLOR = color("ff7f7f7f");
    _G.BRIGHTBLUE_FONT_COLOR = color("ff00b0ff");

    --- **The tooltip is an argument, not a screen.** `ActionTooltip.lua` takes the frame it writes
    --- to and knows nothing else about the client, so what it needs from here is the free functions
    --- the client puts the lines through -- and a tooltip to collect them is `M.newTooltip()`.
    ---
    --- Each keeps which kind of line it was. A spec that only ever read the text back could not
    --- tell "the reason is written" from "the reason is written in the ordinary colour", and the
    --- error lines are the ones the tooltip exists to carry.
    local function addLine(kind)
        return function(tooltip, text, wrap, leftOffset)
            tooltip.lines[#tooltip.lines + 1] = {
                kind = kind, text = text, wrap = wrap, leftOffset = leftOffset,
            };
        end
    end
    _G.GameTooltip_AddNormalLine = addLine("normal");
    _G.GameTooltip_AddErrorLine = addLine("error");
    _G.GameTooltip_AddHighlightLine = addLine("highlight");
    _G.GameTooltip_AddInstructionLine = addLine("instruction");
    _G.GameTooltip_AddBlankLineToTooltip = function(tooltip)
        tooltip.lines[#tooltip.lines + 1] = { kind = "blank", text = "" };
    end
    _G.GameTooltip_SetTitle = function(tooltip, text)
        tooltip.lines[#tooltip.lines + 1] = { kind = "title", text = text };
    end

    _G.SLASH_SCRIPT1 = "/script";
    _G.SLASH_CANCELFORM1 = "/cancelform";
    -- **`ConvertToMacroText` writes the body with these**, and an absent one does not raise here:
    -- `%s` in Lua 5.4 takes any value and prints `nil`, so the body came out reading `nil Regrowth`
    -- and the check looking for the spell name still found it. `lua5.1` -- which is what CI runs --
    -- refuses a nil for `%s`, so the same run was green locally and red there.
    _G.SLASH_CAST1 = "/cast";
    _G.SLASH_USE1 = "/use";

    --- **`"%s-%s"` in every locale, and `Misc.lua` caches it into a file local at load.** A nil
    --- there does not fall back to anything -- `FULL_PLAYER_NAME:format(...)` indexes it -- so the
    --- specs were one step away from the same fault `SLASH_CAST1` had, and only stayed clear of it
    --- because nothing reached that path.
    _G.FULL_PLAYER_NAME = "%s-%s";

    --- **One binding command that resolves.** `ActionDisplay` asks `_G["BINDING_NAME_" .. value]`
    --- and falls back to the command code, so without a single one defined every spec walked the
    --- fallback and a command action was named by its code -- which is what a reader sees when the
    --- client has no name for it, not what they see for a real one.
    _G.BINDING_NAME_TOGGLEGAMEMENU = "Game Menu";
    -- A pet command that has a slash command, so `GetPetActionMacroText` answers for it. The
    -- commands that have none are the ones the addon refuses to bind, and reaching that branch is
    -- a matter of naming one that is not here.
    _G.SLASH_PETATTACK1 = "/petattack";
end

--- A tooltip to draw into, and the lines it ends up holding.
---
--- **Only what `ActionTooltip.lua` reaches for.** It sets a minimum width and hides, and everything
--- else it does goes through the `GameTooltip_Add…` free functions above -- so this is the whole
--- surface, and a call outside it should fail loudly here rather than be absorbed.
---
--- `text()` is the reader's view: every line's text, in order, joined the way the in-game kit joins
--- what it reads off `GameTooltipTextLeft…`.
function M.newTooltip()
    local tooltip = { lines = {} };
    function tooltip:SetMinimumWidth(width, shown)
        self.minimumWidth = width;
        self.minimumWidthShown = shown;
    end
    function tooltip:Hide() self.hidden = true; end
    function tooltip:text()
        local parts = {};
        for i = 1, #self.lines do parts[i] = self.lines[i].text or ""; end
        return table.concat(parts, "\n");
    end
    return tooltip;
end

--- Reads the bundled libraries. They are ordinary Lua files with no addon arguments -- `LibStub`
--- puts itself in `_G` and the rest find it there -- so they load ahead of the addon and outside
--- `loadAddon`, which exists to hand a file the two arguments `local _, DebindPrivate = ...` wants.
function M.loadLibs(root, files)
    for i = 1, #files do
        local path = root .. "/" .. files[i];
        local chunk, err = loadfile(path);
        if (not chunk) then
            error("failed to load " .. path .. ": " .. tostring(err), 0);
        end
        chunk();
    end
end

--- Cuts the `--@debug@` blocks out, which is what the packager does on the way to a release. Three
--- files carry one (`Constants.lua`, `Profile.lua`, `Public.lua`) and thirty lines come out, but
--- the one that matters is three of them: `Constants.DEBUG` stops being true, and every
--- `if (DEBUG)` in the addon changes answer with it.
---
--- **Only the stripping half is here.** The packager also uncomments `--[===[@non-debug@ ... ]===]`,
--- and this repo has no such block in any Lua file - the only `@non-debug@` is in the TOC. If one
--- is ever written, this stops being a faithful stand-in and the shipped pass starts lying.
local function stripDebugBlocks(src)
    -- **`loadfile` skips a UTF-8 BOM and `load` does not.** `Debind.lua` carries one, so the
    -- shipped pass died on line 1 of the first file it read while the ordinary pass had never
    -- noticed. The game reads files the way `loadfile` does.
    src = src:gsub("^\239\187\191", "");
    local out, skipping = {}, false;
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        if (line:match("^%s*%-%-@debug@%s*$")) then
            skipping = true;
        elseif (line:match("^%s*%-%-@end%-debug@%s*$")) then
            skipping = false;
        elseif (not skipping) then
            out[#out + 1] = line;
        end
    end
    return table.concat(out, "\n");
end

--- 애드온 파일들을 순서대로 로드하고 애드온 private 테이블을 돌려준다.
---
--- `addon` is optional and exists for the companion addons. `DebindStorage` is a **second** addon
--- with its own table, so its files cannot be loaded into Debind's; the caller builds the table
--- the game would have given it (with `DebindPrivate` on it, the way the real handshake does) and
--- passes it in here.
---
--- `opts.shipped` reads the shape a user gets rather than the one in the working tree, and
--- `opts.readFile` is how it gets the bytes (`run.lua`).
function M.loadAddon(root, files, addon, opts)
    addon = addon or { L = setmetatable({}, { __index = function(_, k) return k; end }) };
    opts = opts or {};
    for i = 1, #files do
        local path = root .. "/" .. files[i];
        local chunk, err;
        if (opts.shipped) then
            local src = opts.readFile(path);
            if (not src) then
                error("failed to read " .. path, 0);
            end
            chunk, err = loadstring(stripDebugBlocks(src), "@" .. path);
        else
            chunk, err = loadfile(path);
        end
        if (not chunk) then
            error("failed to load " .. path .. ": " .. tostring(err), 0);
        end
        chunk("Debind", addon);
    end
    return addon;
end


--------------------------------------------------------------------------------
-- Globals this stand-in never answered
--------------------------------------------------------------------------------

--- **A global the shim forgot reads as `nil`, and nothing about that is loud.** `SLASH_CAST1` was
--- missing, so `ConvertToMacroText` built its body around a nil, and the spec that looked for the
--- spell name inside that body found it and passed. What eventually said so was CI running lua5.1,
--- where `%s` refuses a nil -- which is luck rather than a check. Had the value flowed anywhere
--- other than a `format`, the specs would still be certifying a body the game would never produce.
---
--- So every read of a name nothing defined is recorded here and the runner fails on the list.
---
--- **The read itself is left alone.** Asking whether a global is there is an ordinary thing for an
--- addon to do, and an `__index` that raised would turn feature detection into a crash.
---
--- **Each exemption is a signature saying the specs are meant to run without that value.** A name
--- added here without a reason beside it is the hole this whole mechanism exists to close.
local ALLOWED_ABSENT = {
    -- Set by the addon itself while it loads, so they read nil right up until they do not. Every
    -- one is reached back through `_G` by another of our own files.
    DebindPublic = true, DebindPrivate = true, DebindVars = true, DebindVarsPerChar = true,
    DebindDevDB = true, DebindStorageVars = true, DebouncePublic = true, DebounceVars = true,
    DebounceVarsPerChar = true, Debounce_CompartmentFunc = true, DebindStorage = true,

    -- Asked as "is that addon installed". No is the answer these specs want.
    Clique = true, Grid2 = true, Grid2Options = true, ClickCastFrames = true,
    DevTool = true, ViragDevTool_AddData = true, LibStub = true,

    -- **Blizzard's own unit frames, and there are none here.** `FrameRegistry` names them to
    -- register click-casting on; a spec that wants a unit frame builds its own.
    PlayerFrame = true, TargetFrame = true, TargetFrameToT = true,
    FocusFrame = true, FocusFrameToT = true, PetFrame = true,
    Boss1TargetFrame = true, Boss2TargetFrame = true, Boss3TargetFrame = true,
    Boss4TargetFrame = true, Boss5TargetFrame = true,
    CompactUnitFrame_SetUpFrame = true,

    -- **Absent is one of the two answers, and the addon asks.** `issecretvalue` arrived in 12.1
    -- and every read of it is behind `if (issecretvalue and ...)`; `EventRegistry` is asked with
    -- `~= nil` before the house-editor callback goes on. Running without them is running the
    -- older-client branch, which is a shape worth being in.
    issecretvalue = true, EventRegistry = true,

    -- `_ENV` is 5.2's and this runs on 5.1, so it is absent here the way it is absent in the
    -- game. `restricted.lua` asks for it by presence before it reaches for `setfenv`.
    _ENV = true,

    -- Reached only from a path no spec runs: the reload the migration asks for.
    ReloadUI = true,

    -- **A fixture, and the one name here that is meant to be missing.** `describe_spec` and the
    -- emission fixture both bind `PETNOSUCHCOMMAND` on purpose: a pet command the client has no
    -- slash command for is the case `SetBindingAttributes` has to refuse, and the way to be in it
    -- is to name one that does not exist.
    --
    -- **Exempted by its exact name and not by an `^SLASH_` prefix.** A prefix would have covered
    -- `SLASH_CAST1` too, which is the very miss this whole mechanism was built for -- the guard
    -- would have been shaped so that it could not catch the thing that made it necessary. Only one
    -- name is built by concatenation in practice, so there is nothing a prefix buys.
    SLASH_PETNOSUCHCOMMAND1 = true,
};

local _absent = {};

--- Starts recording. The runner calls it straight after `install()`.
function M.watchGlobals()
    local previous = getmetatable(_G);
    setmetatable(_G, {
        __index = function(_, key)
            if (type(key) == "string" and not ALLOWED_ABSENT[key]) then
                _absent[key] = true;
            end
            if (previous and previous.__index) then
                return previous.__index(_G, key);
            end
            return nil;
        end,
    });
end

--- The names that were read while nothing defined them, sorted. Empty is the passing answer.
function M.absentGlobals()
    local names = {};
    for name in pairs(_absent) do
        names[#names + 1] = name;
    end
    table.sort(names);
    return names;
end

return M;
