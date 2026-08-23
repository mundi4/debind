-- 헤드리스 테스트 진입점.
--   lua tests/run.lua            (저장소 루트에서)
--   node tests/run.js            (lua 바이너리가 없을 때)

local root = arg and arg[0] and arg[0]:match("^(.*)[/\\]run%.lua$") or "tests";
local repoRoot = root:match("^(.*)[/\\][^/\\]+$") or ".";

package.path = root .. "/?.lua;" .. package.path;

local shim = require("wow_shim");
shim.install();

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

local bench = false;
--- Rewrite the recorded files instead of comparing against them. The emission golden is a net for
--- a refactor and not a specification (`devdocs/legacy/going-headless-outside-the-ui.md` §6), so a
--- deliberate change to what a rebuild emits is answered by updating it and reading the diff --
--- the same discipline `tools/snippet-golden.txt` already runs on.
local updateGolden = false;
--- Read the shape a user gets rather than the one in the working tree: the `--@debug@` blocks come
--- out, `Constants.DEBUG` stops being true, and every branch under it changes answer
--- (`going-headless-outside-the-ui.md` §10-2). **This has to be known before the addon is loaded**,
--- which is why the argument walk sits up here rather than beside the spec list.
local shipped = false;
for i = 1, #(arg or {}) do
    if (arg[i] == "--bench") then bench = true; end
    if (arg[i] == "--update-golden") then updateGolden = true; end
    if (arg[i] == "--shipped") then shipped = true; end
end

local loadOpts = { shipped = shipped, readFile = readFile };

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
--- **This is `Debind.xml` plus two, and it is not "everything but the UI".** §11 of
--- `devdocs/legacy/going-headless-outside-the-ui.md` says which rule decides: whether the
--- **function** needs a frame, not whether the file is UI.
---
---   `ActionDisplay.lua` and `ActionTooltip.lua` are `DebindUI.xml`'s and are here, in that XML's
---     order. Neither calls `CreateFrame` or touches the screen: the first resolves what an action
---     is called, the second **takes the tooltip as an argument** and puts its lines through the
---     client's `GameTooltip_Add…` functions. Everything drawn anywhere reads through them, so
---     leaving them out put the words a reader sees out of reach of every spec -- and put
---     `ActionCatalog` out of reach too, since it asks the first one to name a row
---   `Flyout.lua` is UI and is here anyway. `SetBindingAttributes` asks it for a flyout opener
---     and that opener is a frame, so by that rule it sits on the in-game side; the file comes
---     along because the pipeline calls into it
---   `StorageUI.lua` is UI and is **not** here any more. It was, for two functions that decided
---     which layers the bring dialog offered; the tick moved onto the action and both went with
---     the dialog (`devdocs/building-export-import.md` 12절)
---   `Public.lua` is **not** UI and is **not** here. It is in the TOC after `DebindUI.xml`
---     rather than in this XML, and nothing in the pipeline calls it - it is what other addons
---     call
---   `DevSeed.lua` has to stay out: it plants a profile, and every spec that starts from an
---     empty one would be handed the seed instead (`Profile.lua`, `InitDB`)
--- One addon, loaded fresh. **Every spec gets its own**, which is what keeps module level
--- state from crossing between them: `BindingAttrsCache`, `KeyMap`, the switch table and the
--- counter the button names come off all start where the game starts them
--- (`devdocs/legacy/going-headless-outside-the-ui.md` §10-1). A load is 9ms, so the whole list costs
--- a fraction of one spec.
local function loadAddons()
    local DebindPrivate = shim.loadAddon(repoRoot .. "/Debind", {
    "Constants.lua",
    "Snippets.lua",
    "Ordering.lua",
    "Solver.lua",
    "Misc.lua",
    "ActionCatalog.lua",
    "BindingContexts.lua",
    "Debind.lua",
    "ActionDisplay.lua",
    "ActionTooltip.lua",
    "Flyout.lua",
    "Profile.lua",
    "Legacy.lua",
    "SecureBindings.lua",
    "Events.lua",
    "UnitWatch.lua",
    "FrameRegistry.lua",
    "UpdateBindings.lua",
    "Switches.lua",
    }, nil, loadOpts);

    --- `DebindStorage` is a separate addon (LoadOnDemand; see its TOC). The game gives it its own addon
    --- table and Debind hands its private table across for the length of `LoadAddOn`, so the spec
    --- stands that same shape up here rather than loading its files into Debind's table.
    local DebindStorage = shim.loadAddon(repoRoot .. "/DebindStorage", {
    "Export.lua",
    "Import.lua",
    }, { DebindPrivate = DebindPrivate }, loadOpts);

    --- What `DebindStorage.lua` does the instant the game loads that addon. It is not in the list
    --- above, because the shim has no `LoadAddOn` for it to run inside, so the half that points
    --- Debind back at the store is done here.
    DebindPrivate.Store = DebindStorage;
    return DebindPrivate, DebindStorage;
end

if (bench) then
    assert(loadfile(root .. "/bench.lua"))()((loadAddons()));
    return;
end

--- **The order here does not matter.** Every spec is handed an addon loaded a moment earlier and a
--- client reset to empty, so nothing one leaves behind reaches the next: not
--- `BindingAttrsCache`, not the counter the button names come off, not a `_G` stub a spec put up
--- for itself. Reversing this list is a run that has to pass, and it is how the last of that was
--- found -- `emit_fixture` had never installed a macro store and was passing on one another spec
--- had left in `_G` (`devdocs/legacy/going-headless-outside-the-ui.md` §10-1).
---
--- The order is still worth keeping readable: cheapest first, and the ones that run a whole
--- rebuild after the ones that measure a single function.
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
    { name = "identity", path = root .. "/identity_spec.lua" },
    { name = "export", path = root .. "/export_spec.lua" },
    { name = "entry", path = root .. "/entry_spec.lua" },
    { name = "import", path = root .. "/import_spec.lua" },
    { name = "keygroup", path = root .. "/keygroup_spec.lua" },
    { name = "renumber", path = root .. "/renumber_spec.lua" },
    { name = "switch", path = root .. "/switch_spec.lua" },
    { name = "switchgate", path = root .. "/switchgate_spec.lua" },
    { name = "emit", path = root .. "/emit_spec.lua" },
    { name = "plan", path = root .. "/plan_spec.lua" },
    { name = "describe", path = root .. "/describe_spec.lua" },
    { name = "record", path = root .. "/record_spec.lua" },
    { name = "context", path = root .. "/context_spec.lua" },
    { name = "frames", path = root .. "/frames_spec.lua" },
    { name = "eval", path = root .. "/eval_spec.lua" },
    { name = "keymap", path = root .. "/keymap_spec.lua" },
    { name = "boundkey", path = root .. "/boundkey_spec.lua" },
    { name = "display", path = root .. "/display_spec.lua" },
    { name = "hover", path = root .. "/hover_spec.lua" },
};

--- What a spec is handed besides the addon. Only the golden reads it so far, and what it needs is
--- the repository root -- a spec is loaded with `loadfile` and has no idea where it lives.
local ctx = {
    repoRoot = repoRoot,
    root = root,
    updateGolden = updateGolden,
    shipped = shipped,
    readFile = readFile,
    writeFile = writeFile,
};

local totalPassed, totalFailures = 0, {};

for _, spec in ipairs(specs) do
    local chunk = assert(loadfile(spec.path));
    shim.resetWorld();
    require("wow_frames").reset();
    local DebindPrivate, DebindStorage = loadAddons();
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
