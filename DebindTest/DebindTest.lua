-- DebindTest: Integration test framework for Debind addon
-- Usage: /debtest opens the list. Every run is a button in it -- plain, the one that includes the
-- tests which end the session, and the one that reloads first and runs on the other side.
-- Requires DEBUG mode (DebindPrivate must be exposed as global)

local DebindPrivate = _G.DebindPrivate
if not DebindPrivate then
    print("|cffff0000[DebindTest]|r DebindPrivate not found. Enable DEBUG mode in Constants.lua.")
    return
end

local Constants = DebindPrivate.Constants
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
-- for something that had already happened. `devdocs/when-a-change-takes-effect.md` has the whole
-- map, including the two traps in writing a condition to wait on.
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
    DebindTestDB = DebindTestDB or {}
    return DebindTestDB
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
    error("RequestReload: 리로드가 일어나지 않았다")
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
        local real = assert(DebindPrivate.GetProfileLayer(1), "프로필이 아직 안 올라왔다")
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
        return nil, "전투 중에는 바인딩을 건드릴 수 없다"
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
                print(format("|cffff8800[DebindTest]|r 기존 바인딩 끄기가 터졌다: %s. 그대로 진행한다.",
                    tostring(cleared)))
            elseif not cleared then
                print(format("|cffff8800[DebindTest]|r 기존 바인딩을 못 껐다: %s. 테스터의 키가 깔려 있는 채로 돈다.", err))
            elseif cleared > 0 then
                print(format("|cff00ccff[DebindTest]|r 기존 바인딩 %d개를 껐다. 런이 끝나면 되돌린다.", cleared))
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

local function InsertAction(action)
    local layer = GetTestLayer()
    layer:Insert(action)
    -- 순서 번호는 레이어가 준다. 안 주면 같은 조건끼리 seq가 전부 nil이라 발동 순서가
    -- 정해지지 않고, 삽입 순서를 기대하는 테스트가 정렬 구현에 따라 흔들린다.
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

-- KeyMap에서 특정 키에 바인딩된 정보 찾기
local function GetKeyBindings(key)
    local keyMap = DebindPrivate.KeyMap
    return keyMap[key]
end

-- KeyMap에서 특정 키의 N번째 바인딩 정보
local function GetNthBinding(key, n)
    local bindings = GetKeyBindings(key)
    return bindings and bindings[n]
end

-- DefaultClickFrame의 attribute 확인
local function GetClickAttribute(attrPrefix, buttonName)
    local frame = DebindPrivate.DefaultClickFrame
    return frame:GetAttribute(attrPrefix .. buttonName)
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
        return false, format("%s 는 클릭 시점 키가 아니다 (ClickTimeKeys에 없음)", key)
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
        return false, "등록된 프레임이 아니다 (ccframes에 없음)"
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
        return nil, format("RegisterFrame이 %s를 안 받았다 (ccframes=%s)", name, tostring(registered))
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

--- What the secure side currently calls the hovered unit, as seen from outside. The secure
--- `SetUnit` mirrors it out through `CallMethod`, and that is a call rather than a queue, so
--- after `HoverEnter`/`HoverLeave` this is already true in the same breath.
local function GetHoverUnit()
    return DebindPrivate.Units.hover
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
-- Test Cases: Action Types
-----------------------------------------------------------

RegisterTest("Spell binding", {
    description = "주문 타입 액션이 바인딩되고 attribute가 설정되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD1" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD1", 1)
        if not b then return Fail("Spell binding", "NUMPAD1 not in KeyMap") end
        if b.type ~= Constants.SPELL then return Fail("Spell binding", "type=" .. tostring(b.type)) end
        if not b.clickbutton then return Fail("Spell binding", "no clickbutton assigned") end
        local spellAttr = GetClickAttribute("*type-", b.clickbutton)
        if spellAttr ~= "spell" then return Fail("Spell binding", "*type-=" .. tostring(spellAttr)) end
        return Pass("Spell binding", "clickbutton=" .. b.clickbutton)
    end,
})

RegisterTest("Item binding", {
    description = "아이템 타입 액션이 바인딩되는지",
    run = function()
        InsertAction({ type = Constants.ITEM, value = 6948, key = "NUMPAD2" }) -- Hearthstone
        ApplyBindings()
        local b = GetNthBinding("NUMPAD2", 1)
        if not b then return Fail("Item binding", "NUMPAD2 not in KeyMap") end
        local typeAttr = GetClickAttribute("*type-", b.clickbutton)
        if typeAttr ~= "item" then return Fail("Item binding", "*type-=" .. tostring(typeAttr)) end
        local itemAttr = GetClickAttribute("*item-", b.clickbutton)
        if itemAttr ~= "item:6948" then return Fail("Item binding", "*item-=" .. tostring(itemAttr)) end
        return Pass("Item binding")
    end,
})

RegisterTest("Macrotext binding", {
    description = "매크로텍스트 액션이 바인딩되는지",
    run = function()
        InsertAction({ type = Constants.MACROTEXT, value = "/say test", key = "NUMPAD3", name = "test macro" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD3", 1)
        if not b then return Fail("Macrotext binding", "NUMPAD3 not in KeyMap") end
        local typeAttr = GetClickAttribute("*type-", b.clickbutton)
        if typeAttr ~= "macro" then return Fail("Macrotext binding", "*type-=" .. tostring(typeAttr)) end
        return Pass("Macrotext binding")
    end,
})

RegisterTest("Command binding", {
    description = "커맨드 타입은 SetOverrideBinding 방식 - KeyMap에 들어가는지",
    run = function()
        InsertAction({ type = Constants.COMMAND, value = "TOGGLECHARACTER0", key = "NUMPAD4" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD4", 1)
        if not b then return Fail("Command binding", "NUMPAD4 not in KeyMap") end
        if b.type ~= Constants.COMMAND then return Fail("Command binding", "type=" .. tostring(b.type)) end
        return Pass("Command binding")
    end,
})

RegisterTest("Target binding", {
    description = "대상 지정 액션이 바인딩되는지",
    run = function()
        InsertAction({ type = Constants.TARGET, key = "NUMPAD5", unit = "focus" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD5", 1)
        if not b then return Fail("Target binding", "NUMPAD5 not in KeyMap") end
        local typeAttr = GetClickAttribute("*type-", b.clickbutton)
        if typeAttr ~= "target" then return Fail("Target binding", "*type-=" .. tostring(typeAttr)) end
        return Pass("Target binding")
    end,
})

RegisterTest("Unused binding", {
    description = "UNUSED 타입은 attribute 없이 KeyMap에만 존재하는지",
    run = function()
        InsertAction({ type = Constants.UNUSED, key = "NUMPAD6" })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD6", 1)
        if not b then return Fail("Unused binding", "NUMPAD6 not in KeyMap") end
        if b.type ~= Constants.UNUSED then return Fail("Unused binding", "type=" .. tostring(b.type)) end
        return Pass("Unused binding")
    end,
})

--- An imported action reaches no key at all until the badge comes off.
---
--- **It is the one promise this addon makes about importing, and this is the only place it is
--- checked.** Headless does not load `Debind.lua`, which is where `BuildKeyMap` lives, and the
--- static checks cannot see the game. Break it and pasting a string is the moment somebody else's
--- keys go live, which is precisely what quarantine is for.
---
--- **Both directions, and the game is asked in both.** "It did not bind" on its own passes for an
--- action that was never going to bind anyway, so the same action with only the badge removed has
--- to be seen binding before the badge can be called the cause. And `KeyMap` on its own is our own
--- bookkeeping: an override left behind from an earlier build makes the key still fire while our
--- table says nothing is there, so each half reads `GetBindingAction` as well.
---
--- No waiting anywhere in here, and that is not an oversight. `ApplyBindings` calls
--- `UpdateBindings` directly, which finishes the state pass and the bindings inside the call, and
--- `SetOverrideBinding` is what `GetBindingAction` reads - so both are answered by the time the
--- line after returns. The file header has the full map.
RegisterTest("Import quarantine", {
    description = "가져오기 배지가 붙어 있는 동안 키에 안 걸리고, 떼면 걸리는지",
    run = function()
        local NAME = "Import quarantine"
        local KEY = "NUMPAD7"

        local action = InsertAction({ type = Constants.SPELL, value = 585, key = KEY, imported = 1 })
        ApplyBindings()

        if GetNthBinding(KEY, 1) then
            return Fail(NAME, "배지가 붙었는데 KeyMap에 들어갔다")
        end
        local quarantined = GetBindingAction(KEY, true) or ""
        if quarantined ~= "" then
            return Fail(NAME, "배지가 붙었는데 키가 걸려 있다: " .. quarantined)
        end

        -- Taking the badge off is the whole of accepting (`ApproveImportedActions`).
        action.imported = nil
        ApplyBindings()

        if not GetNthBinding(KEY, 1) then
            return Fail(NAME, "배지를 뗐는데도 KeyMap에 안 들어간다 - 앞 절반이 무의미해진다")
        end
        -- `CLICK ` is what a bound action looks like to the game: every type goes out through a
        -- click button, so the prefix is the whole assertion available here.
        local accepted = GetBindingAction(KEY, true) or ""
        if accepted:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("배지를 뗐는데 게임에는 안 걸렸다: %q", accepted))
        end
        return Pass(NAME)
    end,
})

-----------------------------------------------------------
-- Test Cases: Conditions
-----------------------------------------------------------

RegisterTest("Combat condition", {
    description = "전투 조건이 바인딩 정보에 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD7", combat = true })
        InsertAction({ type = Constants.SPELL, value = 116, key = "NUMPAD7", combat = false })
        ApplyBindings()
        local bindings = GetKeyBindings("NUMPAD7")
        if not bindings or #bindings < 2 then
            return Fail("Combat condition", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        local hasCombatTrue, hasCombatFalse = false, false
        for i = 1, #bindings do
            if bindings[i].combat == true then hasCombatTrue = true end
            if bindings[i].combat == false then hasCombatFalse = true end
        end
        if not (hasCombatTrue and hasCombatFalse) then
            return Fail("Combat condition", format("combatTrue=%s, combatFalse=%s", tostring(hasCombatTrue), tostring(hasCombatFalse)))
        end
        return Pass("Combat condition", "2 bindings with combat true/false")
    end,
})

RegisterTest("Group condition", {
    description = "그룹 조건(파티/레이드) 비트플래그가 바인딩에 반영되는지",
    run = function()
        local groups = bor(Constants.GROUP_PARTY, Constants.GROUP_RAID)
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD8", groups = groups })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD8", 1)
        if not b then return Fail("Group condition", "NUMPAD8 not in KeyMap") end
        if b.groups ~= groups then
            return Fail("Group condition", format("expected groups=%d, got %s", groups, tostring(b.groups)))
        end
        return Pass("Group condition", format("groups=%d", b.groups))
    end,
})

RegisterTest("Stealth condition", {
    description = "은신 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD9", stealth = true })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD9", 1)
        if not b then return Fail("Stealth condition", "NUMPAD9 not in KeyMap") end
        if b.stealth ~= true then return Fail("Stealth condition", "stealth=" .. tostring(b.stealth)) end
        return Pass("Stealth condition")
    end,
})

RegisterTest("Pet condition", {
    description = "펫 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "NUMPAD0", pet = true })
        ApplyBindings()
        local b = GetNthBinding("NUMPAD0", 1)
        if not b then return Fail("Pet condition", "NUMPAD0 not in KeyMap") end
        if b.pet ~= true then return Fail("Pet condition", "pet=" .. tostring(b.pet)) end
        return Pass("Pet condition")
    end,
})

RegisterTest("Forms condition", {
    description = "변신/자세 조건 비트플래그가 반영되는지",
    run = function()
        local forms = bor(2^0, 2^1) -- form 0 and form 1
        InsertAction({ type = Constants.SPELL, value = 585, key = "F5", forms = forms })
        ApplyBindings()
        local b = GetNthBinding("F5", 1)
        if not b then return Fail("Forms condition", "F5 not in KeyMap") end
        if b.forms ~= forms then
            return Fail("Forms condition", format("expected forms=%d, got %s", forms, tostring(b.forms)))
        end
        return Pass("Forms condition", format("forms=%d", b.forms))
    end,
})

RegisterTest("Bonusbars condition", {
    description = "보너스바 조건 비트플래그가 반영되는지",
    run = function()
        local bonusbars = bor(2^0, 2^1) -- bonusbar 0 and 1
        InsertAction({ type = Constants.SPELL, value = 585, key = "F6", bonusbars = bonusbars })
        ApplyBindings()
        local b = GetNthBinding("F6", 1)
        if not b then return Fail("Bonusbars condition", "F6 not in KeyMap") end
        if b.bonusbars ~= bonusbars then
            return Fail("Bonusbars condition", format("expected bonusbars=%d, got %s", bonusbars, tostring(b.bonusbars)))
        end
        return Pass("Bonusbars condition", format("bonusbars=%d", b.bonusbars))
    end,
})

RegisterTest("Specialbar condition", {
    description = "특수바(차량/변형) 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F7", specialbar = true })
        ApplyBindings()
        local b = GetNthBinding("F7", 1)
        if not b then return Fail("Specialbar condition", "F7 not in KeyMap") end
        if b.specialbar ~= true then return Fail("Specialbar condition", "specialbar=" .. tostring(b.specialbar)) end
        return Pass("Specialbar condition")
    end,
})

RegisterTest("Extrabar condition", {
    description = "추가 액션바 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F8", extrabar = true })
        ApplyBindings()
        local b = GetNthBinding("F8", 1)
        if not b then return Fail("Extrabar condition", "F8 not in KeyMap") end
        if b.extrabar ~= true then return Fail("Extrabar condition", "extrabar=" .. tostring(b.extrabar)) end
        return Pass("Extrabar condition")
    end,
})

RegisterTest("Petbattle condition", {
    description = "펫 배틀 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F9", petbattle = false })
        ApplyBindings()
        local b = GetNthBinding("F9", 1)
        if not b then return Fail("Petbattle condition", "F9 not in KeyMap") end
        if b.petbattle ~= false then return Fail("Petbattle condition", "petbattle=" .. tostring(b.petbattle)) end
        return Pass("Petbattle condition")
    end,
})

RegisterTest("Known condition", {
    description = "주문 습득 조건이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F10", known = true })
        ApplyBindings()
        local b = GetNthBinding("F10", 1)
        if not b then return Fail("Known condition", "F10 not in KeyMap") end
        if b.known ~= true then return Fail("Known condition", "known=" .. tostring(b.known)) end
        return Pass("Known condition")
    end,
})

RegisterTest("Custom state condition", {
    description = "커스텀 상태 조건($state1~5)이 반영되는지",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "F11", ["$state1"] = true })
        InsertAction({ type = Constants.SPELL, value = 116, key = "F11", ["$state1"] = false })
        ApplyBindings()
        local bindings = GetKeyBindings("F11")
        if not bindings or #bindings < 2 then
            return Fail("Custom state condition", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        local hasTrue, hasFalse = false, false
        for i = 1, #bindings do
            if bindings[i]["$state1"] == true then hasTrue = true end
            if bindings[i]["$state1"] == false then hasFalse = true end
        end
        if not (hasTrue and hasFalse) then
            return Fail("Custom state condition", format("true=%s, false=%s", tostring(hasTrue), tostring(hasFalse)))
        end
        return Pass("Custom state condition")
    end,
})

RegisterTest("Hover condition with reactions", {
    description = "호버 조건 + 반응(아군/적군) 비트플래그가 반영되는지",
    run = function()
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            checkedUnits = { hover = { reaction = bor(Constants.REACTION_HELP, Constants.REACTION_HARM) } },
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()
        local b = GetNthBinding("BUTTON3", 1)
        if not b then return Fail("Hover condition", "BUTTON3 not in KeyMap") end
        if b.hover ~= true then return Fail("Hover condition", "hover=" .. tostring(b.hover)) end
        if band(b.reactions, Constants.REACTION_HELP) == 0 then
            return Fail("Hover condition", "REACTION_HELP not set")
        end
        if b.frameTypes ~= Constants.FRAMETYPE_GROUP then
            return Fail("Hover condition", "frameTypes=" .. tostring(b.frameTypes))
        end
        return Pass("Hover condition", format("reactions=%d, frameTypes=%d", b.reactions, b.frameTypes))
    end,
})

RegisterTest("CheckedUnits condition", {
    description = "유닛 존재 확인 조건이 반영되는지",
    run = function()
        -- 다른 유닛(focus, pet 등)의 존재를 조건으로 사용
        InsertAction({
            type = Constants.SPELL, value = 585, key = "F12",
            unit = "target",
            checkedUnits = { ["focus"] = true },
        })
        ApplyBindings()
        local b = GetNthBinding("F12", 1)
        if not b then return Fail("CheckedUnits condition", "F12 not in KeyMap") end
        if not b.checkedUnits then
            return Fail("CheckedUnits condition", "checkedUnits is nil")
        end
        if not b.checkedUnits["focus"] then
            return Fail("CheckedUnits condition", "checkedUnits[focus]=" .. tostring(b.checkedUnits["focus"]))
        end
        return Pass("CheckedUnits condition")
    end,
})

-----------------------------------------------------------
-- Test Cases: Priority & Ordering
-----------------------------------------------------------

RegisterTest("Priority ordering", {
    description = "우선순위가 높은 바인딩이 KeyMap에서 먼저 오는지",
    run = function()
        -- 조건이 겹치면 뒤쪽이 UNREACHABLE로 제거되므로 서로 배타적인 조건을 준다.
        -- 삽입 순서(ordinal)는 priority 5가 먼저이므로 정렬이 실제로 동작해야만 통과한다.
        InsertAction({ type = Constants.SPELL, value = 585, key = "INSERT", priority = 5, combat = false }) -- Very Low
        InsertAction({ type = Constants.SPELL, value = 116, key = "INSERT", priority = 1, combat = true }) -- Very High
        ApplyBindings()
        local bindings = GetKeyBindings("INSERT")
        if not bindings or #bindings < 2 then
            return Fail("Priority ordering", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        -- priority 1 (Very High) should come first
        if bindings[1].priority ~= 1 then
            return Fail("Priority ordering", format("first binding priority=%s, expected 1", tostring(bindings[1].priority)))
        end
        if (bindings[2].priority or 3) ~= 5 then
            return Fail("Priority ordering", format("second binding priority=%s, expected 5", tostring(bindings[2].priority)))
        end
        return Pass("Priority ordering", "priority=1 before priority=5")
    end,
})

RegisterTest("Conditional before unconditional", {
    description = "조건부 바인딩이 무조건 바인딩보다 먼저 오는지 (같은 우선순위)",
    run = function()
        InsertAction({ type = Constants.SPELL, value = 585, key = "DELETE" }) -- unconditional
        InsertAction({ type = Constants.SPELL, value = 116, key = "DELETE", combat = true }) -- conditional
        ApplyBindings()
        local bindings = GetKeyBindings("DELETE")
        if not bindings or #bindings < 2 then
            return Fail("Conditional ordering", format("expected 2 bindings, got %d", bindings and #bindings or 0))
        end
        if not bindings[1].isConditional then
            return Fail("Conditional ordering", "first binding is not conditional")
        end
        if bindings[2].isConditional then
            return Fail("Conditional ordering", "second binding is also conditional")
        end
        return Pass("Conditional ordering")
    end,
})

-----------------------------------------------------------
-- Test Cases: Renumbering a key group
--
-- `devdocs/legacy/renumbering-a-key-group.md`. The rule itself is settled headlessly
-- (`tests/renumber_spec.lua`) against `CollectActionsForKey`, which is the list the **window
-- draws**. What only this layer sees is the other end: that the same numbers reach `BuildKeyMap`
-- and the solver, so the order the reader is shown is the order the key actually fires in. Those
-- are two walks over the same profile and nothing but a test makes them agree.
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
    description = "↑↓로 두 레코드의 차례를 바꾸면 넓은 쪽이 좁은 쪽을 덮어 KeyMap에서 빠지는지",
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
            return Fail(NAME, format("좁은 쪽이 앞인데: %s", KeyMapOrder(KEY)))
        end

        -- The function the arrow buttons and the right-click menu both go through. It swaps the two
        -- numbers and renumbers that group.
        DebindPrivate.DebindUI.ApplyOrderSwap(broad, narrow)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "585" then
            return Fail(NAME, format("넓은 쪽이 앞인데: %s", KeyMapOrder(KEY)))
        end

        -- **Swapping back, and watching it come alive again.** Without this the test also passes on
        -- a key that only ever held one record.
        DebindPrivate.DebindUI.ApplyOrderSwap(narrow, broad)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "116 585" then
            return Fail(NAME, format("되돌아오지 않았다: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "116 585 -> 585 -> 116 585")
    end,
})

--- Two bands on one key. **Split by importance** -- splitting by whether there are conditions means
--- that the moment two unconditional records exist one covers the other whole and the solver drops
--- it, and then what is measured is a deletion rather than a position. Four conditions on four
--- different axes, so none of them covers another.
---
--- The numbers are planted **deliberately out of step**. Lined up with the drawn order, this setup
--- measures nothing.
local function InsertTwoBandKey(key)
    local high1 = InsertAction({ type = Constants.SPELL, value = 1, key = key, priority = 1, combat = true })
    local high2 = InsertAction({ type = Constants.SPELL, value = 2, key = key, priority = 1, stealth = true })
    local low1 = InsertAction({ type = Constants.SPELL, value = 3, key = key, pet = true })
    local low2 = InsertAction({ type = Constants.SPELL, value = 4, key = key, petbattle = true })

    high1.seq, high2.seq, low1.seq, low2.seq = 10, 20, 2, 15
    return high1, high2, low1, low2
end

RegisterTest("Renumber: crossing a band lands at the near end", {
    description = "밴드를 넘긴 액션이 그 밴드의 가까운 쪽 끝에 서고, 그 차례로 KeyMap이 서는지",
    run = function()
        local NAME = "Band crossing"
        local KEY = "CTRL-ALT-F2"
        local _, _, _, low2 = InsertTwoBandKey(KEY)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "1 2 3 4" then
            return Fail(NAME, format("심어놓은 차례: %s", KeyMapOrder(KEY)))
        end

        -- One edit passing through closes the group up to 1..4. The invariant stands by induction,
        -- so numbers out of step from an older profile are brought inside it by the first edit that
        -- reaches the group.
        GetTestLayer():RenumberKeyGroup(KEY)

        -- Lift 4 into the upper band. Carrying its 15 along would put it between 10 and 20 -- the
        -- **middle**.
        low2.priority = 1
        DebindPrivate.RenumberKeyGroupForAction(low2)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "1 2 4 3" then
            return Fail(NAME, format("가까운 끝이 아니다: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "1 2 4 3")
    end,
})

RegisterTest("Renumber: an edit inside one band moves nothing", {
    description = "밴드를 안 바꾸는 편집이 KeyMap 차례를 안 흔드는지",
    run = function()
        local NAME = "Band-neutral edit"
        local KEY = "CTRL-ALT-F3"
        local _, _, low1 = InsertTwoBandKey(KEY)
        ApplyBindings()
        GetTestLayer():RenumberKeyGroup(KEY)

        -- One more condition on an action that already has one. `isConditional` is derived, so the
        -- band does not move. Refining conditions is most of what editing is, and losing the place
        -- every time is not on.
        --
        -- combat is the axis to use. Adding stealth would let the upper band's stealth record cover
        -- this one, and then a deletion is measured rather than a position.
        low1.combat = false
        DebindPrivate.RenumberKeyGroupForAction(low1)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "1 2 3 4" then
            return Fail(NAME, format("자리가 움직였다: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "1 2 3 4")
    end,
})

-----------------------------------------------------------
-- Test Cases: A key group whose key has not been decided yet
--
-- A string sent with the keys left out arrives on a **synthetic key**, a number rather than a
-- binding string (`devdocs/building-export-import.md`). Two halves of that only this layer sees:
-- that a number never reaches `BuildKeyMap` even once the badge is off, and that the order the set
-- arrived with is the order the key actually fires in after it is given a real one.
--
-- The headless specs measure both against `CollectActionsForKey`, which is the list the **window**
-- draws. The failure they cannot see is the two walks disagreeing.
-----------------------------------------------------------

RegisterTest("Import: a pending key group reaches nothing, then keeps its order", {
    description = "숫자 키가 KeyMap에 안 서고, 키를 주면 실려온 차례 그대로 발동하는지",
    run = function()
        local NAME = "Pending key group"
        local KEY = "CTRL-ALT-F4"
        -- What `NextSyntheticKey` hands out. Nothing in the game can be bound to it.
        local PENDING = 1

        -- **No badge on any of them**, which is the point: quarantine is what keeps a set out of
        -- the build until the reader accepts, and accepting takes the badge off and leaves the
        -- number. If the two tests were folded into one, this is the moment a dead key appears.
        --
        -- Three conditions on three axes, so none of them covers another and the solver drops none.
        local third = InsertAction({ type = Constants.SPELL, value = 3, key = PENDING, combat = true })
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = PENDING, stealth = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = PENDING, pet = true })
        -- **저장 배열의 차례와 일부러 어긋나게.** 둘이 같으면 아래 차례는 배열 순서를 잰 것이지
        -- 실려온 차례를 잰 것이 아니다.
        third.seq, first.seq, second.seq = 3, 1, 2
        ApplyBindings()

        if GetKeyBindings(PENDING) then
            return Fail(NAME, "숫자 키가 KeyMap에 섰다")
        end
        if GetKeyBindings(KEY) then
            return Fail(NAME, format("전제가 틀렸다 - %s가 이미 차 있다", KEY))
        end

        local group = DebindPrivate.CollectKeyGroupActions(PENDING)
        if #group ~= 3 then
            return Fail(NAME, format("그룹 크기 %d - 숫자 키로 안 모인다", #group))
        end

        DebindPrivate.SetKeyForActions(group, KEY)
        ApplyBindings()

        if KeyMapOrder(KEY) ~= "1 2 3" then
            return Fail(NAME, format("보낸 쪽 차례가 아니다: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "숫자 키는 안 서고, 키를 주니 1 2 3")
    end,
})

-----------------------------------------------------------
-- Test Cases: The export window counts what actually leaves
--
-- **This is the one the headless specs cannot reach.** They check the payload, and separately the
-- window's list is built by code that never runs outside the game. What can go wrong is the two
-- disagreeing - the window says "12 selected" and nine leave - and neither half is wrong on its
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
        return nil, format("봉투가 아니다: %s", tostring(str and str:sub(1, 12)))
    end

    local LibSerialize, LibDeflate = LibStub("LibSerialize", true), LibStub("LibDeflate", true)
    if not LibSerialize or not LibDeflate then
        return nil, "라이브러리가 없다"
    end

    local compressed = LibDeflate:DecodeForPrint(body)
    local serialized = compressed and LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return nil, "못 푼다"
    end

    local ok, payload = LibSerialize:Deserialize(serialized)
    if not ok or type(payload) ~= "table" then
        return nil, "역직렬화 실패"
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

RegisterTest("Export: the window's count is what the string carries", {
    description = "격리 중인 행이 목록에서 빠지고, 창이 센 수와 실제로 나간 수가 같은지",
    run = function()
        local NAME = "Export counts"

        -- Two the tester owns and one still quarantined. A key with both on it is the sharpest
        -- case: the group goes out half, which is right, and a filter that worked per key rather
        -- than per action would send three or one.
        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F5", combat = true })
        InsertAction({ type = Constants.SPELL, value = 589, key = "CTRL-ALT-F5" })
        local badged = InsertAction({ type = Constants.SPELL, value = 6603, key = "CTRL-ALT-F6" })
        badged.imported = 99
        ApplyBindings()

        -- The export tab, opened the way a reader opens it: this is what loads `DebindShare` and
        -- runs the panel's `OnShow`, which is where the list and the selection are built.
        DebindFrame:Show()
        AddTeardown(function() DebindFrame:Hide() end)
        DebindFrame:SelectPanel(3)

        local panel = _G.DebindShareExportPanel
        if not panel or not panel.layers then
            return Fail(NAME, "익스포트 패널을 못 얻었다 - 탭 번호나 LoadAddOn을 볼 것")
        end
        -- The copy dialog takes keyboard focus when it opens (that is what it is for), so it is put
        -- away by the runner rather than left holding it over whatever runs next.
        AddTeardown(function()
            DebindShareCopyFrame.Output.EditBox:ClearFocus()
            DebindShareCopyFrame:Hide()
        end)

        -- What the window says, counted twice the way the window counts it: the [select all] total
        -- walks every listed action, and each header prints its own layer's length.
        local listed = panel:EnumerateListedActions()
        local headerTotal = 0
        for _, layer in ipairs(panel.layers) do
            headerTotal = headerTotal + #layer.actions
        end
        if headerTotal ~= #listed then
            return Fail(NAME, format("머리글 합 %d, 전체 목록 %d", headerTotal, #listed))
        end

        for _, action in ipairs(listed) do
            if action == badged then
                return Fail(NAME, "격리 중인 액션이 목록에 있다")
            end
        end

        -- And what leaves. `OnGenerateClicked` is the button, and the dialog it fills holds the
        -- string a reader would be handed.
        panel:OnGenerateClicked()
        local payload, why = DecodeExportedString(DebindShareCopyFrame.text)
        if not payload then
            return Fail(NAME, format("문자열을 못 읽었다: %s", why))
        end

        local sent = PayloadActions(payload)
        if #sent ~= #listed then
            return Fail(NAME, format("창은 %d개라 해놓고 %d개를 보냈다", #listed, #sent))
        end
        for _, action in ipairs(sent) do
            if action.value == badged.value then
                return Fail(NAME, "격리 중인 액션이 문자열에 실렸다")
            end
        end

        return Pass(NAME, format("%d개 = %d개, 배지는 안 나감", #listed, #sent))
    end,
})

-----------------------------------------------------------
-- Test Cases: Binding Issue Detection
-----------------------------------------------------------

RegisterTest("Issue: BUTTON1 without hover", {
    description = "BUTTON1을 hover 없이 쓰면 NOT_SUPPORTED_MOUSE_BUTTON 이슈가 나오는지",
    run = function()
        local action = { type = Constants.SPELL, value = 585, key = "BUTTON1" }
        local issue = DebindPrivate.GetBindingIssue(action)
        if issue ~= Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON then
            return Fail("BUTTON1 issue", format("expected NOT_SUPPORTED_MOUSE_BUTTON, got %s", tostring(issue)))
        end
        return Pass("BUTTON1 issue")
    end,
})

RegisterTest("Issue: groups=0", {
    description = "groups=0이면 GROUPS_NONE_SELECTED 이슈가 나오는지",
    run = function()
        local action = { type = Constants.SPELL, value = 585, key = "T", groups = 0 }
        local issue = DebindPrivate.GetBindingIssue(action)
        if issue ~= Constants.BINDING_ISSUE_GROUPS_NONE_SELECTED then
            return Fail("Groups=0 issue", format("expected GROUPS_NONE_SELECTED, got %s", tostring(issue)))
        end
        return Pass("Groups=0 issue")
    end,
})

RegisterTest("Issue: forms=0", {
    description = "forms=0이면 FORMS_NONE_SELECTED 이슈가 나오는지",
    run = function()
        local action = { type = Constants.SPELL, value = 585, key = "T", forms = 0 }
        local issue = DebindPrivate.GetBindingIssue(action)
        if issue ~= Constants.BINDING_ISSUE_FORMS_NONE_SELECTED then
            return Fail("Forms=0 issue", format("expected FORMS_NONE_SELECTED, got %s", tostring(issue)))
        end
        return Pass("Forms=0 issue")
    end,
})

-- 이 이슈만 **끝까지** 본다. 나머지 이슈 테스트는 `GetBindingIssue`의 답만 묻는데, 그건
-- 헤드리스가 더 싸게 본다(`tests/issue_spec.lua`). 여기서 물을 값이 있는 것은 그 답이
-- `KeyMap`까지 도달하느냐다 - 마커가 막지 못하면 오타 난 조건이 `[]`로 구워져 **조건 없이
-- 상시 발동**한다. 안 나가는 게 아니라 더 나가는 쪽이라, 이슈가 났다는 것만으로는 부족하다.
RegisterTest("Issue: undefined $state in macrotext", {
    description = "정의되지 않은 [$이름]이 든 매크로텍스트가 KeyMap에서 빠지는지",
    run = function()
        -- 통과하는 쪽을 먼저 세운다. 이게 없으면 아래 nil이 "마커가 막았다"인지
        -- "매크로텍스트가 원래 안 걸린다"인지 구분되지 않는다.
        InsertAction({ type = Constants.MACROTEXT, value = "/say [$state1] ok", key = "F5" })
        InsertAction({ type = Constants.MACROTEXT, value = "/say [$typo] bad", key = "F6" })
        ApplyBindings()

        if not GetNthBinding("F5", 1) then
            return Fail("Undefined $state", "전제가 깨졌다 - 정의된 $state1도 KeyMap에 없다")
        end
        if GetNthBinding("F6", 1) then
            return Fail("Undefined $state", "오타 난 조건이 그대로 바인딩됐다 - 항상 참으로 굽힌다")
        end

        local issue = DebindPrivate.GetBindingIssue({
            type = Constants.MACROTEXT, value = "/say [$typo] bad", key = "F6" })
        if issue ~= Constants.BINDING_ISSUE_UNDEFINED_STATE then
            return Fail("Undefined $state", format("issue=%s", tostring(issue)))
        end
        return Pass("Undefined $state", "F5 걸림 / F6 빠짐")
    end,
})

-- **코드젠의 fail-safe가 혼자 서는 유일한 자리다.** 위 마커는 액션만 보는데 상태의 계산식은
-- 액션이 아니라 옵션이라 그 검사에 아예 안 걸린다. 그러니 여기서 미정의 이름이 참으로 굽히면
-- 막는 것이 하나도 없고, 그 상태를 참조하는 바인딩이 **전부** 조건 없이 켜진 것으로 돈다.
--
-- 경로: `expr` -> `addMacrotext` -> 코드젠의 `arg.fixed` -> `UpdateMacroTexts`가 완성한 문자열
-- -> `SecureCmdOptionParse`. `""`로 구우면 `[$typo]`가 `[]`가 되어 **참**이고, `known:0`이면
-- 거짓이다. 그 갈림이 보안 환경 안에서만 일어나서 헤드리스로는 못 본다.
RegisterTest("Undefined $state inside a state's own expression", {
    description = "상태 계산식의 정의되지 않은 [$이름]이 그 상태를 켜버리지 않는지",
    run = function()
        local NAME = "Undefined $state in expr"
        local KEY = "CTRL-SHIFT-F8"
        local MODES = Constants.CUSTOM_STATE_MODES

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 리빌드가 미뤄져서 판정이 안 선다")
        end

        -- **`DebindPrivate.CustomStates`의 슬롯만 갈아끼운다.** 그 표의 항목은
        -- `db.customStates`의 표와 **같은 테이블**이라(`BindDerivedTables`), 필드를 고치면
        -- 사용자의 저장된 설정을 고치는 것이 된다. 슬롯을 바꾸면 되돌릴 것이 참조 둘뿐이다.
        local saved1, saved2 = DebindPrivate.CustomStates[1], DebindPrivate.CustomStates[2]
        AddTeardown(function()
            DebindPrivate.CustomStates[1] = saved1
            DebindPrivate.CustomStates[2] = saved2
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)

        DebindPrivate.CustomStates[2] = { mode = MODES.MANUAL, value = true }
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, ["$state1"] = true })

        -- 켜지는 쪽을 먼저 세운다. 이게 없으면 아래의 "안 걸림"이 계산식 상태로는 원래
        -- 아무것도 안 걸리는 것과 구분되지 않는다.
        DebindPrivate.CustomStates[1] = { mode = MODES.MACRO_CONDITIONAL, expr = "[$state2]" }
        ApplyBindings()
        local whenTrue = GetBindingAction(KEY, true) or ""
        if whenTrue:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "전제가 깨졌다 - 참인 계산식($state2=켜짐)인데 %q. 계산식 상태가 바인딩까지 안 닿는다",
                whenTrue))
        end

        DebindPrivate.CustomStates[1] = { mode = MODES.MACRO_CONDITIONAL, expr = "[$typo]" }
        ApplyBindings()
        local whenUndefined = GetBindingAction(KEY, true) or ""
        if whenUndefined ~= "" then
            return Fail(NAME, format(
                "미정의 이름이 계산식을 참으로 만들었다 (%q) - 그 상태를 쓰는 바인딩이 전부 켜진다",
                whenUndefined))
        end

        return Pass(NAME, format("[$state2] -> %s / [$typo] -> 안 걸림", whenTrue))
    end,
})

-----------------------------------------------------------
-- Test Cases: Special Units (macrotext with @tank etc.)
-----------------------------------------------------------

RegisterTest("Macrotext with @tank", {
    description = "@tank 유닛이 포함된 매크로텍스트가 파싱되는지",
    run = function()
        local text = "/cast [@tank] Heal"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("@tank macrotext", "ParseMacroText returned nil args") end
        local foundTank = false
        for _, arg in ipairs(args) do
            if arg.name == "tank" and arg.type == Constants.MACROTEXT_ARG_UNIT then
                foundTank = true
                break
            end
        end
        if not foundTank then return Fail("@tank macrotext", "tank unit not found in args") end
        return Pass("@tank macrotext")
    end,
})

RegisterTest("Macrotext with @custom1", {
    description = "@custom1 유닛이 포함된 매크로텍스트가 파싱되는지",
    run = function()
        local text = "/cast [@custom1,exists] Heal"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("@custom1 macrotext", "ParseMacroText returned nil args") end
        local found = false
        for _, arg in ipairs(args) do
            if arg.name == "custom1" then
                found = true
                break
            end
        end
        if not found then return Fail("@custom1 macrotext", "custom1 not found in args") end
        return Pass("@custom1 macrotext")
    end,
})

RegisterTest("Macrotext with $state", {
    description = "$state 커스텀 상태가 매크로텍스트에서 파싱되는지",
    run = function()
        local text = "/cast [$state1] Heal; Smite"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("$state macrotext", "ParseMacroText returned nil args") end
        local found = false
        for _, arg in ipairs(args) do
            if arg.name == "$state1" and arg.type == Constants.MACROTEXT_ARG_CUSTOM_STATE then
                found = true
                break
            end
        end
        if not found then return Fail("$state macrotext", "$state1 not found in args") end
        return Pass("$state macrotext")
    end,
})

-- README가 광고하는 형태. 두 번째 이후 대괄호 그룹이 파서에 도달하지 못하면
-- @healer가 글자 그대로 와우에 넘어가고, 모르는 유닛이라 조용히 실패한다.
RegisterTest("Macrotext with multiple condition groups", {
    description = "두 번째 이후 대괄호 그룹의 특수 유닛도 치환되는지",
    run = function()
        local text = "/cast [@custom2,exists][@healer,exists][] Innervate"
        local _, args = DebindPrivate.ParseMacroText(text)
        if not args then return Fail("multi-group macrotext", "ParseMacroText returned nil args") end
        local seen = {}
        for _, arg in ipairs(args) do
            if arg.type == Constants.MACROTEXT_ARG_UNIT then
                seen[arg.name] = true
            end
        end
        local missing = {}
        if not seen.custom2 then tinsert(missing, "custom2") end
        if not seen.healer then tinsert(missing, "healer") end
        if #missing > 0 then
            return Fail("multi-group macrotext", "치환 안 됨: " .. table.concat(missing, ", "))
        end
        return Pass("multi-group macrotext", "custom2 + healer 모두 인자로 잡힘")
    end,
})

-----------------------------------------------------------
-- Test Cases: Multi-condition combo
-----------------------------------------------------------

RegisterTest("Multi-condition: combat + group + stealth", {
    description = "여러 조건 동시 설정이 바인딩에 모두 반영되는지",
    run = function()
        InsertAction({
            type = Constants.SPELL, value = 585, key = "HOME",
            combat = true,
            groups = Constants.GROUP_RAID,
            stealth = false,
            pet = true,
            ["$state2"] = true,
        })
        ApplyBindings()
        local b = GetNthBinding("HOME", 1)
        if not b then return Fail("Multi-condition", "HOME not in KeyMap") end
        local errors = {}
        if b.combat ~= true then tinsert(errors, "combat=" .. tostring(b.combat)) end
        if b.groups ~= Constants.GROUP_RAID then tinsert(errors, "groups=" .. tostring(b.groups)) end
        if b.stealth ~= false then tinsert(errors, "stealth=" .. tostring(b.stealth)) end
        if b.pet ~= true then tinsert(errors, "pet=" .. tostring(b.pet)) end
        if b["$state2"] ~= true then tinsert(errors, "$state2=" .. tostring(b["$state2"])) end
        if #errors > 0 then
            return Fail("Multi-condition", table.concat(errors, ", "))
        end
        return Pass("Multi-condition", "all 5 conditions preserved")
    end,
})

-----------------------------------------------------------
-- Test Cases: Secure Handler Health
-----------------------------------------------------------

-- 재빌드가 시큐어 환경까지 실제로 도달했는지. 이게 끊기면 아무것도 안 터지고, 바인딩이
-- 마지막에 적용된 상태로 얼어붙는다 - 키는 계속 뭔가 나가고 상태 전환만 멈추므로
-- 유저는 "가끔 안 먹혀요"라고밖에 말할 수 없다. 조용한 고장을 시끄럽게 만드는 것이 목적.
RegisterTest("Secure update path", {
    description = "UpdateBindings가 시큐어 핸들러까지 도달하는지 (state-unitexists를 핸들러가 소비했는가)",
    run = function()
        if InCombatLockdown() then
            return Fail("Secure update path", "전투 중에는 UpdateBindings가 미뤄지므로 판정 불가")
        end

        local driver = DebindPrivate.BindingDriver
        if not driver then return Fail("Secure update path", "BindingDriver가 없다") end

        ApplyBindings()

        -- UpdateBindings의 마지막 동작이 state-unitexists=1이고, 시큐어 _onattributechanged가
        -- 첫 동작으로 0으로 되돌린다. 핸들러는 동기적으로 도니까 여기까지 왔는데도 0이 아니면
        -- 핸들러가 아예 안 돈 것이다. 대기 상태의 0과 헷갈릴 일이 없다 - 방금 1을 넣었으므로.
        local value = driver:GetAttribute("state-unitexists")
        if value ~= 0 then
            return Fail("Secure update path", format(
                "state-unitexists=%s, 0이어야 한다. 시큐어 핸들러가 돌지 않았다 - 바인딩이 갱신을 멈춘 상태다",
                tostring(value)))
        end

        return Pass("Secure update path", "핸들러가 소비함")
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
-- 리빌드는 `States`를 통째로 새로 채우는데, `unitframe`만은 enter/leave 이벤트로만 서는 값이라
-- 다시 채워줄 사람이 없다. 지우면 커서가 프레임 위에 그대로 있는데도 hover가 죽고, 마우스를
-- 뺐다 다시 올려야 살아난다. 조건 하나만 바뀌어도 리빌드는 돌므로 - 전투 진입, 자세 변경 -
-- 실사용에서 밟힌다.
--
-- **`GetHoverUnit()`만 봐서는 못 잡는다.** 짝이 되는 `UnitAliasMap["hover"]`는 리빌드가 안 지우니
-- 버그가 있어도 "player"로 남는다. 그래서 leave로 본다: 슬롯이 날아갔으면 leave가 지울 것을
-- 못 찾고 그냥 나가므로, hover가 안 지워진 채로 남는다.
RegisterTest("Hover slot: survives a rebuild under a still cursor", {
    description = "hover 중에 리빌드가 돌아도 hover 슬롯이 살아남는가",
    run = function()
        local NAME = "Hover survives rebuild"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 리빌드가 막힌다")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            checkedUnits = { hover = {} },
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("진입 후 hover=%s, player여야 한다", tostring(GetHoverUnit())))
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
            return Fail(NAME, format("리빌드 뒤 hover=%s, 아직 player여야 한다", tostring(GetHoverUnit())))
        end

        -- 슬롯이 살아 있는지는 여기서 갈린다. 날아갔으면 leave가 지울 것을 못 찾는다.
        HoverLeave(frame)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "leave 뒤에도 hover=%s. 리빌드가 hover 슬롯을 지웠다는 뜻이다",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "리빌드를 건너 살아남고, leave가 제대로 지운다")
    end,
})

RegisterTest("Hover slot: unit disappears under a still cursor", {
    description = "커서가 멈춘 채 유닛만 사라졌을 때 hover 슬롯이 비는가, 돌아오면 다시 차는가",
    run = function()
        local NAME = "Hover slot"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 속성 쓰기가 막힌다")
        end

        -- A hover binding has to exist, or the hover axis is never measured at all and the slot
        -- this reads stays empty. The test builds its own precondition rather than hoping for one.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            checkedUnits = { hover = {} },
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("진입 후 hover=%s, player여야 한다", tostring(GetHoverUnit())))
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
                "유닛이 사라졌는데 hover=%s. 고치기 전에는 반응이 계속 남아 있었다",
                tostring(GetHoverUnit())))
        end

        -- The frame is deliberately not dropped when its unit goes away, so that this same poll
        -- can pick it back up. Without that, the slot would stay empty until the mouse moved.
        SetFrameUnit(frame, "player")
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format(
                "유닛이 돌아왔는데 hover=%s. 폴링이 프레임을 버렸다는 뜻이다",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "사라짐 -> 비고, 돌아옴 -> 다시 참")
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
    targets[#targets + 1] = { label = "우리 프레임", frame = frame }

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
    description = "등록된 프레임의 type1/2/3에 우리가 쓴 것이 없는가 (블리자드 프레임 포함)",
    run = function()
        local NAME = "Click-cast non-invasion"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록이 막힌다")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            checkedUnits = { hover = {} },
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
                return Fail(NAME, format("%s: *type-debind1=%s, click 이어야 한다",
                    target.label, tostring(frame:GetAttribute("*type-debind1"))))
            end

            -- And nothing of ours in the slots that belong to the frame. "click" is the value the
            -- old routing wrote; a frame of its own may legitimately hold other types.
            for i = 1, 5 do
                for _, attr in ipairs({ "*type" .. i, "type" .. i }) do
                    if frame:GetAttribute(attr) == "click" then
                        return Fail(NAME, format(
                            "%s: %s 에 click 이 남아 있다. 옛 라우팅이 아직 그 자리를 쓴다",
                            target.label, attr))
                    end
                end
            end
            checked[#checked + 1] = target.label
        end

        return Pass(NAME, table.concat(checked, ", ") .. " — 남의 자리 비어 있음")
    end,
})

RegisterTest("Click-cast: the frame's wrapper picks a winner", {
    description = "유닛 프레임 클릭이 래퍼까지 닿아 조건에 맞는 레코드를 고르는가 (우리 프레임 + 블리자드 프레임)",
    run = function()
        local NAME = "Click-cast winner"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 래핑이 막힌다")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            checkedUnits = { hover = {} },
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
                return Fail(NAME, format("%s: 아무것도 안 골랐다 - 조건이 안 맞았거나 "
                    .. "그 버튼·수식어로 등록된 키가 없다", target.label))
            end
            seen[#seen + 1] = format("%s=%d", target.label, LastWinner())

            HoverLeave(target.frame)
            WaitForHoverSlot(false)
        end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})

-- The point of judging on the frame instead of ahead of it: when nothing matches we return nil,
-- the button name is left alone, and the click carries on into whatever the frame itself does.
-- On the old path the frame's own `type` had been overwritten, so a click that matched nothing
-- did nothing at all -- silently, which is the shape of fault this addon keeps running into.
RegisterTest("Click-cast: a click that matches nothing falls through", {
    description = "조건이 안 맞으면 프레임 자신의 동작이 그대로 나가는가 (동적 폴백)",
    run = function()
        local NAME = "Click-cast fallback"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 래핑이 막힌다")
        end

        -- **프로브를 켜야 `LastWinner()`가 답을 한다.** 배포 갈래에서 `PROBE.Winner`는 통째로
        -- 지워지므로, 안 켜면 이 테스트의 "아무것도 안 골랐나" 검사가 언제나 nil을 보고 통과한다
        -- - 조건 목이 빠져서 엉뚱한 레코드를 골라도 조용하다.
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "프로브 켜기 실패: " .. tostring(probesErr))
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
            checkedUnits = { hover = {} },
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
                        "%s: 조건이 안 맞는데 %d번을 골랐다. combat 목이 안 걸렸을 수 있다",
                        target.label, LastWinner()))
                end

                if LastEvalAnswer() ~= nil then
                    return Fail(NAME, format(
                        "%s: 고른 것이 없는데 %q를 반환했다. 그러면 버튼 이름이 바뀌어 프레임 "
                        .. "자신의 동작이 안 나간다",
                        target.label, tostring(LastEvalAnswer())))
                end

                HoverLeave(target.frame)
                WaitForHoverSlot(false)
            end
        end

        return Pass(NAME, "안 맞음 -> 고르지 않고 이름도 안 바꿈 (프레임 쪽으로 넘어간다)")
    end,
})

-----------------------------------------------------------
-- Test Cases: State Injection (live)
-----------------------------------------------------------

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
    description = "전투 중이라고 주입하면 전투 전용 바인딩이 실제로 걸리는가",
    run = function()
        local NAME = "Combat injection"
        local KEY = "CTRL-SHIFT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "진짜 전투 중에는 주입 결과와 실제가 구분되지 않는다")
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
                "combat을 뒤집었는데 바인딩이 그대로다 (%q). 주입이 스니펫까지 안 닿았다",
                inCombat))
        end

        if inCombat:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("combat=true 인데 %q, CLICK 이어야 한다", inCombat))
        end

        -- Back to peace: the binding has to go away again. Without this the test would pass on a
        -- key that was simply bound the whole time.
        SetMockState("combat", false)
        local again = GetBindingAction(KEY, true) or ""

        if again ~= atPeace then
            return Fail(NAME, format("combat을 되돌렸는데 %q, %q 여야 한다", again, atPeace))
        end

        return Pass(NAME, format("전투 밖에서 전투 경로를 구동함 (%s)", inCombat))
    end,
})

-- Turning probes on rebuilds every registered snippet from its raw text, including the click
-- wrapper -- the hottest path here and the one that decides which record wins. A rebuild that
-- produced a body the restricted environment refuses would leave the addon looking loaded and
-- doing nothing, so what is checked is not that the rebake returned, but that the same judgement
-- still runs afterwards.
RegisterTest("Snippet probes: rebaked snippets still decide", {
    description = "프로브를 켜고 스니펫을 다시 구워도 조건 판정이 그대로 도는가",
    run = function()
        local NAME = "Probe rebake"
        local KEY = "CTRL-SHIFT-F8"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 다시 구울 수 없다")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(err))
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
            return Fail(NAME, format("다시 구운 뒤 조건이 안 먹는다 (%q 그대로)", inCombat))
        end

        if inCombat:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("다시 구운 뒤 %q, CLICK 이어야 한다", inCombat))
        end

        return Pass(NAME, "프로브 켠 채로도 판정이 그대로")
    end,
})

-----------------------------------------------------------
-- Test Cases: The unit axes, measured for real
-----------------------------------------------------------

-- Headless cannot reach any of this. `UpdateBindings.lua` and `SecureBindings.lua` are not loaded
-- there, so the whole emit-and-match half -- registering an axis, measuring it every tick,
-- comparing it in the snippet -- has no coverage until the game runs it.

-- The live half of the life axis: a unit that is really there and really alive.
--
-- **Both directions, and neither of them mocked.** `dead = false` has to bind and `dead = true`
-- has to not, on the same key with the same unit, which is what tells a measured axis apart from
-- an axis nobody emitted. A condition that is never registered leaves `u.dead` nil, and nil
-- matches neither -- so a broken registration fails the first half, while a broken comparison
-- fails the second.
RegisterTest("Dead axis: measured against a living unit", {
    description = "살아 있는 플레이어에 대해 생사 조건이 양쪽으로 갈리는가",
    run = function()
        local NAME = "Dead axis"
        local ALIVE_KEY = "CTRL-SHIFT-F10"
        local DEAD_KEY = "CTRL-SHIFT-F11"

        if UnitIsDeadOrGhost("player") then
            return Fail(NAME, "플레이어가 죽어 있다. 이 테스트는 살아 있는 것을 전제로 한다")
        end

        -- 키를 둘로 나눈다. 하나에 두 조건을 차례로 걸면 뒤엣것이 앞엣것의 결과를 지우고,
        -- 무엇이 무엇을 뒤집었는지 구분이 안 된다.
        InsertAction({
            type = Constants.SPELL, value = 585, key = ALIVE_KEY,
            checkedUnits = { player = { dead = false } },
        })
        InsertAction({
            type = Constants.SPELL, value = 585, key = DEAD_KEY,
            checkedUnits = { player = { dead = true } },
        })
        ApplyBindings()

        local whenAlive = GetBindingAction(ALIVE_KEY, true) or ""
        if whenAlive:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "살아있음 조건인데 %q. 생사 축이 등록되지 않아 u.dead가 nil일 수 있다", whenAlive))
        end

        local whenDead = GetBindingAction(DEAD_KEY, true) or ""
        if whenDead:sub(1, 6) == "CLICK " then
            return Fail(NAME, format(
                "죽음 조건인데 살아 있는 플레이어에게 %q가 걸렸다. 비교가 안 도는 것이다", whenDead))
        end

        return Pass(NAME, format("alive -> %s, dead -> %q", whenAlive, whenDead))
    end,
})

-- The other half, which no living session can produce. `player-dead` is injected at the same
-- point `combat` is -- right after the snippet measures it, before it stores it -- so the update
-- loop runs its real path and only the value it lands on differs.
RegisterTest("State injection: dead flips a binding", {
    description = "죽었다고 주입하면 죽음 조건 바인딩이 실제로 걸리는가",
    run = function()
        local NAME = "Dead injection"
        local KEY = "CTRL-SHIFT-F10"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 주입 결과와 실제가 구분되지 않는다")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            checkedUnits = { player = { dead = true } },
        })
        ApplyBindings()

        SetMockState("player-dead", false)
        local whenAlive = GetBindingAction(KEY, true) or ""

        SetMockState("player-dead", true)
        local whenDead = GetBindingAction(KEY, true) or ""

        if whenDead == whenAlive then
            return Fail(NAME, format(
                "생사를 뒤집었는데 바인딩이 그대로다 (%q). 주입이 스니펫까지 안 닿았다", whenDead))
        end

        if whenDead:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("dead=true 인데 %q, CLICK 이어야 한다", whenDead))
        end

        -- 되돌려서 사라지는 것까지 본다. 없으면 내내 걸려 있던 키에도 통과한다.
        SetMockState("player-dead", false)
        local again = GetBindingAction(KEY, true) or ""

        if again ~= whenAlive then
            return Fail(NAME, format("되돌렸는데 %q, %q 여야 한다", again, whenAlive))
        end

        return Pass(NAME, format("죽음 주입으로 키를 잡음 (%s)", whenDead))
    end,
})

-- The hover condition now rides the unit column (`t.units["hover"]`) instead of its own pair of
-- record fields. What that has to keep doing is decide **key ownership**: a hover-conditioned
-- keyboard key is ours only while the cursor is on a matching frame, and that judgement is made
-- by the update loop before the key is ever pressed.
RegisterTest("Hover condition owns the key through the unit column", {
    description = "호버 조건이 유닛 컬럼으로 옮겨간 뒤에도 키를 잡았다 놓는가",
    run = function()
        local NAME = "Hover ownership"
        local KEY = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록이 막힌다")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            checkedUnits = { hover = { reaction = Constants.REACTION_HELP } },
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
                "호버 전인데 %q가 걸려 있다. 호버 조건이 방출에서 빠졌을 수 있다", before))
        end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("진입 후 hover=%s, player여야 한다", tostring(GetHoverUnit())))
        end

        local hovering = GetBindingAction(KEY, true) or ""
        if hovering:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "아군 프레임에 올렸는데 %q. t.units[\"hover\"]가 안 맞은 것이다", hovering))
        end

        HoverLeave(frame)
        WaitForHoverSlot(false)

        local after = GetBindingAction(KEY, true) or ""
        if after ~= before then
            return Fail(NAME, format("leave 뒤에도 %q, %q 여야 한다", after, before))
        end

        return Pass(NAME, format("호버 -> %s, 벗어남 -> 놓음", hovering))
    end,
})

-- `frameTypes` kept its own field, and with the hover pair gone it lost the `t.hover` wrapper
-- that used to stand in front of it -- it carries its own "is there a frame at all" guard now.
-- What this pins is that the guard narrows: a frame of the wrong kind must not hand the key over.
RegisterTest("Hover frame types still narrow on their own", {
    description = "프레임 종류 제한이 제 존재 검사를 들고도 좁히는가",
    run = function()
        local NAME = "Hover frame types"
        local KEY = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록이 막힌다")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            checkedUnits = { hover = {} },
            frameTypes = Constants.FRAMETYPE_BOSS,
        })
        ApplyBindings()

        -- 조건은 boss인데 올리는 것은 group이다. 유닛은 있고 종류만 어긋난다.
        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("진입 후 hover=%s, player여야 한다", tostring(GetHoverUnit())))
        end

        local wrongType = GetBindingAction(KEY, true) or ""
        if wrongType:sub(1, 6) == "CLICK " then
            return Fail(NAME, format(
                "boss 제한인데 group 프레임에서 %q가 걸렸다. frameTypes가 안 걸린 것이다", wrongType))
        end

        return Pass(NAME, format("종류가 어긋나면 안 잡음 (%q)", wrongType))
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

-- **The split itself, which nothing else asserts.** `IsKeyAlwaysOurs` says whether a key's wiring
-- is fixed and headless tests cover that verdict; what is not covered anywhere else is the emitter
-- acting on it. The two are asserted as a pair, because either half alone passes for the wrong
-- reason: "not state-driven" also describes a key that failed to emit at all, and "state-driven"
-- also describes an emitter that ignores the verdict and puts everything in.
RegisterTest("Split: a key whose conditions leave no gap is not state-driven", {
    description = "전투/비전투가 다 덮인 키가 상태 루프의 표에서 빠지는가",
    run = function()
        local NAME = "Split covered"
        local KEY = "CTRL-SHIFT-F4"

        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "combat"',
            key = KEY, name = "combat", combat = true })
        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "peace"',
            key = KEY, name = "peace", combat = false })
        ApplyBindings()

        ReadKeyMembership(KEY)
        local m = WaitForMembership()
        if not m then return Fail(NAME, "제한 환경이 답을 안 보냈다") end

        -- 클릭 시점 표에 있어야 "안 넣은 것"과 "아예 안 나간 것"이 갈린다.
        if not m.clickTime then
            return Fail(NAME, "ClickTimeKeys에도 없다 - 갈린 게 아니라 레코드가 안 나갔다")
        end
        if m.stateDriven then
            return Fail(NAME,
                "StateDrivenBindings에 들어 있다 - 조건 공간이 다 덮였는데 상태 루프가 매 틱 훑는다")
        end

        return Pass(NAME, "clickTime만, stateDriven 아님")
    end,
})

RegisterTest("Split: a key that can be released stays state-driven", {
    description = "전투 조건만 있는 키는 상태 루프가 계속 정해야 하므로 표에 남는가",
    run = function()
        local NAME = "Split gapped"
        local KEY = "CTRL-SHIFT-F3"

        -- 비전투에서 맞는 레코드가 없다 = 그때는 키를 와우에 돌려줘야 한다. 그 판단을 하는
        -- 것이 상태 루프이므로 이 키는 반드시 그 표에 있어야 한다.
        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "combat"',
            key = KEY, name = "combat", combat = true })
        ApplyBindings()

        ReadKeyMembership(KEY)
        local m = WaitForMembership()
        if not m then return Fail(NAME, "제한 환경이 답을 안 보냈다") end

        if not m.stateDriven then
            return Fail(NAME,
                "StateDrivenBindings에 없다 - 비전투에서 놓아줄 사람이 없어 키가 물린 채로 남는다")
        end

        return Pass(NAME, format("stateDriven, clickTime=%s", tostring(m.clickTime)))
    end,
})

-- 클릭캐스팅 전용 키 - 마우스 버튼에 hover 조건만 걸린 키다. 키를 잡는 레코드가 하나도 없으니
-- 걸었다 놓았다 할 키 역할이 없고, 상태 루프가 이 키에서 정할 것도 없다.
--
-- **전에는 표에 들어 있었고 루프가 레코드 하나 안 읽고 끝냈다.** 그 no-op을 없앤 것이 이
-- 케이스가 지키는 것이다. `clickCast`를 같이 묻는 이유는 위 둘과 같다 - 이 키는 `ClickTimeKeys`에
-- 없으므로, `clickCast`가 없으면 "안 넣었다"와 "아예 안 나갔다"가 밖에서 똑같이 보인다.
RegisterTest("Split: a click-casting-only key is not state-driven", {
    description = "키를 잡는 레코드가 없는 키가 상태 루프의 표에서 빠지는가",
    run = function()
        local NAME = "Split clickcast-only"
        local KEY = "BUTTON3"

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            checkedUnits = { hover = {} },
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()

        ReadKeyMembership(KEY)
        local m = WaitForMembership()
        if not m then return Fail(NAME, "제한 환경이 답을 안 보냈다") end

        if not m.clickCast then
            return Fail(NAME, "ClickCastKeys에도 없다 - 갈린 게 아니라 레코드가 안 나갔다")
        end
        if m.stateDriven then
            return Fail(NAME,
                "StateDrivenBindings에 들어 있다 - 정할 것이 없는데 상태 루프가 매 틱 훑는다")
        end

        return Pass(NAME, format("clickCast만, stateDriven 아님 (clickTime=%s)", tostring(m.clickTime)))
    end,
})

RegisterTest("Click-time key: the press picks the record the state matches", {
    description = "배선이 고정된 키에서 누르는 순간의 상태가 승자를 가르는가",
    run = function()
        local NAME = "Click-time winner"
        local KEY = "CTRL-SHIFT-F6"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 다시 구울 수 없다")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(err))
        end

        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "combat"',
            key = KEY, name = "combat", combat = true })
        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "peace"',
            key = KEY, name = "peace", combat = false })
        ApplyBindings()

        -- 양쪽을 다 본다. 한쪽만 보면 조건을 아예 안 보고 늘 같은 것을 고르는 구현도 통과한다.
        local picked = {}
        for _, want in ipairs({ true, false }) do
            SetMockState("combat", want)

            -- **매번 다시 읽는다.** `SetMockState`가 끝에 리빌드를 돌리므로 KeyMap 배열이
            -- 갈린다. 루프 밖에서 한 번 잡아두면 두 번째 바퀴가 죽은 표를 본다.
            local records = GetKeyBindings(KEY)
            if not records or #records ~= 2 then
                return Fail(NAME, format("레코드가 2개여야 한다, 지금 %d개",
                    records and #records or 0))
            end

            -- 걸려 있는지부터 본다. 이 대조가 없으면 평가만 맞고 실제로는 아무 키에도 안 걸린
            -- 상태가 통과한다 - 평가를 클릭 없이 부르는 대가로 생기는 구멍이고, 여기서 막는다.
            local bound = GetBindingAction(KEY, true) or ""
            local want1 = "CLICK " .. DebindPrivate.DefaultClickFrame:GetName()
                .. ":" .. tostring(DebindPrivate.ClickTimeKeys[KEY])
            if bound ~= want1 then
                return Fail(NAME, format("combat=%s: %q, %q여야 한다",
                    tostring(want), bound, want1))
            end

            local ran, rerr = EvalClickTimeKey(KEY)
            if not ran then return Fail(NAME, rerr) end

            local idx = WaitForWinner()
            if idx == nil then
                return Fail(NAME, format(
                    "combat=%s: 평가는 돌았는데 맞는 레코드가 없다", tostring(want)))
            end

            -- 승자 색인은 **방출된** 레코드 안에서의 자리다. 걸 수단이 없거나 도달 불가라
            -- 떨어져 나간 것이 있으면 KeyMap 배열과 어긋나는데, 위에서 2개를 확인했고 둘 다
            -- 매크로텍스트라 떨어질 이유가 없다.
            local got = records[idx]
            if not got then
                return Fail(NAME, format("combat=%s 에서 색인 %d, 그 자리에 레코드가 없다",
                    tostring(want), idx))
            end
            if got.combat ~= want then
                return Fail(NAME, format("combat=%s 인데 combat=%s 레코드(%d번)를 골랐다",
                    tostring(want), tostring(got.combat), idx))
            end
            picked[#picked + 1] = idx
        end

        -- **음성 대조.** 위 두 검사는 `records[idx].combat`을 보는데, 방출부가 `combat=false`를
        -- 안 실어 보내면 그 레코드가 무조건 매치가 되고 색인은 양쪽 바퀴에서 같아진다 - 그때도
        -- 두 검사가 다 통과할 수 있다(첫 바퀴에서 combat 레코드가 먼저 맞고, 둘째 바퀴에서도
        -- 같은 것이 맞는데 KeyMap 쪽 `.combat`은 여전히 false로 남아 있는 경우). 색인이 실제로
        -- 갈렸는지가 "조건을 보고 골랐다"의 유일한 직접 증거다.
        if picked[1] == picked[2] then
            return Fail(NAME, format(
                "양쪽 다 %d번을 골랐다 - 조건을 안 보고 늘 같은 것을 고르고 있다", picked[1]))
        end

        return Pass(NAME, format("전투=%d번, 비전투=%d번", picked[1], picked[2]))
    end,
})

-- The other half: the key stays ours. A binding that never gets handed back is the premise the
-- build-time `SetBindingClick` rests on, and if the update loop ever decided to release this key
-- the press above would have nothing to arrive at.
--
-- Three flips rather than two, so that "it happens to be right on the way out" fails.
RegisterTest("Click-time key: fixed wiring is never handed back", {
    description = "조건 공간이 다 덮인 키는 상태가 뒤집혀도 배선이 그대로인가",
    run = function()
        local NAME = "Click-time wiring"
        local KEY = "CTRL-SHIFT-F12"

        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "combat"',
            key = KEY, name = "combat", combat = true })
        InsertAction({ type = Constants.MACROTEXT, value = '/run local _ = "peace"',
            key = KEY, name = "peace", combat = false })
        ApplyBindings()

        for _, want in ipairs({ true, false, true }) do
            SetMockState("combat", want)

            local bound = GetBindingAction(KEY, true) or ""
            if bound:sub(1, 6) ~= "CLICK " then
                return Fail(NAME, format("combat=%s 에서 %q, CLICK 이어야 한다",
                    tostring(want), bound))
            end
        end

        return Pass(NAME, "상태를 뒤집어도 CLICK 그대로")
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

local SWEEP_VALUES = {
    combat  = { false, true },
    stealth = { false, true },
    -- 0 is "no form". The masks below name form numbers, not bits, and only `ToSweepAction`
    -- turns them into bits -- so the whole test speaks the same language the mock does.
    form    = { 0, 1, 2 },
    group   = { Constants.GROUP_NONE, Constants.GROUP_PARTY, Constants.GROUP_RAID },
}

local GROUP_LABEL = {
    [Constants.GROUP_NONE]  = "solo",
    [Constants.GROUP_PARTY] = "party",
    [Constants.GROUP_RAID]  = "raid",
}

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
    if cond.combat ~= nil then action.combat = cond.combat end
    if cond.stealth ~= nil then action.stealth = cond.stealth end
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
    return action
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
        return nil, format("레코드가 %d개여야 한다, 지금 %d개 - 솔버가 떨궜거나 걸 수단이 없어 빠졌다",
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
            missing[#missing + 1] = format("%d번(%s)", i, records[i].label)
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
local CLICKTIME_SWEEP = {
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

RegisterTest("Multi-axis: the press picks the exact record out of seven", {
    description = "네 축의 조합을 전부 훑어, 일곱 레코드가 물린 키에서 매번 정확히 그 레코드가 이기는지",
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
            return Fail(NAME, "전투 중에는 다시 구울 수 없다")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(probesErr))
        end

        local ok, err = SetUpSweepKey(CLICKTIME_SWEEP, KEY)
        if not ok then return Fail(NAME, err) end

        local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY]
        if not button then
            return Fail(NAME, "클릭 시점 키가 아니다 - 이 테스트가 재려는 경로를 안 탄다")
        end

        local combos = BuildCombos()
        local wins = {}

        for _, state in ipairs(combos) do
            ApplySweepState(state)

            local want = SweepWinner(CLICKTIME_SWEEP, state)
            if not want then
                return Fail(NAME, format("%s: 기대 승자가 없다 - 마지막이 무조건인데 그럴 수 없다",
                    ComboLabel(state)))
            end

            -- **매번 다시 읽는다.** 상태를 세울 때마다 리빌드가 돌아 표가 갈린다. 개수가
            -- 어긋나면 색인이 가리키는 자리가 달라지므로, 승자를 묻기 전에 여기서 끊는다.
            local emitted = GetKeyBindings(KEY)
            if not emitted or #emitted ~= #CLICKTIME_SWEEP then
                return Fail(NAME, format("%s: 리빌드 뒤 레코드가 %d개 - 색인이 뜻을 잃었다",
                    ComboLabel(state), emitted and #emitted or 0))
            end

            -- 걸려 있는지부터 본다. 평가는 클릭 없이도 도니까, 이 대조가 없으면 판정만 맞고
            -- 실제로는 어느 키에도 안 걸린 상태가 통과한다.
            local bound = GetBindingAction(KEY, true) or ""
            local wantBound = "CLICK " .. DebindPrivate.DefaultClickFrame:GetName() .. ":" .. button
            if bound ~= wantBound then
                return Fail(NAME, format("%s: 키가 %q, %q여야 한다",
                    ComboLabel(state), bound, wantBound))
            end

            local ran, rerr = EvalClickTimeKey(KEY)
            if not ran then return Fail(NAME, rerr) end

            local got = WaitForWinner()
            if got ~= want then
                return Fail(NAME, format("%s: %d번(%s)이 이겨야 하는데 %s",
                    ComboLabel(state), want, CLICKTIME_SWEEP[want].label,
                    got and format("%d번(%s)", got, CLICKTIME_SWEEP[got] and CLICKTIME_SWEEP[got].label or "?")
                        or "아무도 안 이겼다"))
            end

            wins[got] = (wins[got] or 0) + 1
        end

        local missing = UnreachedRecords(CLICKTIME_SWEEP, wins)
        if missing then
            return Fail(NAME, format("%d개 조합 어디서도 안 이긴 레코드: %s - 훑는 축이 그 자리를 못 만든다",
                #combos, table.concat(missing, ", ")))
        end

        return Pass(NAME, format("%d개 조합 전부 정확히 맞음, 레코드 %d개가 모두 한 번 이상 이김",
            #combos, #CLICKTIME_SWEEP))
    end,
})

-- The same question asked of the **poll**, which needs a different key to be asked at all.
--
-- A key whose records are all clickable tells the state loop almost nothing apart: whichever
-- record wins, what gets bound is the one click-time button, so `GetBindingAction` answers the
-- same string for every winner. Commands do not share: the loop calls `SetBinding(true, key,
-- t.command)` with the winning record's own string, and `ClearBinding` for an unused one -- so
-- the key's own reported action names the record exactly, and it is the *game* naming it.
--
-- Those records also make the key state-driven rather than fixed: a reachable command or unused
-- record is precisely what `IsKeyAlwaysOurs` refuses, so this key stays in the loop's table.
local STATELOOP_SWEEP = {
    { label = "combat+form1|2", value = "TOGGLEWORLDMAP",
      cond = { combat = true, forms = { [1] = true, [2] = true } } },
    { label = "combat+raid",    value = "OPENALLBAGS",
      cond = { combat = true, groups = { [Constants.GROUP_RAID] = true } } },
    { label = "stealth+form0",  value = "TOGGLEBACKPACK",
      cond = { stealth = true, forms = { [0] = true } } },
    { label = "peace+grouped",  value = "TOGGLECHARACTER0",
      cond = { combat = false, stealth = false,
               groups = { [Constants.GROUP_PARTY] = true, [Constants.GROUP_RAID] = true } } },
    { label = "form2",          value = "TOGGLEACHIEVEMENT",
      cond = { forms = { [2] = true } } },
    { label = "combat",         value = "JUMP",
      cond = { combat = true } },
    -- Unconditional and unused: the key is released rather than bound, which is its own outcome
    -- and the only one that is an empty string.
    { label = "fallback-unused", cond = {} },
}

for i = 1, #STATELOOP_SWEEP do
    local record = STATELOOP_SWEEP[i]
    if record.value then
        record.action = { type = Constants.COMMAND, value = record.value }
        record.expect = record.value
    else
        record.action = { type = Constants.UNUSED }
        record.expect = ""
    end
end

RegisterTest("Multi-axis: the state loop binds the exact record out of seven", {
    description = "네 축의 조합을 전부 훑어, 상태 루프가 매번 정확히 그 레코드를 키에 거는지",
    timeout = 120,
    run = function()
        local NAME = "Multi-axis state loop"
        local KEY = "CTRL-SHIFT-F2"

        if InCombatLockdown() then
            return Fail(NAME, "진짜 전투 중에는 주입 결과와 실제가 구분되지 않는다")
        end

        local ok, err = SetUpSweepKey(STATELOOP_SWEEP, KEY)
        if not ok then return Fail(NAME, err) end

        -- 이 키가 상태 루프의 표에 있어야 여기서 재는 것이 그 루프다. 배선이 고정된 키였다면
        -- 아래 대조는 전부 통과하면서 아무것도 안 재게 된다.
        ReadKeyMembership(KEY)
        local membership = WaitForMembership()
        if not membership then return Fail(NAME, "제한 환경이 답을 안 보냈다") end
        if not membership.stateDriven then
            return Fail(NAME, "상태 구동 키가 아니다 - 이 테스트가 재려는 루프가 이 키를 안 본다")
        end

        local combos = BuildCombos()
        local wins = {}

        for _, state in ipairs(combos) do
            -- No wait after this, and it used to be the most expensive one in the file -- 36
            -- combos paying 0.4s each. The claim it rested on ("the state loop measures on its
            -- own 0.2s beat") is not true of this path: every axis here is set with
            -- `SetMockState`, which ends in a rebuild, and the rebuild sets `state-unitexists`
            -- itself and runs the state pass and the bindings before it returns.
            ApplySweepState(state)

            local want = SweepWinner(STATELOOP_SWEEP, state)
            if not want then
                return Fail(NAME, format("%s: 기대 승자가 없다 - 마지막이 무조건인데 그럴 수 없다",
                    ComboLabel(state)))
            end

            local record = STATELOOP_SWEEP[want]
            local bound = GetBindingAction(KEY, true) or ""
            if bound ~= record.expect then
                return Fail(NAME, format("%s: %d번(%s)이 이겨야 하니 %q여야 하는데 %q",
                    ComboLabel(state), want, record.label, record.expect, bound))
            end

            wins[want] = (wins[want] or 0) + 1
        end

        local missing = UnreachedRecords(STATELOOP_SWEEP, wins)
        if missing then
            return Fail(NAME, format("%d개 조합 어디서도 안 이긴 레코드: %s - 훑는 축이 그 자리를 못 만든다",
                #combos, table.concat(missing, ", ")))
        end

        -- **음성 대조는 표가 이미 들고 있다.** 마지막 레코드가 이기는 조합에서 키는 풀려
        -- 있어야 하고(`""`), 그것이 위 루프에서 다른 칸과 똑같이 검사된다 - 조건이 맞을 때
        -- 걸리는 것만 보고 안 맞을 때 놓는지는 안 보는 반쪽짜리가 될 수 없다.
        return Pass(NAME, format("%d개 조합 전부 정확히 맞음, 레코드 %d개가 모두 한 번 이상 이김",
            #combos, #STATELOOP_SWEEP))
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
local GAPPED_SWEEP = {}
for i = 1, #CLICKTIME_SWEEP - 1 do
    GAPPED_SWEEP[i] = CLICKTIME_SWEEP[i]
end

RegisterTest("Multi-axis: poll and press agree on a key with a gap", {
    description = "조건에 구멍이 있는 키에서, 잡고 놓는 판정과 누가 이기는지가 서로 어긋나지 않는지",
    timeout = 120,
    run = function()
        local NAME = "Multi-axis poll vs press"
        local KEY = "CTRL-SHIFT-F5"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 다시 구울 수 없다")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(probesErr))
        end

        local ok, err = SetUpSweepKey(GAPPED_SWEEP, KEY)
        if not ok then return Fail(NAME, err) end

        local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY]
        if not button then
            return Fail(NAME, "클릭 시점 키가 아니다 - 누가 이겼는지를 물을 데가 없다")
        end

        -- 구멍이 남아 있어야 상태 루프가 이 키를 계속 정한다. 무조건 레코드를 뺀 것이
        -- 실제로 그 효과를 냈는지 여기서 확인한다 - 안 그러면 아래 "놓아야 한다" 쪽이
        -- 한 번도 안 돈 채로 통과한다.
        ReadKeyMembership(KEY)
        local membership = WaitForMembership()
        if not membership then return Fail(NAME, "제한 환경이 답을 안 보냈다") end
        if not membership.stateDriven then
            return Fail(NAME, "상태 구동 키가 아니다 - 조건 공간에 구멍이 없다는 뜻이다")
        end
        if not membership.clickTime then
            return Fail(NAME, "클릭 시점 표에도 없다 - 누가 이겼는지를 물을 데가 없다")
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
                    return Fail(NAME, format("%s: %d번(%s)이 맞는데 키가 %q - 잡았어야 한다",
                        ComboLabel(state), want, GAPPED_SWEEP[want].label, bound))
                end
            elseif bound ~= "" then
                return Fail(NAME, format("%s: 맞는 레코드가 없는데 키가 %q - 놓았어야 한다",
                    ComboLabel(state), bound))
            end

            local ran, evalErr = EvalClickTimeKey(KEY)
            if not ran then return Fail(NAME, evalErr) end

            local got = WaitForWinner()
            if got ~= want then
                return Fail(NAME, format("%s: 누름이 %s를 골랐다, %s여야 한다",
                    ComboLabel(state),
                    got and format("%d번(%s)", got, GAPPED_SWEEP[got] and GAPPED_SWEEP[got].label or "?")
                        or "아무도 안",
                    want and format("%d번(%s)", want, GAPPED_SWEEP[want].label) or "아무도 안"))
            end

            if want then
                wins[want] = (wins[want] or 0) + 1
            else
                released = released + 1
            end
        end

        -- 구멍이 실제로 밟혔는가. 안 밟혔으면 "놓아야 한다" 쪽은 한 줄도 안 돈 것이고,
        -- 이 테스트는 앞의 것과 같은 것을 두 번 잰 셈이 된다.
        if released == 0 then
            return Fail(NAME, format("%d개 조합 중 아무 데서도 안 놓았다 - 구멍을 못 밟았다", #combos))
        end

        local missing = UnreachedRecords(GAPPED_SWEEP, wins)
        if missing then
            return Fail(NAME, format("%d개 조합 어디서도 안 이긴 레코드: %s", #combos, table.concat(missing, ", ")))
        end

        return Pass(NAME, format("%d개 조합에서 폴과 누름이 일치, 그중 %d개는 키를 놓음",
            #combos, released))
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
    description = "런이 /reload를 건너 이어지는가, 단계와 스크래치가 그대로 오는가",
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
            return Fail(NAME, format("phase=%s, second-half여야 한다", tostring(phase)))
        end

        if not scratch.token or scratch.token:sub(1, 7) ~= "before-" then
            return Fail(NAME, format("스크래치가 안 넘어왔다 (token=%s)", tostring(scratch.token)))
        end

        -- The run's own tally has to come back too. It is what the report is built from, and a
        -- resumed run that forgot it would report only the tests after the reload.
        local kept = scratch.token
        scratch.token, scratch.index = nil, nil

        return Pass(NAME, format("리로드 뒤 %s 로 이어짐 (%s)", phase, kept))
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

    local onDone = run.onDone
    run = nil
    runner:Hide()
    Persist()

    DB().last = lastResultText

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
    text = "DebindTest: %s\n\n이 테스트는 /reload를 건너야 한다. 리로드하면 이어서 계속한다.",
    button1 = RELOAD_UI or "Reload UI",
    button2 = CANCEL or "Cancel",
    OnAccept = function() ReloadUI() end,
    OnCancel = function()
        DB().pending = nil
        -- Declining ends the run here, and the session carries on -- so the user's own bindings
        -- have to come back. The reload path does not need this: the swap is only in memory.
        SetIsolated(false)
        UI.SetRunning(false)
        print("|cffff8800[DebindTest]|r 리로드를 취소해서 런을 중단했다.")
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

    print(format("|cff00ccff[DebindTest]|r %s -> /reload 대기 (%s)", name, phase))
    StaticPopup_Show("DEBINDTEST_RELOAD", name)
end

--- One resume of the current test. Returns true when the runner may keep going this frame.
local function Step()
    if not run.co then
        if run.index > #testOrder then
            FinishRun()
            return false
        end

        -- **예약된 리빌드가 없을 때까지 시작하지 않는다.**
        --
        -- 셋업이 유발한 리빌드는 다음 프레임에 터지고, 리빌드는 `States`를 통째로 새로
        -- 채운다. 테스트가 그 전에 시작하면 자기가 세워둔 상태가 도중에 지워지고, 증상은
        -- "아무 이유 없이 값이 사라졌다"로 나온다 - hover 슬롯이 그렇게 죽었다.
        --
        -- 큐가 빈 뒤에도 한 프레임을 더 준다. `updateBindingsQueued`는 타이머 콜백이 **리빌드를
        -- 부르기 전에** 지우므로, 비었다는 것이 그 리빌드가 끝났다는 뜻은 아니다.
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
            Record(run.name, "skip", format("SKIP %s: /debtest reload 로 실행", run.name), "ff888888")
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
                format("ERROR %s: 리로드를 %d번 넘게 요청했다", run.name, MAX_RELOADS), "ffff8800")
            RunTeardowns()
            run.co, run.wait = nil, nil
            run.index = run.index + 1
            -- 다음 테스트가 남의 phase로 시작하지 않게. 이 값을 지우는 것이 정상 종료
            -- 갈래에만 있어서, 리로드를 건넌 테스트가 중간에 죽으면 그 phase가 다음
            -- 테스트로 넘어갔다 - 받는 쪽은 준비 단계를 통째로 건너뛴다.
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
        print(format("|cffff8800[DebindTest]|r 이전 실행이 %s 에서 끊겼다 (리로드 요청 없음). 이어가지 않는다.",
            name))
        tinsert(pending.lines, format("DIED %s: 세션이 이 테스트 도중에 끝났다", name))
        lastResultText = table.concat(pending.lines, "\n")
        DB().last = lastResultText
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

    print(format("|cff00ccff[DebindTest]|r 리로드 뒤 이어서 실행: %s (%s)",
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
        print(format("|cffff0000[DebindTest]|r 이어받기가 터졌다: %s", tostring(err)))
        tinsert(pending.lines, format("RESUME FAILED %s: %s", testOrder[pending.index] or "?", tostring(err)))
        lastResultText = table.concat(pending.lines, "\n")
        DB().last = lastResultText
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

    print("|cff00ccff[DebindTest]|r 리로드 뒤 처음부터 실행한다.")
    UI.Open()
    RunAllTests()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

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
--- absence of the word 실패 is the report.
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
    local parts = { format("|cffcccccc전체 %d|r", total), format("|cff00ff00통과 %d|r", pass) }
    if fail > 0 then parts[#parts + 1] = format("|cffff4444실패 %d|r", fail) end
    if err > 0 then parts[#parts + 1] = format("|cffff8800오류 %d|r", err) end
    if skip > 0 then parts[#parts + 1] = format("|cff888888건너뜀 %d|r", skip) end

    local left = total - (pass + fail + err + skip)
    if left > 0 then parts[#parts + 1] = format("|cff666666남음 %d|r", left) end

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
    -- before anyone presses 실행.
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
    f.runBtn:SetText("실행")
    f.runBtn:SetScript("OnClick", function()
        RunAllTests()
    end)

    -- **The reload run is a button, not a slash command.** Ending the session is the one thing in
    -- here that costs the tester something, and the place they decide it should be the place they
    -- are already looking -- next to the run they were going to press anyway.
    f.reloadBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reloadBtn:SetSize(120, 24)
    f.reloadBtn:SetPoint("RIGHT", f.runBtn, "LEFT", -6, 0)
    f.reloadBtn:SetText("리로드 포함")
    -- No `onDone`. **Finishing does not open the copy window** -- the results are in this list and
    -- the 복사 button is right here. A popup that covers the list the moment it becomes worth
    -- reading is the opposite of the one-window shape.
    f.reloadBtn:SetScript("OnClick", function()
        RunAllTests(nil, true)
    end)
    f.reloadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("리로드 포함 실행", 1, 1, 1)
        GameTooltip:AddLine("/reload을 건너야 하는 테스트까지 돈다. 그 자리에서 세션이 한 번 끊긴다.",
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
    f.freshBtn:SetText("리로드 후 실행")
    f.freshBtn:SetScript("OnClick", function()
        RequestFreshRun()
    end)
    f.freshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("리로드 후 실행", 1, 1, 1)
        GameTooltip:AddLine(
            "지금 /reload 하고, 돌아오면 창을 열어 처음부터 돈다. 지금 세션이 굴러온 상태 위에서가 아니라 "
            .. "갓 로그인한 세션에서 재는 것이 목적이다. |cffffff00실행|r 과 같은 범위라 "
            .. "/reload을 건너야 하는 테스트는 건너뛴다.",
            nil, nil, nil, true)
        GameTooltip:Show()
    end)
    f.freshBtn:SetScript("OnLeave", GameTooltip_Hide)

    f.copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.copyBtn:SetSize(100, 24)
    f.copyBtn:SetPoint("RIGHT", f.reloadBtn, "LEFT", -6, 0)
    f.copyBtn:SetText("복사")
    f.copyBtn:SetScript("OnClick", function()
        if lastResultText ~= "" then
            ShowCopyableText(lastResultText)
        else
            local stored = DB().last
            ShowCopyableText(stored or "아직 실행한 적이 없다.")
        end
    end)

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
    f.keepBindings.text:SetText("기존 바인딩 남겨두기")
    f.keepBindings:SetChecked(skipBlackout)
    f.keepBindings:SetScript("OnClick", function(self)
        skipBlackout = self:GetChecked() and true or false
    end)
    f.keepBindings:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("기존 바인딩 남겨두기", 1, 1, 1)
        GameTooltip:AddLine(
            "평소에는 런 동안 게임의 기존 바인딩을 전부 끈다 - 그래야 어느 기계에서 돌려도 같은 답이 나온다. "
            .. "체크하면 그대로 두고 돈다. 어떤 실패가 그 조치 탓인지 가리려고 있는 것이지 설정이 아니다.",
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
        TestFrame.runBtn:SetText(running and "실행 중" or "실행")
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

    -- **A frame we leave alone is not in here**, so the box that says "여기" would be pointing at
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
            frame.debindTestSkinText:SetText("여기")
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
            print("|cff00ccff[DebindTest]|r 아직 결과가 없다. |cffffff00/debtest|r 창의 |cffffff00실행|r 부터.")
        end
    elseif msg == "last" then
        local stored = DB().last
        if stored then
            ShowCopyableText(stored)
        else
            print("|cff00ccff[DebindTest]|r 저장된 결과가 없다.")
        end
    else
        -- **Opening does not run.** These tests cast, and one of them stops to ask for a click;
        -- a window opened to read the last results should not start any of that. The run is a
        -- button because pressing it is the point at which someone meant it.
        UI.Open()
    end
end

print("|cff00ccff[DebindTest]|r Loaded. |cffffff00/debtest|r = 목록 창. 실행은 창 안의 |cffffff00실행|r / |cffffff00리로드 포함|r / |cffffff00리로드 후 실행|r 버튼. |cffffff00/debtest last|r = 지난 결과.")
