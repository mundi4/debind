local _, Dev = ...

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local PressEscape = Dev.PressEscape
local STORAGE_PANEL_ID = Dev.STORAGE_PANEL_ID
local OVERVIEW_PANEL_ID = Dev.OVERVIEW_PANEL_ID

--- **One press is one rung, and everything registered in `UISpecialFrames` goes down together.**
--- The window and the sharing dialogs are all in that table, so the sweep behind one ESCAPE hides
--- them all at once; what puts the rest back and closes exactly one is the pair
--- `DebindDialogMixin:OnDialogHide` and `DebindFrameMixin:OnHide`. Break either and one press takes
--- the dialog and the window together, or leaves a dialog standing over nothing.
---
--- The order is the half that cannot be read off one dialog: both can stand at once, since the copy
--- dialog outlives the tab it came from on purpose (`DebindStoragePanelMixin:OnHide`).
---
--- **There were three.** The bring dialog asked which layers to take, and went with the question
--- when the tick moved onto the action (section 12 of `building-export-import.md`).
---
--- `PressEscape` is why this is not a real key press; its comment carries that.
RegisterTest("Escape: the sharing dialogs close before the window", {
    description = "With a sharing dialog up, ESC closes that first and one at a time, rather than the window",
    run = function()
        local NAME = "Escape ladder"

        -- 앞 케이스의 teardown이 남긴 `closeAt`과 프레임을 나눈다 (`PressEscape`).
        coroutine.yield(0)

        DebindFrame:Show()
        AddTeardown(function()
            DebindCopyFrame.Output.EditBox:ClearFocus()
            DebindPasteFrame.Input.EditBox:ClearFocus()
            DebindAddFrame:CloseDialog()
            DebindPasteFrame:CloseDialog()
            DebindCopyFrame:CloseDialog()
            DebindFrame:CloseWindow()
        end)

        -- All three are stood up. **The add dialog is a top-level frame**, so a missing rung does
        -- not just take two at once: the window goes and the dialog stays up over nothing.
        DebindCopyFrame:ShowText("DEBIND-TEST")
        DebindPasteFrame:Open()
        DebindAddFrame:Open({ fromClique = true, hasSpecs = true })

        local steps = {
            { frame = DebindAddFrame,   name = "the add dialog" },
            { frame = DebindPasteFrame, name = "the paste dialog" },
            { frame = DebindCopyFrame,  name = "the copy dialog" },
        }
        for _, step in ipairs(steps) do
            if not step.frame:IsShown() then
                return Fail(NAME, format("could not even stand %s up", step.name))
            end
        end

        for i, step in ipairs(steps) do
            PressEscape()
            if step.frame:IsShown() then
                return Fail(NAME, format("ESC number %d did not close %s", i, step.name))
            end
            -- **The window closing here is the bug this test holds off.** The dialog would be left
            -- standing with nothing under it.
            if not DebindFrame:IsShown() then
                return Fail(NAME, format("the ESC that should have closed %s closed the window", step.name))
            end
            -- One rung at a time. Taking one whose turn has not come yet makes a single press remove two.
            for j = i + 1, #steps do
                if not steps[j].frame:IsShown() then
                    return Fail(NAME, format("the ESC that closes %s took %s with it", step.name, steps[j].name))
                end
            end
        end

        -- And the window closes only **after** every dialog is gone. Without this line, the pass above
        -- is explained just as well by "ESC does nothing".
        PressEscape()
        if DebindFrame:IsShown() then
            return Fail(NAME, "every dialog has closed and the window does not close on ESC")
        end

        return Pass(NAME, "stepped back one at a time: add, paste, copy, then the window")
    end,
})

--- **Being in `UISpecialFrames` costs the window every close it did not ask for.** That table is
--- not an ESCAPE-only net: `ShowUIPanel` goes through `CloseWindows` too, so opening the spellbook
--- with P sweeps this window out -- and the spellbook is the very thing a reader opens to drag a
--- spell in here. What holds that off is `DebindFrameMixin:OnHide` recognising an unmarked close
--- and putting the window straight back.
---
--- **The sweep, not `ShowUIPanel`.** Opening a real panel would measure the panel manager and take
--- whatever else the reader had up; the bare `Hide` is the one thing `CloseSpecialWindows` does to
--- this frame.
---
--- Both halves are here because either alone passes for the wrong reason: a window that comes back
--- from everything can never be closed, and one that stays down is the bug.
RegisterTest("Escape: a close the window did not ask for is undone", {
    description = "Opening a panel sweeps UISpecialFrames; the window comes back, and its own close still closes",
    run = function()
        local NAME = "Foreign close"

        -- 앞 케이스의 teardown이 남긴 `closeAt`과 프레임을 나눈다 (`PressEscape`).
        coroutine.yield(0)

        DebindFrame:Show()
        AddTeardown(function()
            DebindPasteFrame:CloseDialog()
            DebindFrame:CloseWindow()
        end)

        -- **What the sweep must not take with it.** Every descendant's `OnHide` fires on it, so any
        -- of them treating "hidden" as "the reader left" loses something for a keypress that was
        -- meant for the spellbook. Bind mode did (and `SetBindingMode(false)` is the commit path,
        -- so its undo list went too); the paste box did; the list scroll did.
        DebindFrame:ToggleBindMode()
        AddTeardown(function() DebindFrame:SetBindingMode(false) end)

        DebindFrame:Hide()
        if not DebindFrame:IsCapturingKey() then
            return Fail(NAME, "the sweep ended bind mode, which throws away its undo list")
        end

        if not DebindFrame:IsShown() then
            return Fail(NAME, "swept out by somebody else's CloseSpecialWindows and stayed down")
        end

        -- **A dialog is swept by the same call and comes back the same way**, and what it has to
        -- bring back with it is what the reader typed: the reset moved to `Open` for this
        -- (`DebindPasteFrameMixin:Open`).
        DebindPasteFrame:Open()
        DebindPasteFrame.Input.EditBox:SetText("DEBIND-TEST")
        DebindPasteFrame:Hide()
        if not DebindPasteFrame:IsShown() then
            return Fail(NAME, "the paste dialog was swept out and stayed down")
        end
        if DebindPasteFrame.Input.EditBox:GetText() ~= "DEBIND-TEST" then
            return Fail(NAME, "the paste dialog came back empty, so a sweep throws away what was typed")
        end
        -- **The tab it belongs to is a second way to lose it.** `DebindStoragePanelMixin:OnHide`
        -- drops the paste box, and that script runs for a sweep as well, so the drop had to move
        -- to the two moments that mean it. Leaving the tab is one of them; this checks the other
        -- side of that move.
        DebindFrame:SelectPanel(STORAGE_PANEL_ID)
        AddTeardown(function() DebindFrame:SelectPanel(OVERVIEW_PANEL_ID) end)
        DebindFrame:Hide()
        if DebindPasteFrame.Input.EditBox:GetText() ~= "DEBIND-TEST" then
            return Fail(NAME, "a sweep with the Sharing tab up threw away what was typed")
        end

        -- The add dialog belongs to the tab the same way, and a sweep brings it back the same way.
        DebindAddFrame:Open({ fromClique = false })
        AddTeardown(function() DebindAddFrame:CloseDialog() end)
        DebindAddFrame:Hide()
        if not DebindAddFrame:IsShown() then
            return Fail(NAME, "the add dialog was swept out and stayed down")
        end

        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
        if DebindPasteFrame:IsShown() then
            return Fail(NAME, "leaving the tab left the paste box up")
        end
        if DebindAddFrame:IsShown() then
            return Fail(NAME, "leaving the tab left the add dialog up")
        end

        DebindPasteFrame.Input.EditBox:ClearFocus()
        DebindPasteFrame:CloseDialog()
        if DebindPasteFrame:IsShown() then
            return Fail(NAME, "the dialog's own close did not close it")
        end

        DebindFrame:CloseWindow()
        if DebindFrame:IsShown() then
            return Fail(NAME, "the window's own close did not close it")
        end

        return Pass(NAME, "somebody else's close is undone, our own close stands")
    end,
})
