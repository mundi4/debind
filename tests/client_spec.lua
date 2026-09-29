-- **What the client layer hands the rest of the addon, on each client.** `Debind/Client/` is where
-- the two clients are asked for the same thing in different ways (`preparing-the-code-for-camelot.md`
-- §3), so every case here runs twice: once in the retail world and once in the camelot one, which
-- `run.lua` picks with the spec entry's `client`. A case states what both clients must end up with,
-- and the world decides what it takes to get there.

return function(DebindPrivate, DebindStorage)
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local camelot = shim.world.client == "camelot";

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

    --- The class ids each world's client has, in its own order.
    local EXPECTED_CLASSES = camelot and { 1, 2, 3, 4, 5, 7, 8, 9, 11 } or { 1, 2, 8, 11 };

    local function Ids(list)
        local out = {};
        for i = 1, #list do
            out[i] = tostring(list[i]);
        end
        return table.concat(out, ",");
    end

    -- **The catalog is where a missing class shows**: the specialization menu, the class masks and
    -- "nothing is selected" all read it. On camelot `GetNumClasses()` is 9 and Druid is index 11,
    -- so a walk to the count stops before Druid.
    test("the class catalog holds every class the client has", function()
        local ids = {};
        for _, entry in ipairs(DebindPrivate.ClassSpecCatalog()) do
            ids[#ids + 1] = entry.id;
        end
        check(Ids(ids) == Ids(EXPECTED_CLASSES),
            "catalog " .. Ids(ids) .. ", client has " .. Ids(EXPECTED_CLASSES));
    end);

    -- **What a payload says it was made on** (`Constants.GAME_TYPE`), from the file this world
    -- loaded the way the TOC has the client load one.
    test("the game type is this client's, and a payload made here carries it", function()
        local expected = camelot and "camelot" or "standard";
        check(DebindPrivate.Constants.GAME_TYPE == expected,
            "GAME_TYPE " .. tostring(DebindPrivate.Constants.GAME_TYPE));
        _G.DebindVars = { dbver = DebindPrivate.Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = {} } } }, characters = {}, migrated = {} };
        DebindPrivate.InitDB();
        check(DebindStorage.BuildAccountPayload().gameType == expected, "payload");
    end);

    test("a class the client has is one a specialization condition can hold", function()
        check(DebindPrivate.ClassSpecMask(11) ~= 0, "Druid's mask is 0");
    end);

    -- **Offset 5 is named after the skyriding flyout, which camelot does not have and raises for.**
    -- The tooltip line and the condition menu both build these labels on first use, so a raise
    -- there stops both.
    test("every bonus bar offset has a label", function()
        for offset = 0, DebindPrivate.Constants.MAX_BONUSBAR_OFFSET do
            local ok, label = pcall(DebindPrivate.BonusBarLabel, offset);
            check(ok, "offset " .. offset .. " raised: " .. tostring(label));
            check(type(label) == "string" and label:find("^%[bonusbar:" .. offset .. "%]"),
                "offset " .. offset .. " is labelled " .. tostring(label));
        end
    end);

    -- **A flyout action can name a flyout this client does not have**: a string from retail carries
    -- its flyout ids across. Camelot raises for one where retail answers nothing, and the list, the
    -- icon and the button all ask.
    test("a flyout the client does not have answers nothing rather than raising", function()
        local ok, err = pcall(function()
            DebindPrivate.GetFlyoutNameAndIcon(229);
            DebindPrivate.GetFlyoutCastableSlots(229);
        end);
        check(ok, tostring(err));
    end);

    -- **A class of one specialization has no specialization layers to open.** Its one
    -- specialization is the class itself, so those two layers would hold what the class and
    -- character layers already hold. Retail's druid has four and opens all eleven.
    test("the layers a character can open skip specializations when the class has one", function()
        local expected = camelot and { 1, 2, 7 } or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
        check(Ids(DebindPrivate.GetOpenableLayerIDs()) == Ids(expected),
            "openable " .. Ids(DebindPrivate.GetOpenableLayerIDs()) .. ", expected " .. Ids(expected));
        local overridable = {};
        for i = 2, #expected do
            overridable[#overridable + 1] = expected[i];
        end
        check(Ids(DebindPrivate.GetOverridableLayerIDs()) == Ids(overridable),
            "overridable " .. Ids(DebindPrivate.GetOverridableLayerIDs()) .. ", expected " .. Ids(overridable));
    end);

    -- **A string lands where this client has a place for it** (2026-09-25, owner). A specialization
    -- layer of a class that has none here goes up to its class or character layer; a class nobody
    -- can play here has no place at all. Retail keeps every address it had.
    test("an arriving specialization layer goes up where the class has none", function()
        local Address = DebindStorage.ImportAddress;
        local scope, class, spec = Address("account", "MAGE", 2);
        check(scope == "class" and class == "MAGE" and spec == (camelot and 0 or 2),
            "class MAGE 2 -> " .. tostring(scope) .. "/" .. tostring(class) .. "/" .. tostring(spec));
        scope, class, spec = Address("1", DebindPrivate.Constants.PLAYER_CLASS, 3);
        check(scope == "character" and spec == (camelot and 0 or 3),
            "character 3 -> " .. tostring(scope) .. "/" .. tostring(spec));
    end);

    test("a class this client cannot play has no place, and says so", function()
        local scope, reason = DebindStorage.ImportAddress("account", "DEATHKNIGHT", 0);
        check(scope == nil and reason == "UNKNOWN_CLASS",
            "DEATHKNIGHT -> " .. tostring(scope) .. ", " .. tostring(reason));
    end);

    -- **A class cell is only placed or not**, so a name this client lacks is not a broken string.
    test("a string holding a class this client does not have is not refused", function()
        local payload = {
            v = DebindStorage.PAYLOAD_VERSION, dbver = DebindPrivate.Constants.DB_VERSION,
            layers = { account = { DEATHKNIGHT = { [0] = {
                { type = DebindPrivate.Constants.SPELL, value = 1 } } } } },
        };
        check(not DebindStorage.PayloadIsImpossible(payload), "refused as impossible");
    end);

    -- **Each client reads its own spell data** (`SpecSpells.lua`). The shim's character is a druid,
    -- Balance on retail and the one specialization on camelot. A class-name fallback used to hand
    -- camelot retail's Revive, which that client does not have.
    --
    -- The second dispel is the first one again on retail. On camelot it is Abolish Poison over Cure
    -- Poison, and with neither known the row shows Cure Poison, the one learned first.
    test("a druid resolves its own client's spells", function()
        shim.world.specIndex = 1;
        local SpecSpells = DebindPrivate.SpecSpells;
        local C = DebindPrivate.Constants;
        local want = camelot and { dispel = 2782, dispel2 = 8946, raidbuff = 1126, rez = 437138 }
            or { dispel = 2782, dispel2 = 2782, raidbuff = 1126, rez = 50769 };
        check(SpecSpells.SpellForType(C.DISPEL) == want.dispel,
            "dispel " .. tostring(SpecSpells.SpellForType(C.DISPEL)));
        check(SpecSpells.SpellForType(C.DISPEL2) == want.dispel2,
            "dispel 2 " .. tostring(SpecSpells.SpellForType(C.DISPEL2)));
        check(SpecSpells.SpellForType(C.RAIDBUFF) == want.raidbuff,
            "raid buff " .. tostring(SpecSpells.SpellForType(C.RAIDBUFF)));
        check(SpecSpells.SpellForType(C.RESURRECT) == want.rez,
            "resurrect " .. tostring(SpecSpells.SpellForType(C.RESURRECT)));
        shim.world.specIndex = nil;
    end);

    -- **A character is named by its whole name.** Camelot's first names repeat on one realm and
    -- even on one account; the surname is what tells those characters apart.
    local function WholeName()
        if (camelot) then
            return "Tester" .. _G.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
                .. "Surname";
        end
        return "Tester";
    end

    test("a character's stored identity carries its whole name", function()
        local guid = UnitGUID("player");
        local C = DebindPrivate.Constants;
        _G.DebindVars = {
            dbver = C.DB_VERSION,
            layers = { [guid] = { [C.PLAYER_CLASS] = { [0] = {
                { type = C.SPELL, value = 1, key = "F1", seq = 1 } } } } },
            characters = {}, migrated = {}, legacyNeeded = false,
        };
        DebindPrivate.InitDB();
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");
        DebindPrivate.CleanUpDB();
        local entry = _G.DebindVars.characters[guid];
        check(entry and entry.name == WholeName(),
            "stored " .. tostring(entry and entry.name) .. ", expected " .. WholeName());
    end);

    test("an entry made here carries the character's whole name", function()
        _G.DebindStorageVars = nil;
        _G.DebindVars = { dbver = DebindPrivate.Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = {
                { type = DebindPrivate.Constants.SPELL, value = 1, key = "F1", seq = 1 } } } } },
            characters = {}, migrated = {} };
        DebindPrivate.InitDB();
        local entry = DebindStorage.CreateEntry();
        check(entry.character == WholeName(),
            "made by " .. tostring(entry.character) .. ", expected " .. WholeName());
    end);

    -- **A layer label is one value.** It goes last into `GameTooltip_SetTitle`, `format` and
    -- `SetText`, so a second return from the client call behind it lands in the next parameter:
    -- camelot's `UnitName("player")` adds the surname and the tab tooltip took it for its colour.
    test("the tab and side tab labels are one value each", function()
        local DebindUI = DebindPrivate.DebindUI;
        for tab = 1, 2 do
            local n = select("#", DebindUI.GetTabLabel(tab));
            check(n == 1, "tab " .. tab .. " answers " .. n .. " values");
        end
        for sideTab = 1, 3 do
            local n = select("#", DebindUI.GetSideTabLabel(sideTab));
            check(n == 1, "side tab " .. sideTab .. " answers " .. n .. " values");
        end
    end);

    -- **A character has one class, so its layer below the specializations is that class** and sits
    -- on the class side tab. A label reading "General" there names a side tab the account tab has
    -- too, and a reader following it lands in the account-wide layer.
    test("the character's own layer is its class", function()
        local DebindUI = DebindPrivate.DebindUI;
        local tab, sideTab = DebindUI.GetLayerTabs(7);
        check(tab == 2 and sideTab == 2, "layer 7 sits at " .. tostring(tab) .. ", " .. tostring(sideTab));
        -- The side half: the shim's locale answers "ORDER_LAYER_LABEL" for the whole label.
        local mine = select(3, DebindUI.GetColoredLayerLabel(7));
        local class = UnitClass("player");
        check(mine and mine:find(class, 1, true), "own side half " .. tostring(mine) .. ", expected " .. class);
        local theirs = select(3, DebindUI.GetColoredLayerLabel(7, "MAGE", "Bob"));
        local mage = DebindPrivate.Constants.CLASS_NAMES.MAGE;
        check(theirs and theirs:find(mage, 1, true), "named side half " .. tostring(theirs) .. ", expected " .. mage);
    end);

    -- **A layer is named by what sets it apart and nothing more**: the account-wide layer is
    -- General, an account class layer its class, a character layer its character. "Account" is a
    -- tab's word and is left out; a name with no character in it is the account's.
    test("a layer below the specializations is one word", function()
        local DebindUI = DebindPrivate.DebindUI;
        local LLL = DebindPrivate.L;
        local mage = DebindPrivate.Constants.CLASS_NAMES.MAGE;
        local cases = {
            { DebindUI.GetLayerLabel(1), LLL["GENERAL"] },
            { DebindUI.GetLayerLabel(2), (UnitClass("player")) },
            { DebindUI.GetLayerLabel(2, "MAGE"), mage },
            { DebindUI.GetLayerLabel(7), WholeName() },
            { DebindUI.GetLayerLabel(7, "MAGE", "Bob"), "Bob" },
        };
        for i, case in ipairs(cases) do
            check(case[1] == case[2], "case " .. i .. ": " .. tostring(case[1]) .. ", expected " .. case[2]);
        end
    end);

    -- **A spell's subtext rides into its cast name to tell same-named spells apart**, which retail
    -- needs for a specialization's own version of a shapeshift. On camelot the subtext is the rank
    -- ("Rank 1", measured on 69977), and a cast name carrying it keeps casting that rank after the
    -- next one is learned; the bare name casts the highest known.
    test("a cast name keeps the subtext only where it tells spells apart", function()
        local name = DebindPrivate.ComposeSpellCastName("Healing Touch", "Rank 1");
        local expected = camelot and "Healing Touch" or "Healing Touch(Rank 1)";
        check(name == expected, "cast name " .. tostring(name) .. ", expected " .. expected);
    end);

    -- **The class tab's icon is the class line's.** Retail's book keeps that at index 2; camelot's
    -- index 2 is a talent tree (Restoration for a druid) and the class line is asked for apart.
    -- Retail's shim book holds one line, so this is asked of camelot alone.
    if (camelot) then
        test("the class line is the class's, not the book's second line", function()
            local line = DebindPrivate.Client.ClassSkillLine();
            check(line and line.name == "Druid", "class line " .. tostring(line and line.name));
        end);
    end

    -- **Each rank is its own book item and its own id.** With every rank listed, the spell list
    -- stands one row per rank, and a cast name without its rank casts the highest anyway. The
    -- client's own book hides the lower ranks unless `ShowAllSpellRanks` is on, and the list
    -- follows the same setting.
    local function SpellRowIds()
        local ActionCatalog = DebindPrivate.ActionCatalog;
        local ids = {};
        for _, category in ipairs(ActionCatalog.GetCategories()) do
            if (category.source == "spellbook") then
                ActionCatalog.Invalidate(category.source);
                for _, entry in ipairs(ActionCatalog.GetEntries(category)) do
                    if (entry.value ~= nil) then
                        ids[entry.value] = true;
                    end
                end
            end
        end
        return ids;
    end

    local function TwoRanks()
        shim.world.spells[5185] = { name = "Healing Touch", subtext = "Rank 1" };
        shim.world.spells[5186] = { name = "Healing Touch", subtext = "Rank 2" };
        shim.world.spellbook[5185] = true;
        shim.world.spellbook[5186] = true;
        shim.world.lowRanks[5185] = true;
    end

    test("the spell list holds one row per spell, not per rank", function()
        TwoRanks();
        local ids = SpellRowIds();
        check(ids[5186], "the highest rank has no row");
        if (camelot) then
            check(not ids[5185], "the lower rank has a row of its own");
        else
            check(ids[5185], "a spell the client does not call a low rank lost its row");
        end
    end);

    -- **Retail's picker has no Dispel 2** (2026-09-29, owner): there it casts Dispel's spell under
    -- Dispel's name and description, so the reader would see one row twice. Camelot's two dispels
    -- remove different debuffs and both are offered.
    test("the spell list offers the second dispel only where it differs", function()
        local C = DebindPrivate.Constants;
        local ActionCatalog = DebindPrivate.ActionCatalog;
        local offered = {};
        for _, category in ipairs(ActionCatalog.GetCategories()) do
            if (category.source == "spellbook") then
                ActionCatalog.Invalidate(category.source);
                for _, entry in ipairs(ActionCatalog.GetEntries(category)) do
                    if (C.SPEC_RESOLVED_TYPES[entry.type]) then
                        offered[#offered + 1] = entry.type;
                    end
                end
            end
        end
        table.sort(offered);
        local expected = camelot and "dispel,dispel2,raidbuff,resurrect" or "dispel,raidbuff,resurrect";
        check(table.concat(offered, ",") == expected, "offered " .. table.concat(offered, ","));
    end);

    test("with every rank shown in the book, every rank has a row", function()
        TwoRanks();
        shim.world.cvars.ShowAllSpellRanks = true;
        local ids = SpellRowIds();
        check(ids[5185] and ids[5186], "a rank lost its row");
    end);

    -- **A rank can also be pinned, per action** (2026-09-24, owner): classic players cast a lower
    -- rank on purpose. The stored id cannot say it on its own, since the highest rank on the day it
    -- was picked is a lower one after the next is learned, so `pinRank` says it.
    local ME = "Player-1-CLIENTRANK";

    local function Bind(actions)
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = DebindPrivate.Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [ME] = { switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    local function CastOn(key)
        local records = require("castmod").without(DebindPrivate.Constants, DebindPrivate.KeyMap[key]);
        return records and records[1] and records[1].castSpell;
    end

    test("a pinned rank casts that rank, an unpinned action the highest", function()
        shim.world.spells[5185] = { name = "Healing Touch", subtext = "Rank 1" };
        shim.world.spellbook[5185] = true;
        local SPELL = DebindPrivate.Constants.SPELL;
        Bind({
            { type = SPELL, value = 5185, key = "F1", seq = 1, pinRank = true },
            { type = SPELL, value = 5185, key = "F2", seq = 1 },
        });
        check(CastOn("F1") == "Healing Touch(Rank 1)", "pinned casts " .. tostring(CastOn("F1")));
        local highest = camelot and "Healing Touch" or "Healing Touch(Rank 1)";
        check(CastOn("F2") == highest, "unpinned casts " .. tostring(CastOn("F2")));
    end);

    -- **The name a row and a tooltip show is the name the button casts by**, so a held rank is on
    -- screen without a line of its own.
    test("a pinned rank shows in the action's name", function()
        shim.world.spells[5185] = { name = "Healing Touch", subtext = "Rank 1" };
        local SPELL = DebindPrivate.Constants.SPELL;
        local shown = select(3, DebindPrivate.DebindUI.NameAndIconForAction(
            { type = SPELL, value = 5185, pinRank = true }));
        local plain = select(3, DebindPrivate.DebindUI.NameAndIconForAction({ type = SPELL, value = 5185 }));
        check(tostring(shown):find("Healing Touch(Rank 1)", 1, true), "pinned shows " .. tostring(shown));
        check(not tostring(plain):find("Rank", 1, true), "unpinned shows " .. tostring(plain));
    end);

    -- The pin belongs to the spell it was set on. Putting another spell in the action's place
    -- keeps everything else about the action, and a pin carried across would pin the new spell to
    -- whatever rank it happens to be stored at.
    test("putting another spell in an action's place drops the pin", function()
        local action = { type = DebindPrivate.Constants.SPELL, value = 5185, pinRank = true };
        DebindPrivate.SetActionEntry(action, DebindPrivate.Constants.SPELL, 774, "Rejuvenation", nil, nil);
        check(action.pinRank == nil, "the pin stayed on the new spell");
    end);

    -- The ranks the rank menu offers: every book item under the spell's name, in book order.
    test("a spell's ranks are the book's items under its name", function()
        TwoRanks();
        shim.world.spells[774] = { name = "Rejuvenation", subtext = "Rank 1" };
        shim.world.spellbook[774] = true;
        local ranks = DebindPrivate.Client.SpellRanks(5186);
        local got = {};
        for i = 1, #ranks do
            got[i] = ranks[i].id .. "=" .. tostring(ranks[i].subtext);
        end
        local expected = camelot and "5185=Rank 1,5186=Rank 2" or "";
        check(table.concat(got, ",") == expected, "ranks " .. table.concat(got, ","));
    end);

    if (camelot) then
        -- **A lower rank's row is there only because the reader asked the book for every rank**,
        -- and picking it is picking that rank.
        test("a lower rank picked from the list comes pinned", function()
            TwoRanks();
            shim.world.cvars.ShowAllSpellRanks = true;
            local ActionCatalog = DebindPrivate.ActionCatalog;
            local pinned = {};
            for _, category in ipairs(ActionCatalog.GetCategories()) do
                if (category.source == "spellbook") then
                    ActionCatalog.Invalidate(category.source);
                    for _, entry in ipairs(ActionCatalog.GetEntries(category)) do
                        if (entry.value ~= nil) then
                            pinned[entry.value] = entry.props and entry.props.pinRank or false;
                        end
                    end
                end
            end
            check(pinned[5185] == true, "the lower rank's row is not pinned");
            check(pinned[5186] == false, "the highest rank's row is pinned");
        end);
    end

    -- **The tri-state checkbox's middle mark is an atlas camelot does not have** (`common-icon-minus`,
    -- 69977), and a missing atlas is a mark that draws nothing. The first of the names the client
    -- has is the one drawn.
    test("an atlas the client lacks gives way to one it has", function()
        local name = DebindPrivate.Client.FirstAtlas("common-icon-minus", "common-button-list-minus");
        local expected = camelot and "common-button-list-minus" or "common-icon-minus";
        check(name == expected, "drawn with " .. tostring(name));
    end);

    return T;
end
