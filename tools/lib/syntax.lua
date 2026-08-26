-- Compiles one chunk and reports what 5.1 says about it. Nothing is run.
--
-- `check-snippets.js` asks. The parser has to be the game's, not one that also knows 5.2 and 5.3:
-- a `goto` or a `//` reads fine to those and leaves the restricted environment with a body it
-- cannot compile, which shows up as one key quietly not working.
--
--   lua5.1 tools/lib/syntax.lua <chunkName> <sourceFile> <responseFile>

local name, sourcePath, responsePath = ...;
assert(name and sourcePath and responsePath, "usage: syntax.lua <name> <source> <response>");

local source = assert(io.open(sourcePath, "rb"), sourcePath .. " could not be opened");
local contents = source:read("*a");
source:close();

local _, err = loadstring(contents, "@" .. name);

local out = assert(io.open(responsePath, "wb"));
out:write(err or "");
out:close();
