-- **Unlearned spells on camelot** (`listing-unlearned-spells-on-forever.md`): what a class
-- trainer's window is read into, and how the spell list's groups take that together with the
-- book and the ids written in `UnlearnedSpells_Camelot.lua`. Run in the camelot world, whose
-- character is a druid.

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

    local function describe(t)
        local ids = {};
        for id in pairs(t or {}) do
            ids[#ids + 1] = id;
        end
        table.sort(ids);
        local parts = {};
        for _, id in ipairs(ids) do
            parts[#parts + 1] = id .. "=" .. tostring(t[id]);
        end
        return "{" .. table.concat(parts, ",") .. "}";
    end

    local WRATH_1, WRATH_2 = 5176, 5177;
    local TOUCH_1, TOUCH_2, TOUCH_3 = 5185, 5186, 5187;
    local THORNS_1, THORNS_2 = 467, 782;
    local MARK_1, ROAR, NATURES_GRACE, CURE_POISON = 1126, 99, 16880, 8946;

    local spells = shim.world.spells;
    spells[WRATH_1] = { name = "Wrath", iconID = 1 };
    spells[WRATH_2] = { name = "Wrath", iconID = 1 };
    spells[TOUCH_1] = { name = "Healing Touch", iconID = 2 };
    spells[TOUCH_2] = { name = "Healing Touch", iconID = 2 };
    spells[TOUCH_3] = { name = "Healing Touch", iconID = 2 };
    spells[THORNS_1] = { name = "Thorns", iconID = 3 };
    spells[THORNS_2] = { name = "Thorns", iconID = 3 };
    spells[MARK_1] = { name = "Mark of the Wild", iconID = 4 };
    spells[ROAR] = { name = "Demoralizing Roar", iconID = 5 };
    spells[NATURES_GRACE] = { name = "Nature's Grace", iconID = 6, passive = true };
    -- A weapon skill: passive, though its trainer row has no "Passive" subtext (measured 2026-10-01).
    local STAVES = 227;
    spells[STAVES] = { name = "Staves", iconID = 12, passive = true };
    spells[CURE_POISON] = { name = "Cure Poison", iconID = 7 };

    -- The generated class lists, set by the spec rather than the shipped ones: a row from those would
    -- depend on which of their ids this world happens to name.
    local REGROWTH = 8936;
    spells[REGROWTH] = { name = "Regrowth", iconID = 10 };
    -- A higher rank of a talent's spell, the way a trainer sells one (Counterattack's second at 30).
    local SWIFTMEND_2 = 90001;
    spells[SWIFTMEND_2] = { name = "Swiftmend", iconID = 8 };
    -- A string in a level's place names where the spell comes from (2026-10-01, owner).
    local ELSEWHERE = 90002;
    spells[ELSEWHERE] = { name = "Elsewhere Spell", iconID = 11 };
    -- A pet's, in its class's list with where it comes from (2026-10-01, owner: a warlock's grimoires).
    local PET_SPELL = 90003;
    spells[PET_SPELL] = { name = "Pet Spell", iconID = 14 };
    DebindPrivate.CamelotClassSpells = {
        DRUID = { [REGROWTH] = 12, [SWIFTMEND_2] = 30, [ELSEWHERE] = "quest", [PET_SPELL] = "pet" },
    };
    -- A profession's spell, offered to every class (2026-10-01, owner).
    local FISHING = 7620;
    spells[FISHING] = { name = "Fishing", iconID = 13 };
    DebindPrivate.CamelotProfessionSpells = { [FISHING] = "profession" };

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

    local function stored()
        local store = _G.DebindVars.trainerSpells;
        return store and store.DRUID;
    end

    -- **A learned row reports level 0** (probe, 70009), so read it would win the merge over the
    -- rank still to be bought. A passive one is not something a key can cast.
    test("a class trainer's rows are kept by id with their level, learned and passive ones not",
        function()
            shim.world.trainerServices = {
                { id = MARK_1, serviceType = "used", level = 0, subText = "Rank 1" },
                { id = WRATH_2, serviceType = "available", level = 6, subText = "Rank 2" },
                { id = TOUCH_2, serviceType = "unavailable", level = 8, subText = "Rank 2" },
                { id = TOUCH_3, serviceType = "unavailable", level = 14, subText = "Rank 3" },
                { id = NATURES_GRACE, serviceType = "unavailable", level = 12, subText = "Passive" },
                { id = STAVES, serviceType = "available", level = 0, subText = "" },
            };
            check(frames.fireEvent("TRAINER_SHOW") > 0, "nothing is listening for TRAINER_SHOW");
            local want = describe({ [WRATH_2] = 6, [TOUCH_2] = 8, [TOUCH_3] = 14 });
            check(describe(stored()) == want, "stored " .. describe(stored()) .. ", expected " .. want);
        end);

    -- **The reader's filters are left alone**, so each read is a part of the list and what an
    -- earlier one saw has to stay.
    test("a later read adds to what is kept and takes nothing away", function()
        shim.world.trainerServices = {
            { id = ROAR, serviceType = "unavailable", level = 10, subText = "Rank 1" },
        };
        frames.fireEvent("TRAINER_UPDATE");
        local want = describe({ [WRATH_2] = 6, [TOUCH_2] = 8, [TOUCH_3] = 14, [ROAR] = 10 });
        check(describe(stored()) == want, "stored " .. describe(stored()) .. ", expected " .. want);
    end);

    test("a pet trainer is not read", function()
        local before = describe(stored());
        shim.world.trainerType = Enum.TrainerType.Pet;
        shim.world.trainerServices = {
            { id = THORNS_1, serviceType = "unavailable", level = 6, subText = "Rank 1" },
        };
        frames.fireEvent("TRAINER_SHOW");
        shim.world.trainerType = nil;
        check(describe(stored()) == before, "stored " .. describe(stored()) .. ", expected " .. before);
    end);

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
    test("the groups are the class, General, Pet, Professions and Others", function()
        withBook(function()
            local _, groups = groupedRows();
            local want = "Druid,General," .. DebindPrivate.L["PET"] .. ",Professions,"
                .. DebindPrivate.L["SPELL_PICKER_GROUP_OTHERS"];
            check(groups == want, "groups " .. groups .. ", expected " .. want);
        end);
    end);

    -- **One row per name, under the rank the character reaches first**, and nothing the book already
    -- lists under that name. The ids written in the file and the talent tree's spells join what the
    -- trainer gave. Level above the character's is the subtitle, the way retail's unlearned spells
    -- show it; a talent's spell has no level and says where it comes from instead, after the rest,
    -- even where another source sells a higher rank of it with one (2026-10-01, owner). A passive
    -- talent is not offered. The learned rows come first, by name across the talent trees' lines.
    test("the class group: learned by name, then every source merged, one row per name", function()
        _G.DebindVars.trainerSpells.DRUID[THORNS_1] = 6;
        _G.DebindVars.trainerSpells.DRUID[THORNS_2] = 14;
        -- The same id with a level from another source: where it comes from still wins.
        _G.DebindVars.trainerSpells.DRUID[ELSEWHERE] = 5;
        withBook(function()
            local byGroup = groupedRows();
            local want = "Healing Touch:5185:nil:learned | Mark of the Wild:1126:nil:learned"
                .. " | Thorns:467:nil | Wrath:5177:nil | Demoralizing Roar:99:nil"
                .. " | Regrowth:8936:Level 12 | Cure Poison:8946:Level 14 | Elsewhere Spell:90002:nil"
                .. " | Swiftmend:18562:Talent";
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

    test("a spell leaves the unlearned rows once the book holds it", function()
        shim.world.spellbook[WRATH_1] = true;
        local byGroup = groupedRows();
        shim.world.spellbook[WRATH_1] = nil;
        for _, row in ipairs(byGroup.Druid) do
            check(not (row.name == "Wrath" and row.isUnlearned), "Wrath is still unlearned: "
                .. rowText(byGroup.Druid));
        end
    end);

    return T;
end
