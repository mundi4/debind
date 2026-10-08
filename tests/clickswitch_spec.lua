-- A computed switch is worked out at the press, and nothing works one out between presses. No WoW
-- client needed.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local MODES = Constants.SWITCH_MODES;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    -- The eval hook is DEBUG-only.
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

    local GUID = "Player-1-CLICKSWITCH";
    local interp;

    --- Registered before the first rebuild, for the reason `eval_spec.lua` gives at the same place.
    local unitFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(unitFrame, "group");

    local Rebuild;

    local function Bind(switches, key, actions)
        _G.UnitGUID = function() return GUID; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = {
                account = { GENERAL = { [0] = actions or {
                    { type = Constants.SPELL, value = 585, key = key or "F1", seq = 1,
                        conditions = { ["$s1"] = true } },
                } } },
                [GUID] = { [Constants.PLAYER_CLASS] = {} },
            },
            characters = { [GUID] = { class = Constants.PLAYER_CLASS } },
            migrated = {},
            switches = { account = { GENERAL = { [0] = switches or {} } } },
            -- **Every key here is held with nothing running.** This file asks what the press
            -- answers with no beat in between, and a key given back would not be pressed at all
            -- until one came (`giving-keys-back-when-no-action-runs.md`).
            options = { giveBackWhenNoActionRuns = false },
        };
        DebindPrivate.InitDB();
        return Rebuild();
    end

    --- A rebuild on the profile that is already loaded.
    ---
    --- **Split out because a reload is not a rebuild.** `Bind` builds `DebindVars` from scratch, so
    --- anything written into the profile since -- a switch value the character remembers, say --
    --- goes with it. A case about what survives a rebuild has to use this one.
    function Rebuild()
        -- A case that failed with combat on must not hand that to the next one.
        if (interp) then
            interp:resetState();
        end
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
        return interp;
    end

    local function Fires(key)
        return interp:evalKey(key or "F1") ~= nil;
    end

    ---------------------------------------------------------------------------
    -- At the press
    ---------------------------------------------------------------------------

    -- **No beat in between**, which is the whole case: nothing but the press can have worked the
    -- switch out when it answers.
    test("a computed switch with no message is worked out at the press", function()
        Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[combat]" } });

        interp.state.combat = true;
        check(Fires(), "combat went on and the key hanging off [combat] fired nothing");

        interp.state.combat = false;
        check(not Fires(), "combat went off and the key still fired");
        interp:resetState();
    end);

    -- **The press reports nothing back.** A computed switch has a value only at the press that
    -- worked it out, so a value carried outside is one nobody can measure again: the screen it
    -- reached drew it as what the switch is now, and the character's memory took it for something
    -- somebody had set by hand.
    --
    -- What is asserted is the insecure side, because that is where the report landed. The press
    -- itself still has to answer, which the case above covers.
    test("the press reports nothing about a computed switch", function()
        Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[combat]" } });
        frames.drainTimers();
        check(DebindPrivate.Switches["$s1"].value ~= true, "setup: the switch already reads on");

        interp.state.combat = true;
        Fires();
        frames.drainTimers();
        check(DebindPrivate.Switches["$s1"].value ~= true,
            "the press wrote what it worked out into the definition");
        check(DebindPrivate.db.charState.switches["$s1"] == nil,
            "the press wrote what it worked out into this character's memory");
        interp:resetState();
    end);

    -- **And nothing is pushed in, either.** A stored value for a computed switch is what the last
    -- press left behind; pushed back in at the next rebuild it would stand as the switch's value
    -- until a press replaced it -- and it goes in through `SetSwitch`, which reports it straight
    -- back out to the two places above.
    test("a rebuild pushes no stored value in for a computed switch", function()
        local i = Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[combat]" } });

        DebindPrivate.SetSwitchValue("$s1", true);
        Rebuild();

        check(i.env.States["$s1"] == nil,
            "the rebuild pushed a stored value in: " .. tostring(i.env.States["$s1"]));
    end);

    -- **What gives a defined switch no unset cell in a judgment item** (`RecordConstraints`): after a
    -- rebuild a manual one is a boolean in `States` before anything reads it, and a computed one is in
    -- `ComputedSwitches`, which the press works out ahead of comparing (`COMPUTE_SWITCHES_SNIPPET`).
    -- Lose either and the item holds a key the press can no longer match.
    test("after a rebuild a defined switch is never left unset", function()
        local i = Bind({ ["$s1"] = { mode = MODES.MANUAL } });
        check(type(i.env.States["$s1"]) == "boolean",
            "a manual switch is " .. tostring(i.env.States["$s1"]) .. " in States");

        i = Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[combat]" } });
        local listed = false;
        for _, name in ipairs(i.env.ComputedSwitches) do
            listed = listed or name == "$s1";
        end
        check(listed, "a computed switch a record reads is not in ComputedSwitches");
    end);

    -- **A switch built on another computed switch reads that one's answer from the same press.**
    -- Both move with combat and neither is on the beat, so a stale value on either link shows.
    test("a chain of computed switches is worked out in order at the press", function()
        Bind({
            ["$s1"] = { mode = MODES.EXPR, expr = "[$s2]" },
            ["$s2"] = { mode = MODES.EXPR, expr = "[combat]" },
        });

        interp.state.combat = true;
        check(Fires(), "the near link moved and the far one did not follow at the press");

        interp.state.combat = false;
        check(not Fires(), "the near link went off and the far one still fired");
        interp:resetState();
    end);

    -- **`@unitframe` inside a switch is the frame the press judged, not the alias the poll keeps.** The
    -- cursor stays on the frame while its unit changes, and no beat runs. The interpreter answers a
    -- target selector as a match whoever it names, so what is asked is the text the press parsed.
    test("an @unitframe inside a switch is composed from the frame at the press", function()
        shim.world.units = {
            party1 = { id = "p1", reaction = "help" },
            party2 = { id = "p2", reaction = "help" },
        };
        Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[@unitframe]" } });

        unitFrame:SetAttribute("unit", "party1");
        interp:hoverEnter(unitFrame);
        local before = interp:parseCount("[@party1]");
        Fires();
        check(interp:parseCount("[@party1]") > before, "the press did not compose [@unitframe] from the frame");

        unitFrame:SetAttribute("unit", "party2");
        before = interp:parseCount("[@party2]");
        Fires();
        check(interp:parseCount("[@party2]") > before,
            "the frame's unit changed under the cursor and the press composed the old one");

        interp:clearHoverSlot();
        shim.world.units = {};
    end);

    -- **A toggle and the whole chain hanging off it land inside the one click.** Two computed
    -- links deep, and the press is the only thing that works either of them out, so what this
    -- asks is whether the key the far link gates fires on the press that follows the toggle.
    test("a toggle carries two computed links and the key in the one click", function()
        local i = Bind({
            ["$s1"] = { mode = MODES.EXPR, expr = "[$s3]" },
            ["$s3"] = { mode = MODES.EXPR, expr = "[$s2]" },
            ["$s2"] = { mode = MODES.MANUAL, resetValue = false },
        });

        check(not Fires(), "the key fired before anything went on");

        i.driverHandle:RunAttribute("ToggleSwitch", "$s2");
        check(Fires(), "the key did not fire on the press that followed the toggle");
        check(i.env.States["$s3"] == true, "the near link was not worked out by that press");

        i.driverHandle:RunAttribute("ToggleSwitch", "$s2");
        check(not Fires(), "the key still fired after the toggle went back off");
    end);

    ---------------------------------------------------------------------------
    -- Back through the restricted side
    ---------------------------------------------------------------------------

    -- **The echo of a reset must not become a memory** (§4-9 of
    -- `redesigning-custom-states.md`). The insecure side writes a switch's starting value and
    -- pushes it in; the restricted side reports that same value straight back out (`SetSwitch` ->
    -- `OnSwitchChanged`), and taking the report as a person having moved the switch overwrites the
    -- memory **on one login** -- which is the value the character goes back to when it leaves a
    -- layer that forces the answer.
    --
    -- **The whole round trip, not the two halves.** `switch_spec.lua` pins each end separately: that
    -- a reset writes `value`, and that `SetSwitchValue` writes the memory. Neither can see them meet,
    -- and meeting is the fault: the report arrives a frame later through the mirror
    -- (`SwitchesChangedCallback`), so it is `drainTimers` that puts the two in the same room.
    test("a reset that comes back through the restricted side is not remembered", function()
        -- **No starting value yet**, so the switch is a plain "leave it where I left it" one and
        -- turning it on is a memory rather than something a reset will argue with.
        local i = Bind({ ["$s1"] = { mode = MODES.MANUAL } });

        DebindPrivate.SetSwitchValue("$s1", true);
        check(DebindPrivate.db.charState.switches["$s1"] == true, "setup: nothing was remembered");

        -- **Giving it a starting value is what moves the answer**, and a moved answer is the only
        -- thing that makes the next rebuild re-apply one (`ApplySwitchResets` compares
        -- `layerKey|mode|resetValue`). Rebuilding with the same answer would push nothing in and
        -- there would be no echo to mistake for a person.
        DebindPrivate.Switches["$s1"].resetValue = false;
        Rebuild();

        check(i.env.States["$s1"] == false, "the reset did not reach the restricted side");
        frames.drainTimers();

        check(DebindPrivate.db.charState.switches["$s1"] == true,
            "the reset's echo was taken for a person and ate the memory");
    end);

    ---------------------------------------------------------------------------
    -- A click on the switch frame
    ---------------------------------------------------------------------------

    --- **What `/click DebindSwitch $s1-on` runs**: the frame's own `_onclick` with the button the line
    --- carries, then the attribute write it makes, into `SetSwitch`. The game cannot be asked this
    --- from the kit: a `Click()` from addon code is tainted, and `CallRestrictedClosure` refuses to
    --- run a body for it, while a macro's `/click` is secure.
    ---
    --- The frame is not among the ones the interpreter replays, so its own setup (the reference to
    --- the driver) is replayed here.
    local function ClickSwitchFrame(i, button)
        local frame = DebindPrivate.SwitchesUpdaterFrame;
        if (not i.replayFrames[frame]) then
            i.replayFrames[frame] = true;
            local own = {};
            for _, entry in ipairs(frames.all()) do
                if (entry.frame == frame) then
                    own[#own + 1] = entry;
                end
            end
            i:replay(own);
        end
        i:run(frame:GetAttribute("_onclick"), restricted.handleFor(i, frame), "self,button,down",
            i:envFor(frame), button, false);
    end

    test("a click on the switch frame sets the switch its button names", function()
        local i = Bind({ ["$s1"] = { mode = MODES.MANUAL, resetValue = false } });
        check(i.env.States["$s1"] == false, "setup: the switch is not registered off");

        ClickSwitchFrame(i, "$s1-on");
        check(i.env.States["$s1"] == true, "-on left it " .. tostring(i.env.States["$s1"]));

        ClickSwitchFrame(i, "$s1-off");
        check(i.env.States["$s1"] == false, "-off left it " .. tostring(i.env.States["$s1"]));

        ClickSwitchFrame(i, "$s1");
        check(i.env.States["$s1"] == true, "no mode did not toggle: " .. tostring(i.env.States["$s1"]));
    end);

    -- **A number is shorthand for `$state<n>`** (`_onclick`), the one door a bare number comes
    -- through.
    test("a click on the switch frame reads a number as $state<n>", function()
        local i = Bind({ ["$state1"] = { mode = MODES.MANUAL, resetValue = false } }, "F1", {
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { ["$state1"] = true } },
        });
        ClickSwitchFrame(i, "1-on");
        check(i.env.States["$state1"] == true, "1-on left $state1 " .. tostring(i.env.States["$state1"]));
    end);

    return T;
end
