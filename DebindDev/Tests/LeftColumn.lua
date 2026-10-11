local _, Dev = ...

local DebindPrivate, Constants, DebindUI
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants, DebindUI = private, private.Constants, private.DebindUI
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local GetTestLayer = Dev.GetTestLayer
local GetOffSpecLayer = Dev.GetOffSpecLayer
local InsertAction = Dev.InsertAction
local UseOffSpecLayer = Dev.UseOffSpecLayer
local ApplyBindings = Dev.ApplyBindings
local TypeInto = Dev.TypeInto
local LeftColumnProvider = Dev.LeftColumnProvider
local FindLeftElement = Dev.FindLeftElement
local LeftRowOf = Dev.LeftRowOf
local OpenOverviewWithNothingPicked = Dev.OpenOverviewWithNothingPicked

-----------------------------------------------------------
-- Left column: picking across layers
--
-- **Needs the window.** The selection lives in `DebindUI.lua` beside the two lists it is drawn over,
-- and what is measured is what the left column as drawn decides.
--
-- **What these cannot reach**: CTRL and SHIFT held by a hand. `OnClick` reads the client's own
-- `IsControlKeyDown` and `IsShiftKeyDown`, and a test may not write over a client global, so the
-- modifier branches are driven through the functions they call. A heading's plain press is a real
-- click. A row of the test layers cannot be hovered, pressed plainly or right-clicked: each names the
-- row's layer or opens its tab, and the test layers' ids name no tab.
-----------------------------------------------------------

local function LeftHeadingOf(key)
    return FindLeftElement(function(e) return e.isHeader and e.key == key and e.arrivalID == nil end)
end

local function FindHeadingFrame(key)
    local found
    DebindResultPanel.ContentArea.ScrollBox:ForEachFrame(function(frame)
        local elementData = frame.GetElementData and frame:GetElementData()
        if elementData and elementData.isHeader and elementData.key == key then
            found = frame
        end
    end)
    return found
end

--- Three key groups, the middle one holding two rows.
local function PlantThreeGroups()
    local a = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F5" })
    local b1 = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F6", combat = true })
    local b2 = InsertAction({ type = Constants.SPELL, value = 3, key = "CTRL-ALT-F6" })
    local c = InsertAction({ type = Constants.SPELL, value = 4, key = "CTRL-ALT-F7" })
    ApplyBindings()
    return a, b1, b2, c
end

RegisterTest("Left column: a selection spans layers and outlives a tab switch", {
    description = "Two rows from two layers picked in the left column are both picked, both handed to the menu, and still picked after the side tab, the layer tab, Switches and back, and Settings and Back",
    run = function()
        local NAME = "Left column across layers"

        local InsertOffSpec = UseOffSpecLayer()
        local mine = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F5" })
        local other = InsertOffSpec({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F6" })
        ApplyBindings()
        OpenOverviewWithNothingPicked()

        if not LeftRowOf(mine) or not LeftRowOf(other) then
            return Fail(NAME, "setup: a planted row is not in the left column, is a search term or filter on")
        end

        DebindLayerPanel:ToggleActionSelected(mine)
        DebindLayerPanel:ToggleActionSelected(other)
        if DebindFrame:GetSelectionCount() ~= 2
                or not DebindFrame:IsActionSelected(mine) or not DebindFrame:IsActionSelected(other) then
            return Fail(NAME, format("%d picked after two rows from two layers", DebindFrame:GetSelectionCount()))
        end

        -- **What the menu is handed**, which is where a selection read out of one layer's list dropped
        -- the other layer's row without a word.
        local handed = DebindFrame:GetSelectedActions()
        if #handed ~= 2 then
            return Fail(NAME, format("the menu would be handed %d of 2", #handed))
        end

        -- Before the tab switch, so that its teardown runs after the tab is back and the side tab it
        -- clicks is one that tab shows.
        local checkedSideTab, otherSideTab
        for _, sideTab in ipairs(DebindFrame.LayerPanel.SideTabs) do
            if sideTab:IsShown() then
                if sideTab:GetChecked() then
                    checkedSideTab = sideTab
                elseif not otherSideTab then
                    otherSideTab = sideTab
                end
            end
        end
        if not checkedSideTab or not otherSideTab then
            return Fail(NAME, "setup: no second side tab is shown to switch to")
        end
        AddTeardown(function() checkedSideTab:Click() end)
        otherSideTab:Click()
        if DebindFrame:GetSelectionCount() ~= 2 then
            return Fail(NAME, format("switching the side tab left %d picked", DebindFrame:GetSelectionCount()))
        end

        local tab = DebindFrame.LayerPanel.selectedTab
        AddTeardown(function() DebindFrame:SetTab(tab) end)
        DebindFrame:SetTab(tab == 1 and 2 or 1)
        if DebindFrame:GetSelectionCount() ~= 2 then
            return Fail(NAME, format("switching the tab left %d picked", DebindFrame:GetSelectionCount()))
        end

        AddTeardown(function() DebindFrame.OverviewTab:Click() end)
        DebindFrame.SwitchesTab:Click()
        DebindFrame.OverviewTab:Click()
        if DebindFrame:GetSelectionCount() ~= 2 then
            return Fail(NAME, format("Switches and back left %d picked", DebindFrame:GetSelectionCount()))
        end

        -- The gear's second press is the settings panel's Back (`LeaveSettings`).
        local gear = DebindFrame.OptionsButton
        local gearScript = gear:GetScript("OnMouseUp")
        if not gearScript then
            return Fail(NAME, "the gear has no OnMouseUp, so the XML wiring is gone")
        end
        gearScript(gear, "LeftButton", true)
        if not DebindFrame.SettingsPanel:IsShown() then
            return Fail(NAME, "setup: the gear did not open the settings tab")
        end
        gearScript(gear, "LeftButton", true)
        if not DebindFrame.OverviewPanel:IsShown() then
            return Fail(NAME, "setup: Back did not return to the overview")
        end
        if DebindFrame:GetSelectionCount() ~= 2 then
            return Fail(NAME, format("Settings and Back left %d picked", DebindFrame:GetSelectionCount()))
        end

        DebindLayerPanel:ToggleActionSelected(other)
        if DebindFrame:GetSelectionCount() ~= 1 or DebindFrame:IsActionSelected(other) then
            return Fail(NAME, "CTRL on a picked row of another layer did not take it out")
        end

        return Pass(NAME, "two layers picked, handed over whole, kept across every tab")
    end,
})

RegisterTest("Left column: SHIFT measures from the same row every time", {
    description = "SHIFT from the first drawn row to the last takes every row between, across groups; SHIFT again to the second row shrinks it to two",
    run = function()
        local NAME = "Left column row range"

        PlantThreeGroups()
        OpenOverviewWithNothingPicked()

        local rows = {}
        for _, elementData in LeftColumnProvider():EnumerateEntireRange() do
            if elementData.row then
                rows[#rows + 1] = elementData
            end
        end
        if #rows ~= 4 then
            return Fail(NAME, format("setup: the left column draws %d rows, not the 4 planted", #rows))
        end

        DebindLayerPanel:ToggleActionSelected(rows[1].row.action)
        DebindResultPanel:SelectRangeTo(rows[4], false)
        if DebindFrame:GetSelectionCount() ~= 4 then
            return Fail(NAME, format("a range across three groups held %d of 4", DebindFrame:GetSelectionCount()))
        end

        DebindResultPanel:SelectRangeTo(rows[2], false)
        if DebindFrame:GetSelectionCount() ~= 2 or not DebindFrame:IsActionSelected(rows[1].row.action) then
            return Fail(NAME, format("SHIFT again held %d, the anchor moved", DebindFrame:GetSelectionCount()))
        end

        return Pass(NAME, "four across the groups, then two from the same anchor")
    end,
})

RegisterTest("Left column: a heading is its whole group, at either end of a range", {
    description = "Pressing a heading picks its rows; SHIFT from it to a row above or below keeps the group whole; CTRL on it takes the group out",
    run = function()
        local NAME = "Left column heading"

        local a, b1, b2, c = PlantThreeGroups()
        OpenOverviewWithNothingPicked()

        local _, headingIndex = LeftHeadingOf("CTRL-ALT-F6")
        local rowA, indexA = LeftRowOf(a)
        local rowC, indexC = LeftRowOf(c)
        if not headingIndex or not rowA or not rowC then
            return Fail(NAME, "setup: a planted group is not in the left column, is a search term or filter on")
        end
        local above, aboveIndex, below, belowIndex = rowA, indexA, rowC, indexC
        if indexA > indexC then
            above, aboveIndex, below, belowIndex = rowC, indexC, rowA, indexA
        end
        if not (aboveIndex < headingIndex and headingIndex < belowIndex) then
            return Fail(NAME, "setup: the two-row group is not drawn between the other two")
        end

        local frame = FindHeadingFrame("CTRL-ALT-F6")
        if not frame then
            return Fail(NAME, "setup: the heading has no frame on screen")
        end
        frame:Click("LeftButton")
        if DebindFrame:GetSelectionCount() ~= 2
                or not DebindFrame:IsActionSelected(b1) or not DebindFrame:IsActionSelected(b2) then
            return Fail(NAME, format("pressing the heading picked %d", DebindFrame:GetSelectionCount()))
        end

        FindHeadingFrame("CTRL-ALT-F6"):Click("LeftButton")
        if DebindFrame:GetSelectionCount() ~= 0 then
            return Fail(NAME, format("pressing the heading of the group that was the whole selection left %d picked",
                DebindFrame:GetSelectionCount()))
        end
        FindHeadingFrame("CTRL-ALT-F6"):Click("LeftButton")

        local function GroupWholeWith(row)
            return DebindFrame:GetSelectionCount() == 3 and DebindFrame:IsActionSelected(b1)
                and DebindFrame:IsActionSelected(b2) and DebindFrame:IsActionSelected(row.row.action)
        end

        DebindResultPanel:SelectRangeTo(above, false)
        if not GroupWholeWith(above) then
            return Fail(NAME, format("SHIFT to the row above held %d, not the group and that row", DebindFrame:GetSelectionCount()))
        end
        DebindResultPanel:SelectRangeTo(below, false)
        if not GroupWholeWith(below) then
            return Fail(NAME, format("SHIFT to the row below held %d, not the group and that row", DebindFrame:GetSelectionCount()))
        end

        DebindResultPanel:ToggleGroupSelected(LeftHeadingOf("CTRL-ALT-F6"))
        if DebindFrame:IsActionSelected(b1) or DebindFrame:IsActionSelected(b2) then
            return Fail(NAME, "CTRL on a heading whose group was all picked left some of it picked")
        end

        return Pass(NAME, "the group held whole above and below, and CTRL took it out")
    end,
})

RegisterTest("Left column: a group anchor goes with its group", {
    description = "A heading pressed and then hidden by a search leaves no anchor: the next SHIFT picks only the row pressed",
    run = function()
        local NAME = "Left column released group anchor"

        local _, _, _, c = PlantThreeGroups()
        OpenOverviewWithNothingPicked()

        local frame = FindHeadingFrame("CTRL-ALT-F6")
        if not frame then
            return Fail(NAME, "setup: the heading has no frame on screen")
        end
        frame:Click("LeftButton")

        local searchBox = DebindFrame.OverviewPanel.SearchBox
        AddTeardown(function() TypeInto(searchBox, "") end)
        if not TypeInto(searchBox, "f5") then
            return Fail(NAME, "the search box has no OnTextChanged")
        end
        if LeftHeadingOf("CTRL-ALT-F6") then
            return Fail(NAME, "setup: the search did not hide the two-row group")
        end
        TypeInto(searchBox, "")

        DebindResultPanel:SelectRangeTo(LeftRowOf(c), false)
        if DebindFrame:GetSelectionCount() ~= 1 or not DebindFrame:IsActionSelected(c) then
            return Fail(NAME, format("SHIFT held %d, measured from a group the search had let go", DebindFrame:GetSelectionCount()))
        end

        return Pass(NAME, "the hidden group left no anchor, and SHIFT picked one row")
    end,
})

RegisterTest("Left column: SHIFT with no anchor drawn keeps a heading that already is the selection", {
    description = "With the anchor row hidden by a search and exactly one group picked, SHIFT on that group's heading keeps it picked rather than letting go the way a plain press does",
    run = function()
        local NAME = "Left column SHIFT on the picked heading"

        local a, b1, b2 = PlantThreeGroups()
        OpenOverviewWithNothingPicked()

        -- The anchor ends on `a` and the set is the two-row group alone.
        DebindLayerPanel:ToggleActionSelected(b1)
        DebindLayerPanel:ToggleActionSelected(b2)
        DebindLayerPanel:ToggleActionSelected(a)
        DebindLayerPanel:ToggleActionSelected(a)

        local searchBox = DebindFrame.OverviewPanel.SearchBox
        AddTeardown(function() TypeInto(searchBox, "") end)
        if not TypeInto(searchBox, "f6") then
            return Fail(NAME, "the search box has no OnTextChanged")
        end
        local heading = LeftHeadingOf("CTRL-ALT-F6")
        if LeftRowOf(a) or not heading then
            return Fail(NAME, "setup: the search did not hide the anchor row and keep the two-row group")
        end
        if DebindFrame:GetSelectionCount() ~= 2 then
            return Fail(NAME, format("setup: %d picked before SHIFT, not the two-row group", DebindFrame:GetSelectionCount()))
        end

        DebindResultPanel:SelectRangeTo(heading, false)
        if DebindFrame:GetSelectionCount() ~= 2
                or not DebindFrame:IsActionSelected(b1) or not DebindFrame:IsActionSelected(b2) then
            return Fail(NAME, format("SHIFT on the heading of the picked group left %d picked", DebindFrame:GetSelectionCount()))
        end

        return Pass(NAME, "the group stayed picked")
    end,
})

RegisterTest("Left column: the layer list lights a linked action only where it draws it", {
    description = "An action linked from the left column locks its row's highlight in the layer list, lets go when unlinked, and lights nothing for an action that list does not draw",
    run = function()
        local NAME = "Linked highlight"

        local mine = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F5" })
        local InsertOffSpec = UseOffSpecLayer()
        local other = InsertOffSpec({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F6" })
        ApplyBindings()

        local realGetProfileLayer = DebindPrivate.GetProfileLayer
        DebindPrivate.GetProfileLayer = function(layerID)
            if layerID == DebindUI.GetLayerID() then
                return GetTestLayer()
            end
            return realGetProfileLayer(layerID)
        end
        AddTeardown(function() DebindPrivate.GetProfileLayer = realGetProfileLayer end)

        DebindFrame:Show()
        AddTeardown(function()
            DebindLayerPanel:SetLinkedAction(nil)
            DebindFrame:CloseWindow()
        end)
        DebindLayerPanel:Refresh(true)

        local line
        DebindLayerPanel.List.ContentArea.ScrollBox:ForEachFrame(function(frame)
            if frame:GetElementData().action == mine then
                line = frame
            end
        end)
        if not line then
            return Fail(NAME, "setup: the planted row is not in the layer list, is a search term or filter on")
        end

        DebindLayerPanel:SetLinkedAction(mine)
        if not line:IsHighlightLocked() then
            return Fail(NAME, "the drawn row is not lit")
        end
        DebindLayerPanel:SetLinkedAction(nil)
        if line:IsHighlightLocked() then
            return Fail(NAME, "the row stayed lit after the link went")
        end

        DebindLayerPanel:SetLinkedAction(other)
        local lit = 0
        DebindLayerPanel.List.ContentArea.ScrollBox:ForEachFrame(function(frame)
            if frame:IsHighlightLocked() then
                lit = lit + 1
            end
        end)
        if lit ~= 0 then
            return Fail(NAME, format("%d row(s) lit for an action this list does not draw", lit))
        end

        return Pass(NAME, "lit where drawn, dark after, dark for another layer's action")
    end,
})

RegisterTest("Move: a moved action is the same action, still picked", {
    description = "Moving a picked action to another layer puts that same table in the destination, and the selection still holds it",
    run = function()
        local NAME = "Move keeps the action"

        local mine = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F5" })
        UseOffSpecLayer()
        local destination = GetOffSpecLayer()
        ApplyBindings()

        -- `MoveAction` finds both layers by id, and the test layers' ids are in no profile.
        local realGetProfileLayer = DebindPrivate.GetProfileLayer
        DebindPrivate.GetProfileLayer = function(layerID)
            if layerID == GetTestLayer().layerID then
                return GetTestLayer()
            elseif layerID == destination.layerID then
                return destination
            end
            return realGetProfileLayer(layerID)
        end
        AddTeardown(function() DebindPrivate.GetProfileLayer = realGetProfileLayer end)

        OpenOverviewWithNothingPicked()
        DebindLayerPanel:ToggleActionSelected(mine)

        DebindUI.MoveActions({ mine }, destination.layerID, false)

        local layerID = DebindPrivate.FindLayerID(mine)
        if layerID ~= destination.layerID then
            return Fail(NAME, format("the picked table is in layer %s after the move, not the destination",
                tostring(layerID)))
        end
        if DebindFrame:GetSelectionCount() ~= 1 or not DebindFrame:IsActionSelected(mine) then
            return Fail(NAME, format("%d picked after the move", DebindFrame:GetSelectionCount()))
        end

        return Pass(NAME, "the same table moved and stayed picked")
    end,
})

RegisterTest("Move: a copy in its own layer goes to the back", {
    description = "Copying an action within its layer appends the copy after every action already there",
    run = function()
        local NAME = "Copy goes to the back"

        local first = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F5" })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F6" })
        local layer = GetTestLayer()
        ApplyBindings()

        local realGetProfileLayer = DebindPrivate.GetProfileLayer
        DebindPrivate.GetProfileLayer = function(layerID)
            if layerID == layer.layerID then
                return layer
            end
            return realGetProfileLayer(layerID)
        end
        AddTeardown(function() DebindPrivate.GetProfileLayer = realGetProfileLayer end)

        OpenOverviewWithNothingPicked()
        DebindUI.MoveActions({ first }, layer.layerID, true)

        local count = layer:GetNumActions()
        local last = layer:GetAction(count)
        if count ~= 3 or layer:GetAction(1) ~= first or layer:GetAction(2) ~= second then
            return Fail(NAME, format("%d actions, the first two not where they were", count))
        end
        if last == first or last.value ~= first.value then
            return Fail(NAME, "the last action is not the copy")
        end

        return Pass(NAME, "the copy stands after both")
    end,
})
