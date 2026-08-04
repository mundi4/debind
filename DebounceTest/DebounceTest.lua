-- DebounceTest: Integration test framework for Debounce addon
-- Usage: /debtest to run all tests, /debtest ui to open UI
-- Requires DEBUG mode (DebouncePrivate must be exposed as global)

local DebouncePrivate = _G.DebouncePrivate
if not DebouncePrivate then
    print("|cffff0000[DebounceTest]|r DebouncePrivate not found. Enable DEBUG mode in Constants.lua.")
    return
end

local Constants = DebouncePrivate.Constants
local band, bor = bit.band, bit.bor

-----------------------------------------------------------
-- Test Framework
-----------------------------------------------------------

local tests = {}
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
-- Test Helpers: Setup & Teardown
-----------------------------------------------------------

-- GENERAL layer (layerID=1)에 테스트 액션을 삽입하고 UpdateBindings 실행
local GENERAL_LAYER_ID = 1

local function GetGeneralLayer()
    return DebouncePrivate.GetProfileLayer(GENERAL_LAYER_ID)
end

local insertedActions = {}

local function InsertAction(action)
    local layer = GetGeneralLayer()
    layer:Insert(action)
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
        DebouncePrivate.UpdateBindings()
    end
end

local function ApplyBindings()
    DebouncePrivate.UpdateBindings()
end

-- KeyMap에서 특정 키에 바인딩된 정보 찾기
local function GetKeyBindings(key)
    local keyMap = DebouncePrivate.KeyMap
    return keyMap[key]
end

-- KeyMap에서 특정 키의 N번째 바인딩 정보
local function GetNthBinding(key, n)
    local bindings = GetKeyBindings(key)
    return bindings and bindings[n]
end

-- DefaultClickFrame의 attribute 확인
local function GetClickAttribute(attrPrefix, buttonName)
    local frame = DebouncePrivate.DefaultClickFrame
    return frame:GetAttribute(attrPrefix .. buttonName)
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
        local issue = DebouncePrivate.GetBindingIssue(action)
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
        local issue = DebouncePrivate.GetBindingIssue(action)
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
        local issue = DebouncePrivate.GetBindingIssue(action)
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
        local _, args = DebouncePrivate.ParseMacroText(text)
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
        local _, args = DebouncePrivate.ParseMacroText(text)
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
        local _, args = DebouncePrivate.ParseMacroText(text)
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

        local driver = DebouncePrivate.BindingDriver
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
-- Copyable Output Popup
-----------------------------------------------------------

local CopyFrame

local function ShowCopyableText(text)
    if not CopyFrame then
        local f = CreateFrame("Frame", "DebounceTestCopyFrame", UIParent, "BasicFrameTemplateWithInset")
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

local function RunAllTests()
    wipe(results)
    local passCount, failCount, errorCount = 0, 0, 0
    local outputLines = {}

    for _, testName in ipairs(testOrder) do
        -- Clean state before each test
        CleanupActions()

        local test = tests[testName]
        local ok, passed, msg = pcall(test.run)

        if not ok then
            errorCount = errorCount + 1
            results[testName] = { status = "error", msg = passed }
            local line = format("ERROR %s: %s", testName, passed)
            tinsert(outputLines, line)
            print(format("|cffff8800%s|r", line))
        elseif passed then
            passCount = passCount + 1
            results[testName] = { status = "pass", msg = msg }
            tinsert(outputLines, msg)
            print(msg)
        else
            failCount = failCount + 1
            results[testName] = { status = "fail", msg = msg }
            tinsert(outputLines, msg)
            print(msg)
        end
    end

    -- Final cleanup
    CleanupActions()

    local summary = format("[DebounceTest] Complete: %d passed, %d failed, %d errors / %d total",
        passCount, failCount, errorCount, #testOrder)
    tinsert(outputLines, "")
    tinsert(outputLines, summary)
    print(format("\n|cff00ccff%s|r", summary))

    lastResultText = table.concat(outputLines, "\n")
end

-----------------------------------------------------------
-- UI (optional, simple scrollable results viewer)
-----------------------------------------------------------

local TestFrame

local function CreateTestUI()
    if TestFrame then
        TestFrame:Show()
        return
    end

    local f = CreateFrame("Frame", "DebounceTestFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(650, 500)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f.TitleText:SetText("Debounce Test Results")

    local runBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    runBtn:SetSize(100, 24)
    runBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -30)
    runBtn:SetText("Run All")
    runBtn:SetScript("OnClick", function()
        RunAllTests()
        -- refresh display
        TestFrame:Hide()
        CreateTestUI()
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(590, 1)
    scrollFrame:SetScrollChild(content)

    local yOffset = 0
    for _, testName in ipairs(testOrder) do
        local test = tests[testName]
        local result = results[testName]

        local row = CreateFrame("Frame", nil, content)
        row:SetSize(590, 28)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)

        local statusIcon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusIcon:SetPoint("LEFT", 4, 0)
        statusIcon:SetWidth(14)
        if result then
            if result.status == "pass" then
                statusIcon:SetText("|cff00ff00O|r")
            elseif result.status == "fail" then
                statusIcon:SetText("|cffff0000X|r")
            else
                statusIcon:SetText("|cffff8800!|r")
            end
        else
            statusIcon:SetText("|cffffff00-|r")
        end

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", statusIcon, "RIGHT", 6, 0)
        nameText:SetWidth(560)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)

        local displayText = testName
        if result and result.msg then
            -- strip color codes for compact display
            local clean = result.msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            displayText = displayText .. "  " .. (result.status == "pass" and "|cff888888" or "|cffff8888") .. clean .. "|r"
        end
        nameText:SetText(displayText)

        -- Tooltip with description
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(testName, 1, 1, 1)
            if test.description then
                GameTooltip:AddLine(test.description, nil, nil, nil, true)
            end
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

        yOffset = yOffset + 28
    end

    content:SetHeight(yOffset)
    TestFrame = f
end

-----------------------------------------------------------
-- Slash Command
-----------------------------------------------------------

SLASH_DEBOUNCETEST1 = "/debtest"
SlashCmdList["DEBOUNCETEST"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "ui" then
        CreateTestUI()
    elseif msg == "copy" then
        if lastResultText ~= "" then
            ShowCopyableText(lastResultText)
        else
            print("|cff00ccff[DebounceTest]|r No results yet. Run |cffffff00/debtest|r first.")
        end
    else
        RunAllTests()
        ShowCopyableText(lastResultText)
    end
end

print("|cff00ccff[DebounceTest]|r Loaded. |cffffff00/debtest|r = run & show copyable results, |cffffff00/debtest ui|r = results window.")
