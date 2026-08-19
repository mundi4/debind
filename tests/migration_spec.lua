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
        -- 상수로 묻는다. 숫자를 박아두면 `DB_VERSION`을 올릴 때마다 이 줄이 같이 깨지는데,
        -- 그건 마이그레이션이 틀렸다는 신호가 아니라 이 테스트가 낡았다는 신호일 뿐이다.
        check(_G.DebindVars.dbver == DebindPrivate.Constants.DB_VERSION,
            "dbver was overwritten with the old value");
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

        local c = layer[1].checkedUnits;
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
        check(layer[1].checkedUnits["@"].reaction == Constants.REACTION_HELP, "\"@\"가 안 옮겨짐");
    end);

    -- 단계는 자기가 이미 끝낸 데이터 위에서 다시 돌아도 안전해야 한다(`MigrateLayer` 주석).
    -- 두 판 밀린 프로필이 여기를 두 번 지난다.
    test("dbver 5 is safe to run twice", function()
        local layer = { { key = "A", type = 1, value = 1,
            checkedUnits = { focus = "help", tank = false } } };
        MigrateLayer(layer, 4);
        MigrateLayer(layer, 4);
        check(layer[1].checkedUnits.focus.reaction == Constants.REACTION_HELP, "두 번째에 뭉개짐");
        check(layer[1].checkedUnits.tank.exists == false, "두 번째에 뭉개짐");
    end);

    test("dbver 5 leaves actions without unit conditions alone", function()
        local layer = { { key = "A", type = 1, value = 1 } };
        MigrateLayer(layer, 4);
        check(layer[1].checkedUnits == nil, "없던 표가 생김");
    end);

    ---------------------------------------------------------------------------
    -- dbver 5의 핵심 불변식: **표현만 바꾸고 뜻은 안 바꾼다**
    --
    -- 마이그레이션은 한 번 돌면 되돌릴 수 없고, 틀려도 화면에 아무 표시가 없다. 그래서 값이
    -- 어떻게 생겼는지가 아니라 **소비자가 보는 것이 그대로인지**를 못 박는다. 소비자는 둘뿐이다:
    --
    --   solver  `BuildUnitStates`가 만드는 유닛 축 마스크
    --   런타임  스니펫에 내려가는 스칼라
    --
    -- 둘 다 옛 값과 새 값에서 같은 답이 나오면, 이 마이그레이션은 사용자가 걸어둔 조건을
    -- 한 개도 안 바꾼 것이다.
    ---------------------------------------------------------------------------

    local UnitConditionToRuntimeScalar = DebindPrivate.UnitConditionToRuntimeScalar;

    --- 옛 형식이 실제로 가질 수 있던 값 전부. `Profile.lua`의 `dbver <= 1` 단계가
    --- `checkedUnitValue`를 그대로 옮겨 넣으므로, 그 시절 값도 이 넷 안에 있어야 한다.
    local OLD_VALUES = { true, false, "help", "harm" };

    local function stateFor(action)
        return DebindPrivate.GetBindingInfoForAction(action, true).unitStates;
    end

    test("dbver 5 keeps every old value meaning the same thing to the solver", function()
        for _, old in ipairs(OLD_VALUES) do
            local before = stateFor({
                type = Constants.SPELL, value = 100,
                checkedUnits = { target = old },
            });

            local layer = { { key = "A", type = Constants.SPELL, value = 100,
                checkedUnits = { target = old } } };
            MigrateLayer(layer, 4);
            local after = stateFor(layer[1]);

            check(before.target == after.target,
                ("%s의 뜻이 바뀜: %s -> %s"):format(tostring(old),
                    tostring(before.target), tostring(after.target)));
        end
    end);

    test("dbver 5 keeps every old value emitting the same thing to the snippet", function()
        for _, old in ipairs(OLD_VALUES) do
            local layer = { { key = "A", type = Constants.SPELL, value = 100,
                checkedUnits = { target = old } } };
            MigrateLayer(layer, 4);

            local emitted = UnitConditionToRuntimeScalar(layer[1].checkedUnits.target);
            check(emitted == old,
                ("%s가 스니펫에 %s로 내려감"):format(tostring(old), tostring(emitted)));
        end
    end);

    ---------------------------------------------------------------------------
    -- 같은 단계가 hover 조건도 옮긴다
    --
    -- `hover`/`reactions`는 **릴리스된 프로필에 실제로 들어 있는** 값이라, 여기가 틀리면
    -- 사용자가 걸어둔 호버 조건이 조용히 사라지거나 넓어진다. 위와 같은 불변식으로 본다:
    -- 소비자(solver의 유닛 축)가 옛 값과 새 값에서 같은 답을 내는가.
    ---------------------------------------------------------------------------

    local HOVER_VALUES = {
        { hover = true },
        { hover = true, reactions = Constants.REACTION_HELP },
        { hover = true, reactions = Constants.REACTION_ALL },
        { hover = false },
    };

    test("dbver 5 keeps every hover condition meaning the same thing", function()
        for _, old in ipairs(HOVER_VALUES) do
            local before = stateFor({ type = Constants.SPELL, value = 100,
                hover = old.hover, reactions = old.reactions });

            local layer = { { key = "A", type = Constants.SPELL, value = 100,
                hover = old.hover, reactions = old.reactions } };
            MigrateLayer(layer, 4);
            local after = stateFor(layer[1]);

            check(before.hover == after.hover,
                ("hover=%s reactions=%s의 뜻이 바뀜: %s -> %s"):format(
                    tostring(old.hover), tostring(old.reactions),
                    tostring(before.hover), tostring(after.hover)));
        end
    end);

    test("dbver 5 moves the hover condition onto the unit it names", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP } };
        MigrateLayer(layer, 4);

        check(layer[1].hover == nil, "옛 hover 필드가 남음");
        check(layer[1].reactions == nil, "옛 reactions 필드가 남음");
        check(layer[1].checkedUnits.hover.reaction == Constants.REACTION_HELP,
            "반응이 유닛 조건으로 안 옮겨감");
    end);

    -- 두 메뉴가 다 살아 있던 시절의 프로필. 덮으면 걸어둔 것보다 넓어지므로 교집합하고,
    -- 안 겹치면 어떤 유닛도 못 드는 조건(마스크 0)이 되어 이슈로 잡힌다.
    test("dbver 5 intersects a hover condition with one already on that unit", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP,
            checkedUnits = { hover = { reaction = Constants.REACTION_HARM } } } };
        MigrateLayer(layer, 4);

        check(stateFor(layer[1]).hover == 0, "안 겹치는 두 조건이 0이 안 됨");
    end);

    test("dbver 5 is safe to run twice over a folded hover condition", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP } };
        MigrateLayer(layer, 4);
        local once = stateFor(layer[1]).hover;
        MigrateLayer(layer, 4);

        check(stateFor(layer[1]).hover == once, "다시 돌렸더니 뜻이 바뀜");
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
        check(type(db.shared.GENERAL[1].checkedUnits.target) == "table",
            "공유 GENERAL이 안 올라감");
        check(type(db.shared.classes.DRUID[0][1].checkedUnits.focus) == "table",
            "공유 클래스 레이어가 안 올라감");
        check(type(db.shared.classes.DRUID[2][1].checkedUnits.tank) == "table",
            "특성이 0이 아닌 레이어가 안 올라감");
        check(type(db.characters[GUID].layers[0][1].checkedUnits.mouseover) == "table",
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
        check(type(action.checkedUnits.focus) == "table"
            and action.checkedUnits.focus.reaction == Constants.REACTION_HELP,
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
                target = layer[1].checkedUnits.target.reaction,
                tank = layer[1].checkedUnits.tank,
                at = layer[1].checkedUnits["@"].reaction,
                seq = layer[1].seq,
            };

            MigrateLayer(layer, from);
            check(layer[1].checkedUnits.target.reaction == once.target
                and layer[1].checkedUnits.tank == once.tank
                and layer[1].checkedUnits["@"].reaction == once.at
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

        check(_G.DebindVars.shared.GENERAL[1].checkedUnits.target.reaction
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
        local action = { type = Constants.SPELL, value = 774, key = "F", seq = 1, imported = 7 };
        layer:Insert(action);

        -- **키를 아직 안 정한 그룹의 키도 견뎌야 한다.** 숫자라는 것만 다를 뿐 키이고, 지워지면
        -- 그 묶음이 흩어진 채로 지정 안 된 더미에 떨어진다.
        local pending = { type = Constants.SPELL, value = 775, key = 3, seq = 1, imported = 7 };
        layer:Insert(pending);

        DebindPrivate.CleanUpDB();

        check(action.imported == 7, "배치 번호가 지워졌다 - 다음 접속에 격리가 저절로 풀린다");
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
    -- 그래서 여기 박아둔다. `devdocs/guarding-against-a-downgrade.md`.
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

    -- 되돌아온 자리. 물러섰던 세션 다음에 정상 프로필로 들어오면 깃발이 서 있으면 안 된다.
    test("정상 프로필로 돌아오면 깃발이 내려간다", function()
        NewerInit();
        FreshInit();
        check(not DebindPrivate.profileIsNewer, "깃발이 선 채로 남았다");
    end);

    return T;
end
