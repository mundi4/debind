local _, Dev = ...

local Constants
Dev.OnDebindLoaded(function(private)
    Constants = private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local WaitUntil = Dev.WaitUntil
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local HoldUnmatchedKeys = Dev.HoldUnmatchedKeys
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local LastWinner = Dev.LastWinner

-----------------------------------------------------------
-- Test Cases: The macro store as an input
-----------------------------------------------------------

-- **A `MACRO` action naming a macro that does not exist is left out of the build entirely**
-- (`GetMissingMacroName` -> `BINDING_ISSUE_MISSING_MACRO` -> `BuildKeyMap`), which makes the macro
-- store an input to what the keys are. Nothing was watching it: create the macro and the row stops
-- being marked -- the window says nothing is wrong -- while the key stays dead until something
-- unrelated rebuilds, or a `/reload`. `UPDATE_MACROS` is registered for that.
--
-- **The key is ours through both halves** (`Debind.lua`'s `KeysOnLiveLayers`, with `HoldUnmatchedKeys`),
-- so dead means the press fires nothing, and that is what is asked.
--
-- **The half that is left is the client's.** `tests/boundkey_spec.lua` sends `UPDATE_MACROS` by
-- hand and holds everything downstream of it: that the addon is listening, that the handler queues
-- a rebuild, and that the key comes back. What no harness can send is the event itself, and this
-- makes a real macro rather than faking one for exactly that reason -- what broke was never "a
-- rebuild does not read the store" but that **no rebuild happens**.
--
-- Deleting it belongs to the runner, so it goes however this ends.
RegisterTest("Macro store: creating the missing macro revives the key", {
    description = "Creating the missing macro revives the key with no reload",
    run = function()
        local NAME = "Macro revive"
        local KEY = "CTRL-SHIFT-F6"
        local MACRO = "DebindTestRevive"

        if InCombatLockdown() then
            return Fail(NAME, "a macro cannot be created in combat")
        end

        AddTeardown(function()
            if not InCombatLockdown() and GetMacroIndexByName(MACRO) > 0 then
                DeleteMacro(MACRO)
            end
        end)

        if GetMacroIndexByName(MACRO) > 0 then
            DeleteMacro(MACRO)
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        HoldUnmatchedKeys()
        InsertAction({ type = Constants.MACRO, value = MACRO, key = KEY })
        ApplyBindings()

        -- **The negative first.** Without it a key that fired the whole time reads as a pass,
        -- and this test would go green on a build where the issue never drops anything.
        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then
            return Fail(NAME, "the macro does not exist and the key was handed back: " .. rerr)
        end
        if LastWinner() ~= nil then
            return Fail(NAME, format("the macro does not exist and the press already fires #%d", LastWinner()))
        end

        -- **Asked of the store, not of the return value.** `CreateMacro` raises when there is no
        -- room, and `0` back would pass a plain `not` check anyway - `0` is true in Lua. Either way
        -- the answer wanted here is whether the macro is now there.
        pcall(CreateMacro, MACRO, 132219, "/say debtest")
        if GetMacroIndexByName(MACRO) == 0 then
            return Fail(NAME, "the macro could not be created, the macro slots may be full")
        end

        -- **Waiting on the press is right here only because the lines above proved it fired
        -- nothing.** The usual objection -- that waiting for what you are about to assert can only
        -- fail by timing out -- needs the expected value to be a possible current one, and it is
        -- not. A timeout *is* the finding: nothing rebuilt.
        local winner
        WaitUntil(function()
            if EvalClickTimeKey(KEY) then
                winner = LastWinner()
            end
            return winner ~= nil
        end, 3)

        if winner == nil then
            return Fail(NAME,
                "the macro was created and the press still fires nothing, nobody is listening to UPDATE_MACROS")
        end

        return Pass(NAME, format("fires #%d", winner))
    end,
})
