-- What a rebuild **decides**, asked without a client.
--
-- Six state driver registrations, which units get watched, and whether the hover frame is worth
-- re-deciding on. Every one of them is a reading of what the profile asked to be measured, and
-- until `UpdateBindings()` was split into deciding and doing, the only way to see one was to stand
-- up a `SecureStateDriverManager` in the game and look at what had been registered on it
-- (`going-headless-outside-the-ui.md` §3-1).
--
-- **Two faults have already come out of this exact place**, and the file's own comments record
-- them: the old predicate did not look at *which* unit carried a reaction condition, so putting
-- one on `target` alone dragged the mouseover registration along with it; and `HoverBindings` was
-- so wide that the narrow test beside it never mattered. Both are pure decisions and no layer
-- looked at either.
--
-- **The expectations here are the rule, not a transcript.** Each one says what the registration is
-- *for* -- this event exists so that this axis gets re-measured -- so a change that widens a
-- predicate fails here rather than being recorded as the new answer.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");

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

    --- A profile holding exactly the actions handed in, and nothing else. Every test starts from
    --- one: what gets registered depends on what is in the profile, so a leftover action from the
    --- test before is a leftover registration.
    local function Profile(actions, switches, options)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = { account = { GENERAL = { [0] = switches or {} } } },
        };
        DebindPrivate.InitDB();
    end

    --- Builds the plan for a profile **without applying any of it**. Nothing reaches the game,
    --- which is the whole claim this file rests on.
    local function PlanFor(actions, switches, options)
        Profile(actions, switches, options);
        local ctx = DebindPrivate.CollectBindingContext();
        return DebindPrivate.BuildBindingPlan(ctx);
    end

    local seq = 0;
    local function spell(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.value = t.value or 585;
        t.seq = seq;
        return t;
    end

    ---------------------------------------------------------------------------
    -- May it build at all
    ---------------------------------------------------------------------------

    -- **Two refusals, and the caller has to tell them apart.** Combat is owed a retry and an
    -- unknown specialization is not, so an answer that only said "no" would either leave a rebuild
    -- unpaid or queue one nobody asked for.
    test("combat and an unknown specialization are different refusals", function()
        shim.world.inCombat = true;
        local ok, why = DebindPrivate.CanBuildBindings();
        shim.world.inCombat = false;
        check(ok == false and why == "combat", "combat: " .. tostring(ok) .. "/" .. tostring(why));

        local realSpec = _G.C_SpecializationInfo.GetSpecialization;
        _G.C_SpecializationInfo.GetSpecialization = function() return nil; end
        local ok2, why2 = DebindPrivate.CanBuildBindings();
        _G.C_SpecializationInfo.GetSpecialization = realSpec;
        check(ok2 == false and why2 == "spec", "spec: " .. tostring(ok2) .. "/" .. tostring(why2));

        check(DebindPrivate.CanBuildBindings() == true, "an ordinary world refused to build");
    end);

    ---------------------------------------------------------------------------
    -- What never reaches a key at all
    ---------------------------------------------------------------------------

    -- **A marker that fails to hold makes a binding fire *more*, not less.** An action naming a
    -- switch nothing defines is kept out of `KeyMap` by `GetBindingIssue`; if it got through, the
    -- macro body would bake `[$typo]` down to `[]`, which is **always true**, and one typo would
    -- turn a conditional binding into an unconditional one. Asking whether the issue was reported
    -- is not enough -- the question is whether the answer reaches the key.
    --
    -- **The passing half is set up first.** Without it, "the key is absent" reads the same as
    -- "macro text never binds at all".
    test("a macro body naming an undefined switch reaches no key", function()
        PlanFor({
            spell({ type = Constants.MACROTEXT, key = "F1", value = "/say [$burst] ok" }),
            spell({ type = Constants.MACROTEXT, key = "F2", value = "/say [$typo] bad" }),
        }, { ["$burst"] = { mode = Constants.SWITCH_MODES.MANUAL } });

        check(DebindPrivate.KeyMap["F1"], "a defined switch kept its key out too -- bad premise");
        check(DebindPrivate.KeyMap["F2"] == nil, "a typo bound anyway, and bakes to always-true");
    end);

    ---------------------------------------------------------------------------
    -- Watched units
    ---------------------------------------------------------------------------

    --- Is this alias watched, per the plan? nil where the plan does not mention it.
    local function watched(plan, alias)
        for i = 1, #plan.units do
            if (plan.units[i].alias == alias) then
                return plan.units[i].watch;
            end
        end
    end

    -- A role unit is watched because something named it, and the rest are turned off in the same
    -- pass. **Turning one off is not nothing** -- it clears the alias, so a role unit that was
    -- resolvable a moment ago stops being.
    test("only the role units something named are watched", function()
        local plan = PlanFor({
            spell({ key = "F1", unit = "tank" }),
        });
        check(watched(plan, "tank") == true, "tank was not watched");
        check(watched(plan, "healer") == false, "healer was watched");
        check(watched(plan, "maintank") == false, "maintank was watched");
    end);

    -- The two custom targets are set by an action rather than measured, so the plan has no say
    -- over them at all -- and answering "off" for one would clear a target the reader chose.
    test("the custom targets are not the plan's to turn on or off", function()
        local plan = PlanFor({
            spell({ key = "F1", unit = "custom1" }),
        });
        check(watched(plan, "custom1") == nil, "custom1 is in the plan");
        check(watched(plan, "custom2") == nil, "custom2 is in the plan");
    end);

    -- A unit named inside macro text counts the same as one named as a target. The parser is what
    -- finds it, and the alias has to resolve at the press either way.
    test("a unit named in macro text is watched", function()
        local plan = PlanFor({
            spell({ type = Constants.MACROTEXT, key = "F1", value = "/cast [@healer] Regrowth" }),
        });
        check(watched(plan, "healer") == true, "healer was not watched");
    end);

    ---------------------------------------------------------------------------
    -- Which state driver events a profile asks for
    ---------------------------------------------------------------------------

    --- Does the plan ask for this event? nil where the plan does not mention it at all.
    local function registers(plan, name)
        for i = 1, #plan.events do
            if (plan.events[i].name == name) then
                return plan.events[i].register;
            end
        end
    end

    -- **An event costs a wake, and what a press decides reads none.** Every condition is measured at
    -- the press and every computed switch is worked out there. The two readers are Keys Given Back,
    -- an account answer (`giving-keys-back.md` §4), and the loop that judges a key. With
    -- `giveBackWhenNoActionRuns` off and no tail, nothing judges the key, and a condition asks for
    -- nothing; on, its end gives the key back and the loop judges it.
    test("a measured condition on a key the loop does not judge asks for no event", function()
        local actions = function()
            return {
                spell({ key = "F1", conditions = { combat = true, mounted = true } }),
                { type = Constants.MACROTEXT, key = "F2", value = "/cast [@mouseover] Renew", seq = 1 },
            };
        end
        local switches = {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[mounted]" },
        };
        check(PlanFor(actions(), switches).judges == true,
            "a key whose actions can all fail was not judged with the option on");

        local plan = PlanFor(actions(), switches, { giveBackWhenNoActionRuns = false });

        check(registers(plan, "PLAYER_MOUNT_DISPLAY_CHANGED") == false,
            "a mounted condition asked for an event");
        check(registers(plan, "UPDATE_MOUSEOVER_UNIT") == false, "mouseover asked for an event");
        check(registers(plan, "UPDATE_VEHICLE_ACTIONBAR") == false,
            "the bar event was registered with nothing to give back");
        check(plan.judges == false, "a key with no tail asked for the loop");
    end);

    -- **The loop measures on the manager's beat, and an event pulls that beat to the next frame.**
    -- Each of these is asked for because a column of a tail key's item reads what it announces; the
    -- negative half is the case above.
    test("a tail key's columns ask for the events that announce them", function()
        local plan = PlanFor({
            spell({ key = "F1", conditions = { mounted = true, known = true } }),
            spell({ key = "F1", conditions = { units = { mouseover = {} } } }),
            spell({ key = "F1", type = Constants.GIVEBACK, value = nil }),
        });

        check(plan.judges == true, "a key holding a tail did not ask for the loop");
        check(registers(plan, "PLAYER_MOUNT_DISPLAY_CHANGED") == true, "mounted asked for nothing");
        check(registers(plan, "UPDATE_MOUSEOVER_UNIT") == true, "mouseover asked for nothing");
        check(registers(plan, "UNIT_FACTION") == true, "a unit's reaction asked for nothing");
        check(registers(plan, "SPELLS_CHANGED") == true, "known asked for nothing");
        check(registers(plan, "UPDATE_EXTRA_ACTIONBAR") == false,
            "a column nobody reads asked for an event");
    end);

    -- **The beat runs only where it measures something.** A switch set by hand and a pet battle move
    -- on our own wakes alone. A mouseover that goes away and a frame laid out again under a still
    -- cursor send nothing at all, and the beat is the only thing that sees them.
    test("the beat is asked for only where it measures a column", function()
        local function Tail(conditions)
            return PlanFor({
                spell({ key = "F1", conditions = conditions }),
                spell({ key = "F1", type = Constants.GIVEBACK, value = nil }),
            }, { ["$hand"] = { mode = Constants.SWITCH_MODES.MANUAL } });
        end
        for _, case in ipairs({
            { what = "a switch set by hand", conditions = { ["$hand"] = true }, beats = false },
            { what = "a pet battle", conditions = { petbattle = true }, beats = false },
            { what = "the mouseover", conditions = { units = { mouseover = {} } }, beats = true },
            { what = "the pointed frame", conditions = { units = { unitframe = {} } }, beats = true },
            { what = "a pet battle beside combat", conditions = { petbattle = true, combat = true }, beats = true },
        }) do
            local plan = Tail(case.conditions);
            check(plan.judges == true, case.what .. ": the tail key asked for no loop");
            check(plan.beats == case.beats, case.what .. ": beats is " .. tostring(plan.beats));
        end
        check(PlanFor({ spell({ key = "F1", conditions = { combat = true } }) }, nil,
                { giveBackWhenNoActionRuns = false }).beats == false,
            "a key with no tail asked for the beat with the option off");
    end);

    -- **Conditional actions that between them hold in every state leave nothing to judge.** No one
    -- of them holds everywhere, so the key still ends in its giveback, which no state reaches. A
    -- command or a giveback action below them is unreachable the same way, and the solver takes it
    -- off the key before an item is built; `judgment_spec.lua` asks the item about one that gets
    -- there. One that a state reaches, or one standing ahead of them, keeps the loop.
    --
    -- **Every cell of a column counts, not just the two a condition names.** Groups have three and
    -- take all three to cover. A unit is absent or one of six states, so a focus that exists and
    -- none cover it, and a friendly one and none leave a hostile focus, where the key is let go. A
    -- defined switch is on or off wherever it is read, manual or computed.
    test("a key whose conditional actions cover every state asks for no loop", function()
        local MAP = "TOGGLEWORLDMAP";
        local GIVEBACK = Constants.GIVEBACK;
        local wrong = {};
        for _, case in ipairs({
            { what = "a giveback below combat and not", judges = false, actions = {
                spell({ key = "F1", conditions = { combat = true } }),
                spell({ key = "F1", conditions = { combat = false } }),
                spell({ key = "F1", type = GIVEBACK, conditions = { mounted = true } }),
            } },
            { what = "a giveback ahead of combat and not", judges = true, actions = {
                spell({ key = "F1", type = GIVEBACK, conditions = { mounted = true } }),
                spell({ key = "F1", conditions = { combat = true } }),
                spell({ key = "F1", conditions = { combat = false } }),
            } },
            { what = "every group", judges = false, actions = {
                spell({ key = "F1", conditions = { groups = Constants.GROUP_NONE } }),
                spell({ key = "F1", conditions = { groups = Constants.GROUP_PARTY } }),
                spell({ key = "F1", conditions = { groups = Constants.GROUP_RAID } }),
            } },
            { what = "a focus and none", judges = false, actions = {
                spell({ key = "F1", conditions = { units = { focus = {} } } }),
                spell({ key = "F1", conditions = { units = { focus = false } } }),
            } },
            { what = "a manual switch on and off", judges = false,
                switches = { ["$x"] = { mode = Constants.SWITCH_MODES.MANUAL } }, actions = {
                spell({ key = "F1", conditions = { ["$x"] = true } }),
                spell({ key = "F1", conditions = { ["$x"] = false } }),
            } },
            { what = "a computed switch on and off", judges = false,
                switches = { ["$c"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" } }, actions = {
                spell({ key = "F1", conditions = { ["$c"] = true } }),
                spell({ key = "F1", conditions = { ["$c"] = false } }),
            } },
            { what = "a friendly focus and none", judges = true, actions = {
                spell({ key = "F1", conditions = { units = { focus = { reaction = Constants.REACTION_HELP } } } }),
                spell({ key = "F1", conditions = { units = { focus = false } } }),
            } },
            { what = "combat and not", judges = false, actions = {
                spell({ key = "F1", conditions = { combat = true } }),
                spell({ key = "F1", conditions = { combat = false } }),
            } },
            { what = "a command below combat and not", judges = false, actions = {
                spell({ key = "F1", conditions = { combat = true } }),
                spell({ key = "F1", conditions = { combat = false } }),
                spell({ key = "F1", type = Constants.COMMAND, value = MAP, conditions = { mounted = true } }),
            } },
            { what = "combat, and mounted out of it", judges = true, actions = {
                spell({ key = "F1", conditions = { combat = true } }),
                spell({ key = "F1", conditions = { combat = false, mounted = true } }),
            } },
            { what = "a command ahead of combat and not", judges = true, actions = {
                spell({ key = "F1", type = Constants.COMMAND, value = MAP, conditions = { mounted = true } }),
                spell({ key = "F1", conditions = { combat = true } }),
                spell({ key = "F1", conditions = { combat = false } }),
            } },
        }) do
            local plan = PlanFor(case.actions, case.switches);
            if (plan.judges ~= case.judges) then
                wrong[#wrong + 1] = case.what .. ": judges is " .. tostring(plan.judges);
            end
        end
        check(#wrong == 0, table.concat(wrong, "; "));
    end);

    -- **The beat goes through `state-visibility` only on the login check's yes** (`BeatSignal.lua`).
    -- No answer yet and a no both keep the `"a"` driver, which is the one that works whatever the
    -- manager does.
    test("the beat's signal follows the login check", function()
        for _, case in ipairs({
            { comes = nil, signal = "attribute" },
            { comes = false, signal = "attribute" },
            { comes = true, signal = "visibility" },
        }) do
            DebindPrivate.BeatSignal.comes = case.comes;
            -- Put back even where the build raises, or every case after it plans on this signal.
            local built, plan = pcall(PlanFor, {
                spell({ key = "F1", conditions = { combat = true } }),
                spell({ key = "F1", type = Constants.GIVEBACK, value = nil }),
            });
            DebindPrivate.BeatSignal.comes = nil;
            check(built, tostring(plan));
            check(plan.beats == true, tostring(case.comes) .. ": the tail key asked for no beat");
            check(plan.beatSignal == case.signal,
                tostring(case.comes) .. ": the beat goes through " .. tostring(plan.beatSignal));
        end
    end);

    -- The other side of it: the rows that do want a wake still get one.
    test("giving keys back on a replaced bar asks for the bar events", function()
        local plan = PlanFor({ spell({ key = "F1" }) });
        DebindPrivate.Options.giveBackOnReplacedBar = true;
        plan = DebindPrivate.BuildBindingPlan(DebindPrivate.CollectBindingContext());
        DebindPrivate.Options.giveBackOnReplacedBar = nil;

        check(registers(plan, "UPDATE_VEHICLE_ACTIONBAR") == true,
            "the vehicle bar event was not asked for");
        check(registers(plan, "UPDATE_OVERRIDE_ACTIONBAR") == true,
            "the override bar event was not asked for");
    end);

    -- **`updatetime` belongs to Blizzard and a rebuild leaves it alone** (2026-09-19, owner). A
    -- stored throttle from a build that had the slider is still in some profiles, so what this
    -- asks is that reading one changes nothing: the value cannot reach the plan, and the manager's
    -- attribute is nobody's here to write.
    test("a stored throttle reaches nothing", function()
        Profile({ spell({ key = "F1" }) });
        DebindPrivate.Options.stateDriverUpdateThrottle = 0.05;
        local plan = DebindPrivate.BuildBindingPlan(DebindPrivate.CollectBindingContext());
        DebindPrivate.Options.stateDriverUpdateThrottle = nil;

        check(plan.updatetime == nil, "the throttle is back in the plan: " .. tostring(plan.updatetime));
    end);

    ---------------------------------------------------------------------------
    -- The plan is a decision and nothing more
    ---------------------------------------------------------------------------

    -- **Every test above built a plan and applied none of it.** If building reached the state
    -- driver, they would all be measuring the game rather than the decision -- so this asks the
    -- one thing that makes the rest of the file mean what it says.
    test("building a plan registers nothing on the state driver", function()
        local frames = require("wow_frames");
        local mark = frames.mark();
        PlanFor({ spell({ key = "F1", conditions = { specialbar = true } }) });
        local entries = frames.since(mark);

        for i = 1, #entries do
            local e = entries[i];
            check(e.target ~= "SecureStateDriverManager",
                "the build reached the state driver: " .. e.kind .. " " .. tostring(e.name));
        end
    end);

    return T;
end
