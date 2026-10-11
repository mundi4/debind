local _, Dev = ...

local DebindPrivate, Constants, LLL, DebindUI
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants, LLL, DebindUI = private, private.Constants, private.L, private.DebindUI
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local GetTestLayer = Dev.GetTestLayer
local InsertAction = Dev.InsertAction
local CleanupActions = Dev.CleanupActions
local ApplyBindings = Dev.ApplyBindings
local KeyMapOrder = Dev.KeyMapOrder
local STORAGE_PANEL_ID = Dev.STORAGE_PANEL_ID
local OVERVIEW_PANEL_ID = Dev.OVERVIEW_PANEL_ID
local SWITCHES_PANEL_ID = Dev.SWITCHES_PANEL_ID
local SETTINGS_PANEL_ID = Dev.SETTINGS_PANEL_ID

-----------------------------------------------------------
-- Test Cases: The window's three panels
--
-- **All three are Debind's own XML now** (2026-08-15). Two of them used to be built by the
-- load-on-demand addon and fetched by global name; they are children of the frame by
-- `parent=` + `parentKey=` and arrive by `panelKey` (`building-export-import.md`).
--
-- Everything below fails **silently** if it breaks, which is why it is here rather than in a
-- checklist: a `parentKey` renamed, an XML dropped from the TOC, another panel added without a
-- width, `EnsureStore` simplified back to `IsAddOnLoaded`. None of that raises, and none of it is
-- visible to `npm run check` - the panels are built by code that only runs in the game.
--
-- **Nothing here inserts an action, on purpose.** Showing a panel is all these ask about, and an
-- empty profile is the cheapest way to ask it. What the storage tab draws with actions in it is
-- what the "Storage:" cases ask, and they build an entry rather than a screen.
-----------------------------------------------------------

RegisterTest("Panels: every tab resolves to a panel of its own", {
    description = "All three tabs resolve to a panel of their own, neither collapsing onto one nor falling through to MissingPanel",
    run = function()
        local NAME = "Panels resolve"

        local seen = {}
        for _, id in ipairs({ OVERVIEW_PANEL_ID, SWITCHES_PANEL_ID, STORAGE_PANEL_ID }) do
            local panel = DebindFrame:ResolvePanel(id)
            if not panel then
                return Fail(NAME, format("tab %d got no panel, check panelKey in PANELS or the TOC", id))
            end
            if panel == DebindFrame.MissingPanel then
                return Fail(NAME, format("tab %d fell through to MissingPanel", id))
            end
            -- The whole point of the move: they are the frame's children rather than something
            -- reparented on the first press.
            if panel:GetParent() ~= DebindFrame then
                return Fail(NAME, format("panel %d's parent is not the window", id))
            end
            if seen[panel] then
                return Fail(NAME, format("tab %d gives the same panel as tab %d", id, seen[panel]))
            end
            seen[panel] = id
        end

        return Pass(NAME, "4 tabs onto 4 panels of their own")
    end,
})

-- **The width is a `KeyValue` in the XML and nothing checks it.** It used to be read back out of
-- `GetWidth()` in `OnLoad`, which worked only while the panel stood unanchored at load; pinned to
-- the host on four sides that read answers with the window's own width - the value fed back - and
-- every tab would quietly settle on one size. Turning the KeyValue back into a `<Size>` restores
-- exactly that failure, with no error anywhere.
RegisterTest("Panels: the window takes each tab's own width", {
    description = "Moving tabs really does take the window to the width that panel asked for",
    run = function()
        local NAME = "Panel width"

        -- **The pair is Overview and Settings.** It was Overview and the export tab, then Overview
        -- and Switches; both of those grew a second column and came to ask for Overview's own
        -- width, and two panels legitimately wanting the same number leave this nothing to measure.
        -- Settings is the one panel left that is not a list beside a list.
        local overview = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        local narrow = DebindFrame:ResolvePanel(SETTINGS_PANEL_ID)
        if not overview or not narrow then
            return Fail(NAME, "could not get the panel")
        end
        if not overview.preferredWidth or not narrow.preferredWidth then
            return Fail(NAME, format("it is not holding a width (overview=%s, settings=%s)",
                tostring(overview.preferredWidth), tostring(narrow.preferredWidth)))
        end
        if overview.preferredWidth == narrow.preferredWidth then
            return Fail(NAME, format(
                "both panels ask for the same width (%d), they may be reading the window's width back",
                overview.preferredWidth))
        end

        -- Put the reader back where they were, whatever happens below.
        AddTeardown(function() DebindFrame:SelectPanel(OVERVIEW_PANEL_ID) end)

        -- And that the frame actually listens. Asking the panels alone would pass on a
        -- `SelectPanel` that stopped applying it.
        DebindFrame:SelectPanel(SETTINGS_PANEL_ID)
        local narrowWidth = DebindFrame:GetWidth()
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
        local overviewWidth = DebindFrame:GetWidth()

        -- **Within a pixel, not exact.** `GetWidth` reads back what the frame ended up at, and that
        -- is not obliged to be the number `SetWidth` was handed once the UI scale has been through
        -- it - 812 comes back as 811 on some scales. What this test is for is that the frame follows
        -- the panel at all, which an exact compare answers wrongly rather than more strictly.
        local function Off(got, want) return math.abs(got - want) > 1 end
        if Off(narrowWidth, narrow.preferredWidth) or Off(overviewWidth, overview.preferredWidth) then
            return Fail(NAME, format("the window does not follow: settings %d (wanted %d), overview %d (wanted %d)",
                narrowWidth, narrow.preferredWidth, overviewWidth, overview.preferredWidth))
        end

        return Pass(NAME, format("overview %d, settings %d", overviewWidth, narrowWidth))
    end,
})

-- **A dragged window hangs by whatever anchor `StartMoving` chose**, and one dropped near the
-- middle of the screen comes back on a centre one. `SetWidth` then splits the difference between
-- both sides, so every tab change slid the window sideways by half of it. `OnDragStop` saved a
-- top left corner and nothing pinned the window to one, which is why a `/reload` appeared to fix
-- it: the load path was the only place that anchored by the corner.
--
-- The drag itself cannot be driven from here. What the test stands in for is the one thing
-- `StartMoving` leaves behind, the centre anchor, and everything after that is the window's own
-- `OnDragStop`.
RegisterTest("Panels: a dragged window keeps its left edge across a tab change", {
    description = "A window that was dragged keeps its left edge when a tab change moves its width",
    run = function()
        local NAME = "Left edge"

        local overview = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        local narrow = DebindFrame:ResolvePanel(SETTINGS_PANEL_ID)
        if not overview or not narrow then
            return Fail(NAME, "could not get the panel")
        end
        -- Two panels of the same width would leave nothing to measure, and this would pass on any
        -- anchor at all. **Settings is the narrow one**; all three tabs ask for Overview's width.
        if overview.preferredWidth == narrow.preferredWidth then
            return Fail(NAME, format("both panels ask for the same width (%s)", tostring(overview.preferredWidth)))
        end

        if not DebindFrame:IsShown() then
            DebindFrame:Show()
            AddTeardown(function() DebindFrame:CloseWindow() end)
        end

        -- Where the tester had the window, and what they had saved. `OnDragStop` writes both.
        local point, relativeTo, relativePoint, x, y = DebindFrame:GetPoint(1)
        local saved = DebindPrivate.UIVars.main and DebindPrivate.UIVars.main.pos
        AddTeardown(function()
            DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
            DebindPrivate.UIVars.main = DebindPrivate.UIVars.main or {}
            DebindPrivate.UIVars.main.pos = saved
            if point then
                DebindFrame:ClearAllPoints()
                DebindFrame:SetPoint(point, relativeTo, relativePoint, x, y)
            end
        end)

        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
        DebindFrame:ClearAllPoints()
        DebindFrame:SetPoint("CENTER", "UIParent", 0, 0)

        local dragStop = DebindFrame:GetScript("OnDragStop")
        if not dragStop then
            return Fail(NAME, "no OnDragStop, the window cannot be dragged")
        end
        dragStop(DebindFrame)

        local before = DebindFrame:GetLeft()
        DebindFrame:SelectPanel(SETTINGS_PANEL_ID)
        local after = DebindFrame:GetLeft()
        if not before or not after then
            return Fail(NAME, "could not read the window's left edge")
        end
        -- Within a pixel: `GetLeft` reads back what the frame ended up at, and the UI scale is in
        -- the middle of that (the tab width test above says the same thing).
        if math.abs(after - before) > 1 then
            return Fail(NAME, format("the left edge moved from %.0f to %.0f", before, after))
        end

        return Pass(NAME, format("%.0f unmoved (width %d -> %d)",
            before, overview.preferredWidth, narrow.preferredWidth))
    end,
})

-- **The panel is always there; what can be missing is what it reads.** `EnsureStore` asks whether
-- `DebindPrivate.Store` was handed over, not whether the addon is loaded - the addon can be in
-- memory having handed over nothing, and every caller dereferences that table. Asking
-- `IsAddOnLoaded` reads as the natural thing to write (it was, first), and it turns this fallback
-- into an error on the tab.
RegisterTest("Panels: no store means no panel, not an error", {
    description = "With no Store to be had, ResolvePanel answers nil and MissingPanel stands",
    run = function()
        local NAME = "Store missing"

        local saved = DebindPrivate.Store
        if not saved then
            return Fail(NAME, "there is no Store to begin with, this test has nothing to measure")
        end
        AddTeardown(function() DebindPrivate.Store = saved end)

        DebindPrivate.Store = nil
        local storagePanel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        local overviewPanel = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        DebindPrivate.Store = saved

        if storagePanel ~= nil then
            return Fail(NAME, "no Store and it handed over the storage panel, which indexes nil behind that")
        end
        -- Overview reads none of it, so it must not be dragged down with them.
        if overviewPanel == nil then
            return Fail(NAME, "the overview, which has nothing to do with Store, was blocked too")
        end

        return Pass(NAME, "import is blocked and the overview stands")
    end,
})

--- **The client is the only thing that can answer this one.** Both halves are frame questions: what
--- `UpdateButtons` left the button's enabled state at, and whether the press put the client's own
--- confirmation up. The headless harness has neither.
---
--- What it guards is the button being the only door. It is grey exactly when the sweep finds
--- nothing, so a lit button is a promise, and `RemoveDuplicateActions` walking a second time on the
--- press is what keeps that promise from resting on a cached answer. Gate the two on different
--- walks and a lit button starts answering `REMOVE_DUPLICATES_NONE`.
RegisterTest("Duplicates: the clean up button is lit only where there is something to remove", {
    description = "The clean up button lights only where there is a duplicate, and pressing it raises the confirmation",
    run = function()
        local NAME = "Duplicates clean up"
        local KEY = "CTRL-ALT-F7"

        if not DebindFrame:IsShown() then
            DebindFrame:Show()
            AddTeardown(function() DebindFrame:CloseWindow() end)
        end
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)

        -- The confirmation is the client's and outlives a failed run, so it goes whatever happens.
        AddTeardown(function() StaticPopup_Hide("GENERIC_CONFIRMATION") end)
        -- **The two duplicates below go too.** This case opens by asserting the layer holds nothing
        -- the sweep would find, and leaving them behind hands that same precondition to the next
        -- case as something it has to know about.
        AddTeardown(CleanupActions)

        local cleanUp = DebindFrame.OverviewPanel.PortraitRow.CleanUpPortrait
        DebindFrame:Update()
        if cleanUp:IsEnabled() then
            return Fail(NAME, "there is no duplicate at all and the clean up button is lit")
        end
        -- Grey with no reason on the tooltip is a button that cannot say why.
        if cleanUp.disabledReason ~= LLL["REMOVE_DUPLICATES_NONE"] then
            return Fail(NAME, "the dark button is not holding a reason")
        end

        -- Two actions a signature cannot tell apart, in one layer. That is the whole of what the
        -- sweep looks for.
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        ApplyBindings()

        DebindFrame:Update()
        if not cleanUp:IsEnabled() then
            return Fail(NAME, "there is a duplicate and the clean up button is dark")
        end
        if cleanUp.disabledReason ~= nil then
            return Fail(NAME, "the lit button is still holding the reason it was dark")
        end

        local onClick = cleanUp:GetScript("OnClick")
        if not onClick then
            return Fail(NAME, "the clean up button has no OnClick on it")
        end
        onClick(cleanUp)

        -- **The press has to reach the confirmation**, which is the half `UpdateButtons` cannot
        -- promise: the button lighting up says the walk found something, and this says the press
        -- walked again and agreed.
        if not StaticPopup_IsCustomGenericConfirmationShown("DebindDeleteConfirmation") then
            return Fail(NAME, "the button is lit and pressing it brought up no confirmation, the two detections have come apart")
        end

        return Pass(NAME, "dark where there is none, lit where there is, and pressing it reaches the confirmation")
    end,
})

--- The other half of the sweep: what the press actually takes away.
---
--- **This is the only path in the addon that deletes with no way back, so the kit is where it gets
--- pressed.** The headless spec stops at `CollectDuplicateActions` handing back a list
--- (`tests/identity_spec.lua`). Between that list and the profile afterwards lie the press, the
--- client's confirmation and `DeleteActions` renumbering what is left, and the reader says yes to
--- all of it at once.
---
--- **Every action here carries a condition, and the two kinds carry different ones.** The solver
--- drops a binding a higher one already covers, so two unconditional actions on one key leave a
--- single row in the key map and `KeyMapOrder` stops being able to say what survived. Different
--- axes keep both, which is what lets the last check ask whether the key still does what it did.
---
--- **Crossing layers is left to the headless spec.** A run is isolated to one layer
--- (`SetIsolated`), so a second one here would be a stand-in of my own making, measured against the
--- same walk the spec already measures against a profile that really has two.
RegisterTest("Duplicates: the press takes the copy that never fires", {
    description = "What the clean up removes and what it leaves, once confirmed",
    run = function()
        local NAME = "Duplicates removal"
        local KEY = "CTRL-ALT-F8"

        if not DebindFrame:IsShown() then
            DebindFrame:Show()
            AddTeardown(function() DebindFrame:CloseWindow() end)
        end
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)

        AddTeardown(function() StaticPopup_Hide("GENERIC_CONFIRMATION") end)
        AddTeardown(CleanupActions)

        local cleanUp = DebindFrame.OverviewPanel.PortraitRow.CleanUpPortrait

        --- The action while it is still in the layer, nil once it has been deleted. The table it
        --- was is still in hand either way, so asking it is no answer.
        local function Living(action)
            for _, candidate in GetTestLayer():Enumerate() do
                if candidate == action then
                    return candidate
                end
            end
            return nil
        end

        --- One group's `seq` on `KEY`, smallest first, as a string. The group is `(key, arrivalID)`.
        local function GroupSeqs(arrivalID)
            local out = {}
            for _, action in GetTestLayer():Enumerate() do
                if action.key == KEY and action.arrivalID == arrivalID then
                    out[#out + 1] = action.seq or -1
                end
            end
            table.sort(out)
            for i = 1, #out do
                out[i] = tostring(out[i])
            end
            return table.concat(out, " ")
        end

        --- Presses the button and says yes to what comes up.
        ---
        --- **The reference key is read before anything is clicked.** `GENERIC_CONFIRMATION` is the
        --- client's shared dialog and `StaticPopup_Visible` hands back whichever went up first, so
        --- pressing blind is pressing a stranger's [Yes].
        local function SweepAndAccept()
            DebindFrame:Update()
            if not cleanUp:IsEnabled() then
                return "a duplicate was stood up and the clean up button is dark"
            end
            cleanUp:Click()
            if not StaticPopup_IsCustomGenericConfirmationShown("DebindDeleteConfirmation") then
                return "pressing it brought up no confirmation"
            end
            local _, dialog = StaticPopup_Visible("GENERIC_CONFIRMATION")
            if not dialog or not dialog.data
                or dialog.data.referenceKey ~= "DebindDeleteConfirmation" then
                return "a confirmation that is not ours is standing in front"
            end
            dialog:GetButton1():Click()
            ApplyBindings()
            return nil
        end

        -- 1. One duplicate inside my group, and one inside the arrival group sitting on the same
        --    key. Both have to be caught at once, and afterwards neither group may have touched the
        --    other's numbers.
        CleanupActions()
        local keeper = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, stealth = true })
        local twinA = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, combat = true })
        local twinB = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, combat = true })
        local badgedA = InsertAction({ type = Constants.SPELL, value = 3, key = KEY,
            arrivalID = 7, combat = true })
        local badgedB = InsertAction({ type = Constants.SPELL, value = 3, key = KEY,
            arrivalID = 7, combat = true })
        ApplyBindings()

        -- **The premise: each group starts at 1 of its own.** Without that there is no telling what
        -- the number checks below measure.
        if GroupSeqs(nil) ~= "1 2 3" or GroupSeqs(7) ~= "1 2" then
            return Fail(NAME, format("the board did not stand. mine [%s], arrival [%s]",
                GroupSeqs(nil), GroupSeqs(7)))
        end
        local loser, winner = twinB, twinA
        if twinB.seq < twinA.seq then
            loser, winner = twinA, twinB
        end

        local err = SweepAndAccept()
        if err then return Fail(NAME, err) end

        if Living(loser) then
            return Fail(NAME, "the one with the higher seq was not deleted")
        end
        if not Living(winner) or not Living(keeper) then
            return Fail(NAME, "the one that fires first was deleted")
        end
        if not Living(badgedA) or Living(badgedB) then
            return Fail(NAME, "the duplicate inside the arrival group was missed, or the wrong one was caught")
        end
        -- **Each group is 1..n again within itself.** Numbered across the two together, the arrival
        -- carries 3 and my group fills 1..3.
        if GroupSeqs(nil) ~= "1 2" then
            return Fail(NAME, format("my group's numbers do not run on after the delete: [%s]", GroupSeqs(nil)))
        end
        if GroupSeqs(7) ~= "1" then
            return Fail(NAME, format("the arrival was numbered mixed in with my group: [%s]", GroupSeqs(7)))
        end
        if KeyMapOrder(KEY) ~= "1 2" then
            return Fail(NAME, format("what that key did changed after the delete: [%s]", KeyMapOrder(KEY)))
        end

        -- 2. An arrival that came as an exact copy of one of mine. **While the badge is on it
        --    reaches no key at all** (`BuildKeyMap`), so keeping that one and deleting mine takes
        --    away something the key was doing. Because each group numbers from 1, the arrival's
        --    `seq` can be lower than mine, and ordering on `seq` alone loses in exactly that way.
        CleanupActions()
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, stealth = true })
        local mine = InsertAction({ type = Constants.SPELL, value = 4, key = KEY, combat = true })
        local badged = InsertAction({ type = Constants.SPELL, value = 4, key = KEY,
            arrivalID = 9, combat = true })
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "1 4" then
            return Fail(NAME, format("the board did not stand. the key is [%s]", KeyMapOrder(KEY)))
        end
        if not (badged.seq and mine.seq and badged.seq < mine.seq) then
            return Fail(NAME, format("arrival %s, mine %s. not what this board set out to measure",
                tostring(badged.seq), tostring(mine.seq)))
        end

        err = SweepAndAccept()
        if err then return Fail(NAME, err) end

        if not Living(mine) or not Living(first) then
            return Fail(NAME, "the badged copy was kept and my action was deleted")
        end
        if Living(badged) then
            return Fail(NAME, "the arrival's copy was not deleted")
        end
        if KeyMapOrder(KEY) ~= "1 4" then
            return Fail(NAME, format("the confirmation said no key would change and one did: [%s]",
                KeyMapOrder(KEY)))
        end

        -- 3. When there is none at all. **The button cannot reach this branch** (it is greyed), so
        --    it is called outright. That it is greyed is what the case above measures.
        CleanupActions()
        InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        ApplyBindings()
        DebindFrame:Update()
        if cleanUp:IsEnabled() then
            return Fail(NAME, "there is no duplicate and the clean up button is lit")
        end

        local said
        local realDisplay = DebindPrivate.DisplayMessage
        DebindPrivate.DisplayMessage = function(message) said = message end
        local ok, thrown = pcall(DebindUI.RemoveDuplicateActions)
        DebindPrivate.DisplayMessage = realDisplay
        if not ok then
            return Fail(NAME, format("it raised on the empty branch: %s", tostring(thrown)))
        end
        if said ~= LLL["REMOVE_DUPLICATES_NONE"] then
            return Fail(NAME, format("it did not say there was none: %s", tostring(said)))
        end
        if StaticPopup_IsCustomGenericConfirmationShown("DebindDeleteConfirmation") then
            return Fail(NAME, "there is nothing to delete and a confirmation came up")
        end

        return Pass(NAME, "the one that fires first is kept, the groups do not mix numbers, and with none it answers in one line")
    end,
})
