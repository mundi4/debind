-- **Unlearned spells on camelot** (`listing-unlearned-spells-on-forever.md`): how the spell list's
-- groups take the generated table and the talent tree together with the book. Run in the camelot
-- world, whose character is a druid.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local ActionCatalog = DebindPrivate.ActionCatalog;
    local shim = require("wow_shim");
    local frames = require("wow_frames");

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

    local WRATH_1, WRATH_2 = 5176, 5177;
    local TOUCH_1, MARK_1 = 5185, 1126;

    local spells = shim.world.spells;
    spells[WRATH_1] = { name = "Wrath", iconID = 1 };
    spells[WRATH_2] = { name = "Wrath", iconID = 1 };
    spells[TOUCH_1] = { name = "Healing Touch", iconID = 2 };
    spells[MARK_1] = { name = "Mark of the Wild", iconID = 4 };
    -- A druid's spell the client names and the table below does not carry: no row.
    local CURE_POISON = 8946;
    spells[CURE_POISON] = { name = "Cure Poison", iconID = 7 };

    -- The generated class lists, set by the spec rather than the shipped ones: a row from those would
    -- depend on which of their ids this world happens to name.
    local REGROWTH = 8936;
    spells[REGROWTH] = { name = "Regrowth", iconID = 10 };
    -- A higher rank of a talent's spell, listed with a level (Counterattack's second at 30).
    local SWIFTMEND_2 = 90001;
    spells[SWIFTMEND_2] = { name = "Swiftmend", iconID = 8 };
    -- A string in a level's place names where the spell comes from (2026-10-01, owner).
    local ELSEWHERE = 90002;
    spells[ELSEWHERE] = { name = "Elsewhere Spell", iconID = 11 };
    -- A pet's, in its class's list with where it comes from (2026-10-01, owner: a warlock's grimoires).
    local PET_SPELL = 90003;
    spells[PET_SPELL] = { name = "Pet Spell", iconID = 14 };
    -- A profession's spell, offered to every class (2026-10-01, owner).
    local FISHING = 7620;
    spells[FISHING] = { name = "Fishing", iconID = 13 };
    -- Neither offered: a higher rank stands under its first rank's row, and a mage's spell is not a
    -- druid's.
    local REGROWTH_2, FROSTBOLT = 8938, 116;
    spells[REGROWTH_2] = { name = "Regrowth", iconID = 10 };
    spells[FROSTBOLT] = { name = "Frostbolt", iconID = 19 };
    -- The generated table's shape (`keeping-a-pinned-rank-apart-from-the-spell.md` §4): a first rank
    -- holds where it comes from and its classes, a higher rank its first rank's id.
    local DRUID, MAGE = { DRUID = true }, { MAGE = true };
    DebindPrivate.CamelotSpells = {
        [REGROWTH] = { 12, classes = DRUID },
        [REGROWTH_2] = REGROWTH,
        [SWIFTMEND_2] = { 30, classes = DRUID },
        [ELSEWHERE] = { "quest", classes = DRUID },
        [PET_SPELL] = { "pet", classes = DRUID },
        [FISHING] = { "profession" },
        [FROSTBOLT] = { 4, classes = MAGE },
    };

    -- What the book holds: one spell on General, two class spells on two talent trees' lines in the
    -- reverse of name order, and a profession's.
    local HEARTHSTONE, FIND_HERBS, HERBALISM = 8690, 2383, 2366;
    spells[HEARTHSTONE] = { name = "Hearthstone", iconID = 15 };
    spells[FIND_HERBS] = { name = "Find Herbs", iconID = 16 };
    spells[HERBALISM] = { name = "Herbalism", iconID = 17, subtext = "Apprentice" };
    shim.world.bookLines[MARK_1] = 2;
    shim.world.bookLines[TOUCH_1] = 3;

    -- The talent tree, untaken: one spell a key can cast and one passive (probe, 70009, a druid).
    -- Stood up before the login, whose rebuild walks it once for the specialization (`Spells.lua`).
    local SWIFTMEND, MOONGLOW = 18562, 16845;
    spells[SWIFTMEND] = { name = "Swiftmend", iconID = 8 };
    spells[MOONGLOW] = { name = "Moonglow", iconID = 9, passive = true };
    shim.world.traits = {
        configID = 7,
        treeIDs = { 1 },
        trees = { [1] = { 1, 2 } },
        nodes = {
            [1] = { entryIDs = { 11 }, entryIDsWithCommittedRanks = {} },
            [2] = { entryIDs = { 12 }, entryIDsWithCommittedRanks = {} },
        },
        entries = { [11] = { definitionID = 21 }, [12] = { definitionID = 22 } },
        definitions = { [21] = { spellID = SWIFTMEND }, [22] = { spellID = MOONGLOW } },
    };

    _G.DebindVars = { dbver = Constants.DB_VERSION, layers = {}, characters = {}, migrated = {},
        legacyNeeded = false };
    DebindPrivate.InitDB();
    DebindPrivate.ShowMigrationDialogIfPending =
        DebindPrivate.ShowMigrationDialogIfPending or function() end;
    frames.fireEvent("PLAYER_LOGIN");

    local function spellCategory()
        for _, category in ipairs(ActionCatalog.GetCategories()) do
            if (category.key == "spell") then
                return category;
            end
        end
    end

    --- The spell list's rows by heading, and the headings in order.
    local function groupedRows()
        ActionCatalog.Invalidate("spellbook");
        local byGroup, groups = {}, {};
        for _, entry in ipairs(ActionCatalog.GetEntries(spellCategory())) do
            if (groups[#groups] ~= entry.group) then
                groups[#groups + 1] = entry.group;
                byGroup[entry.group] = {};
            end
            table.insert(byGroup[entry.group], entry);
        end
        return byGroup, table.concat(groups, ",");
    end

    local function rowText(rows)
        local parts = {};
        for _, row in ipairs(rows or {}) do
            parts[#parts + 1] = row.name .. ":" .. tostring(row.value) .. ":" .. tostring(row.subName)
                .. (row.isUnlearned and "" or ":learned");
        end
        return table.concat(parts, " | ");
    end

    --- The book `groupedRows` reads in the tests below, stood up and taken down around `fn`.
    local function withBook(fn)
        for _, id in ipairs({ HEARTHSTONE, MARK_1, TOUCH_1 }) do
            shim.world.spellbook[id] = true;
        end
        shim.world.professions[1] = { name = "Herbalism", spells = { HERBALISM, FIND_HERBS } };
        local unitLevel = _G.UnitLevel;
        _G.UnitLevel = function() return 10; end
        local ok, err = pcall(fn);
        _G.UnitLevel = unitLevel;
        shim.world.professions[1] = nil;
        for _, id in ipairs({ HEARTHSTONE, MARK_1, TOUCH_1 }) do
            shim.world.spellbook[id] = nil;
        end
        if (not ok) then
            error(err, 0);
        end
    end

    -- **The class is one group under its name, and General, Pet and Professions follow** (2026-10-01,
    -- owner). Each holds what is learned, then what is not; no group of unlearned spells of its own.
    -- The spells added by id close the list, their group standing on its Add row when empty.
    test("the groups are the class, General, Pet, Professions, Others and the added spells", function()
        withBook(function()
            local _, groups = groupedRows();
            local want = "Druid,General," .. DebindPrivate.L["PET"] .. ",Professions,"
                .. DebindPrivate.L["SPELL_PICKER_GROUP_OTHERS"] .. ","
                .. DebindPrivate.L["SPELL_PICKER_GROUP_USER"];
            check(groups == want, "groups " .. groups .. ", expected " .. want);
        end);
    end);

    -- **One row per name, by name**: the generated table's first ranks and the talent tree's spells,
    -- nothing else. Level above the character's is the subtitle, the way retail's unlearned spells
    -- show it; a talent's spell has no level and says where it comes from instead, even where the
    -- table lists a higher rank of it with one (2026-10-01, owner). A passive talent is not offered.
    -- The learned rows come first, by name across the talent trees' lines.
    test("the class group: learned by name, then the table and the talent tree, one row per name", function()
        withBook(function()
            local byGroup = groupedRows();
            local want = "Healing Touch:5185:nil:learned | Mark of the Wild:1126:nil:learned"
                .. " | Elsewhere Spell:90002:nil | Regrowth:8936:Level 12 | Swiftmend:18562:Talent";
            check(rowText(byGroup.Druid) == want, "rows " .. rowText(byGroup.Druid) .. "\n  expected " .. want);
        end);
    end);

    -- A pet's spell comes from the class's own list, said by "pet" in its level's place; the
    -- professions' ones have the heading to say where they come from, and no subtitle, learned or
    -- not: a profession's rank ("Apprentice") says nothing a key needs (2026-10-01, owner).
    test("pet and profession spells join their own groups, after what is learned", function()
        withBook(function()
            local byGroup = groupedRows();
            local want = "Pet Spell:90003:nil";
            local pet = byGroup[DebindPrivate.L["PET"]];
            check(rowText(pet) == want, "pet " .. rowText(pet) .. ", expected " .. want);
            want = "Herbalism:2366:nil:learned | Find Herbs:2383:nil:learned | Fishing:7620:nil";
            check(rowText(byGroup.Professions) == want,
                "professions " .. rowText(byGroup.Professions) .. ", expected " .. want);
        end);
    end);

    -- **A row picked from the list adds the highest rank known**, so a rank under it would say that
    -- rank is what gets added, and one name is one row whatever the book shows (2026-10-01, owner).
    -- A subtitle that is not a rank stays.
    test("a spell's ranks are one row with no rank under it, and a racial keeps its subtitle", function()
        local STONEFORM = 20594;
        spells[STONEFORM] = { name = "Stoneform", iconID = 18, subtext = "Racial" };
        spells[WRATH_1].subtext, spells[WRATH_2].subtext = "Rank 1", "Rank 2";
        shim.world.spellbook[STONEFORM] = true;
        shim.world.spellbook[WRATH_1], shim.world.spellbook[WRATH_2] = true, true;
        shim.world.bookLines[WRATH_1], shim.world.bookLines[WRATH_2] = 2, 2;
        shim.world.lowRanks[WRATH_1] = true;
        shim.world.cvars.ShowAllSpellRanks = "1";
        local ok, err = pcall(function()
            local byGroup = groupedRows();
            local wrath = {};
            for _, row in ipairs(byGroup.Druid) do
                if (row.name == "Wrath") then
                    wrath[#wrath + 1] = row;
                end
            end
            local want = "Wrath:5177:nil:learned";
            check(rowText(wrath) == want, "wrath " .. rowText(wrath) .. ", expected " .. want);
            want = "Stoneform:20594:Racial:learned";
            check(rowText(byGroup.General) == want, "general " .. rowText(byGroup.General) .. ", expected " .. want);
        end);
        shim.world.cvars.ShowAllSpellRanks = nil;
        shim.world.lowRanks[WRATH_1] = nil;
        shim.world.bookLines[WRATH_1], shim.world.bookLines[WRATH_2] = nil, nil;
        shim.world.spellbook[WRATH_1], shim.world.spellbook[WRATH_2] = nil, nil;
        shim.world.spellbook[STONEFORM] = nil;
        spells[WRATH_1].subtext, spells[WRATH_2].subtext = nil, nil;
        if (not ok) then
            error(err, 0);
        end
    end);

    -- The book holds a higher rank than the table's id, so only the name can tell.
    test("a spell leaves the unlearned rows once the book holds any rank of it", function()
        shim.world.spellbook[REGROWTH_2], shim.world.bookLines[REGROWTH_2] = true, 2;
        local byGroup = groupedRows();
        shim.world.spellbook[REGROWTH_2], shim.world.bookLines[REGROWTH_2] = nil, nil;
        local want = "Regrowth:8938:nil:learned";
        local regrowth = {};
        for _, row in ipairs(byGroup.Druid) do
            if (row.name == "Regrowth") then
                regrowth[#regrowth + 1] = row;
            end
        end
        check(rowText(regrowth) == want, "regrowth " .. rowText(regrowth) .. ", expected " .. want);
    end);

    return T;
end
