local _, Dev = ...

local LLL, DebindUI
Dev.OnDebindLoaded(function(private)
    LLL, DebindUI = private.L, private.DebindUI
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local WaitUntil = Dev.WaitUntil
local AddTeardown = Dev.AddTeardown
local PressEscape = Dev.PressEscape

RegisterTest("Overview: the question mark opens its page and wears the ring", {
    description = "The (?) on the portrait row opens the setting-keys-up page and closes it again, and it is lit for as long as the help window is up",
    run = function()
        local NAME = "Help portrait"

        DebindFrame:Show()
        AddTeardown(function() DebindFrame:CloseWindow() end)
        AddTeardown(function() DebindMessageFrame:Hide() end)
        DebindMessageFrame:Hide()

        local help = DebindFrame.OverviewPanel.PortraitRow.HelpPortrait
        if not help:IsVisible() then
            return Fail(NAME, "the (?) is not on screen with the window open")
        end
        if help.UnselectedFrame:IsShown() == false then
            return Fail(NAME, "the (?) is lit with no help window up")
        end

        help:Click()
        if not DebindMessageFrame:IsShown() then
            return Fail(NAME, "the press on the (?) opened no help")
        end
        if DebindMessageFrame.Dropdown:GetText() ~= LLL["HELP_SETTING_KEYS_UP_TITLE"] then
            return Fail(NAME, format("the help that opened is titled %q",
                tostring(DebindMessageFrame.Dropdown:GetText())))
        end
        if help.UnselectedFrame:IsShown() then
            return Fail(NAME, "the (?) is not lit while the help is up")
        end

        -- **The ring says the window, not the page.** Walking to another page through the dropdown
        -- never left it, so the light stays on.
        DebindUI.ShowHelp("switches")
        if help.UnselectedFrame:IsShown() then
            return Fail(NAME, "the (?) went out when the help moved to another page")
        end

        -- A press while another page is up swaps to this one rather than closing (`ToggleHelp`).
        help:Click()
        if not DebindMessageFrame:IsShown() then
            return Fail(NAME, "the press closed the help instead of coming back to its page")
        end
        if DebindMessageFrame.Dropdown:GetText() ~= LLL["HELP_SETTING_KEYS_UP_TITLE"] then
            return Fail(NAME, format("the press from another page landed on %q",
                tostring(DebindMessageFrame.Dropdown:GetText())))
        end

        help:Click()
        if DebindMessageFrame:IsShown() then
            return Fail(NAME, "a press on its own page left the help up")
        end
        if help.UnselectedFrame:IsShown() == false then
            return Fail(NAME, "the (?) stayed lit after the help closed")
        end

        return Pass(NAME, "the (?) opened its page, stayed lit across a page change, came back to it, and closed it")
    end,
})

RegisterTest("Help window: Back returns to the page and where it was scrolled", {
    description = "A link moves to another page, Back comes back to the first at the same scroll, and closing the window forgets the way back",
    run = function()
        local NAME = "Help Back"
        local frame = DebindMessageFrame

        -- Short enough that the targeting page scrolls in any locale, so a kept position is a
        -- number other than the top.
        local height = frame:GetHeight()
        frame:Hide()
        frame:SetHeight(260)
        AddTeardown(function()
            frame:Hide()
            frame:SetHeight(height)
        end)

        DebindUI.ShowHelp("targeting")
        if frame.BackButton:IsEnabled() then
            return Fail(NAME, "Back is pressable on the first page opened")
        end

        local scroll = frame.ScrollFrame
        local range = WaitUntil(function()
            scroll:UpdateScrollChildRect()
            return scroll:GetVerticalScrollRange() > 0 and scroll:GetVerticalScrollRange()
        end)
        if not range then
            return Fail(NAME, "the targeting page does not scroll even in a short window")
        end
        local kept = floor(range / 2)
        scroll:SetVerticalScroll(kept)

        frame:OnHyperlinkClick("debind:help:cast-options")
        if frame.topic ~= "cast-options" then
            return Fail(NAME, format("the link opened %s", tostring(frame.topic)))
        end
        if scroll:GetVerticalScroll() ~= 0 then
            return Fail(NAME, format("the page the link opened starts scrolled to %s", scroll:GetVerticalScroll()))
        end
        if not frame.BackButton:IsEnabled() then
            return Fail(NAME, "Back is locked after following a link")
        end

        frame.BackButton:Click()
        if frame.topic ~= "targeting" then
            return Fail(NAME, format("Back opened %s", tostring(frame.topic)))
        end
        if abs(scroll:GetVerticalScroll() - kept) > 1 then
            return Fail(NAME, format("Back came back scrolled to %s, not %s", scroll:GetVerticalScroll(), kept))
        end
        if frame.BackButton:IsEnabled() then
            return Fail(NAME, "Back is still pressable with nothing left to go back to")
        end

        frame:OnHyperlinkClick("debind:help:cast-options")
        frame:Hide()
        DebindUI.ShowHelp("ordering")
        if frame.BackButton:IsEnabled() then
            return Fail(NAME, "a page opened after closing the window can go back into the last visit")
        end

        return Pass(NAME, "a link, Back to the same scroll, and a fresh start after closing")
    end,
})

RegisterTest("Help window: ESC closes the help and leaves the main window up", {
    description = "With the help over the main window, one ESC takes only the help down; the next one closes the main window",
    run = function()
        local NAME = "Help escape"

        -- 앞 케이스의 teardown이 남긴 `closeAt`과 프레임을 나눈다 (`PressEscape`).
        coroutine.yield(0)

        DebindFrame:Show()
        AddTeardown(function() DebindFrame:CloseWindow() end)
        AddTeardown(function() DebindMessageFrame:Hide() end)

        DebindUI.ShowHelp("ordering")
        if not DebindMessageFrame:IsShown() then
            return Fail(NAME, "the help did not open")
        end

        PressEscape()
        if DebindMessageFrame:IsShown() then
            return Fail(NAME, "the first ESC left the help up")
        end
        if not DebindFrame:IsShown() then
            return Fail(NAME, "the ESC that closed the help took the main window with it")
        end

        PressEscape()
        if DebindFrame:IsShown() then
            return Fail(NAME, "the second ESC did not close the main window")
        end

        return Pass(NAME, "help first, then the main window")
    end,
})
