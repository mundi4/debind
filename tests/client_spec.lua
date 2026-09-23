-- **What the client layer hands the rest of the addon, on each client.** `Debind/Client/` is where
-- the two clients are asked for the same thing in different ways (`preparing-the-code-for-camelot.md`
-- §3), so every case here runs twice: once in the retail world and once in the camelot one, which
-- `run.lua` picks with the spec entry's `client`. A case states what both clients must end up with,
-- and the world decides what it takes to get there.

return function(DebindPrivate)
    local shim = require("wow_shim");
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

    test("with every rank shown in the book, every rank has a row", function()
        TwoRanks();
        shim.world.cvars.ShowAllSpellRanks = true;
        local ids = SpellRowIds();
        check(ids[5185] and ids[5186], "a rank lost its row");
    end);

    return T;
end
