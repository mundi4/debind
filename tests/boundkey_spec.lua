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

    return T;
end
