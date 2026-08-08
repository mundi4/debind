local ADDON_NAME, DebindPrivate = ...;
local L                           = DebindPrivate.L;

local Constants                   = DebindPrivate.Constants;
local dump                        = DebindPrivate.dump;
local luatype                     = type;
local EventFrame                  = CreateFrame("Frame");
local Events                      = {};

function Events.ADDON_LOADED(_, addonName)
    if (addonName == ADDON_NAME) then
        EventFrame:UnregisterEvent("ADDON_LOADED");
        DebindPrivate.InitDB();
    end
end

--- The identity fields, **refreshed on every login** - they have to follow renames, level-ups and
--- faction changes, and for a later export/import to show a human *"the Paladin named X, level
--- 80, in this file"* the entry has to carry enough to introduce itself.
---
--- **The reason this is here and not in `InitDB` (ADDON_LOADED) is `realm`, and only `realm`.**
--- Everything else is already available when the addon's files load, but
--- `GetNormalizedRealmName()` does not answer until PLAYER_LOGIN. Splitting the refresh across two
--- events for the sake of one field is worse than keeping it whole here.
---
--- `realm` arriving late costs nothing because **it is not used to identify anything** - the entry
--- is keyed by GUID, and the realm identifier is already inside it (the `205` in
--- `Player-205-0A1B2C3D`). The name is there for people to read.
local function RefreshIdentity()
    local entry = DebindPrivate.db.char;
    if (not entry) then
        return;
    end

    entry.name    = UnitName("player");
    entry.realm   = GetNormalizedRealmName();
    entry.class   = select(2, UnitClass("player"));
    entry.race    = select(2, UnitRace("player"));
    entry.sex     = UnitSex("player");
    entry.level   = UnitLevel("player");
    entry.faction = UnitFactionGroup("player");

    entry.firstSeen = entry.firstSeen or time();
    entry.lastSeen  = time();
    entry.origin    = entry.origin or "local";
end

function Events.PLAYER_LOGIN()
    -- **Everything that happens here must be synchronous.** UpdateBindings below has to be up in
    -- the same tick as PLAYER_LOGIN for the addon to survive a reconnect into a boss encounter
    -- (see the comment on ACTIVE_PLAYER_SPECIALIZATION_CHANGED). If importing the old
    -- SavedVariables fails it simply falls through - it has no right to delay bindings.
    if (DebindPrivate.ImportLegacySavedVars()) then
        -- Order matters. The import swaps out the `options`/`customStates` tables wholesale, so
        -- rebind the references **first**, then re-read the layers.
        DebindPrivate.BindDerivedTables();
        DebindPrivate.LoadProfile();
    end
    RefreshIdentity();

    EventFrame:RegisterEvent("PLAYER_LOGOUT");
    EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
    EventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED");
    EventFrame:RegisterEvent("PLAYER_PVP_TALENT_UPDATE");
    EventFrame:RegisterEvent("UPDATE_BINDINGS");
    EventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
    EventFrame:RegisterEvent("CVAR_UPDATE");
    DebindPrivate.ApplyOptions();
    DebindPrivate.UpdateBlizzardFrames(true);
    Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED();

    DebindPrivate.DisplayMessage(L["LOGIN_MESSAGE"]);
    if (DebindPrivate.CliqueDetected) then
        DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_CLIQUE_DETECTED"], WARNING_FONT_COLOR:GetRGBA());
    end

    -- **Rename-related warnings belong here, after the bindings are up.** Moving them earlier
    -- would let the migration path start talking before the bindings exist, and that is spending
    -- the combat deadline on a chat message.
    if (DebindPrivate.legacyLoadFailure) then
        DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_LEGACY_ADDON_UNAVAILABLE"],
            WARNING_FONT_COLOR:GetRGBA());
    end
    if (DebindPrivate.CheckLegacyAddonConflict()) then
        DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_LEGACY_ADDON_STILL_INSTALLED"],
            WARNING_FONT_COLOR:GetRGBA());
    end
    -- Only reachable when the dummy came back late and the user had already built something in
    -- the same place. The import refuses to overwrite in that case, so say so - a partial import
    -- that stays silent is indistinguishable from a broken one.
    if (DebindPrivate.legacySkipped) then
        DebindPrivate.legacySkipped = nil;
        DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_LEGACY_PARTIALLY_IMPORTED"],
            WARNING_FONT_COLOR:GetRGBA());
    end
end

function Events.PLAYER_LOGOUT()
    DebindPrivate.CleanUpDB();
end

function Events.TRAIT_CONFIG_UPDATED(_, configID)
    if (configID == C_ClassTalents.GetActiveConfigID()) then
        DebindPrivate.QueueUpdateBindings();
    end
end

function Events.PLAYER_PVP_TALENT_UPDATE()
    DebindPrivate.QueueUpdateBindings();
end

function Events.PLAYER_REGEN_ENABLED()
    if (#DebindPrivate.RegisterQueue > 0) then
        for i = 1, #DebindPrivate.RegisterQueue do
            DebindPrivate.RegisterFrame(DebindPrivate.RegisterQueue[i][1], DebindPrivate.RegisterQueue[i][2]);
        end
        wipe(DebindPrivate.RegisterQueue);
    end
    if (#DebindPrivate.UnregisterQueue > 0) then
        for i = 1, #DebindPrivate.UnregisterQueue do
            DebindPrivate.UnregisterFrame(DebindPrivate.UnregisterQueue[i]);
        end
        wipe(DebindPrivate.UnregisterQueue);
    end
    if (#DebindPrivate.RegisterClickQueue > 0) then
        for i = 1, #DebindPrivate.RegisterClickQueue do
            DebindPrivate.UpdateRegisteredClicks(DebindPrivate.RegisterClickQueue[i]);
        end
        wipe(DebindPrivate.RegisterClickQueue);
    end

    if (DebindPrivate.updateBindingsSuspended) then
        DebindPrivate.updateBindingsSuspended = nil;
        DebindPrivate.UpdateBindings();
    end
end

function Events.UPDATE_BINDINGS()
    DebindPrivate.QueueUpdateBindings();
end

-- **Keep this function synchronous.** PLAYER_LOGIN calls it directly and it calls
-- `UpdateBindings` directly, so bindings come up in the **same tick** as PLAYER_LOGIN. They have
-- to be there before the server re-applies combat on a reconnect into an encounter, which is why
-- this must not be switched to `QueueUpdateBindings` (next frame).
--
-- The retry branch below is the only thing that can break that guarantee, and it does not fire at
-- max level - `GetSpecialization()` already answers when the addon's files load, earlier than
-- ADDON_LOADED. What is **unverified** is the branch having no upper bound: what happens on a
-- character whose spec never arrives. See `.zzz/refactor-candidates.md` 24.
function Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED()
    local spec = C_SpecializationInfo.GetSpecialization();
    if (not spec) then
        C_Timer.After(0.05, function()
            Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED();
        end);
        return;
    end

    DebindPrivate.UpdateBindings();
end

function Events.CVAR_UPDATE(_, name, value)
    if (name == "ActionButtonUseKeyDown") then
        DebindPrivate.QueueUpdateBindings();
    end
end

EventFrame:RegisterEvent("ADDON_LOADED");
EventFrame:RegisterEvent("PLAYER_LOGIN");

EventFrame:SetScript("OnEvent", function(_, event, ...)
    if (Events[event]) then
        Events[event](event, ...);
    end
end);
