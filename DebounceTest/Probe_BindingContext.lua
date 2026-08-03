-- Probe_BindingContext.lua
-- Midnight의 바인딩 컨텍스트(하우징 편집기)가 Debounce의 오버라이드 바인딩과
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

-----------------------------------------------------------
-- 프로브 대상 키
-----------------------------------------------------------

-- 휠은 Debounce 유저가 실제로 쓰는 키라서 기본으로 넣는다.
-- BUTTON1/2는 Debounce가 hover 외에는 막고 있으므로 제외.
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

local function SampleKeys()
    local out = {}
    for _, key in ipairs(probeKeys) do
        -- GetBindingAction의 2번째 인자(checkOverride)는 레거시 API라
        -- 생성된 문서에 없다. 두 형태를 다 찍어서 살아있는지부터 본다.
        local entry = {
            action_default = GetBindingAction(key),
            action_checkOverride = GetBindingAction(key, true),
            action_noOverride = GetBindingAction(key, false),
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

    local before = Sample("OFF (baseline)")

    local activateErrors = SetAllContexts(true)
    -- ON 샘플링이 터져도 컨텍스트는 반드시 되돌린다
    local ok, during = pcall(Sample, "ON (all contexts active)")
    local deactivateErrors = SetAllContexts(false)

    local after = Sample("OFF (restored)")

    local result = {
        before = before,
        during = ok and during or ("ERR: " .. tostring(during)),
        after = after,
        activateErrors = next(activateErrors) and activateErrors or "none",
        deactivateErrors = next(deactivateErrors) and deactivateErrors or "none",
        note = "before/after가 다르면 원복 실패. /reload 할 것.",
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
        local failed = SetAllContexts(true)
        -- 컨텍스트를 손으로 켜면 HOUSE_EDITOR_MODE_CHANGED가 안 오므로 재빌드를 직접 민다.
        local private = _G.DebouncePrivate
        if (private and private.QueueUpdateBindings) then private.QueueUpdateBindings() end
        Status("전 컨텍스트 ON + 재빌드 요청. 실패: %s", next(failed) and "있음(DevTool 확인)" or "없음")
        if (next(failed)) then Dump(PROBE_NAME .. ":activateErrors", failed) end
    elseif (cmd == "off") then
        SetAllContexts(false)
        local private = _G.DebouncePrivate
        if (private and private.QueueUpdateBindings) then private.QueueUpdateBindings() end
        Status("전 컨텍스트 OFF + 재빌드 요청.")
    elseif (cmd == "key" and arg and arg ~= "") then
        local key = strupper(strtrim(arg))
        tinsert(probeKeys, key)
        Status("프로브 키 추가: %s", key)
    else
        RunFullProbe()
    end
end
