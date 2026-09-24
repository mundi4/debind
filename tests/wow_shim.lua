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
    spellbook = {},
    --- The ids in `spellbook` that are a lower rank of another. Only the camelot world reads it.
    lowRanks = {},
    baseSpells = {},
    overrideSpells = {},
    --- 이름으로 물었을 때 답할 주문 id. **비워 두면 `spells`에서 이름이 같은 것을 찾는다**,
    --- 그러니까 덮인 것이 없는 평범한 상태다.
    ---
    --- **오버라이드를 세우는 자리가 여기다.** 클라이언트는 이름을 그때그때 풀고, 덮인 주문이
    --- 있으면 그쪽을 답한다 - `GetSpellInfo("Celestial Alignment")`가
    --- `Incarnation: Chosen of Elune`를 낸다(2026-09-21, 소유자가 게임에서). 그래서 굽힌 이름
    --- 하나가 상황에 따라 다른 주문을 가리킨다.
    castNames = {},
    --- Which spell ids `[known:<id>]` answers true for. Empty is a character who knows none of
    --- them, which is what a spec that never mentions one gets.
    knownSpells = {},
    --- The talent configuration, empty for a character who has none.
    traits = {},
    pvpTalentSlots = {},
    pvpTalents = {},
    mounts = {},
    callPetSlots = {},
    flyouts = {},
    inCombat = false,
    bindings = {},
    units = {},
    bindingContexts = {},
    activeBindingContexts = {},
    inPetBattle = false,
    macros = {},
    --- `[itemID] = { name = ..., icon = ... }`: the items the client's cache holds. An item left out
    --- is one this session has not seen, which is when the client answers nil by id and by name.
    items = {},
    equipped = {},
    --- The dialogs `StaticPopup_Show` was asked for, in order, as `{ which, ... }`.
    popups = {},
};

--- Puts the world back to empty and reinstalls every stand-in over it.
---
--- **A spec that overwrites a global keeps it for the whole run otherwise**, and the next spec
--- inherits a client somebody else configured. That was not theoretical: `emit_fixture` never
--- installed a macro store and passed anyway, on whichever `_G.GetMacroInfo` the spec before it
--- had left behind, and reversing the spec list was what said so (§10-1).
---
--- `client` picks which client the stand-ins answer as: nil is retail, `"camelot"` is the camelot
--- client as `DebindCamelotProbe` measured it (`preparing-the-code-for-camelot.md` §4). **It has to
--- be chosen here, before the addon loads**, because files take client answers into upvalues as
--- they are read (`NUM_SPECS` in `Profile.lua`).
function M.resetWorld(client)
    for key, value in pairs(M.world) do
        if (type(value) == "table") then
            for k in pairs(value) do value[k] = nil; end
        end
    end
    M.world.inCombat = false;
    M.world.specIndex = nil;
    M.world.client = client;
    --- **The one global an addon instance leaves behind.** `ClickCastTable.lua` puts its own table
    --- under this name at file scope, and the next instance would meet it as a foreign holder and
    --- wrap its metatable, one more layer per spec (code review, 2026-09-08).
    _G.ClickCastFrames = nil;
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

local function bxor(a, b)
    a, b = norm(a), norm(b);
    local res, bitval = 0, 1;
    while a > 0 or b > 0 do
        if (a % 2 ~= b % 2) then
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
    _G.bit = { band = band, bor = bor, bxor = bxor, bnot = bnot, lshift = lshift, rshift = rshift };

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
    -- 클라이언트가 내는 것과 같은 이스케이프. 무엇이 그려지는지는 화면에서만 보이고, 스펙이
    -- 재는 것은 글자가 붙었느냐다.
    _G.CreateAtlasMarkup = function(name, height, width)
        return format("|A:%s:%d:%d|a", name, height or 0, width or 0);
    end
    _G.CreateSimpleTextureMarkup = function(file, width, height, xOffset, yOffset)
        return format("|T%s:%d:%d:%d:%d|t", file, height or width, width, xOffset or 0, yOffset or 0);
    end
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
    --- **소환수까지 참인 쪽이라 위 둘보다 넓다** (`macro-conditionals.md` 3.1절). 제한 환경이
    --- 가진 것이 이쪽이고, 유닛 소속 축이 두 경로에서 부르는 것도 이쪽이다.
    ---
    --- 두 값이 겹치는 것을 세계가 그대로 들고 있어야 한다. 공대에서 같은 소그룹인 유닛은
    --- **둘 다 참**이다(2026-09-07 인게임 확인). 스텁이 하나를 거짓으로 만들면 그 칸을
    --- 가르는 스펙이 무엇을 넣어도 통과한다.
    _G.UnitPlayerOrPetInParty = function(token)
        local unit = M.world.units[token];
        return (unit and unit.inParty) and true or false;
    end
    _G.UnitPlayerOrPetInRaid = function(token)
        local unit = M.world.units[token];
        return (unit and unit.inRaid) and true or false;
    end

    --- The world the non-secure side asks about while it rebuilds. Every one of these is a value
    --- returning query, the cheap side to mock (§4 of
    --- `going-headless-outside-the-ui.md`), and the answers come out of `M.world` so a
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
    --- **The insecure side's copy, and it answers only `[known:]`.** That is the one conditional
    --- a rebuild hands this global (`UpdateBindings.lua` settles a fixed `known` here); the
    --- restricted environment has its own reader with the whole grammar (`tests/restricted.lua`).
    --- Everything else keeps answering the empty string, which is a match.
    _G.SecureCmdOptionParse = function(expr)
        local argument = expr and expr:match("^%[known:(.+)%]$");
        if (argument) then
            local spellID = tonumber(argument);
            if (not spellID) then
                -- **A name answers for whichever id carries it.** The client reads the argument as
                -- a name when it is not a number, and a condition stores one
                -- (`making-known-a-spell-name.md`). Two ids sharing a name is the case
                -- this has to get right, and one of them being known is enough.
                for id, spell in pairs(M.world.spells) do
                    if (spell.name == argument and M.world.knownSpells[id]) then
                        return "";
                    end
                end
                return nil;
            end
            return M.world.knownSpells[spellID] and "" or nil;
        end
        return "";
    end

    --- The game's own binding table, which the addon reads and never writes: `BindingContexts.lua`
    --- walks the whole table to find the keys an open editor has claimed, and the restricted side
    --- asks what each `ACTIONBUTTON` sits on. `M.world.bindings` is a list of
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
    _G.C_PetBattles = {
        IsInBattle = function() return M.world.inPetBattle; end,
    };
    -- The page numbers the probe read on retail (§4-5 of `dropping-the-game-fallback.md`),
    -- and a client whose slots hold nothing.
    _G.C_ActionBar = {
        GetExtraBarIndex = function() return 19; end,
        GetActionBarPage = function() return 1; end,
    };
    _G.GetActionTexture = function() return nil; end
    -- A character with no stances and no pet.
    _G.GetShapeshiftFormInfo = function() return nil; end
    _G.GetPetActionInfo = function() return nil; end
    -- The world markers the command tab lists (`Blizzard_CompactRaidFrameManager.lua`), with the
    -- enUS names stripped of their icon and colour.
    -- The headings the command tab files a binding under, as enUS has them.
    _G.BINDING_HEADER_CAMERA = "Camera";
    _G.BINDING_HEADER_CHAT = "Chat";
    _G.BINDING_HEADER_INTERFACE = "Interface Panel";
    _G.BINDING_HEADER_MISC = "Miscellaneous";
    _G.BINDING_HEADER_MOVEMENT = "Movement Keys";
    _G.BINDING_HEADER_OTHER = "Other";
    _G.BINDING_HEADER_RAID_TARGET = "Target Markers";
    _G.BINDING_HEADER_TARGETING = "Targeting";
    _G.BINDING_HEADER_VEHICLE = "Vehicle Controls";
    _G.NUM_WORLD_RAID_MARKERS = 8;
    _G.WORLD_RAID_MARKER_ORDER = { 8, 4, 1, 7, 2, 3, 6, 5 };
    for i, colour in ipairs({ "Blue", "Green", "Purple", "Red", "Yellow", "Orange", "Silver", "White" }) do
        _G["WORLD_MARKER" .. i] = colour .. " World Marker";
    end

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

    --- The specializations of the classes below, by class id, as the client hands them out:
    --- the named ones at 1.. and the nameless initial one at `INITIAL_SPEC_INDEX`, whatever the
    --- count of the named ones is. **The gap is the point.** A class with fewer than four named
    --- specializations still has its initial one at 5 and nothing at the indices in between, so
    --- anything that walks a class by counting would come out wrong here and only here.
    ---
    --- The druid's four are in the client's order, so index 1 is Balance and 4 is Restoration.
    --- `SpecSpells.lua` keys its tables by those ids.
    local INITIAL_SPEC_INDEX = 5;
    local SPECS_BY_CLASS = {
        [1]  = { named = { { 71, "Arms" }, { 72, "Fury" }, { 73, "Protection" } }, initial = 1446 },
        [2]  = { named = { { 65, "Holy" }, { 66, "Protection" }, { 70, "Retribution" } }, initial = 1451 },
        [8]  = { named = { { 62, "Arcane" }, { 63, "Fire" }, { 64, "Frost" } }, initial = 1449 },
        [11] = { named = { { 102, "Balance" }, { 103, "Feral" }, { 104, "Guardian" },
                           { 105, "Restoration" } }, initial = 1447 },
    };

    --- **Camelot: nine classes, one specialization each, and no initial one** (probe, 69977).
    local camelot = M.world.client == "camelot";
    if (camelot) then
        SPECS_BY_CLASS = {
            [1] = { named = { { 1491, "Warrior" } } },
            [2] = { named = { { 1486, "Paladin" } } },
            [3] = { named = { { 1485, "Hunter" } } },
            [4] = { named = { { 1488, "Rogue" } } },
            [5] = { named = { { 1487, "Priest" } } },
            [7] = { named = { { 1489, "Shaman" } } },
            [8] = { named = { { 1482, "Mage" } } },
            [9] = { named = { { 1490, "Warlock" } } },
            [11] = { named = { { 1484, "Druid" } } },
        };
    end

    --- One class's specialization at one index, as the two calls below both answer it.
    local function SpecOfClass(classID, index)
        local specs = SPECS_BY_CLASS[classID];
        if (not specs) then
            return nil;
        end
        if (index == INITIAL_SPEC_INDEX) then
            return specs.initial;
        end
        local spec = specs.named[index];
        if (not spec) then
            return nil;
        end
        return spec[1], spec[2];
    end

    _G.C_SpecializationInfo = {
        --- **The named ones only.** The initial specialization sits past this count, which is what
        --- `IsInitialSpec` means by an index greater than the number of specializations.
        GetNumSpecializationsForClassID = function(classID)
            local specs = SPECS_BY_CLASS[classID];
            return specs and #specs.named or 0;
        end,
        GetSpecialization = function() return M.world.specIndex or 1; end,
        --- This character's class, which the shim plays as a druid.
        GetSpecializationInfo = function(index)
            return SpecOfClass(11, index);
        end,
    };

    --- A global rather than one of `C_SpecializationInfo`'s, the way the client has it.
    _G.GetSpecializationInfoForClassID = SpecOfClass;

    --- The playable classes, as the client lists them. **The argument is a position in that list
    --- and not a class id**, and the ids here have gaps in them for the same reason the client's
    --- do, so anything reading the index as an id comes out wrong.
    local PLAYABLE_CLASSES = {
        { "Warrior", "WARRIOR", 1 },
        { "Paladin", "PALADIN", 2 },
        { "Mage", "MAGE", 8 },
        { "Druid", "DRUID", 11 },
    };
    local numClasses = #PLAYABLE_CLASSES;
    --- **Camelot answers by class id with holes, and counts only the classes that are there**: 9,
    --- while index 6 and 10 are empty and Druid is at 11. The list of ids the client itself walks
    --- is `GetAllClassIDs`, which only camelot has (probe, 69977).
    if (camelot) then
        PLAYABLE_CLASSES = {
            [1] = { "Warrior", "WARRIOR", 1 }, [2] = { "Paladin", "PALADIN", 2 },
            [3] = { "Hunter", "HUNTER", 3 }, [4] = { "Rogue", "ROGUE", 4 },
            [5] = { "Priest", "PRIEST", 5 }, [7] = { "Shaman", "SHAMAN", 7 },
            [8] = { "Mage", "MAGE", 8 }, [9] = { "Warlock", "WARLOCK", 9 },
            [11] = { "Druid", "DRUID", 11 },
        };
        numClasses = 9;
        _G.C_SpecializationInfo.GetAllClassIDs = function() return { 1, 2, 3, 4, 5, 7, 8, 9, 11 }; end
    end
    _G.GetNumClasses = function() return numClasses; end
    _G.GetClassInfo = function(index)
        local class = PLAYABLE_CLASSES[index];
        if (not class) then
            return nil;
        end
        return class[1], class[2], class[3];
    end

    --- The spellbook as `FindSpellBookSlotBySpellID` sees it: a set of ids, and a slot for any id
    --- in it. **One stub for both sides** -- the restricted environment gets this global handed to
    --- it (`ENV.FindSpellBookSlotBySpellID`) and the insecure side calls the same name
    --- (`Spells.SettleKnown`), so a spec that stands an id in the book gets one answer everywhere.
    _G.FindSpellBookSlotBySpellID = function(spellID)
        return M.world.spellbook[spellID] and 1 or nil;
    end

    --- That same set as an ordered list, which is what a slot number indexes.
    local function BookSlots()
        local ids = {};
        for spellID in pairs(M.world.spellbook) do
            ids[#ids + 1] = spellID;
        end
        table.sort(ids);
        return ids;
    end

    --- The talent tree, flat. `M.world.traits` is `{ configID =, treeIDs =, trees =, nodes =,
    --- entries =, definitions = }`; empty is a character with no configuration, which is what
    --- every spec that does not care about talents gets.
    _G.C_ClassTalents = {
        GetActiveConfigID = function() return M.world.traits.configID; end,
        --- The hero trees this specialization is offered, **in the order the talent window lays
        --- them out** -- which is what the condition menu's two hero rows follow. Nothing means a
        --- specialization that has none.
        GetHeroTalentSpecsForClassSpec = function()
            return M.world.traits.heroSpecs;
        end,
    };
    _G.C_Traits = {
        GetConfigInfo = function(configID)
            if (configID ~= M.world.traits.configID) then return nil; end
            return { treeIDs = M.world.traits.treeIDs };
        end,
        GetTreeNodes = function(treeID) return (M.world.traits.trees or {})[treeID]; end,
        GetNodeInfo = function(_, nodeID) return (M.world.traits.nodes or {})[nodeID]; end,
        GetEntryInfo = function(_, entryID) return (M.world.traits.entries or {})[entryID]; end,
        GetDefinitionInfo = function(definitionID)
            return (M.world.traits.definitions or {})[definitionID];
        end,
        --- The three the talent condition's **menu** reads (`Talents.lua`): the tree's
        --- currencies tell the class panel from the specialization one, a node's cost says which
        --- of them it belongs to, and a subtree is a hero tree. Empty is a world that says every
        --- node is the specialization's, which is what a spec that does not care about the split
        --- gets.
        GetTreeCurrencyInfo = function() return M.world.traits.currencies or {}; end,
        GetNodeCost = function(_, nodeID) return (M.world.traits.costs or {})[nodeID]; end,
        GetSubTreeInfo = function(_, subTreeID)
            return (M.world.traits.subTrees or {})[subTreeID];
        end,
    };
    _G.C_SpecializationInfo.GetPvpTalentSlotInfo = function(slot)
        return M.world.pvpTalentSlots[slot];
    end
    _G.C_SpecializationInfo.GetPvpTalentInfo = function(talentID)
        return M.world.pvpTalents[talentID];
    end

    -- `MAGE` is here because the sharing specs need **a class that is not ours**: a string from one
    -- keeps its own class and spec on the way in, and the import refuses a class name no client
    -- has (`ImportAddress`). Without it those cases would measure the refusal instead.
    --- **The name rides with the token**, the way the client hands them over together: it is where
    --- `Constants.CLASS_NAMES` comes from, and a screen naming a class reads that.
    local CLASS_FILES = {
        [1] = { "WARRIOR", "Warrior" },
        [2] = { "PALADIN", "Paladin" },
        [8] = { "MAGE", "Mage" },
        [11] = { "DRUID", "Druid" },
    };
    if (camelot) then
        CLASS_FILES = {};
        for id, class in pairs(PLAYABLE_CLASSES) do
            CLASS_FILES[id] = { class[2], class[1] };
        end
    end
    _G.C_CreatureInfo = {
        GetClassInfo = function(classId)
            local class = CLASS_FILES[classId];
            if (not class) then
                return nil;
            end
            return { classFile = class[1], className = class[2], classID = classId };
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
        --- **Nothing installed**, the same answer `GetNumAddOns` gives. A spec that wants a pack
        --- row drawn stands its addon up here itself. The client answers this one for an addon
        --- that is installed and turned off, which is what the pack rows are drawn from.
        GetAddOnInfo = function() return nil; end,
    };

    -- What `MacroText.lua` reaches at file scope. It has nothing to do with the macro text parser,
    -- but the file does not load without it.
    --
    -- **They answer out of `M.world`, and it starts empty.** Every one of these is a query
    -- returning a value, which is the cheap side to mock (§4 of
    -- `going-headless-outside-the-ui.md`), but nothing here invents an answer for an id
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
    --- **`ItemInfo` takes an id or a name** (`ItemDocumentation.lua`), and the name is what an item
    --- imported by name asks with. Either way it answers only for an item `items` holds.
    local function ItemFor(itemInfo)
        if (type(itemInfo) == "number") then
            return M.world.items[itemInfo];
        end
        for _, item in pairs(M.world.items) do
            if (item.name == itemInfo) then
                return item;
            end
        end
    end
    _G.C_Item = {
        GetItemNameByID = function(itemInfo)
            local item = ItemFor(itemInfo);
            return item and item.name;
        end,
        GetItemIconByID = function(itemInfo)
            local item = ItemFor(itemInfo);
            return item and item.icon;
        end,
    };
    --- **`SpellIdentifier`는 id도 이름도 받는다**, 그리고 이름 쪽이 이 저장소에 중요하다.
    --- 버튼에 굽는 것은 이름이고(`*spell-`), 클릭 때 그 이름으로 다시 묻는 자리가 있다.
    ---
    --- 이름은 `castNames`가 먼저 답하고, 없으면 `spells`에서 이름이 같은 것을 찾는다. 부제까지
    --- 붙은 꼴(`이름(부제)`)도 같은 이름으로 읽는다 - `ComposeSpellCastName`이 굽는 모양이다.
    local function SpellFor(identifier)
        if (type(identifier) == "number") then
            return M.world.spells[identifier];
        end
        if (type(identifier) ~= "string") then
            return nil;
        end
        local byName = M.world.castNames[identifier];
        if (byName) then
            return M.world.spells[byName];
        end
        local bare = identifier:match("^(.-)%b()$") or identifier;
        for _, spell in pairs(M.world.spells) do
            if (spell.name == bare or spell.name == identifier) then
                return spell;
            end
        end
        return nil;
    end

    _G.C_Spell = {
        GetSpellInfo = function(identifier) return SpellFor(identifier); end,
        GetSpellName = function(identifier)
            local spell = SpellFor(identifier);
            return spell and spell.name;
        end,
        GetSpellSubtext = function(identifier)
            local spell = SpellFor(identifier);
            return spell and spell.subtext;
        end,
        IsPressHoldReleaseSpell = function(identifier)
            local spell = SpellFor(identifier);
            return (spell and spell.pressAndHold) and true or false;
        end,
        IsSpellPassive = function(identifier)
            local spell = SpellFor(identifier);
            return (spell and spell.passive) and true or false;
        end,
    };
    --- Both clients have it (the camelot probe found it). Nothing to suggest, which is what a
    --- character without assisted combat set up gets.
    _G.C_AssistedCombat = {
        GetActionSpell = function() return nil; end,
    };
    --- Every atlas answers, square, except the ones camelot was measured without (69977).
    local CAMELOT_MISSING_ATLASES = {
        ["common-icon-minus"] = true,
        ["communities-icon-minus"] = true,
        ["Campaign_HeaderIcon_Minus"] = true,
    };
    local ATLAS_SIZES = { ["common-button-list-minus"] = { 13, 4 } };
    _G.C_Texture = {
        GetAtlasInfo = function(name)
            if (camelot and CAMELOT_MISSING_ATLASES[name]) then
                return nil;
            end
            local size = ATLAS_SIZES[name] or { 16, 16 };
            return { width = size[1], height = size[2] };
        end,
    };
    --- **These two take an id and nothing else**, where `C_Spell` above also takes a name: the
    --- client's own documentation types the argument `number` (`SpellBookDocumentation.lua`).
    --- Answering a name with nil instead would let a stored spell name reach them unnoticed. A nil
    --- is let through, since the documentation's `Nilable` is not to be trusted.
    local function RequireSpellID(spellID, api)
        if (spellID ~= nil and type(spellID) ~= "number") then
            error(format("bad argument #1 to '%s' (number expected, got %s)", api, type(spellID)), 3);
        end
    end
    _G.C_SpellBook = {
        --- The id an override points back at. Absent from the table means "this id is its own
        --- base", which is what the client answers for every spell that is not overridden.
        FindBaseSpellByID = function(spellID)
            RequireSpellID(spellID, "FindBaseSpellByID");
            return M.world.baseSpells[spellID];
        end,
        --- The other direction: what this spell has *become*. A talent or a form replaces a spell
        --- while it holds, and the name a reader is shown is the replacement's -- so a stand-in
        --- that always answered the id back would hide the whole branch.
        ---
        --- `M.world.overrideSpells[id]` is the replacement; absent means nothing is overriding it,
        --- which the client answers as the id itself.
        FindSpellOverrideByID = function(spellID)
            RequireSpellID(spellID, "FindSpellOverrideByID");
            return M.world.overrideSpells[spellID] or spellID;
        end,
        --- `M.world.spellbook` again, this time as the **skill-line walk** sees it: one
        --- player-bank line holding every id in it, in id order so a slot number means the same
        --- thing on two reads. What a spell is learned at comes off
        --- `M.world.spells[id].levelLearned`, and an id without one answers no level at all --
        --- the shape `Spells` reads as a spell the book cannot date.
        --- No pet, which is what a spec that does not stand one up gets. The client answers nil
        --- rather than 0 then.
        HasPetSpells = function() return nil; end,
        GetNumSpellBookSkillLines = function() return 1; end,
        GetSpellBookSkillLineInfo = function(index)
            if (index ~= 1) then return nil; end
            return { itemIndexOffset = 0, numSpellBookItems = #BookSlots() };
        end,
        GetSpellBookItemInfo = function(slot, bank)
            local spellID = bank == Enum.SpellBookSpellBank.Player and BookSlots()[slot];
            if (not spellID) then return nil; end
            return {
                spellID = spellID,
                actionID = spellID,
                itemType = Enum.SpellBookItemType.Spell,
            };
        end,
        GetSpellBookItemLevelLearned = function(slot, bank)
            local spellID = bank == Enum.SpellBookSpellBank.Player and BookSlots()[slot];
            local spell = spellID and M.world.spells[spellID];
            return spell and spell.levelLearned;
        end,
    };
    --- **Only camelot has spell ranks, and only it has this call.** A low rank is an id in
    --- `M.world.lowRanks`.
    ---
    --- **Camelot's book has a line per talent tree and none for the class** (a druid on 69977:
    --- General, Restoration, Balance). The class line comes from a call only that client has. The
    --- book's spells stay on the first line, so a walk reads the same ids either way.
    if (camelot) then
        _G.C_SpellBook.IsSpellBookItemLowRank = function(slot, bank)
            local spellID = bank == Enum.SpellBookSpellBank.Player and BookSlots()[slot];
            return spellID and M.world.lowRanks[spellID] or false;
        end
        local LINES = { { "General", 136830 }, { "Restoration", 136041 }, { "Balance", 136096 } };
        _G.C_SpellBook.GetNumSpellBookSkillLines = function() return #LINES; end
        _G.C_SpellBook.GetSpellBookSkillLineInfo = function(index)
            local line = LINES[index];
            if (not line) then return nil; end
            local count = #BookSlots();
            return { name = line[1], iconID = line[2], itemIndexOffset = index == 1 and 0 or count,
                numSpellBookItems = index == 1 and count or 0 };
        end
        _G.C_SpellBook.GetClassSkillLineInfo = function()
            return { name = "Druid", iconID = 625999, itemIndexOffset = 0, numSpellBookItems = 0 };
        end
    end
    --- A flyout and its slots. `M.world.flyouts[id]` is `{ name =, slots = { spellID… } }`; a
    --- flyout the world does not name answers with no slot count at all, which is the "not
    --- learned" case and the one that makes `SetBindingAttributes` refuse to bind the key.
    ---
    --- **Camelot raises instead** for a flyout it does not have: `GetFlyoutInfo(229)`, the
    --- skyriding one, came back "No flyout found for ID" on 69977.
    _G.GetFlyoutInfo = function(flyoutID)
        local flyout = M.world.flyouts[flyoutID];
        if (not flyout and camelot) then
            error("No flyout found for ID=" .. tostring(flyoutID), 2);
        end
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
    -- (`going-headless-outside-the-ui.md` §4).
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

    --- The client's colour objects, down to the two methods the addon uses on them. The wrap is the
    --- real escape sequence rather than a passthrough, so a spec reading a tooltip line back sees
    --- what a reader would -- including a colour that swallowed the text it was meant to wrap.
    ---
    --- **`GetRGB` is here because a `MenuKit` row paints its label with whatever colour an issue
    --- resolved to** (`MenuKit.lua`), so a colour without it turned every row carrying a problem
    --- into a crash the moment a spec drew one.
    local function color(code)
        local r = tonumber(code:sub(3, 4), 16) / 255;
        local g = tonumber(code:sub(5, 6), 16) / 255;
        local b = tonumber(code:sub(7, 8), 16) / 255;
        return {
            WrapTextInColorCode = function(_, text) return "|c" .. code .. text .. "|r"; end,
            GetRGB = function() return r, g, b; end,
        };
    end
    _G.DISABLED_FONT_COLOR = color("ff808080");
    _G.ERROR_COLOR = color("ffff2020");
    _G.INACTIVE_COLOR = color("ff7f7f7f");
    _G.BRIGHTBLUE_FONT_COLOR = color("ff00b0ff");
    _G.ORANGE_FONT_COLOR = color("ffff7f3f");
    _G.NORMAL_FONT_COLOR = color("ffffd100");
    _G.GREEN_FONT_COLOR = color("ff19ff19");

    --- **A colour per class, so a spec reading a line back can tell two of them apart.** The codes
    --- are this file's own rather than the client's; what a case asks is which class a name was
    --- painted with, and any two distinct codes answer that.
    local CLASS_COLORS = {
        WARRIOR = color("ffc79c6e"),
        PALADIN = color("fff58cba"),
        MAGE = color("ff69ccf0"),
        DRUID = color("ffff7d0a"),
    };
    _G.GetClassColorObj = function(classFile) return CLASS_COLORS[classFile]; end

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

    --- **The colour comes along.** A grade decides it (`Issues.lua`'s `GetIssueColor`), so a spec
    --- that only saw "not an error line" could not tell the warning colour from any other.
    _G.GameTooltip_AddColoredLine = function(tooltip, text, color, wrap, leftOffset)
        tooltip.lines[#tooltip.lines + 1] = {
            kind = "colored", text = text, color = color, wrap = wrap, leftOffset = leftOffset,
        };
    end
    _G.GameTooltip_AddBlankLineToTooltip = function(tooltip)
        tooltip.lines[#tooltip.lines + 1] = { kind = "blank", text = "" };
    end
    _G.GameTooltip_SetTitle = function(tooltip, text)
        tooltip.lines[#tooltip.lines + 1] = { kind = "title", text = text };
    end

    --- Where the client keeps a slash command's handler. `Public.lua` files `/debind` into it at
    --- load, so the table has to be there for that file to be read at all (`holder_spec`).
    _G.SlashCmdList = {};

    --- **Recorded rather than drawn.** `StaticPopupDialogs` is built in `DebindUI.lua`, which is
    --- not loaded here, so the dialog itself is out of reach; what a spec can ask is whether the
    --- addon decided to raise one (`Events.lua`, the unit frame notice).
    _G.StaticPopup_Show = function(which, ...)
        M.world.popups[#M.world.popups + 1] = { which, ... };
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

    --- The two words a yes/no condition row falls back to when the locale names none of its own
    --- (`MenuKit`'s `Appender:YesNo`).
    _G.YES = "Yes";
    _G.NO = "No";
    -- The value an unticked Normal Cast is drawn with in the action tooltip.
    _G.OFF = "Off";

    --- The client strings the action menu reads while it is built: the aimed unit's row names the
    --- two cast keys, and every class submenu opens on the client's own "all specializations".
    _G.AUTO_SELF_CAST_KEY_TEXT = "Self Cast Key";
    _G.FOCUS_CAST_KEY_TEXT = "Focus Cast Key";
    _G.AUTO_SELF_CAST_TEXT = "Auto Self Cast";
    _G.AUTO_DISMOUNT_FLYING_TEXT = "Auto Dismount in Flight";
    _G.ALL_SPECS = "All Specializations";
    _G.UNCHECK_ALL = "Uncheck All";
    --- The talent condition's pvp branch is named by the client, the way its class, specialization
    --- and hero branches are (`Talents.lua`).
    _G.PVP_TALENTS = "PvP Talents";

    --- **One binding command that resolves.** `ActionDisplay` asks `_G["BINDING_NAME_" .. value]`
    --- and falls back to the command code, so without a single one defined every spec walked the
    --- fallback and a command action was named by its code -- which is what a reader sees when the
    --- client has no name for it, not what they see for a real one.
    _G.BINDING_NAME_TOGGLEGAMEMENU = "Game Menu";
    -- A pet command that has a slash command, so `GetPetActionMacroText` answers for it. The
    -- commands that have none are the ones the addon refuses to bind, and reaching that branch is
    -- a matter of naming one that is not here.
    _G.SLASH_PETATTACK1 = "/petattack";

    --- 메뉴 설명자를 만드는 것 중 **커널이 스스로 부르는 하나**(`MenuKit.QueueTitle`). 다른
    --- 행은 모두 부모 설명자가 만들어 주므로 스펙이 자기 대역을 넘긴다.
    local function newTitleDescription(text)
        local initializers = {};
        return {
            text = text,
            initializers = initializers,
            AddInitializer = function(_, fn)
                initializers[#initializers + 1] = fn;
            end,
        };
    end

    --- The colour a `MenuKit` row starts from, and the one it turns while active. `GetRGB` is all
    --- either is asked for.
    _G.HIGHLIGHT_FONT_COLOR = { GetRGB = function() return 1, 1, 1; end };
    _G.BLUE_FONT_COLOR = { GetRGB = function() return 0, 0, 1; end };

    _G.MenuUtil = {
        GetElementText = function(description) return description.text; end,
        SetElementText = function(description, text) description.text = text; end,
        CreateTitle = newTitleDescription,
    };

    _G.ReloadUI = function() M.world.reloadedUI = true; end;
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

    -- The same question in HealBot's shape. It offers no table to hold, so what
    -- `AttachPackHooks` asks for is the function it hooks, and the spec that exercises that door
    -- stands both of these up itself.
    HealBot_Action_RegisterUnitEvents = true, HealBot_Emerg_Button = true,

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

    -- **The same shape, for a binding command the client does not name.** `convert_spec` converts a
    -- retired `COMMAND` whose `BINDING_NAME_*` is missing, which is what a command from an older
    -- build or another locale looks like; the conversion has to fall back to the command itself.
    BINDING_NAME_ZZZUNKNOWNCOMMAND = true,
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
