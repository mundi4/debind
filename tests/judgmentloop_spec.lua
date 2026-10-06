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
        Bind({ action({ conditions = { combat = true } }), action({ type = Constants.UNUSED }) });
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
            action({ key = "F1", type = Constants.UNUSED }),
            action({ key = "F2", conditions = { mounted = true } }),
            action({ key = "F2", type = Constants.UNUSED }),
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
            action({ key = "F1", type = Constants.UNUSED }),
            action({ key = "F2", value = 585, conditions = { combat = true } }),
            action({ key = "F2", type = Constants.UNUSED }),
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
        Bind({ action({ conditions = { ["$c1"] = true } }), action({ type = Constants.UNUSED }) });
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
        Bind({ action({ conditions = { indoors = true } }), action({ type = Constants.UNUSED }) });
        Bind({ action({ conditions = { combat = true } }), action({ type = Constants.UNUSED }) });
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
            action({ type = Constants.UNUSED }),
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

    -- **A chord goes on at priority false, its key at true** (2-4). Priority decides between two
    -- owners on one key whatever order they were set in (§6, measured), so another addon's override
    -- at true wins over the chord even when the loop sets the chord again after it. Asked after the
    -- rebuild, after a beat that rewrites the chord, and after a key handed to the game comes back.
    test("the chords are bound at priority false and the keys at true", function()
        Bind({
            action({ key = "1", conditions = { combat = true } }),
            action({ key = "1", type = Constants.UNUSED }),
            action({ key = "F3" }),
        }, { giveBackOnReplacedBar = true }, { { action = "ACTIONBUTTON1", keys = { "1" } } });
        local function Priority(key)
            local entry = interp.bindings[key];
            return entry and entry.priority;
        end
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
            action({ type = Constants.UNUSED }),
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
            action({ type = Constants.UNUSED }),
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
            Bind({ action({ conditions = { ["$s1"] = true } }), action({ type = Constants.UNUSED }) });
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
            action({ type = Constants.UNUSED }),
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

    test("a switch set by hand wakes the loop with no beat", function()
        Bind({ action({ conditions = { ["$s1"] = true } }), action({ type = Constants.UNUSED }) });
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
            action({ key = "1", type = Constants.UNUSED }),
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

    return T;
end
