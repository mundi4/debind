local ADDON_NAME, DebouncePrivate = ...;
local L                           = DebouncePrivate.L;

local Constants                   = DebouncePrivate.Constants;
local dump                        = DebouncePrivate.dump;
local luatype                     = type;
local EventFrame                  = CreateFrame("Frame");
local Events                      = {};

function Events.ADDON_LOADED(_, addonName)
    if (addonName == ADDON_NAME) then
        EventFrame:UnregisterEvent("ADDON_LOADED");
        DebouncePrivate.InitDB();
    end
end

function Events.PLAYER_LOGIN()
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

-- **이 함수는 동기로 유지할 것.** PLAYER_LOGIN이 이걸 직접 부르고 이게 `UpdateBindings`를
-- 직접 부르므로, 바인딩이 PLAYER_LOGIN과 **같은 틱**에 선다. 재접-인카운터에서 서버가 전투를
-- 다시 걸기 전에 서야 하는 것이라 `QueueUpdateBindings`(다음 프레임)로 바꾸면 안 된다.
--
-- 아래 재시도 갈래가 그 보장을 깨는 유일한 지점인데, 만렙에서는 안 뜬다 - `GetSpecialization()`은
-- 애드온 파일 로드 시점(ADDON_LOADED보다 앞)에 이미 값을 준다. 다만 **상한이 없어서** 스펙이
-- 영영 안 오는 캐릭터에서 어떻게 되는지는 미확인이다 → `.zzz/refactor-candidates.md` 24.
function Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    local spec = C_SpecializationInfo.GetSpecialization();
    if (not spec) then
        C_Timer.After(0.05, function()
            Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED();
        end);
        return;
    end

    DebouncePrivate.UpdateBindings();
end

function Events.CVAR_UPDATE(_, name, value)
    if (name == "ActionButtonUseKeyDown") then
        DebouncePrivate.QueueUpdateBindings();
    end
end

EventFrame:RegisterEvent("ADDON_LOADED");
EventFrame:RegisterEvent("PLAYER_LOGIN");

EventFrame:SetScript("OnEvent", function(_, event, ...)
    if (Events[event]) then
        Events[event](event, ...);
    end
end);
