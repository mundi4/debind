local _, Dev = ...

local Constants, LLL
Dev.OnDebindLoaded(function(private)
    Constants, LLL = private.Constants, private.L
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local PressEscape = Dev.PressEscape
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local TypeInto = Dev.TypeInto

-----------------------------------------------------------
-- Test Cases: The macro editor commits by closing and by nothing else
--
-- **The one rule this window has**, and the only layer that can see it: the body reaches the
-- profile when the window hides, from every path that hides it, and no path writes it while the
-- window is up. Everything else here hangs off that -- [Cancel] can promise to put the body back
-- only because nothing moved it, and there is no [Save] because a button saying so would describe
-- the opposite of what happens.
--
-- Nothing below reads the field it is about to assert on. What it checks is `action.value`, which
-- is what the profile keeps and what the next build reads.
-----------------------------------------------------------
-- **Commented out with its only caller**, the popup-order test below.
--- What is drawn over what. These two are all the game answers with, so the order is measured with
--- them: what `toplevel` does in the end is raise the second of them within one layer.
-- local STRATA_RANK = {
--     BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
--     DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
-- }
--
-- local function DrawsAbove(a, b)
--     local ra = STRATA_RANK[a:GetFrameStrata()]
--     local rb = STRATA_RANK[b:GetFrameStrata()]
--     if ra ~= rb then
--         return ra > rb
--     end
--     return a:GetFrameLevel() > b:GetFrameLevel()
-- end

--- Shows the window, plants one macrotext action and opens the editor on it. Putting things back is
--- the runner's job.
---
--- **An icon goes in.** An action with no icon is a shape this addon cannot make ([New Custom
--- Macro] goes through the icon selector), and on one of those the name/icon popup opens blank.
local function OpenMacroEditor(body, cancelFunc)
    DebindFrame:Show()
    AddTeardown(function()
        DebindIconSelectorFrame:Hide()
        DebindMacroFrame:Hide()
        DebindFrame:CloseWindow()
    end)

    local action = InsertAction({ type = Constants.MACROTEXT, value = body,
        name = "Macro editor test", icon = 134400, key = "CTRL-ALT-F11" })
    ApplyBindings()

    DebindMacroFrame:Open(action, cancelFunc)
    return action, DebindMacroFrame.Editor.ScrollFrame.EditBox
end

--- **What this test protects is edit mode, not the icon list.**
---
--- Blizzard's `IconDataProvider` has the file-local `BaseIconFilenames` **built by whoever uses it
--- first and released by whoever puts it down last.** Stepping into that place makes Debind the
--- owner of that variable, and edit mode reads its value on the way in to pull a sample aura icon
--- (`GetSampleAuraIcon` -> `GetNumIcons` in `EditModeAuraDataProvider.lua`). That single read taints
--- the whole execution that enters edit mode, and the same execution goes on to update the party
--- health bars and is stopped at a secret comparison. In a session that had opened the name/icon
--- window once, the party health bars died every time edit mode was entered.
---
--- **That symptom is not something even an in-game test can measure**: taint is invisible from Lua,
--- and a test cannot press its way into edit mode. So what is measured is the **structure** that
--- produces the cause. It fails if our provider is Blizzard's own.
RegisterTest("Icon picker: the icon list is ours, not Blizzard's shared one", {
    description = "We neither create nor release Blizzard's shared IconDataProvider",
    run = function()
        local NAME = "Icon provider"

        DebindFrame:Show()
        AddTeardown(function()
            DebindIconSelectorFrame:Hide()
            DebindFrame:CloseWindow()
        end)

        local provider = DebindFrame:RefreshIconDataProvider()
        if not provider then
            return Fail(NAME, "no provider")
        end

        -- Both the side that builds the list and the side that releases it have to be ours.
        if provider.GetNumIcons == IconDataProviderMixin.GetNumIcons then
            return Fail(NAME, "GetNumIcons is Blizzard's, it reads the shared BaseIconFilenames")
        end
        if provider.Release == IconDataProviderMixin.Release then
            return Fail(NAME, "Release is Blizzard's, it releases the shared BaseIconFilenames")
        end

        -- And the list still has to stand: one question mark, the spell book, and the base list.
        local numIcons = provider:GetNumIcons()
        if numIcons < 2 then
            return Fail(NAME, format("only %d icons, the list was never filled", numIcons))
        end

        local questionMark = provider:GetIconByIndex(1)
        if questionMark ~= [[INTERFACE\ICONS\INV_MISC_QUESTIONMARK]] then
            return Fail(NAME, format("slot 1 is not the question mark: %s", tostring(questionMark)))
        end

        -- A real icon has to come back for every slot including the last. Set the boundary wrong and
        -- this is where nil appears.
        local last = provider:GetIconByIndex(numIcons)
        if last == nil then
            return Fail(NAME, format("the last slot (%d) is empty, the per-type list boundary is out of step", numIcons))
        end

        -- Getting it back. The same icon can appear more than once, so this compares icons rather
        -- than indices.
        local found = provider:GetIndexOfIcon(last)
        if not found or provider:GetIconByIndex(found) ~= last then
            return Fail(NAME, format("GetIndexOfIcon cannot find %s", tostring(last)))
        end

        return Pass(NAME, format("our provider, %d icons", numIcons))
    end,
})

RegisterTest("Macro editor: the body reaches the profile when the window closes", {
    description = "Closing is what saves; a trip through the name/icon popup does not",
    run = function()
        local NAME = "Macro commit"

        local action, box = OpenMacroEditor("/say one")
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "it did not open")
        end
        if box:GetText() ~= "/say one" then
            return Fail(NAME, format("the body did not come up: %q", box:GetText()))
        end

        if not TypeInto(box, "/say two") then
            return Fail(NAME, "the edit box has no OnTextChanged on it")
        end
        if action.value ~= "/say one" then
            return Fail(NAME, "it saved while typing, the profile moved with the window still open")
        end

        -- A trip out to the name/icon editor and back. The default macro window saves at this point
        -- and we do not: saving would push the place [Cancel] returns to along, over an outing that
        -- never touched the body.
        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the name/icon popup did not open")
        end
        if action.value ~= "/say one" then
            return Fail(NAME, format("opening the popup saved: %q", action.value))
        end

        DebindIconSelectorFrame:Close(true)
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "the popup closing took the editor with it")
        end
        if box:GetText() ~= "/say two" then
            return Fail(NAME, format("the body changed while we were away: %q", box:GetText()))
        end

        -- [Close]. This button does nothing but close the window, and the closing is what saves.
        DebindMacroFrame.Editor.CloseButton:Click()
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "pressed [Close] and it did not close")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("it closed and nothing was saved: %q", action.value))
        end

        return Pass(NAME, "the trip to the popup wrote nothing, the closing wrote")
    end,
})

RegisterTest("Macro editor: [Revert] lights up only when there is something to put back", {
    description = "Dark while nothing has been edited, and pressing it restores the box alone without moving the profile",
    run = function()
        local NAME = "Macro revert"

        local action, box = OpenMacroEditor("/say one")
        local button = DebindMacroFrame.Editor.RevertButton

        if button:IsEnabled() then
            return Fail(NAME, "just opened and it says there is something to put back")
        end
        if button:GetText() ~= LLL["MACROFRAME_REVERT"] then
            return Fail(NAME, format("the label is not [Revert]: %q", tostring(button:GetText())))
        end

        if not TypeInto(box, "/say two") then
            return Fail(NAME, "the edit box has no OnTextChanged on it")
        end
        if not button:IsEnabled() then
            return Fail(NAME, "the body was edited and the button is dark")
        end

        button:Click()

        if box:GetText() ~= "/say one" then
            return Fail(NAME, format("the edit box did not come back: %q", box:GetText()))
        end
        if action.value ~= "/say one" then
            return Fail(NAME, format("the profile moved: %q", action.value))
        end
        if button:IsEnabled() then
            return Fail(NAME, "the button is still lit after putting it back")
        end
        -- **It does not close.** The restored body has to be there to be edited again.
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "[Revert] closed the window too")
        end

        return Pass(NAME, "dark -> lit -> put back and dark again")
    end,
})

RegisterTest("Macro editor: [Cancel] gives the conversion its action back", {
    description = "Opened by a conversion, the label reads [Cancel] and pressing it runs the function that undoes it",
    run = function()
        local NAME = "Macro conversion cancel"

        local reverted = false
        local action, box = OpenMacroEditor("/cast Fireball", function() reverted = true end)
        local button = DebindMacroFrame.Editor.RevertButton

        if button:GetText() ~= LLL["MACROFRAME_CANCEL"] then
            return Fail(NAME, format("the label is not [Cancel]: %q", tostring(button:GetText())))
        end
        -- What there is to revert is a conversion that already happened, so it has to be lit even
        -- with nothing typed.
        if not button:IsEnabled() then
            return Fail(NAME, "opened by a conversion and the button is dark")
        end
        if not DebindMacroFrame.macroCancelFunc then
            return Fail(NAME, "no cancelFunc on it, did Refresh clear it with nobody putting it back")
        end

        TypeInto(box, "/cast Frostbolt")
        button:Click()

        if not reverted then
            return Fail(NAME, "pressed it and the function that puts it back never ran")
        end
        -- The body just thrown away must not be saved back over the reverted action.
        if action.value ~= "/cast Fireball" then
            return Fail(NAME, format("the body that was thrown away got saved: %q", action.value))
        end

        return Pass(NAME, "[Cancel] stood, pressing it put things back, and the body did not leak")
    end,
})

RegisterTest("Macro editor: ESC steps out of the popup, then the editor, then the window", {
    description = "One ESC steps back one place, and the ESC that closes the editor leaves the body behind",
    run = function()
        local NAME = "Macro escape"

        local action, box = OpenMacroEditor("/say one")

        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the name/icon popup did not open")
        end

        PressEscape()
        if DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the first ESC did not close the popup")
        end
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "the first ESC took the editor with it")
        end

        TypeInto(box, "/say two")
        PressEscape()
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "the second ESC did not close the editor")
        end
        if not DebindFrame:IsShown() then
            return Fail(NAME, "the second ESC closed the main window too, is this rung missing from the ladder")
        end
        -- Closing is what saves. Leaving by ESC still leaves the body behind.
        if action.value ~= "/say two" then
            return Fail(NAME, format("closed by ESC and the body was not kept: %q", action.value))
        end

        PressEscape()
        if DebindFrame:IsShown() then
            return Fail(NAME, "the third ESC did not close the main window")
        end

        return Pass(NAME, "popup -> editor -> main window, and the body was kept")
    end,
})

-- **Commented out: the two frames sit on one layer on purpose now, so there is no order to
-- assert.** The test read a strict "the popup draws above the editor", which was true while the
-- popup was raised over it; with both on MEDIUM the answer is a tie and the assertion cannot
-- hold. Kept rather than deleted because the question comes back the moment either frame is
-- given a strata of its own.
-- RegisterTest("Macro editor: the name/icon popup stays over the editor", {
--     description = "Raising the editor to the front does not put the popup above it behind",
--     run = function()
--         local NAME = "Macro popup order"
--
--         OpenMacroEditor("/say one")
--         DebindMacroFrame:EditNameIcon_OnClick()
--         if not DebindIconSelectorFrame:IsShown() then
--             return Fail(NAME, "the name/icon popup did not open")
--         end
--
--         local function Where()
--             return format("%s/%d vs %s/%d",
--                 DebindIconSelectorFrame:GetFrameStrata(), DebindIconSelectorFrame:GetFrameLevel(),
--                 DebindMacroFrame:GetFrameStrata(), DebindMacroFrame:GetFrameLevel())
--         end
--
--         if not DrawsAbove(DebindIconSelectorFrame, DebindMacroFrame) then
--             return Fail(NAME, format("it is underneath as soon as it opens: %s", Where()))
--         end
--
--         -- What happens when the editor is clicked. With the two on one layer, this single line is
--         -- what turns the order around.
--         DebindMacroFrame:Raise()
--
--         if not DrawsAbove(DebindIconSelectorFrame, DebindMacroFrame) then
--             return Fail(NAME, format("raising the editor put the popup behind: %s", Where()))
--         end
--
--         return Pass(NAME, Where())
--     end,
-- })

-- **The filter takes the row out of the set, and a selection that changed closes the windows
-- standing on an action** (`PruneSelectionToBinFilter` -> `CommitSelection`). The rebuild itself
-- closes nothing over an undrawn row, which is why the trigger is the set and not the drawing
-- (`closing-the-windows-that-stand-on-an-action.md`).
RegisterTest("Macro editor: a row filtered out of the bin takes its editor with it", {
    description = "A row filtered out by the search closes its editor, and the body is saved",
    run = function()
        local NAME = "Macro filtered out"

        local action, box = OpenMacroEditor("/say one")
        local searchBox = DebindFrame.OverviewPanel.SearchBox
        -- The script runs here too. Without it, a search term survives the day this fails partway
        -- through and every test after it looks into an empty bin.
        AddTeardown(function() TypeInto(searchBox, "") end)

        TypeInto(box, "/say two")

        -- Text that cannot collide with this action's name. The search filters on the name.
        if not TypeInto(searchBox, "qqzzxx") then
            return Fail(NAME, "the search box has no OnTextChanged on it")
        end

        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "the row was filtered out and the editor is still there")
        end
        if not DebindFrame:IsShown() then
            return Fail(NAME, "the main window closed too")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("it closed and nothing was saved: %q", action.value))
        end

        -- Clearing the search brings the row back. It does not bring the editor back: opening that
        -- is the user's move.
        TypeInto(searchBox, "")
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "clearing the search opened the editor again on its own")
        end

        return Pass(NAME, "closed as it was filtered out, the body was saved, and it did not come back on its own")
    end,
})

RegisterTest("Macro editor: opening the spell picker closes it", {
    description = "The spell picker opening closes the editor and popup that would sit under it first",
    run = function()
        local NAME = "Macro picker"

        local action, box = OpenMacroEditor("/say one")
        AddTeardown(function() DebindSpellPickerFrame:Hide() end)

        DebindMacroFrame:EditNameIcon_OnClick()
        TypeInto(box, "/say two")

        DebindSpellPickerFrame:Show()

        if DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the name/icon popup is still there")
        end
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "the editor is still there, the spell picker sits on top of it")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("it closed and nothing was saved: %q", action.value))
        end

        return Pass(NAME, "both closed and the body was kept")
    end,
})
