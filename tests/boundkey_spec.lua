-- **What the game reports the key is bound to.** No WoW client needed, which it used to be.
--
-- Everything the addon does to a key is an override on the driver, and until now the harness only
-- recorded those going past: `SetOverrideBinding*` wrote into the recording and `GetBindingAction`
-- read a different table entirely, so the two never met and the question had no headless answer.
-- They meet now in `wow_frames.lua`'s `overrides`, which the restricted `SetBindingClick` writes
-- and `GetBindingAction(key, true)` reads.
--
-- **So this file asks the one question the specs beside it stop short of.** Each of them pins a
-- value -- which answer a switch lands on, which record the solver keeps, what a rename rewrote --
-- and every one of those can be right while the key stays dead, because between the value and the
-- key there are three more steps: `BuildKeyMap`'s gate, codegen, and the state loop. Nothing raises
-- when one of them drops the answer on the floor.
--
-- The cases came down from `/debtest` when the table above was joined up. What did **not** come
-- down with them is written at the case that lost it.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local MODES = Constants.SWITCH_MODES;
    local shim = require("wow_shim");
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

    local ME = "Player-1-BOUNDKEY";
    local interp;
    local Rebuild;

    --- Stands a profile up, rebuilds, and runs the state loop once on top of the rebuild's own
    --- pass -- which is where a state-driven key is taken or handed back.
    ---
    --- **The interpreter is built once and fed each rebuild after that**, for the reason
    --- `eval_spec.lua` gives at the same place: the login setup is what creates the tables, and
    --- replaying it into one environment twice is not what the game does.
    local function Bind(actions, switches)
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches,
        };
        DebindPrivate.InitDB();
        return Rebuild();
    end

    --- A rebuild on the profile that is already loaded, for the edits a test makes after `Bind`.
    ---
    --- **Split out because half of these cases are about the second rebuild.** Renaming, answering
    --- an override and taking it off again are all edits to a live profile, and what they are
    --- asked is whether the key moved -- which needs the key to have been somewhere first.
    function Rebuild()
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:pollStates();
        return interp;
    end

    --- What the client says the key is bound to, `""` for a key nothing holds. The same string the
    --- in-game kit reads, so a case that moved down here did not change what it compares.
    local function Bound(key)
        return _G.GetBindingAction(key, true) or "";
    end

    --- Is it ours? Every type this addon binds goes out through a click button, so the prefix is
    --- the whole of what a key being live looks like from outside.
    local function IsLive(key)
        return Bound(key):sub(1, 6) == "CLICK ";
    end

    --- **The premise every case here rests on, and the one that fails silently.** A key whose
    --- records leave no gap is wired once by the rebuild and never handed back, so it reads as
    --- bound in whatever state it is asked about -- and a case that only ever asks `IsLive` goes
    --- green on it while measuring nothing.
    ---
    --- That is not hypothetical. The life axis case below was first written with the unit condition
    --- at the top of the action instead of under `conditions`, so the key carried no condition at
    --- all, came out fixed-wired, and both halves agreed with a key that could not move.
    ---
    --- **Asked of `StateDrivenBindings` and not of the click-time table**, because a releasable key
    --- is in both: the loop decides whether the key is ours and the press decides which record runs
    --- (`eval_spec.lua`, "a key that can be released stays with the state loop"). Reading the
    --- click-time table as the answer fails every case here, correct ones included.
    local function CheckStateDriven(key)
        check(interp.env.StateDrivenBindings[key] ~= nil, key
            .. " is not state-driven, so nothing below it can move: " .. Bound(key));
    end

    --- The key the character-and-specialization scope files an override under, asked through the
    --- addon. A test that wrote its own answer to "what is this layer called" would agree with
    --- itself and with nothing else.
    local function CharKey()
        return DebindPrivate.GetSwitchLayerKey(DebindPrivate.GetLayerID(1, true));
    end

    local function spell(t)
        t.type = t.type or Constants.SPELL;
        t.value = t.value or 585;
        t.seq = t.seq or 1;
        return t;
    end

    ---------------------------------------------------------------------------
    -- Quarantine
    ---------------------------------------------------------------------------

    -- **The one promise this addon makes about importing.** What arrives keeps the sender's key
    -- and is held out of the build by the badge alone, so the key it names is a real one the
    -- client could bind this instant.
    --
    -- **Both directions, and the key is asked in both.** "It did not bind" on its own also
    -- describes an action that was never going to bind, so the same action with only the badge
    -- taken off has to be seen binding before the badge can be called the cause.
    --
    -- ⚠ `KeyMap` is checked beside the key, and that is not the same question twice. `KeyMap` is
    -- our own bookkeeping; an override left behind by an earlier rebuild makes the key fire while
    -- that table says nothing is there, and the disagreement is the fault worth finding.
    test("an arrival reaches no key until the badge comes off", function()
        local action = spell({ key = "F1", arrivalID = 1 });
        Bind({ action }, {});

        check(DebindPrivate.KeyMap["F1"] == nil, "a badged action stood in KeyMap");
        check(Bound("F1") == "", "a badged action was bound to the key it arrived on");

        -- Taking the badge off is the whole of accepting (`ApproveArrivedActions`).
        action.arrivalID = nil;
        Rebuild();

        check(DebindPrivate.KeyMap["F1"], "the badge came off and KeyMap still refuses it");
        check(IsLive("F1"), "the badge came off and the key stayed dead: " .. Bound("F1"));
    end);

    ---------------------------------------------------------------------------
    -- A switch's own expression
    ---------------------------------------------------------------------------

    -- **A name nothing defines must not read as true.** Codegen bakes an undefined name to
    -- `known:0`, which is false; baking it to `""` instead leaves `[$typo]` as `[]`, and `[]` is
    -- true -- so one typo turns every binding hanging off that switch into an unconditional one.
    -- The failure is louder than a dead key and quieter to notice.
    --
    -- **The true half is stood up first.** Without it "not bound" also describes a computed switch
    -- that never reaches a key at all.
    --
    -- ⚠ `resetValue`, not `value`. `ApplySwitchResets` rewrites `value` from `resetValue` and what
    -- the character was left on whenever a switch's answer moves, and planting a definition **is**
    -- a move, so a hand-set `value` is gone before codegen reads it.
    test("an undefined name in a switch's expression does not turn it on", function()
        Bind({ spell({ key = "F1", conditions = { ["$state1"] = true } }) }, {
            ["$state1"] = { mode = MODES.EXPR, expr = "[$state2]" },
            ["$state2"] = { mode = MODES.MANUAL, resetValue = true },
        });
        CheckStateDriven("F1");
        check(IsLive("F1"),
            "a true expression left the key dead, so the half below proves nothing: " .. Bound("F1"));

        DebindPrivate.Switches["$state1"] = { mode = MODES.EXPR, expr = "[$typo]" };
        Rebuild();
        check(Bound("F1") == "",
            "an undefined name made the expression true: " .. Bound("F1"));
    end);

    ---------------------------------------------------------------------------
    -- Renaming, from the key's end
    ---------------------------------------------------------------------------

    -- **The reference that is not inside an action**: a switch named in another switch's
    -- expression. `switch_spec` reads the rewritten table back; what it cannot see is that the
    -- rewritten text still bakes to something the restricted side matches on. A name left behind
    -- bakes to `known:0` and every key that switch drives goes quiet with nothing said.
    --
    -- **Turning the new name off is what tells "followed" from "vanished" apart.** A rewrite that
    -- emptied the clause instead of renaming inside it leaves the outer switch always true, and
    -- the key stays bound through both halves above.
    test("a rename follows the name inside another switch's expression", function()
        Bind({ spell({ key = "F1", conditions = { ["$outer"] = true } }) }, {
            ["$outer"] = { mode = MODES.EXPR, expr = "[$from]" },
            ["$from"] = { mode = MODES.MANUAL },
        });
        DebindPrivate.SetSwitchValue("$from", true);
        Rebuild();
        CheckStateDriven("F1");
        check(IsLive("F1"), "the expression did not reach the key before the rename");

        local ok, reason = DebindPrivate.RenameSwitch("$from", "$to");
        check(ok, "the rename was refused: " .. tostring(reason));
        Rebuild();
        check(IsLive("F1"),
            "the expression kept the old name and baked to known:0: " .. Bound("F1"));

        DebindPrivate.SetSwitchValue("$to", false);
        Rebuild();
        check(Bound("F1") == "",
            "the new name went off and the key stayed: the clause was dropped, not renamed");
    end);

    ---------------------------------------------------------------------------
    -- Layer overrides
    ---------------------------------------------------------------------------

    -- **The answer a layer forces has to travel the whole way.** `switch_spec` settles which row
    -- wins; the three steps after that are `ApplySwitchResets` putting the value back on, codegen
    -- baking the winning row's `mode`, and the loop binding it. Any one missing and the window
    -- shows the new answer while the key plays the old one.
    --
    -- **Taking it off again is half the test.** Without it the first half also describes a switch
    -- that is simply always on.
    --
    -- ⚠ **What stayed in `/debtest`**: that the layer key carries the real `UnitGUID`. The GUID
    -- here is the shim's own invention, so this file can only agree with itself about it.
    test("an override's answer reaches the key, and comes off again", function()
        Bind({ spell({ key = "F1", conditions = { ["$ovr"] = true } }) }, {
            ["$ovr"] = { mode = MODES.MANUAL, resetValue = false },
        });
        CheckStateDriven("F1");
        check(Bound("F1") == "",
            "a switch that starts off already held the key: " .. Bound("F1"));

        local layerKey = CharKey();
        check(layerKey, "this character and specialization have no layer key");

        DebindPrivate.SetSwitchAnswer("$ovr", layerKey, MODES.MANUAL, true);
        Rebuild();
        check(IsLive("F1"), "the override says on and the key is " .. Bound("F1"));

        DebindPrivate.ClearSwitchOverride("$ovr", layerKey);
        Rebuild();
        check(Bound("F1") == "",
            "the override came off and the key did not go back to the root answer: " .. Bound("F1"));
    end);

    -- **Which expression codegen bakes.** `addSwitch` used to read `mode` and `expr` off the
    -- definition, and both of those are the winning row's now. The root here is manual, off, and
    -- has no expression at all, so reading it again bakes "off" while the window says that override
    -- is a conditional.
    --
    -- **Two expressions, and neither half stands alone.** The client is at peace for the whole of
    -- this, so `[nocombat]` has to hold the key and `[combat]` has to let it go:
    --
    --   the true half alone   passes on codegen baking an **empty** expression, since `[]` is true
    --   the false half alone  passes on codegen baking the root, since the root answers off too
    --
    -- The first draft here had only the true half and went green against `addSwitch` reading
    -- `options.expr` -- nil, baked to `""`, true for the wrong reason.
    test("an override's expression is the one baked, not the root's", function()
        Bind({ spell({ key = "F1", conditions = { ["$ovrexpr"] = true } }) }, {
            ["$ovrexpr"] = { mode = MODES.MANUAL, resetValue = false },
        });
        local layerKey = CharKey();
        DebindPrivate.SetSwitchAnswer("$ovrexpr", layerKey, MODES.EXPR);
        DebindPrivate.SetSwitchExpression("$ovrexpr", layerKey, "[nocombat]");
        Rebuild();
        CheckStateDriven("F1");
        check(IsLive("F1"),
            "the override's [nocombat] did not hold the key: " .. Bound("F1"));

        DebindPrivate.SetSwitchExpression("$ovrexpr", layerKey, "[combat]");
        Rebuild();
        check(Bound("F1") == "",
            "[combat] at peace still held the key, so what was baked was not that expression: "
            .. Bound("F1"));
    end);

    ---------------------------------------------------------------------------
    -- Registration is what carries a value across a rebuild
    ---------------------------------------------------------------------------

    -- **Registration does not only come from conditions.** One action in `KeyMap` that uses a
    -- switch is enough to owe it registration, and registration is what puts the stored value back
    -- into `States` at every rebuild (the `_switches` walk in `UpdateBindings`). An on/off/toggle
    -- action names its switch in `value`, so the **condition** loop never sees it -- and without
    -- registration the window reads the stored value while the restricted side holds nothing.
    --
    -- It arrives as "the key does nothing": the first press is spent matching the two up, and the
    -- next rebuild puts them back out of step, so it keeps happening.
    --
    -- **The key is asked first.** With it unbound, the answer below cannot tell "the state was not
    -- registered" from "the action never went out at all".
    test("an action that only sets a switch still registers it", function()
        Bind({ spell({ type = Constants.SETSTATE_TOGGLE, value = "$state4", key = "F1" }) },
            { ["$state4"] = { mode = MODES.MANUAL } });
        DebindPrivate.SetSwitchValue("$state4", true);
        Rebuild();

        check(IsLive("F1"), "the switch action did not reach the key: " .. Bound("F1"));
        check(interp.env.States["$state4"] ~= nil,
            "the restricted side holds no $state4 -- a switch only an action uses went unregistered");
        check(interp.env.States["$state4"] == true,
            "the stored value is on and the restricted side reads "
            .. tostring(interp.env.States["$state4"]));
    end);

    ---------------------------------------------------------------------------
    -- A key the loop is not allowed to touch
    ---------------------------------------------------------------------------

    -- **A key whose records leave no gap is wired once and never handed back**, and the build-time
    -- `SetBindingClick` rests on that: let the loop release it and the press it was wired for has
    -- nothing to arrive at. `eval_spec` says the key comes out that way; this says it stays that way
    -- while the state under it moves.
    --
    -- **Three flips rather than two**, so "it happens to be right on the way out" fails.
    test("a key with no gap is never handed back while the state moves", function()
        Bind({
            spell({ type = Constants.MACROTEXT, value = '/run local _ = "combat"', key = "F1",
                name = "combat", conditions = { combat = true } }),
            spell({ type = Constants.MACROTEXT, value = '/run local _ = "peace"', key = "F1",
                seq = 2, name = "peace", conditions = { combat = false } }),
        }, {});
        check(interp.env.StateDrivenBindings["F1"] == nil,
            "the key was handed to the state loop, so this is not the case it says it is");

        for _, want in ipairs({ true, false, true }) do
            interp.state.combat = want;
            interp:pollStates();
            check(IsLive("F1"),
                "combat=" .. tostring(want) .. " and the key came back as " .. Bound("F1"));
        end
        interp.state.combat = false;
    end);

    ---------------------------------------------------------------------------
    -- The macro store as an input
    ---------------------------------------------------------------------------

    -- **A `MACRO` action naming a macro that does not exist is left out of the build entirely**
    -- (`GetMissingMacroName` -> `BINDING_ISSUE_MISSING_MACRO` -> `BuildKeyMap`), which makes the
    -- macro store an input to what the keys are. Nothing was watching it: make the macro and the row
    -- stops being red -- the window says nothing is wrong -- while the key stays dead until
    -- something unrelated rebuilds, or a `/reload`. `UPDATE_MACROS` is what is registered for that.
    --
    -- **The login has to have happened, because that is where the listening starts.**
    -- `Events.PLAYER_LOGIN` registers `UPDATE_MACROS` and seven others, so an addon that was loaded
    -- and never logged in hears none of them -- which is the shape every spec here ran in until the
    -- harness could deliver an event at all.
    --
    -- **No `CheckStateDriven`, and that is the case rather than an omission.** The action carries no
    -- condition, so once it builds at all the key is wired once and the loop never looks at it
    -- again. What stands in for that premise is the line below it: the key is not bound to start
    -- with, so the assertion at the end cannot pass on a key that was live the whole time.
    --
    -- ⚠ **What stays in `/debtest`**: that the client sends `UPDATE_MACROS` when a macro is made.
    -- The store is the harness's here and the event is sent by hand, so what this holds is that the
    -- handler is listening and rebuilds -- not that anything ever calls it.
    test("the store moving under a key revives it, once the event arrives", function()
        shim.world.macros["Revive"] = nil;
        Bind({ spell({ type = Constants.MACRO, value = "Revive", key = "F1" }) }, {});
        check(Bound("F1") == "",
            "a key naming a macro that does not exist was bound: " .. Bound("F1"));

        -- **The last thing the login does is talk to the window**, and `DebindUI.lua` needs frames
        -- so the harness does not read it. Standing the one function in is the spec saying "this
        -- part is UI and is somebody else's to check" -- everything above it in the handler is the
        -- pipeline, which is what is wanted here.
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");
        _G.CreateMacro("Revive", 132219, "/say hello");

        local mark = frames.mark();
        check(frames.fireEvent("UPDATE_MACROS") > 0, "nobody is listening for UPDATE_MACROS");

        -- `Events.UPDATE_MACROS` queues rather than rebuilds: renaming a macro fires it per
        -- keystroke in the client's editor and there is nothing to be first for.
        frames.drainTimers();
        interp:replay(frames.since(mark));
        interp:pollStates();

        check(IsLive("F1"), "the macro exists and the key is still dead: " .. Bound("F1"));
    end);

    ---------------------------------------------------------------------------
    -- The life axis, at the key
    ---------------------------------------------------------------------------

    -- **Two keys, not one.** Putting both conditions on one key lets the second answer erase the
    -- first, and then which of them moved is unreadable.
    --
    -- **Both directions, because they fail differently.** An axis nobody registered leaves
    -- `u.dead` nil, and nil matches neither -- so a broken registration kills the first half while
    -- a broken comparison kills the second. `eval_spec` splits the same pair at the press; this
    -- asks the poll, which is the other decider and the one that owns the key.
    test("the life axis splits a living unit from a dead one, at the key", function()
        shim.world.units.player = { id = "player" };
        Bind({
            spell({ key = "F1", conditions = { units = { player = { dead = false } } } }),
            spell({ key = "F2", seq = 2, conditions = { units = { player = { dead = true } } } }),
        }, {});
        CheckStateDriven("F1");
        CheckStateDriven("F2");

        check(IsLive("F1"),
            "an alive condition on a living player left the key dead: " .. Bound("F1"));
        check(Bound("F2") == "",
            "a dead condition bound against a living player: " .. Bound("F2"));
    end);

    ---------------------------------------------------------------------------
    -- Keys the state loop has nothing to decide
    ---------------------------------------------------------------------------

    local function command(t)
        t.type = Constants.COMMAND;
        t.value = t.value or "TOGGLEWORLDMAP";
        t.seq = t.seq or 1;
        return t;
    end

    --- A rebuild starting from a known world. **The interpreter is shared and its state is not
    --- reset between cases**, so a case that leaves combat on hands the next one a player in
    --- combat and nothing in the pass says so. The cases below turn it on deliberately, which is
    --- exactly the way to leave that behind.
    local function BindOutOfCombat(actions)
        Bind(actions, {});
        interp.state.combat = false;
        interp:pollStates();
        return interp;
    end

    --- Was the key left out of the loop that re-decides keys every pass?
    local function CheckNotStateDriven(key)
        check(interp.env.StateDrivenBindings[key] == nil,
            key .. " is still state-driven, and nothing about it can change");
        check(interp:recordsFor(key) == nil,
            key .. " registered a click-time button that nothing can reach");
    end

    -- **A command with no condition is settled before any state is read.** It is the third kind of
    -- key the loop has nothing to decide for, beside the two `AppendBindingsList` already leaves
    -- out, and it fell in only because `stateDriven` is written as `not alwaysOurs` and
    -- `alwaysOurs` means fixed **to our click frame**.
    --
    -- **What the key answers must not move**, which is the whole of what this pair asks. Where it
    -- is decided changed; the answer did not.
    test("an unconditional command binds without the state loop", function()
        Bind({ command({ key = "F4" }) }, {});
        check(Bound("F4") == "TOGGLEWORLDMAP", "the command did not reach the key: " .. Bound("F4"));
        CheckNotStateDriven("F4");
    end);

    -- **Unused is the same answer with nothing to do.** The rebuild's prologue already cleared
    -- every override the driver owned, so releasing a key it never took again is a call that
    -- cannot change anything.
    test("an unconditional unused leaves the key alone without the state loop", function()
        Bind({ { type = Constants.UNUSED, key = "F4", seq = 1 } }, {});
        check(Bound("F4") == "", "unused left something on the key: " .. Bound("F4"));
        CheckNotStateDriven("F4");
    end);

    -- **A command that a state can lose is not settled.** Out of combat nothing matches, and the
    -- key has to go back to the game -- which is the loop's job and nobody else's.
    test("a command behind a condition stays with the state loop", function()
        BindOutOfCombat({ command({ key = "F4", conditions = { combat = true } }) });
        CheckStateDriven("F4");
        check(Bound("F4") == "", "a combat command bound out of combat: " .. Bound("F4"));

        interp.state.combat = true;
        interp:pollStates();
        check(Bound("F4") == "TOGGLEWORLDMAP",
            "a combat command did not bind in combat: " .. Bound("F4"));
    end);

    -- **A conditional `UNUSED` is the dangerous half of this predicate.** Settle it by mistake and
    -- the key is released for good: the action below it never gets its turn, and there is nothing
    -- to see. Both directions are asked, because a key that was never bound would read as a pass on
    -- the release half alone.
    test("an unused behind a condition stays with the state loop", function()
        BindOutOfCombat({
            { type = Constants.UNUSED, key = "F4", seq = 1, conditions = { combat = true } },
            spell({ key = "F4", seq = 2 }),
        });
        CheckStateDriven("F4");
        check(IsLive("F4"),
            "the action under a combat-only unused did not take the key: " .. Bound("F4"));

        interp.state.combat = true;
        interp:pollStates();
        check(Bound("F4") == "", "the unused did not release the key in combat: " .. Bound("F4"));
    end);

    -- **The two directions of the same edit**, which is where a build-time decision that outlives
    -- its rebuild shows. Settling a key files an override from outside the restricted environment,
    -- and nothing but the next rebuild's prologue takes it off again; letting a key settle hands it
    -- over from a loop that was holding it.
    test("a key crossing into and out of settled follows the edit", function()
        Bind({ command({ key = "F4" }) }, {});
        check(Bound("F4") == "TOGGLEWORLDMAP", "settled: " .. Bound("F4"));
        CheckNotStateDriven("F4");

        BindOutOfCombat({ command({ key = "F4", conditions = { combat = true } }) });
        CheckStateDriven("F4");
        check(Bound("F4") == "",
            "the override outlived the rebuild that stopped settling the key: " .. Bound("F4"));

        Bind({ command({ key = "F4" }) }, {});
        check(Bound("F4") == "TOGGLEWORLDMAP",
            "the key did not settle again: " .. Bound("F4"));
        CheckNotStateDriven("F4");
    end);

    -- **Settling the key side settles the key side and nothing else.** A mouse button carries two
    -- roles at once: what the key does, and what a click arriving from a unit frame does. They are
    -- judged apart, kept in different tables, and only the first of them is what `GetSettledBinding`
    -- answers about -- so taking the key half out of the snippet has to leave the other half whole.
    --
    -- **Missing this reads as "click-casting stopped working on that button"** and nothing else.
    -- The key would still answer with the command, so every check above would pass.
    test("a settled key keeps its click-cast side", function()
        Bind({
            command({ key = "BUTTON4" }),
            spell({ key = "BUTTON4", seq = 2, unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
        }, {});
        check(Bound("BUTTON4") == "TOGGLEWORLDMAP",
            "the command did not reach the key: " .. Bound("BUTTON4"));
        CheckNotStateDriven("BUTTON4");

        local byMod = interp.env.ClickCastKeys[4];
        local bindings = byMod and byMod[0];
        check(bindings ~= nil, "the click-cast half went out with the key half");
        check(bindings[1] and bindings[1].isClickCast,
            "the click-cast list is there and holds no click-cast record");
    end);

    -- **The command keys a rebuild files live in arrays the module keeps and a count it resets.**
    -- A rebuild with fewer of them than the last one reads less of the array; read the whole array
    -- instead and the key the reader just deleted comes back, filed from a leftover.
    --
    -- The release itself is the prologue's, which clears every override the driver owns. So what
    -- this asks is that nothing files it again afterwards.
    --
    -- **The key that goes is the one further down the array, and that is the whole test.** Keys are
    -- filled in sorted order, so dropping `F4` leaves `F5` written over the slot `F4` had and the
    -- leftover is a key that is still in the profile -- which a reader past the count would file
    -- again to no effect. Dropping `F5` is the case where the leftover is the deleted one.
    test("a command key the profile drops is released", function()
        Bind({
            command({ key = "F4" }),
            command({ key = "F5", value = "TOGGLECHARACTER", seq = 2 }),
        }, {});
        check(Bound("F4") == "TOGGLEWORLDMAP", "F4: " .. Bound("F4"));
        check(Bound("F5") == "TOGGLECHARACTER", "F5: " .. Bound("F5"));

        Bind({ command({ key = "F4" }) }, {});
        check(Bound("F5") == "",
            "a dropped command came back from a leftover: " .. Bound("F5"));
        check(Bound("F4") == "TOGGLEWORLDMAP",
            "the command that stayed did not: " .. Bound("F4"));
    end);

    -- **Nor is one a higher priority action can take the key from.** The command is unconditional
    -- and still not the answer, because in combat the spell above it wins.
    test("a command under a conditional action stays with the state loop", function()
        BindOutOfCombat({
            spell({ key = "F4", conditions = { combat = true } }),
            command({ key = "F4", seq = 2 }),
        });
        CheckStateDriven("F4");
        check(Bound("F4") == "TOGGLEWORLDMAP",
            "the command did not win out of combat: " .. Bound("F4"));

        interp.state.combat = true;
        interp:pollStates();
        check(IsLive("F4"), "the spell did not take the key in combat: " .. Bound("F4"));
    end);

    return T;
end
