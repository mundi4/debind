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
-- key there are more steps: `BuildKeyMap`'s gate, codegen, and the press. Nothing raises when one
-- of them drops the answer on the floor.
--
-- The cases came down from `/debtest` when the table above was joined up. What did **not** come
-- down with them is written at the case that lost it.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local MODES = Constants.SWITCH_MODES;
    local shipped = ctx and ctx.shipped;
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

    --- Stands a profile up, rebuilds, and runs one beat on top of the rebuild's own pass.
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

    --- **Does a press on the key fire anything.** Every key that holds a record is bound for good
    --- (`dropping-the-game-fallback.md` §3), so whether a switch or a unit condition reached
    --- it shows at the press and never in what the key is bound to.
    local function Fires(key)
        return interp:evalKey(key) ~= nil;
    end

    --- A case that asks the press. The eval hook is DEBUG-only, so the shipped pass leaves it out.
    local function pressTest(name, fn)
        if (not shipped) then
            test(name, fn);
        end
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
    pressTest("an undefined name in a switch's expression does not turn it on", function()
        Bind({ spell({ key = "F1", conditions = { ["$state1"] = true } }) }, {
            ["$state1"] = { mode = MODES.EXPR, expr = "[$state2]" },
            ["$state2"] = { mode = MODES.MANUAL, resetValue = true },
        });
        check(Fires("F1"), "a true expression left the key dead, so the half below proves nothing");

        DebindPrivate.Switches["$state1"] = { mode = MODES.EXPR, expr = "[$typo]" };
        Rebuild();
        check(not Fires("F1"), "an undefined name made the expression true");
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
    pressTest("a rename follows the name inside another switch's expression", function()
        Bind({ spell({ key = "F1", conditions = { ["$outer"] = true } }) }, {
            ["$outer"] = { mode = MODES.EXPR, expr = "[$from]" },
            ["$from"] = { mode = MODES.MANUAL },
        });
        DebindPrivate.SetSwitchValue("$from", true);
        Rebuild();
        check(Fires("F1"), "the expression did not reach the key before the rename");

        local ok, reason = DebindPrivate.RenameSwitch("$from", "$to");
        check(ok, "the rename was refused: " .. tostring(reason));
        Rebuild();
        check(Fires("F1"), "the expression kept the old name and baked to known:0");

        DebindPrivate.SetSwitchValue("$to", false);
        Rebuild();
        check(not Fires("F1"),
            "the new name went off and the key still fired: the clause was dropped, not renamed");
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
    pressTest("an override's answer reaches the key, and comes off again", function()
        Bind({ spell({ key = "F1", conditions = { ["$ovr"] = true } }) }, {
            ["$ovr"] = { mode = MODES.MANUAL, resetValue = false },
        });
        check(not Fires("F1"), "a switch that starts off already fired the key");

        local layerKey = CharKey();
        check(layerKey, "this character and specialization have no layer key");

        DebindPrivate.SetSwitchAnswer("$ovr", layerKey, MODES.MANUAL, true);
        Rebuild();
        check(Fires("F1"), "the override says on and the key does not fire");

        DebindPrivate.ClearSwitchOverride("$ovr", layerKey);
        Rebuild();
        check(not Fires("F1"), "the override came off and the key did not go back to the root answer");
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
    pressTest("an override's expression is the one baked, not the root's", function()
        Bind({ spell({ key = "F1", conditions = { ["$ovrexpr"] = true } }) }, {
            ["$ovrexpr"] = { mode = MODES.MANUAL, resetValue = false },
        });
        local layerKey = CharKey();
        DebindPrivate.SetSwitchAnswer("$ovrexpr", layerKey, MODES.EXPR);
        DebindPrivate.SetSwitchExpression("$ovrexpr", layerKey, "[nocombat]");
        Rebuild();
        check(Fires("F1"), "the override's [nocombat] did not fire the key");

        DebindPrivate.SetSwitchExpression("$ovrexpr", layerKey, "[combat]");
        Rebuild();
        check(not Fires("F1"),
            "[combat] at peace still fired the key, so what was baked was not that expression");
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
    -- The macro store as an input
    ---------------------------------------------------------------------------

    -- **A `MACRO` action naming a macro that does not exist is left out of the build entirely**
    -- (`GetMissingMacroName` -> `BINDING_ISSUE_MISSING_MACRO` -> `BuildKeyMap`), which makes the
    -- macro store an input to what the keys are. Nothing was watching it: make the macro and the row
    -- stops being red -- the window says nothing is wrong -- while the key stays dead until
    -- something unrelated rebuilds, or a `/reload`. `UPDATE_MACROS` is what is registered for that.
    --
    -- **The key is ours through both halves**, since the action is on a live layer; what the macro
    -- store moves is whether the press fires.
    --
    -- **The login has to have happened, because that is where the listening starts.**
    -- `Events.PLAYER_LOGIN` registers `UPDATE_MACROS` and seven others, so an addon that was loaded
    -- and never logged in hears none of them -- which is the shape every spec here ran in until the
    -- harness could deliver an event at all.
    --
    -- ⚠ **What stays in `/debtest`**: that the client sends `UPDATE_MACROS` when a macro is made.
    -- The store is the harness's here and the event is sent by hand, so what this holds is that the
    -- handler is listening and rebuilds -- not that anything ever calls it.
    pressTest("the store moving under a key revives it, once the event arrives", function()
        shim.world.macros["Revive"] = nil;
        Bind({ spell({ type = Constants.MACRO, value = "Revive", key = "F1" }) }, {});
        check(IsLive("F1"), "an action on a live layer handed its key back: " .. Bound("F1"));
        check(not Fires("F1"), "a key naming a macro that does not exist fired");

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

        check(Fires("F1"), "the macro exists and the key is still dead");
    end);

    ---------------------------------------------------------------------------
    -- The life axis, at the key
    ---------------------------------------------------------------------------

    -- **Two keys, not one.** Putting both conditions on one key lets the second answer erase the
    -- first, and then which of them moved is unreadable.
    --
    -- **Both directions, because they fail differently.** A broken measurement kills the first
    -- half while a broken comparison kills the second.
    pressTest("the life axis splits a living unit from a dead one, at the key", function()
        shim.world.units.player = { id = "player" };
        Bind({
            spell({ key = "F1", conditions = { units = { player = { dead = false } } } }),
            spell({ key = "F2", seq = 2, conditions = { units = { player = { dead = true } } } }),
        }, {});

        check(Fires("F1"), "an alive condition on a living player left the key dead");
        check(not Fires("F2"), "a dead condition fired against a living player");
    end);

    -- **The whole reason this axis is three overlapping boxes and not three exclusive values.**
    -- A raid member in the reader's own subgroup answers true to both predicates, so [in my party]
    -- has to keep reaching them once the party becomes a raid. An ordered chain -- ask raid first,
    -- take the first true -- gives that unit the raid answer only, and the key goes dead.
    --
    -- The second key is what stops this passing on a stub that answers true to everything.
    pressTest("in my party still reaches a raid member in my own subgroup, at the key", function()
        shim.world.units.party1 = { id = "party1", inParty = true, inRaid = true };
        shim.world.units.raid7 = { id = "raid7", inParty = false, inRaid = true };
        Bind({
            spell({ key = "F1",
                conditions = { units = { party1 = { group = Constants.UNITGROUP_PARTY } } } }),
            spell({ key = "F2", seq = 2,
                conditions = { units = { raid7 = { group = Constants.UNITGROUP_PARTY } } } }),
        }, {});

        check(Fires("F1"), "a party condition missed a raid member in my own subgroup");
        check(not Fires("F2"), "a party condition caught a raid member in another subgroup");
    end);

    pressTest("not in my group splits an outsider from a group member, at the key", function()
        shim.world.units.target = { id = "target" };
        shim.world.units.focus = { id = "focus", inParty = true };
        Bind({
            spell({ key = "F1",
                conditions = { units = { target = { group = Constants.UNITGROUP_NONE } } } }),
            spell({ key = "F2", seq = 2,
                conditions = { units = { focus = { group = Constants.UNITGROUP_NONE } } } }),
        }, {});

        check(Fires("F1"), "an outsider failed a [not in my group] condition");
        check(not Fires("F2"), "a party member passed a [not in my group] condition");
    end);

    return T;
end
