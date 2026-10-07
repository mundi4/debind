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
        -- 7-1's P, 2026-10-06, each write changing the key: `SetBindingClick` 1.477, `SetBinding`
        -- 1.101. A clear that changes the key was timed only alternating with a click (1.188 a call),
        -- so it is twice that less the click. Writing what is already there cost the same each time
        -- (1.469, 1.085, a clear over nothing 0.882): the client skips nothing.
        ["handle:SetBindingClick"] = { 1.477, true },
        ["handle:SetBinding"] = { 1.101, true },
        ["handle:ClearBinding"] = { 0.899, true },
        -- A parse, each group it judges and each word in one, `@unit` counted as a word: 7-1's N,
        -- texts of 4 to 256 groups lying on this within 5%.
        ["parse"] = { 0.146, true },
        ["parse group"] = { 0.032, true },
        ["parse word"] = { 0.057, true },
        -- `[flyable]` 5.15 and `[advflyable]` 23.97, less the one-word parse above.
        ["parse word flyable"] = { 4.915, true },
        ["parse word advflyable"] = { 23.735, true },
        -- 7-1, 2026-10-06: `[form:1]` 1.217, five values 1.263, ten 1.283.
        ["parse word alternative"] = { 0.007, true },
        -- A clause with a value, over a bare group: 13 false clauses 1.425 against 13 groups 1.405.
        ["parse clause value"] = { 0.0015, true },
        -- **`form` over an ordinary word, by the class** (7-1): `[form:1]` 1.217 on a druid, 0.210 on
        -- a warlock. Set per row (`FORM_PRICES`).
        ["parse word form"] = { 0, true },
        -- A unit word asked of another unit that is there: one hostile target, insecure side, once.
        ["parse word on another unit"] = { 0.135, false },
        -- 7-1's P: `tonumber(s)` 0.204, `s + 0` 0.043 on one digit and 0.046 on four.
        ["call tonumber"] = { 0.204, true },
        ["call BENCHCOERCE"] = { 0.045, true },
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
    --- insecure side of Blizzard's state driver, per tick, for whatever carries the beat (7-1, J),
    --- its write to the driver included (`restricted.lua` does not tally that one). `state-visibility`
    --- is its tick on a frame with no handler, which holds the show and the write. `"a"` is its tick
    --- (0.37, the parse and the compare with no write) and a plain frame's `SetAttribute` (0.30).
    local MANAGER_TICK = { attribute = 0.37 + 0.30, visibility = 0.489 };
    local function managerTick()
        local drivers = frames.attributeDrivers[DebindPrivate.BindingDriver] or {};
        if (drivers["state-visibility"]) then
            return MANAGER_TICK.visibility;
        elseif (drivers[DebindPrivate.JUDGE_BEAT_ATTRIBUTE]) then
            return MANAGER_TICK.attribute;
        end
        return 0;
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
    -- Registered before the first rebuild, whose recording the one interpreter is made from, for
    -- the large shape's enter wake.
    local groupFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(groupFrame, "group");
    groupFrame:SetAttribute("unit", "party1");
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
    --- `bare` leaves the command off: the key then ends in nothing of its own, and with
    --- `giveBackWhenNoActionRuns` on it is judged all the same (`giving-keys-back-when-no-action-runs.md`).
    local function profile(keys, bare)
        local actions = {};
        for i = 1, keys do
            local key = "CTRL-F" .. i;
            actions[#actions + 1] = action({ value = 585, key = key, conditions = SHAPES[(i - 1) % #SHAPES + 1] });
            if (not bare) then
                actions[#actions + 1] = action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = key });
            end
        end
        return actions;
    end

    --- **One interpreter for every profile**, made with the first rebuild and handed only what each
    --- later rebuild added. A new one replays the whole recording, earlier profiles' rebuilds with it.
    local interp;
    --- The rebuild alone, the last `bind` took, in ms.
    local lastRebuild;
    local function bind(actions, switches, options)
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
            options = options,
        };
        DebindPrivate.InitDB();
        local mark = frames.mark();
        local started = os.clock();
        assert(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        lastRebuild = (os.clock() - started) * 1000;
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

    --- **What a beat costs past getting into the body**: the two writes of the beat's attribute and
    --- the two handler entries behind them are what the body cannot shorten (the report's 9.33).
    local OUTSIDE_THE_BODY = { ["handler entry"] = true, ["handle:SetAttribute"] = true };
    local function BodyShare(lines)
        local us = 0;
        for _, l in ipairs(lines) do
            if (not OUTSIDE_THE_BODY[l.what]) then
                us = us + l.us;
            end
        end
        return us;
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
        if (unit == "beat") then
            print(string.format("  %-34s %9s       %8.2f us", "in the body", "", BodyShare(lines) / n));
        end
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

    --- **The same keys with nothing under the spell**, which `giveBackWhenNoActionRuns` alone puts
    --- in the loop: the end of the key is the one giveback every key shares.
    for _, keys in ipairs({ 4, 12, 30 }) do
        bind(profile(keys, true));
        local perInstruction = instructionCost(interp);
        interp.state.combat = true;
        interp:beat();
        assert((frames.overrides["CTRL-F1"] or {}).buttonName, "a combat beat did not take the first bare key");
        interp.state.combat = false;
        interp:beat();
        assert(interp.bindings["CTRL-F1"] == nil, "a peaceful beat did not let the first bare key go");

        local tick = managerTick();
        report(string.format("%d keys with no tail, no state changed", keys), scenario(QUIET, {}), QUIET,
            perInstruction, "beat", tick);
        report(string.format("%d keys with no tail, combat and mounted flipping", keys),
            scenario(MOVING, movingWorld()), MOVING, perInstruction, "beat", tick);
    end

    --- **What judging every key adds to a rebuild**: the bare keys above, with the option on and off.
    --- Off, no key of theirs is judged. The median of a few, the first dropped as the warm-up.
    local REBUILDS = 7;
    local function rebuildMs(actions, options)
        local runs = {};
        for r = 1, REBUILDS do
            bind(actions, nil, options);
            runs[r] = lastRebuild;
        end
        table.remove(runs, 1);
        table.sort(runs);
        return runs[math.floor(#runs / 2) + 1];
    end
    print("\nThe rebuild, keys with no tail, headless ms: the option on | off");
    for _, keys in ipairs({ 12, 30, 60, 120 }) do
        local actions = profile(keys, true);
        local on = rebuildMs(actions);
        local items = 0;
        for _ in pairs(DebindPrivate.JudgmentItems) do
            items = items + 1;
        end
        local off = rebuildMs(actions, { giveBackWhenNoActionRuns = false });
        print(string.format("  %3d keys  %7.1f | %7.1f   (%d items on)", keys, on, off, items));
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
        -- Mount keys as they are written: out of combat and where the zone allows flying (R1-c).
        mounts = function(i) return { flyable = true, mounted = i % 2 == 0, combat = false }; end,
        -- Out of a pet battle, or off a replaced bar, beside a state. The two cannot share an action.
        bars = function(i)
            if (i % 2 == 0) then
                return { petbattle = false, combat = true };
            end
            return { specialbar = false, mounted = true };
        end,
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

    --- A beat with no state changed, out of combat and in it, and a beat where `combat` and `mounted`
    --- flip every 4th one, each priced.
    local function gateBeat(perInstruction)
        local still = price(scenario(QUIET, {}), perInstruction) / QUIET;
        interp.state.combat = true;
        interp:beat();
        local stillInCombat = price(scenario(QUIET, {}), perInstruction) / QUIET;
        interp.state.combat = false;
        interp:beat();
        local moves = {};
        for b = 1, MOVING do
            if (b % 4 == 0) then
                moves[b] = function(state) state.combat = not state.combat; state.mounted = not state.mounted; end;
            end
        end
        local flipping = price(scenario(MOVING, moves), perInstruction) / MOVING;
        return still, stillInCombat, flipping;
    end

    print("\nBy shape, 12 keys, a beat in us, no state changed (out of combat / in it) | combat and mounted flipped"
        .. " every 4th beat:");
    for _, shape in ipairs({ "shared", "distinct", "units", "flyable", "mounts", "bars" }) do
        shim.world.units = { target = { id = "enemy", reaction = "harm" } };
        bind(gateProfile(shape, 12));
        local still, stillInCombat, flipping = gateBeat(instructionCost(interp));
        print(string.format("  %-9s %5.2f / %5.2f | %5.2f", shape, still, stillInCombat, flipping));
    end
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

    ---------------------------------------------------------------------------
    -- The large shape (`implementing-the-cuts-inside-the-beat-handler.md` Q0)
    ---------------------------------------------------------------------------

    --- **Every state column there is but the two flying ones, then units, `known` and computed
    --- switches**: there are only 13 state columns, so a large profile is large in the rest. Three
    --- of the units are there, three of the `known` carry an id the book is asked for as well.
    --- `flyable` and `advflyable` stay out because they cost 5 and 24 and would drown the rest.
    local LARGE_SWITCHES = {
        ["$x"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[indoors,nocombat]" },
        ["$y"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@focus,help,nodead]" },
    };
    local LARGE_PIECES = {
        { combat = true }, { stealth = true }, { mounted = true }, { indoors = true }, { flying = true },
        { extrabar = true }, { specialbar = true }, { groups = Constants.GROUP_RAID }, { forms = 2 ^ 1 },
        { bonusbars = 2 ^ 5 },
        { units = { target = { reaction = Constants.REACTION_HARM, dead = false } } },
        { units = { focus = { reaction = Constants.REACTION_HELP } } },
        { units = { pet = { dead = false } } },
        { units = { mouseover = { reaction = Constants.REACTION_HELP } } },
        { units = { custom1 = { reaction = Constants.REACTION_HELP } } },
        { units = { unitframe = { reaction = Constants.REACTION_HELP } } },
        { known = 90001 }, { known = 90002 }, { known = 90003 },
        { known = "Bench Spell A" }, { known = "Bench Spell B" }, { known = "Bench Spell C" },
        { ["$x"] = true }, { ["$y"] = true },
    };

    --- One key per piece, each reading its piece and the one half the list away, over the game's
    --- command. The first `leading` keys open with `[combat]` alone, which is the knob: every record
    --- under it then carries `nocombat` (`Judgment.Build`).
    local function largeProfile(leading)
        local out, n = {}, #LARGE_PIECES;
        for i = 1, n do
            local key = "CTRL-F" .. i;
            if (i <= leading) then
                out[#out + 1] = action({ value = 585, key = key, conditions = { combat = true } });
            end
            out[#out + 1] = action({ value = 585, key = key, conditions = LARGE_PIECES[i] });
            out[#out + 1] = action({ value = 585, key = key, conditions = LARGE_PIECES[(i + n / 2 - 1) % n + 1] });
            out[#out + 1] = action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = key });
        end
        return out;
    end

    local TARGETS = {
        { id = "enemy", reaction = "harm" },
        { id = "friend2", reaction = "help" },
    };
    local function largeWorld()
        shim.world.units = {
            player = { id = "me", reaction = "help" },
            target = TARGETS[1],
            focus = { id = "friend", reaction = "help" },
            pet = { id = "imp", reaction = "help" },
            party1 = { id = "member", reaction = "help" },
        };
    end

    local LARGE_BEATS = 100;
    print("\nThe large shape, 24 keys over 24 columns, a beat in us with the body's share after the slash."
        .. "\nBy how many keys open with [combat] alone, and whether in combat:");
    print(string.format("  %-16s %-14s %-14s %-14s %-14s %-12s %s", "", "quiet", "a state moved",
        "the form moved", "target moved", "enter wake",
        "the body a second at 5 / 20 / 144 beats with 3 of them moved"));
    --- **What `form` costs over an ordinary word, by the class** (7-1): about 0.06 a token on a
    --- warlock (2026-10-05), which has no forms, and 1.07 on a druid (2026-10-06), where `[form:1]`
    --- parsed in 1.217. No other class with forms was measured. A profile with a forms column is a
    --- class that has them, so the second row is the one that stands for this shape.
    --- `GetShapeshiftForm()` as well, by the same runs: 0.143 on the warlock, 1.137 on the druid.
    local FORM_PRICES = {
        { "class without forms, form 0.06", 0, 0.143 },
        { "forms column, class with forms (druid), form 1.07", 1.217 - 0.146 - 0.032 - 0.057, 1.137 },
    };
    local function LargeRow(leading, combat)
        largeWorld();
        bind(largeProfile(leading), LARGE_SWITCHES);
        local columns = {};
        for _, item in pairs(DebindPrivate.JudgmentItems) do
            for _, column in ipairs(item.columns) do
                columns[column.key] = true;
            end
        end
        local count = 0;
        for _ in pairs(columns) do
            count = count + 1;
        end
        assert(count == #LARGE_PIECES, "the large shape reads " .. count .. " columns");
        local perInstruction = instructionCost(interp);
        local tick = managerTick();
        interp.state.combat = combat;
        interp:beat();

        local function priced(counts, n)
            local total, _, lines = price(counts, perInstruction);
            return total / n + tick, BodyShare(lines) / n;
        end

        local quiet, quietBody = priced(scenario(LARGE_BEATS, {}), LARGE_BEATS);

        local stateMoves = {};
        for b = 1, LARGE_BEATS do
            stateMoves[b] = function(state) state.mounted = not state.mounted; end;
        end
        local moved, movedBody = priced(scenario(LARGE_BEATS, stateMoves), LARGE_BEATS);

        local formMoves = {};
        for b = 1, LARGE_BEATS do
            formMoves[b] = function(state) state.form = state.form == 0 and 2 or 0; end;
        end
        local formMoved, formMovedBody = priced(scenario(LARGE_BEATS, formMoves), LARGE_BEATS);
        interp.state.form = 3;
        interp:beat();
        local _, inFormBody = priced(scenario(LARGE_BEATS, {}), LARGE_BEATS);
        print(string.format("    quiet in form 3, the body: %5.2f", inFormBody));
        interp.state.form = 0;
        interp:beat();

        local targetMoves = {};
        for b = 1, LARGE_BEATS do
            targetMoves[b] = function() shim.world.units.target = TARGETS[b % 2 + 1]; end;
        end
        local retarget, retargetBody = priced(scenario(LARGE_BEATS, targetMoves), LARGE_BEATS);

        -- A friend and an enemy under the cursor in turn: the mouseover column moves on every beat.
        local mouseMoves = {};
        for b = 1, LARGE_BEATS do
            mouseMoves[b] = function() shim.world.units.mouseover = TARGETS[b % 2 + 1]; end;
        end
        local _, mouseBody = priced(scenario(LARGE_BEATS, mouseMoves), LARGE_BEATS);
        shim.world.units.mouseover = nil;
        interp:beat();

        -- Entered and left in turn, only the enter metered.
        local enterCounts = {};
        for _ = 1, LARGE_BEATS do
            interp:meterStart();
            interp:hoverEnter(groupFrame);
            for what, n in pairs(interp:meterStop()) do
                enterCounts[what] = (enterCounts[what] or 0) + n;
            end
            interp:hoverLeave(groupFrame);
        end
        local enter = price(enterCounts, perInstruction) / LARGE_BEATS;

        local function second(beats)
            return (beats - 3) * quietBody + 3 * movedBody;
        end
        print(string.format("  %2d lead, %-6s %5.2f / %5.2f  %5.2f / %5.2f  %5.2f / %5.2f  %5.2f / %5.2f  %6.2f"
            .. "       %3.0f / %3.0f / %4.0f",
            leading, combat and "in" or "out", quiet, quietBody, moved, movedBody, formMoved, formMovedBody,
            retarget, retargetBody, enter, second(5), second(20), second(144)));
        -- **A second where units move**, which the line above cannot show: three of its beats move a
        -- state. Three target swaps a second, and the mouseover moving on every beat.
        local function targets(beats)
            return (beats - 3) * quietBody + 3 * retargetBody;
        end
        print(string.format("    the body a second, 3 target swaps: %3.0f / %3.0f / %4.0f;"
            .. " the mouseover on every beat: %3.0f / %3.0f / %4.0f",
            targets(5), targets(20), targets(144), 5 * mouseBody, 20 * mouseBody, 144 * mouseBody));

        -- **A second where combat moves**: every key that opens with `[combat]` reads it, so with
        -- 24 leading every bundle is judged. The rows above judge two bundles a move.
        local combatMoves = {};
        for b = 1, LARGE_BEATS do
            combatMoves[b] = function(state) state.combat = not state.combat; end;
        end
        local _, combatBody = priced(scenario(LARGE_BEATS, combatMoves), LARGE_BEATS);
        interp.state.combat = combat;
        interp:beat();
        print(string.format("    combat moving, the beat's body %5.2f; a second, 3 moves: %3.0f / %3.0f / %4.0f;"
            .. " on every beat: %3.0f / %3.0f / %4.0f", combatBody,
            (5 - 3) * quietBody + 3 * combatBody, (20 - 3) * quietBody + 3 * combatBody,
            (144 - 3) * quietBody + 3 * combatBody, 5 * combatBody, 20 * combatBody, 144 * combatBody));
    end
    for _, formPrice in ipairs(FORM_PRICES) do
        COST["parse word form"][1] = formPrice[2];
        COST["call GetShapeshiftForm"][1] = formPrice[3];
        print("  " .. formPrice[1] .. ":");
        for _, leading in ipairs({ 0, 12, 24 }) do
            for _, combat in ipairs({ false, true }) do
                LargeRow(leading, combat);
            end
        end
    end
    COST["parse word form"][1] = 0;
    COST["call GetShapeshiftForm"][1] = 0.143;

    --- **What the watch's cap decides** (`JudgeWatchRounds`): k of the large shape's watched
    --- columns moved in one beat, the body by the cap. A beat measures the first `cap` columns that
    --- answered one at a time, a round each, and every carried column at the round after. "none" is
    --- every column a round of its own, 0 every column at the first answer. The movers are the
    --- shape's watched states and units a beat can move here, `combat` among them for a fight
    --- starting; `indoors` also moves `$x`, which reads it.
    do
        local function flip(name)
            return function(state) state[name] = not state[name]; end;
        end
        local units = shim.world.units;
        local MOVERS = {
            flip("mounted"), flip("stealth"), flip("indoors"), flip("flying"), flip("combat"),
            function() units.target = (units.target == TARGETS[1]) and TARGETS[2] or TARGETS[1]; end,
            function() units.focus.reaction = (units.focus.reaction == "help") and "harm" or "help"; end,
            function() units.pet.dead = not units.pet.dead; end,
        };
        local was = DebindPrivate.JudgeWatchRounds;
        print(string.format("\nThe large shape, k watched columns moved in one beat, the body in us by the watch's cap (now %s):",
            tostring(was or "none")));
        local head = {};
        for k = 1, #MOVERS do
            head[k] = string.format("%6s", "k=" .. k);
        end
        print("          " .. table.concat(head, " "));
        for _, cap in ipairs({ 0, 1, 2, 3, 6, false }) do
            DebindPrivate.JudgeWatchRounds = cap or nil;
            local row = {};
            for k = 1, #MOVERS do
                largeWorld();
                units = shim.world.units;
                bind(largeProfile(0), LARGE_SWITCHES);
                local perInstruction = instructionCost(interp);
                interp.state.combat = false;
                interp:beat();
                local moves = {};
                for b = 1, LARGE_BEATS do
                    moves[b] = function(state)
                        for j = 1, k do
                            MOVERS[j](state);
                        end
                    end;
                end
                local _, _, lines = price(scenario(LARGE_BEATS, moves), perInstruction);
                row[#row + 1] = string.format("%6.2f", BodyShare(lines) / LARGE_BEATS);
            end
            print(string.format("  cap %-4s %s", tostring(cap or "none"), table.concat(row, " ")));
        end
        DebindPrivate.JudgeWatchRounds = was;
    end
    shim.world.units = {};

    --- **The owner's shape** (R3 of `cutting-the-beat-under-a-zero-period.md`): 30 keys, each 10
    --- actions of 5 conditions over the game's command, the conditions drawn by a fixed sequence from
    --- the large shape's pieces (`mouseover` and the pointed frame left to the knob) and three more
    --- state sides, so the bundles read them mixed. 20 of the keys read `mouseover` on two of their
    --- actions. The knob is how many of those ask `help` on both (`help` alone) rather than `help` on
    --- one and `harm` on the other. The moving row is the cursor on every beat, enemy, nobody,
    --- friend, nobody, with how many bundles a moving beat judges beside it.
    do
        local PIECES = {};
        for _, piece in ipairs(LARGE_PIECES) do
            local units = piece.units;
            if (not (units and (units.mouseover or units.unitframe))) then
                PIECES[#PIECES + 1] = piece;
            end
        end
        for _, piece in ipairs({ { combat = false }, { mounted = false }, { flying = false } }) do
            PIECES[#PIECES + 1] = piece;
        end
        -- Park and Miller's: the product stays under 2^46, exact in a double on any interpreter.
        local seed = 12345;
        local function nextPiece()
            seed = (seed * 16807) % 2147483647;
            return PIECES[seed % #PIECES + 1];
        end
        --- Five pieces, none sharing a field with another, into one conditions table.
        local function conditionsOf(mouseover)
            local out, used = {}, {};
            if (mouseover) then
                out.units = { mouseover = { reaction = mouseover } };
            end
            local count = mouseover and 1 or 0;
            while (count < 5) do
                local piece = nextPiece();
                local field, value = next(piece);
                local unit = field == "units" and next(value);
                local slot = unit and ("unit " .. unit) or field;
                if (not used[slot]) then
                    used[slot] = true;
                    if (unit) then
                        out.units = out.units or {};
                        out.units[unit] = value[unit];
                    else
                        out[field] = value;
                    end
                    count = count + 1;
                end
            end
            return out;
        end
        local function ownersProfile(helpOnly, bare)
            seed = 12345;
            local out = {};
            for k = 1, 30 do
                local key = "CTRL-F" .. k;
                local readsMouseover = k <= 20;
                local onlyHelp = readsMouseover and (k <= math.floor(20 * helpOnly + 0.5));
                for a = 1, 10 do
                    local mouseover;
                    if (readsMouseover and a == 1) then
                        mouseover = Constants.REACTION_HELP;
                    elseif (readsMouseover and a == 2) then
                        mouseover = onlyHelp and Constants.REACTION_HELP or Constants.REACTION_HARM;
                    end
                    out[#out + 1] = action({ value = 585 + a, key = key, conditions = conditionsOf(mouseover) });
                end
                if (not bare) then
                    out[#out + 1] = action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = key });
                end
            end
            return out;
        end
        local CURSOR = {
            { id = "enemy", reaction = "harm" }, false, { id = "friend3", reaction = "help" }, false,
        };
        print("\nThe owner's shape, 30 keys x 10 actions x 5 conditions, 20 reading mouseover, the body in us,"
            .. "\nby the share of those asking help alone: quiet, the cursor moving on every beat, the bundles a"
            .. "\nmoving beat judges of all, a second at 144:");
        for _, helpOnly in ipairs({ 0, 0.5, 1 }) do
            largeWorld();
            local owners = ownersProfile(helpOnly);
            local started = os.clock();
            bind(owners, LARGE_SWITCHES);
            local rebuild = (os.clock() - started) * 1000;
            local readers = 0;
            for _, item in pairs(DebindPrivate.JudgmentItems) do
                for _, column in ipairs(item.columns) do
                    if (item.base == nil and column.kind == "unit" and column.arg == "mouseover") then
                        readers = readers + 1;
                    end
                end
            end
            assert(readers == 20, "the owner's shape has " .. readers .. " keys reading mouseover");
            local perInstruction = instructionCost(interp);
            interp.state.combat = false;
            interp:beat();
            local _, _, quietLines = price(scenario(LARGE_BEATS, {}), perInstruction);
            local moves = {};
            for b = 1, LARGE_BEATS do
                moves[b] = function()
                    shim.world.units.mouseover = CURSOR[b % #CURSOR + 1] or nil;
                end;
            end
            local _, _, movingLines = price(scenario(LARGE_BEATS, moves), perInstruction);
            local moving = BodyShare(movingLines) / LARGE_BEATS;
            -- The same moves again, unmetered, counting the bundles each beat stamps.
            local J, all, judged = interp.env.Judge, 0, 0;
            while (J.bundles[all + 1]) do
                all = all + 1;
            end
            for b = 1, LARGE_BEATS do
                moves[b]();
                local generation = J.generation;
                interp:beat();
                if (J.generation ~= generation) then
                    for n = 1, all do
                        if (J.bundles[n].stamp == J.generation) then
                            judged = judged + 1;
                        end
                    end
                end
            end
            assert(judged > 0, "no moving beat judged anything");
            print(string.format("  help alone %3d%%   quiet %6.2f   moving %7.2f   judged %4.1f of %d   %6.0f us a second"
                .. "   the rebuild %.0f ms headless", helpOnly * 100, BodyShare(quietLines) / LARGE_BEATS, moving,
                judged / LARGE_BEATS, all, moving * 144, rebuild));
            if (helpOnly == 0) then
                for _, l in ipairs(movingLines) do
                    if (not OUTSIDE_THE_BODY[l.what] and l.us / LARGE_BEATS >= 1) then
                        print(string.format("      %-30s %9.1f a beat %8.2f us%s", l.what, l.n / LARGE_BEATS,
                            l.us / LARGE_BEATS, l.measured and "" or " *"));
                    end
                end
            end
        end

        -- The same shape with nothing under each key's ten actions: the rebuild with every key
        -- judged against the one where none is, and the quiet beat that judging costs.
        largeWorld();
        local bare = ownersProfile(0, true);
        local tailed = rebuildMs(ownersProfile(0));
        local off = rebuildMs(bare, { giveBackWhenNoActionRuns = false });
        local on = rebuildMs(bare);
        local perInstruction = instructionCost(interp);
        interp.state.combat = false;
        interp:beat();
        local _, _, quietLines = price(scenario(LARGE_BEATS, {}), perInstruction);
        print(string.format("  no tail: the rebuild %.0f ms on, %.0f ms off (%.0f with the tail); quiet %6.2f",
            on, off, tailed, BodyShare(quietLines) / LARGE_BEATS));
    end
    shim.world.units = {};

    --- **A key of long bundles**: the Multi-axis kit case's seven records over combat, stealth,
    --- the form and the group, with outcomes that differ, so its item keeps several entries the loop
    --- walks. Each beat moves one of the four, in turn, so every beat judges it.
    local function LongRows()
        local MAP, CHAR = "TOGGLEWORLDMAP", "TOGGLECHARACTER0";
        bind({
            action({ value = 585, key = "CTRL-F1", conditions = { combat = true, forms = 2 ^ 1 + 2 ^ 2 } }),
            action({ type = Constants.COMMAND, value = MAP, key = "CTRL-F1",
                conditions = { combat = true, groups = Constants.GROUP_RAID } }),
            action({ value = 585, key = "CTRL-F1", conditions = { stealth = true, forms = 2 ^ 0 } }),
            action({ type = Constants.COMMAND, value = CHAR, key = "CTRL-F1",
                conditions = { combat = false, stealth = false, groups = Constants.GROUP_PARTY + Constants.GROUP_RAID } }),
            action({ type = Constants.GIVEBACK, key = "CTRL-F1", conditions = { forms = 2 ^ 2 } }),
            action({ type = Constants.COMMAND, value = MAP, key = "CTRL-F1", conditions = { combat = true } }),
            action({ value = 585, key = "CTRL-F1" }),
        });
        shim.world.units = { player = { id = "me", reaction = "help" } };
        local perInstruction = instructionCost(interp);
        interp:resetState();
        interp:beat();
        local function body(counts, n)
            local _, _, lines = price(counts, perInstruction);
            return BodyShare(lines) / n;
        end
        local quietBody = body(scenario(LARGE_BEATS, {}), LARGE_BEATS);
        local GROUPS = { "none", "party", "raid" };
        local moves = {};
        for b = 1, LARGE_BEATS do
            local which = b % 4;
            moves[b] = function(state)
                if (which == 0) then
                    state.combat = not state.combat;
                elseif (which == 1) then
                    state.stealth = not state.stealth;
                elseif (which == 2) then
                    state.form = (state.form + 1) % 3;
                else
                    state.group = GROUPS[b % 3 + 1];
                end
            end;
        end
        local movedBody = body(scenario(LARGE_BEATS, moves), LARGE_BEATS);
        print(string.format("  quiet %5.2f, a move on every beat %5.2f; a second, 3 moves: %3.0f / %3.0f / %4.0f;"
            .. " every beat: %3.0f / %3.0f / %4.0f", quietBody, movedBody,
            2 * quietBody + 3 * movedBody, 17 * quietBody + 3 * movedBody, 141 * quietBody + 3 * movedBody,
            5 * movedBody, 20 * movedBody, 144 * movedBody));
        interp:resetState();
        shim.world.units = {};
    end
    print("\nThe long key, seven records over four columns, the body in us:");
    LongRows();

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

    ---------------------------------------------------------------------------
    -- The beat's signal (`implementing-the-cuts-inside-the-beat-handler.md` Q1b)
    ---------------------------------------------------------------------------

    --- Every shape above but the gate table, a beat in total, on the `"a"` driver and on
    --- `state-visibility` (`BeatSignal.lua`). Everything else above ran on `"a"`, which is what a
    --- login without the check's answer gets.
    local SIGNAL_SHAPES = {
        { "12 tail keys", function() bind(profile(12)); end },
        { "computed switches", function()
            shim.world.units = { party3 = { id = "friend", reaction = "help" } };
            bind(actions, COMPUTED);
            interp.driverHandle:RunAttribute("SetUnit", "custom1", "party3");
        end },
        { "the large shape", function()
            largeWorld();
            bind(largeProfile(0), LARGE_SWITCHES);
        end },
    };
    print("\nThe beat's signal, a beat in us: quiet | one state moved on every beat");
    for _, shape in ipairs(SIGNAL_SHAPES) do
        local row = {};
        for _, comes in ipairs({ false, true }) do
            DebindPrivate.BeatSignal.comes = comes;
            shape[2]();
            local instruction = instructionCost(interp);
            local tick = managerTick();
            interp:beat();
            local quiet = price(scenario(QUIET, {}), instruction) / QUIET + tick;
            local moves = {};
            for b = 1, MOVING do
                moves[b] = function(state) state.mounted = not state.mounted; end;
            end
            local moved = price(scenario(MOVING, moves), instruction) / MOVING + tick;
            row[#row + 1] = string.format("%s %5.2f | %5.2f", comes and "visibility" or "attribute ", quiet, moved);
        end
        print(string.format("  %-18s %s   %s", shape[1], row[1], row[2]));
    end
    DebindPrivate.BeatSignal.comes = nil;
    shim.world.units = {};
end
