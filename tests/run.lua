-- 헤드리스 테스트 진입점.
--   lua tests/run.lua            (저장소 루트에서)
--   node tests/run.js            (lua 바이너리가 없을 때)

local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]run%.lua$") or "tests";
local repoRoot = root:match("^(.*)[/\\][^/\\]+$") or ".";

package.path = root .. "/?.lua;" .. package.path;

local shim = require("wow_shim");
shim.install();

local DebindPrivate = shim.loadAddon(repoRoot .. "/Debind", {
    "Constants.lua",
    "Ordering.lua",
    "Solver.lua",
    "Misc.lua",
    "ActionCatalog.lua",
    "Profile.lua",
    "Legacy.lua",
    -- **A UI file, and the only one the harness loads.** It builds no frames when it is read, and
    -- the two functions that decide the reader's lines live in it (`CollectImportLines`).
    "ImportUI.lua",
});

--- `DebindStorage` is a separate addon (LoadOnDemand; see its TOC). The game gives it its own addon
--- table and Debind hands its private table across for the length of `LoadAddOn`, so the spec
--- stands that same shape up here rather than loading its files into Debind's table.
local DebindStorage = shim.loadAddon(repoRoot .. "/DebindStorage", {
    "Export.lua",
    "Import.lua",
}, { DebindPrivate = DebindPrivate });

--- What `DebindStorage.lua` does the instant the game loads that addon. It is not in the list
--- above, because the shim has no `LoadAddOn` for it to run inside, so the half that points Debind
--- back at the store is done here. `CollectImportLines` reads it (`ImportUI.lua`).
DebindPrivate.Store = DebindStorage;

local bench = false;
for i = 1, #(arg or {}) do
    if (arg[i] == "--bench") then bench = true; end
end

if (bench) then
    assert(loadfile(root .. "/bench.lua"))()(DebindPrivate);
    return;
end

local specs = {
    { name = "solver", path = root .. "/solver_spec.lua" },
    { name = "ordering", path = root .. "/ordering_spec.lua" },
    { name = "macrotext", path = root .. "/macrotext_spec.lua" },
    { name = "catalog", path = root .. "/catalog_spec.lua" },
    { name = "migration", path = root .. "/migration_spec.lua" },
    { name = "issue", path = root .. "/issue_spec.lua" },
    { name = "suppression", path = root .. "/suppression_spec.lua" },
    { name = "grade", path = root .. "/grade_spec.lua" },
    { name = "overview", path = root .. "/overview_spec.lua" },
    { name = "normalize", path = root .. "/normalize_spec.lua" },
    { name = "clicktime", path = root .. "/clicktime_spec.lua" },
    { name = "clickcast", path = root .. "/clickcast_spec.lua" },
    { name = "alwaysours", path = root .. "/alwaysours_spec.lua" },
    { name = "export", path = root .. "/export_spec.lua" },
    { name = "batch", path = root .. "/batch_spec.lua" },
    { name = "import", path = root .. "/import_spec.lua" },
    { name = "keygroup", path = root .. "/keygroup_spec.lua" },
    { name = "renumber", path = root .. "/renumber_spec.lua" },
    { name = "switch", path = root .. "/switch_spec.lua" },
};

local totalPassed, totalFailures = 0, {};

for _, spec in ipairs(specs) do
    local chunk = assert(loadfile(spec.path));
    local result = chunk()(DebindPrivate, DebindStorage);
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
