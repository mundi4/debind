local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local UNIT_TOKEN_ABSENT = Dev.UNIT_TOKEN_ABSENT
local StandDownTestFrame = Dev.StandDownTestFrame
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local SetFrameUnit = Dev.SetFrameUnit
local HoverEnter = Dev.HoverEnter
local HoverLeave = Dev.HoverLeave
local GetHoverUnit = Dev.GetHoverUnit
local WaitForHoverSlot = Dev.WaitForHoverSlot

-----------------------------------------------------------
-- Test Cases: Hover Slot (live)
-----------------------------------------------------------

-- The one state that could not be checked by hand: **the cursor sits still on a unit frame and
-- the unit goes away.** No enter fires and no leave fires, so what has to answer is the read a
-- press makes. Reproducing that in the world means waiting for a boss to despawn or an arena to
-- swap -- a raid schedule, not a check.
--
-- Owning the frame turns it into three attribute writes. Pointing it at a unit that does not
-- exist is indistinguishable from a unit that stopped existing: the read takes the attribute,
-- asks `UnitExists`, and follows the same branch either way.
--
-- No mocks are involved. The test picks the unit token, so reality supplies both answers --
-- `player` exists, an unrecognised token does not.
-- A rebuild fills `States` afresh, and `unitframe` alone is a value that only enter and leave set,
-- so nobody fills it back in. Cleared, hover dies with the cursor still sitting on the frame and
-- only comes back if the mouse leaves and returns. One condition changing is enough to run a
-- rebuild, entering combat or changing form among them, so this is walked in real use.
--
-- **`GetHoverUnit()` alone cannot catch it.** Its counterpart `UnitAliasMap["unitframe"]` is not cleared
-- by a rebuild, so it stays "player" even where the bug is. Hence looking at leave: with the slot
-- gone, leave finds nothing to clear and simply goes out, and hover is left standing.
RegisterTest("Hover slot: survives a rebuild under a still cursor", {
    description = "The hover slot survives a rebuild that runs while hovering",
    run = function()
        local NAME = "Hover survives rebuild"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and rebuilding are both blocked in combat")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { frameTypes = Constants.FRAMETYPE_GROUP } },
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        -- The cursor stays where it is. Only the rebuild runs.
        --
        -- **Giving up no frame at all here is the stricter test.** A rebuild runs its snippets
        -- before it returns, so if the slot went it is already empty on the next line. That is why
        -- this is the bare call and not `ApplyBindings`, which gives up a frame in `WaitForIdle`.
        DebindPrivate.UpdateBindings()

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after the rebuild, it should still be player", tostring(GetHoverUnit())))
        end

        -- Whether the slot is alive comes apart here. Gone, leave finds nothing to clear.
        HoverLeave(frame)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "hover=%s even after leave. that means the rebuild cleared the hover slot",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "survives the rebuild, and leave clears it properly")
    end,
})

-- **The hovered unit is read off the frame at the call** (`GetUnitFrameUnit`, §3 of
-- `dropping-the-game-fallback.md`). The beat no longer polls the slot, so a unit that goes
-- away under a still cursor leaves the slot as it was; what has to answer "nobody" is the read. The
-- headless half is `tests/hover_spec.lua`; what only the client shows is that
-- `GetEffectiveAttribute` on a frame handle answers in the real sandbox.
RegisterTest("Hover unit: read off the frame when a unit disappears under a still cursor", {
    description = "GetUnitFrameUnit answers nobody when the unit alone disappears under a still cursor, and the unit again when it comes back",
    run = function()
        local NAME = "Hover unit"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and writing attributes are both blocked in combat")
        end

        -- A hover binding has to exist, or the hover axis is never measured at all and the slot
        -- this reads stays empty. The test builds its own precondition rather than hoping for one.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { frameTypes = Constants.FRAMETYPE_GROUP } },
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        local hovered
        DebindPrivate.BindingDriver.DebindTestHovered = function(_, unit)
            hovered = unit
        end
        local function ReadHovered()
            hovered = nil
            SecureHandlerExecute(DebindPrivate.BindingDriver,
                [[self:CallMethod("DebindTestHovered", self:RunAttribute("GetUnitFrameUnit"))]])
            return hovered
        end

        if ReadHovered() ~= "player" then
            return Fail(NAME, format("GetUnitFrameUnit=%s over the frame, it should be player", tostring(hovered)))
        end

        -- The cursor has not moved. Only the attribute changed, which is exactly the shape of a
        -- unit despawning under it. Nothing has to come round first: the read is the call.
        SetFrameUnit(frame, UNIT_TOKEN_ABSENT)
        if ReadHovered() ~= nil then
            return Fail(NAME, format("the unit is gone and GetUnitFrameUnit=%s", tostring(hovered)))
        end

        -- The slot still holds the frame, so the same read finds the unit when it comes back.
        SetFrameUnit(frame, "player")
        if ReadHovered() ~= "player" then
            return Fail(NAME, format("the unit came back and GetUnitFrameUnit=%s", tostring(hovered)))
        end

        return Pass(NAME, "gone -> nobody, back -> the unit again")
    end,
})

-- When the cursor enters a frame whose registration has been dropped.
--
-- Dropping it does not take the wrapper off (`_hoverWrapped` in `FrameRegistry.lua`). Only the
-- topmost wrapper can be taken off and there is no guarantee that one is ours, so our
-- `setup_onenter` goes on running even on a frame that is no longer registered. What it does in
-- there is what dropping the registration actually amounts to.
--
-- Simply standing back will not do. Mouse focus is one at a time, so **the cursor being inside a
-- frame we do not track is itself proof that it is not inside the frame we last wrote down.** So the
-- slot is emptied. It is also the clean-up for a lost `OnLeave`.
--
-- **Why this stays here.** The value side is already seen by `tests/hover_spec.lua`, which runs the
-- same two snippets. What this test sees on top of that is one thing: whether **the real sandbox
-- allows** calling another body with `RunAttribute` from inside a wrapped script. Where it does not,
-- that branch dies with no error and no log.
RegisterTest("Hover slot: a frame we stepped off stands the slot down", {
    description = "Entering a frame the addon has stepped off empties the hover slot",
    run = function()
        local NAME = "Frame stepped off"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and standing off one are both blocked in combat")
        end

        -- The hover axis is measured only where there is a hover condition, and that is what gives
        -- this slot a value to read.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = {} },
        })
        ApplyBindings()

        local tracked, trackedErr = CreateTestUnitFrame("player", "group")
        if not tracked then return Fail(NAME, trackedErr) end

        local dropped, droppedErr = CreateTestUnitFrame("player", "group")
        if not dropped then return Fail(NAME, droppedErr) end

        StandDownTestFrame(dropped)
        if DebindPrivate.ccframes[dropped] ~= false then
            return Fail(NAME, "the premise is gone: the fight did not stand us down")
        end

        HoverEnter(tracked)
        AddTeardown(function() HoverLeave(tracked) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        -- The wrapper is still on, so our body runs here too.
        --
        -- **Nothing is waited on.** `SecureHandlerExecute` returns after running the body, and the
        -- slot not emptying is exactly the fault this test is looking for.
        HoverEnter(dropped)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "entered a frame we do not track and hover=%s. the old frame is still in the slot",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "entering a frame the addon stepped off empties the slot")
    end,
})
