-- **The loop binds a tail key to what its judgment item answers, as the world moves**
-- (`handing-the-rest-of-a-key-to-the-game.md` 2-5, 2-6, §8). What is asked is what the client says
-- the key is bound to (`GetBindingAction(key, true)`, the override table `restricted.lua` writes),
-- after Blizzard's beat or one of our own wakes has gone round.
--
-- `judgment_spec.lua` holds the item against the press at every point of its columns, and the loop
-- against the item at the same points. This file holds what that sweep cannot: a wake of ours with
-- no beat behind it, a pass that rewrites only the keys whose columns moved, and a key handed to the
-- game being left alone and coming back judged.
--
-- What is **not** here: Blizzard's manager delivering the beat at all, and how often. No manager runs
-- here; `Interp:beat()` writes what the beat driver the rebuild registered would.

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

    local GUID = "Player-1-JUDGMENTLOOP";
    local MAP = "TOGGLEWORLDMAP";
    local interp;

    -- Registered before the first rebuild, for the reason `eval_spec.lua` gives.
    local groupFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(groupFrame, "group");
    groupFrame:SetAttribute("unit", "party1");
    local otherFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(otherFrame, "group");
    otherFrame:SetAttribute("unit", "party2");

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.value = t.value or (t.type == Constants.SPELL and 774 or nil);
        t.key = t.key or "F1";
        t.seq = seq;
        return t;
    end

    --- Puts the world back the way every case starts. **Also run before the rebuild**, because the
    --- rebuild ends by judging every tail key against whatever world is standing.
    local function ResetWorld()
        if (interp) then
            interp:resetState();
            interp:clearHoverSlot();
            interp.driver.__attributes["state-giveback"] = nil;
        end
        shim.world.units = { player = { id = "me", reaction = "help" } };
    end

    local function Bind(actions, options, bindings)
        shim.world.spells[774] = { name = "Rejuvenation" };
        shim.world.bindings = bindings or {};
        ResetWorld();
        _G.UnitGUID = function() return GUID; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = { account = { GENERAL = { [0] = {
                ["$s1"] = { mode = Constants.SWITCH_MODES.MANUAL },
                ["$c1"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" },
            } } } },
        };
        DebindPrivate.InitDB();
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:takeWrites();
    end

    local function Bound(key)
        return _G.GetBindingAction(key, true) or "";
    end

    local function IsOurs(key)
        return Bound(key):sub(1, 6) == "CLICK ";
    end

    --- No override of ours on the key. **Not `Bound(key) == ""`**: a key the game binds answers with
    --- the game's own command once ours is off, which is what letting it go is for.
    local function Released(key)
        return interp.bindings[key] == nil;
    end

    local function Writes()
        local list = interp:takeWrites();
        table.sort(list);
        return table.concat(list, " ");
    end

    ---------------------------------------------------------------------------
    -- The beat
    ---------------------------------------------------------------------------

    test("B1 B2 the key is taken and let go as the state moves", function()
        Bind({ action({ conditions = { combat = true } }), action({ type = Constants.GIVEBACK }) });
        check(Released("F1"), "the rebuild left F1 bound out of combat: " .. Bound("F1"));
        interp.state.combat = true;
        interp:beat();
        check(IsOurs("F1"), "a beat in combat did not take F1: " .. Bound("F1"));
        interp.state.combat = false;
        interp:beat();
        check(Released("F1"), "a beat out of combat did not let F1 go: " .. Bound("F1"));
    end);

    test("B3 a command takes the key as the game's own binding", function()
        Bind({
            action({ conditions = { combat = true } }),
            action({ type = Constants.COMMAND, value = MAP }),
        });
        check(Bound("F1") == MAP, "F1 is not on the command: " .. Bound("F1"));
        interp.state.combat = true;
        interp:beat();
        check(IsOurs("F1"), "a beat in combat did not take F1: " .. Bound("F1"));
    end);

    -- Without the state moving, a beat measures and binds nothing; and where one key's column
    -- moves, only that key is bound again, with the chords made from it: each of those has a twin
    -- on the same column, and where the twin fails the chord follows its base key (2-3). A key with
    -- no tail is never touched by a beat.
    test("a beat binds again only the keys whose columns moved", function()
        Bind({
            action({ key = "F1", conditions = { combat = true } }),
            action({ key = "F1", type = Constants.GIVEBACK }),
            action({ key = "F2", conditions = { mounted = true } }),
            action({ key = "F2", type = Constants.GIVEBACK }),
            action({ key = "F3" }),
        });
        check(IsOurs("F3"), "F3 holds no tail and is not ours");
        interp:beat();
        local writes = Writes();
        check(writes == "", "a beat with nothing moved bound keys: " .. writes);
        interp.state.combat = true;
        interp:beat();
        writes = Writes();
        check(writes == "ALT-CTRL-F1 ALT-F1 CTRL-F1 F1",
            "combat moving bound other than F1 and its chords: " .. writes);
        interp.state.combat = false;
        interp.state.mounted = true;
        interp:beat();
        writes = Writes();
        check(writes == "ALT-CTRL-F1 ALT-CTRL-F2 ALT-F1 ALT-F2 CTRL-F1 CTRL-F2 F1 F2",
            "combat and mounted moving did not bind exactly F1, F2 and their chords: " .. writes);
    end);

    -- **Two keys whose items say the same thing are judged once** (2-5, §3-3). Both follow the
    -- state; how many times it was worked out is in no binding, so the count of bundles is what is
    -- left to ask, the way `parseCount` is for a parse that was skipped. The chords of the two keys
    -- differ by their base and are bundles of their own.
    test("keys with the same item share one bundle", function()
        Bind({
            action({ key = "F1", conditions = { combat = true } }),
            action({ key = "F1", type = Constants.GIVEBACK }),
            action({ key = "F2", value = 585, conditions = { combat = true } }),
            action({ key = "F2", type = Constants.GIVEBACK }),
        });
        local bare = 0;
        for _, bundle in ipairs(interp.env.Judge.bundles) do
            if (not bundle.base) then
                bare = bare + 1;
            end
        end
        check(bare == 1, "F1 and F2 were judged apart: " .. bare .. " bundles");
        check(Released("F1") and Released("F2"), "F1 or F2 is bound at peace");
        interp.state.combat = true;
        interp:beat();
        check(IsOurs("F1") and IsOurs("F2"), "the shared bundle did not take both keys");
    end);

    test("a computed switch is worked out on the beat", function()
        Bind({ action({ conditions = { ["$c1"] = true } }), action({ type = Constants.GIVEBACK }) });
        check(Released("F1"), "F1 is bound with the switch false: " .. Bound("F1"));
        interp.state.combat = true;
        interp:beat();
        check(IsOurs("F1"), "the switch turning true on the beat did not take F1");
    end);

    -- **The manager is Blizzard's and every addon's.** An event somebody else had already asked it
    -- for is not ours to take back when our columns stop reading it, or their drivers stop waking.
    test("an event another addon registered on the manager is left registered", function()
        local manager = _G.SecureStateDriverManager;
        manager:RegisterEvent("ZONE_CHANGED");
        Bind({ action({ conditions = { indoors = true } }), action({ type = Constants.GIVEBACK }) });
        Bind({ action({ conditions = { combat = true } }), action({ type = Constants.GIVEBACK }) });
        local still = manager:IsEventRegistered("ZONE_CHANGED");
        manager:UnregisterEvent("ZONE_CHANGED");
        check(still, "the rebuild unregistered an event it never registered");
    end);

    ---------------------------------------------------------------------------
    -- The chords (2-3)
    ---------------------------------------------------------------------------

    test("B9 to B13 the chords follow their tier and their base key", function()
        Bind({
            action({ conditions = { units = { ["@"] = {} } } }),
            action({ type = Constants.GIVEBACK }),
        });
        -- B13: no target, no focus.
        check(Released("F1"), "B13: F1 is bound");
        check(Released("ALT-F1"), "B13: ALT-F1 is bound");
        check(IsOurs("CTRL-F1"), "the self chord always has a winner and was let go");

        -- B11: the focus alone.
        shim.world.units.focus = { id = "f", reaction = "help" };
        interp:beat();
        check(Released("F1"), "B11: F1 is bound with no target");
        check(IsOurs("ALT-F1"), "B11: ALT-F1 is not ours with a focus");

        -- B10: the target alone. The focus chord is held while the bare key is ours.
        shim.world.units.focus = nil;
        shim.world.units.target = { id = "t", reaction = "help" };
        interp:beat();
        check(IsOurs("F1"), "B10: F1 is not ours with a target");
        check(IsOurs("ALT-F1"), "B10: ALT-F1 was let go while F1 is ours");
    end);

    -- **With `usualIgnoresResolvedUnit` the bare key always has a winner** and is never handed on
    -- (`falling-back-when-the-resolved-unit-fails.md` §6). The focus chord still asks the focus, and
    -- with none it follows the bare key, which is ours.
    test("B10 to B13 with the Resolved Unit fallback: the bare key stays ours", function()
        Bind({
            action({ casting = { usualIgnoresResolvedUnit = true }, conditions = { units = { ["@"] = {} } } }),
            action({ type = Constants.GIVEBACK }),
        });
        -- B13: no target, no focus.
        check(IsOurs("F1"), "B13: F1 was let go");
        check(IsOurs("ALT-F1"), "B13: ALT-F1 was let go while F1 is ours");

        -- B11 and B12: the focus alone.
        shim.world.units.focus = { id = "f", reaction = "help" };
        interp:beat();
        check(IsOurs("F1"), "B11: F1 was let go with no target");
        check(IsOurs("ALT-F1"), "B11: ALT-F1 is not ours with a focus");

        -- B10: the target alone.
        shim.world.units.focus = nil;
        shim.world.units.target = { id = "t", reaction = "help" };
        interp:beat();
        check(IsOurs("F1"), "B10: F1 is not ours with a target");
        check(IsOurs("ALT-F1"), "B10: ALT-F1 was let go while F1 is ours");
    end);

    -- **A chord goes on at priority false, its key at true** (2-4). Priority decides between two
    -- owners on one key whatever order they were set in (§6, measured), so another addon's override
    -- at true wins over a chord at false even when the loop sets the chord again after it. Asked after
    -- the rebuild, after a beat that rewrites the chord, and after a key handed to the game comes back.
    test("the chords are bound at false, and the keys at true", function()
        local function Priority(key)
            local entry = interp.bindings[key];
            return entry and entry.priority;
        end
        Bind({
            action({ key = "1", conditions = { combat = true } }),
            action({ key = "1", type = Constants.GIVEBACK }),
            action({ key = "F3" }),
        }, { giveBackOnReplacedBar = true }, { { action = "ACTIONBUTTON1", keys = { "1" } } });
        check(Priority("F3") == true and Priority("ALT-F3") == false,
            "after the rebuild F3 " .. tostring(Priority("F3")) .. ", ALT-F3 " .. tostring(Priority("ALT-F3")));
        interp.state.combat = true;
        interp:beat();
        check(Priority("1") == true and Priority("ALT-1") == false,
            "after a beat 1 " .. tostring(Priority("1")) .. ", ALT-1 " .. tostring(Priority("ALT-1")));
        interp.driverHandle:SetAttribute("state-giveback", "v");
        interp.driverHandle:SetAttribute("state-giveback", nil);
        check(Priority("1") == true and Priority("ALT-1") == false,
            "after coming back 1 " .. tostring(Priority("1")) .. ", ALT-1 " .. tostring(Priority("ALT-1")));
    end);

    ---------------------------------------------------------------------------
    -- Our own wakes
    ---------------------------------------------------------------------------

    test("the cursor on a frame wakes the loop with no beat", function()
        Bind({
            action({ conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
            action({ type = Constants.GIVEBACK }),
        });
        check(Released("F1"), "F1 is bound with nothing pointed at");
        shim.world.units.party1 = { id = "p1", reaction = "help" };
        interp:hoverEnter(groupFrame);
        check(IsOurs("F1"), "pointing at a friendly frame did not take F1");
        interp:hoverLeave(groupFrame);
        check(Released("F1"), "leaving the frame did not let F1 go");
    end);

    -- **A wake of ours never enters the handler.** It runs its own body (`RunAttribute`), since
    -- whoever wakes the loop already holds the driver; writing an attribute to get a body run would
    -- pay a handler entry on every frame boundary the cursor crossed
    -- (`trimming-the-tail-key-beat.md` 5-2).
    -- **One beat driver at a time, the one the login check picked** (`BeatSignal.lua`). A rebuild
    -- that moves the beat takes the old driver off before it puts the new one on, or both would
    -- carry it.
    test("the beat's driver follows the signal, one at a time", function()
        local actions = {
            action({ conditions = { combat = true } }),
            action({ type = Constants.GIVEBACK }),
        };
        local function Drivers()
            return frames.attributeDrivers[interp and interp.driver] or {};
        end
        -- Put back however the case ends, or every case after it rebuilds on the wrong signal.
        local ok, err = pcall(function()
            for _, case in ipairs({
                { comes = nil, on = "judgebeat" },
                { comes = true, on = "state-visibility" },
                { comes = false, on = "judgebeat" },
                { comes = true, on = "state-visibility" },
            }) do
                DebindPrivate.BeatSignal.comes = case.comes;
                Bind(actions);
                local what = tostring(case.comes) .. ": ";
                check(Drivers().judgebeat == (case.on == "judgebeat" and "a" or nil),
                    what .. "the attribute driver is " .. tostring(Drivers().judgebeat));
                check(Drivers()["state-visibility"] == (case.on == "state-visibility" and "show" or nil),
                    what .. "the visibility driver is " .. tostring(Drivers()["state-visibility"]));
                interp.state.combat = true;
                interp:beat();
                check(IsOurs("F1"), what .. "a beat in combat did not take F1");
                interp.state.combat = false;
                interp:beat();
                check(Released("F1"), what .. "a beat at peace did not let F1 go");
            end
            Bind({ action({ conditions = { ["$s1"] = true } }), action({ type = Constants.GIVEBACK }) });
            check(Drivers().judgebeat == nil and Drivers()["state-visibility"] == nil,
                "a profile the beat measures nothing for kept a beat driver");
        end);
        DebindPrivate.BeatSignal.comes = nil;
        if (not ok) then
            error(err, 0);
        end
    end);

    test("a wake of ours does not run the handler", function()
        Bind({
            action({ conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
            action({ type = Constants.GIVEBACK }),
        });
        shim.world.units.party1 = { id = "p1", reaction = "help" };
        local before = interp.handlerRuns;
        interp:hoverEnter(groupFrame);
        check(IsOurs("F1"), "pointing at a friendly frame did not take F1");
        check(interp.handlerRuns - before == 0,
            "the cursor's wake ran the handler " .. (interp.handlerRuns - before) .. " times");
        before = interp.handlerRuns;
        interp:hoverLeave(groupFrame);
        check(Released("F1"), "leaving the frame did not let F1 go");
        check(interp.handlerRuns - before == 0,
            "the cursor's wake ran the handler " .. (interp.handlerRuns - before) .. " times");
    end);

    ---------------------------------------------------------------------------
    -- Under a period of 0 (§5-1 of `zeroing-the-beat-period-where-it-is-needed.md`): enter and leave
    -- only write the slot, and the frame's beat judges. A case under 0 first shows the cursor's move
    -- bound nothing by itself, or the ordinary form, whose wakes judge, would pass it as well.
    ---------------------------------------------------------------------------

    --- **A new options table on every call**: the addon writes into the one it is handed.
    local function BindPointed(period)
        Bind({
            action({ conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
            action({ type = Constants.GIVEBACK }),
        }, period and { stateDriverPeriod = period } or nil);
        shim.world.units.party1 = { id = "p1", reaction = "help" };
        shim.world.units.party2 = { id = "p2", reaction = "harm" };
    end

    test("under 0 the cursor arriving and leaving is judged on the beat", function()
        BindPointed(0);
        interp:hoverEnter(groupFrame);
        check(Released("F1"), "under 0 pointing at a frame bound F1 by itself");
        interp:beat();
        check(IsOurs("F1"), "a beat over a friendly frame did not take F1");
        interp:hoverLeave(groupFrame);
        check(IsOurs("F1"), "under 0 leaving the frame let F1 go by itself");
        interp:beat();
        check(Released("F1"), "a beat after the cursor left did not let F1 go");
    end);

    test("under 0 leaving and entering between two beats is judged on the frame reached", function()
        BindPointed(0);
        interp:hoverEnter(groupFrame);
        interp:beat();
        check(IsOurs("F1"), "a beat over a friendly frame did not take F1");
        interp:hoverLeave(groupFrame);
        interp:hoverEnter(groupFrame);
        interp:beat();
        check(IsOurs("F1"), "leaving and coming back to the same frame let F1 go");
        interp:hoverLeave(groupFrame);
        interp:hoverEnter(otherFrame);
        check(IsOurs("F1"), "under 0 moving to a hostile frame let F1 go by itself");
        interp:beat();
        check(Released("F1"), "a beat over a hostile frame did not let F1 go");
        interp:hoverLeave(otherFrame);
        interp:hoverEnter(groupFrame);
        interp:beat();
        check(IsOurs("F1"), "a beat back over the friendly frame did not take F1");
    end);

    -- F3: the frame laid out again, the cursor never moving and nothing sent. **A unit gone is the
    -- cursor leaving as far as the beat can tell**, under either period: the frame's token goes, and
    -- its watch has to say the cell was left (`unitFragment`).
    test("a unit changing or gone under a still cursor is judged on the beat", function()
        for _, case in ipairs({ { what = "0.2" }, { what = "0", period = 0 } }) do
            BindPointed(case.period);
            interp:hoverEnter(groupFrame);
            interp:beat();
            check(IsOurs("F1"), case.what .. ": a beat over a friendly frame did not take F1");
            local ok, err = pcall(function()
                for _, step in ipairs({
                    { unit = "party2", ours = false, what = "turned hostile" },
                    { unit = "party1", ours = true, what = "turned friendly again" },
                    { unit = "party9", ours = false, what = "lost its unit" },
                    { unit = "party1", ours = true, what = "had its unit back" },
                }) do
                    groupFrame:SetAttribute("unit", step.unit);
                    interp:beat();
                    check(IsOurs("F1") == step.ours, string.format("%s: a beat after the frame %s left F1 %s",
                        case.what, step.what, Bound("F1")));
                end
            end);
            groupFrame:SetAttribute("unit", "party1");
            interp:clearHoverSlot();
            if (not ok) then
                error(err, 0);
            end
        end
    end);

    -- **The form follows the period the rebuild writes** (§4): one taking 0 off bakes the ordinary
    -- form again, and a period that is not 0 never gets the one that leaves judging to the beat.
    test("a rebuild off 0 judges the cursor's moves where they happen again", function()
        for _, case in ipairs({
            { what = "0 taken off" },
            { what = "a period of 0.1", period = 0.1 },
        }) do
            BindPointed(0);
            BindPointed(case.period);
            interp:hoverEnter(groupFrame);
            check(IsOurs("F1"), case.what .. ": pointing at a friendly frame did not take F1");
            interp:hoverLeave(groupFrame);
            check(Released("F1"), case.what .. ": leaving the frame did not let F1 go");
        end
    end);

    test("a switch set by hand wakes the loop with no beat", function()
        Bind({ action({ conditions = { ["$s1"] = true } }), action({ type = Constants.GIVEBACK }) });
        check(Released("F1"), "F1 is bound with the switch unset");
        interp.driverHandle:RunAttribute("SetSwitch", "$s1", true);
        check(IsOurs("F1"), "setting the switch did not take F1");
        interp.driverHandle:RunAttribute("SetSwitch", "$s1", false);
        check(Released("F1"), "clearing the switch did not let F1 go");
    end);

    ---------------------------------------------------------------------------
    -- Keys given back (2-6)
    ---------------------------------------------------------------------------

    local GIVE_BACK = { giveBackOnReplacedBar = true };
    local ACTION_BUTTON_ON_1 = { { action = "ACTIONBUTTON1", keys = { "1" } } };

    test("G4 G5 a key given back is left alone and comes back judged", function()
        Bind({
            action({ key = "1", conditions = { combat = true } }),
            action({ key = "1", type = Constants.GIVEBACK }),
        }, GIVE_BACK, ACTION_BUTTON_ON_1);
        interp.driverHandle:SetAttribute("state-giveback", "v");
        check(Released("1"), "the vehicle bar did not take 1");
        interp.state.combat = true;
        interp:beat();
        check(Released("1"), "G4: the loop took back a key handed to the game");
        interp.driverHandle:SetAttribute("state-giveback", nil);
        check(IsOurs("1"), "G5: the key came back other than judged now: " .. Bound("1"));
    end);

    test("G6 a key held when handed over comes back on its command", function()
        Bind({
            action({ key = "1", conditions = { combat = true } }),
            action({ key = "1", type = Constants.COMMAND, value = MAP }),
        }, GIVE_BACK, ACTION_BUTTON_ON_1);
        interp.state.combat = true;
        interp:beat();
        check(IsOurs("1"), "1 is not ours in combat");
        interp.driverHandle:SetAttribute("state-giveback", "v");
        interp.state.combat = false;
        interp:beat();
        check(Released("1"), "G4: the loop wrote a key handed to the game: " .. Bound("1"));
        interp.driverHandle:SetAttribute("state-giveback", nil);
        check(Bound("1") == MAP, "G6: the key came back other than on its command: " .. Bound("1"));
    end);

    ---------------------------------------------------------------------------
    -- A press where no action runs (`giving-keys-back-when-no-action-runs.md`). With
    -- `giveBackWhenNoActionRuns` on, every key ends as though a giveback stood unconditional at its
    -- end; off, the default, it ends in a block as before.
    ---------------------------------------------------------------------------

    local HOLD_UNMATCHED = { giveBackWhenNoActionRuns = false };
    local GIVE_BACK_UNMATCHED = { giveBackWhenNoActionRuns = true };

    test("N1 a key whose only action does not run is given back", function()
        Bind({ action({ conditions = { combat = true } }) }, GIVE_BACK_UNMATCHED);
        check(Released("F1"), "F1 is bound out of combat: " .. Bound("F1"));
        interp.state.combat = true;
        interp:beat();
        check(IsOurs("F1"), "a beat in combat did not take F1: " .. Bound("F1"));
        interp.state.combat = false;
        interp:beat();
        check(Released("F1"), "a beat out of combat did not let F1 go: " .. Bound("F1"));
    end);

    test("N2 with the option off the key is held", function()
        Bind({ action({ conditions = { combat = true } }) }, HOLD_UNMATCHED);
        check(IsOurs("F1"), "F1 was let go with the option off: " .. Bound("F1"));
        check(DebindPrivate.JudgmentItems["F1"] == nil, "an item was built with the option off");
    end);

    -- An action that always runs ends the key before the end is reached, so the key has nothing to
    -- judge and stays out of the loop. Nothing, unconditional, is such an action.
    test("N3 a key ending in an action that always runs stays held and out of the loop", function()
        Bind({ action({ conditions = { combat = true } }), action({ value = 774 }) }, GIVE_BACK_UNMATCHED);
        check(IsOurs("F1"), "F1 was let go: " .. Bound("F1"));
        check(DebindPrivate.JudgmentItems["F1"] == nil, "an item was built for F1");

        Bind({ action({ conditions = { combat = true } }), action({ type = Constants.BLOCK }) },
            GIVE_BACK_UNMATCHED);
        check(IsOurs("F1"), "F1 ending in Nothing was let go: " .. Bound("F1"));
        check(DebindPrivate.JudgmentItems["F1"] == nil, "an item was built for F1 ending in Nothing");
    end);

    test("N4 a Nothing with conditions holds the key only where they hold", function()
        Bind({
            action({ conditions = { combat = true } }),
            action({ type = Constants.BLOCK, conditions = { mounted = true } }),
        }, GIVE_BACK_UNMATCHED);
        check(Released("F1"), "F1 is bound out of combat and unmounted: " .. Bound("F1"));
        interp.state.mounted = true;
        interp:beat();
        check(IsOurs("F1"), "mounted, the Nothing did not hold F1: " .. Bound("F1"));
    end);

    -- An action that runs only while a unit frame is pointed at runs on no plain press.
    test("N5 an action only over unit frames gives the key back away from them", function()
        shim.world.units.party1 = { id = "p1", reaction = "help" };
        Bind({ action({ casting = { normalCast = false, hoverCast = "cast" } }) }, GIVE_BACK_UNMATCHED);
        shim.world.units.party1 = { id = "p1", reaction = "help" };
        interp:beat();
        check(Released("F1"), "F1 is bound with no frame pointed at: " .. Bound("F1"));
        interp:hoverEnter(groupFrame);
        check(IsOurs("F1"), "F1 was not taken over the frame: " .. Bound("F1"));
        interp:hoverLeave(groupFrame);
        check(Released("F1"), "F1 was not let go off the frame: " .. Bound("F1"));
    end);

    -- The same case as B9 to B13 with no giveback written: the chords answer as they do there.
    test("N6 the chords follow their tier and their base key", function()
        Bind({ action({ conditions = { units = { ["@"] = {} } } }) }, GIVE_BACK_UNMATCHED);
        check(Released("F1"), "B13: F1 is bound");
        check(Released("ALT-F1"), "B13: ALT-F1 is bound");
        check(IsOurs("CTRL-F1"), "the self chord always has a winner and was let go");

        shim.world.units.focus = { id = "f", reaction = "help" };
        interp:beat();
        check(Released("F1"), "B11: F1 is bound with no target");
        check(IsOurs("ALT-F1"), "B11: ALT-F1 is not ours with a focus");

        shim.world.units.focus = nil;
        shim.world.units.target = { id = "t", reaction = "help" };
        interp:beat();
        check(IsOurs("F1"), "B10: F1 is not ours with a target");
        check(IsOurs("ALT-F1"), "B10: ALT-F1 was let go while F1 is ours");
    end);

    return T;
end
