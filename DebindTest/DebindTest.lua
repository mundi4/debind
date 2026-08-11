-- DebindTest: Integration test framework for Debind addon
-- Usage: /debtest to run all tests, /debtest ui to open UI
-- Requires DEBUG mode (DebindPrivate must be exposed as global)

local DebindPrivate = _G.DebindPrivate
if not DebindPrivate then
    print("|cffff0000[DebindTest]|r DebindPrivate not found. Enable DEBUG mode in Constants.lua.")
    return
end

local Constants = DebindPrivate.Constants
local band, bor = bit.band, bit.bor

-----------------------------------------------------------
-- Test Framework
-----------------------------------------------------------

local tests = {}

--- The window, filled in further down. Declared up here because the tests and the runner both
--- drive it and both are defined before it -- the runner ticks rows as it goes, and a test that
--- needs a click asks it to show one.
local UI = {}
local testOrder = {}
local results = {}

local function RegisterTest(name, opts)
    tests[name] = opts
    tinsert(testOrder, name)
end

local function Pass(name, detail)
    return true, format("|cff00ff00PASS|r %s%s", name, detail and (" - " .. detail) or "")
end

local function Fail(name, reason)
    return false, format("|cffff0000FAIL|r %s: %s", name, reason or "unknown")
end

-----------------------------------------------------------
-- Waiting & Teardown
-----------------------------------------------------------

-- Tests run as coroutines so they can wait. Waiting is not a convenience here: nothing this
-- addon does lands in the frame it was asked for. The state driver polls on its own 0.2s beat,
-- `_onattributechanged` propagates afterwards, `CallMethod` is queued rather than called, and
-- `DirtyFlags` only reaches `UpdateBindings` on the next pass. A test that sets something up and
-- reads it back in the same breath reads the old value and calls it a result.
--
-- **Tests that never yield are unaffected.** A coroutine that runs straight through finishes on
-- its first resume, and the runner steps to the next one without giving up the frame, so a suite
-- of them still completes in a single frame exactly as it did before.

--- Hands the frame back for `seconds` (or until the next one, if omitted or 0).
local function Wait(seconds)
    coroutine.yield(seconds or 0)
end

-- Saved variables are not in place while this file runs -- they arrive between then and
-- ADDON_LOADED -- so the table is never assumed, only ensured.
local function DB()
    DebindTestDB = DebindTestDB or {}
    return DebindTestDB
end

--- Somewhere a test may leave things for a later phase of itself.
---
--- It has to be here rather than in the profile: the runner tears down and cleans up **before**
--- reloading, so anything a test put in a layer is gone by the time the session comes back. That
--- is deliberate -- a run that ends the session must not leave the profile carrying its litter --
--- and it means "survives a reload" has to be stored somewhere the runner does not clean.
local function Scratch()
    local db = DB()
    db.scratch = db.scratch or {}
    return db.scratch
end

-- Asking for a `/reload` is not a longer wait, so it does not travel as one. This marker is what
-- the runner recognises, and it cannot collide with a duration.
local RELOAD_REQUEST = {}

--- Ends the game session and picks this same test back up afterwards, with `phase` telling it
--- where it left off.
---
--- **This call does not return.** A coroutine does not survive a reload, so the test is not
--- resumed -- it is *run again from the top*, and reads `phase` to find its place. Which makes a
--- reload-crossing test a small state machine rather than one straight line:
---
---     run = function(phase)
---         if not phase then ... ; return RequestReload("after") end
---         ...
---     end
---
--- The runner writes its progress out before reloading, so what a later phase compares against
--- is what actually survived the round trip.
local function RequestReload(phase)
    coroutine.yield(RELOAD_REQUEST, phase or "after-reload")
    -- Unreachable: the runner reloads instead of resuming. Erroring here beats returning to a
    -- test that believes a reload happened when none did.
    error("RequestReload: 리로드가 일어나지 않았다")
end

-- Undo registered by whatever needs undoing. **The runner calls these, not the test.** A test
-- that owns its own cleanup only has to be wrong once -- fail early, error, or simply forget --
-- and everything after it runs against a state nobody chose. So the tail is not the test's to
-- run; it belongs to the loop that knows the test ended, however it ended.
local teardowns = {}

local function AddTeardown(fn)
    tinsert(teardowns, fn)
end

--- Runs every registered undo, newest first, and clears the list. Each one is isolated: an undo
--- that throws must not keep the ones after it from running, which is the whole point of having
--- them here.
local function RunTeardowns()
    for i = #teardowns, 1, -1 do
        local ok, err = pcall(teardowns[i])
        if not ok then
            print(format("|cffff8800[DebindTest]|r teardown failed: %s", tostring(err)))
        end
    end
    wipe(teardowns)
end

-----------------------------------------------------------
-- Test Helpers: Setup & Teardown
-----------------------------------------------------------

-- GENERAL layer (layerID=1)에 테스트 액션을 삽입하고 UpdateBindings 실행
local GENERAL_LAYER_ID = 1

local function GetGeneralLayer()
    return DebindPrivate.GetProfileLayer(GENERAL_LAYER_ID)
end

local insertedActions = {}

local function InsertAction(action)
    local layer = GetGeneralLayer()
    layer:Insert(action)
    -- 순서 번호는 레이어가 준다. 안 주면 같은 조건끼리 seq가 전부 nil이라 발동 순서가
    -- 정해지지 않고, 삽입 순서를 기대하는 테스트가 정렬 구현에 따라 흔들린다.
    layer:PlaceLast(action)
    tinsert(insertedActions, action)
    return action
end

local function CleanupActions()
    local layer = GetGeneralLayer()
    for _, action in ipairs(insertedActions) do
        layer:Remove(action)
    end
    wipe(insertedActions)
    -- rebuild to clean state
    if not InCombatLockdown() then
        DebindPrivate.UpdateBindings()
    end
end

local function ApplyBindings()
    DebindPrivate.UpdateBindings()
end

-- KeyMap에서 특정 키에 바인딩된 정보 찾기
local function GetKeyBindings(key)
    local keyMap = DebindPrivate.KeyMap
    return keyMap[key]
end

-- KeyMap에서 특정 키의 N번째 바인딩 정보
local function GetNthBinding(key, n)
    local bindings = GetKeyBindings(key)
    return bindings and bindings[n]
end

-- DefaultClickFrame의 attribute 확인
local function GetClickAttribute(attrPrefix, buttonName)
    local frame = DebindPrivate.DefaultClickFrame
    return frame:GetAttribute(attrPrefix .. buttonName)
end

-----------------------------------------------------------
-- Test Helpers: State Injection
-----------------------------------------------------------

-- **Telling the secure side it is in combat while the client is not.**
--
-- Debind decides from `States.combat`, so an override there drives every combat path. The client
-- is not actually in combat, so no lockdown applies and the insecure side can still click, bind
-- and write attributes -- which is the whole trick. In a real fight the code is reachable but
-- nothing outside can drive it; here it is drivable but nothing stops it.
--
-- The same applies to every axis Debind watches, not only combat. A condition is a combination --
-- `[combat, harm, form:2]` -- and checking one means standing all three up at once. An axis that
-- still has to come from the world puts the test back on a raid schedule.
--
-- Nothing is written into `States` directly: the poll would put the real value back within 0.2s.
-- The override sits at the one point where the freshly computed value is about to be stored, so
-- the update loop runs exactly as it always does.
--
-- Debind carries none of this. It emits a line supplied from here, and for anyone without this
-- addon there is no line and the snippet is what it always was.
-- `%1$q` twice, not `%q` twice. `appendLine` is `format(str, ...)` and it gets one argument, so a
-- second plain `%q` has nothing to consume -- which came out as a snippet missing an `end`, not
-- as a format error. The generated line right below this one uses the positional form for the
-- same reason.
local MOCK_STATE_LINE =
    [[if (MockStatesMap[%1$q] ~= nil) then stateValue = MockStatesMap[%1$q] end]]

local mockStates = {}
local mockPlanted = false

--- Puts the table the injected line reads inside Debind's secure environment.
---
--- It lives there rather than in Debind because the line that reads it is ours: the table and the
--- line that needs it arrive together, and neither exists for a real user.
local function PlantMockTable()
    if mockPlanted then return end
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        if (not MockStatesMap) then MockStatesMap = newtable() end
    ]])
    mockPlanted = true
end

--- Forces `state` to `value` from the next update on. `nil` releases it.
---
--- The bindings are rebuilt because the override rides in the generated snippet -- a state that
--- has never been mocked has no line to read the table.
local function SetMockState(state, value)
    PlantMockTable()

    DebindPrivate.SnippetProbes = DebindPrivate.SnippetProbes or {}
    DebindPrivate.SnippetProbes.stateValue = MOCK_STATE_LINE

    mockStates[state] = value

    SecureHandlerExecute(DebindPrivate.BindingDriver, format(
        value == nil and [[MockStatesMap[%q] = nil]] or [[MockStatesMap[%q] = %s]],
        state, tostring(value)))

    -- Releasing is registered the moment something is held, so a test that fails in the middle
    -- does not leave the game believing it is in combat.
    AddTeardown(function()
        mockStates[state] = nil
        SecureHandlerExecute(DebindPrivate.BindingDriver, format([[MockStatesMap[%q] = nil]], state))

        -- With nothing held any more, the line stops being emitted at all -- the generated
        -- snippet goes back to being exactly the one a real user gets, rather than the one that
        -- merely reads an empty table.
        --
        -- Only this key is cleared. `SnippetProbes` also carries the bake-time table, and the two
        -- are switched on and off independently.
        if next(mockStates) == nil and DebindPrivate.SnippetProbes then
            DebindPrivate.SnippetProbes.stateValue = nil
        end

        if not InCombatLockdown() then
            DebindPrivate.UpdateBindings()
        end
    end)

    ApplyBindings()
end

--- What this addon currently holds `state` at, or nil if it is not holding it.
local function GetMockState(state)
    return mockStates[state]
end

-----------------------------------------------------------
-- Test Helpers: Snippet Probes
-----------------------------------------------------------

-- Turning a probe on means **baking the bodies again**, not flipping a flag the snippet reads.
-- Bodies are baked while Debind loads, which is necessarily before this addon exists, so the
-- decision cannot have been made then. `RebakeSnippets` rebuilds them from the raw text.
--
-- That is also what makes switching honest in the other direction: probes off is not a snippet
-- reading an empty table, it is the snippet a real user runs, rebuilt from the same source.
local probeReports = {}
local probesOn = false

--- What `PROBE.Winner(i)` becomes while probing. `debind_driver` rather than `self`, because the
--- wrapper runs with the click frame as `self` and the method lives on the driver.
local PROBE_DEV = {
    Winner = [[debind_driver:CallMethod("DebindTestWinner", %s)]],
}

local function BuildExpandTable()
    local expand = {}
    for name, form in pairs(DebindPrivate.SNIPPET_PROBES_LIVE) do
        expand[name] = form
    end
    for name, form in pairs(PROBE_DEV) do
        expand[name] = form
    end
    return expand
end

--- Starts reporting from inside the snippets. Returns nil plus a reason if it could not.
local function EnableProbes()
    if probesOn then return true end

    DebindPrivate.BindingDriver.DebindTestWinner = function(_, index)
        probeReports[#probeReports + 1] = index
    end

    DebindPrivate.SnippetProbes = DebindPrivate.SnippetProbes or {}
    DebindPrivate.SnippetProbes.expand = BuildExpandTable()

    local ok, err = DebindPrivate.RebakeSnippets()
    if not ok then
        DebindPrivate.SnippetProbes.expand = nil
        return nil, tostring(err)
    end

    probesOn = true

    AddTeardown(function()
        probesOn = false
        wipe(probeReports)
        if DebindPrivate.SnippetProbes then
            DebindPrivate.SnippetProbes.expand = nil
        end
        DebindPrivate.RebakeSnippets()
    end)

    return true
end

--- Presses the key, the way the game would. A click-time key does not decide anything until it
--- is pressed -- the whole point of that path is that the winner is chosen at the press -- so
--- this is the only way to reach the decision at all.
---
--- The action attached to the winner really does run. In a session set aside for testing that is
--- not a cost worth designing around; the tests use macro bodies that do nothing so the output
--- stays readable, not to avoid consequences.
local function PressKey(key)
    local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[key]
    if not button then
        return nil, format("%s 는 클릭 시점 키가 아니다 (ClickTimeKeys에 없음)", key)
    end

    wipe(probeReports)
    DebindPrivate.DefaultClickFrame:Click(button)
    return true
end

--- The record index the snippet last reported as the winner, or nil if it reported none.
--- `CallMethod` is queued rather than called, so this needs a `Wait` after the press.
local function LastWinner()
    return probeReports[#probeReports]
end

-----------------------------------------------------------
-- Test Helpers: Unit Frames
-----------------------------------------------------------

-- A unit frame the test owns, registered through the same path a real one takes. Owning it is
-- what makes the hover slot reachable at all: the frame is where `unit` is read from, both when
-- the cursor arrives and on every poll after, so a frame we can write to is a hover state we can
-- set. Nothing is faked -- the attribute read, the registration, and the reaction lookup are the
-- shipped ones.
--
-- **Frames are never destroyed in WoW**, so they are reused by name across runs. Teardown
-- unregisters rather than disposing.
local UNIT_TOKEN_ABSENT = "debindtest_absent"

local testFrameCount = 0

local function CreateTestUnitFrame(unit, frameType)
    testFrameCount = testFrameCount + 1

    local name = "DebindTestUnitFrame" .. testFrameCount
    local frame = _G[name] or CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")

    -- **Frames are reused by name, so everything a previous run did to one has to be undone
    -- here.** A test that showed this frame to be clicked left it parented into the window and
    -- sized to fill it; the next run's hover test would then drive a frame that is not where it
    -- thinks it is. That is not hypothetical -- it broke the hover test exactly once.
    frame:SetParent(UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    frame:SetSize(1, 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    frame:SetAttribute("unit", unit)
    frame:Show()

    DebindPrivate.RegisterFrame(frame, frameType or "group")

    AddTeardown(function()
        DebindPrivate.UnregisterFrame(frame)
        frame:Hide()
    end)

    -- `RegisterFrame` refuses quietly, and it records that refusal as `false` so the next attempt
    -- refuses too. Left unchecked the test would drive a frame the addon is not watching and
    -- report whatever the empty hover slot happened to say.
    local registered = DebindPrivate.ccframes[frame]
    if type(registered) ~= "table" then
        return nil, format("RegisterFrame이 %s를 안 받았다 (ccframes=%s)", name, tostring(registered))
    end

    return frame
end

--- Points the frame at another unit. This is the whole simulation of "the unit under the cursor
--- changed": neither enter nor leave fires while the cursor sits still, and what the poll reads
--- is this attribute.
local function SetFrameUnit(frame, unit)
    frame:SetAttribute("unit", unit)
end

--- Drives the real `setup_onenter` / `setup_onleave` for a frame. The wrapped scripts run the
--- same snippets; there is no way to make the game fire OnEnter on demand, so the snippet is run
--- directly with the frame as `self`, which is exactly what the wrapper does.
local function HoverEnter(frame)
    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_hover", frame)
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        self:RunFor(self:GetFrameRef("debindtest_hover"), self:GetAttribute("setup_onenter"))
    ]])
end

local function HoverLeave(frame)
    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_hover", frame)
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        self:RunFor(self:GetFrameRef("debindtest_hover"), self:GetAttribute("setup_onleave"))
    ]])
end

--- What the secure side currently calls the hovered unit, as seen from outside. The secure
--- `SetUnit` mirrors it out through `CallMethod`, which is queued rather than immediate -- so
--- this is only true after a `Wait`, never in the same breath as the change that caused it.
local function GetHoverUnit()
    return DebindPrivate.Units.hover
end

-----------------------------------------------------------
-- Test Cases: Action Types
-----------------------------------------------------------

RegisterTest("Spell binding", {
    description = "주문 타입 액션이 바인딩되고 attribute가 설정되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD1" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD1", 1)
        if not b then return Fail("Spell binding", "NUMPAD1 not in KeyMap") end
        if b.type ~= Constants.SPELL then return Fail("Spell binding", "type=" .. tostring(b.type)) end
        if not b.clickbutton then return Fail("Spell binding", "no clickbutton assigned") end
        local spellAttr = GetClickAttribute("*type-", b.clickbutton)
        if spellAttr ~= "spell" then return Fail("Spell binding", "*type-=" .. tostring(spellAttr)) end
        return Pass("Spell binding", "clickbutton=" .. b.clickbutton)
    end,
})

RegisterTest("Item binding", {
    description = "아이템 타입 액션이 바인딩되는지",
    run = function()
        InsertAction({ type = Constants.ITEM, value = 6948, key = "NUMPAD2" }) -- Hearthstone
        ApplyBindings()
        local b = GetNthBinding("NUMPAD2", 1)
        if not b then return Fail("Item binding", "NUMPAD2 not in KeyMap") end
        local typeAttr = GetClickAttribute("*type-", b.clickbutton)
        if typeAttr ~= "item" then return Fail("Item binding", "*type-=" .. tostring(typeAttr)) end
        local itemAttr = GetClickAttribute("*item-", b.clickbutton)
        if itemAttr ~= "item:6948" then return Fail("Item binding", "*item-=" .. tostring(itemAttr)) end
        return Pass("Item binding")
    end,
})

RegisterTest("Macrotext binding", {
    description = "매크로텍스트 액션이 바인딩되는지",
    run = function()
        InsertAction({ type = Constants.MACROTEXT, value = "/say test", key = "NUMPAD3", name = "test macro" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD3", 1)
        if not b then return Fail("Macrotext binding", "NUMPAD3 not in KeyMap") end
        local typeAttr = GetClickAttribute("*type-", b.clickbutton)
        if typeAttr ~= "macro" then return Fail("Macrotext binding", "*type-=" .. tostring(typeAttr)) end
        return Pass("Macrotext binding")
    end,
})

RegisterTest("Command binding", {
    description = "커맨드 타입은 SetOverrideBinding 방식 - KeyMap에 들어가는지",
    run = function()
        InsertAction({ type = Constants.COMMAND, value = "TOGGLECHARACTER0", key = "NUMPAD4" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD4", 1)
        if not b then return Fail("Command binding", "NUMPAD4 not in KeyMap") end
        if b.type ~= Constants.COMMAND then return Fail("Command binding", "type=" .. tostring(b.type)) end
        return Pass("Command binding")
    end,
})

RegisterTest("Target binding", {
    description = "대상 지정 액션이 바인딩되는지",
    run = function()
        InsertAction({ type = Constants.TARGET, key = "NUMPAD5", unit = "focus" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD5", 1)
        if not b then return Fail("Target binding", "NUMPAD5 not in KeyMap") end
        local typeAttr = GetClickAttribute("*type-", b.clickbutton)
        if typeAttr ~= "target" then return Fail("Target binding", "*type-=" .. tostring(typeAttr)) end
        return Pass("Target binding")
    end,
})

RegisterTest("Unused binding", {
    description = "UNUSED 타입은 attribute 없이 KeyMap에만 존재하는지",
    run = function()
        InsertAction({ type = Constants.UNUSED, key = "NUMPAD6" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD6", 1)
        if not b then return Fail("Unused binding", "NUMPAD6 not in KeyMap") end
        if b.type ~= Constants.UNUSED then return Fail("Unused binding", "type=" .. tostring(b.type)) end
        return Pass("Unused binding")
    end,
})

-----------------------------------------------------------
-- Test Cases: Conditions
-----------------------------------------------------------

RegisterTest("Combat condition", {
    description = "전투 조건이 바인딩 정보에 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD7", combat = true })
        InsertAction({ type = Constants.SPELL, value = 116, key = "NUMPAD7", combat = false })
        ApplyBindings()
        local bindings = GetKeyBindings("NUMPAD7")
        if not bindings or #bindings < 2 then
            return Fail("Combat condition", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        local hasCombatTrue, hasCombatFalse = false, false
        for i = 1, #bindings do
            if bindings[i].combat == true then hasCombatTrue = true end
            if bindings[i].combat == false then hasCombatFalse = true end
        end
        if not (hasCombatTrue and hasCombatFalse) then
            return Fail("Combat condition", format("combatTrue=%s, combatFalse=%s", tostring(hasCombatTrue), tostring(hasCombatFalse)))
        end
        return Pass("Combat condition", "2 bindings with combat true/false")
    end,
})

RegisterTest("Group condition", {
    description = "그룹 조건(파티/레이드) 비트플래그가 바인딩에 반영되는지",
    run = function()
        local groups = bor(Constants.GROUP_PARTY, Constants.GROUP_RAID)
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD8", groups = groups })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD8", 1)
        if not b then return Fail("Group condition", "NUMPAD8 not in KeyMap") end
        if b.groups ~= groups then
            return Fail("Group condition", format("expected groups=%d, got %s", groups, tostring(b.groups)))
        end
        return Pass("Group condition", format("groups=%d", b.groups))
    end,
})

RegisterTest("Stealth condition", {
    description = "은신 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD9", stealth = true })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD9", 1)
        if not b then return Fail("Stealth condition", "NUMPAD9 not in KeyMap") end
        if b.stealth ~= true then return Fail("Stealth condition", "stealth=" .. tostring(b.stealth)) end
        return Pass("Stealth condition")
    end,
})

RegisterTest("Pet condition", {
    description = "펫 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD0", pet = true })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD0", 1)
        if not b then return Fail("Pet condition", "NUMPAD0 not in KeyMap") end
        if b.pet ~= true then return Fail("Pet condition", "pet=" .. tostring(b.pet)) end
        return Pass("Pet condition")
    end,
})

RegisterTest("Forms condition", {
    description = "변신/자세 조건 비트플래그가 반영되는지",
    run = function()
        local forms = bor(2^0, 2^1) -- form 0 and form 1
        InsertAction({ type = Constants.SPELL, value = 585, key = "F5", forms = forms })
        ApplyBindings()
        local b = GetNthBinding("F5", 1)
        if not b then return Fail("Forms condition", "F5 not in KeyMap") end
        if b.forms ~= forms then
            return Fail("Forms condition", format("expected forms=%d, got %s", forms, tostring(b.forms)))
        end
        return Pass("Forms condition", format("forms=%d", b.forms))
    end,
})

RegisterTest("Bonusbars condition", {
    description = "보너스바 조건 비트플래그가 반영되는지",
    run = function()
        local bonusbars = bor(2^0, 2^1) -- bonusbar 0 and 1
        InsertAction({ type = Constants.SPELL, value = 585, key = "F6", bonusbars = bonusbars })
        ApplyBindings()
        local b = GetNthBinding("F6", 1)
        if not b then return Fail("Bonusbars condition", "F6 not in KeyMap") end
        if b.bonusbars ~= bonusbars then
            return Fail("Bonusbars condition", format("expected bonusbars=%d, got %s", bonusbars, tostring(b.bonusbars)))
        end
        return Pass("Bonusbars condition", format("bonusbars=%d", b.bonusbars))
    end,
})

RegisterTest("Specialbar condition", {
    description = "특수바(차량/변형) 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F7", specialbar = true })
        ApplyBindings()
        local b = GetNthBinding("F7", 1)
        if not b then return Fail("Specialbar condition", "F7 not in KeyMap") end
        if b.specialbar ~= true then return Fail("Specialbar condition", "specialbar=" .. tostring(b.specialbar)) end
        return Pass("Specialbar condition")
    end,
})

RegisterTest("Extrabar condition", {
    description = "추가 액션바 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F8", extrabar = true })
        ApplyBindings()
        local b = GetNthBinding("F8", 1)
        if not b then return Fail("Extrabar condition", "F8 not in KeyMap") end
        if b.extrabar ~= true then return Fail("Extrabar condition", "extrabar=" .. tostring(b.extrabar)) end
        return Pass("Extrabar condition")
    end,
})

RegisterTest("Petbattle condition", {
    description = "펫 배틀 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F9", petbattle = false })
        ApplyBindings()
        local b = GetNthBinding("F9", 1)
        if not b then return Fail("Petbattle condition", "F9 not in KeyMap") end
        if b.petbattle ~= false then return Fail("Petbattle condition", "petbattle=" .. tostring(b.petbattle)) end
        return Pass("Petbattle condition")
    end,
})

RegisterTest("Known condition", {
    description = "주문 습득 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F10", known = true })
        ApplyBindings()
        local b = GetNthBinding("F10", 1)
        if not b then return Fail("Known condition", "F10 not in KeyMap") end
        if b.known ~= true then return Fail("Known condition", "known=" .. tostring(b.known)) end
        return Pass("Known condition")
    end,
})

RegisterTest("Custom state condition", {
    description = "커스텀 상태 조건($state1~5)이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F11", ["$state1"] = true })
        InsertAction({ type = Constants.SPELL, value = 116, key = "F11", ["$state1"] = false })
        ApplyBindings()
        local bindings = GetKeyBindings("F11")
        if not bindings or #bindings < 2 then
            return Fail("Custom state condition", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        local hasTrue, hasFalse = false, false
        for i = 1, #bindings do
            if bindings[i]["$state1"] == true then hasTrue = true end
            if bindings[i]["$state1"] == false then hasFalse = true end
        end
        if not (hasTrue and hasFalse) then
            return Fail("Custom state condition", format("true=%s, false=%s", tostring(hasTrue), tostring(hasFalse)))
        end
        return Pass("Custom state condition")
    end,
})

RegisterTest("Hover condition with reactions", {
    description = "호버 조건 + 반응(아군/적군) 비트플래그가 반영되는지",
    run = function()
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            hover = true,
            reactions = bor(Constants.REACTION_HELP, Constants.REACTION_HARM),
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()
        local b = GetNthBinding("BUTTON3", 1)
        if not b then return Fail("Hover condition", "BUTTON3 not in KeyMap") end
        if b.hover ~= true then return Fail("Hover condition", "hover=" .. tostring(b.hover)) end
        if band(b.reactions, Constants.REACTION_HELP) == 0 then
            return Fail("Hover condition", "REACTION_HELP not set")
        end
        if b.frameTypes ~= Constants.FRAMETYPE_GROUP then
            return Fail("Hover condition", "frameTypes=" .. tostring(b.frameTypes))
        end
        return Pass("Hover condition", format("reactions=%d, frameTypes=%d", b.reactions, b.frameTypes))
    end,
})

RegisterTest("CheckedUnits condition", {
    description = "유닛 존재 확인 조건이 반영되는지",
    run = function()
        -- 다른 유닛(focus, pet 등)의 존재를 조건으로 사용
        InsertAction({
            type = Constants.SPELL, value = 585, key = "F12",
            unit = "target",
            checkedUnits = { ["focus"] = true },
        })
        ApplyBindings()
        local b = GetNthBinding("F12", 1)
        if not b then return Fail("CheckedUnits condition", "F12 not in KeyMap") end
        if not b.checkedUnits then
            return Fail("CheckedUnits condition", "checkedUnits is nil")
        end
        if not b.checkedUnits["focus"] then
            return Fail("CheckedUnits condition", "checkedUnits[focus]=" .. tostring(b.checkedUnits["focus"]))
        end
        return Pass("CheckedUnits condition")
    end,
})

-----------------------------------------------------------
-- Test Cases: Priority & Ordering
-----------------------------------------------------------

RegisterTest("Priority ordering", {
    description = "우선순위가 높은 바인딩이 KeyMap에서 먼저 오는지",
    run = function()
        -- 조건이 겹치면 뒤쪽이 UNREACHABLE로 제거되므로 서로 배타적인 조건을 준다.
        -- 삽입 순서(ordinal)는 priority 5가 먼저이므로 정렬이 실제로 동작해야만 통과한다.
        InsertAction({ type = Constants.SPELL, value = 585, key = "INSERT", priority = 5, combat = false }) -- Very Low
        InsertAction({ type = Constants.SPELL, value = 116, key = "INSERT", priority = 1, combat = true }) -- Very High
        ApplyBindings()
        local bindings = GetKeyBindings("INSERT")
        if not bindings or #bindings < 2 then
            return Fail("Priority ordering", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        -- priority 1 (Very High) should come first
        if bindings[1].priority ~= 1 then
            return Fail("Priority ordering", format("first binding priority=%s, expected 1", tostring(bindings[1].priority)))
        end
        if (bindings[2].priority or 3) ~= 5 then
            return Fail("Priority ordering", format("second binding priority=%s, expected 5", tostring(bindings[2].priority)))
        end
        return Pass("Priority ordering", "priority=1 before priority=5")
    end,
})

RegisterTest("Conditional before unconditional", {
    description = "조건부 바인딩이 무조건 바인딩보다 먼저 오는지 (같은 우선순위)",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "DELETE" }) -- unconditional
        InsertAction({ type = Constants.SPELL, value = 116, key = "DELETE", combat = true }) -- conditional
        ApplyBindings()
        local bindings = GetKeyBindings("DELETE")
        if not bindings or #bindings < 2 then
            return Fail("Conditional ordering", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        if not bindings[1].isConditional then
            return Fail("Conditional ordering", "first binding is not conditional")
        end
        if bindings[2].isConditional then
            return Fail("Conditional ordering", "second binding is also conditional")
        end
        return Pass("Conditional ordering")
    end,
})

-----------------------------------------------------------
-- Test Cases: Binding Issue Detection
-----------------------------------------------------------

RegisterTest("Issue: BUTTON1 without hover", {
    description = "BUTTON1을 hover 없이 쓰면 NOT_SUPPORTED_MOUSE_BUTTON 이슈가 나오는지",
    run = function()
        local action = { type = Constants.SPELL, value = 585, key = "BUTTON1" }
        local issue = DebindPrivate.GetBindingIssue(action)
        if issue ~= Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON then
            return Fail("BUTTON1 issue", format("expected NOT_SUPPORTED_MOUSE_BUTTON, got %s", tostring(issue)))
        end
        return Pass("BUTTON1 issue")
    end,
})

RegisterTest("Issue: groups=0", {
    description = "groups=0이면 GROUPS_NONE_SELECTED 이슈가 나오는지",
    run = function()
        local action = { type = Constants.SPELL, value = 585, key = "T", groups = 0 }
        local issue = DebindPrivate.GetBindingIssue(action)
        if issue ~= Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED then
            return Fail("Groups=0 issue", format("expected GROUPS_NONE_SELECTED, got %s", tostring(issue)))
        end
        return Pass("Groups=0 issue")
    end,
})

RegisterTest("Issue: forms=0", {
    description = "forms=0이면 FORMS_NONE_SELECTED 이슈가 나오는지",
    run = function()
        local action = { type = Constants.SPELL, value = 585, key = "T", forms = 0 }
        local issue = DebindPrivate.GetBindingIssue(action)
        if issue ~= Constants.BINDING_ISSUE_FORMS_NONE_SELECTED then
            return Fail("Forms=0 issue", format("expected FORMS_NONE_SELECTED, got %s", tostring(issue)))
        end
        return Pass("Forms=0 issue")
    end,
})

-----------------------------------------------------------
-- Test Cases: Special Units (macrotext with @tank etc.)
-----------------------------------------------------------

RegisterTest("Macrotext with @tank", {
    description = "@tank 유닛이 포함된 매크로텍스트가 파싱되는지",
    run = function()
        local text = "/cast [@tank] Heal"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("@tank macrotext", "ParseMacroText returned nil args") end
        local foundTank = false
        for _, arg in ipairs(args) do
            if arg.name == "tank" and arg.type == Constants.MACROTEXT_ARG_UNIT then
                foundTank = true
                break
            end
        end
        if not foundTank then return Fail("@tank macrotext", "tank unit not found in args") end
        return Pass("@tank macrotext")
    end,
})

RegisterTest("Macrotext with @custom1", {
    description = "@custom1 유닛이 포함된 매크로텍스트가 파싱되는지",
    run = function()
        local text = "/cast [@custom1,exists] Heal"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("@custom1 macrotext", "ParseMacroText returned nil args") end
        local found = false
        for _, arg in ipairs(args) do
            if arg.name == "custom1" then
                found = true
                break
            end
        end
        if not found then return Fail("@custom1 macrotext", "custom1 not found in args") end
        return Pass("@custom1 macrotext")
    end,
})

RegisterTest("Macrotext with $state", {
    description = "$state 커스텀 상태가 매크로텍스트에서 파싱되는지",
    run = function()
        local text = "/cast [$state1] Heal; Smite"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("$state macrotext", "ParseMacroText returned nil args") end
        local found = false
        for _, arg in ipairs(args) do
            if arg.name == "$state1" and arg.type == Constants.MACROTEXT_ARG_CUSTOM_STATE then
                found = true
                break
            end
        end
        if not found then return Fail("$state macrotext", "$state1 not found in args") end
        return Pass("$state macrotext")
    end,
})

-- README가 광고하는 형태. 두 번째 이후 대괄호 그룹이 파서에 도달하지 못하면
-- @healer가 글자 그대로 와우에 넘어가고, 모르는 유닛이라 조용히 실패한다.
RegisterTest("Macrotext with multiple condition groups", {
    description = "두 번째 이후 대괄호 그룹의 특수 유닛도 치환되는지",
    run = function()
        local text = "/cast [@custom2,exists][@healer,exists][] Innervate"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("multi-group macrotext", "ParseMacroText returned nil args") end
        local seen = {}
        for _, arg in ipairs(args) do
            if arg.type == Constants.MACROTEXT_ARG_UNIT then
                seen[arg.name] = true
            end
        end
        local missing = {}
        if not seen.custom2 then tinsert(missing, "custom2") end
        if not seen.healer then tinsert(missing, "healer") end
        if #missing > 0 then
            return Fail("multi-group macrotext", "치환 안 됨: " .. table.concat(missing, ", "))
        end
        return Pass("multi-group macrotext", "custom2 + healer 모두 인자로 잡힘")
    end,
})

-----------------------------------------------------------
-- Test Cases: Multi-condition combo
-----------------------------------------------------------

RegisterTest("Multi-condition: combat + group + stealth", {
    description = "여러 조건 동시 설정이 바인딩에 모두 반영되는지",
    run = function()
        InsertAction({
            type = Constants.SPELL, value = 585, key = "HOME",
            combat = true,
            groups = Constants.GROUP_RAID,
            stealth = false,
            pet = true,
            ["$state2"] = true,
        })
        ApplyBindings()
        local b = GetNthBinding("HOME", 1)
        if not b then return Fail("Multi-condition", "HOME not in KeyMap") end
        local errors = {}
        if b.combat ~= true then tinsert(errors, "combat=" .. tostring(b.combat)) end
        if b.groups ~= Constants.GROUP_RAID then tinsert(errors, "groups=" .. tostring(b.groups)) end
        if b.stealth ~= false then tinsert(errors, "stealth=" .. tostring(b.stealth)) end
        if b.pet ~= true then tinsert(errors, "pet=" .. tostring(b.pet)) end
        if b["$state2"] ~= true then tinsert(errors, "$state2=" .. tostring(b["$state2"])) end
        if #errors > 0 then
            return Fail("Multi-condition", table.concat(errors, ", "))
        end
        return Pass("Multi-condition", "all 5 conditions preserved")
    end,
})

-----------------------------------------------------------
-- Test Cases: Secure Handler Health
-----------------------------------------------------------

-- 재빌드가 시큐어 환경까지 실제로 도달했는지. 이게 끊기면 아무것도 안 터지고, 바인딩이
-- 마지막에 적용된 상태로 얼어붙는다 - 키는 계속 뭔가 나가고 상태 전환만 멈추므로
-- 유저는 "가끔 안 먹혀요"라고밖에 말할 수 없다. 조용한 고장을 시끄럽게 만드는 것이 목적.
RegisterTest("Secure update path", {
    description = "UpdateBindings가 시큐어 핸들러까지 도달하는지 (state-unitexists를 핸들러가 소비했는가)",
    run = function()
        if InCombatLockdown() then
            return Fail("Secure update path", "전투 중에는 UpdateBindings가 미뤄지므로 판정 불가")
        end

        local driver = DebindPrivate.BindingDriver
        if not driver then return Fail("Secure update path", "BindingDriver가 없다") end

        ApplyBindings()

        -- UpdateBindings의 마지막 동작이 state-unitexists=1이고, 시큐어 _onattributechanged가
        -- 첫 동작으로 0으로 되돌린다. 핸들러는 동기적으로 도니까 여기까지 왔는데도 0이 아니면
        -- 핸들러가 아예 안 돈 것이다. 대기 상태의 0과 헷갈릴 일이 없다 - 방금 1을 넣었으므로.
        local value = driver:GetAttribute("state-unitexists")
        if value ~= 0 then
            return Fail("Secure update path", format(
                "state-unitexists=%s, 0이어야 한다. 시큐어 핸들러가 돌지 않았다 - 바인딩이 갱신을 멈춘 상태다",
                tostring(value)))
        end

        return Pass("Secure update path", "핸들러가 소비함")
    end,
})

-----------------------------------------------------------
-- Test Cases: Hover Slot (live)
-----------------------------------------------------------

-- The one state that could not be checked by hand: **the cursor sits still on a unit frame and
-- the unit goes away.** No enter fires, no leave fires, and only the poll sees it. Reproducing
-- that in the world means waiting for a boss to despawn or an arena to swap -- a raid schedule,
-- not a check.
--
-- Owning the frame turns it into three attribute writes. Pointing it at a unit that does not
-- exist is, from the poll's side, indistinguishable from a unit that stopped existing: it reads
-- the attribute, asks `UnitExists`, and takes the same branch either way.
--
-- No mocks are involved. The test picks the unit token, so reality supplies both answers --
-- `player` exists, an unrecognised token does not.
RegisterTest("Hover slot: unit disappears under a still cursor", {
    description = "커서가 멈춘 채 유닛만 사라졌을 때 hover 슬롯이 비는가, 돌아오면 다시 차는가",
    run = function()
        local NAME = "Hover slot"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 속성 쓰기가 막힌다")
        end

        -- A hover binding has to exist, or `HoverBindings` stays false and the hover axis is
        -- never wired up. The test builds its own precondition rather than hoping for one.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            hover = true,
            reactions = Constants.REACTION_ALL,
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        Wait(0.3)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("진입 후 hover=%s, player여야 한다", tostring(GetHoverUnit())))
        end

        -- The cursor has not moved. Only the attribute changed, which is exactly the shape of a
        -- unit despawning under it.
        SetFrameUnit(frame, UNIT_TOKEN_ABSENT)
        Wait(0.5)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "유닛이 사라졌는데 hover=%s. 고치기 전에는 반응이 계속 남아 있었다",
                tostring(GetHoverUnit())))
        end

        -- The frame is deliberately not dropped when its unit goes away, so that this same poll
        -- can pick it back up. Without that, the slot would stay empty until the mouse moved.
        SetFrameUnit(frame, "player")
        Wait(0.5)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format(
                "유닛이 돌아왔는데 hover=%s. 폴링이 프레임을 버렸다는 뜻이다",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "사라짐 -> 비고, 돌아옴 -> 다시 참")
    end,
})

--- Waits for a real mouse click on a frame, shown in the middle of the results window.
---
--- **A test cannot click this itself, and no warm-up changes that.** The wrapper body is a
--- restricted closure; `RestrictedExecution.lua:470` refuses to call one from insecure code, and
--- addon code always is. Declaring the signature was only the first wall. Hardware input on a
--- wrapped frame is the only way into a click-time decision, so the kit asks for one.
---
--- The hook is insecure and rides alongside the secure wrapper without disturbing it; it is only
--- how the test learns the click happened.
local function WaitForRealClick(frame, button, text, timeout)
    frame.debindTestClicked = nil

    -- **Hooked every time, not once.** Turning probes on rebakes the bodies, and the addon
    -- rewraps every registered frame to pick them up -- `SecureHandlerUnwrapScript` puts back the
    -- script from before the wrap, which is from before this hook, so the hook goes with it.
    --
    -- Frames the kit builds are new each run and got a fresh hook by accident. PlayerFrame is the
    -- same object every time, so a "hook once" guard left it with no hook from the second run on
    -- and the click never registered. Stacking a hook per wait costs a field assignment.
    frame:HookScript("OnClick", function(self, clicked)
        self.debindTestClicked = clicked or true
    end)

    wipe(probeReports)
    UI.ShowClickTarget(frame, text)

    local waited, limit = 0, timeout or 25
    while frame.debindTestClicked ~= button and waited < limit do
        Wait(0.25)
        waited = waited + 0.25
    end

    -- Hiding is the runner's, registered the moment it is shown, so a test that fails or throws
    -- before this point cannot leave the window covered by the thing it was asked to click.
    UI.HideClickTarget()

    if frame.debindTestClicked ~= button then
        return false, format("%s초 안에 %s 클릭이 없었다 (받은 것: %s)",
            limit, button, tostring(frame.debindTestClicked))
    end

    -- The probe reports through CallMethod, which is queued rather than called.
    Wait(0.4)
    return true
end

--- Puts an action of the frame's own in the slot our routing avoids, and returns a reader for
--- whether it ran. That answers the question a nil winner cannot: a click that never executed
--- anything and a click our wrapper declined look identical from the winner alone.
---
--- **Our frames only.** Stamping this onto one of Blizzard's would be the addon doing the thing
--- this whole change exists to stop doing.
local function ArmOwnAction(frame, suffix)
    local typeAttr, textAttr = "*type" .. suffix, "*macrotext" .. suffix
    _G.DEBIND_TEST_FELL_THROUGH = nil
    frame:SetAttribute(typeAttr, "macro")
    frame:SetAttribute(textAttr, "/run DEBIND_TEST_FELL_THROUGH = true")
    AddTeardown(function()
        frame:SetAttribute(typeAttr, nil)
        frame:SetAttribute(textAttr, nil)
        _G.DEBIND_TEST_FELL_THROUGH = nil
    end)
    return function() return _G.DEBIND_TEST_FELL_THROUGH and true or false end
end

--- The frames a click-cast test has to cover: one we made, and one of Blizzard's.
---
--- **Driving only our own frame would miss the thing that changed.** Blizzard's frames are the
--- ones whose `type1` the old routing took over, and they arrive through a different door --
--- `UpdateBlizzardFrames` rather than the Clique API -- so "it works on a frame the test built"
--- says nothing about them.
---
--- Blizzard's is skipped rather than failed when it is not registered: that is a user option
--- (`Options.blizzframes`), not a fault.
local function ClickCastTargets()
    local targets = {}

    local frame, err = CreateTestUnitFrame("player", "group")
    if not frame then return nil, err end
    targets[#targets + 1] = { label = "우리 프레임", frame = frame }

    if PlayerFrame and type(DebindPrivate.ccframes[PlayerFrame]) == "table" then
        -- Asked for where it already is. Moving or resizing one of Blizzard's frames to make it
        -- convenient would be the addon reaching into it, which is the thing being tested away.
        PlayerFrame.debindTestLeaveAlone = true
        targets[#targets + 1] = { label = "PlayerFrame", frame = PlayerFrame, blizzard = true }
    end

    return targets
end

-- Click-casting decides at the click now, in a wrapper on the frame rather than in attributes
-- stamped on it ahead of time. Clicking is the only way to reach that decision.
RegisterTest("Click-cast: the frame's wrapper picks a winner", {
    description = "유닛 프레임 클릭이 래퍼까지 닿아 조건에 맞는 레코드를 고르는가 (우리 프레임 + 블리자드 프레임)",
    run = function()
        local NAME = "Click-cast winner"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 래핑이 막힌다")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            hover = true,
            reactions = Constants.REACTION_ALL,
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        ApplyBindings()

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        local seen = {}
        for _, target in ipairs(targets) do
            -- Only to tell the two failures apart if this fails. When we do pick a winner the
            -- button is renamed and this never runs.
            local ranOwn = not target.blizzard and ArmOwnAction(target.frame, 3) or nil
            if ranOwn then Wait(0.4) end

            local clicked, cerr = WaitForRealClick(target.frame, "MiddleButton", target.blizzard
                and format("화면의 %s 를 가운데 버튼으로 클릭", target.label)
                or "아래 칸을 가운데 버튼으로 클릭")
            if not clicked then
                return Fail(NAME, format("%s: %s", target.label, cerr))
            end

            if LastWinner() == nil then
                return Fail(NAME, format("%s: 아무것도 안 골랐다 (%s)", target.label,
                    ranOwn == nil and "블리자드 프레임"
                    or ranOwn() and "클릭은 실행됐다 -> 래퍼가 안 붙었거나 조건이 안 맞았다"
                    or "클릭이 액션까지 못 갔다 -> 래핑 이전에 클릭 경로부터 볼 것"))
            end
            seen[#seen + 1] = format("%s=%d", target.label, LastWinner())
        end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})

-- The point of judging on the frame instead of ahead of it: when nothing matches we return nil,
-- the button name is left alone, and the click carries on into whatever the frame itself does.
-- On the old path the frame's own `type` had been overwritten, so a click that matched nothing
-- did nothing at all -- silently, which is the shape of fault this addon keeps running into.
RegisterTest("Click-cast: a click that matches nothing falls through", {
    description = "조건이 안 맞으면 프레임 자신의 동작이 그대로 나가는가 (동적 폴백)",
    run = function()
        local NAME = "Click-cast fallback"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 래핑이 막힌다")
        end

        -- **The left button, because that is where falling through means something.** A unit
        -- frame's left click is targeting; what this checks is that declining hands the click
        -- back to it. (A hover binding may take BUTTON1 -- the button is only refused without
        -- one.)
        --
        -- Cannot match: the record wants combat and the state says otherwise. The binding still
        -- exists, so the frame is still routed and the wrapper still runs -- which is the point.
        -- A test with no binding at all would pass without the wrapper ever deciding anything.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON1",
            hover = true,
            reactions = Constants.REACTION_ALL,
            frameTypes = Constants.FRAMETYPE_GROUP,
            combat = true,
        })
        ApplyBindings()
        SetMockState("combat", false)

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        -- **Our own frame only, so this costs one click rather than two.** The Blizzard target
        -- would only be able to assert "nothing was chosen", and a wrapper that was never
        -- installed gives that same answer -- a click's worth of nothing.
        for _, target in ipairs(targets) do
            if not target.blizzard then
                local ranOwn = ArmOwnAction(target.frame, 1)
                Wait(0.4)

                local clicked, cerr = WaitForRealClick(target.frame, "LeftButton",
                    "아래 칸을 왼쪽 버튼으로 클릭")
                if not clicked then
                    return Fail(NAME, format("%s: %s", target.label, cerr))
                end

                if LastWinner() ~= nil then
                    return Fail(NAME, format(
                        "%s: 조건이 안 맞는데 %d번을 골랐다. combat 목이 안 걸렸을 수 있다",
                        target.label, LastWinner()))
                end

                if not ranOwn() then
                    return Fail(NAME, format(
                        "%s: 프레임 자신의 동작이 안 나갔다. 래퍼가 nil이 아닌 것을 반환했거나 우리가 그 자리를 덮었다",
                        target.label))
                end
            end
        end

        return Pass(NAME, "안 맞음 -> 고르지 않음, 프레임 원래 동작이 나감")
    end,
})

-----------------------------------------------------------
-- Test Cases: State Injection (live)
-----------------------------------------------------------

-- The reason the kit exists. A combat-only binding is reachable only in combat, and in combat
-- nothing outside can drive it -- lockdown stops the clicking, the binding and the attribute
-- writes. So the one state where this code matters is the one state where it cannot be checked.
--
-- Overriding `States.combat` while the client is at peace breaks that. The decision runs its real
-- path; the client, not actually fighting, never locks anything down.
--
-- What is checked is the game's own answer: `SetBindingClick` inside the snippet registers an
-- override binding, and `GetBindingAction` reads back what the key is bound to. Nothing about the
-- verdict is inferred from the injection.
RegisterTest("State injection: combat-only binding", {
    description = "전투 중이라고 주입하면 전투 전용 바인딩이 실제로 걸리는가",
    run = function()
        local NAME = "Combat injection"
        local KEY = "CTRL-SHIFT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "진짜 전투 중에는 주입 결과와 실제가 구분되지 않는다")
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        ApplyBindings()

        SetMockState("combat", false)
        Wait(0.4)
        local atPeace = GetBindingAction(KEY, true) or ""

        SetMockState("combat", true)
        Wait(0.4)
        local inCombat = GetBindingAction(KEY, true) or ""

        if inCombat == atPeace then
            return Fail(NAME, format(
                "combat을 뒤집었는데 바인딩이 그대로다 (%q). 주입이 스니펫까지 안 닿았다",
                inCombat))
        end

        if inCombat:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("combat=true 인데 %q, CLICK 이어야 한다", inCombat))
        end

        -- Back to peace: the binding has to go away again. Without this the test would pass on a
        -- key that was simply bound the whole time.
        SetMockState("combat", false)
        Wait(0.4)
        local again = GetBindingAction(KEY, true) or ""

        if again ~= atPeace then
            return Fail(NAME, format("combat을 되돌렸는데 %q, %q 여야 한다", again, atPeace))
        end

        return Pass(NAME, format("전투 밖에서 전투 경로를 구동함 (%s)", inCombat))
    end,
})

-- Turning probes on rebuilds every registered snippet from its raw text, including the click
-- wrapper -- the hottest path here and the one that decides which record wins. A rebuild that
-- produced a body the restricted environment refuses would leave the addon looking loaded and
-- doing nothing, so what is checked is not that the rebake returned, but that the same judgement
-- still runs afterwards.
RegisterTest("Snippet probes: rebaked snippets still decide", {
    description = "프로브를 켜고 스니펫을 다시 구워도 조건 판정이 그대로 도는가",
    run = function()
        local NAME = "Probe rebake"
        local KEY = "CTRL-SHIFT-F8"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 다시 구울 수 없다")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            combat = true,
        })
        ApplyBindings()

        SetMockState("combat", false)
        Wait(0.4)
        local atPeace = GetBindingAction(KEY, true) or ""

        SetMockState("combat", true)
        Wait(0.4)
        local inCombat = GetBindingAction(KEY, true) or ""

        if inCombat == atPeace then
            return Fail(NAME, format("다시 구운 뒤 조건이 안 먹는다 (%q 그대로)", inCombat))
        end

        if inCombat:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("다시 구운 뒤 %q, CLICK 이어야 한다", inCombat))
        end

        return Pass(NAME, "프로브 켠 채로도 판정이 그대로")
    end,
})

-----------------------------------------------------------
-- Test Cases: Across a /reload
-----------------------------------------------------------

-- The reload machinery checking itself. That is not as circular as it sounds: everything a
-- migration or a save-format test would assert rests on this one claim -- that a run can end the
-- session, come back, and know where it was -- and nothing else in the suite touches it.
--
-- Opt-in (`/debtest reload`), because a plain run should not end someone's session.
RegisterTest("Run survives /reload", {
    description = "런이 /reload를 건너 이어지는가, 단계와 스크래치가 그대로 오는가",
    crossesReload = true,
    run = function(phase)
        local NAME = "Reload round trip"
        local scratch = Scratch()

        if not phase then
            scratch.token = "before-" .. tostring(GetTime())
            scratch.index = 1
            return RequestReload("second-half")
        end

        -- Anything wrong here means the runner picked the wrong test, the wrong phase, or a run
        -- that was not the one it stored.
        if phase ~= "second-half" then
            return Fail(NAME, format("phase=%s, second-half여야 한다", tostring(phase)))
        end

        if not scratch.token or scratch.token:sub(1, 7) ~= "before-" then
            return Fail(NAME, format("스크래치가 안 넘어왔다 (token=%s)", tostring(scratch.token)))
        end

        -- The run's own tally has to come back too. It is what the report is built from, and a
        -- resumed run that forgot it would report only the tests after the reload.
        local kept = scratch.token
        scratch.token, scratch.index = nil, nil

        return Pass(NAME, format("리로드 뒤 %s 로 이어짐 (%s)", phase, kept))
    end,
})

-----------------------------------------------------------
-- Copyable Output Popup
-----------------------------------------------------------

local CopyFrame

local function ShowCopyableText(text)
    if not CopyFrame then
        local f = CreateFrame("Frame", "DebindTestCopyFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(700, 400)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f.TitleText:SetText("Test Results (Ctrl+A, Ctrl+C to copy)")

        local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -32)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 12)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetWidth(640)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        scrollFrame:SetScrollChild(editBox)

        f.editBox = editBox
        CopyFrame = f
    end

    -- strip WoW color codes for plain text
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    CopyFrame.editBox:SetText(plain)
    CopyFrame:Show()
    CopyFrame.editBox:HighlightText()
    CopyFrame.editBox:SetFocus()
end

-----------------------------------------------------------
-- Test Runner
-----------------------------------------------------------

local lastResultText = ""

local runner = CreateFrame("Frame")
runner:Hide()

local run

-- Progress is written to saved variables **after every test**, not at the end. A run that spans
-- a `/reload` is the point of storing it at all, and a reload can arrive at any test; whatever
-- was only in memory when it does is gone. Storing it also means a session that crashes leaves a
-- record of how far it got, which is otherwise the one outcome that reports nothing.
local function Persist()
    if not run then
        DB().pending = nil
        return
    end

    DB().pending = {
        index = run.index,
        phase = run.phase,
        reloads = run.reloads,
        pass = run.pass,
        fail = run.fail,
        err = run.err,
        skip = run.skip,
        lines = run.lines,
        crossReloads = run.crossReloads,
        -- Set only while a reload is deliberately in flight. Its absence in a stored run is what
        -- separates "the session went away on purpose" from "the session died here".
        expectReload = run.expectReload,
    }
end

local function FinishRun()
    pcall(CleanupActions)
    RunTeardowns()
    UI.SetActive(nil)
    UI.HideClickTarget()
    UI.SetRunning(false)

    -- Skipped tests are named rather than left to be inferred from the total not adding up.
    local summary = format("[DebindTest] Complete: %d passed, %d failed, %d errors%s / %d total",
        run.pass, run.fail, run.err,
        run.skip > 0 and format(", %d skipped", run.skip) or "",
        #testOrder)
    tinsert(run.lines, "")
    tinsert(run.lines, summary)
    print(format("\n|cff00ccff%s|r", summary))

    lastResultText = table.concat(run.lines, "\n")

    local onDone = run.onDone
    run = nil
    runner:Hide()
    Persist()

    DB().last = lastResultText

    if onDone then onDone() end
end

-- A test that yields and never comes back would otherwise hold the runner forever, and `run`
-- staying set means no further run can start either -- one stuck test costs a `/reload`. Long
-- is fine here (waiting is the point), so this is only a ceiling on hanging, not on slowness.
local TEST_TIMEOUT = 30

local function Record(testName, status, msg, color)
    -- A test is meant to return a message with its verdict. One that does not still has to be
    -- recorded as something, and this runs inside OnUpdate where throwing helps nobody.
    msg = msg or format("%s (no message)", testName)
    results[testName] = { status = status, msg = msg }
    tinsert(run.lines, msg)
    print(color and format("|c%s%s|r", color, msg) or msg)
    UI.Update(testName)
end

-- A reload-crossing test that keeps asking for another one would reload the session forever, and
-- a reload loop cannot be interrupted from inside the game. This is the stop.
local MAX_RELOADS = 4

-- **`ReloadUI` is protected.** An addon may only reach it from a hardware event, and an OnUpdate
-- is not one -- calling it there gets ADDON_ACTION_BLOCKED and nothing else. So the reload is
-- asked for rather than performed, and the click on this popup is the hardware event that
-- carries it.
--
-- Having to ask turns out to suit it. Ending someone's session is not something to do silently
-- on the way past, and declining has to mean something, so it stops the run rather than leaving
-- a stored one to surprise the next login.
StaticPopupDialogs["DEBINDTEST_RELOAD"] = {
    text = "DebindTest: %s\n\n이 테스트는 /reload를 건너야 한다. 리로드하면 이어서 계속한다.",
    button1 = RELOAD_UI or "Reload UI",
    button2 = CANCEL or "Cancel",
    OnAccept = function() ReloadUI() end,
    OnCancel = function()
        DB().pending = nil
        print("|cffff8800[DebindTest]|r 리로드를 취소해서 런을 중단했다.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--- Saves progress and asks for the reload. The test is picked up again from the top afterwards,
--- with `phase` telling it where it was.
local function DoReload(phase)
    run.phase = phase
    run.reloads = run.reloads + 1
    run.expectReload = true
    run.co, run.wait = nil, nil

    -- Teardowns run first: whatever they undo is state that must not outlive this session, and
    -- after the reload nothing here gets another chance.
    RunTeardowns()
    pcall(CleanupActions)
    Persist()

    -- The runner stops here either way. Everything it would need is stored, so the run continues
    -- from saved variables if the reload happens and is dropped by OnCancel if it does not.
    local name = run.name
    run = nil
    runner:Hide()

    print(format("|cff00ccff[DebindTest]|r %s -> /reload 대기 (%s)", name, phase))
    StaticPopup_Show("DEBINDTEST_RELOAD", name)
end

--- One resume of the current test. Returns true when the runner may keep going this frame.
local function Step()
    if not run.co then
        if run.index > #testOrder then
            FinishRun()
            return false
        end

        run.name = testOrder[run.index]
        run.spent = 0
        UI.SetActive(run.name)

        local test = tests[run.name]

        -- Reload-crossing tests are opt-in. Ending the session is not something a plain
        -- `/debtest` should do to someone who only wanted to see the list go green.
        if test.crossesReload and not run.crossReloads then
            run.skip = run.skip + 1
            Record(run.name, "skip", format("SKIP %s: /debtest reload 로 실행", run.name), "ff888888")
            run.index = run.index + 1
            Persist()
            return true
        end

        pcall(CleanupActions)
        run.co = coroutine.create(test.run)
    end

    -- The phase is handed in rather than remembered by the test, because the test is being run
    -- from the top again -- there is nothing of its own left to remember with.
    local ok, a, b = coroutine.resume(run.co, run.phase)

    if not ok then
        run.err = run.err + 1
        Record(run.name, "error", format("ERROR %s: %s", run.name, tostring(a)), "ffff8800")
    elseif coroutine.status(run.co) == "dead" then
        if a then
            run.pass = run.pass + 1
            Record(run.name, "pass", b)
        else
            run.fail = run.fail + 1
            Record(run.name, "fail", b)
        end
    elseif a == RELOAD_REQUEST then
        if run.reloads >= MAX_RELOADS then
            run.err = run.err + 1
            Record(run.name, "error",
                format("ERROR %s: 리로드를 %d번 넘게 요청했다", run.name, MAX_RELOADS), "ffff8800")
            RunTeardowns()
            run.co, run.wait = nil, nil
            run.index = run.index + 1
            Persist()
            return true
        end

        DoReload(b)
        return false
    else
        -- Yielded. The test is mid-flight, so nothing is torn down yet.
        run.wait = tonumber(a) or 0
        return false
    end

    RunTeardowns()
    run.co = nil
    run.index = run.index + 1
    run.phase = nil
    Persist()
    return true
end

runner:SetScript("OnUpdate", function(self, elapsed)
    -- The frame is hidden while idle, so this should not fire without a run. A teardown or an
    -- `onDone` that starts something of its own could still land here between the two, and an
    -- error thrown from OnUpdate is not worth the risk of finding out.
    if not run then
        self:Hide()
        return
    end

    if run.co then
        run.spent = run.spent + elapsed
        if run.spent > TEST_TIMEOUT then
            -- Abandon it. The coroutine is simply dropped -- there is no way to unwind one from
            -- outside - so whatever it was holding is left to the teardowns, which is why they
            -- belong to the runner and not to the test.
            run.err = run.err + 1
            Record(run.name, "error",
                format("ERROR %s: timed out after %ds", run.name, TEST_TIMEOUT), "ffff8800")
            RunTeardowns()
            run.co, run.wait = nil, nil
            run.index = run.index + 1
        end
    end

    if run.wait and run.wait > 0 then
        run.wait = run.wait - elapsed
        if run.wait > 0 then return end
    end
    run.wait = nil

    while run and Step() do end
end)

--- Runs the suite. Returns immediately -- `onDone` fires when the last test has finished.
local function RunAllTests(onDone, crossReloads)
    if run then
        print("|cffff8800[DebindTest]|r already running.")
        return
    end

    wipe(results)
    wipe(teardowns)

    run = {
        index = 1, pass = 0, fail = 0, err = 0, skip = 0, reloads = 0,
        lines = {}, onDone = onDone, crossReloads = crossReloads,
    }
    Persist()
    UI.SetRunning(true)
    runner:Show()
end

--- Picks a stored run back up. Called once, after saved variables are available.
---
--- A stored run that was not expecting a reload means the session ended under it -- crash,
--- disconnect, or a `/reload` typed by hand. That is reported rather than continued: carrying on
--- would erase the one fact worth keeping, which is that it died at that test.
local function ResumeStoredRun()
    local pending = DB().pending
    if not pending then return end

    DB().pending = nil

    if not pending.expectReload then
        local name = testOrder[pending.index] or "?"
        print(format("|cffff8800[DebindTest]|r 이전 실행이 %s 에서 끊겼다 (리로드 요청 없음). 이어가지 않는다.",
            name))
        tinsert(pending.lines, format("DIED %s: 세션이 이 테스트 도중에 끝났다", name))
        lastResultText = table.concat(pending.lines, "\n")
        DB().last = lastResultText
        return
    end

    wipe(results)
    wipe(teardowns)

    run = {
        index = pending.index, pass = pending.pass, fail = pending.fail, err = pending.err,
        skip = pending.skip or 0,
        reloads = pending.reloads, lines = pending.lines, phase = pending.phase,
        crossReloads = pending.crossReloads,
        onDone = function() ShowCopyableText(lastResultText) end,
    }

    print(format("|cff00ccff[DebindTest]|r 리로드 뒤 이어서 실행: %s (%s)",
        testOrder[run.index] or "?", tostring(run.phase)))
    UI.Open()
    UI.SetRunning(true)
    runner:Show()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    DB()

    -- Waiting for login rather than ADDON_LOADED: a resumed run drives bindings and unit frames
    -- immediately, and neither is meaningfully in place before the player is.
    ResumeStoredRun()
end)

-----------------------------------------------------------
-- UI (optional, simple scrollable results viewer)
-----------------------------------------------------------

local TestFrame
local rows = {}
local activeTest

local STATUS_MARK = {
    pass = "|cff00ff00v|r",
    fail = "|cffff4444X|r",
    error = "|cffff8800!|r",
    skip = "|cff888888~|r",
}

--- Repaints one row from whatever is known about that test right now.
---
--- **Rows are built once and repainted**, where the old window rebuilt them on open and returned
--- early if it already existed -- so a run's results never reached it and it always showed the
--- state it was first opened in.
local function PaintRow(testName)
    local row = rows[testName]
    if not row then
        return
    end

    local result = results[testName]
    if result then
        row.icon:SetText(STATUS_MARK[result.status] or STATUS_MARK.error)
    elseif activeTest == testName then
        row.icon:SetText("|cffffff00>|r")
    else
        row.icon:SetText("|cff555555-|r")
    end

    local text = testName
    if result and result.msg then
        local clean = result.msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        text = text .. "  " .. (result.status == "pass" and "|cff888888" or "|cffff8888") .. clean .. "|r"
    end
    row.text:SetText(text)
    row.highlight:SetShown(activeTest == testName)
end

local function BuildRows(content)
    local y = 0
    for _, testName in ipairs(testOrder) do
        local test = tests[testName]

        local row = CreateFrame("Frame", nil, content)
        row:SetSize(590, 28)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(0.2, 0.4, 0.1, 0.6)
        row.highlight:Hide()

        row.icon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetWidth(14)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetWidth(560)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(testName, 1, 1, 1)
            if test.description then
                GameTooltip:AddLine(test.description, nil, nil, nil, true)
            end
            local result = results[testName]
            if result and result.msg then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(result.msg, nil, nil, nil, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)

        local sep = row:CreateTexture(nil, "BACKGROUND")
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.3)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

        rows[testName] = row
        y = y + 28
    end
    content:SetHeight(y)
end

local function CreateTestUI()
    if TestFrame then
        TestFrame:Show()
        return TestFrame
    end

    local f = CreateFrame("Frame", "DebindTestFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(650, 500)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f.TitleText:SetText("Debind Test")

    f.runBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.runBtn:SetSize(100, 24)
    f.runBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -30)
    f.runBtn:SetText("실행")
    f.runBtn:SetScript("OnClick", function()
        RunAllTests()
    end)

    f.copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.copyBtn:SetSize(100, 24)
    f.copyBtn:SetPoint("RIGHT", f.runBtn, "LEFT", -6, 0)
    f.copyBtn:SetText("복사")
    f.copyBtn:SetScript("OnClick", function()
        if lastResultText ~= "" then
            ShowCopyableText(lastResultText)
        else
            local stored = DB().last
            ShowCopyableText(stored or "아직 실행한 적이 없다.")
        end
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(590, 1)
    scrollFrame:SetScrollChild(content)
    BuildRows(content)

    -- Where a test parks the frame it wants clicked. Sits over the middle of the list, which is
    -- the one place it cannot be missed, and is hidden the moment the click lands.
    f.clickSlot = CreateFrame("Frame", nil, f)
    f.clickSlot:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.clickSlot:SetSize(420, 160)
    f.clickSlot:SetFrameStrata("FULLSCREEN_DIALOG")
    f.clickSlot:Hide()

    local slotBg = f.clickSlot:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 0.92)

    f.clickSlot.label = f.clickSlot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.clickSlot.label:SetPoint("TOP", f.clickSlot, "TOP", 0, -14)
    f.clickSlot.label:SetWidth(390)
    f.clickSlot.label:SetJustifyH("CENTER")

    f.clickSlot.target = CreateFrame("Frame", nil, f.clickSlot)
    f.clickSlot.target:SetPoint("BOTTOM", f.clickSlot, "BOTTOM", 0, 16)
    f.clickSlot.target:SetSize(380, 90)

    TestFrame = f
    return f
end

function UI.Open()
    return CreateTestUI()
end

function UI.Update(testName)
    PaintRow(testName)
end

--- A second run cannot start while one is going -- `RunAllTests` refuses it -- so the button
--- says so rather than letting it be pressed and answering in the chat frame.
function UI.SetRunning(running)
    if TestFrame then
        TestFrame.runBtn:SetEnabled(not running)
        TestFrame.runBtn:SetText(running and "실행 중" or "실행")
    end
end

--- Marks the test the runner is on, and scrolls nothing -- the list is short enough to see.
function UI.SetActive(testName)
    local previous = activeTest
    activeTest = testName
    if previous then PaintRow(previous) end
    if testName then PaintRow(testName) end
end

--- Puts a frame in the middle of the window and says what to do with it.
---
--- Blizzard's frames are asked for where they already are: moving or resizing one to make it
--- convenient would be the addon reaching into it, which is the thing these tests exist to
--- confirm it stopped doing.
function UI.ShowClickTarget(frame, text)
    local f = CreateTestUI()
    f.clickSlot.label:SetText(text)
    f.clickSlot:Show()

    -- **A frame we leave alone is not in here**, so the box that says "여기" would be pointing at
    -- itself. The overlay shrinks to the line of text and the text is what says where to go.
    f.clickSlot.target:SetShown(not frame.debindTestLeaveAlone)
    if frame.debindTestLeaveAlone then
        f.clickSlot:SetSize(420, 60)
    else
        f.clickSlot:SetSize(420, 160)
    end

    if not frame.debindTestLeaveAlone then
        frame:SetParent(f.clickSlot.target)
        frame:ClearAllPoints()
        frame:SetAllPoints(f.clickSlot.target)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")

        if not frame.debindTestSkin then
            frame.debindTestSkin = frame:CreateTexture(nil, "BACKGROUND")
            frame.debindTestSkin:SetAllPoints()
            frame.debindTestSkin:SetColorTexture(0.15, 0.35, 0.55, 1)
            frame.debindTestSkinText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            frame.debindTestSkinText:SetPoint("CENTER")
            frame.debindTestSkinText:SetText("여기")
        end
        frame:Show()
    end

    -- **Registered here, not at the call site.** Whatever happens to the test after this, the
    -- runner takes the overlay down -- otherwise a test that fails early leaves the window
    -- covered by the very thing that was meant to help read it.
    AddTeardown(function() UI.HideClickTarget() end)
end

function UI.HideClickTarget()
    if TestFrame then
        TestFrame.clickSlot:Hide()
    end
end

-----------------------------------------------------------
-- Slash Command
-----------------------------------------------------------

SLASH_DEBINDTEST1 = "/debtest"
SlashCmdList["DEBINDTEST"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "ui" then
        CreateTestUI()
    elseif msg == "copy" then
        if lastResultText ~= "" then
            ShowCopyableText(lastResultText)
        else
            print("|cff00ccff[DebindTest]|r No results yet. Run |cffffff00/debtest|r first.")
        end
    elseif msg == "last" then
        local stored = DB().last
        if stored then
            ShowCopyableText(stored)
        else
            print("|cff00ccff[DebindTest]|r 저장된 결과가 없다.")
        end
    elseif msg == "reload" then
        UI.Open()
        RunAllTests(function()
            ShowCopyableText(lastResultText)
        end, true)
    else
        -- **Opening does not run.** These tests cast, and one of them stops to ask for a click;
        -- a window opened to read the last results should not start any of that. The run is a
        -- button because pressing it is the point at which someone meant it.
        UI.Open()
    end
end

print("|cff00ccff[DebindTest]|r Loaded. |cffffff00/debtest|r = run & show copyable results, |cffffff00/debtest ui|r = results window.")
