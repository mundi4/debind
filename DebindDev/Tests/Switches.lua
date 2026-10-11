local _, Dev = ...

local DebindPrivate, Constants, DebindUI
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants, DebindUI = private, private.Constants, private.DebindUI
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local WaitUntil = Dev.WaitUntil
local AddTeardown = Dev.AddTeardown
local NarrowestLayerHere = Dev.NarrowestLayerHere
local NestConditions = Dev.NestConditions
local DefaultCasting = Dev.DefaultCasting
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local LastWinner = Dev.LastWinner
local WaitForWinner = Dev.WaitForWinner
local ReadSecureState = Dev.ReadSecureState
local TypeInto = Dev.TypeInto
local LeftRowOf = Dev.LeftRowOf
local OpenOverviewWithNothingPicked = Dev.OpenOverviewWithNothingPicked
local OVERVIEW_PANEL_ID = Dev.OVERVIEW_PANEL_ID
local SWITCHES_PANEL_ID = Dev.SWITCHES_PANEL_ID

-----------------------------------------------------------
-- Test Cases: The Switches tab
--
-- **Everything here is a wire that fails without a word.** A row's toggle writes a value that only
-- means something once codegen has been past it; a rename rewrites four kinds of reference and the
-- ones it misses are silent by construction, since a condition that stops matching draws exactly
-- like one that matches. Headless specs check that the rename moves the stored strings
-- (`tests/switch_spec.lua`); what only the game answers is whether the key still fires afterwards.
--
-- **The definition is put in by hand rather than made through the menu.** A run must not leave a
-- switch in the tester's profile, and the definitions table is the account's. So the slot is
-- swapped and put back, as the switch tests in `Tests/Conditions.lua` do it.
-----------------------------------------------------------

--- The row drawn for one switch, once the list has laid itself out.
---
--- **Whatever is in view**, like every other walk over a scroll box here: `ForEachFrame` reaches
--- the frames that exist, so a caller matches on the name rather than on a position in the list.
local function SwitchRow(panel, name)
    local found
    panel.List.ContentArea.ScrollBox:ForEachFrame(function(frame)
        if frame.switchName == name then
            found = frame
        end
    end)
    return found
end

--- Opens the tab and hands back the panel with its rows built. Puts the reader back on Overview
--- and closes the window afterwards, however the test ends.
---
--- **The list is refreshed here rather than left to `OnShow`.** Showing a frame that is already
--- shown fires nothing, and `SelectPanel` turns back when its tab is already the current one, so a
--- tester who left this tab open gets neither. The rows would then be the ones drawn before the
--- test planted anything, which reads as "the list does not list switches" -- it measured a stale
--- draw. Build the precondition, do not hope for it.
local function OpenSwitchesTab()
    DebindFrame:Show()
    AddTeardown(function()
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
        DebindFrame:CloseWindow()
    end)
    DebindFrame:SelectPanel(SWITCHES_PANEL_ID)

    local panel = DebindFrame.SwitchesPanel
    panel:RefreshRows()
    -- **The detail tab is part of that precondition.** It is not reset when the window closes, so
    -- a test that moved it hands the next one a right column drawing the other face - which is
    -- what the settings tests read as "the block did not come up", on the second run of the kit
    -- and never on the first.
    panel.Detail.TabSystem:SetTab(panel.settingsTabID)
    return panel
end

RegisterTest("Switches tab: the toggle on a row moves the key", {
    description = "The on/off button on a row really does turn on and off the key that switch stands on",
    run = function()
        local NAME = "Switch row toggle"
        local KEY = "CTRL-SHIFT-F7"
        local SWITCH = "$rowtoggle"

        if InCombatLockdown() then
            return Fail(NAME, "this button is disabled in combat, so nothing can be judged")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.SetRememberedSwitch(SWITCH, nil)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- **`resetValue`, not `value`.** The second is derived - a rebuild recomputes it from
        -- the answer in effect and from what this character remembers (`ApplySwitchResets`), so
        -- a setup that writes it is writing something the first rebuild may overwrite. What is
        -- wanted here is the answer "comes up off", and that is a `resetValue`.
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = false }

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, [SWITCH] = true })
        ApplyBindings()

        local panel = OpenSwitchesTab()
        -- The list lays itself out on a later frame, so the row is waited for rather than assumed.
        -- What is waited on is the widget existing, not the answer this test is about.
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            -- What the list did hold, because "no row" has two very different causes: the name
            -- never reached `GetSwitchNames`, or it did and no frame was built for it.
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("no row for that switch in the list. names: [%s]", names))
        end
        if not row.ToggleButton:IsEnabled() then
            return Fail(NAME, "a switch turned on and off by hand and the button is disabled")
        end

        -- **Pressed, not called.** `OnToggleClick` reached directly would pass on a row whose XML
        -- lost its `OnClick`, which is exactly the wiring this test is here for.
        row.ToggleButton:Click()

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if WaitForWinner() == nil then
            return Fail(NAME, "turned on and the key fires nothing, the value never reached the press")
        end

        row.ToggleButton:Click()

        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("turned off and the key still fires #%d", LastWinner()))
        end

        return Pass(NAME, "pressed on -> fires / pressed off -> fires nothing")
    end,
})

-- **A switch nothing binds has no value on the restricted side**, and the press has to work
-- anyway. `States` is filled only for the names the compile put in front of that side
-- (`IsSwitchTracked`), and the second half of this list is made of exactly the names it did not.
-- A press that asked that side to flip what it holds flipped a `nil`, landed on on, and left a
-- switch that was already on sitting there until it was pressed a second time.
--
-- **The one above cannot see this.** Its switch stands under a key, which is what puts it in front
-- of the restricted side, so the value the press flips is really there.
RegisterTest("Switches tab: the toggle turns off a switch nothing binds", {
    description = "A switch no action reads goes off on the first press, not the second",
    run = function()
        local NAME = "Switch row toggle, unbound"
        local SWITCH = "$rowunbound"

        if InCombatLockdown() then
            return Fail(NAME, "this button is disabled in combat, so nothing can be judged")
        end

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.SetRememberedSwitch(SWITCH, nil)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- **`resetValue`, so it comes up on** whatever this character was left holding from an
        -- earlier run of this test (`ApplySwitchResets`).
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true }

        -- No action names it. That is the whole of the setup, and it is what the test is about.
        ApplyBindings()

        if not DebindPrivate.ResolveSwitchDefinition(SWITCH)
                or DebindPrivate.GetSwitchValue(SWITCH) ~= true then
            return Fail(NAME, format("the premise is gone: the switch did not come up on (value=%s)",
                tostring(DebindPrivate.GetSwitchValue(SWITCH))))
        end
        if DebindPrivate.IsSwitchTracked(SWITCH) then
            return Fail(NAME, "the premise is gone: nothing binds this switch and the compile tracked it anyway")
        end
        local st = ReadSecureState(SWITCH)
        if st and st.present then
            return Fail(NAME, "the premise is gone: the restricted side holds a value for a switch nothing binds")
        end

        local panel = OpenSwitchesTab()
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("no row for that switch in the list. names: [%s]", names))
        end
        if not row.ToggleButton:IsEnabled() then
            return Fail(NAME, "a switch turned on and off by hand and the button is disabled")
        end

        -- Pressed rather than called, for the reason the test above is pressed.
        row.ToggleButton:Click()

        -- **Read on the spot and not after a frame.** The press writes the value itself
        -- (`OnToggleClick`), and waiting here would pass on a press that left it to a report the
        -- restricted side has no value to send.
        if DebindPrivate.GetSwitchValue(SWITCH) ~= false then
            return Fail(NAME, format(
                "one press on a switch that was on and it is %s -- it takes two",
                tostring(DebindPrivate.GetSwitchValue(SWITCH))))
        end

        return Pass(NAME, "on -> one press -> off")
    end,
})

-- **A column that fills itself from a pick is a wire, and a wire fails without a word.** Every
-- field on the right is written from the definition when a row on the left is clicked, and a field
-- that is never written sits there blank or holding the switch before it -- which reads exactly
-- like a switch that has nothing set.
--
-- It was a dialog until the tab was split in two, and the dialog's own trap is the reason this test
-- exists at all: `ShowInputBox` reached for `popup.editBox`, a field the client dropped when the
-- dialog became `GameDialogMixin`, so the box opened blank for every caller that passed a value.
-- The fields are ours now and the failure is the same shape.
RegisterTest("Switches tab: picking a switch fills the right column", {
    description = "Clicking a row writes that switch's name and expression into the fields on the right",
    run = function()
        local NAME = "Switch detail fields"
        local SWITCH = "$boxopen"
        local EXPR = "[combat]"

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.EXPR, expr = EXPR }

        local panel = OpenSwitchesTab()
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            return Fail(NAME, format("%s did not stand in the list", SWITCH))
        end
        -- **Clicked, not selected by hand.** What is being measured is the row's own `OnClick`
        -- reaching the panel; calling `SelectSwitch` outright passes on a row whose script never
        -- got wired.
        row:Click()

        local settings = panel.settingsFrame
        if not settings then
            return Fail(NAME, "a row was clicked and the settings block did not come up")
        end
        -- The name is read here and typed in the box the button beside it opens, so the sigil is
        -- drawn with it.
        local shown = settings.NameText:GetText()
        if shown ~= SWITCH then
            return Fail(NAME, format("the name reads %q, the switch is %s", shown, SWITCH))
        end
        local expr = settings.ExprBox:GetText()
        if expr ~= EXPR then
            return Fail(NAME, format(
                "the expression field holds %q, the expression on record was not carried", expr))
        end
        if panel:CurrentMode() ~= Constants.SWITCH_MODES.EXPR then
            return Fail(NAME, "the switch is worked out from an expression and the mode does not say so")
        end

        return Pass(NAME, format("%s -> %q", SWITCH, expr))
    end,
})

-- **The button that replaced the portrait's dropdown** (3c, §6-C of
-- `redesigning-custom-states.md`). Making a switch was a menu on the window's title bar
-- until now; it is this button, the condition menu and an on/off/toggle action's own menu, and all
-- three go through `DebindUI.ShowNewSwitchBox`.
--
-- **Pressed and typed into, not called.** `ShowNewSwitchBox` reached directly passes on a panel
-- whose XML lost the `OnClick`, and `SetText` without the box's own accept path passes on a dialog
-- whose button does nothing. Both of those are the wiring this test is here for.
RegisterTest("Switches tab: the New switch button makes one", {
    description = "The button under the list raises a box, and the name typed into it makes a switch",
    run = function()
        local NAME = "New switch button"
        local SWITCH = "$madehere"

        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = nil
            DebindPrivate.SetRememberedSwitch(SWITCH, nil)
            local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
            if dialog then
                -- Focus first: a hidden box that still holds the keyboard swallows what the next
                -- test types.
                local editBox = dialog:GetEditBox()
                if editBox then
                    editBox:ClearFocus()
                end
                dialog:Hide()
            end
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)

        if DebindPrivate.Switches[SWITCH] then
            return Fail(NAME, "the premise is gone: a switch of that name already exists")
        end

        local panel = OpenSwitchesTab()
        local newButton = panel.PortraitRow and panel.PortraitRow.NewPortrait
        if not newButton then
            return Fail(NAME, "no NewPortrait on the panel, the XML was not loaded")
        end
        if not newButton:IsEnabled() then
            return Fail(NAME, "the button is disabled")
        end

        newButton:Click()

        local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
        if not dialog then
            return Fail(NAME, "pressed the button and the box did not come up")
        end
        local editBox = dialog:GetEditBox()
        if not editBox then
            return Fail(NAME, "the box has no edit field. the client has renamed it again")
        end
        -- **The box opens empty, and `$` is drawn beside it.** The sigil is furniture now: it
        -- cannot be typed over, deleted or doubled, and what the reader types is joined to it by
        -- the caller. So the box holding anything at all is the failure, and the switch coming out
        -- named `$madehere` below is what says the two were joined.
        if editBox:GetText() ~= "" then
            return Fail(NAME, format("the box opened holding %q. it should open empty",
                editBox:GetText()))
        end

        if not TypeInto(editBox, strsub(SWITCH, 2)) then
            return Fail(NAME, "the edit box has no OnTextChanged")
        end
        -- **[Done] is pressed, not the callback called.** The button stays disabled until the box
        -- has text in it (`StaticPopup_StandardNonEmptyTextHandler`), so pressing it is also what
        -- says `TypeInto` reached the handler a hand would have.
        local accept = dialog:GetButton1()
        if not accept:IsEnabled() then
            return Fail(NAME, "a name was typed and [Done] is disabled")
        end
        accept:Click()

        if not DebindPrivate.Switches[SWITCH] then
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("no switch was made. what is there: [%s]", names))
        end

        -- The list has to have heard about it. Making one fires `OnSwitchesChanged` and the panel
        -- rebuilds off that, so a row missing here is that callback not reaching an open tab.
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            return Fail(NAME, "the switch was made and no row stood in the list")
        end

        return Pass(NAME, SWITCH .. " made, with a row in the list")
    end,
})

-- **Two of the three places that make one write the new name straight onto an action**: the
-- condition key, and the target of on/off/toggle (`DropDownMenus.lua`). Both write down the name
-- `ShowNewSwitchBox` hands them, so if the spelling typed in and the name it actually sits under
-- come apart, that action is made pointing at a name with no definition and is marked on the spot.
-- Names are folded to lower case when they are made (`CreateSwitch`).
--
-- **The button test above does not pass through here.** That one opens with no callback and looks
-- only at whether a switch appeared. What name comes back is answered only where it is opened with
-- a callback, and the two places that open it that way are menus.
--
-- Headless goes as far as `CreateSwitch`'s return value ("tells the caller the name it made" in
-- `tests/switch_spec.lua`). What only this layer can answer is whether that value reaches the caller
-- when the box is really typed into and [Done] is really pressed.
RegisterTest("Switches tab: a name typed in capitals reaches the caller folded", {
    description = "A switch made from a name typed in capitals reaches the caller under the name it actually sits on",
    run = function()
        local NAME = "New switch name folds"
        local TYPED = "ZzKit"
        local STORED = "$zzkit"

        AddTeardown(function()
            DebindPrivate.Switches[STORED] = nil
            DebindPrivate.SetRememberedSwitch(STORED, nil)
            local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
            if dialog then
                -- Focus first: a hidden box that still holds the keyboard swallows what the next
                -- test types.
                local editBox = dialog:GetEditBox()
                if editBox then
                    editBox:ClearFocus()
                end
                dialog:Hide()
            end
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)

        if DebindPrivate.Switches[STORED] then
            return Fail(NAME, "the premise is gone: a switch of that name already exists")
        end

        -- **Standing where the caller stands.** What the two menus hand this function is a callback
        -- of exactly this shape, and what they do inside it is write the name they were given into
        -- `action.conditions[name]` or `action.value`.
        local called, handed
        DebindUI.ShowNewSwitchBox(function(name)
            called = true
            handed = name
        end)

        local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
        if not dialog then
            return Fail(NAME, "the box did not come up")
        end
        local editBox = dialog:GetEditBox()
        if not editBox then
            return Fail(NAME, "the box has no edit field. the client has renamed it again")
        end
        if not TypeInto(editBox, TYPED) then
            return Fail(NAME, "the edit box has no OnTextChanged")
        end
        -- Presses [Done]. The callback hangs off that button, and calling it outright measures the
        -- function we handed over rather than the path through the box.
        local accept = dialog:GetButton1()
        if not accept:IsEnabled() then
            return Fail(NAME, "a name was typed and [Done] is disabled")
        end
        accept:Click()

        if not DebindPrivate.Switches[STORED] then
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("it did not sit down as %s. what is there: [%s]", STORED, names))
        end
        if not called then
            return Fail(NAME, "the switch was made and the caller was never called. made from a menu, the condition never lands")
        end
        if handed ~= STORED then
            return Fail(NAME, format(
                "the caller was handed %s. written down as a condition or an on-target, that action is marked",
                tostring(handed)))
        end
        if not DebindPrivate.ResolveSwitchDefinition(handed) then
            return Fail(NAME, format("the definition does not open under %s", tostring(handed)))
        end

        return Pass(NAME, format("%s -> %s", TYPED, handed))
    end,
})

-- **The right column opens on the layer that is deciding the switch**, and that is the one thing
-- it cannot get wrong without lying. Every field under the dropdown is read at whatever layer the
-- dropdown is on, so opening on the account-wide row while a specialization is overriding it shows
-- the reader an answer their keys are not using, with nothing on screen saying so.
--
-- **Both halves are the test.** Opening on the right layer says nothing on a switch that has only
-- one, so the override is put on first and the answer read back has to be the override's and not
-- the account-wide one.
--
-- Headless goes as far as `ResolveSwitchAnswer` naming the winning layer (`tests/switch_spec.lua`).
-- What only this layer can answer is whether the column is standing on that layer when it opens.
RegisterTest("Switches tab: the right column opens on the layer in force", {
    description = "Picking a switch that one specialization overrides opens the column on that layer, holding its answer",
    run = function()
        local NAME = "Switch detail layer"
        local SWITCH = "$rowlayers"
        local MODES = Constants.SWITCH_MODES

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.SetRememberedSwitch(SWITCH, nil)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- `resetValue` and not `value`, for the reason the toggle test above spells out. The
        -- account-wide row starts off and the override starts on, so which of the two the column
        -- is reading comes apart on the starting value it shows.
        DebindPrivate.Switches[SWITCH] = { mode = MODES.MANUAL, resetValue = false }

        local layerID = NarrowestLayerHere(true)
        local layerKey = DebindPrivate.GetSwitchLayerKey(layerID)
        if not layerKey then
            return Fail(NAME, "no layer key for this character and this spec")
        end
        DebindPrivate.SetSwitchAnswer(SWITCH, layerKey, MODES.MANUAL, true)

        local panel = OpenSwitchesTab()
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            return Fail(NAME, format("%s did not stand in the list", SWITCH))
        end
        row:Click()

        if panel.layerID ~= layerID then
            return Fail(NAME, format(
                "the column opened on layer %s and layer %s is the one deciding the switch",
                tostring(panel.layerID), tostring(layerID)))
        end

        local settings = panel.settingsFrame
        if not settings then
            return Fail(NAME, "a row was clicked and the settings block did not come up")
        end
        if panel:CurrentStartValue() ~= "on" then
            return Fail(NAME, format(
                "the override says it starts on and the column reads %s",
                tostring(panel:CurrentStartValue())))
        end
        -- The dropdown's own text, because that is where the reader reads the layer off. A column
        -- standing on the right layer with the wrong name on the button is the same fault seen
        -- from the other side. **In blue**, since this layer is the one in force and the closed
        -- button keeps the colour the menu puts on it (`BuildLayerMenu`).
        local shown = settings.LayerDropdown:GetText()
        local want = BLUE_FONT_COLOR:WrapTextInColorCode(DebindUI.GetLayerLabel(layerID))
        if shown ~= want then
            -- `||` so the colour codes print as text rather than being drawn: two strings that
            -- differ only in a colour code otherwise read as the same line.
            return Fail(NAME, format("the dropdown says %q, the layer is %q",
                (tostring(shown):gsub("|", "||")), (want:gsub("|", "||"))))
        end

        return Pass(NAME, format("%s -> %s", SWITCH, want))
    end,
})

-- **The two ends of a layer's life, in one run.** Measured apart, either could pass on a column
-- that never changed what it was drawing.
--
-- **The list holds only the layers that decide this switch**, so making one and taking it away are
-- the only ways a layer enters and leaves it; measured apart, either could pass on a list that
-- never changed.
--
-- **The seed is half of what is measured.** A new row starts from what the switch is doing here
-- (`CreateOverrideAt`), so making a place to set something is not itself a change to what the
-- switch does. A row seeded with the plain default passes "the row is there" and fails this.
--
-- Headless goes as far as the row being written and taken away (`tests/switch_spec.lua`). What only
-- this layer can answer is that the column lands on the layer it just made, and that the pick goes
-- back to the layer in force once the row it was on is gone.
RegisterTest("Switches tab: a layer is made from the dropdown and taken away again", {
    description = "Making a layer from the list writes its row from what is on screen and reads it there, and taking that row away sends the column back to the layer in force",
    run = function()
        local NAME = "Switch layer make and remove"
        local SWITCH = "$rowmakelayer"
        local MODES = Constants.SWITCH_MODES

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.SetRememberedSwitch(SWITCH, nil)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- The confirmation is the client's and outlives a failed run, so it goes whatever happens.
        AddTeardown(function() StaticPopup_Hide("GENERIC_CONFIRMATION") end)
        -- Off account-wide, so a row that copied what is set elsewhere can be told from one built
        -- out of the defaults: a fresh row comes up `remember`, and this is `off`.
        DebindPrivate.Switches[SWITCH] = { mode = MODES.MANUAL, resetValue = false }

        local layerID = NarrowestLayerHere(true)
        local layerKey = DebindPrivate.GetSwitchLayerKey(layerID)
        if not layerKey then
            return Fail(NAME, "no layer key for this character and this spec")
        end

        local panel = OpenSwitchesTab()
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            return Fail(NAME, format("%s did not stand in the list", SWITCH))
        end
        row:Click()

        panel:CreateOverrideAt(layerID)

        if panel.layerID ~= layerID then
            return Fail(NAME, format("a layer was made at %s and the column is reading %s",
                tostring(layerID), tostring(panel.layerID)))
        end
        -- A new row starts from the plain default, whatever the account-wide row says: it is a
        -- place to set something and not a copy of what is set elsewhere (2026-09-20, 소유자).
        -- The account-wide row above is `off`, so a row that copied would read `off` here.
        local mode, resetValue = DebindPrivate.GetSwitchAnswerAt(SWITCH, layerKey)
        if mode ~= MODES.MANUAL or resetValue ~= nil then
            return Fail(NAME, format("the new row says %s/%s and a fresh one is manual/nil",
                tostring(mode), tostring(resetValue)))
        end

        -- **Asked through the dialog, not around it.** Taking a row away puts a confirmation up,
        -- and calling `RemoveSwitchOverride` from here would pass on a press that never reaches it.
        panel:RemoveOverrideAt(layerID)
        local _, dialog = StaticPopup_Visible("GENERIC_CONFIRMATION")
        if not dialog or not dialog.data
            or dialog.data.referenceKey ~= "DebindSwitchOverrideRemove" then
            return Fail(NAME, "taking the row away brought up no confirmation of ours")
        end
        dialog:GetButton1():Click()

        if DebindPrivate.GetSwitchAnswerAt(SWITCH, layerKey) ~= nil then
            return Fail(NAME, "the confirmation was accepted and the row is still set there")
        end
        -- The account-wide row is the only one left, so that is where the pick has to land.
        if panel.layerID ~= DebindPrivate.GetLayerID(nil, false) then
            return Fail(NAME, format("the row was taken away and the column is still reading %s",
                tostring(panel.layerID)))
        end

        return Pass(NAME, format("%s -> %s", SWITCH, DebindUI.GetLayerLabel(layerID)))
    end,
})

-- Deleting offers a merge (`resolving-switches-on-accept.md` 6-7). What a merge rewrites is headless
-- (`tests/arrivalswitch_spec.lua`); what only the game has is the dialog and the menu it opens, and
-- that picking from that menu is what merges.
--
-- **Measured on another switch's expression**, the one reference a run can watch: test actions sit
-- in the run's own layer, which the account walk a merge goes through does not see.
RegisterTest("Switches tab: deleting can merge into another switch", {
    description = "The delete dialog's [Merge Into...] opens a list of switches, and picking one merges into it",
    run = function()
        local NAME = "Switch delete merge"
        local MODES = Constants.SWITCH_MODES
        local LOSER, WINNER, READER = "$mergeloser", "$mergewinner", "$mergereader"

        local saved = {}
        for _, name in ipairs({ LOSER, WINNER, READER }) do
            saved[name] = DebindPrivate.Switches[name]
        end
        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            StaticPopup_Hide("DEBIND_SWITCH_DELETE")
            for name, definition in pairs(saved) do
                DebindPrivate.Switches[name] = definition
            end
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        DebindPrivate.Switches[LOSER] = { mode = MODES.MANUAL }
        DebindPrivate.Switches[WINNER] = { mode = MODES.MANUAL, resetValue = true }
        DebindPrivate.Switches[READER] = { mode = MODES.EXPR, expr = format("[%s]", LOSER) }

        local panel = OpenSwitchesTab()
        local row = WaitUntil(function() return SwitchRow(panel, LOSER) end, 2)
        if not row then
            return Fail(NAME, format("%s did not stand in the list", LOSER))
        end
        row:Click()
        panel:OnDeleteClick()

        local _, dialog = StaticPopup_Visible("DEBIND_SWITCH_DELETE")
        if not dialog then
            return Fail(NAME, "deleting brought up no dialog of ours")
        end
        if not dialog:GetButton(2):IsEnabled() then
            return Fail(NAME, "there are other switches and [Merge Into...] is dark")
        end
        dialog:GetButton(2):Click()

        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "[Merge Into...] opened no list")
        end
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == WINNER then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("%s is not in the list", WINNER))
        end
        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if DebindPrivate.Switches[LOSER] then
            return Fail(NAME, "picked a switch and the deleted one is still there")
        end
        if not DebindPrivate.Switches[WINNER] then
            return Fail(NAME, "the switch merged into is gone")
        end
        local expr = DebindPrivate.Switches[READER].expr
        if expr ~= format("[%s]", WINNER) then
            return Fail(NAME, format("another switch's expression is %s", tostring(expr)))
        end
        return Pass(NAME, format("%s -> %s", LOSER, WINNER))
    end,
})

-- **The fifth place, and the only one that is not an action.** Where a switch answers with `[expr]`
-- that expression is a macro conditional and can name another switch, but that name lives inside a
-- definition, where `GetUndefinedSwitch` never looks. Leaving a deleted switch's reference standing
-- there is by design (`DeleteSwitch`), and that design only holds while what is left is marked.
-- Without the mark, codegen bakes the name as `known:0` (`EmitMacroTextArg`) and the switch being
-- computed quietly becomes a different one.
--
-- Headless goes as far as the function that answers (`tests/issue_spec.lua`). What only this layer
-- can answer is **whether the field really takes the issue colour**: the colour is painted by
-- `RefreshSettings`, deleting stands the whole tab up again, and what comes back has to be reading
-- the same layer.
--
-- **What it was before the delete is read first.** On a field marked from the start, "it was
-- marked" says nothing.
RegisterTest("Switches tab: an expression left naming a deleted switch is marked", {
    description = "The expression field takes the issue colour where an expression left behind still names a deleted switch",
    run = function()
        local NAME = "Expression names a dead switch"
        local MODES = Constants.SWITCH_MODES
        local SOURCE = "$exprsrc"
        local DERIVED = "$exprdst"

        local savedSource = DebindPrivate.Switches[SOURCE]
        local savedDerived = DebindPrivate.Switches[DERIVED]
        AddTeardown(function()
            DebindPrivate.Switches[SOURCE] = savedSource
            DebindPrivate.Switches[DERIVED] = savedDerived
            DebindPrivate.SetRememberedSwitch(SOURCE, nil)
            DebindPrivate.SetRememberedSwitch(DERIVED, nil)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- **`value` is not used.** That is a derived field and the setting is `resetValue`. All this
        -- needs is "there is one switch turned on and off by hand", so only the mode is written.
        DebindPrivate.Switches[SOURCE] = { mode = MODES.MANUAL }
        DebindPrivate.Switches[DERIVED] = {
            mode = MODES.EXPR,
            expr = format("[%s] [combat]", SOURCE),
        }

        --- **Measured against the issue colour** (`GetIssueColor`). The field is the highlight colour
        --- while it is being read and grey while it is not, so which of the three it is comes apart
        --- on the value alone.
        local function IsMarked(fontString)
            local r, g, b = fontString:GetTextColor()
            local er, eg, eb = DebindPrivate.GetIssueColor(Constants.BINDING_ISSUE_UNDEFINED_SWITCH):GetRGB()
            return math.abs(r - er) < 0.01 and math.abs(g - eg) < 0.01
                and math.abs(b - eb) < 0.01
        end

        local panel = OpenSwitchesTab()
        local row = WaitUntil(function() return SwitchRow(panel, DERIVED) end, 2)
        if not row then
            return Fail(NAME, format("%s did not stand in the list", DERIVED))
        end
        row:Click()

        local box = panel:ExprBox()
        if not box then
            return Fail(NAME, "a row was clicked and the settings block did not come up")
        end
        if IsMarked(box) then
            return Fail(NAME, format("the premise is gone: %s is still there and the field is already marked", SOURCE))
        end

        DebindPrivate.DeleteSwitch(SOURCE)

        -- Deleting fires `OnSwitchesChanged` and the whole tab stands up again, which can move the
        -- picked switch and hands the settings block out afresh. So this waits on the field the
        -- panel is holding now rather than reading back what was true above.
        local marked = WaitUntil(function()
            local current = panel:ExprBox()
            if panel.selectedName == DERIVED and current and IsMarked(current) then
                return current
            end
        end, 2)
        if not marked then
            if panel.selectedName ~= DERIVED then
                return Fail(NAME, format("the column moved off %s after the delete", DERIVED))
            end
            local expr = DebindPrivate.Switches[DERIVED].expr
            return Fail(NAME, format(
                "the expression is %s and the field was not marked (broken name: %s). there is nowhere to find the deleted reference",
                expr, tostring(DebindPrivate.GetUndefinedSwitchInExpr(expr, DERIVED))))
        end

        return Pass(NAME, format("deleted %s -> %s's expression is marked", SOURCE, DERIVED))
    end,
})

--- **The search box takes a switch's name**, which is how the switches tab sends the reader to the
--- actions waiting on one: those are edited on Overview, not there.
---
--- The half that cannot be read off a passing search is the name being matched whole. Everything
--- else in that box matches a piece of a word, so `$find` would drag in `$findtwo` and the list
--- would be a list of something the reader did not ask for. Both names are planted here and the
--- second one has to stay out.
RegisterTest("Overview search: a switch's name finds what waits on it", {
    description = "Typing $name into the search box leaves the actions that use that switch and drops the rest, and a longer name that starts the same stays out",
    run = function()
        local NAME = "Search by switch name"
        local SWITCH = "$findme"
        local LONGER = "$findmetoo"

        local saved, savedLonger = DebindPrivate.Switches[SWITCH], DebindPrivate.Switches[LONGER]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.Switches[LONGER] = savedLonger
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.MANUAL }
        DebindPrivate.Switches[LONGER] = { mode = Constants.SWITCH_MODES.MANUAL }

        local wanted = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F5",
            conditions = { [SWITCH] = true } })
        local longer = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F6",
            conditions = { [LONGER] = true } })
        local unrelated = InsertAction({ type = Constants.SPELL, value = 3, key = "CTRL-ALT-F7" })
        ApplyBindings()
        OpenOverviewWithNothingPicked()

        if not LeftRowOf(wanted) or not LeftRowOf(longer) or not LeftRowOf(unrelated) then
            return Fail(NAME, "setup: a planted row is not in the left column, is a search term or filter on")
        end

        local searchBox = DebindFrame.OverviewPanel.SearchBox
        AddTeardown(function() TypeInto(searchBox, "") end)
        if not TypeInto(searchBox, SWITCH) then
            return Fail(NAME, "the search box has no OnTextChanged")
        end

        if not LeftRowOf(wanted) then
            return Fail(NAME, format("%s is on the action and the search dropped it", SWITCH))
        end
        if LeftRowOf(longer) then
            return Fail(NAME, format("%s dragged in %s: the name is being matched by its first letters", SWITCH, LONGER))
        end
        if LeftRowOf(unrelated) then
            return Fail(NAME, "an action that names no switch survived the search")
        end

        return Pass(NAME, format("%s found its own action and left %s alone", SWITCH, LONGER))
    end,
})

--- **The usage row is a door and nothing else.** What it has to do is carry the reader to the
--- action, which means three things at once: the window tab, the layer tab, and the selection
--- (`GoToAction`). The first of those is the one this row added -- every other caller was already
--- standing on Overview -- and without it the press would land on a panel nobody can see.
RegisterTest("Switches tab: a usage row carries the reader to the action", {
    description = "Clicking an action under 'This character' opens Overview with that action picked",
    run = function()
        local NAME = "Switch usage row goes to the action"
        local SWITCH = "$usagegoto"

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.MANUAL }

        -- **This one action goes into the real account-wide layer rather than the run's own.**
        -- The test layer is a scratch table that is never stored (`GetTestLayer`), and this list
        -- is built by walking the profile (`CollectSwitchUsage`), so a row planted there could
        -- never stand in it however the panel behaves. The teardown takes it back out.
        local layer = DebindPrivate.GetProfileLayer(1)
        local action = NestConditions(DefaultCasting({
            type = Constants.SPELL, value = 1, key = "CTRL-ALT-F5",
            conditions = { [SWITCH] = true },
        }))
        layer:Insert(action)
        layer:PlaceInKeyGroup(action)
        AddTeardown(function()
            layer:Remove(action)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        ApplyBindings()

        local panel = OpenSwitchesTab()
        panel:SelectSwitch(SWITCH)
        -- **Through the strip.** `PickDetailTab` alone moves `detailTabID` and leaves the tab
        -- system pointing at the other face, so the reset in `OpenSwitchesTab` would find the
        -- settings tab already selected and turn back.
        panel.Detail.TabSystem:SetTab(panel.usageTabID)

        local row
        panel.Detail.ContentArea.ScrollBox:ForEachFrame(function(frame)
            if frame.action == action then
                row = frame
            end
        end)
        if not row then
            return Fail(NAME, format("%s is on an action of this character and no row stood for it", SWITCH))
        end

        row:Click("LeftButton")

        if DebindFrame.SwitchesPanel:IsShown() then
            return Fail(NAME, "the press left the window on the switches tab")
        end
        if not DebindFrame:IsActionSelected(action) then
            return Fail(NAME, "the window moved and the action it moved for is not picked")
        end

        return Pass(NAME, format("%s's row landed on the action", SWITCH))
    end,
})
