-- **The Unlearned group on camelot** (`listing-unlearned-spells-on-forever.md`): what a class
-- trainer's window is read into, and what the spell list makes of that together with the ids
-- written in `UnlearnedSpells_Camelot.lua`. Run in the camelot world, whose character is a druid.

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
    spells[CURE_POISON] = { name = "Cure Poison", iconID = 7 };

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

    --- The rows under the Unlearned heading, and whether that group stands between the book's and
    --- Others.
    local function unlearnedRows()
        ActionCatalog.Invalidate("spellbook");
        local rows, groups = {}, {};
        for _, entry in ipairs(ActionCatalog.GetEntries(spellCategory())) do
            if (groups[#groups] ~= entry.group) then
                groups[#groups + 1] = entry.group;
            end
            if (entry.group == PROFESSIONS_CATEGORY_UNLEARNED) then
                rows[#rows + 1] = entry;
            end
        end
        return rows, table.concat(groups, ",");
    end

    local function rowText(rows)
        local parts = {};
        for _, row in ipairs(rows) do
            parts[#parts + 1] = row.name .. ":" .. tostring(row.value) .. ":" .. tostring(row.subName)
                .. (row.isUnlearned and "" or ":learned?");
        end
        return table.concat(parts, " | ");
    end

    -- **One row per name, under the rank the character reaches first**, and nothing the book already
    -- lists under that name. The ids written in the file and the talent tree's spells join what the
    -- trainer gave. Level above the character's is the subtitle, the way retail's unlearned spells
    -- show it; a talent's spell has no level and says where it comes from instead, after the rest
    -- (2026-10-01, owner). A passive talent is not offered.
    test("the list merges every source, one row per name, without what the book holds", function()
        _G.DebindVars.trainerSpells.DRUID[THORNS_1] = 6;
        _G.DebindVars.trainerSpells.DRUID[THORNS_2] = 14;
        shim.world.spellbook[TOUCH_1] = true;
        local unitLevel = _G.UnitLevel;
        _G.UnitLevel = function() return 10; end
        local rows, groups = unlearnedRows();
        _G.UnitLevel = unitLevel;
        shim.world.spellbook[TOUCH_1] = nil;

        local want = "Thorns:467:nil | Wrath:5177:nil | Demoralizing Roar:99:nil"
            .. " | Cure Poison:8946:Level 14 | Swiftmend:18562:Talent";
        check(rowText(rows) == want, "rows " .. rowText(rows) .. "\n  expected " .. want);
        local wantGroups = "General,Unlearned," .. DebindPrivate.L["SPELL_PICKER_GROUP_OTHERS"];
        check(groups == wantGroups, "groups " .. groups .. ", expected " .. wantGroups);
    end);

    -- **The heading's tooltip says how to fill the group**, so a character who has not talked to a
    -- trainer still gets the heading (2026-09-30, owner). A search drops it: nothing under it matches.
    test("the group stands with its tooltip when no spell is in it, and not in a search", function()
        local trainerSpells = _G.DebindVars.trainerSpells;
        _G.DebindVars.trainerSpells = nil;
        -- Swiftmend in the book is its talent taken, which takes it out of the group.
        shim.world.spellbook[CURE_POISON] = true;
        shim.world.spellbook[SWIFTMEND] = true;
        ActionCatalog.Invalidate("spellbook");
        local entries = ActionCatalog.GetEntries(spellCategory());
        shim.world.spellbook[CURE_POISON] = nil;
        shim.world.spellbook[SWIFTMEND] = nil;
        _G.DebindVars.trainerSpells = trainerSpells;

        local marker;
        for _, entry in ipairs(entries) do
            if (entry.group == PROFESSIONS_CATEGORY_UNLEARNED) then
                check(marker == nil and entry.isGroupOnly, "a row is in the group: " .. tostring(entry.name));
                marker = entry;
            end
        end
        check(marker, "no Unlearned group");
        local want = format(DebindPrivate.L["SPELL_PICKER_GROUP_UNLEARNED_DESC"], "Class Trainer",
            "Settings", "Filters", "Unavailable");
        check(marker.groupTooltip == want, "tooltip " .. tostring(marker.groupTooltip));

        local function kept(options)
            for _, entry in ipairs(ActionCatalog.Filter(entries, options)) do
                if (entry == marker) then
                    return true;
                end
            end
            return false;
        end
        check(kept({ includeOffSpec = true }), "the empty group was filtered out");
        check(not kept({ search = "cure", includeOffSpec = true }), "the empty group stood in a search");
    end);

    test("every row carries the heading's tooltip", function()
        local rows = unlearnedRows();
        check(#rows > 0, "no rows");
        for _, row in ipairs(rows) do
            check(row.groupTooltip ~= nil and not row.isGroupOnly, row.name .. " has no tooltip");
        end
    end);

    test("a spell leaves the group once the book holds it", function()
        shim.world.spellbook[WRATH_1] = true;
        local rows = unlearnedRows();
        shim.world.spellbook[WRATH_1] = nil;
        for _, row in ipairs(rows) do
            check(row.name ~= "Wrath", "Wrath is still listed: " .. rowText(rows));
        end
    end);

    return T;
end
