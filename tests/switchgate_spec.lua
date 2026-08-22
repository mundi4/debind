-- **A computed switch on the 0.2s beat: when is its conditional handed to the parser, and when is
-- it not.** No WoW client needed.
--
-- The state loop used to parse every computed switch on every pass. It cannot have moved unless
-- something it reads moved, so the emitted lines now sit behind the dirty flags of the states the
-- conditional names (`devdocs/trimming-the-restricted-hot-paths.md` 4).
--
-- **The gate is invisible in every value the pass leaves behind** -- a switch whose answer did not
-- move reads the same whether the loop worked it out again or let it stand. So the skip itself is
-- asked with `interp:parseCount`, and everything around it asks the ordinary question: does the
-- switch still land on the right value, and does the key that hangs off it follow.
--
-- The failure this guards against is the loud half of the trade: a gate built out of a word nobody
-- measures never opens, and the switch freezes on whatever it answered last with nothing raising
-- anything. Two of the cases below are expressions the gate has to **decline** for that reason.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
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

    local GUID = "Player-1-GATESPEC";
    local interp;

    --- Stands a profile up, rebuilds, and hands back the interpreter with the new records in it.
    ---
    --- **Built once and fed each rebuild after that**, for the reason `eval_spec.lua` gives at the
    --- same place: the login setup is what creates the tables, and replaying it twice into one
    --- environment is not what the game does.
    local function Bind(actions, switches)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches,
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

        -- The pass that closes a rebuild runs with `forceAll` set, and that one is meant to work
        -- every switch out from nothing. One more pass on top of it puts the loop in the steady
        -- state the cases below are about.
        interp:pollStates();
        return interp;
    end

    --- One key, held only while `$state1` is on. That makes the key state-driven, so whether it is
    --- bound at all is the loop's answer to the switch rather than a rebuild's.
    local function GatedKey()
        return {
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { ["$state1"] = true } },
        };
    end

    ---------------------------------------------------------------------------

    test("a conditional built out of measured states is parsed only when one of them moves",
        function()
            local i = Bind(GatedKey(), {
                ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" },
            });

            local before = i:parseCount("[combat]");
            i:pollStates();
            check(i:parseCount("[combat]") == before,
                "a pass where nothing moved parsed the conditional anyway");

            -- **The state has to be measured for any of this to hold**, and nothing but the switch
            -- asks about combat in this profile. `addSwitch` is what registers it.
            check(i.env.States.combat == false,
                "combat was not measured, so the flag the gate opens on never gets set");

            i.state.combat = true;
            i:pollStates();
            check(i.env.States["$state1"] == true, "the switch did not follow combat going on");
            check(i.bindings["F1"], "the key hanging off the switch was not bound");

            i.state.combat = false;
            i:pollStates();
            check(i.env.States["$state1"] == false, "the switch did not follow combat going off");
            check(i.bindings["F1"] == nil, "the key was not let go");
        end);

    test("a conditional naming a state nobody measures is parsed on every pass", function()
        -- `[mounted]` is a real macro conditional and this addon measures nothing that answers it.
        -- A gate would have to be built out of nothing and would never open.
        local i = Bind(GatedKey(), {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[mounted]" },
        });

        local before = i:parseCount("[mounted]");
        i:pollStates();
        check(i:parseCount("[mounted]") > before, "the conditional was skipped on a pass");

        i.state.mounted = true;
        i:pollStates();
        check(i.env.States["$state1"] == true, "the switch did not follow mounted going on");
        check(i.bindings["F1"], "the key hanging off the switch was not bound");

        i.state.mounted = false;
        i:pollStates();
        check(i.env.States["$state1"] == false, "the switch did not follow mounted going off");
        check(i.bindings["F1"] == nil, "the key was not let go");
    end);

    test("a conditional aimed at a unit is parsed on every pass", function()
        -- Who `target` is, and what is true of them, moves without any flag this pass can read.
        local i = Bind(GatedKey(), {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@target,combat]" },
        });

        local before = i:parseCount("[@target,combat]");
        i:pollStates();
        check(i:parseCount("[@target,combat]") > before, "the conditional was skipped on a pass");
    end);

    -- **A state that answers `nil` raises no flag of its own, ever.** The loop stores what it
    -- measured and compares against what was there, and a rebuild leaves `States` empty -- so a
    -- state whose expression comes out `nil` reads as unchanged on the very first pass and on
    -- every pass after it. Whether a client's `PlayerInCombat()` answers `false` or `nil` out of
    -- combat is not something this repository gets to decide, and the loop was never asking.
    --
    -- The switch would then keep the value the rebuild put back, which for a computed switch is a
    -- leftover: `BuildSwitchesSnippet` restores it and the first pass is supposed to overwrite it.
    -- `DirtyFlags.forceAll` is what makes that first pass happen whatever the flags say.
    test("the pass that follows a rebuild works a switch out whether or not its flags fired",
        function()
            -- Not `false`: the key has to be gone from the table, or `resetState` puts a boolean
            -- back into it before the pass runs.
            interp.state.combat = nil;

            local i = Bind(GatedKey(), {
                ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]",
                    value = true },
            });

            check(i.env.States.combat == nil,
                "setup: combat still answers something, so no flag was withheld");
            check(i.env.States["$state1"] == false,
                "the stored value survived the pass that follows a rebuild");
            check(i.bindings["F1"] == nil, "the key was held on the strength of the stored value");

            interp.state.combat = false;
        end);

    test("a switch computed from another switch follows it", function()
        local i = Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { ["$state2"] = true } },
        }, {
            ["$state1"] = { mode = Constants.SWITCH_MODES.MANUAL },
            ["$state2"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$state1]" },
        });

        check(i.env.States["$state2"] == false, "the computed switch did not start off");
        check(i.bindings["F1"] == nil, "the key was bound before the switch went on");

        -- **What reaches the parser is the composed text, not the expression as stored.**
        -- `UpdateMacroTexts` writes the switch it reads in as `known:0` while that switch is off
        -- and as nothing at all while it is on, so the string to count is the composed one.
        local before = i:parseCount("[known:0]");
        i:pollStates();
        check(i:parseCount("[known:0]") == before,
            "a pass where the switch it reads did not move parsed the conditional anyway");

        i.driverHandle:RunAttribute("SetSwitch", "$state1", true);
        check(i.env.States["$state2"] == true, "the computed switch did not follow the one it reads");
        check(i.bindings["F1"], "the key hanging off the computed switch was not bound");

        i.driverHandle:RunAttribute("SetSwitch", "$state1", false);
        check(i.env.States["$state2"] == false, "the computed switch did not follow it back off");
        check(i.bindings["F1"] == nil, "the key was not let go");
    end);

    return T;
end
