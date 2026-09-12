-- The three action types whose spell the class and specialization decide (`SpecSpells.lua`,
-- `devdocs/adding-spec-resolved-actions.md`): what they resolve to, what the binding carries, what
-- is stamped for a specialization that has nothing to cast, and the warlock's two-binding dispel.
--
-- The shim's character is a druid, so the four specialization indexes are Balance, Feral,
-- Guardian, Restoration. The warlock cannot be stood up here (`Constants.PLAYER_CLASS` is read
-- once at load), so the probe derivation is driven by handing `SpellForType` a probe id directly.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    --- The press is reached through the DEBUG eval hook, which the shipped shape does not carry
    --- (`eval_spec`); the checks that press a key stand down there and the rest still run.
    local shipped = ctx and ctx.shipped;
    local frames = require("wow_frames");
    local restricted = require("restricted");

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

    local function Bind(actions, options)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
            options = options,
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

    local function recordField(key, index, field)
        local records = interp:recordsFor(key);
        check(records and records[index], key .. " has no record " .. index);
        return records[index][field];
    end

    ---------------------------------------------------------------------------
    -- Resolution
    ---------------------------------------------------------------------------

    test("a druid resolves by specialization", function()
        shim.world.specIndex = 1;
        local balance = DebindPrivate.SpecSpells.Resolve();
        check(balance.dispel == 2782, "balance dispel: " .. tostring(balance.dispel));
        check(balance.external == nil, "balance external: " .. tostring(balance.external));
        check(balance.massrez == nil, "balance mass rez: " .. tostring(balance.massrez));
        check(balance.rez == 50769 and balance.battlerez == 20484 and balance.raidbuff == 1126,
            "balance class spells");

        shim.world.specIndex = 4;
        local resto = DebindPrivate.SpecSpells.Resolve();
        check(resto.dispel == 88423, "restoration dispel: " .. tostring(resto.dispel));
        check(resto.external == 102342, "restoration external: " .. tostring(resto.external));
        check(resto.massrez == 212040, "restoration mass rez: " .. tostring(resto.massrez));
        shim.world.specIndex = nil;
    end);

    ---------------------------------------------------------------------------
    -- The binding
    ---------------------------------------------------------------------------

    -- The action stores the kind and nothing else; the spell is on the binding, and `known` --
    -- which every type but `SPELL` drops -- survives on these three because there is a spell for it
    -- to ask about.
    test("the binding carries the resolved spell and keeps known", function()
        shim.world.specIndex = 1;
        local dispel = DebindPrivate.GetBindingInfoForAction(
            { type = Constants.DISPEL, key = "F1", conditions = { known = true } });
        check(dispel.spell == 2782, "spell: " .. tostring(dispel.spell));
        check(dispel.value == nil, "value leaked onto the binding: " .. tostring(dispel.value));
        check(dispel.conditions.known == true, "known was dropped");

        local external = DebindPrivate.GetBindingInfoForAction(
            { type = Constants.EXTERNAL, key = "F2", conditions = { known = true } });
        check(external.spell == nil, "balance has an external: " .. tostring(external.spell));
        check(external.conditions.known == true, "known was dropped where there is no spell");
        shim.world.specIndex = nil;
    end);

    ---------------------------------------------------------------------------
    -- What is stamped
    ---------------------------------------------------------------------------

    -- A specialization with nothing to cast is **not a refusal**: a refusal eats the key, and the
    -- design wants the key kept and the press to do nothing. So the descriptor names no attribute.
    test("no spell stamps nothing and is not refused", function()
        local descriptor, reason = DebindPrivate.DescribeBinding(Constants.EXTERNAL, nil, nil, {}, nil);
        check(descriptor, "refused: " .. tostring(reason));
        check(descriptor.count == 0, "attributes were written: " .. descriptor.count);
        check(descriptor.type == Constants.EXTERNAL, "type: " .. tostring(descriptor.type));
    end);

    test("a resolved spell is stamped as a spell", function()
        local descriptor = DebindPrivate.DescribeBinding(Constants.DISPEL, 2782, "focus",
            { spellID = 2782, spellName = "Remove Corruption" }, nil);
        check(descriptor.type == Constants.SPELL, "type: " .. tostring(descriptor.type));
        check(descriptor.unit == "focus", "unit: " .. tostring(descriptor.unit));
        local found;
        for i = 1, descriptor.count do
            if (descriptor.attrNames[i] == "*spell-") then
                found = descriptor.attrValues[i];
            end
        end
        check(found == "Remove Corruption", "*spell-: " .. tostring(found));
    end);

    ---------------------------------------------------------------------------
    -- Through a rebuild
    ---------------------------------------------------------------------------

    -- `known` bakes the resolved spell, **by name like every other one**. `true` is what these
    -- three store because the spell is the specialization's answer rather than a stored value
    -- (`devdocs/making-known-a-spell-name.md`), and naming it at the bake is what puts them on the
    -- same state key as a spell action asking about the same spell.
    test("known is baked from the resolved spell", function()
        shim.world.specIndex = 1;
        shim.world.spells[2782] = { name = "Remove Corruption" };
        Bind({
            action({ type = Constants.DISPEL, key = "F1", conditions = { known = true } }),
        });
        check(recordField("F1", 1, "known") == "[known:Remove Corruption]",
            "dispel known: " .. tostring(recordField("F1", 1, "known")));
        check(recordField("F1", 1, "clickbutton") ~= nil, "dispel has no button");

        if (not shipped) then
            interp.state.known["Remove Corruption"] = true;
            check(interp:evalKey("F1") == 1, "the dispel did not fire with its spell known");
        end
        shim.world.specIndex = nil;
    end);

    -- **A `known` this specialization has no spell for never reaches the build.** The condition is
    -- false for every press this build will see, so the rebuild leaves the action out the way it
    -- leaves out an action for another specialization (`Misc.lua`'s `KnownConditionCanHold`).
    test("a known with no spell is left out of the build", function()
        shim.world.specIndex = 1;
        Bind({
            action({ type = Constants.EXTERNAL, key = "F2", conditions = { known = true } }),
        });
        check(interp:recordsFor("F2") == nil, "the key was bound anyway");
        shim.world.specIndex = nil;
    end);

    -- **A `known` naming a spell of its own is a different question and stays in the build.** What
    -- the filter above answers is "there is nothing to ask about", which only `true` can be
    -- (`devdocs/making-known-a-spell-name.md`); a name asks the same thing whatever this
    -- specialization resolves to.
    test("a known that names a spell survives a specialization with none", function()
        shim.world.specIndex = 1;
        shim.world.spells[8936] = { name = "Regrowth" };
        Bind({
            action({ type = Constants.EXTERNAL, key = "F2",
                conditions = { known = "Regrowth" } }),
        });
        check(recordField("F2", 1, "known") == "[known:Regrowth]",
            "known: " .. tostring(recordField("F2", 1, "known")));
        shim.world.specIndex = nil;
    end);

    -- And the key goes to whatever stands behind it, which is the whole point of leaving it out.
    test("the action behind it takes the key", function()
        shim.world.specIndex = 1;
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ type = Constants.EXTERNAL, key = "F3", conditions = { known = true } }),
            action({ type = Constants.SPELL, key = "F3", value = 774 }),
        });
        local records = interp:recordsFor("F3");
        check(records and #records == 1, "records on F3: " .. tostring(records and #records));
        check(recordField("F3", 1, "known") == nil,
            "the spell row carries a known: " .. tostring(recordField("F3", 1, "known")));
        if (not shipped) then
            check(interp:evalKey("F3") == 1, "the spell behind it did not fire");
        end
        shim.world.specIndex = nil;
    end);

    -- Without `known` the action stays, and the key stays ours with nothing to press: that is the
    -- reader not having asked for anything (§4).
    test("no known keeps the action on the key", function()
        shim.world.specIndex = 1;
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ type = Constants.EXTERNAL, key = "F4" }),
            action({ type = Constants.SPELL, key = "F4", value = 774 }),
        });
        check(recordField("F4", 1, "clickbutton") ~= nil, "the external lost its button");
        shim.world.specIndex = nil;
    end);

    -- The warlock's shape, driven directly: the dispel resolves to one spell and a probe id, and
    -- the probe becomes a derived binding ahead of the original that the press gates on the
    -- spellbook.
    test("a probe id derives a spellbook-gated binding ahead of the original", function()
        local SpecSpells = DebindPrivate.SpecSpells;
        local saved = SpecSpells.SpellForType;
        SpecSpells.SpellForType = function(type)
            if (type == Constants.DISPEL) then
                return 132411, 119905;
            end
            return saved(type);
        end

        local ok, err = pcall(function()
            shim.world.spells[132411] = { name = "Singe Magic" };
            shim.world.spells[119905] = { name = "Command Demon" };

            local a = action({ type = Constants.DISPEL, key = "F3" });
            local list = DebindPrivate.GetBindingsForAction(a);
            check(#list == 2, "list length: " .. #list);
            check(list[1].spell == 132411 and list[1].spellbook == nil, "the original is not the player's spell");
            check(list[2].spell == 119905 and list[2].spellbook == 119905, "the derived is not the probe");

            Bind({ a });
            check(recordField("F3", 1, "spellbook") == 119905, "the derived record carries no probe");
            check(recordField("F3", 2, "spellbook") == nil, "the original record carries a probe");

            if (not shipped) then
                shim.world.spellbook[119905] = nil;
                check(interp:evalKey("F3") == 2, "without the imp the original did not win");
                shim.world.spellbook[119905] = true;
                check(interp:evalKey("F3") == 1, "with the imp the probe binding did not win");
                shim.world.spellbook[119905] = nil;
            end

            -- With a hover twin as well, the twin gets a probe of its own ahead of it. The list is
            -- read back to front by the unroll, so the key order is probe-twin, twin, probe,
            -- original: over a frame with the imp out, the probe twin is the first record.
            local twinned = action({ type = Constants.DISPEL, key = "F4" });
            Bind({ twinned }, { hoverCast = true });

            local twinnedList = DebindPrivate.GetBindingsForAction(twinned);
            check(#twinnedList == 4, "twinned list length: " .. #twinnedList);
            check(twinnedList[2].unit == nil and twinnedList[2].spellbook == 119905, "probe");
            check(twinnedList[3].unit == "hover" and twinnedList[3].spellbook == nil, "twin");
            check(twinnedList[4].unit == "hover" and twinnedList[4].spellbook == 119905, "probe twin");

            local keyed = interp:recordsFor("F4");
            check(keyed and #keyed == 4, "F4 records: " .. tostring(keyed and #keyed));
            check(keyed[1].spellbook == 119905 and keyed[1].units and keyed[1].units.hover,
                "the first record on the key is not the probe twin");
            check(keyed[2].spellbook == nil and keyed[2].units and keyed[2].units.hover,
                "the second record on the key is not the twin");
            check(keyed[3].spellbook == 119905 and not (keyed[3].units and keyed[3].units.hover),
                "the third record on the key is not the probe");
            check(keyed[4].spellbook == nil and not (keyed[4].units and keyed[4].units.hover),
                "the last record on the key is not the original");
        end);

        SpecSpells.SpellForType = saved;
        if (not ok) then
            error(err, 0);
        end
    end);

    return T;
end
