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

    --- What one press of `key` on both edges fired (`restricted.lua`'s `press`), with `down` and
    --- `up` the modifiers held at each edge: every edge the gate acted on, in order, and the name of
    --- the binding the press came in on.
    local function PressEdges(key, down, up, useKeyDown)
        interp:resetState();
        local fires, _, name = interp:press(key, { down = down, up = up, useKeyDown = useKeyDown });
        return fires, name;
    end

    --- The one edge a press fired a click on, after checking there was exactly one and on `edge`.
    local function OneClick(fires, edge)
        check(#fires == 1, #fires .. " edges acted");
        local fire = fires[1];
        check(fire.edge == edge and fire.kind == "click",
            "the " .. fire.edge .. " edge acted (" .. fire.kind .. ")");
        return fire;
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

    -- **Another addon's override is the game's side too.** A bar or click-casting addon puts its keys
    -- on overrides of its own with nothing in the saved set behind them, and a press of that chord
    -- went to it before the chords were bound. Asked of the saved set alone, the chord read as free
    -- and was taken at priority.
    test("N7a another addon's override on a chord is left to it by default", function()
        local other = frames.newFrame("Frame");
        _G.SetOverrideBindingClick(other, false, "ALT-F1", "OtherButton");
        Bind({ action({ value = 774, key = "F1" }) });
        local bound = BoundTo("ALT-F1");
        _G.ClearOverrideBindings(other);
        check(bound == "CLICK OtherButton:LeftButton", "ALT-F1 is bound to " .. bound);
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

    local WithCastKeys = shim.withCastKeys;

    -- With self on SHIFT, F1's self chord is the game's SHIFT-F1 and its both-cast chord
    -- ALT-SHIFT-F1 would land there too, so neither is ours.
    test("N11a a modifier held on top goes to the game's chord under it first", function()
        WithCastKeys("SHIFT", "ALT", function()
            Bind({ action({ value = 774, key = "F1" }) }, nil,
                { { action = "TOGGLEWORLDMAP", keys = { "SHIFT-F1" } } });
            check(not Ours("ALT-SHIFT-F1"), "ALT-SHIFT-F1 is bound to " .. BoundTo("ALT-SHIFT-F1"));
            check(Press("SHIFT-F1", "FOCUSCAST") == nil, "the press reached us");
        end);
    end);

    test("N12 a key with a modifier of its own gets the chord on top of it", function()
        Bind({ action({ value = 774, key = "SHIFT-F1" }) });
        check(Ours("ALT-SHIFT-F1"), "ALT-SHIFT-F1 is bound to " .. BoundTo("ALT-SHIFT-F1"));
        check(Tier(Press("SHIFT-F1", "FOCUSCAST")) == Constants.CASTMOD_FOCUS, "not the focus twin");
    end);

    test("N14 both cast keys on ALT give ALT to self", function()
        WithCastKeys("ALT", "ALT", function()
            Bind({ action({ value = 774, key = "F1" }) });
            check(Ours("ALT-F1") and not Ours("CTRL-F1"),
                "ALT-F1 " .. BoundTo("ALT-F1") .. ", CTRL-F1 " .. BoundTo("CTRL-F1"));
            check(Tier(Press("ALT-F1")) == Constants.CASTMOD_SELF, "not the self twin");
        end);
    end);

    test("N15 a cast key on NONE has no chord", function()
        WithCastKeys("NONE", "ALT", function()
            Bind({ action({ value = 774, key = "F1" }) });
            check(not Ours("CTRL-F1"), "CTRL-F1 is bound to " .. BoundTo("CTRL-F1"));
            check(Tier(Press("CTRL-F1")) == Constants.CASTMOD_NONE, "not the original");
        end);
    end);

    local SKIP_SELF = { selfCastKey = "skip" };
    local SKIP_BOTH = { selfCastKey = "skip", focusCastKey = "skip" };

    test("N18 a key with no twins gets no chords and a held press does nothing", function()
        Bind({ action({ value = 774, key = "F1", casting = SKIP_BOTH }) });
        for _, chord in ipairs({ "CTRL-F1", "ALT-F1", "ALT-CTRL-F1" }) do
            check(not Ours(chord), chord .. " is bound to " .. BoundTo(chord));
        end
        check(Tier(Press("F1")) == Constants.CASTMOD_NONE, "the bare key lost its original");
        for _, held in ipairs({ { "SELFCAST" }, { "FOCUSCAST" }, { "SELFCAST", "FOCUSCAST" } }) do
            local record = Press("F1", unpack(held));
            check(record == nil, table.concat(held, "+") .. " sent " .. tostring(Tier(record)));
        end
    end);

    test("N19 a held press over a frame with no twins does nothing", function()
        Bind({ action({ value = 774, key = "F1", casting = { selfCastKey = "skip", focusCastKey = "skip",
            hoverCast = "cast" } }) });
        shim.world.units.party1 = { id = "pal", reaction = "help" };
        interp:hoverEnter(unitFrame);
        local _, _, pointed = Press("F1");
        local held = Press("F1", "FOCUSCAST");
        interp:hoverLeave(unitFrame);
        check(pointed == "party1", "the pointed press went at " .. tostring(pointed));
        check(held == nil, "a held pointed press sent " .. tostring(Tier(held)));
    end);

    test("N20 with the option off a chord with no twin is the game's", function()
        Bind({ action({ value = 774, key = "F1", casting = SKIP_SELF }) }, { castKeyChordsOverGame = true },
            { { action = "TOGGLEWORLDMAP", keys = { "CTRL-F1" } } });
        check(BoundTo("CTRL-F1") == "TOGGLEWORLDMAP", "CTRL-F1 is bound to " .. BoundTo("CTRL-F1"));
        check(Press("F1", "SELFCAST") == nil, "the press reached us");
    end);

    test("N21 with no self twin both cast keys held fall to the focus twin", function()
        Bind({ action({ value = 774, key = "F1", casting = SKIP_SELF }) });
        check(Ours("ALT-F1"), "ALT-F1 is bound to " .. BoundTo("ALT-F1"));
        for _, chord in ipairs({ "CTRL-F1", "ALT-CTRL-F1" }) do
            check(not Ours(chord), chord .. " is bound to " .. BoundTo(chord));
        end
        local record, _, unit = Press("F1", "SELFCAST", "FOCUSCAST");
        check(Tier(record) == Constants.CASTMOD_FOCUS and unit == "focus",
            "tier " .. tostring(Tier(record)) .. " at " .. tostring(unit));
    end);

    -- Either way the option is set: with it off, nothing but the rule keeps the both-held chord
    -- from being taken for focus over the game's self chord under it.
    test("N21a with no self twin both cast keys held go to the game's self chord", function()
        for _, options in ipairs({ {}, { castKeyChordsOverGame = true } }) do
            Bind({ action({ value = 774, key = "F1", casting = SKIP_SELF }) }, options,
                { { action = "TOGGLEWORLDMAP", keys = { "CTRL-F1" } } });
            local label = options.castKeyChordsOverGame and "option off: " or "option on: ";
            check(not Ours("ALT-CTRL-F1"), label .. "ALT-CTRL-F1 is bound to " .. BoundTo("ALT-CTRL-F1"));
            check(Press("F1", "SELFCAST", "FOCUSCAST") == nil, label .. "the press reached us");
        end
    end);

    test("N22 both cast keys on ALT give ALT to focus where no action uses self", function()
        WithCastKeys("ALT", "ALT", function()
            Bind({ action({ value = 774, key = "F1", casting = SKIP_SELF }) });
            check(Ours("ALT-F1"), "ALT-F1 is bound to " .. BoundTo("ALT-F1"));
            local record, _, unit = Press("F1", "FOCUSCAST");
            check(Tier(record) == Constants.CASTMOD_FOCUS and unit == "focus",
                "tier " .. tostring(Tier(record)) .. " at " .. tostring(unit));
        end);
    end);

    test("N22a both cast keys on ALT and no twins leave ALT alone", function()
        WithCastKeys("ALT", "ALT", function()
            Bind({ action({ value = 774, key = "F1", casting = SKIP_BOTH }) });
            check(not Ours("ALT-F1"), "ALT-F1 is bound to " .. BoundTo("ALT-F1"));
            check(Press("F1", "FOCUSCAST") == nil, "ALT reached a tier");
        end);
    end);

    test("N23 a cast key turned off in the settings is a key not held", function()
        Bind({ action({ value = 774, key = "F1" }) }, { selfCast = false });
        check(not Ours("CTRL-F1"), "CTRL-F1 is bound to " .. BoundTo("CTRL-F1"));
        check(Tier(Press("F1", "SELFCAST")) == Constants.CASTMOD_NONE, "not the original");
    end);

    test("N24 a key's own modifier is hidden from its press", function()
        Bind({ action({ value = 774, key = "ALT-F1" }) });
        check(Tier(Press("ALT-F1")) == Constants.CASTMOD_NONE, "not the original");
    end);

    ---------------------------------------------------------------------------
    -- 8-1. Both edges of a press
    ---------------------------------------------------------------------------

    test("R0 cast on key down fires the press edge alone", function()
        Bind({ action({ value = 774, key = "F1" }) });
        local fire = OneClick(PressEdges("F1", {}, { "CTRL" }, true), "down");
        check(Tier(fire.record) == Constants.CASTMOD_NONE, "tier " .. tostring(Tier(fire.record)));
    end);

    test("R1 a self cast key held before the release sends the self twin", function()
        Bind({ action({ value = 774, key = "F1" }) });
        local fire = OneClick(PressEdges("F1", {}, { "CTRL" }, false), "up");
        check(Tier(fire.record) == Constants.CASTMOD_SELF and fire.unit == "player",
            "tier " .. tostring(Tier(fire.record)) .. " at " .. tostring(fire.unit));
    end);

    test("R2 a focus cast key held before the release sends the focus twin", function()
        Bind({ action({ value = 774, key = "F1" }) });
        local fire = OneClick(PressEdges("F1", {}, { "ALT" }, false), "up");
        check(Tier(fire.record) == Constants.CASTMOD_FOCUS and fire.unit == "focus",
            "tier " .. tostring(Tier(fire.record)) .. " at " .. tostring(fire.unit));
    end);

    test("R3 a self cast key held before the release does nothing with no self twin", function()
        Bind({ action({ value = 774, key = "F1", casting = SKIP_SELF }) });
        local fires = PressEdges("F1", {}, { "CTRL" }, false);
        check(#fires == 0, "the " .. tostring(fires[1] and fires[1].edge) .. " edge fired "
            .. tostring(fires[1] and Tier(fires[1].record)));
    end);

    test("R5 self cast added to a focus press before the release sends the self twin", function()
        Bind({ action({ value = 774, key = "F1" }) });
        local fire = OneClick(PressEdges("F1", { "ALT" }, { "ALT", "CTRL" }, false), "up");
        check(Tier(fire.record) == Constants.CASTMOD_SELF and fire.unit == "player",
            "tier " .. tostring(Tier(fire.record)) .. " at " .. tostring(fire.unit));
    end);

    test("R6 both cast keys held at the press send the self twin after self is let go", function()
        Bind({ action({ value = 774, key = "F1" }) });
        local fires, name = PressEdges("F1", { "CTRL", "ALT" }, { "ALT" }, false);
        check(name == "ALT-CTRL-F1", "the press came in on " .. tostring(name));
        local fire = OneClick(fires, "up");
        check(Tier(fire.record) == Constants.CASTMOD_SELF and fire.unit == "player",
            "tier " .. tostring(Tier(fire.record)) .. " at " .. tostring(fire.unit));
    end);

    test("R6a with no self twin the same press sends the focus twin", function()
        Bind({ action({ value = 774, key = "F1", casting = SKIP_SELF }) });
        local fires, name = PressEdges("F1", { "CTRL", "ALT" }, { "ALT" }, false);
        check(name == "ALT-F1", "the press came in on " .. tostring(name));
        local fire = OneClick(fires, "up");
        check(Tier(fire.record) == Constants.CASTMOD_FOCUS and fire.unit == "focus",
            "tier " .. tostring(Tier(fire.record)) .. " at " .. tostring(fire.unit));
    end);

    test("R7 a held spell started at the press is let go at the release", function()
        shim.world.spells[8936] = { name = "Regrowth", pressAndHold = true };
        Bind({ action({ value = 8936, key = "F1" }) });
        interp:resetState();
        interp.state.channeling = true;
        local fires = interp:press("F1", { up = { "CTRL" }, useKeyDown = false });
        interp:resetState();
        check(#fires == 2, #fires .. " edges acted");
        check(fires[1].edge == "down" and fires[1].kind == "click"
            and Tier(fires[1].record) == Constants.CASTMOD_NONE,
            "the press: " .. fires[1].edge .. " " .. fires[1].kind .. " " .. tostring(Tier(fires[1].record)));
        check(fires[2].edge == "up" and fires[2].kind == "release" and fires[2].button == fires[1].button,
            "the release: " .. fires[2].edge .. " " .. fires[2].kind .. " " .. tostring(fires[2].button));
    end);

    test("R7a a press with nothing to run lets nothing go of a release that never came", function()
        shim.world.spells[8936] = { name = "Regrowth", pressAndHold = true };
        Bind({ action({ value = 8936, key = "F1", casting = SKIP_SELF }) });
        interp:resetState();
        interp:runWrapped(DebindPrivate.DefaultClickFrame, "OnClick", Constants.CLICKTIME_BUTTON_PREFIX .. "F1", true);
        interp.state.channeling = true;
        local fires = interp:press("F1", { down = { "CTRL" }, useKeyDown = false });
        interp:resetState();
        check(#fires == 0, "the " .. tostring(fires[1] and fires[1].edge) .. " edge "
            .. tostring(fires[1] and fires[1].kind) .. " " .. tostring(fires[1] and fires[1].button));
    end);

    --- Fires the login the way the client does, once per spec, so the handlers it registers and the
    --- hooks it installs are standing.
    local loggedIn = false;
    local function LogIn()
        if (loggedIn) then
            return;
        end
        loggedIn = true;
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        local mark = frames.mark();
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");
        frames.drainTimers();
        interp:replay(frames.since(mark));
    end

    --- Did anything since `mark` take the driver's overrides off, which a rebuild always does first.
    local function Rebuilt(mark)
        for _, entry in ipairs(frames.since(mark)) do
            if (entry.kind == "ClearOverrideBindings" and entry.frame == DebindPrivate.BindingDriver) then
                return true;
            end
        end
        return false;
    end

    -- **Not before the login.** Another addon can move a cast key while its own files load, and a
    -- rebuild queued then runs before the profile is up.
    test("a cast key moved before the login queues no rebuild", function()
        frames.drainTimers();
        _G.SetModifiedClick("FOCUSCAST", "ALT");
        check(#frames.timers == 0, "a rebuild was queued before the login");
    end);

    test("N16 moving a cast key in the options moves its chords", function()
        Bind({ action({ value = 774, key = "F1" }) });
        LogIn();
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
        Bind({ action({ value = 774, key = "F1" }) });
        LogIn();
        check(Ours("ALT-F1"), "ALT-F1 is not ours to begin with");

        local mark = frames.mark();
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

    -- **An addon putting an override on one of our chords after the rebuild gets a rebuild**, which
    -- then leaves the chord to it (N7a). Overrides move with no event; the call is the signal.
    test("an override another addon puts on a chord later is answered with a rebuild", function()
        Bind({ action({ value = 774, key = "F1" }) });
        LogIn();
        check(Ours("ALT-F1"), "ALT-F1 is not ours to begin with");

        local other = frames.newFrame("Frame");
        local mark = frames.mark();
        _G.SetOverrideBindingClick(other, false, "ALT-F1", "OtherButton");
        frames.drainTimers();
        interp:replay(frames.since(mark));
        local rebuilt, bound = Rebuilt(mark), BoundTo("ALT-F1");
        _G.ClearOverrideBindings(other);
        frames.drainTimers();
        check(rebuilt, "no rebuild followed the other addon's override");
        check(bound == "CLICK OtherButton:LeftButton", "ALT-F1 is bound to " .. bound);
    end);

    -- **Our own overrides do not count**, or the rebuild's own `ClearOverrideBindings` would queue
    -- the next rebuild and the addon would never stop rebuilding. A chord is left to the game's
    -- binding here, which is what makes a cleared override worth a rebuild at all.
    test("a rebuild's own overrides queue no rebuild", function()
        Bind({ action({ value = 774, key = "F1" }) }, nil,
            { { action = "TOGGLEWORLDMAP", keys = { "ALT-F1" } } });
        LogIn();
        frames.drainTimers();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        check(#frames.timers == 0, "a rebuild queued another");
    end);

    ---------------------------------------------------------------------------
    -- 8-3. A tail in the middle
    ---------------------------------------------------------------------------

    -- The action under the tail answers presses over a frame; with no tail it would take this one.
    -- **The tail follows Hover Cast like any action**, so whether it holds that press back is its
    -- own value: on the pointed unit or the usual target it stands ahead of the action under it,
    -- and "don't run while pointing" lets the press past.
    local function M2(tailCasting)
        local list = { action({ value = 585, key = "F1", conditions = { combat = true } }) };
        if (tailCasting) then
            list[#list + 1] = action({ type = Constants.GIVEBACK, key = "F1", casting = tailCasting });
        end
        list[#list + 1] = action({ value = 774, key = "F1", casting = { hoverCast = "cast" } });
        Bind(list);
        shim.world.units.party1 = { id = "pal", reaction = "help" };
        interp:hoverEnter(unitFrame);
        local record, spell = Press("F1");
        interp:hoverLeave(unitFrame);
        return record, spell;
    end

    test("M2 a tail holds back the pointed twin of the action under it", function()
        local _, spell = M2(nil);
        check(spell == "Rejuvenation", "without the tail the pointed press went to " .. tostring(spell));
        for _, casting in ipairs({ { hoverCast = "cast" }, {} }) do
            local record = M2(casting);
            check(record == nil, tostring(casting.hoverCast) .. ": a pointed press got past the unused: "
                .. tostring(record and record.value));
        end
    end);

    test("M2a a tail that does not run while pointing lets the pointed press past", function()
        local _, spell = M2({ hoverCast = "skip" });
        check(spell == "Rejuvenation", "the pointed press went to " .. tostring(spell));
    end);

    test("M3 a tail holds back the actions under it only on the key itself", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true } }),
            action({ type = Constants.GIVEBACK, key = "F1" }),
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
