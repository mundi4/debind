-- Tests for the Debounce -> Debind migration. No WoW client needed.
--
-- **This code runs exactly once per user, and when it is wrong it loses settings silently.**
-- Reproducing it in-game means staging an old SavedVariables file and switching characters, which
-- is not something you can do once and be finished with. So it is pinned here.
--
-- Two of these are the kind you cannot check by looking:
--
--   1. **Are the old globals left alone?** In a session where the dummy addon is loaded, WoW
--      rewrites `Debounce.lua` on logout. Plug in a reference and edits made later in Debind leak
--      into the old file, so rolling back to the old addon no longer gives back what was there
--   2. **Is the account's share pulled only once?** When an alt loads the dummy for its own
--      per-character data, re-attaching the account share would resurrect shared bindings the user
--      has deleted in between

return function(DebindPrivate)
    -- `LoadProfile` fires "OnProfileLoaded". The callback machinery is built in Debind.lua, which
    -- drags in a pile of frames, so here it just gets an ear that does not listen.
    DebindPrivate.callbacks = DebindPrivate.callbacks or { Fire = function() end };

    local T = { passed = 0, failures = {} };

    local function fail(name, msg)
        T.failures[#T.failures + 1] = name .. ": " .. msg;
    end

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            fail(name, tostring(err));
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    local GUID = _G.UnitGUID();

    --- One set of pre-rename SavedVariables. The actions are already in `dbver = 3` shape (the
    --- current one), so no content migration runs and this exercises **the container move only**.
    local function LegacyAccount()
        return {
            dbver = 3,
            GENERAL = { { type = "spell", value = 1, key = "F1", seq = 1 } },
            DRUID = {
                [0] = { { type = "spell", value = 2, key = "F2", seq = 1 } },
                [1] = {},
            },
            options = { unitframeUseMouseDown = true },
            ui = { anchorPos = { x = 100, y = 200 } },
            spellPickerUI = { pos = { x = 300, y = 400 } },
            overviewui = { pos = { x = 500, y = 600 } },
            -- Keys whose shape does not change. `spellPicker` is one that was actually lost once;
            -- `somethingAddedLater` stands for a key someone adds after this code was written.
            spellPicker = { spell = { showOffSpec = true, favoritesOnly = false } },
            somethingAddedLater = { deep = { value = 7 } },
        };
    end

    local function LegacyChar()
        return {
            dbver = 3,
            [0] = { { type = "spell", value = 3, key = "F3", seq = 1 } },
            [1] = {},
            CustomTargets = { custom1 = "focus" },
        };
    end

    --- Runs InitDB from a clean slate.
    local function FreshInit()
        _G.DebindVars = nil;
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        DebindPrivate.legacyLoadFailure = nil;
        DebindPrivate.InitDB();
    end

    test("a fresh install comes up with no old file present", function()
        FreshInit();
        check(_G.DebindVars ~= nil, "DebindVars was not created");
        check(_G.DebindVars.shared ~= nil, "no shared");
        check(_G.DebindVars.characters ~= nil, "no characters");
        check(DebindPrivate.db.char.layers ~= nil, "no char.layers");
    end);

    test("an empty character gets no entry in characters", function()
        FreshInit();
        DebindPrivate.CleanUpDB();
        check(_G.DebindVars.characters[GUID] == nil,
            "a character with no content created an entry (lazy creation is not working)");
    end);

    test("the account's share moves into shared", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.ImportLegacySavedVars();

        local shared = _G.DebindVars.shared;
        check(shared.GENERAL and #shared.GENERAL == 1, "GENERAL did not arrive");
        check(shared.GENERAL[1].key == "F1", "GENERAL contents differ");
        check(shared.classes.DRUID and #shared.classes.DRUID[0] == 1, "class layer did not arrive");
        check(shared.classes.DRUID[0][1].key == "F2", "class layer contents differ");
    end);

    -- **Pins something that was actually lost.** The first version listed the keys to copy by hand,
    -- and because that list was transcribed from a stale structure diagram, `spellPicker` (the
    -- picker's per-tab filters) disappeared entirely. The import is one-shot and irreversible, so
    -- an unrecognised key must be **carried over, not dropped**.
    test("keys whose shape does not change come across without being named", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.ImportLegacySavedVars();

        local db = _G.DebindVars;
        check(db.spellPicker and db.spellPicker.spell.showOffSpec == true,
            "spellPicker did not arrive");
        check(db.somethingAddedLater and db.somethingAddedLater.deep.value == 7,
            "an unrecognised key was dropped - this went back to an allow list");

        -- What is carried over must be deep-copied too, or the old file gets contaminated.
        db.spellPicker.spell.showOffSpec = false;
        check(_G.DebounceVars.spellPicker.spell.showOffSpec == true,
            "a carried-over key was copied shallowly");
    end);

    test("class keys go only to shared.classes and do not leak to the top level", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.ImportLegacySavedVars();

        check(_G.DebindVars.DRUID == nil, "a class key leaked to the top level");
        check(_G.DebindVars.dbver == 4, "dbver was overwritten with the old value");
        check(_G.DebindVars.GENERAL == nil, "GENERAL stayed at the top level");
    end);

    test("window positions fold into one table and overviewui is dropped", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.ImportLegacySavedVars();

        local ui = _G.DebindVars.ui;
        check(ui and ui.main and ui.main.x == 100, "ui.main did not arrive");
        check(ui.spellPicker and ui.spellPicker.x == 300, "ui.spellPicker did not arrive");
        check(ui.overviewui == nil and ui.overview == nil, "the dead key overviewui was imported");
    end);

    test("the options reference survives the import", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.ImportLegacySavedVars();
        DebindPrivate.BindDerivedTables();

        check(DebindPrivate.Options == _G.DebindVars.options,
            "Options still points at the pre-import empty table");
        check(DebindPrivate.Options.unitframeUseMouseDown == true, "the old option did not arrive");
    end);

    test("the character's share moves into the char entry", function()
        FreshInit();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.ImportLegacySavedVars();

        local charEntry = DebindPrivate.db.char;
        check(#charEntry.layers[0] == 1, "character layer did not arrive");
        check(charEntry.layers[0][1].key == "F3", "character layer contents differ");
        check(charEntry.CustomTargets.custom1 == "focus", "CustomTargets did not arrive");

        DebindPrivate.CleanUpDB();
        check(_G.DebindVars.characters[GUID] == charEntry,
            "there is content but the entry was not attached");
    end);

    test("the old globals are never modified - the copy must be deep", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.ImportLegacySavedVars();

        -- Edit the imported side. If references were plugged in, the old tables change with it.
        _G.DebindVars.shared.GENERAL[1].key = "CHANGED";
        _G.DebindVars.shared.classes.DRUID[0][1].key = "CHANGED";
        DebindPrivate.db.char.layers[0][1].key = "CHANGED";
        DebindPrivate.db.char.CustomTargets.custom1 = "CHANGED";

        check(_G.DebounceVars.GENERAL[1].key == "F1", "the old GENERAL changed along with it");
        check(_G.DebounceVars.DRUID[0][1].key == "F2", "the old class layer changed along with it");
        check(_G.DebounceVarsPerChar[0][1].key == "F3",
            "the old character layer changed along with it");
        check(_G.DebounceVarsPerChar.CustomTargets.custom1 == "focus",
            "the old CustomTargets changed along with it");
    end);

    test("the account's share is not pulled twice", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.ImportLegacySavedVars();

        -- The user deletes a shared binding.
        _G.DebindVars.shared.GENERAL = {};

        -- An alt logs in. Same account file, different character.
        _G.DebindVars.migrated = {};
        DebindPrivate.ImportLegacySavedVars();

        check(#_G.DebindVars.shared.GENERAL == 0,
            "a deleted shared binding came back through re-import (legacyAccountPulled failed)");
    end);

    -- **The one-shot guard is not enough on its own.** It only starts counting once the import has
    -- run, so if the dummy addon is unavailable for a while the user can build a full config in
    -- Debind first. When the dummy comes back, an unconditional import would replace all of it -
    -- silently, on a login with nothing special about it. So only empty destinations are filled.
    test("an import never replaces content the user already has", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();

        -- The user has been playing with the dummy disabled and built their own bindings.
        _G.DebindVars.shared.GENERAL = { { type = "spell", value = 99, key = "MINE", seq = 1 } };
        _G.DebindVars.shared.classes.DRUID = {
            [0] = { { type = "spell", value = 98, key = "ALSO_MINE", seq = 1 } },
        };
        DebindPrivate.db.char.layers[0] = { { type = "spell", value = 97, key = "CHAR_MINE", seq = 1 } };
        DebindPrivate.db.char.CustomTargets = { custom1 = "target" };

        DebindPrivate.ImportLegacySavedVars();

        check(_G.DebindVars.shared.GENERAL[1].key == "MINE",
            "the import replaced a shared layer the user had already filled");
        check(_G.DebindVars.shared.classes.DRUID[0][1].key == "ALSO_MINE",
            "the import replaced a class layer the user had already filled");
        check(DebindPrivate.db.char.layers[0][1].key == "CHAR_MINE",
            "the import replaced a character layer the user had already filled");
        check(DebindPrivate.db.char.CustomTargets.custom1 == "target",
            "the import replaced CustomTargets the user had already set");
        check(DebindPrivate.legacySkipped == true,
            "content was skipped but the user is never told");
    end);

    test("an empty destination is still filled when others are occupied", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();

        -- Only GENERAL is taken. The class layer is untouched and must still come across.
        _G.DebindVars.shared.GENERAL = { { type = "spell", value = 99, key = "MINE", seq = 1 } };

        DebindPrivate.ImportLegacySavedVars();

        check(_G.DebindVars.shared.GENERAL[1].key == "MINE", "the occupied layer was replaced");
        check(_G.DebindVars.shared.classes.DRUID[0][1].key == "F2",
            "an empty layer was skipped just because another one was occupied");
    end);

    test("options are imported even though InitDB creates them first", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.ImportLegacySavedVars();

        -- `InitDB` synthesizes `options`/`customStates` before the import runs, so a naive
        -- "is it nil" test would treat them as occupied and never import the old ones.
        check(_G.DebindVars.options.unitframeUseMouseDown == true,
            "the pre-rename options were skipped as if the user had set them");
    end);

    test("a character already migrated is not read again", function()
        FreshInit();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.ImportLegacySavedVars();

        -- The user deletes a character-specific binding.
        DebindPrivate.db.char.layers[0] = {};
        DebindPrivate.ImportLegacySavedVars();

        check(#DebindPrivate.db.char.layers[0] == 0, "a deleted character binding came back");
    end);

    test("no flag is set when the dummy addon is disabled", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();

        local realLoadAddOn = _G.C_AddOns.LoadAddOn;
        _G.C_AddOns.LoadAddOn = function() return false, "DISABLED"; end
        local changed = DebindPrivate.ImportLegacySavedVars();
        _G.C_AddOns.LoadAddOn = realLoadAddOn;

        check(changed == false, "the load failed but it reported an import");
        check(_G.DebindVars.migrated[GUID] == nil,
            "the load failed but a flag was set - the next login will not retry");
        check(DebindPrivate.legacyLoadFailure == "DISABLED", "the failure reason was not recorded");

        -- Once the dummy is enabled again, the next login must bring it in.
        DebindPrivate.ImportLegacySavedVars();
        check(#_G.DebindVars.shared.GENERAL == 1, "the retry did not happen");
    end);

    test("actions from an older version (dbver=1) are raised to the current one", function()
        FreshInit();
        local old = LegacyAccount();
        old.dbver = 1;
        -- The dbver 2 step numbers actions that have a key. Clear that trace and see it reapplied.
        old.GENERAL[1].seq = nil;
        _G.DebounceVars = old;

        DebindPrivate.ImportLegacySavedVars();
        check(_G.DebindVars.shared.GENERAL[1].seq == 1,
            "the import was not raised to the current version - MigrateLayer did not run");
    end);

    return T;
end
