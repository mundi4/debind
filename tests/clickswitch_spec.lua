-- A computed switch is worked out at the press, and the beat is left to the ones that announce a
-- change (`devdocs/dropping-the-game-fallback.md` §3). No WoW client needed.

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

    local function Bind(switches, key)
        _G.UnitGUID = function() return GUID; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {
                { type = Constants.SPELL, value = 585, key = key or "F1", seq = 1,
                    conditions = { ["$s1"] = true } },
            }, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches,
        };
        DebindPrivate.InitDB();

        -- The rebuild's own pass reads the world, so a case that failed with combat on must not
        -- hand that to the next one.
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

    -- **`@hover` inside a switch is the frame the press judged, not the alias the poll keeps.** The
    -- cursor stays on the frame while its unit changes, and no beat runs. The interpreter answers a
    -- target selector as a match whoever it names, so what is asked is the text the press parsed.
    test("an @hover inside a switch is composed from the frame at the press", function()
        shim.world.units = {
            party1 = { id = "p1", reaction = "help" },
            party2 = { id = "p2", reaction = "help" },
        };
        Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[@hover]" } });

        unitFrame:SetAttribute("unit", "party1");
        interp:hoverEnter(unitFrame);
        local before = interp:parseCount("[@party1]");
        Fires();
        check(interp:parseCount("[@party1]") > before, "the press did not compose [@hover] from the frame");

        unitFrame:SetAttribute("unit", "party2");
        before = interp:parseCount("[@party2]");
        Fires();
        check(interp:parseCount("[@party2]") > before,
            "the frame's unit changed under the cursor and the press composed the old one");

        interp:clearHoverSlot();
        shim.world.units = {};
    end);

    ---------------------------------------------------------------------------
    -- The beat
    ---------------------------------------------------------------------------

    -- **A switch that announces nothing is not worked out on the beat at all.** A parse count is the
    -- only thing that can see it, since the press answers right either way.
    test("the beat leaves a switch with no message alone", function()
        local i = Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[combat]" } });

        local before = i:parseCount("[combat]");
        i.state.combat = true;
        i:pollStates();
        i.state.combat = false;
        i:pollStates();
        check(i:parseCount("[combat]") == before,
            "the beat parsed a switch nobody is told about: "
            .. (i:parseCount("[combat]") - before) .. " times");
        i:resetState();
    end);

    -- The other side, so the case above cannot pass on a beat that parses nothing at all.
    test("a switch with a message is worked out on the beat", function()
        local i = Bind({ ["$s1"] = { mode = MODES.EXPR, expr = "[combat]", displayMessage = true } });

        i.state.combat = true;
        i:pollStates();
        check(i.env.States["$s1"] == true, "the beat did not work out a switch that announces");
        i:resetState();
    end);

    return T;
end
