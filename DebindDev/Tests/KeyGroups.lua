local _, Dev = ...

local DebindPrivate, Constants, LLL, DebindUI
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants, LLL, DebindUI = private, private.Constants, private.L, private.DebindUI
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local CleanupActions = Dev.CleanupActions
local ApplyBindings = Dev.ApplyBindings
local KeyMapOrder = Dev.KeyMapOrder

-----------------------------------------------------------
-- Test Cases: Renumbering a key group
--
-- `renumbering-a-key-group.md`. **The rule and both of its ends are headless now**
-- (`tests/renumber_spec.lua`): the drawn order, and that the same numbers reach `BuildKeyMap` and
-- the solver. Two cases came down there on 2026-08-23 and this one did not follow them, for a
-- reason that has nothing to do with numbers.
--
-- **What is left is the door.** The arrows and the right-click menu both go through
-- `DebindUI.ApplyOrderSwap`, which redraws the list when it is done -- so it needs the window
-- standing, and the window is what the harness does not have.
-----------------------------------------------------------

RegisterTest("Renumber: the arrows' order reaches the solver", {
    description = "Swapping two records with the arrows lets the wider one cover the narrower, which then leaves KeyMap",
    run = function()
        local NAME = "Arrow order"
        local KEY = "CTRL-ALT-F1"

        -- **The window has to be open, because this test presses one of its buttons.**
        -- `ApplyOrderSwap` redraws the list when it is done, and the window builds itself on its
        -- first `OnShow` -- `OnLoad` is what reaches `LayerPanel` across to where `Refresh` looks
        -- for it. Nothing here is worth guarding against in `Refresh`: the arrows and the
        -- right-click menu both live on a row, so there is no way to reach it with the window shut.
        DebindFrame:Show()
        AddTeardown(function() DebindFrame:CloseWindow() end)

        -- **The order is the only difference.** Both are conditional, at the same importance, in
        -- one layer, so they share a band and nothing but `seq` can split them. With the narrow one
        -- (combat+stealth) in front both survive; with the broad one (combat) in front the narrow
        -- one sits entirely inside it and the solver drops it. So what this measures is not "the
        -- numbers changed" but **that the numbers reached the solver**.
        local narrow = InsertAction({ type = Constants.SPELL, value = 116, key = KEY,
            combat = true, stealth = true })
        local broad = InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "116 585" then
            return Fail(NAME, format("the narrower one is in front: %s", KeyMapOrder(KEY)))
        end

        -- The function the arrow buttons and the right-click menu both go through. It swaps the two
        -- numbers and renumbers that group.
        DebindPrivate.DebindUI.ApplyOrderSwap(broad, narrow)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "585" then
            return Fail(NAME, format("the wider one is in front: %s", KeyMapOrder(KEY)))
        end

        -- **Swapping back, and watching it come alive again.** Without this the test also passes on
        -- a key that only ever held one record.
        DebindPrivate.DebindUI.ApplyOrderSwap(narrow, broad)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "116 585" then
            return Fail(NAME, format("it did not come back: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "116 585 -> 585 -> 116 585")
    end,
})
RegisterTest("Key group: the conflict popup's second answer runs", {
    description = "[Overwrite] on an occupied key really does take the key off the occupant",
    run = function()
        local NAME = "Conflict overwrite"
        local KEY = "CTRL-ALT-F7"

        -- The occupant, and the set that wants its key.
        local occupant = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        local mover = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F9", combat = true })
        ApplyBindings()

        -- **The dialog is opened by name, and answered by pressing its button.** Calling the
        -- handler directly would prove nothing: the defect this stands over was never in the
        -- handler but in whether the popup ever reaches it. `StaticPopup_OnClick` dispatches by
        -- index only when the dialog says to, and without that it sends every index but the first
        -- to `OnCancel` - so [overwrite] closed and did nothing at all.
        local dialog = StaticPopup_Show("DEBIND_KEY_GROUP_CONFLICT", nil, nil, {
            actions = { mover },
            key = KEY,
            occupants = { occupant },
            label = "test",
        })
        if not dialog then
            return Fail(NAME, "the dialog did not come up")
        end
        AddTeardown(function() StaticPopup_Hide("DEBIND_KEY_GROUP_CONFLICT") end)

        local button = dialog.GetButton and dialog:GetButton(2)
        if not button then
            return Fail(NAME, "could not get button 2, has the client's dialog shape changed")
        end
        button:Click()

        if occupant.key ~= nil then
            return Fail(NAME, format("the occupant is still holding the key: %s", tostring(occupant.key)))
        end
        if mover.key ~= KEY then
            return Fail(NAME, format("the one that moved did not get the key: %s", tostring(mover.key)))
        end
        return Pass(NAME, "the occupant stood aside and the group took the key")
    end,
})

-----------------------------------------------------------
-- Test Cases: what the pair costs, and what pays for it
--
-- An arrival keeps the key it was sent on and a badge holds it back, so the two things that used to
-- be impossible are now ordinary: **two groups on one key**, and **accepting putting a key live**.
-- Each is answered by a question the reader is asked, and a question is exactly the kind of thing
-- that can be wired up wrong in silence -- the popup opens, a button does nothing, and only someone
-- who pressed it finds out (section 12 of `building-export-import.md`).
-----------------------------------------------------------

RegisterTest("Unbind: a set is not scattered without asking", {
    description = "[Unbind] on a group of several raises a confirmation, and only confirming scatters them",
    run = function()
        local NAME = "Unbind scatters"
        local KEY = "CTRL-ALT-F11"

        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        AddTeardown(function() StaticPopup_Hide("DEBIND_UNBIND_SCATTERS") end)

        DebindUI.UnbindActions({ first, second })

        -- **The gate comes first.** Nothing may be off its key while the question is still standing:
        -- that is the whole of what the box buys, and a call that acts and then asks would pass
        -- every check written about the popup itself.
        if first.key ~= KEY or second.key ~= KEY then
            return Fail(NAME, "the key was released before anything was asked")
        end
        local dialog = StaticPopup_FindVisible("DEBIND_UNBIND_SCATTERS")
        if not dialog then
            return Fail(NAME, "the confirmation did not come up")
        end

        local button = dialog.GetButton and dialog:GetButton(1)
        if not button then
            return Fail(NAME, "could not get button 1, has the client's dialog shape changed")
        end
        button:Click()

        if first.key ~= nil or second.key ~= nil then
            return Fail(NAME, format("confirmed and the key is still there: %s %s",
                tostring(first.key), tostring(second.key)))
        end
        return Pass(NAME, "asked first, then scattered")
    end,
})

RegisterTest("Unbind: one action is not asked about", {
    description = "[Unbind] on an action that is alone releases it outright, with nothing to confirm",
    run = function()
        local NAME = "Unbind single"
        local KEY = "CTRL-ALT-F12"

        -- **Alone, there is no set to lose.** A confirmation here would put a box in front of an
        -- ordinary move.
        local only = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        ApplyBindings()

        AddTeardown(function() StaticPopup_Hide("DEBIND_UNBIND_SCATTERS") end)

        DebindUI.UnbindActions({ only })

        if StaticPopup_FindVisible("DEBIND_UNBIND_SCATTERS") then
            return Fail(NAME, "only one of them and a confirmation came up")
        end
        if only.key ~= nil then
            return Fail(NAME, format("the key was not released: %s", tostring(only.key)))
        end
        return Pass(NAME, "released outright, nothing asked")
    end,
})

RegisterTest("Accept all: an occupied key is asked about, and all three answers run", {
    description = "An arrival on a key I use raises the confirmation, and each of its three answers really runs",
    run = function()
        local NAME = "Accept all occupied"
        local KEY = "CTRL-ALT-F5"
        local FREE = "CTRL-ALT-F3"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        --- Measuring all three answers in one place means standing the same board up again each
        --- time: one of mine, one arrival on the same key, and **one arrival on a key nobody
        --- uses**. That last one must not be pushed aside by any of the three answers, and it is
        --- the quietest place in this window to get wrong.
        ---
        --- **Both carry one condition, on different axes.** Different axes are what make the
        --- solver keep both, and **both being conditional** is what takes the comparator down as
        --- far as `seq`: `isConditional` is step 2 and `seq` is step 5 (`Ordering.lua`), so with
        --- only one of them conditional that one leads at the merge regardless of whether the
        --- arrival stands behind. Drop either condition and this test goes red against correct
        --- code.
        ---
        --- **The layer is emptied for every board.** The kit does not empty it between tests and
        --- this one reuses a single key three times, so without that the third board's order is
        --- measured over a heap that carries what the first two left behind, and the answer comes
        --- out as whatever the solver dropped for overlapping. Emptying once more at the end is
        --- the next test's business.
        AddTeardown(CleanupActions)

        local mine, arrived, free
        local function Setup(arrivalID)
            CleanupActions()
            mine = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, stealth = true })
            arrived = InsertAction({ type = Constants.SPELL, value = 2, key = KEY,
                arrivalID = arrivalID, combat = true })
            free = InsertAction({ type = Constants.SPELL, value = 3, key = FREE,
                arrivalID = arrivalID })
            ApplyBindings()
        end

        local function Answer(index, label)
            DebindFrame:ApproveAllImported()
            if arrived.arrivalID == nil then
                return format("[%s] the badge came off before anything was asked", label)
            end
            local dialog = StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED")
            if not dialog then
                return format("[%s] the confirmation did not come up", label)
            end
            local button = dialog.GetButton and dialog:GetButton(index)
            if not button then
                return format("[%s] could not get button %d, has the dialog shape changed", label, index)
            end
            button:Click()
            ApplyBindings()
            if free.key ~= FREE or free.arrivalID ~= nil then
                return format("[%s] the one on a key that does not clash was swept up: %s", label, tostring(free.key))
            end
            return nil
        end

        -- **The premise: while the badge is on, a real key on it still does not stand.** With that
        -- gone there is no telling what the three below measure.
        Setup(1)
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("the badged one is already standing: %s", KeyMapOrder(KEY)))
        end

        -- 1. [Keep Existing]. My key stays as it is and the arrival that clashed sits down with none.
        local err = Answer(1, "Keep Existing")
        if err then return Fail(NAME, err) end
        if mine.key ~= KEY then
            return Fail(NAME, format("[Keep Existing] and my key was released: %s", tostring(mine.key)))
        end
        if arrived.key ~= nil or arrived.arrivalID ~= nil or arrived.seq ~= nil then
            return Fail(NAME, format("the arrival that clashed did not sit down without a key: %s", tostring(arrived.key)))
        end
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("my key changed: %s", KeyMapOrder(KEY)))
        end

        -- 2. [Take Incoming]. The occupant loses the key and is not deleted.
        Setup(2)
        err = Answer(2, "Take Incoming")
        if err then return Fail(NAME, err) end
        if mine.key ~= nil then
            return Fail(NAME, format("[Take Incoming] and my key is still there: %s", tostring(mine.key)))
        end
        if arrived.key ~= KEY or arrived.arrivalID ~= nil then
            return Fail(NAME, "the arrival did not take the key, or the badge is still on")
        end

        -- 3. [Merge]. Both stay on the key and the arrival stands behind.
        Setup(3)
        err = Answer(3, "Merge")
        if err then return Fail(NAME, err) end
        if mine.key ~= KEY then
            return Fail(NAME, format("[Merge] and my key was released: %s", tostring(mine.key)))
        end
        if KeyMapOrder(KEY) ~= "1 2" then
            return Fail(NAME, format("not the merge order: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "asked, all three answers ran, and the key that does not clash was untouched in all three")
    end,










})

RegisterTest("Accept all: a free key is not asked about", {
    description = "An arrival on a key I do not use lands outright, with nothing to confirm",
    run = function()
        local NAME = "Accept all free"
        local KEY = "CTRL-ALT-F6"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        -- **This is the common case.** A box here turns the badge from a safeguard into homework.
        local arrived = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, arrivalID = 1 })
        ApplyBindings()

        DebindFrame:ApproveAllImported()

        if StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED") then
            return Fail(NAME, "a free key and a confirmation came up")
        end
        if arrived.arrivalID ~= nil then
            return Fail(NAME, "the badge did not come off")
        end
        ApplyBindings()
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("accepted and it is not standing: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "stood outright, nothing asked")
    end,
})

-----------------------------------------------------------
-- Test Cases: The heading's right-click menu
--
-- One right-click passes through three pieces: the template's `registerForClicks`, the right-hand
-- branch of `OnClick`, and the `rows` the left column loads onto the heading's elementData.
-- **Any one of them missing and nothing happens at all**: no error either, and only someone who
-- pressed it finds out. All three exist only inside the game, so this layer is the only place they
-- can be looked at.
-----------------------------------------------------------

RegisterTest("Key group: the heading's right-click arms the whole group", {
    description = "The entry on the heading's right-click menu opens a capture window carrying the whole group",
    run = function()
        local NAME = "Key group heading menu"
        local KEY = "CTRL-ALT-F8"

        -- **Two, and two split by a condition.** One on its own cannot measure "the whole group":
        -- it passes even where what was aimed at is a single row.
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        -- **The elementData on the heading is the thing the left column built.** Built by hand
        -- here, this test would pass on the day `rows` stopped being loaded, and that field is how
        -- the menu finds the group. The window is not shown: the data is built with no frame at all.
        DebindResultPanel:RefreshKeyboard()

        local elementData
        for _, data in DebindResultPanel.ContentArea.ScrollBox:GetDataProvider():Enumerate() do
            if data.isHeader and data.key == KEY then
                elementData = data
            end
        end
        if not elementData then
            return Fail(NAME, format("no heading for %s in the left column, is a search term or filter on", KEY))
        end

        local header = CreateFrame("Button", nil, UIParent, "DebindKeyHeaderTemplate")
        header:SetPoint("CENTER")
        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
            header:Hide()
            header:SetParent(nil)
        end)
        header:Init(elementData)

        -- **Opened by pressing.** Calling `OpenKeyGroupMenu` outright measures that function
        -- alone and passes without ever measuring whether a right-click reaches it, which is why
        -- the dialog tests above press the button itself.
        --
        -- **One thing this cannot measure:** whether `registerForClicks` really takes a
        -- right-click. `Click()` can call the handler regardless of what is registered, and there
        -- is no API that reads the registration back.
        header:Click("RightButton")

        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "the right-click brought up no menu")
        end

        -- **Found by its wording.** For a while it was found as "the only thing selectable", which
        -- was a shortcut from the days of a single entry and went red the moment [Unbind] joined
        -- it. What this measures is what the entry aims at, not how **many** entries there are,
        -- and it was tied to the count.
        --
        -- The question is now the same one the row test asks, so it is found the same way.
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["KEY_HEADER_SET_KEY"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("no [%s] entry", LLL["KEY_HEADER_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        -- Is what the window aims at the whole group? Carrying only one, the key that gets pressed
        -- reaches a single action.
        local armed = DebindKeyCaptureFrame.actions or {}
        local seen = {}
        for _, action in ipairs(armed) do
            seen[action] = true
        end
        if #armed ~= 2 or not seen[first] or not seen[second] then
            return Fail(NAME, format("what it aims at is not the group: %d", #armed))
        end

        return Pass(NAME, format("right-click -> menu -> %d in the capture window", #armed))
    end,
})

--- The other end of the same axis, and **the one that cannot be walked back**. A capture window
--- opened on the wrong set is closed again; a press here takes the key off whatever it gathered and
--- nothing records which of them went together (`ClearKeyForActions`).
---
--- **The confirmation is what measures the reach.** `UnbindActions` only asks when two or more of
--- one group are in what it was handed, so a box standing at all says the press gathered both. A
--- single action would go through in silence, which is what the pair of tests above this section
--- measures from the other side.
RegisterTest("Key group: the heading's [Unbind key] takes the whole group off", {
    description = "The heading's unbind entry gathers the whole group and asks before it scatters them",
    run = function()
        local NAME = "Key group heading unbind"
        local KEY = "CTRL-ALT-F4"

        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        DebindResultPanel:RefreshKeyboard()

        local elementData
        for _, data in DebindResultPanel.ContentArea.ScrollBox:GetDataProvider():Enumerate() do
            if data.isHeader and data.key == KEY then
                elementData = data
            end
        end
        if not elementData then
            return Fail(NAME, format("no heading for %s in the left column, is a search term or filter on", KEY))
        end

        local header = CreateFrame("Button", nil, UIParent, "DebindKeyHeaderTemplate")
        header:SetPoint("CENTER")
        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            StaticPopup_Hide("DEBIND_UNBIND_SCATTERS")
            header:Hide()
            header:SetParent(nil)
        end)
        header:Init(elementData)
        header:Click("RightButton")

        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "the right-click brought up no menu")
        end

        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["KEY_HEADER_UNBIND"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("no [%s] entry", LLL["KEY_HEADER_UNBIND"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if first.key ~= KEY or second.key ~= KEY then
            return Fail(NAME, "the key was released before anything was asked")
        end
        local dialog = StaticPopup_FindVisible("DEBIND_UNBIND_SCATTERS")
        if not dialog then
            return Fail(NAME, "pressed the entry and nothing was asked, what it gathered is not the group")
        end

        local button = dialog.GetButton and dialog:GetButton(1)
        if not button then
            return Fail(NAME, "could not get button 1, has the client's dialog shape changed")
        end
        button:Click()

        if first.key ~= nil or second.key ~= nil then
            return Fail(NAME, format("confirmed and the key is still there: %s %s",
                tostring(first.key), tostring(second.key)))
        end
        return Pass(NAME, "right-click -> menu -> asked over the group -> scattered")
    end,
})

--- **What is ticked has to be what the menu aims at**, and the heading is where the two can part:
--- its menu acts on the key group whatever the reader picked, so a pick made somewhere else and
--- left standing would be the window pointing at one set and acting on another.
---
--- **Picked elsewhere on purpose.** Starting with nothing picked passes on the day the fold stops
--- happening, since the group is what the menu takes either way.
RegisterTest("Key group: the heading's right-click folds the pick onto the group", {
    description = "A right-click on a heading makes that group the picked set, dropping a pick made elsewhere",
    run = function()
        local NAME = "Key group heading picks"
        local KEY = "CTRL-ALT-F2"

        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        local elsewhere = InsertAction({ type = Constants.SPELL, value = 3, key = "CTRL-ALT-F3" })
        ApplyBindings()

        DebindLayerPanel:ToggleActionSelected(elsewhere)
        if DebindFrame:GetSelectionCount() ~= 1 or not DebindFrame:IsActionSelected(elsewhere) then
            return Fail(NAME, format("setup: %d picked", DebindFrame:GetSelectionCount()))
        end

        DebindResultPanel:RefreshKeyboard()

        local elementData
        for _, data in DebindResultPanel.ContentArea.ScrollBox:GetDataProvider():Enumerate() do
            if data.isHeader and data.key == KEY then
                elementData = data
            end
        end
        if not elementData then
            return Fail(NAME, format("no heading for %s in the left column, is a search term or filter on", KEY))
        end

        local header = CreateFrame("Button", nil, UIParent, "DebindKeyHeaderTemplate")
        header:SetPoint("CENTER")
        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            header:Hide()
            header:SetParent(nil)
        end)
        header:Init(elementData)
        header:Click("RightButton")

        if not Menu.GetManager():GetOpenMenu() then
            return Fail(NAME, "the right-click brought up no menu")
        end

        if DebindFrame:IsActionSelected(elsewhere) then
            return Fail(NAME, "the pick made elsewhere is still in the set")
        end
        if DebindFrame:GetSelectionCount() ~= 2
                or not DebindFrame:IsActionSelected(first) or not DebindFrame:IsActionSelected(second) then
            return Fail(NAME, format("the set is not the group: %d picked", DebindFrame:GetSelectionCount()))
        end

        return Pass(NAME, "right-click -> the group is the picked set")
    end,
})
