-- DebindTest: Integration test framework for Debind addon
-- Usage: /debtest opens the list. Every run is a button in it -- plain, the one that includes the
-- tests which end the session, and the one that reloads first and runs on the other side.
-- Requires DEBUG mode (DebindPrivate must be exposed as global)
--
-- **What is here is what needs the game.** Twenty-nine cases came down to the headless specs
-- when the harness learned to read UpdateBindings.lua and to run the restricted environment
-- (devdocs/legacy/going-headless-outside-the-ui.md): the binding types, the twelve condition families,
-- priority ordering, the three Split: cases, the four Issue: ones and the four macro text ones.
-- Every one of them asked a question about a value, and a question about a value is answered
-- more cheaply -- and on every commit -- by npm test.
--
-- **`Events.lua` runs headless now** (2026-08-23). Everything but `ADDON_LOADED` and `PLAYER_LOGIN`
-- is registered **inside** `Events.PLAYER_LOGIN`, so an addon that was loaded and never logged in
-- hears nothing -- which is the shape every spec ran in, and the reason no event handler had ever
-- been exercised outside the game. `wow_frames.fireEvent` delivers one now. The macro-store case
-- kept only its client half here: sending `UPDATE_MACROS` is the one part no harness can do.
--
-- **Two more came down on the re-read that followed** (2026-08-23). Both were kept by a line
-- naming `GetBindingAction`, which had stopped being a reason a few hours earlier: whether a
-- fixed-wired key is ever handed back, and the state loop's own sweep over four axes. The press
-- sweep and the poll-and-press one **stay** -- those two are §9's anchors and are meant to be in
-- both places, which the one that left was not.
--
-- **Nine more came down that were never blocked by anything** (2026-08-23). Every one asked what
-- `BuildKeyMap` hands out for a key, which the harness has been able to answer since 2026-08-21;
-- what kept them here was a line above each saying otherwise. `tests/keymap_spec.lua` and two
-- cases in `tests/renumber_spec.lua` took them.
--
-- **Two more came down when a spec first drained the harness's timer queue** (2026-08-23).
-- `C_Timer.After(0)` is queued rather than run there, and `wow_frames.drainTimers` had never been
-- called by anything -- so "the mirror arrives next frame" read as out of reach when the next
-- frame was one function call away.
--
-- **Three more came down when the two frame-free UI files joined the load list** (2026-08-23).
-- `ActionDisplay.lua` names an action and `ActionTooltip.lua` writes the block that hangs off it,
-- and neither ever needed a frame -- the tooltip is an argument. So the words a reader sees are a
-- value now, and `tests/display_spec.lua` is what asks about them.
--
-- **Five more came down when `GetBindingAction` learned to answer** (2026-08-23). Overrides used
-- to cross to a recording that nothing read back, so "what is the key bound to" was the line
-- between the layers and a great many cases here were on the wrong side of it; the restricted
-- `SetBindingClick` and `GetBindingAction` share one table now (`tests/wow_frames.lua`), and
-- `tests/boundkey_spec.lua` is what asks it. **A justification naming what the harness cannot load
-- has to be re-read against `tests/run.lua` before it is believed** -- that list has grown twice.
--
-- What stayed asks something only a client can answer: a snippet the sandbox really compiled, a
-- frame under a real cursor, Blizzard's own 0.2s beat, a dialog the client builds, a real macro
-- store, a reload. **Each of those carries a line above it saying which of the three it is and
-- why**, so the next reader does not have to work out again why this one is still here.

-- **Filled at `ADDON_LOADED`, not here.** This addon loads ahead of Debind (`DebindDev.toc` says
-- why), so at the time this file runs there is no `DebindPrivate` to read. Everything below that
-- touches these is inside a function that runs at `PLAYER_LOGIN` or later, with the four tables
-- near the click-time sweep as the exception -- those are built at load time out of `Constants`,
-- so `BuildConstantTables` below carries them over to the same moment.
local DebindPrivate
local Constants
-- Some tests find a menu entry by its wording, which is what this is for. Found by position
-- instead, they quietly press something else the day one more entry appears.
local LLL
local DebindUI
local band, bor = bit.band, bit.bor

-----------------------------------------------------------
-- Test Framework
-----------------------------------------------------------

local tests = {}

--- The window, filled in further down. Declared up here because the tests and the runner both
--- drive it and both are defined before it -- the runner ticks rows as it goes, and a test that
--- needs a click asks it to show one.
local UI = {}
local testOrder = {}
local results = {}

local function RegisterTest(name, opts)
    tests[name] = opts
    tinsert(testOrder, name)
end

local function Pass(name, detail)
    return true, format("|cff00ff00PASS|r %s%s", name, detail and (" - " .. detail) or "")
end

local function Fail(name, reason)
    return false, format("|cffff0000FAIL|r %s: %s", name, reason or "unknown")
end

-----------------------------------------------------------
-- Waiting & Teardown
-----------------------------------------------------------

-- Tests run as coroutines so they can wait. **Almost nothing here has to.** This file used to say
-- the opposite -- that nothing the addon does lands in the frame it was asked for -- and paid a
-- fixed 0.4s at every step for asynchrony that is not there. Following the four paths it named:
--
--   * `SecureHandlerExecute` runs the body before it returns.
--   * `CallMethod` is **not** queued. `HANDLE:CallMethod`
--     (`Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua`) is a `securecall(pcall, ...)`
--     straight onto the method, so anything a snippet mirrors out is already in the local by the
--     time the `SecureHandlerExecute` that asked for it returns.
--   * `SetBindingClick` from the restricted environment calls `SetOverrideBindingClick` directly,
--     so `GetBindingAction` answers with the new binding immediately.
--   * `UpdateBindings` ends by setting `state-unitexists` on the driver itself
--     (`UpdateBindings.lua`, the "execute UpdateBindings with forceAll set" block), which runs
--     `_onattributechanged` -> the whole state pass -> the bindings, all inside the call. A
--     rebuild leaves nothing for the poll to finish, which is why `SetMockState` needs no wait
--     after it: it ends in a rebuild.
--
-- Two things do take time, and each has a helper that stops the moment it happens rather than
-- spending a fixed sum:
--
--   * a **queued** rebuild -- `QueueUpdateBindings` defers to `C_Timer.After(0)`, so that one
--     lands a frame later. `WaitForIdle`.
--   * Blizzard's state driver poll, up to `updatetime` (0.2s). It is what notices a unit
--     appearing or going away under a cursor that never moved, and nothing can shorten it.
--     `WaitUntil`.
--
-- **There is no fixed-duration wait left in this file, and adding one back needs an argument.**
-- The runner still understands a duration -- `coroutine.yield(seconds)` -- so the door is there;
-- what is gone is the helper that made walking through it look routine. A number here means
-- "I could not name what I am waiting for", and every one that was here turned out to be waiting
-- for something that had already happened. `devdocs/reading-back-what-you-just-set.md` has the
-- whole map, including the two traps in writing a condition to wait on.
--
-- **Tests that never yield are unaffected.** A coroutine that runs straight through finishes on
-- its first resume, and the runner steps to the next one without giving up the frame, so a suite
-- of them still completes in a single frame exactly as it did before.

--- Gives the frame back until `predicate` answers true, and no longer. Answers what the predicate
--- last answered, so the caller can tell "it happened" from "the limit ran out".
---
--- **The predicate is asked before the first yield.** Most of what this waits on is already true
--- by then, and a helper that yielded first would put back into every call site the frame this
--- exists to take out of.
---
--- A thing that never happens is indistinguishable from a slow one, so only that case costs the
--- whole `limit` -- which is the right way round, since a passing run reaches none of it.
local function WaitUntil(predicate, limit)
    local start = GetTime()
    limit = limit or 0.5
    local answer = predicate()
    while not answer and (GetTime() - start) < limit do
        coroutine.yield(0)
        answer = predicate()
    end
    return answer
end

--- True while a test is stopped waiting for a person to click something.
---
--- The runner's timeout is a guard against a coroutine that hangs, **not a budget for how fast
--- the tester is** -- and the two were the same clock. A test that asks for two clicks allows 25
--- seconds each, which is already past the 30-second ceiling, so a tester who took their time on
--- the first one had the test killed while the second prompt was still on screen. The clock stops
--- here instead.
local awaitingHuman = false

-- Saved variables are not in place while this file runs -- they arrive between then and
-- ADDON_LOADED -- so the table is never assumed, only ensured.
local function DB()
    DebindDevDB = DebindDevDB or {}
    return DebindDevDB
end

--- Somewhere a test may leave things for a later phase of itself.
---
--- It has to be here rather than in the profile: the runner tears down and cleans up **before**
--- reloading, so anything a test put in a layer is gone by the time the session comes back. That
--- is deliberate -- a run that ends the session must not leave the profile carrying its litter --
--- and it means "survives a reload" has to be stored somewhere the runner does not clean.
local function Scratch()
    local db = DB()
    db.scratch = db.scratch or {}
    return db.scratch
end

-- Asking for a `/reload` is not a longer wait, so it does not travel as one. This marker is what
-- the runner recognises, and it cannot collide with a duration.
local RELOAD_REQUEST = {}

--- Ends the game session and picks this same test back up afterwards, with `phase` telling it
--- where it left off.
---
--- **This call does not return.** A coroutine does not survive a reload, so the test is not
--- resumed -- it is *run again from the top*, and reads `phase` to find its place. Which makes a
--- reload-crossing test a small state machine rather than one straight line:
---
---     run = function(phase)
---         if not phase then ... ; return RequestReload("after") end
---         ...
---     end
---
--- The runner writes its progress out before reloading, so what a later phase compares against
--- is what actually survived the round trip.
local function RequestReload(phase)
    coroutine.yield(RELOAD_REQUEST, phase or "after-reload")
    -- Unreachable: the runner reloads instead of resuming. Erroring here beats returning to a
    -- test that believes a reload happened when none did.
    error("RequestReload: the reload never happened")
end

-- Undo registered by whatever needs undoing. **The runner calls these, not the test.** A test
-- that owns its own cleanup only has to be wrong once -- fail early, error, or simply forget --
-- and everything after it runs against a state nobody chose. So the tail is not the test's to
-- run; it belongs to the loop that knows the test ended, however it ended.
local teardowns = {}

local function AddTeardown(fn)
    tinsert(teardowns, fn)
end

--- Runs every registered undo, newest first, and clears the list. Each one is isolated: an undo
--- that throws must not keep the ones after it from running, which is the whole point of having
--- them here.
local function RunTeardowns()
    for i = #teardowns, 1, -1 do
        local ok, err = pcall(teardowns[i])
        if not ok then
            print(format("|cffff8800[DebindTest]|r teardown failed: %s", tostring(err)))
        end
    end
    wipe(teardowns)
end

-----------------------------------------------------------
-- Test Helpers: Setup & Teardown
-----------------------------------------------------------

--- Tests live in a layer of their own, and while a run is on it is the only layer there is.
---
--- They used to go into the user's GENERAL layer. Then a test key carried the user's own actions
--- too: the record a test looked up by position could be someone else's, the winner a click-time
--- test read back could be someone else's, and asking the tester to click a frame fired whatever
--- **they** had bound there. None of that is a flaky test - a test that cannot tell its own
--- record from the user's is not testing anything.
---
--- The layer is built here rather than by the addon, and it is never saved. It borrows a real
--- layer's metatable because the prototype is private to `Profile.lua` - the methods are what is
--- wanted, not the storage.
local testLayer

local function GetTestLayer()
    if not testLayer then
        local real = assert(DebindPrivate.GetProfileLayer(1), "the profile is not up yet")
        testLayer = setmetatable({
            -- Past every real layer id, so ordering can never mistake it for a saved one.
            layerID = 100,
            actions = {},
        }, getmetatable(real))
    end
    return testLayer
end

-----------------------------------------------------------
-- Test Helpers: The game's own bindings
-----------------------------------------------------------

-- Isolating the profile layer was only half of it. **The game's own binding table is still under
-- everything**, and it belongs to whoever is running the test.
--
-- What that costs: `GetBindingAction(KEY)` on a key the test did not bind answers with the
-- tester's action rather than nothing, so every "and now it goes away again" assertion is really
-- "and now it says something else" -- true on a machine where that key is free and quietly
-- meaningless on one where it is not. A test key that fires the tester's spell is the same fault
-- wearing a louder coat. The suite is supposed to give the same answer on every machine.
--
-- **Only the in-memory set is touched.** `SetBinding` writes there; nothing is written to disk
-- until someone calls `SaveBindings`, and this addon never does. `LoadBindings` reads the saved
-- set back over it, which is exactly how Blizzard's own quick-keybind cancels
-- (`QuickKeybind.lua:180`). So restoring is one call and it restores the truth, not a copy we
-- remembered.
--
-- The danger is the session ending while they are off, so every exit is covered: the runner
-- restores when the run finishes, when a reload is asked for, when the reload popup is declined,
-- and on `PLAYER_LOGOUT`. A crash writes no config at all, so it needs no cover.

--- Left bound, so a run that wedges is still recoverable.
---
--- **Not a softening of "turn them all off" -- an escape hatch.** Without a menu key and a way to
--- open chat, a tester whose run hangs cannot type `/reload`, and the way out of a test kit is
--- Alt+F4. Two commands is the smallest list that keeps that from being true.
local KEEP_BOUND = {
    TOGGLEGAMEMENU = true,
    OPENCHAT = true,
    OPENCHATSLASH = true,
}

--- The window's one checkbox, off by default. A probe rather than a setting: it exists so "is
--- this failure the blackout's doing" is answered by one run instead of by argument.
local skipBlackout = false

local blackedOut = false
local restoreWatcher

--- Puts the tester's bindings back. Safe to call when they were never taken away.
local function RestoreGameBindings()
    if not blackedOut then return end

    -- `LoadBindings` is refused in combat. Rather than dropping the restore, the watcher is left
    -- armed and does it when the fight ends -- `blackedOut` stays true so nothing thinks it ran.
    if InCombatLockdown() then
        if restoreWatcher then restoreWatcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end

    blackedOut = false
    if restoreWatcher then restoreWatcher:UnregisterAllEvents() end
    LoadBindings(GetCurrentBindingSet())
end

--- Unbinds everything the game currently has bound. Returns how many keys went, or nil plus a
--- reason if it could not.
local function BlackoutGameBindings()
    if blackedOut then return 0 end
    if InCombatLockdown() then
        return nil, "bindings cannot be touched in combat"
    end

    if not restoreWatcher then
        restoreWatcher = CreateFrame("Frame")
        restoreWatcher:SetScript("OnEvent", function() RestoreGameBindings() end)
    end
    restoreWatcher:RegisterEvent("PLAYER_LOGOUT")

    -- Collected before anything is cleared. `GetBindingKey` answers from the table being
    -- rewritten, so reading and clearing in the same pass drops keys.
    local doomed = {}
    for i = 1, GetNumBindings() do
        local command = GetBinding(i)
        -- Header rows have no command, and a command may have no key at all.
        if command and not KEEP_BOUND[command] then
            for j = 1, select("#", GetBindingKey(command)) do
                local key = select(j, GetBindingKey(command))
                if key then
                    doomed[#doomed + 1] = key
                end
            end
        end
    end

    -- Set before the first `SetBinding`, so a restore is owed even if the loop throws partway.
    blackedOut = true
    for i = 1, #doomed do
        SetBinding(doomed[i])
    end

    return #doomed
end

--- Swaps the addon's layer enumeration for one that yields only the test layer, and takes the
--- game's own bindings out from under it.
---
--- **Everything that decides what is bound goes through these two functions** -- `BuildKeyMap`,
--- the ordering, the UI -- and both are looked up on `DebindPrivate` at each call, so replacing
--- the fields is enough and the addon needs no seam of its own. Test scaffolding does not belong
--- in a shipped build.
---
--- `EnumerateAllProfileLayers` is the second one. It answers "everything stored" rather than "what
--- is live", which is what the overview walks so that inactive specializations show up; leaving it
--- alone would have an isolated run reading the tester's real profile through half its paths while
--- `BuildKeyMap` held only the test layer. It yields two more values, and the stand-in has to yield
--- them too or the rows come out with no scope and no specialization.
---
--- **`FindLayerID` is the third**, and it is not an enumeration -- it walks `LayerArray`, a local in
--- `Profile.lua` that the test layer is deliberately not in. Left alone it answers nil for every
--- test action, and everything built on it becomes a silent no-op: `RenumberKeyGroupForAction`
--- returns without renumbering, so the arrows and every edit path would appear to work and settle
--- nothing. A test that drives a real button has to reach the same layer the run is isolated to.
local realEnumerate
local realEnumerateAll
local realFindLayerID

local function SetIsolated(isolated)
    if isolated then
        -- **Wrapped, because this is a convenience and the run is not.** Blacking the tester's
        -- keys out makes the suite reproducible; a run that cannot start because that failed
        -- would be the tail wagging the dog. Say so and carry on.
        if not skipBlackout then
            local ok, cleared, err = pcall(BlackoutGameBindings)
            if not ok then
                print(format("|cffff8800[DebindTest]|r clearing the existing bindings raised: %s. Carrying on regardless.",
                    tostring(cleared)))
            elseif not cleared then
                print(format("|cffff8800[DebindTest]|r could not clear the existing bindings: %s. The run goes ahead with the tester's own keys in place.", err))
            elseif cleared > 0 then
                print(format("|cff00ccff[DebindTest]|r cleared %d existing binding(s). They go back when the run ends.", cleared))
            end
        end

        if not realEnumerate then
            realEnumerate = DebindPrivate.EnumerateProfileLayers
            realEnumerateAll = DebindPrivate.EnumerateAllProfileLayers
            local only = { GetTestLayer() }
            DebindPrivate.EnumerateProfileLayers = function()
                return function(tbl, index)
                    index = index + 1
                    if tbl[index] then
                        return index, tbl[index]
                    end
                end, only, 0
            end
            -- Scope 5 and no specialization. **Neither value can decide anything** -- there is one
            -- layer, so every row carries the same pair -- and 5 is what the layer it was cloned
            -- from would answer (`GetTestLayer` takes the general layer's metatable). What matters
            -- is that they are answered at all: a nil scope would reach the comparator.
            DebindPrivate.EnumerateAllProfileLayers = function()
                return function(tbl, index)
                    index = index + 1
                    if tbl[index] then
                        return index, tbl[index], 5, 0
                    end
                end, only, 0
            end

            realFindLayerID = DebindPrivate.FindLayerID
            DebindPrivate.FindLayerID = function(action)
                if action == nil then
                    return nil
                end
                local layer = only[1]
                for _, candidate in layer:Enumerate() do
                    if candidate == action then
                        return layer.layerID, layer
                    end
                end
                -- Not the test layer's. Falls through to the real walk so a test that reaches for
                -- something the tester actually owns is answered rather than quietly told "nowhere".
                return realFindLayerID(action)
            end
        end
    else
        pcall(RestoreGameBindings)
        if realEnumerate then
            DebindPrivate.EnumerateProfileLayers = realEnumerate
            DebindPrivate.EnumerateAllProfileLayers = realEnumerateAll
            DebindPrivate.FindLayerID = realFindLayerID
            realEnumerate = nil
            realEnumerateAll = nil
            realFindLayerID = nil
        end
    end

    if not InCombatLockdown() then
        DebindPrivate.UpdateBindings()
    end
end

--- Moves the conditions into `action.conditions`.
---
--- Tests write conditions flat: `InsertAction({ ..., combat = true })`. The stored shape is
--- nested (`devdocs/action-and-binding-shapes.md`), so planting one flat leaves the condition
--- short of the binding and the action runs **without the condition the test believes it set**.
--- An action missing a condition is the wider one, so it usually goes green.
---
--- **What counts as a condition is not decided here.** `Constants.IsConditionField` answers it
--- the same way production does.
local function NestConditions(action)
    local conditions = action.conditions
    for k, v in pairs(action) do
        if Constants.IsConditionField(k) then
            conditions = conditions or {}
            conditions[k] = v
            action[k] = nil
        end
    end
    action.conditions = conditions
    return action
end

local function InsertAction(action)
    local layer = GetTestLayer()
    layer:Insert(NestConditions(action))
    -- The layer is what hands out the order number. Without one, actions sharing a condition all
    -- carry a nil `seq`, nothing settles which fires first, and a test expecting insertion order
    -- moves with whatever the sort happens to do.
    layer:PlaceInKeyGroup(action)
    return action
end

--- Empties the layer wholesale. Nothing else is in it, so there is nothing to be careful about.
local function CleanupActions()
    wipe(GetTestLayer().actions)
    if not InCombatLockdown() then
        DebindPrivate.UpdateBindings()
    end
end

--- Waits until no rebuild is queued any more.
---
--- **A rebuild refills `States` wholesale.** One queued during setup that goes off in the middle
--- of a test erases the state the test had stood up, and the symptom is "the value disappeared
--- for no reason" -- which is how the hover slot died once.
---
--- A direct `DebindPrivate.UpdateBindings()` needs none of this: it finishes everything inside
--- the call. This is for the queued kind, which `QueueUpdateBindings` hands to `C_Timer.After(0)`.
local function WaitForIdle(limit)
    WaitUntil(function() return not DebindPrivate.IsUpdateBindingsQueued() end, limit or 2)
    -- An empty queue does not mean that rebuild has finished -- the timer callback clears the
    -- flag before it calls `UpdateBindings` -- so one more frame, for whatever follows it.
    coroutine.yield(0)
end

local function ApplyBindings()
    DebindPrivate.UpdateBindings()
    WaitForIdle()
end

-- What `KeyMap` holds for one key.
local function GetKeyBindings(key)
    local keyMap = DebindPrivate.KeyMap
    return keyMap[key]
end

-- The nth binding on one key, out of `KeyMap`.
local function GetNthBinding(key, n)
    local bindings = GetKeyBindings(key)
    return bindings and bindings[n]
end


-----------------------------------------------------------
-- Test Helpers: State Injection
-----------------------------------------------------------

-- **Telling the secure side it is in combat while the client is not.**
--
-- Debind decides from `States.combat`, so an override there drives every combat path. The client
-- is not actually in combat, so no lockdown applies and the insecure side can still click, bind
-- and write attributes -- which is the whole trick. In a real fight the code is reachable but
-- nothing outside can drive it; here it is drivable but nothing stops it.
--
-- The same applies to every axis Debind watches, not only combat. A condition is a combination --
-- `[combat, harm, form:2]` -- and checking one means standing all three up at once. An axis that
-- still has to come from the world puts the test back on a raid schedule.
--
-- Nothing is written into `States` directly: the poll would put the real value back within 0.2s.
-- The override sits at the one point where the freshly computed value is about to be stored, so
-- the update loop runs exactly as it always does.
--
-- Debind carries none of this. It emits a line supplied from here, and for anyone without this
-- addon there is no line and the snippet is what it always was.
-- `%1$q` twice, not `%q` twice. `appendLine` is `format(str, ...)` and it gets one argument, so a
-- second plain `%q` has nothing to consume -- which came out as a snippet missing an `end`, not
-- as a format error. The generated line right below this one uses the positional form for the
-- same reason.
local MOCK_STATE_LINE =
    [[if (MockStatesMap[%1$q] ~= nil) then stateValue = MockStatesMap[%1$q] end]]

local mockStates = {}
local mockPlanted = false

--- Puts the table the injected line reads inside Debind's secure environment.
---
--- It lives there rather than in Debind because the line that reads it is ours: the table and the
--- line that needs it arrive together, and neither exists for a real user.
local function PlantMockTable()
    if mockPlanted then return end
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        if (not MockStatesMap) then MockStatesMap = newtable() end
    ]])
    mockPlanted = true
end

--- Writes `value` as source text the restricted environment can read back as the same value.
---
--- `%q` is not it: this is Lua 5.1, where `%q` takes strings only and errors on the booleans most
--- axes actually carry. `%s` on `tostring` is not it either -- a reaction comes back as
--- `"help"`/`"harm"`/`"other"` and unquoted that is an undefined global, which reads back as `nil`
--- and lets the injected line's `~= nil` guard decline to override. The test would then measure
--- the real world while believing it had forced the axis. So: quote strings, spell the rest out.
local function ToLiteral(value)
    if type(value) == "string" then
        return format("%q", value)
    end
    return tostring(value)
end

--- Forces `state` to `value` from the next update on. `nil` releases it.
---
--- The bindings are rebuilt because the override rides in the generated snippet -- a state that
--- has never been mocked has no line to read the table.
---
--- **Two paths read the table, and they are switched on separately.** The update loop's line
--- comes from the rebuild this does; the click path's comes from `PROBE.MockState`, which is only
--- in the body while probes are on. So a test that mocks a state and then asks what a *press*
--- decided has to call `EnableProbes()` as well -- without it the press measures the real state
--- and the mock is not wrong so much as absent.
local function SetMockState(state, value)
    PlantMockTable()

    DebindPrivate.SnippetProbes = DebindPrivate.SnippetProbes or {}
    DebindPrivate.SnippetProbes.stateValue = MOCK_STATE_LINE

    mockStates[state] = value

    SecureHandlerExecute(DebindPrivate.BindingDriver, format(
        [[MockStatesMap[%q] = %s]], state, ToLiteral(value)))

    -- Releasing is registered the moment something is held, so a test that fails in the middle
    -- does not leave the game believing it is in combat.
    AddTeardown(function()
        mockStates[state] = nil
        SecureHandlerExecute(DebindPrivate.BindingDriver, format([[MockStatesMap[%q] = nil]], state))

        -- With nothing held any more, the line stops being emitted at all -- the generated
        -- snippet goes back to being exactly the one a real user gets, rather than the one that
        -- merely reads an empty table.
        --
        -- Only this key is cleared. `SnippetProbes` also carries the bake-time table, and the two
        -- are switched on and off independently.
        if next(mockStates) == nil and DebindPrivate.SnippetProbes then
            DebindPrivate.SnippetProbes.stateValue = nil
        end

        if not InCombatLockdown() then
            DebindPrivate.UpdateBindings()
        end
    end)

    ApplyBindings()
end

--- What this addon currently holds `state` at, or nil if it is not holding it.
local function GetMockState(state)
    return mockStates[state]
end

-----------------------------------------------------------
-- Test Helpers: Snippet Probes
-----------------------------------------------------------

-- Turning a probe on means **baking the bodies again**, not flipping a flag the snippet reads.
-- Bodies are baked while Debind loads, which is necessarily before this addon exists, so the
-- decision cannot have been made then. `RebakeSnippets` rebuilds them from the raw text.
--
-- That is also what makes switching honest in the other direction: probes off is not a snippet
-- reading an empty table, it is the snippet a real user runs, rebuilt from the same source.
local probeReports = {}
local probesOn = false

--- What `PROBE.Winner(i)` becomes while probing. `debind_driver` rather than `self`, because the
--- wrapper runs with the click frame as `self` and the method lives on the driver.
--- What `PROBE.MockState(x)` becomes while probing: the same override the update loop's generated
--- snippet gets, moved to the click path. The argument is the local **and** the state name, which
--- is why they are spelled the same in `EVAL_SNIPPET`.
---
--- `~= nil` and an `if`, not `and`/`or`: most of these axes are booleans, and a false held value
--- would fall straight through an `and`/`or` to the measured one.
local PROBE_DEV = {
    Winner = [[debind_driver:CallMethod("DebindTestWinner", %s)]],
    MockState = [[if (MockStatesMap["%1$s"] ~= nil) then %1$s = MockStatesMap["%1$s"] end]],
}

local function BuildExpandTable()
    local expand = {}
    for name, form in pairs(DebindPrivate.SNIPPET_PROBES_LIVE) do
        expand[name] = form
    end
    for name, form in pairs(PROBE_DEV) do
        expand[name] = form
    end
    return expand
end

--- Starts reporting from inside the snippets. Returns nil plus a reason if it could not.
local function EnableProbes()
    if probesOn then return true end

    -- **The table has to exist before the bodies that read it do.** `PROBE.MockState` bakes into
    -- the click path unconditionally once probes are on, so a run that turns them on and never
    -- mocks anything would index a nil table on the next keypress. `SetMockState` also plants it,
    -- but that is too late and only on the paths that mock.
    PlantMockTable()

    DebindPrivate.BindingDriver.DebindTestWinner = function(_, index)
        probeReports[#probeReports + 1] = index
    end

    DebindPrivate.SnippetProbes = DebindPrivate.SnippetProbes or {}
    DebindPrivate.SnippetProbes.expand = BuildExpandTable()

    local ok, err = DebindPrivate.RebakeSnippets()
    if not ok then
        DebindPrivate.SnippetProbes.expand = nil
        return nil, tostring(err)
    end

    probesOn = true

    AddTeardown(function()
        probesOn = false
        wipe(probeReports)
        if DebindPrivate.SnippetProbes then
            DebindPrivate.SnippetProbes.expand = nil
        end
        DebindPrivate.RebakeSnippets()
    end)

    return true
end

--- Runs the click-time decision for `key` and leaves the answer in `LastWinner()`.
---
--- **Nobody presses anything.** A real press cannot be made from Lua -- `Click()` on a protected
--- button does not fire `OnClick` from insecure code, and the restricted environment has no click
--- of its own -- so the addon carries a DEBUG-only `EvalClickTimeKey` that runs the same
--- `EVAL_SNIPPET` the wrapper splices. Asking a person to press a key on every run was the other
--- option, and this kit exists to spend less of their time, not more.
---
--- What this does not prove: that a real press arrives, and that it arrives under this button
--- name. Assert those with `GetBindingAction`, which needs no press either.
---
--- Needs `EnableProbes()`: the index comes back through `PROBE.Winner`.
local function EvalClickTimeKey(key)
    local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[key]
    if not button then
        return false, format("%s is not a click-time key (not in ClickTimeKeys)", key)
    end

    wipe(probeReports)
    SecureHandlerExecute(DebindPrivate.BindingDriver, format(
        [[self:RunAttribute("EvalClickTimeKey", %q)]], button))
    return true
end

--- What the click-cast side answered: the button name it chose, or nil for "not ours, carry on".
---
--- `lastEvalAnswered` is the pair to it because **nil is one of the two real answers**, so the
--- variable alone cannot say whether the answer has arrived.
local lastEvalAnswer
local lastEvalAnswered

--- Runs the click-cast decision for `frame` as if it were clicked with mouse button `n` under
--- modifier mask `mod`. Same shape as `EvalClickTimeKey` and the same limits -- see there.
---
--- Run **for the frame**, because that is what the real wrapper does: the click-cast path reads
--- hover off the frame under the cursor rather than off the cache, and running it for anything
--- else would quietly test the other branch.
local function EvalClickCast(frame, n, mod)
    if type(DebindPrivate.ccframes[frame]) ~= "table" then
        return false, "not a registered frame (not in ccframes)"
    end

    wipe(probeReports)
    lastEvalAnswer, lastEvalAnswered = nil, false
    DebindPrivate.BindingDriver.DebindTestEvalAnswer = function(_, answer)
        lastEvalAnswer, lastEvalAnswered = answer, true
    end

    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_eval", frame)
    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[
        local f = self:GetFrameRef("debindtest_eval")
        local answer = self:RunFor(f, self:GetAttribute("EvalClickCastFrame"), %d, %d)
        self:CallMethod("DebindTestEvalAnswer", answer)
    ]], n, mod))
    return true
end

--- The button name the last `EvalClickCast` chose, or nil if it declined.
local function LastEvalAnswer()
    return lastEvalAnswer
end

--- Waits for the last `EvalClickCast` to have reported back at all, whatever it decided.
---
--- **This, not `WaitForWinner`, is what to wait on after a click-cast evaluation** -- including
--- when the test expects nothing to be chosen. The answer always comes; a winner does not, and
--- waiting on one where none is expected spends the whole limit proving what was already known.
--- Read the outcome afterwards with `LastEvalAnswer` and `LastWinner`.
local function WaitForEvalAnswer(limit)
    return WaitUntil(function() return lastEvalAnswered end, limit)
end

--- The record index the snippet last reported as the winner, or nil if it reported none.
local function LastWinner()
    return probeReports[#probeReports]
end

--- Waits for the winner report to arrive and answers with it.
---
--- In practice it is already there: the snippet reports through `CallMethod`, which is called
--- rather than queued, so the report lands inside the `SecureHandlerExecute` that ran the
--- evaluation. The wait is what covers the other case -- **no report at all**, which is how
--- "nothing matched" looks from here and is indistinguishable from a slow one. Only that case
--- costs the limit, and a sweep is mostly hits.
local function WaitForWinner(limit)
    return WaitUntil(function() return probeReports[#probeReports] end, limit)
end

--- Which of the three tables a key's record list ended up in.
---
--- **The split is the one thing nothing else here can see.** `IsKeyAlwaysOurs` is covered
--- headlessly, and the click tests cover what a press decides -- but both pass whichever table
--- the key landed in, so an emitter that ignored the verdict entirely would not show up in either.
---
--- `clickCast` is here for the same reason the other two are asked as a pair: for a key that holds
--- no keyboard role, "not state-driven" and "never emitted" look identical from the outside, and
--- only its `ClickCastKeys` slot tells them apart.
---
--- Asked of the restricted environment rather than of the source that built it. Reading the
--- generated snippet back would only confirm that the generator wrote what the generator meant to
--- write; `StateDrivenBindings` is what the update loop actually walks.
---
--- Read the answer with `WaitForMembership`.
local lastMembership
local function ReadKeyMembership(key)
    local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[key]
    local mouseButton, mousePrefix = DebindPrivate.GetMouseButtonAndPrefix(key)
    lastMembership = nil
    DebindPrivate.BindingDriver.DebindTestMembership = function(_, stateDriven, clickTime, clickCast)
        lastMembership = { stateDriven = stateDriven, clickTime = clickTime, clickCast = clickCast }
    end

    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[
        self:CallMethod("DebindTestMembership", StateDrivenBindings[%q] ~= nil, %s, %s)
    ]], key,
        button and format([[ClickTimeKeys[%q] ~= nil]], button) or "false",
        mouseButton and format([[ClickCastKeys[%d] ~= nil and ClickCastKeys[%d][%d] ~= nil]],
            mouseButton, mouseButton, DebindPrivate.GetModifierIndex(mousePrefix)) or "false"))
    return true
end

--- `{ stateDriven = bool, clickTime = bool, clickCast = bool }` from the last `ReadKeyMembership`,
--- waited for. nil means the restricted environment never came back -- the snippet failed to
--- compile, or the driver is not carrying the tables it reads.
---
--- There is no unwaited reader. The answer is already here by the time `ReadKeyMembership`
--- returns, so the wait costs nothing, and one way in means no call site can read the table
--- before the answer has replaced it.
local function WaitForMembership(limit)
    return WaitUntil(function() return lastMembership end, limit)
end

local lastRoleMap

--- 역할 맵의 상태: `{ present = bool, role = string, count = number }`.
---
--- **`present`가 다른 데서는 못 얻는 반쪽이다.** 표가 있다는 것이 곧 세 역할 헤더가 다 서 있다는
--- 뜻이라(`UpdateBindings.lua`), 그것과 "표는 있는데 비어 있다"를 값만으로는 못 가린다. 그리고
--- 혼자일 때는 헤더가 아무도 안 담으므로 비어 있는 것이 정답이다.
---
--- `role`은 문자열 자리를 비워둘 수가 없어서 없을 때 `"none"`으로 온다. 제한 환경에는
--- `tostring`이 없고, `CallMethod`에 중간 nil을 흘리면 뒤 인자가 밀린다.
local function ReadRoleMap(unit)
    lastRoleMap = nil
    DebindPrivate.BindingDriver.DebindTestRoleMap = function(_, present, role, count)
        lastRoleMap = { present = present, role = role, count = count }
    end

    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[
        local count = 0
        if (UnitRoles) then
            for _ in pairs(UnitRoles) do
                count = count + 1
            end
        end
        self:CallMethod("DebindTestRoleMap", UnitRoles and true or false,
            (UnitRoles and UnitRoles[%q]) or "none", count)
    ]], unit or "player"))
    return true
end

local function WaitForRoleMap(limit)
    return WaitUntil(function() return lastRoleMap end, limit)
end

--- What the restricted environment holds for a custom state: `{ present = bool, value = bool }`.
---
--- **`present` is the half that cannot be got any other way.** `States` carries a custom state only
--- once a rebuild has registered it, and a state that was never registered is indistinguishable
--- from an off one by its value alone -- which is exactly the pair that goes wrong: the window
--- reads the stored value, the restricted side reads nothing, and a press spends itself matching
--- them up.
---
--- Two booleans rather than the value, because the unregistered case would hand `CallMethod` a nil
--- and there is no `tostring` in the restricted environment to spell it with. `%1$q` twice for the
--- reason given at `MOCK_STATE_LINE`.
---
--- Asked of `States` rather than of `DebindPrivate.Switches`, because the stored table is the
--- source that was *supposed* to reach the restricted side; reading it back would only confirm that
--- the test wrote what the test wrote.
local function ReadSecureState(state)
    local answer
    DebindPrivate.BindingDriver.DebindTestSecureState = function(_, present, value)
        answer = { present = present, value = value }
    end

    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[
        self:CallMethod("DebindTestSecureState", States[%1$q] ~= nil, States[%1$q] == true)
    ]], state))

    return answer
end

--- Which unit an alias currently points at in the restricted environment, as
--- `{ present = bool, value = string }`. `value` is `""` when the alias holds nothing.
---
--- `UnitAliasMap` rather than `DebindPrivate.Units`, for the reason `ReadSecureState` reads
--- `States`: the insecure table is the mirror, and a mirror that kept a value the restricted side
--- had dropped would read as a pass.
local function ReadSecureUnit(alias)
    local answer
    DebindPrivate.BindingDriver.DebindTestSecureUnit = function(_, present, value)
        answer = { present = present, value = value }
    end

    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[
        self:CallMethod("DebindTestSecureUnit", UnitAliasMap[%1$q] ~= nil, UnitAliasMap[%1$q] or "")
    ]], alias))

    return answer
end

-----------------------------------------------------------
-- Test Helpers: Unit Frames
-----------------------------------------------------------

-- A unit frame the test owns, registered through the same path a real one takes. Owning it is
-- what makes the hover slot reachable at all: the frame is where `unit` is read from, both when
-- the cursor arrives and on every poll after, so a frame we can write to is a hover state we can
-- set. Nothing is faked -- the attribute read, the registration, and the reaction lookup are the
-- shipped ones.
--
-- **Frames are never destroyed in WoW**, so they are reused by name across runs. Teardown
-- unregisters rather than disposing.
local UNIT_TOKEN_ABSENT = "debindtest_absent"

local testFrameCount = 0

local function CreateTestUnitFrame(unit, frameType)
    testFrameCount = testFrameCount + 1

    local name = "DebindTestUnitFrame" .. testFrameCount
    local frame = _G[name] or CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")

    -- **Frames are reused by name, so everything a previous run did to one has to be undone
    -- here.** A test that showed this frame to be clicked left it parented into the window and
    -- sized to fill it; the next run's hover test would then drive a frame that is not where it
    -- thinks it is. That is not hypothetical -- it broke the hover test exactly once.
    frame:SetParent(UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    frame:SetSize(1, 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    frame:SetAttribute("unit", unit)
    frame:Show()

    DebindPrivate.RegisterFrame(frame, frameType or "group")

    AddTeardown(function()
        DebindPrivate.UnregisterFrame(frame)
        frame:Hide()
    end)

    -- `RegisterFrame` refuses quietly, and it records that refusal as `false` so the next attempt
    -- refuses too. Left unchecked the test would drive a frame the addon is not watching and
    -- report whatever the empty hover slot happened to say.
    local registered = DebindPrivate.ccframes[frame]
    if type(registered) ~= "table" then
        return nil, format("RegisterFrame did not take %s (ccframes=%s)", name, tostring(registered))
    end

    return frame
end

--- Points the frame at another unit. This is the whole simulation of "the unit under the cursor
--- changed": neither enter nor leave fires while the cursor sits still, and what the poll reads
--- is this attribute.
local function SetFrameUnit(frame, unit)
    frame:SetAttribute("unit", unit)
end

--- Drives the real `setup_onenter` / `setup_onleave` for a frame. The wrapped scripts run the
--- same snippets; there is no way to make the game fire OnEnter on demand, so the snippet is run
--- directly with the frame as `self`, which is exactly what the wrapper does.
local function HoverEnter(frame)
    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_hover", frame)
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        self:RunFor(self:GetFrameRef("debindtest_hover"), self:GetAttribute("setup_onenter"))
    ]])
end

local function HoverLeave(frame)
    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_hover", frame)
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        self:RunFor(self:GetFrameRef("debindtest_hover"), self:GetAttribute("setup_onleave"))
    ]])
end

--- What the restricted side currently calls the hovered unit.
---
--- **Asked of `UnitAliasMap` and not of `DebindPrivate.Units`**, which is what `ReadSecureUnit`
--- says about every other alias: the insecure table is a mirror, and a mirror that kept a value
--- the restricted side had dropped would read as a pass. This one was the odd reader out.
---
--- It has to be, now: hover is the one alias that is **not** mirrored out at all (2026-08-22).
--- `SetUnit` stopped reporting it, so `DebindPrivate.Units.hover` is nil whatever is hovered.
local function GetHoverUnit()
    local answer = ReadSecureUnit("hover")
    if not (answer and answer.present) then
        return nil
    end
    return answer.value
end

--- Waits for the hover slot to be filled (`true`) or emptied (`false`), as seen from outside.
---
--- **Which unit is deliberately not asked.** The test that follows one of these compares the unit
--- itself, and a wait that already agreed with it would be the assertion written twice -- the
--- wait would pass or time out on exactly what the comparison below is there to decide.
---
--- After `HoverEnter`/`HoverLeave` this costs nothing: those run the real snippets through
--- `SecureHandlerExecute` and the mirror is written before the call returns. It earns its keep
--- after `SetFrameUnit`, where nothing is driving anything and the change is only noticed when
--- Blizzard's state driver comes round -- up to `updatetime`, and never sooner.
local function WaitForHoverSlot(filled, limit)
    return WaitUntil(function() return (GetHoverUnit() ~= nil) == filled end, limit)
end

-----------------------------------------------------------
-- Test Cases: Renumbering a key group
--
-- `devdocs/legacy/renumbering-a-key-group.md`. **The rule and both of its ends are headless now**
-- (`tests/renumber_spec.lua`): the drawn order, and that the same numbers reach `BuildKeyMap` and
-- the solver. Two cases came down there on 2026-08-23 and this one did not follow them, for a
-- reason that has nothing to do with numbers.
--
-- **What is left is the door.** The arrows and the right-click menu both go through
-- `DebindUI.ApplyOrderSwap`, which redraws the list when it is done -- so it needs the window
-- standing, and the window is what the harness does not have.
-----------------------------------------------------------

--- The order `BuildKeyMap` ended up with, as a string of spell ids. Records the solver dropped
--- are not in it, which is the point of asking here rather than asking the drawing side.
local function KeyMapOrder(key)
    local bindings = GetKeyBindings(key)
    if not bindings then
        return "<none>"
    end
    local out = {}
    for i = 1, #bindings do
        out[i] = tostring(bindings[i].value)
    end
    return table.concat(out, " ")
end

RegisterTest("Renumber: the arrows' order reaches the solver", {
    description = "Swapping two records with the arrows lets the wider one cover the narrower, which then leaves KeyMap",
    run = function()
        local NAME = "Arrow order"
        local KEY = "CTRL-ALT-F1"

        -- **The window has to be open, because this test presses one of its buttons.**
        -- `ApplyOrderSwap` redraws the list when it is done, and the window builds itself on its
        -- first `OnShow` -- `OnLoad` is what reaches `LayerPanel` across to where `Refresh` looks
        -- for it. Nothing here is worth guarding against in `Refresh`: the arrows and the
        -- right-click menu both live on a row, so there is no way to reach it with the window shut.
        DebindFrame:Show()
        AddTeardown(function() DebindFrame:Hide() end)

        -- **The order is the only difference.** Both are conditional, at the same importance, in
        -- one layer, so they share a band and nothing but `seq` can split them. With the narrow one
        -- (combat+stealth) in front both survive; with the broad one (combat) in front the narrow
        -- one sits entirely inside it and leaves as UNREACHABLE. So what this measures is not "the
        -- numbers changed" but **that the numbers reached the solver**.
        local narrow = InsertAction({ type = Constants.SPELL, value = 116, key = KEY,
            combat = true, stealth = true })
        local broad = InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "116 585" then
            return Fail(NAME, format("the narrower one is in front: %s", KeyMapOrder(KEY)))
        end

        -- The function the arrow buttons and the right-click menu both go through. It swaps the two
        -- numbers and renumbers that group.
        DebindPrivate.DebindUI.ApplyOrderSwap(broad, narrow)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "585" then
            return Fail(NAME, format("the wider one is in front: %s", KeyMapOrder(KEY)))
        end

        -- **Swapping back, and watching it come alive again.** Without this the test also passes on
        -- a key that only ever held one record.
        DebindPrivate.DebindUI.ApplyOrderSwap(narrow, broad)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "116 585" then
            return Fail(NAME, format("it did not come back: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "116 585 -> 585 -> 116 585")
    end,
})
RegisterTest("Key group: the conflict popup's second answer runs", {
    description = "[Overwrite] on an occupied key really does take the key off the occupant",
    run = function()
        local NAME = "Conflict overwrite"
        local KEY = "CTRL-ALT-F7"

        -- The occupant, and the set that wants its key.
        local occupant = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        local mover = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F9", combat = true })
        ApplyBindings()

        -- **The dialog is opened by name, and answered by pressing its button.** Calling the
        -- handler directly would prove nothing: the defect this stands over was never in the
        -- handler but in whether the popup ever reaches it. `StaticPopup_OnClick` dispatches by
        -- index only when the dialog says to, and without that it sends every index but the first
        -- to `OnCancel` - so [overwrite] closed and did nothing at all.
        local dialog = StaticPopup_Show("DEBIND_KEY_GROUP_CONFLICT", nil, nil, {
            actions = { mover },
            key = KEY,
            occupants = { occupant },
            label = "test",
        })
        if not dialog then
            return Fail(NAME, "the dialog did not come up")
        end
        AddTeardown(function() StaticPopup_Hide("DEBIND_KEY_GROUP_CONFLICT") end)

        local button = dialog.GetButton and dialog:GetButton(2)
        if not button then
            return Fail(NAME, "could not get button 2, has the client's dialog shape changed")
        end
        button:Click()

        if occupant.key ~= nil then
            return Fail(NAME, format("the occupant is still holding the key: %s", tostring(occupant.key)))
        end
        if mover.key ~= KEY then
            return Fail(NAME, format("the one that moved did not get the key: %s", tostring(mover.key)))
        end
        return Pass(NAME, "the occupant stood aside and the group took the key")
    end,
})

-----------------------------------------------------------
-- Test Cases: what the pair costs, and what pays for it
--
-- An arrival keeps the key it was sent on and a badge holds it back, so the two things that used to
-- be impossible are now ordinary: **two groups on one key**, and **accepting putting a key live**.
-- Each is answered by a question the reader is asked, and a question is exactly the kind of thing
-- that can be wired up wrong in silence -- the popup opens, a button does nothing, and only someone
-- who pressed it finds out (section 12 of `devdocs/building-export-import.md`).
-----------------------------------------------------------

RegisterTest("Unbind: a set is not scattered without asking", {
    description = "[Unbind] on a group of several raises a confirmation, and only confirming scatters them",
    run = function()
        local NAME = "Unbind scatters"
        local KEY = "CTRL-ALT-F11"

        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        AddTeardown(function() StaticPopup_Hide("DEBIND_UNBIND_SCATTERS") end)

        DebindUI.UnbindActions({ first, second })

        -- **The gate comes first.** Nothing may be off its key while the question is still standing:
        -- that is the whole of what the box buys, and a call that acts and then asks would pass
        -- every check written about the popup itself.
        if first.key ~= KEY or second.key ~= KEY then
            return Fail(NAME, "the key was released before anything was asked")
        end
        local dialog = StaticPopup_FindVisible("DEBIND_UNBIND_SCATTERS")
        if not dialog then
            return Fail(NAME, "the confirmation did not come up")
        end

        local button = dialog.GetButton and dialog:GetButton(1)
        if not button then
            return Fail(NAME, "could not get button 1, has the client's dialog shape changed")
        end
        button:Click()

        if first.key ~= nil or second.key ~= nil then
            return Fail(NAME, format("confirmed and the key is still there: %s %s",
                tostring(first.key), tostring(second.key)))
        end
        return Pass(NAME, "asked first, then scattered")
    end,
})

RegisterTest("Unbind: one action is not asked about", {
    description = "[Unbind] on an action that is alone releases it outright, with nothing to confirm",
    run = function()
        local NAME = "Unbind single"
        local KEY = "CTRL-ALT-F12"

        -- **Alone, there is no set to lose.** A confirmation here would put a box in front of an
        -- ordinary move.
        local only = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        ApplyBindings()

        AddTeardown(function() StaticPopup_Hide("DEBIND_UNBIND_SCATTERS") end)

        DebindUI.UnbindActions({ only })

        if StaticPopup_FindVisible("DEBIND_UNBIND_SCATTERS") then
            return Fail(NAME, "only one of them and a confirmation came up")
        end
        if only.key ~= nil then
            return Fail(NAME, format("the key was not released: %s", tostring(only.key)))
        end
        return Pass(NAME, "released outright, nothing asked")
    end,
})

RegisterTest("Accept all: an occupied key is asked about, and all three answers run", {
    description = "An arrival on a key I use raises the confirmation, and each of its three answers really runs",
    run = function()
        local NAME = "Accept all occupied"
        local KEY = "CTRL-ALT-F5"
        local FREE = "CTRL-ALT-F3"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        --- Measuring all three answers in one place means standing the same board up again each
        --- time: one of mine, one arrival on the same key, and **one arrival on a key nobody
        --- uses**. That last one must not be pushed aside by any of the three answers, and it is
        --- the quietest place in this window to get wrong.
        ---
        --- **Both carry one condition, on different axes.** Different axes are what make the
        --- solver keep both, and **both being conditional** is what takes the comparator down as
        --- far as `seq`: `isConditional` is step 3 and `seq` is step 6 (`Ordering.lua`), so with
        --- only one of them conditional that one leads at the merge regardless of whether the
        --- arrival stands behind. Drop either condition and this test goes red against correct
        --- code.
        ---
        --- **The layer is emptied for every board.** The kit does not empty it between tests and
        --- this one reuses a single key three times, so without that the third board's order is
        --- measured over a heap that carries what the first two left behind, and the answer comes
        --- out as whatever the solver dropped for overlapping. Emptying once more at the end is
        --- the next test's business.
        AddTeardown(CleanupActions)

        local mine, arrived, free
        local function Setup(arrivalID)
            CleanupActions()
            mine = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, stealth = true })
            arrived = InsertAction({ type = Constants.SPELL, value = 2, key = KEY,
                arrivalID = arrivalID, combat = true })
            free = InsertAction({ type = Constants.SPELL, value = 3, key = FREE,
                arrivalID = arrivalID })
            ApplyBindings()
        end

        local function Answer(index, label)
            DebindFrame:ApproveAllImported()
            if arrived.arrivalID == nil then
                return format("[%s] the badge came off before anything was asked", label)
            end
            local dialog = StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED")
            if not dialog then
                return format("[%s] the confirmation did not come up", label)
            end
            local button = dialog.GetButton and dialog:GetButton(index)
            if not button then
                return format("[%s] could not get button %d, has the dialog shape changed", label, index)
            end
            button:Click()
            ApplyBindings()
            if free.key ~= FREE or free.arrivalID ~= nil then
                return format("[%s] the one on a key that does not clash was swept up: %s", label, tostring(free.key))
            end
            return nil
        end

        -- **The premise: while the badge is on, a real key on it still does not stand.** With that
        -- gone there is no telling what the three below measure.
        Setup(1)
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("the badged one is already standing: %s", KeyMapOrder(KEY)))
        end

        -- 1. [Keep Existing]. My key stays as it is and the arrival that clashed sits down with none.
        local err = Answer(1, "Keep Existing")
        if err then return Fail(NAME, err) end
        if mine.key ~= KEY then
            return Fail(NAME, format("[Keep Existing] and my key was released: %s", tostring(mine.key)))
        end
        if arrived.key ~= nil or arrived.arrivalID ~= nil or arrived.seq ~= nil then
            return Fail(NAME, format("the arrival that clashed did not sit down without a key: %s", tostring(arrived.key)))
        end
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("my key changed: %s", KeyMapOrder(KEY)))
        end

        -- 2. [Take Incoming]. The occupant loses the key and is not deleted.
        Setup(2)
        err = Answer(2, "Take Incoming")
        if err then return Fail(NAME, err) end
        if mine.key ~= nil then
            return Fail(NAME, format("[Take Incoming] and my key is still there: %s", tostring(mine.key)))
        end
        if arrived.key ~= KEY or arrived.arrivalID ~= nil then
            return Fail(NAME, "the arrival did not take the key, or the badge is still on")
        end

        -- 3. [Merge]. Both stay on the key and the arrival stands behind.
        Setup(3)
        err = Answer(3, "Merge")
        if err then return Fail(NAME, err) end
        if mine.key ~= KEY then
            return Fail(NAME, format("[Merge] and my key was released: %s", tostring(mine.key)))
        end
        if KeyMapOrder(KEY) ~= "1 2" then
            return Fail(NAME, format("not the merge order: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "asked, all three answers ran, and the key that does not clash was untouched in all three")
    end,










})

RegisterTest("Accept all: a free key is not asked about", {
    description = "An arrival on a key I do not use lands outright, with nothing to confirm",
    run = function()
        local NAME = "Accept all free"
        local KEY = "CTRL-ALT-F6"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        -- **This is the common case.** A box here turns the badge from a safeguard into homework.
        local arrived = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, arrivalID = 1 })
        ApplyBindings()

        DebindFrame:ApproveAllImported()

        if StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED") then
            return Fail(NAME, "a free key and a confirmation came up")
        end
        if arrived.arrivalID ~= nil then
            return Fail(NAME, "the badge did not come off")
        end
        ApplyBindings()
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("accepted and it is not standing: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "stood outright, nothing asked")
    end,
})

-----------------------------------------------------------
-- Test Cases: The heading's right-click menu
--
-- One right-click passes through three pieces: the template's `registerForClicks`, the right-hand
-- branch of `OnClick`, and the `rows` the left column loads onto the heading's elementData.
-- **Any one of them missing and nothing happens at all**: no error either, and only someone who
-- pressed it finds out. All three exist only inside the game, so this layer is the only place they
-- can be looked at.
-----------------------------------------------------------

RegisterTest("Key group: the heading's right-click arms the whole group", {
    description = "The entry on the heading's right-click menu opens a capture window carrying the whole group",
    run = function()
        local NAME = "Key group heading menu"
        local KEY = "CTRL-ALT-F8"

        -- **Two, and two split by a condition.** One on its own cannot measure "the whole group":
        -- it passes even where what was aimed at is a single row.
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        -- **The elementData on the heading is the thing the left column built.** Built by hand
        -- here, this test would pass on the day `rows` stopped being loaded, and that field is how
        -- the menu finds the group. The window is not shown: the data is built with no frame at all.
        DebindResultPanel:RefreshKeyboard()

        local elementData
        for _, data in DebindResultPanel.ContentArea.OrderArea.ScrollBox:GetDataProvider():Enumerate() do
            if data.isHeader and data.key == KEY then
                elementData = data
            end
        end
        if not elementData then
            return Fail(NAME, format("no heading for %s in the left column, is a search term or filter on", KEY))
        end

        local header = CreateFrame("Button", nil, UIParent, "DebindKeyHeaderTemplate")
        header:SetPoint("CENTER")
        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
            header:Hide()
            header:SetParent(nil)
        end)
        header:Init(elementData)

        -- **Opened by pressing.** Calling `OpenKeyGroupMenu` outright measures that function
        -- alone and passes without ever measuring whether a right-click reaches it, which is why
        -- the dialog tests above press the button itself.
        --
        -- **One thing this cannot measure:** whether `registerForClicks` really takes a
        -- right-click. `Click()` can call the handler regardless of what is registered, and there
        -- is no API that reads the registration back.
        header:Click("RightButton")

        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "the right-click brought up no menu")
        end

        -- **Found by its wording.** For a while it was found as "the only thing selectable", which
        -- was a shortcut from the days of a single entry and went red the moment [Unbind] joined
        -- it. What this measures is what the entry aims at, not how **many** entries there are,
        -- and it was tied to the count.
        --
        -- The question is now the same one the row test asks, so it is found the same way.
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["KEY_HEADER_SET_KEY"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("no [%s] entry", LLL["KEY_HEADER_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        -- Is what the window aims at the whole group? Carrying only one, the key that gets pressed
        -- reaches a single action.
        local armed = DebindKeyCaptureFrame.actions or {}
        local seen = {}
        for _, action in ipairs(armed) do
            seen[action] = true
        end
        if #armed ~= 2 or not seen[first] or not seen[second] then
            return Fail(NAME, format("what it aims at is not the group: %d", #armed))
        end

        return Pass(NAME, format("right-click -> menu -> %d in the capture window", #armed))
    end,
})

--- The entry that opens the same window stands on a row too, and **there it must carry that row
--- alone**. It reads the same as the heading's (both say [Assign a key]), so the eye cannot tell
--- them apart, and getting it wrong is quiet: the window opens and takes a key either way.
---
--- **What this does not measure:** whether a right-click reaches the menu. The test above measures
--- that, and measuring it here would need a row frame that came out of the scroll box
--- (`DebindOrderLineMixin` reads `GetElementData`, so a hand-made frame cannot open it). So the
--- menu generator runs on a real menu frame and the click is skipped.
RegisterTest("Assign a key: a row's item takes that row alone", {
    description = "[Assign a key] on an overview row's menu opens a capture window carrying that row alone",
    run = function()
        local NAME = "Row assign key"
        local KEY = "CTRL-ALT-F9"

        -- **Two on one key.** Whether only one is carried is the whole of this test, so there has
        -- to be something beside it to measure against.
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupOrderDropdownMenu, first)
        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "the menu did not come up")
        end

        -- Found by its wording here. This menu has several selectable entries (the two ordering
        -- ones), so it cannot be found as "the only one" the way the heading's is.
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["ACTION_SET_KEY"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("no [%s] entry", LLL["ACTION_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        if #armed ~= 1 or armed[1] ~= first then
            return Fail(NAME, format("what it aims at is not this row alone: %d", #armed))
        end

        return Pass(NAME, "one row alone was carried")
    end,
})

--- **The same item, on a row that has not been accepted yet.** It was deliberately withheld there
--- for a while, so a later reading of that reasoning can take it out again and nothing on screen
--- says so: the menu opens, the other two items are there, and only someone who came to give this
--- row a key finds out.
---
--- **This does not measure what happens after the press.** Giving the key accepts the row, and that
--- is `SetKeyForActions`' own rule with its own coverage. What is measured here is that the item
--- stands and that it aims at this row alone.
RegisterTest("Assign a key: a badged row is offered one too", {
    description = "A row not yet accepted is offered [Assign a key] too, and carries that row alone",
    run = function()
        local NAME = "Imported row assign key"

        -- **An arrival carrying a key.** The real key and the badge come as a pair: an arrival
        -- brings the sender's key exactly as it was, and the one thing holding it back is the badge.
        local action = InsertAction({
            type = Constants.SPELL,
            value = 1,
            key = "SHIFT-Q",
            arrivalID = 1,
        })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupOrderDropdownMenu, action)
        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "the menu did not come up")
        end

        -- **The badged row's own label**, which is the plain one with the other half spelled out:
        -- giving an arrival a key accepts it, and the item says so before it is pressed
        -- (`ACTION_SET_KEY_ACCEPT`). Looking for the plain words here would pass on a row that had
        -- lost its badge somewhere earlier in the run.
        local wanted = LLL["ACTION_SET_KEY_ACCEPT"]
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == wanted then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("no [%s] entry", wanted))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        if #armed ~= 1 or armed[1] ~= action then
            return Fail(NAME, format("what it aims at is not this row alone: %d", #armed))
        end

        return Pass(NAME, "the entry stands on a badged row too, and carried that row alone")
    end,
})

--- **Both answers in that window are the reader deciding the key** (2026-08-23, the owner), and
--- deciding the key is what accepting an arrival is (`DebindFrameMixin:SetActionKey`). The item that
--- opened it says so on its face, so pressing the button on the window it opened has to keep the
--- promise: [Unbind Key] used to leave the arrival with no key **and** still waiting, which is
--- neither half of what the label said.
---
--- The menu's own [Unbind] is not this and does not accept - it is aimed at a row rather than opened
--- over a question, and one function serves both, so nothing but the flag tells them apart.
RegisterTest("Assign a key: unbinding from that window accepts too", {
    description = "[Unbind] in a window opened by [Assign a key & Accept] still accepts",
    run = function()
        local NAME = "Imported row unbind accepts"

        local action = InsertAction({
            type = Constants.SPELL,
            value = 1,
            key = "SHIFT-Q",
            arrivalID = 1,
        })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        DebindUI.BeginKeyCapture({ action })
        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "the capture window did not come up")
        end
        if not DebindKeyCaptureFrame.UnbindButton:IsEnabled() then
            return Fail(NAME, "it came carrying a real key and [Unbind] is dark")
        end

        -- Exactly what that button does: it hands the answer over as nil.
        DebindKeyCaptureFrame:Commit(nil)

        if action.key ~= nil then
            return Fail(NAME, format("the key did not come off: %s", tostring(action.key)))
        end
        if action.arrivalID ~= nil then
            return Fail(NAME, format("it was not accepted, the badge is still %s",
                tostring(action.arrivalID)))
        end

        return Pass(NAME, "the key came off and the badge came off with it")
    end,
})

--- The fourth way into the same window, and the one with no heading behind it: several rows the
--- reader ticked, which may sit on different keys or on none.
---
--- **Two things are measured and the second is the one that bites.** That the item stands, and that
--- [Unbind] beside it goes dead when nothing in the selection holds a key at all. Lit over rows that
--- are all keyless it offers to take off a key none of them has, and pressing it does nothing.
RegisterTest("Bulk menu: the key pair aims at the whole selection", {
    description = "[Assign a key] on a multiple selection opens a window carrying all of it, and [Unbind] goes dark when nothing picked has a key",
    run = function()
        local NAME = "Bulk key items"
        local KEY = "CTRL-ALT-F10"

        -- **Two on keys of their own.** A key group cannot produce this state, and whether the bulk
        -- path carries it as far as the window is half of this test.
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = "CTRL-ALT-F11" })
        ApplyBindings()

        AddTeardown(function()
            Menu.GetManager():CloseMenus()
            DebindKeyCaptureFrame:Hide()
        end)

        local function OpenBulkMenu(actions)
            Menu.GetManager():CloseMenus()
            MenuUtil.CreateContextMenu(UIParent, DebindUI.SetupBulkDropdownMenu, actions)
            return Menu.GetManager():GetOpenMenu()
        end

        local function FindItem(menu, text)
            local found
            menu:EnumerateElementDescriptions(function(_, description)
                if MenuUtil.GetElementText(description) == text then
                    found = description
                end
            end)
            return found
        end

        local menu = OpenBulkMenu({ first, second })
        if not menu then
            return Fail(NAME, "the menu did not come up")
        end

        local unbind = FindItem(menu, LLL["UNBIND"])
        if not unbind or not unbind:IsEnabled() then
            return Fail(NAME, "a selection holding a real key and [Unbind] is dark")
        end

        local item = FindItem(menu, LLL["ACTION_SET_KEY"])
        if not item then
            return Fail(NAME, format("no [%s] entry", LLL["ACTION_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "pressed the entry and no capture window came up")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        local seen = {}
        for _, action in ipairs(armed) do
            seen[action] = true
        end
        if #armed ~= 2 or not seen[first] or not seen[second] then
            return Fail(NAME, format("not everything picked was carried: %d", #armed))
        end
        DebindKeyCaptureFrame:Hide()

        -- **A selection holding only things with no key at all.** [Unbind] alive here says a key
        -- can be taken off where there is none to take, and pressing it does nothing.
        local keyless = InsertAction({
            type = Constants.SPELL,
            value = 3,
        })
        ApplyBindings()

        menu = OpenBulkMenu({ keyless })
        if not menu then
            return Fail(NAME, "the second menu did not come up")
        end
        unbind = FindItem(menu, LLL["UNBIND"])
        if not unbind then
            return Fail(NAME, format("no [%s] entry", LLL["UNBIND"]))
        end
        if unbind:IsEnabled() then
            return Fail(NAME, "nothing picked has a key and [Unbind] is lit")
        end

        return Pass(NAME, "both picked were carried into the window, and [Unbind] went dark where nothing picked had a key")
    end,
})

--- The mode's own way in. **Four things have to line up for one press, and three of them are silent
--- when they do not**: the widget key the frame reaches for (`BindModePortrait` -- a wrong one is a
--- nil index, but only when someone presses it), the XML `OnClick`, the keyboard being switched on
--- at that button (without it the mode is on and nothing hears a key), and the lit ring that is the
--- only thing on screen saying selecting and the menu have stopped.
---
--- All four moved on the same day the toggle became a portrait: it used to be a labelled button
--- above the left column, wearing a square silver texture and carrying its state in its text.
---
--- **This does not measure what `RegisterForClicks` receives.** `Click()` reaches `OnClick`
--- whatever the registration says (the same limit the key group popup test writes down).
RegisterTest("Bind mode: the portrait toggle turns the mode on and off", {
    description = "The toggle on the portrait row turns the mode on, and the keyboard and the lit state follow",
    run = function()
        local NAME = "Bind mode toggle"

        -- The window has to be up. The portrait builds itself on its first `OnShow`
        -- (`DebindPortraitMixin`), and before that neither the tooltip fields nor the textures are on it.
        DebindFrame:Show()
        AddTeardown(function()
            DebindFrame:SetBindingMode(false)
            DebindFrame:Hide()
        end)

        local toggle = DebindFrame.OverviewPanel.BindModePortrait
        if not toggle then
            return Fail(NAME, "no BindModePortrait, has the parentKey in the XML changed")
        end
        if DebindFrame:IsCapturingKey() then
            return Fail(NAME, "the mode was on from the start")
        end

        toggle:Click()

        if not DebindFrame:IsCapturingKey() then
            return Fail(NAME, "pressed it and the mode did not come on")
        end
        if not toggle:IsKeyboardEnabled() then
            return Fail(NAME, "the mode is on and this button is not listening to the keyboard")
        end
        -- The lit state is the border (`SetSelectedState`): the colour comes back and the dark plate
        -- over it goes down.
        if toggle.Frame:IsDesaturated() or toggle.UnselectedFrame:IsShown() then
            return Fail(NAME, "it is on and the border is still in its dark shape")
        end
        if toggle.TooltipTitle ~= LLL["BIND_MODE_STOP"] then
            return Fail(NAME, format("the tooltip title did not change: %s", tostring(toggle.TooltipTitle)))
        end

        toggle:Click()

        if DebindFrame:IsCapturingKey() then
            return Fail(NAME, "pressed again and the mode did not go off")
        end
        if toggle:IsKeyboardEnabled() then
            return Fail(NAME, "the mode is off and it is still listening to the keyboard")
        end
        if not toggle.Frame:IsDesaturated() or not toggle.UnselectedFrame:IsShown() then
            return Fail(NAME, "it is off and the lit state is still on it")
        end
        if toggle.TooltipTitle ~= LLL["BIND_MODE"] or toggle.TooltipText ~= LLL["BIND_MODE_DESC"] then
            return Fail(NAME, format("the tooltip did not come back: %s / %s",
                tostring(toggle.TooltipTitle), tostring(toggle.TooltipText)))
        end

        return Pass(NAME, "one toggle moved the mode, the keyboard, the border and the tooltip together")
    end,
})

-----------------------------------------------------------
-- Test Cases: The macro editor commits by closing and by nothing else
--
-- **The one rule this window has**, and the only layer that can see it: the body reaches the
-- profile when the window hides, from every path that hides it, and no path writes it while the
-- window is up. Everything else here hangs off that -- [Cancel] can promise to put the body back
-- only because nothing moved it, and there is no [Save] because a button saying so would describe
-- the opposite of what happens.
--
-- Nothing below reads the field it is about to assert on. What it checks is `action.value`, which
-- is what the profile keeps and what the next build reads.
-----------------------------------------------------------

--- What is drawn over what. These two are all the game answers with, so the order is measured with
--- them: what `toplevel` does in the end is raise the second of them within one layer.
local STRATA_RANK = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local function DrawsAbove(a, b)
    local ra = STRATA_RANK[a:GetFrameStrata()]
    local rb = STRATA_RANK[b:GetFrameStrata()]
    if ra ~= rb then
        return ra > rb
    end
    return a:GetFrameLevel() > b:GetFrameLevel()
end

--- Puts text into an edit box. **`SetText` alone does not run `OnTextChanged`.** That script, which
--- does run when a person types, is what turns [Cancel] on and off in this window and what sets the
--- search term in the search box, so skipping it makes everything measured here a different act
--- from the one a person performs.
---
--- **A missing script comes back as a failure.** Skipped quietly, these tests would go green on the
--- day the wiring fell out of the XML.
local function TypeInto(editBox, text)
    editBox:SetText(text)
    local script = editBox:GetScript("OnTextChanged")
    if not script then
        return false
    end
    script(editBox, true)
    return true
end

--- Shows the window, plants one macrotext action and opens the editor on it. Putting things back is
--- the runner's job.
---
--- **An icon goes in.** An action with no icon is a shape this addon cannot make ([New Custom
--- Macro] goes through the icon selector), and on one of those the name/icon popup opens blank.
local function OpenMacroEditor(body, cancelFunc)
    DebindFrame:Show()
    AddTeardown(function()
        DebindIconSelectorFrame:Hide()
        DebindMacroFrame:Hide()
        DebindFrame:Hide()
    end)

    local action = InsertAction({ type = Constants.MACROTEXT, value = body,
        name = "Macro editor test", icon = 134400, key = "CTRL-ALT-F11" })
    ApplyBindings()

    DebindMacroFrame:Open(action, cancelFunc)
    return action, DebindMacroFrame.Editor.ScrollFrame.EditBox
end

--- **What this test protects is edit mode, not the icon list.**
---
--- Blizzard's `IconDataProvider` has the file-local `BaseIconFilenames` **built by whoever uses it
--- first and released by whoever puts it down last.** Stepping into that place makes Debind the
--- owner of that variable, and edit mode reads its value on the way in to pull a sample aura icon
--- (`GetSampleAuraIcon` -> `GetNumIcons` in `EditModeAuraDataProvider.lua`). That single read taints
--- the whole execution that enters edit mode, and the same execution goes on to update the party
--- health bars and is stopped at a secret comparison. In a session that had opened the name/icon
--- window once, the party health bars died every time edit mode was entered.
---
--- **That symptom is not something even an in-game test can measure**: taint is invisible from Lua,
--- and a test cannot press its way into edit mode. So what is measured is the **structure** that
--- produces the cause. It fails if our provider is Blizzard's own.
RegisterTest("Icon picker: the icon list is ours, not Blizzard's shared one", {
    description = "We neither create nor release Blizzard's shared IconDataProvider",
    run = function()
        local NAME = "Icon provider"

        DebindFrame:Show()
        AddTeardown(function()
            DebindIconSelectorFrame:Hide()
            DebindFrame:Hide()
        end)

        local provider = DebindFrame:RefreshIconDataProvider()
        if not provider then
            return Fail(NAME, "no provider")
        end

        -- Both the side that builds the list and the side that releases it have to be ours.
        if provider.GetNumIcons == IconDataProviderMixin.GetNumIcons then
            return Fail(NAME, "GetNumIcons is Blizzard's, it reads the shared BaseIconFilenames")
        end
        if provider.Release == IconDataProviderMixin.Release then
            return Fail(NAME, "Release is Blizzard's, it releases the shared BaseIconFilenames")
        end

        -- And the list still has to stand: one question mark, the spell book, and the base list.
        local numIcons = provider:GetNumIcons()
        if numIcons < 2 then
            return Fail(NAME, format("only %d icons, the list was never filled", numIcons))
        end

        local questionMark = provider:GetIconByIndex(1)
        if questionMark ~= [[INTERFACE\ICONS\INV_MISC_QUESTIONMARK]] then
            return Fail(NAME, format("slot 1 is not the question mark: %s", tostring(questionMark)))
        end

        -- A real icon has to come back for every slot including the last. Set the boundary wrong and
        -- this is where nil appears.
        local last = provider:GetIconByIndex(numIcons)
        if last == nil then
            return Fail(NAME, format("the last slot (%d) is empty, the per-type list boundary is out of step", numIcons))
        end

        -- Getting it back. The same icon can appear more than once, so this compares icons rather
        -- than indices.
        local found = provider:GetIndexOfIcon(last)
        if not found or provider:GetIconByIndex(found) ~= last then
            return Fail(NAME, format("GetIndexOfIcon cannot find %s", tostring(last)))
        end

        return Pass(NAME, format("our provider, %d icons", numIcons))
    end,
})

RegisterTest("Macro editor: the body reaches the profile when the window closes", {
    description = "Closing is what saves; a trip through the name/icon popup does not",
    run = function()
        local NAME = "Macro commit"

        local action, box = OpenMacroEditor("/say one")
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "it did not open")
        end
        if box:GetText() ~= "/say one" then
            return Fail(NAME, format("the body did not come up: %q", box:GetText()))
        end

        if not TypeInto(box, "/say two") then
            return Fail(NAME, "the edit box has no OnTextChanged on it")
        end
        if action.value ~= "/say one" then
            return Fail(NAME, "it saved while typing, the profile moved with the window still open")
        end

        -- A trip out to the name/icon editor and back. The default macro window saves at this point
        -- and we do not: saving would push the place [Cancel] returns to along, over an outing that
        -- never touched the body.
        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the name/icon popup did not open")
        end
        if action.value ~= "/say one" then
            return Fail(NAME, format("opening the popup saved: %q", action.value))
        end

        DebindIconSelectorFrame:Close(true)
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "the popup closing took the editor with it")
        end
        if box:GetText() ~= "/say two" then
            return Fail(NAME, format("the body changed while we were away: %q", box:GetText()))
        end

        -- [Close]. This button does nothing but close the window, and the closing is what saves.
        DebindMacroFrame.Editor.CloseButton:Click()
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "pressed [Close] and it did not close")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("it closed and nothing was saved: %q", action.value))
        end

        return Pass(NAME, "the trip to the popup wrote nothing, the closing wrote")
    end,
})

RegisterTest("Macro editor: [Cancel] lights up only when there is something to put back", {
    description = "Dark while nothing has been edited, and pressing it restores the box alone without moving the profile",
    run = function()
        local NAME = "Macro cancel"

        local action, box = OpenMacroEditor("/say one")
        local button = DebindMacroFrame.Editor.RevertButton

        if button:IsEnabled() then
            return Fail(NAME, "just opened and it says there is something to put back")
        end
        if button:GetText() ~= CANCEL then
            return Fail(NAME, format("the label is not [Cancel]: %q", tostring(button:GetText())))
        end

        if not TypeInto(box, "/say two") then
            return Fail(NAME, "the edit box has no OnTextChanged on it")
        end
        if not button:IsEnabled() then
            return Fail(NAME, "the body was edited and the button is dark")
        end

        button:Click()

        if box:GetText() ~= "/say one" then
            return Fail(NAME, format("the edit box did not come back: %q", box:GetText()))
        end
        if action.value ~= "/say one" then
            return Fail(NAME, format("the profile moved: %q", action.value))
        end
        if button:IsEnabled() then
            return Fail(NAME, "the button is still lit after putting it back")
        end
        -- **It does not close.** The reverted body has to be there to be edited again.
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "[Cancel] closed the window too")
        end

        return Pass(NAME, "dark -> lit -> put back and dark again")
    end,
})

RegisterTest("Macro editor: [Revert] gives the conversion its action back", {
    description = "Opened by a conversion, the label reads REVERT and pressing it runs the function that undoes it",
    run = function()
        local NAME = "Macro revert"

        local reverted = false
        local action, box = OpenMacroEditor("/cast Fireball", function() reverted = true end)
        local button = DebindMacroFrame.Editor.RevertButton

        if button:GetText() ~= REVERT then
            return Fail(NAME, format("the label is not REVERT: %q", tostring(button:GetText())))
        end
        -- What there is to revert is a conversion that already happened, so it has to be lit even
        -- with nothing typed.
        if not button:IsEnabled() then
            return Fail(NAME, "opened by a conversion and the button is dark")
        end
        if not DebindMacroFrame.macroCancelFunc then
            return Fail(NAME, "no cancelFunc on it, did Refresh clear it with nobody putting it back")
        end

        TypeInto(box, "/cast Frostbolt")
        button:Click()

        if not reverted then
            return Fail(NAME, "pressed it and the function that puts it back never ran")
        end
        -- The body just thrown away must not be saved back over the reverted action.
        if action.value ~= "/cast Fireball" then
            return Fail(NAME, format("the body that was thrown away got saved: %q", action.value))
        end

        return Pass(NAME, "REVERT stood, pressing it put things back, and the body did not leak")
    end,
})

RegisterTest("Macro editor: ESC steps out of the popup, then the editor, then the window", {
    description = "One ESC steps back one place, and the ESC that closes the editor leaves the body behind",
    run = function()
        local NAME = "Macro escape"

        local action, box = OpenMacroEditor("/say one")

        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the name/icon popup did not open")
        end

        DebindFrame:HandleEscape()
        if DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the first ESC did not close the popup")
        end
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "the first ESC took the editor with it")
        end

        TypeInto(box, "/say two")
        DebindFrame:HandleEscape()
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "the second ESC did not close the editor")
        end
        if not DebindFrame:IsShown() then
            return Fail(NAME, "the second ESC closed the main window too, is this rung missing from the ladder")
        end
        -- Closing is what saves. Leaving by ESC still leaves the body behind.
        if action.value ~= "/say two" then
            return Fail(NAME, format("closed by ESC and the body was not kept: %q", action.value))
        end

        DebindFrame:HandleEscape()
        if DebindFrame:IsShown() then
            return Fail(NAME, "the third ESC did not close the main window")
        end

        return Pass(NAME, "popup -> editor -> main window, and the body was kept")
    end,
})

RegisterTest("Macro editor: the name/icon popup stays over the editor", {
    description = "Raising the editor to the front does not put the popup above it behind",
    run = function()
        local NAME = "Macro popup order"

        OpenMacroEditor("/say one")
        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the name/icon popup did not open")
        end

        local function Where()
            return format("%s/%d vs %s/%d",
                DebindIconSelectorFrame:GetFrameStrata(), DebindIconSelectorFrame:GetFrameLevel(),
                DebindMacroFrame:GetFrameStrata(), DebindMacroFrame:GetFrameLevel())
        end

        if not DrawsAbove(DebindIconSelectorFrame, DebindMacroFrame) then
            return Fail(NAME, format("it is underneath as soon as it opens: %s", Where()))
        end

        -- What happens when the editor is clicked. With the two on one layer, this single line is
        -- what turns the order around.
        DebindMacroFrame:Raise()

        if not DrawsAbove(DebindIconSelectorFrame, DebindMacroFrame) then
            return Fail(NAME, format("raising the editor put the popup behind: %s", Where()))
        end

        return Pass(NAME, Where())
    end,
})

RegisterTest("Macro editor: a row filtered out of the bin takes its editor with it", {
    description = "A row filtered out by the search closes its editor, and the body is saved",
    run = function()
        local NAME = "Macro filtered out"

        local action, box = OpenMacroEditor("/say one")
        local searchBox = DebindFrame.OverviewPanel.SearchBox
        -- The script runs here too. Without it, a search term survives the day this fails partway
        -- through and every test after it looks into an empty bin.
        AddTeardown(function() TypeInto(searchBox, "") end)

        TypeInto(box, "/say two")

        -- Text that cannot collide with this action's name. The search filters on the name.
        if not TypeInto(searchBox, "qqzzxx") then
            return Fail(NAME, "the search box has no OnTextChanged on it")
        end

        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "the row was filtered out and the editor is still there")
        end
        if not DebindFrame:IsShown() then
            return Fail(NAME, "the main window closed too")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("it closed and nothing was saved: %q", action.value))
        end

        -- Clearing the search brings the row back. It does not bring the editor back: opening that
        -- is the user's move.
        TypeInto(searchBox, "")
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "clearing the search opened the editor again on its own")
        end

        return Pass(NAME, "closed as it was filtered out, the body was saved, and it did not come back on its own")
    end,
})

RegisterTest("Macro editor: opening the spell picker closes it", {
    description = "The spell picker opening closes the editor and popup that would sit under it first",
    run = function()
        local NAME = "Macro picker"

        local action, box = OpenMacroEditor("/say one")
        AddTeardown(function() DebindSpellPickerFrame:Hide() end)

        DebindMacroFrame:EditNameIcon_OnClick()
        TypeInto(box, "/say two")

        DebindSpellPickerFrame:Show()

        if DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "the name/icon popup is still there")
        end
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "the editor is still there, the spell picker sits on top of it")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("it closed and nothing was saved: %q", action.value))
        end

        return Pass(NAME, "both closed and the body was kept")
    end,
})

-----------------------------------------------------------
-- Test Cases: The storage tab counts what actually leaves
--
-- **This is the one the headless specs cannot reach.** They check the payload, and separately the
-- panel's list is built by code that never runs outside the game. What can go wrong is the two
-- disagreeing - the panel says "12 selected" and nine leave - and neither half is wrong on its
-- own, so only asking both at once finds it.
--
-- Nothing here reads a field to decide what it expects: the string is decoded the way any receiver
-- would decode it, and the count in it is set against the count the window drew.
-----------------------------------------------------------

--- The payload inside an exported string, undone the way the far side undoes it. LibStub is global
--- and the two libraries register with it, so this needs nothing private.
local function DecodeExportedString(str)
    local body = type(str) == "string" and str:match("^DEB1:(.+)$")
    if not body then
        return nil, format("not an envelope: %s", tostring(str and str:sub(1, 12)))
    end

    local LibSerialize, LibDeflate = LibStub("LibSerialize", true), LibStub("LibDeflate", true)
    if not LibSerialize or not LibDeflate then
        return nil, "no library"
    end

    local compressed = LibDeflate:DecodeForPrint(body)
    local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return nil, "cannot decompress"
    end

    local ok, payload = LibSerialize:Deserialize(serialized)
    if not ok or type(payload) ~= "table" then
        return nil, "deserialisation failed"
    end
    return payload
end

--- Every action in a payload, whatever layer it sits under. The nesting is the address, so this is
--- the walk a reader makes (`devdocs/building-export-import.md`).
local function PayloadActions(payload)
    local out = {}
    local function Take(list)
        for _, action in ipairs(list or {}) do
            out[#out + 1] = action
        end
    end
    local function TakeSpecTable(specTbl)
        for _, list in pairs(specTbl or {}) do
            Take(list)
        end
    end

    Take(payload.shared and payload.shared.GENERAL)
    for _, classTbl in pairs(payload.shared and payload.shared.classes or {}) do
        TakeSpecTable(classTbl)
    end
    TakeSpecTable(payload.char)
    return out
end

--- The storage tab's seat in `PANELS` (`DebindUI.lua`). That table is a local over there, so this
--- is the one thing here that has to be kept in step by hand -- the guard below is what says so out
--- loud rather than quietly measuring the wrong panel.
local STORAGE_PANEL_ID = 3

--- **Three numbers, and they have to agree.** What the preview counts, what the string carries, and
--- what adding it back would put in the profile. The tick set feeds all three (`FilterPayload`,
--- `PlanArrival`), so a filter read in one place and not another is silent everywhere else: the
--- window says 12, the string carries 9, and nobody sees the difference until somebody else opens
--- it (section 12 of `devdocs/building-export-import.md`).
RegisterTest("Storage: the preview, the string and the add all count the same", {
    description = "What the preview counts, what the string carries and what Add places are one number, and the badge is left out",
    run = function()
        local NAME = "Export counts"

        -- Two the tester owns and one still quarantined. A key with both on it is the sharpest
        -- case: the group goes out half, which is right, and a filter that worked per key rather
        -- than per action would send three or one.
        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F5", combat = true })
        InsertAction({ type = Constants.SPELL, value = 589, key = "CTRL-ALT-F5" })
        local badged = InsertAction({ type = Constants.SPELL, value = 6603, key = "CTRL-ALT-F6" })
        badged.arrivalID = 99
        ApplyBindings()

        -- **The panel is fetched, not opened.** `ResolvePanel` is what the tab calls to bring
        -- `DebindStorage` in, and stopping there is enough: nothing below needs a frame on screen.
        --
        -- The run's own layer has an id past every real one (`GetTestLayer`), and that used to be a
        -- reason not to build the list at all. It is not one any more: the preview names a layer by
        -- the **payload's address** rather than by that id, and `BuildExportPayload` files a layer
        -- with no character flag and no spec under the class block -- an address every client has.
        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        -- **The entry is real and it stays until teardown.** Making one is the only way into the
        -- list, and a row the runner leaves behind is a row the tester finds later - so it goes,
        -- along with the panel's own view state, which `OnHide` would normally clear and cannot on
        -- a panel that was never shown.
        --
        -- The copy dialog goes too: it takes keyboard focus when it opens, which is what it is for,
        -- and it must not hold it over whatever runs next.
        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            DebindCopyFrame.Output.EditBox:ClearFocus()
            DebindCopyFrame:Hide()
            panel:SelectEntry(nil)
            DebindPrivate.Store.DeleteEntry(entry.id)
        end)

        -- What `OnShow` does: pick the row, which builds the preview and ticks all of it.
        panel:SelectEntry(entry)

        -- What the window says, counted twice the way the window counts it: the [select all] total
        -- walks every listed action, and each header prints its own layer's length.
        local listed = panel:EnumerateListedActions()
        local headerTotal = 0
        for _, layer in ipairs(panel.previewLayers or {}) do
            headerTotal = headerTotal + #layer.actions
        end
        if headerTotal ~= #listed then
            return Fail(NAME, format("headings total %d, whole list %d", headerTotal, #listed))
        end

        for _, action in ipairs(listed) do
            if action == badged then
                return Fail(NAME, "an isolated action is in the list")
            end
        end

        -- And what leaves. `OnCopyClicked` is the button, and the box it fills is the one the
        -- reader copies out of. **The dialog keeps no copy of the string beside that box**, so the
        -- box is the only place to read it from (`ShowText`).
        panel:OnCopyClicked()
        local payload, why = DecodeExportedString(DebindCopyFrame.Output.EditBox:GetText())
        if not payload then
            return Fail(NAME, format("could not read the string: %s", why))
        end

        local sent = PayloadActions(payload)
        if #sent ~= #listed then
            return Fail(NAME, format("the window said %d and it sent %d", #listed, #sent))
        end
        for _, action in ipairs(sent) do
            if action.value == badged.value then
                return Fail(NAME, "an isolated action was carried into the string")
            end
        end

        -- **The third number.** Adding puts the same set into the profile and gets there through
        -- `PlanArrival` rather than through the string, so this is what catches a tick set one of the
        -- two reads and the other does not. Planned rather than placed: the count is what is being
        -- asked, and placing would leave the run's layer holding a second copy of everything.
        --
        -- **The entry's own payload, not the one decoded above.** A tick is the action table
        -- itself, so a payload built by decoding holds a second set of tables that nothing has
        -- ticked, and planning against it places nothing. `OnAddClicked` reaches `PlanArrival`
        -- through `CommitEntry`, which opens the entry the same way the preview did
        -- (`GetEntryPayload`).
        local stored = DebindPrivate.Store.GetEntryPayload(entry)
        if not stored then
            return Fail(NAME, "could not open the entry payload")
        end

        local planned, skipped = DebindPrivate.Store.PlanArrival(stored, { selection = panel.selected })
        if #planned ~= #listed then
            return Fail(NAME, format("the window said %d and it places %d", #listed, #planned))
        end
        if skipped ~= 0 then
            return Fail(NAME, format("%d came back with nowhere to go, those are addresses this board made", skipped))
        end

        return Pass(NAME, format("%d = %d = %d, and the badge did not go out", #listed, #sent, #planned))
    end,
})

--- **The two verbs grey out, they do not leave** (2026-08-23, the owner). A control that disappears
--- takes with it the answer to "what can I do here", and the screen where nothing is picked is
--- exactly where the reader is asking. The heading check is the other way round - it heads a list,
--- so with no list under it there is nothing for it to head.
---
--- **Nothing raises when an `IsEnabled` goes the wrong way** and no static check reads frame state,
--- so the three can only be held together from in here. One of them going missing altogether raises
--- for a different reason: `parentKey` is what these are found by, and a renamed one answers nil.
RegisterTest("Storage: the verbs grey out when nothing is picked", {
    description = "With no entry picked the two buttons grey out rather than disappear",
    run = function()
        local NAME = "Storage verbs"

        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F7" })

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        local verbs = {
            { button = panel.Preview.AddButton,  name = "[Add to My Setup]" },
            { button = panel.Preview.CopyButton, name = "[Create Share Code]" },
        }
        for _, verb in ipairs(verbs) do
            if not verb.button then
                return Fail(NAME, format("no %s button, check the parentKey in the XML", verb.name))
            end
        end

        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            panel:SelectEntry(nil)
            DebindPrivate.Store.DeleteEntry(entry.id)
        end)

        -- **The lit state is checked first.** Without it, the pass below is explained just as well
        -- by "both were dark to begin with".
        panel:SelectEntry(entry)
        if #panel:EnumerateListedActions() == 0 then
            return Fail(NAME, "the premise is gone: the entry just made holds no action at all")
        end
        if not panel.Preview.SelectAllCheck:IsShown() then
            return Fail(NAME, "picked an entry that has actions and there is no [select all]")
        end
        for _, verb in ipairs(verbs) do
            if not verb.button:IsEnabled() then
                return Fail(NAME, format("picked a fully ticked entry and %s is grey", verb.name))
            end
        end

        panel:SelectEntry(nil)
        if panel.Preview.SelectAllCheck:IsShown() then
            return Fail(NAME, "nothing is picked and [select all] is standing")
        end
        for _, verb in ipairs(verbs) do
            if not verb.button:IsShown() then
                return Fail(NAME, format("%s disappeared, it should have gone grey", verb.name))
            end
            if verb.button:IsEnabled() then
                return Fail(NAME, format("nothing is picked and %s can still be pressed", verb.name))
            end
        end

        return Pass(NAME, "both light up when something is picked, and go grey in place when nothing is")
    end,
})

--- **The second door to the same outcome asks the same question** (2026-08-23, the owner). [Add and
--- Accept] used to reach down into the plan and leave the badge off, which put the arrivals live on
--- the sender's keys with nothing asked - and on a key the reader already uses, that is a merge
--- they never chose. It lands badged now and runs the approval, so the prompt [Accept all] raises
--- stands here too.
---
--- **Until the prompt is answered the arrivals are pending**, which is what makes its [Cancel] a
--- whole answer: nothing is half done, the actions are in and waiting like any other arrival.
---
--- `StaticPopup_Show` is the game's, so nothing outside it can see this.
RegisterTest("Storage: adding and accepting asks about a key I am using", {
    description = "[Add and Accept] raises the bulk approval confirmation for a key that clashes",
    run = function()
        local NAME = "Storage add and accept"
        local KEY = "CTRL-ALT-F4"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        -- One of mine already stands on that key. The payload is lifted from the profile, so it
        -- comes back carrying the same key.
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        ApplyBindings()

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            panel:SelectEntry(nil)
            DebindPrivate.Store.DeleteEntry(entry.id)
        end)

        panel:SelectEntry(entry)
        local listed = panel:EnumerateListedActions()
        if #listed == 0 then
            return Fail(NAME, "the premise is gone: the entry holds no action at all")
        end

        panel:OnAddClicked(true)

        local dialog = StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED")
        if not dialog then
            return Fail(NAME, "it came in on a key I use and nothing was asked")
        end

        -- **What the window is holding is what gets read.** `CollectArrivedActions` cannot see it:
        -- the payload cannot carry the address of a layer this board made (`ImportAddress`), so the
        -- arrivals settle into the **real** class layer, and the kit swaps the three enumerators out
        -- and does not show that one. In the game they are the same thing, and here this list is
        -- where it is.
        local pending = dialog.data and dialog.data.arrivals or {}
        if #pending == 0 then
            return Fail(NAME, "the confirmation stood holding nothing")
        end

        -- **They are pending for as long as the question stands.** With the badge already off, the
        -- window would be asking about something that has already happened.
        for _, action in ipairs(pending) do
            if action.arrivalID == nil then
                return Fail(NAME, "the confirmation is up and something has already lost its badge")
            end
            if action.key ~= KEY then
                return Fail(NAME, format("the arrival lost the key it was sent on: %s", tostring(action.key)))
            end
        end

        return Pass(NAME, format("the confirmation stood and %d are pending", #pending))
    end,
})

--- **Leaving the tab is not the same as picking a different entry** (2026-08-23, the owner). What is
--- ticked and which layers are open are the reader's answers, and `OnShow` used to throw both away
--- and start the entry over - so a glance at Overview undid however many clicks they had spent
--- setting up what to bring.
---
--- **What makes keeping them safe is that the tables do not move.** A tick is keyed by the action
--- table itself, and both walks that open a stored payload write into the tables rather than
--- replacing them (`GetEntryPayload`, `MigrateLayer`). Nothing headless can see that, because what
--- is being asked is what two frame scripts do in sequence.
RegisterTest("Storage: a tab change keeps what is ticked and what is open", {
    description = "Leaving the tab and coming back keeps what is ticked and what is open",
    run = function()
        local NAME = "Storage view state"

        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F8" })
        InsertAction({ type = Constants.SPELL, value = 589, key = "CTRL-ALT-F9" })

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "could not get the storage panel, check the tab number or LoadAddOn")
        end

        -- **The window is stood up first.** The panel's `OnShow` registers on the window's callback
        -- bus, that bus is made by `DebindFrameMixin:OnLoad`, and what calls that is the window's
        -- first `OnShow`. Called without standing it up, `DebindFrame.Event` is nil.
        DebindFrame:Show()

        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            panel:SelectEntry(nil)
            panel:OnHide()
            DebindPrivate.Store.DeleteEntry(entry.id)
            DebindFrame:Hide()
        end)

        panel:OnShow()
        panel:SelectEntry(entry)

        local listed = panel:EnumerateListedActions()
        local layer = (panel.previewLayers or {})[1]
        if #listed < 2 or not layer then
            return Fail(NAME, format("the premise is gone: %d action(s), layer %s",
                #listed, tostring(layer and layer.key)))
        end

        -- Straight after picking, everything is ticked and everything is collapsed. This turns over
        -- one of each of the things a reader would touch.
        local untickedAction = listed[1]
        panel:ToggleAction(untickedAction)
        panel:ToggleLayerCollapsed(layer.key)
        if panel.selected[untickedAction] or panel:IsLayerCollapsed(layer.key) then
            return Fail(NAME, "the premise is gone: what was touched did not turn over on the spot")
        end

        -- Leaves the tab and comes back. These two are what run when the window swaps panels.
        panel:OnHide()
        panel:OnShow()

        if panel:GetSelectedEntry() ~= entry then
            return Fail(NAME, "the picked entry changed while we were away")
        end
        if panel.selected[untickedAction] then
            return Fail(NAME, "a tick that was cleared is back on")
        end
        if panel:IsLayerCollapsed(layer.key) then
            return Fail(NAME, "a layer that was opened is collapsed again")
        end

        -- It also checks that the rest stayed as they were. On the two above alone, "everything went
        -- off" passes too.
        local stillTicked = 0
        for _, action in ipairs(panel:EnumerateListedActions()) do
            if panel.selected[action] then
                stillTicked = stillTicked + 1
            end
        end
        if stillTicked ~= #listed - 1 then
            return Fail(NAME, format("%d ticks should be left and there are %d", #listed - 1, stillTicked))
        end

        return Pass(NAME, format("%d ticks and the open layer survived the tab change", stillTicked))
    end,
})

-----------------------------------------------------------
-- Test Cases: The window's three panels
--
-- **All three are Debind's own XML now** (2026-08-15). Two of them used to be built by the
-- load-on-demand addon and fetched by global name; they are children of the frame by
-- `parent=` + `parentKey=` and arrive by `panelKey` (`devdocs/building-export-import.md`).
--
-- Everything below fails **silently** if it breaks, which is why it is here rather than in a
-- checklist: a `parentKey` renamed, an XML dropped from the TOC, another panel added without a
-- width, `EnsureStore` simplified back to `IsAddOnLoaded`. None of that raises, and none of it is
-- visible to `npm run check` - the panels are built by code that only runs in the game.
--
-- **Nothing here inserts an action, on purpose.** Showing a panel is all these ask about, and an
-- empty profile is the cheapest way to ask it. What the storage tab draws with actions in it is the
-- test above, which builds an entry rather than a screen.
-----------------------------------------------------------

--- The other two seats in `PANELS`, kept in step by hand for the reason `STORAGE_PANEL_ID` gives:
--- that table is a local in `DebindUI.lua`. The first test below is what says so out loud - ids
--- that answer with different panels cannot all be pointing at the wrong seat.
---
--- **Switches sits second, ahead of sharing.** There were four seats while making a string and
--- taking one in were separate tabs; they are one now. Numbers that drift here do not error: they
--- measure a different panel and pass.
local OVERVIEW_PANEL_ID, SWITCHES_PANEL_ID = 1, 2

RegisterTest("Panels: every tab resolves to a panel of its own", {
    description = "All three tabs resolve to a panel of their own, neither collapsing onto one nor falling through to MissingPanel",
    run = function()
        local NAME = "Panels resolve"

        local seen = {}
        for _, id in ipairs({ OVERVIEW_PANEL_ID, SWITCHES_PANEL_ID, STORAGE_PANEL_ID }) do
            local panel = DebindFrame:ResolvePanel(id)
            if not panel then
                return Fail(NAME, format("tab %d got no panel, check panelKey in PANELS or the TOC", id))
            end
            if panel == DebindFrame.MissingPanel then
                return Fail(NAME, format("tab %d fell through to MissingPanel", id))
            end
            -- The whole point of the move: they are the frame's children rather than something
            -- reparented on the first press.
            if panel:GetParent() ~= DebindFrame then
                return Fail(NAME, format("panel %d's parent is not the window", id))
            end
            if seen[panel] then
                return Fail(NAME, format("tab %d gives the same panel as tab %d", id, seen[panel]))
            end
            seen[panel] = id
        end

        return Pass(NAME, "4 tabs onto 4 panels of their own")
    end,
})

-- **The width is a `KeyValue` in the XML and nothing checks it.** It used to be read back out of
-- `GetWidth()` in `OnLoad`, which worked only while the panel stood unanchored at load; pinned to
-- the host on four sides that read answers with the window's own width - the value fed back - and
-- every tab would quietly settle on one size. Turning the KeyValue back into a `<Size>` restores
-- exactly that failure, with no error anywhere.
RegisterTest("Panels: the window takes each tab's own width", {
    description = "Moving tabs really does take the window to the width that panel asked for",
    run = function()
        local NAME = "Panel width"

        -- **The pair is Overview and Switches.** It was Overview and the export tab until the two
        -- sharing tabs became one that has two columns -- which asks for Overview's own width, and
        -- two panels legitimately wanting the same number leave this nothing to measure.
        local overview = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        local narrow = DebindFrame:ResolvePanel(SWITCHES_PANEL_ID)
        if not overview or not narrow then
            return Fail(NAME, "could not get the panel")
        end
        if not overview.preferredWidth or not narrow.preferredWidth then
            return Fail(NAME, format("it is not holding a width (overview=%s, switches=%s)",
                tostring(overview.preferredWidth), tostring(narrow.preferredWidth)))
        end
        if overview.preferredWidth == narrow.preferredWidth then
            return Fail(NAME, format(
                "both panels ask for the same width (%d), they may be reading the window's width back",
                overview.preferredWidth))
        end

        -- Put the reader back where they were, whatever happens below.
        AddTeardown(function() DebindFrame:SelectPanel(OVERVIEW_PANEL_ID) end)

        -- And that the frame actually listens. Asking the panels alone would pass on a
        -- `SelectPanel` that stopped applying it.
        DebindFrame:SelectPanel(SWITCHES_PANEL_ID)
        local narrowWidth = DebindFrame:GetWidth()
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
        local overviewWidth = DebindFrame:GetWidth()

        -- **Within a pixel, not exact.** `GetWidth` reads back what the frame ended up at, and that
        -- is not obliged to be the number `SetWidth` was handed once the UI scale has been through
        -- it - 812 comes back as 811 on some scales. What this test is for is that the frame follows
        -- the panel at all, which an exact compare answers wrongly rather than more strictly.
        local function Off(got, want) return math.abs(got - want) > 1 end
        if Off(narrowWidth, narrow.preferredWidth) or Off(overviewWidth, overview.preferredWidth) then
            return Fail(NAME, format("the window does not follow: switches %d (wanted %d), overview %d (wanted %d)",
                narrowWidth, narrow.preferredWidth, overviewWidth, overview.preferredWidth))
        end

        return Pass(NAME, format("overview %d, switches %d", overviewWidth, narrowWidth))
    end,
})

-- **A dragged window hangs by whatever anchor `StartMoving` chose**, and one dropped near the
-- middle of the screen comes back on a centre one. `SetWidth` then splits the difference between
-- both sides, so every tab change slid the window sideways by half of it. `OnDragStop` saved a
-- top left corner and nothing pinned the window to one, which is why a `/reload` appeared to fix
-- it: the load path was the only place that anchored by the corner.
--
-- The drag itself cannot be driven from here. What the test stands in for is the one thing
-- `StartMoving` leaves behind, the centre anchor, and everything after that is the window's own
-- `OnDragStop`.
RegisterTest("Panels: a dragged window keeps its left edge across a tab change", {
    description = "A window that was dragged keeps its left edge when a tab change moves its width",
    run = function()
        local NAME = "Left edge"

        local overview = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        local narrow = DebindFrame:ResolvePanel(SWITCHES_PANEL_ID)
        if not overview or not narrow then
            return Fail(NAME, "could not get the panel")
        end
        -- Two tabs of the same width would leave nothing to measure, and this would pass on any
        -- anchor at all. **Switches is the narrow one**; the storage tab asks for Overview's width.
        if overview.preferredWidth == narrow.preferredWidth then
            return Fail(NAME, format("both tabs ask for the same width (%s)", tostring(overview.preferredWidth)))
        end

        if not DebindFrame:IsShown() then
            DebindFrame:Show()
            AddTeardown(function() DebindFrame:Hide() end)
        end

        -- Where the tester had the window, and what they had saved. `OnDragStop` writes both.
        local point, relativeTo, relativePoint, x, y = DebindFrame:GetPoint(1)
        local saved = DebindPrivate.db.global.ui.main
        AddTeardown(function()
            DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
            DebindPrivate.db.global.ui.main = saved
            if point then
                DebindFrame:ClearAllPoints()
                DebindFrame:SetPoint(point, relativeTo, relativePoint, x, y)
            end
        end)

        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
        DebindFrame:ClearAllPoints()
        DebindFrame:SetPoint("CENTER", "UIParent", 0, 0)

        local dragStop = DebindFrame:GetScript("OnDragStop")
        if not dragStop then
            return Fail(NAME, "no OnDragStop, the window cannot be dragged")
        end
        dragStop(DebindFrame)

        local before = DebindFrame:GetLeft()
        DebindFrame:SelectPanel(SWITCHES_PANEL_ID)
        local after = DebindFrame:GetLeft()
        if not before or not after then
            return Fail(NAME, "could not read the window's left edge")
        end
        -- Within a pixel: `GetLeft` reads back what the frame ended up at, and the UI scale is in
        -- the middle of that (the tab width test above says the same thing).
        if math.abs(after - before) > 1 then
            return Fail(NAME, format("the left edge moved from %.0f to %.0f", before, after))
        end

        return Pass(NAME, format("%.0f unmoved (width %d -> %d)",
            before, overview.preferredWidth, narrow.preferredWidth))
    end,
})

-- **The panel is always there; what can be missing is what it reads.** `EnsureStore` asks whether
-- `DebindPrivate.Store` was handed over, not whether the addon is loaded - the addon can be in
-- memory having handed over nothing, and every caller dereferences that table. Asking
-- `IsAddOnLoaded` reads as the natural thing to write (it was, first), and it turns this fallback
-- into an error on the tab.
RegisterTest("Panels: no store means no panel, not an error", {
    description = "With no Store to be had, ResolvePanel answers nil and MissingPanel stands",
    run = function()
        local NAME = "Store missing"

        local saved = DebindPrivate.Store
        if not saved then
            return Fail(NAME, "there is no Store to begin with, this test has nothing to measure")
        end
        AddTeardown(function() DebindPrivate.Store = saved end)

        DebindPrivate.Store = nil
        local storagePanel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        local overviewPanel = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        DebindPrivate.Store = saved

        if storagePanel ~= nil then
            return Fail(NAME, "no Store and it handed over the storage panel, which indexes nil behind that")
        end
        -- Overview reads none of it, so it must not be dragged down with them.
        if overviewPanel == nil then
            return Fail(NAME, "the overview, which has nothing to do with Store, was blocked too")
        end

        return Pass(NAME, "import is blocked and the overview stands")
    end,
})

--- **The client is the only thing that can answer this one.** Both halves are frame questions: what
--- `UpdateButtons` left the button's enabled state at, and whether the press put the client's own
--- confirmation up. The headless harness has neither.
---
--- What it guards is the button being the only door. It is grey exactly when the sweep finds
--- nothing, so a lit button is a promise, and `RemoveDuplicateActions` walking a second time on the
--- press is what keeps that promise from resting on a cached answer. Gate the two on different
--- walks and a lit button starts answering `REMOVE_DUPLICATES_NONE`.
RegisterTest("Duplicates: the clean up button is lit only where there is something to remove", {
    description = "The clean up button lights only where there is a duplicate, and pressing it raises the confirmation",
    run = function()
        local NAME = "Duplicates clean up"
        local KEY = "CTRL-ALT-F7"

        if not DebindFrame:IsShown() then
            DebindFrame:Show()
            AddTeardown(function() DebindFrame:Hide() end)
        end
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)

        -- The confirmation is the client's and outlives a failed run, so it goes whatever happens.
        AddTeardown(function() StaticPopup_Hide("GENERIC_CONFIRMATION") end)
        -- **The two duplicates below go too.** This case opens by asserting the layer holds nothing
        -- the sweep would find, and leaving them behind hands that same precondition to the next
        -- case as something it has to know about.
        AddTeardown(CleanupActions)

        local cleanUp = DebindFrame.OverviewPanel.CleanUpPortrait
        DebindFrame:Update()
        if cleanUp:IsEnabled() then
            return Fail(NAME, "there is no duplicate at all and the clean up button is lit")
        end
        -- Grey with no reason on the tooltip is a button that cannot say why.
        if cleanUp.disabledReason ~= LLL["REMOVE_DUPLICATES_NONE"] then
            return Fail(NAME, "the dark button is not holding a reason")
        end

        -- Two actions a signature cannot tell apart, in one layer. That is the whole of what the
        -- sweep looks for.
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        ApplyBindings()

        DebindFrame:Update()
        if not cleanUp:IsEnabled() then
            return Fail(NAME, "there is a duplicate and the clean up button is dark")
        end
        if cleanUp.disabledReason ~= nil then
            return Fail(NAME, "the lit button is still holding the reason it was dark")
        end

        local onClick = cleanUp:GetScript("OnClick")
        if not onClick then
            return Fail(NAME, "the clean up button has no OnClick on it")
        end
        onClick(cleanUp)

        -- **The press has to reach the confirmation**, which is the half `UpdateButtons` cannot
        -- promise: the button lighting up says the walk found something, and this says the press
        -- walked again and agreed.
        if not StaticPopup_IsCustomGenericConfirmationShown("DebindDeleteConfirmation") then
            return Fail(NAME, "the button is lit and pressing it brought up no confirmation, the two detections have come apart")
        end

        return Pass(NAME, "dark where there is none, lit where there is, and pressing it reaches the confirmation")
    end,
})

--- The other half of the sweep: what the press actually takes away.
---
--- **This is the only path in the addon that deletes with no way back, so the kit is where it gets
--- pressed.** The headless spec stops at `CollectDuplicateActions` handing back a list
--- (`tests/identity_spec.lua`). Between that list and the profile afterwards lie the press, the
--- client's confirmation and `DeleteActions` renumbering what is left, and the reader says yes to
--- all of it at once.
---
--- **Every action here carries a condition, and the two kinds carry different ones.** The solver
--- drops a binding a higher one already covers, so two unconditional actions on one key leave a
--- single row in the key map and `KeyMapOrder` stops being able to say what survived. Different
--- axes keep both, which is what lets the last check ask whether the key still does what it did.
---
--- **Crossing layers is left to the headless spec.** A run is isolated to one layer
--- (`SetIsolated`), so a second one here would be a stand-in of my own making, measured against the
--- same walk the spec already measures against a profile that really has two.
RegisterTest("Duplicates: the press takes the copy that never fires", {
    description = "What the clean up removes and what it leaves, once confirmed",
    run = function()
        local NAME = "Duplicates removal"
        local KEY = "CTRL-ALT-F8"

        if not DebindFrame:IsShown() then
            DebindFrame:Show()
            AddTeardown(function() DebindFrame:Hide() end)
        end
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)

        AddTeardown(function() StaticPopup_Hide("GENERIC_CONFIRMATION") end)
        AddTeardown(CleanupActions)

        local cleanUp = DebindFrame.OverviewPanel.CleanUpPortrait

        --- The action while it is still in the layer, nil once it has been deleted. The table it
        --- was is still in hand either way, so asking it is no answer.
        local function Living(action)
            for _, candidate in GetTestLayer():Enumerate() do
                if candidate == action then
                    return candidate
                end
            end
            return nil
        end

        --- One group's `seq` on `KEY`, smallest first, as a string. The group is `(key, arrivalID)`.
        local function GroupSeqs(arrivalID)
            local out = {}
            for _, action in GetTestLayer():Enumerate() do
                if action.key == KEY and action.arrivalID == arrivalID then
                    out[#out + 1] = action.seq or -1
                end
            end
            table.sort(out)
            for i = 1, #out do
                out[i] = tostring(out[i])
            end
            return table.concat(out, " ")
        end

        --- Presses the button and says yes to what comes up.
        ---
        --- **The reference key is read before anything is clicked.** `GENERIC_CONFIRMATION` is the
        --- client's shared dialog and `StaticPopup_Visible` hands back whichever went up first, so
        --- pressing blind is pressing a stranger's [Yes].
        local function SweepAndAccept()
            DebindFrame:Update()
            if not cleanUp:IsEnabled() then
                return "a duplicate was stood up and the clean up button is dark"
            end
            cleanUp:Click()
            if not StaticPopup_IsCustomGenericConfirmationShown("DebindDeleteConfirmation") then
                return "pressing it brought up no confirmation"
            end
            local _, dialog = StaticPopup_Visible("GENERIC_CONFIRMATION")
            if not dialog or not dialog.data
                or dialog.data.referenceKey ~= "DebindDeleteConfirmation" then
                return "a confirmation that is not ours is standing in front"
            end
            dialog:GetButton1():Click()
            ApplyBindings()
            return nil
        end

        -- 1. One duplicate inside my group, and one inside the arrival group sitting on the same
        --    key. Both have to be caught at once, and afterwards neither group may have touched the
        --    other's numbers.
        CleanupActions()
        local keeper = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, stealth = true })
        local twinA = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, combat = true })
        local twinB = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, combat = true })
        local badgedA = InsertAction({ type = Constants.SPELL, value = 3, key = KEY,
            arrivalID = 7, combat = true })
        local badgedB = InsertAction({ type = Constants.SPELL, value = 3, key = KEY,
            arrivalID = 7, combat = true })
        ApplyBindings()

        -- **The premise: each group starts at 1 of its own.** Without that there is no telling what
        -- the number checks below measure.
        if GroupSeqs(nil) ~= "1 2 3" or GroupSeqs(7) ~= "1 2" then
            return Fail(NAME, format("the board did not stand. mine [%s], arrival [%s]",
                GroupSeqs(nil), GroupSeqs(7)))
        end
        local loser, winner = twinB, twinA
        if twinB.seq < twinA.seq then
            loser, winner = twinA, twinB
        end

        local err = SweepAndAccept()
        if err then return Fail(NAME, err) end

        if Living(loser) then
            return Fail(NAME, "the one with the higher seq was not deleted")
        end
        if not Living(winner) or not Living(keeper) then
            return Fail(NAME, "the one that fires first was deleted")
        end
        if not Living(badgedA) or Living(badgedB) then
            return Fail(NAME, "the duplicate inside the arrival group was missed, or the wrong one was caught")
        end
        -- **Each group is 1..n again within itself.** Numbered across the two together, the arrival
        -- carries 3 and my group fills 1..3.
        if GroupSeqs(nil) ~= "1 2" then
            return Fail(NAME, format("my group's numbers do not run on after the delete: [%s]", GroupSeqs(nil)))
        end
        if GroupSeqs(7) ~= "1" then
            return Fail(NAME, format("the arrival was numbered mixed in with my group: [%s]", GroupSeqs(7)))
        end
        if KeyMapOrder(KEY) ~= "1 2" then
            return Fail(NAME, format("what that key did changed after the delete: [%s]", KeyMapOrder(KEY)))
        end

        -- 2. An arrival that came as an exact copy of one of mine. **While the badge is on it
        --    reaches no key at all** (`BuildKeyMap`), so keeping that one and deleting mine takes
        --    away something the key was doing. Because each group numbers from 1, the arrival's
        --    `seq` can be lower than mine, and ordering on `seq` alone loses in exactly that way.
        CleanupActions()
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, stealth = true })
        local mine = InsertAction({ type = Constants.SPELL, value = 4, key = KEY, combat = true })
        local badged = InsertAction({ type = Constants.SPELL, value = 4, key = KEY,
            arrivalID = 9, combat = true })
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "1 4" then
            return Fail(NAME, format("the board did not stand. the key is [%s]", KeyMapOrder(KEY)))
        end
        if not (badged.seq and mine.seq and badged.seq < mine.seq) then
            return Fail(NAME, format("arrival %s, mine %s. not what this board set out to measure",
                tostring(badged.seq), tostring(mine.seq)))
        end

        err = SweepAndAccept()
        if err then return Fail(NAME, err) end

        if not Living(mine) or not Living(first) then
            return Fail(NAME, "the badged copy was kept and my action was deleted")
        end
        if Living(badged) then
            return Fail(NAME, "the arrival's copy was not deleted")
        end
        if KeyMapOrder(KEY) ~= "1 4" then
            return Fail(NAME, format("the confirmation said no key would change and one did: [%s]",
                KeyMapOrder(KEY)))
        end

        -- 3. When there is none at all. **The button cannot reach this branch** (it is greyed), so
        --    it is called outright. That it is greyed is what the case above measures.
        CleanupActions()
        InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        ApplyBindings()
        DebindFrame:Update()
        if cleanUp:IsEnabled() then
            return Fail(NAME, "there is no duplicate and the clean up button is lit")
        end

        local said
        local realDisplay = DebindPrivate.DisplayMessage
        DebindPrivate.DisplayMessage = function(message) said = message end
        local ok, thrown = pcall(DebindUI.RemoveDuplicateActions)
        DebindPrivate.DisplayMessage = realDisplay
        if not ok then
            return Fail(NAME, format("it raised on the empty branch: %s", tostring(thrown)))
        end
        if said ~= LLL["REMOVE_DUPLICATES_NONE"] then
            return Fail(NAME, format("it did not say there was none: %s", tostring(said)))
        end
        if StaticPopup_IsCustomGenericConfirmationShown("DebindDeleteConfirmation") then
            return Fail(NAME, "there is nothing to delete and a confirmation came up")
        end

        return Pass(NAME, "the one that fires first is kept, the groups do not mix numbers, and with none it answers in one line")
    end,
})

-----------------------------------------------------------
-- Test Cases: The Switches tab
--
-- **Everything here is a wire that fails without a word.** A row's toggle writes a value that only
-- means something once codegen has been past it; a rename rewrites four kinds of reference and the
-- ones it misses are silent by construction, since a condition that stops matching draws exactly
-- like one that matches. Headless specs check that the rename moves the stored strings
-- (`tests/switch_spec.lua`); what only the game answers is whether the key still fires afterwards.
--
-- **The definition is put in by hand rather than made through the menu.** A run must not leave a
-- switch in the tester's profile, and the definitions table is the account's. So the slot is
-- swapped and put back, the way the switch tests further up do it.
-----------------------------------------------------------

--- The row drawn for one switch, once the list has laid itself out.
---
--- **`layerID` is what tells the two kinds of row apart.** Since stage 4 a switch's own row is
--- followed by one row per tab that answers for it, and those carry the same `switchName` - without
--- this a test asking for "the row" gets whichever the walk reached last, which is a tab row with
--- no toggle on it.
local function SwitchRow(panel, name)
    local found
    panel.ScrollBox:ForEachFrame(function(frame)
        if frame.switchName == name and not frame.layerID then
            found = frame
        end
    end)
    return found
end

--- The tab rows under one switch. **Whatever is in view**, like every other walk over a scroll box
--- here: `ForEachFrame` reaches the frames that exist, so a caller matches on `layerKey` rather
--- than on a position in the list.
local function SwitchLayerRows(panel, name)
    local rows = {}
    panel.ScrollBox:ForEachFrame(function(frame)
        if frame.switchName == name and frame.layerID then
            rows[#rows + 1] = frame
        end
    end)
    return rows
end

--- Opens the tab and hands back the panel with its rows built. Puts the reader back on Overview
--- and closes the window afterwards, however the test ends.
---
--- **The list is refreshed here rather than left to `OnShow`.** Showing a frame that is already
--- shown fires nothing, and `SelectPanel` turns back when its tab is already the current one, so a
--- tester who left this tab open gets neither. The rows would then be the ones drawn before the
--- test planted anything, which reads as "the list does not list switches" -- it measured a stale
--- draw. Build the precondition, do not hope for it.
local function OpenSwitchesTab()
    DebindFrame:Show()
    AddTeardown(function()
        DebindFrame:SelectPanel(OVERVIEW_PANEL_ID)
        DebindFrame:Hide()
    end)
    DebindFrame:SelectPanel(SWITCHES_PANEL_ID)

    local panel = DebindFrame.SwitchesPanel
    panel:RefreshRows()
    return panel
end

RegisterTest("Switches tab: the toggle on a row moves the key", {
    description = "The on/off button on a row really does bind and release the key that switch stands on",
    run = function()
        local NAME = "Switch row toggle"
        local KEY = "CTRL-SHIFT-F7"
        local SWITCH = "$rowtoggle"

        if InCombatLockdown() then
            return Fail(NAME, "this button is disabled in combat, so nothing can be judged")
        end

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.db.char.switches[SWITCH] = nil
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- **`resetValue`, not `value`.** The second is derived - a rebuild recomputes it from
        -- the answer in effect and from what this character remembers (`ApplySwitchResets`), so
        -- a setup that writes it is writing something the first rebuild may overwrite. What is
        -- wanted here is the answer "comes up off", and that is a `resetValue`.
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = false }

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, [SWITCH] = true })
        ApplyBindings()

        local panel = OpenSwitchesTab()
        -- The list lays itself out on a later frame, so the row is waited for rather than assumed.
        -- What is waited on is the widget existing, not the answer this test is about.
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            -- What the list did hold, because "no row" has two very different causes: the name
            -- never reached `GetSwitchNames`, or it did and no frame was built for it.
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("no row for that switch in the list. names: [%s]", names))
        end
        if not row.ToggleButton:IsEnabled() then
            return Fail(NAME, "a switch turned on and off by hand and the button is disabled")
        end

        -- **Pressed, not called.** `OnToggleClick` reached directly would pass on a row whose XML
        -- lost its `OnClick`, which is exactly the wiring this test is here for.
        row.ToggleButton:Click()

        local whenOn = GetBindingAction(KEY, true) or ""
        if whenOn:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("turned on and the key is %q, the value never reached codegen", whenOn))
        end

        row.ToggleButton:Click()

        local whenOff = GetBindingAction(KEY, true) or ""
        if whenOff ~= "" then
            return Fail(NAME, format("turned off and the key is still %q", whenOff))
        end

        return Pass(NAME, "pressed on -> bound / pressed off -> released")
    end,
})

-- **A dialog that opens on a value is two things, and only one of them is checkable by eye.** That
-- it opens is obvious; that it opens *carrying* what is already stored is a line of code that runs
-- after the popup is up, reaching into the client's own frame. That reach was written against
-- `popup.editBox`, a field the dialog stopped having when it became `GameDialogMixin`, so the box
-- opened blank and then errored -- and it errored only for callers that pass a value, which is why
-- it lived so long (`ShowInputBox` in `DebindUI.lua`).
--
-- The rename box goes through the same function, so this covers both.
RegisterTest("Switches tab: the expression box opens on the expression", {
    description = "The expression box opens holding the expression as it stands",
    run = function()
        local NAME = "Switch input box"
        local SWITCH = "$boxopen"
        local EXPR = "[combat]"

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
            if dialog then
                -- **Focus first.** The box takes the keyboard when it opens, and a hidden frame
                -- that still holds it swallows what the next test types.
                local editBox = dialog:GetEditBox()
                if editBox then
                    editBox:ClearFocus()
                end
                dialog:Hide()
            end
        end)
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.EXPR, expr = EXPR }

        DebindUI.ShowSwitchExpressionBox(SWITCH)

        local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
        if not dialog then
            return Fail(NAME, "the box did not come up")
        end
        local editBox = dialog:GetEditBox()
        if not editBox then
            return Fail(NAME, "the box has no edit field, the client has renamed it again")
        end
        local text = editBox:GetText()
        if text ~= EXPR then
            return Fail(NAME, format("the box opened holding %q, the expression on record was not carried", text))
        end

        return Pass(NAME, format("%q", text))
    end,
})

-- **The button that replaced the portrait's dropdown** (3c, §6-C of
-- `devdocs/legacy/redesigning-custom-states.md`). Making a switch was a menu on the window's title bar
-- until now; it is this button, the condition menu and an on/off/toggle action's own menu, and all
-- three go through `DebindUI.ShowNewSwitchBox`.
--
-- **Pressed and typed into, not called.** `ShowNewSwitchBox` reached directly passes on a panel
-- whose XML lost the `OnClick`, and `SetText` without the box's own accept path passes on a dialog
-- whose button does nothing. Both of those are the wiring this test is here for.
RegisterTest("Switches tab: the New switch button makes one", {
    description = "The button under the list raises a box, and the name typed into it makes a switch",
    run = function()
        local NAME = "New switch button"
        local SWITCH = "$madehere"

        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = nil
            DebindPrivate.db.char.switches[SWITCH] = nil
            local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
            if dialog then
                -- Focus first: a hidden box that still holds the keyboard swallows what the next
                -- test types (the expression box test above says the same).
                local editBox = dialog:GetEditBox()
                if editBox then
                    editBox:ClearFocus()
                end
                dialog:Hide()
            end
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)

        if DebindPrivate.Switches[SWITCH] then
            return Fail(NAME, "the premise is gone: a switch of that name already exists")
        end

        local panel = OpenSwitchesTab()
        if not panel.NewButton then
            return Fail(NAME, "no NewButton on the panel, the XML was not loaded")
        end
        if not panel.NewButton:IsEnabled() then
            return Fail(NAME, "the button is disabled")
        end

        panel.NewButton:Click()

        local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
        if not dialog then
            return Fail(NAME, "pressed the button and the box did not come up")
        end
        local editBox = dialog:GetEditBox()
        if not editBox then
            return Fail(NAME, "the box has no edit field. the client has renamed it again")
        end
        -- **The box opens empty, and `$` is drawn beside it.** The sigil is furniture now: it
        -- cannot be typed over, deleted or doubled, and what the reader types is joined to it by
        -- the caller. So the box holding anything at all is the failure, and the switch coming out
        -- named `$madehere` below is what says the two were joined.
        if editBox:GetText() ~= "" then
            return Fail(NAME, format("the box opened holding %q. it should open empty",
                editBox:GetText()))
        end

        if not TypeInto(editBox, strsub(SWITCH, 2)) then
            return Fail(NAME, "the edit box has no OnTextChanged")
        end
        -- **[Done] is pressed, not the callback called.** The button stays disabled until the box
        -- has text in it (`StaticPopup_StandardNonEmptyTextHandler`), so pressing it is also what
        -- says `TypeInto` reached the handler a hand would have.
        local accept = dialog:GetButton1()
        if not accept:IsEnabled() then
            return Fail(NAME, "a name was typed and [Done] is disabled")
        end
        accept:Click()

        if not DebindPrivate.Switches[SWITCH] then
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("no switch was made. what is there: [%s]", names))
        end

        -- The list has to have heard about it. Making one fires `OnSwitchesChanged` and the panel
        -- rebuilds off that, so a row missing here is that callback not reaching an open tab.
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            return Fail(NAME, "the switch was made and no row stood in the list")
        end

        return Pass(NAME, SWITCH .. " made, with a row in the list")
    end,
})

-- **Two of the three places that make one write the new name straight onto an action**: the
-- condition key, and the target of on/off/toggle (`DropDownMenus.lua`). Both write down the name
-- `ShowNewSwitchBox` hands them, so if the spelling typed in and the name it actually sits under
-- come apart, that action is made pointing at a name with no definition and goes red on the spot.
-- Names are folded to lower case when they are made (`CreateSwitch`).
--
-- **The button test above does not pass through here.** That one opens with no callback and looks
-- only at whether a switch appeared. What name comes back is answered only where it is opened with
-- a callback, and the two places that open it that way are menus.
--
-- Headless goes as far as `CreateSwitch`'s return value ("tells the caller the name it made" in
-- `tests/switch_spec.lua`). What only this layer can answer is whether that value reaches the caller
-- when the box is really typed into and [Done] is really pressed.
RegisterTest("Switches tab: a name typed in capitals reaches the caller folded", {
    description = "A switch made from a name typed in capitals reaches the caller under the name it actually sits on",
    run = function()
        local NAME = "New switch name folds"
        local TYPED = "ZzKit"
        local STORED = "$zzkit"

        AddTeardown(function()
            DebindPrivate.Switches[STORED] = nil
            DebindPrivate.db.char.switches[STORED] = nil
            local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
            if dialog then
                -- Focus first: a hidden box that still holds the keyboard swallows what the next
                -- test types (the two tests above say the same).
                local editBox = dialog:GetEditBox()
                if editBox then
                    editBox:ClearFocus()
                end
                dialog:Hide()
            end
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)

        if DebindPrivate.Switches[STORED] then
            return Fail(NAME, "the premise is gone: a switch of that name already exists")
        end

        -- **Standing where the caller stands.** What the two menus hand this function is a callback
        -- of exactly this shape, and what they do inside it is write the name they were given into
        -- `action.conditions[name]` or `action.value`.
        local called, handed
        DebindUI.ShowNewSwitchBox(function(name)
            called = true
            handed = name
        end)

        local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
        if not dialog then
            return Fail(NAME, "the box did not come up")
        end
        local editBox = dialog:GetEditBox()
        if not editBox then
            return Fail(NAME, "the box has no edit field. the client has renamed it again")
        end
        if not TypeInto(editBox, TYPED) then
            return Fail(NAME, "the edit box has no OnTextChanged")
        end
        -- Presses [Done]. The callback hangs off that button, and calling it outright measures the
        -- function we handed over rather than the path through the box.
        local accept = dialog:GetButton1()
        if not accept:IsEnabled() then
            return Fail(NAME, "a name was typed and [Done] is disabled")
        end
        accept:Click()

        if not DebindPrivate.Switches[STORED] then
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("it did not sit down as %s. what is there: [%s]", STORED, names))
        end
        if not called then
            return Fail(NAME, "the switch was made and the caller was never called. made from a menu, the condition never lands")
        end
        if handed ~= STORED then
            return Fail(NAME, format(
                "the caller was handed %s. written down as a condition or an on-target, that action goes red",
                tostring(handed)))
        end
        if not DebindPrivate.ResolveSwitchDefinition(handed) then
            return Fail(NAME, format("the definition does not open under %s", tostring(handed)))
        end

        return Pass(NAME, format("%s -> %s", TYPED, handed))
    end,
})

-- **The rows under a switch, and the tick on the one in use** (§6-B). What the list has to answer
-- without a click is *where is this different*, so the tab that is answering right now is marked
-- and the ones that are not are still drawn.
--
-- **Both halves are the test.** A tick nowhere and a tick on every row look equally like "the mark
-- works" from one row, and the row a reader takes as the answer is whichever one is ticked - if
-- that is the account-wide row while a tab is overriding it, the list is telling them the opposite
-- of what their keys do.
--
-- **A switch nothing reads has no ticked row at all**, and that is the third half. The tick says
-- "this is the answer in force", which a switch outside the compile has none of: which tab would
-- win is still true, but it decides a value nobody collects. So the same rows are read twice here,
-- once with nothing binding the switch and once with an action that does.
--
-- The XML is measured too: `Check` is a `parentKey` on the template, and a texture that lost its
-- key leaves `SetShown` reaching nil.
RegisterTest("Switches tab: the rows under a switch mark the one that wins", {
    description = "The override rows are drawn, and where an action reads the switch only the winning row is marked",
    run = function()
        local NAME = "Switch layer rows"
        local SWITCH = "$rowlayers"
        local MODES = Constants.SWITCH_MODES

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.db.char.switches[SWITCH] = nil
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- `resetValue` and not `value`, for the reason the toggle test above spells out.
        DebindPrivate.Switches[SWITCH] = { mode = MODES.MANUAL, resetValue = false }

        local layerKey = DebindPrivate.GetSwitchLayerKey(
            DebindPrivate.GetLayerID(C_SpecializationInfo.GetSpecialization(), true))
        if not layerKey then
            return Fail(NAME, "no layer key for this character and this spec")
        end
        DebindPrivate.SetSwitchAnswer(SWITCH, layerKey, MODES.MANUAL, true)

        local panel = OpenSwitchesTab()
        local rows = WaitUntil(function()
            local found = SwitchLayerRows(panel, SWITCH)
            return #found >= 2 and found or nil
        end, 2)
        if not rows then
            local drawn = #SwitchLayerRows(panel, SWITCH)
            return Fail(NAME, format(
                "%d rows, there should be two: the one override put on top and the account-wide one", drawn))
        end

        -- Nothing binds `$rowlayers` yet, so it is outside the compile and no row is the live
        -- answer to anything.
        local function ReadTicks()
            local marked, unmarked = {}, {}
            for _, row in ipairs(rows) do
                if not row.Check then
                    return nil, "the row has no Check, the template lost its parentKey"
                end
                local list = row.Check:IsShown() and marked or unmarked
                list[#list + 1] = row.layerKey or "(account)"
            end
            return marked, unmarked
        end

        local marked, unmarked = ReadTicks()
        if not marked then
            return Fail(NAME, unmarked)
        end
        if #marked ~= 0 then
            return Fail(NAME, format(
                "no action reads this switch and row %d is marked [%s]. there is a place to win, but "
                .. "nowhere takes that value away", #marked, table.concat(marked, " ")))
        end

        -- Now one action reads it, which is what puts the name in front of the restricted side.
        -- The rows are told to redraw by hand: what changed is the bindings, and the list rebuilds
        -- itself off switch changes rather than off those.
        InsertAction({ type = Constants.SETSTATE_TOGGLE, value = SWITCH, key = "CTRL-SHIFT-F8" })
        ApplyBindings()
        for _, row in ipairs(rows) do
            row:Update()
        end

        marked, unmarked = ReadTicks()
        if not marked then
            return Fail(NAME, unmarked)
        end

        if #marked ~= 1 then
            return Fail(NAME, format("%d rows are marked [%s], the winning row is always one",
                #marked, table.concat(marked, " ")))
        end
        if marked[1] ~= layerKey then
            return Fail(NAME, format(
                "%q is marked, %q is the one that wins and the list says otherwise", marked[1], layerKey))
        end
        if #unmarked == 0 then
            return Fail(NAME, "not one losing row was drawn, there is no seeing what is different")
        end

        return Pass(NAME, format("%d rows, unmarked while unread -> %s once read", #rows, marked[1]))
    end,
})

-- **The fifth place, and the only one that is not an action.** Where a switch answers with `[expr]`
-- that expression is a macro conditional and can name another switch, but that name lives inside a
-- definition, where `GetUndefinedSwitch` never looks. Leaving a deleted switch's reference standing
-- there is by design (`DeleteSwitch`), and that design only holds while what is left goes red.
-- Without the red, codegen bakes the name as `known:0` (`EmitMacroTextArg`) and the switch being
-- computed quietly becomes a different one.
--
-- Headless goes as far as the function that answers (`tests/issue_spec.lua`). What only this layer
-- can answer is **whether the row really goes red**: the colour is painted by `Update`, deleting
-- stands the whole list up again, and the row that comes back has to be holding the same answer.
--
-- **What it was before the delete is read first.** On a row that was red from the start, "it went
-- red" says nothing.
RegisterTest("Switches tab: an expression left naming a deleted switch goes red", {
    description = "A row goes red where an expression left behind still names a deleted switch",
    run = function()
        local NAME = "Expression names a dead switch"
        local MODES = Constants.SWITCH_MODES
        local SOURCE = "$exprsrc"
        local DERIVED = "$exprdst"

        local savedSource = DebindPrivate.Switches[SOURCE]
        local savedDerived = DebindPrivate.Switches[DERIVED]
        AddTeardown(function()
            DebindPrivate.Switches[SOURCE] = savedSource
            DebindPrivate.Switches[DERIVED] = savedDerived
            DebindPrivate.db.char.switches[SOURCE] = nil
            DebindPrivate.db.char.switches[DERIVED] = nil
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- **`value` is not used.** That is a derived field and the setting is `resetValue`. All this
        -- needs is "there is one switch turned on and off by hand", so only the mode is written.
        DebindPrivate.Switches[SOURCE] = { mode = MODES.MANUAL }
        DebindPrivate.Switches[DERIVED] = {
            mode = MODES.EXPR,
            expr = format("[%s] [combat]", SOURCE),
        }

        --- The account-wide row. With no override on top, this is the only row this switch has.
        local function RootRow(panel)
            for _, row in ipairs(SwitchLayerRows(panel, DERIVED)) do
                if row.layerKey == nil then
                    return row
                end
            end
        end

        --- **"Red" means measured against the addon's own red.** The winning row is the highlight
        --- colour and a losing row is grey, so which of the three it is comes apart on the value alone.
        local function IsRed(fontString)
            local r, g, b = fontString:GetTextColor()
            local er, eg, eb = ERROR_COLOR:GetRGB()
            return math.abs(r - er) < 0.01 and math.abs(g - eg) < 0.01
                and math.abs(b - eb) < 0.01
        end

        local panel = OpenSwitchesTab()
        local row = WaitUntil(function() return RootRow(panel) end, 2)
        if not row then
            return Fail(NAME, format("%s's account-wide row did not stand", DERIVED))
        end
        if not row.Setting then
            return Fail(NAME, "the row has no Setting. the template lost its parentKey")
        end
        if IsRed(row.Setting) then
            return Fail(NAME, format("the premise is gone: %s is still there and the row is already red", SOURCE))
        end

        DebindPrivate.DeleteSwitch(SOURCE)

        -- Deleting fires `OnSwitchesChanged` and the list stands up again. Frames are recycled, so
        -- this finds the row again rather than reading back what was held above.
        local reddened = WaitUntil(function()
            local found = RootRow(panel)
            if found and found.Setting and IsRed(found.Setting) then
                return found
            end
        end, 2)
        if not reddened then
            if not RootRow(panel) then
                return Fail(NAME, format("%s's row disappeared from the list", DERIVED))
            end
            local expr = DebindPrivate.Switches[DERIVED].expr
            return Fail(NAME, format(
                "the expression is %s and the row did not go red (broken name: %s). there is nowhere to find the deleted reference",
                expr, tostring(DebindPrivate.GetUndefinedSwitchInExpr(expr, DERIVED))))
        end

        return Pass(NAME, format("deleted %s -> %s's row is red", SOURCE, DERIVED))
    end,
})

--- **ESC is this window's ladder, not the game's net.** The two sharing dialogs are in
--- `UISpecialFrames` as well, but that table is read by the ESCAPE *binding*, and the window takes
--- ESCAPE before any binding runs (`DebindFrameMixin:OnKeyDown`). Neither enables the keyboard, so
--- nothing hands it back to them either. Take their rungs off `HandleEscape` and one press hides
--- the window and leaves the dialog standing over nothing, which is the first thing below.
---
--- The rest is the order, and it is the half that cannot be read off one dialog: both can stand at
--- once, since the copy dialog outlives the tab it came from on purpose
--- (`DebindStoragePanelMixin:OnHide`). One press has to move one rung.
---
--- **There were three.** The bring dialog asked which layers to take, and went with the question
--- when the tick moved onto the action (section 12 of `devdocs/building-export-import.md`).
---
--- **`HandleEscape` rather than a key.** A run unbinds the game's own bindings, so a real ESCAPE
--- measures the runner as much as the window; and this function is split out from the key plumbing
--- to be the order on its own, which is exactly what is being asked here.
RegisterTest("Escape: the sharing dialogs close before the window", {
    description = "With a sharing dialog up, ESC closes that first and one at a time, rather than the window",
    run = function()
        local NAME = "Escape ladder"

        DebindFrame:Show()
        AddTeardown(function()
            DebindCopyFrame.Output.EditBox:ClearFocus()
            DebindPasteFrame.Input.EditBox:ClearFocus()
            DebindPasteFrame:Hide()
            DebindCopyFrame:Hide()
            DebindFrame:Hide()
        end)

        -- Both are stood up.
        DebindCopyFrame:ShowText("DEBIND-TEST")
        DebindPasteFrame:Open()

        local steps = {
            { frame = DebindPasteFrame, name = "the paste dialog" },
            { frame = DebindCopyFrame,  name = "the copy dialog" },
        }
        for _, step in ipairs(steps) do
            if not step.frame:IsShown() then
                return Fail(NAME, format("could not even stand %s up", step.name))
            end
        end

        for i, step in ipairs(steps) do
            if not DebindFrame:HandleEscape() then
                return Fail(NAME, format("nobody took ESC number %d", i))
            end
            if step.frame:IsShown() then
                return Fail(NAME, format("ESC number %d did not close %s", i, step.name))
            end
            -- **The window closing here is the bug this test holds off.** The dialog would be left
            -- standing with nothing under it.
            if not DebindFrame:IsShown() then
                return Fail(NAME, format("the ESC that should have closed %s closed the window", step.name))
            end
            -- One rung at a time. Taking one whose turn has not come yet makes a single press remove two.
            for j = i + 1, #steps do
                if not steps[j].frame:IsShown() then
                    return Fail(NAME, format("the ESC that closes %s took %s with it", step.name, steps[j].name))
                end
            end
        end

        -- And the window closes only **after** all three are gone. Without this line, the pass above
        -- is explained just as well by "ESC does nothing".
        if not DebindFrame:HandleEscape() then
            return Fail(NAME, "nobody took the ESC after every dialog had closed")
        end
        if DebindFrame:IsShown() then
            return Fail(NAME, "every dialog has closed and the window does not close on ESC")
        end

        return Pass(NAME, "stepped back one at a time: import, paste, copy, then the window")
    end,
})

-----------------------------------------------------------
-- Test Cases: Binding Issue Detection
-----------------------------------------------------------

-- **Does one toggle flip the value once.** The chain is: write the `$state4` attribute ->
-- `_onattributechanged` (`Switches.lua`) -> `ToggleSwitch` -> `States` -> the mirror.
-- Broken at any link, it is silent.
--
-- **Pressing twice is the point.** The second write carries the **same** `"toggle"` the first one
-- did, so on a client that skips `OnAttributeChanged` for an unchanged value the first press works
-- and every one after it is dead. Measured, it does fire (`.zzz/findings.md` §12-2) -- this is what
-- catches that answer changing.
--
-- What it does not prove: that a real keypress arrives. The test above asks that, with
-- `GetBindingAction`.
RegisterTest("Custom state toggle flips the value", {
    description = "The toggle flips States and what the window reads together, twice running",
    run = function()
        local NAME = "Custom state toggle"
        local KEY = "ALT-F7"
        local MODES = Constants.SWITCH_MODES

        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat, so nothing can be judged")
        end

        local saved = DebindPrivate.Switches["$state4"]
        AddTeardown(function()
            DebindPrivate.Switches["$state4"] = saved
            DebindPrivate.db.char.switches["$state4"] = nil
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        -- **`resetValue` and not `value`**, which is what makes the premise below hold on a
        -- second run: written as a value it is recomputed from what this character remembers,
        -- and this test leaves a remembered value behind every time it toggles.
        local options = { mode = MODES.MANUAL, resetValue = false }
        DebindPrivate.Switches["$state4"] = options

        -- Registered through a condition. What this test looks at is the toggle, not registration,
        -- and if a broken registration turned this one red as well neither could be read off the
        -- result. Macrotext rather than a spell because it binds whoever the character is.
        InsertAction({ type = Constants.MACROTEXT, value = "/say toggle test", key = KEY, ["$state4"] = false })
        ApplyBindings()

        local st = ReadSecureState("$state4")
        if not (st and st.present) then
            return Fail(NAME, "the premise is gone: the state used as the condition is not in States either")
        end
        if st.value ~= false then
            return Fail(NAME, format("the premise is gone: the stored value is off and States says %s", tostring(st.value)))
        end

        local frame = DebindPrivate.SwitchesUpdaterFrame
        frame:SetAttribute("$state4", "toggle")
        st = ReadSecureState("$state4")
        if not (st and st.value == true) then
            return Fail(NAME, "the first toggle did not turn States over")
        end

        frame:SetAttribute("$state4", "toggle")
        st = ReadSecureState("$state4")
        if not (st and st.value == false) then
            return Fail(NAME, "the second toggle did not take, writing the same attribute value again does not carry")
        end

        -- The mirror arrives on `C_Timer.After(0)` (`OnSwitchChanged`, `Misc.lua`). It is what
        -- the window reads, so a mirror that does not follow leaves the restricted side right and
        -- the screen lying.
        coroutine.yield(0)
        if options.value ~= false then
            return Fail(NAME, format("what the window reads did not follow (options.value=%s)", tostring(options.value)))
        end

        return Pass(NAME, "off -> on -> off, mirror included")
    end,
})

-- **The first place a name goes outside `$state1`..`$state5`.** Codegen turned back any name not in
-- `SWITCH_INDICES` at the door, so a condition naming one baked nothing at all. With the door gone,
-- the only thing that tells names apart is whether there is a definition.
--
-- All three are looked at in one place. Without the on case, the off case cannot be told from
-- "nothing was ever bound"; without the off case, the on case cannot be told from "the condition is
-- never looked at".
--
-- **What keeps this here is not those three but the last line.** `tests/boundkey_spec.lua` can see
-- the three. What it cannot see is **the path walked in combat**: writing an attribute on
-- `SwitchesUpdaterFrame` has the client call `_onattributechanged`, and the key is rebound in there,
-- while the harness stores the attribute and never calls that handler. A spec calling the body by
-- hand changes what is measured into "is the body right", and what is asked here is **whether the
-- write calls the handler**.
RegisterTest("Switch condition on a name outside the five", {
    description = "A name outside $state1..5 stands as a condition, and nothing goes out where there is no definition",
    run = function()
        local NAME = "Free switch name"
        local KEY = "CTRL-SHIFT-F10"
        local UNDEFINED_KEY = "CTRL-SHIFT-F11"
        local MODES = Constants.SWITCH_MODES

        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat, so nothing can be judged")
        end

        -- Why only the slot is swapped is in the comment on `Undefined $state inside a state's own
        -- expression` above. `$burst` will not be in a user's profile, and is put back even if it is.
        local saved = DebindPrivate.Switches["$burst"]
        local savedStored = DebindPrivate.db.char.switches["$burst"]
        AddTeardown(function()
            DebindPrivate.Switches["$burst"] = saved
            DebindPrivate.db.char.switches["$burst"] = savedStored
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, ["$burst"] = true })
        InsertAction({ type = Constants.SPELL, value = 585, key = UNDEFINED_KEY, ["$nodefinition"] = true })

        -- **Defined once and then flipped**, rather than re-planted on either side. Writing `value`
        -- into the definition stopped being a way to turn a switch on -- the ⚠ on the rename test
        -- above says why -- and flipping it is what the reader does anyway.
        DebindPrivate.Switches["$burst"] = { mode = MODES.MANUAL }
        DebindPrivate.SetSwitchValue("$burst", true)
        ApplyBindings()

        local whenOn = GetBindingAction(KEY, true) or ""
        if whenOn:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "$burst is defined and on and the key is %q, a name outside the five never reached codegen", whenOn))
        end

        DebindPrivate.SetSwitchValue("$burst", false)
        ApplyBindings()

        local whenOff = GetBindingAction(KEY, true) or ""
        if whenOff ~= "" then
            return Fail(NAME, format(
                "$burst went off and the key is still %q, the name got through and the value is not compared", whenOff))
        end

        -- A name with no definition. Dropping the condition outright sends that action out
        -- **wider**, so a failure here reads as "bound with no condition", not "not bound".
        local whenUndefined = GetBindingAction(UNDEFINED_KEY, true) or ""
        if whenUndefined ~= "" then
            return Fail(NAME, format(
                "an action on an undefined name went out as %q, the condition is gone and it fires always", whenUndefined))
        end

        -- **Two layers hold it back.** The marker takes that action out of `KeyMap` (the row goes
        -- red and the tooltip writes the name), and under it codegen bakes the condition as false.
        -- The line above is green with either one alive, and **which of the two held it is not a
        -- question for here**: what the marker answers is a pure function, so `tests/issue_spec.lua`
        -- looks at that. What this answers is whether that answer really keeps the key from being
        -- bound (the gate in `BuildKeyMap`).

        -- **The path walked in combat.** The two above are the insecure rebuild `ApplyBindings()`
        -- runs, and in combat that is deferred, so what settles the key again when a value moves is
        -- the restricted side: `SetSwitch` -> `DirtyFlags` -> `state-unitexists` -> the restricted
        -- `UpdateBindings`. For that path to know this name, codegen has to have filed the key under
        -- it in `DirtyKeys`; unfiled, the key does not come back until the fight ends.
        --
        -- Nothing is waited on. `SetAttribute` runs the handler on the spot and the restricted
        -- `SetBindingClick` binds immediately (`devdocs/reading-back-what-you-just-set.md`).
        DebindPrivate.SwitchesUpdaterFrame:SetAttribute("$burst", true)

        local afterToggle = GetBindingAction(KEY, true) or ""
        if afterToggle:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "turned on with no rebuild and the key is %q, in combat it would never come back", afterToggle))
        end

        return Pass(NAME, "$burst on -> bound / off -> released / undefined -> marked and released / on with no rebuild")
    end,
})

-- Test Cases: layer overrides (§4-6 to §4-9)
--
-- The definition is the account's and **only the behaviour is covered over by a layer.** Which
-- answer wins is read back off the table by `tests/switch_spec.lua`, and whether that answer really
-- reaches the key is `tests/boundkey_spec.lua`: the whole chain of `ApplySwitchResets` setting the
-- value again, codegen baking the winning row's `mode` and `expr`, and the state loop taking the key.
--
-- **Only one thing is left for here.** See below.
-----------------------------------------------------------

-- **Which name an override piles up under.** With this character missing from the character
-- layer's key, the next character reads somebody else's answer as its own.
--
-- **This one thing is what headless cannot see.** `tests/switch_spec.lua` looks at the same string,
-- but the GUID over there is one the shim made up, so what the spec confirms is only that the value
-- it planted came back. Whether a key built from a real `UnitGUID` is right is answered by the
-- client alone.
RegisterTest("Switch override: the layer key carries this character", {
    description = "The override key for this character and this spec carries the real GUID",
    run = function()
        local NAME = "Switch override layer key"

        local layerKey = DebindPrivate.GetSwitchLayerKey(
            DebindPrivate.GetLayerID(C_SpecializationInfo.GetSpecialization(), true))
        if not layerKey then
            return Fail(NAME, "no layer key for this character and this spec")
        end

        local guid = UnitGUID("player")
        if not layerKey:find(guid, 1, true) then
            return Fail(NAME, format(
                "the character layer's key is %q, without %q the next character reads somebody else's answer",
                layerKey, guid))
        end

        -- **The other half of the comparison.** The class layer's key must not carry the character.
        -- Without this, the line above cannot be told from "every layer key carries a GUID", and
        -- then another character of the same class cannot read the answer they are meant to share.
        local classKey = DebindPrivate.GetSwitchLayerKey(
            DebindPrivate.GetLayerID(C_SpecializationInfo.GetSpecialization(), false))
        if classKey and classKey:find(guid, 1, true) then
            return Fail(NAME, format(
                "the class layer's key is %q, with the character in it the same class cannot share an answer",
                classKey))
        end

        return Pass(NAME, format("char=%q / class=%q", layerKey, tostring(classKey)))
    end,
})

-- **Holds down why the custom-target action owes no registration.** A custom state's value lives in
-- `States`, which a rebuild wipes and refills from the registered ones only -- registration is what
-- carries the value across. A custom target's value lives in `UnitAliasMap` and UnitWatch's
-- `unitMap`, and nobody wipes either after they are created at load, so unlike the state action the
-- target action has nothing to register.
--
-- That rests on three things standing in three places. Any one of them changing loses a chosen
-- target at the next rebuild, silently:
--   * the rebuild prologue does not wipe those two tables (`UpdateBindings.lua`, the opening
--     `SecureHandlerExecute`)
--   * the loop that clears an alias nobody registered with `SetUnit(nil)` skips custom1/2, and
--     only those (same file)
--   * the header is created at load whether or not anything registered (`CreateUnitWatchHeader`,
--     `UnitWatch.lua`)
--
-- `"player"` is the target because it is a valid token, is not the group kind so it does not go
-- down the name-tracking branch, and exists for anyone alone. Writing the attribute instead of
-- pressing the key is the same door the action goes through (`*attribute-frame` is UnitWatch,
-- `*attribute-name` is `custom1`).
--
-- **And that door is why this stays.** The write lands on the UnitWatch header, and
-- `tests/restricted.lua` replays **only the driver's** bodies -- every other header has its own
-- managed environment in the game, and replaying its bodies into the driver's would put their
-- globals in the wrong table. So the one thing this measures is the one thing that harness declines
-- to have an opinion about.
RegisterTest("Custom target survives a rebuild", {
    description = "An @custom1 that was set is still there after a rebuild",
    run = function()
        local NAME = "Custom target survives"
        local KEY = "CTRL-F6"

        if InCombatLockdown() then
            return Fail(NAME, "both setting it and rebuilding are deferred in combat, so nothing can be judged")
        end

        local previous = DebindPrivate.Units and DebindPrivate.Units.custom1
        AddTeardown(function()
            if not InCombatLockdown() then
                DebindPrivate.UnitWatch:SetAttribute("custom1", previous or "none")
            end
        end)

        -- The action is stood up as well. What is being asked is whether the value survives with
        -- no registration **while that action is in the map**, and a rebuild without it is not
        -- standing where the question is.
        InsertAction({ type = Constants.SETCUSTOM, value = 1, key = KEY })
        ApplyBindings()

        local action = GetBindingAction(KEY, true) or ""
        if action:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("the premise is gone: the targeting action never bound to the key (%q)", action))
        end

        DebindPrivate.UnitWatch:SetAttribute("custom1", "player")
        local u = ReadSecureUnit("custom1")
        if not (u and u.value == "player") then
            return Fail(NAME, format("the premise is gone: what was set never went into UnitAliasMap (%s)",
                u and format("%q", u.value) or "no answer"))
        end

        ApplyBindings()

        u = ReadSecureUnit("custom1")
        if not u then
            return Fail(NAME, "the secure environment gave no answer")
        end
        if u.value ~= "player" then
            return Fail(NAME, format("the rebuild cleared what was set (%q), a targeting action does not register the alias",
                u.value))
        end

        return Pass(NAME, "custom1 = player after the rebuild too")
    end,
})

-----------------------------------------------------------
-- Test Cases: Secure Handler Health
-----------------------------------------------------------

-- Whether a rebuild really reaches the secure environment. Cut, nothing raises and the bindings
-- freeze in the state last applied: the keys keep sending something out and only the state changes
-- stop, so the user has no words for it beyond "sometimes it does not work". The point is to make a
-- silent fault loud.
RegisterTest("Secure update path", {
    description = "UpdateBindings reaches the secure handler, measured by the handler having consumed state-unitexists",
    run = function()
        if InCombatLockdown() then
            return Fail("Secure update path", "UpdateBindings is deferred in combat, so nothing can be judged")
        end

        local driver = DebindPrivate.BindingDriver
        if not driver then return Fail("Secure update path", "no BindingDriver") end

        ApplyBindings()

        -- The last thing UpdateBindings does is state-unitexists=1, and the first thing the secure
        -- _onattributechanged does is put it back to 0. The handler runs synchronously, so anything
        -- other than 0 by the time we are here means the handler never ran at all. There is no
        -- confusing it with a resting 0, since 1 was just written.
        local value = driver:GetAttribute("state-unitexists")
        if value ~= 0 then
            return Fail("Secure update path", format(
                "state-unitexists=%s, it should be 0. the secure handler never ran, the bindings have stopped updating",
                tostring(value)))
        end

        return Pass("Secure update path", "the handler consumed it")
    end,
})

-- **The 0.2s beat runs only where there is something to measure**
-- (`devdocs/legacy/trimming-the-restricted-hot-paths.md`, item 3). A profile with no conditions at all
-- lets `RegisterUnitWatch` go, and one condition brings it back.
--
-- Headless can see **the decision only** (`plan.statePoll`, `tests/plan_spec.lua`). The
-- interpreter's `pollStates` writes the attribute itself, so it runs a pass whether or not the
-- frame is registered. Whether the registration really reached Blizzard's manager is answerable
-- here and nowhere else.
--
-- **It asks whether the key is still bound, in the same breath.** What this item rests on is that
-- a fixed-wiring key is bound once by the rebuild snippet and owes the poll nothing -- and
-- without checking that, the test would see the registration go and not see the key die with it.
RegisterTest("State poll follows what is measured", {
    description = "With nothing to measure the 0.2s beat is dropped, and one condition puts it back",
    run = function()
        local NAME = "State poll registration"
        local PLAIN = "CTRL-SHIFT-F10"
        local CONDITIONAL = "CTRL-SHIFT-F11"

        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat, so nothing can be judged")
        end

        local driver = DebindPrivate.BindingDriver
        if not driver then return Fail(NAME, "no BindingDriver") end

        -- One conditional action left behind by an earlier test and the beat is registered for
        -- reasons of its own. An empty layer is this test's premise, and it leaves one behind.
        CleanupActions()
        AddTeardown(CleanupActions)

        InsertAction({ type = Constants.SPELL, value = 585, key = PLAIN })
        ApplyBindings()

        if UnitWatchRegistered(driver) then
            return Fail(NAME, "a profile with no condition at all and the 0.2s beat is on")
        end

        local bound = GetBindingAction(PLAIN, true) or ""
        if bound:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("the beat was dropped and the key did not bind (%q)", bound))
        end

        -- **A different key.** Put on the same one, the unconditional action already covers the
        -- condition space, so the key stays fixed-wiring -- and a key like that registers no axis
        -- in `_measuredStates`. The condition would be in the profile with nothing measured for
        -- it, and this test would go quietly meaningless.
        InsertAction({ type = Constants.SPELL, value = 585, key = CONDITIONAL, combat = true })
        ApplyBindings()

        if not UnitWatchRegistered(driver) then
            return Fail(NAME, "a combat condition went in and the 0.2s beat did not come back")
        end

        return Pass(NAME, "the registration comes and goes with what there is to measure")
    end,
})

-- **The state pass measures a base axis only when the poll is the one asking**, and what tells the
-- two apart is the value written to `state-unitexists`. Blizzard's poll writes `exists or false`,
-- and the driver carries `unit = "player"`, so it writes `true`; our own wakes write a string or a
-- number. `UpdateAttrChangedHandler` reads that.
--
-- **That reading is the one thing the harness models rather than observes.** `tests/hover_spec.lua`
-- drives the same handler with the same values, but it is a stand-in writing `true` because this
-- comment says the client does. If the client ever wrote something else, every base axis would
-- quietly stop being measured between rebuilds, and nothing anywhere would say so.
--
-- So this asks the client. A wrong answer is written straight into `States` and the beat is given
-- its chance to put it back. Only the block behind the gate can, and no rebuild is run in between:
-- the rebuild's own pass opens the gate on `DirtyFlags.forceAll` and would answer for the wrong
-- reason.
RegisterTest("State pass: the beat re-measures what a wake does not", {
    description = "A value written under States is corrected by the 0.2s beat and not by a rebuild",
    run = function()
        local NAME = "Poll gate"
        local KEY = "CTRL-SHIFT-F2"

        if InCombatLockdown() then
            return Fail(NAME, "combat is what would be measured, and it would be measured true")
        end

        -- Something has to name `combat`, or it is not a measured axis and there is no line to
        -- correct it. This is also what keeps the beat registered (`WantsStatePoll`).
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        ApplyBindings()

        SecureHandlerExecute(DebindPrivate.BindingDriver, [[States["combat"] = true]])

        local wrong = ReadSecureState("combat")
        if not (wrong and wrong.value == true) then
            return Fail(NAME, "the wrong value did not go in, so nothing below is being measured")
        end

        local corrected = WaitUntil(function()
            local st = ReadSecureState("combat")
            return st and st.present and st.value == false
        end, 1)

        if not corrected then
            return Fail(NAME,
                "a second went by and States.combat is still the value written under it, so the beat never measured it")
        end

        return Pass(NAME, "the beat put combat back, so the poll opens the gate")
    end,
})

-----------------------------------------------------------
-- Test Cases: Hover Slot (live)
-----------------------------------------------------------

-- The one state that could not be checked by hand: **the cursor sits still on a unit frame and
-- the unit goes away.** No enter fires, no leave fires, and only the poll sees it. Reproducing
-- that in the world means waiting for a boss to despawn or an arena to swap -- a raid schedule,
-- not a check.
--
-- Owning the frame turns it into three attribute writes. Pointing it at a unit that does not
-- exist is, from the poll's side, indistinguishable from a unit that stopped existing: it reads
-- the attribute, asks `UnitExists`, and takes the same branch either way.
--
-- No mocks are involved. The test picks the unit token, so reality supplies both answers --
-- `player` exists, an unrecognised token does not.
-- A rebuild fills `States` afresh, and `unitframe` alone is a value that only enter and leave set,
-- so nobody fills it back in. Cleared, hover dies with the cursor still sitting on the frame and
-- only comes back if the mouse leaves and returns. One condition changing is enough to run a
-- rebuild, entering combat or changing form among them, so this is walked in real use.
--
-- **`GetHoverUnit()` alone cannot catch it.** Its counterpart `UnitAliasMap["hover"]` is not cleared
-- by a rebuild, so it stays "player" even where the bug is. Hence looking at leave: with the slot
-- gone, leave finds nothing to clear and simply goes out, and hover is left standing.
RegisterTest("Hover slot: survives a rebuild under a still cursor", {
    description = "The hover slot survives a rebuild that runs while hovering",
    run = function()
        local NAME = "Hover survives rebuild"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and rebuilding are both blocked in combat")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        -- The cursor stays where it is. Only the rebuild runs.
        --
        -- **Giving up no frame at all here is the stricter test.** The poll picks the frame back
        -- up, so a rebuild that did wipe the slot would have it refilled within a tick -- wait,
        -- and the comparison below reads the recovered value and passes. The rebuild finishes its
        -- own state pass before it returns, so if the slot went it is already empty on the next
        -- line. That is why this is the bare call and not `ApplyBindings`, which gives up a frame
        -- in `WaitForIdle`.
        DebindPrivate.UpdateBindings()

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after the rebuild, it should still be player", tostring(GetHoverUnit())))
        end

        -- Whether the slot is alive comes apart here. Gone, leave finds nothing to clear.
        HoverLeave(frame)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "hover=%s even after leave. that means the rebuild cleared the hover slot",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "survives the rebuild, and leave clears it properly")
    end,
})

RegisterTest("Hover slot: unit disappears under a still cursor", {
    description = "The hover slot empties when the unit alone disappears under a still cursor, and fills again when it comes back",
    run = function()
        local NAME = "Hover slot"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and writing attributes are both blocked in combat")
        end

        -- A hover binding has to exist, or the hover axis is never measured at all and the slot
        -- this reads stays empty. The test builds its own precondition rather than hoping for one.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        -- The cursor has not moved. Only the attribute changed, which is exactly the shape of a
        -- unit despawning under it.
        --
        -- **This is one of the two waits in the file that is really a wait.** Nothing is driving
        -- anything here: the change is only noticed when Blizzard's state driver next comes round,
        -- which is what this test exists to check. The limit is the ceiling, not the cost -- a
        -- passing run leaves as soon as the poll lands.
        SetFrameUnit(frame, UNIT_TOKEN_ABSENT)
        WaitForHoverSlot(false)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "the unit is gone and hover=%s. before the fix the reaction stayed behind",
                tostring(GetHoverUnit())))
        end

        -- The frame is deliberately not dropped when its unit goes away, so that this same poll
        -- can pick it back up. Without that, the slot would stay empty until the mouse moved.
        SetFrameUnit(frame, "player")
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format(
                "the unit came back and hover=%s. that means the poll threw the frame away",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "gone -> empty, back -> filled again")
    end,
})

-- When the cursor enters a frame whose registration has been dropped.
--
-- Dropping it does not take the wrapper off (`_hoverWrapped` in `FrameRegistry.lua`). Only the
-- topmost wrapper can be taken off and there is no guarantee that one is ours, so our
-- `setup_onenter` goes on running even on a frame that is no longer registered. What it does in
-- there is what dropping the registration actually amounts to.
--
-- Simply standing back will not do. Mouse focus is one at a time, so **the cursor being inside a
-- frame we do not track is itself proof that it is not inside the frame we last wrote down.** So the
-- slot is emptied. It is also the clean-up for a lost `OnLeave`.
--
-- **Why this stays here.** The value side is already seen by `tests/hover_spec.lua`, which runs the
-- same two snippets. What this test sees on top of that is one thing: whether **the real sandbox
-- allows** calling another body with `RunAttribute` from inside a wrapped script. Where it does not,
-- that branch dies with no error and no log.
RegisterTest("Hover slot: a deregistered frame stands the slot down", {
    description = "Entering a frame whose registration has been dropped empties the hover slot",
    run = function()
        local NAME = "Deregistered frame"

        if InCombatLockdown() then
            return Fail(NAME, "registering and unregistering a frame are both blocked in combat")
        end

        -- The hover axis is measured only where there is a hover condition, and that is what gives
        -- this slot a value to read.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = {} },
        })
        ApplyBindings()

        local tracked, trackedErr = CreateTestUnitFrame("player", "group")
        if not tracked then return Fail(NAME, trackedErr) end

        local dropped, droppedErr = CreateTestUnitFrame("player", "group")
        if not dropped then return Fail(NAME, droppedErr) end

        DebindPrivate.UnregisterFrame(dropped)
        if DebindPrivate.ccframes[dropped] ~= nil then
            return Fail(NAME, "the premise is gone: UnregisterFrame did not remove the row")
        end

        HoverEnter(tracked)
        AddTeardown(function() HoverLeave(tracked) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        -- The wrapper is still on, so our body runs here too.
        --
        -- **Nothing is waited on.** `SecureHandlerExecute` returns after running the body, and the
        -- slot not emptying is exactly the fault this test is looking for. Waiting could read a
        -- value the poll has since tidied and pass.
        HoverEnter(dropped)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "entered a frame we do not track and hover=%s. the old frame is still in the slot",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "entering a frame whose registration was dropped empties the slot")
    end,
})

--- The frames a click-cast test has to cover: one we made, and one of Blizzard's.
---
--- **Driving only our own frame would miss the thing that changed.** Blizzard's frames are the
--- ones whose `type1` the old routing took over, and they arrive through a different door --
--- `UpdateBlizzardFrames` rather than the Clique API -- so "it works on a frame the test built"
--- says nothing about them.
---
--- Blizzard's is skipped rather than failed when it is not registered: that is a user option
--- (`Options.blizzframes`), not a fault.
local function ClickCastTargets()
    local targets = {}

    local frame, err = CreateTestUnitFrame("player", "group")
    if not frame then return nil, err end
    targets[#targets + 1] = { label = "our frame", frame = frame }

    if PlayerFrame and type(DebindPrivate.ccframes[PlayerFrame]) == "table" then
        -- Asked for where it already is. Moving or resizing one of Blizzard's frames to make it
        -- convenient would be the addon reaching into it, which is the thing being tested away.
        PlayerFrame.debindTestLeaveAlone = true
        targets[#targets + 1] = { label = "PlayerFrame", frame = PlayerFrame, blizzard = true }
    end

    return targets
end

-- Click-casting decides at the click now, in a wrapper on the frame rather than in attributes
-- stamped on it ahead of time. Clicking is the only way to reach that decision.
-- The claim the routing change was made for: a registered frame's own action slots are not
-- somewhere this addon writes. They used to be -- click-casting worked by overwriting `type1`
-- and remembering what had been there -- so this could not have been asserted before now.
--
-- No click needed; it only reads.
RegisterTest("Click-cast: the frame's own slots stay ours to not touch", {
    description = "Nothing of ours is written to type1/2/3 on a registered frame, Blizzard's own included",
    run = function()
        local NAME = "Click-cast non-invasion"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        ApplyBindings()

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        local checked = {}
        for _, target in ipairs(targets) do
            local frame = target.frame

            -- Ours is a suffix nobody else uses, and it is what carries the click to us.
            if frame:GetAttribute("*type-debind1") ~= "click" then
                return Fail(NAME, format("%s: *type-debind1=%s, it should be click",
                    target.label, tostring(frame:GetAttribute("*type-debind1"))))
            end

            -- And nothing of ours in the slots that belong to the frame. "click" is the value the
            -- old routing wrote; a frame of its own may legitimately hold other types.
            for i = 1, 5 do
                for _, attr in ipairs({ "*type" .. i, "type" .. i }) do
                    if frame:GetAttribute(attr) == "click" then
                        return Fail(NAME, format(
                            "%s: click is still on %s. the old routing still writes to that slot",
                            target.label, attr))
                    end
                end
            end
            checked[#checked + 1] = target.label
        end

        return Pass(NAME, table.concat(checked, ", ") .. ", and the slots that are not ours are empty")
    end,
})

-- **A registered frame gets both edges, and the wrapper picks between them.**
--
-- The release is the edge a frame's own actions run on: `SECURE_ACTIONS.menu` acts on the release
-- and returns while `down` is true, so a frame missing it loses its unit menu outright, with no
-- error to say so. `target` does not gate on the edge, which is why targeting went on working and
-- hid that through several releases. Neither is tied to a button, since
-- `Enum.ClickBindingInteraction.Target` and `.OpenContextMenu` are both movable in Blizzard's
-- click binding window, which is why this asks for the whole release edge rather than one
-- button's.
--
-- **The press has to be there too, which is the reverse of what this case used to ask.** It was
-- written when `unitframeUseMouseDown` had just been removed, over a claim that registering an
-- edge another addon never asked for runs its `OnClick` twice per click. That claim is false:
-- `SecureActionButton_OnClick` computes
-- `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)`, so a frame acts on
-- exactly one edge however many are delivered. Delivery and action are separate, and the option
-- is back with three answers, one of them the press.
--
-- So a narrowing here is a silent death in either direction: without the press, choosing to cast
-- on mouse down does nothing at all; without the release, the default does. And narrowing to
-- per-button forms takes the middle and thumb buttons off the frame entirely, since a frame
-- delivers only what it is registered for.
--
-- The registration call is captured on a frame the test owns, because there is no API that asks a
-- frame which clicks it is registered for (`SimpleButtonAPIDocumentation.lua` has the setter and
-- no getter). Shadowing the method on our own frame leaves every other frame alone, and the real
-- one is still called.
RegisterTest("Click-cast: a registered frame carries both click edges", {
    description = "A registered frame carries both the press edge and the release edge",
    run = function()
        local NAME = "Click edges"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and RegisterForClicks are both blocked in combat")
        end

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        local captured
        local realRegisterForClicks = frame.RegisterForClicks
        frame.RegisterForClicks = function(self, ...)
            captured = { ... }
            return realRegisterForClicks(self, ...)
        end
        AddTeardown(function() frame.RegisterForClicks = nil end)

        DebindPrivate.UpdateRegisteredClicks(frame)

        if not captured then
            return Fail(NAME, "the registration itself never ran")
        end

        local function Registered(want)
            for _, got in ipairs(captured) do
                if got == want then return true end
            end
            return false
        end

        local seen = table.concat(captured, " ")

        if not Registered("AnyUp") then
            return Fail(NAME, format(
                "[%s] has no release edge. that edge is the only place the unit menu runs, so a button "
                .. "carrying the menu goes dead, and anyone casting on release gets no click at all", seen))
        end

        if not Registered("AnyDown") then
            return Fail(NAME, format(
                "[%s] has no press edge. anyone casting on press gets no click "
                .. "at all", seen))
        end

        return Pass(NAME, seen)
    end,
})

RegisterTest("Click-cast: the frame's wrapper picks a winner", {
    description = "A unit frame click reaches the wrapper and picks the record the condition matches, on our frame and on Blizzard's",
    run = function()
        local NAME = "Click-cast winner"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        ApplyBindings()

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        local seen = {}
        for _, target in ipairs(targets) do
            -- Hover is what the record is conditioned on, and the click-cast path reads it off the
            -- frame rather than the cache -- so it has to be under the cursor for real.
            HoverEnter(target.frame)
            AddTeardown(function() HoverLeave(target.frame) end)
            WaitForHoverSlot(true)

            local ran, rerr = EvalClickCast(target.frame, 3, 0)
            if not ran then return Fail(NAME, format("%s: %s", target.label, rerr)) end
            WaitForEvalAnswer()

            if LastWinner() == nil then
                return Fail(NAME, format("%s: it picked nothing, either nothing matched or "
                    .. "no key is registered for that button and modifier", target.label))
            end
            seen[#seen + 1] = format("%s=%d", target.label, LastWinner())

            HoverLeave(target.frame)
            WaitForHoverSlot(false)
        end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})

-- A key whose records all carry a hover condition holds no key-binding record, so there is no key
-- role to take and hand back and the state loop has nothing to decide for it. `UpdateBindingsMap`
-- therefore registers none of its axes for measurement -- the click path measures them at the
-- press, and click-casting does not even take the hover from the cache.
--
-- **What this holds is that narrowing the registration did not narrow the judgement.** With
-- nothing measured on the key's account, a press still has to ask about `combat`. The membership
-- assertion has to sit next to it: widen the gate back and the registration returns while the
-- judgement half goes on passing, so on its own it would not notice.
RegisterTest("Click-cast only: judged at the press with nothing measured for it", {
    description = "A click-cast only key drops out of the state loop's table and still judges its conditions",
    run = function()
        local NAME = "Click-cast only"
        local KEY = "BUTTON3"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_ALL,
            combat = true,
        })
        ApplyBindings()

        ReadKeyMembership(KEY)
        local m = WaitForMembership()
        if not m then return Fail(NAME, "the restricted environment sent no answer") end

        -- The positive side is checked first. "Not state driven" is true of a key whose records
        -- never went out at all.
        if not m.clickCast then
            return Fail(NAME, "not in ClickCastKeys, and not because it was dropped: no record went out")
        end
        if m.stateDriven then
            return Fail(NAME, "it is in StateDrivenBindings, and with not one record taking the key "
                .. "the state loop still sweeps it every tick")
        end

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end
        local target = targets[1]

        -- The record carries hover as a condition and the click-cast path reads that off the frame
        -- rather than a cache, so the cursor really has to be on it.
        HoverEnter(target.frame)
        AddTeardown(function() HoverLeave(target.frame) end)
        WaitForHoverSlot(true)

        local function judge(inCombat)
            SetMockState("combat", inCombat)
            local ran, rerr = EvalClickCast(target.frame, 3, 0)
            if not ran then return false, rerr end
            WaitForEvalAnswer()
            return true, LastWinner()
        end

        local ran, hit = judge(true)
        if not ran then return Fail(NAME, tostring(hit)) end
        if hit == nil then
            return Fail(NAME, "set to combat and it still picked nothing, cutting the registration cut the judging with it")
        end

        local ran2, miss = judge(false)
        if not ran2 then return Fail(NAME, tostring(miss)) end
        if miss ~= nil then
            return Fail(NAME, format("out of combat and it picked %s, the combat condition is not being looked at",
                tostring(miss)))
        end

        return Pass(NAME, format("click-cast only: %s in combat, nothing out of it", tostring(hit)))
    end,
})

-- The point of judging on the frame instead of ahead of it: when nothing matches we return nil,
-- the button name is left alone, and the click carries on into whatever the frame itself does.
-- On the old path the frame's own `type` had been overwritten, so a click that matched nothing
-- did nothing at all -- silently, which is the shape of fault this addon keeps running into.
RegisterTest("Click-cast: a click that matches nothing falls through", {
    description = "Where nothing matches, the frame's own action goes out untouched: the dynamic fallback",
    run = function()
        local NAME = "Click-cast fallback"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        -- **`LastWinner()` answers only with the probes on.** `PROBE.Winner` is removed outright on
        -- the release branch, so without them this test's "did it pick nothing" check reads nil every
        -- time and passes: it stays quiet even where a missing condition makes it pick the wrong
        -- record.
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "turning the probes on failed: " .. tostring(probesErr))
        end

        -- **The left button, because that is where falling through means something.** A unit
        -- frame's left click is targeting; what this checks is that declining hands the click
        -- back to it. (A hover binding may take BUTTON1 -- the button is only refused without
        -- one.)
        --
        -- Cannot match: the record wants combat and the state says otherwise. The binding still
        -- exists, so the frame is still routed and the wrapper still runs -- which is the point.
        -- A test with no binding at all would pass without the wrapper ever deciding anything.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON1",
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_GROUP,
            combat = true,
        })
        ApplyBindings()
        SetMockState("combat", false)

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        -- **Our own frame only.** The Blizzard target could only assert "nothing was chosen", and
        -- a wrapper that was never installed gives that same answer.
        --
        -- **What is asserted is the decline, not the carrying-on.** Declining is answering nil,
        -- which leaves the button name alone so the click continues into the frame's own handler
        -- -- and only a real click can show that continuing. Answering nil is the half this addon
        -- decides; the rest is the game's.
        for _, target in ipairs(targets) do
            if not target.blizzard then
                HoverEnter(target.frame)
                AddTeardown(function() HoverLeave(target.frame) end)
                WaitForHoverSlot(true)

                local ran, rerr = EvalClickCast(target.frame, 1, 0)
                if not ran then return Fail(NAME, format("%s: %s", target.label, rerr)) end

                -- **The answer, not a winner.** Nothing is expected to be chosen here, and
                -- `WaitForWinner` would sit out its whole limit on every target proving it.
                WaitForEvalAnswer()

                if LastWinner() ~= nil then
                    return Fail(NAME, format(
                        "%s: nothing matched and it picked #%d. the combat check may not be in place",
                        target.label, LastWinner()))
                end

                if LastEvalAnswer() ~= nil then
                    return Fail(NAME, format(
                        "%s: it picked nothing and returned %q. that changes the button name, so the frame's "
                        .. "own action never goes out",
                        target.label, tostring(LastEvalAnswer())))
                end

                HoverLeave(target.frame)
                WaitForHoverSlot(false)
            end
        end

        return Pass(NAME, "no match -> picks nothing and changes no name (it falls through to the frame)")
    end,
})

-----------------------------------------------------------
-- Test Cases: State Injection (live)
-----------------------------------------------------------

-- **Kept here.** The decision is headless now (`tests/eval_spec.lua`), and what stays is the
-- half that needs the client: `GetBindingAction` reporting the key, and the injection landing
-- between the measurement and the comparison inside a snippet that really compiled.
-- The reason the kit exists. A combat-only binding is reachable only in combat, and in combat
-- nothing outside can drive it -- lockdown stops the clicking, the binding and the attribute
-- writes. So the one state where this code matters is the one state where it cannot be checked.
--
-- Overriding `States.combat` while the client is at peace breaks that. The decision runs its real
-- path; the client, not actually fighting, never locks anything down.
--
-- What is checked is the game's own answer: `SetBindingClick` inside the snippet registers an
-- override binding, and `GetBindingAction` reads back what the key is bound to. Nothing about the
-- verdict is inferred from the injection.
RegisterTest("State injection: combat-only binding", {
    description = "Injecting combat really does bind the combat-only binding",
    run = function()
        local NAME = "Combat injection"
        local KEY = "CTRL-SHIFT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "in real combat there is no telling the injected result from the real one")
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        ApplyBindings()

        -- No wait after either: `SetMockState` ends in a rebuild, and a rebuild runs the state
        -- pass and the binding inside the call.
        SetMockState("combat", false)
        local atPeace = GetBindingAction(KEY, true) or ""

        SetMockState("combat", true)
        local inCombat = GetBindingAction(KEY, true) or ""

        if inCombat == atPeace then
            return Fail(NAME, format(
                "combat was turned over and the binding is unchanged (%q). the injection never reached the snippet",
                inCombat))
        end

        if inCombat:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("combat=true and it is %q, it should be CLICK", inCombat))
        end

        -- Back to peace: the binding has to go away again. Without this the test would pass on a
        -- key that was simply bound the whole time.
        SetMockState("combat", false)
        local again = GetBindingAction(KEY, true) or ""

        if again ~= atPeace then
            return Fail(NAME, format("combat was put back and it is %q, it should be %q", again, atPeace))
        end

        return Pass(NAME, format("drove the combat path from outside combat (%s)", inCombat))
    end,
})

-- **The one half of a settled command the harness cannot reach.** Which keys stop being
-- state-driven, and that the record and the click-time button go with them, is decided in pure
-- code and asked in `tests/boundkey_spec.lua`. What is left for the client is whether an override
-- the addon files from **outside** the restricted environment actually takes: every other binding
-- this addon puts out goes through a frame handle, and `SetOverrideBinding` called from our own
-- Lua is a path nothing here had walked before.
--
-- The state loop is also asked, and asked with the one driver that carries no rebuild: a `forceAll`
-- pass poked straight at the driver. Anything that runs a rebuild files the override again, so a
-- key the loop had taken away would read as one that was never touched.
RegisterTest("Settled command: filed from outside the restricted environment", {
    description = "An unconditional command reaches the key without the update loop",
    run = function()
        local NAME = "Settled command"
        local KEY = "CTRL-SHIFT-F12"
        local COMMAND = "TOGGLEWORLDMAP"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be filed")
        end

        InsertAction({ type = Constants.COMMAND, value = COMMAND, key = KEY })
        ApplyBindings()

        local bound = GetBindingAction(KEY, true) or ""
        if bound ~= COMMAND then
            return Fail(NAME, format("the key answers %q, it should answer %q", bound, COMMAND))
        end

        if DebindPrivate.StateDrivenKeys and DebindPrivate.StateDrivenKeys[KEY] then
            return Fail(NAME, "the key is still in the update loop, which has nothing to decide for it")
        end
        if DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY] then
            return Fail(NAME, "the key got a click-time button that no click can arrive under")
        end

        -- A pass of the state loop **without a rebuild behind it**, which is the only way this
        -- read means anything: every helper that pokes a state here ends in `ApplyBindings`, and a
        -- rebuild files the override again, so the key would answer with the command whatever the
        -- loop did to it in between.
        --
        -- `forceAll` and the `1` are the pair `ApplyBindingPlan` closes a rebuild with, minus the
        -- rebuild. It is the widest pass there is: every key in `StateDrivenBindings` is re-decided
        -- and the ones with no matching record are handed back with `ClearBinding`. This key is not
        -- in that table, so what this asks is that the pass leaves an override it never filed alone.
        SecureHandlerExecute(DebindPrivate.BindingDriver, [[
            DirtyFlags.forceAll = true
            self:SetAttribute("state-unitexists", 1)
        ]])

        local afterPass = GetBindingAction(KEY, true) or ""
        if afterPass ~= COMMAND then
            return Fail(NAME, format("a state pass left the key at %q", afterPass))
        end

        return Pass(NAME, format("%s is on the key and the loop never sees it", COMMAND))
    end,
})

-- Turning probes on rebuilds every registered snippet from its raw text, including the click
-- wrapper -- the hottest path here and the one that decides which record wins. A rebuild that
-- produced a body the restricted environment refuses would leave the addon looking loaded and
-- doing nothing, so what is checked is not that the rebake returned, but that the same judgement
-- still runs afterwards.
RegisterTest("Snippet probes: rebaked snippets still decide", {
    description = "Turning the probes on and rebaking the snippets leaves the condition judging as it was",
    run = function()
        local NAME = "Probe rebake"
        local KEY = "CTRL-SHIFT-F8"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            combat = true,
        })
        ApplyBindings()

        -- No wait after either: `SetMockState` ends in a rebuild, and a rebuild runs the state
        -- pass and the binding inside the call.
        SetMockState("combat", false)
        local atPeace = GetBindingAction(KEY, true) or ""

        SetMockState("combat", true)
        local inCombat = GetBindingAction(KEY, true) or ""

        if inCombat == atPeace then
            return Fail(NAME, format("the condition does not take after the rebake (still %q)", inCombat))
        end

        if inCombat:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("%q after the rebake, it should be CLICK", inCombat))
        end

        return Pass(NAME, "judging is unchanged with the probes on")
    end,
})

-----------------------------------------------------------
-- Test Cases: The unit axes, measured for real
-----------------------------------------------------------

-- The emit-and-match half -- registering an axis, measuring it every tick, comparing it in the
-- snippet -- reads headless now: `tests/eval_spec.lua` asks it at the press and
-- `tests/boundkey_spec.lua` asks it at the key. What is left here is the axis nothing outside the
-- game can put a unit into.

-- **Kept here.** The axis itself is headless (`tests/eval_spec.lua`, the life axis) and so is the
-- living half (`tests/boundkey_spec.lua`). This is the dead half, which no living session can
-- produce and no world a spec writes down can prove.
-- The other half, which no living session can produce. `player-dead` is injected at the same
-- point `combat` is -- right after the snippet measures it, before it stores it -- so the update
-- loop runs its real path and only the value it lands on differs.
RegisterTest("State injection: dead flips a binding", {
    description = "Injecting dead really does bind the binding conditioned on it",
    run = function()
        local NAME = "Dead injection"
        local KEY = "CTRL-SHIFT-F10"

        if InCombatLockdown() then
            return Fail(NAME, "in combat there is no telling the injected result from the real one")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { player = { dead = true } },
        })
        ApplyBindings()

        SetMockState("player-dead", false)
        local whenAlive = GetBindingAction(KEY, true) or ""

        SetMockState("player-dead", true)
        local whenDead = GetBindingAction(KEY, true) or ""

        if whenDead == whenAlive then
            return Fail(NAME, format(
                "alive/dead was turned over and the binding is unchanged (%q). the injection never reached the snippet", whenDead))
        end

        if whenDead:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("dead=true and it is %q, it should be CLICK", whenDead))
        end

        -- It also checks that putting it back makes the binding go. Without that, a key that was
        -- bound the whole time passes too.
        SetMockState("player-dead", false)
        local again = GetBindingAction(KEY, true) or ""

        if again ~= whenAlive then
            return Fail(NAME, format("it was put back and it is %q, it should be %q", again, whenAlive))
        end

        return Pass(NAME, format("took the key by injecting dead (%s)", whenDead))
    end,
})

-- The hover condition now rides the unit column (`t.units["hover"]`) instead of its own pair of
-- record fields. What that has to keep doing is decide **key ownership**: a hover-conditioned
-- keyboard key is ours only while the cursor is on a matching frame, and that judgement is made
-- by the update loop before the key is ever pressed.
RegisterTest("Hover condition owns the key through the unit column", {
    description = "The hover condition still takes and releases the key now that it lives in the unit column",
    run = function()
        local NAME = "Hover ownership"
        local KEY = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { hover = { reaction = Constants.REACTION_HELP } },
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        -- Registering a frame can leave a rebuild queued behind it, and that one lands a frame
        -- later. Everything else on this path has already happened.
        WaitForIdle()

        local before = GetBindingAction(KEY, true) or ""
        if before:sub(1, 6) == "CLICK " then
            return Fail(NAME, format(
                "%q is bound before any hover. the hover condition may have been left out of the emission", before))
        end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        local hovering = GetBindingAction(KEY, true) or ""
        if hovering:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "put on a friendly frame and it is %q. t.units[\"hover\"] did not match", hovering))
        end

        HoverLeave(frame)
        WaitForHoverSlot(false)

        local after = GetBindingAction(KEY, true) or ""
        if after ~= before then
            return Fail(NAME, format("%q even after leave, it should be %q", after, before))
        end

        return Pass(NAME, format("hover -> %s, leave -> released", hovering))
    end,
})

-- `frameTypes` kept its own field, and with the hover pair gone it lost the `t.hover` wrapper
-- that used to stand in front of it -- it carries its own "is there a frame at all" guard now.
-- What this pins is that the guard narrows: a frame of the wrong kind must not hand the key over.
RegisterTest("Hover frame types still narrow on their own", {
    description = "A frame type limit narrows even while carrying its own existence check",
    run = function()
        local NAME = "Hover frame types"
        local KEY = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_BOSS,
        })
        ApplyBindings()

        -- The condition says boss and what is put up is group. The unit is there and only the type
        -- fails to match.
        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        local wrongType = GetBindingAction(KEY, true) or ""
        if wrongType:sub(1, 6) == "CLICK " then
            return Fail(NAME, format(
                "limited to boss and %q bound on a group frame. frameTypes did not take", wrongType))
        end

        return Pass(NAME, format("does not take where the type fails to match (%q)", wrongType))
    end,
})

-- **Only the game runs this one.** `clickcast_register` is a snippet body, and the takeover it
-- performs happens inside the restricted environment on tables the headless harness never builds.
-- `tests/frames_spec.lua` covers the other half -- what `RegisterFrame` works the type out to.
--
-- What is pinned: an addon reaching us through both doors gets the same answer whichever order it
-- uses them in. It did not. `ClickCastFrames` writes `unknown` because the Clique protocol carries
-- no kind, and this body used to stand down on finding any row at all -- so an addon that registers
-- through the header before it styles the child came out a group frame, while one that styles first
-- kept the `unknown` the styling pass had left behind.
RegisterTest("Header registration takes a frame back from the click-cast table", {
    description = "Header registration takes back a frame ClickCastFrames got to first",
    run = function()
        local NAME = "Header takeover"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        -- `true` is what unit frame addons actually put in `ClickCastFrames`, and it is not one of
        -- our category names -- so this is the door that yields `unknown`.
        local frame, err = CreateTestUnitFrame(UNIT_TOKEN_ABSENT, true)
        if not frame then return Fail(NAME, err) end

        local before = DebindPrivate.ccframes[frame]
        if before.frameType ~= Constants.FRAMETYPE_UNKNOWN then
            return Fail(NAME, format("the first registration should be unknown and it was %s", tostring(before.frameType)))
        end

        -- Exactly what a header does: hand the button over on the driver and run the body.
        SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_cc", frame)
        SecureHandlerExecute(DebindPrivate.BindingDriver, [[
            self:SetAttribute("clickcast_button", self:GetFrameRef("debindtest_cc"))
            self:RunAttribute("clickcast_register")
        ]])

        -- `UnregisterFrame` skips `hd` rows, so the header's own door is the only way back out.
        AddTeardown(function()
            SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_cc", frame)
            SecureHandlerExecute(DebindPrivate.BindingDriver, [[
                self:SetAttribute("clickcast_button", self:GetFrameRef("debindtest_cc"))
                self:RunAttribute("clickcast_unregister")
            ]])
        end)

        local after = DebindPrivate.ccframes[frame]
        if type(after) ~= "table" then
            return Fail(NAME, format("the row disappeared after the header registration (%s)", tostring(after)))
        end
        if not after.hd then
            return Fail(NAME, "the header registration stood down. hd never came on")
        end
        if after.frameType ~= Constants.FRAMETYPE_GROUP then
            return Fail(NAME, format("unknown was not covered over. frameType=%s", tostring(after.frameType)))
        end

        return Pass(NAME, "the header took an unknown row back as group")
    end,
})

-- **Another addon takes the name `ClickCastFrames`, and we take it back.** The harness cannot see
-- this: that table is stood up by `DebindCliqueFake`, which is only read once `DebindPublic` is
-- there, and the runner loads neither.
--
-- Three questions. Does the name come back; does a frame handed over **before** the theft still
-- answer afterwards (which is why the store lives outside the table); and is a second reclaim
-- harmless. The last one is the quiet one: putting a fresh table over a name that is already ours
-- throws away everything taken so far, and the `nil` another addon writes to reclaim a frame then
-- reaches nothing.
RegisterTest("Click-cast table: the name comes back, and twice is not twice", {
    description = "We take ClickCastFrames back when someone else has it, and calling twice after that is not twice",
    run = function()
        local NAME = "ClickCastFrames reclaim"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end
        if not DebindPrivate.ReclaimClickCastFrames then
            return Fail(NAME, "DebindCliqueFake did not come up, there is no name to take back on this board")
        end

        local ours = _G.ClickCastFrames
        if type(ours) ~= "table" then
            return Fail(NAME, format("ClickCastFrames is not a table (%s)", type(ours)))
        end
        AddTeardown(function() _G.ClickCastFrames = ours end)

        -- One frame in through our door before the theft. `CreateTestUnitFrame` calls
        -- `RegisterFrame` outright, so the write below is what goes through the table.
        local frame, err = CreateTestUnitFrame(UNIT_TOKEN_ABSENT, "group")
        if not frame then return Fail(NAME, err) end
        _G.ClickCastFrames[frame] = true
        if not _G.ClickCastFrames[frame] then
            return Fail(NAME, "a frame put into the table does not read back, somebody else's sweep cannot pass through us")
        end

        -- Somebody puts their own proxy over it, in the shape the real one has: a fresh table, a
        -- store of its own in an upvalue, no chaining.
        local theirs = setmetatable({}, {
            __index = function() return nil end,
            __newindex = function() end,
        })
        _G.ClickCastFrames = theirs

        DebindPrivate.ReclaimClickCastFrames()
        local reclaimed = _G.ClickCastFrames
        if reclaimed == theirs then
            return Fail(NAME, "the name was not taken back, every registration after this goes into somebody else's table")
        end
        if not reclaimed[frame] then
            return Fail(NAME, "the table we took back forgot the frames taken in before it was lost")
        end

        -- And on a name that is already ours, nothing at all should happen.
        DebindPrivate.ReclaimClickCastFrames()
        if _G.ClickCastFrames ~= reclaimed then
            return Fail(NAME, "a table was put on a name that is already ours, which throws away the list taken in")
        end
        if not _G.ClickCastFrames[frame] then
            return Fail(NAME, "the second reclaim cleared the frames taken in")
        end

        return Pass(NAME, "taken back, what was taken in was kept, and the second time is a no-op")
    end,
})

-- **Does the hook stand on a real secure frame.** What the harness sees is the rule: narrowed, we
-- put it back (`tests/frames_spec.lua`). What only the game answers is whether hanging
-- `hooksecurefunc` on the frame's own method takes at all, and whether the call that puts it back
-- is refused for taint.
RegisterTest("Click-cast: another addon narrowing the frame is put back", {
    description = "We put RegisterForClicks and EnableMouseWheel back where someone else narrowed them",
    run = function()
        local NAME = "Click input reasserted"

        if InCombatLockdown() then
            return Fail(NAME, "RegisterForClicks is blocked in combat")
        end

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        -- There is no getter for what was last registered, so what is measured is the call our
        -- side makes to put it back.
        local seen
        local realRegisterForClicks = frame.RegisterForClicks
        frame.RegisterForClicks = function(self, ...)
            seen = table.concat({ ... }, " ")
            return realRegisterForClicks(self, ...)
        end
        AddTeardown(function() frame.RegisterForClicks = nil end)

        -- The call another click-casting engine makes to write its own edge on. A hook runs after
        -- the original returns, so this one line has to drag our own reassert along with it.
        frame:RegisterForClicks("AnyUp")
        if not seen then
            return Fail(NAME, "our hook never ran, the narrowed frame stays as it is")
        end
        if not (strfind(seen, "AnyUp", 1, true) and strfind(seen, "AnyDown", 1, true)) then
            return Fail(NAME, format("what was put back is [%s], one edge does not arrive", seen))
        end

        -- And the wheel. That addon turns it off in the **line after** the one that narrows the
        -- clicks, so hooking only the clicks leaves it off a moment after we put things back.
        seen = nil
        frame:EnableMouseWheel(false)
        if not seen then
            return Fail(NAME, "the call that turned the wheel off never called the restore")
        end

        return Pass(NAME, seen)
    end,
})

-- **`EQUIPSLOT` reaches the game as an item, and the shape of the value is the whole of it.**
-- `tests/eval_spec.lua` already holds the emitted attribute byte for byte, so what is left for the
-- game is the half no headless run can see: that `SecureCmdItemParse` really reads a bare number
-- as an inventory slot rather than an item id. Getting that wrong fires item 13 -- a real item,
-- with a real effect -- instead of the trinket, and nothing raises.
RegisterTest("Equipment slot: the attribute names a slot, not an item", {
    description = "슬롯 액션이 게임 쪽 파서에 슬롯으로 읽히는지",
    run = function()
        local NAME = "Equip slot attribute"
        local KEY = "CTRL-SHIFT-F8"
        local SLOT = 13

        InsertAction({ type = Constants.EQUIPSLOT, value = SLOT, key = KEY })
        ApplyBindings()

        local binding = GetNthBinding(KEY, 1)
        local button = binding and binding.clickbutton
        if not button then
            return Fail(NAME, "the action got no click button name")
        end

        local attr = DebindPrivate.DefaultClickFrame:GetAttribute("*item-" .. button)
        if attr ~= tostring(SLOT) then
            return Fail(NAME, format("*item- is %q, it should be %q", tostring(attr), tostring(SLOT)))
        end

        -- **The game's own parser, asked directly.** This is the claim the whole type rests on and
        -- the only place it can be checked: `name` comes back as the link of what is worn in that
        -- slot, `bag` as nil, and `slot` as the number we passed. An item id would answer the
        -- other way round.
        local name, bag, slot = SecureCmdItemParse(attr)
        if bag ~= nil or tostring(slot) ~= tostring(SLOT) then
            return Fail(NAME, format("parsed as bag=%s slot=%s, it should be bag=nil slot=%d",
                tostring(bag), tostring(slot), SLOT))
        end

        -- `name` is nil when nothing is worn there, and that is not a fault -- the binding is still
        -- correct, it just has nothing to fire today. Reported so a run in an empty slot reads as
        -- what it is rather than as a pass that measured nothing.
        return Pass(NAME, format("slot %d, worn=%s", SLOT, tostring(name)))
    end,
})

-----------------------------------------------------------
-- Test Cases: Click-time keys (what the press decides)
-----------------------------------------------------------

-- A key whose conditions cover the whole space is wired once, at build time, and the update loop
-- never looks at it again -- so **everything about it that can be wrong is wrong at the press**,
-- and nothing outside these two tests looks there. `GetBindingAction` answers the same `CLICK`
-- for a key that picks the right action and for one that picks nothing at all.
--
-- Both use a key carrying `[combat]` and `[nocombat]`, which is the smallest binding whose
-- conditions leave no gap: there is no state in which we would hand the key back.

-- **Kept here.** `tests/eval_spec.lua` runs the same `EVAL_SNIPPET` against the same records,
-- so what this adds is the two things it cannot reach: a body the sandbox really compiled, and
-- `GetBindingAction` agreeing that the key arrives under the name we bound.
RegisterTest("Click-time key: the press picks the record the state matches", {
    description = "On a key whose wiring is fixed, the state at the press is what picks the winner",
    run = function()
        local NAME = "Click-time winner"
        local KEY = "CTRL-SHIFT-F6"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "combat"',
            key = KEY, name = "combat", combat = true })
        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "peace"',
            key = KEY, name = "peace", combat = false })
        ApplyBindings()

        -- Both sides are checked. On one alone, an implementation that never looks at the condition
        -- and always picks the same record passes.
        local picked = {}
        for _, want in ipairs({ true, false }) do
            SetMockState("combat", want)

            -- **Read again every time.** `SetMockState` runs a rebuild at the end, which replaces
            -- the KeyMap array. Held once outside the loop, the second pass reads a dead table.
            local records = GetKeyBindings(KEY)
            if not records or #records ~= 2 then
                return Fail(NAME, format("there should be 2 records, there are %d",
                    records and #records or 0))
            end

            -- Whether it is bound comes first. Without this comparison, a state where the evaluation
            -- is right and nothing is bound to any key passes. That hole is the price of calling the
            -- evaluation without a click, and this is where it is closed.
            local bound = GetBindingAction(KEY, true) or ""
            local want1 = "CLICK " .. DebindPrivate.DefaultClickFrame:GetName()
                .. ":" .. tostring(DebindPrivate.ClickTimeKeys[KEY])
            if bound ~= want1 then
                return Fail(NAME, format("combat=%s: %q, it should be %q",
                    tostring(want), bound, want1))
            end

            local ran, rerr = EvalClickTimeKey(KEY)
            if not ran then return Fail(NAME, rerr) end

            local idx = WaitForWinner()
            if idx == nil then
                return Fail(NAME, format(
                    "combat=%s: the evaluation ran and no record matched", tostring(want)))
            end

            -- The winner index is a place within the records that were **emitted**. Anything dropped
            -- for having no way to be bound, or for being unreachable, puts it out of step with the
            -- KeyMap array; two were confirmed above and both are macrotext, so there is nothing to
            -- drop them for.
            local got = records[idx]
            if not got then
                return Fail(NAME, format("combat=%s gave index %d and there is no record in that place",
                    tostring(want), idx))
            end
            if got.conditions.combat ~= want then
                return Fail(NAME, format("combat=%s and it picked the combat=%s record (#%d)",
                    tostring(want), tostring(got.conditions.combat), idx))
            end
            picked[#picked + 1] = idx
        end

        -- **The negative comparison.** The two checks above read `records[idx].combat`, and if the
        -- emitter does not carry `combat=false` across, that record matches unconditionally and the
        -- index comes out the same on both passes -- and both checks can still go green (the combat
        -- record matches first on the first pass, the same one matches on the second, and KeyMap's
        -- `.combat` is still false). Whether the index really moved is the only direct evidence of
        -- "it picked by looking at the condition".
        if picked[1] == picked[2] then
            return Fail(NAME, format(
                "both picked #%d, it is picking the same one every time without looking at the condition", picked[1]))
        end

        return Pass(NAME, format("in combat #%d, out of combat #%d", picked[1], picked[2]))
    end,
})

-- **The three axes added in 3.4, at the press.** Which record wins is headless
-- (`tests/eval_spec.lua`'s axis table), so what is answerable only here is the half that is
-- silent: `IsMounted`, `IsIndoors` and `GetBonusBarOffset` have to be **callable inside the
-- restricted environment**. A name that is not on Blizzard's whitelist raises nothing anybody can
-- see -- the body fails to compile, the snippet never attaches, and the key stops working.
--
-- `SetMockState` overrides the value the press lands on but not the call that produced it: the
-- probe sits after the measurement, so the real function still runs and a missing one still
-- fails here.
RegisterTest("Click-time key: mounted, indoors and skyriding decide the press", {
    description = "세 축이 제한 환경에서 실제로 읽히고, 누른 순간의 값이 승자를 고른다",
    run = function()
        local NAME = "New axes at the press"
        local KEY = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        local seen = {}
        for _, axis in ipairs({ "mounted", "indoors", "skyriding" }) do
            CleanupActions()

            InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "on"',
                key = KEY, name = axis .. " on", [axis] = true })
            InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "off"',
                key = KEY, name = axis .. " off", [axis] = false })
            ApplyBindings()

            -- Both sides, for the reason the combat test above gives: on one alone, an
            -- implementation that never reads the condition also passes.
            local picked = {}
            for _, want in ipairs({ true, false }) do
                SetMockState(axis, want)

                -- Read again every pass. `SetMockState` ends in a rebuild, which replaces the
                -- KeyMap array.
                local records = GetKeyBindings(KEY)
                if not records or #records ~= 2 then
                    return Fail(NAME, format("%s: there should be 2 records, there are %d",
                        axis, records and #records or 0))
                end

                local ran, rerr = EvalClickTimeKey(KEY)
                if not ran then return Fail(NAME, axis .. ": " .. tostring(rerr)) end

                -- **This is where a missing whitelist entry lands.** The body would not have
                -- compiled, so nothing answers rather than something answering wrong.
                local idx = WaitForWinner()
                if idx == nil then
                    return Fail(NAME, format(
                        "%s=%s: the evaluation ran and no record matched -- if the body did not "
                        .. "compile, that function is not readable in the restricted environment",
                        axis, tostring(want)))
                end

                local got = records[idx]
                if not got then
                    return Fail(NAME, format("%s=%s gave index %d and there is no record there",
                        axis, tostring(want), idx))
                end
                if got.conditions[axis] ~= want then
                    return Fail(NAME, format("%s=%s and it picked the %s=%s record (#%d)",
                        axis, tostring(want), axis, tostring(got.conditions[axis]), idx))
                end
                picked[#picked + 1] = idx

                SetMockState(axis, nil)
            end

            if picked[1] == picked[2] then
                return Fail(NAME, format(
                    "%s: both picked #%d, it is picking the same one without reading the condition",
                    axis, picked[1]))
            end
            seen[#seen + 1] = format("%s #%d/#%d", axis, picked[1], picked[2])
        end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})

-- **The click bakes the macro body** (`devdocs/legacy/trimming-the-restricted-hot-paths.md`, item 2).
-- A body that goes on a button is baked by nobody when a state moves, and by the click that
-- picks that button.
--
-- The value itself is headless (`tests/hover_spec.lua`). **What is answerable only here is
-- whether that write goes through**: inside the wrapper it sets an attribute on a protected
-- frame, and the game reads the same name a moment later. If it does not go through, nothing
-- raises and the old body fires.
--- Raised once per run of the test below, so the body it binds is one no earlier run has bound.
--- Why that matters is on the line that uses it.
local macroBodySeq = 0

RegisterTest("Click bakes the deferred macro body", {
    description = "The click bakes an @hover macro body, which is also whether SetAttribute carries in the restricted environment",
    run = function()
        local NAME = "Deferred macrotext"
        local KEY = "CTRL-SHIFT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat, so nothing can be judged")
        end

        AddTeardown(CleanupActions)

        local frame, why = CreateTestUnitFrame("player", "unit")
        if not frame then
            return Fail(NAME, "the test frame registration was refused: " .. tostring(why))
        end

        -- **A body no run has used before, and that is what makes the check below mean anything.**
        -- `BindingAttrsCache` is keyed by (type, body) and never cleared, and a hit means
        -- `StampBinding` writes no attribute at all (`UpdateBindings.lua`). The click further down
        -- bakes `*macrotext-` itself, so on a second run in one session the same body would come
        -- back to a button still carrying what the first run's click baked -- and the assertion
        -- would read that instead of what `StampBinding` wrote. In play nothing is wrong with
        -- that: every press composes the body afresh before running it.
        macroBodySeq = macroBodySeq + 1
        local body = format("/cast [@hover] Debind%d", macroBodySeq)

        InsertAction({ type = Constants.MACROTEXT, value = body, key = KEY })
        ApplyBindings()

        local binding = GetNthBinding(KEY, 1)
        local button = binding and binding.clickbutton
        if not button then
            return Fail(NAME, "the premise is gone: this action has no click button name on it")
        end

        SetFrameUnit(frame, "player")
        HoverEnter(frame)
        WaitForHoverSlot(true)

        -- **Nobody should have baked it yet.** What is here is what `StampBinding` wrote, and
        -- `@hover` still standing in it is the proof that the poll does not touch this body.
        local raw = DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. button)
        if not (raw and raw:find("@hover", 1, true)) then
            return Fail(NAME, format("the premise is gone: the body is already %q before any click", tostring(raw)))
        end

        local ok, evalWhy = EvalClickTimeKey(KEY)
        if not ok then
            return Fail(NAME, evalWhy)
        end
        WaitForWinner()

        local baked = DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. button)
        if not (baked and baked:find("@player", 1, true)) then
            return Fail(NAME, format("the click did not bake the body (%q)", tostring(baked)))
        end

        return Pass(NAME, baked)
    end,
})

-----------------------------------------------------------
-- Test Cases: Many records on one key, many axes at once
-----------------------------------------------------------

-- One condition on one key answers "does it look at the condition at all". Everything above this
-- line stops there. What a real profile looks like is the next question and nothing was asking
-- it: **a key carrying half a dozen records, each naming several axes, and exactly one of them
-- has to win.**
--
-- Three tests below, because there are three separate deciders and each can be wrong on its own:
--
--   the press        which record the click-time snippet picks, on a key whose wiring is fixed
--   the poll         what the state loop binds the key to, when the winner decides the outcome
--   the two together on a key with a gap, where the poll decides *whether* and the press decides
--                    *which* -- the one place the two can contradict each other
--
-- **The axes are chosen for the shapes they compare, not for their number.** `combat` and
-- `stealth` are equality; `groups` is a bitmask whose measured value is already the bit;
-- `forms` is a bitmask whose measured value is a *form number* that both paths raise to a power
-- of two after measuring -- so a mock lands on the number and the comparison happens on the bit,
-- and getting that boundary wrong is a fault no single-axis test can produce.

--- The states swept, in the order the cross product is taken. Every value here has to be one both
--- paths can be forced to: the click path takes it through `PROBE.MockState` and the update loop
--- through the generated `stateValue` line, and the two only agree on the axes that are measured
--- rather than read (so no unit axis, no `known`, no custom state -- see `SetMockState`).
local SWEEP_ORDER = { "combat", "stealth", "form", "group" }

--- Both read `Constants`, so both are built by `BuildConstantTables` rather than here.
local SWEEP_VALUES
local GROUP_LABEL

--- Every combination of every swept axis, as a list of plain state tables.
local function BuildCombos()
    local combos = { {} }
    for _, axis in ipairs(SWEEP_ORDER) do
        local grown = {}
        for _, base in ipairs(combos) do
            for _, value in ipairs(SWEEP_VALUES[axis]) do
                local state = {}
                for k, v in pairs(base) do state[k] = v end
                state[axis] = value
                grown[#grown + 1] = state
            end
        end
        combos = grown
    end
    return combos
end

local function ComboLabel(state)
    return format("combat=%s stealth=%s form=%d %s",
        tostring(state.combat), tostring(state.stealth), state.form,
        GROUP_LABEL[state.group] or tostring(state.group))
end

--- Does this record's condition hold in this state?
---
--- **This is a second implementation and it is meant to be.** Writing the expected winner of
--- thirty-six combinations out by hand is the one part of this that would be wrong, and it would
--- be wrong quietly -- a mistranscribed row reads exactly like a bug in the addon. So the
--- expectation is derived from the same record definition the actions are built from.
---
--- It shares no code with the snippet and, more to the point, no *shape*: the snippet compares
--- bitmasks with the `%` idiom the restricted environment forces on it and decides each axis
--- inside a chain of short-circuits, while this is a set lookup and a plain comparison. The
--- faults the snippet can have are not available here.
local function SweepMatches(cond, state)
    if cond.combat ~= nil and cond.combat ~= state.combat then return false end
    if cond.stealth ~= nil and cond.stealth ~= state.stealth then return false end
    if cond.forms and not cond.forms[state.form] then return false end
    if cond.groups and not cond.groups[state.group] then return false end
    return true
end

--- Which record ought to win: the first one in emitted order whose condition holds.
local function SweepWinner(records, state)
    for i = 1, #records do
        if SweepMatches(records[i].cond, state) then return i end
    end
    return nil
end

--- Turns a record definition into the action the addon is given. The form and group sets become
--- bitmasks **here and nowhere else**, so `SweepMatches` above never has to agree with the
--- addon about what a bit means.
local function ToSweepAction(record, key)
    local action = { key = key }
    for k, v in pairs(record.action) do action[k] = v end

    local cond = record.cond
    action.combat = cond.combat
    action.stealth = cond.stealth
    if cond.forms then
        local mask = 0
        for form in pairs(cond.forms) do mask = bor(mask, 2 ^ form) end
        action.forms = mask
    end
    if cond.groups then
        local mask = 0
        for group in pairs(cond.groups) do mask = bor(mask, group) end
        action.groups = mask
    end
    -- Written flat and moved in one place. The same function `InsertAction` uses.
    return NestConditions(action)
end

--- Stands the swept state up for real.
---
--- **Only what changed.** `SetMockState` ends in a rebuild, and a sweep that re-forces every axis
--- on every combination pays for four rebuilds where it needs one. Sweeping in `SWEEP_ORDER`
--- means the slowest-moving axis is re-forced least.
local function ApplySweepState(state)
    for _, axis in ipairs(SWEEP_ORDER) do
        if GetMockState(axis) ~= state[axis] then
            SetMockState(axis, state[axis])
        end
    end
end

--- Inserts the records in order and checks that all of them came out the other side.
---
--- **The count is the load-bearing part.** Every assertion below is on a record *index*, and an
--- index only means what the test thinks it means while the emitted list is the list that went
--- in. A record the solver judged unreachable, or one dropped for having no way to be bound,
--- shifts every index after it -- and the sweep would then report a confident, precise, wrong
--- answer about which condition won.
local function SetUpSweepKey(records, key)
    for i = 1, #records do
        InsertAction(ToSweepAction(records[i], key))
    end
    ApplyBindings()

    local emitted = GetKeyBindings(key)
    if not emitted or #emitted ~= #records then
        return nil, format("there should be %d records, there are %d, either the solver dropped one or one had no way to be bound",
            #records, emitted and #emitted or 0)
    end
    return true
end

--- Names every record that never won, once the sweep is over.
---
--- A record no combination can reach is not a passing test, it is a test with a hole in it: the
--- sweep would go green while that condition was never asked about. It also catches the addon
--- changing under the test -- an emitter that quietly stopped producing one record leaves the
--- count intact only if something else took its place, and this is the second net.
local function UnreachedRecords(records, wins)
    local missing
    for i = 1, #records do
        if not wins[i] then
            missing = missing or {}
            missing[#missing + 1] = format("#%d (%s)", i, records[i].label)
        end
    end
    return missing
end

-- Seven records, and the last is unconditional -- which is what makes this key `alwaysOurs`: the
-- condition space has no gap, the key is bound once at build time, and the only thing left to
-- decide is *which* record, at the press. Exactly the path being measured.
--
-- Every record is a macrotext so that all seven are clickable and none can be dropped for having
-- no way to be bound.
local CLICKTIME_SWEEP

--- The three tables above read `Constants`, which is not there when this file loads: this addon
--- is ahead of Debind in the load order (`DebindDev.toc`). So they are built here instead, from
--- the `ADDON_LOADED` handler at the tail, which is still long before any test runs.
local function BuildConstantTables()
    SWEEP_VALUES = {
        combat  = { false, true },
        stealth = { false, true },
        -- 0 is "no form". The masks below name form numbers, not bits, and only `ToSweepAction`
        -- turns them into bits -- so the whole test speaks the same language the mock does.
        form    = { 0, 1, 2 },
        group   = { Constants.GROUP_NONE, Constants.GROUP_PARTY, Constants.GROUP_RAID },
    }

    GROUP_LABEL = {
        [Constants.GROUP_NONE]  = "solo",
        [Constants.GROUP_PARTY] = "party",
        [Constants.GROUP_RAID]  = "raid",
    }

    CLICKTIME_SWEEP = {
        { label = "combat+form1|2", cond = { combat = true, forms = { [1] = true, [2] = true } } },
        { label = "combat+raid",    cond = { combat = true, groups = { [Constants.GROUP_RAID] = true } } },
        { label = "stealth+form0",  cond = { stealth = true, forms = { [0] = true } } },
        { label = "peace+grouped",  cond = { combat = false, stealth = false,
                                             groups = { [Constants.GROUP_PARTY] = true,
                                                        [Constants.GROUP_RAID] = true } } },
        { label = "form2",          cond = { forms = { [2] = true } } },
        { label = "combat",         cond = { combat = true } },
        { label = "fallback",       cond = {} },
    }

    for i = 1, #CLICKTIME_SWEEP do
        local record = CLICKTIME_SWEEP[i]
        record.action = {
            type = Constants.MACROTEXT,
            value = format('/run local _ = "%s"', record.label),
            name = record.label,
        }
    end
end

-- **Both places, deliberately.** The same sweep runs headless (`tests/eval_spec.lua`), and this
-- one is the anchor: four axes over seven records is where an interpretation of the restricted
-- environment and the real one would part, and there is no other way to find out that they
-- have (`going-headless-outside-the-ui.md` §9).
RegisterTest("Multi-axis: the press picks the exact record out of seven", {
    description = "Sweeping every combination of four axes, exactly the right one of seven records wins each time",
    -- The runner's ceiling is a guard against a hung coroutine, not a budget. This one drives a
    -- rebuild per state change, thirty-six combinations over, and none of that is the test being
    -- slow in the sense the ceiling is watching for. It is kept where it is rather than trimmed
    -- to what the run now costs -- the number is a ceiling on hanging, and a test that has to be
    -- re-raised every time the machine is slower is a test that fails for the wrong reason.
    timeout = 120,
    run = function()
        local NAME = "Multi-axis click-time"
        local KEY = "CTRL-SHIFT-F1"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        local ok, err = SetUpSweepKey(CLICKTIME_SWEEP, KEY)
        if not ok then return Fail(NAME, err) end

        local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY]
        if not button then
            return Fail(NAME, "not a click-time key, it does not walk the path this test measures")
        end

        local combos = BuildCombos()
        local wins = {}

        for _, state in ipairs(combos) do
            ApplySweepState(state)

            local want = SweepWinner(CLICKTIME_SWEEP, state)
            if not want then
                return Fail(NAME, format("%s: no expected winner, and the last one is unconditional so there has to be one",
                    ComboLabel(state)))
            end

            -- **Read again every time.** Standing a state up runs a rebuild and replaces the table.
            -- A count out of step moves what the index points at, so this stops here before asking
            -- who won.
            local emitted = GetKeyBindings(KEY)
            if not emitted or #emitted ~= #CLICKTIME_SWEEP then
                return Fail(NAME, format("%s: %d records after the rebuild, the index has lost its meaning",
                    ComboLabel(state), emitted and #emitted or 0))
            end

            -- Whether it is bound comes first. The evaluation runs without a click, so without this
            -- comparison a state where the judgement is right and nothing is bound to any key passes.
            local bound = GetBindingAction(KEY, true) or ""
            local wantBound = "CLICK " .. DebindPrivate.DefaultClickFrame:GetName() .. ":" .. button
            if bound ~= wantBound then
                return Fail(NAME, format("%s: the key is %q, it should be %q",
                    ComboLabel(state), bound, wantBound))
            end

            local ran, rerr = EvalClickTimeKey(KEY)
            if not ran then return Fail(NAME, rerr) end

            local got = WaitForWinner()
            if got ~= want then
                return Fail(NAME, format("%s: #%d (%s) should have won and it was %s",
                    ComboLabel(state), want, CLICKTIME_SWEEP[want].label,
                    got and format("#%d (%s)", got, CLICKTIME_SWEEP[got] and CLICKTIME_SWEEP[got].label or "?")
                        or "nobody won"))
            end

            wins[got] = (wins[got] or 0) + 1
        end

        local missing = UnreachedRecords(CLICKTIME_SWEEP, wins)
        if missing then
            return Fail(NAME, format("records that won in none of the %d combinations: %s. the swept axes cannot produce that place",
                #combos, table.concat(missing, ", ")))
        end

        return Pass(NAME, format("all %d combinations exactly right, and all %d records won at least once",
            #combos, #CLICKTIME_SWEEP))
    end,
})

-- The one place the two deciders meet, and the only place they can contradict each other.
--
-- Drop the unconditional record and the condition space has a hole in it. Now both halves are
-- live on the same key: the **poll** decides whether the key is ours at all -- it has to grab it
-- when something matches and hand it back when nothing does -- and the **press** decides which of
-- the survivors runs. The comments in `SecureBindings.lua` call drift between them the worst kind
-- of quiet, because neither side can tell which of the two is the one that is wrong.
--
-- So both are asked in every combination, against one expectation:
--
--   something matches   the key is bound to the click-time button *and* the press picks that record
--   nothing matches     the key is released *and* the press picks nobody
--
-- Half of this would pass on a key that was simply bound the whole time; the other half would
-- pass on a snippet that always answered the first record. Together they do not.
--- **The table is made here and filled later.** What it is cut from, `CLICKTIME_SWEEP`, does not
--- exist until `ADDON_LOADED` (`BuildConstantTables`), and the tests below hold this table itself
--- rather than a copy, so it has to be the same one they were given.
local GAPPED_SWEEP = {}
local function BuildGappedSweep()
    for i = 1, #CLICKTIME_SWEEP - 1 do
        GAPPED_SWEEP[i] = CLICKTIME_SWEEP[i]
    end
end

-- **Both places, deliberately.** The second anchor (§9). The headless twin is in
-- `tests/eval_spec.lua`; keeping this one is what would show the two sides parting.
RegisterTest("Multi-axis: poll and press agree on a key with a gap", {
    description = "On a key whose conditions have a gap, taking and releasing it never contradicts which record wins",
    timeout = 120,
    run = function()
        local NAME = "Multi-axis poll vs press"
        local KEY = "CTRL-SHIFT-F5"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        local ok, err = SetUpSweepKey(GAPPED_SWEEP, KEY)
        if not ok then return Fail(NAME, err) end

        local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY]
        if not button then
            return Fail(NAME, "not a click-time key, there is nowhere to ask who won")
        end

        -- The gap has to survive for the state loop to keep settling this key. This is where
        -- dropping the unconditional record is confirmed to have had that effect; without it the
        -- "has to be released" side below passes without ever running.
        ReadKeyMembership(KEY)
        local membership = WaitForMembership()
        if not membership then return Fail(NAME, "the restricted environment sent no answer") end
        if not membership.stateDriven then
            return Fail(NAME, "not a state-driven key, which means the condition space has no gap")
        end
        if not membership.clickTime then
            return Fail(NAME, "not in the click-time table either, there is nowhere to ask who won")
        end

        local combos = BuildCombos()
        local wantBound = "CLICK " .. DebindPrivate.DefaultClickFrame:GetName() .. ":" .. button
        local wins, released = {}, 0

        for _, state in ipairs(combos) do
            ApplySweepState(state)

            local want = SweepWinner(GAPPED_SWEEP, state)
            local bound = GetBindingAction(KEY, true) or ""

            if want then
                if bound ~= wantBound then
                    return Fail(NAME, format("%s: #%d (%s) matches and the key is %q, it should have been taken",
                        ComboLabel(state), want, GAPPED_SWEEP[want].label, bound))
                end
            elseif bound ~= "" then
                return Fail(NAME, format("%s: no record matches and the key is %q, it should have been released",
                    ComboLabel(state), bound))
            end

            local ran, evalErr = EvalClickTimeKey(KEY)
            if not ran then return Fail(NAME, evalErr) end

            local got = WaitForWinner()
            if got ~= want then
                return Fail(NAME, format("%s: the press picked %s, it should be %s",
                    ComboLabel(state),
                    got and format("#%d (%s)", got, GAPPED_SWEEP[got] and GAPPED_SWEEP[got].label or "?")
                        or "nobody",
                    want and format("#%d (%s)", want, GAPPED_SWEEP[want].label) or "nobody"))
            end

            if want then
                wins[want] = (wins[want] or 0) + 1
            else
                released = released + 1
            end
        end

        -- Was the gap actually walked into? If not, not a line of the "has to be released" side ran,
        -- and this test measured the same thing as the one before it twice.
        if released == 0 then
            return Fail(NAME, format("it released in none of the %d combinations, the gap was never walked into", #combos))
        end

        local missing = UnreachedRecords(GAPPED_SWEEP, wins)
        if missing then
            return Fail(NAME, format("records that won in none of the %d combinations: %s", #combos, table.concat(missing, ", ")))
        end

        return Pass(NAME, format("the poll and the press agreed in %d combinations, and %d of those released the key",
            #combos, released))
    end,
})

-----------------------------------------------------------
-- Test Cases: The macro store as an input
-----------------------------------------------------------

-- **A `MACRO` action naming a macro that does not exist is left out of the build entirely**
-- (`GetMissingMacroName` -> `BINDING_ISSUE_MISSING_MACRO` -> `BuildKeyMap`), which makes the macro
-- store an input to what the keys are. Nothing was watching it: create the macro and the row stops
-- being red -- the window says nothing is wrong -- while the key stays dead until something
-- unrelated rebuilds, or a `/reload`. `UPDATE_MACROS` is registered for that.
--
-- **The half that is left is the client's.** `tests/boundkey_spec.lua` sends `UPDATE_MACROS` by
-- hand and holds everything downstream of it: that the addon is listening, that the handler queues
-- a rebuild, and that the key comes back. What no harness can send is the event itself, and this
-- makes a real macro rather than faking one for exactly that reason -- what broke was never "a
-- rebuild does not read the store" but that **no rebuild happens**.
--
-- Deleting it belongs to the runner, so it goes however this ends.
RegisterTest("Macro store: creating the missing macro revives the key", {
    description = "Creating the missing macro revives the key with no reload",
    run = function()
        local NAME = "Macro revive"
        local KEY = "CTRL-SHIFT-F6"
        local MACRO = "DebindTestRevive"

        if InCombatLockdown() then
            return Fail(NAME, "a macro cannot be created in combat")
        end

        AddTeardown(function()
            if not InCombatLockdown() and GetMacroIndexByName(MACRO) > 0 then
                DeleteMacro(MACRO)
            end
        end)

        if GetMacroIndexByName(MACRO) > 0 then
            DeleteMacro(MACRO)
        end

        InsertAction({ type = Constants.MACRO, value = MACRO, key = KEY })
        ApplyBindings()

        -- **The negative first.** Without it a key that was live the whole time reads as a pass,
        -- and this test would go green on a build where the issue never drops anything.
        local before = GetBindingAction(KEY, true) or ""
        if before ~= "" then
            return Fail(NAME, format("the macro does not exist and the key is already taken: %q", before))
        end

        -- **Asked of the store, not of the return value.** `CreateMacro` raises when there is no
        -- room, and `0` back would pass a plain `not` check anyway - `0` is true in Lua. Either way
        -- the answer wanted here is whether the macro is now there.
        pcall(CreateMacro, MACRO, 132219, "/say debtest")
        if GetMacroIndexByName(MACRO) == 0 then
            return Fail(NAME, "the macro could not be created, the macro slots may be full")
        end

        -- **Waiting on the binding is right here only because the line above proved it was not
        -- bound.** The usual objection -- that waiting for what you are about to assert can only
        -- fail by timing out -- needs the expected value to be a possible current one, and it is
        -- not. A timeout *is* the finding: nothing rebuilt.
        WaitUntil(function()
            return (GetBindingAction(KEY, true) or ""):sub(1, 6) == "CLICK "
        end, 3)

        local after = GetBindingAction(KEY, true) or ""
        if after:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "the macro was created and the key is still dead (%q), nobody is listening to UPDATE_MACROS",
                after))
        end

        return Pass(NAME, after)
    end,
})

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

        DebindFrame:Hide()
        AddTeardown(function() DebindFrame:Hide() end)

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

-----------------------------------------------------------
-- Test Cases: Across a /reload
-----------------------------------------------------------

-- The reload machinery checking itself. That is not as circular as it sounds: everything a
-- migration or a save-format test would assert rests on this one claim -- that a run can end the
-- session, come back, and know where it was -- and nothing else in the suite touches it.
--
-- Opt-in (`/debtest reload`), because a plain run should not end someone's session.
RegisterTest("Run survives /reload", {
    description = "The run carries across a /reload, and the phase and the scratch come with it",
    crossesReload = true,
    run = function(phase)
        local NAME = "Reload round trip"
        local scratch = Scratch()

        if not phase then
            scratch.token = "before-" .. tostring(GetTime())
            scratch.index = 1
            return RequestReload("second-half")
        end

        -- Anything wrong here means the runner picked the wrong test, the wrong phase, or a run
        -- that was not the one it stored.
        if phase ~= "second-half" then
            return Fail(NAME, format("phase=%s, it should be second-half", tostring(phase)))
        end

        if not scratch.token or scratch.token:sub(1, 7) ~= "before-" then
            return Fail(NAME, format("the scratch did not come across (token=%s)", tostring(scratch.token)))
        end

        -- The run's own tally has to come back too. It is what the report is built from, and a
        -- resumed run that forgot it would report only the tests after the reload.
        local kept = scratch.token
        scratch.token, scratch.index = nil, nil

        return Pass(NAME, format("carried on into %s after the reload (%s)", phase, kept))
    end,
})

-- The client behaviour the role map's hook is built on: does `SetAttribute` with a value the
-- frame already holds still raise a **wrapped** `OnAttributeChanged`?
--
-- **Only the game can answer.** It is not documented anywhere, and the headless harness records
-- wrapped bodies rather than running them. It was measured in game on
-- 2026-08-28; this is what will notice the day the client stops doing it.
--
-- If it goes red, the role map stops updating on any layout where the roster did not change, and
-- nothing else says so -- `UnitWatch.lua`'s hook rides the header's last child, and that child is
-- written with the same `nil` on almost every pass.
RegisterTest("Unchanged attribute writes still raise a wrapped handler", {
    description = "SetAttribute with the value already there fires OnAttributeChanged, which the role map's hook needs",
    run = function()
        local NAME = "Unchanged write"

        if InCombatLockdown() then
            return Fail(NAME, "wrapping is blocked in combat")
        end

        local header = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
        local target = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")

        local fired = 0
        function target:DebindTestRoleProbe()
            fired = fired + 1
        end

        SecureHandlerWrapScript(target, "OnAttributeChanged", header, [[
            self:CallMethod("DebindTestRoleProbe")
        ]])
        AddTeardown(function()
            SecureHandlerUnwrapScript(target, "OnAttributeChanged")
        end)

        -- The first write is a real change, so it is not evidence. The two after it are not.
        target:SetAttribute("debindprobe", "raid1")
        local baseline = fired
        target:SetAttribute("debindprobe", "raid1")
        target:SetAttribute("debindprobe", "raid1")

        if fired <= baseline then
            return Fail(NAME, format("only the changing write fired (%d), so the role map would "
                .. "stop updating whenever the roster held still", fired))
        end

        -- Writing `nil` onto a field that is already absent is the case the tidy loop actually
        -- runs on every child past the ones it filled.
        local before = fired
        target:SetAttribute("debindprobenil", nil)
        target:SetAttribute("debindprobenil", nil)
        if fired <= before then
            return Fail(NAME, "writing nil onto an absent attribute raised nothing")
        end

        return Pass(NAME, format("%d fires for 5 writes", fired))
    end,
})

-- The role headers are the only thing that fills `UnitRoles`, and a header can only hold as many
-- people as it has child frames. Those frames cannot be made during combat, so the rebuild has to
-- have made them already.
--
-- **The hook has to be on the header's highest child.** `configureChildren` writes `unit` on every
-- child it has and the highest one is the last of those writes, so a hook anywhere below it reads
-- a half-placed arrangement. Growing the header moves it, and this is where that lands in a real
-- header rather than a recording.
RegisterTest("A role condition widens the role headers", {
    description = "Asking about a role gives tank/healer/damager a slot per raid member and leaves the hook on the last one",
    run = function()
        local NAME = "Role headers"

        if InCombatLockdown() then
            return Fail(NAME, "growing a header needs the secure handler API")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = { role = Constants.ROLE_TANK } },
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        ApplyBindings()

        local seen = {}
        for _, alias in ipairs({ "tank", "healer", "damager" }) do
            local header = DebindPrivate.UnitWatchHeaders[alias]
            if not header then
                return Fail(NAME, alias .. " has no header")
            end
            if not header:IsShown() then
                return Fail(NAME, alias .. " was not shown")
            end

            local count = 0
            while header:GetAttribute("child" .. (count + 1)) do
                count = count + 1
            end
            if count ~= Constants.MAX_ROLE_SLOTS then
                return Fail(NAME, format("%s has %d children, wanted %d",
                    alias, count, Constants.MAX_ROLE_SLOTS))
            end
            if header:GetAttribute("unitsPerColumn") ~= Constants.MAX_ROLE_SLOTS then
                return Fail(NAME, format("%s fills only %s of them",
                    alias, tostring(header:GetAttribute("unitsPerColumn"))))
            end
            seen[#seen + 1] = alias .. "=" .. count
        end

        -- **표가 서 있다는 것이 곧 셋이 다 섰다는 뜻이다.** 헤더 상태만 보면 표가 안 선 채로
        -- 셋이 켜져 있는 경우를 못 잡는데, 그러면 판정이 아예 안 서서 조건이 조용히 통과한다.
        ReadRoleMap()
        WaitForRoleMap()
        if not lastRoleMap then
            return Fail(NAME, "the restricted environment never answered")
        end
        if not lastRoleMap.present then
            return Fail(NAME, "the headers are up but the role map is not")
        end

        return Pass(NAME, table.concat(seen, ", ") .. format(", map=%d", lastRoleMap.count))
    end,
})

-- **표는 셋을 켜기로 정한 리빌드가 세우고 내린다.** 헤더가 저마다 세우면 반쪽 맵이 유효해
-- 보이고, 그때 `unknown`은 "셋이 다 보고도 아무도 안 데려갔다"가 아니라 "덜 봤다"가 된다.
-- 탱커 헤더만 켜진 채로 답을 내면 딜러가 전부 `unknown`으로 떨어져서, [탱커]와 [알 수 없음]을
-- 고른 사용자에게 딜러까지 걸린다.
--
-- **끄는 쪽만 이 순서로 잡힌다.** 켜는 쪽은 위 테스트가 보고, 여기는 조건이 사라졌을 때 표가
-- 실제로 내려가는지 -- 그리고 다시 걸었을 때 되돌아오는지 -- 를 본다.
RegisterTest("Dropping the role condition takes the map down", {
    description = "The role map stands up with the condition and goes with it, so a half-built map never answers",
    run = function()
        local NAME = "Role map lifecycle"

        if InCombatLockdown() then
            return Fail(NAME, "showing and hiding a header needs the secure handler API")
        end

        local function mapPresent()
            ReadRoleMap()
            WaitForRoleMap()
            if not lastRoleMap then
                return nil
            end
            return lastRoleMap.present
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = { role = Constants.ROLE_TANK } },
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        ApplyBindings()
        if mapPresent() ~= true then
            return Fail(NAME, "the map never stood up")
        end

        CleanupActions()
        InsertAction({ type = Constants.SPELL, value = 585, key = "BUTTON3" })
        ApplyBindings()
        if mapPresent() ~= false then
            return Fail(NAME, "the map outlived the condition that asked for it")
        end
        for _, alias in ipairs({ "tank", "healer", "damager" }) do
            local header = DebindPrivate.UnitWatchHeaders[alias]
            if header and header:IsShown() then
                return Fail(NAME, alias .. " is still shown with nothing asking about roles")
            end
        end

        CleanupActions()
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = { role = Constants.ROLE_HEALER } },
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        ApplyBindings()
        if mapPresent() ~= true then
            return Fail(NAME, "the map did not come back when the condition did")
        end

        return Pass(NAME, "up, down, up")
    end,
})

-- The role axis at the press, without needing anybody else online.
--
-- **Two records that partition the axis.** One asks for `unknown`, the other for the three real
-- roles, so exactly one of them can match whatever the tester's group looks like -- and which one
-- wins is not something this test has to know. What it holds is that **one of them does**: a unit
-- with no row on the map has to read as `unknown` rather than as nothing, and if that fallback
-- goes, neither record matches and the key dies with nobody saying so.
RegisterTest("Role at the press: a unit off the map reads as unknown", {
    description = "One of two records partitioning the role axis wins the click, so the missing-row fallback is real",
    run = function()
        local NAME = "Role at the press"
        local REAL_ROLES = Constants.ROLE_TANK + Constants.ROLE_HEALER
            + Constants.ROLE_DAMAGER

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { hover = { role = Constants.ROLE_UNKNOWN } },
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        InsertAction({
            type = Constants.SPELL, value = 8936, key = "BUTTON3",
            units = { hover = { role = REAL_ROLES } },
            frameTypes = Constants.FRAMETYPE_ALL,
        })
        ApplyBindings()

        local frame, ferr = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, ferr) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        local ran, rerr = EvalClickCast(frame, 3, 0)
        if not ran then return Fail(NAME, rerr) end
        WaitForEvalAnswer()

        local winner = LastWinner()
        if winner == nil then
            return Fail(NAME, "neither record matched, so the role of a unit with no row on the "
                .. "map came back as neither unknown nor a real role")
        end

        return Pass(NAME, format("record %d took it", winner))
    end,
})

-----------------------------------------------------------
-- Copyable Output Popup
-----------------------------------------------------------

local CopyFrame

local function ShowCopyableText(text)
    if not CopyFrame then
        local f = CreateFrame("Frame", "DebindTestCopyFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(700, 400)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f.TitleText:SetText("Test Results (Ctrl+A, Ctrl+C to copy)")

        local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -32)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 12)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetWidth(640)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        scrollFrame:SetScrollChild(editBox)

        f.editBox = editBox
        CopyFrame = f
    end

    -- strip WoW color codes for plain text
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    CopyFrame.editBox:SetText(plain)
    CopyFrame:Show()
    CopyFrame.editBox:HighlightText()
    CopyFrame.editBox:SetFocus()
end

-----------------------------------------------------------
-- Test Runner
-----------------------------------------------------------

local lastResultText = ""
--- The same run, cut down to what did not pass. Kept beside the full text rather than derived from
--- it on demand, because the run it describes is gone by the time anyone presses the button.
local lastFailureText = ""

local runner = CreateFrame("Frame")
runner:Hide()

local run

-- Progress is written to saved variables **after every test**, not at the end. A run that spans
-- a `/reload` is the point of storing it at all, and a reload can arrive at any test; whatever
-- was only in memory when it does is gone. Storing it also means a session that crashes leaves a
-- record of how far it got, which is otherwise the one outcome that reports nothing.
local function Persist()
    if not run then
        DB().pending = nil
        return
    end

    DB().pending = {
        index = run.index,
        phase = run.phase,
        reloads = run.reloads,
        pass = run.pass,
        fail = run.fail,
        err = run.err,
        skip = run.skip,
        lines = run.lines,
        crossReloads = run.crossReloads,
        -- Carried so the resumed list still shows what already passed. `lines` is the report and
        -- is not indexed by test, so without this the window comes back with every row before the
        -- reload point greyed out -- a run that looks like it is starting over.
        results = results,
        -- Set only while a reload is deliberately in flight. Its absence in a stored run is what
        -- separates "the session went away on purpose" from "the session died here".
        expectReload = run.expectReload,
    }
end

--- Just the ones that did not pass, in the order they ran.
---
--- **Built from `results`, not by filtering the report.** The report is a list of lines written for
--- a person and its shape is free to change; picking failures out of it by looking for a word would
--- go quietly empty the day one of those words moves. `results` is what the run actually decided,
--- keyed by test.
---
--- **Errors count as failures here**, because the reader pressing this wants everything that is not
--- a pass. Skips do not: nothing went wrong with one, and a list that carried them would bury two
--- real failures under thirty rows the reader asked to leave out.
---
--- The tally comes along. Without it "3 lines" reads the same whether the run was three tests or
--- three hundred, and the first thing anyone asks of a failure list is how much of the suite it is.
--- `source` is the results table to read, for the two callers that have one which is not the live
--- one: a run that died with the session and a resume that threw both report on results that were
--- stored before this session began.
local function FailuresText(summary, source)
    source = source or results
    local lines = {};
    for i = 1, #testOrder do
        local result = source[testOrder[i]];
        if (result and (result.status == "fail" or result.status == "error")) then
            lines[#lines + 1] = result.msg;
        end
    end

    if #lines == 0 then
        return "No failures.\n\n" .. summary
    end

    tinsert(lines, "")
    tinsert(lines, summary)
    return table.concat(lines, "\n")
end

local function FinishRun()
    pcall(CleanupActions)
    RunTeardowns()
    SetIsolated(false)
    UI.SetActive(nil)
    UI.HideClickTarget()
    UI.SetRunning(false)

    -- Skipped tests are named rather than left to be inferred from the total not adding up.
    local summary = format("[DebindTest] Complete: %d passed, %d failed, %d errors%s / %d total",
        run.pass, run.fail, run.err,
        run.skip > 0 and format(", %d skipped", run.skip) or "",
        #testOrder)
    tinsert(run.lines, "")
    tinsert(run.lines, summary)
    print(format("\n|cff00ccff%s|r", summary))

    lastResultText = table.concat(run.lines, "\n")
    lastFailureText = FailuresText(summary)

    local onDone = run.onDone
    run = nil
    runner:Hide()
    Persist()

    DB().last = lastResultText
    DB().lastFailures = lastFailureText

    if onDone then onDone() end
end

-- A test that yields and never comes back would otherwise hold the runner forever, and `run`
-- staying set means no further run can start either -- one stuck test costs a `/reload`. Long
-- is fine here (waiting is the point), so this is only a ceiling on hanging, not on slowness.
--
-- A test that sweeps a cross product spends most of a minute waiting on rebuilds and polls it
-- genuinely has to wait for, which is not the thing this guards against. Those raise the ceiling
-- with `timeout` in their registration rather than raising it for everyone -- a hung test should
-- still be caught in thirty seconds unless someone said otherwise about that one test.
local TEST_TIMEOUT = 30

local function Record(testName, status, msg, color)
    -- A test is meant to return a message with its verdict. One that does not still has to be
    -- recorded as something, and this runs inside OnUpdate where throwing helps nobody.
    msg = msg or format("%s (no message)", testName)
    results[testName] = { status = status, msg = msg }
    tinsert(run.lines, msg)
    print(color and format("|c%s%s|r", color, msg) or msg)
    UI.Update(testName)
end

-- A reload-crossing test that keeps asking for another one would reload the session forever, and
-- a reload loop cannot be interrupted from inside the game. This is the stop.
local MAX_RELOADS = 4

-- **`ReloadUI` is protected.** An addon may only reach it from a hardware event, and an OnUpdate
-- is not one -- calling it there gets ADDON_ACTION_BLOCKED and nothing else. So the reload is
-- asked for rather than performed, and the click on this popup is the hardware event that
-- carries it.
--
-- Having to ask turns out to suit it. Ending someone's session is not something to do silently
-- on the way past, and declining has to mean something, so it stops the run rather than leaving
-- a stored one to surprise the next login.
StaticPopupDialogs["DEBINDTEST_RELOAD"] = {
    text = "DebindTest: %s\n\nThis test has to cross a /reload. Reloading carries the run on from here.",
    button1 = RELOAD_UI or "Reload UI",
    button2 = CANCEL or "Cancel",
    OnAccept = function() ReloadUI() end,
    OnCancel = function()
        DB().pending = nil
        -- Declining ends the run here, and the session carries on -- so the user's own bindings
        -- have to come back. The reload path does not need this: the swap is only in memory.
        SetIsolated(false)
        UI.SetRunning(false)
        print("|cffff8800[DebindTest]|r the reload was cancelled, so the run was stopped.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

--- Saves progress and asks for the reload. The test is picked up again from the top afterwards,
--- with `phase` telling it where it was.
local function DoReload(phase)
    run.phase = phase
    run.reloads = run.reloads + 1
    run.expectReload = true
    run.co, run.wait = nil, nil

    -- Teardowns run first: whatever they undo is state that must not outlive this session, and
    -- after the reload nothing here gets another chance.
    RunTeardowns()
    pcall(CleanupActions)

    -- **Progress is written before anything else is undone.** Whatever follows can throw, and if
    -- it does before this line the stored run is the one from the previous test -- no
    -- `expectReload` on it, so the session that comes back reports the run as having died rather
    -- than continuing it. Persisting first costs nothing and removes the whole class.
    Persist()

    -- **The layer swap is not restored here and the bindings are** -- the two are not the same
    -- kind of thing. The swap lives only in memory and dies with the session; the tester's
    -- bindings are the game's own table, and the session is about to end while they are missing.
    -- The resumed run blacks them out again on the other side.
    pcall(RestoreGameBindings)

    -- The runner stops here either way. Everything it would need is stored, so the run continues
    -- from saved variables if the reload happens and is dropped by OnCancel if it does not.
    local name = run.name
    run = nil
    runner:Hide()

    print(format("|cff00ccff[DebindTest]|r %s -> waiting for /reload (%s)", name, phase))
    StaticPopup_Show("DEBINDTEST_RELOAD", name)
end

--- One resume of the current test. Returns true when the runner may keep going this frame.
local function Step()
    if not run.co then
        if run.index > #testOrder then
            FinishRun()
            return false
        end

        -- **Nothing starts while a rebuild is still scheduled.**
        --
        -- A rebuild the setup provoked goes off on the next frame, and a rebuild fills `States`
        -- afresh. A test starting before that has the state it stood up wiped out from under it, and
        -- the symptom reads as "the value disappeared for no reason". The hover slot died that way.
        --
        -- One more frame is given after the queue empties. `updateBindingsQueued` is cleared by the
        -- timer callback **before it calls the rebuild**, so empty does not mean that rebuild is done.
        if (DebindPrivate.IsUpdateBindingsQueued()) then
            run.settle = true
            return false
        end
        if (run.settle) then
            run.settle = nil
            return false
        end

        run.name = testOrder[run.index]
        run.spent = 0
        awaitingHuman = false
        UI.SetActive(run.name)

        local test = tests[run.name]

        -- Reload-crossing tests are opt-in. Ending the session is not something a plain
        -- `/debtest` should do to someone who only wanted to see the list go green.
        if test.crossesReload and not run.crossReloads then
            run.skip = run.skip + 1
            Record(run.name, "skip", format("SKIP %s: run it with /debtest reload", run.name), "ff888888")
            run.index = run.index + 1
            Persist()
            return true
        end


        pcall(CleanupActions)
        run.co = coroutine.create(test.run)
        run.timeout = test.timeout or TEST_TIMEOUT
    end

    -- The phase is handed in rather than remembered by the test, because the test is being run
    -- from the top again -- there is nothing of its own left to remember with.
    local ok, a, b = coroutine.resume(run.co, run.phase)

    if not ok then
        run.err = run.err + 1
        Record(run.name, "error", format("ERROR %s: %s", run.name, tostring(a)), "ffff8800")
    elseif coroutine.status(run.co) == "dead" then
        if a then
            run.pass = run.pass + 1
            Record(run.name, "pass", b)
        else
            run.fail = run.fail + 1
            Record(run.name, "fail", b)
        end
    elseif a == RELOAD_REQUEST then
        if run.reloads >= MAX_RELOADS then
            run.err = run.err + 1
            Record(run.name, "error",
                format("ERROR %s: asked for more than %d reloads", run.name, MAX_RELOADS), "ffff8800")
            RunTeardowns()
            run.co, run.wait = nil, nil
            run.index = run.index + 1
            -- So the next test does not start on somebody else's phase. Clearing this used to be on
            -- the normal-exit branch alone, so a test that died partway across a reload handed its
            -- phase to the next one, and the receiver skipped its whole setup stage.
            run.phase = nil
            Persist()
            return true
        end

        DoReload(b)
        return false
    else
        -- Yielded. The test is mid-flight, so nothing is torn down yet.
        run.wait = tonumber(a) or 0
        return false
    end

    RunTeardowns()
    run.co = nil
    run.index = run.index + 1
    run.phase = nil
    Persist()
    return true
end

runner:SetScript("OnUpdate", function(self, elapsed)
    -- The frame is hidden while idle, so this should not fire without a run. A teardown or an
    -- `onDone` that starts something of its own could still land here between the two, and an
    -- error thrown from OnUpdate is not worth the risk of finding out.
    if not run then
        self:Hide()
        return
    end

    if run.co and not awaitingHuman then
        run.spent = run.spent + elapsed
        if run.spent > (run.timeout or TEST_TIMEOUT) then
            -- Abandon it. The coroutine is simply dropped -- there is no way to unwind one from
            -- outside - so whatever it was holding is left to the teardowns, which is why they
            -- belong to the runner and not to the test.
            run.err = run.err + 1
            Record(run.name, "error",
                format("ERROR %s: timed out after %ds", run.name, run.timeout or TEST_TIMEOUT), "ffff8800")
            RunTeardowns()
            run.co, run.wait = nil, nil
            run.index = run.index + 1
            run.phase = nil
        end
    end

    if run.wait and run.wait > 0 then
        run.wait = run.wait - elapsed
        if run.wait > 0 then return end
    end
    run.wait = nil

    while run and Step() do end
end)

--- Runs the suite. Returns immediately -- `onDone` fires when the last test has finished.
local function RunAllTests(onDone, crossReloads)
    if run then
        print("|cffff8800[DebindTest]|r already running.")
        return
    end

    wipe(results)
    wipe(teardowns)
    UI.Reset()

    run = {
        index = 1, pass = 0, fail = 0, err = 0, skip = 0, reloads = 0,
        lines = {}, onDone = onDone, crossReloads = crossReloads,
    }
    Persist()
    -- **The user's bindings go away for the length of the run.** Switching back is the runner's,
    -- not a test's: one that fails early would otherwise leave them switched off.
    SetIsolated(true)
    UI.SetRunning(true)
    runner:Show()
end

--- Picks a stored run back up. Called once, after saved variables are available.
---
--- A stored run that was not expecting a reload means the session ended under it -- crash,
--- disconnect, or a `/reload` typed by hand. That is reported rather than continued: carrying on
--- would erase the one fact worth keeping, which is that it died at that test.
--- **The stored run is not cleared until the resumed one is standing.** It used to go first, so
--- anything that threw between there and `runner:Show()` took the record with it -- the run did
--- not continue and the results of every test before the reload were gone, with nothing left to
--- say why. Now the failure is reported, the report survives, and it is not retried on the next
--- login either.
local function ResumeStoredRun()
    local pending = DB().pending
    if not pending then return end

    if not pending.expectReload then
        DB().pending = nil
        local name = testOrder[pending.index] or "?"
        print(format("|cffff8800[DebindTest]|r the previous run was cut off at %s (no reload was asked for). It is not carried on.",
            name))
        local died = format("DIED %s: the session ended partway through this test", name)
        tinsert(pending.lines, died)
        lastResultText = table.concat(pending.lines, "\n")
        DB().last = lastResultText
        -- **The failure list is rewritten too, or it answers for the run before this one.** A
        -- reader who presses [Copy failures] after a run died would otherwise be handed a stale list
        -- with nothing saying so, and the death itself -- the one thing worth reading -- would not
        -- be in it.
        lastFailureText = FailuresText(died, pending.results)
        DB().lastFailures = lastFailureText
        return
    end

    wipe(results)
    for testName, result in pairs(pending.results or {}) do
        results[testName] = result
    end
    wipe(teardowns)

    run = {
        index = pending.index, pass = pending.pass, fail = pending.fail, err = pending.err,
        skip = pending.skip or 0,
        reloads = pending.reloads, lines = pending.lines, phase = pending.phase,
        crossReloads = pending.crossReloads,
    }

    print(format("|cff00ccff[DebindTest]|r carrying on after the reload: %s (%s)",
        testOrder[run.index] or "?", tostring(run.phase)))

    local ok, err = pcall(function()
        UI.Open()
        UI.Reset()
        SetIsolated(true)
        UI.SetRunning(true)
        runner:Show()
    end)

    DB().pending = nil

    if not ok then
        run = nil
        runner:Hide()
        print(format("|cffff0000[DebindTest]|r picking the run back up raised: %s", tostring(err)))
        local failed = format("RESUME FAILED %s: %s", testOrder[pending.index] or "?", tostring(err))
        tinsert(pending.lines, failed)
        lastResultText = table.concat(pending.lines, "\n")
        DB().last = lastResultText
        lastFailureText = FailuresText(failed, pending.results)
        DB().lastFailures = lastFailureText
    end
end

--- Ends the session and starts the suite from the top when it comes back.
---
--- **A run is not the same thing twice.** The session a tester has been playing in has cast,
--- moved, entered combat and rebuilt bindings a hundred times before the first test starts; a
--- freshly logged-in one has not. A suite that reads secure state and the game's own binding
--- table is exactly where those two come apart, and this is the button that says which of them
--- was measured.
---
--- `ReloadUI` is protected, so the reload has to ride a hardware event -- which is why this is
--- reached from a click and not decided by the runner (see `DEBINDTEST_RELOAD`).
local function RequestFreshRun()
    if run then
        print("|cffff8800[DebindTest]|r already running.")
        return
    end

    -- A stored run is picked back up on the other side and would hold the runner before this
    -- request could reach it. The button says *from the top*, so the stored one is dropped rather
    -- than continued.
    DB().pending = nil

    -- The checkbox lives in memory and the session is about to end. Carried across, because the
    -- run on the other side is the one the tester set it for.
    DB().autorun = { skipBlackout = skipBlackout }

    ReloadUI()
end

--- Starts the run asked for before the reload. Called once, after saved variables are available.
---
--- The request is cleared before the run rather than after: whatever the run does to the session,
--- it must not be able to ask for another login that starts it again.
local function StartRequestedRun()
    local request = DB().autorun
    if not request then return end
    DB().autorun = nil

    -- Set before the window is built -- the checkbox reads this when it is created, so writing it
    -- afterwards would leave the box unticked while the run behind it honoured the tick.
    skipBlackout = request.skipBlackout and true or false

    print("|cff00ccff[DebindTest]|r running from the top after the reload.")
    UI.Open()
    RunAllTests()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= "Debind" then return end
        self:UnregisterEvent("ADDON_LOADED")

        -- Everything this file reads off Debind, taken at the first moment it exists. A release
        -- build never sets the global at all (`Debind.lua` parks it under `DEBUG`), and then the
        -- kit stays inert rather than erroring: nothing below runs before `PLAYER_LOGIN`.
        DebindPrivate = _G.DebindPrivate
        if not DebindPrivate then
            print("|cffff0000[DebindTest]|r DebindPrivate not found. Enable DEBUG mode in Constants.lua.")
            return
        end
        Constants = DebindPrivate.Constants
        LLL = DebindPrivate.L
        DebindUI = DebindPrivate.DebindUI
        BuildConstantTables()
        BuildGappedSweep()
        return
    end

    self:UnregisterAllEvents()
    if not DebindPrivate then return end

    DB()

    -- Waiting for login rather than ADDON_LOADED: a resumed run drives bindings and unit frames
    -- immediately, and neither is meaningfully in place before the player is.
    ResumeStoredRun()
    StartRequestedRun()
end)

-----------------------------------------------------------
-- UI (optional, simple scrollable results viewer)
-----------------------------------------------------------

local TestFrame
local rows = {}
local activeTest

-- Real icons, not letters -- the pass mark was a lowercase `v`.
--
-- **A texture object, not `|T...|t` in the label.** The first attempt put the old
-- `Interface\RaidFrame\ReadyCheck-*` paths in font markup; retail moved those to atlases
-- (`ReadyCheck.lua:1-4`), so the file was gone and markup that resolves to nothing draws
-- nothing -- silently, which is how it shipped looking like no icon at all. A texture asked for
-- an atlas by name either shows or is visibly wrong.
local STATUS_ATLAS = {
    pass = "UI-LFG-ReadyMark",
    fail = "UI-LFG-DeclineMark",
    error = "UI-LFG-PendingMark",
}

-- The quiet states are drawn rather than named, so they cannot depend on an art asset at all.
local STATUS_DOT = {
    skip = { 0.45, 0.45, 0.45 },
    pending = { 0.30, 0.30, 0.30 },
    active = { 1.00, 0.82, 0.20 },
}

--- Paints one row's marker. `status` is a key of either table above.
local function SetRowMark(row, status)
    local atlas = STATUS_ATLAS[status]
    if atlas then
        row.icon:SetSize(16, 16)
        row.icon:SetAtlas(atlas)
        return
    end

    local dot = STATUS_DOT[status] or STATUS_DOT.pending
    row.icon:SetSize(status == "active" and 10 or 7, status == "active" and 10 or 7)
    row.icon:SetColorTexture(dot[1], dot[2], dot[3], 1)
end

--- The tally above the list.
---
--- **Counted from `results`, not from the runner's own totals.** They are the same number while a
--- run is on and only one of them exists at any other time -- before a run, after one, and in the
--- session that resumes one. Counting the rows means the line is right in all four.
---
--- Zero counts are left out rather than shown as zero. A row of red zeroes reads as a report; the
--- absence of the word Fail is the report.
local function UpdateSummary()
    if not TestFrame then return end

    local pass, fail, err, skip = 0, 0, 0, 0
    for _, testName in ipairs(testOrder) do
        local result = results[testName]
        if result then
            if result.status == "pass" then
                pass = pass + 1
            elseif result.status == "fail" then
                fail = fail + 1
            elseif result.status == "skip" then
                skip = skip + 1
            else
                err = err + 1
            end
        end
    end

    local total = #testOrder
    local parts = { format("|cffccccccTotal %d|r", total), format("|cff00ff00Pass %d|r", pass) }
    if fail > 0 then parts[#parts + 1] = format("|cffff4444Fail %d|r", fail) end
    if err > 0 then parts[#parts + 1] = format("|cffff8800Error %d|r", err) end
    if skip > 0 then parts[#parts + 1] = format("|cff888888Skip %d|r", skip) end

    local left = total - (pass + fail + err + skip)
    if left > 0 then parts[#parts + 1] = format("|cff666666Left %d|r", left) end

    TestFrame.summary:SetText(table.concat(parts, "   "))
end

--- Repaints one row from whatever is known about that test right now.
---
--- **Rows are built once and repainted**, where the old window rebuilt them on open and returned
--- early if it already existed -- so a run's results never reached it and it always showed the
--- state it was first opened in.
local function PaintRow(testName)
    local row = rows[testName]
    if not row then
        return
    end

    local result = results[testName]
    SetRowMark(row, result and result.status or (activeTest == testName and "active" or "pending"))

    local text = testName
    if result and result.msg then
        local clean = result.msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        text = text .. "  " .. (result.status == "pass" and "|cff888888" or "|cffff8888") .. clean .. "|r"
    else
        -- Nothing has been asked of this test yet. The description says what it is for, so the
        -- list reads as a plan before it reads as a report.
        local test = tests[testName]
        if test and test.description then
            text = text .. "  |cff666666" .. test.description .. "|r"
        end
        if test and test.crossesReload then
            text = text .. " |cff7788aa[reload]|r"
        end
    end
    row.text:SetText(text)
    row.highlight:SetShown(activeTest == testName)

    UpdateSummary()
end

--- Paints every row from scratch. Called when the list is first built and whenever the results
--- table is emptied -- clearing `results` alone leaves the previous run's verdicts on screen
--- until each test happens to run again, which reads as a run that is already half done.
local function PaintAllRows()
    for _, testName in ipairs(testOrder) do
        PaintRow(testName)
    end
end

local function BuildRows(content)
    local y = 0
    for _, testName in ipairs(testOrder) do
        local test = tests[testName]

        local row = CreateFrame("Frame", nil, content)
        row:SetSize(590, 28)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(0.2, 0.4, 0.1, 0.6)
        row.highlight:Hide()

        -- Centred in a fixed slot, because the marker changes size with the status and the label
        -- must not move with it.
        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetPoint("CENTER", row, "LEFT", 13, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 26, 0)
        row.text:SetWidth(560)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(testName, 1, 1, 1)
            if test.description then
                GameTooltip:AddLine(test.description, nil, nil, nil, true)
            end
            local result = results[testName]
            if result and result.msg then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(result.msg, nil, nil, nil, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)

        local sep = row:CreateTexture(nil, "BACKGROUND")
        sep:SetColorTexture(0.3, 0.3, 0.3, 0.3)
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)

        rows[testName] = row
        y = y + 28
    end
    content:SetHeight(y)

    -- **Built is not painted.** The row frames existed from the first open, but nothing filled
    -- them in until the runner reached that test -- so the window came up as a stack of blank
    -- lines and the suite only became visible by running it. The list is meant to be readable
    -- before anyone presses Run.
    PaintAllRows()
end

local function CreateTestUI()
    if TestFrame then
        TestFrame:Show()
        return TestFrame
    end

    local f = CreateFrame("Frame", "DebindTestFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(650, 500)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f.TitleText:SetText("Debind Test")

    f.runBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.runBtn:SetSize(100, 24)
    f.runBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -30)
    f.runBtn:SetText("Run")
    f.runBtn:SetScript("OnClick", function()
        RunAllTests()
    end)

    -- **The reload run is a button, not a slash command.** Ending the session is the one thing in
    -- here that costs the tester something, and the place they decide it should be the place they
    -- are already looking -- next to the run they were going to press anyway.
    f.reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reloadBtn:SetSize(120, 24)
    f.reloadBtn:SetPoint("RIGHT", f.runBtn, "LEFT", -6, 0)
    f.reloadBtn:SetText("With reload")
    -- No `onDone`. **Finishing does not open the copy window** -- the results are in this list and
    -- the Copy button is right here. A popup that covers the list the moment it becomes worth
    -- reading is the opposite of the one-window shape.
    f.reloadBtn:SetScript("OnClick", function()
        RunAllTests(nil, true)
    end)
    f.reloadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Run including reload", 1, 1, 1)
        GameTooltip:AddLine("Runs the tests that have to cross a /reload as well. The session is cut once, at that point.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    f.reloadBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Second row rather than beside the other two: the button row is also where the tally is
    -- written, and a fourth button there pushes it off the left edge on a run that has something
    -- to report.
    f.freshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.freshBtn:SetSize(130, 24)
    f.freshBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -58)
    f.freshBtn:SetText("Reload, then run")
    f.freshBtn:SetScript("OnClick", function()
        RequestFreshRun()
    end)
    f.freshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reload, then run", 1, 1, 1)
        GameTooltip:AddLine(
            "Reloads now, and on the way back opens the window and runs from the top. The point is to measure on a "
            .. "freshly logged in session rather than on whatever this one has accumulated. Same scope as |cffffff00Run|r, so "
            .. "the tests that have to cross a /reload are skipped.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    f.freshBtn:SetScript("OnLeave", GameTooltip_Hide)

    f.copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.copyBtn:SetSize(100, 24)
    f.copyBtn:SetPoint("RIGHT", f.reloadBtn, "LEFT", -6, 0)
    f.copyBtn:SetText("Copy")
    f.copyBtn:SetScript("OnClick", function()
        if lastResultText ~= "" then
            ShowCopyableText(lastResultText)
        else
            local stored = DB().last
            ShowCopyableText(stored or "Nothing has been run yet.")
        end
    end)

    -- **The list somebody actually reads after a run.** A full report is sixty lines of PASS with
    -- two failures somewhere in it, and the first thing anyone does with it is search. This hands
    -- over the two.
    --
    -- Beside [Copy] rather than instead of it: the whole report is what to keep when the question is
    -- "what did this build do", and that is a different question from "what do I fix now".
    f.copyFailBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.copyFailBtn:SetSize(100, 24)
    -- **Under [Copy] rather than beside it.** The top row already reaches within 290 of the left
    -- edge and the tally sits there; one more button on it would run into the numbers. Under it the
    -- pair reads as a pair, and the second row has nothing between here and [Reload, then run].
    f.copyFailBtn:SetPoint("TOP", f.copyBtn, "BOTTOM", 0, -4)
    f.copyFailBtn:SetText("Copy failures")
    f.copyFailBtn:SetScript("OnClick", function()
        if lastFailureText ~= "" then
            ShowCopyableText(lastFailureText)
        else
            local stored = DB().lastFailures
            ShowCopyableText(stored or "Nothing has been run yet.")
        end
    end)
    f.copyFailBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Copy failures", 1, 1, 1)
        GameTooltip:AddLine(
            "Opens just the failures and errors from the last run. Skipped ones are left out, "
            .. "since nothing was wrong with them. The whole tally comes along underneath.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    f.copyFailBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- The tally, on the button row -- the first thing to read, level with the thing that changes
    -- it.
    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.summary:SetPoint("LEFT", f, "TOPLEFT", 16, -42)
    f.summary:SetJustifyH("LEFT")

    -- Second row, out of the tally's way. It changes what pressing the buttons does, so it stays
    -- with them rather than going somewhere quieter.
    f.keepBindings = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.keepBindings:SetSize(24, 24)
    f.keepBindings:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -58)
    f.keepBindings.text:SetText("Keep existing bindings")
    f.keepBindings:SetChecked(skipBlackout)
    f.keepBindings:SetScript("OnClick", function(self)
        skipBlackout = self:GetChecked() and true or false
    end)
    f.keepBindings:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Keep existing bindings", 1, 1, 1)
        GameTooltip:AddLine(
            "Normally every existing game binding is cleared for the length of a run, which is what makes the answer the same on any machine. "
            .. "Ticked, the run leaves them alone. It is here to tell which failures that clearing caused, not as a setting.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    f.keepBindings:SetScript("OnLeave", GameTooltip_Hide)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -86)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(590, 1)
    scrollFrame:SetScrollChild(content)
    BuildRows(content)

    -- Where a test parks the frame it wants clicked. Sits over the middle of the list, which is
    -- the one place it cannot be missed, and is hidden the moment the click lands.
    f.clickSlot = CreateFrame("Frame", nil, f)
    f.clickSlot:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.clickSlot:SetSize(420, 160)
    f.clickSlot:SetFrameStrata("FULLSCREEN_DIALOG")
    f.clickSlot:Hide()

    local slotBg = f.clickSlot:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 0.92)

    f.clickSlot.label = f.clickSlot:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.clickSlot.label:SetPoint("TOP", f.clickSlot, "TOP", 0, -14)
    f.clickSlot.label:SetWidth(390)
    f.clickSlot.label:SetJustifyH("CENTER")

    f.clickSlot.target = CreateFrame("Frame", nil, f.clickSlot)
    f.clickSlot.target:SetPoint("BOTTOM", f.clickSlot, "BOTTOM", 0, 16)
    f.clickSlot.target:SetSize(380, 90)

    TestFrame = f
    -- `BuildRows` ran before this assignment, so the tally it tried to write had nowhere to go.
    UpdateSummary()
    return f
end

function UI.Open()
    return CreateTestUI()
end

function UI.Update(testName)
    PaintRow(testName)
end

--- Puts the list back to "nothing has run yet". The runner calls this when it empties `results`.
function UI.Reset()
    PaintAllRows()
end

--- A second run cannot start while one is going -- `RunAllTests` refuses it -- so the button
--- says so rather than letting it be pressed and answering in the chat frame.
function UI.SetRunning(running)
    if TestFrame then
        TestFrame.runBtn:SetEnabled(not running)
        TestFrame.runBtn:SetText(running and "Running" or "Run")
        TestFrame.reloadBtn:SetEnabled(not running)
        TestFrame.freshBtn:SetEnabled(not running)
    end
end

--- Marks the test the runner is on, and scrolls nothing -- the list is short enough to see.
function UI.SetActive(testName)
    local previous = activeTest
    activeTest = testName
    if previous then PaintRow(previous) end
    if testName then PaintRow(testName) end
end

--- Puts a frame in the middle of the window and says what to do with it.
---
--- Blizzard's frames are asked for where they already are: moving or resizing one to make it
--- convenient would be the addon reaching into it, which is the thing these tests exist to
--- confirm it stopped doing.
function UI.ShowClickTarget(frame, text)
    local f = CreateTestUI()
    f.clickSlot.label:SetText(text)
    f.clickSlot:Show()

    -- **A frame we leave alone is not in here**, so the box that says "here" would be pointing at
    -- itself. The overlay shrinks to the line of text and the text is what says where to go.
    f.clickSlot.target:SetShown(not frame.debindTestLeaveAlone)
    if frame.debindTestLeaveAlone then
        f.clickSlot:SetSize(420, 60)
    else
        f.clickSlot:SetSize(420, 160)
    end

    if not frame.debindTestLeaveAlone then
        frame:SetParent(f.clickSlot.target)
        frame:ClearAllPoints()
        frame:SetAllPoints(f.clickSlot.target)
        frame:SetFrameStrata("FULLSCREEN_DIALOG")

        if not frame.debindTestSkin then
            frame.debindTestSkin = frame:CreateTexture(nil, "BACKGROUND")
            frame.debindTestSkin:SetAllPoints()
            frame.debindTestSkin:SetColorTexture(0.15, 0.35, 0.55, 1)
            frame.debindTestSkinText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            frame.debindTestSkinText:SetPoint("CENTER")
            frame.debindTestSkinText:SetText("here")
        end
        frame:Show()
    end

    -- **Registered here, not at the call site.** Whatever happens to the test after this, the
    -- runner takes the overlay down -- otherwise a test that fails early leaves the window
    -- covered by the very thing that was meant to help read it.
    AddTeardown(function() UI.HideClickTarget() end)
end

function UI.HideClickTarget()
    if TestFrame then
        TestFrame.clickSlot:Hide()
    end
end

-----------------------------------------------------------
-- Slash Command
-----------------------------------------------------------

SLASH_DEBINDTEST1 = "/debtest"
SlashCmdList["DEBINDTEST"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "ui" then
        CreateTestUI()
    elseif msg == "copy" then
        if lastResultText ~= "" then
            ShowCopyableText(lastResultText)
        else
            print("|cff00ccff[DebindTest]|r no results yet. Start with |cffffff00Run|r in the |cffffff00/debtest|r window.")
        end
    elseif msg == "last" then
        local stored = DB().last
        if stored then
            ShowCopyableText(stored)
        else
            print("|cff00ccff[DebindTest]|r no stored results.")
        end
    else
        -- **Opening does not run.** These tests cast, and one of them stops to ask for a click;
        -- a window opened to read the last results should not start any of that. The run is a
        -- button because pressing it is the point at which someone meant it.
        UI.Open()
    end
end

print("|cff00ccff[DebindTest]|r Loaded. |cffffff00/debtest|r = the list window. Run it from the |cffffff00Run|r / |cffffff00With reload|r / |cffffff00Reload, then run|r buttons inside it. |cffffff00/debtest last|r = the previous results.")
