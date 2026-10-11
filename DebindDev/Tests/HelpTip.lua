local _, Dev = ...

local DebindPrivate
Dev.OnDebindLoaded(function(private)
    DebindPrivate = private
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown

-----------------------------------------------------------
-- Test Cases: Our own help tip
--
-- **The client's `HelpTip` is not called and must not be** (`Debind/Help/HelpTip.lua`): one frame pool
-- for the whole game, so taking a frame out of it from here taints what the action bar reads. That
-- is why there is a copy at all, and none of it runs without frames.
-----------------------------------------------------------

RegisterTest("Help tip: closed once, gone for good", {
    description = "The balloon on the title bar gear stands on open, and closing it is remembered in the profile",
    run = function()
        local NAME = "Settings tip"

        local HelpTip = DebindPrivate.HelpTip
        local SEEN_KEY = "settingsGear"

        local wasSeen = HelpTip.WasSeen(SEEN_KEY)
        AddTeardown(function()
            HelpTip.HideAll()
            if wasSeen then
                HelpTip.MarkSeen(SEEN_KEY)
            else
                HelpTip.ForgetSeen(SEEN_KEY)
            end
            DebindFrame:CloseWindow()
        end)

        HelpTip.ForgetSeen(SEEN_KEY)
        HelpTip.HideAll()

        -- 말풍선은 `OnShow`가 세운다. 앞 테스트가 두고 간 창이 서 있으면 `Show`가 그 자리를
        -- 안 지난다.
        DebindFrame:CloseWindow()
        DebindFrame:Show()
        local gear = DebindFrame.OptionsButton
        if not HelpTip.IsShowing(gear) then
            return Fail(NAME, "opening the window did not raise the balloon on the gear")
        end

        -- 창을 닫았다 여는 것은 읽은 것이 아니다. 같이 내려간 안내는 다시 서야 한다.
        DebindFrame:CloseWindow()
        DebindFrame:Show()
        if not HelpTip.IsShowing(gear) then
            return Fail(NAME, "the balloon did not come back after a close nobody answered")
        end

        if HelpTip.WasSeen(SEEN_KEY) then
            return Fail(NAME, "closing the window counted as having read it")
        end

        -- [알겠습니다]. 버튼의 `OnClick`이 부르는 것과 같은 자리다.
        HelpTip.Acknowledge(gear)
        if not HelpTip.WasSeen(SEEN_KEY) then
            return Fail(NAME, "[Got It] did not record anything")
        end
        if HelpTip.IsShowing(gear) then
            return Fail(NAME, "[Got It] left the balloon standing")
        end

        DebindFrame:CloseWindow()
        DebindFrame:Show()
        if HelpTip.IsShowing(gear) then
            return Fail(NAME, "the balloon came back after it had been closed for good")
        end

        return Pass(NAME, "it stood until answered, survived a close, and stayed away once answered")
    end,
})
