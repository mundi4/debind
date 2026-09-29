-- **Camelot's two dispels, each with a lower and an upper spell** (`splitting-the-camelot-dispel.md`).
-- Run in the camelot world, whose character is a druid: `dispel2` is Abolish Poison then Cure
-- Poison there, the one type on this client with two entries a spec can stand up.
--
-- What is measured is what the key does and what the row says, one entry per binding: each binding
-- asks about the spell it casts, the upper one is tried first, and the row names the spell a press
-- would cast.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    --- The press is reached through the DEBUG eval hook, which the shipped shape does not carry
    --- (`eval_spec`); the checks that press a key stand down there and the rest still run.
    local shipped = ctx and ctx.shipped;
    local frames = require("wow_frames");
    local restricted = require("restricted");
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

    local GUID = "Player-1-TESTGUID";
    local interp;
    local seq = 0;

    local function action(t)
        seq = seq + 1;
        t.seq = seq;
        return t;
    end

    local function Bind(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();

        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");

        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
        return interp;
    end

    --- Indexed without the self and focus twins, which ride on every action.
    local function recordField(key, index, field)
        local records = castmod.without(Constants, interp:recordsFor(key));
        check(records and records[index], key .. " has no record " .. index);
        return records[index][field];
    end

    --- The spell the winning record casts, nil for one that holds the key and casts nothing.
    local function firedSpell(key)
        local _, _, record = interp:evalKey(key);
        return record and record.spell;
    end

    local ABOLISH, CURE, REGROWTH = 2893, 8946, 8936;

    --- **Stood up whole at the start of every case**, so one that fails before its last line leaves
    --- nothing known or in the book for the next.
    local function druidWorld()
        shim.world.specIndex = 1;
        shim.world.spells[ABOLISH] = { name = "Abolish Poison", iconID = 136068 };
        shim.world.spells[CURE] = { name = "Cure Poison", iconID = 136067 };
        shim.world.spells[REGROWTH] = { name = "Regrowth" };
        for _, spellID in ipairs({ ABOLISH, CURE }) do
            shim.world.knownSpells[spellID] = nil;
            shim.world.spellbook[spellID] = nil;
        end
    end

    -- **The upper spell first, the lower behind it, and the key held behind both** while the reader
    -- has not asked for it to be handed on. Each binding asks about the spell it casts, so a press
    -- casts the upper one where it is known and the lower one where only that is.
    test("the second dispel casts the upper spell first, then the lower", function()
        druidWorld();
        Bind({
            action({ type = Constants.DISPEL2, key = "F1" }),
            action({ type = Constants.SPELL, key = "F1", value = REGROWTH }),
        });
        check(recordField("F1", 1, "known") == "[known:Abolish Poison]",
            "record 1 known: " .. tostring(recordField("F1", 1, "known")));
        check(recordField("F1", 2, "known") == "[known:Cure Poison]",
            "record 2 known: " .. tostring(recordField("F1", 2, "known")));
        check(recordField("F1", 3, "known") == nil,
            "the holding record asks: " .. tostring(recordField("F1", 3, "known")));
        check(recordField("F1", 3, "spell") == nil,
            "the holding record casts: " .. tostring(recordField("F1", 3, "spell")));

        if (not shipped) then
            check(firedSpell("F1") == nil, "with neither known the key was not held: "
                .. tostring(firedSpell("F1")));
            interp.state.known["Cure Poison"] = true;
            check(firedSpell("F1") == "Cure Poison",
                "with the lower known: " .. tostring(firedSpell("F1")));
            interp.state.known["Abolish Poison"] = true;
            check(firedSpell("F1") == "Abolish Poison",
                "with both known: " .. tostring(firedSpell("F1")));
            interp:resetState();
        end
        shim.world.specIndex = nil;
    end);

    -- **Handed on, the original is the upper spell's binding even while the row shows the lower.**
    -- The row names what a press would cast now, which with nothing learned is the lower one; the
    -- binding the reader sees still asks about and casts the upper, or a press would cast the upper
    -- spell under the lower one's `known`.
    test("the original casts and asks about the upper spell while the row shows the lower", function()
        druidWorld();
        local a = action({ type = Constants.DISPEL2, key = "F2", skipWhenUnusable = true });
        local binding = DebindPrivate.GetBindingInfoForAction(a);
        check(binding.spell == CURE, "the row shows " .. tostring(binding.spell));
        check(binding.spellToCast == ABOLISH, "the original casts " .. tostring(binding.spellToCast));
        check(DebindPrivate.KnownSpellAsked(binding) == "Abolish Poison",
            "the original asks about " .. tostring(DebindPrivate.KnownSpellAsked(binding)));

        if (not shipped) then
            Bind({ a, action({ type = Constants.SPELL, key = "F2", value = REGROWTH }) });
            check(firedSpell("F2") == "Regrowth",
                "with neither known the key was not handed on: " .. tostring(firedSpell("F2")));
            interp.state.known["Cure Poison"] = true;
            check(firedSpell("F2") == "Cure Poison",
                "with the lower known: " .. tostring(firedSpell("F2")));
            interp.state.known["Cure Poison"] = nil;
            interp.state.known["Abolish Poison"] = true;
            check(firedSpell("F2") == "Abolish Poison",
                "with the upper known: " .. tostring(firedSpell("F2")));
            interp:resetState();
        end
        shim.world.specIndex = nil;
    end);

    -- **The row names the first spell known, and the last where none is** (2026-09-29, owner): the
    -- last is the one the character learns first.
    test("the row shows the first spell known, the last where none is", function()
        druidWorld();
        local a = action({ type = Constants.DISPEL2, key = "F3" });
        check(DebindPrivate.SpecSpells.SpellForType(Constants.DISPEL2) == CURE,
            "with neither known: " .. tostring(DebindPrivate.SpecSpells.SpellForType(Constants.DISPEL2)));
        local _, icon = DebindPrivate.DebindUI.NameAndIconForAction(a);
        check(icon == 136067, "row icon with neither known: " .. tostring(icon));

        shim.world.knownSpells[ABOLISH] = true;
        check(DebindPrivate.SpecSpells.SpellForType(Constants.DISPEL2) == ABOLISH,
            "with the upper known: " .. tostring(DebindPrivate.SpecSpells.SpellForType(Constants.DISPEL2)));
        _, icon = DebindPrivate.DebindUI.NameAndIconForAction(a);
        check(icon == 136068, "row icon with the upper known: " .. tostring(icon));
        shim.world.specIndex = nil;
    end);

    -- **The row says the spell is not there only while no entry is known.** The original asks about
    -- the upper spell, and a druid who has not trained it still casts the lower one from this key.
    --
    -- The world is stood up before the rebuild: `Spells` builds its table once, and a spell it
    -- cannot date is never called missing.
    test("the row is not marked missing while the lower spell is known", function()
        druidWorld();
        shim.world.spells[ABOLISH].levelLearned = 26;
        shim.world.spells[CURE].levelLearned = 14;
        shim.world.spellbook[ABOLISH] = true;
        shim.world.spellbook[CURE] = true;

        shim.world.knownSpells[CURE] = true;
        Bind({ action({ type = Constants.DISPEL2, key = "F4", skipWhenUnusable = true }) });
        local row = DebindPrivate.CollectActionsForKey("F4")[1];
        check(row and row.noSpell == nil, "marked with the lower spell known: "
            .. tostring(row and row.noSpell));

        shim.world.knownSpells[CURE] = nil;
        Bind({ action({ type = Constants.DISPEL2, key = "F4", skipWhenUnusable = true }) });
        row = DebindPrivate.CollectActionsForKey("F4")[1];
        check(row and row.noSpell == true, "not marked with neither known: "
            .. tostring(row and row.noSpell));
        shim.world.specIndex = nil;
    end);

    return T;
end
