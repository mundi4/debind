local ADDON_NAME, DebindPrivate = ...;
local L                           = DebindPrivate.L;

local dump                        = DebindPrivate.dump;
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
    -- **Stood down, so this is where the addon ends.** It returns above the eight
    -- `RegisterEvent` lines below, and the only two registered at file scope are `ADDON_LOADED`
    -- and `PLAYER_LOGIN`, so this one return leaves the addon listening to nothing at all. That is
    -- also why `PLAYER_LOGOUT` never gets to call `CleanUpDB` on the way out.
    --
    -- `RunLegacyMigration` is the reason the return has to be *here* rather than only in `InitDB`:
    -- it reaches the stored table by a different path, this one.
    if (DebindPrivate.profileIsNewer) then
        DebindPrivate.ReportNewerProfile();
        return;
    end

    -- **Everything that happens here must be synchronous.** UpdateBindings below has to be up in
    -- the same tick as PLAYER_LOGIN for the addon to survive a reconnect into a boss encounter
    -- (see the comment on ACTIVE_PLAYER_SPECIALIZATION_CHANGED). If importing the old
    -- SavedVariables fails it simply falls through - it has no right to delay bindings.
    if (DebindPrivate.RunLegacyMigration()) then
        -- Order matters. The import swaps out the `options`/`switches` tables wholesale, so
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
    EventFrame:RegisterEvent("UPDATE_MACROS");
    EventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
    EventFrame:RegisterEvent("CVAR_UPDATE");
    EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
    DebindPrivate.ApplyOptions();
    DebindPrivate.UpdateBlizzardFrames(true);
    Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED();

    -- The version rides on the front of a line that was already printed, rather than taking a line
    -- of its own. It is here so that a bug report can carry it without anyone having to ask.
    --
    -- Composed here rather than written into `LOGIN_MESSAGE`, so that the three locales keep the
    -- one sentence they already have and no translator is handed work for a change that did not
    -- alter what the sentence says. The separator is what keeps the version from reading as the
    -- first word of it.
    --
    -- **ASCII, deliberately.** Each locale loads its own font file and players replace those, so a
    -- dash or a middle dot is a glyph that may or may not be there -- and when it is not, the
    -- separator that was meant to make the version legible renders as a box instead.
    DebindPrivate.DisplayMessage(format("%s |cffa0a0a0-|r %s",
        DebindPrivate.GetVersionLabel(), L["LOGIN_MESSAGE"]));
    -- **Only when it is actually costing them something.** This used to go out on the mere presence
    -- of Clique, which is most often no news at all -- and the login it does matter on is the one
    -- where a line they have learned to skip is the only thing telling them their unit frame
    -- bindings stopped. Once per session is enough on its own: the addon list cannot change without
    -- a reload, so this is the moment the answer can change.
    if (DebindPrivate.HasBindingBlockedByClique()) then
        DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_CLIQUE_DETECTED"], WARNING_FONT_COLOR:GetRGBA());
    end

    -- **The rename says nothing here.** Warnings used to be printed for a disabled companion addon
    -- and for the old one still being installed, and both were the wrong surface: a line that
    -- scrolls past while the user is reading loot and quest text is not where you put something
    -- that needs answering. The window puts an overlay up instead, and it cannot be scrolled away.
    if (DebindPrivate.CheckLegacyAddonConflict()) then
        DebindPrivate.DisplayMessage(L["WARNING_MESSAGE_LEGACY_ADDON_STILL_INSTALLED"],
            WARNING_FONT_COLOR:GetRGBA());
    end

    -- **여기서 먼저 말을 건다.** 업데이트한 사람이 겪는 것은 "잘 되던 단축키가 전부 안 먹는다"
    -- 이고, 그 상태에서 애드온 창을 열어볼 이유가 없다. 창에 붙여두면 원인을 스스로 찾아낸
    -- 사람에게만 보이는 안내가 된다.
    DebindPrivate.ShowMigrationDialogIfPending();

    --- **In this tick, never on a timer.** A unit frame addon that runs its own click casting can
    --- put its own table over `ClickCastFrames`, and the ones that do it do it from their own
    --- handler for this same event. From then on every registration goes there instead of here,
    --- its own frames and every other addon's alike. A tick later would sit after every addon's
    --- login handler and is the obvious place for this, and it is the wrong one.
    ---
    --- Logging in during a fight was measured: the whole sequence from the first `ADDON_LOADED`
    --- through `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_DISABLED` and the first event that answers
    --- `InCombatLockdown()` true arrives **before the first `OnUpdate` of the session**. There is
    --- 160ms between this event and lockdown and not one frame in it, so every delay lands after
    --- lockdown, and a frame claimed under lockdown waits for the fight to end. Reconnecting into
    --- an encounter is the login where the bindings matter most, and it is the same reason this
    --- function is synchronous (see `ACTIVE_PLAYER_SPECIALIZATION_CHANGED`).
    ---
    --- **`PLAYER_ENTERING_WORLD` catches what this one is too early for.** It is a separate event,
    --- so it is dispatched after every addon's handler for this one, and it measured 156ms later
    --- and still out of lockdown. Claiming in both places is the whole of the window.
    if (DebindPrivate.ReclaimClickCastFrames) then
        DebindPrivate.ReclaimClickCastFrames();
    end
end

--- Registered from `PLAYER_LOGIN` above, so the first one to arrive is the login's own. Also comes
--- on every zone change, which costs a table read while the name is already ours.
---
--- **This is the moment both of these need.** Every addon's login handler has run, so the frames
--- exist and whoever was going to take `ClickCastFrames` has taken it, and combat has not been
--- re-applied yet, so a frame can still be wired. It is also the last such moment: after this the
--- next one out of lockdown is `PLAYER_REGEN_ENABLED`, which is a fight away.
function Events.PLAYER_ENTERING_WORLD()
    if (DebindPrivate.ReclaimClickCastFrames) then
        DebindPrivate.ReclaimClickCastFrames();
    end
    DebindPrivate.CollectOUFFrames();
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
    --- **Before the queues, because it decides what is in them next time.** The login claim only
    --- covers an addon that had taken `ClickCastFrames` by then; one that takes it later, or that
    --- the user switches on mid-session, is caught here. Costs a table read and a metatable
    --- comparison when the name is already ours, which is every other fight.
    if (DebindPrivate.ReclaimClickCastFrames) then
        DebindPrivate.ReclaimClickCastFrames();
    end

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

--- **A `MACRO` action naming a macro that does not exist is now left out of the build entirely**
--- (`GetMissingMacroName` -> `BINDING_ISSUE_MISSING_MACRO` -> `BuildKeyMap`), so the macro store is
--- an input to what the keys are, and nothing was watching it.
---
--- What that cost: create the missing macro and the row stops being red - the window says nothing
--- is wrong - while the key stays dead until something unrelated rebuilds, or a `/reload`. The same
--- shape at login, where the store may not be answerable yet in the `PLAYER_LOGIN` tick: every
--- `MACRO` action would drop for the whole session.
---
--- Queued rather than immediate. Renaming a macro fires this per keystroke in the macro editor and
--- there is nothing to be first for.
function Events.UPDATE_MACROS()
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
        -- The click edge too, where the reader left that one to the game (`ApplyOptions`).
        DebindPrivate.ApplyOptions("unitframeUseMouseDown");
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
