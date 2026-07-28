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

local function copyTable(src)
    local dest = {};
    for k, v in pairs(src) do
        if (type(v) == "table") then
            dest[k] = copyTable(v);
        else
            dest[k] = v;
        end
    end
    return dest;
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

    _G.format = string.format;
    _G.strmatch = string.match;
    _G.strsub = string.sub;
    _G.strfind = string.find;
    _G.strlower = string.lower;
    _G.strupper = string.upper;
    _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")); end
    _G.strsplit = function() error("strsplit: not stubbed"); end
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
end

--- 애드온 파일들을 순서대로 로드하고 애드온 private 테이블을 돌려준다.
function M.loadAddon(root, files)
    local addon = { L = setmetatable({}, { __index = function(_, k) return k; end }) };
    for i = 1, #files do
        local path = root .. "/" .. files[i];
        local chunk, err = loadfile(path);
        if (not chunk) then
            error("failed to load " .. path .. ": " .. tostring(err), 0);
        end
        chunk("Debounce", addon);
    end
    return addon;
end

return M;
