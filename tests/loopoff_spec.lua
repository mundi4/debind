-- With `giveBackWhenNoActionRuns` off, every key that holds a key record is ours for good, and a
-- press nothing answers does nothing (`dropping-the-game-fallback.md` §2, §3). On, the default, a
-- key where no action can ever run is not held at all, and one whose actions run in some states is
-- judged (`giving-keys-back-when-no-action-runs.md`; `judgmentloop_spec.lua`). Each case asks both
-- where the two part. No WoW client needed.
--
-- **Asked of the emission fixture too**, the one profile shaped to reach every branch of the
-- rebuild, and not only of keys built to pass: a key that came out unbound there is a
-- key the game still answers for.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    -- The eval hook is DEBUG-only, and so is everything below that presses a key.
    if (ctx and ctx.shipped) then
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

    --- A party frame for the cases that click one. **Registered before the first rebuild**, which is
    --- when the interpreter replays everything recorded so far; a frame registered after that never
    --- reaches it. So every case in this file runs with it registered.
    local groupFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(groupFrame, "group");
    groupFrame:SetAttribute("unit", "party1");

    local function Rebuild()
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
    end

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    local HOLD_UNMATCHED = { giveBackWhenNoActionRuns = false };

    local function Bind(actions, options)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        Rebuild();
    end

    local function Bound(key)
        return _G.GetBindingAction(key, true) or "";
    end

    local function IsOurs(key)
        local bound = Bound(key);
        return bound:sub(1, 6) == "CLICK "
            and bound:match(":(.*)$") == Constants.CLICKTIME_BUTTON_PREFIX .. key;
    end

    ---------------------------------------------------------------------------
    -- The fixture
    ---------------------------------------------------------------------------

    -- Asked of `KeyMap` rather than of a list written here, so a key the fixture gains is asked too.
    -- A key whose every record is click-cast only holds no key record and is left to the frame.
    --
    -- **A key holding a tail is the one exception, and the reader put it there.** Its judgment item
    -- decides whose it is from state to state (`handing-the-rest-of-a-key-to-the-game.md` 2-2), and
    -- `judgment_spec.lua` holds what it is bound to.
    test("every key of the emission fixture that holds a key record and no tail is ours", function()
        local fixture = assert(loadfile(ctx.root .. "/emit_fixture.lua"))()(DebindPrivate, shim);
        fixture.install();
        DebindPrivate.Options.giveBackWhenNoActionRuns = false;
        Rebuild();

        local notOurs, asked = {}, 0;
        for key, bindings in pairs(DebindPrivate.KeyMap) do
            local holds = false;
            for i = 1, #bindings do
                holds = holds or bindings[i].holdsKey;
            end
            if (holds and not DebindPrivate.JudgmentItems[key]) then
                asked = asked + 1;
                if (not IsOurs(key)) then
                    notOurs[#notOurs + 1] = key .. "=" .. Bound(key);
                end
            end
        end
        table.sort(notOurs);
        check(asked > 30, "keys asked: " .. asked);
        check(#notOurs == 0, "not ours: " .. table.concat(notOurs, ", "));
    end);

    ---------------------------------------------------------------------------
    -- The three ways a key used to be handed back. The gap no longer does; an unused or a command
    -- does again, from where the reader put it
    ---------------------------------------------------------------------------

    -- The gap after the last action. Both halves are asked, so a key that never moves cannot pass.
    -- With the option on the gap is the key's end, which gives it back (`judgmentloop_spec.lua` N1).
    test("a key with a gap stays ours and does nothing in the gap", function()
        Bind({ action({ value = 585, key = "F1", conditions = { combat = true } }) });
        check(not IsOurs("F1"), "the option on left the key ours out of combat: " .. Bound("F1"));

        Bind({ action({ value = 585, key = "F1", conditions = { combat = true } }) }, HOLD_UNMATCHED);
        check(IsOurs("F1"), "the key is not ours out of combat: " .. Bound("F1"));
        check(interp:evalKey("F1") == nil, "something fired in the gap");

        interp.state.combat = true;
        check(IsOurs("F1"), "the key is not ours in combat: " .. Bound("F1"));
        check(interp:evalKey("F1") ~= nil, "the action did not fire in combat");
        interp:resetState();
    end);

    -- An unused stands where it was put: from its place the key is the game's, and nothing under it
    -- is reached by a plain press (`handing-the-rest-of-a-key-to-the-game.md` 2-1). The press is
    -- asked under the key's own button name, since the key let go reaches nothing of ours.
    test("an unused action stands where it is and cuts off the action under it", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true } }),
            action({ type = Constants.GIVEBACK, key = "F1" }),
            action({ value = 774, key = "F1" }),
        });

        check(interp.bindings.F1 == nil, "the key was not let go: " .. Bound("F1"));
        check(interp:evalUnder("F1") == nil, "the action saved under the unused one fired");
    end);

    test("a command hands the key to the command and the press does nothing", function()
        Bind({ action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "F1" }) });

        check(Bound("F1") == "TOGGLEWORLDMAP", "the key is not on the command: " .. Bound("F1"));
        check(interp:evalUnder("F1") == nil, "the press did something");
    end);

    ---------------------------------------------------------------------------
    -- A key on a live layer whose every action the rebuild leaves out
    ---------------------------------------------------------------------------

    -- **What a rebuild skips because it already knows the answer must do what a condition that
    -- never holds would.** To the reader the action is on the key; it just never runs (owner,
    -- 2026-10-07). So with the option off the key is held and the press does nothing, and with it
    -- on the key is not held at all -- not bound and let go by a beat, which would leave
    -- `IsKeyOurs` saying yes.
    --
    -- Each case asks `IsKeyOurs` beside the bound key, so the function and the key cannot part.
    local function checkOursAndSilent(key)
        check(IsOurs(key), "the key is not ours: " .. Bound(key));
        check(DebindPrivate.IsKeyOurs(key), "the key is bound to us and IsKeyOurs says no");
        check(interp:evalKey(key) == nil, "the press did something");
    end

    local function checkNotOurs(key)
        check(Bound(key) == "", "the key was bound: " .. Bound(key));
        check(not DebindPrivate.IsKeyOurs(key), "the key is not bound and IsKeyOurs says yes");
    end

    -- The shim plays specialization 1.
    local function OtherSpec()
        return { [select(3, UnitClass("player"))] = Constants.SpecIndexFlag(2) };
    end

    test("a key whose one action the specialization condition leaves out", function()
        Bind({ action({ value = 585, key = "F1", conditions = { specs = OtherSpec() } }) });
        checkNotOurs("F1");
        Bind({ action({ value = 585, key = "F1", conditions = { specs = OtherSpec() } }) }, HOLD_UNMATCHED);
        checkOursAndSilent("F1");
    end);

    -- **The frame keeps its click either way.** The hover action is click-cast only and holds
    -- nothing, so all that holds the key is the action the condition left out.
    test("a hover action on a mouse button beside a left-out action", function()
        local actions = function()
            return {
                action({ value = 585, key = "SHIFT-BUTTON2", conditions = { units = { unitframe = {} } } }),
                action({ value = 774, key = "SHIFT-BUTTON2", conditions = { specs = OtherSpec() } }),
            };
        end
        Bind(actions());
        checkNotOurs("SHIFT-BUTTON2");
        check(DebindPrivate.IsKeyHandled("SHIFT-BUTTON2"), "the frame's click no longer reads as ours");
        Bind(actions(), HOLD_UNMATCHED);
        checkOursAndSilent("SHIFT-BUTTON2");
    end);

    -- **A mouse button whose only action runs over a frame and is left out reaches nothing of ours**,
    -- whichever way the option stands: no frame click is written for it and no key is held, so the
    -- window must not read it as ours.
    test("a left-out frame action alone leaves its mouse button unhandled", function()
        local function actions()
            return { action({ value = 585, key = "SHIFT-BUTTON2",
                conditions = { units = { unitframe = {} }, specs = OtherSpec() } }) };
        end
        Bind(actions());
        check(not DebindPrivate.IsKeyHandled("SHIFT-BUTTON2"), "it reads as ours with the option on");
        Bind(actions(), HOLD_UNMATCHED);
        check(not DebindPrivate.IsKeyHandled("SHIFT-BUTTON2"), "it reads as ours with the option off");
    end);

    -- **Escape reaching a live layer some other way is still not a key** (`BuildKeyMap`), so the
    -- game menu is never taken. Set after loading, which is the path the data guards do not see.
    test("an action that comes to sit on Escape after loading does not take it", function()
        local stored = action({ value = 585, key = "F1" });
        Bind({ stored }, HOLD_UNMATCHED);
        ctx.HandMade(stored).key = "ESCAPE";
        Rebuild();
        check(not IsOurs("ESCAPE"), "Escape was taken: " .. Bound("ESCAPE"));
        check(not DebindPrivate.IsKeyHandled("ESCAPE"), "Escape reads as ours");
    end);

    -- **Negative of the one above.** Without it that case also passes on a rebuild that takes
    -- every mouse button it sees.
    test("a hover action alone leaves its mouse button to the frame", function()
        Bind({ action({ value = 585, key = "SHIFT-BUTTON2", conditions = { units = { unitframe = {} } } }) });
        checkNotOurs("SHIFT-BUTTON2");
    end);

    -- A binding with no way to fire is dropped per key, which left a key holding nothing.
    test("a key whose one action has no way to fire", function()
        Bind({ action({ type = Constants.PETACTION, value = "PETNOSUCHCOMMAND", key = "F1" }) });
        checkNotOurs("F1");
        Bind({ action({ type = Constants.PETACTION, value = "PETNOSUCHCOMMAND", key = "F1" }),
            }, HOLD_UNMATCHED);
        checkOursAndSilent("F1");
    end);

    -- **What an issue missed, the binding builder still refuses** (`PrepareKeyBindings`), and by then
    -- the key map has taken the binding. Run with every issue answered nil, which is the only way a
    -- refused value reaches the builder.
    local function WithoutIssues(fn)
        local real = DebindPrivate.GetIssueOutcome;
        DebindPrivate.GetIssueOutcome = function() return nil; end
        local ok, err = pcall(fn);
        DebindPrivate.GetIssueOutcome = real;
        if (not ok) then
            error(err, 0);
        end
    end

    -- **Whether the key is ours is settled after the builder has refused**, so the window and the
    -- key agree: with the option on nothing of ours is bound and the heading has to say so.
    test("a key whose only binding the builder refuses", function()
        WithoutIssues(function()
            local function actions()
                return { action({ type = Constants.PETACTION, value = "PETNOSUCHCOMMAND", key = "F1" }) };
            end
            Bind(actions());
            check(DebindPrivate.KeyMap["F1"] ~= nil, "the binding never reached the builder");
            checkNotOurs("F1");
            check(not DebindPrivate.IsKeyHandled("F1"), "a key not bound reads as ours");
            Bind(actions(), HOLD_UNMATCHED);
            checkOursAndSilent("F1");
            check(DebindPrivate.IsKeyHandled("F1"), "a key held doing nothing reads as not ours");
        end);
    end);

    -- **A mouse button that answers through the frame alone** holds no key, so the frame click the
    -- builder refused is the whole of it, whichever way the option stands.
    test("a frame action alone whose binding the builder refuses", function()
        WithoutIssues(function()
            local function actions()
                return { action({ type = Constants.PETACTION, value = "PETNOSUCHCOMMAND", key = "SHIFT-BUTTON2",
                    conditions = { units = { unitframe = {} } } }) };
            end
            Bind(actions());
            check(DebindPrivate.KeyMap["SHIFT-BUTTON2"] ~= nil, "the binding never reached the builder");
            checkNotOurs("SHIFT-BUTTON2");
            check(not DebindPrivate.IsKeyHandled("SHIFT-BUTTON2"), "it reads as ours with the option on");
            Bind(actions(), HOLD_UNMATCHED);
            checkNotOurs("SHIFT-BUTTON2");
            check(not DebindPrivate.IsKeyHandled("SHIFT-BUTTON2"), "it reads as ours with the option off");
        end);
    end);

    -- **Which binding each record that went out stands for, as the emission itself says**
    -- (`EmittedRecords`). The kit names a press's winner from it; a copy of the layout rule kept in
    -- the kit missed that the self and focus blocks go only where those keys are on, and that a
    -- binding the builder drops makes no record. Asked against the records the press really walks.
    test("the emission says which binding each record it sent stands for", function()
        local function checkKey(key, label)
            local records = interp:recordsFor(key) or {};
            local emitted = DebindPrivate.EmittedRecords and DebindPrivate.EmittedRecords[key] or {};
            check(#records > 0, label .. ": no records went out");
            check(#emitted == #records, label .. ": " .. #emitted .. " named for " .. #records .. " records");
            for i = 1, #records do
                local binding = emitted[i];
                check(binding ~= nil and binding.castModifier == records[i].castModifier,
                    label .. ": record " .. i .. " is named for another tier");
                check((binding.type == Constants.BLOCK) == (records[i].clickbutton == nil),
                    label .. ": record " .. i .. " is named for a block and is not one, or the other way");
            end
        end
        local function actions()
            return {
                action({ value = 6792, key = "F4", conditions = { combat = true } }),
                action({ value = 6793, key = "F4" }),
            };
        end
        Bind(actions(), { selfCast = false });
        checkKey("F4", "self cast key off");
        Bind(actions(), { focusCast = false });
        checkKey("F4", "focus cast key off");
        WithoutIssues(function()
            Bind({ action({ type = Constants.PETACTION, value = "PETNOSUCHCOMMAND", key = "F4",
                    conditions = { combat = true } }),
                action({ value = 6793, key = "F4" }) });
            checkKey("F4", "a binding the builder refuses");
            local onKey, named = 0, 0;
            for _, binding in ipairs(DebindPrivate.KeyMap["F4"] or {}) do
                if (binding.type == Constants.PETACTION) then onKey = onKey + 1; end
            end
            for _, binding in ipairs(DebindPrivate.EmittedRecords["F4"] or {}) do
                if (binding.type == Constants.PETACTION) then named = named + 1; end
            end
            check(onKey > 0 and named == 0, "the refused binding: " .. onKey .. " on the key, " .. named .. " named");
        end);
    end);

    -- **An action holding a value no build writes is left out, and deletes nothing under it.** Read as
    -- [when there is none], its unit condition would cover the real [when there is none] action
    -- below and the solver would delete that one (`INVALID_ACTION`).
    test("an action holding a value no build writes is left out and the one under it stays", function()
        Bind({
            action({ value = 6790, key = "F3", conditions = { units = { target = "from a hand edit" } } }),
            action({ value = 6791, key = "F3", conditions = { units = { target = false } } }),
        });
        local on = {};
        for _, binding in ipairs(DebindPrivate.KeyMap["F3"] or {}) do
            on[binding.value] = true;
        end
        check(not on[6790], "the invalid action reached the key");
        check(on[6791], "the [when there is none] action under it was deleted");
    end);

    -- **A role or frame type on a unit that is not the pointed frame's is not a condition**, so it
    -- cannot empty a binding by meeting another row there. `"@"` on an action with no target lands
    -- on `target`, and the two picked roles below never meet; the solver keeps the binding, and the
    -- emission has to send the record it kept.
    test("roles that do not meet on a unit nothing measures them on still make a record", function()
        local units = shim.world.units;
        local saved = units.target;
        units.target = { id = "t", reaction = "help" };
        local ok, err = pcall(function()
            Bind({ action({ value = 6789, key = "F2", conditions = { units = {
                ["@"] = { role = Constants.ROLE_TANK },
                target = { role = Constants.ROLE_HEALER },
            } } }) }, HOLD_UNMATCHED);
            -- **The original, which is the one whose `"@"` lands on `target`.** The self and focus twins
            -- carry the same rows with `"@"` on `player` and `focus`, and their records go out either way.
            local original;
            for _, binding in ipairs(DebindPrivate.KeyMap["F2"] or {}) do
                if (binding.castModifier == Constants.CASTMOD_NONE) then
                    original = binding;
                end
            end
            check(original and not original.dead, "the solver left the original off");
            local sent = false;
            for _, record in ipairs(interp:recordsFor("F2") or {}) do
                sent = sent or (record.castModifier == Constants.CASTMOD_NONE and record.clickbutton ~= nil);
            end
            check(sent, "the solver kept the original and the emission sent no record for it");
        end);
        units.target = saved;
        if (not ok) then
            error(err, 0);
        end
    end);

    -- **A profile from before 8 loses Escape as a key on the way up** (`MigrateLayer`), so the game
    -- menu keeps it. The action stays, keyless. With the option off as well: nothing about holding
    -- is asked here.
    test("an action stored on Escape loses the key and the game keeps it", function()
        shim.world.bindings = { { action = "TOGGLEGAMEMENU", keys = { "ESCAPE" } } };
        local ok, err = pcall(function()
            _G.DebindVars = {
                dbver = 7,
                options = HOLD_UNMATCHED,
                shared = { GENERAL = { action({ value = 585, key = "ESCAPE" }) } },
                characters = { [GUID] = { switches = {} } },
                migrated = {},
                switches = {},
            };
            DebindPrivate.InitDB();
            Rebuild();
            -- Read back out of the profile: the ladder raises a copy (`TryMigrateDB`).
            local stored = _G.DebindVars.layers.account.GENERAL[0][1];
            check(stored.value == 585, "the action did not stay");
            check(stored.key == nil, "the action kept Escape: " .. tostring(stored.key));
            check(#DebindPrivate.CollectActionsForKey("ESCAPE") == 0, "an action still stands on Escape");
            -- The game's own binding stays on it, so what is asked is that ours is not.
            check(Bound("ESCAPE") == "TOGGLEGAMEMENU", "the key was bound: " .. Bound("ESCAPE"));
            check(not DebindPrivate.IsKeyOurs("ESCAPE"), "the key is not bound and IsKeyOurs says yes");
        end);
        shim.world.bindings = {};
        if (not ok) then
            error(err, 0);
        end
    end);

    -- **The bare left and right click are never taken** (`which-action-a-key-runs.md` §7),
    -- and no longer because of an issue: the action there runs over a unit frame or not at all.
    test("the bare left click is not taken", function()
        Bind({ action({ value = 585, key = "BUTTON1" }) });
        checkNotOurs("BUTTON1");
    end);

    return T;
end
