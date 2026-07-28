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
        -- local function initDB(dbKey)
        --     local dbTbl = _G[dbKey];
        --     if (not dbTbl) then
        --         dbTbl = {};
        --         _G[dbKey] = dbTbl;
        --     end
        --     dbTbl.dbver = dbTbl.dbver or 1;
        --     return dbTbl;
        -- end

        -- DebouncePrivate.db = {
        --     global = initDB("DebounceVars"),
        --     char = initDB("DebounceVarsPerChar"),
        -- };

        -- DebouncePrivate.db.global.options = DebouncePrivate.db.global.options or {};
        -- DebouncePrivate.db.global.options.blizzframes = DebouncePrivate.db.global.options.blizzframes or {};
        -- DebouncePrivate.Options = DebouncePrivate.db.global.options;
        
        -- DebouncePrivate.db.global.customStates = DebouncePrivate.db.global.customStates or {};
        -- DebouncePrivate.CustomStates = {};

        -- for i = 1, Constants.MAX_NUM_CUSTOM_STATES do
        --     local stateOptions = DebouncePrivate.db.global.customStates[i];
        --     if (not stateOptions) then
        --         stateOptions = {};
        --         DebouncePrivate.db.global.customStates[i] = stateOptions;
        --     end

        --     stateOptions.mode = stateOptions.mode or Constants.CUSTOM_STATE_MODES.MANUAL;
        --     if (stateOptions.mode == Constants.CUSTOM_STATE_MODES.MANUAL) then
        --         if (stateOptions.initialValue ~= nil) then
        --             stateOptions.value = stateOptions.initialValue;
        --         else
        --             stateOptions.value = stateOptions.savedValue and true or false;
        --         end
        --     else
        --         stateOptions.value = stateOptions.value or false;
        --     end

        --     DebouncePrivate.CustomStates[i] = stateOptions;
        -- end

        -- DebouncePrivate.LoadProfile();
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
