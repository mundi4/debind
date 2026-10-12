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
local GetKeyBindings = Dev.GetKeyBindings
local SetMockState = Dev.SetMockState
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local LastWinner = Dev.LastWinner
local WaitForWinner = Dev.WaitForWinner

--- The entry that opens the same window stands on a row too, and **there it must carry that row
--- alone**. It reads the same as the heading's (both say [Assign a key]), so the eye cannot tell
--- them apart, and getting it wrong is quiet: the window opens and takes a key either way.
---
--- **What this does not measure:** whether a right-click reaches the menu. "Key group: the heading's
--- right-click arms the whole group" measures that, and measuring it here would need a row frame
--- that came out of the scroll box
--- (`DebindOrderLineMixin` reads `GetElementData`, so a hand-made frame cannot open it). So the
--- menu generator runs on a real menu frame and the click is skipped.
RegisterTest("Assign a key: a row's item takes that row alone", {
    description = "[Assign a key] on an overview row's menu opens a capture window carrying that row alone",
    run = function()
        local NAME = "Row assign key"
        local KEY = "CTRL-ALT-F9"

        -- **Two on one key.** Whether only one is carried is the whole of this test, so there has
        -- to be something beside it to measure against.
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupActionDropdownMenu,
            { actions = { first }, inOrderList = true })
        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "the menu did not come up")
        end

        -- Found by its wording here. This menu has several selectable entries (the two ordering
        -- ones), so it cannot be found as "the only one" the way the heading's is.
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["ACTION_SET_KEY"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("no [%s] entry", LLL["ACTION_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        if #armed ~= 1 or armed[1] ~= first then
            return Fail(NAME, format("what it aims at is not this row alone: %d", #armed))
        end

        return Pass(NAME, "one row alone was carried")
    end,
})

--- **The same item, on a row that has not been accepted yet.** It was deliberately withheld there
--- for a while, so a later reading of that reasoning can take it out again and nothing on screen
--- says so: the menu opens, the other two items are there, and only someone who came to give this
--- row a key finds out.
---
--- **This does not measure what happens after the press.** Giving the key accepts the row, and that
--- is `SetKeyForActions`' own rule with its own coverage. What is measured here is that the item
--- stands and that it aims at this row alone.
RegisterTest("Assign a key: a badged row is offered one too", {
    description = "A row not yet accepted is offered [Assign a key] too, and carries that row alone",
    run = function()
        local NAME = "Imported row assign key"

        -- **An arrival carrying a key.** The real key and the badge come as a pair: an arrival
        -- brings the sender's key exactly as it was, and the one thing holding it back is the badge.
        local action = InsertAction({
            type = Constants.SPELL,
            value = 1,
            key = "SHIFT-Q",
            arrivalID = 1,
        })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupActionDropdownMenu,
            { actions = { action }, inOrderList = true })
        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "the menu did not come up")
        end

        -- **The badged row's own label**, which is the plain one with the other half spelled out:
        -- giving an arrival a key accepts it, and the item says so before it is pressed
        -- (`ACTION_SET_KEY_ACCEPT`). Looking for the plain words here would pass on a row that had
        -- lost its badge somewhere earlier in the run.
        local wanted = format(LLL["ACTION_SET_KEY_ACCEPT"], LLL["ACTION_SET_KEY"], LLL["APPROVE_IMPORT"])
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == wanted then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("no [%s] entry", wanted))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        if #armed ~= 1 or armed[1] ~= action then
            return Fail(NAME, format("what it aims at is not this row alone: %d", #armed))
        end

        return Pass(NAME, "the entry stands on a badged row too, and carried that row alone")
    end,
})

--- **Both answers in that window are the reader deciding the key** (2026-08-23, the owner), and
--- deciding the key is what accepting an arrival is (`DebindFrameMixin:SetActionKey`). The item that
--- opened it says so on its face, so pressing the button on the window it opened has to keep the
--- promise: [Unbind key] used to leave the arrival with no key **and** still waiting, which is
--- neither half of what the label said.
---
--- The menu's own [Unbind] is not this and does not accept - it is aimed at a row rather than opened
--- over a question, and one function serves both, so nothing but the flag tells them apart.
RegisterTest("Assign a key: unbinding from that window accepts too", {
    description = "[Unbind] in a window opened by [Assign a key & Accept] still accepts",
    run = function()
        local NAME = "Imported row unbind accepts"

        local action = InsertAction({
            type = Constants.SPELL,
            value = 1,
            key = "SHIFT-Q",
            arrivalID = 1,
        })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        DebindUI.BeginKeyCapture({ action })
        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "the capture window did not come up")
        end
        if not DebindKeyCaptureFrame.UnbindButton:IsEnabled() then
            return Fail(NAME, "it came carrying a real key and [Unbind] is dark")
        end

        -- Exactly what that button does: it hands the answer over as nil.
        DebindKeyCaptureFrame:Commit(nil)

        if action.key ~= nil then
            return Fail(NAME, format("the key did not come off: %s", tostring(action.key)))
        end
        if action.arrivalID ~= nil then
            return Fail(NAME, format("it was not accepted, the badge is still %s",
                tostring(action.arrivalID)))
        end

        return Pass(NAME, "the key came off and the badge came off with it")
    end,
})

--- The fourth way into the same window, and the one with no heading behind it: several rows the
--- reader ticked, which may sit on different keys or on none.
---
--- **Two things are measured and the second is the one that bites.** That the item stands, and that
--- [Unbind] beside it goes dead when nothing in the selection holds a key at all. Lit over rows that
--- are all keyless it offers to take off a key none of them has, and pressing it does nothing.
RegisterTest("Bulk menu: the key pair aims at the whole selection", {
    description = "[Assign a key] on a multiple selection opens a window carrying all of it, and [Unbind] goes dark when nothing picked has a key",
    run = function()
        local NAME = "Bulk key items"
        local KEY = "CTRL-ALT-F10"

        -- **Two on keys of their own.** A key group cannot produce this state, and whether the bulk
        -- path carries it as far as the window is half of this test.
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F11" })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        local function OpenBulkMenu(actions)
            Menu.GetManager():CloseMenus()
            MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupActionDropdownMenu, { actions = actions })
            return Menu.GetManager():GetOpenMenu()
        end

        local function FindItem(menu, text)
            local found
            menu:EnumerateElementDescriptions(function(_, description)
                if MenuUtil.GetElementText(description) == text then
                    found = description
                end
            end)
            return found
        end

        local menu = OpenBulkMenu({ first, second })
        if not menu then
            return Fail(NAME, "the menu did not come up")
        end

        local unbind = FindItem(menu, LLL["UNBIND"])
        if not unbind or not unbind:IsEnabled() then
            return Fail(NAME, "a selection holding a real key and [Unbind] is dark")
        end

        local item = FindItem(menu, LLL["ACTION_SET_KEY"])
        if not item then
            return Fail(NAME, format("no [%s] entry", LLL["ACTION_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        local seen = {}
        for _, action in ipairs(armed) do
            seen[action] = true
        end
        if #armed ~= 2 or not seen[first] or not seen[second] then
            return Fail(NAME, format("not everything picked was carried: %d", #armed))
        end
        DebindKeyCaptureFrame:Hide()

        -- **A selection holding only things with no key at all.** [Unbind] alive here says a key
        -- can be taken off where there is none to take, and pressing it does nothing.
        local keyless = InsertAction({
            type = Constants.SPELL,
            value = 3,
        })
        ApplyBindings()

        menu = OpenBulkMenu({ keyless })
        if not menu then
            return Fail(NAME, "the second menu did not come up")
        end
        unbind = FindItem(menu, LLL["UNBIND"])
        if not unbind then
            return Fail(NAME, format("no [%s] entry", LLL["UNBIND"]))
        end
        if unbind:IsEnabled() then
            return Fail(NAME, "nothing picked has a key and [Unbind] is lit")
        end

        return Pass(NAME, "both picked were carried into the window, and [Unbind] went dark where nothing picked had a key")
    end,
})

--- **Needs the window.** The selection lives in `DebindUI.lua` beside the list it is drawn over, and
--- the rebuild after a key change is what folded it onto one row.
RegisterTest("Bulk key change: a selection of several stays selected", {
    description = "Taking the key off two picked rows leaves both picked; the same change sent from outside the selection still folds onto one",
    run = function()
        local NAME = "Selection after key change"

        local first = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F7" })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F8" })
        local third = InsertAction({ type = Constants.SPELL, value = 3 })
        ApplyBindings()

        -- **The list draws the open tab's layer, and the run does not isolate that lookup.** The setup
        -- below checks the planted rows through that list, so the test layer has to be what the open
        -- tab shows.
        local realGetProfileLayer = DebindPrivate.GetProfileLayer
        DebindPrivate.GetProfileLayer = function(layerID)
            if layerID == DebindUI.GetLayerID() then
                return GetTestLayer()
            end
            return realGetProfileLayer(layerID)
        end
        AddTeardown(function() DebindPrivate.GetProfileLayer = realGetProfileLayer end)

        DebindFrame:Show()
        AddTeardown(function() DebindFrame:CloseWindow() end)
        DebindLayerPanel:Refresh(true)

        for _, action in ipairs({ first, second, third }) do
            if not DebindLayerPanel:FindElementDataByActionInfo(action) then
                return Fail(NAME, "setup: a planted row is not in the list, is a search term or filter on")
            end
        end

        DebindLayerPanel:SetSelectedAction(first)
        DebindLayerPanel:ToggleActionSelected(second)
        if DebindFrame:GetSelectionCount() ~= 2 then
            return Fail(NAME, format("setup: %d picked", DebindFrame:GetSelectionCount()))
        end

        DebindUI.UnbindActions({ first, second })
        if DebindFrame:GetSelectionCount() ~= 2
                or not DebindFrame:IsActionSelected(first) or not DebindFrame:IsActionSelected(second) then
            return Fail(NAME, format("after unbinding the picked two, %d picked", DebindFrame:GetSelectionCount()))
        end

        -- **The other half.** A set that was not the selection has no selection to keep.
        first.key, second.key = "CTRL-ALT-F7", "CTRL-ALT-F8"
        ApplyBindings()
        DebindLayerPanel:SetSelectedAction(third)
        DebindUI.UnbindActions({ first, second })
        if DebindFrame:GetSelectionCount() ~= 1 then
            return Fail(NAME, format("a set sent from outside the selection left %d picked",
                DebindFrame:GetSelectionCount()))
        end

        return Pass(NAME, "the picked two stayed picked, and an unpicked set folded onto one")
    end,
})

--- **Needs the game.** Where the resolved target's row stands in the menu, when it is locked and
--- which setter pressing it reaches is the client's menu tree, which only exists here
--- (`implementing-focus-and-self-cast.md` §3-6).
RegisterTest("Resolved Unit: the row under Units writes the condition, and Target opens none", {
    description = "The Resolved Unit row sits under Units, stores \"@\" on an action with no target, on Always Ask and on a macro. The Target menu opens no submenu.",
    run = function()
        local NAME = "Resolved Unit row"

        AddTeardown(CleanupActions)
        AddTeardown(function()
            Menu.GetManager():CloseMenus()
        end)

        local function ChildByText(description, text)
            for _, child in description:EnumerateElementDescriptions() do
                if MenuUtil.GetElementText(child) == text then
                    return child
                end
            end
        end

        local function ChildTexts(description)
            local names = {}
            for _, child in description:EnumerateElementDescriptions() do
                tinsert(names, tostring(MenuUtil.GetElementText(child)))
            end
            return table.concat(names, " | ")
        end

        --- The menu opened afresh, and one group in it by its label.
        local function Group(action, label)
            Menu.GetManager():CloseMenus()
            MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupActionDropdownMenu, { actions = { action } })
            local menu = Menu.GetManager():GetOpenMenu()
            if not menu then
                return nil, "the menu did not come up"
            end
            local found
            menu:EnumerateElementDescriptions(function(_, description)
                if MenuUtil.GetElementText(description) == label then
                    found = description
                end
            end)
            if not found then
                return nil, format("no [%s] group", label)
            end
            return found
        end

        local action = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F7" })
        ApplyBindings()

        local units, err = Group(action, LLL["CONDITION_UNITS"])
        if not units then return Fail(NAME, err) end
        local row = ChildByText(units, LLL["RESOLVED_TARGET"])
        if not row then
            return Fail(NAME, format("no [%s] row under [%s]: %s", LLL["RESOLVED_TARGET"],
                LLL["CONDITION_UNITS"], ChildTexts(units)))
        end
        if not row:IsEnabled() then
            return Fail(NAME, "the row is locked on an action with no target")
        end
        local exists = ChildByText(row, LLL["CONDITION_UNIT_EXISTS"])
        if not exists then
            return Fail(NAME, format("no [%s] entry: %s", LLL["CONDITION_UNIT_EXISTS"], ChildTexts(row)))
        end
        exists:Pick(MenuInputContext.MouseButton, "LeftButton")
        local stored = action.conditions and action.conditions.units and action.conditions.units["@"]
        if not (type(stored) == "table" and stored.exists == true) then
            return Fail(NAME, "pressing it stored " .. tostring(stored))
        end

        -- **The Target menu is a list of targets and nothing else now.** A child with rows of its
        -- own is a submenu, which is what the old condition row was.
        local target, terr = Group(action, LLL["TARGET_UNIT"])
        if not target then return Fail(NAME, terr) end
        for _, child in target:EnumerateElementDescriptions() do
            for _ in child:EnumerateElementDescriptions() do
                return Fail(NAME, format("[%s] still opens a submenu: %s", LLL["TARGET_UNIT"],
                    tostring(MenuUtil.GetElementText(child))))
            end
        end

        -- **`none` has the row too** (2026-09-15, owner): it is aimed like an action with no target,
        -- and only the cast asks.
        local always = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F9", unit = "none" })
        ApplyBindings()
        units, err = Group(always, LLL["CONDITION_UNITS"])
        if not units then return Fail(NAME, err) end
        row = ChildByText(units, LLL["RESOLVED_TARGET"])
        if not row or not row:IsEnabled() then
            return Fail(NAME, "on Always Ask the row is " .. (row and "locked" or "missing"))
        end
        exists = ChildByText(row, LLL["CONDITION_UNIT_EXISTS"])
        if not exists then
            return Fail(NAME, format("no [%s] entry on Always Ask: %s", LLL["CONDITION_UNIT_EXISTS"], ChildTexts(row)))
        end
        exists:Pick(MenuInputContext.MouseButton, "LeftButton")
        stored = always.conditions and always.conditions.units and always.conditions.units["@"]
        if not (type(stored) == "table" and stored.exists == true) then
            return Fail(NAME, "pressing it on Always Ask stored " .. tostring(stored))
        end

        -- **A macro takes no target and still has the row** (2026-09-15, owner): its self and
        -- focus twins aim at a unit, and that is what the row asks.
        local macro = InsertAction({ type = Constants.MACROTEXT, value = "/say x", key = "CTRL-ALT-F8" })
        ApplyBindings()
        units, err = Group(macro, LLL["CONDITION_UNITS"])
        if not units then return Fail(NAME, err) end
        row = ChildByText(units, LLL["RESOLVED_TARGET"])
        if not row or not row:IsEnabled() then
            return Fail(NAME, "on a macro the row is " .. (row and "locked" or "missing"))
        end
        exists = ChildByText(row, LLL["CONDITION_UNIT_EXISTS"])
        if not exists then
            return Fail(NAME, format("no [%s] entry on a macro: %s", LLL["CONDITION_UNIT_EXISTS"], ChildTexts(row)))
        end
        exists:Pick(MenuInputContext.MouseButton, "LeftButton")
        stored = macro.conditions and macro.conditions.units and macro.conditions.units["@"]
        if not (type(stored) == "table" and stored.exists == true) then
            return Fail(NAME, "pressing it on a macro stored " .. tostring(stored))
        end

        return Pass(NAME, "under Units, stores \"@\" with no target, on Always Ask and on a macro")
    end,
})

--- **Needs the game** for the menu half: the box's place under Resolved Unit, that it is never
--- locked, and the setter a press on it reaches are the client's menu tree. The press half runs the
--- real snippet on a target the reader cannot be asked to set up, so its life is injected
--- ("State injection: dead flips a binding" does the same). Which binding wins each press is headless
--- (`tests/eval_spec.lua`, §6 #73 to #89).
RegisterTest("Resolved Unit: the box below the row stores the option, and the press stops asking the row", {
    description = "Resolved Unit 메뉴의 체크박스가 casting.usualIgnoresResolvedUnit을 쓰고 지우며, 대상을 골라도 잠기지 않는다. 켜면 현재 대상이 조건에 안 맞아도 그냥 누름이 나가고, 끄면 다시 안 나간다",
    run = function()
        local NAME = "Resolved Unit box"
        local KEY = "CTRL-ALT-F5"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end
        AddTeardown(function() Menu.GetManager():CloseMenus() end)

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        local function ChildByText(description, text)
            for _, child in description:EnumerateElementDescriptions() do
                if MenuUtil.GetElementText(child) == text then
                    return child
                end
            end
        end

        local function ChildTexts(description)
            local names = {}
            for _, child in description:EnumerateElementDescriptions() do
                tinsert(names, tostring(MenuUtil.GetElementText(child)))
            end
            return table.concat(names, " | ")
        end

        --- The box, in the menu opened afresh on `action`.
        local function Box(action)
            Menu.GetManager():CloseMenus()
            MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupActionDropdownMenu, { actions = { action } })
            local menu = Menu.GetManager():GetOpenMenu()
            if not menu then
                return nil, "the menu did not come up"
            end
            local units
            menu:EnumerateElementDescriptions(function(_, description)
                if MenuUtil.GetElementText(description) == LLL["CONDITION_UNITS"] then
                    units = description
                end
            end)
            if not units then
                return nil, format("no [%s] group", LLL["CONDITION_UNITS"])
            end
            local row = ChildByText(units, LLL["RESOLVED_TARGET"])
            if not row then
                return nil, format("no [%s] row: %s", LLL["RESOLVED_TARGET"], ChildTexts(units))
            end
            local box = ChildByText(row, LLL["RESOLVED_TARGET_USUAL"])
            if not box then
                return nil, format("no [%s] box: %s", LLL["RESOLVED_TARGET_USUAL"], ChildTexts(row))
            end
            return box
        end

        -- Asked of the target, which the injection holds alive, so the row never holds.
        local action = InsertAction({ type = Constants.SPELL, value = 585, key = KEY,
            units = { ["@"] = { exists = true, dead = true } } })
        ApplyBindings()
        SetMockState("target-dead", false)

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("before the box, a press fired #%d against a row that cannot hold", LastWinner()))
        end

        local box, err = Box(action)
        if not box then return Fail(NAME, err) end
        box:Pick(MenuInputContext.MouseButton, "LeftButton")
        if not (action.casting and action.casting.usualIgnoresResolvedUnit == true) then
            return Fail(NAME, "ticking the box stored " .. tostring(action.casting and action.casting.usualIgnoresResolvedUnit))
        end
        ApplyBindings()
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local ticked = WaitForWinner()
        if ticked == nil then
            return Fail(NAME, "with the box ticked the press still asked the row and fired nothing")
        end

        -- Unticked, the row is asked again. Without this half a key that fires whatever the box says
        -- passes too.
        box, err = Box(action)
        if not box then return Fail(NAME, err) end
        box:Pick(MenuInputContext.MouseButton, "LeftButton")
        if action.casting and action.casting.usualIgnoresResolvedUnit ~= nil then
            return Fail(NAME, "unticking the box left " .. tostring(action.casting.usualIgnoresResolvedUnit))
        end
        ApplyBindings()
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("unticked, the press fired #%d", LastWinner()))
        end

        -- **Not locked where it does nothing** (`falling-back-when-the-resolved-unit-fails.md` 3-6).
        local picked = InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F4", unit = "focus",
            units = { ["@"] = { exists = true } } })
        ApplyBindings()
        box, err = Box(picked)
        if not box then return Fail(NAME, err) end
        if not box:IsEnabled() then
            return Fail(NAME, "the box is locked on an action with a unit picked")
        end

        return Pass(NAME, format("stored and cleared from the menu; ticked, the press fired #%d", ticked))
    end,
})

--- **The menu is the only writer of the field, and which setter a press on it reaches is the client's
--- menu tree.** What the press stores, and the twin it turns into, is measured here; which record
--- wins a press with the key held is `tests/eval_spec.lua`'s.
RegisterTest("Menu: casting a cast key as usual aims that key's twin where the action goes", {
    description = "Casting 메뉴의 조합키 줄에서 [Cast as usual]이 casting 값을 쓰고, 그 조합키의 쌍둥이가 액션의 대상을 겨눈다",
    run = function()
        local NAME = "Cast as usual row"
        local KEY = "CTRL-ALT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end
        AddTeardown(function() Menu.GetManager():CloseMenus() end)

        -- **No target picked**: a picked unit is not moved by the key at all, so aiming its twin could
        -- not be told from leaving it alone, and the row stands locked there.
        local action = InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        ApplyBindings()

        local function ChildByText(description, text)
            for _, child in description:EnumerateElementDescriptions() do
                if MenuUtil.GetElementText(child) == text then
                    return child
                end
            end
        end

        local function ChildTexts(description)
            local names = {}
            for _, child in description:EnumerateElementDescriptions() do
                tinsert(names, tostring(MenuUtil.GetElementText(child)))
            end
            return table.concat(names, " | ")
        end

        local seen = {}
        for _, case in ipairs({
            { label = AUTO_SELF_CAST_KEY_TEXT, row = "selfCastKey", castModifier = Constants.CASTMOD_SELF },
            { label = FOCUS_CAST_KEY_TEXT, row = "focusCastKey", castModifier = Constants.CASTMOD_FOCUS },
        }) do
            Menu.GetManager():CloseMenus()
            MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupActionDropdownMenu, { actions = { action } })
            local menu = Menu.GetManager():GetOpenMenu()
            if not menu then
                return Fail(NAME, "the menu did not come up")
            end
            local casting
            menu:EnumerateElementDescriptions(function(_, description)
                if MenuUtil.GetElementText(description) == LLL["CASTING"] then
                    casting = description
                end
            end)
            if not casting then
                return Fail(NAME, format("no [%s] group in the action's menu", LLL["CASTING"]))
            end
            local keyRow = ChildByText(casting, case.label)
            if not keyRow then
                return Fail(NAME, format("no [%s] row under [%s]: %s", case.label, LLL["CASTING"],
                    ChildTexts(casting)))
            end
            local box = ChildByText(keyRow, LLL["CASTING_AS_USUAL"])
            if not box then
                return Fail(NAME, format("no [%s] row under [%s]: %s", LLL["CASTING_AS_USUAL"],
                    case.label, ChildTexts(keyRow)))
            end

            box:Pick(MenuInputContext.MouseButton, "LeftButton")
            local stored = action.casting and action.casting[case.row]
            if stored ~= "usual" then
                return Fail(NAME, format("pressing [%s] stored %s", LLL["CASTING_AS_USUAL"],
                    tostring(stored)))
            end

            local function TwinOnKey()
                for _, binding in ipairs(GetKeyBindings(KEY) or {}) do
                    if binding.castModifier == case.castModifier and binding.type ~= Constants.BLOCK then
                        return binding
                    end
                end
            end

            ApplyBindings()
            local twin = TwinOnKey()
            if not twin or twin.unit ~= nil then
                return Fail(NAME, format("%s: the twin aims at %s", case.row,
                    tostring(twin and twin.unit)))
            end

            -- **Off takes that twin away.** Measuring the aim alone would never show the other value
            -- failing to reach the same field.
            action.casting[case.row] = "skip"
            ApplyBindings()
            if TwinOnKey() then
                return Fail(NAME, format("%s, off: the twin is still on %s", case.row, KEY))
            end

            action.casting[case.row] = nil
            ApplyBindings()
            seen[#seen + 1] = case.row
        end

        return Pass(NAME, table.concat(seen, ", ") .. " aimed where the action goes, then skipped")
    end,
})

--- **The three radios are the only thing that writes a unit condition's mode.** What the writer
--- stores is `tests/actionmenu_spec.lua`'s too; what is left to the game is that pressing each row of
--- the client's menu reaches it with the right mode.
---
--- What it is guarding is the shape rather than the wording. A mode that leaves no value behind
--- rides on the table being empty, and the rest of the addon reads an empty table as nothing at
--- all -- `ActionSignature` folds one away, which is what made a unit-conditioned action and an
--- unconditional one come out as duplicates of each other.
RegisterTest("Unit condition: each mode writes a value of its own", {
    description = "[When it exists] stores exists, [Disable] stores disabled and keeps the axes, and a mode with nothing to remember leaves no table behind",
    run = function()
        local NAME = "Unit condition modes"

        local action = InsertAction({ type = Constants.SPELL, value = 1, key = "CTRL-ALT-F7" })
        ApplyBindings()

        AddTeardown(CleanupActions)
        AddTeardown(function()
            Menu.GetManager():CloseMenus()
        end)

        --- 이름으로 자식 하나. **한 겹씩 좁혀 들어간다** - [사용 안 함]은 이 트리의 여러
        --- 묶음에 있어서 통째로 뒤지면 남의 것을 누른다.
        local function ChildByText(description, text)
            for _, child in description:EnumerateElementDescriptions() do
                if MenuUtil.GetElementText(child) == text then
                    return child
                end
            end
        end

        --- 실패했을 때 무엇이 거기 있었는지. 이름으로 찾아 누르는 테스트라, 못 찾았는지
        --- 눌렀는데 안 먹었는지가 갈려야 다음 판에서 고칠 자리가 나온다.
        local function ChildTexts(description)
            local names = {}
            for _, child in description:EnumerateElementDescriptions() do
                tinsert(names, tostring(MenuUtil.GetElementText(child)))
            end
            return table.concat(names, " | ")
        end

        local function StoredCondition()
            local conditions = action.conditions
            local units = conditions and conditions.units
            return units and units.target
        end

        local function DescribeStored()
            local cond = StoredCondition()
            if type(cond) ~= "table" then
                return tostring(cond)
            end
            return format("exists=%s disabled=%s reaction=%s",
                tostring(cond.exists), tostring(cond.disabled), tostring(cond.reaction))
        end

        --- 메뉴를 새로 열고 `target` 유닛의 서브메뉴를 집는다. 누를 때마다 다시 여는 것은
        --- 값이 바뀌면 라디오가 다시 그려지기 때문이다.
        local function TargetSubmenu()
            Menu.GetManager():CloseMenus()
            MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupActionDropdownMenu, { actions = { action } })
            local menu = Menu.GetManager():GetOpenMenu()
            if not menu then
                return nil, "the menu did not come up"
            end
            local units
            menu:EnumerateElementDescriptions(function(_, description)
                if MenuUtil.GetElementText(description) == LLL["CONDITION_UNITS"] then
                    units = description
                end
            end)
            if not units then
                return nil, format("no [%s] group", LLL["CONDITION_UNITS"])
            end
            local target = ChildByText(units, DebindUI.UNIT_INFO.target.name)
            if not target then
                return nil, format("no [%s] row under it: %s",
                    DebindUI.UNIT_INFO.target.name, ChildTexts(units))
            end
            return target
        end

        --- 하나 누르고, 그 자리에서 값이 움직였는지 본다. **`Pick`이 거짓을 돌려주는 것과 값이
        --- 안 움직이는 것은 다른 고장이다** - 앞은 그 줄이 잠긴 것이고 뒤는 setter가 딴 값을
        --- 쓴 것이라, 실패 문구가 둘을 갈라야 한다.
        local function Press(text, settled)
            local submenu, err = TargetSubmenu()
            if not submenu then
                return err
            end
            local item = ChildByText(submenu, text)
            if not item then
                return format("no [%s] entry: %s", text, ChildTexts(submenu))
            end
            local picked = item:Pick(MenuInputContext.MouseButton, "LeftButton")
            if settled and not settled() then
                return format("[%s] did not take (Pick said %s): %s",
                    text, tostring(picked), DescribeStored())
            end
        end

        local err = Press(LLL["CONDITION_UNIT_EXISTS"], function()
            local cond = StoredCondition()
            return type(cond) == "table" and cond.exists == true
        end)
        if err then
            return Fail(NAME, err)
        end

        -- 축을 하나 골라둔다. 그래야 아래 [사용 안 함]이 기억하는 갈래로 간다.
        err = Press(LLL["REACTION_HELP"], function()
            local cond = StoredCondition()
            return type(cond) == "table" and cond.reaction ~= nil
        end)
        if err then
            return Fail(NAME, err)
        end

        err = Press(LLL["DISABLE"], function()
            local cond = StoredCondition()
            return type(cond) == "table" and cond.disabled == true and cond.exists == nil
        end)
        if err then
            return Fail(NAME, err)
        end
        if StoredCondition().reaction == nil then
            return Fail(NAME, "the axis it was told to remember is gone")
        end

        -- 기억할 축이 없는 조건을 끄면 그 유닛이 통째로 빠진다. 여기서 빈 표가 남으면 아무것도
        -- 안 고른 유닛이 프로필에 쌓인다.
        local kept = action
        action = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F7" })
        ApplyBindings()

        err = Press(LLL["CONDITION_UNIT_EXISTS"], function()
            local cond = StoredCondition()
            return type(cond) == "table" and cond.exists == true
        end)
        if err then
            action = kept
            return Fail(NAME, err)
        end
        err = Press(LLL["DISABLE"], function()
            return StoredCondition() == nil
        end)
        if err then
            action = kept
            return Fail(NAME, err)
        end

        action = kept
        return Pass(NAME, "the modes wrote exists and disabled, the axes survived being turned off, and nothing was left behind where there was nothing to remember")
    end,
})

--- The mode's own way in. **Four things have to line up for one press, and three of them are silent
--- when they do not**: the widget key the frame reaches for (`BindModePortrait` -- a wrong one is a
--- nil index, but only when someone presses it), the XML `OnClick`, the keyboard staying off this
--- button (it holds one from birth, and the mode's keys belong to the row under the cursor), and
--- the lit ring that is the only thing on screen saying selecting and the menu have stopped.
---
--- All four moved on the same day the toggle became a portrait: it used to be a labelled button
--- above the left column, wearing a square silver texture and carrying its state in its text.
---
--- **This does not measure what `RegisterForClicks` receives.** `Click()` reaches `OnClick`
--- whatever the registration says (the same limit the key group popup test writes down).
RegisterTest("Bind mode: the portrait toggle turns the mode on and off", {
    description = "The toggle on the portrait row turns the mode on, and the keyboard and the lit state follow",
    run = function()
        local NAME = "Bind mode toggle"

        -- The window has to be up. The portrait builds itself on its first `OnShow`
        -- (`DebindPortraitMixin`), and before that neither the tooltip fields nor the textures are on it.
        DebindFrame:Show()
        AddTeardown(function()
            DebindFrame:SetBindingMode(false)
            DebindFrame:CloseWindow()
        end)

        local toggle = DebindFrame.OverviewPanel.PortraitRow.BindModePortrait
        if not toggle then
            return Fail(NAME, "no BindModePortrait, has the parentKey in the XML changed")
        end
        if DebindFrame:IsCapturingKey() then
            return Fail(NAME, "the mode was on from the start")
        end

        toggle:Click()

        if not DebindFrame:IsCapturingKey() then
            return Fail(NAME, "pressed it and the mode did not come on")
        end
        -- **The keyboard is not this button's, on or off.** It belongs to the row under the cursor
        -- while the mode is on (`DebindLayerRowMixin:Update`), because a key pressed off a row has no
        -- row to land on and eating it there costs the reader every key in the game. This button
        -- holds the keyboard from the moment it is built, so the assertion is that it was taken
        -- away and stays away (`DebindUI.xml`).
        if toggle:IsKeyboardEnabled() then
            return Fail(NAME, "the mode is on and this button is eating the keys instead of the row")
        end
        -- The lit state is the border (`SetSelectedState`): the colour comes back and the dark plate
        -- over it goes down.
        if toggle.Frame:IsDesaturated() or toggle.UnselectedFrame:IsShown() then
            return Fail(NAME, "it is on and the border is still in its dark shape")
        end
        if toggle.TooltipTitle ~= LLL["BIND_MODE_STOP"] then
            return Fail(NAME, format("the tooltip title did not change: %s", tostring(toggle.TooltipTitle)))
        end

        toggle:Click()

        if DebindFrame:IsCapturingKey() then
            return Fail(NAME, "pressed again and the mode did not go off")
        end
        if toggle:IsKeyboardEnabled() then
            return Fail(NAME, "the mode is off and this button is listening to the keyboard again")
        end
        if not toggle.Frame:IsDesaturated() or not toggle.UnselectedFrame:IsShown() then
            return Fail(NAME, "it is off and the lit state is still on it")
        end
        if toggle.TooltipTitle ~= LLL["BIND_MODE"] or toggle.TooltipText ~= LLL["BIND_MODE_DESC"] then
            return Fail(NAME, format("the tooltip did not come back: %s / %s",
                tostring(toggle.TooltipTitle), tostring(toggle.TooltipText)))
        end

        return Pass(NAME, "one toggle moved the mode, the border and the tooltip, and left the keyboard alone")
    end,
})
