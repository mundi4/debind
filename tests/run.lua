-- 헤드리스 테스트 진입점.
--   lua tests/run.lua            (저장소 루트에서)
--   node tests/run.js            (lua 바이너리가 없을 때)

local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]run%.lua$") or "tests";
local repoRoot = root:match("^(.*)[/\\][^/\\]+$") or ".";

package.path = root .. "/?.lua;" .. package.path;

local shim = require("wow_shim");
shim.install();

-- Two of the bundled libraries are plain Lua and the harness reads them rather than standing in
-- for what they do. `CallbackHandler-1.0` is the one that matters: `DebindPrivate.callbacks` is
-- built out of it in `Debind.lua`, and several specs used to hand-build a stub for that.
shim.loadLibs(repoRoot .. "/Debind/Libs", {
    "LibStub/LibStub.lua",
    "CallbackHandler-1.0/CallbackHandler-1.0.lua",
});

--- **The load order is `Debind/Debind.xml`'s, and it has to stay that way.** Every file here takes
--- upvalues off `DebindPrivate` when it is read -- `SecureBindings.lua` opens with
--- `local BindingDriver = DebindPrivate.BindingDriver` -- so a file read before the one that puts
--- the value there binds nil and fails much later, somewhere else.
---
--- What is missing is the UI (`devdocs/going-headless-outside-the-ui.md` §11): the line is not
--- whether a file is UI but whether the function needs a frame, and `ImportUI.lua` is here for
--- exactly that reason.
local DebindPrivate = shim.loadAddon(repoRoot .. "/Debind", {
    "Constants.lua",
    "Snippets.lua",
    "Ordering.lua",
    "Solver.lua",
    "Misc.lua",
    "ActionCatalog.lua",
    "BindingContexts.lua",
    "Debind.lua",
    "Flyout.lua",
    "Profile.lua",
    "Legacy.lua",
    "SecureBindings.lua",
    "Events.lua",
    "UnitWatch.lua",
    "FrameRegistry.lua",
    "UpdateBindings.lua",
    "Switches.lua",
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
--- Rewrite the recorded files instead of comparing against them. The emission golden is a net for
--- a refactor and not a specification (`devdocs/going-headless-outside-the-ui.md` §6), so a
--- deliberate change to what a rebuild emits is answered by updating it and reading the diff --
--- the same discipline `tools/snippet-golden.txt` already runs on.
local updateGolden = false;
for i = 1, #(arg or {}) do
    if (arg[i] == "--bench") then bench = true; end
    if (arg[i] == "--update-golden") then updateGolden = true; end
end

if (bench) then
    assert(loadfile(root .. "/bench.lua"))()(DebindPrivate);
    return;
end

local specs = {
    -- The shim itself. It stands in for the client, so what it gets wrong every spec below
    -- inherits (`wow_shim.lua`, the `CopyTable` comment).
    { name = "format", path = root .. "/format_spec.lua" },
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
    -- **Last, and it runs a whole rebuild.** Everything above measures a function; this one drives
    -- `UpdateBindings()` end to end and holds what came out against a recorded file. Module level
    -- state -- `BindingAttrsCache`, `KeyMap`, the switch table -- is left behind by that
    -- (`devdocs/going-headless-outside-the-ui.md` §10-1), so it goes after the specs that would
    -- otherwise inherit it.
    { name = "emit", path = root .. "/emit_spec.lua" },
    -- **After the golden**, because it builds plans of its own and the button names
    -- `SetBindingAttributes` hands out run on one counter -- a rebuild before the golden's would
    -- shift every name in it.
    { name = "plan", path = root .. "/plan_spec.lua" },
    { name = "describe", path = root .. "/describe_spec.lua" },
};

--- Reading and writing a whole file, whichever interpreter this is.
---
--- **fengari has no `io.open`.** It offers `io.write` and nothing that opens a file, so the two
--- fall back on functions `run.js` installs. A real interpreter never reaches them.
local function readFile(path)
    if (io.open) then
        local file = io.open(path, "rb");
        if (not file) then return nil, path .. " could not be opened"; end
        local contents = file:read("*a");
        file:close();
        return contents;
    end
    return _G.__hostReadFile(path);
end

local function writeFile(path, contents)
    if (io.open) then
        local file = assert(io.open(path, "wb"));
        file:write(contents);
        file:close();
        return;
    end
    _G.__hostWriteFile(path, contents);
end

--- What a spec is handed besides the addon. Only the golden reads it so far, and what it needs is
--- the repository root -- a spec is loaded with `loadfile` and has no idea where it lives.
local ctx = {
    repoRoot = repoRoot,
    root = root,
    updateGolden = updateGolden,
    readFile = readFile,
    writeFile = writeFile,
};

local totalPassed, totalFailures = 0, {};

for _, spec in ipairs(specs) do
    local chunk = assert(loadfile(spec.path));
    local result = chunk()(DebindPrivate, DebindStorage, ctx);
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
