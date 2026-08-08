local ADDON_NAME, DebindPrivate = ...;

--- Midnight에서 생긴 바인딩 컨텍스트 대응.
---
--- 집 편집기가 열리면 게임이 키 일부를 자기 몫으로 가져간다(Bindings_Standard.xml의
--- bindingContext 속성). 그런데 SetOverrideBinding은 정의상 그 위층이라, 그냥 두면
--- 편집기 안에서 우리가 하우징 조작 키를 가로챈다. 우리 것이 아니므로 물러난다.
---
--- 물러나는 범위는 겹치는 키뿐이다. 이 애드온은 전투용 키만 두는 곳이 아니라서
--- (점프·이동·매크로도 들어온다) 편집기가 열렸다고 전부 내리는 건 과하다.
---
--- 어떤 키가 걸리는지는 목록으로 들고 있지 않고 게임에 물어본다. 블리자드가 다음
--- 패치에서 바인딩을 더 추가해도 질의가 알아서 따라간다.

local YieldedKeys                 = {};

-- 컨텍스트는 12.0에서 생겼다. 하위 인터페이스 버전에서도 로드되므로 확인하고 쓴다.
local supported                   = C_KeyBindings and C_KeyBindings.GetBindingContextForAction
    and C_KeyBindings.IsBindingContextActive and Enum and Enum.BindingContext and true or false;

--- 지금 이 키를 게임에 양보 중인가.
function DebindPrivate.IsKeyYielded(key)
    return YieldedKeys[key] == true;
end

--- 활성 컨텍스트가 하나라도 있는지만 싸게 본다. 없으면 전수 조사를 건너뛴다.
local function AnyContextActive()
    for _, value in pairs(Enum.BindingContext) do
        if (value ~= Enum.BindingContext.None and C_KeyBindings.IsBindingContextActive(value)) then
            return true;
        end
    end
    return false;
end

--- GetBindingKey는 저장된 바인딩을 읽으므로 우리가 덮고 있어도 원래 키가 나온다.
--- 반대 방향(GetBindingByKey로 "이 키를 게임이 원하나" 묻기)은 못 쓴다. 우리 오버라이드가
--- 전 컨텍스트에서 우리 것만 돌려주기 때문이다.
local function CollectClaimedKeys(out)
    for i = 1, GetNumBindings() do
        local action = GetBinding(i);
        -- 헤더 행은 컨텍스트가 nil이다
        local context = action and C_KeyBindings.GetBindingContextForAction(action);
        if (context and context ~= Enum.BindingContext.None and C_KeyBindings.IsBindingContextActive(context)) then
            local numKeys = select("#", GetBindingKey(action));
            for j = 1, numKeys do
                local key = select(j, GetBindingKey(action));
                if (key) then
                    out[key] = true;
                end
            end
        end
    end
end

local _claimed = {};

--- 양보할 키를 다시 계산한다. 바뀌었으면 true.
function DebindPrivate.RefreshYieldedKeys()
    wipe(_claimed);

    if (supported and AnyContextActive()) then
        CollectClaimedKeys(_claimed);
    end

    local changed = false;
    for key in pairs(_claimed) do
        if (not YieldedKeys[key]) then
            changed = true;
            break;
        end
    end
    if (not changed) then
        for key in pairs(YieldedKeys) do
            if (not _claimed[key]) then
                changed = true;
                break;
            end
        end
    end

    if (changed) then
        wipe(YieldedKeys);
        for key in pairs(_claimed) do
            YieldedKeys[key] = true;
        end
    end

    return changed;
end

--- 알림이 컨텍스트 활성화보다 먼저 올 수 있다. HouseEditorFrame:OnShow는
--- ActivateBindingContext를 부른 다음에 StateUpdated를 쏘지만, HOUSE_EDITOR_MODE_CHANGED는
--- 그보다 앞선다. 그 시점에 세면 활성 컨텍스트가 하나도 없어서 빈손으로 끝나고,
--- 뒤이어 오는 알림이 없으니 그대로 굳는다. 그래서 세는 일을 다음 프레임으로 미룬다.
local scheduled = false;

local function DoRefresh()
    scheduled = false;
    if (DebindPrivate.RefreshYieldedKeys()) then
        DebindPrivate.QueueUpdateBindings();
    end
end

local function ScheduleRefresh()
    if (not scheduled) then
        scheduled = true;
        C_Timer.After(0, DoRefresh);
    end
end

--- 트리거는 둘이고 **서로 다른 전이를 맡는다.** 서로를 덮어주지 않는다:
---
---   HOUSE_EDITOR_MODE_CHANGED  - 모드 전환. 모드마다 다른 컨텍스트가 켜지고 꺼진다.
---   HouseEditor.StateUpdated   - 편집기 열림/닫힘. HouseEditorFrameMixin의 OnShow/OnHide가
---                                쏘는 것이 전부라 모드 전환에는 오지 않는다.
---
--- 컨텍스트 바인딩의 대부분이 모드 스코프라, 앞의 것이 빠지면 떠난 모드의 키를 계속
--- 양보하고 들어간 모드의 키는 양보하지 않는다. 둘 중 하나만 붙은 채로 두면 기능이
--- 반쯤 살아 있게 되므로, 어느 쪽이 붙었는지는 남겨서 나중에 물어볼 수 있게 한다.
if (supported) then
    local EventFrame = CreateFrame("Frame");
    EventFrame:SetScript("OnEvent", ScheduleRefresh);
    -- 이 인터페이스 버전에 이벤트가 없을 수도 있다.
    local modeTrigger = pcall(EventFrame.RegisterEvent, EventFrame, "HOUSE_EDITOR_MODE_CHANGED");

    -- Blizzard_HouseEditor가 아직 안 올라왔어도 등록은 된다(CallbackRegistry라서).
    local stateTrigger = EventRegistry ~= nil;
    if (stateTrigger) then
        EventRegistry:RegisterCallback("HouseEditor.StateUpdated", ScheduleRefresh, EventFrame);
    end

    DebindPrivate.BindingContextTriggers = { mode = modeTrigger, state = stateTrigger };
end
