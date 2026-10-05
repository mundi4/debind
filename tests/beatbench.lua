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
        ["call BENCHLEN"] = { 0.074, false },
    };
    --- What an unpriced call is guessed at.
    local UNPRICED_CALL = 0.3;

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
    local function bind(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = {},
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
    local function scenario(interp, beats, moves)
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

    local function report(title, counts, beats, perInstruction)
        local total, guessed, lines = price(counts, perInstruction);
        print(string.format("\n%s: %.2f us a beat (%.0f%% of it on guessed prices)", title, total / beats,
            total > 0 and 100 * guessed / total or 0));
        for i = 1, math.min(#lines, 14) do
            local l = lines[i];
            print(string.format("  %-34s %9.1f a beat %8.2f us%s", l.what, l.n / beats, l.us / beats,
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

        report(string.format("%d tail keys, quiet", keys), scenario(interp, QUIET, {}), QUIET, perInstruction);
        report(string.format("%d tail keys, the world moving", keys), scenario(interp, MOVING, movingWorld()),
            MOVING, perInstruction);
    end
end
