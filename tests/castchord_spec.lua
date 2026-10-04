-- **The self and focus tiers on chords of their own** (`handing-the-rest-of-a-key-to-the-game.md`
-- 2-3, 2-4, 2-6). Each case is a row of that document's answer table, named by its number.
--
-- A press is run the way the client runs it (`restricted.lua`'s `evalKey`): the cast keys held
-- are added to the key, the chord is looked up with one modifier dropped at a time, and the
-- decision runs under the button the binding it landed on carries. So the question each case asks
-- is the reader's own: what goes out when this is pressed.
--
-- The world puts SELFCAST on CTRL and FOCUSCAST on ALT unless a case says otherwise
-- (`wow_shim.lua`).

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    -- `evalKey` reaches the decision through a DEBUG-only attribute (`eval_spec.lua` says why).
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

    local GUID = "Player-1-CASTCHORD";
    local interp;

    --- A registered unit frame for the pointed presses. Registered before the first rebuild, for the
    --- reason `eval_spec.lua` gives: the interpreter is stood up on what was recorded so far.
    local unitFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(unitFrame, "group");
    unitFrame:SetAttribute("unit", "party1");

    shim.world.spells[585] = { name = "Renew" };
    shim.world.spells[774] = { name = "Rejuvenation" };

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    --- Stands a profile up over the game's own `gameBindings` and rebuilds. The world's units and
    --- modifiers are each case's to set before this.
    local function Bind(actions, options, gameBindings)
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        shim.world.bindings = gameBindings or {};
        _G.UnitGUID = function() return GUID; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = {},
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
        shim.world.units = {
            player = { id = "me", reaction = "help" },
            target = { id = "friend", reaction = "help" },
            focus = { id = "buddy", reaction = "help" },
        };
    end

    --- What a press of `key` sends, with the cast keys named in `held` down: the record that won,
    --- the spell its button casts, and the unit.
    local function Press(key, ...)
        interp:resetState();
        for i = 1, select("#", ...) do
            interp.state.modifiedClick[select(i, ...)] = true;
        end
        local _, button, record, unit = interp:evalKey(key);
        interp:resetState();
        if (not button) then
            return nil;
        end
        return record, DebindPrivate.DefaultClickFrame:GetAttribute("*spell-" .. interp:actionButton(button)),
            unit;
    end

    local function BoundTo(key)
        return _G.GetBindingAction(key, true) or "";
    end

    local function Ours(key)
        return BoundTo(key):sub(1, 6) == "CLICK ";
    end

    local function Tier(record)
        return record and record.castModifier;
    end

    ---------------------------------------------------------------------------
    -- 8-1. No tail
    ---------------------------------------------------------------------------

    test("N3 the focus chord casts the focus twin at the focus", function()
        Bind({ action({ value = 774, key = "F1" }) });
        check(Ours("ALT-F1"), "ALT-F1 is bound to " .. BoundTo("ALT-F1"));
        local record, spell, unit = Press("F1", "FOCUSCAST");
        check(Tier(record) == Constants.CASTMOD_FOCUS, "tier " .. tostring(Tier(record)));
        check(spell == "Rejuvenation" and unit == "focus", tostring(spell) .. " at " .. tostring(unit));
    end);

    test("N4 a focus tier with no winner does nothing", function()
        Bind({ action({ value = 774, key = "F1",
            conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }) });
        shim.world.units.focus = { id = "enemy", reaction = "harm" };
        local record = Press("F1", "FOCUSCAST");
        check(record == nil or record.clickbutton == nil, "something went out: " .. tostring(record));
        local plain = Press("F1");
        check(Tier(plain) == Constants.CASTMOD_NONE, "the bare key lost its action");
    end);

    test("N5 the self chord casts the self twin at the player", function()
        Bind({ action({ value = 774, key = "F1" }) });
        check(Ours("CTRL-F1"), "CTRL-F1 is bound to " .. BoundTo("CTRL-F1"));
        local record, _, unit = Press("F1", "SELFCAST");
        check(Tier(record) == Constants.CASTMOD_SELF and unit == "player",
            "tier " .. tostring(Tier(record)) .. " at " .. tostring(unit));
    end);

    test("N6 both cast keys held picks self", function()
        Bind({ action({ value = 774, key = "F1" }) });
        check(Ours("ALT-CTRL-F1"), "ALT-CTRL-F1 is bound to " .. BoundTo("ALT-CTRL-F1"));
        local record = Press("F1", "SELFCAST", "FOCUSCAST");
        check(Tier(record) == Constants.CASTMOD_SELF, "tier " .. tostring(Tier(record)));
    end);

    test("N7 the game's own chord is left to the game by default", function()
        Bind({ action({ value = 774, key = "F1" }) }, nil,
            { { action = "TOGGLEWORLDMAP", keys = { "ALT-F1" } } });
        check(BoundTo("ALT-F1") == "TOGGLEWORLDMAP", "ALT-F1 is bound to " .. BoundTo("ALT-F1"));
        check(Press("F1", "FOCUSCAST") == nil, "the press reached us");
    end);

    test("N8 the game's own chord is taken when the reader says so", function()
        Bind({ action({ value = 774, key = "F1" }) }, { castKeyChordsOverGame = true },
            { { action = "TOGGLEWORLDMAP", keys = { "ALT-F1" } } });
        check(Ours("ALT-F1"), "ALT-F1 is bound to " .. BoundTo("ALT-F1"));
        check(Tier(Press("F1", "FOCUSCAST")) == Constants.CASTMOD_FOCUS, "not the focus twin");
    end);

    test("N9 a chord that is a key of its own runs that key", function()
        Bind({
            action({ value = 774, key = "F1" }),
            action({ value = 585, key = "ALT-F1" }),
        });
        local record, spell = Press("ALT-F1");
        check(Tier(record) == Constants.CASTMOD_NONE and spell == "Renew",
            "tier " .. tostring(Tier(record)) .. ", " .. tostring(spell));
        record, spell = Press("F1", "FOCUSCAST");
        check(spell == "Renew", "a focus press on F1 went to " .. tostring(spell));
    end);

    test("N10 a cast key turned off leaves its chord to the bare key", function()
        Bind({ action({ value = 774, key = "F1" }) }, { focusCast = false });
        check(not Ours("ALT-F1"), "ALT-F1 is bound to " .. BoundTo("ALT-F1"));
        check(Tier(Press("F1", "FOCUSCAST")) == Constants.CASTMOD_NONE, "not the original");
    end);

    test("N11 a modifier held on top falls to the focus chord", function()
        Bind({ action({ value = 774, key = "F1" }) });
        check(not Ours("ALT-SHIFT-F1"), "ALT-SHIFT-F1 is bound to " .. BoundTo("ALT-SHIFT-F1"));
        check(Tier(Press("SHIFT-F1", "FOCUSCAST")) == Constants.CASTMOD_FOCUS, "not the focus twin");
    end);

    -- With self on SHIFT, F1's self chord is the game's SHIFT-F1 and its both-cast chord
    -- ALT-SHIFT-F1 would land there too, so neither is ours.
    test("N11a a modifier held on top goes to the game's chord under it first", function()
        shim.world.modifiedClicks.SELFCAST = "SHIFT";
        Bind({ action({ value = 774, key = "F1" }) }, nil,
            { { action = "TOGGLEWORLDMAP", keys = { "SHIFT-F1" } } });
        check(not Ours("ALT-SHIFT-F1"), "ALT-SHIFT-F1 is bound to " .. BoundTo("ALT-SHIFT-F1"));
        check(Press("SHIFT-F1", "FOCUSCAST") == nil, "the press reached us");
        shim.world.modifiedClicks.SELFCAST = "CTRL";
    end);

    test("N12 a key with a modifier of its own gets the chord on top of it", function()
        Bind({ action({ value = 774, key = "SHIFT-F1" }) });
        check(Ours("ALT-SHIFT-F1"), "ALT-SHIFT-F1 is bound to " .. BoundTo("ALT-SHIFT-F1"));
        check(Tier(Press("SHIFT-F1", "FOCUSCAST")) == Constants.CASTMOD_FOCUS, "not the focus twin");
    end);

    test("N14 both cast keys on ALT give ALT to self", function()
        shim.world.modifiedClicks.SELFCAST = "ALT";
        shim.world.modifiedClicks.FOCUSCAST = "ALT";
        Bind({ action({ value = 774, key = "F1" }) });
        check(Ours("ALT-F1") and not Ours("CTRL-F1"), "ALT-F1 " .. BoundTo("ALT-F1") .. ", CTRL-F1 " .. BoundTo("CTRL-F1"));
        check(Tier(Press("ALT-F1")) == Constants.CASTMOD_SELF, "not the self twin");
        shim.world.modifiedClicks.SELFCAST = "CTRL";
    end);

    test("N15 a cast key on NONE has no chord", function()
        shim.world.modifiedClicks.SELFCAST = "NONE";
        Bind({ action({ value = 774, key = "F1" }) });
        check(not Ours("CTRL-F1"), "CTRL-F1 is bound to " .. BoundTo("CTRL-F1"));
        check(Tier(Press("CTRL-F1")) == Constants.CASTMOD_NONE, "not the original");
        shim.world.modifiedClicks.SELFCAST = "CTRL";
    end);

    test("N16 moving a cast key in the options moves its chords", function()
        Bind({ action({ value = 774, key = "F1" }) });
        check(Ours("ALT-F1"), "ALT-F1 is not ours to begin with");
        local mark = frames.mark();
        _G.SetModifiedClick("FOCUSCAST", "SHIFT");
        frames.drainTimers();
        interp:replay(frames.since(mark));
        check(not Ours("ALT-F1"), "ALT-F1 is still " .. BoundTo("ALT-F1"));
        check(Ours("SHIFT-F1"), "SHIFT-F1 is bound to " .. BoundTo("SHIFT-F1"));
        check(Tier(Press("SHIFT-F1")) == Constants.CASTMOD_FOCUS, "not the focus twin");
        shim.world.modifiedClicks.FOCUSCAST = "ALT";
    end);

    -- Switching between the account and the character binding set moves the cast keys with no call
    -- to `SetModifiedClick`; what comes is `UPDATE_BINDINGS`, with the new set's values already
    -- readable (§6-1, measured).
    --
    -- **The login is fired first**, since `UPDATE_BINDINGS` is registered in its handler and an
    -- event nobody listens for would measure nothing.
    test("N17 switching the binding set moves the chords", function()
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        Bind({ action({ value = 774, key = "F1" }) });
        local mark = frames.mark();
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");
        frames.drainTimers();
        interp:replay(frames.since(mark));
        check(Ours("ALT-F1"), "ALT-F1 is not ours to begin with");

        mark = frames.mark();
        shim.world.modifiedClicks.FOCUSCAST = "SHIFT";
        local heard = frames.fireEvent("UPDATE_BINDINGS");
        frames.drainTimers();
        interp:replay(frames.since(mark));
        local altF1, shiftF1 = BoundTo("ALT-F1"), BoundTo("SHIFT-F1");
        shim.world.modifiedClicks.FOCUSCAST = "ALT";

        check(heard > 0, "nothing is listening for UPDATE_BINDINGS");
        check(altF1:sub(1, 6) ~= "CLICK ", "ALT-F1 is still " .. altF1);
        check(shiftF1:sub(1, 6) == "CLICK ", "SHIFT-F1 is bound to " .. shiftF1);
    end);

    ---------------------------------------------------------------------------
    -- 8-3. A tail in the middle
    ---------------------------------------------------------------------------

    -- The action under the tail answers presses over a frame; with no tail it would take this one.
    test("M2 a tail holds back the pointed twin of the action under it", function()
        local function Actions(withTail)
            local list = { action({ value = 585, key = "F1", conditions = { combat = true } }) };
            if (withTail) then
                list[#list + 1] = action({ type = Constants.UNUSED, key = "F1" });
            end
            list[#list + 1] = action({ value = 774, key = "F1", casting = { hoverCast = "cast" } });
            return list;
        end

        Bind(Actions(false));
        shim.world.units.party1 = { id = "pal", reaction = "help" };
        interp:hoverEnter(unitFrame);
        local _, spell = Press("F1");
        interp:hoverLeave(unitFrame);
        check(spell == "Rejuvenation", "without the tail the pointed press went to " .. tostring(spell));

        Bind(Actions(true));
        shim.world.units.party1 = { id = "pal", reaction = "help" };
        interp:hoverEnter(unitFrame);
        local record = Press("F1");
        interp:hoverLeave(unitFrame);
        check(record == nil, "a pointed press got past the unused: " .. tostring(record and record.value));
    end);

    test("M3 a tail holds back the actions under it only on the key itself", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true } }),
            action({ type = Constants.UNUSED, key = "F1" }),
            action({ value = 774, key = "F1" }),
        });
        check(Press("F1") == nil, "a plain press got past the unused");
        local record, spell = Press("F1", "FOCUSCAST");
        check(Tier(record) == Constants.CASTMOD_FOCUS and spell == "Rejuvenation",
            "a focus press: tier " .. tostring(Tier(record)) .. ", " .. tostring(spell));
    end);

    ---------------------------------------------------------------------------
    -- 8-4. Giving keys back
    ---------------------------------------------------------------------------

    test("G2 a key handed to the bar takes its chords with it", function()
        Bind({ action({ value = 774, key = "1" }) }, { giveBackOnReplacedBar = true },
            { { action = "ACTIONBUTTON1", keys = { "1" } } });
        interp.driverHandle:SetAttribute("state-giveback", "p");
        for _, key in ipairs({ "1", "ALT-1", "CTRL-1", "ALT-CTRL-1" }) do
            check(not Ours(key), key .. " stayed ours over the bar");
        end
        interp.driverHandle:SetAttribute("state-giveback", nil);
        for _, key in ipairs({ "1", "ALT-1", "CTRL-1", "ALT-CTRL-1" }) do
            check(Ours(key), key .. " did not come back");
        end
    end);

    test("G3 a key of the reader's own is not a chord of the key handed over", function()
        Bind({
            action({ value = 774, key = "1" }),
            action({ value = 585, key = "ALT-1" }),
        }, { giveBackOnReplacedBar = true }, { { action = "ACTIONBUTTON1", keys = { "1" } } });
        interp.driverHandle:SetAttribute("state-giveback", "p");
        check(not Ours("1"), "1 stayed ours over the bar");
        check(Ours("ALT-1"), "the reader's ALT-1 went over with 1");
        interp.driverHandle:SetAttribute("state-giveback", nil);
    end);

    return T;
end
