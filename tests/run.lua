-- 헤드리스 테스트 진입점.
--   lua tests/run.lua            (저장소 루트에서)
--   node tests/run.js            (lua 바이너리가 없을 때)

local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]run%.lua$") or "tests";
local repoRoot = root:match("^(.*)[/\\][^/\\]+$") or ".";

package.path = root .. "/?.lua;" .. package.path;

local shim = require("wow_shim");
shim.install();

local DebouncePrivate = shim.loadAddon(repoRoot .. "/Debounce", {
    "Constants.lua",
    "Solver.lua",
});

local specs = {
    { name = "solver", path = root .. "/solver_spec.lua" },
};

local totalPassed, totalFailures = 0, {};

for _, spec in ipairs(specs) do
    local chunk = assert(loadfile(spec.path));
    local result = chunk()(DebouncePrivate);
    totalPassed = totalPassed + result.passed;
    for _, f in ipairs(result.failures) do
        totalFailures[#totalFailures + 1] = spec.name .. " / " .. f;
    end
end

for _, f in ipairs(totalFailures) do
    io.write("FAIL  ", f, "\n");
end

io.write(("\n%d passed, %d failed\n"):format(totalPassed, #totalFailures));

if (#totalFailures > 0) then
    os.exit(1);
end
