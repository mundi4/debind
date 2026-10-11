local _, Dev = ...

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local OVERVIEW_PANEL_ID = Dev.OVERVIEW_PANEL_ID
local SETTINGS_PANEL_ID = Dev.SETTINGS_PANEL_ID

-----------------------------------------------------------
-- The settings window
-----------------------------------------------------------

RegisterTest("Settings: the gear opens the settings tab", {
    description = "제목줄 톱니바퀴가 우리 창의 설정 탭을 연다",
    run = function()
        local NAME = "the gear"

        local frameWasShown = DebindFrame:IsShown()
        AddTeardown(function()
            DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
            if not frameWasShown and DebindFrame:IsShown() then
                DebindFrame:CloseWindow()
            end
        end)

        if not DebindFrame:IsShown() then
            DebindFrame:Show()
        end
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)

        -- **Its own script, the way a hand presses it.** Calling `SelectPanel` here would prove the
        -- function works and say nothing about the button being wired to it.
        local button = DebindFrame.OptionsButton
        local script = button:GetScript("OnMouseUp")
        if not script then
            return Fail(NAME, "the gear has no OnMouseUp, so the XML wiring is gone")
        end
        script(button, "LeftButton", true)

        local settings = DebindFrame:ResolvePanel(SETTINGS_PANEL_ID)
        if settings ~= DebindFrame.SettingsPanel then
            return Fail(NAME, format("tab %d is not the settings panel", SETTINGS_PANEL_ID))
        end
        if not settings:IsShown() then
            return Fail(NAME, "pressing the gear did not show the settings tab")
        end
        if DebindFrame.OverviewPanel:IsShown() then
            return Fail(NAME, "the overview is still showing beside the settings tab")
        end

        return Pass(NAME, "the settings tab is up")
    end,
})
