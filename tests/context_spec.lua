-- Which keys the game has taken for itself, and what the addon does about them.
--
-- The house editor claims part of the keyboard while it is open (`bindingContext` in
-- `Bindings_Standard.xml`). `SetOverrideBinding` sits above that by definition, so left alone we
-- would take the editor's own keys inside the editor. They are not ours, so we stand back -- and
-- only on the keys that overlap, because this addon is not only for combat keys.
--
-- **This file had no test of any kind** (`.zzz/refactor-candidates.md` 10, opened 2026-08-04). It
-- was checked by opening the editor and pressing keys, and the reason was the harness: it read
-- pure logic only, and this one builds a frame when it loads. That line is gone
-- (`devdocs/legacy/going-headless-outside-the-ui.md`) -- the file is read whole now, on a frame shell.

return function(DebindPrivate)
    local shim = require("wow_shim");

    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    local HOUSING = _G.Enum.BindingContext.Housing;
    local NONE = _G.Enum.BindingContext.None;

    --- Stands the client's binding table up. `bindings` is what `GetNumBindings` walks and
    --- `contexts` says which context claims which action; a binding with no entry is one the
    --- client answers nil for, which is what a header row is.
    local function World(bindings, contexts, active)
        shim.world.bindings = bindings or {};
        shim.world.bindingContexts = contexts or {};
        shim.world.activeBindingContexts = active or {};
    end

    --- Back to a client with nothing bound and no context open, which is where every other spec
    --- expects to find it.
    local function Reset()
        World();
        DebindPrivate.RefreshYieldedKeys();
    end

    ---------------------------------------------------------------------------
    -- What gets yielded
    ---------------------------------------------------------------------------

    -- With the editor open, the keys its own bindings sit on stop being ours.
    test("an active context's keys are yielded", function()
        World(
            { { action = "HOUSING_MODE_DECOR", keys = { "F5" } } },
            { HOUSING_MODE_DECOR = HOUSING },
            { [HOUSING] = true });

        check(DebindPrivate.RefreshYieldedKeys() == true, "nothing changed");
        check(DebindPrivate.IsKeyYielded("F5") == true, "F5 was not yielded");
        Reset();
    end);

    -- **The gate is whether any context is active, not whether one exists.** The same table with
    -- the editor shut yields nothing, and that is the ordinary state of every client.
    test("a context that exists but is not active yields nothing", function()
        World(
            { { action = "HOUSING_MODE_DECOR", keys = { "F5" } } },
            { HOUSING_MODE_DECOR = HOUSING },
            {});

        DebindPrivate.RefreshYieldedKeys();
        check(DebindPrivate.IsKeyYielded("F5") == false, "F5 was yielded with the editor shut");
        Reset();
    end);

    -- **A header row is not a binding.** The client answers no context for one, and asking it for
    -- keys is meaningless -- walking it as though it were claims whatever `GetBindingKey` returns
    -- for a name that is not an action.
    test("a header row claims nothing", function()
        World(
            {
                { action = "BINDING_HEADER_HOUSING", keys = { "F6" } },
                { action = "HOUSING_MODE_DECOR", keys = { "F5" } },
            },
            { HOUSING_MODE_DECOR = HOUSING },
            { [HOUSING] = true });

        DebindPrivate.RefreshYieldedKeys();
        check(DebindPrivate.IsKeyYielded("F5") == true, "F5 was not yielded");
        check(DebindPrivate.IsKeyYielded("F6") == false, "a header row's key was yielded");
        Reset();
    end);

    -- An action explicitly filed under "no context" is not a claim either.
    test("the None context claims nothing", function()
        World(
            { { action = "JUMP", keys = { "SPACE" } } },
            { JUMP = NONE },
            { [HOUSING] = true });

        DebindPrivate.RefreshYieldedKeys();
        check(DebindPrivate.IsKeyYielded("SPACE") == false, "a None-context key was yielded");
        Reset();
    end);

    -- **Both keys of a two-key binding**, and none of a binding with no key at all. The client
    -- gives an action up to two, and taking only the first leaves the second ours inside the
    -- editor.
    test("every key of a claimed action is yielded, and an unbound one claims nothing", function()
        World(
            {
                { action = "HOUSING_MODE_DECOR", keys = { "F5", "SHIFT-F5" } },
                { action = "HOUSING_PLACE", keys = {} },
            },
            { HOUSING_MODE_DECOR = HOUSING, HOUSING_PLACE = HOUSING },
            { [HOUSING] = true });

        DebindPrivate.RefreshYieldedKeys();
        check(DebindPrivate.IsKeyYielded("F5") == true, "the first key was not yielded");
        check(DebindPrivate.IsKeyYielded("SHIFT-F5") == true, "the second key was not yielded");
        Reset();
    end);

    -- A context can be open with nothing bound under it. Nothing is yielded, and nothing errors.
    test("an active context with no keys bound yields nothing", function()
        World(
            { { action = "HOUSING_PLACE", keys = {} } },
            { HOUSING_PLACE = HOUSING },
            { [HOUSING] = true });

        check(DebindPrivate.RefreshYieldedKeys() == false, "an empty claim reported a change");
        Reset();
    end);

    ---------------------------------------------------------------------------
    -- Whether anything changed
    ---------------------------------------------------------------------------

    -- **The answer drives a rebuild, so a false "yes" costs one for nothing.** The same set
    -- arriving in a different order is the same set.
    test("the same set in a different order is not a change", function()
        World(
            {
                { action = "HOUSING_MODE_DECOR", keys = { "F5" } },
                { action = "HOUSING_PLACE", keys = { "F6" } },
            },
            { HOUSING_MODE_DECOR = HOUSING, HOUSING_PLACE = HOUSING },
            { [HOUSING] = true });
        check(DebindPrivate.RefreshYieldedKeys() == true, "the first claim reported no change");

        World(
            {
                { action = "HOUSING_PLACE", keys = { "F6" } },
                { action = "HOUSING_MODE_DECOR", keys = { "F5" } },
            },
            { HOUSING_MODE_DECOR = HOUSING, HOUSING_PLACE = HOUSING },
            { [HOUSING] = true });
        check(DebindPrivate.RefreshYieldedKeys() == false, "reordering reported a change");
        Reset();
    end);

    -- **Both directions of "it moved".** A key gained and a key lost each have to answer yes, and
    -- the second one is the half that is easy to leave out: comparing only what is newly claimed
    -- misses the editor closing.
    test("a key gained and a key lost both count as a change", function()
        World(
            { { action = "HOUSING_MODE_DECOR", keys = { "F5" } } },
            { HOUSING_MODE_DECOR = HOUSING },
            { [HOUSING] = true });
        DebindPrivate.RefreshYieldedKeys();

        World(
            {
                { action = "HOUSING_MODE_DECOR", keys = { "F5" } },
                { action = "HOUSING_PLACE", keys = { "F6" } },
            },
            { HOUSING_MODE_DECOR = HOUSING, HOUSING_PLACE = HOUSING },
            { [HOUSING] = true });
        check(DebindPrivate.RefreshYieldedKeys() == true, "a key gained reported no change");

        World(
            { { action = "HOUSING_MODE_DECOR", keys = { "F5" } } },
            { HOUSING_MODE_DECOR = HOUSING },
            { [HOUSING] = true });
        check(DebindPrivate.RefreshYieldedKeys() == true, "a key lost reported no change");
        check(DebindPrivate.IsKeyYielded("F6") == false, "the lost key is still yielded");
        Reset();
    end);

    ---------------------------------------------------------------------------
    -- What yielding does to the bindings
    ---------------------------------------------------------------------------

    local Constants = DebindPrivate.Constants;
    local GUID = "Player-1-TESTGUID";

    local function Profile(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        DebindPrivate.BuildKeyMap();
        return DebindPrivate.KeyMap;
    end

    -- Standing back means the key is not in `KeyMap`, so no override is put on it and the editor
    -- gets it. **`keepInBindingContext` is the reader overruling that**, and it is theirs to set:
    -- the editor goes on showing the key on its own button while it does nothing.
    test("a yielded key leaves KeyMap unless the reader asked to keep it", function()
        World(
            { { action = "HOUSING_MODE_DECOR", keys = { "F5" } } },
            { HOUSING_MODE_DECOR = HOUSING },
            { [HOUSING] = true });
        DebindPrivate.RefreshYieldedKeys();

        local keyMap = Profile({
            { type = Constants.SPELL, value = 585, key = "F5", seq = 1 },
            { type = Constants.SPELL, value = 774, key = "F6", seq = 2 },
        });
        check(keyMap["F5"] == nil, "a yielded key stayed in KeyMap");
        check(keyMap["F6"] ~= nil, "a key nobody claimed was dropped");

        local kept = Profile({
            { type = Constants.SPELL, value = 585, key = "F5", seq = 1,
                keepInBindingContext = true },
        });
        check(kept["F5"] ~= nil, "keepInBindingContext did not hold the key");

        Reset();
    end);

    return T;
end
