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

    --- Did the plan ask for this event, or ask for it gone? Answers nil when the plan says nothing
    --- about it at all, which is a third outcome and not the same as "no".
    local function registration(plan, name)
        for i = 1, #plan.events do
            if (plan.events[i].name == name) then
                return plan.events[i].register;
            end
        end
    end

    local function wants(plan, name, msg)
        check(registration(plan, name) == true, msg or (name .. " was not registered"));
    end

    local function drops(plan, name, msg)
        check(registration(plan, name) == false, msg or (name .. " was registered"));
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
    -- The mouseover registration, and the fault it used to carry
    ---------------------------------------------------------------------------

    -- `UPDATE_MOUSEOVER_UNIT` exists so a hover unit that goes away under a cursor that never
    -- moves is noticed. A profile that measures the hover axis needs it.
    test("a hover condition registers the mouseover event", function()
        local plan = PlanFor({
            spell({ key = "F1", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
        });
        wants(plan, "UPDATE_MOUSEOVER_UNIT");
    end);

    -- **The fault this place is known for.** A reaction condition on `target` says nothing about
    -- hovering, and the old predicate asked "does anything measure reaction" without asking about
    -- which unit -- so this profile registered the mouseover event and re-measured the hover slot
    -- five times a second for nothing.
    test("a reaction condition on target does not drag the mouseover event with it", function()
        local plan = PlanFor({
            spell({ key = "F1", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
        });
        wants(plan, "UNIT_FACTION", "a measured reaction did not register UNIT_FACTION");
        drops(plan, "UPDATE_MOUSEOVER_UNIT");
    end);

    -- The other half: with nothing measuring reaction anywhere, `UNIT_FACTION` goes.
    test("a profile that measures no reaction unregisters UNIT_FACTION", function()
        local plan = PlanFor({
            spell({ key = "F1", conditions = { combat = true } }),
        });
        drops(plan, "UNIT_FACTION");
        drops(plan, "UPDATE_MOUSEOVER_UNIT");
    end);

    -- **Nothing is measured for a key the state loop never walks.** A key whose actions cover the
    -- whole condition space is bound once and never re-decided, so the axes it names have no
    -- reader -- the click path measures them again at the press. A registration here would pay for
    -- a measurement nobody reads.
    test("a key that is always ours registers nothing", function()
        local plan = PlanFor({
            spell({ key = "F1", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
            -- **This second action is what changes the answer.** It is unconditional, so nothing
            -- can take the key away, so the key is bound once and the state loop never walks it.
            -- The first action on its own registers `UNIT_FACTION` -- two tests above.
            spell({ key = "F1", value = 774 }),
        });
        drops(plan, "UNIT_FACTION");
    end);

    ---------------------------------------------------------------------------
    -- The bar axes
    ---------------------------------------------------------------------------

    -- `specialbar` folds `[petbattle]` into its own value, so a profile that asks about it needs
    -- the pet battle events as well as the two bar events. That is one axis asking for four
    -- registrations, and the fold is the reason.
    test("specialbar takes the bar events and the pet battle events", function()
        local plan = PlanFor({
            spell({ key = "F1", conditions = { specialbar = true } }),
            spell({ key = "F2", conditions = { specialbar = false } }),
        });
        wants(plan, "UPDATE_OVERRIDE_ACTIONBAR");
        wants(plan, "UPDATE_VEHICLE_ACTIONBAR");
        wants(plan, "PET_BATTLE_OPENING_START");
        wants(plan, "PET_BATTLE_CLOSE");
        drops(plan, "UPDATE_EXTRA_ACTIONBAR");
    end);

    -- And the other direction: a pet battle condition takes the pet battle events **only**. The
    -- fold runs one way.
    test("petbattle does not take the bar events", function()
        local plan = PlanFor({
            spell({ key = "F1", conditions = { petbattle = true } }),
        });
        wants(plan, "PET_BATTLE_OPENING_START");
        wants(plan, "PET_BATTLE_CLOSE");
        drops(plan, "UPDATE_OVERRIDE_ACTIONBAR");
        drops(plan, "UPDATE_VEHICLE_ACTIONBAR");
    end);

    test("extrabar takes its own event and nothing else", function()
        local plan = PlanFor({
            spell({ key = "F1", conditions = { extrabar = true } }),
        });
        wants(plan, "UPDATE_EXTRA_ACTIONBAR");
        drops(plan, "UPDATE_OVERRIDE_ACTIONBAR");
        drops(plan, "PET_BATTLE_CLOSE");
    end);

    -- A `known:` condition is answered by `SecureCmdOptionParse`, and the spell book is what
    -- changes that answer. **The state it registers is named after the spell**, so the predicate
    -- behind this event is a prefix walk over what got measured rather than one lookup -- and on
    -- an ordinary profile it comes out empty and the event goes.
    test("a known condition registers SPELLS_CHANGED and nothing else does", function()
        local plan = PlanFor({
            spell({ key = "F1", value = 8936, conditions = { known = true } }),
        });
        wants(plan, "SPELLS_CHANGED");

        local bare = PlanFor({
            spell({ key = "F1", conditions = { combat = true } }),
        });
        drops(bare, "SPELLS_CHANGED");
    end);

    ---------------------------------------------------------------------------
    -- Every axis a record carries is an axis the loop measures
    ---------------------------------------------------------------------------

    -- **The pairing this sweeps used to be written down twice.** Emitting an axis onto a record
    -- and registering the state that wakes a key carrying it were two lines beside each other, so
    -- either could go without the other -- an emitted axis with no state is a key that never wakes
    -- up, and a state with no axis is a measurement nobody reads. The states are read off the
    -- finished record now, and this is what says the two still line up.
    --
    -- **The state names are not the field names for four of them**, which is the other half of why
    -- the pairing was easy to get wrong: `groups` wakes on `group`, `forms` on `form`,
    -- `bonusbars` on `bonusbar`.
    test("every condition axis on a state-driven key is measured by the state loop", function()
        local AXES = {
            { conditions = { groups = Constants.GROUP_PARTY }, state = "group" },
            { conditions = { combat = true }, state = "combat" },
            { conditions = { stealth = true }, state = "stealth" },
            { conditions = { forms = 3 }, state = "form" },
            { conditions = { bonusbars = 5 }, state = "bonusbar" },
            { conditions = { specialbar = true }, state = "specialbar" },
            { conditions = { extrabar = true }, state = "extrabar" },
            { conditions = { pet = true }, state = "pet" },
            { conditions = { petbattle = true }, state = "petbattle" },
        };

        for i = 1, #AXES do
            local axis = AXES[i];
            local plan = PlanFor({ spell({ key = "F1", conditions = axis.conditions }) });
            local measured = ('States["%s"]'):format(axis.state);
            check(plan.attrChangedSnippet:find(measured, 1, true),
                axis.state .. " is carried by a record and never measured");

            -- **And the other direction, in the same pass.** Without it the sweep also passes on a
            -- loop that measures every axis whatever the profile asks for, which is what the
            -- registration narrowing above exists to prevent.
            for j = 1, #AXES do
                if (j ~= i) then
                    local other = ('States["%s"]'):format(AXES[j].state);
                    -- `specialbar` folds `[petbattle]` into itself, so those two travel together
                    -- and neither one alone proves anything about the other.
                    local paired = (axis.state == "specialbar" and AXES[j].state == "petbattle")
                        or (axis.state == "petbattle" and AXES[j].state == "specialbar");
                    if (not paired) then
                        check(not plan.attrChangedSnippet:find(other, 1, true),
                            axis.state .. " dragged " .. AXES[j].state .. " into the loop");
                    end
                end
            end
        end
    end);

    ---------------------------------------------------------------------------
    -- Who builds the unit rows
    ---------------------------------------------------------------------------

    -- **A row in `UnitStates` says one thing: this unit is measured.** Two snippets read it that
    -- way -- `SetUnit` asks whether moving an alias can change what a key answers, and the
    -- matcher treats a missing row as "not a unit this build measures". Neither survives the tick
    -- owning the row: while the poll created it on first sight, its absence also meant *no tick
    -- has been round yet*, and the two readers had no way to tell which they were looking at.
    --
    -- So the rebuild builds them and the tick only reads them. Both halves are asserted here,
    -- because either one alone passes on a build that creates rows in both places.
    test("the rebuild builds a row for each measured unit and the tick builds none", function()
        local plan = PlanFor({
            spell({ key = "F1", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HARM } } } }),
            spell({ key = "F2", conditions = { units = { focus = { exists = true } } } }),
        });

        check(plan.unitRowsSnippet, "no rebuild snippet builds the rows");
        for _, unit in ipairs({ "target", "focus" }) do
            check(plan.unitRowsSnippet:find(('UnitStates["%s"]=newtable()'):format(unit), 1, true),
                unit .. " is measured but the rebuild builds no row for it");
        end

        -- **A unit nothing measures gets no row**, or the readers above go back to answering
        -- "measured" for every alias that exists.
        check(not plan.unitRowsSnippet:find("pet", 1, true),
            "a row was built for a unit the loop never reads");

        check(not plan.attrChangedSnippet:find("newtable()", 1, true),
            "the tick still builds a row, so its absence still means two things");
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
    -- Re-deciding on the hover frame
    ---------------------------------------------------------------------------

    -- **This flag is the narrow question, and its old name was the wide one.** What it asks is
    -- whether any state-driven key has to be re-decided when the frame under the cursor changes
    -- while the unit under it does not -- and only a `frameTypes` record can. The unit changing is
    -- already answered by `SetUnit`.
    test("only a frame type condition makes the hover frame worth re-deciding on", function()
        local withFrameType = PlanFor({
            spell({ key = "F1", unit = "hover", conditions = {
                frameTypes = Constants.FRAMETYPE_GROUP,
                units = { hover = { reaction = Constants.REACTION_ALL } },
            } }),
        });
        check(withFrameType.rebindOnHoverFrame == true, "a frameTypes record did not set it");

        -- The same key with a hover condition and no frame type: hovering is measured, but no
        -- record can answer differently for one frame than another.
        local plain = PlanFor({
            spell({ key = "F1", unit = "hover", conditions = {
                units = { hover = { reaction = Constants.REACTION_ALL } },
            } }),
        });
        check(plain.rebindOnHoverFrame == false, "a plain hover condition set it");
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

    -- **State-driven and measuring nothing is a real shape**, and it is the one that looks like a
    -- hole. A mouse button carries "not while hovering" from the key itself (`BuildUnitStates`),
    -- so an unconditional action on `BUTTON4` does not cover the space and its wiring belongs to
    -- the state loop -- while no condition anywhere asks for a measurement. The pass that closes
    -- the rebuild binds it with `forceAll` and nothing exists that could take it away, so the
    -- answer is `false` on purpose.
    test("a key the state loop owns but measures nothing does not ask for the beat", function()
        local plan = PlanFor({ spell({ key = "BUTTON4" }) });
        check(plan.statePoll == false,
            "a mouse-button key with no conditions asked for a beat with nothing to measure");
    end);

    test("a measured state asks for the beat", function()
        local plan = PlanFor({ spell({ key = "F1", conditions = { combat = true } }) });
        check(plan.statePoll == true, "a combat condition did not ask for the beat");
    end);

    -- A unit condition lands in `_measuredUnitAxes` rather than `_measuredStates`, so the two
    -- are separate terms and this is the one that catches a predicate asking only the first.
    test("a unit condition asks for the beat", function()
        local plan = PlanFor({
            spell({ key = "F1", unit = "target",
                conditions = { units = { ["@"] = { exists = true } } } }),
        });
        check(plan.statePoll == true, "a target condition did not ask for the beat");
    end);

    -- Hover is the one alias the beat itself keeps fresh -- a unit changing under a cursor that
    -- never moved is invisible to enter and leave both.
    test("naming hover asks for the beat", function()
        local plan = PlanFor({
            { type = Constants.MACROTEXT, key = "F1", value = "/cast [@hover] Renew", seq = 1 },
        });
        check(plan.statePoll == true, "an @hover macro body did not ask for the beat");
    end);

    -- **Asked of `_switches`, not of what is measured.** Nothing conditions on this switch, so it
    -- is absent from `_measuredStates` while its two lines are still in the pass -- a macro body
    -- reads it and `displayMessage` announces it.
    --
    -- **`[mounted]` and not `[combat]`, and that is the whole test.** A conditional the gate can
    -- read registers the states behind it as measured (`addSwitch`), and then the first term of
    -- the predicate answers before this one is ever reached -- so a version that forgot computed
    -- switches entirely would pass. This is the switch that measures nothing.
    test("a computed switch nothing conditions on asks for the beat", function()
        local plan = PlanFor({
            { type = Constants.MACROTEXT, key = "F1", value = "/cast [$state1] Renew", seq = 1 },
        }, {
            ["$state1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[mounted]" },
        });
        check(plan.statePoll == true, "a computed switch did not ask for the beat");
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
