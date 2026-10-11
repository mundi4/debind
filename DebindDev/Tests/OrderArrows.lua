local _, Dev = ...

local Constants, LLL
Dev.OnDebindLoaded(function(private)
    Constants, LLL = private.Constants, private.L
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local UseOffSpecLayer = Dev.UseOffSpecLayer
local ApplyBindings = Dev.ApplyBindings

-----------------------------------------------------------
-- Test Cases: The order arrows on a key holding another specialization's row
--
-- **Both of these need a second layer that is stored and not live**, which is what an inactive
-- specialization's layer is, and `UseOffSpecLayer` is the only way to stand one up. Everything
-- measured here is a frame: which buttons the row put up, what a press on one wrote. The headless
-- specs reach `ComputeOrderSwap` and stop there -- they cannot see the row deciding what to show,
-- and they cannot see the swap reach a layer through `FindLayerID`.
--
-- **What they cannot reach in principle**: how any of it looks. That the reason column reads well
-- beside a dead arrow, or that the button band sits where the name ends, is not a thing an
-- assertion can hold.
-----------------------------------------------------------

--- The live row frame for one action, or nil. Read off the ScrollBox rather than built by hand:
--- these tests are about what the list decided, and a frame built here would be answering for a
--- list that never ran.
local function FindOrderLine(action)
    local found
    DebindResultPanel.ContentArea.ScrollBox:ForEachFrame(function(frame)
        local elementData = frame.GetElementData and frame:GetElementData()
        if elementData and elementData.row and elementData.row.action == action then
            found = frame
        end
    end)
    return found
end

RegisterTest("Order arrows: a line drawn under the row is what puts them up", {
    description = "A key holding one of this specialization's rows and one of another's shows the arrows on both, dead and saying which",
    run = function()
        local NAME = "Order arrows drawn count"
        local KEY = "CTRL-ALT-F9"

        -- **The counted number and the live number differ here, and only here.** With both rows
        -- live the two agree and the test passes whichever one the row is counting.
        local InsertOffSpec = UseOffSpecLayer()
        local mine = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        InsertOffSpec({ type = Constants.SPELL, value = 2, key = KEY })
        ApplyBindings()

        DebindFrame:Show()
        AddTeardown(function() DebindFrame:CloseWindow() end)
        DebindLayerPanel:SetSelectedAction(mine)
        DebindResultPanel:RefreshKeyboard()

        local line = FindOrderLine(mine)
        if not line then
            return Fail(NAME, format("no row for %s in the left column, is a search term or filter on", KEY))
        end

        if not line.MoveDownButton:IsShown() then
            return Fail(NAME, "a row with a line drawn under it put up no arrows")
        end
        if line.MoveDownButton:IsEnabled() then
            return Fail(NAME, "the arrow toward another specialization's row is live")
        end
        if line.MoveDownButton.reason ~= "SPEC" then
            return Fail(NAME, format("the dead arrow points at the wrong reason: %s",
                tostring(line.MoveDownButton.reason)))
        end
        if line.MoveUpButton.reason ~= "ALREADY_FIRST" then
            return Fail(NAME, format("the top row is not saying it is the top row: %s",
                tostring(line.MoveUpButton.reason)))
        end

        return Pass(NAME, "the arrows stood, dead, and named the specialization step")
    end,
})

RegisterTest("Order arrows: another specialization's rows reorder among themselves", {
    description = "Pressing an arrow on a row in an inactive specialization's layer swaps the numbers in that layer",
    run = function()
        local NAME = "Order arrows off-spec swap"
        local KEY = "CTRL-ALT-F10"

        local InsertOffSpec = UseOffSpecLayer()
        local first = InsertOffSpec({ type = Constants.SPELL, value = 1, key = KEY })
        local second = InsertOffSpec({ type = Constants.SPELL, value = 2, key = KEY })
        ApplyBindings()

        if not (first.seq < second.seq) then
            return Fail(NAME, format("setup: the numbers did not come out in order, %s then %s",
                tostring(first.seq), tostring(second.seq)))
        end

        DebindFrame:Show()
        AddTeardown(function() DebindFrame:CloseWindow() end)
        DebindLayerPanel:SetSelectedAction(second)
        DebindResultPanel:RefreshKeyboard()

        local line = FindOrderLine(second)
        if not line then
            return Fail(NAME, format("no row for %s in the left column, is a search term or filter on", KEY))
        end
        if not line.MoveUpButton:IsEnabled() then
            return Fail(NAME, format("the arrow is dead in its own layer: %s",
                tostring(line.MoveUpButton.reason)))
        end

        -- **Pressed rather than calling `ApplyOrderSwap`.** What is being measured is that the
        -- press reaches the layer at all: the swap finds it through `FindLayerID`, and a layer
        -- that walk cannot see makes the whole gesture a silent no-op.
        line.MoveUpButton:Click()

        if not (second.seq < first.seq) then
            return Fail(NAME, format("the press settled nothing, %s then %s",
                tostring(first.seq), tostring(second.seq)))
        end

        return Pass(NAME, "the press moved a row inside a layer this specialization does not run")
    end,
})

-- The lines standing in GameTooltip right now, top to bottom. A test that wants to know what a
-- tooltip says asks the tooltip, not the function that filled it.
local function TooltipLines()
    local lines = {}
    for i = 1, GameTooltip:NumLines() do
        local fontString = _G["GameTooltipTextLeft" .. i]
        lines[i] = fontString and fontString:GetText() or ""
    end
    return lines
end

local function HasLine(lines, text)
    for _, line in ipairs(lines) do
        if line == text then
            return true
        end
    end
    return false
end

-- Two rows on one key in this layer, one with a condition. The conditions step settles their
-- order, so the arrows between them are locked by a rule and the ones at the ends are not.
local function PlantConditionLockedPair(key)
    local first = InsertAction({ type = Constants.SPELL, value = 1, key = key, combat = true })
    local second = InsertAction({ type = Constants.SPELL, value = 2, key = key })
    ApplyBindings()

    DebindFrame:Show()
    AddTeardown(function() DebindFrame:CloseWindow() end)
    DebindLayerPanel:SetSelectedAction(second)
    DebindResultPanel:RefreshKeyboard()
    return first, second, FindOrderLine(second)
end

-- What the game does: the window, the tooltip and the real button scripts, none of which the
-- headless run has.
RegisterTest("Order arrows: an arrow a rule holds is dead", {
    description = "An arrow held by the conditions step is disabled, and so is one at the end of its group",
    run = function()
        local NAME = "Locked arrow"
        local KEY = "CTRL-ALT-F11"

        local _, _, line = PlantConditionLockedPair(KEY)
        if not line then
            return Fail(NAME, format("no row for %s in the left column, is a search term or filter on", KEY))
        end
        AddTeardown(function() line:OnMoveLeave() end)

        local up, down = line.MoveUpButton, line.MoveDownButton
        if up.reason ~= "CONDITIONAL" then
            return Fail(NAME, format("setup: the upward arrow is not held by the conditions step: %s",
                tostring(up.reason)))
        end
        if up:IsEnabled() then
            return Fail(NAME, "the arrow a rule holds is live")
        end

        -- The arrow at the end of the group is dead too, for a reason of its own.
        if down.reason ~= "ALREADY_LAST" then
            return Fail(NAME, format("setup: the downward arrow is not at the end: %s", tostring(down.reason)))
        end
        if down:IsEnabled() then
            return Fail(NAME, "an arrow at the end of its group is live")
        end

        return Pass(NAME, "both arrows are dead, one by the conditions step and one at the end of its group")
    end,
})

RegisterTest("Order arrows: the locked tooltip says the rule", {
    description = "A locked arrow's tooltip carries the rule's sentence; an arrow at the end carries its own",
    run = function()
        local NAME = "Locked arrow tooltip"
        local KEY = "CTRL-ALT-F12"

        local _, _, line = PlantConditionLockedPair(KEY)
        if not line then
            return Fail(NAME, format("no row for %s in the left column, is a search term or filter on", KEY))
        end
        AddTeardown(function() line:OnMoveLeave() end)

        line:OnMoveEnter(line.MoveUpButton)
        local lines = TooltipLines()
        if not HasLine(lines, LLL["ORDER_BLOCKED_CONDITIONAL"]) then
            return Fail(NAME, format("the locked tooltip does not say the rule: %s", table.concat(lines, " | ")))
        end
        line:OnMoveLeave()

        line:OnMoveEnter(line.MoveDownButton)
        lines = TooltipLines()
        if not HasLine(lines, LLL["ORDER_BLOCKED_ALREADY_LAST"]) then
            return Fail(NAME, format("the end arrow's tooltip lost its sentence: %s", table.concat(lines, " | ")))
        end
        line:OnMoveLeave()

        return Pass(NAME, "the rule on the lock; the end arrow's own sentence at the end")
    end,
})
