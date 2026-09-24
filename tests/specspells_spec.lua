-- The three action types whose spell the class and specialization decide (`SpecSpells.lua`,
-- `adding-spec-resolved-actions.md`): what they resolve to, what the binding carries, what
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

    --- **Hover Cast는 기본값 그대로 꺼져 있다.** 이 파일이 재는 것은 전문화가 고르는 주문이고,
    --- 켜져 있으면 액션마다 쌍둥이가 하나씩 더 서서 키의 목록이 두 배가 된다.
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

    local castmod = require("castmod");

    --- Indexed without the self and focus twins, which ride on every action
    --- and are not what this file is about.
    local function recordField(key, index, field)
        local records = castmod.without(Constants, interp:recordsFor(key));
        check(records and records[index], key .. " has no record " .. index);
        return records[index][field];
    end

    --- Which record a press with no modifier held fires, counted the same way.
    local function winner(key)
        return castmod.index(Constants, interp:recordsFor(key), (interp:evalKey(key)));
    end

    --- The spell the winning record casts, nil for one that holds the key and casts nothing.
    --- **Asked by what fires rather than by index**: a record that holds the key covers every
    --- action behind it, the solver drops those, and an index then names a different record.
    local function firedSpell(key)
        local _, _, record = interp:evalKey(key);
        return record and record.spell;
    end

    ---------------------------------------------------------------------------
    -- Resolution
    ---------------------------------------------------------------------------

    test("a druid resolves by specialization", function()
        shim.world.specIndex = 1;
        local balance = DebindPrivate.SpecSpells.Resolve();
        check(balance.dispel == 2782, "balance dispel: " .. tostring(balance.dispel));
        check(balance.raidbuff == 1126, "balance raid buff: " .. tostring(balance.raidbuff));

        shim.world.specIndex = 4;
        local resto = DebindPrivate.SpecSpells.Resolve();
        check(resto.dispel == 88423, "restoration dispel: " .. tostring(resto.dispel));
        shim.world.specIndex = nil;
    end);

    --- A dispel with nothing to cast, the way a warrior's is. Every druid specialization has one,
    --- and `Constants.PLAYER_CLASS` is read once at load, so `SpellForType` is handed the answer.
    local function withNoDispel(fn)
        local SpecSpells = DebindPrivate.SpecSpells;
        local saved = SpecSpells.SpellForType;
        SpecSpells.SpellForType = function(type)
            if (type == Constants.DISPEL) then
                return nil;
            end
            return saved(type);
        end
        local ok, err = pcall(fn);
        SpecSpells.SpellForType = saved;
        if (not ok) then
            error(err, 0);
        end
    end

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

        withNoDispel(function()
            local none = DebindPrivate.GetBindingInfoForAction(
                { type = Constants.DISPEL, key = "F2", conditions = { known = true } });
            check(none.spell == nil, "a dispel resolved: " .. tostring(none.spell));
            check(none.conditions.known == true, "known was dropped where there is no spell");
        end);
        shim.world.specIndex = nil;
    end);

    ---------------------------------------------------------------------------
    -- What is stamped
    ---------------------------------------------------------------------------

    -- A specialization with nothing to cast is **not a refusal**: a refusal eats the key, and the
    -- design wants the key kept and the press to do nothing. So the descriptor names no attribute.
    test("no spell stamps nothing and is not refused", function()
        local descriptor, reason = DebindPrivate.DescribeBinding(Constants.DISPEL, nil, nil, {}, nil);
        check(descriptor, "refused: " .. tostring(reason));
        check(descriptor.count == 0, "attributes were written: " .. descriptor.count);
        check(descriptor.type == Constants.DISPEL, "type: " .. tostring(descriptor.type));
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
    -- (`making-known-a-spell-name.md`), and naming it at the bake is what puts them on the
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
            check(winner("F1") == 1, "the dispel did not fire with its spell known");
        end
        shim.world.specIndex = nil;
    end);

    -- **A `known` this specialization has no spell for never reaches the build.** The condition is
    -- false for every press this build will see, so the rebuild leaves the action out the way it
    -- leaves out an action for another specialization (`Known.lua`'s `KnownConditionCanHold`).
    -- **Out of the build, not off the key**: the key stays ours and the press does nothing.
    test("a known with no spell is left out of the build", function()
        shim.world.specIndex = 1;
        withNoDispel(function()
            Bind({
                action({ type = Constants.DISPEL, key = "F2", conditions = { known = true } }),
            });
            check(DebindPrivate.KeyMap["F2"] == nil, "the action reached the key map anyway");
            check(DebindPrivate.IsKeyOurs("F2"), "the key was handed back");
            if (not shipped) then
                check(interp:evalKey("F2") == nil, "the press fired something");
            end
        end);
        shim.world.specIndex = nil;
    end);

    -- **A `known` naming a spell of its own is a different question and stays in the build.** What
    -- the filter above answers is "there is nothing to ask about", which only `true` can be
    -- (`making-known-a-spell-name.md`); a name asks the same thing whatever this
    -- specialization resolves to.
    test("a known that names a spell survives a specialization with none", function()
        shim.world.specIndex = 1;
        shim.world.spells[8936] = { name = "Regrowth" };
        withNoDispel(function()
            Bind({
                action({ type = Constants.DISPEL, key = "F2",
                    conditions = { known = "Regrowth" } }),
            });
            check(recordField("F2", 1, "known") == "[known:Regrowth]",
                "known: " .. tostring(recordField("F2", 1, "known")));
        end);
        shim.world.specIndex = nil;
    end);

    -- And the key goes to whatever stands behind it, which is the whole point of leaving it out.
    test("the action behind it takes the key", function()
        shim.world.specIndex = 1;
        shim.world.spells[774] = { name = "Rejuvenation" };
        withNoDispel(function()
            Bind({
                action({ type = Constants.DISPEL, key = "F3", conditions = { known = true } }),
                action({ type = Constants.SPELL, key = "F3", value = 774 }),
            });
            local records = castmod.without(Constants, interp:recordsFor("F3"));
            check(records and #records == 1, "records on F3: " .. tostring(records and #records));
            check(recordField("F3", 1, "known") == nil,
                "the spell row carries a known: " .. tostring(recordField("F3", 1, "known")));
            if (not shipped) then
                check(winner("F3") == 1, "the spell behind it did not fire");
            end
        end);
        shim.world.specIndex = nil;
    end);

    -- Without `known` the action stays, and the key stays ours with nothing to press: that is the
    -- reader not having asked for anything (§4).
    test("no known keeps the action on the key", function()
        shim.world.specIndex = 1;
        shim.world.spells[774] = { name = "Rejuvenation" };
        withNoDispel(function()
            Bind({
                action({ type = Constants.DISPEL, key = "F4" }),
                action({ type = Constants.SPELL, key = "F4", value = 774 }),
            });
            check(recordField("F4", 1, "clickbutton") ~= nil, "the dispel lost its button");
            if (not shipped) then
                check(winner("F4") == 1, "the key went to the spell behind");
            end
        end);
        shim.world.specIndex = nil;
    end);

    --- What the click frame casts when that button is pressed.
    local function spellOn(button)
        return DebindPrivate.DefaultClickFrame:GetAttribute("*spell-" .. tostring(button));
    end

    --- Stands the warlock's dispel up. `Constants.PLAYER_CLASS` is read once at load so the class
    --- itself cannot be set here; what the rest of the addon sees of it is `SpellForType`'s pair,
    --- and that is handed over directly.
    local function withGate(gate, fn)
        local SpecSpells = DebindPrivate.SpecSpells;
        local saved = SpecSpells.SpellForType;
        SpecSpells.SpellForType = function(type)
            if (type == Constants.DISPEL) then
                return gate.known[1], gate;
            end
            return saved(type);
        end
        local ok, err = pcall(fn);
        SpecSpells.SpellForType = saved;
        if (not ok) then
            error(err, 0);
        end
    end

    local WARLOCK_GATE = { cast = 119898, known = { 119905, 132411 } };

    local function warlockWorld()
        shim.world.spells[119898] = { name = "Command Demon", iconID = 136122 };
        shim.world.spells[119905] = { name = "Singe Magic", iconID = 135795 };
        shim.world.spells[132411] = { name = "Singe Magic", iconID = 135795 };
        shim.world.spellbook[119905] = nil;
        shim.world.spellbook[132411] = nil;
    end

    -- **Nothing ticked still asks the book before it casts** (2026-09-23, owner). Command Demon
    -- casts whatever the demon that is out has, so without the question the key sent a Spell Lock
    -- where the reader asked for a dispel. One binding per id casts, and the last one holds the key
    -- and casts nothing: the reader did not ask for the key to be handed on.
    test("an unticked gated dispel casts only under an id and holds the key otherwise", function()
        withGate(WARLOCK_GATE, function()
            warlockWorld();

            local a = action({ type = Constants.DISPEL, key = "F3" });
            Bind({ a });
            -- In the gate's own order. Which comes first changes nothing: the book never holds both.
            check(recordField("F3", 1, "known") == "[known:119905]",
                "record 1 known: " .. tostring(recordField("F3", 1, "known")));
            check(recordField("F3", 1, "knownID") == 119905,
                "record 1 id: " .. tostring(recordField("F3", 1, "knownID")));
            check(recordField("F3", 2, "known") == "[known:132411]",
                "record 2 known: " .. tostring(recordField("F3", 2, "known")));
            check(recordField("F3", 3, "known") == nil,
                "the holding record asks: " .. tostring(recordField("F3", 3, "known")));
            check(recordField("F3", 3, "spell") == nil,
                "the holding record casts: " .. tostring(recordField("F3", 3, "spell")));
            local button = recordField("F3", 1, "clickbutton");
            check(spellOn(button) == "Command Demon", "*spell-: " .. tostring(spellOn(button)));

            -- **The row is drawn off the first id and not off what is cast.** Taken from the
            -- button, a warlock's dispel would wear Command Demon's icon.
            local _, icon = DebindPrivate.DebindUI.NameAndIconForAction(a);
            check(icon == 135795, "row icon: " .. tostring(icon));
        end);
    end);

    -- **Ticking `known` splits the action into one binding per id.** "Either of these two is in
    -- the book" is not something one condition can say, and each binding says half of it on the
    -- ordinary `known` axis.
    test("a ticked known derives one binding per id", function()
        withGate(WARLOCK_GATE, function()
            warlockWorld();

            local a = action({ type = Constants.DISPEL, key = "F3", conditions = { known = true } });
            local list = castmod.without(Constants, DebindPrivate.GetBindingsForAction(a));
            check(#list == 2, "list length: " .. #list);
            check(list[1].conditions.known == 119905, "first: " .. tostring(list[1].conditions.known));
            check(list[2].conditions.known == 132411, "second: " .. tostring(list[2].conditions.known));

            -- The derived one stands ahead of the original, the way every derived binding does
            -- (`GetBindingsForAction` fills the list back to front). Which of the two comes first
            -- changes nothing here: the book never holds both.
            Bind({ a });
            check(recordField("F3", 1, "known") == "[known:132411]",
                "record 1 known: " .. tostring(recordField("F3", 1, "known")));
            check(recordField("F3", 1, "knownID") == 132411,
                "record 1 id: " .. tostring(recordField("F3", 1, "knownID")));
            check(recordField("F3", 2, "known") == "[known:119905]",
                "record 2 known: " .. tostring(recordField("F3", 2, "known")));
            check(recordField("F3", 2, "knownID") == 119905,
                "record 2 id: " .. tostring(recordField("F3", 2, "knownID")));

            -- Both cast the same spell, so the attribute cache hands back one button.
            check(recordField("F3", 1, "clickbutton") == recordField("F3", 2, "clickbutton"),
                "one spell came out as two buttons");
        end);
    end);

    -- A `known` naming a spell is a different question and takes the ordinary road: no split, and
    -- no id on the record because the conditional carries a name.
    test("a named known on a gated dispel stays one binding", function()
        withGate(WARLOCK_GATE, function()
            warlockWorld();
            shim.world.spells[8936] = { name = "Regrowth" };

            local a = action({ type = Constants.DISPEL, key = "F4",
                conditions = { known = "Regrowth" } });
            local list = castmod.without(Constants, DebindPrivate.GetBindingsForAction(a));
            check(#list == 1, "list length: " .. #list);

            Bind({ a });
            check(recordField("F4", 1, "known") == "[known:Regrowth]",
                "known: " .. tostring(recordField("F4", 1, "known")));
            check(recordField("F4", 1, "knownID") == nil, "a name went out with an id beside it");
        end);
    end);

    -- **Unticked, neither id in the book is a press that does nothing**, and not one handed to the
    -- action behind.
    test("an unticked gated dispel keeps the key with neither id in the book", function()
        if (shipped) then
            return;
        end
        withGate(WARLOCK_GATE, function()
            warlockWorld();
            shim.world.spells[8936] = { name = "Regrowth" };
            Bind({
                action({ type = Constants.DISPEL, key = "F3" }),
                action({ type = Constants.SPELL, key = "F3", value = 8936 }),
            });

            shim.world.spellbook[119905] = true;
            check(firedSpell("F3") == "Command Demon", "with the imp out the dispel did not fire");

            shim.world.spellbook[119905] = nil;
            shim.world.spellbook[132411] = true;
            check(firedSpell("F3") == "Command Demon", "with the imp swallowed the dispel did not fire");

            shim.world.spellbook[132411] = nil;
            local index, _, record = interp:evalKey("F3");
            check(index ~= nil and record.spell == nil,
                "with neither in the book the key was not held: " .. tostring(record and record.spell));
        end);
    end);

    -- **The same for every dispel, not only the gated one** (2026-09-23, owner). A class with no
    -- dispel already holds the key and sends nothing (§4); one that has a dispel it has not learned
    -- yet has to look the same, not send a cast for the game to refuse.
    test("an unticked dispel holds the key while its spell is not known", function()
        if (shipped) then
            return;
        end
        shim.world.specIndex = 1;
        shim.world.spells[2782] = { name = "Remove Corruption" };
        shim.world.spells[8936] = { name = "Regrowth" };
        Bind({
            action({ type = Constants.DISPEL, key = "F5" }),
            action({ type = Constants.SPELL, key = "F5", value = 8936 }),
        });
        check(recordField("F5", 1, "known") == "[known:Remove Corruption]",
            "record 1 known: " .. tostring(recordField("F5", 1, "known")));
        check(recordField("F5", 2, "spell") == nil,
            "the holding record casts: " .. tostring(recordField("F5", 2, "spell")));

        local index, _, record = interp:evalKey("F5");
        check(index ~= nil and record.spell == nil,
            "unlearned, the key was not held: " .. tostring(record and record.spell));
        interp.state.known["Remove Corruption"] = true;
        check(firedSpell("F5") == "Remove Corruption", "learned, the dispel did not fire");
        interp:resetState();
        shim.world.specIndex = nil;
    end);

    -- **A stored `false` is no condition** (`FillBinding` strips it; a shared profile can carry one),
    -- so it splits like nothing ticked. Read raw, it held the key with nothing ahead to cast.
    test("a stored false known behaves as unticked", function()
        if (shipped) then
            return;
        end
        shim.world.specIndex = 1;
        shim.world.spells[2782] = { name = "Remove Corruption" };
        Bind({
            action({ type = Constants.DISPEL, key = "F8", conditions = { known = false } }),
        });
        interp.state.known["Remove Corruption"] = true;
        local _, _, record = interp:evalKey("F8");
        check(record and record.spell ~= nil, "learned, the dispel did not cast");
        interp:resetState();
        shim.world.specIndex = nil;
    end);

    -- **"Skip when nothing to cast" hands the key on** (2026-09-23, owner). It is the reader's one
    -- switch for every reason the action has nothing to cast, so it does what ticking `known` does
    -- without the reader having to know that `known` is the reason.
    test("skipping hands the key on while the dispel is not known", function()
        if (shipped) then
            return;
        end
        shim.world.specIndex = 1;
        shim.world.spells[2782] = { name = "Remove Corruption" };
        shim.world.spells[8936] = { name = "Regrowth" };
        Bind({
            action({ type = Constants.DISPEL, key = "F9", skipWhenUnusable = true }),
            action({ type = Constants.SPELL, key = "F9", value = 8936 }),
        });
        check(firedSpell("F9") == "Regrowth",
            "unlearned, the spell behind did not take the key: " .. tostring(firedSpell("F9")));
        interp.state.known["Remove Corruption"] = true;
        check(firedSpell("F9") == "Remove Corruption",
            "learned, the dispel did not fire: " .. tostring(firedSpell("F9")));
        interp:resetState();
        shim.world.specIndex = nil;
    end);

    test("skipping hands the key on where there is no dispel", function()
        if (shipped) then
            return;
        end
        shim.world.specIndex = 1;
        shim.world.spells[8936] = { name = "Regrowth" };
        withNoDispel(function()
            Bind({
                action({ type = Constants.DISPEL, key = "F9", skipWhenUnusable = true }),
                action({ type = Constants.SPELL, key = "F9", value = 8936 }),
            });
            check(firedSpell("F9") == "Regrowth",
                "the spell behind did not take the key: " .. tostring(firedSpell("F9")));
        end);
        shim.world.specIndex = nil;
    end);

    test("skipping hands the key on with neither warlock id in the book", function()
        if (shipped) then
            return;
        end
        withGate(WARLOCK_GATE, function()
            warlockWorld();
            shim.world.spells[8936] = { name = "Regrowth" };
            Bind({
                action({ type = Constants.DISPEL, key = "F9", skipWhenUnusable = true }),
                action({ type = Constants.SPELL, key = "F9", value = 8936 }),
            });
            shim.world.spellbook[132411] = true;
            check(firedSpell("F9") == "Command Demon",
                "with the imp swallowed the dispel did not fire: " .. tostring(firedSpell("F9")));
            shim.world.spellbook[132411] = nil;
            check(firedSpell("F9") == "Regrowth",
                "with neither in the book the spell behind did not win: " .. tostring(firedSpell("F9")));
        end);
    end);

    -- **Known Spell is not offered on these types any more** (Spell to Cast is), so a `known` of
    -- `true` stored on one moves to the switch it reads as. Left, the row would say Off over an
    -- action that hands the key on.
    test("a stored known on a dispel moves to the Spell to Cast switch", function()
        local dispel = { type = Constants.DISPEL, key = "F1", seq = 1, conditions = { known = true } };
        Bind({ dispel });
        DebindPrivate.CleanUpDB();
        check(dispel.skipWhenUnusable == true, "the switch was not set");
        check(dispel.conditions == nil or dispel.conditions.known == nil, "known was left");
    end);

    -- The menu offers the switch on these types alone, so a stored one anywhere else is taken off.
    test("skipping is kept on a dispel and taken off a spell", function()
        local dispel = { type = Constants.DISPEL, key = "F1", seq = 1, skipWhenUnusable = true };
        local spell = { type = Constants.SPELL, value = 8936, key = "F2", seq = 1,
            skipWhenUnusable = true };
        Bind({ dispel, spell });
        DebindPrivate.CleanUpDB();
        check(dispel.skipWhenUnusable == true, "taken off the dispel");
        check(spell.skipWhenUnusable == nil, "left on the spell");
    end);

    -- **Every tier the action stands in splits the same way**: a held self cast key reaches the self
    -- tier's own holding binding and its own casting one, not the plain tier's.
    test("an unticked dispel splits in the self cast tier too", function()
        if (shipped) then
            return;
        end
        shim.world.specIndex = 1;
        shim.world.spells[2782] = { name = "Remove Corruption" };
        shim.world.spells[8936] = { name = "Regrowth" };
        Bind({
            action({ type = Constants.DISPEL, key = "F7" }),
            action({ type = Constants.SPELL, key = "F7", value = 8936 }),
        });
        interp.state.modifiedClick.SELFCAST = true;

        local _, _, record = interp:evalKey("F7");
        check(record and record.castModifier == Constants.CASTMOD_SELF,
            "unlearned, the self tier did not answer");
        check(record.spell == nil, "unlearned, the self tier cast " .. tostring(record.spell));

        interp.state.known["Remove Corruption"] = true;
        _, _, record = interp:evalKey("F7");
        check(record and record.castModifier == Constants.CASTMOD_SELF and record.spell ~= nil,
            "learned, the self tier did not cast the dispel: " .. tostring(record and record.spell));

        interp:resetState();
        shim.world.specIndex = nil;
    end);

    -- Ticked is the reader asking for the key to be handed on, so nothing holds it.
    test("a ticked dispel hands the key on while its spell is not known", function()
        if (shipped) then
            return;
        end
        shim.world.specIndex = 1;
        shim.world.spells[2782] = { name = "Remove Corruption" };
        shim.world.spells[8936] = { name = "Regrowth" };
        Bind({
            action({ type = Constants.DISPEL, key = "F6", conditions = { known = true } }),
            action({ type = Constants.SPELL, key = "F6", value = 8936 }),
        });
        local records = castmod.without(Constants, interp:recordsFor("F6"));
        check(#records == 2, "records on F6: " .. #records);
        check(winner("F6") == 2, "the spell behind did not take the key");
        shim.world.specIndex = nil;
    end);

    -- **Nothing here is opaque to the solver** (`Solver.lua`). Each id stands on the ordinary
    -- `known` axis, so a gated dispel is covered and ordered like any other binding. It used to be
    -- opaque, and then an unconditional action in front of it left it on the key with no mark and
    -- no press it could ever win.
    --
    -- **Importance is what puts the spell in front of the ticked one.** A ticked dispel carries
    -- `known` and so has conditions, which stand it ahead of an action without them on its own.
    test("a gated dispel behind an unconditional action is unreachable", function()
        withGate(WARLOCK_GATE, function()
            warlockWorld();
            shim.world.spells[8936] = { name = "Regrowth" };

            local spell = action({ type = Constants.SPELL, key = "F3", value = 8936,
                priority = Constants.DEFAULT_IMPORTANCE - 1 });
            local ticked = action({ type = Constants.DISPEL, key = "F3",
                conditions = { known = true } });
            local plain = action({ type = Constants.DISPEL, key = "F4" });
            local ahead = action({ type = Constants.SPELL, key = "F4", value = 8936 });
            ahead.seq, plain.seq = plain.seq, ahead.seq;
            Bind({ spell, ticked, plain, ahead });

            check(DebindPrivate.IsUnreachableAction(ticked) == true,
                "a ticked one behind an unconditional action was left reachable");
            check(DebindPrivate.IsUnreachableAction(plain) == true,
                "a plain one behind an unconditional action was left reachable");
            check(DebindPrivate.IsUnreachableAction(spell) == false,
                "the action in front was deleted");
        end);
    end);

    -- The press takes either answer for an id: the conditional, or the spell book. Neither is what
    -- sends the key on to the action behind it.
    test("an id in the book answers a known the conditional cannot", function()
        if (shipped) then
            return;
        end
        withGate(WARLOCK_GATE, function()
            warlockWorld();
            shim.world.spells[8936] = { name = "Regrowth" };
            Bind({
                action({ type = Constants.DISPEL, key = "F3", conditions = { known = true } }),
                action({ type = Constants.SPELL, key = "F3", value = 8936 }),
            });

            -- Records 1 and 2 are the dispel's two ids and 3 is the spell behind it.
            shim.world.spellbook[119905] = true;
            check(winner("F3") == 2, "with the imp out the dispel did not fire");

            shim.world.spellbook[119905] = nil;
            shim.world.spellbook[132411] = true;
            check(winner("F3") == 1, "with the imp swallowed the dispel did not fire");

            shim.world.spellbook[132411] = nil;
            check(winner("F3") == 3, "with neither in the book the key did not fall through");
        end);
    end);

    -- A body names one spell, and these three have none of their own to name: the specialization
    -- picks it at the rebuild.
    test("a spec-resolved type is not offered custom macro conversion", function()
        withGate(WARLOCK_GATE, function()
            warlockWorld();
            check(DebindPrivate.CanConvertToMacroText(action({ type = Constants.DISPEL, key = "F3" }))
                == false, "the dispel offered conversion");
            check(DebindPrivate.CanConvertToMacroText(action({ type = Constants.DISPEL, key = "F3",
                conditions = { known = true } })) == false, "the ticked dispel offered conversion");
        end);
    end);

    return T;
end
