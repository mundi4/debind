-- **Which action a key fires, asked without the game.**
--
-- Everything above this file measures what a rebuild decided. This one runs the decision: the
-- emitted records go into a restricted environment, `EVAL_SNIPPET` walks them, and the winner is
-- read back (`devdocs/legacy/going-headless-outside-the-ui.md` §5, `tests/restricted.lua`).
--
-- These came down from `/debtest`, where they were the only layer that could see them. What each
-- one gives up by coming down is the same three things (§8): whether the sandbox would compile the
-- body at all, whether a real press arrives under the button name we bound, and what the action
-- button does once it has one. **The two `Multi-axis:` sweeps stay in both places** -- they are the
-- anchor, and if this interpretation and the game ever part, that is where it shows.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    --- **In the shipped shape there is nothing here to run, and that is the check.**
    ---
    --- Every case below reaches the decision through `EvalClickTimeKey`, an attribute
    --- `SecureBindings.lua` sets only under `DEBUG` -- a way to ask the click path what it would
    --- pick without hardware input, which a released build has no business carrying. So the
    --- shipped pass asks the one question that is left: **is it really not there.** A hook that
    --- shipped would be a test entry point on every user's driver frame, reachable by anything
    --- that can run a snippet.
    if (ctx and ctx.shipped) then
        local driver = DebindPrivate.BindingDriver;
        if (driver:GetAttribute("EvalClickTimeKey") ~= nil
                or driver:GetAttribute("EvalClickCastFrame") ~= nil) then
            T.failures[#T.failures + 1] =
                "the DEBUG-only eval hooks are installed in the shipped shape";
        else
            T.passed = T.passed + 1;
        end
        return T;
    end

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

    --- A registered unit frame, for the click-cast test far below.
    ---
    --- **Registered before the first rebuild, on purpose.** The interpreter is stood up on
    --- everything recorded so far and fed each rebuild after that, so anything that has to be in
    --- its world has to cross before it exists -- a registration slipped in between two rebuilds
    --- would be in neither window.
    local unitFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(unitFrame, "group");
    unitFrame:SetAttribute("unit", "party1");

    local seq = 0;
    --- One action, in the shape the profile stores. `seq` runs on its own so the order actions
    --- are written in is the order they sit in the layer.
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    --- Stands a profile up, rebuilds, and hands back the interpreter with the new records in it.
    ---
    --- **The interpreter is built once and fed each rebuild after that.** Standing a new one up
    --- would mean replaying the login setup again for every test, and the login setup is what
    --- creates the tables -- replaying it twice into one environment is not what the game does.
    local function Bind(actions, switches, options)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches or {},
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

    --- Which record wins on this key right now, by its place among the records that are not self or
    --- focus twins. Every action has both, and a press with no modifier held never reaches them;
    --- the cases about the twins read `interp:evalKey` itself.
    local function winner(key)
        return castmod.index(Constants, interp:recordsFor(key), (interp:evalKey(key)));
    end

    ---------------------------------------------------------------------------
    -- The client's own targeting branches
    ---------------------------------------------------------------------------

    -- **All three of the client's targeting branches are off.** Mouseover cast cannot reach a right
    -- answer on our button (`CalculateAction` answers slot 1 for it), and self cast and focus cast
    -- are the click wrapper's to decide now: left on, they would still redirect every press that
    -- fires with no unit, in the order the addon took them over to fix
    -- (`devdocs/implementing-focus-and-self-cast.md` §1, §3-7).
    --
    -- A key press and a frame click are both run through the wrapper here, since the wrapper used
    -- to write two of them on every click.
    test("the client's three targeting branches stay off", function()
        -- Named before the first bind: the button a type and value get is stamped once and cached,
        -- and the cases below read the name off it.
        shim.world.spells[585] = { name = "Renew" };
        Bind({
            action({ value = 585, key = "F1" }),
            action({ value = 585, key = "BUTTON2", ignoreHoverUnit = true,
                conditions = { units = { hover = { reaction = Constants.REACTION_ALL } } } }),
        });
        local clickFrame = DebindPrivate.DefaultClickFrame;
        shim.world.units = { party1 = { id = "friend", reaction = "help" } };

        local function allOff(when)
            for _, name in ipairs({ "checkmouseovercast", "checkselfcast", "checkfocuscast" }) do
                check(clickFrame:GetAttribute(name) == false,
                    when .. ": " .. name .. " is " .. tostring(clickFrame:GetAttribute(name)));
            end
        end

        allOff("at login");
        interp:runWrapped(clickFrame, "OnClick", Constants.CLICKTIME_BUTTON_PREFIX .. "F1", true);
        allOff("after a key press");
        interp:clickFrame(unitFrame, "RightButton", false);
        interp:runWrapped(clickFrame, "OnClick", "debind1", false);
        allOff("after a frame click");

        shim.world.units = {};
    end);


    -- **A target the reader chose is the whole condition for the detour.** The press comes back
    -- with a twin button whose body switches the engine's automatic self-cast off around the real
    -- one, and the target goes on the cast frame rather than on the wrapped click frame -- the
    -- wrapper's own prologue would wipe it off that one.
    --
    -- Without the detour the same profile answers two ways: a chosen unit that exists casts and
    -- the engine redirects it to the caster, and one that does not exist is dropped by the
    -- client's `UnitExists` guard with nothing happening at all.
    test("a chosen target takes the self-cast-off route", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        shim.world.spells[8936] = { name = "Regrowth", pressAndHold = true };
        Bind({
            action({ value = 585, key = "F1", unit = "focus" }),
            action({ value = 774, key = "F2" }),
            action({ value = 8936, key = "F3", unit = "focus" }),
        });

        local clickFrame = DebindPrivate.DefaultClickFrame;

        local _, chosen = interp:evalKey("F1");
        check(clickFrame:GetAttribute("*type-" .. chosen) == "macro",
            "a chosen target did not reach the twin: " .. tostring(chosen));
        check(clickFrame:GetAttribute("*macrotext-" .. chosen) ==
            '/run DebindAutoSelfCast=GetCVar("autoSelfCast");SetCVar("autoSelfCast","0")\n'
            .. '/click DebindCastButton ' .. interp:actionButton(chosen) .. '\n'
            .. '/run SetCVar("autoSelfCast",DebindAutoSelfCast)',
            "the twin's body: " .. tostring(clickFrame:GetAttribute("*macrotext-" .. chosen)));
        check(clickFrame:GetAttribute("*spell-" .. interp:actionButton(chosen)) == "Renew",
            "the twin clicks the wrong button: " .. tostring(interp:actionButton(chosen)));

        -- **The target goes on the cast frame**, because that is the one the body clicks and the
        -- only one nothing wipes between the decision and the cast.
        check(DebindPrivate.CastFrame:GetAttribute("unit") == "focus",
            "the cast frame's unit: " .. tostring(DebindPrivate.CastFrame:GetAttribute("unit")));

        -- **No target chosen, no detour.** The game's own rules are what the reader gets, which is
        -- both self-cast branches and the automatic one.
        local _, plain = interp:evalKey("F2");
        check(clickFrame:GetAttribute("*type-" .. plain) == "spell",
            "an untargeted spell took the detour: " .. tostring(plain));

        -- **Press-and-hold keeps the direct route even with a target chosen.** A macro runs once
        -- and the hold the gate starts on the down edge has no release to pair with inside one.
        local _, held = interp:evalKey("F3");
        check(clickFrame:GetAttribute("*type-" .. held) == "spell",
            "a press-and-hold spell took the detour: " .. tostring(held));
    end);

    ---------------------------------------------------------------------------
    -- The binding types
    ---------------------------------------------------------------------------

    -- **What a press ends at is a button name**, and the attributes under that name are what the
    -- game reads to fire the action. So the two halves are checked together: the record picked,
    -- and what is stamped on the button it names.
    test("each type reaches the attributes that fire it", function()
        shim.world.spells[585] = { name = "Renew" };
        Bind({
            action({ value = 585, key = "F1" }),
            action({ type = Constants.ITEM, value = 6948, key = "F2" }),
            action({ type = Constants.MACROTEXT, value = "/cast Renew", key = "F3" }),
            action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "F4" }),
            action({ type = Constants.TARGET, key = "F5", unit = "focus" }),
            action({ type = Constants.USESLOT, value = 13, key = "F6" }),
        });

        local clickFrame = DebindPrivate.DefaultClickFrame;
        local function attributesOf(key)
            local _, button = interp:evalKey(key);
            check(button, key .. " picked no action");
            button = interp:actionButton(button);
            return clickFrame:GetAttribute("*type-" .. button),
                clickFrame:GetAttribute("*spell-" .. button)
                or clickFrame:GetAttribute("*item-" .. button)
                or clickFrame:GetAttribute("*macrotext-" .. button);
        end

        local spellType, spellValue = attributesOf("F1");
        check(spellType == "spell" and spellValue == "Renew", "spell: " .. tostring(spellValue));

        local itemType, itemValue = attributesOf("F2");
        check(itemType == "item" and itemValue == "item:6948", "item: " .. tostring(itemValue));

        -- **An equipment slot is the same attribute with a different shape of value**, and the
        -- shape is the whole of it: `SecureCmdItemParse` reads a bare number as an inventory slot
        -- and `item:13` as an item id. Getting this wrong fires item 13 instead of the trinket,
        -- and nothing anywhere says so.
        local slotType, slotValue = attributesOf("F6");
        check(slotType == "item" and slotValue == "13", "equipslot: " .. tostring(slotValue));

        -- **And it keeps a target, because the game hands one on.** `SECURE_ACTIONS.item` passes
        -- its `unit` down to `UseInventoryItem(slot, target)`, so a slot aims exactly the way an
        -- item id does. A type left out of `TYPES_WITH_UNIT` has its unit wiped on the way to the
        -- binding while the window still shows the one that was picked -- the fault that list was
        -- made single for.
        local targeted = DebindPrivate.GetBindingInfoForAction(
            { type = Constants.USESLOT, value = 13, key = "F7", unit = "focus" });
        check(targeted.unit == "focus",
            "equipslot lost its unit: " .. tostring(targeted.unit));

        local textType, textValue = attributesOf("F3");
        check(textType == "macro" and textValue == "/cast Renew", "macrotext: " .. tostring(textValue));

        local targetType = attributesOf("F5");
        check(targetType == "target", "target: " .. tostring(targetType));
    end);

    -- **Unused wins by having nothing to fire.** A key whose conditional action does not match
    -- falls through to it, and the press answers with no button at all.
    test("unused wins the key and fires nothing", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true } }),
            action({ type = Constants.UNUSED, key = "F1" }),
        });

        interp.state.combat = true;
        check(winner("F1") == 1, "the conditional action did not win in combat");

        interp.state.combat = false;
        local index, button = interp:evalKey("F1");
        check(index == nil and button == nil, "unused fired something: " .. tostring(button));
        interp:resetState();
    end);

    ---------------------------------------------------------------------------
    -- One axis at a time
    ---------------------------------------------------------------------------

    --- Every plain axis, with the world that makes it true. Two actions per key: the first
    --- carries the condition, the second is the fallback -- so **both directions are asked in
    --- one pass** and a test that only ever set the state would also pass on a condition nobody
    --- reads.
    local AXES = {
        { name = "combat", conditions = { combat = true }, on = function(s) s.combat = true; end },
        { name = "stealth", conditions = { stealth = true }, on = function(s) s.stealth = true; end },
        { name = "extrabar", conditions = { extrabar = true }, on = function(s) s.extrabar = true; end },
        { name = "petbattle", conditions = { petbattle = true }, on = function(s) s.petbattle = true; end },
        { name = "specialbar", conditions = { specialbar = true },
            on = function(s) s.vehiclebar = true; end },
        { name = "groups", conditions = { groups = Constants.GROUP_RAID },
            on = function(s) s.group = "raid"; end },
        -- **The form axis is a bit, and what the client answers is an index.** The condition is a
        -- mask over `2^index`, so form 2 is bit 4 -- getting that shift wrong is a class of fault
        -- the two sides used to be able to disagree about.
        { name = "forms", conditions = { forms = 4 }, on = function(s) s.form = 2; end },
        { name = "bonusbars", conditions = { bonusbars = 8 }, on = function(s) s.bonusbar = 3; end },
        { name = "mounted", conditions = { mounted = true }, on = function(s) s.mounted = true; end },
        { name = "indoors", conditions = { indoors = true }, on = function(s) s.indoors = true; end },
        -- **The one axis here whose world is a number rather than a flag.** `skyriding` reads the
        -- same `GetBonusBarOffset()` that `bonusbars` above reads, so what turns it on is that
        -- offset landing on `BONUSBAR_SKYRIDING` -- and a press that read the offset as a bit, or
        -- compared against the wrong number, fails here rather than in the game.
        { name = "skyriding", conditions = { skyriding = true },
            on = function(s) s.bonusbar = Constants.BONUSBAR_SKYRIDING; end },
        -- **Area predicates, not state.** They answer what the zone allows rather than what the
        -- reader is doing, which is what lets several mounts on one key pick themselves. Both
        -- also read a function whose name is one word off the other's, so the pair is here as
        -- much to catch a swap as to check the wiring.
        { name = "flyable", conditions = { flyable = true }, on = function(s) s.flyable = true; end },
        { name = "advflyable", conditions = { advflyable = true },
            on = function(s) s.advflyable = true; end },
        -- The pair of `flyable` above, and the one that is not about the zone: whether the reader
        -- is off the ground. Their functions differ by one word too.
        { name = "flying", conditions = { flying = true }, on = function(s) s.flying = true; end },
    };

    test("every axis decides the press, both ways", function()
        for i = 1, #AXES do
            local axis = AXES[i];
            Bind({
                action({ value = 585, key = "F1", conditions = axis.conditions }),
                action({ value = 774, key = "F1" }),
            });

            check(winner("F1") == 2, axis.name .. ": the fallback did not win with the axis off");

            axis.on(interp.state);
            check(winner("F1") == 1, axis.name .. ": the condition did not win with the axis on");
            interp:resetState();
        end
    end);

    -- **`specialbar` is three bars folded into one value, plus pet battle.** Any one of them turns
    -- it on, which is what the state loop measures too -- if the two sides folded it differently
    -- the same world would answer two ways.
    test("specialbar answers to each of the bars it folds", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { specialbar = true } }),
            action({ value = 774, key = "F1" }),
        });

        local FOLDS = { "vehiclebar", "overridebar", "shapeshiftbar", "petbattle" };
        for i = 1, #FOLDS do
            interp:resetState();
            check(winner("F1") == 2, FOLDS[i] .. ": it won with nothing on");
            interp.state[FOLDS[i]] = true;
            check(winner("F1") == 1, FOLDS[i] .. " did not turn specialbar on");
        end
        interp:resetState();
    end);

    -- A `known` condition is answered by parsing the conditional the record carries. The value it
    -- names is the spell, and `true` is the action's own, named at the bake
    -- (`devdocs/making-known-a-spell-name.md`). The state loop reads the same string as a key in
    -- `States`.
    test("a known condition follows the spell book", function()
        Bind({
            action({ value = 8936, key = "F1", conditions = { known = true } }),
            action({ value = 774, key = "F1" }),
        });

        check(winner("F1") == 2, "the known action won without the spell");
        interp.state.known["Regrowth"] = true;
        check(winner("F1") == 1, "the known action did not win with the spell");
        interp:resetState();
    end);

    -- **The same two outcomes, reached at the rebuild instead of at the press.** A `known` the
    -- rebuild can settle carries no axis at all, or takes its record out of the key
    -- (`devdocs/baking-the-known-condition.md` §5) -- and the press has to land where it lands
    -- today either way. That is the whole claim the optimization rests on, and the restricted
    -- side is the only thing that can check it.
    --
    -- **The restricted side is never told about either spell.** A record that still carried the
    -- axis would ask `[known:]` here and lose, so the settled-true action winning is what says
    -- the axis is really gone rather than merely quiet.
    test("a known settled at the rebuild lands where a measured one does", function()
        for spellID, learned in pairs({ [1000] = true, [1001] = false }) do
            shim.world.spellbook[spellID] = true;
            shim.world.spells[spellID] = { name = "Spell " .. spellID, levelLearned = 10 };
            shim.world.knownSpells[spellID] = learned or nil;
        end

        Bind({
            action({ value = 1000, key = "F1", conditions = { known = true } }),
            action({ value = 774, key = "F1" }),
            action({ value = 1001, key = "F2", conditions = { known = true } }),
            action({ value = 774, key = "F2" }),
        });

        check(winner("F1") == 1, "the settled-true action did not win");

        -- **The record count, not only the winner.** With the dropped record still emitted, the
        -- fallback would sit at index 2 and this key would answer 2; asserting the count is what
        -- keeps "it was dropped" apart from "it lost".
        local f2 = castmod.without(Constants,
            interp.env.ClickTimeKeys[Constants.CLICKTIME_BUTTON_PREFIX .. "F2"]);
        check(#f2 == 1, "the settled-false record was emitted: " .. #f2);
        check(winner("F2") == 1, "the fallback did not win the key");
        interp:resetState();
    end);

    -- A switch is the one axis the press does **not** measure: there is nothing to measure, the
    -- stored value is the original, so it is read straight out of `States`.
    test("a switch condition is read out of the shared state", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { ["$burst"] = true } }),
            action({ value = 774, key = "F1" }),
        }, { ["$burst"] = { mode = Constants.SWITCH_MODES.MANUAL } });

        check(winner("F1") == 2, "the switch action won with the switch off");
        interp.env.States["$burst"] = true;
        check(winner("F1") == 1, "the switch action did not win with the switch on");
        interp.env.States["$burst"] = false;
    end);

    ---------------------------------------------------------------------------
    -- Units
    ---------------------------------------------------------------------------

    -- **Existence, reaction and life are three axes on one unit**, and the press measures each of
    -- them again rather than reading what the poll left -- a click is where the truth can be had.
    test("a unit condition is measured at the press", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = {};
        check(winner("F1") == 2, "the unit action won with no unit there");

        shim.world.units = { target = { id = "friend", reaction = "help" } };
        check(winner("F1") == 1, "the unit action did not win on a friendly target");

        shim.world.units = { target = { id = "enemy", reaction = "harm" } };
        check(winner("F1") == 2, "a hostile target matched a friendly condition");

        shim.world.units = {};
    end);

    -- Life is the axis a poll cannot be asked to stand up on demand, and the one the press has to
    -- get right: a heal sent at a corpse is a wasted global cooldown.
    test("the life axis splits a living unit from a dead one", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { dead = true } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "friend", reaction = "help" } };
        check(winner("F1") == 2, "the dead condition won on a living unit");

        shim.world.units = { target = { id = "friend", reaction = "help", dead = true } };
        check(winner("F1") == 1, "the dead condition lost on a corpse");

        -- **A ghost is dead**, which `UnitIsDead` alone does not say -- and the restricted
        -- environment has no `UnitIsDeadOrGhost`, so both have to be asked.
        shim.world.units = { target = { id = "friend", reaction = "help", ghost = true } };
        check(winner("F1") == 1, "a ghost read as alive");

        shim.world.units = {};
    end);

    -- **The overlap, at the press.** The two predicates are not exclusive: a raid member in the
    -- reader's own subgroup answers true to both. So [in my party] has to keep reaching the people
    -- beside the reader once the party becomes a raid, which is the whole reason this axis is
    -- three overlapping boxes rather than three values picked by an ordered chain.
    --
    -- The third world is what stops this passing on a stub that answers true to everything.
    test("in my party reaches a raid member in my own subgroup", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { group = Constants.UNITGROUP_PARTY } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "mate", inParty = true } };
        check(winner("F1") == 1, "a party condition missed a plain party member");

        shim.world.units = { target = { id = "mate", inParty = true, inRaid = true } };
        check(winner("F1") == 1,
            "a party condition missed a raid member in my own subgroup");

        shim.world.units = { target = { id = "other", inRaid = true } };
        check(winner("F1") == 2,
            "a party condition caught a raid member in another subgroup");

        shim.world.units = { target = { id = "stranger" } };
        check(winner("F1") == 2, "a party condition caught an outsider");

        shim.world.units = {};
    end);

    -- **Two group conditions on one unit, which is the case the three boxes cannot represent.**
    -- `"@"` and an explicit condition on the same unit are merged before anything is emitted, and
    -- [in my party] meeting [in my raid] leaves exactly one cell: in the raid, in my own subgroup.
    -- No combination of the three boxes says that, so intersecting the stored bits answers zero,
    -- the record is dropped as unsatisfiable, and the key quietly does nothing.
    test("in my party and in my raid on one unit leave the shared cell", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = {
                    ["@"] = { group = Constants.UNITGROUP_PARTY },
                    target = { group = Constants.UNITGROUP_RAID },
                } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "mate", inParty = true, inRaid = true } };
        check(winner("F1") == 1,
            "the intersection lost the raid member in my own subgroup");

        shim.world.units = { target = { id = "mate", inParty = true } };
        check(winner("F1") == 2, "a plain party member passed both conditions");

        shim.world.units = { target = { id = "other", inRaid = true } };
        check(winner("F1") == 2, "a raid member in another subgroup passed both conditions");

        shim.world.units = {};
    end);

    test("not in my group is the outsider and nobody else", function()
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { group = Constants.UNITGROUP_NONE } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "stranger" } };
        check(winner("F1") == 1, "an outsider failed [not in my group]");

        shim.world.units = { target = { id = "mate", inParty = true } };
        check(winner("F1") == 2, "a party member passed [not in my group]");

        shim.world.units = { target = { id = "other", inRaid = true } };
        check(winner("F1") == 2, "a raid member passed [not in my group]");

        shim.world.units = {};
    end);

    -- **The case that shipped unverified.** One key asks whether the focus exists; another asks
    -- whether it is friendly. Under the old encoding, *registering* the reaction axis changed what
    -- the measured value **meant** -- with nobody asking about reaction a friendly unit came back
    -- as `true` -- so the second key's condition silently decided the first key's. The symptom was
    -- key one dying for no reason anyone could see from key one.
    --
    -- It went out in 3.1.1 with the secure half checked by a one-off script and nothing else
    -- (`.zzz/TODO.md` E-7). Both halves are asked here: the press, and the poll that takes the key.
    test("a reaction condition on one key does not decide another key's", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { units = { focus = {} } } }),
            action({ value = 774, key = "F2",
                conditions = { units = { focus = { reaction = Constants.REACTION_HELP } } } }),
        });

        shim.world.units = { focus = { id = "friend", reaction = "help" } };
        check(winner("F1") == 1, "the existence key did not fire on a friendly focus");
        check(winner("F2") == 1, "the friendly key did not fire on a friendly focus");

        shim.world.units = { focus = { id = "enemy", reaction = "harm" } };
        check(winner("F1") == 1,
            "the existence key died on a hostile focus -- another key's reaction decided it");
        check(winner("F2") == nil, "the friendly key fired on a hostile focus");

        shim.world.units = {};
        check(winner("F1") == nil, "the existence key fired with the focus gone");
    end);

    ---------------------------------------------------------------------------
    -- Order
    ---------------------------------------------------------------------------

    -- **The first record that matches wins**, so the order they were emitted in is the order the
    -- reader set. A conditional action placed above an unconditional one is the ordinary shape,
    -- and the unconditional one must not be able to take the press from it.
    test("the first matching record wins", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true, stealth = true } }),
            action({ value = 774, key = "F1", conditions = { combat = true } }),
            action({ value = 8936, key = "F1" }),
        });

        check(winner("F1") == 3, "the fallback did not win at rest");

        interp.state.combat = true;
        check(winner("F1") == 2, "the wider condition did not win in combat");

        interp.state.stealth = true;
        check(winner("F1") == 1, "the narrower condition lost to the wider one");
        interp:resetState();
    end);

    ---------------------------------------------------------------------------
    -- How the key is wired
    ---------------------------------------------------------------------------

    --- Which of the two the key came out as. Read off the tables the restricted side actually
    --- holds, rather than the copies baked beside them.
    local function wiring(key)
        local button = Constants.CLICKTIME_BUTTON_PREFIX .. key;
        return {
            clickTime = interp.env.ClickTimeKeys[button] ~= nil,
            bound = interp.bindings[key] ~= nil,
        };
    end

    -- A key that only click-casts holds no key-binding record at all, so it must not be bound: the
    -- world click and the camera stay the game's.
    test("a click-casting-only key is not bound", function()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_ALL } } } }),
        });

        local how = wiring("BUTTON2");
        check(not how.clickTime, "a click-cast-only key was registered as a click-time key");
        check(not how.bound, "a click-cast-only key was bound");

        -- It is registered where a click that arrives on a unit frame can find it, which is the
        -- one table it does belong in.
        check(interp.env.ClickCastKeys[2] and interp.env.ClickCastKeys[2][0],
            "the click-cast registration is missing");
    end);

    -- **A click that arrives on a unit frame judges the conditions on the frame**, not from the
    -- hover cache -- the frame that was clicked is the hover, so there is nothing to look up.
    -- Answering nil is the fall-through: the click carries on into the frame's own handler, which
    -- is only reachable from that side.
    test("a click-cast click is judged against the frame it arrived on", function()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
        });

        shim.world.units = { party1 = { id = "friend", reaction = "help" } };
        check(interp:evalClickCast(unitFrame, 2, 0), "a friendly unit frame was declined");

        shim.world.units = { party1 = { id = "enemy", reaction = "harm" } };
        check(interp:evalClickCast(unitFrame, 2, 0) == nil,
            "a hostile unit frame was taken by a friendly condition");

        shim.world.units = {};
        check(interp:evalClickCast(unitFrame, 2, 0) == nil, "an empty unit frame was taken");
    end);

    ---------------------------------------------------------------------------
    -- Self cast and focus cast (`devdocs/implementing-focus-and-self-cast.md`)
    ---------------------------------------------------------------------------

    --- Two actions on F1: a heal that asks for a friendly target, and a plain one behind it. Both
    --- aim at `target`, so a press with nothing held goes where they say.
    local function ModifierBind()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ value = 774, key = "F1", unit = "target" }),
        });
    end

    --- What a press fires: the record, the spell on the button it clicks, and the unit it goes at.
    local function Fired(key)
        local _, button, record = interp:evalKey(key);
        if (not button) then
            return nil;
        end
        return record, DebindPrivate.DefaultClickFrame:GetAttribute("*spell-" .. interp:actionButton(button)),
            DebindPrivate.CastFrame:GetAttribute("unit");
    end

    -- **The held modifier is what the press means, and the reader's condition goes with it** (§3-1,
    -- §3-6). The `@` that asked whether the target is friendly asks it of the player once self cast
    -- is held -- so the heal goes out at a friendly player over a hostile target, and a hostile
    -- player falls to the next action, still at the player.
    test("a held self-cast modifier sends the press at the player", function()
        ModifierBind();
        shim.world.units = { target = { id = "enemy", reaction = "harm" },
            player = { id = "me", reaction = "help" } };

        check(winner("F1") == 2, "nothing held, hostile target: " .. tostring(winner("F1")));

        interp.state.modifiedClick.SELFCAST = true;
        local record, spell, unit = Fired("F1");
        check(record and record.castModifier == Constants.CASTMOD_SELF,
            "the winner is not a self twin: " .. tostring(record and record.castModifier));
        check(spell == "Renew" and unit == "player", "fired " .. tostring(spell) .. " at " .. tostring(unit));

        shim.world.units.player = { id = "me", reaction = "harm" };
        record, spell, unit = Fired("F1");
        check(spell == "Rejuvenation" and unit == "player",
            "a hostile player: fired " .. tostring(spell) .. " at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    -- **Focus cast never falls back to the target** (§3-2). The first action's condition fails on
    -- a hostile focus, and what wins is the next action's focus twin -- not the first action at the
    -- friendly target the press would have reached with nothing held.
    test("a held focus-cast modifier keeps to the focus", function()
        ModifierBind();
        shim.world.units = { target = { id = "friend", reaction = "help" },
            focus = { id = "enemy", reaction = "harm" } };

        check(winner("F1") == 1, "nothing held, friendly target: " .. tostring(winner("F1")));

        interp.state.modifiedClick.FOCUSCAST = true;
        local record, spell, unit = Fired("F1");
        check(record and record.castModifier == Constants.CASTMOD_FOCUS,
            "the winner is not a focus twin: " .. tostring(record and record.castModifier));
        check(spell == "Rejuvenation" and unit == "focus",
            "fired " .. tostring(spell) .. " at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    -- **With no target picked, `@` is asked of `target`, and the press still carries no unit**
    -- (§3-6). The game keeps deciding where the cast goes; the condition only decides whether this
    -- action is the one that goes. The shape the decision was made on: an attack for enemies ahead
    -- of a heal, where a friendly target has to fall through to the heal.
    test("with no target picked the resolved target's condition is asked of the target", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
            action({ value = 774, key = "F1" }),
        });

        shim.world.units = { target = { id = "friend", reaction = "help" } };
        check(winner("F1") == 2, "a friendly target: " .. tostring(winner("F1")));

        shim.world.units = { target = { id = "enemy", reaction = "harm" } };
        check(winner("F1") == 1, "a hostile target: " .. tostring(winner("F1")));
        local _, button, record = interp:evalKey("F1");
        check(record and record.unit == nil and record.unitAlias == nil,
            "the press carries a unit: " .. tostring(record and (record.unit or record.unitAlias)));
        check(button == interp:actionButton(button), "the press took the route that turns Auto Self Cast off");

        shim.world.units = {};
    end);

    -- The client's own order: `checkselfcast` is read first and ends it (§3-3).
    test("both modifiers held is self cast", function()
        ModifierBind();
        shim.world.units = { player = { id = "me", reaction = "help" },
            focus = { id = "friend", reaction = "help" } };

        interp.state.modifiedClick.SELFCAST = true;
        interp.state.modifiedClick.FOCUSCAST = true;
        local _, spell, unit = Fired("F1");
        check(spell == "Renew" and unit == "player", "fired " .. tostring(spell) .. " at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    -- **A frame click ignores what is held** (§3-10). A modifier on a click arrives only with the
    -- binding made for that exact combination, so it picked the binding and says nothing about the
    -- target. The click goes at the frame's unit whatever `IsModifiedClick` answers.
    test("a frame click goes at the frame with a modifier held", function()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
        });
        shim.world.units = { party1 = { id = "friend", reaction = "help" },
            player = { id = "me", reaction = "help" }, focus = { id = "friend", reaction = "help" } };
        interp.state.modifiedClick.SELFCAST = true;
        interp.state.modifiedClick.FOCUSCAST = true;

        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1", "the frame click was declined");
        local handed = interp.env.HandoffWinner;
        check(handed and not castmod.isTwin(Constants, handed),
            "a twin took the frame click: " .. tostring(handed and handed.castModifier));
        interp:runWrapped(DebindPrivate.DefaultClickFrame, "OnClick", "debind1", false);
        local unit = DebindPrivate.CastFrame:GetAttribute("unit");
        check(unit == "party1", "the click went at " .. tostring(unit));

        interp:resetState();
        shim.world.units = {};
    end);

    ---------------------------------------------------------------------------
    -- The key laid out in tiers (`devdocs/implementing-focus-and-self-cast.md` §3-4)
    ---------------------------------------------------------------------------

    local FRIEND = { id = "friend", reaction = "help" };
    local ENEMY = { id = "enemy", reaction = "harm" };

    --- The unit a record goes out at, whichever field carries it.
    local function Aimed(record)
        return record and (record.unit or record.unitAlias);
    end

    --- Which of the key's originals a winning record came from, by the button both click.
    local function ActionOf(key, record)
        local originals = castmod.without(Constants, interp:recordsFor(key));
        for i = 1, #originals do
            if (originals[i].clickbutton == record.clickbutton) then
                return i;
            end
        end
    end

    local function PointAt(unit)
        unitFrame:SetAttribute("unit", unit);
        interp:hoverEnter(unitFrame);
    end

    -- **Every hover twin stands ahead of every original** (§3-4, 2026-09-13, owner). An attack for
    -- hostile units ahead of a heal for friendly ones, neither with a target picked, Hover Cast on.
    -- With each twin beside its own original, a press over a friendly frame with a hostile target
    -- reached the attack's original before the heal's twin, and the attack went at the target; over
    -- a hostile frame with a friendly target the attack went at the frame. One key, two rules.
    test("a pointed unit is tried for every action before any target is", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
            action({ value = 774, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
        }, nil, { hoverCast = true });

        shim.world.units = { target = ENEMY, party1 = FRIEND };
        PointAt("party1");
        local record, spell = Fired("F1");
        check(spell == "Rejuvenation" and Aimed(record) == "hover",
            "hostile target, friendly frame: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        shim.world.units = { target = FRIEND, party1 = ENEMY };
        record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == "hover",
            "friendly target, hostile frame: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    -- **A hover twin is ordered as the action the reader would have made by hand**: the same spell
    -- with [pointing at a unit] on it (§3-4). Ordered by its own action, the twin of an action with
    -- no condition stood behind every action with a hover condition, whichever came first.
    test("hover twins keep the order the reader put the actions in", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        for _, case in ipairs({ { "plain", "Rejuvenation" }, { "hover", "Renew" } }) do
            local plain = { value = 774, key = "F1" };
            local hovered = { value = 585, key = "F1", conditions = { units = { hover = {} } } };
            if (case[1] == "plain") then
                Bind({ action(plain), action(hovered) }, nil, { hoverCast = true });
            else
                Bind({ action(hovered), action(plain) }, nil, { hoverCast = true });
            end
            shim.world.units = { party1 = FRIEND };
            PointAt("party1");
            local record, spell = Fired("F1");
            check(spell == case[2] and Aimed(record) == "hover",
                case[1] .. " first: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));
            interp:hoverLeave(unitFrame);
        end
        shim.world.units = {};
    end);

    -- **An action that takes no unit has the twins too** (§3-4). Placed first, a macro carried no
    -- modifier column and answered every held modifier, so nothing behind it could be focus cast.
    -- A held modifier is now answered in its own tier: the spell's twin where its condition holds on
    -- the focus, and otherwise the macro's -- carrying `focus`, which is what lets the client's own
    -- `UnitExists` guard stop it where there is no focus, as it does on an action bar.
    test("a macro placed ahead of a spell answers a held focus cast key as a focus cast", function()
        shim.world.spells[585] = { name = "Renew" };
        Bind({
            action({ type = Constants.MACROTEXT, value = "/say hi", key = "F1" }),
            action({ value = 585, key = "F1",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
        });
        interp.state.modifiedClick.FOCUSCAST = true;

        for _, case in ipairs({ { FRIEND, 1, "a friendly focus" }, { ENEMY, 2, "a hostile focus" },
                { nil, 2, "no focus" } }) do
            shim.world.units = { focus = case[1] };
            local _, _, record = interp:evalKey("F1");
            check(record and record.castModifier == Constants.CASTMOD_FOCUS,
                case[3] .. ": the winner is not a focus twin: " .. tostring(record and record.castModifier));
            check(ActionOf("F1", record) == case[2] and Aimed(record) == "focus",
                case[3] .. ": action " .. tostring(ActionOf("F1", record)) .. " at " .. tostring(Aimed(record)));
        end

        interp:resetState();
        shim.world.units = {};
    end);

    -- The same for a pet command whose handler takes no unit. Whether a focus exists is the client's
    -- guard to ask, so both answers pick the same twin here.
    test("a pet command that takes no unit is focus cast like any action", function()
        _G.SLASH_PET_FOLLOW1 = "/petfollow";
        Bind({ action({ type = Constants.PETACTION, value = "PET_FOLLOW", key = "F1" }) });
        interp.state.modifiedClick.FOCUSCAST = true;

        for _, focus in ipairs({ false, true }) do
            shim.world.units = { focus = focus and FRIEND or nil };
            local _, _, record = interp:evalKey("F1");
            check(record and record.castModifier == Constants.CASTMOD_FOCUS and Aimed(record) == "focus",
                "focus " .. tostring(focus) .. ": " .. tostring(record and record.castModifier)
                    .. " at " .. tostring(Aimed(record)));
        end

        interp:resetState();
        shim.world.units = {};
    end);

    -- **`none` has every twin and every one of them asks** (§3-4). Its twins stand in each tier the
    -- way any action's do, so an Always Ask action put first keeps the key whatever is held or
    -- pointed at -- and the cast still asks for a unit.
    test("an Always Ask action placed first answers a held key and a pointed unit by asking", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", unit = "none", priority = Constants.MIN_IMPORTANCE }),
            action({ value = 774, key = "F1" }),
        }, nil, { hoverCast = true });
        shim.world.units = { focus = FRIEND, party1 = FRIEND };

        interp.state.modifiedClick.FOCUSCAST = true;
        local record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == "none",
            "focus cast key: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));
        interp:resetState();

        PointAt("party1");
        record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == "none",
            "pointing: fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    -- **An action left out of Hover Cast still stands in the pointed tier** (§3-4). It goes out at
    -- its own target there; without a twin it waited in the last tier and the Hover Cast action
    -- behind it took every press made over a unit, whatever the reader had put first.
    test("an action left out of Hover Cast placed first keeps a pointed press at its own target", function()
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        Bind({
            action({ value = 585, key = "F1", ignoreHoverUnit = true, priority = Constants.MIN_IMPORTANCE }),
            action({ value = 774, key = "F1" }),
        }, nil, { hoverCast = true });
        shim.world.units = { target = FRIEND, party1 = FRIEND };

        PointAt("party1");
        local record, spell = Fired("F1");
        check(spell == "Renew" and Aimed(record) == nil,
            "fired " .. tostring(spell) .. " at " .. tostring(Aimed(record)));

        interp:hoverLeave(unitFrame);
        shim.world.units = {};
    end);

    ---------------------------------------------------------------------------
    -- Which edge of the click we take
    ---------------------------------------------------------------------------

    -- **Which edges arrive is the frame's state and not ours.** `RegisterForClicks` is set on the
    -- frame, so the last addon to call it decides for every wrapper on it, and a frame we put on
    -- the release can be moved to the press behind our back. `FrameRegistry` therefore asks for
    -- both, and the wrapper has to answer for both. Three rules come out of that, one test each:
    --
    --   * the release is the edge we act on, which is the one every unit frame Blizzard ships is
    --     registered for (`SecureUnitButton_OnLoad`);
    --   * a click we are not taking is left alone on both edges, so the frame's own action runs
    --     exactly where it would have;
    --   * a click we *are* taking is swallowed on the press as well, or the frame acts on the
    --     press and we act on the release and one click casts twice.
    --
    -- These run the shipped wrapper body (`interp:clickFrame`), not `EVAL_SNIPPET` with the
    -- prologue replaced -- the prologue is the whole of what is being asked about here.
    --- The reader's answer, put in the way the options menu puts it. `nil` is one of the three and
    --- means the game decides, so the CVar it falls to is set here alongside it.
    local function SetClickEdge(value, useKeyDown)
        DebindPrivate.Options.unitframeUseMouseDown = value;
        shim.world.cvars.ActionButtonUseKeyDown = useKeyDown;

        local mark = frames.mark();
        DebindPrivate.ApplyOptions("unitframeUseMouseDown");
        interp:replay(frames.since(mark));
    end

    local function ClickCastBind()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
            -- A second button, for the case where two are held at once.
            action({ value = 585, key = "BUTTON1", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
        });
        shim.world.units = { party1 = { id = "friend", reaction = "help" } };
        -- Nothing chosen and the game's own setting off, which is where a fresh install stands.
        SetClickEdge(nil, nil);
    end

    test("the release fires the binding", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not take the click");
    end);

    -- `debindnull` is a suffix nobody wrote an attribute for, so the press is taken and nothing
    -- runs on it -- the frame's own `type1` included.
    test("the press of a click we take is swallowed", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debindnull",
            "the press was left for the frame's own action");
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not fire after its press was swallowed");
    end);

    -- **Both edges of a click we decline are left alone**, so the frame keeps whichever one it
    -- acts on. Answering the press with `debindnull` here would eat clicks we have no binding for.
    test("a click we decline is left alone on both edges", function()
        ClickCastBind();
        shim.world.units = { party1 = { id = "enemy", reaction = "harm" } };
        check(interp:clickFrame(unitFrame, "RightButton", true) == nil,
            "the press of a declined click was swallowed");
        check(interp:clickFrame(unitFrame, "RightButton", false) == nil,
            "the release of a declined click was swallowed");
    end);

    -- A button we bound nothing to is declined the same way, and never reaches the eval at all.
    test("a button with no binding is left alone on both edges", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "MiddleButton", true) == nil,
            "the press of an unbound button was swallowed");
        check(interp:clickFrame(unitFrame, "MiddleButton", false) == nil,
            "the release of an unbound button was swallowed");
    end);

    -- **Nothing is carried between buttons.** Two held at once interleave their presses and
    -- releases, and each has to be judged where it stands.
    test("two buttons held at once each resolve on their own release", function()
        ClickCastBind();
        check(interp:clickFrame(unitFrame, "LeftButton", true) == "debindnull",
            "the first press was not swallowed");
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debindnull",
            "the second press was not swallowed");
        check(interp:clickFrame(unitFrame, "LeftButton", false) == "debind1",
            "the first button did not fire on its release");
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the second button did not fire on its release");
    end);


    -- **And which edge that is, is the reader's.** The wrapper reads one boolean; folding the
    -- three answers onto it is `ApplyOptions`', and the restricted side cannot read a CVar for
    -- itself. The swallowing goes with it: whichever edge is not the one we act on.
    test("choosing the press moves both the firing and the swallowing", function()
        ClickCastBind();
        SetClickEdge(true, nil);
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the press did not fire once it was chosen");
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debindnull",
            "the release was left for the frame's own action");
    end);

    -- The third answer: the reader has chosen nothing, so the game's own keybind setting decides.
    test("leaving it to the game follows the game's setting", function()
        ClickCastBind();
        SetClickEdge(nil, true);
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the press did not fire with the game's setting on");

        SetClickEdge(nil, false);
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not fire with the game's setting off");
    end);

    -- And an answer of their own outranks it, or the third answer would be the only one there is.
    test("a chosen edge outranks the game's setting", function()
        ClickCastBind();
        SetClickEdge(false, true);
        check(interp:clickFrame(unitFrame, "RightButton", false) == "debind1",
            "the release did not fire though it was the one chosen");
        check(interp:clickFrame(unitFrame, "RightButton", true) == "debindnull",
            "the press fired against the reader's answer");
    end);

    --- The same answer given during a lockdown, and the fight ending after it.
    ---
    --- Answers how much crossed while the lockdown was up, and replays whatever crosses when it
    --- lifts. The push is the only thing the wrapper reads, so a value that never crosses is a
    --- value the reader does not have.
    --- **The login is fired first because nothing listens for the fight ending before it.**
    --- `PLAYER_REGEN_ENABLED` is registered in the login handler, so a spec that only sends the
    --- second one measures nothing at all and goes green on a broken addon.
    local function SetClickEdgeInCombat(apply)
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");

        shim.world.inCombat = true;
        local mark = frames.mark();
        apply();
        local crossed = #frames.since(mark);

        shim.world.inCombat = false;
        mark = frames.mark();
        check(frames.fireEvent("PLAYER_REGEN_ENABLED") > 0,
            "nothing is listening for PLAYER_REGEN_ENABLED");
        interp:replay(frames.since(mark));
        return crossed;
    end

    -- **`SecureHandlerExecute` cannot cross a lockdown, and nothing else pushes this value.** So an
    -- answer given in combat reached nothing and stayed unreached for the session, while the menu
    -- went on showing it as the one chosen. It waits for the end of the fight now.
    test("an edge chosen in combat is pushed when the fight ends", function()
        ClickCastBind();
        DebindPrivate.Options.unitframeUseMouseDown = true;
        check(SetClickEdgeInCombat(function()
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
        end) == 0, "the push crossed during the lockdown");

        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the answer given in combat never reached the wrapper");
    end);

    -- The same road for the third answer, which the game moves rather than the reader. A CVar can
    -- be set in a fight, and `Events.CVAR_UPDATE` re-resolves the edge off it through this same
    -- call. **What waits is the fact that a push is owed, not the value**, so the answer that
    -- crosses is the one standing when the fight ends.
    test("the game's setting moving in combat is followed when the fight ends", function()
        ClickCastBind();
        DebindPrivate.Options.unitframeUseMouseDown = nil;
        check(SetClickEdgeInCombat(function()
            shim.world.cvars.ActionButtonUseKeyDown = true;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
            shim.world.cvars.ActionButtonUseKeyDown = false;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
            shim.world.cvars.ActionButtonUseKeyDown = true;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
        end) == 0, "a push crossed during the lockdown");

        check(interp:clickFrame(unitFrame, "RightButton", true) == "debind1",
            "the setting that moved in combat never reached the wrapper");
    end);

    ---------------------------------------------------------------------------
    -- Four axes over seven records
    ---------------------------------------------------------------------------

    -- **One condition on one key proves almost nothing.** Every fault worth finding is past that
    -- line: a key carrying several records, each naming several axes, where exactly one has to
    -- win. This sweeps the full cross product of four axes over a seven-record key.
    --
    -- **The expectations are derived from the same definition the actions are**, because a
    -- mistranscribed row reads exactly like a bug in the addon. And the sweep checks two things
    -- about itself, or it goes green measuring nothing: that the emitted record count still
    -- matches (an index means nothing once the solver drops one and shifts the rest), and that
    -- every record won at least once (a record no combination can reach is a hole, not a pass).
    --
    -- **This one stays in `/debtest` as well.** It is the anchor: four axes over seven records is
    -- where a difference between this interpretation and the real environment would show
    -- (`devdocs/legacy/going-headless-outside-the-ui.md` §9).
    test("the press picks the exact record out of seven", function()
        --- The key's records, in order, each as the world it needs. `nil` means the axis is not
        --- named by that record.
        local ROWS = {
            { combat = true, stealth = true, group = "raid", petbattle = false },
            { combat = true, stealth = true },
            { combat = true, group = "raid" },
            { combat = true },
            { stealth = true, petbattle = true },
            { group = "raid" },
            {},
        };

        local actions = {};
        for i = 1, #ROWS do
            local row = ROWS[i];
            local conditions = {};
            if (row.combat ~= nil) then conditions.combat = row.combat; end
            if (row.stealth ~= nil) then conditions.stealth = row.stealth; end
            if (row.petbattle ~= nil) then conditions.petbattle = row.petbattle; end
            if (row.group ~= nil) then conditions.groups = Constants.GROUP_RAID; end
            actions[i] = action({ value = 100 + i, key = "F1", conditions = conditions });
        end
        Bind(actions);

        local records = castmod.without(Constants, interp:recordsFor("F1"));
        check(records and #records == #ROWS,
            "records emitted: " .. tostring(records and #records) .. " of " .. #ROWS);

        --- Which row the definition says should win in a given world. The same walk the snippet
        --- does, written from the rows rather than from the snippet.
        local function expected(world)
            for i = 1, #ROWS do
                local row = ROWS[i];
                local matched = true;
                if (row.combat ~= nil and row.combat ~= world.combat) then matched = false; end
                if (row.stealth ~= nil and row.stealth ~= world.stealth) then matched = false; end
                if (row.petbattle ~= nil and row.petbattle ~= world.petbattle) then matched = false; end
                if (row.group ~= nil and world.group ~= "raid") then matched = false; end
                if (matched) then
                    return i;
                end
            end
        end

        local won = {};
        local combinations = 0;
        for combat = 0, 1 do
            for stealth = 0, 1 do
                for petbattle = 0, 1 do
                    for grouped = 0, 1 do
                        local world = {
                            combat = combat == 1,
                            stealth = stealth == 1,
                            petbattle = petbattle == 1,
                            group = grouped == 1 and "raid" or "none",
                        };
                        interp:resetState();
                        interp.state.combat = world.combat;
                        interp.state.stealth = world.stealth;
                        interp.state.petbattle = world.petbattle;
                        interp.state.group = world.group;

                        combinations = combinations + 1;
                        local got = winner("F1");
                        local want = expected(world);
                        check(got == want, ("combat=%s stealth=%s petbattle=%s group=%s: got %s, want %s")
                            :format(tostring(world.combat), tostring(world.stealth),
                                tostring(world.petbattle), world.group,
                                tostring(got), tostring(want)));
                        if (got) then
                            won[got] = true;
                        end
                    end
                end
            end
        end

        check(combinations == 16, "combinations swept: " .. combinations);
        for i = 1, #ROWS do
            check(won[i], "record " .. i .. " never won -- the sweep cannot reach it");
        end
        interp:resetState();
    end);

    return T;
end
