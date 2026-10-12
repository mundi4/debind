local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local GetNthBinding = Dev.GetNthBinding
local SetMockState = Dev.SetMockState
local SetMockModifiedClick = Dev.SetMockModifiedClick
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local EvalClickCast = Dev.EvalClickCast
local LastEvalUnit = Dev.LastEvalUnit
local LastWinner = Dev.LastWinner
local WaitForWinner = Dev.WaitForWinner
local WaitForEvalAnswer = Dev.WaitForEvalAnswer
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local HoverEnter = Dev.HoverEnter
local HoverLeave = Dev.HoverLeave
local WaitForHoverSlot = Dev.WaitForHoverSlot

-- **Needs the game.** Which binding wins each press and at which unit is headless
-- (`tests/eval_spec.lua`, `deciding-what-a-press-runs.md` §6 #73 to #94). What only the client can
-- show is the same answers out of the real restricted environment: the fallback's records compiled
-- into the press body, the real unit resolution on the click-time path, and the frame click's own
-- path. The Resolved Unit row is [dead], with life injected, because no unit the kit can stand up
-- is dead on demand.
RegisterTest("Resolved Unit fallback: which binding wins each press, and at whom", {
    description = "Otherwise, cast on yourself를 켠 액션에서 누름마다 어느 바인딩이 이기고 어느 유닛에 나가는지: 그냥 누름, 가리킨 누름, Self·Focus Cast Key, 개체창 클릭",
    applies = function()
        local selfMod, focusMod = DebindPrivate.CastKeyModifiers()
        if not selfMod or not focusMod then
            return false, "needs both cast keys on in the settings tab and the game"
        end
        return true
    end,
    run = function()
        local NAME = "Resolved Unit fallback"
        -- **Bare keys**: a key that holds a cast key's modifier in its own name never reads that
        -- key at the press (`bindings.checkSelfCast`).
        local KEY, USUAL_KEY, CLICK_KEY = "F7", "F8", "BUTTON3"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then return Fail(NAME, "rebake failed: " .. tostring(probesErr)) end

        local function Fallback(key, casting)
            casting.fallbackToSelf = true
            casting.hoverCast = "cast"
            return InsertAction({ type = Constants.SPELL, value = 585, key = key, casting = casting,
                units = { ["@"] = { exists = true, dead = true } } })
        end
        Fallback(KEY, {})
        Fallback(USUAL_KEY, { selfCastKey = "usual", focusCastKey = "usual" })
        Fallback(CLICK_KEY, {})
        ApplyBindings()

        local frame, ferr = CreateTestUnitFrame("player")
        if not frame then return Fail(NAME, ferr) end

        SetMockState("target-dead", false)
        SetMockState("player-dead", false)
        SetMockState("focus-dead", false)

        local seen = {}

        --- Presses `key` and answers what won: `"fallback"`, `"other"` or `"nothing"`, and the unit
        --- the press settled on. **The wait costs nothing where nothing runs**: the tier's closing
        --- block wins and is reported (`LastWinner` reads it as nil), so the limit is spent only on
        --- a press that reported nothing at all.
        local function Press(key)
            local ran, rerr = EvalClickTimeKey(key)
            if not ran then return nil, rerr end
            local index = WaitForWinner()
            if index == nil then
                return "nothing"
            end
            local binding = GetNthBinding(key, index)
            return binding and binding.fallback and "fallback" or "other", LastEvalUnit()
        end

        local function Expect(label, key, want, wantUnit)
            local got, unit = Press(key)
            if got ~= want or (wantUnit and unit ~= wantUnit) then
                return format("%s: %s won at %s, it should be %s at %s", label, tostring(got),
                    tostring(unit), want, tostring(wantUnit))
            end
            seen[#seen + 1] = format("%s=%s@%s", label, got, tostring(unit))
        end

        local err = Expect("plain", KEY, "fallback", "player")
        if err then return Fail(NAME, err) end

        HoverEnter(frame)
        WaitForHoverSlot(true)
        err = Expect("pointed", KEY, "fallback", "player")
        if err then return Fail(NAME, err) end

        -- **The negative**: the pointed unit holding the row takes the press from the fallback, so a
        -- key whose fallback won everything would fail here.
        SetMockState("player-dead", true)
        HoverEnter(frame)
        err = Expect("pointed, row holds", KEY, "other", "player")
        if err then return Fail(NAME, err) end
        SetMockState("player-dead", false)

        -- The frame click, read off the winner itself: the click path reports no unit.
        local ran, rerr = EvalClickCast(frame, 3, 0)
        if not ran then return Fail(NAME, rerr) end
        WaitForEvalAnswer()
        local clicked = LastWinner() and GetNthBinding(CLICK_KEY, LastWinner())
        if not (clicked and clicked.fallback and clicked.unit == "player") then
            return Fail(NAME, format("frame click: #%s won, %s at %s", tostring(LastWinner()),
                clicked and (clicked.fallback and "the fallback" or "not the fallback") or "nothing",
                tostring(clicked and clicked.unit)))
        end
        seen[#seen + 1] = "click=fallback@player"

        HoverLeave(frame)
        WaitForHoverSlot(false)

        -- **Held presses last**: a held cast key is let go only by the run's teardown. The Focus Cast
        -- Key first, since with both held the Self Cast Key's press is the one asked.
        SetMockModifiedClick("FOCUSCAST")
        err = Expect("focus held, on your focus", KEY, "nothing")
        if err then return Fail(NAME, err) end
        err = Expect("focus held, usual target", USUAL_KEY, "fallback", "player")
        if err then return Fail(NAME, err) end

        SetMockModifiedClick("SELFCAST")
        err = Expect("self held, on you", KEY, "nothing")
        if err then return Fail(NAME, err) end
        err = Expect("self held, usual target", USUAL_KEY, "fallback", "player")
        if err then return Fail(NAME, err) end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})
