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
            shared = { GENERAL = actions or {
                { type = Constants.SPELL, value = 585, key = key or "F1", seq = 1,
                    conditions = { ["$s1"] = true } },
            }, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches,
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

    -- **The press reports what it found.** The tab reads the value the report writes, and with no
    -- beat for this switch the press is the only thing left to write it.
    test("the press reports a switch it moved", function()
        Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[combat]" } });
        frames.drainTimers();
        check(DebindPrivate.Switches["$s1"].value ~= true, "setup: the switch already reads on");

        interp.state.combat = true;
        Fires();
        frames.drainTimers();
        check(DebindPrivate.Switches["$s1"].value == true,
            "the press moved the switch and the definition still reads "
            .. tostring(DebindPrivate.Switches["$s1"].value));
        interp:resetState();
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
        check(DebindPrivate.db.char.switches["$s1"] == true, "setup: nothing was remembered");

        -- **Giving it a starting value is what moves the answer**, and a moved answer is the only
        -- thing that makes the next rebuild re-apply one (`ApplySwitchResets` compares
        -- `layerKey|mode|resetValue`). Rebuilding with the same answer would push nothing in and
        -- there would be no echo to mistake for a person.
        DebindPrivate.Switches["$s1"].resetValue = false;
        Rebuild();

        check(i.env.States["$s1"] == false, "the reset did not reach the restricted side");
        frames.drainTimers();

        check(DebindPrivate.db.char.switches["$s1"] == true,
            "the reset's echo was taken for a person and ate the memory");
    end);

    return T;
end
