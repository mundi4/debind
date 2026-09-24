-- **A `SPELL` action whose value is a name** (`importing-clique-profiles.md` §4).
--
-- Clique stores a spell by name only, and the index that turns a name into an id stands for one
-- character's one specialization, so the name is what the action keeps and every rebuild resolves
-- it again. Resolved, it has to come out exactly as an action holding that id does; unresolved, the
-- name goes on the button as it is.
--
-- **`C_SpellBook` in the shim takes an id only**, the way the client documents it. Before that the
-- shim answered a name with nil, and a name reaching `FindBaseSpellByID` went unnoticed here.

return function(DebindPrivate, DebindStorage)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local castmod = require("castmod");

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

    local SPELL = Constants.SPELL;
    local ME = "Player-1-SPELLNAME";
    local INCARNATION = "Incarnation: Chosen of Elune";

    --- Regrowth has one id in the index. Incarnation has two, of which only the second climbs, to
    --- Celestial Alignment -- the second, so taking the first id under the name reads differently
    --- from taking the root. Starsurge is a spell the client can name but this specialization's book
    --- does not hold, which is what another specialization's spell looks like.
    ---
    --- **The index is kept per specialization index** (`Spells.lua`'s `EnsureWalked`), so a test
    --- that changes the book changes `specIndex` with it.
    local function installWorld(specIndex)
        local world = shim.world;
        for _, field in ipairs({ "spells", "spellbook", "baseSpells" }) do
            for k in pairs(world[field]) do
                world[field][k] = nil;
            end
        end
        world.specIndex = specIndex;
        -- A book row the walk cannot date is left out of the index (`AddSpellBook`).
        world.spells[8936] = { name = "Regrowth", subtext = "Restoration", iconID = 136085,
            levelLearned = 1 };
        world.spells[102560] = { name = INCARNATION, iconID = 571586, levelLearned = 1 };
        world.spells[390414] = { name = INCARNATION, iconID = 571586, levelLearned = 1 };
        world.spells[194223] = { name = "Celestial Alignment", iconID = 136060 };
        world.spells[78674] = { name = "Starsurge", subtext = "Balance", iconID = 135730,
            levelLearned = 1 };
        world.baseSpells[390414] = 194223;
        world.spellbook[8936] = true;
        world.spellbook[102560] = true;
        world.spellbook[390414] = true;
    end

    local function Bind(actions)
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    --- What the key's action casts, twice over: the value its record carries and the `*spell-` on
    --- the button it clicks. The button is what fires, and a cache hit is where the two part.
    local function CastOn(key)
        local records = castmod.without(Constants, DebindPrivate.KeyMap[key]);
        local record = records and records[1];
        check(record, "nothing on " .. key);
        check(record.clickframe and record.clickbutton, "no button on " .. key);
        return record.castSpell, record.clickframe:GetAttribute("*spell-" .. record.clickbutton);
    end

    local function ExpectCast(key, expected)
        local cast, stamped = CastOn(key);
        check(cast == expected, key .. " casts " .. tostring(cast) .. ", expected " .. expected);
        check(stamped == expected,
            key .. "'s button is stamped " .. tostring(stamped) .. ", expected " .. expected);
    end

    test("a name with one id in the index casts as that id does", function()
        installWorld(1);
        Bind({
            { type = SPELL, value = "Regrowth", key = "F1", seq = 1 },
            { type = SPELL, value = 8936, key = "F2", seq = 1 },
        });
        ExpectCast("F1", "Regrowth(Restoration)");
        ExpectCast("F2", "Regrowth(Restoration)");
    end);

    test("a name with several ids in the index casts as their root", function()
        installWorld(1);
        Bind({
            { type = SPELL, value = INCARNATION, key = "F1", seq = 1 },
            { type = SPELL, value = 390414, key = "F2", seq = 1 },
        });
        ExpectCast("F1", "Celestial Alignment");
        ExpectCast("F2", "Celestial Alignment");
    end);

    test("a name the index does not hold goes on the button as it is", function()
        installWorld(1);
        Bind({ { type = SPELL, value = "Starsurge", key = "F1", seq = 1 } });
        ExpectCast("F1", "Starsurge");
    end);

    -- **The button follows the resolution.** The cache writes nothing on a hit and is never
    -- cleared, so a button filed under the name would go on casting what the first rebuild found.
    test("a name is resolved again at the next rebuild", function()
        installWorld(2);
        Bind({ { type = SPELL, value = "Starsurge", key = "F1", seq = 1 } });
        ExpectCast("F1", "Starsurge");

        installWorld(3);
        shim.world.spellbook[78674] = true;
        check(DebindPrivate.UpdateBindings() == true, "the second rebuild declined");
        ExpectCast("F1", "Starsurge(Balance)");
    end);

    test("a name is drawn as the id it resolves to, or as itself", function()
        installWorld(1);
        local NameAndIcon = DebindPrivate.DebindUI.NameAndIconForAction;

        local _, icon, name = NameAndIcon({ type = SPELL, value = "Regrowth" });
        check(name == "Regrowth" and icon == 136085,
            "resolved: " .. tostring(name) .. " / " .. tostring(icon));

        _, icon, name = NameAndIcon({ type = SPELL, value = INCARNATION });
        check(name == "Celestial Alignment" and icon == 136060,
            "several: " .. tostring(name) .. " / " .. tostring(icon));

        _, icon, name = NameAndIcon({ type = SPELL, value = "Starsurge" });
        check(name == "Starsurge" and icon == Constants.QUESTION_MARK_ICON,
            "unresolved: " .. tostring(name) .. " / " .. tostring(icon));
    end);

    test("a name converts to the body its button casts", function()
        installWorld(1);
        local function convert(value)
            local action = { type = SPELL, value = value };
            check(DebindPrivate.ConvertToMacroText(action), "the conversion refused " .. value);
            return action.value;
        end
        check(convert("Regrowth") == "/cast Regrowth(Restoration)", "resolved: " .. convert("Regrowth"));
        check(convert(INCARNATION) == "/cast Celestial Alignment", "several: " .. convert(INCARNATION));
        check(convert("Starsurge") == "/cast Starsurge", "unresolved: " .. convert("Starsurge"));
    end);

    -- **What the stored id is for is a name this client cannot read**, which is what a profile
    -- written under another locale looks like. `Regrowth` in the index, `Nachwachsen` on disk.
    local FOREIGN = "Nachwachsen";

    test("a name the index does not hold casts as the id stored beside it", function()
        installWorld(1);
        Bind({
            { type = SPELL, value = FOREIGN, resolvedSpellID = 8936, key = "F1", seq = 1 },
            { type = SPELL, value = FOREIGN, key = "F2", seq = 1 },
        });
        ExpectCast("F1", "Regrowth(Restoration)");
        ExpectCast("F2", FOREIGN);
    end);

    -- The other half: the stored id is a fallback, not a second opinion. It was right for the
    -- character that added the action, and the name is what this one resolves.
    test("a name the index holds wins over the id stored beside it", function()
        installWorld(1);
        Bind({ { type = SPELL, value = "Regrowth", resolvedSpellID = 102560, key = "F1", seq = 1 } });
        ExpectCast("F1", "Regrowth(Restoration)");
    end);

    test("the stored id reaches the row and the macro conversion", function()
        installWorld(1);
        local _, icon, name = DebindPrivate.DebindUI.NameAndIconForAction(
            { type = SPELL, value = FOREIGN, resolvedSpellID = 8936 });
        check(name == "Regrowth" and icon == 136085, "row: " .. tostring(name) .. " / " .. tostring(icon));

        local action = { type = SPELL, value = FOREIGN, resolvedSpellID = 8936 };
        check(DebindPrivate.ConvertToMacroText(action), "the conversion refused");
        check(action.value == "/cast Regrowth(Restoration)", "macro: " .. tostring(action.value));
    end);

    test("an arriving name has the id it resolves to stored beside it", function()
        installWorld(1);
        Bind({});
        local resolved = { type = SPELL, value = "Regrowth", key = "F1", seq = 1, arrivalID = 1 };
        local unresolved = { type = SPELL, value = "Starsurge", key = "F2", seq = 1, arrivalID = 1 };
        local carried = { type = SPELL, value = FOREIGN, resolvedSpellID = 8936, key = "F3", seq = 1,
            arrivalID = 1 };
        local byID = { type = SPELL, value = 8936, key = "F4", seq = 1, arrivalID = 1 };
        DebindPrivate.PlaceArrivedActions({
            { scope = "general", action = resolved },
            { scope = "general", action = unresolved },
            { scope = "general", action = carried },
            { scope = "general", action = byID },
        });
        check(resolved.value == "Regrowth" and resolved.resolvedSpellID == 8936,
            "resolved: " .. tostring(resolved.value) .. " / " .. tostring(resolved.resolvedSpellID));
        check(unresolved.value == "Starsurge" and unresolved.resolvedSpellID == nil,
            "unresolved: " .. tostring(unresolved.resolvedSpellID));
        check(carried.resolvedSpellID == 8936, "carried: " .. tostring(carried.resolvedSpellID));
        check(byID.resolvedSpellID == nil, "by id: " .. tostring(byID.resolvedSpellID));
    end);

    test("the stored id survives a save only beside a spell name", function()
        installWorld(1);
        local byName = { type = SPELL, value = "Regrowth", resolvedSpellID = 8936, key = "F1", seq = 1 };
        local byID = { type = SPELL, value = 8936, resolvedSpellID = 8936, key = "F2", seq = 1 };
        local macro = { type = Constants.MACRO, value = "Regrowth", resolvedSpellID = 8936, key = "F3",
            seq = 1 };
        Bind({ byName, byID, macro });
        DebindPrivate.CleanUpDB();
        check(byName.resolvedSpellID == 8936, "name: " .. tostring(byName.resolvedSpellID));
        check(byID.resolvedSpellID == nil, "id: " .. tostring(byID.resolvedSpellID));
        check(macro.resolvedSpellID == nil, "macro: " .. tostring(macro.resolvedSpellID));
    end);

    test("picking another spell drops the stored id", function()
        local action = { type = SPELL, value = "Regrowth", resolvedSpellID = 8936 };
        DebindPrivate.SetActionEntry(action, SPELL, 78674, nil, nil, nil);
        check(action.resolvedSpellID == nil, "kept: " .. tostring(action.resolvedSpellID));
    end);

    test("the stored id travels in a payload", function()
        installWorld(1);
        Bind({});
        local payload = {
            v = 1, class = Constants.PLAYER_CLASS,
            shared = { GENERAL = { { type = SPELL, value = FOREIGN, resolvedSpellID = 8936, key = "F1",
                seq = 1 } } },
        };
        local placements = DebindStorage.PlanArrival(payload);
        check(#placements == 1, "placements: " .. #placements);
        check(placements[1].action.resolvedSpellID == 8936,
            "arrived: " .. tostring(placements[1].action.resolvedSpellID));
    end);

    test("a payload holding a name is taken in with the name for its value", function()
        installWorld(1);
        Bind({});
        local payload = {
            v = 1, class = Constants.PLAYER_CLASS,
            shared = { GENERAL = { { type = SPELL, value = "Regrowth", key = "F1", seq = 1 } } },
        };
        check(not DebindStorage.PayloadIsImpossible(payload), "the payload was refused");
        local placements = DebindStorage.PlanArrival(payload);
        check(#placements == 1, "placements: " .. #placements);
        check(placements[1].action.value == "Regrowth",
            "value: " .. tostring(placements[1].action.value));
    end);

    return T;
end
