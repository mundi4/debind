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
    local function Bind(actions, switches)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
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

    --- Which record wins on this key right now, by its place in the emitted list.
    local function winner(key)
        return (interp:evalKey(key));
    end

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
            action({ type = Constants.EQUIPSLOT, value = 13, key = "F6" }),
        });

        local clickFrame = DebindPrivate.DefaultClickFrame;
        local function attributesOf(key)
            local _, button = interp:evalKey(key);
            check(button, key .. " picked no action");
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
            { type = Constants.EQUIPSLOT, value = 13, key = "F7", unit = "focus" });
        check(targeted.unit == "focus",
            "equipslot lost its unit: " .. tostring(targeted.unit));

        local textType, textValue = attributesOf("F3");
        check(textType == "macro" and textValue == "/cast Renew", "macrotext: " .. tostring(textValue));

        local targetType = attributesOf("F5");
        check(targetType == "target", "target: " .. tostring(targetType));

        -- **A command has no button to click, and with no condition in front of it there is
        -- nothing for the press path to know about at all.** The rebuild files the override
        -- itself, so the key never gets a click-time button and the wrapper can never be handed
        -- one for it (`GetSettledBinding`). A command a state can lose still comes down here; that
        -- pair is in `boundkey_spec`.
        check(interp:recordsFor("F4") == nil, "a settled command left a record for the press path");
        check(_G.GetBindingAction("F4", true) == "TOGGLEWORLDMAP",
            "the command did not reach the key: " .. tostring(_G.GetBindingAction("F4", true)));
    end);

    -- **Unused takes the key back**, and it is the only record that wins by having nothing to
    -- fire. A key whose conditional action does not match falls through to it, and the press
    -- answers with no button at all.
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
        check(interp:recordsFor("F1")[2].type == Constants.UNUSED,
            "the second record is not the unused one");

        -- **And the key goes back to the game.** Firing nothing is not enough: an unused record
        -- that still held the key would leave the reader's own binding dead under it.
        interp:pollStates();
        check(interp.bindings["F1"] == nil, "unused kept the key");
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
        { name = "pet", conditions = { pet = true }, on = function(s) s.pet = true; end },
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

    -- A `known` condition is answered by parsing the conditional the record carries, which is the
    -- action's own spell. The state loop reads the same string as a key in `States`.
    test("a known condition follows the spell book", function()
        Bind({
            action({ value = 8936, key = "F1", conditions = { known = true } }),
            action({ value = 774, key = "F1" }),
        });

        check(winner("F1") == 2, "the known action won without the spell");
        interp.state.known[8936] = true;
        check(winner("F1") == 1, "the known action did not win with the spell");
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

        -- The poll is where the value that meant two things was stored, so it is asked too.
        interp:pollStates();
        check(interp.bindings["F1"], "the poll let the existence key go on a hostile focus");
        check(interp.bindings["F2"] == nil, "the poll kept the friendly key on a hostile focus");

        shim.world.units = {};
        interp:pollStates();
        check(interp.bindings["F1"] == nil, "the existence key survived the focus going away");
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

    --- Which of the three the key came out as. Read off the tables the restricted side actually
    --- holds, rather than the copies baked beside them -- membership is the answer and the fields
    --- are its mirror.
    local function wiring(key)
        local button = Constants.CLICKTIME_BUTTON_PREFIX .. key;
        return {
            stateDriven = interp.env.StateDrivenBindings[key] ~= nil,
            clickTime = interp.env.ClickTimeKeys[button] ~= nil,
            bound = interp.bindings[key] ~= nil,
        };
    end

    -- A key whose actions cover the whole condition space is ours whatever happens, so it is bound
    -- once here and the state loop is never given it.
    test("a key with no gap is bound once and left out of the state loop", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true } }),
            action({ value = 774, key = "F1", conditions = { combat = false } }),
        });

        local how = wiring("F1");
        check(how.clickTime, "the key is not decided at the press");
        check(not how.stateDriven, "a covered key was handed to the state loop");
        check(how.bound, "a covered key was never bound");
    end);

    -- A key that can be released has to stay with the state loop: **binding it once would mean
    -- never letting go**, and the game's own binding under that key would stop working.
    test("a key that can be released stays with the state loop", function()
        Bind({ action({ value = 585, key = "F1", conditions = { combat = true } }) });

        local how = wiring("F1");
        check(how.stateDriven, "a releasable key was not handed to the state loop");
        check(how.clickTime, "a releasable key is not decided at the press");
    end);

    -- **The state loop is what takes and releases such a key**, and this is the pass that does it.
    -- Out of combat nothing on the key matches, so it goes back to the game.
    test("the state loop takes the key and gives it back", function()
        Bind({ action({ value = 585, key = "F1", conditions = { combat = true } }) });

        interp.state.combat = true;
        interp:pollStates();
        check(interp.bindings["F1"], "the key was not taken while the condition held");

        interp.state.combat = false;
        interp:pollStates();
        check(interp.bindings["F1"] == nil, "the key was not given back");
        interp:resetState();
    end);

    -- A key that only click-casts holds no key-binding record at all, so there is no key role to
    -- take or release -- it must not reach the state loop, and it must not be bound.
    test("a click-casting-only key is not in the state loop", function()
        Bind({
            action({ value = 585, key = "BUTTON2", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_ALL } } } }),
        });

        local how = wiring("BUTTON2");
        check(not how.stateDriven, "a click-cast-only key was handed to the state loop");
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

        local records = interp:recordsFor("F1");
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

    -- **The same cross product, asked of the other decider.** The press picks a record out of a key
    -- it already holds; the loop decides what the key *is*, and it reads the same four axes through
    -- the code the 0.2s beat runs. A sweep of one says nothing about the other.
    --
    -- **`COMMAND` records, so the answer names itself.** Every other type goes out through a click
    -- button and reads back as the same `CLICK` whichever record won; a command override reads back
    -- as the command, so what the key is bound to identifies the row without decoding anything.
    -- The last row is `UNUSED`: the key is released rather than bound, and `""` is the only outcome
    -- that is an empty string -- which is the negative half, checked in the same table as the rest.
    test("the state loop binds the exact record out of seven", function()
        local ROWS = {
            { expect = "TOGGLEBAGS", combat = true, stealth = true, group = "raid",
                petbattle = false },
            { expect = "OPENALLBAGS", combat = true, stealth = true },
            { expect = "TOGGLEBACKPACK", combat = true, group = "raid" },
            { expect = "TOGGLECHARACTER0", combat = true },
            { expect = "TOGGLEACHIEVEMENT", stealth = true, petbattle = true },
            { expect = "JUMP", group = "raid" },
            { expect = "", unused = true },
        };

        local actions = {};
        for i = 1, #ROWS do
            local row = ROWS[i];
            local conditions = {};
            if (row.combat ~= nil) then conditions.combat = row.combat; end
            if (row.stealth ~= nil) then conditions.stealth = row.stealth; end
            if (row.petbattle ~= nil) then conditions.petbattle = row.petbattle; end
            if (row.group ~= nil) then conditions.groups = Constants.GROUP_RAID; end
            if (row.unused) then
                actions[i] = action({ type = Constants.UNUSED, key = "F1",
                    conditions = conditions });
            else
                actions[i] = action({ type = Constants.COMMAND, value = row.expect, key = "F1",
                    conditions = conditions });
            end
        end
        Bind(actions);

        local records = interp:recordsFor("F1");
        check(records and #records == #ROWS,
            "records emitted: " .. tostring(records and #records) .. " of " .. #ROWS);
        check(interp.env.StateDrivenBindings["F1"] ~= nil,
            "the key is not state-driven, so this sweep is measuring the wrong decider");

        local function expected(world)
            for i = 1, #ROWS do
                local row = ROWS[i];
                local matched = true;
                if (row.combat ~= nil and row.combat ~= world.combat) then matched = false; end
                if (row.stealth ~= nil and row.stealth ~= world.stealth) then matched = false; end
                if (row.petbattle ~= nil and row.petbattle ~= world.petbattle) then matched = false; end
                if (row.group ~= nil and world.group ~= "raid") then matched = false; end
                if (matched) then return i; end
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
                        interp:pollStates();

                        combinations = combinations + 1;
                        local want = expected(world);
                        check(want, "no row is expected to win, which the last one makes impossible");
                        local bound = frames.overrideAction("F1") or "";
                        check(bound == ROWS[want].expect,
                            ("combat=%s stealth=%s petbattle=%s group=%s: row %d should hold the key,"
                                .. " so %q -- got %q"):format(tostring(world.combat),
                                tostring(world.stealth), tostring(world.petbattle), world.group,
                                want, ROWS[want].expect, bound));
                        won[want] = true;
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

    -- **The poll and the press have to agree.** They measure the same axes through different code:
    -- the poll writes into `States` on its 0.2s beat and the press measures at the click. A key
    -- with a gap in it -- no record matches in some worlds -- is where they part if they are going
    -- to, because that is where one says "take the key" and the other says "fire nothing".
    test("poll and press agree on a key with a gap", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true, stealth = true } }),
            action({ value = 774, key = "F1", conditions = { combat = false } }),
        });

        for combat = 0, 1 do
            for stealth = 0, 1 do
                interp:resetState();
                interp.state.combat = combat == 1;
                interp.state.stealth = stealth == 1;

                -- **The binding is not cleared between rounds.** The loop acts on what changed,
                -- the way the real one does; wiping the answer first and expecting it back would
                -- be asking the poll to redo work it correctly skipped.
                interp:pollStates();
                local taken = interp.bindings["F1"] ~= nil;
                local fires = winner("F1") ~= nil;

                check(taken == fires, ("combat=%d stealth=%d: the poll %s and the press %s")
                    :format(combat, stealth,
                        taken and "took the key" or "let it go",
                        fires and "fires" or "fires nothing"));
            end
        end
        interp:resetState();
    end);

    return T;
end
