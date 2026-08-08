-- Probe_BindingContext.lua
-- Midnight의 바인딩 컨텍스트(하우징 편집기)가 Debind의 오버라이드 바인딩과
-- 어떻게 상호작용하는지 조사하기 위한 일회성 프로브.
--
-- 결론이 나면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 사용법:
--   /debprobe          컨텍스트 OFF/ON 두 상태를 샘플링해서 DevTool로 내보냄 (원복까지)
--   /debprobe on       전 컨텍스트 활성화 (실사격용, 수동)
--   /debprobe off      전 컨텍스트 비활성화
--   /debprobe key <키> 프로브 대상 키 추가 (예: /debprobe key BUTTON3)

local PROBE_NAME = "BindingContextProbe"

-----------------------------------------------------------
-- 출력: DevTool > ViragDevTool > 채팅
-----------------------------------------------------------

local function Dump(name, data)
    if (_G.DevTool and _G.DevTool.AddData) then
        _G.DevTool:AddData(data, name)
        return "DevTool"
    elseif (_G.ViragDevTool_AddData) then
        _G.ViragDevTool_AddData(data, name)
        return "ViragDevTool"
    end
    return nil
end

local function Status(msg, ...)
    print("|cff00ccff[Probe]|r " .. format(msg, ...))
end

-----------------------------------------------------------
-- 컨텍스트 목록
-----------------------------------------------------------

-- Enum.BindingContext는 name -> value. 값 순으로 정렬해서 들고 있는다.
local function GetContexts()
    local list = {}
    for name, value in pairs(Enum.BindingContext) do
        tinsert(list, { name = name, value = value })
    end
    sort(list, function(a, b) return a.value < b.value end)
    return list
end

local CONTEXT_NAME = {}
for name, value in pairs(Enum.BindingContext) do
    CONTEXT_NAME[value] = name
end

local function SetAllContexts(active)
    local failed = {}
    for _, ctx in ipairs(GetContexts()) do
        if (ctx.value ~= Enum.BindingContext.None) then
            local fn = active and C_KeyBindings.ActivateBindingContext or C_KeyBindings.DeactivateBindingContext
            local ok, err = pcall(fn, ctx.value)
            if (not ok) then
                failed[ctx.name] = tostring(err)
            end
        end
    end
    return failed
end

--- 되돌리기는 "전부 끄기"가 **아니다.**
---
--- 이 프로브가 흥미로워지는 순간은 하우스 편집기가 열려 있을 때인데, 바로 그때 편집기가
--- 자기 OnShow에서 컨텍스트를 켜둔 상태다. 전부 끄면 그걸 같이 꺼버리고, 블리자드는
--- 다음 OnShow까지 다시 켜지 않는다 - 편집기 자기 단축키가 세션 내내 죽는다.
--- 애드온 전체가 "블리자드 것은 건드리지 않는다"로 서 있는데 시험 도구가 그걸 깨면 안 된다.
---
--- 그래서 켜기 전에 뜬 상태를 그대로 되돌려 놓는다.
local function RestoreContexts(activeByName)
    local failed = {}
    for _, ctx in ipairs(GetContexts()) do
        if (ctx.value ~= Enum.BindingContext.None) then
            local wasActive = activeByName and activeByName[ctx.name];
            local fn = wasActive and C_KeyBindings.ActivateBindingContext or C_KeyBindings.DeactivateBindingContext
            local ok, err = pcall(fn, ctx.value)
            if (not ok) then
                failed[ctx.name] = tostring(err)
            end
        end
    end
    return failed
end

--- /debprobe on이 켜기 직전에 떠둔 상태. off가 여기로 되돌린다.
local savedContexts

-----------------------------------------------------------
-- 프로브 대상 키
-----------------------------------------------------------

-- 휠은 Debind 유저가 실제로 쓰는 키라서 기본으로 넣는다.
-- BUTTON1/2는 Debind가 hover 외에는 막고 있으므로 제외.
local probeKeys = {
    "MOUSEWHEELUP",
    "MOUSEWHEELDOWN",
    "BUTTON3",
    "BUTTON4",
    "BUTTON5",
    "A",
    "D",
}

-----------------------------------------------------------
-- 샘플링
-----------------------------------------------------------

local function SampleContextedBindings()
    local out = {}
    for i = 1, GetNumBindings() do
        local action = GetBinding(i)
        -- 헤더 행은 GetBindingContextForAction이 nil을 준다
        local context = action and C_KeyBindings.GetBindingContextForAction(action)
        if (context and context ~= Enum.BindingContext.None) then
            out[action] = {
                context = context,
                contextName = CONTEXT_NAME[context] or "?",
                keys = { GetBindingKey(action) },
            }
        end
    end
    return out
end

--- 인자를 못 믿는 API는 이걸로 부른다. 실패해도 그 칸에만 남고 프로브는 계속 돈다.
local function Try(fn, ...)
    local ok, result = pcall(fn, ...)
    if (ok) then
        return result
    end
    return "ERR: " .. tostring(result)
end

local function SampleKeys()
    local out = {}
    for _, key in ipairs(probeKeys) do
        -- GetBindingAction의 2번째 인자는 레거시 시절 checkOverride였지만 지금은 아닌
        -- 것으로 보인다 - 블리자드는 GetBindingAction(key, nil, bindingContext) 꼴로
        -- 부른다(Blizzard_Keybindings.lua). 불리언을 넣으면 그냥 터질 수 있으므로
        -- 반드시 감싸서 부른다. 이름도 "무엇을 물었는지"로 바꿨다 - 예전 이름은
        -- 오버라이드를 물은 것처럼 읽혀서, 다른 걸 답해도 증거로 오해된다.
        local entry = {
            action_default = Try(GetBindingAction, key),
            action_arg2_true = Try(GetBindingAction, key, true),
            action_arg2_false = Try(GetBindingAction, key, false),
            byContext = {},
        }
        -- GetBindingByKey는 인자 이름이 문서상 'action'이지만 실제로는 키를 받는다.
        -- (Blizzard_HousingEventHandler.lua의 사용례 기준)
        for _, ctx in ipairs(GetContexts()) do
            local ok, binding = pcall(C_KeyBindings.GetBindingByKey, key, ctx.value)
            entry.byContext[ctx.name] = ok and binding or ("ERR: " .. tostring(binding))
        end
        out[key] = entry
    end
    return out
end

local function SampleActiveContexts()
    local out = {}
    for _, ctx in ipairs(GetContexts()) do
        if (ctx.value ~= Enum.BindingContext.None) then
            out[ctx.name] = C_KeyBindings.IsBindingContextActive(ctx.value)
        end
    end
    return out
end

local function Sample(label)
    return {
        label = label,
        activeContexts = SampleActiveContexts(),
        contextedBindings = SampleContextedBindings(),
        probeKeys = SampleKeys(),
    }
end

-----------------------------------------------------------
-- 본 실험: OFF -> ON -> OFF, 두 상태를 비교 가능하게 내보낸다
-----------------------------------------------------------

local function RunFullProbe()
    if (InCombatLockdown()) then
        Status("|cffff0000전투 중에는 못 돌린다.|r")
        return
    end

    local before = Sample("baseline")

    local activateErrors = SetAllContexts(true)
    -- ON 샘플링이 터져도 컨텍스트는 반드시 되돌린다
    local ok, during = pcall(Sample, "ON (all contexts active)")
    local restoreErrors = RestoreContexts(before.activeContexts)

    local after = Sample("restored")

    -- 정말로 켜졌는지 확인한다. 보호된 함수라 조용히 막히면 pcall도 성공으로 보이는데,
    -- 그러면 during == before가 되고 읽는 사람은 "컨텍스트는 우리 오버라이드에 영향이
    -- 없다"는 **거짓 결론**을 얻는다. 아무것도 안 켜졌으면 그렇다고 말해야 한다.
    local turnedOn = 0
    if (ok and during) then
        for _, active in pairs(during.activeContexts) do
            if (active) then turnedOn = turnedOn + 1 end
        end
    end

    local result = {
        before = before,
        during = ok and during or ("ERR: " .. tostring(during)),
        after = after,
        activateErrors = next(activateErrors) and activateErrors or "none",
        restoreErrors = next(restoreErrors) and restoreErrors or "none",
        contextsActuallyActivated = turnedOn,
        note = turnedOn == 0
            and "켜진 컨텍스트가 하나도 없다. during은 증거가 못 된다."
            or "before/after가 다르면 원복 실패. /reload 할 것.",
    }

    local sink = Dump(PROBE_NAME, result)
    if (sink) then
        local n = 0
        for _ in pairs(before.contextedBindings) do n = n + 1 end
        Status("%s에 '%s' 노드 추가. 컨텍스트 바인딩 %d개.", sink, PROBE_NAME, n)
    else
        Status("|cffff0000DevTool도 ViragDevTool도 없다.|r")
    end
end

-----------------------------------------------------------
-- 슬래시 명령
-----------------------------------------------------------

SLASH_DEBPROBE1 = "/debprobe"
SlashCmdList["DEBPROBE"] = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""), 2)
    cmd = strlower(cmd or "")

    if (cmd == "on") then
        -- off로 되돌릴 자리를 여기서 떠둔다. 이게 없으면 off가 편집기 것까지 끈다.
        savedContexts = SampleActiveContexts()
        local failed = SetAllContexts(true)
        -- 컨텍스트를 손으로 켜면 HOUSE_EDITOR_MODE_CHANGED가 안 오므로 재빌드를 직접 민다.
        local private = _G.DebindPrivate
        local rebuilt = private and private.QueueUpdateBindings
        if (rebuilt) then private.QueueUpdateBindings() end
        Status("전 컨텍스트 ON%s. 실패: %s",
            rebuilt and " + 재빌드 요청" or " (재빌드 못 미룸 - DEBUG 빌드가 아니다)",
            next(failed) and "있음(DevTool 확인)" or "없음")
        if (next(failed)) then Dump(PROBE_NAME .. ":activateErrors", failed) end
    elseif (cmd == "off") then
        RestoreContexts(savedContexts)
        local private = _G.DebindPrivate
        local rebuilt = private and private.QueueUpdateBindings
        if (rebuilt) then private.QueueUpdateBindings() end
        Status("컨텍스트 원복%s.%s",
            rebuilt and " + 재빌드 요청" or " (재빌드 못 미룸 - DEBUG 빌드가 아니다)",
            savedContexts and "" or " |cffffff00켜기 전 상태를 못 떠뒀다 - 전부 껐다.|r")
        savedContexts = nil
    elseif (cmd == "key" and arg and arg ~= "") then
        local key = strupper(strtrim(arg))
        tinsert(probeKeys, key)
        Status("프로브 키 추가: %s", key)
    else
        RunFullProbe()
    end
end
