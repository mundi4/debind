-- What a rebuild **decides**, asked without a client.
--
-- Six state driver registrations, which units get watched, and whether the hover frame is worth
-- re-deciding on. Every one of them is a reading of what the profile asked to be measured, and
-- until `UpdateBindings()` was split into deciding and doing, the only way to see one was to stand
-- up a `SecureStateDriverManager` in the game and look at what had been registered on it
-- (`devdocs/legacy/going-headless-outside-the-ui.md` §3-1).
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
    local CLASS = Constants.PLAYER_CLASS;

    --- A profile holding exactly the actions handed in, and nothing else. Every test starts from
    --- one: what gets registered depends on what is in the profile, so a leftover action from the
    --- test before is a leftover registration.
    local function Profile(actions, switches)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches or {},
        };
        DebindPrivate.InitDB();
    end

    --- Builds the plan for a profile **without applying any of it**. Nothing reaches the game,
    --- which is the whole claim this file rests on.
    local function PlanFor(actions, switches)
        Profile(actions, switches);
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
    -- Whether the 0.2s beat runs at all
    ---------------------------------------------------------------------------

    -- **The beat costs something before anything of ours is measured**: Blizzard writes
    -- `state-unitexists` and the handler writes it back, five times a second, forever. A profile
    -- with nothing to re-read has no use for any of that, and `RegisterUnitWatch` was a load-time
    -- call nothing ever took back.
    --
    -- What follows says what the beat is *for* in each case, one reason per test, because a
    -- predicate is only as good as the narrowest thing it still catches.
    test("a profile with no conditions at all does not ask for the beat", function()
        local plan = PlanFor({ spell({ key = "F1" }) });
        check(plan.statePoll == false,
            "nothing in this profile is measured and the beat was asked for anyway");
    end);

    -- **A condition asks for no beat.** The press measures every axis a record names, so nothing is
    -- left for a pass to have ready (`devdocs/legacy/dropping-the-game-fallback.md` §3).
    test("a key condition does not ask for the beat", function()
        local plan = PlanFor({
            spell({ key = "F1", conditions = { combat = true } }),
            spell({ key = "F2", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
        });
        check(plan.statePoll == false, "a key condition asked for the beat");
    end);

    -- **A body on a button is composed at the press**, which reads the frame itself, so naming hover
    -- there leaves the beat nothing to keep current.
    test("an @unitframe body on a button asks for no beat", function()
        local plan = PlanFor({
            { type = Constants.MACROTEXT, key = "F1", value = "/cast [@unitframe] Renew", seq = 1 },
        });
        check(plan.statePoll == false, "an @unitframe macro body asked for the beat");
    end);

    -- **A computed switch is worked out at the press**, so only one that announces a change needs a
    -- pass that runs with nobody pressing anything.
    test("a computed switch with no message asks for no beat", function()
        local plan = PlanFor({
            { type = Constants.MACROTEXT, key = "F1", value = "/cast [$state1] Renew", seq = 1 },
        }, {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[mounted]" },
        });
        check(plan.statePoll == false, "a computed switch that announces nothing asked for the beat");
    end);

    test("a computed switch that announces asks for the beat", function()
        local plan = PlanFor({
            { type = Constants.MACROTEXT, key = "F1", value = "/cast [$state1] Renew", seq = 1 },
        }, {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[mounted]",
                displayMessage = true },
        });
        check(plan.statePoll == true, "a computed switch that announces did not ask for the beat");
    end);

    -- **The account-wide switch takes the last reason away.**
    test("turning switch messages off drops the beat", function()
        Profile({
            { type = Constants.MACROTEXT, key = "F1", value = "/cast [$state1] Renew", seq = 1 },
        }, {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[mounted]",
                displayMessage = true },
        });
        DebindPrivate.Options.switchMessages = false;
        local plan = DebindPrivate.BuildBindingPlan(DebindPrivate.CollectBindingContext());
        DebindPrivate.Options.switchMessages = nil;
        check(plan.statePoll == false, "switch messages are off and the beat was asked for anyway");
    end);

    ---------------------------------------------------------------------------
    -- The state driver throttle
    ---------------------------------------------------------------------------

    --- Builds a plan with one option value stored, so the throttle can be asked about on its own.
    local function PlanWithThrottle(value)
        Profile({ spell({ key = "F1" }) });
        DebindPrivate.Options.stateDriverUpdateThrottle = value;
        return DebindPrivate.BuildBindingPlan(DebindPrivate.CollectBindingContext());
    end

    -- **The rebuild's write is the fallback for the slider's, so it has to be reading the same
    -- key.** It was reading `Options.updatetime`, a key left behind when the slider was built
    -- around `stateDriverUpdateThrottle` (2024-08-24), and nothing has written it since. So the
    -- fallback always came out at the default and could never carry what the reader chose --
    -- which is only invisible because `ApplyOptions` overwrites it a moment later on every path
    -- where the stored value is a number.
    test("the throttle the reader chose reaches the plan", function()
        check(PlanWithThrottle(0.05).updatetime == 0.05, "the stored throttle did not reach the plan");
        check(PlanWithThrottle(0).updatetime == 0, "zero was not carried; the slider goes there");
    end);

    -- **Nothing type-checks `db.options`**, and this is the one path that reads the key without
    -- `ApplyOptions`'s `type(value) == "number"` in front of it. A hand-edited string used to be
    -- unreachable here because the key was dead; pointing this at the live one puts it in range of
    -- a `<` against a number, which raises rather than falling back.
    --
    -- **A number out of range is clamped and not refused**, floor as well as ceiling, because
    -- `ApplyOptions` clamps and runs last. The two landing on different numbers is what left the
    -- manager sweeping every frame on a stored negative while this side believed it was throttled.
    test("a throttle that is not a usable number falls back to the default", function()
        local default = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;
        check(PlanWithThrottle("0.05").updatetime == default, "a string did not fall back");
        check(PlanWithThrottle(nil).updatetime == default, "nil did not fall back");
        check(PlanWithThrottle(-1).updatetime == 0, "a negative did not clamp to the floor");
        check(PlanWithThrottle(5).updatetime == default, "a value past the ceiling did not clamp");
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
