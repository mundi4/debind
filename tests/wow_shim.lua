-- 게임 없이 애드온 파일을 로드하기 위한 최소 WoW 환경.
-- 순수 Lua 5.1/5.3 양쪽에서 돌아야 함 (CI의 lua 바이너리 + 로컬 fengari).

local M = {};

local frames = require("wow_frames");
M.frames = frames;

--- The client facts the value-returning stand-ins answer from. A spec fills in what it needs and
--- everything else stays absent, which is not the same as a default -- see the comment on
--- `C_Spell` in `install`.
M.world = {
    spells = {},
    baseSpells = {},
    mounts = {},
    callPetSlots = {},
    flyouts = {},
    inCombat = false,
    bindings = {},
    units = {},
    bindingContexts = {},
    activeBindingContexts = {},
    macros = {},
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
--- `DebindStorage/` and `DebindTest/`, and every locale file carries some.
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
local positionalFormat;   -- defined below, after the float fixup it calls

--- **fengari's bare `%f` is not C's.** `string.format("%f", 0.5)` answers `0.5` there and
--- `0.500000` under every real interpreter, the client's 5.1 included. `Flyout.lua` bakes a
--- threshold into a snippet body with a bare `%f`, so the same rebuild produced two different
--- snippets depending on which interpreter ran it -- and the emission golden, which is compared
--- byte for byte, could then only ever hold for one of them.
---
--- C's default precision is 6 and this writes it in. **Only a bare `%f` moves**: a precision that
--- was spelled out (`%.2f`, `%5.1f`) already answers the same both ways.
local function normalizeBareFloat(fmt)
    if (not strfind(fmt, "f", 1, true)) then
        return fmt;
    end

    local out, i = {}, 1;
    while (true) do
        local at = strfind(fmt, "%", i, true);
        if (not at) then
            out[#out + 1] = strsub(fmt, i);
            break;
        end
        out[#out + 1] = strsub(fmt, i, at - 1);

        if (strsub(fmt, at + 1, at + 1) == "%") then
            out[#out + 1] = "%%";
            i = at + 2;
        else
            local spec, after = strmatch(fmt, "^%%([-+ #0]*%d*%.?%d*)()", at);
            local conv = strsub(fmt, after, after);
            if ((conv == "f" or conv == "F") and not strfind(spec, ".", 1, true)) then
                out[#out + 1] = "%" .. spec .. ".6" .. conv;
            else
                out[#out + 1] = "%" .. spec .. conv;
            end
            i = after + 1;
        end
    end
    return table.concat(out);
end

function positionalFormat(fmt, ...)
    if (type(fmt) == "string") then
        fmt = normalizeBareFloat(fmt);
    end
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

    return rawformat(table.concat(out), (table.unpack or unpack)(ordered, 1, count));
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
        return (table.unpack or unpack)(out, 1, #out);
    end
    -- The client runs Lua 5.1, where `unpack` is a global. fengari answers 5.3 and only has
    -- `table.unpack`, so a file that calls the bare name loads under a real 5.1 and dies here --
    -- a difference that would show up as one interpreter finding a fault the other cannot.
    _G.unpack = unpack or table.unpack;
    -- 5.1 has `loadstring`; 5.3 and 5.4 renamed it to `load`. `AssertSnippetCompiles` reaches for
    -- it on every generated snippet in a DEBUG build, so the harness gets the real thing rather
    -- than a stand-in -- the compile it runs is a check worth having here too.
    _G.loadstring = loadstring or load;
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
            (table.unpack or unpack)(entry.keys or {}, 1, #(entry.keys or {}));
    end
    _G.GetBindingKey = function(action)
        for i = 1, #M.world.bindings do
            local entry = M.world.bindings[i];
            if (entry.action == action) then
                return (table.unpack or unpack)(entry.keys or {}, 1, #(entry.keys or {}));
            end
        end
    end
    _G.GetBindingText = function(key) return key; end
    _G.GetBindingAction = function(key)
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
    _G.C_AddOns = {
        LoadAddOn = function() return true; end,
        IsAddOnLoaded = function() return false; end,
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

    _G.SLASH_SCRIPT1 = "/script";
    _G.SLASH_CANCELFORM1 = "/cancelform";
    -- A pet command that has a slash command, so `GetPetActionMacroText` answers for it. The
    -- commands that have none are the ones the addon refuses to bind, and reaching that branch is
    -- a matter of naming one that is not here.
    _G.SLASH_PETATTACK1 = "/petattack";
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
--- `opts.readFile` is how it gets the bytes -- fengari has no `io.open`, so the runner hands its
--- own reader down (`run.lua`).
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
            chunk, err = load(stripDebugBlocks(src), "@" .. path);
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

return M;
