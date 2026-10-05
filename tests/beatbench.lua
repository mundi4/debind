-- What one beat of the tail-key loop costs in the client, estimated headless.
-- `lua5.1 tests/run.lua --bench-beat`
--
-- **Counted, not timed** (`restricted.lua`, "Metering"). The interpreter counts what the bodies do
-- and this file multiplies each count by what the same thing was measured to cost in the restricted
-- environment (`trimming-the-tail-key-beat.md` 7-1). The absolute figure misses what the model has
-- no line for -- garbage collection, string length, the cache -- so it is for holding two designs
-- side by side under one model (`implementing-the-trimmed-tail-key-beat.md` P0-3). One generated
-- body measured in the game with `Probe_BeatCost.lua` is what says how far the model is off.
--
-- A line marked `*` was not measured and carries a guess; the report says how much of the total
-- rests on guesses.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    --- µs per event in the restricted environment, from 7-1 (secure column). `false` marks a guess.
    local COST = {
        ["global read"] = { 0.154, true },
        ["global write"] = { 0.497, true },
        ["field read"] = { 0.074, true },
        ["field write"] = { 0.443, true },
        ["handle:GetAttribute"] = { 1.18, true },
        ["handle:SetAttribute"] = { 1.29, true },
        -- An empty `_onattributechanged` behind a `SetAttribute` measured 4.43; less the 1.24 of a
        -- `SetAttribute` with no handler behind it.
        ["handler entry"] = { 3.19, true },
        ["handle:RunAttribute"] = { 3.09, true },
        -- `[known:1]` 0.188 and `[swimming]` 0.216 for one word; six words in a group 0.373.
        ["parse"] = { 0.19, true },
        ["parse word"] = { 0.035, true },
        ["parse word flyable"] = { 4.95, true },
        ["parse word advflyable"] = { 23.77, true },
        -- The parse is priced by the two lines above; the call itself adds nothing on top.
        ["call SecureCmdOptionParse"] = { 0, true },
        ["call PlayerInCombat"] = { 0.912, true },
        ["call IsMounted"] = { 0.182, true },
        ["call IsStealthed"] = { 0.18, false },
        ["call IsIndoors"] = { 0.18, false },
        ["call IsFlying"] = { 0.18, false },
        ["call IsFlyableArea"] = { 5.15, true },
        ["call IsAdvancedFlyableArea"] = { 23.98, true },
        ["call GetShapeshiftForm"] = { 0.143, true },
        ["call GetBonusBarOffset"] = { 0.53, true },
        ["call HasExtraActionBar"] = { 0.523, true },
        ["call HasVehicleActionBar"] = { 0.55, true },
        ["call HasOverrideActionBar"] = { 0.55, true },
        ["call HasTempShapeshiftActionBar"] = { 0.55, true },
        ["call UnitExists"] = { 0.290, true },
        ["call UnitIsDead"] = { 0.284, true },
        ["call UnitIsGhost"] = { 0.284, false },
        ["call PlayerCanAssist"] = { 0.844, true },
        ["call PlayerCanAttack"] = { 0.844, false },
        ["call UnitPlayerOrPetInParty"] = { 0.24, true },
        ["call UnitPlayerOrPetInRaid"] = { 0.24, true },
        ["call FindSpellBookSlotBySpellID"] = { 0.563, true },
        ["call newtable"] = { 0.71, true },
        ["call wipe"] = { 0.52, true },
        -- Measured with three fragments; a computed switch's text has about that many.
        ["call table.concat"] = { 0.54, true },
        ["call BENCHLEN"] = { 0.074, false },
    };
    --- What an unpriced call is guessed at.
    local UNPRICED_CALL = 0.3;

    --- **The manager's own work per tick, which no body does and so nothing above counts**: the
    --- insecure side of Blizzard's state driver, per tick, for whatever carries the beat (7-1, J).
    --- Which one the rebuild registered is read off the recording.
    local MANAGER_TICK = { unitWatch = 1.94, attributeDriver = 0.37 };
    local function managerTick()
        local cost = 0;
        for _, entry in ipairs(frames.all()) do
            if (entry.kind == "RegisterUnitWatch") then
                cost = MANAGER_TICK.unitWatch;
            elseif (entry.kind == "UnregisterUnitWatch") then
                cost = 0;
            elseif (entry.kind == "RegisterAttributeDriver" and entry.name == DebindPrivate.JUDGE_BEAT_ATTRIBUTE) then
                cost = MANAGER_TICK.attributeDriver;
            end
        end
        return cost;
    end

    ---------------------------------------------------------------------------
    -- What one VM instruction is worth: "a mask test on locals" measured 0.026 µs
    ---------------------------------------------------------------------------

    local function instructionCost(interp)
        local empty = interp:meterBody("local c, x = 2 for i = 1, 1000 do end");
        local masked = interp:meterBody("local c, x = 2 for i = 1, 1000 do x = (2 % (c + c)) >= c end");
        local perTest = ((masked["vm instruction"] or 0) - (empty["vm instruction"] or 0)) / 1000;
        assert(perTest > 0, "the calibration body counted no instructions");
        return 0.026 / perTest, perTest;
    end

    ---------------------------------------------------------------------------
    -- A profile of tail keys
    ---------------------------------------------------------------------------

    local GUID = "Player-1-TESTGUID";
    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    --- `keys` keys, each a spell under one or two states with the game's command under it, which
    --- is what makes a key a tail key. The states rotate so the columns are shared the way a real
    --- profile shares them.
    local SHAPES = {
        { combat = true },
        { mounted = true },
        { combat = true, stealth = true },
        { flying = true },
        { indoors = true },
        { combat = false, mounted = true },
    };
    local function profile(keys)
        local actions = {};
        for i = 1, keys do
            local key = "CTRL-F" .. i;
            actions[#actions + 1] = action({ value = 585, key = key, conditions = SHAPES[(i - 1) % #SHAPES + 1] });
            actions[#actions + 1] = action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = key });
        end
        return actions;
    end

    --- **One interpreter for every profile**, made with the first rebuild and handed only what each
    --- later rebuild added. A new one replays the whole recording, earlier profiles' rebuilds with it.
    local interp;
    local function bind(actions, switches)
        local defined = { ["$w"] = { mode = Constants.SWITCH_MODES.MANUAL } };
        for name, definition in pairs(switches or {}) do
            defined[name] = definition;
        end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = { account = { GENERAL = { [0] = defined } } },
        };
        DebindPrivate.InitDB();
        local mark = frames.mark();
        assert(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world, { meter = true });
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
        return interp;
    end

    ---------------------------------------------------------------------------
    -- Pricing
    ---------------------------------------------------------------------------

    local function price(counts, perInstruction)
        local total, guessed, lines = 0, 0, {};
        for what, n in pairs(counts) do
            local cost, measured;
            if (what == "vm instruction") then
                cost, measured = perInstruction, true;
            elseif (COST[what]) then
                cost, measured = COST[what][1], COST[what][2];
            elseif (what:sub(1, 5) == "call ") then
                cost, measured = UNPRICED_CALL, false;
            else
                cost, measured = 0, false;
            end
            local us = n * cost;
            total = total + us;
            if (not measured) then
                guessed = guessed + us;
            end
            lines[#lines + 1] = { what = what, n = n, us = us, measured = measured };
        end
        table.sort(lines, function(a, b) return a.us > b.us; end);
        return total, guessed, lines;
    end

    --- Runs `beats` beats, the world moving at the given beats, and prices the average beat.
    local function scenario(beats, moves)
        interp:meterStart();
        for b = 1, beats do
            local move = moves[b];
            if (move) then
                move(interp.state);
            end
            interp:beat();
        end
        return interp:meterStop();
    end

    --- `unit` is what one of `n` priced events is called in the report. `outside` is per event and
    --- not counted by the meter (the manager's tick).
    local function report(title, counts, n, perInstruction, unit, outside)
        local total, guessed, lines = price(counts, perInstruction);
        outside = outside or 0;
        print(string.format("\n%s: %.2f us a %s (%.0f%% of it on guessed prices)", title, total / n + outside,
            unit, total > 0 and 100 * guessed / total or 0));
        if (outside > 0) then
            print(string.format("  %-34s %9s       %8.2f us", "manager tick (insecure)", "", outside));
        end
        for i = 1, math.min(#lines, 14) do
            local l = lines[i];
            print(string.format("  %-34s %9.1f a %s %8.2f us%s", l.what, l.n / n, unit, l.us / n,
                l.measured and "" or " *"));
        end
    end

    local QUIET = 200;
    local MOVING = 200;
    local function movingWorld()
        local moves = {};
        for b = 1, MOVING do
            if (b % 20 == 0) then
                moves[b] = function(state) state.combat = not state.combat; end;
            elseif (b % 35 == 0) then
                moves[b] = function(state) state.mounted = not state.mounted; end;
            end
        end
        return moves;
    end

    for _, keys in ipairs({ 4, 12, 30 }) do
        bind(profile(keys));
        local perInstruction, perTest = instructionCost(interp);
        if (keys == 4) then
            print(string.format("one VM instruction priced at %.4f us (a mask test is %.1f instructions)",
                perInstruction, perTest));
        end

        -- The loop has to be judging: a combat beat takes the first key, a peaceful one gives it back.
        interp.state.combat = true;
        interp:beat();
        assert((frames.overrides["CTRL-F1"] or {}).buttonName, "a combat beat did not take the first key");
        interp.state.combat = false;
        interp:beat();
        assert((frames.overrides["CTRL-F1"] or {}).command == "TOGGLEWORLDMAP",
            "a peaceful beat did not give the first key back");

        local tick = managerTick();
        report(string.format("%d tail keys, no state changed", keys), scenario(QUIET, {}), QUIET, perInstruction,
            "beat", tick);
        report(string.format("%d tail keys, combat and mounted flipping", keys), scenario(MOVING, movingWorld()),
            MOVING, perInstruction, "beat", tick);
    end

    ---------------------------------------------------------------------------
    -- The loop by the profile's shape
    ---------------------------------------------------------------------------

    --- **Synthetic shapes and not a real profile** (2026-10-05, owner). `shared` is the rotation
    --- above, few bundles over few columns. `distinct` gives every key a bundle of its own. `units`
    --- reads units beside states, and `flyable` puts `flyable` on every key.
    local GATE_SHAPES = {
        shared = function(i) return SHAPES[(i - 1) % #SHAPES + 1]; end,
        distinct = function(i)
            return { forms = 2 ^ (i % 11), combat = i % 2 == 0, bonusbars = 2 ^ (i % 3) };
        end,
        units = function(i)
            local reactions = { Constants.REACTION_HELP, Constants.REACTION_HARM };
            return { combat = i % 2 == 0, units = {
                target = { reaction = reactions[i % 2 + 1], dead = i % 3 == 0 },
                focus = i % 4 == 0 and { dead = false } or nil,
            } };
        end,
        flyable = function(i) return { flyable = true, mounted = i % 2 == 0, combat = i % 3 == 0 }; end,
    };

    local function gateProfile(shape, keys)
        local actions = {};
        for i = 1, keys do
            local key = "CTRL-F" .. i;
            actions[#actions + 1] = action({ value = 585, key = key, conditions = GATE_SHAPES[shape](i) });
            actions[#actions + 1] = action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = key });
        end
        return actions;
    end

    --- A beat with no state changed, and a beat where `combat` and `mounted` flip every 4th one, each
    --- priced.
    local function gateBeat(perInstruction)
        local still = price(scenario(QUIET, {}), perInstruction) / QUIET;
        local moves = {};
        for b = 1, MOVING do
            if (b % 4 == 0) then
                moves[b] = function(state) state.combat = not state.combat; state.mounted = not state.mounted; end;
            end
        end
        local flipping = price(scenario(MOVING, moves), perInstruction) / MOVING;
        return still, flipping;
    end

    print("\nBy shape, 12 keys, a beat in us, no state changed | combat and mounted flipped every 4th beat,"
        .. " by how many boolean columns one detecting parse takes (P3-7):");
    for _, shape in ipairs({ "shared", "distinct", "units", "flyable" }) do
        local row = {};
        for _, detect in ipairs({ 0, 2, 3, 4, 5 }) do
            DebindPrivate.JudgeDetectMax = detect;
            shim.world.units = { target = { id = "enemy", reaction = "harm" } };
            bind(gateProfile(shape, 12));
            local still, flipping = gateBeat(instructionCost(interp));
            row[#row + 1] = string.format("%d: %5.2f | %5.2f", detect, still, flipping);
        end
        print(string.format("  %-9s %s", shape, table.concat(row, "   ")));
    end
    DebindPrivate.JudgeDetectMax = nil;
    shim.world.units = {};

    --- **Computed switches whose text is composed** (P4): one reading a switch set by hand, one an
    --- alias, one another computed switch, beside one with nothing to compose. Flipping `combat`
    --- flips `$a`, which `$c` reads.
    local COMPUTED = {
        ["$a"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" },
        ["$h"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$w,mounted]" },
        ["$u"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@custom1,help]" },
        ["$c"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$a,stealth]" },
    };
    local COMPUTED_SHAPES = {
        { ["$h"] = true },
        { ["$u"] = true, combat = true },
        { ["$c"] = true },
        { ["$a"] = false, mounted = true },
    };
    local actions = {};
    for i = 1, 12 do
        local key = "CTRL-F" .. i;
        actions[#actions + 1] = action({ value = 585, key = key,
            conditions = COMPUTED_SHAPES[(i - 1) % #COMPUTED_SHAPES + 1] });
        actions[#actions + 1] = action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = key });
    end
    shim.world.units = { party3 = { id = "friend", reaction = "help" } };
    bind(actions, COMPUTED);
    interp.driverHandle:RunAttribute("SetUnit", "custom1", "party3");
    do
        local WAKES_ALIAS = 100;
        local perInstruction = instructionCost(interp);
        local tick = managerTick();
        report("computed switches, 12 tail keys, no state changed", scenario(QUIET, {}), QUIET, perInstruction,
            "beat", tick);
        local moves = {};
        for b = 1, MOVING do
            if (b % 4 == 0) then
                moves[b] = function(state) state.combat = not state.combat; state.mounted = not state.mounted; end;
            end
        end
        report("computed switches, 12 tail keys, combat and mounted flipped every 4th beat",
            scenario(MOVING, moves), MOVING, perInstruction, "beat", tick);
        interp:meterStart();
        for w = 1, WAKES_ALIAS do
            interp.driverHandle:RunAttribute("SetUnit", "custom1", w % 2 == 1 and "party3" or "party4");
        end
        report("custom1 moved, SetUnit with what it wakes", interp:meterStop(), WAKES_ALIAS, perInstruction, "wake");
    end
    shim.world.units = {};

    --- **A wake of ours**: a switch set by hand, which only `SetSwitch` moves. What it costs on top
    --- of `SetSwitch` itself is the wake.
    local WAKES = 100;
    bind({
        action({ value = 585, key = "CTRL-F1", conditions = { ["$w"] = true } }),
        action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "CTRL-F1" }),
    });
    local perInstruction = instructionCost(interp);
    interp.driverHandle:RunAttribute("SetSwitch", "$w", true);
    assert((frames.overrides["CTRL-F1"] or {}).buttonName, "setting the switch did not take the key");
    interp.driverHandle:RunAttribute("SetSwitch", "$w", false);
    assert((frames.overrides["CTRL-F1"] or {}).command == "TOGGLEWORLDMAP", "clearing the switch did not give it back");
    interp:meterStart();
    for w = 1, WAKES do
        interp.driverHandle:RunAttribute("SetSwitch", "$w", w % 2 == 1);
    end
    report("a switch set by hand, SetSwitch with its wake", interp:meterStop(), WAKES, perInstruction, "wake");
end
