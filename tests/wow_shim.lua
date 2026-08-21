-- 게임 없이 애드온 파일을 로드하기 위한 최소 WoW 환경.
-- 순수 Lua 5.1/5.3 양쪽에서 돌아야 함 (CI의 lua 바이너리 + 로컬 fengari).

local M = {};

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
    _G.UnitExists = function() return false; end

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
    _G.C_MountJournal = { GetMountInfoByID = function() end };
    _G.C_Spell = { GetSpellSubtext = function() end, GetSpellInfo = function() end };
    -- 이벤트를 듣기만 하는 프레임(플라이아웃 아이콘 표 무효화 등). 아무것도 안 하는 껍데기면
    -- 되지만, 없으면 파일이 로드되다 죽는다.
    _G.CreateFrame = function()
        return {
            RegisterEvent = function() end,
            UnregisterEvent = function() end,
            SetScript = function() end,
        };
    end
    _G.SLASH_SCRIPT1 = "/script";
    _G.SLASH_CANCELFORM1 = "/cancelform";
end

--- 애드온 파일들을 순서대로 로드하고 애드온 private 테이블을 돌려준다.
---
--- `addon` is optional and exists for the companion addons. `DebindStorage` is a **second** addon
--- with its own table, so its files cannot be loaded into Debind's; the caller builds the table
--- the game would have given it (with `DebindPrivate` on it, the way the real handshake does) and
--- passes it in here.
function M.loadAddon(root, files, addon)
    addon = addon or { L = setmetatable({}, { __index = function(_, k) return k; end }) };
    for i = 1, #files do
        local path = root .. "/" .. files[i];
        local chunk, err = loadfile(path);
        if (not chunk) then
            error("failed to load " .. path .. ": " .. tostring(err), 0);
        end
        chunk("Debind", addon);
    end
    return addon;
end

return M;
