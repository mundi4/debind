local ADDON_NAME, DebouncePrivate = ...;
local L                           = DebouncePrivate.L;

local Constants                   = DebouncePrivate.Constants;
local dump                        = DebouncePrivate.dump;
local luatype                     = type;
local EventFrame                  = CreateFrame("Frame");
local Events                      = {};

--- **진단 전용. DEBUG 빌드에서만 돈다** (`--@debug@` 블록이 릴리즈에서 벗겨진다).
---
--- 답하려는 질문은 둘이다:
---
--- 1. **`GetSpecialization()`이 언제부터 값을 주나.** 로그인 경로에서 바인딩을 세우는 건
---    `ACTIVE_PLAYER_SPECIALIZATION_CHANGED`인데, 이게 nil을 받으면 0.05초 재시도로 새면서
---    `UpdateBindings`가 PLAYER_LOGIN과 같은 틱을 벗어난다. 재접-인카운터에서 서버가 전투를
---    다시 걸기 전에 바인딩이 서야 하므로 **그 창을 넘기는지**가 핵심이다.
--- 2. **`InitDB` 시점에 신원 API가 뭘 주나.** 특히 `GetNormalizedRealmName()` -
---    나머지(`UnitGUID`/`UnitClass`)는 Constants.lua가 이미 청크 로드에서 읽고 있어서
---    사실상 답이 나와 있지만, 이건 아니다.
---
--- `GetTime()`은 프레임 단위라 같은 프레임 안의 순서를 못 가른다. 그래서
--- `debugprofilestop()`(ms)을 같이 찍는다. 두 값이 같이 있어야 "다음 프레임인가, 같은
--- 프레임인가"를 읽을 수 있다.
local function Probe(label)
    if (not Constants.DEBUG) then
        return;
    end

    -- 전투 게이팅이 `InCombatLockdown()`에서 이쪽으로 옮겨가는 중으로 보인다(PTR 추출본에
    -- `Enum.AddOnRestrictionType.Combat = 0` - *"The player is actively affecting combat."*).
    -- **라이브에 있는지 모르므로 존재 확인 후에 부른다.** 없으면 "-"로 찍힌다.
    local restricted = "-";
    if (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then
        local combatType = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat or 0;
        restricted = tostring(C_RestrictedActions.IsAddOnRestrictionActive(combatType));
    end

    DebouncePrivate.DisplayMessage(format(
        "|cff00ff00%s|r ms=%.1f spec=%s guid=%s realm=%s lv=%s class=%s |cffff8080잠금=%s 교전=%s 제약=%s|r",
        label,
        debugprofilestop(),
        tostring(C_SpecializationInfo.GetSpecialization()),
        tostring(UnitGUID("player")),
        tostring(GetNormalizedRealmName()),
        tostring(UnitLevel("player")),
        tostring(select(2, UnitClass("player"))),
        tostring(InCombatLockdown()),
        tostring(UnitAffectingCombat("player")),
        restricted));
end

function Events.ADDON_LOADED(_, addonName)
    if (addonName == ADDON_NAME) then
        EventFrame:UnregisterEvent("ADDON_LOADED");
        Probe("ADDON_LOADED");
        DebouncePrivate.InitDB();
    end
end

function Events.PLAYER_ENTERING_WORLD(_, isInitialLogin, isReloadingUi)
    Probe(format("PLAYER_ENTERING_WORLD(initial=%s, reload=%s)",
        tostring(isInitialLogin), tostring(isReloadingUi)));
end

--- 진단 전용 (DEBUG에서만 등록된다). **`잠금`이 정확히 언제 내려앉는지**를 보려는 것이다.
---
--- `교전`(`UnitAffectingCombat`)은 서버가 나를 전투로 보고 있느냐고, `잠금`
--- (`InCombatLockdown`)은 클라이언트가 보호된 동작을 막고 있느냐다. **둘은 같이 안 움직인다** -
--- 로그인/리로드 시퀀스 동안 `교전=true`인데 `잠금=false`인 유예 창이 있고, 그 창 안에서
--- `UpdateBindings`가 끝나야 재접-인카운터에서 애드온이 산다.
function Events.PLAYER_REGEN_DISABLED()
    Probe("PLAYER_REGEN_DISABLED (잠금 시작)");
end

function Events.PLAYER_LOGIN()
    Probe("PLAYER_LOGIN");
    EventFrame:RegisterEvent("PLAYER_LOGOUT");
    EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
    EventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED");
    EventFrame:RegisterEvent("PLAYER_PVP_TALENT_UPDATE");
    EventFrame:RegisterEvent("UPDATE_BINDINGS");
    EventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
    EventFrame:RegisterEvent("CVAR_UPDATE");
    DebouncePrivate.ApplyOptions();
    DebouncePrivate.UpdateBlizzardFrames(true);
    Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED();

    DebouncePrivate.DisplayMessage(L["LOGIN_MESSAGE"]);
    if (DebouncePrivate.CliqueDetected) then
        DebouncePrivate.DisplayMessage(L["WARNING_MESSAGE_CLIQUE_DETECTED"], WARNING_FONT_COLOR:GetRGBA());
    end
end

function Events.PLAYER_LOGOUT()
    DebouncePrivate.CleanUpDB();
end

function Events.TRAIT_CONFIG_UPDATED(_, configID)
    if (configID == C_ClassTalents.GetActiveConfigID()) then
        DebouncePrivate.QueueUpdateBindings();
    end
end

function Events.PLAYER_PVP_TALENT_UPDATE()
    DebouncePrivate.QueueUpdateBindings();
end

function Events.PLAYER_REGEN_ENABLED()
    if (#DebouncePrivate.RegisterQueue > 0) then
        for i = 1, #DebouncePrivate.RegisterQueue do
            DebouncePrivate.RegisterFrame(DebouncePrivate.RegisterQueue[i][1], DebouncePrivate.RegisterQueue[i][2]);
        end
        wipe(DebouncePrivate.RegisterQueue);
    end
    if (#DebouncePrivate.UnregisterQueue > 0) then
        for i = 1, #DebouncePrivate.UnregisterQueue do
            DebouncePrivate.UnregisterFrame(DebouncePrivate.UnregisterQueue[i]);
        end
        wipe(DebouncePrivate.UnregisterQueue);
    end
    if (#DebouncePrivate.RegisterClickQueue > 0) then
        for i = 1, #DebouncePrivate.RegisterClickQueue do
            DebouncePrivate.UpdateRegisteredClicks(DebouncePrivate.RegisterClickQueue[i]);
        end
        wipe(DebouncePrivate.RegisterClickQueue);
    end

    if (DebouncePrivate.updateBindingsSuspended) then
        DebouncePrivate.updateBindingsSuspended = nil;
        DebouncePrivate.UpdateBindings();
    end
end

function Events.UPDATE_BINDINGS()
    DebouncePrivate.QueueUpdateBindings();
end

-- 이 재시도 루프는 로그인 경로에서 `UpdateBindings`를 **다음 틱 밖으로 밀어내는 유일한
-- 갈래**다 (§Probe 참조). 상한이 없어서, 스펙이 영영 안 오는 캐릭터(스펙 선택 전 저렙)에서는
-- 20Hz로 계속 도는 것으로 보인다 - 그것도 이 로그로 확인한다. 채팅 도배를 막으려고 처음
-- 10회는 매번, 그 뒤로는 20회(약 1초)에 한 줄로 줄인다.
local specRetryCount, specRetryStart;

function Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    local spec = C_SpecializationInfo.GetSpecialization();
    if (not spec) then
        if (Constants.DEBUG) then
            specRetryCount = (specRetryCount or 0) + 1;
            specRetryStart = specRetryStart or debugprofilestop();
            if (specRetryCount <= 10 or specRetryCount % 20 == 0) then
                Probe(format("SPEC_RETRY #%d (+%.1fms)",
                    specRetryCount, debugprofilestop() - specRetryStart));
            end
        end

        C_Timer.After(0.05, function()
            Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED();
        end);
        return;
    end

    if (Constants.DEBUG) then
        if (specRetryCount) then
            Probe(format("SPEC_READY 재시도 %d회 후 (+%.1fms)",
                specRetryCount, debugprofilestop() - specRetryStart));
            specRetryCount, specRetryStart = nil, nil;
        else
            Probe("SPEC_READY 재시도 없음");
        end
    end

    DebouncePrivate.UpdateBindings();
    Probe("BINDINGS_DONE");
end

function Events.CVAR_UPDATE(_, name, value)
    if (name == "ActionButtonUseKeyDown") then
        DebouncePrivate.QueueUpdateBindings();
    end
end

EventFrame:RegisterEvent("ADDON_LOADED");
EventFrame:RegisterEvent("PLAYER_LOGIN");

-- 진단 전용. 릴리즈에서는 이 이벤트들을 안 받는다 - 프로브 때문에 출시 동작이 달라지면 안 된다.
-- (PLAYER_REGEN_ENABLED는 PLAYER_LOGIN에서 따로 등록된다. 여기 없는 게 맞다.)
if (Constants.DEBUG) then
    EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
    EventFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
end

EventFrame:SetScript("OnEvent", function(_, event, ...)
    if (Events[event]) then
        Events[event](event, ...);
    end
end);

-- 이 파일이 실행되는 시점 = 애드온 파일 로딩 중, ADDON_LOADED보다 앞. 타임라인의 첫 줄이다.
Probe("FILE_LOAD (Events.lua)");
