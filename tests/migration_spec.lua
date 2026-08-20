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

    --- 저장된 유닛 조건 하나 -> 소비자 둘이 보는 답.
    ---
    --- 옛 스칼라 넷은 `Profile.lua`의 `dbver <= 1` 단계가 `checkedUnitValue`를 그대로 옮겨
    --- 넣은 것이라 그 시절 값도 이 안에 있다. 표 모양은 `dbver <= 4`가 낸 것과 메뉴가 지금
    --- 쓰는 것 전부다.
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
        { "{off=true,reaction=HELP}", { off = true, reaction = Constants.REACTION_HELP },
            nil, nil },
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

    local function checkHoverCase(case, action, when)
        local hover, reactions, existing = case[1], case[2], case[3];
        local wantMask, wantCond = case[4], case[5];
        local label = ("hover=%s reactions=%s existing=%s"):format(
            tostring(hover), tostring(reactions), describe(existing));

        local binding = bindingFor(action);
        local gotMask = binding.unitStates and binding.unitStates.hover;
        local gotCond = binding.conditions.units and binding.conditions.units.hover;

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
            checkHoverCase(case, layer[1], "(마이그레이션 후)");
        end
    end);

    test("dbver 5 moves the hover condition onto the unit it names", function()
        local layer = { { key = "A", type = Constants.SPELL, value = 100,
            hover = true, reactions = Constants.REACTION_HELP } };
        MigrateLayer(layer, 4);

        check(layer[1].hover == nil, "옛 hover 필드가 남음");
        check(layer[1].reactions == nil, "옛 reactions 필드가 남음");
        check(layer[1].conditions.units.hover.reaction == Constants.REACTION_HELP,
            "반응이 유닛 조건으로 안 옮겨감");
    end);

    test("dbver 5 is safe to run twice over a folded hover condition", function()
        for _, case in ipairs(HOVER_CASES) do
            local layer = { hoverAction(case) };
            MigrateLayer(layer, 4);
            MigrateLayer(layer, 4);
            checkHoverCase(case, layer[1], "(두 번 돌린 뒤)");
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
        check(type(db.shared.GENERAL[1].conditions.units.target) == "table",
            "공유 GENERAL이 안 올라감");
        check(type(db.shared.classes.DRUID[0][1].conditions.units.focus) == "table",
            "공유 클래스 레이어가 안 올라감");
        check(type(db.shared.classes.DRUID[2][1].conditions.units.tank) == "table",
            "특성이 0이 아닌 레이어가 안 올라감");
        check(type(db.characters[GUID].layers[0][1].conditions.units.mouseover) == "table",
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

        check(_G.DebindVars.shared.GENERAL[1].conditions.units.target.reaction
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
        check(#DebindPrivate.db.global.shared.GENERAL == 0,
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

    test("dbver 6 moves the switch definitions under their new name", function()
        local db = InitWith(OldSwitchAccount());
        check(db.customStates == nil,
            "옛 이름이 남았다 - 읽는 쪽이 없으니 로그아웃마다 죽은 표가 같이 저장된다");
        check(type(db.switches) == "table", "switches가 없다");
        check(db.switches[1].displayMessage == true, "정의가 안 따라왔다");
        check(db.switches[2].expr == "[combat]", "계산식이 안 따라왔다");
    end);

    test("dbver 6 turns the mode numbers into names", function()
        local db = InitWith(OldSwitchAccount());
        check(db.switches[1].mode == MODES.MANUAL,
            "수동이 " .. tostring(db.switches[1].mode) .. "로 남았다");
        check(db.switches[2].mode == MODES.EXPR,
            "계산식이 " .. tostring(db.switches[2].mode) .. "로 남았다 - 숫자는 어느 쪽과도 안 맞는다");
    end);

    -- **`false`와 없는 것은 다른 답이다.** 뭉개면 "로그인 때 꺼짐"으로 해둔 스위치가 지난
    -- 세션의 값을 들고 올라온다.
    test("dbver 6 renames initialValue without flattening its three answers", function()
        local db = InitWith(OldSwitchAccount());
        check(db.switches[1].initialValue == nil and db.switches[3].initialValue == nil,
            "옛 필드가 남았다");
        check(db.switches[1].resetValue == true, "true가 안 옮겨졌다");
        check(db.switches[3].resetValue == false,
            "false가 " .. tostring(db.switches[3].resetValue) .. "가 됐다");
        check(db.switches[4].resetValue == nil, "없던 값이 생겼다");
    end);

    -- 이름이 아니라 **그 이름으로 나오는 답**을 본다. `value`를 정하는 것은 저장이 아니라
    -- `BindDerivedTables`이고, 그것이 새 이름을 못 읽으면 위가 다 초록이어도 스위치는 틀린
    -- 값으로 켜진다.
    --
    -- **살아 있는 표는 이름으로 연다.** 저장은 번호로 앉아 있고 조건·매크로 본문·SETSTATE는
    -- 전부 이름으로 부르므로, 둘을 잇는 것이 `BindDerivedTables`다. 번호로 열리면
    -- `ResolveSwitchDefinition`이 아무것도 못 찾는다.
    test("dbver 6 keeps what each switch comes up as", function()
        InitWith(OldSwitchAccount());
        local switches = DebindPrivate.Switches;
        check(switches["$state1"].value == true, "로그인 때 켜짐이 안 켜졌다");
        check(switches["$state3"].value == false, "로그인 때 꺼짐이 안 꺼졌다");
        check(switches["$state4"].value == true, "기억한 값으로 안 돌아갔다");
        check(switches[1] == nil, "번호로도 열린다 - 이름 하나로 답이 나와야 한다");
    end);

    -- 단계는 자기가 이미 끝낸 데이터 위에서 다시 돌아도 안전해야 한다(`MigrateLayer` 주석).
    -- 두 번째 바퀴가 문자열 `mode`를 숫자로 못 읽어 수동으로 떨어뜨리면 계산식 스위치가
    -- 조용히 손으로 켜는 것이 된다.
    --
    -- **값을 옮기는 것이 다시 도는 쪽에서 제일 위험하다.** 두 번째 바퀴에는 옮길 것이 안
    -- 남아 있는데, 걷어내는 쪽이 그것을 계정에서 읽으면 첫 바퀴가 살려둔 정의를 두 번째
    -- 바퀴가 지운다.
    test("dbver 6 is safe to run twice", function()
        local db = OldSwitchAccount();
        local charEntry = { layers = {}, switches = {} };
        DebindPrivate.MigrateSwitches(db, 5, charEntry);
        DebindPrivate.MigrateSwitches(db, 5, charEntry);
        check(db.switches[2].mode == MODES.EXPR, "두 번째에 계산식 모드가 뭉개졌다");
        check(db.switches[1].resetValue == true, "두 번째에 되돌릴 값이 뭉개졌다");
        check(db.switches[3].resetValue == false, "두 번째에 false가 뭉개졌다");
        check(charEntry.switches["$state4"] == true, "두 번째에 기억한 값이 뭉개졌다");
        check(db.switches[4] ~= nil, "두 번째 바퀴가 눌러본 적 있는 정의를 지웠다");
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
        for index in pairs(db.switches or {}) do
            names[Constants.SWITCH_NAMES[index]] = true;
        end
        return names;
    end

    test("dbver 6 drops the definitions nobody made", function()
        local db = InitWith(AccountWithUntouchedSwitches());
        check(next(db.switches) == nil,
            "아무도 안 건드린 정의가 남았다 - 목록이 빈 줄로 시작한다");
        check(next(DebindPrivate.Switches) == nil, "살아 있는 표에도 남았다");
    end);

    -- **로드가 다시 심으면 안 된다.** 걷어내는 것과 안 심는 것은 다른 자리에 있고
    -- (`MigrateSwitches` / `BindDerivedTables`), 뒤엣것만 빠뜨리면 지운 것이 같은 로그인
    -- 안에서 도로 생긴다.
    test("BindDerivedTables no longer plants the five", function()
        local db = InitWith(AccountWithUntouchedSwitches());
        DebindPrivate.BindDerivedTables();
        check(next(db.switches) == nil, "로드가 빈 정의를 다시 심었다");
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

    -- 켜기/끄기/전환 액션은 `value`에 번호를 싣는다. 조건 표를 안 지나가므로 조건만 훑으면
    -- 안 보이고, 그 정의가 사라지면 그 액션이 켜는 것이 아무 데도 없는 이름이 된다.
    test("dbver 6 keeps a definition a SETSTATE action names", function()
        local db = InitWith(AccountWithUntouchedSwitches(function(account)
            account.shared.GENERAL = {
                { type = "setstate", key = "F4", seq = 1,
                  value = bit.bor(Constants.SETCUSTOM_MODE_TOGGLE, 2) },
            };
        end));
        local names = switchNames(db);
        check(names["$state2"], "전환 액션이 가리킨 정의가 사라졌다");
        check(not names["$state1"], "아무도 안 부른 것까지 남았다 - 전제가 깨졌다");
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
        check(next(db.switches) == nil, "본문의 이름이 정의를 살려뒀다");
    end);

    -- **개명 전 파일의 정의는 `MigrateDB`가 지나간 뒤에 도착한다.** 계정 몫은 덩어리째 얹히는
    -- 길이고(`Legacy.lua`의 `ImportAccount`), 레이어와 달리 정의를 올려주는 것이 그 위에
    -- 아무것도 없다. 거기서 사다리를 안 밟으면 옛 모양이 그대로 앉는데 `db.dbver`는 이미
    -- 찍혀 있어서 다시 돌 기회가 없다.
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
        check(db.switches[1].mode == MODES.MANUAL and db.switches[1].resetValue == true,
            "수동 정의가 안 올라왔다");
        check(db.switches[2].mode == MODES.EXPR, "계산식 정의가 안 올라왔다");
        check(DebindPrivate.Switches["$state1"].displayMessage == true,
            "올라온 정의가 살아 있는 표에 안 걸렸다");
    end);

    ---------------------------------------------------------------------------
    -- dbver 6: 기억한 값이 계정에서 캐릭터로
    --
    -- **저장되는 값은 하나뿐이다.** 계산식 스위치는 파생값이라 저장할 것이 없고, 남는 것은
    -- 수동 + "기억하기"(`resetValue == nil`)의 `savedValue` 하나다. 그것이 계정에 앉아 있는
    -- 동안 "기억하기"는 **마지막에 로그아웃한 캐릭터가 남긴 값 기억하기**였다
    -- (`devdocs/redesigning-custom-states.md` §5).
    --
    -- **`db.characters`는 계정 파일 안에 있고 전부 한꺼번에 메모리에 올라온다.** 그래서
    -- "캐릭터마다 자기 첫 로그인에 알아서 마이그레이션된다"가 여기서는 성립하지 않는다 -
    -- 사다리는 계정당 한 번 돈다. 그 한 번에 항목이 있는 캐릭터 전부와 지금 들어온 캐릭터가
    -- 값을 나눠 받는다.
    ---------------------------------------------------------------------------

    test("dbver 6 hands the remembered value to this character", function()
        local db = InitWith(OldSwitchAccount());
        check(type(DebindPrivate.db.char.switches) == "table", "캐릭터 쪽에 표가 없다");
        check(DebindPrivate.db.char.switches["$state4"] == true,
            "기억한 값이 캐릭터로 안 왔다");
        check(db.switches[4].savedValue == nil,
            "정의에 값이 남았다 - 두 자리가 같은 것을 말하면 어느 쪽이 답인지가 없다");
    end);

    -- 항목이 이미 있는 다른 캐릭터도 같은 값을 받는다. 안 받으면 마이그레이션 다음 로그인에
    -- 스위치가 저 혼자 꺼지고, 그 스위치가 어느 키에 무엇이 걸리는지를 가른다.
    test("dbver 6 hands the same value to the alts that have an entry", function()
        local ALT = "Player-1234-0000ABCD";
        local account = OldSwitchAccount();
        account.characters[ALT] = {
            layers = { [0] = { { type = "spell", value = 9, key = "F9", seq = 1 } } },
        };
        local db = InitWith(account);
        check(type(db.characters[ALT].switches) == "table", "다른 캐릭터에 표가 없다");
        check(db.characters[ALT].switches["$state4"] == true, "다른 캐릭터가 값을 못 받았다");
    end);

    -- 값을 옮기고 나면 그 정의에 남는 것은 `mode` 하나, 곧 **손 안 댄 기본값과 같은 모양**이다.
    -- 걷어내는 쪽이 눌러본 증거를 계정이 아니라 캐릭터에서 읽지 않으면, 실제로 쓰던 스위치가
    -- 값을 옮긴 바로 그 단계에 지워진다.
    test("dbver 6 keeps a definition whose only trace is the value it moved", function()
        local db = InitWith(OldSwitchAccount());
        check(db.switches[4] ~= nil, "눌러본 적 있는 정의가 값을 옮기면서 같이 사라졌다");
        check(DebindPrivate.Switches["$state4"] ~= nil, "살아 있는 표에서도 사라졌다");
    end);

    -- 개명 전 SavedVariables를 얹는 길은 이 계정이 **이미 값을 쓰고 있는 동안** 열린다
    -- (`Legacy.lua`의 `ImportAccount`는 PLAYER_LOGIN에 돈다). 실려 오는 계정 값은 그것들보다
    -- 오래된 것이라, 덮으면 사용자가 방금 이 캐릭터에서 정한 것이 옛 값으로 되돌아간다.
    test("dbver 6 does not overwrite a value the character already has", function()
        local db = OldSwitchAccount();
        local charEntry = { layers = {}, switches = { ["$state4"] = false } };
        DebindPrivate.MigrateSwitches(db, 5, charEntry);
        check(charEntry.switches["$state4"] == false,
            "이 캐릭터가 정해둔 값이 실려 온 계정 값으로 덮였다");
    end);

    ---------------------------------------------------------------------------
    -- ⚑4. `HasCharContent`가 새 저장소를 안 세면 값만 저장한 캐릭터의 항목이 로그아웃 한 번에
    -- 통째로 사라진다. 붙이고 떼는 판정이 그 함수 하나이고(`CleanUpDB`), 떼는 쪽은 조용하다.
    ---------------------------------------------------------------------------

    test("a character whose only content is a switch value keeps its entry", function()
        FreshInit();
        DebindPrivate.db.char.switches = DebindPrivate.db.char.switches or {};
        DebindPrivate.db.char.switches["$state1"] = true;
        DebindPrivate.CleanUpDB();
        local entry = _G.DebindVars.characters[GUID];
        check(entry ~= nil, "값만 있는 항목이 로그아웃 한 번에 통째로 사라졌다");
        check(entry.switches["$state1"] == true, "항목은 붙었는데 값이 없다");
    end);

    return T;
end
