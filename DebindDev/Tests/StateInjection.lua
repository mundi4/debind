local _, Dev = ...

local Constants
Dev.OnDebindLoaded(function(private)
    Constants = private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local SetMockState = Dev.SetMockState
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local LastWinner = Dev.LastWinner
local WaitForWinner = Dev.WaitForWinner

-----------------------------------------------------------
-- Test Cases: State Injection (live)
-----------------------------------------------------------

-- **Kept here.** The decision is headless now (`tests/eval_spec.lua`), and what stays is the
-- injection landing between the measurement and the comparison inside a snippet that really
-- compiled.
-- The reason the kit exists. A combat-only binding is reachable only in combat, and in combat
-- nothing outside can drive it -- lockdown stops the clicking, the binding and the attribute
-- writes. So the one state where this code matters is the one state where it cannot be checked.
--
-- Overriding the measured combat while the client is at peace breaks that. The decision runs its
-- real path; the client, not actually fighting, never locks anything down.
RegisterTest("State injection: combat-only binding", {
    description = "Injecting combat really does fire the combat-only binding",
    run = function()
        local NAME = "Combat injection"
        local KEY = "CTRL-SHIFT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "in real combat there is no telling the injected result from the real one")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        ApplyBindings()

        SetMockState("combat", false)
        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("at peace and the combat-only binding fired #%d", LastWinner()))
        end

        SetMockState("combat", true)
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local inCombat = WaitForWinner()
        if inCombat == nil then
            return Fail(NAME, "combat was injected and nothing fired, the injection never reached the snippet")
        end

        -- Back to peace: the press has to fire nothing again. Without this the test would pass on
        -- a key that fires whatever the state.
        SetMockState("combat", false)
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, "combat was put back and it still fired")
        end

        return Pass(NAME, format("drove the combat path from outside combat (#%d)", inCombat))
    end,
})

-----------------------------------------------------------
-- Test Cases: The unit axes, measured for real
-----------------------------------------------------------

-- The emit-and-match half -- registering an axis, measuring it every tick, comparing it in the
-- snippet -- reads headless now: `tests/eval_spec.lua` asks it at the press and
-- `tests/boundkey_spec.lua` asks it at the key. What is left here is the axis nothing outside the
-- game can put a unit into.

-- **Kept here.** The axis itself is headless (`tests/eval_spec.lua`, the life axis) and so is the
-- living half (`tests/boundkey_spec.lua`). This is the dead half, which no living session can
-- produce and no world a spec writes down can prove. `player-dead` rewrites the word in the
-- expression the press parses (`PROBE.ParseUnit`), so the press runs its real path and only the
-- answer differs.
RegisterTest("State injection: dead flips a binding", {
    description = "Injecting dead really does fire the binding conditioned on it",
    run = function()
        local NAME = "Dead injection"
        local KEY = "CTRL-SHIFT-F10"

        if InCombatLockdown() then
            return Fail(NAME, "in combat there is no telling the injected result from the real one")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { player = { dead = true } },
        })
        ApplyBindings()

        SetMockState("player-dead", false)
        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("alive and the dead-only binding fired #%d", LastWinner()))
        end

        SetMockState("player-dead", true)
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local whenDead = WaitForWinner()
        if whenDead == nil then
            return Fail(NAME, "dead was injected and nothing fired, the injection never reached the snippet")
        end

        -- Putting it back has to stop it again. Without that, a key that fires whatever the state
        -- passes too.
        SetMockState("player-dead", false)
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, "it was put back and it still fired")
        end

        return Pass(NAME, format("fired by injecting dead (#%d)", whenDead))
    end,
})

-- **Kept here for the same reason as the one above.** The cells themselves are headless
-- (`tests/eval_spec.lua` and `tests/boundkey_spec.lua` both split the shared cell), but a session
-- can only be in one group at a time, and the cell that matters -- in the raid, in the reader's
-- own subgroup -- takes a raid to reach. `player-group` is injected where `player-dead` is.
--
-- **The value injected is a cell name, not a ticked box.** The three boxes overlap and the four
-- cells partition; the press measures the cell and the condition holds the boxes it covers
-- (`Constants.lua`'s `UNITGROUPCELL_*`). Injecting `"both"` against a `[in my party]` condition
-- is what asks whether the overlap survived to the snippet: a chain that took the raid answer and
-- stopped would leave this key firing nothing.
RegisterTest("State injection: the party cell reaches a raid subgroup", {
    description = "A unit condition of [in my party] fires while the injected cell is raid+party",
    run = function()
        local NAME = "Group cell injection"
        local KEY = "CTRL-SHIFT-F11"

        if InCombatLockdown() then
            return Fail(NAME, "in combat there is no telling the injected result from the real one")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { player = { group = Constants.UNITGROUP_PARTY } },
        })
        ApplyBindings()

        SetMockState("player-group", "neither")
        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("cell=neither and the party binding fired #%d", LastWinner()))
        end

        SetMockState("player-group", "both")
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local whenBoth = WaitForWinner()
        if whenBoth == nil then
            return Fail(NAME, "cell=both and nothing fired, the injection never reached the snippet or the overlap was lost")
        end

        -- The cell [in my raid] alone is the other subgroup, which [in my party] does not cover.
        -- Without this the test passes on a snippet that ignores the condition entirely.
        SetMockState("player-group", "raid")
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, "cell=raid is another subgroup and the party binding fired")
        end

        SetMockState("player-group", nil)
        return Pass(NAME, format("the party condition fired on the shared cell (#%d)", whenBoth))
    end,
})
