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

-----------------------------------------------------------
-- Test Cases: The spell picker's two modes and its own button
--
-- **None of this is reachable headless.** `SpellPicker.lua` and the icon selector are not in
-- `tests/run.lua`'s load list: every one of these questions is about a frame - which layer a popup
-- three windows deep finally inserts into, and what the window does to a button in the one under it.
-----------------------------------------------------------

RegisterTest("Spell picker: where a new custom macro lands", {
    description = "Left click puts the new macro in the open tab; a tab named on the right-click menu gets it instead",
    run = function()
        local NAME = "New macro destination"

        DebindFrame:Show()
        AddTeardown(function()
            DebindIconSelectorFrame:Hide()
            DebindMacroFrame:Hide()
            DebindSpellPickerFrame:Hide()
            DebindFrame:CloseWindow()
        end)

        local openLayerID = DebindUI.GetLayerID()
        local destLayerID
        for _, tabInfo in ipairs(DebindPrivate.ActionMenu.GetTabList()) do
            if tabInfo.layerID ~= openLayerID then
                destLayerID = tabInfo.layerID
                break
            end
        end
        if not destLayerID then
            return Fail(NAME, "setup: only one layer in the tab list, so there is no other tab to name")
        end

        -- **두 목적지를 다 시험용 레이어로 돌린다.** 이 길은 진짜 `Insert`까지 가므로, 안 돌리면
        -- 매크로 둘이 사용자 프로필에 남는다.
        UseOffSpecLayer()
        local named = GetOffSpecLayer()
        local open = GetTestLayer()
        local realGetProfileLayer = DebindPrivate.GetProfileLayer
        DebindPrivate.GetProfileLayer = function(layerID)
            if layerID == openLayerID then
                return open
            elseif layerID == destLayerID then
                return named
            end
            return realGetProfileLayer(layerID)
        end
        AddTeardown(function() DebindPrivate.GetProfileLayer = realGetProfileLayer end)

        -- **본문 편집기까지 간다.** 그 이어붙임은 버튼이 주는 콜백이고(`InitializeNewMacroButton`),
        -- 탭을 지목한 쪽만 `AddNewAction`이 창을 건너뛰게 만들어 그 콜백을 잃을 수 있다.
        local opened
        local function MakeMacro(name, layerID)
            opened = nil
            DebindIconSelectorFrame:OpenForNewMacro(function(elementData)
                opened = elementData
                DebindMacroFrame:Open(elementData.action)
            end, layerID)
            if not DebindIconSelectorFrame:IsShown() then
                return "the icon selector did not open"
            end
            DebindIconSelectorFrame.BorderBox.IconSelectorEditBox:SetText(name)
            DebindIconSelectorFrame:OkayButton_OnClick()
            return nil
        end

        local function Holds(layer, name)
            for _, action in ipairs(layer.actions) do
                if action.name == name then
                    return true
                end
            end
            return false
        end

        -- **열린 탭 쪽을 먼저 한다.** 탭을 이름으로 부르면 창이 그 탭으로 건너가므로
        -- (`AddNewAction`의 `GoToAction`), 순서를 바꾸면 "열린 탭"이 이미 목적지 탭이다.
        local err = MakeMacro("Picker open tab", nil)
        if err then
            return Fail(NAME, "setup: " .. err)
        end
        if not Holds(open, "Picker open tab") then
            return Fail(NAME, "left click did not put the macro in the open tab's layer")
        end
        if Holds(named, "Picker open tab") then
            return Fail(NAME, "left click put the macro in the other tab")
        end
        if not opened or not DebindMacroFrame:IsShown() then
            return Fail(NAME, "the body editor did not follow the open tab's macro")
        end

        err = MakeMacro("Picker named tab", destLayerID)
        if err then
            return Fail(NAME, "setup: " .. err)
        end
        if not Holds(named, "Picker named tab") then
            return Fail(NAME, "the named tab's layer did not get the macro")
        end
        if Holds(open, "Picker named tab") then
            return Fail(NAME, "naming a tab still put the macro in the tab that was open")
        end
        if not opened or not DebindMacroFrame:IsShown() then
            return Fail(NAME, "naming a tab left the macro without its body editor")
        end

        return Pass(NAME, "left click landed in the open tab, the named tab got its own, and both reached the editor")
    end,
})

-- `handing-the-rest-of-a-key-to-the-game.md` §8-5 S3, S4. **Needs the game**: the window is a frame
-- of its own (`DebindTailNotice`), and what is measured is that it stands on screen.
RegisterTest("S3 S4 adding a command or giveback opens its notice until the box is ticked", {
    description = "Adding either type shows the notice each time; once [Don't show this again] is ticked it does not, and a spell never does",
    run = function()
        local NAME = "Tail notice"
        local HelpTip = DebindPrivate.HelpTip
        local SEEN_KEY = "tailNotice"

        if InCombatLockdown() then
            return Fail(NAME, "adding an action rebuilds, which is blocked in combat")
        end

        DebindFrame:Show()
        AddTeardown(function()
            StaticPopupSpecial_Hide(DebindTailNotice)
            DebindFrame:CloseWindow()
        end)

        -- `AddNewAction` inserts into the open tab's layer; the run's own takes it instead.
        local openLayerID = DebindUI.GetLayerID()
        local realGetProfileLayer = DebindPrivate.GetProfileLayer
        DebindPrivate.GetProfileLayer = function(layerID)
            if layerID == openLayerID then
                return GetTestLayer()
            end
            return realGetProfileLayer(layerID)
        end
        AddTeardown(function() DebindPrivate.GetProfileLayer = realGetProfileLayer end)

        local wasSeen = HelpTip.WasSeen(SEEN_KEY)
        HelpTip.ForgetSeen(SEEN_KEY)
        AddTeardown(function()
            if wasSeen then
                HelpTip.MarkSeen(SEEN_KEY)
            else
                HelpTip.ForgetSeen(SEEN_KEY)
            end
        end)

        DebindFrame:AddNewAction(Constants.SPELL, 585)
        if DebindTailNotice:IsShown() then
            return Fail(NAME, "adding a spell opened the notice")
        end

        DebindFrame:AddNewAction(Constants.GIVEBACK)
        if not DebindTailNotice:IsShown() then
            return Fail(NAME, "S3: adding a giveback did not open the notice")
        end
        DebindTailNotice.OkayButton:Click()
        if DebindTailNotice:IsShown() then
            return Fail(NAME, "[Okay] left the notice open")
        end

        -- **Okay alone is not "don't show again".** The next one opens it once more.
        DebindFrame:AddNewAction(Constants.COMMAND, "JUMP")
        if not DebindTailNotice:IsShown() then
            return Fail(NAME, "S3: adding a command after [Okay] alone did not open the notice")
        end
        if DebindTailNotice.HidePopupCheckbox.Checkbox:GetChecked() then
            return Fail(NAME, "the box opened ticked")
        end
        DebindTailNotice.HidePopupCheckbox.Checkbox:Click()
        DebindTailNotice.OkayButton:Click()

        DebindFrame:AddNewAction(Constants.GIVEBACK)
        if DebindTailNotice:IsShown() then
            return Fail(NAME, "S4: the notice opened after the box was ticked")
        end

        return Pass(NAME, "a spell: none; giveback: opened; command after Okay: opened; after the box: none")
    end,
})

RegisterTest("Spell picker: [+] while replacing", {
    description = "Replace mode leaves [+] plain, and pressing it returns to add mode instead of closing the window",
    run = function()
        local NAME = "Picker replace mode"

        DebindFrame:Show()
        AddTeardown(function()
            DebindSpellPickerFrame:Hide()
            DebindFrame:CloseWindow()
        end)

        local action = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F6" })
        local addPortrait = DebindFrame.OverviewPanel.PortraitRow.AddPortrait

        -- **`Show`가 `OnShow`를 지나야 모드가 버튼에 반영된다.** 앞 테스트가 두고 간 창이 이미
        -- 서 있으면 `Show`는 아무 일도 안 하고, 읽는 것은 그때의 표시가 된다.
        DebindSpellPickerFrame:Hide()
        DebindSpellPickerFrame:Show()
        -- 눌린 표시는 테두리의 채도로 그린다(`DebindPortraitMixin:SetSelectedState`). 상태를
        -- 따로 들고 있지 않으므로 그려진 것을 읽는다.
        if addPortrait.UnselectedFrame:IsShown() then
            return Fail(NAME, "setup: add mode left [+] plain")
        end

        DebindSpellPickerFrame:BeginReplace({ action })
        if not addPortrait.UnselectedFrame:IsShown() then
            return Fail(NAME, "[+] is still lit while replacing, which says this window came from it")
        end
        if DebindSpellPickerFrame.NewMacroButton:IsEnabled() then
            return Fail(NAME, "[New Custom Macro] is still live while replacing")
        end

        DebindSpellPickerFrame:Toggle()
        if not DebindSpellPickerFrame:IsShown() then
            return Fail(NAME, "[+] closed the window instead of taking it back to add mode")
        end
        if DebindSpellPickerFrame.replaceTargets then
            return Fail(NAME, "the window stayed in replace mode")
        end
        if addPortrait.UnselectedFrame:IsShown() then
            return Fail(NAME, "[+] is plain although the window is back in add mode")
        end

        DebindSpellPickerFrame:Toggle()
        if DebindSpellPickerFrame:IsShown() then
            return Fail(NAME, "the second press did not close the window")
        end
        if not addPortrait.UnselectedFrame:IsShown() then
            return Fail(NAME, "[+] stayed lit after the window closed")
        end

        return Pass(NAME, "[+] was plain while replacing, took the window back to add mode, then closed it")
    end,
})
