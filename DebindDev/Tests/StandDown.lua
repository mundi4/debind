local _, Dev = ...

local DebindPrivate
Dev.OnDebindLoaded(function(private)
    DebindPrivate = private
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown

-----------------------------------------------------------
-- Test Cases: Standing down from a profile newer than this build
-----------------------------------------------------------

-- **The half of standing down that the headless spec cannot reach.** `migration_spec` pins the data
-- side, meaning that the stored table comes out exactly as it went in. It has no window and no
-- slash command, so the two doors on this side are only checkable here.
--
-- The real decision is made at ADDON_LOADED and cannot be remade inside a session, so the flag is
-- set by hand. That is the whole of what the flag does: everything downstream of it reads
-- `profileIsNewer` and nothing else.
--
-- **`/deb reset confirm` is deliberately not exercised.** It empties `_G.DebindVars` and reloads,
-- which is the tester's own settings, and the runner has no way to give them back. What is checked
-- instead is the two things that would make the second step reachable by accident: that the first
-- step deletes nothing, and that the command does not exist at all outside this state.
RegisterTest("Stood down: the window refuses and the reset asks twice", {
    description = "In front of a profile newer than itself the window refuses to open, and the first step of /deb reset erases nothing",
    run = function()
        local NAME = "Stand down"

        -- **The negative first.** `/deb reset` in ordinary operation must fall through to the
        -- window, not wipe the account, and asking before the flag is up is the only way to see
        -- that the guard inside the handler is the thing answering.
        if DebindPrivate.HandleNewerProfileReset({ "reset" }) then
            return Fail(NAME, "/deb reset took while not stood down. it has become an always-available wipe command")
        end

        local restore = DebindPrivate.profileIsNewer
        AddTeardown(function() DebindPrivate.profileIsNewer = restore end)

        DebindFrame:CloseWindow()
        AddTeardown(function() DebindFrame:CloseWindow() end)

        DebindPrivate.profileIsNewer = true

        -- The refusal sits ahead of the toggle in `ToggleUI`, so a closed window has to stay
        -- closed. Opening it would hand the user a window whose every edit is thrown away.
        DebindPublic:ToggleUI()
        if DebindFrame:IsShown() then
            return Fail(NAME, "the window opened while stood down. a binding put in here is never saved")
        end

        -- The compartment button is a second door into the same call, and it is the one a user
        -- reaches for when a slash command looks broken.
        Debind_CompartmentFunc()
        if DebindFrame:IsShown() then
            return Fail(NAME, "the window opened from the compartment button")
        end

        local before = _G.DebindVars
        if not DebindPrivate.HandleNewerProfileReset({ "reset" }) then
            return Fail(NAME, "stood down and nobody took /deb reset")
        end
        if _G.DebindVars ~= before then
            return Fail(NAME, "the first step replaced the stored table. it wipes before anything is confirmed")
        end

        -- A word that is not the token must not count as one. `confirm` is the only second word,
        -- and anything else has to land back on the first step.
        if not DebindPrivate.HandleNewerProfileReset({ "reset", "yes" }) then
            return Fail(NAME, "the second word differs, so the command was not taken at all")
        end
        if _G.DebindVars ~= before then
            return Fail(NAME, "it wiped on a word that is not confirm")
        end

        return Pass(NAME)
    end,
})

-- The other way to stand down: the ladder failed (`TryMigrateDB`). `migration_spec` pins the data
-- side and the login; `Public.lua` is not loaded there, so the window door is checked here. The
-- kit only runs on a development build, where the door raises instead of showing the dialog.
RegisterTest("Stood down after a failed ladder: the window refuses", {
    description = "With the profile's migration failed, the window stays shut and a development build raises",
    run = function()
        local NAME = "Failed ladder"

        local restore = DebindPrivate.migrationFailed
        AddTeardown(function() DebindPrivate.migrationFailed = restore end)

        DebindFrame:CloseWindow()
        AddTeardown(function() DebindFrame:CloseWindow() end)

        DebindPrivate.migrationFailed = true

        if pcall(DebindPublic.ToggleUI, DebindPublic) then
            return Fail(NAME, "a development build opened the door quietly. the failure has to be loud there")
        end
        if DebindFrame:IsShown() then
            return Fail(NAME, "the window opened on the empty profile StandDown handed out. nothing put in here is saved")
        end

        pcall(Debind_CompartmentFunc)
        if DebindFrame:IsShown() then
            return Fail(NAME, "the window opened from the compartment button")
        end

        return Pass(NAME)
    end,
})

-- **The failure dialog's buttons, dispatched by the client.** Which callback a button reaches is
-- `StaticPopup_OnClick`'s decision and Escape is `StaticPopup_EscapePressed`'s, and neither runs
-- headless. The two answers are stood in for, so keeping writes no hold and resetting wipes nothing.
RegisterTest("Failed ladder dialog: each button does its own thing and Escape does neither", {
    description = "Keep holds, Reset asks to confirm, Escape closes the dialog with neither",
    run = function()
        local NAME = "Failed ladder dialog"

        local realHold, realWipe = DebindPrivate.HoldFailedMigration, DebindPrivate.WipeStoredProfile
        AddTeardown(function()
            DebindPrivate.HoldFailedMigration, DebindPrivate.WipeStoredProfile = realHold, realWipe
            StaticPopup_Hide("DEBIND_MIGRATION_FAILED")
            StaticPopup_Hide("DEBIND_MIGRATION_RESET")
        end)
        local held, wiped = 0, 0
        DebindPrivate.HoldFailedMigration = function() held = held + 1 end
        DebindPrivate.WipeStoredProfile = function() wiped = wiped + 1 end

        local dialog = StaticPopup_Show("DEBIND_MIGRATION_FAILED")
        if not dialog then
            return Fail(NAME, "the dialog did not come up")
        end
        StaticPopup_EscapePressed()
        if dialog:IsShown() or held ~= 0 or wiped ~= 0
                or StaticPopup_FindVisible("DEBIND_MIGRATION_RESET") then
            return Fail(NAME, "Escape did more than close it")
        end

        dialog = StaticPopup_Show("DEBIND_MIGRATION_FAILED")
        dialog:GetButton(1):Click()
        if held ~= 1 then
            return Fail(NAME, "Keep did not hold")
        end

        dialog = StaticPopup_Show("DEBIND_MIGRATION_FAILED")
        dialog:GetButton(2):Click()
        local confirm = StaticPopup_FindVisible("DEBIND_MIGRATION_RESET")
        if not confirm then
            return Fail(NAME, "Reset did not ask to confirm. the second button may be dead")
        end
        if wiped ~= 0 then
            return Fail(NAME, "Reset wiped before it was confirmed")
        end
        confirm:GetButton(1):Click()
        if wiped ~= 1 then
            return Fail(NAME, "the confirmation did not wipe")
        end

        return Pass(NAME)
    end,
})
