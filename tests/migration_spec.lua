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

    -- The import narrates what it did. That is for a person watching in-game; here it would just
    -- interleave with the test output. (Without DevTool present `log` falls back to `print`.)
    DebindPrivate.log = function() end;

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
        DebindPrivate.RunLegacyMigration();

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
        DebindPrivate.RunLegacyMigration();

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
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.DRUID == nil, "a class key leaked to the top level");
        check(_G.DebindVars.dbver == 4, "dbver was overwritten with the old value");
        check(_G.DebindVars.GENERAL == nil, "GENERAL stayed at the top level");
    end);

    test("window positions fold into one table and overviewui is dropped", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        local ui = _G.DebindVars.ui;
        check(ui and ui.main and ui.main.x == 100, "ui.main did not arrive");
        check(ui.spellPicker and ui.spellPicker.x == 300, "ui.spellPicker did not arrive");
        check(ui.overviewui == nil and ui.overview == nil, "the dead key overviewui was imported");
    end);

    test("the options reference survives the import", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();
        DebindPrivate.BindDerivedTables();

        check(DebindPrivate.Options == _G.DebindVars.options,
            "Options still points at the pre-import empty table");
        check(DebindPrivate.Options.unitframeUseMouseDown == true, "the old option did not arrive");
    end);

    test("the character's share moves into the char entry", function()
        FreshInit();
        -- The account file has to be there too. Every version that could write a per-character
        -- file created this one on its first run, so its absence is what tells us the account
        -- never ran an older version at all - `legacyNeeded` keys off it alone.
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.RunLegacyMigration();

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
        DebindPrivate.RunLegacyMigration();

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

    -- **The rename reached inside the saved data, not just around it.** "Convert to a Custom Macro"
    -- wrote the addon's own frame name into the macro body, so a pre-rename conversion holds
    -- `/click DebounceCustom1 hover` - a frame that no longer exists. It fails the way this whole
    -- file guards against: no error, the key simply stops doing anything.
    --
    -- Covers both import paths (a flat layer and a per-spec table) because they are separate
    -- functions, and the character path is the one that runs on every alt for as long as the account
    -- lives. The hand-written case is here too - the rewrite is on the frame name, not on the
    -- generated body, so a `/click` the user typed themselves is repaired the same way.
    test("old click targets inside converted macros are rewritten", function()
        FreshInit();
        _G.DebounceVars = {
            dbver = 3,
            GENERAL = {
                { type = "macrotext", value = "/click DebounceCustom1 hover", key = "F1", seq = 1 },
            },
            DRUID = {
                [0] = {
                    { type = "macrotext", value = "/click DebounceStates $state1-on", key = "F2", seq = 1 },
                },
            },
        };
        _G.DebounceVarsPerChar = {
            dbver = 3,
            [0] = {
                -- Two on one action, and a line the user wrote around them.
                {
                    type = "macrotext",
                    value = "/cast Rejuvenation\n/click DebounceCustom2 hover\n/click DebounceStates $state2-toggle",
                    key = "F3",
                    seq = 1,
                },
            },
        };
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.shared.GENERAL[1].value == "/click DebindCustom1 hover",
            "a shared layer kept the old frame name: " .. tostring(_G.DebindVars.shared.GENERAL[1].value));
        check(_G.DebindVars.shared.classes.DRUID[0][1].value == "/click DebindStates $state1-on",
            "a class layer kept the old frame name: " .. tostring(_G.DebindVars.shared.classes.DRUID[0][1].value));

        local charBody = DebindPrivate.db.char.layers[0][1].value;
        check(not charBody:find("Debounce"), "the character layer kept an old frame name: " .. charBody);
        check(charBody:find("/cast Rejuvenation", 1, true), "the rewrite ate the rest of the body");
        check(charBody:find("DebindCustom2", 1, true) and charBody:find("DebindStates", 1, true),
            "only one of the two targets was rewritten: " .. charBody);

        -- The old file is read-only. Repairing on the way in must not repair in place.
        check(_G.DebounceVars.GENERAL[1].value == "/click DebounceCustom1 hover",
            "the rewrite reached back into the old file");
    end);

    -- Only macro bodies are touched. Other action types keep a number in `value`, and a rewrite that
    -- was not type-checked would run `gsub` on whatever it found.
    test("the click-target rewrite leaves other action types alone", function()
        FreshInit();
        _G.DebounceVars = {
            dbver = 3,
            GENERAL = { { type = "spell", value = 774, key = "F1", seq = 1 } },
        };
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.shared.GENERAL[1].value == 774,
            "a spell action's value was altered by the click-target rewrite");
    end);

    -- **순서 번호의 그물.** 여기 있는 이유는 마이그레이션과 같은 종류의 실패라서다 - 틀려도
    -- 아무 소리가 안 나고, 눈으로 봐서는 알 수 없다.
    --
    -- 겹치는 번호를 놓치면 비교자가 두 액션을 동률로 보고(Ordering.lua) `sort`가 임의로
    -- 놓는다. 같은 키에 걸린 두 지정의 발동 순서가 정렬할 때마다 달라질 수 있다는 뜻이고,
    -- 사용자는 그걸 못 고친다 - 순서 이동은 두 번호를 맞바꾸는 것이라 같은 값끼리는 바꿔도
    -- 그대로다. 실제로 그 상태로 배포될 뻔했다.
    local function LoadLayerAndClean(actions)
        FreshInit();
        _G.DebindVars.shared.GENERAL = actions;
        DebindPrivate.LoadProfile();
        DebindPrivate.CleanUpDB();
        return _G.DebindVars.shared.GENERAL;
    end

    local function checkDistinctSeq(actions, msg)
        local seen = {};
        for i, action in ipairs(actions) do
            local seq = action.seq;
            check(seq ~= nil, msg .. ": [" .. i .. "]에 번호가 없다");
            check(not seen[seq], msg .. ": 번호 " .. tostring(seq) .. "이(가) 겹친다");
            seen[seq] = true;
        end
    end

    test("겹치는 순서 번호에 새 번호를 준다", function()
        local actions = LoadLayerAndClean({
            { type = "spell", value = 1, key = "F1", seq = 1 },
            { type = "spell", value = 2, key = "F1", seq = 2 },
            -- 1번과 똑같은 액션. 같은 번호를 들고 들어온다.
            { type = "spell", value = 1, key = "F1", seq = 1 },
        });

        checkDistinctSeq(actions, "겹침 정리 후");
        -- 나중에 만난 쪽이 밀린다. 앞의 둘은 건드릴 이유가 없다.
        check(actions[1].seq == 1 and actions[2].seq == 2,
            "겹치지 않은 번호까지 바뀌었다: " .. tostring(actions[1].seq) .. ", " .. tostring(actions[2].seq));
    end);

    test("번호가 없는 액션과 겹치는 액션이 섞여 있어도 전부 갈린다", function()
        -- nil은 비교자가 0으로 접으므로(Ordering.lua) 둘 다 동률이다. 한 번의 청소로
        -- 두 갈래가 같이 나아야 한다 - nil을 먼저 채우고 나서 겹침을 보기 때문이다.
        local actions = LoadLayerAndClean({
            { type = "spell", value = 1, key = "F1" },
            { type = "spell", value = 2, key = "F1" },
            { type = "spell", value = 3, key = "F1", seq = 1 },
            { type = "spell", value = 4, key = "F1", seq = 1 },
        });

        checkDistinctSeq(actions, "섞인 상태 정리 후");
    end);

    test("키를 뗀 채로 번호만 들고 있는 액션도 겹치면 갈린다", function()
        -- 키를 떼도 번호는 남긴다(PlaceLast). 그 번호가 남의 것과 겹쳐 있으면 다시 걸었을 때
        -- 지킬 자리가 애초에 없으므로, 키가 없다고 넘어가지 않는다.
        local actions = LoadLayerAndClean({
            { type = "spell", value = 1, key = "F1", seq = 1 },
            { type = "spell", value = 2, seq = 1 },
        });

        check(actions[1].seq ~= actions[2].seq,
            "키 없는 액션의 겹친 번호를 지나쳤다: " .. tostring(actions[1].seq) .. ", " .. tostring(actions[2].seq));
    end);

    test("성한 번호는 청소를 거쳐도 그대로다", function()
        local actions = LoadLayerAndClean({
            { type = "spell", value = 1, key = "F1", seq = 3 },
            { type = "spell", value = 2, key = "F2", seq = 7 },
        });

        check(actions[1].seq == 3 and actions[2].seq == 7,
            "멀쩡한 번호를 다시 매겼다: " .. tostring(actions[1].seq) .. ", " .. tostring(actions[2].seq));
    end);

    test("the account's share is not pulled twice", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        -- The user deletes a shared binding.
        _G.DebindVars.shared.GENERAL = {};

        -- An alt logs in. Same account file, different character.
        _G.DebindVars.migrated = {};
        DebindPrivate.RunLegacyMigration();

        check(#_G.DebindVars.shared.GENERAL == 0,
            "a deleted shared binding came back through re-import (legacyAccountPulled failed)");
    end);


    -- Even a fresh install has to open the dummy once - `legacyNeeded` starts as nil, and the only
    -- way to learn there is nothing to move is to look. What matters is that it settles to `false`,
    -- because that is what stops it happening again for this character or any future one.
    test("a fresh install settles at false after looking once", function()
        FreshInit();
        -- No DebounceVars: this account never ran an older version.
        check(DebindPrivate.IsLegacyPending() == true, "a fresh install should still have a question");

        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.legacyNeeded == false, "legacyNeeded did not settle to false");
        check(DebindPrivate.IsLegacyPending() == false, "the question is still open after answering it");
    end);

    test("once false, nothing is ever loaded again", function()
        FreshInit();
        DebindPrivate.RunLegacyMigration();

        -- Old data appears afterwards (a restored WTF folder, say). `false` is final: this account
        -- said its piece, and the dummy is not opened to re-litigate it.
        _G.DebounceVars = LegacyAccount();
        local loads = 0;
        local realLoadAddOn = _G.C_AddOns.LoadAddOn;
        _G.C_AddOns.LoadAddOn = function(...) loads = loads + 1; return realLoadAddOn(...); end
        DebindPrivate.RunLegacyMigration();
        _G.C_AddOns.LoadAddOn = realLoadAddOn;

        check(loads == 0, "the dummy was loaded even though the account is not a migration target");
        check(#(_G.DebindVars.shared.GENERAL or {}) == 0, "something was imported after false");
    end);

    -- The user pressed "start fresh without them". That is recorded as the **same value a fresh
    -- install reaches**, so from here the account simply is not a migration target - including for
    -- characters that have never logged in, and ones not yet created.
    test("declining lands on the same value as a fresh install", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();

        DebindPrivate.DeclineLegacyMigration();

        check(_G.DebindVars.legacyNeeded == false, "declining did not settle the account");
        check(DebindPrivate.IsLegacyPending() == false, "the overlay would still be shown");

        DebindPrivate.RunLegacyMigration();
        check(#(_G.DebindVars.shared.GENERAL or {}) == 0, "the import ran after being declined");
    end);

    test("the account's settings arrive along with its bindings", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.options.unitframeUseMouseDown == true, "the old options did not arrive");
        check(_G.DebindVars.shared.GENERAL[1].key == "F1", "the bindings did not arrive");
    end);

    test("a character already migrated is not read again", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.RunLegacyMigration();

        -- The user deletes a character-specific binding.
        DebindPrivate.db.char.layers[0] = {};
        DebindPrivate.RunLegacyMigration();

        check(#DebindPrivate.db.char.layers[0] == 0, "a deleted character binding came back");
    end);

    -- With the dummy unavailable there is nothing to decide from, so **nothing at all happens** -
    -- no state moves, and the question stays open for the window to put to the user.
    test("a disabled dummy leaves every flag exactly as it was", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();

        local realLoadAddOn = _G.C_AddOns.LoadAddOn;
        _G.C_AddOns.LoadAddOn = function() return false, "DISABLED"; end
        local changed = DebindPrivate.RunLegacyMigration();
        _G.C_AddOns.LoadAddOn = realLoadAddOn;

        check(changed == false, "the load failed but it reported an import");
        check(_G.DebindVars.legacyNeeded == nil,
            "an unanswerable question was answered anyway - nil means 'never looked'");
        check(_G.DebindVars.migrated[GUID] == nil, "the character was marked done without doing it");
        check(DebindPrivate.IsLegacyPending() == true, "the overlay would not be shown");

        -- Once the dummy is back, the next login does the whole job.
        DebindPrivate.RunLegacyMigration();
        check(_G.DebindVars.legacyNeeded == true, "the retry did not settle the account");
        check(#_G.DebindVars.shared.GENERAL == 1, "the retry did not import");
    end);

    test("actions from an older version (dbver=1) are raised to the current one", function()
        FreshInit();
        local old = LegacyAccount();
        old.dbver = 1;
        -- The dbver 2 step numbers actions that have a key. Clear that trace and see it reapplied.
        old.GENERAL[1].seq = nil;
        _G.DebounceVars = old;

        DebindPrivate.RunLegacyMigration();
        check(_G.DebindVars.shared.GENERAL[1].seq == 1,
            "the import was not raised to the current version - MigrateLayer did not run");
    end);

    return T;
end
