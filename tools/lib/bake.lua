-- Bakes a snippet body, or reads a constant table out, for the tools that check them.
--
-- `bake.js` runs this with the same lua5.1 the game and CI use, and hands the body across in a
-- file: bytes go out and come back untouched that way, where a pipe on Windows would translate
-- newlines and the golden is locked byte for byte.
--
--   lua5.1 tools/lib/bake.lua live|shipped <requestFile> <responseFile>
--   lua5.1 tools/lib/bake.lua constants <tableNameFile> <responseFile>

local mode, requestPath, responsePath = ...;
assert(mode and requestPath and responsePath, "usage: bake.lua <mode> <request> <response>");

local here = arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]+$") or "tools/lib";
local srcDir = here .. "/../../Debind";

local function readFile(path)
    local file = assert(io.open(path, "rb"), path .. " could not be opened");
    local contents = file:read("*a");
    file:close();
    return contents;
end

local function writeFile(path, contents)
    local file = assert(io.open(path, "wb"));
    file:write(contents);
    file:close();
end

--- Runs one addon file the way the game does, handing it `local _, DebindPrivate = ...`.
local function runAddonFile(file, private)
    local chunk = assert(loadfile(srcDir .. "/" .. file));
    chunk("Debind", private);
end

--- What `Constants.lua` reads from the client while it loads.
---
--- **None of these is a rule of ours.** They are the client's own values, so a wrong one here is a
--- lie rather than a drift, and there is nothing in the repo to compare it against. Take them from
--- `reference/wow-ui-source/` when adding one.
local function installWowGlobals()
    _G.format = string.format;
    _G.tremove = table.remove;
    _G.MAX_PARTY_MEMBERS = 4;
    _G.MAX_RAID_MEMBERS = 40;
    _G.MAX_ARENA_ENEMIES = 5;
    _G.UnitClass = function() return "Warrior", "WARRIOR", 1; end
    -- The class table Constants.lua builds at load (CLASS_IDS). One real answer is enough: nothing
    -- baked reads that table, and what the loop needs is a call that does not raise and a range
    -- that ends.
    _G.C_CreatureInfo = {
        GetClassInfo = function(classID)
            if (classID == 1) then return { classFile = "WARRIOR" }; end
            return nil;
        end,
    };
end

--- `Snippets.lua` alone, on an empty `Constants`.
---
--- Nothing on this path looks at a constant's value, which is also why it stops short of
--- `BakeSnippet` -- that one does need the real ones.
local function loadSnippetsOnly()
    local private = { Constants = {} };
    runAddonFile("Snippets.lua", private);
    return private;
end

--- `Constants.lua` really loaded, so `BakeSnippet` itself can run, `CONSTANTS.*` included.
local function loadWithConstants()
    installWowGlobals();
    local private = {};
    -- The order is not free: `Snippets.lua` takes `DebindPrivate.Constants` as a local at load.
    runAddonFile("Constants.lua", private);
    runAddonFile("Snippets.lua", private);
    return private;
end

if (mode == "live") then
    local private = loadSnippetsOnly();
    local body = readFile(requestPath);
    writeFile(responsePath,
        private.applyProbesForTools(private.StripSnippetComments(body), private.SNIPPET_PROBES_LIVE));

elseif (mode == "shipped") then
    local private = loadWithConstants();
    writeFile(responsePath, private.BakeSnippet(readFile(requestPath)));

elseif (mode == "constants") then
    local private = loadWithConstants();
    local name = readFile(requestPath);
    local t = private.Constants[name];
    assert(t, "no such constant table: " .. name);
    local out = {};
    for k, v in pairs(t) do
        assert(type(v) == "string", name .. "." .. k .. " is not a string");
        out[#out + 1] = k .. string.char(9) .. v;
    end
    table.sort(out);
    writeFile(responsePath, table.concat(out, string.char(10)));

else
    error("unknown mode: " .. tostring(mode), 0);
end
