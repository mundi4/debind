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
            -- **The excluded Blizzard frames as the old build stored them**, which is the shape the
            -- ladder folds, beside an option whose shape never changed.
            options = { unitframeUseMouseDown = true, blizzframes = { player = false } },
            ui = { anchorPos = { x = 100, y = 200 } },
            spellPickerUI = { pos = { x = 300, y = 400 } },
            overviewui = { pos = { x = 500, y = 600 } },
            -- `spellPicker` is the one key an earlier version of the import lost outright.
            -- `somethingAddedLater` stands for a key the pre-rename addon never wrote.
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
        check(_G.DebindVars.layers ~= nil, "no layers");
        check(_G.DebindVars.characters ~= nil, "no characters");
        check(DebindPrivate.db.charLayers ~= nil, "no charLayers");
    end);

    -- **Every character that logs in is kept**: the entry is what says a GUID has been seen
    -- before, and a character moved off a hardcore realm arrives under a new one.
    test("an empty character still gets its entry, and nothing else", function()
        FreshInit();
        DebindPrivate.CleanUpDB();
        check(_G.DebindVars.characters[GUID] == DebindPrivate.db.char,
            "a character with no content left no entry");
        check(_G.DebindVars.layers[GUID] == nil,
            "a character with no layers got a place in layers (lazy creation is not working)");
    end);

    test("the account's share moves into layers.account", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        local account = _G.DebindVars.layers.account;
        check(account.GENERAL and #account.GENERAL[0] == 1, "GENERAL did not arrive");
        check(account.GENERAL[0][1].key == "F1", "GENERAL contents differ");
        check(account.DRUID and #account.DRUID[0] == 1, "class layer did not arrive");
        check(account.DRUID[0][1].key == "F2", "class layer contents differ");
    end);

    -- **What only the old window read is left behind, and so is a stranger.** Window positions and
    -- the picker's filters cost a drag and a click to set again; a key the pre-rename addon never
    -- wrote was never ours to read.
    test("the old window state and a stranger key stay behind", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        local db = _G.DebindVars;
        check(db.spellPicker == nil and db.ui == nil, "the old window state came across");
        check(DebindPrivate.UIVars.spellPicker == nil and DebindPrivate.UIVars.main == nil,
            "the old window state came across into DebindUIVars");
        check(db.somethingAddedLater == nil, "a key the pre-rename addon never wrote came across");
        check(db.overviewui == nil, "the dead key overviewui came across");
    end);

    --- **The import rides the ladder like a stored profile.** Left unfolded, the reader's side
    --- would see an empty `frameBlacklist` and take every frame they had excluded.
    test("the excluded Blizzard frames are folded on the way in", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        local options = _G.DebindVars.options;
        check(options.blizzframes == nil, "옛 칸이 남았다");
        check(options.frameBlacklist and options.frameBlacklist.blizzard.player == false,
            "빼둔 블리자드 개체창이 안 옮겨졌다");
        check(options.unitframeUseMouseDown == true, "옆 옵션이 같이 날아갔다");
    end);

    test("class keys go only to layers.account and do not leak to the top level", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.DRUID == nil, "a class key leaked to the top level");
        -- 상수로 묻는다. 숫자를 박아두면 `DB_VERSION`을 올릴 때마다 이 줄이 같이 깨지는데,
        -- 그건 마이그레이션이 틀렸다는 신호가 아니라 이 테스트가 낡았다는 신호일 뿐이다.
        check(_G.DebindVars.dbver == DebindPrivate.Constants.DB_VERSION,
            "dbver was overwritten with the old value");
        check(_G.DebindVars.GENERAL == nil, "GENERAL stayed at the top level");
    end);

    --- **Only what the old file had is laid down.** The ladder makes `layers.account` and `options`
    --- whether or not there was anything to raise, so taking its tables whole would replace live
    --- ones the old file never mentioned.
    test("the import leaves alone what the old file did not carry", function()
        FreshInit();
        local class = DebindPrivate.Constants.PLAYER_CLASS;
        DebindPrivate.db.global.options.unitframeUseMouseDown = true;
        DebindPrivate.db.global.layers.account[class] = { [3] = { { type = "spell", value = 9, key = "F9" } } };
        DebindPrivate.db.charLayers[class] = { [3] = { { type = "spell", value = 8, key = "F8" } } };
        local old = LegacyAccount();
        old.options = nil;
        _G.DebounceVars = old;
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.options.unitframeUseMouseDown == true,
            "the live options were replaced though the old file had none");
        check(_G.DebindVars.layers.account[class][3][1].value == 9,
            "a live class layer the old file lacked was dropped");
        check(DebindPrivate.db.charLayers[class][3][1].value == 8,
            "a live character layer the old file lacked was dropped");
        check(DebindPrivate.db.charLayers[class][0][1].key == "F3", "the old character layer did not arrive");
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

    test("the character's share moves into this character's layers", function()
        FreshInit();
        -- The account file has to be there too. Every version that could write a per-character
        -- file created this one on its first run, so its absence is what tells us the account
        -- never ran an older version at all - `legacyNeeded` keys off it alone.
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.RunLegacyMigration();

        local charLayers = DebindPrivate.db.charLayers;
        local mine = charLayers[DebindPrivate.Constants.PLAYER_CLASS];
        check(mine and #mine[0] == 1, "character layer did not arrive");
        check(mine[0][1].key == "F3", "character layer contents differ");
        check(DebindPrivate.GetSavedCustomTarget("custom1") == "focus", "CustomTargets did not arrive");

        DebindPrivate.CleanUpDB();
        check(_G.DebindVars.layers[GUID] == charLayers,
            "there are layers but they were not attached");
        check(_G.DebindVars.states[GUID] == DebindPrivate.db.charState,
            "there are custom targets but the state was not attached");
        check(_G.DebindVars.characters[GUID] == DebindPrivate.db.char,
            "there is content but the entry was not attached");
        check(DebindPrivate.db.char.CustomTargets == nil, "the entry holds the custom targets too");
    end);

    test("the old globals are never modified - the copy must be deep", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.RunLegacyMigration();

        -- Edit the imported side. If references were plugged in, the old tables change with it.
        _G.DebindVars.layers.account.GENERAL[0][1].key = "CHANGED";
        _G.DebindVars.layers.account.DRUID[0][1].key = "CHANGED";
        DebindPrivate.db.charLayers[DebindPrivate.Constants.PLAYER_CLASS][0][1].key = "CHANGED";
        DebindPrivate.SaveCustomTarget("custom1", "CHANGED");

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

        -- **Three renames meet in one body.** This file repairs the addon's rename before the
        -- ladder runs, `dbver <= 6` renames the unit after it, and `dbver <= 7` carries the switch
        -- frame on to its current name. Repaired after the ladder, `DebindStates` would stay.
        local account = _G.DebindVars.layers.account;
        check(account.GENERAL[0][1].value == "/click DebindCustom1 unitframe",
            "a shared layer kept an old name: " .. tostring(account.GENERAL[0][1].value));
        check(account.DRUID[0][1].value == "/click DebindSwitch $state1-on",
            "a class layer kept an old frame name: " .. tostring(account.DRUID[0][1].value));

        local charBody =
            DebindPrivate.db.charLayers[DebindPrivate.Constants.PLAYER_CLASS][0][1].value;
        check(not charBody:find("Debounce") and not charBody:find("DebindStates"),
            "the character layer kept an old frame name: " .. charBody);
        check(charBody:find("/cast Rejuvenation", 1, true), "the rewrite ate the rest of the body");
        check(charBody:find("DebindCustom2", 1, true) and charBody:find("DebindSwitch", 1, true),
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

        check(_G.DebindVars.layers.account.GENERAL[0][1].value == 774,
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
        _G.DebindVars.layers.account = { GENERAL = { [0] = actions } };
        DebindPrivate.LoadProfile();
        DebindPrivate.CleanUpDB();
        return _G.DebindVars.layers.account.GENERAL[0];
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

    -- **No key, no number.** This used to split a keyless action's number off another's as well --
    -- back when taking a key away kept the number, and coming back on a collision left no place to
    -- keep. Taking the key away now drops the number with it (`Profile.lua`'s `ClearActionKey`), so
    -- an action like this only exists in an older profile, and this is where it is cleared out.
    test("키 없는 액션의 번호는 청소가 지운다", function()
        local actions = LoadLayerAndClean({
            { type = "spell", value = 1, key = "F1", seq = 1 },
            { type = "spell", value = 2, seq = 1 },
        });

        check(actions[1].seq == 1, "키 있는 쪽이 바뀌었다: " .. tostring(actions[1].seq));
        check(actions[2].seq == nil, "키 없는 쪽에 번호가 남았다: " .. tostring(actions[2].seq));
    end);

    -- For the same reason, sharing a number with another key's action is normal too.
    test("다른 키끼리 겹치는 번호는 안 건드린다", function()
        local actions = LoadLayerAndClean({
            { type = "spell", value = 1, key = "F1", seq = 1 },
            { type = "spell", value = 2, key = "F2", seq = 1 },
        });

        check(actions[1].seq == 1 and actions[2].seq == 1,
            "번호가 바뀌었다: " .. tostring(actions[1].seq) .. ", " .. tostring(actions[2].seq));
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
        _G.DebindVars.layers.account.GENERAL[0] = {};

        -- An alt logs in. Same account file, different character.
        _G.DebindVars.migrated = {};
        DebindPrivate.RunLegacyMigration();

        check(#_G.DebindVars.layers.account.GENERAL[0] == 0,
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
        check(#_G.DebindVars.layers.account.GENERAL[0] == 0, "something was imported after false");
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
        check(#_G.DebindVars.layers.account.GENERAL[0] == 0, "the import ran after being declined");
    end);

    test("the account's settings arrive along with its bindings", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.options.unitframeUseMouseDown == true, "the old options did not arrive");
        check(_G.DebindVars.layers.account.GENERAL[0][1].key == "F1", "the bindings did not arrive");
    end);

    test("a character already migrated is not read again", function()
        FreshInit();
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.RunLegacyMigration();

        -- The user deletes a character-specific binding.
        local mine = DebindPrivate.db.charLayers[DebindPrivate.Constants.PLAYER_CLASS];
        mine[0] = {};
        DebindPrivate.RunLegacyMigration();

        check(#mine[0] == 0, "a deleted character binding came back");
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
        check(#_G.DebindVars.layers.account.GENERAL[0] == 1, "the retry did not import");
    end);

    test("actions from an older version (dbver=1) are raised to the current one", function()
        FreshInit();
        local old = LegacyAccount();
        old.dbver = 1;
        -- The dbver 2 step numbers actions that have a key. Clear that trace and see it reapplied.
        old.GENERAL[1].seq = nil;
        _G.DebounceVars = old;

        DebindPrivate.RunLegacyMigration();
        check(_G.DebindVars.layers.account.GENERAL[0][1].seq == 1,
            "the import was not raised to the current version - MigrateLayer did not run");
    end);

    ---------------------------------------------------------------------------
    -- dbver 5: 유닛 조건이 축별 마스크로
    --
    -- 스칼라 네 값으로는 "우호 또는 기타"도 "우호이면서 살아있음"도 못 쓴다. 값 하나에
    -- 존재와 반응이 뭉쳐 있어서 축을 얹을 자리가 없기 때문이다.
    --
    -- **뭉친 열거가 아니라 축마다 필드**인 것이 요점이다. 열거였다면 생사·소속이 올 때 같은
    -- 숫자의 뜻이 바뀌어 마이그레이션이 한 번 더 붙는다.
    ---------------------------------------------------------------------------

    local Constants = DebindPrivate.Constants;
    local MigrateLayer = DebindPrivate.MigrateLayer;
    local shim = require("wow_shim");

    test("dbver 5 raises unit conditions to per-axis masks", function()
        local layer = { {
            key = "A", type = 1, value = 1,
            checkedUnits = {
                target    = true,
                focus     = "help",
                mouseover = "harm",
                tank      = false,
            },
        } };
        MigrateLayer(layer, 4);

        local c = layer[1].conditions.units;
        check(type(c.target) == "table" and c.target.reaction == nil,
            "\"존재\"가 빈 테이블이 아님 - 제약하는 축이 없다는 뜻이어야 한다");
        check(type(c.focus) == "table" and c.focus.reaction == Constants.REACTION_HELP,
            "우호가 안 옮겨짐");
        check(type(c.mouseover) == "table" and c.mouseover.reaction == Constants.REACTION_HARM,
            "적대가 안 옮겨짐");
        check(type(c.tank) == "table" and c.tank.exists == false,
            "\"없을 때\"가 표가 아님 - 끈 축을 기억할 자리가 있어야 한다");
    end);

    -- `"@"`도 같은 표에 산다. 유닛 이름이 아니라 포인터일 뿐 값의 모양은 같다.
    test("dbver 5 raises the \"@\" entry too", function()
        local layer = { { key = "A", type = 1, value = 1, unit = "focus",
            checkedUnits = { ["@"] = "help" } } };
        MigrateLayer(layer, 4);
        check(layer[1].conditions.units["@"].reaction == Constants.REACTION_HELP, "\"@\"가 안 옮겨짐");
    end);

    -- 단계는 자기가 이미 끝낸 데이터 위에서 다시 돌아도 안전해야 한다(`MigrateLayer` 주석).
    -- 두 판 밀린 프로필이 여기를 두 번 지난다.
    test("dbver 5 is safe to run twice", function()
        local layer = { { key = "A", type = 1, value = 1,
            checkedUnits = { focus = "help", tank = false } } };
        MigrateLayer(layer, 4);
        MigrateLayer(layer, 4);
        check(layer[1].conditions.units.focus.reaction == Constants.REACTION_HELP, "두 번째에 뭉개짐");
        check(layer[1].conditions.units.tank.exists == false, "두 번째에 뭉개짐");
    end);

    test("dbver 5 leaves actions without unit conditions alone", function()
        local layer = { { key = "A", type = 1, value = 1 } };
        MigrateLayer(layer, 4);
        check(layer[1].conditions == nil, "없던 표가 생김");
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: `equipslot` becomes `useslot`. The stored string is the type, so the rename is a
    -- migration step and not a constant edit (`0-ROADMAP.md`, 2026-08-28).
    ---------------------------------------------------------------------------

    test("dbver 7 renames the equipslot type", function()
        local layer = { { key = "A", type = "equipslot", value = 13 } };
        MigrateLayer(layer, 6);
        check(layer[1].type == Constants.USESLOT, "타입이 " .. tostring(layer[1].type));
        check(layer[1].value == 13, "값이 따라 바뀌었다");
    end);

    test("dbver 7 leaves every other type alone", function()
        local layer = {
            { key = "A", type = Constants.SPELL, value = 13 },
            { key = "B", type = Constants.ITEM, value = 13 },
        };
        MigrateLayer(layer, 6);
        check(layer[1].type == Constants.SPELL and layer[2].type == Constants.ITEM, "다른 타입이 바뀌었다");
    end);

    -- An action slot command becomes the action button action, under the same command name
    -- (`dropping-the-game-fallback.md` §3). Every other command stays what it was saved as.
    test("dbver 7 moves the action slot commands to the action button type", function()
        local layer = {
            { key = "A", type = Constants.COMMAND, value = "ACTIONBUTTON3" },
            { key = "B", type = Constants.COMMAND, value = "MULTIACTIONBAR7BUTTON12" },
            { key = "C", type = Constants.COMMAND, value = "EXTRAACTIONBUTTON1" },
            { key = "D", type = Constants.COMMAND, value = "TOGGLEWORLDMAP" },
        };
        -- Stopped at 7: the next step turns what is left into a block.
        MigrateLayer(layer, 6, 7);
        for i = 1, 3 do
            check(layer[i].type == Constants.ACTIONBUTTON, layer[i].value .. ": " .. tostring(layer[i].type));
        end
        check(layer[1].value == "ACTIONBUTTON3", "the value moved: " .. tostring(layer[1].value));
        check(layer[4].type == Constants.COMMAND, "a command with nowhere to go moved");
    end);

    test("dbver 7 is safe to run twice", function()
        local layer = { { key = "A", type = "equipslot", value = 13 } };
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        check(layer[1].type == Constants.USESLOT, "두 번째에 뭉개짐: " .. tostring(layer[1].type));
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: a pinned rank moves out of `value` into `pinnedSpell`
    -- (`keeping-a-pinned-rank-apart-from-the-spell.md`). `value` keeps the id it held, which is
    -- still that spell; only the profile's own step can put it on the first rank.
    ---------------------------------------------------------------------------

    test("dbver 7 moves a pinned rank into pinnedSpell", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 705, pinRank = true } };
        MigrateLayer(layer, 7);
        check(layer[1].pinnedSpell == 705, "pinnedSpell: " .. tostring(layer[1].pinnedSpell));
        check(layer[1].pinRank == nil, "pinRank stayed");
        check(layer[1].value == 705, "value: " .. tostring(layer[1].value));
    end);

    -- A payload's fields arrive as any type at all (the ladder's header), and only a spell can hold a
    -- rank.
    test("dbver 7 drops a pin that is not a spell's or not true", function()
        local layer = {
            { key = "A", type = Constants.ITEM, value = 705, pinRank = true },
            { key = "B", type = Constants.SPELL, value = 705, pinRank = "yes" },
            { key = "C", type = Constants.SPELL, value = "Shadow Bolt", pinRank = true },
        };
        MigrateLayer(layer, 7);
        for i = 1, 2 do
            check(layer[i].pinRank == nil and layer[i].pinnedSpell == nil,
                layer[i].key .. ": " .. tostring(layer[i].pinRank) .. " " .. tostring(layer[i].pinnedSpell));
        end
        check(layer[3].pinnedSpell == nil and layer[3].pinRank == nil, "a name was pinned as its own rank");
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: a saved command or unused becomes a block where it stands
    -- (`handing-the-rest-of-a-key-to-the-game.md` 2-8). Left as either type, the order would carry it
    -- to the top or the bottom of its key and set free whatever it was blocking.
    ---------------------------------------------------------------------------

    test("dbver 7 turns a saved command and unused into blocks", function()
        local layer = {
            { key = "A", type = Constants.COMMAND, value = "TOGGLEWORLDMAP", seq = 2,
                conditions = { combat = true } },
            { key = "B", type = Constants.UNUSED, seq = 1 },
        };
        MigrateLayer(layer, 7);
        check(layer[1].type == Constants.BLOCK, "command: " .. tostring(layer[1].type));
        check(layer[1].value == nil, "command value stayed: " .. tostring(layer[1].value));
        check(layer[1].seq == 2 and layer[1].key == "A" and layer[1].conditions.combat == true,
            "the command's place or conditions moved");
        check(layer[2].type == Constants.BLOCK, "unused: " .. tostring(layer[2].type));
        check(layer[2].seq == 1 and layer[2].key == "B", "the unused's place moved");
    end);

    test("dbver 7 leaves an action button command to the step before it", function()
        local layer = { { key = "A", type = Constants.COMMAND, value = "ACTIONBUTTON3" } };
        MigrateLayer(layer, 6);
        check(layer[1].type == Constants.ACTIONBUTTON, "type: " .. tostring(layer[1].type));
        check(layer[1].value == "ACTIONBUTTON3", "value: " .. tostring(layer[1].value));
    end);

    test("dbver 7 is safe to run twice over a pin", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 705, pinRank = true } };
        MigrateLayer(layer, 7);
        MigrateLayer(layer, 7);
        check(layer[1].pinnedSpell == 705, "pinnedSpell: " .. tostring(layer[1].pinnedSpell));
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: `known`이 "물어본다"에서 **무엇을 묻는가**로 바뀐다
    -- (`making-known-a-spell-name.md`).
    ---------------------------------------------------------------------------

    local function knownLayer(action)
        action.key = "A";
        action.conditions = { known = true };
        return { action };
    end

    test("dbver 7 turns a spell's known into the name it asks about", function()
        shim.world.spells[8936] = { name = "Regrowth" };
        local layer = knownLayer({ type = Constants.SPELL, value = 8936 });
        MigrateLayer(layer, 6);
        check(layer[1].conditions.known == "Regrowth",
            "known: " .. tostring(layer[1].conditions.known));
    end);

    -- A name the client cannot hand back leaves the id standing. A spell nobody can place is one
    -- whose `[known:]` answer is false anyway, so the conditional it bakes says the same thing.
    test("dbver 7 keeps the id where the client has no name for it", function()
        local layer = knownLayer({ type = Constants.SPELL, value = 424242 });
        MigrateLayer(layer, 6);
        check(layer[1].conditions.known == 424242,
            "known: " .. tostring(layer[1].conditions.known));
    end);

    -- The three types whose spell the specialization picks keep `true`, which goes on meaning
    -- "the spell this action resolves to". A name would nail it to one specialization.
    test("dbver 7 leaves a spec-resolved known as true", function()
        local layer = knownLayer({ type = Constants.DISPEL });
        MigrateLayer(layer, 6);
        check(layer[1].conditions.known == true,
            "known: " .. tostring(layer[1].conditions.known));
    end);

    -- **A `known` on a type that is not a spell is dropped, not raised.** The old normalization threw
    -- such a line away whole (`FillBinding`), so the stored value was doing nothing. Raised to a
    -- name, that name bakes into the conditional, and the name of a macro or an item id is false
    -- for good, so the key dies in silence.
    test("dbver 7 drops a known on a type that has no spell", function()
        local layer = knownLayer({ type = Constants.MACROTEXT, value = "/cast Foo" });
        MigrateLayer(layer, 6);
        check(layer[1].conditions.known == nil,
            "known: " .. tostring(layer[1].conditions.known));
    end);

    -- 이름을 든 것도 같다. **UI가 만들 수 없는 값**이고, 주문이 아닌 액션에서는 그 조건을 여는
    -- 메뉴 자체가 안 서므로 저장에 남으면 되돌릴 길이 없다.
    test("dbver 7 drops a named known on a type that has no spell", function()
        local layer = { { key = "A", type = Constants.MACROTEXT, value = "/cast Foo",
            conditions = { known = "Regrowth" } } };
        MigrateLayer(layer, 6);
        check(layer[1].conditions.known == nil,
            "known: " .. tostring(layer[1].conditions.known));
    end);

    -- **저장까지 지운다.** 사다리를 이미 지난 프로필과 지금 `dbver`로 들어온 공유 문자열은
    -- 그 단계를 안 타므로, 로그인과 로그아웃마다 도는 청소가 같은 규칙을 한 번 더 건다.
    test("cleanup drops a known that its action's type cannot carry", function()
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = {
                { key = "F1", seq = 1, type = Constants.MACROTEXT, value = "/cast Foo",
                    conditions = { known = "Regrowth" } },
                { key = "F2", seq = 1, type = Constants.SPELL, value = 8936,
                    conditions = { known = "Regrowth" } },
            } } } },
            characters = {},
            migrated = {},
        };
        DebindPrivate.InitDB();
        DebindPrivate.CleanUpDB();

        local general = _G.DebindVars.layers.account.GENERAL[0];
        check(general[1].conditions == nil or general[1].conditions.known == nil,
            "매크로 액션에 남음: " .. tostring(general[1].conditions and general[1].conditions.known));
        check(general[2].conditions.known == "Regrowth",
            "주문 액션에서 사라짐: " .. tostring(general[2].conditions and general[2].conditions.known));
    end);

    test("dbver 7 is safe to run twice over a known", function()
        shim.world.spells[8936] = { name = "Regrowth" };
        local layer = knownLayer({ type = Constants.SPELL, value = 8936 });
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        check(layer[1].conditions.known == "Regrowth",
            "known: " .. tostring(layer[1].conditions.known));
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: 유닛 조건의 세 모드가 저마다 자기 값을 든다.
    --
    -- **빈 표가 "있을 때"를 뜻하던 것이 이 단계가 없애는 것이다.** 리포의 나머지는 빈 표를
    -- 아무것도 아닌 것으로 접는다 - `ActionSignature`가 그렇게 접는 바람에 유닛 조건 하나만
    -- 걸린 액션이 조건 없는 액션과 같은 서명을 냈고, 중복 제거가 둘을 한 쌍으로 봤다.
    --
    -- `off`는 같은 상태를 가리키는 리포의 말(`AppendDisable`, `disabledReason`)과 갈라져
    -- 있었다. 이름만 바꾸는 것이라 뜻은 그대로다.
    ---------------------------------------------------------------------------

    local function unitCond(value)
        return { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { units = { target = value } } } };
    end

    test("dbver 7 stamps exists on a condition that carried no marker", function()
        local layer = unitCond({});
        MigrateLayer(layer, 6);
        local cond = layer[1].conditions.units.target;
        check(cond.exists == true, "exists가 " .. tostring(cond.exists));
    end);

    test("dbver 7 stamps exists beside the axes a condition remembered", function()
        local layer = unitCond({ reaction = Constants.REACTION_HELP, dead = false });
        MigrateLayer(layer, 6);
        local cond = layer[1].conditions.units.target;
        check(cond.exists == true, "exists가 " .. tostring(cond.exists));
        check(cond.reaction == Constants.REACTION_HELP and cond.dead == false, "축이 바뀌었다");
    end);

    test("dbver 7 leaves [when there is none] alone", function()
        local layer = unitCond({ exists = false, dead = true });
        MigrateLayer(layer, 6);
        local cond = layer[1].conditions.units.target;
        check(cond.exists == false, "exists가 " .. tostring(cond.exists));
        check(cond.dead == true, "기억한 축이 사라졌다");
    end);

    test("dbver 7 renames off to disabled and stamps no exists on it", function()
        local layer = unitCond({ off = true, reaction = Constants.REACTION_HARM });
        MigrateLayer(layer, 6);
        local cond = layer[1].conditions.units.target;
        check(cond.disabled == true, "disabled가 " .. tostring(cond.disabled));
        check(cond.off == nil, "옛 이름이 남았다");
        check(cond.exists == nil, "꺼진 조건에 모드가 얹혔다: " .. tostring(cond.exists));
        check(cond.reaction == Constants.REACTION_HARM, "기억한 축이 사라졌다");
    end);

    --- 개체창 조건에 축이 하나라도 있으면 조건으로 남고, 그 표도 `exists`를 받는다. 축이 없는
    --- [올렸을 때]뿐인 조건은 Casting으로 옮겨져 여기 안 남는다(아래 단계).
    test("dbver 7 walks every unit key, the unit frame and @ included", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1, unit = "focus",
            conditions = { units = { hover = { reaction = Constants.REACTION_HELP },
                ["@"] = { reaction = Constants.REACTION_HELP } } } } };
        MigrateLayer(layer, 6);
        local units = layer[1].conditions.units;
        check(units.unitframe.exists == true, "unitframe이 " .. tostring(units.unitframe.exists));
        check(units["@"].exists == true, "@가 " .. tostring(units["@"].exists));
    end);

    --- 개체창 유닛의 이름이 `hover`에서 `unitframe`으로 간다. `hover`는 3단계에서 **다른 뜻**으로
    --- 돌아오므로, 안 옮긴 값은 안 깨지는 것이 아니라 조용히 다른 것을 뜻하게 된다.
    test("dbver 7 renames the pointed frame's unit condition", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } } };
        MigrateLayer(layer, 6);
        local units = layer[1].conditions.units;
        check(units.hover == nil, "옛 이름이 남았다");
        check(units.unitframe and units.unitframe.reaction == Constants.REACTION_HELP,
            "반응이 안 따라왔다: " .. tostring(units.unitframe and units.unitframe.reaction));
    end);

    test("dbver 7 renames the picked target too", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1, unit = "hover" } };
        MigrateLayer(layer, 6);
        check(layer[1].unit == "unitframe", "unit이 " .. tostring(layer[1].unit));
    end);

    --- **본문도 옮긴다.** 유닛을 이름으로 읽는 자리라, 안 옮기면 파서가 못 알아보고 게임에 글자
    --- 그대로 나가는데 아무것도 안 터진다.
    test("dbver 7 renames the unit token in a hand-written body", function()
        local layer = { { key = "A", type = Constants.MACROTEXT,
            value = "/cast [@hover,harm] Smite\n/cast [@hovertarget] Renew" } };
        MigrateLayer(layer, 6);
        check(layer[1].value == "/cast [@unitframe,harm] Smite\n/cast [@unitframetarget] Renew",
            "본문이 " .. tostring(layer[1].value) .. "다");
    end);

    --- **토큰 전체일 때만.** 사용자가 손으로 친 글자라, 이 유닛이 아닌 것을 건드리면 말없이 바뀐
    --- 매크로를 스스로 찾아내야 한다.
    test("dbver 7 leaves a body that only looks like the unit alone", function()
        local layer = { { key = "A", type = Constants.MACROTEXT,
            value = "/say [@hovering] hi\n/say hover" } };
        MigrateLayer(layer, 6);
        check(layer[1].value == "/say [@hovering] hi\n/say hover",
            "본문이 " .. tostring(layer[1].value) .. "다");
    end);

    test("dbver 7 renames the unit a custom target is filled from", function()
        local layer = { { key = "A", type = Constants.MACROTEXT,
            value = "/click DebindCustom1 hover" } };
        MigrateLayer(layer, 6);
        check(layer[1].value == "/click DebindCustom1 unitframe",
            "본문이 " .. tostring(layer[1].value) .. "다");
    end);

    test("dbver 7 is safe to run twice over the rename", function()
        local layer = { { key = "A", type = Constants.MACROTEXT, unit = "hover",
            value = "/cast [@hover] Renew",
            conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } } };
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        check(layer[1].unit == "unitframe", "unit이 " .. tostring(layer[1].unit));
        check(layer[1].value == "/cast [@unitframe] Renew", "본문이 " .. tostring(layer[1].value) .. "다");
        check(layer[1].conditions.units.unitframe ~= nil, "조건이 사라졌다");
    end);

    test("dbver 7 leaves an action with no unit conditions alone", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { combat = true } } };
        MigrateLayer(layer, 6);
        check(layer[1].conditions.units == nil, "없던 표가 생김");
        check(layer[1].conditions.combat == true, "다른 조건이 바뀌었다");
    end);

    test("dbver 7 is safe to run twice", function()
        local layer = unitCond({ off = true, dead = true });
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        local cond = layer[1].conditions.units.target;
        check(cond.disabled == true and cond.off == nil and cond.exists == nil,
            "두 번째에 뭉개짐");
    end);

    test("dbver 7 leaves a scalar it cannot read alone", function()
        local layer = unitCond("help");
        MigrateLayer(layer, 6);
        check(layer[1].conditions.units.target == "help", "스칼라를 건드렸다");
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: 소환수 조건이 소환수 유닛의 행이 된다.
    --
    -- 둘 다 "소환수가 있느냐"를 물었고 유닛 행 쪽은 생사까지 든다. 좁은 쪽이 남을 이유가 없다.
    ---------------------------------------------------------------------------

    test("dbver 7 folds the pet condition into the pet unit row", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { pet = true } } };
        MigrateLayer(layer, 6);
        local c = layer[1].conditions;
        check(c.pet == nil, "옛 축이 남았다: " .. tostring(c.pet));
        check(c.units and c.units.pet and c.units.pet.exists == true,
            "행이 안 섰다: " .. tostring(c.units and c.units.pet and c.units.pet.exists));
    end);

    test("dbver 7 folds [when you have no pet] the same way", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { pet = false } } };
        MigrateLayer(layer, 6);
        local c = layer[1].conditions;
        check(c.pet == nil, "옛 축이 남았다");
        check(c.units.pet.exists == false, "exists가 " .. tostring(c.units.pet.exists));
    end);

    -- 한 행이 두 답을 들 수 없다. 서 있던 행이 이기고 축은 버려진다.
    test("dbver 7 keeps a pet row that was already there", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { pet = true, units = { pet = { exists = false, dead = true } } } } };
        MigrateLayer(layer, 6);
        local c = layer[1].conditions;
        check(c.pet == nil, "옛 축이 남았다");
        check(c.units.pet.exists == false and c.units.pet.dead == true, "서 있던 행이 뭉개졌다");
    end);

    test("dbver 7 leaves the other unit rows alone while folding", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { pet = true, units = { target = { exists = true } } } } };
        MigrateLayer(layer, 6);
        local units = layer[1].conditions.units;
        check(units.target.exists == true, "다른 행이 바뀌었다");
        check(units.pet.exists == true, "행이 안 섰다");
    end);

    -- **사다리를 아래 칸부터 탄 프로필.** `pet`은 저장에서 조건 이름이 아니게 됐는데, 최상단
    -- 조건을 `conditions` 안으로 내리는 것은 `dbver <= 5`이고 그 단계가 무엇이 조건인지를
    -- `IsConditionField`에 묻는다. 이름이 표에서 빠지면 그 액션의 `pet`은 최상단에 남고,
    -- 접는 단계는 `conditions.pet`만 보므로 만나지 못한다. 그 뒤 `CleanUpDB`가 지운다.
    test("a pet condition from before conditions moved still folds", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1, pet = true } };
        MigrateLayer(layer, 5);
        check(layer[1].pet == nil, "최상단에 남았다: " .. tostring(layer[1].pet));
        local units = layer[1].conditions and layer[1].conditions.units;
        check(units and units.pet and units.pet.exists == true,
            "행이 안 섰다: " .. tostring(units and units.pet and units.pet.exists));
    end);

    -- 같은 값이 더 아래에서 올라오는 길. `dbver <= 1`이 옛 `checkedUnits["pet"]`을 최상단
    -- `action.pet`으로 만든다.
    test("the oldest pet shape rides the whole ladder into the row", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            checkedUnits = { pet = false } } };
        MigrateLayer(layer, 1);
        local units = layer[1].conditions and layer[1].conditions.units;
        check(units and units.pet and units.pet.exists == false,
            "행이 안 섰다: " .. tostring(units and units.pet and units.pet.exists));
    end);

    -- **꺼진 행은 반대 답이 아니라 답이 없는 것이다.** 옛 축이 걸어둔 조건을 그 행에 넘기지
    -- 않으면 액션이 조건을 통째로 잃는다.
    test("a disabled pet row does not swallow the axis", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { pet = true, units = { pet = { disabled = true, dead = true } } } } };
        MigrateLayer(layer, 6);
        local cond = layer[1].conditions.units.pet;
        check(layer[1].conditions.pet == nil, "옛 축이 남았다");
        check(cond.exists == true, "조건이 사라졌다: exists가 " .. tostring(cond.exists));
        check(cond.disabled == nil, "끈 표시가 남았다");
        check(cond.dead == true, "기억한 축이 사라졌다");
    end);

    test("dbver 7 pet fold is safe to run twice", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { pet = false } } };
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        check(layer[1].conditions.units.pet.exists == false, "두 번째에 뭉개짐");
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: 프레임 종류가 가리킨 개체창 유닛 조건의 축이 된다.
    --
    -- 자기 조건 필드였던 것은 개체창이 자기 조건 축을 갖고 있던 시절의 모양이다. 그 유닛이
    -- 보통 유닛이 되면서(`which-action-a-key-runs.md` §0) 마스크도 그 유닛에 대해
    -- 하는 말 하나가 된다.
    ---------------------------------------------------------------------------

    test("dbver 7 folds the frame type mask into the pointed frame's unit row", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { frameTypes = Constants.FRAMETYPE_GROUP,
                units = { unitframe = { exists = true, reaction = Constants.REACTION_HELP } } } } };
        MigrateLayer(layer, 6);
        local c = layer[1].conditions;
        check(c.frameTypes == nil, "옛 축이 남았다: " .. tostring(c.frameTypes));
        check(c.units.unitframe.frameTypes == Constants.FRAMETYPE_GROUP,
            "행에 안 실렸다: " .. tostring(c.units.unitframe.frameTypes));
        check(c.units.unitframe.reaction == Constants.REACTION_HELP, "다른 축이 바뀌었다");
    end);

    -- **개체창 조건이 없는 액션의 마스크도 안 버린다.** 끄는 것과 지우는 것은 다르므로,
    -- 조건을 켜면 고른 값이 그대로 있어야 한다. 그래서 [사용 안 함]인 행으로 들어간다.
    test("dbver 7 remembers the mask on an action with no unit frame condition", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { frameTypes = Constants.FRAMETYPE_BOSS } } };
        MigrateLayer(layer, 6);
        local row = layer[1].conditions.units.unitframe;
        check(row.disabled == true, "켜진 조건이 생겼다: " .. tostring(row.disabled));
        check(row.frameTypes == Constants.FRAMETYPE_BOSS,
            "마스크가 사라졌다: " .. tostring(row.frameTypes));
    end);

    -- 한 행이 두 답을 들 수 없다. 서 있던 마스크가 이긴다 - 새 모양에 맞춰 고친 값을
    -- 바깥의 옛 값으로 되돌리면 안 된다.
    test("dbver 7 keeps a frame type mask that was already on the row", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { frameTypes = Constants.FRAMETYPE_BOSS,
                units = { unitframe = { exists = true,
                    frameTypes = Constants.FRAMETYPE_GROUP } } } } };
        MigrateLayer(layer, 6);
        check(layer[1].conditions.units.unitframe.frameTypes == Constants.FRAMETYPE_GROUP,
            "서 있던 마스크가 뭉개졌다");
        check(layer[1].conditions.frameTypes == nil,
            "밖의 옛 값이 남았다: " .. tostring(layer[1].conditions.frameTypes));
    end);

    -- **사다리를 아래 칸부터 탄 프로필.** 소환수 축과 같은 사정이다: `frameTypes`가 조건
    -- 이름에서 빠졌으므로 최상단 조건을 내리는 `dbver <= 5` 단계가 그것을 안 옮기고, 마스크는
    -- 액션 최상단에 남은 채로 이 단계를 만난다.
    test("a frame type mask from before conditions moved still folds", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            frameTypes = Constants.FRAMETYPE_GROUP,
            checkedUnits = { hover = {} } } };
        MigrateLayer(layer, 5);
        check(layer[1].frameTypes == nil, "최상단에 남았다: " .. tostring(layer[1].frameTypes));
        local row = layer[1].conditions and layer[1].conditions.units
            and layer[1].conditions.units.unitframe;
        check(row and row.frameTypes == Constants.FRAMETYPE_GROUP,
            "행에 안 실렸다: " .. tostring(row and row.frameTypes));
    end);

    test("dbver 7 frame type fold is safe to run twice", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 1,
            conditions = { frameTypes = Constants.FRAMETYPE_GROUP,
                units = { unitframe = { exists = true } } } } };
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        check(layer[1].conditions.units.unitframe.frameTypes == Constants.FRAMETYPE_GROUP,
            "두 번째에 뭉개짐");
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: 발동 순서에서 개체창 단계가 빠진 자리를 번호가 받는다.
    --
    -- **이 단계가 틀리면 화면에 아무것도 안 뜬 채 순서가 뒤집힌다.** 비교자는 개체창 조건이
    -- 걸린 액션을 안 걸린 것보다 앞세우고 있었고, 그 단계가 없어지면 그 자리를 `seq`가 들어야
    -- 한다. 그래서 키 묶음마다 **옛 비교자** 순서로 1..n을 다시 매긴다.
    ---------------------------------------------------------------------------

    --- 같은 키의 두 액션을 배열 순서대로 넣고, 마이그레이션 뒤의 번호를 돌려준다.
    local function seqsAfterMigrate(layer)
        MigrateLayer(layer, 6);
        local out = {};
        for i = 1, #layer do
            out[i] = layer[i].seq;
        end
        return out;
    end

    -- The unit frame condition was on the later number, and the old comparator put it first, so it
    -- has to come out as 1. Left unrenumbered, the new comparator finds two conditional actions
    -- tied and lets `seq` decide, which turns the order over.
    --
    -- **Both carry `combat`**, so both are still conditional after the upgrade and nothing but
    -- `seq` stands between them. With the first one unconditional, the conditions step would put
    -- the second in front on its own, and this case would pass with no renumbering at all.
    test("dbver 7 renumbers so the old unit frame tier keeps its order", function()
        local seqs = seqsAfterMigrate({
            { key = "F1", seq = 1, type = Constants.SPELL, value = 1,
                conditions = { combat = true } },
            { key = "F1", seq = 2, type = Constants.SPELL, value = 2,
                conditions = { combat = true, units = { unitframe = { exists = true } } } },
        });
        check(seqs[2] == 1, "개체창 조건이 1번이 아니다: " .. tostring(seqs[2]));
        check(seqs[1] == 2, "조건 액션이 2번이 아니다: " .. tostring(seqs[1]));
    end);

    -- **[안 올렸을 때]도 개체창 조건이다.** 옛 비교자는 `nil`이 아닌 것을 앞세웠지 참인 것을
    -- 앞세운 것이 아니다.
    test("dbver 7 counts [when not over a frame] as the old tier did", function()
        local seqs = seqsAfterMigrate({
            { key = "F1", seq = 1, type = Constants.SPELL, value = 1,
                conditions = { combat = true } },
            { key = "F1", seq = 2, type = Constants.SPELL, value = 2,
                conditions = { units = { unitframe = { exists = false } } } },
        });
        check(seqs[2] == 1, "[안 올렸을 때]가 1번이 아니다: " .. tostring(seqs[2]));
    end);

    -- 꺼진 조건은 조건이 아니다. 옛 비교자도 접어서 봤으므로 꺼진 행을 든 액션은 개체창
    -- 단계를 못 탄다. 진짜 개체창 조건을 든 셋째가 있어야 번호가 실제로 움직이고, 꺼진 것을
    -- 조건으로 세면 그 액션이 같이 앞으로 딸려 오는 것이 보인다.
    test("dbver 7 does not let a disabled unit frame condition win the tier", function()
        local seqs = seqsAfterMigrate({
            { key = "F1", seq = 1, type = Constants.SPELL, value = 1,
                conditions = { combat = true } },
            { key = "F1", seq = 2, type = Constants.SPELL, value = 2,
                conditions = { combat = false, units = { unitframe = { disabled = true } } } },
            -- 조건이 하나 더 있는 이유는 위 테스트와 같다.
            { key = "F1", seq = 3, type = Constants.SPELL, value = 3,
                conditions = { combat = true, units = { unitframe = { exists = true } } } },
        });
        check(seqs[3] == 1, "진짜 개체창 조건이 1번이 아니다: " .. tostring(seqs[3]));
        check(seqs[1] == 2, "조건 액션이 2번이 아니다: " .. tostring(seqs[1]));
        check(seqs[2] == 3, "꺼진 조건이 앞질렀다: " .. tostring(seqs[2]));
    end);

    -- 중요도가 개체창보다 위다. 옛 비교자의 첫 단계라 개체창 조건이 밴드를 못 넘는다.
    test("dbver 7 keeps importance above the old unit frame tier", function()
        local seqs = seqsAfterMigrate({
            { key = "F1", seq = 2, type = Constants.SPELL, value = 1, priority = 1 },
            { key = "F1", seq = 1, type = Constants.SPELL, value = 2,
                conditions = { units = { unitframe = { exists = true } } } },
        });
        check(seqs[1] == 1, "중요도가 밀렸다: " .. tostring(seqs[1]));
        check(seqs[2] == 2, "개체창 조건이 앞질렀다: " .. tostring(seqs[2]));
    end);

    -- 키 묶음마다 1부터다. 한 레이어의 번호를 통째로 세면 다른 키의 액션이 사이에 끼어
    -- 번호가 벌어지고, `RenumberKeyGroup`이 다음에 돌 때 그것을 다시 접는다.
    test("dbver 7 numbers each key group from one", function()
        local seqs = seqsAfterMigrate({
            { key = "F1", seq = 1, type = Constants.SPELL, value = 1 },
            { key = "F2", seq = 2, type = Constants.SPELL, value = 2 },
            { key = "F1", seq = 3, type = Constants.SPELL, value = 3 },
        });
        check(seqs[1] == 1 and seqs[3] == 2, "F1이 1,2가 아니다: "
            .. tostring(seqs[1]) .. "," .. tostring(seqs[3]));
        check(seqs[2] == 1, "F2가 1이 아니다: " .. tostring(seqs[2]));
    end);

    -- 받은 묶음은 제 번호 공간이다. 같이 세면 격리된 액션이 읽는 이의 순서 안으로 끼어든다.
    test("dbver 7 numbers an arrival apart from the reader's own set", function()
        local seqs = seqsAfterMigrate({
            { key = "F1", seq = 1, type = Constants.SPELL, value = 1 },
            { key = "F1", seq = 2, type = Constants.SPELL, value = 2, arrivalID = 3 },
        });
        check(seqs[1] == 1 and seqs[2] == 1, "묶음이 같이 세어졌다: "
            .. tostring(seqs[1]) .. "," .. tostring(seqs[2]));
    end);

    -- 키가 없으면 번호도 없다(`PlaceInKeyGroup`). 번호를 주면 그 액션만 영원히 한 묶음으로 선다.
    test("dbver 7 leaves a keyless action without a number", function()
        local layer = { { type = Constants.SPELL, value = 1 } };
        MigrateLayer(layer, 6);
        check(layer[1].seq == nil, "번호가 생겼다: " .. tostring(layer[1].seq));
    end);

    ---------------------------------------------------------------------------
    -- dbver 7: the three boxes become one `casting` table
    --
    -- **An old unit frame condition action becomes a twin-only action**
    -- (`which-action-a-key-runs.md` §8). It meant "on a pointed press only, ahead of the
    -- layers", which in the new shape is Hover Cast on Unit Frames with Normal Cast off. The rest keep
    -- doing what they did: a keyboard key as Cast as usual, a mouse button as Skip on Unit Frames.
    ---------------------------------------------------------------------------

    local function castingAfterMigrate(action)
        local layer = { action };
        MigrateLayer(layer, 6);
        return layer[1].casting or {}, layer[1];
    end

    test("dbver 7 moves the two cast key boxes onto casting", function()
        local casting = castingAfterMigrate({ key = "F1", type = Constants.SPELL, value = 1,
            ignoreSelfCastKey = true, ignoreFocusCastKey = true });
        check(casting.selfCastKey == "skip", "self가 " .. tostring(casting.selfCastKey));
        check(casting.focusCastKey == "skip", "focus가 " .. tostring(casting.focusCastKey));
    end);

    test("dbver 7 leaves an action that ignored neither cast key alone", function()
        local casting = castingAfterMigrate({ key = "F1", type = Constants.SPELL, value = 1 });
        check(casting.selfCastKey == nil and casting.focusCastKey == nil,
            "안 끈 조합키에 값이 생겼다");
    end);

    --- **An action with no unit frame condition gets nothing written**, because off is the default
    --- and off is what it did: the pointed press reaches its original in the last tier.
    test("dbver 7 leaves an action with no unit frame condition alone", function()
        for _, key in ipairs({ "F1", "ALT-BUTTON4" }) do
            local casting = castingAfterMigrate({ key = key, type = Constants.SPELL, value = 1 });
            check(next(casting) == nil, key .. ": " .. tostring(casting.hoverCastMode)
                .. "/" .. tostring(casting.hoverCast) .. "/" .. tostring(casting.normalCast));
        end
    end);

    --- 빈 [올렸을 때]. 조건이 하던 일을 Casting 값 둘이 통째로 들고, 조건은 안 남는다.
    test("dbver 7 turns a bare unit frame condition into a twin-only action", function()
        local casting, action = castingAfterMigrate({ key = "F1", type = Constants.SPELL, value = 1,
            conditions = { units = { unitframe = { exists = true } } } });
        check(casting.hoverCastMode == "unitframe",
            "Hover Cast가 " .. tostring(casting.hoverCastMode));
        check(casting.normalCast == false, "Normal Cast가 " .. tostring(casting.normalCast));
        check(action.conditions == nil or action.conditions.units == nil,
            "빈 조건이 남았다");
    end);

    --- 축이 붙어 있으면 조건으로 남는다. 반응과 역할과 프레임 종류는 쌍둥이가 물려받아야 한다.
    test("dbver 7 keeps a unit frame condition that says more than [there is one]", function()
        local casting, action = castingAfterMigrate({ key = "F1", type = Constants.SPELL, value = 1,
            conditions = { units = { unitframe = { exists = true, reaction = Constants.REACTION_HELP,
                role = Constants.ROLE_HEALER } } } });
        check(casting.hoverCastMode == "unitframe",
            "Hover Cast가 " .. tostring(casting.hoverCastMode));
        check(casting.normalCast == false, "Normal Cast가 " .. tostring(casting.normalCast));
        local row = action.conditions.units.unitframe;
        check(row and row.reaction == Constants.REACTION_HELP and row.role == Constants.ROLE_HEALER,
            "축이 사라졌다");
    end);

    --- 겨누기를 껐던 액션은 Cast as usual로 온다. 쌍둥이는 서되 원본이 가는 곳으로 나간다.
    test("dbver 7 moves the pointed unit box onto the aim", function()
        local casting = castingAfterMigrate({ key = "F1", type = Constants.SPELL, value = 1,
            ignoreHoverUnit = true,
            conditions = { units = { unitframe = { exists = true } } } });
        check(casting.hoverCast == "usual", "겨눔이 " .. tostring(casting.hoverCast));
        check(casting.normalCast == false, "Normal Cast가 " .. tostring(casting.normalCast));
    end);

    --- [when none is pointed at] never ran over a unit frame, so there is nothing to turn on. The
    --- condition stays and says it, and the action gets what any other old action gets, nothing.
    test("dbver 7 keeps [when none is pointed at] as a condition", function()
        local casting, action = castingAfterMigrate({ key = "F1", type = Constants.SPELL, value = 1,
            conditions = { units = { unitframe = { exists = false } } } });
        check(next(casting) == nil, "Hover Cast가 " .. tostring(casting.hoverCast));
        check(action.conditions.units.unitframe.exists == false, "조건이 사라졌다");
    end);

    test("dbver 7 casting is safe to run twice", function()
        local layer = { { key = "F1", type = Constants.SPELL, value = 1,
            conditions = { units = { unitframe = { exists = true } } } } };
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        local casting = layer[1].casting;
        check(casting.hoverCastMode == "unitframe" and casting.normalCast == false,
            "두 번째에 뭉개짐");
        check(layer[1].conditions == nil or layer[1].conditions.units == nil, "조건이 되살아났다");
    end);

    test("dbver 7 renumbering is safe to run twice", function()
        local layer = {
            { key = "F1", seq = 1, type = Constants.SPELL, value = 1,
                conditions = { combat = true } },
            -- 조건이 하나 더 있는 이유는 위 renumber 테스트와 같다.
            { key = "F1", seq = 2, type = Constants.SPELL, value = 2,
                conditions = { combat = true, units = { unitframe = { exists = true } } } },
        };
        MigrateLayer(layer, 6);
        MigrateLayer(layer, 6);
        check(layer[2].seq == 1 and layer[1].seq == 2, "두 번째에 뭉개짐: "
            .. tostring(layer[2].seq) .. "," .. tostring(layer[1].seq));
    end);

    ---------------------------------------------------------------------------
    -- dbver 5의 핵심 불변식: **표현만 바꾸고 뜻은 안 바꾼다**
    --
    -- 마이그레이션은 한 번 돌면 되돌릴 수 없고, 틀려도 화면에 아무 표시가 없다.
    --
    -- **전후를 맞대지 않는다.** 옛 값과 새 값을 각각 같은 함수에 통과시켜 결과가 같은지만 보면
    -- 판정자가 검사 대상과 같은 함수다. 그러면 `UnitConditionForBinding`이 두 값을 **같은
    -- 방향으로** 잘못 읽는 버그는 양쪽이 나란히 틀린 채 초록으로 지나간다. 그래서 여기 적는
    -- 것은 "이 값의 답은 이것이다"이고, 답을 정하는 것은 그 함수가 아니라 소비자 둘이다.
    --
    --   solver   `binding.unitStates[유닛]`. 유닛에 대해 solver가 읽는 것은 이것 하나다
    --   런타임   `binding.checkedUnits[유닛]`. 축마다 한 필드고, `UpdateBindings.lua`가
    --            `u.exists` / `u.reaction.<이름>` / `u.dead`로 그대로 옮겨 적는다.
    --            스니펫은 그 셋을 축마다 하나씩 비교한다 (`SecureBindings.lua`)
    ---------------------------------------------------------------------------

    local function copy(value)
        if (type(value) ~= "table") then
            return value;
        end
        local out = {};
        for k, v in pairs(value) do
            out[k] = v;
        end
        return out;
    end

    local function bindingFor(action)
        return DebindPrivate.GetBindingInfoForAction(action);
    end

    local function stateFor(action)
        return bindingFor(action).unitStates;
    end

    --- 축별 조건이 기대한 것과 같은가.
    ---
    --- `nil`은 "조건이 아예 안 실렸다"(꺼진 조건), `false`는 "없을 때"다. 둘은 다른 답이고
    --- 둘 다 방출부가 다르게 다룬다 - `nil`은 `t.units`에 키가 없는 것이고 `false`는
    --- `u.exists=false`다.
    local function sameCondition(got, want)
        if (want == nil or want == false) then
            return got == want;
        end
        return type(got) == "table" and got.reaction == want.reaction and got.dead == want.dead;
    end

    local function describe(value)
        if (type(value) ~= "table") then
            return tostring(value);
        end
        return ("{reaction=%s,dead=%s}"):format(tostring(value.reaction), tostring(value.dead));
    end

    --- One stored unit condition, and the answer both consumers see for it.
    ---
    --- The four old scalars are what the `dbver <= 1` step in `Migration.lua` carried across from
    --- `checkedUnitValue` unchanged, so values from that era are in here too. The table shapes are
    --- every one `dbver <= 4` produced and every one the menu writes now.
    local UNIT_CONDITION_CASES = {
        -- 옛 스칼라
        { "true", true, Constants.UNITSTATE_EXISTS, {} },
        { "false", false, Constants.UNITSTATE_NONE, false },
        { "\"help\"", "help", Constants.UNITSTATE_HELP, { reaction = Constants.REACTION_HELP } },
        { "\"harm\"", "harm", Constants.UNITSTATE_HARM, { reaction = Constants.REACTION_HARM } },

        -- 축별 표
        { "{}", {}, Constants.UNITSTATE_EXISTS, {} },
        { "{exists=false}", { exists = false }, Constants.UNITSTATE_NONE, false },
        -- 끈 조건. 기억한 축을 들고 있어도 바인딩에는 안 실린다.
        { "{disabled=true,reaction=HELP}", { disabled = true, reaction = Constants.REACTION_HELP },
            nil, nil },
        -- `dbver <= 6` 앞의 이름(`off`)은 여기 없다. 그 단계가 프로필과 페이로드 양쪽에서
        -- 이름을 올리므로 저장을 읽는 자리에는 `disabled`만 도착하고, 읽는 자리 둘 중 하나만
        -- 옛 이름을 알면 같은 표가 두 가지로 읽힌다. 사다리가 그 이름을 지우는 것은 위쪽
        -- `dbver <= 6` 케이스들이 잡는다.
        -- "없을 때"도 축을 기억한다. 기억은 메뉴 것이고 판정에는 안 따라온다.
        { "{exists=false,reaction=HELP}", { exists = false, reaction = Constants.REACTION_HELP },
            Constants.UNITSTATE_NONE, false },

        { "{reaction=HELP}", { reaction = Constants.REACTION_HELP },
            Constants.UNITSTATE_HELP, { reaction = Constants.REACTION_HELP } },
        { "{reaction=HARM}", { reaction = Constants.REACTION_HARM },
            Constants.UNITSTATE_HARM, { reaction = Constants.REACTION_HARM } },
        { "{reaction=OTHER}", { reaction = Constants.REACTION_OTHER },
            Constants.UNITSTATE_OTHER, { reaction = Constants.REACTION_OTHER } },
        { "{reaction=HELP+OTHER}",
            { reaction = Constants.REACTION_HELP + Constants.REACTION_OTHER },
            Constants.UNITSTATE_HELP + Constants.UNITSTATE_OTHER,
            { reaction = Constants.REACTION_HELP + Constants.REACTION_OTHER } },
        -- 셋을 다 고른 것은 "존재"와 같은 집합이다. 마스크는 접히고 저장은 안 접힌다.
        { "{reaction=ALL}", { reaction = Constants.REACTION_ALL },
            Constants.UNITSTATE_EXISTS, { reaction = Constants.REACTION_ALL } },
        -- `REACTION_NONE`은 런타임이 "호버 안 함"을 표시하는 값이라 `REACTION_ALL` **밖**의
        -- 비트다. 메뉴는 그것을 내주지 않으므로 저장에 있으면 손으로 넣었거나 가져온 것이고,
        -- 어느 반응에도 안 걸리는 것이 맞는 답이다. 마스크 0은 이슈로 잡혀 화면에 뜬다.
        { "{reaction=NONE}", { reaction = Constants.REACTION_NONE },
            0, { reaction = Constants.REACTION_NONE } },

        { "{dead=false}", { dead = false }, Constants.UNITSTATE_ALIVE, { dead = false } },
        { "{dead=true}", { dead = true }, Constants.UNITSTATE_DEAD, { dead = true } },
        { "{reaction=HELP,dead=false}", { reaction = Constants.REACTION_HELP, dead = false },
            Constants.UNITSTATE_HELP_ALIVE,
            { reaction = Constants.REACTION_HELP, dead = false } },
    };

    local function checkUnitConditionCase(case, action, when)
        local label, _, wantMask, wantCond = case[1], case[2], case[3], case[4];
        local binding = bindingFor(action);
        local gotMask = binding.unitStates and binding.unitStates.target;
        local gotCond = binding.conditions.units and binding.conditions.units.target;

        check(gotMask == wantMask, ("%s %s: 마스크가 %s여야 하는데 %s"):format(
            label, when, tostring(wantMask), tostring(gotMask)));
        check(sameCondition(gotCond, wantCond), ("%s %s: 축별 조건이 %s여야 하는데 %s"):format(
            label, when, describe(wantCond), describe(gotCond)));
    end

    test("a stored unit condition means one fixed thing to both consumers", function()
        for _, case in ipairs(UNIT_CONDITION_CASES) do
            checkUnitConditionCase(case, { type = Constants.SPELL, value = 100,
                checkedUnits = { target = copy(case[2]) } }, "(마이그레이션 전)");
        end
    end);

    -- 같은 표를 마이그레이션 뒤에도 그대로 요구한다. 옛 스칼라는 여기서 표가 되고, 이미 표인
    -- 것은 안 건드려져야 한다. **답을 두 번 계산해 맞대는 것이 아니라 같은 리터럴에 두 번
    -- 맞추는 것**이라, 두 경로가 같은 방향으로 틀리면 두 쪽 다 빨개진다.
    test("dbver 5 leaves that meaning exactly where it was", function()
        for _, case in ipairs(UNIT_CONDITION_CASES) do
            local layer = { { key = "A", type = Constants.SPELL, value = 100,
                checkedUnits = { target = copy(case[2]) } } };
            MigrateLayer(layer, 4);
            checkUnitConditionCase(case, layer[1], "(마이그레이션 후)");
        end
    end);

    ---------------------------------------------------------------------------
    -- 같은 단계가 hover 조건도 옮긴다
    --
    -- `hover`/`reactions`는 **릴리스된 프로필에 실제로 들어 있는** 값이라, 여기가 틀리면
    -- 사용자가 걸어둔 호버 조건이 조용히 사라지거나 넓어진다. 위와 같이 리터럴로 못 박는다.
    --
    -- **`reactions`는 비트마스크라 정의역이 코드로 정해진다.** 실데이터를 안 봐도 여기서 다
    -- 셀 수 있고, 아래가 그 전부다.
    --
    --   필드가 없음                         제약 안 함
    --   `HELP`/`HARM`/`OTHER`의 부분집합     여덟 가지. 셋을 다 고른 것이 `REACTION_ALL`이고
    --                                       빈 것이 `0`인데, `0`은 메뉴가 못 만들고 교집합이
    --                                       비었을 때만 나오므로 아래 교집합 칸에 있다
    --   `REACTION_NONE`                      `REACTION_ALL` **밖**의 비트라 어느 반응에도
    --                                       안 걸린다. `Constants.lua`
    ---------------------------------------------------------------------------

    local HELP, HARM, OTHER = Constants.REACTION_HELP, Constants.REACTION_HARM,
        Constants.REACTION_OTHER;

    --- `{ hover, reactions, 그 유닛에 이미 있던 조건, 기대 마스크, 기대 축별 조건 }`
    ---
    --- 셋째 자리의 `existing`은 두 메뉴가 다 살아 있던 시절의 프로필이다. 덮으면 걸어둔 것보다
    --- 넓어지므로 교집합하고, 안 겹치면 어떤 유닛도 못 드는 조건(마스크 0)이 되어 이슈로 잡힌다.
    local HOVER_CASES = {
        -- 반응 정의역 전부. 셋을 다 고른 것(`REACTION_ALL`)은 "제약 안 함"으로 접힌다.
        { true, nil, nil, Constants.UNITSTATE_EXISTS, {} },
        { true, HELP, nil, Constants.UNITSTATE_HELP, { reaction = HELP } },
        { true, HARM, nil, Constants.UNITSTATE_HARM, { reaction = HARM } },
        { true, OTHER, nil, Constants.UNITSTATE_OTHER, { reaction = OTHER } },
        { true, HELP + HARM, nil, Constants.UNITSTATE_HELP + Constants.UNITSTATE_HARM,
            { reaction = HELP + HARM } },
        { true, HELP + OTHER, nil, Constants.UNITSTATE_HELP + Constants.UNITSTATE_OTHER,
            { reaction = HELP + OTHER } },
        { true, HARM + OTHER, nil, Constants.UNITSTATE_HARM + Constants.UNITSTATE_OTHER,
            { reaction = HARM + OTHER } },
        { true, Constants.REACTION_ALL, nil, Constants.UNITSTATE_EXISTS, {} },
        -- `REACTION_ALL` 밖의 비트. 위 표의 `{reaction=NONE}`과 같은 답이어야 한다.
        { true, Constants.REACTION_NONE, nil, 0, { reaction = Constants.REACTION_NONE } },

        -- "호버 안 할 때". 반응은 hover가 참일 때만 뜻이 있으므로 답을 안 바꾼다.
        { false, nil, nil, Constants.UNITSTATE_NONE, false },
        { false, HELP, nil, Constants.UNITSTATE_NONE, false },
        { false, Constants.REACTION_ALL, nil, Constants.UNITSTATE_NONE, false },

        -- 이미 있던 조건과의 교집합.
        { true, HARM + OTHER, { reaction = HELP + OTHER }, Constants.UNITSTATE_OTHER,
            { reaction = OTHER } },
        { true, HARM, { reaction = HELP }, 0, { reaction = 0 } },
        { true, HELP, { dead = false }, Constants.UNITSTATE_HELP_ALIVE,
            { reaction = HELP, dead = false } },
        -- 생사는 반응 축이 아니므로 반응만 걸린 hover와 겹칠 것이 없다. 그대로 남아야 한다.
        { true, nil, { dead = true }, Constants.UNITSTATE_DEAD, { dead = true } },
        -- 한쪽이 "없을 때"면 겹치는 유닛 상태가 없다. 둘 다 "없을 때"면 같은 말이라 살아남는다.
        { true, HELP, false, 0, { reaction = 0 } },
        { false, nil, {}, 0, { reaction = 0 } },
        { false, nil, false, Constants.UNITSTATE_NONE, false },
    };

    --- **A bare [when one is pointed at] is not a condition after the ladder.** The `dbver` 7 step
    --- writes it as Casting instead -- Hover Cast on Unit Frames with Normal Cast off, which is what
    --- that condition meant (`which-action-a-key-runs.md` §8) -- and takes the row out. So
    --- the same case reads one way before the ladder and another after it, and `migrated` says which
    --- side is being asked.
    local function checkHoverCase(case, action, when, migrated)
        local hover, reactions, existing = case[1], case[2], case[3];
        local wantMask, wantCond = case[4], case[5];
        local label = ("hover=%s reactions=%s existing=%s"):format(
            tostring(hover), tostring(reactions), describe(existing));

        if (migrated and type(wantCond) == "table" and next(wantCond) == nil) then
            local casting = action.casting;
            check(casting and casting.hoverCastMode == "unitframe",
                ("%s %s: Hover Cast가 %s다"):format(label, when,
                    tostring(casting and casting.hoverCastMode)));
            check(casting.normalCast == false,
                ("%s %s: Normal Cast가 %s다"):format(label, when, tostring(casting.normalCast)));
            wantMask, wantCond = nil, nil;
        end

        local binding = bindingFor(action);
        local gotMask = binding.unitStates and binding.unitStates.unitframe;
        local gotCond = binding.conditions.units and binding.conditions.units.unitframe;

        check(gotMask == wantMask, ("%s %s: 마스크가 %s여야 하는데 %s"):format(
            label, when, tostring(wantMask), tostring(gotMask)));
        check(sameCondition(gotCond, wantCond), ("%s %s: 축별 조건이 %s여야 하는데 %s"):format(
            label, when, describe(wantCond), describe(gotCond)));
    end

    local function hoverAction(case)
        local action = { key = "A", type = Constants.SPELL, value = 100,
            hover = case[1], reactions = case[2] };
        if (case[3] ~= nil) then
            action.checkedUnits = { hover = copy(case[3]) };
        end
        return action;
    end

    test("the old hover pair means one fixed thing to both consumers", function()
        for _, case in ipairs(HOVER_CASES) do
            checkHoverCase(case, hoverAction(case), "(마이그레이션 전)");
        end
    end);

    test("dbver 5 leaves the hover condition's meaning exactly where it was", function()
        for _, case in ipairs(HOVER_CASES) do
            local layer = { hoverAction(case) };
            MigrateLayer(layer, 4);
            checkHoverCase(case, layer[1], "(마이그레이션 후)", true);
        end
    end);

    test("dbver 5 moves the hover condition onto the unit it names", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP } };
        MigrateLayer(layer, 4);

        check(layer[1].hover == nil, "옛 hover 필드가 남음");
        check(layer[1].reactions == nil, "옛 reactions 필드가 남음");
        check(layer[1].conditions.units.unitframe.reaction == Constants.REACTION_HELP,
            "반응이 유닛 조건으로 안 옮겨감");
    end);

    test("dbver 5 is safe to run twice over a folded hover condition", function()
        for _, case in ipairs(HOVER_CASES) do
            local layer = { hoverAction(case) };
            MigrateLayer(layer, 4);
            MigrateLayer(layer, 4);
            checkHoverCase(case, layer[1], "(두 번 돌린 뒤)", true);
        end
    end);

    -- 모르는 값이 섞여 있어도 **뜻이 뒤집히면 안 된다.** 옛 버전이 쓴 값을 우리가 모를 수
    -- 있고, 그때 조용히 "없을 때"로 읽히면 걸려 있던 바인딩이 정반대로 동작한다.
    test("dbver 5 does not change what an unknown value means", function()
        local before = stateFor({
            type = Constants.SPELL, value = 100,
            checkedUnits = { target = "somethingWeNeverWrote" },
        });

        local layer = { { key = "A", type = Constants.SPELL, value = 100,
            checkedUnits = { target = "somethingWeNeverWrote" } } };
        MigrateLayer(layer, 4);
        local after = stateFor(layer[1]);

        check(before.target == after.target, "모르는 값의 뜻이 마이그레이션으로 바뀜");
    end);

    ---------------------------------------------------------------------------
    -- dbver 6: 조건이 `conditions` 안으로 내려간다
    --
    -- 저장 필드 서른 개 중 열여덟이 조건이었고 `unit`이 그 사이에 섞여 앉아 있었다.
    -- `unit`은 겨누는 대상이고 조건은 언제 발동하느냐라, 이름만 보면 한 식구인데 성격이
    -- 정반대다.
    --
    -- **여기서 조건 목록을 따로 적지 않는다.** `Constants.IsConditionField`가 유일한 답이고,
    -- 스펙이 자기 목록을 들면 그 표가 갈리는 날 스펙만 초록으로 남는다.
    ---------------------------------------------------------------------------

    test("dbver 6 moves every condition into conditions", function()
        local layer = { {
            key = "A", type = Constants.SPELL, value = 100, unit = "target", priority = 2,
            combat = true, groups = 3, checkedUnits = { target = {} }, ["$state2"] = false,
        } };
        MigrateLayer(layer, 5);
        local action = layer[1];

        check(action.conditions ~= nil, "조건 표가 안 생김");
        check(action.conditions.combat == true, "combat이 안 옮겨짐");
        check(action.conditions.groups == 3, "groups가 안 옮겨짐");
        check(action.conditions["$state2"] == false, "커스텀 상태가 안 옮겨짐 - false는 nil이 아니다");
        check(type(action.conditions.units) == "table", "유닛 조건이 안 옮겨짐");

        check(action.combat == nil and action.groups == nil and action.checkedUnits == nil
            and action["$state2"] == nil, "최상단에 조건이 남음");
        -- 조건이 아닌 것은 그대로 있어야 한다. 겨누는 대상까지 같이 내려가면 매크로가
        -- 겨눌 곳을 잃는다.
        check(action.unit == "target" and action.priority == 2 and action.value == 100,
            "조건이 아닌 필드가 같이 내려갔다");
    end);

    test("dbver 6 leaves an action with no conditions without a table", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 100 } };
        MigrateLayer(layer, 5);
        -- 빈 표는 조건이 하나도 없는 액션을 조건부로 만든다(`IsConditionalBinding`), 그리고
        -- 조건부는 발동 순서에서 무조건보다 앞이다.
        check(layer[1].conditions == nil, "없던 표가 생김");
    end);

    test("dbver 6 is safe to run twice", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 100, combat = true } };
        MigrateLayer(layer, 5);
        MigrateLayer(layer, 5);
        check(layer[1].conditions.combat == true, "두 번째에 뭉개짐");
    end);

    test("dbver 6 runs after the unit-mask step, not before it", function()
        -- 순서가 뒤집히면 `<= 4`가 평면 `checkedUnits`를 찾다가 못 찾고, 옛 스칼라가 표로
        -- 안 올라간 채 조건 표 안에 눌러앉는다. 그 뒤로는 다시 돌 기회가 없다.
        local layer = { { key = "A", type = Constants.SPELL, value = 100,
            checkedUnits = { target = "help" } } };
        MigrateLayer(layer, 4);
        local cond = layer[1].conditions.units.target;
        check(type(cond) == "table" and cond.reaction == Constants.REACTION_HELP,
            "옛 스칼라가 축별 표로 안 올라왔다");
    end);

    ---------------------------------------------------------------------------
    -- dbver 6: SETSTATE가 타입 셋과 이름으로 갈린다
    --
    -- 저장은 `mode | index` 비트팩 하나였다. 모드가 `type`으로 올라가고 대상이 이름이 된다
    -- (`redesigning-custom-states.md` §9-1).
    --
    -- **틀리면 조용하다.** 모드를 잘못 읽으면 켜는 키가 끄는 키가 되고, 이름을 잘못 읽으면
    -- 남의 스위치를 켠다. 둘 다 화면에는 멀쩡한 줄로 그려진다.
    ---------------------------------------------------------------------------

    --- 옛 모드 비트. 단계와 마찬가지로 스펙도 자기 리터럴을 든다 - `Constants`에는 이제
    --- 이 숫자들이 없고, 있으면 안 된다.
    local OLD_SETSTATE_FLAGS = { on = 0x100, off = 0x200, toggle = 0x400 };

    test("dbver 6 splits the SETSTATE bitpack into three types", function()
        for mode, flag in pairs(OLD_SETSTATE_FLAGS) do
            local layer = { { key = "A", type = "setstate", value = flag + 3, seq = 1 } };
            MigrateLayer(layer, 5);
            local action = layer[1];
            check(Constants.SETSWITCH_MODES[action.type] == mode,
                mode .. " -> " .. tostring(action.type));
            check(action.value == "$state3", "이름 " .. tostring(action.value));
        end
    end);

    -- 다섯 슬롯이 전부 자기 이름으로 나와야 한다. 한 칸 밀리면 그 키는 옆 스위치를 켠다.
    test("dbver 6 maps every switch index to its own name", function()
        for index = 1, #Constants.SWITCH_NAMES do
            local layer = { { key = "A", type = "setstate", value = 0x400 + index } };
            MigrateLayer(layer, 5);
            check(layer[1].value == "$state" .. index,
                index .. " -> " .. tostring(layer[1].value));
        end
    end);

    -- 세 값 중 어느 것도 아닌 비트팩은 무엇을 하려던 액션인지 말해주지 않는다. 아무 타입이나
    -- 골라주면 켜기가 끄기가 되므로 옛 타입인 채로 남기고, 그 타입은 어디서도 안 걸린다.
    test("dbver 6 leaves a mode it cannot read alone", function()
        local layer = { { key = "A", type = "setstate", value = 0x800 + 3 } };
        MigrateLayer(layer, 5);
        check(layer[1].type == "setstate", "타입 " .. tostring(layer[1].type));
        check(layer[1].value == 0x800 + 3, "값이 바뀌었다: " .. tostring(layer[1].value));
    end);

    -- 이미 갈린 액션 위에서 다시 돌면 이름을 숫자로 읽으려 든다. 타입으로 걸러지는 것이
    -- 그것을 막고, **페이로드 쪽이 바로 그 성질 위에 선다** - v1 어댑터가 서브테이블을 곧장
    -- 새 타입으로 펴서 이 단계에 넘긴다(`Export.lua`).
    test("dbver 6 is safe to run twice over a split SETSTATE", function()
        local layer = { { key = "A", type = "setstate", value = 0x400 + 2 } };
        MigrateLayer(layer, 5);
        MigrateLayer(layer, 5);
        check(layer[1].type == Constants.SETSWITCH_TOGGLE, "타입 " .. tostring(layer[1].type));
        check(layer[1].value == "$state2", "이름 " .. tostring(layer[1].value));
    end);

    ---------------------------------------------------------------------------
    -- dbver 6: the import badge becomes a key and an arrival number
    --
    -- 3.2 stored a waiting set as a synthetic number in `key` plus `imported`, which held the
    -- sender's real key. The synthetic key is gone: `key` is the sender's own and `arrivalID` is
    -- what holds the set back (`building-export-import.md` 12절).
    --
    -- **Both ways of getting this wrong are silent, and one of them fires keys.** Drop the badge
    -- and a set the reader never agreed to reaches every key it was sent on. Leave the synthetic
    -- number in `key` and those rows stand under a heading nobody can press, for good.
    ---------------------------------------------------------------------------

    test("dbver 6 gives an arrival back the key it was sent on", function()
        local layer = { { type = Constants.SPELL, value = 1, key = 12345, seq = 1,
            imported = "F1" } };
        MigrateLayer(layer, 5);
        local action = layer[1];
        check(action.key == "F1", "키 " .. tostring(action.key));
        check(action.arrivalID == 1, "배지 " .. tostring(action.arrivalID));
        check(action.imported == nil, "옛 배지가 남음");
    end);

    -- `imported = true` was a set that arrived on no key at all. There is nothing to give back, and
    -- the synthetic number was never one the reader could press -- so the key goes, and the number
    -- inside the group goes with it (`PlaceInKeyGroup`의 규칙: 키가 없으면 번호도 없다).
    test("dbver 6 takes the synthetic key off a set that arrived without one", function()
        local layer = { { type = Constants.SPELL, value = 1, key = 12345, seq = 2,
            imported = true } };
        MigrateLayer(layer, 5);
        local action = layer[1];
        check(action.key == nil, "키 " .. tostring(action.key));
        check(action.seq == nil, "키 없는 액션이 번호를 들고 있다");
        check(action.arrivalID == 1, "배지 " .. tostring(action.arrivalID));
    end);

    -- A number in `key` with no badge beside it is a set the user unbound by hand. Nobody can name
    -- that number, so leaving it would stand those rows up as a group of their own forever.
    test("dbver 6 drops a numbered key that carries no badge", function()
        local layer = { { type = Constants.SPELL, value = 1, key = 999, seq = 3 } };
        MigrateLayer(layer, 5);
        local action = layer[1];
        check(action.key == nil and action.seq == nil, "숫자 키가 남음");
        check(action.arrivalID == nil, "배지가 없는데 도착 번호가 붙었다");
    end);

    test("dbver 6 is safe to run twice over a raised badge", function()
        local layer = { { type = Constants.SPELL, value = 1, key = 12345, seq = 1,
            imported = "F1" } };
        MigrateLayer(layer, 5);
        MigrateLayer(layer, 5);
        check(layer[1].key == "F1", "키 " .. tostring(layer[1].key));
        check(layer[1].arrivalID == 1, "배지 " .. tostring(layer[1].arrivalID));
    end);

    -- **The counter is `MigrateDB`'s, not the layer ladder's**, and that split is what this pins.
    -- Every badge the ladder meets is stamped arrival 1, so the next number handed out has to be 2;
    -- hand out 1 again and the new arrival merges into the migrated one, since a group is
    -- `(key, arrivalID)`. Accepting one would then accept both.
    test("dbver 6 stands the arrival counter above the badges it stamped", function()
        _G.DebindVars = {
            dbver = 5,
            migrated = {},
            shared = {
                GENERAL = { { type = Constants.SPELL, value = 1, key = 777, seq = 1,
                    imported = "F1" } },
                classes = {},
            },
            characters = {},
            -- What the counter was called when it counted keys instead of arrivals.
            nextSyntheticKey = 778,
        };
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        DebindPrivate.InitDB();

        local db = _G.DebindVars;
        check(db.layers.account.GENERAL[0][1].arrivalID == 1, "배지가 안 올라감 - 전제가 깨졌다");
        check(db.nextArrivalID == 2, "다음 도착 번호 " .. tostring(db.nextArrivalID));
        check(DebindPrivate.NextArrivalID() == 2, "새 도착분이 마이그레이션된 것과 같은 번호를 받는다");
        check(db.nextSyntheticKey == nil, "아무도 안 읽는 옛 카운터가 남음");
    end);

    ---------------------------------------------------------------------------
    -- 옛 자리를 읽으면 소리가 난다
    --
    -- 조건이 `conditions`로 내려간 뒤, 옛 자리를 읽는 코드는 에러가 아니라 `nil`을 받는다.
    -- `nil`은 "조건 없음"과 생김새가 같아서 바인딩이 넓어지고, 넓어진 바인딩은 남의 키를
    -- 가져간다. 화면에도 로그에도 아무것도 안 남는다.
    --
    -- **이름으로 훑어서는 다 못 찾는다.** `action.combat`은 grep에 걸리지만 `action[field]`
    -- 처럼 변수로 도는 자리는 안 걸리고, 조건이 열여덟 개라 그렇게 도는 코드가 오히려 흔하다.
    -- 실제로 그렇게 놓친 자리가 셋 나왔다.
    ---------------------------------------------------------------------------

    test("프로필에 든 액션의 옛 조건 자리를 읽으면 터진다", function()
        if (not Constants.DEBUG) then
            return;
        end
        FreshInit();
        local action = { type = Constants.SPELL, value = 100, key = "F", seq = 1,
            conditions = { combat = true } };
        DebindPrivate.GetProfileLayer(1):Insert(action);
        DebindPrivate.CleanUpDB();

        check(action.conditions.combat == true, "전제가 깨졌다 - 조건이 제자리에 없다");
        check(pcall(function() return action.combat end) == false,
            "최상단에서 읽었는데 조용히 nil이 나온다");
        -- 조건이 아닌 이름은 그대로 nil이어야 한다. 함정이 넓으면 멀쩡한 코드가 터진다.
        check(pcall(function() return action.somethingElse end) == true,
            "조건이 아닌 이름까지 터진다");
    end);

    ---------------------------------------------------------------------------
    -- 한 판도 빠지지 않는가
    --
    -- 액션이 사는 곳은 셋이다(공유 GENERAL, 공유 클래스/특성, 캐릭터별). 한 곳이라도
    -- 빠지면 그 프로필은 옛 형식으로 남는데, `dbver`는 이미 올라가 있어서 **다시는 안 돈다.**
    ---------------------------------------------------------------------------

    test("raising the db reaches every place actions live", function()
        _G.DebindVars = {
            dbver = 4,
            migrated = {},
            shared = {
                GENERAL = { { key = "A", type = 1, value = 1, checkedUnits = { target = "help" } } },
                classes = {
                    DRUID = {
                        [0] = { { key = "B", type = 1, value = 1, checkedUnits = { focus = "harm" } } },
                        [2] = { { key = "C", type = 1, value = 1, checkedUnits = { tank = true } } },
                    },
                },
            },
            characters = {
                [GUID] = {
                    class = "DRUID",
                    layers = {
                        [0] = { { key = "D", type = 1, value = 1, checkedUnits = { mouseover = "help" } } },
                    },
                },
            },
        };
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        DebindPrivate.InitDB();

        local db = _G.DebindVars;
        check(type(db.layers.account.GENERAL[0][1].conditions.units.target) == "table",
            "공유 GENERAL이 안 올라감");
        check(type(db.layers.account.DRUID[0][1].conditions.units.focus) == "table",
            "공유 클래스 레이어가 안 올라감");
        check(type(db.layers.account.DRUID[2][1].conditions.units.tank) == "table",
            "특성이 0이 아닌 레이어가 안 올라감");
        check(type(db.layers[GUID].DRUID[0][1].conditions.units.mouseover) == "table",
            "캐릭터별 레이어가 안 올라감");
        check(db.dbver == Constants.DB_VERSION, "dbver가 안 올라감");
    end);

    ---------------------------------------------------------------------------
    -- 두 판 밀린 프로필
    --
    -- 단계는 `<= N`으로 열리므로 한 번의 호출이 여러 단계를 연달아 밟는다. dbver 1의
    -- 결과물(`checkedUnits`)을 dbver 5 단계가 받아야 한다 - 이 연결이 끊기면 옛 프로필만
    -- 조용히 옛 형식으로 남는다.
    ---------------------------------------------------------------------------

    test("a dbver 1 profile lands in the new shape in one pass", function()
        local layer = { {
            key = "A", type = 1, value = 1,
            unit = "focus",
            checkedUnit = true,
            checkedUnitValue = "help",
        } };
        MigrateLayer(layer, 1);

        local action = layer[1];
        check(action.checkedUnit == nil and action.checkedUnitValue == nil,
            "dbver 1 단계가 안 돎 - 전제가 깨졌다");
        check(type(action.conditions.units.focus) == "table"
            and action.conditions.units.focus.reaction == Constants.REACTION_HELP,
            "dbver 1이 만든 값을 dbver 5 단계가 못 받음");
        check(action.seq == 1, "dbver 2 단계가 건너뛰어짐");
    end);

    test("raising from any version twice changes nothing the second time", function()
        for _, from in ipairs({ 1, 2, 3, 4 }) do
            local layer = { {
                key = "A", type = 1, value = 1, unit = "focus",
                checkedUnits = { target = "help", tank = false, ["@"] = true },
            } };
            MigrateLayer(layer, from);
            local once = {
                target = layer[1].conditions.units.target.reaction,
                tank = layer[1].conditions.units.tank,
                at = layer[1].conditions.units["@"].reaction,
                seq = layer[1].seq,
            };

            MigrateLayer(layer, from);
            check(layer[1].conditions.units.target.reaction == once.target
                and layer[1].conditions.units.tank == once.tank
                and layer[1].conditions.units["@"].reaction == once.at
                and layer[1].seq == once.seq,
                ("dbver %d에서 두 번째 실행이 값을 바꿈"):format(from));
        end
    end);

    ---------------------------------------------------------------------------
    -- 옛 파일을 건드리지 않는가
    --
    -- 가져오기는 옛 SavedVariables 위에서 도는 것이 아니라 복사본 위에서 돌아야 한다.
    -- `dbver 5` 단계는 **`checkedUnits` 테이블을 제자리에서 고치므로**, 복사가 얕았다면
    -- 옛 파일의 조건까지 같이 바뀐다 - 롤백하면 그 조건이 이미 새 형식이라 안 읽힌다.
    ---------------------------------------------------------------------------

    test("raising an import does not rewrite the old file's unit conditions", function()
        FreshInit();
        local old = LegacyAccount();
        old.GENERAL[1].checkedUnits = { target = "help" };
        _G.DebounceVars = old;

        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.layers.account.GENERAL[0][1].conditions.units.target.reaction
            == Constants.REACTION_HELP, "가져온 쪽이 안 올라감 - 전제가 깨졌다");
        check(old.GENERAL[1].checkedUnits.target == "help",
            "옛 파일의 조건이 새 형식으로 덮어써짐 - 롤백이 깨진다");
    end);

    ---------------------------------------------------------------------------
    -- The import badge has to survive `CleanUpDB`
    --
    -- `CleanUpDB` strips every field that is not in `KEYS_TO_SAVE`, and it runs on the way out.
    -- The badge is what keeps an imported action out of the binding build, so **if it were not on
    -- that list, quarantine would lift itself on the next login** - someone else's keys would
    -- quietly start firing, which is the worst direction this addon can fail in and the one thing
    -- the reader was promised would not happen.
    --
    -- Nothing else catches it. Registration is one word in a list of twenty-five, the action still
    -- saves, and the symptom only shows up a relog later on a machine that imported something.
    ---------------------------------------------------------------------------

    test("가져오기 배지는 정리를 견딘다", function()
        FreshInit();
        local layer = DebindPrivate.GetProfileLayer(1);
        local action = { type = Constants.SPELL, value = 774, key = "F", seq = 1, arrivalID = 7 };
        layer:Insert(action);

        -- **키를 아직 안 정한 그룹의 키도 견뎌야 한다.** 숫자라는 것만 다를 뿐 키이고, 지워지면
        -- 그 묶음이 흩어진 채로 지정 안 된 더미에 떨어진다.
        local pending = { type = Constants.SPELL, value = 775, key = 3, seq = 1, arrivalID = 7 };
        layer:Insert(pending);

        DebindPrivate.CleanUpDB();

        check(action.arrivalID == 7, "배치 번호가 지워졌다 - 다음 접속에 격리가 저절로 풀린다");
        check(pending.key == 3, "숫자 키가 지워졌다 - 온 묶음이 흩어진다");
        check(pending.seq == 1, "숫자 키 그룹의 번호가 지워졌다");
    end);

    -- The other half: the whitelist really does strip, so the test above is not passing because
    -- `CleanUpDB` leaves everything alone.
    test("등록 안 된 필드는 정리가 걷어낸다", function()
        FreshInit();
        local layer = DebindPrivate.GetProfileLayer(1);
        local action = { type = Constants.SPELL, value = 774, key = "F", seq = 1,
            importedTypo = true };
        layer:Insert(action);

        DebindPrivate.CleanUpDB();

        check(action.importedTypo == nil, "정리가 아무것도 안 걷어낸다 - 위 검사가 무의미해진다");
    end);

    ---------------------------------------------------------------------------
    -- 되돌린 빌드는 자기보다 새 프로필을 안 건드린다
    --
    -- `MigrateDB`가 "이미 최신"과 "미래에서 왔다"를 한 `return`에 묶고 있어서, 되돌린 빌드가
    -- 그냥 지나쳐 `CleanUpDB`까지 갔다. 거기가 이 빌드의 `KEYS_TO_SAVE`에 없는 액션 필드를
    -- 전부 지우고, 내용을 못 알아본 캐릭터 항목을 통째로 뗀다. `db.dbver`는 높은 채로 남아
    -- 마이그레이션이 다시 돌 근거가 없어진다. **조용하고 되돌릴 수 없다.**
    --
    -- 게임에서 재현하려면 애드온을 실제로 내려야 하고, 한 번 밟으면 그 프로필이 없어진 뒤다.
    -- 그래서 여기 박아둔다. `guarding-against-a-downgrade.md`.
    ---------------------------------------------------------------------------

    --- 이 빌드보다 한 판 위의 프로필. 액션에도 캐릭터 항목에도 **이 빌드가 모르는 이름**이
    --- 하나씩 들어 있다. 그 둘이 지워지는 것이 이 버그다.
    local function NewerProfile()
        return {
            dbver = Constants.DB_VERSION + 1,
            shared = {
                GENERAL = { { type = "spell", value = 1, key = "F1", seq = 1,
                    somethingAddedLater = { "kept" } } },
                classes = {},
            },
            -- **비어 보이지만 안 비었다.** `HasCharContent`는 자기가 아는 것만 세므로, 새 판이
            -- 새 이름으로 담은 내용은 안 보이고 항목이 통째로 떨어져 나간다.
            characters = {
                [GUID] = { name = "Tester", layers = {}, somethingAddedLater = { "kept" } },
            },
            migrated = {},
        };
    end

    local function NewerInit()
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        _G.DebindVars = NewerProfile();
        DebindPrivate.InitDB();
    end

    test("새 프로필을 만나면 물러선다", function()
        NewerInit();
        check(DebindPrivate.profileIsNewer == true, "물러서지 않았다");
    end);

    test("새 프로필은 들어온 그대로 남는다", function()
        NewerInit();

        local db = _G.DebindVars;
        check(db.dbver == Constants.DB_VERSION + 1,
            "dbver가 내려앉았다. 다시 올라가도 마이그레이션이 돌 근거가 없어진다");
        check(db.shared.GENERAL[1].somethingAddedLater ~= nil,
            "이 빌드가 모르는 액션 필드가 지워졌다");
        check(db.characters[GUID] ~= nil,
            "캐릭터 항목이 통째로 떨어졌다");
    end);

    -- 로그아웃 경로. 이벤트를 안 걸어서 게임에서는 안 불리지만, **불려도 그 표에 못 닿는
    -- 것**이 물러선다는 말의 내용이다. 물러설 때 쥐여준 빈 프로필은 떨어져 있어서
    -- `LayerArray`도 `db.global`도 `_G.DebindVars`가 아니다.
    test("물러선 뒤에는 정리가 돌아도 새 프로필에 안 닿는다", function()
        NewerInit();
        DebindPrivate.CleanUpDB();

        local db = _G.DebindVars;
        check(db.shared.GENERAL[1].somethingAddedLater ~= nil,
            "정리가 새 프로필의 액션 필드를 걷어냈다");
        check(db.characters[GUID] ~= nil, "정리가 캐릭터 항목을 뗐다");
    end);

    ---------------------------------------------------------------------------
    -- 리셋은 새 설치가 아니다
    --
    -- `/deb reset confirm`이 빈 표를 놓고 리로드하는데, **빈 표는 첫 로그인이 시작하는 바로 그
    -- 자리다.** `legacyNeeded`가 안 서 있으면 다음 로그인이 개명 전 `DebounceVars`를 보고
    -- 통째로 인수한다. 되돌릴 수 없다는 말을 읽고 친 사람이 바인딩으로 가득 찬 화면을 다시
    -- 만나고, 그게 어디서 왔는지 알 방법이 없다. 실제로 밟았다.
    ---------------------------------------------------------------------------

    test("리셋한 계정은 옛 파일을 다시 안 가져온다", function()
        _G.DebindVars = NewerProfile();
        _G.DebounceVars = LegacyAccount();
        _G.DebounceVarsPerChar = LegacyChar();
        DebindPrivate.InitDB();

        -- 리로드는 여기서 할 수 없으므로 그 자리만 막아두고, 남는 표를 본다.
        local reloaded = false;
        local realReload = _G.ReloadUI;
        _G.ReloadUI = function() reloaded = true; end;
        local handled = DebindPrivate.HandleNewerProfileReset({ "reset", "confirm" });
        _G.ReloadUI = realReload;

        check(handled and reloaded, "confirm이 안 먹었다");
        check(_G.DebindVars.legacyNeeded == false,
            "리셋한 표가 개명 전 설정을 사절하지 않는다");

        -- 그 표로 다시 올라온 다음 로그인.
        DebindPrivate.InitDB();
        check(DebindPrivate.RunLegacyMigration() == false,
            "리셋 직후인데 옛 파일을 가져왔다");
        check(#DebindPrivate.db.global.layers.account.GENERAL[0] == 0,
            "리셋 직후인데 공유 레이어에 액션이 있다");
    end);

    -- 되돌아온 자리. 물러섰던 세션 다음에 정상 프로필로 들어오면 깃발이 서 있으면 안 된다.
    test("정상 프로필로 돌아오면 깃발이 내려간다", function()
        NewerInit();
        FreshInit();
        check(not DebindPrivate.profileIsNewer, "깃발이 선 채로 남았다");
    end);

    ---------------------------------------------------------------------------
    -- dbver 6: 스위치 정의의 저장 모양
    --
    -- **정의는 액션이 아니라 사다리가 따로 선다.** `MigrateLayer`가 걷는 것은 레이어의 액션
    -- 배열이고 정의는 그 근처에 없다 - `MigrateSwitches`가 계정 표의 꼭대기에서 따로 돈다.
    --
    -- 셋이 한 단계에 간다. 표 이름 `customStates` -> `switches`, `mode`의 숫자 -> 문자열,
    -- `initialValue` -> `resetValue`. 어느 하나를 놓쳐도 아무 소리가 안 난다: 새 이름 아래가
    -- 비어 있으면 다섯 개가 기본값으로 새로 깔리고 사용자가 해둔 설정이 통째로 없던 것이 된다.
    ---------------------------------------------------------------------------

    local MODES = Constants.SWITCH_MODES;

    --- `dbver` 5 그대로의 계정 표. `DevSeed.lua`의 `SEEDS[5]`가 심는 것과 같은 모양이고,
    --- **옛 숫자를 직접 든다** - `Constants.SWITCH_MODES`는 그 언어를 더 이상 모른다.
    ---
    --- 넷을 두는 이유는 되돌릴 값의 세 답이 서로 다른 답이라서다. `true`와 `false`는 로그인
    --- 때 켜고 끄는 것이고, 없는 것은 "기억한 값(`savedValue`)으로 가라"다.
    local function OldSwitchAccount()
        return {
            dbver = 5,
            shared = { classes = {} },
            characters = {},
            migrated = {},
            customStates = {
                [1] = { mode = 0, initialValue = true, displayMessage = true },
                [2] = { mode = 3, expr = "[combat]" },
                [3] = { mode = 0, initialValue = false },
                [4] = { mode = 0, savedValue = true },
            },
        };
    end

    local function InitWith(db)
        _G.DebounceVars = nil;
        _G.DebounceVarsPerChar = nil;
        _G.DebindVars = db;
        DebindPrivate.InitDB();
        return _G.DebindVars;
    end

    --- The definitions where the ladder leaves them, the root rows.
    local function Defs(db)
        return db.switches.account.GENERAL[0];
    end

    test("dbver 6 moves the switch definitions under their new name", function()
        local db = InitWith(OldSwitchAccount());
        check(db.customStates == nil,
            "옛 이름이 남았다 - 읽는 쪽이 없으니 로그아웃마다 죽은 표가 같이 저장된다");
        check(type(db.switches) == "table", "switches가 없다");
        check(Defs(db)["$state1"].resetValue == true, "정의가 안 따라왔다");
        check(Defs(db)["$state2"].expr == "[combat]", "계산식이 안 따라왔다");
    end);

    test("dbver 6 turns the mode numbers into names", function()
        local db = InitWith(OldSwitchAccount());
        check(Defs(db)["$state1"].mode == MODES.MANUAL,
            "수동이 " .. tostring(Defs(db)["$state1"].mode) .. "로 남았다");
        check(Defs(db)["$state2"].mode == MODES.EXPR,
            "계산식이 " .. tostring(Defs(db)["$state2"].mode) .. "로 남았다 - 숫자는 어느 쪽과도 안 맞는다");
    end);

    -- **`false`와 없는 것은 다른 답이다.** 뭉개면 "로그인 때 꺼짐"으로 해둔 스위치가 지난
    -- 세션의 값을 들고 올라온다.
    test("dbver 6 renames initialValue without flattening its three answers", function()
        local db = InitWith(OldSwitchAccount());
        check(Defs(db)["$state1"].initialValue == nil and Defs(db)["$state3"].initialValue == nil,
            "옛 필드가 남았다");
        check(Defs(db)["$state1"].resetValue == true, "true가 안 옮겨졌다");
        check(Defs(db)["$state3"].resetValue == false,
            "false가 " .. tostring(Defs(db)["$state3"].resetValue) .. "가 됐다");
        check(Defs(db)["$state4"].resetValue == nil, "없던 값이 생겼다");
    end);

    -- **What each name comes up as, not only the name.** The value is set by `BindDerivedTables`
    -- and not by storage, so if that cannot read the new name everything above is green and the
    -- switch still comes up wrong.
    test("dbver 6 keeps what each switch comes up as", function()
        InitWith(OldSwitchAccount());
        local Get = DebindPrivate.GetSwitchValue;
        check(Get("$state1") == true, "로그인 때 켜짐이 안 켜졌다");
        check(Get("$state3") == false, "로그인 때 꺼짐이 안 꺼졌다");
        -- The account's remembered value is dropped (owner), so "as you left it" starts off.
        check(Get("$state4") == false, "the dropped account value came back as " .. tostring(Get("$state4")));
    end);

    -- **The number was a second identity and it is gone.** A definition is filed under its own
    -- name now, which is what the Switches tab needs to be able to rename one: a name that lives
    -- beside a number is a name the number can disagree with. Leaving a numbered row behind is
    -- silent: `BindDerivedTables` walks names, so the row is simply never seen again and
    -- everything set on that switch is gone from the screen while still sitting in the file.
    test("dbver 6 files the definitions by name", function()
        local db = InitWith(OldSwitchAccount());
        check(Defs(db)[1] == nil and Defs(db)[2] == nil,
            "번호로도 열린다 - 한 스위치에 두 이름이 남았다");
        check(Defs(db)["$state1"] ~= nil, "이름으로 안 옮겨졌다");
        check(Defs(db)["$state1"] == DebindPrivate.Switches["$state1"],
            "저장과 살아 있는 표가 서로 다른 정의를 들고 있다");
    end);

    -- A step has to be safe to run again over what it already finished (`MigrateLayer`'s comment).
    -- A second pass that cannot read the string `mode` as a number and drops it to manual turns a
    -- computed switch quietly into one worked by hand.
    --
    -- **The dropped value is the riskiest part of a second pass.** It is gone after the first, so a
    -- second pass that judged use by it alone would delete the definition the first one kept.
    test("dbver 6 is safe to run twice", function()
        local db = OldSwitchAccount();
        DebindPrivate.MigrateSwitches(db, 5);
        DebindPrivate.MigrateSwitches(db, 5);
        check(Defs(db)["$state2"].mode == MODES.EXPR, "두 번째에 계산식 모드가 뭉개졌다");
        check(Defs(db)["$state1"].resetValue == true, "두 번째에 되돌릴 값이 뭉개졌다");
        check(Defs(db)["$state3"].resetValue == false, "두 번째에 false가 뭉개졌다");
        check(Defs(db)["$state4"] ~= nil, "두 번째 바퀴가 눌러본 적 있는 정의를 지웠다");
    end);

    --- 계산식도 매크로 본문이라 유닛을 이름으로 든다. 액션 사다리가 옮기는 것과 같은 이름이고,
    --- 여기는 사다리가 다르다 - 정의는 액션이 아니라 계정 표 꼭대기에 산다.
    ---
    --- **뿌리만이 아니라 덮어쓴 줄도 본다.** 한 탭에서만 거짓이 되는 것이 여기서 제일 조용한
    --- 실패라, `RenameSwitch`가 덮어쓴 줄을 도는 이유와 같다.
    test("dbver 7 renames the unit token in a switch expression", function()
        local db = {
            switches = {
                ["$s1"] = {
                    mode = MODES.EXPR,
                    expr = "[@hover,harm]",
                    overrides = { ["Player-1:2"] = { mode = MODES.EXPR, expr = "[@hovertarget]" } },
                },
            },
        };
        DebindPrivate.MigrateSwitches(db, 6);
        check(Defs(db)["$s1"].expr == "[@unitframe,harm]",
            "뿌리 계산식이 " .. tostring(Defs(db)["$s1"].expr) .. "다");
        -- `Player-1` has no entry in `characters`, so its row waits under `"*"` (the `dbver` 8 step).
        local row = db.switches["Player-1"]["*"][2]["$s1"];
        check(row.expr == "[@unitframetarget]", "덮어쓴 줄이 " .. tostring(row.expr) .. "다");
    end);

    ---------------------------------------------------------------------------
    -- dbver 6: 아무도 만든 적 없는 정의를 걷어낸다
    --
    -- 빈 정의 다섯 개를 매 로드마다 심던 자리가 `BindDerivedTables`였다. 그래서 이 기능을
    -- 한 번도 안 쓴 프로필에도 정의 다섯이 앉아 있고, §6-B의 목록이 서는 날 그 사람은 빈 줄
    -- 다섯 개로 시작한다. 심는 것을 그만두고, 이미 심긴 것은 이 단계가 한 번 걷어낸다.
    --
    -- **지우는 쪽이 실수하면 조용하다.** 살아 있어야 할 정의가 사라지면 그 이름을 건 조건은
    -- 영영 거짓이 되고, 매크로 본문의 그 이름은 빨간 마커를 달아 액션째 `KeyMap`에서 빠진다.
    -- 그래서 아래는 "지운다" 한 줄이 아니라 **남겨야 하는 경우들**이 대부분이다.
    ---------------------------------------------------------------------------

    --- `dbver` 5 계정 표에 정의 다섯과 레이어를 함께 세운다. 정의는 전부 **손 안 댄 기본값**
    --- 이므로, 남는 것이 있다면 이유는 참조 하나뿐이다.
    local function AccountWithUntouchedSwitches(layers)
        local db = {
            dbver = 5,
            shared = { classes = {} },
            characters = {},
            migrated = {},
            customStates = {},
        };
        for i = 1, 5 do
            db.customStates[i] = { mode = 0 };
        end
        if (layers) then
            layers(db);
        end
        return db;
    end

    local function switchNames(db)
        local names = {};
        for name in pairs(Defs(db)) do
            names[name] = true;
        end
        return names;
    end

    test("dbver 6 drops the definitions nobody made", function()
        local db = InitWith(AccountWithUntouchedSwitches());
        check(next(Defs(db)) == nil,
            "아무도 안 건드린 정의가 남았다 - 목록이 빈 줄로 시작한다");
        check(next(DebindPrivate.Switches) == nil, "살아 있는 표에도 남았다");
    end);

    -- **로드가 다시 심으면 안 된다.** 걷어내는 것과 안 심는 것은 다른 자리에 있고
    -- (`MigrateSwitches` / `BindDerivedTables`), 뒤엣것만 빠뜨리면 지운 것이 같은 로그인
    -- 안에서 도로 생긴다.
    test("BindDerivedTables no longer plants the five", function()
        local db = InitWith(AccountWithUntouchedSwitches());
        DebindPrivate.BindDerivedTables();
        check(next(Defs(db)) == nil, "로드가 빈 정의를 다시 심었다");
    end);

    -- 설정을 해뒀지만 아직 아무 액션에도 안 건 스위치. 참조만 보면 조용히 사라진다.
    test("dbver 6 keeps a definition that carries a setting", function()
        local db = InitWith(AccountWithUntouchedSwitches(function(account)
            account.customStates[1].initialValue = true;
            account.customStates[2].mode = 3;
            account.customStates[2].expr = "[combat]";
            account.customStates[3].displayMessage = true;
            -- 한 번이라도 눌러본 스위치. 누르면 `savedValue`가 남는다
            -- (`SwitchesChangedCallback`).
            account.customStates[4].savedValue = false;
        end));
        local names = switchNames(db);
        check(names["$state1"], "되돌릴 값이 있는 정의가 사라졌다");
        check(names["$state2"], "계산식 정의가 사라졌다");
        check(names["$state3"], "메시지 설정이 있는 정의가 사라졌다");
        check(names["$state4"], "눌러본 적 있는 정의가 사라졌다 - 기억한 값이 날아간다");
        check(not names["$state5"], "손 안 댄 것까지 남았다");
    end);

    -- 조건이 이름을 부르면 남는다. 세 자리 전부 - 계정, 클래스, 캐릭터 - 를 훑어야 한다.
    test("dbver 6 keeps a definition a condition names", function()
        local db = InitWith(AccountWithUntouchedSwitches(function(account)
            account.shared.GENERAL = {
                { type = "spell", value = 1, key = "F1", seq = 1, conditions = { ["$state1"] = true } },
            };
            account.shared.classes.DRUID = {
                [0] = { { type = "spell", value = 2, key = "F2", seq = 1, conditions = { ["$state2"] = false } } },
            };
            account.characters[GUID] = {
                class = "DRUID",
                layers = {
                    [3] = { { type = "spell", value = 3, key = "F3", seq = 1, conditions = { ["$state3"] = true } } },
                },
            };
        end));
        local names = switchNames(db);
        check(names["$state1"], "계정 레이어의 조건이 안 걷혔다");
        check(names["$state2"], "클래스 레이어의 조건이 안 걷혔다");
        check(names["$state3"], "캐릭터 레이어의 조건이 안 걷혔다");
        check(not names["$state5"], "아무도 안 부른 것까지 남았다 - 전제가 깨졌다");
    end);

    -- 켜기/끄기/전환 액션은 대상을 `value`에 싣는다. 조건 표를 안 지나가므로 조건만 훑으면
    -- 안 보이고, 그 정의가 사라지면 그 액션이 켜는 것이 아무 데도 없는 이름이 된다.
    --
    -- **This also pins the order of two ladders in one pass.** The seed is at `dbver` 5, so the
    -- action is still a bitpack, while the walk that collects references reads names. Unless
    -- `MigrateDB` raises the layers before `MigrateSwitches` runs, no name is collected here and
    -- every definition is deleted.
    test("dbver 6 keeps a definition a SETSTATE action names", function()
        local db = InitWith(AccountWithUntouchedSwitches(function(account)
            account.shared.GENERAL = {
                { type = "setstate", key = "F4", seq = 1, value = 0x400 + 2 },
            };
        end));
        local names = switchNames(db);
        check(names["$state2"], "전환 액션이 가리킨 정의가 사라졌다");
        check(not names["$state1"], "아무도 안 부른 것까지 남았다 - 전제가 깨졌다");

        local action = db.layers.account.GENERAL[0][1];
        check(action.type == Constants.SETSWITCH_TOGGLE, "액션이 안 갈렸다: " .. tostring(action.type));
        check(action.value == "$state2", "이름 " .. tostring(action.value));
    end);

    -- **본문은 안 본다.** 조건과 SETSTATE는 목록에서 골라 넣는 자리라 오타가 못 들어오지만,
    -- 매크로 본문의 `[$이름]`은 손으로 치는 자리다. 거기서 본 이름을 "쓰이는 중"으로 읽으면
    -- 오타 하나가 정의를 살려두고, ⚑2가 세운 빨간 마커가 그만큼 조용해진다.
    test("dbver 6 does not read macro bodies as a use", function()
        local db = InitWith(AccountWithUntouchedSwitches(function(account)
            account.shared.GENERAL = {
                { type = "macrotext", value = "/cast [$state1] Foo", key = "F5", seq = 1 },
            };
        end));
        check(next(Defs(db)) == nil, "본문의 이름이 정의를 살려뒀다");
    end);

    -- **The pre-rename definitions arrive after the stored profile has been raised**
    -- (`Legacy.lua`'s `ImportAccount` runs at PLAYER_LOGIN). Unless they ride the ladder on the
    -- way in, the old shape sits there under a `db.dbver` already stamped, and nothing raises it
    -- again.
    test("the pre-rename import raises the switch definitions too", function()
        FreshInit();
        local old = LegacyAccount();
        old.customStates = {
            [1] = { mode = 0, initialValue = true, displayMessage = true },
            [2] = { mode = 3, expr = "[combat]" },
        };
        _G.DebounceVars = old;

        DebindPrivate.RunLegacyMigration();
        -- `Events.lua`가 임포트 직후에 하는 것과 같은 순서. 표가 통째로 갈리므로 참조부터
        -- 다시 걸어야 한다.
        DebindPrivate.BindDerivedTables();

        local db = _G.DebindVars;
        check(db.customStates == nil, "옛 이름 그대로 앉았다 - 읽는 쪽이 없다");
        check(Defs(db)["$state1"].mode == MODES.MANUAL and Defs(db)["$state1"].resetValue == true,
            "수동 정의가 안 올라왔다");
        check(Defs(db)["$state2"].mode == MODES.EXPR, "계산식 정의가 안 올라왔다");
        check(DebindPrivate.Switches["$state1"] == Defs(db)["$state1"],
            "올라온 정의가 살아 있는 표에 안 걸렸다");
    end);

    ---------------------------------------------------------------------------
    -- dbver 6: the account's remembered value is dropped (owner, 2026-09-27)
    --
    -- Up to 5, "as you left it" was one `savedValue` on the account's definition. From 6 a
    -- character remembers its own, and the account's one goes to nobody: which character it
    -- belongs to is not in the data.
    ---------------------------------------------------------------------------

    test("dbver 6 drops the account's remembered value", function()
        local ALT = "Player-1234-0000ABCD";
        local account = OldSwitchAccount();
        account.characters[ALT] = {
            class = "PRIEST",
            layers = { [0] = { { type = "spell", value = 9, key = "F9", seq = 1 } } },
        };
        local db = InitWith(account);
        check(Defs(db)["$state4"].savedValue == nil, "the value stayed on the definition");
        check(DebindPrivate.GetRememberedSwitch("$state4") == nil, "this character got the value");
        check(db.states[ALT] == nil and db.characters[ALT].switches == nil, "another character got the value");
    end);

    -- With the value gone, all a definition that was only ever pressed has left is `mode`: **the
    -- same shape as an untouched one.** The value is evidence of use and has to be read before it
    -- goes, or a switch in use is deleted by the very step that drops the value.
    test("dbver 6 keeps a definition whose only trace is the value it dropped", function()
        local db = InitWith(OldSwitchAccount());
        check(Defs(db)["$state4"] ~= nil, "a definition that was pressed went with its value");
        check(DebindPrivate.Switches["$state4"] ~= nil, "the live table lost it too");
    end);

    --- The pre-rename import rides the same step, so it brings the old account value to nobody,
    --- and a value a character already has stays as it is.
    test("the pre-rename import drops the account's remembered value", function()
        local ALT = "Player-1234-0000ABCD";
        FreshInit();
        _G.DebindVars.characters[ALT] = { class = "PRIEST" };
        _G.DebindVars.states[ALT] = { switches = { ["$state4"] = false } };
        local old = LegacyAccount();
        old.customStates = { [4] = { mode = 0, savedValue = true } };
        _G.DebounceVars = old;

        DebindPrivate.RunLegacyMigration();
        check(DebindPrivate.GetRememberedSwitch("$state4") == nil, "this character got the value");
        check(_G.DebindVars.states[ALT].switches["$state4"] == false, "another character's value moved");
    end);

    ---------------------------------------------------------------------------
    -- ⚑4. `HasCharContent`가 새 저장소를 안 세면 값만 저장한 캐릭터의 항목이 로그아웃 한 번에
    -- 통째로 사라진다. 붙이고 떼는 판정이 그 함수 하나이고(`CleanUpDB`), 떼는 쪽은 조용하다.
    ---------------------------------------------------------------------------

    test("a character whose only content is a switch value keeps its entry", function()
        FreshInit();
        DebindPrivate.SetRememberedSwitch("$state1", true);
        DebindPrivate.CleanUpDB();
        check(_G.DebindVars.characters[GUID] ~= nil, "값만 있는 캐릭터의 항목이 로그아웃 한 번에 통째로 사라졌다");
        local state = _G.DebindVars.states[GUID];
        check(state ~= nil, "값만 있는 상태가 로그아웃 한 번에 통째로 사라졌다");
        check(state.switches["$state1"] == true, "상태는 붙었는데 값이 없다");
    end);

    ---------------------------------------------------------------------------
    -- 어느 팩을 안 건드릴지
    ---------------------------------------------------------------------------

    --- **없는 것은 우리 것이다.** 상자를 안 건드린 사람의 프로필에는 칸이 없고, 그 사람이 쓰던
    --- 것은 넓은 쪽이다. 여기서 `false`로 읽히면 리로드 한 번에 개체창 절반이 조용히 사라진다.
    test("a profile with no answer takes a known pack's frames", function()
        InitWith({});
        check(DebindPrivate.TakesPackFrames("Grid2") == true,
            "칸이 없는 프로필이 꺼짐으로 읽혔다");
    end);

    --- 반대쪽. 없이는 위 케이스가 "언제나 참"에도 초록으로 나온다.
    test("a profile that names a pack leaves it alone", function()
        InitWith({ options = { frameBlacklist = { addons = { Grid2 = false } } } });
        check(DebindPrivate.TakesPackFrames("Grid2") == false,
            "블랙리스트에 든 팩이 우리 것으로 읽혔다");
        check(DebindPrivate.TakesPackFrames("VuhDo") == true,
            "한 팩을 뺐더니 다른 팩까지 따라 나갔다");
    end);

    ---------------------------------------------------------------------------
    -- 블랙리스트 한 칸으로 모으기
    ---------------------------------------------------------------------------

    --- **`blizzframes`는 이미 나간 칸이다.** 안 옮기면 옛 프로필의 답이 아무 데서도 안 읽히고,
    --- 빼둔 블리자드 개체창이 리로드 한 번에 전부 우리 것으로 돌아온다. 조용하다.
    test("dbver 7 folds blizzframes into the one blacklist cell", function()
        local db = InitWith({
            dbver = 6,
            options = { blizzframes = { player = false }, unitframeUseMouseDown = true },
        });
        check(db.options.blizzframes == nil,
            "옛 칸이 남았다 - 읽는 쪽이 없으니 로그아웃마다 죽은 표가 같이 저장된다");
        check(db.options.frameBlacklist.blizzard.player == false,
            "빼둔 블리자드 개체창이 안 옮겨졌다");
        check(db.options.unitframeUseMouseDown == true,
            "옆 옵션이 같이 날아갔다");
    end);

    --- 워크트리 프로필만 갖고 있는 칸이라 어느 태그도 안 실어 날랐지만, 워크트리도 누가 쓰는
    --- 프로필이다.
    test("dbver 7 moves packFrames in beside it", function()
        local db = InitWith({ dbver = 6, packFrames = { Grid2 = false } });
        check(db.packFrames == nil, "옛 칸이 남았다");
        check(db.options.frameBlacklist.addons.Grid2 == false, "꺼둔 팩이 안 옮겨졌다");
        check(DebindPrivate.TakesPackFrames("Grid2") == false,
            "옮겨는 놨는데 관문이 못 읽는다");
    end);

    ---------------------------------------------------------------------------
    -- dbver 8: the layers gather in `layers` (`reshaping-stored-layers.md` §1)
    ---------------------------------------------------------------------------

    local ALT = "Player-1234-0000ABCD";

    --- A profile at 7 with a layer in every place 7 kept one, plus the leftovers the step has to
    --- drop: a string key beside the actions, an empty list, and a spec 5 behind a hole at 3 and 4.
    local function ProfileAt7()
        return {
            dbver = 7,
            migrated = {},
            shared = {
                GENERAL = {
                    { type = Constants.SPELL, value = 1, key = "F1", seq = 1 },
                    customStates = {},
                },
                classes = {
                    DRUID = {
                        [0] = { { type = Constants.SPELL, value = 2, key = "F2", seq = 1 } },
                        [1] = {},
                        [5] = { { type = Constants.SPELL, value = 5, key = "F5", seq = 1 } },
                    },
                },
            },
            characters = {
                [ALT] = {
                    name = "Alt", class = "PRIEST",
                    layers = { [2] = { { type = Constants.SPELL, value = 3, key = "F3", seq = 1 } } },
                    switches = { ["$state1"] = true },
                },
            },
        };
    end

    test("dbver 8 moves every layer into layers under its owner and class", function()
        local db = InitWith(ProfileAt7());
        local account = db.layers.account;
        check(account and account.GENERAL[0][1].value == 1, "GENERAL did not move");
        check(account.DRUID[0][1].value == 2, "the class layer did not move");
        check(account.DRUID[5] and account.DRUID[5][1].value == 5,
            "spec 5 behind the hole was left behind");
        check(db.layers[ALT] and db.layers[ALT].PRIEST[2][1].value == 3,
            "another character's layer did not move under its class");
        check(db.shared == nil, "shared is still there");
        check(db.characters[ALT].layers == nil, "the character entry still holds layers");
        check(db.characters[ALT].name == "Alt", "the identity went with the layers");
    end);

    --- **`characters` keeps identity only.** Backing up an account copies `characters` as it stands
    --- and carries no state (`reshaping-stored-layers.md` §1-1), so state left on the entry would
    --- have to be picked out on every export.
    test("dbver 8 moves what a character carries into states", function()
        local profile = ProfileAt7();
        profile.characters[ALT].CustomTargets = { custom1 = "focus" };
        profile.characters[GUID] = {
            name = "Me", class = "DRUID",
            switches = { ["$state2"] = false },
            CustomTargets = { custom2 = "party1" },
        };
        local db = InitWith(profile);
        check(db.states and db.states[ALT], "the alt's state did not move");
        check(db.states[ALT].switches["$state1"] == true, "the alt's remembered value did not move");
        check(db.states[ALT].CustomTargets.custom1 == "focus", "the alt's custom targets did not move");
        check(db.characters[ALT].switches == nil and db.characters[ALT].CustomTargets == nil,
            "the alt's entry still holds its state");
        check(db.characters[ALT].name == "Alt" and db.characters[ALT].class == "PRIEST",
            "the alt's identity went with its state");
        check(DebindPrivate.GetRememberedSwitch("$state2") == false,
            "this character's remembered value is not read from where it moved");
        check(DebindPrivate.GetSavedCustomTarget("custom2") == "party1",
            "this character's custom targets are not read from where they moved");
        check(DebindPrivate.db.char.switches == nil and DebindPrivate.db.char.CustomTargets == nil,
            "this character's entry still holds its state");
    end);

    --- An empty table the old load planted is no state, and moving it would give every alt a place
    --- in `states`.
    test("dbver 8 leaves an empty state behind", function()
        local profile = ProfileAt7();
        profile.characters[ALT].switches = {};
        local db = InitWith(profile);
        check(db.states[ALT] == nil, "an empty state moved");
    end);

    --- **The profile's spells are put on their first rank, once** (`keeping-a-pinned-rank-apart-from-
    --- the-spell.md` §7). Off the generated table, since the class of a layer's spell need not be
    --- logged in; a pinned one keeps its rank in `pinnedSpell`, and an id the table does not know is
    --- left as it is. Not the shared ladder's: a received payload does this where it arrives.
    test("dbver 8 puts the profile's spells on their first rank, the pin apart", function()
        local spells = DebindPrivate.CamelotSpells;
        DebindPrivate.CamelotSpells = { [686] = { 1 }, [695] = 686, [705] = 686 };
        local profile = ProfileAt7();
        local general = profile.shared.GENERAL;
        general[1].value = 705;
        general[2] = { type = Constants.SPELL, value = 695, key = "F6", seq = 1, pinRank = true };
        general[3] = { type = Constants.SPELL, value = 424242, key = "F7", seq = 1 };
        general[4] = { type = Constants.ITEM, value = 705, key = "F8", seq = 1 };
        local ok, err = pcall(DebindPrivate.MigrateDB, profile);
        DebindPrivate.CamelotSpells = spells;
        check(ok, tostring(err));
        local got = {};
        for _, action in ipairs(profile.layers.account.GENERAL[0]) do
            got[action.key] = tostring(action.value) .. "/" .. tostring(action.pinnedSpell);
        end
        check(got.F1 == "686/nil", "unpinned: " .. tostring(got.F1));
        check(got.F6 == "686/695", "pinned: " .. tostring(got.F6));
        check(got.F7 == "424242/nil", "unknown id: " .. tostring(got.F7));
        check(got.F8 == "705/nil", "an item: " .. tostring(got.F8));

        local layer = { { key = "A", type = Constants.SPELL, value = 705 } };
        DebindPrivate.CamelotSpells = { [686] = { 1 }, [705] = 686 };
        MigrateLayer(layer, 7);
        DebindPrivate.CamelotSpells = spells;
        check(layer[1].value == 705, "the shared ladder moved a value: " .. tostring(layer[1].value));
    end);

    --- Read off `MigrateDB` itself, since a load makes the lists this character reads again.
    test("dbver 8 drops what is not an action list", function()
        local db = ProfileAt7();
        DebindPrivate.MigrateDB(db);
        local general = db.layers.account.GENERAL[0];
        check(general.customStates == nil, "a string key beside the actions came across");
        check(#general == 1, "GENERAL holds " .. #general);
        check(db.layers.account.DRUID[1] == nil, "an empty list came across");
    end);

    --- **A step reads its own version's data and nothing later.** Raised one version, the bitpack
    --- opens into version 6's type names and goes no further; the `dbver <= 7` step is what renames
    --- them.
    test("a layer raised one version runs that version's step only", function()
        local layer = { { key = "A", type = "setstate", value = 0x400 + 2, seq = 1 } };
        DebindPrivate.MigrateLayer(layer, 5, 6);
        check(layer[1].type == "setstate_toggle", "the type is " .. tostring(layer[1].type));
    end);

    --- The switch step at 5 meets version 5's containers (`shared`, character entries) and the type
    --- names its own version's layer step just wrote. Reading later shapes, it found no reference
    --- and deleted every definition.
    test("the dbver 5 switch step finds references in version 5's shape", function()
        local db = {
            shared = {
                GENERAL = { { type = "setstate_toggle", value = "$state2", key = "F1", seq = 1 } },
                classes = { DRUID = { [0] = {
                    { type = "spell", value = 1, key = "F2", seq = 1, conditions = { ["$state3"] = true } },
                } } },
            },
            characters = {},
            customStates = { [1] = { mode = 0 }, [2] = { mode = 0 }, [3] = { mode = 0 } },
        };
        DebindPrivate.MigrateSwitches(db, 5, 6);
        check(db.switches["$state2"] ~= nil, "the definition an on/off/toggle action names was deleted");
        check(db.switches["$state3"] ~= nil, "the definition a condition names was deleted");
        check(db.switches["$state1"] == nil, "an untouched, unnamed definition stayed");
    end);

    --- **A switch stops being called a state in what is stored.** The three action types and the
    --- frame a converted macro clicks both carried the old word; a body left behind clicks a frame
    --- that no longer exists, and nothing says so.
    test("dbver 8 renames the switch action types and the frame a body clicks", function()
        local layer = {
            { type = "setstate_on", value = "$burst", key = "F1", seq = 1 },
            { type = "setstate_off", value = "$burst", key = "F2", seq = 1 },
            { type = "setstate_toggle", value = "$burst", key = "F3", seq = 1 },
            { type = Constants.MACROTEXT, value = "/cast Foo\n/click DebindStates $burst-on",
              key = "F4", seq = 1 },
            { type = Constants.SPELL, value = 5, key = "F5", seq = 1 },
        };
        DebindPrivate.MigrateLayer(layer, 7);
        check(layer[1].type == Constants.SETSWITCH_ON, "on is " .. tostring(layer[1].type));
        check(layer[2].type == Constants.SETSWITCH_OFF, "off is " .. tostring(layer[2].type));
        check(layer[3].type == Constants.SETSWITCH_TOGGLE, "toggle is " .. tostring(layer[3].type));
        check(layer[4].value == "/cast Foo\n/click DebindSwitch $burst-on",
            "the body is " .. tostring(layer[4].value));
        check(layer[5].value == 5, "another type's value was touched");

        DebindPrivate.MigrateLayer(layer, 7);
        check(layer[1].type == Constants.SETSWITCH_ON and layer[4].value
            == "/cast Foo\n/click DebindSwitch $burst-on", "a second run changed the result");
    end);

    --- **A hand-edited file is not ours to read.** The class is written on every login, so an entry
    --- without one did not come from the addon; what is asked is only that it does not raise.
    test("dbver 8 drops the layers of a character entry that has no class", function()
        local profile = ProfileAt7();
        profile.characters[ALT].class = nil;
        local ok, err = pcall(InitWith, profile);
        check(ok, "a class-less entry raised: " .. tostring(err));
        local db = _G.DebindVars;
        check(db.layers[ALT] == nil, "the layers of a class-less entry came across");
        check(db.characters[ALT].layers == nil, "the layers stayed on the entry");
    end);

    test("dbver 8 drops origin and keeps when the character was seen", function()
        local profile = ProfileAt7();
        profile.characters[ALT].origin = "local";
        profile.characters[ALT].firstSeen = 1;
        profile.characters[ALT].lastSeen = 2;
        local db = InitWith(profile);
        check(db.characters[ALT].origin == nil, "origin is still there");
        check(db.characters[ALT].firstSeen == 1 and db.characters[ALT].lastSeen == 2,
            "when the character was seen went with it");
    end);

    test("dbver 8 drops the keys nothing reads", function()
        local profile = ProfileAt7();
        profile.global = { customStates = {} };
        profile.char = { ["Name - Realm"] = {} };
        profile.class = { DRUID = {} };
        profile.profileKeys = { ["Name - Realm"] = "Default" };
        profile.unitFrameNoticeSeen = true;
        profile.options = {
            overviewui = { pos = {} },
            stateDriverUpdateThrottle = 0.2,
            removeStateDriverUpdateThrottle = true,
            addCustomTargetMenusOnUnitPopup = true,
            addCustomTargetMenusToUnitPopup = true,
            unitframeUseMouseDown = true,
        };
        local db = InitWith(profile);
        for _, key in ipairs({ "global", "char", "class", "profileKeys", "unitFrameNoticeSeen" }) do
            check(db[key] == nil, key .. " is still there");
        end
        for _, key in ipairs({ "overviewui", "stateDriverUpdateThrottle",
                "removeStateDriverUpdateThrottle", "addCustomTargetMenusOnUnitPopup",
                "addCustomTargetMenusToUnitPopup" }) do
            check(db.options[key] == nil, "options." .. key .. " is still there");
        end
        check(db.options.unitframeUseMouseDown == true, "an option something reads went too");
    end);

    --- **At 7 the old cell is a stray, not an answer.** The `dbver` 7 step moved it long ago; one
    --- still there came in afterwards, and folding it now would put back frames the reader has
    --- since taken.
    test("dbver 8 drops a stray blizzframes without folding it", function()
        local profile = ProfileAt7();
        profile.options = {
            blizzframes = { player = false },
            frameBlacklist = { blizzard = { player = true }, addons = {} },
        };
        local db = InitWith(profile);
        check(db.options.blizzframes == nil, "the stray cell is still there");
        check(db.options.frameBlacklist.blizzard.player == true,
            "the stray cell overwrote what the reader has ticked since");
    end);

    --- **A switch lays out the way the layers do.** The overrides leave the definition for cells of
    --- their own; a character whose class the file does not hold waits under `"*"`.
    test("dbver 8 files every override row in a cell of its layer", function()
        local profile = ProfileAt7();
        profile.switches = {
            ["$burst"] = {
                mode = MODES.MANUAL, resetValue = true, value = true, displayMessage = true,
                overrides = {
                    ["DRUID:2"] = { mode = MODES.EXPR, expr = "[combat]" },
                    [ALT .. ":1"] = { mode = MODES.MANUAL, resetValue = false },
                    ["Player-9-FFFF:3"] = { mode = MODES.IGNORE },
                },
            },
        };
        local db = profile;
        DebindPrivate.MigrateDB(db);
        local switches = db.switches;
        local root = switches.account.GENERAL[0]["$burst"];
        check(root and root.mode == MODES.MANUAL and root.resetValue == true, "the root row moved wrong");
        check(root.value == nil and root.displayMessage == nil and root.overrides == nil,
            "a field that is not a setting came across");
        check(switches.account.DRUID[2]["$burst"].expr == "[combat]", "the class row did not move");
        check(switches[ALT].PRIEST[1]["$burst"].resetValue == false,
            "the character row did not move under the class its entry holds");
        check(switches["Player-9-FFFF"]["*"][3]["$burst"].mode == MODES.IGNORE,
            "the row of a character with no entry did not wait under *");

        DebindPrivate.MigrateSwitches(db, 7);
        check(switches == db.switches and db.switches.account.GENERAL[0]["$burst"] == root,
            "a second run moved the new shape again");
    end);

    --- **Only the closed tips cross over** to `DebindUIVars`; positions, the sort and the filters
    --- start over.
    test("dbver 8 carries the closed tips into DebindUIVars and drops the rest", function()
        local profile = ProfileAt7();
        profile.tipsSeen = { settingsGear = true };
        profile.ui = { main = { x = 1, y = 2 }, binSort = "key" };
        profile.spellPicker = { spell = { showOffSpec = true } };
        _G.DebindUIVars = nil;
        local db = InitWith(profile);
        check(db.tipsSeen == nil and db.ui == nil and db.spellPicker == nil,
            "the window's values stayed in DebindVars");
        check(_G.DebindUIVars and _G.DebindUIVars.tipsSeen
            and _G.DebindUIVars.tipsSeen.settingsGear == true, "the closed tips did not cross over");
        check(_G.DebindUIVars.main == nil and _G.DebindUIVars.spellPicker == nil,
            "a position or a filter crossed over");
    end);

    --- **A new shape empties the table and keeps the tips and the spells added by id.** It does not
    --- ride the ladder.
    test("a DebindUIVars of another version is emptied but for the closed tips and added spells", function()
        _G.DebindUIVars = {
            version = Constants.UI_VARS_VERSION - 1,
            main = { pos = { x = 1, y = 2 } },
            tipsSeen = { settingsGear = true },
            userSpells = { [8690] = true },
        };
        InitWith({});
        local vars = _G.DebindUIVars;
        check(vars.version == Constants.UI_VARS_VERSION, "the version was not stamped");
        check(vars.main == nil, "a value of the old shape stayed");
        check(vars.tipsSeen and vars.tipsSeen.settingsGear == true, "the closed tips were dropped");
        check(vars.userSpells and vars.userSpells[8690] == true, "the spells added by id were dropped");
        check(DebindPrivate.UIVars == vars, "the addon reads another table than the one saved");
    end);

    --- **The entry names the layers.** Whoever reads `layers[guid]` from another character has only
    --- `characters[guid]` to tell them whose they are, so a character whose only content is a layer
    --- keeps its entry.
    test("a character whose only content is a layer keeps its entry", function()
        FreshInit();
        DebindPrivate.GetProfileLayer(DebindPrivate.GetLayerID(0, true)):Insert(
            { type = Constants.SPELL, value = 1, key = "F1", seq = 1 });
        DebindPrivate.CleanUpDB();
        check(_G.DebindVars.layers[GUID] == DebindPrivate.db.charLayers,
            "the layers were not attached");
        check(_G.DebindVars.characters[GUID] == DebindPrivate.db.char,
            "the layers were attached without the entry that names them");
    end);

    --- **The higher of the two counters.** The ladder stamps every badge in the old file as arrival
    --- 1; a live counter left at 1 hands the next arrival the same number, and a group is
    --- `(key, arrivalID)`, so accepting one would accept both.
    test("the pre-rename import raises the arrival counter past its badges", function()
        FreshInit();
        local old = LegacyAccount();
        old.GENERAL[1].key = 777;
        old.GENERAL[1].imported = "F1";
        old.dbver = 3;
        _G.DebounceVars = old;
        DebindPrivate.RunLegacyMigration();

        check(_G.DebindVars.layers.account.GENERAL[0][1].arrivalID == 1,
            "the badge was not raised - the premise broke");
        check(DebindPrivate.NextArrivalID() == 2,
            "a new arrival gets the number the imported badge already holds");
    end);

    ---------------------------------------------------------------------------
    -- 없어진 옵션의 값
    ---------------------------------------------------------------------------

    --- **끄는 것과 지우는 것은 다르다는 원칙은 옵션이 살아 있을 때의 것이다.** 상자가 없어지면
    --- 다시 켤 길도 없으니 그 값은 아무에게도 뜻이 없는 고아고, 안 지우면 SavedVariables에
    --- 영영 남는다 (`taking-every-unit-frame-with-one-blacklist.md` §3).
    test("the two switches the blacklist replaced are swept out of the account file", function()
        local db = InitWith({ workAlongsideClique = true, takeUnregisteredFrames = false });
        DebindPrivate.CleanUpDB();
        check(db.workAlongsideClique == nil,
            "workAlongsideClique가 남았다: " .. tostring(db.workAlongsideClique));
        check(db.takeUnregisteredFrames == nil,
            "takeUnregisteredFrames가 남았다: " .. tostring(db.takeUnregisteredFrames));
    end);

    test("what the class trainers were read selling is swept out of the account file", function()
        local db = InitWith({ trainerSpells = { DRUID = { [5177] = 6 } } });
        DebindPrivate.CleanUpDB();
        check(db.trainerSpells == nil, "trainerSpells is still there");
    end);

    return T;
end
