local _, DebindPrivate = ...;

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
---
--- **물러날지는 전역 옵션이 정한다** (`GiveBackInBindingContext`). 없으면 물러나는 쪽이 기본인
--- 것은 여기 적힌 이유 그대로다. 액션마다 있던 `keepInBindingContext`는 그 옵션이 서면서
--- 나갔다(`giving-keys-back.md` §7).
---
--- **물러나는 일은 보안 쪽이 한다.** 여기는 점유 키 목록만 실어 보내고(`ContextKeys`), 키를
--- 놓을지 잡을지는 `UpdateGivenBackKeys`가 네 갈래를 합쳐 한 번에 정한다. 그래야 한 키의
--- 양보를 드는 곳이 `bindings.givenBack` 하나로 남는다 - 비보안 쪽에서 그 키만 따로 여닫으면
--- 차량바가 끝날 때 편집기가 열린 채로 키가 돌아오고, 편집기를 닫으며 씌우면 차량바가 서
--- 있는 내내 키가 우리 것으로 남는다.
---
--- 예전에는 집합이 움직일 때마다 리빌드를 걸었다. 집 편집기는 모드마다 컨텍스트가 갈리니
--- 한 번 열고 닫는 동안 여러 번 돌고, 리빌드는 솔버와 굽기를 통째로 다시 한다.

local YieldedKeys                 = {};

-- 컨텍스트는 12.0에서 생겼다. 하위 인터페이스 버전에서도 로드되므로 확인하고 쓴다.
local supported                   = C_KeyBindings and C_KeyBindings.GetBindingContextForAction
    and C_KeyBindings.IsBindingContextActive and Enum and Enum.BindingContext and true or false;

--- 지금 이 키를 게임에 양보 중인가. **리빌드는 안 묻는다** - 양보는 보안 쪽이 하므로 구울 때는
--- 이 답이 필요 없다. 집합이 무엇으로 채워졌는지를 밖에서 읽을 수 있는 자리로 남는다.
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

--- Makes `set` hold exactly the keys in `claimed`. True if that moved anything.
local function ReplaceSet(set, claimed)
    local changed = false;
    for key in pairs(claimed) do
        if (not set[key]) then
            changed = true;
            break;
        end
    end
    if (not changed) then
        for key in pairs(set) do
            if (not claimed[key]) then
                changed = true;
                break;
            end
        end
    end

    if (changed) then
        wipe(set);
        for key in pairs(claimed) do
            set[key] = true;
        end
    end
    return changed;
end

local _claimed = {};

--- Recomputes the keys handed to the game. True if the set changed.
function DebindPrivate.RefreshYieldedKeys()
    wipe(_claimed);
    if (supported and AnyContextActive() and DebindPrivate.GiveBackInBindingContext()) then
        CollectClaimedKeys(_claimed);
    end
    return ReplaceSet(YieldedKeys, _claimed);
end

--- 알림이 컨텍스트 활성화보다 먼저 올 수 있다. HouseEditorFrame:OnShow는
--- ActivateBindingContext를 부른 다음에 StateUpdated를 쏘지만, HOUSE_EDITOR_MODE_CHANGED는
--- 그보다 앞선다. 그 시점에 세면 활성 컨텍스트가 하나도 없어서 빈손으로 끝나고,
--- 뒤이어 오는 알림이 없으니 그대로 굳는다. 그래서 세는 일을 다음 프레임으로 미룬다.
local scheduled = false;

local _lines = {};
local _sorted = {};

--- Whether a transition arrived during a fight and is still owed its crossing.
local pendingPush = false;

--- Writes the claimed set into the restricted `ContextKeys`.
---
--- **Assignments rather than a list the body has to cut up.** A parser in the restricted
--- environment is a cost on every transition and a body that goes wrong without saying so; this is
--- the shape `ApplyGiveBack` already emits.
---
--- Sorted so two transitions claiming the same keys emit the same bytes, which is what makes a
--- recorded run readable.
function DebindPrivate.BakeContextKeys(driver)
    wipe(_sorted);
    for key in pairs(YieldedKeys) do
        _sorted[#_sorted + 1] = key;
    end
    sort(_sorted);

    wipe(_lines);
    _lines[1] = "wipe(ContextKeys)";
    for i = 1, #_sorted do
        _lines[i + 1] = format("ContextKeys[%q]=true", _sorted[i]);
    end
    SecureHandlerExecute(driver, table.concat(_lines, "\n"));
    -- Whatever a fight refused has just been made good, by the rebuild or by the flush below.
    pendingPush = false;
end

--- Hands the set over and has the restricted side work every key out again.
---
--- **The call is made whether or not the set moved.** What it decides is the union of four
--- sources, and the other three move without this one; the pass is what makes a key that is now
--- only wanted by one of them come back. A pass that decides what the last one did touches no
--- binding at all (`UpdateGivenBackKeys`).
local function PushContextKeys(rebake)
    -- Nothing can cross into the restricted side during a fight. Same constraint a rebuild is
    -- under, and `PLAYER_REGEN_ENABLED` is where both are paid.
    if (InCombatLockdown()) then
        pendingPush = true;
        return;
    end

    local driver = DebindPrivate.BindingDriver;
    if (rebake) then
        DebindPrivate.BakeContextKeys(driver);
    end
    SecureHandlerExecute(driver, [[self:RunAttribute("UpdateGivenBackKeys")]]);
end

--- The crossing a fight refused, made once it ends (`Events.lua`).
---
--- **Baked again rather than replayed.** What was refused is not a set but the fact that the set
--- moved, and it may have moved several times over the fight.
function DebindPrivate.FlushContextKeys()
    if (pendingPush) then
        PushContextKeys(true);
    end
end

local function DoRefresh()
    scheduled = false;
    PushContextKeys(DebindPrivate.RefreshYieldedKeys());
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

