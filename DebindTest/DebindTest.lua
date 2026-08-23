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

local DebindPrivate = _G.DebindPrivate
if not DebindPrivate then
    print("|cffff0000[DebindTest]|r DebindPrivate not found. Enable DEBUG mode in Constants.lua.")
    return
end

local Constants = DebindPrivate.Constants
-- 메뉴 항목을 문구로 찾는 테스트가 있어서 필요하다. 자리로 찾으면 항목이 하나 끼어드는 날
-- 조용히 다른 것을 누른다.
local LLL = DebindPrivate.L
local DebindUI = DebindPrivate.DebindUI
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

--- 조건을 `action.conditions` 안으로 옮긴다.
---
--- 테스트는 조건을 평평하게 적는다 - `InsertAction({ ..., combat = true })`. 저장 모양은
--- 중첩이라(`devdocs/action-and-binding-shapes.md`), 평평하게 심으면 그 조건이 바인딩까지
--- 안 가고 **테스트가 걸었다고 믿는 조건 없이** 도는 액션이 된다. 조건이 빠진 액션은
--- 넓어지는 쪽이라 대개 초록으로 지나간다.
---
--- **무엇이 조건인지는 여기서 안 정한다.** `Constants.IsConditionField`가 프로덕션과 같은
--- 답을 낸다.
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
RegisterTest("Key group: the conflict popup's second answer runs", {
    description = "차 있는 키에 [덮어쓰기]를 눌렀을 때 점유자가 실제로 키를 잃는지",
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
            return Fail(NAME, "대화상자가 안 떴다")
        end
        AddTeardown(function() StaticPopup_Hide("DEBIND_KEY_GROUP_CONFLICT") end)

        local button = dialog.GetButton and dialog:GetButton(2)
        if not button then
            return Fail(NAME, "2번 버튼을 못 얻었다 - 클라이언트의 대화상자 모양이 바뀌었나")
        end
        button:Click()

        if occupant.key ~= nil then
            return Fail(NAME, format("점유자가 키를 그대로 들고 있다: %s", tostring(occupant.key)))
        end
        if mover.key ~= KEY then
            return Fail(NAME, format("옮긴 쪽이 키를 못 받았다: %s", tostring(mover.key)))
        end
        return Pass(NAME, "점유자가 비켰고 그룹이 키를 받았다")
    end,
})

-----------------------------------------------------------
-- Test Cases: what the pair costs, and what pays for it
--
-- An arrival keeps the key it was sent on and a badge holds it back, so the two things that used to
-- be impossible are now ordinary: **two groups on one key**, and **accepting putting a key live**.
-- Each is answered by a question the reader is asked, and a question is exactly the kind of thing
-- that can be wired up wrong in silence -- the popup opens, a button does nothing, and only someone
-- who pressed it finds out (`devdocs/building-export-import.md` 12절).
-----------------------------------------------------------

RegisterTest("Unbind: a set is not scattered without asking", {
    description = "여러 개짜리 그룹의 [단축키 해제]가 확인창을 세우고, 확인해야 흩어지는가",
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
            return Fail(NAME, "묻기도 전에 키가 풀렸다")
        end
        local dialog = StaticPopup_FindVisible("DEBIND_UNBIND_SCATTERS")
        if not dialog then
            return Fail(NAME, "확인창이 안 떴다")
        end

        local button = dialog.GetButton and dialog:GetButton(1)
        if not button then
            return Fail(NAME, "1번 버튼을 못 얻었다 - 클라이언트의 대화상자 모양이 바뀌었나")
        end
        button:Click()

        if first.key ~= nil or second.key ~= nil then
            return Fail(NAME, format("확인했는데 키가 남았다: %s %s",
                tostring(first.key), tostring(second.key)))
        end
        return Pass(NAME, "묻고 나서 흩어졌다")
    end,
})

RegisterTest("Unbind: one action is not asked about", {
    description = "혼자인 액션의 [단축키 해제]는 확인창 없이 바로 풀리는가",
    run = function()
        local NAME = "Unbind single"
        local KEY = "CTRL-ALT-F12"

        -- **혼자면 잃을 세트가 없다.** 여기에 확인창이 서면 흔한 조작마다 상자가 뜬다.
        local only = InsertAction({ type = Constants.SPELL, value = 1, key = KEY })
        ApplyBindings()

        AddTeardown(function() StaticPopup_Hide("DEBIND_UNBIND_SCATTERS") end)

        DebindUI.UnbindActions({ only })

        if StaticPopup_FindVisible("DEBIND_UNBIND_SCATTERS") then
            return Fail(NAME, "하나뿐인데 확인창이 떴다")
        end
        if only.key ~= nil then
            return Fail(NAME, format("키가 안 풀렸다: %s", tostring(only.key)))
        end
        return Pass(NAME, "안 묻고 바로 풀렸다")
    end,
})

RegisterTest("Accept all: an occupied key is asked about, and all three answers run", {
    description = "도착 키가 내가 쓰는 키면 확인창이 서고, 답 셋이 각각 실제로 도는가",
    run = function()
        local NAME = "Accept all occupied"
        local KEY = "CTRL-ALT-F5"
        local FREE = "CTRL-ALT-F3"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        --- 세 답을 한 자리에서 재려면 매번 같은 판을 다시 세워야 한다. 내 것 하나, 같은 키로
        --- 도착한 것 하나, 그리고 **아무도 안 쓰는 키로 도착한 것 하나** - 마지막 것이 세 답
        --- 어디서도 안 밀려나야 한다는 것이 이 창에서 제일 조용히 틀릴 자리다.
        ---
        --- **둘 다 조건을 하나씩 지고, 축이 다르다.** 축이 달라야 솔버가 둘 다 남기고, **둘 다
        --- 조건부여야** 비교자가 `seq`까지 내려온다 - `isConditional`이 3단계고 `seq`는
        --- 6단계라(`Ordering.lua`), 한쪽만 조건부면 병합 차례는 도착분이 뒤에 서는지와 아무
        --- 상관없이 그쪽이 앞선다. 한쪽 조건을 지우면 이 테스트는 맞는 코드에 대고 빨개진다.
        ---
        --- **판마다 레이어를 비운다.** 이 키트는 테스트 사이에 안 비우고, 이 테스트는 한 키를 세
        --- 번 다시 쓴다 - 안 비우면 세 번째 판의 차례는 그 판의 둘이 아니라 앞 두 판이 남긴
        --- 것까지 섞인 더미를 재게 되고, 겹치는 것을 솔버가 떨어낸 결과가 답으로 나온다.
        --- 끝나고 한 번 더 비우는 것은 뒤에 오는 테스트 몫이다.
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
                return format("[%s] 묻기도 전에 배지가 떨어졌다", label)
            end
            local dialog = StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED")
            if not dialog then
                return format("[%s] 확인창이 안 떴다", label)
            end
            local button = dialog.GetButton and dialog:GetButton(index)
            if not button then
                return format("[%s] %d번 버튼을 못 얻었다 - 대화상자 모양이 바뀌었나", label, index)
            end
            button:Click()
            ApplyBindings()
            if free.key ~= FREE or free.arrivalID ~= nil then
                return format("[%s] 안 겹치는 키로 온 것이 휩쓸렸다: %s", label, tostring(free.key))
            end
            return nil
        end

        -- **전제: 배지가 붙어 있는 동안은 실키를 들고도 안 선다.** 이게 무너지면 아래 셋은
        -- 무엇을 재는지 알 수 없다.
        Setup(1)
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("배지 달린 것이 이미 섰다: %s", KeyMapOrder(KEY)))
        end

        -- 1. [Keep Existing]. 내 키는 그대로, 겹친 도착분은 키 없이 앉는다.
        local err = Answer(1, "Keep Existing")
        if err then return Fail(NAME, err) end
        if mine.key ~= KEY then
            return Fail(NAME, format("[Keep Existing]인데 내 키가 풀렸다: %s", tostring(mine.key)))
        end
        if arrived.key ~= nil or arrived.arrivalID ~= nil or arrived.seq ~= nil then
            return Fail(NAME, format("겹친 도착분이 키 없이 안 앉았다: %s", tostring(arrived.key)))
        end
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("내 키가 달라졌다: %s", KeyMapOrder(KEY)))
        end

        -- 2. [Take Incoming]. 점유자가 키를 잃고, 지워지지는 않는다.
        Setup(2)
        err = Answer(2, "Take Incoming")
        if err then return Fail(NAME, err) end
        if mine.key ~= nil then
            return Fail(NAME, format("[Take Incoming]인데 내 키가 남았다: %s", tostring(mine.key)))
        end
        if arrived.key ~= KEY or arrived.arrivalID ~= nil then
            return Fail(NAME, "도착분이 키를 못 받았거나 배지가 남았다")
        end

        -- 3. [Merge]. 둘 다 그 키에 남고 도착분이 뒤에 선다.
        Setup(3)
        err = Answer(3, "Merge")
        if err then return Fail(NAME, err) end
        if mine.key ~= KEY then
            return Fail(NAME, format("[Merge]인데 내 키가 풀렸다: %s", tostring(mine.key)))
        end
        if KeyMapOrder(KEY) ~= "1 2" then
            return Fail(NAME, format("병합 차례가 아니다: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "묻고, 셋이 각각 돌고, 안 겹치는 키는 셋 다에서 그대로였다")
    end,










})

RegisterTest("Accept all: a free key is not asked about", {
    description = "도착 키가 내가 안 쓰는 키면 확인창 없이 바로 서는가",
    run = function()
        local NAME = "Accept all free"
        local KEY = "CTRL-ALT-F6"

        AddTeardown(function() StaticPopup_Hide("DEBIND_APPROVE_ALL_OCCUPIED") end)

        -- **흔한 경우다.** 여기에 상자가 서면 배지가 안전장치가 아니라 숙제가 된다.
        local arrived = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, arrivalID = 1 })
        ApplyBindings()

        DebindFrame:ApproveAllImported()

        if StaticPopup_FindVisible("DEBIND_APPROVE_ALL_OCCUPIED") then
            return Fail(NAME, "빈 키인데 확인창이 떴다")
        end
        if arrived.arrivalID ~= nil then
            return Fail(NAME, "배지가 안 떨어졌다")
        end
        ApplyBindings()
        if KeyMapOrder(KEY) ~= "1" then
            return Fail(NAME, format("승인했는데 안 섰다: %s", KeyMapOrder(KEY)))
        end
        return Pass(NAME, "안 묻고 바로 섰다")
    end,
})

-----------------------------------------------------------
-- Test Cases: The heading's right-click menu
--
-- 우클릭 하나가 세 조각을 지난다: 템플릿의 `registerForClicks`, `OnClick`의 오른쪽 갈래,
-- 그리고 왼쪽 열이 머리글 elementData에 실어 보내는 `rows`. **어느 하나가 빠져도 아무 일도 안
-- 일어난다** - 오류도 없고, 눌러본 사람만 안다. 셋 다 게임 안에서만 있는 것이라 이 층 말고는
-- 볼 데가 없다.
-----------------------------------------------------------

RegisterTest("Key group: the heading's right-click arms the whole group", {
    description = "머리글을 우클릭해 연 메뉴의 항목이 그룹 전부를 실은 캡처 창을 여는가",
    run = function()
        local NAME = "Key group heading menu"
        local KEY = "CTRL-ALT-F8"

        -- **둘, 그리고 조건으로 갈린 둘.** 하나짜리로는 "그룹째"를 못 잰다 - 겨눈 것이 행
        -- 하나여도 통과한다.
        local first = InsertAction({ type = Constants.SPELL, value = 1, key = KEY, combat = true })
        local second = InsertAction({ type = Constants.SPELL, value = 2, key = KEY, stealth = true })
        ApplyBindings()

        -- **머리글에 실리는 elementData는 왼쪽 열이 지은 그 물건이다.** 손으로 지어 넣으면
        -- `rows`를 안 싣게 된 날에도 이 테스트가 통과하는데, 메뉴가 그룹을 찾아가는 근거가
        -- 그 필드다. 창을 띄우지는 않는다 - 데이터는 프레임이 하나도 없어도 지어진다.
        DebindResultPanel:RefreshKeyboard()

        local elementData
        for _, data in DebindResultPanel.ContentArea.OrderArea.ScrollBox:GetDataProvider():Enumerate() do
            if data.isHeader and data.key == KEY then
                elementData = data
            end
        end
        if not elementData then
            return Fail(NAME, format("%s의 머리글이 왼쪽 열에 없다 - 검색어나 필터가 걸려 있나", KEY))
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

        -- **눌러서 연다.** `OpenKeyGroupMenu`를 직접 부르면 그 함수만 재고, 우클릭이 거기까지
        -- 닿는지는 안 잰 채로 통과한다 - 위 대화상자 테스트가 버튼을 직접 누르는 것과 같은
        -- 이유다.
        --
        -- **이것이 못 재는 것 하나:** `registerForClicks`가 진짜 우클릭을 받는지. `Click()`은
        -- 등록과 무관하게 핸들러를 부를 수 있고, 등록을 되읽는 API는 없다.
        header:Click("RightButton")

        local menu = Menu.GetManager():GetOpenMenu()
        if not menu then
            return Fail(NAME, "우클릭에 메뉴가 안 떴다")
        end

        -- **문구로 찾는다.** 한동안은 "고를 수 있는 것이 하나뿐"으로 짚었는데, 그건 항목이
        -- 하나이던 시절의 편법이었고 [단축키 해제]가 서면서 곧바로 빨개졌다 - 재려던 것은
        -- 항목 **개수**가 아니라 그 항목이 무엇을 겨누느냐였는데 개수에 매여 있었다.
        --
        -- 이 물음은 행 쪽 테스트와 같아졌으므로 찾는 방법도 같다.
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["KEY_HEADER_SET_KEY"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("[%s] 항목이 없다", LLL["KEY_HEADER_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "항목을 눌렀는데 캡처 창이 안 떴다")
        end

        -- 창이 겨눈 것이 그룹 전부인가. 하나만 실려 있으면 누른 키가 한 액션에만 간다.
        local armed = DebindKeyCaptureFrame.actions or {}
        local seen = {}
        for _, action in ipairs(armed) do
            seen[action] = true
        end
        if #armed ~= 2 or not seen[first] or not seen[second] then
            return Fail(NAME, format("겨눈 것이 그룹이 아니다 - %d개", #armed))
        end

        return Pass(NAME, format("우클릭 -> 메뉴 -> 캡처 창에 %d개", #armed))
    end,
})

--- 같은 창을 여는 항목이 행에도 서는데, **거기서는 그 행 하나만** 실려야 한다. 머리글 것과 낱말이
--- 같아서(둘 다 「단축키 지정」) 눈으로는 안 갈리고, 틀려도 조용하다 - 창이 뜨고 키도 받는다.
---
--- **이것이 안 재는 것:** 우클릭이 메뉴까지 닿는지. 그건 위 테스트가 재고, 여기서 재려면
--- 스크롤박스에서 나온 행 프레임이 있어야 한다(`DebindOrderLineMixin`은 `GetElementData`를
--- 읽으므로 손으로 만든 프레임으로는 못 연다). 그래서 메뉴 생성기를 진짜 메뉴 틀에 태우되
--- 클릭은 건너뛴다.
RegisterTest("Assign a key: a row's item takes that row alone", {
    description = "오버뷰 행 메뉴의 [단축키 지정]이 그 행 하나만 실은 캡처 창을 여는가",
    run = function()
        local NAME = "Row assign key"
        local KEY = "CTRL-ALT-F9"

        -- **한 키에 둘.** 하나만 실리는지가 이 테스트의 전부라, 딸린 것이 있어야 잰다.
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
            return Fail(NAME, "메뉴가 안 떴다")
        end

        -- 여기서는 문구로 찾는다. 이 메뉴에는 고를 수 있는 항목이 여럿이라(순서 두 개) 머리글
        -- 쪽처럼 "하나뿐"으로는 못 짚는다.
        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["ACTION_SET_KEY"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("[%s] 항목이 없다", LLL["ACTION_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "항목을 눌렀는데 캡처 창이 안 떴다")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        if #armed ~= 1 or armed[1] ~= first then
            return Fail(NAME, format("겨눈 것이 이 행 하나가 아니다 - %d개", #armed))
        end

        return Pass(NAME, "행 하나만 실렸다")
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
    description = "아직 안 받은 행의 메뉴에도 [단축키 지정]이 서고 그 행 하나만 실리는가",
    run = function()
        local NAME = "Imported row assign key"

        -- **키를 들고 도착한 것.** 실키와 배지가 짝이다 - 도착분은 보낸 사람의 키를 그대로 들고
        -- 오고, 붙잡아 두는 것은 배지 하나다.
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
            return Fail(NAME, "메뉴가 안 떴다")
        end

        local item
        menu:EnumerateElementDescriptions(function(_, description)
            if MenuUtil.GetElementText(description) == LLL["ACTION_SET_KEY"] then
                item = description
            end
        end)
        if not item then
            return Fail(NAME, format("[%s] 항목이 없다", LLL["ACTION_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "항목을 눌렀는데 캡처 창이 안 떴다")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        if #armed ~= 1 or armed[1] ~= action then
            return Fail(NAME, format("겨눈 것이 이 행 하나가 아니다 - %d개", #armed))
        end

        return Pass(NAME, "배지가 붙은 행에도 항목이 서고, 그 행 하나만 실렸다")
    end,
})

--- The fourth way into the same window, and the one with no heading behind it: several rows the
--- reader ticked, which may sit on different keys or on none.
---
--- **Two things are measured and the second is the one that bites.** That the item stands, and that
--- [Unbind] beside it goes dead when nothing in the selection holds a key at all. Lit over rows that
--- are all keyless it offers to take off a key none of them has, and pressing it does nothing.
RegisterTest("Bulk menu: the key pair aims at the whole selection", {
    description = "여럿 고른 메뉴의 [단축키 지정]이 고른 것 전부를 실은 창을 열고, [단축키 해제]가 키 없는 것만 골랐을 때 꺼지는가",
    run = function()
        local NAME = "Bulk key items"
        local KEY = "CTRL-ALT-F10"

        -- **서로 다른 키에 걸린 둘.** 키 그룹으로는 못 만드는 상태이고, 벌크가 그 상태를
        -- 창까지 나르는지가 이 테스트의 절반이다.
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
            return Fail(NAME, "메뉴가 안 떴다")
        end

        local unbind = FindItem(menu, LLL["UNBIND"])
        if not unbind or not unbind:IsEnabled() then
            return Fail(NAME, "진짜 키를 든 선택인데 [단축키 해제]가 꺼져 있다")
        end

        local item = FindItem(menu, LLL["ACTION_SET_KEY"])
        if not item then
            return Fail(NAME, format("[%s] 항목이 없다", LLL["ACTION_SET_KEY"]))
        end

        item:Pick(MenuInputContext.MouseButton, "LeftButton")

        if not DebindKeyCaptureFrame:IsShown() then
            return Fail(NAME, "항목을 눌렀는데 캡처 창이 안 떴다")
        end

        local armed = DebindKeyCaptureFrame.actions or {}
        local seen = {}
        for _, action in ipairs(armed) do
            seen[action] = true
        end
        if #armed ~= 2 or not seen[first] or not seen[second] then
            return Fail(NAME, format("고른 것 전부가 안 실렸다 - %d개", #armed))
        end
        DebindKeyCaptureFrame:Hide()

        -- **키가 아예 없는 것만 든 선택.** 여기서 [단축키 해제]가 살아 있으면 뗄 것이 없는데 뗄
        -- 수 있다고 말하는 것이고, 눌러도 아무 일이 안 일어난다.
        local keyless = InsertAction({
            type = Constants.SPELL,
            value = 3,
        })
        ApplyBindings()

        menu = OpenBulkMenu({ keyless })
        if not menu then
            return Fail(NAME, "두 번째 메뉴가 안 떴다")
        end
        unbind = FindItem(menu, LLL["UNBIND"])
        if not unbind then
            return Fail(NAME, format("[%s] 항목이 없다", LLL["UNBIND"]))
        end
        if unbind:IsEnabled() then
            return Fail(NAME, "키가 없는 것뿐인데 [단축키 해제]가 켜져 있다")
        end

        return Pass(NAME, "고른 둘이 창에 실렸고, 키 없는 것만 골랐을 때 해제가 꺼졌다")
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
    description = "포트레잇 줄의 토글을 누르면 모드가 켜지고 키보드와 켜진 표시가 따라오는가",
    run = function()
        local NAME = "Bind mode toggle"

        -- 창이 떠 있어야 한다. 포트레잇은 첫 `OnShow`에서 스스로를 세우고(`DebindPortraitMixin`),
        -- 그 전에는 툴팁 필드도 텍스처도 붙지 않은 상태다.
        DebindFrame:Show()
        AddTeardown(function()
            DebindFrame:SetBindingMode(false)
            DebindFrame:Hide()
        end)

        local toggle = DebindFrame.OverviewPanel.BindModePortrait
        if not toggle then
            return Fail(NAME, "BindModePortrait이 없다 - XML의 parentKey가 바뀌었나")
        end
        if DebindFrame:IsCapturingKey() then
            return Fail(NAME, "시작부터 모드가 켜져 있다")
        end

        toggle:Click()

        if not DebindFrame:IsCapturingKey() then
            return Fail(NAME, "눌렀는데 모드가 안 켜졌다")
        end
        if not toggle:IsKeyboardEnabled() then
            return Fail(NAME, "모드는 켜졌는데 이 버튼이 키보드를 안 듣는다")
        end
        -- 켜진 표시는 테두리다(`SetSelectedState`): 채도가 돌아오고 그 위의 어두운 판이 내려간다.
        if toggle.Frame:IsDesaturated() or toggle.UnselectedFrame:IsShown() then
            return Fail(NAME, "켜졌는데 테두리가 꺼진 모양 그대로다")
        end
        if toggle.TooltipTitle ~= LLL["BIND_MODE_STOP"] then
            return Fail(NAME, format("툴팁 제목이 안 바뀌었다: %s", tostring(toggle.TooltipTitle)))
        end

        toggle:Click()

        if DebindFrame:IsCapturingKey() then
            return Fail(NAME, "다시 눌렀는데 모드가 안 꺼졌다")
        end
        if toggle:IsKeyboardEnabled() then
            return Fail(NAME, "모드가 꺼졌는데 키보드를 계속 듣는다")
        end
        if not toggle.Frame:IsDesaturated() or not toggle.UnselectedFrame:IsShown() then
            return Fail(NAME, "꺼졌는데 켜진 표시가 남아 있다")
        end
        if toggle.TooltipTitle ~= LLL["BIND_MODE"] or toggle.TooltipText ~= LLL["BIND_MODE_DESC"] then
            return Fail(NAME, format("툴팁이 안 돌아왔다: %s / %s",
                tostring(toggle.TooltipTitle), tostring(toggle.TooltipText)))
        end

        return Pass(NAME, "토글 한 번에 모드·키보드·테두리·툴팁이 함께 움직였다")
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

--- 무엇이 무엇 위에 그려지는가. 게임이 답하는 것은 이 둘뿐이라 순서도 이 둘로 잰다 -
--- `toplevel`이 하는 일도 결국 같은 층 안에서 둘째 값을 올리는 것이다.
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

--- 편집칸에 글자를 넣는다. **`SetText`만으로는 `OnTextChanged`가 안 돈다.** 사람이 치면 도는
--- 그 스크립트가 이 창에서 [취소]를 켜고 끄는 자리이고 검색 상자에서는 검색어를 세우는 자리라,
--- 안 태우면 여기서 재는 것이 전부 사람이 하는 것과 다른 일이 된다.
---
--- **스크립트가 없으면 실패로 돌아온다.** 조용히 건너뛰면 XML의 배선이 빠진 날 이 테스트들이
--- 초록으로 지나간다.
local function TypeInto(editBox, text)
    editBox:SetText(text)
    local script = editBox:GetScript("OnTextChanged")
    if not script then
        return false
    end
    script(editBox, true)
    return true
end

--- 창을 띄우고 매크로텍스트 액션 하나를 심어 편집 창을 연다. 되돌려 놓는 일은 러너가 한다.
---
--- **아이콘을 넣는다.** 아이콘 없는 액션은 이 애드온이 만들 수 없는 모양이고([새 사용자 지정
--- 매크로]는 아이콘 선택기를 지난다), 그런 액션은 이름·아이콘 팝업이 빈 칸으로 열린다.
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

--- **이 테스트가 지키는 것은 아이콘 목록이 아니라 편집모드다.**
---
--- 블리자드의 `IconDataProvider`는 파일 로컬 `BaseIconFilenames`를 **처음 쓰는 쪽이 만들고
--- 마지막에 놓는 쪽이 지운다.** 그 자리를 우리가 밟으면 그 변수의 주인이 Debind가 되고,
--- 편집모드는 진입할 때 샘플 오라 아이콘을 뽑느라 그 값을 읽는다
--- (`EditModeAuraDataProvider.lua`의 `GetSampleAuraIcon` -> `GetNumIcons`). 그 한 번의 읽기로
--- 편집모드 진입 실행 전체가 물들고, 같은 실행이 이어서 파티 체력바를 갱신하다 secret 비교에
--- 막힌다. 이름/아이콘 창을 한 번 연 세션은 편집모드에 들어갈 때마다 파티 체력바가 죽었다.
---
--- **그 증상은 인게임에서도 못 재는 종류다** - 오염은 Lua에서 안 보이고, 편집모드 진입을
--- 테스트가 대신 눌러줄 수도 없다. 그래서 재는 것은 그 원인을 만드는 **구조**다. 우리 제공자가
--- 블리자드 것 그대로면 실패한다.
RegisterTest("Icon picker: the icon list is ours, not Blizzard's shared one", {
    description = "블리자드 공용 IconDataProvider를 우리가 만들거나 지우지 않는가",
    run = function()
        local NAME = "Icon provider"

        DebindFrame:Show()
        AddTeardown(function()
            DebindIconSelectorFrame:Hide()
            DebindFrame:Hide()
        end)

        local provider = DebindFrame:RefreshIconDataProvider()
        if not provider then
            return Fail(NAME, "제공자가 없다")
        end

        -- 목록을 만드는 쪽과 지우는 쪽, 둘 다 우리 것이어야 한다.
        if provider.GetNumIcons == IconDataProviderMixin.GetNumIcons then
            return Fail(NAME, "GetNumIcons가 블리자드 것이다 - 공용 BaseIconFilenames를 읽는다")
        end
        if provider.Release == IconDataProviderMixin.Release then
            return Fail(NAME, "Release가 블리자드 것이다 - 공용 BaseIconFilenames를 지운다")
        end

        -- 그러고도 목록이 실제로 서야 한다. 물음표 한 칸 + 스펠북 + 기본 목록.
        local numIcons = provider:GetNumIcons()
        if numIcons < 2 then
            return Fail(NAME, format("아이콘이 %d개뿐이다 - 목록이 안 채워졌다", numIcons))
        end

        local questionMark = provider:GetIconByIndex(1)
        if questionMark ~= [[INTERFACE\ICONS\INV_MISC_QUESTIONMARK]] then
            return Fail(NAME, format("1번 칸이 물음표가 아니다: %s", tostring(questionMark)))
        end

        -- 마지막 칸까지 실제 아이콘이 나와야 한다. 경계를 잘못 세면 여기서 nil이 나온다.
        local last = provider:GetIconByIndex(numIcons)
        if last == nil then
            return Fail(NAME, format("마지막 칸(%d)이 비었다 - 종류별 목록 경계가 어긋났다", numIcons))
        end

        -- 되찾기. 같은 아이콘이 여러 번 나올 수 있으므로 번호가 아니라 아이콘으로 견준다.
        local found = provider:GetIndexOfIcon(last)
        if not found or provider:GetIconByIndex(found) ~= last then
            return Fail(NAME, format("GetIndexOfIcon이 %s를 못 찾는다", tostring(last)))
        end

        return Pass(NAME, format("우리 제공자, 아이콘 %d개", numIcons))
    end,
})

RegisterTest("Macro editor: the body reaches the profile when the window closes", {
    description = "닫아야 저장되고, 이름·아이콘 팝업을 다녀오는 것으로는 저장되지 않는가",
    run = function()
        local NAME = "Macro commit"

        local action, box = OpenMacroEditor("/say one")
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "열리지 않았다")
        end
        if box:GetText() ~= "/say one" then
            return Fail(NAME, format("본문이 안 올라왔다: %q", box:GetText()))
        end

        if not TypeInto(box, "/say two") then
            return Fail(NAME, "편집칸에 OnTextChanged가 안 걸려 있다")
        end
        if action.value ~= "/say one" then
            return Fail(NAME, "치는 동안 이미 저장됐다 - 창이 열려 있는데 프로필이 움직였다")
        end

        -- 이름·아이콘 편집기로 갔다 온다. 기본 매크로 창은 이 자리에서 저장하고 우리는 안 한다:
        -- 저장하면 [취소]가 돌아갈 자리가, 본문을 건드리지도 않은 나들이에 밀린다.
        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "이름·아이콘 팝업이 안 열렸다")
        end
        if action.value ~= "/say one" then
            return Fail(NAME, format("팝업을 여는 것이 저장했다: %q", action.value))
        end

        DebindIconSelectorFrame:Close(true)
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "팝업이 닫히면서 편집 창까지 데려갔다")
        end
        if box:GetText() ~= "/say two" then
            return Fail(NAME, format("돌아왔더니 본문이 달라졌다: %q", box:GetText()))
        end

        -- [닫기]. 이 버튼은 창을 닫는 것 말고 아무것도 하지 않고, 저장은 그 닫힘이 한다.
        DebindMacroFrame.Editor.CloseButton:Click()
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "[닫기]를 눌렀는데 안 닫혔다")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("닫혔는데 저장이 안 됐다: %q", action.value))
        end

        return Pass(NAME, "팝업 나들이는 안 썼고, 닫힘이 썼다")
    end,
})

RegisterTest("Macro editor: [Cancel] lights up only when there is something to put back", {
    description = "고친 것이 없으면 꺼져 있고, 누르면 편집칸만 돌아오고 프로필은 안 움직이는가",
    run = function()
        local NAME = "Macro cancel"

        local action, box = OpenMacroEditor("/say one")
        local button = DebindMacroFrame.Editor.RevertButton

        if button:IsEnabled() then
            return Fail(NAME, "연 직후인데 되돌릴 것이 있다고 한다")
        end
        if button:GetText() ~= CANCEL then
            return Fail(NAME, format("라벨이 [취소]가 아니다: %q", tostring(button:GetText())))
        end

        if not TypeInto(box, "/say two") then
            return Fail(NAME, "편집칸에 OnTextChanged가 안 걸려 있다")
        end
        if not button:IsEnabled() then
            return Fail(NAME, "본문을 고쳤는데 버튼이 꺼져 있다")
        end

        button:Click()

        if box:GetText() ~= "/say one" then
            return Fail(NAME, format("편집칸이 안 돌아왔다: %q", box:GetText()))
        end
        if action.value ~= "/say one" then
            return Fail(NAME, format("프로필이 움직였다: %q", action.value))
        end
        if button:IsEnabled() then
            return Fail(NAME, "되돌린 뒤에도 버튼이 켜져 있다")
        end
        -- **닫지 않는다.** 되돌린 본문을 눈앞에 두고 다시 고칠 수 있어야 한다.
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "[취소]가 창까지 닫았다")
        end

        return Pass(NAME, "꺼짐 -> 켜짐 -> 되돌리고 다시 꺼짐")
    end,
})

RegisterTest("Macro editor: [Revert] gives the conversion its action back", {
    description = "변환으로 열렸으면 라벨이 REVERT가 되고, 눌렀을 때 되돌리는 함수가 도는가",
    run = function()
        local NAME = "Macro revert"

        local reverted = false
        local action, box = OpenMacroEditor("/cast Fireball", function() reverted = true end)
        local button = DebindMacroFrame.Editor.RevertButton

        if button:GetText() ~= REVERT then
            return Fail(NAME, format("라벨이 REVERT가 아니다: %q", tostring(button:GetText())))
        end
        -- 되돌릴 것은 이미 일어난 변환이라, 아무것도 안 쳤어도 켜져 있어야 한다.
        if not button:IsEnabled() then
            return Fail(NAME, "변환으로 열렸는데 버튼이 꺼져 있다")
        end
        if not DebindMacroFrame.macroCancelFunc then
            return Fail(NAME, "cancelFunc이 안 걸렸다 - Refresh가 지우고 아무도 다시 안 걸었나")
        end

        TypeInto(box, "/cast Frostbolt")
        button:Click()

        if not reverted then
            return Fail(NAME, "눌렀는데 되돌리는 함수가 안 돌았다")
        end
        -- 되돌린 액션 위에 방금 버린 본문이 다시 저장되면 안 된다.
        if action.value ~= "/cast Fireball" then
            return Fail(NAME, format("버린 본문이 저장됐다: %q", action.value))
        end

        return Pass(NAME, "REVERT가 걸리고, 눌러서 되돌렸고, 본문은 안 새어나갔다")
    end,
})

RegisterTest("Macro editor: ESC steps out of the popup, then the editor, then the window", {
    description = "ESC 한 번에 한 칸씩 물러나는가, 그리고 편집 창을 닫은 ESC가 본문을 남기는가",
    run = function()
        local NAME = "Macro escape"

        local action, box = OpenMacroEditor("/say one")

        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "이름·아이콘 팝업이 안 열렸다")
        end

        DebindFrame:HandleEscape()
        if DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "첫 ESC가 팝업을 안 닫았다")
        end
        if not DebindMacroFrame:IsShown() then
            return Fail(NAME, "첫 ESC가 편집 창까지 데려갔다")
        end

        TypeInto(box, "/say two")
        DebindFrame:HandleEscape()
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "둘째 ESC가 편집 창을 안 닫았다")
        end
        if not DebindFrame:IsShown() then
            return Fail(NAME, "둘째 ESC가 메인 창까지 닫았다 - 사다리에 이 칸이 없나")
        end
        -- 닫는 것이 저장하는 것이다. ESC로 나가도 본문은 남는다.
        if action.value ~= "/say two" then
            return Fail(NAME, format("ESC로 닫혔는데 본문이 안 남았다: %q", action.value))
        end

        DebindFrame:HandleEscape()
        if DebindFrame:IsShown() then
            return Fail(NAME, "셋째 ESC가 메인 창을 안 닫았다")
        end

        return Pass(NAME, "팝업 -> 편집 창 -> 메인 창, 본문은 남았다")
    end,
})

RegisterTest("Macro editor: the name/icon popup stays over the editor", {
    description = "편집 창을 앞으로 끌어올려도 그 위에 뜬 팝업이 뒤로 가지 않는가",
    run = function()
        local NAME = "Macro popup order"

        OpenMacroEditor("/say one")
        DebindMacroFrame:EditNameIcon_OnClick()
        if not DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "이름·아이콘 팝업이 안 열렸다")
        end

        local function Where()
            return format("%s/%d vs %s/%d",
                DebindIconSelectorFrame:GetFrameStrata(), DebindIconSelectorFrame:GetFrameLevel(),
                DebindMacroFrame:GetFrameStrata(), DebindMacroFrame:GetFrameLevel())
        end

        if not DrawsAbove(DebindIconSelectorFrame, DebindMacroFrame) then
            return Fail(NAME, format("열자마자 아래다: %s", Where()))
        end

        -- 편집 창을 클릭하면 일어나는 일. 둘이 같은 층에 있으면 이 한 줄이 순서를 뒤집는다.
        DebindMacroFrame:Raise()

        if not DrawsAbove(DebindIconSelectorFrame, DebindMacroFrame) then
            return Fail(NAME, format("편집 창을 올렸더니 팝업이 뒤로 갔다: %s", Where()))
        end

        return Pass(NAME, Where())
    end,
})

RegisterTest("Macro editor: a row filtered out of the bin takes its editor with it", {
    description = "검색어에 안 걸려 행이 사라지면 편집 창이 닫히는가, 그리고 본문은 저장되는가",
    run = function()
        local NAME = "Macro filtered out"

        local action, box = OpenMacroEditor("/say one")
        local searchBox = DebindFrame.OverviewPanel.SearchBox
        -- 여기서도 스크립트를 태운다. 안 그러면 중간에 실패한 날 검색어가 살아남아,
        -- 뒤따르는 테스트가 전부 텅 빈 통을 보게 된다.
        AddTeardown(function() TypeInto(searchBox, "") end)

        TypeInto(box, "/say two")

        -- 이 액션의 이름과 겹칠 수 없는 글자. 검색은 이름을 보고 거른다.
        if not TypeInto(searchBox, "qqzzxx") then
            return Fail(NAME, "검색 상자에 OnTextChanged가 안 걸려 있다")
        end

        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "행이 걸러졌는데 편집 창이 남아 있다")
        end
        if not DebindFrame:IsShown() then
            return Fail(NAME, "메인 창까지 닫혔다")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("닫혔는데 저장이 안 됐다: %q", action.value))
        end

        -- 검색어를 지우면 행은 돌아온다. 편집 창은 안 돌아온다 - 여는 것은 사용자가 한다.
        TypeInto(searchBox, "")
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "검색어를 지웠더니 편집 창이 혼자 다시 열렸다")
        end

        return Pass(NAME, "걸러지면서 닫혔고, 본문은 저장됐고, 혼자 안 돌아왔다")
    end,
})

RegisterTest("Macro editor: opening the spell picker closes it", {
    description = "주문 선택 창이 뜨면 그 아래 깔릴 편집 창과 팝업이 먼저 닫히는가",
    run = function()
        local NAME = "Macro picker"

        local action, box = OpenMacroEditor("/say one")
        AddTeardown(function() DebindSpellPickerFrame:Hide() end)

        DebindMacroFrame:EditNameIcon_OnClick()
        TypeInto(box, "/say two")

        DebindSpellPickerFrame:Show()

        if DebindIconSelectorFrame:IsShown() then
            return Fail(NAME, "이름·아이콘 팝업이 남아 있다")
        end
        if DebindMacroFrame:IsShown() then
            return Fail(NAME, "편집 창이 남아 있다 - 주문 선택 창이 그 아래에 깔린다")
        end
        if action.value ~= "/say two" then
            return Fail(NAME, format("닫혔는데 저장이 안 됐다: %q", action.value))
        end

        return Pass(NAME, "둘 다 닫혔고 본문은 남았다")
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

--- The storage tab's seat in `PANELS` (`DebindUI.lua`). That table is a local over there, so this
--- is the one thing here that has to be kept in step by hand -- the guard below is what says so out
--- loud rather than quietly measuring the wrong panel.
local STORAGE_PANEL_ID = 3

--- **Three numbers, and they have to agree.** What the preview counts, what the string carries, and
--- what adding it back would put in the profile. The tick set feeds all three (`FilterPayload`,
--- `PlanArrival`), so a filter read in one place and not another is silent everywhere else: the
--- window says 12, the string carries 9, and nobody sees the difference until somebody else opens
--- it (12절 of `devdocs/building-export-import.md`).
RegisterTest("Storage: the preview, the string and the add all count the same", {
    description = "미리보기가 센 수와 문자열이 나른 수와 Add가 놓을 수가 같은지, 배지는 빠지는지",
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
            return Fail(NAME, "보관함 패널을 못 얻었다 - 탭 번호나 LoadAddOn을 볼 것")
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
            return Fail(NAME, format("머리글 합 %d, 전체 목록 %d", headerTotal, #listed))
        end

        for _, action in ipairs(listed) do
            if action == badged then
                return Fail(NAME, "격리 중인 액션이 목록에 있다")
            end
        end

        -- And what leaves. `OnCopyClicked` is the button, and the box it fills is the one the
        -- reader copies out of. **The dialog keeps no copy of the string beside that box**, so the
        -- box is the only place to read it from (`ShowText`).
        panel:OnCopyClicked()
        local payload, why = DecodeExportedString(DebindCopyFrame.Output.EditBox:GetText())
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
            return Fail(NAME, "엔트리 페이로드를 못 열었다")
        end

        local planned, skipped = DebindPrivate.Store.PlanArrival(stored, { selection = panel.selected })
        if #planned ~= #listed then
            return Fail(NAME, format("창은 %d개라 해놓고 %d개를 놓는다", #listed, #planned))
        end
        if skipped ~= 0 then
            return Fail(NAME, format("갈 데 없는 것이 %d개 나왔다 - 이 판이 만든 주소다", skipped))
        end

        return Pass(NAME, format("%d개 = %d개 = %d개, 배지는 안 나감", #listed, #sent, #planned))
    end,
})

--- **The two verbs grey out, they do not leave** (2026-08-23, 소유자). A control that disappears
--- takes with it the answer to "what can I do here", and the screen where nothing is picked is
--- exactly where the reader is asking. The heading check is the other way round - it heads a list,
--- so with no list under it there is nothing for it to head.
---
--- **Nothing raises when an `IsEnabled` goes the wrong way** and no static check reads frame state,
--- so the three can only be held together from in here. One of them going missing altogether raises
--- for a different reason: `parentKey` is what these are found by, and a renamed one answers nil.
RegisterTest("Storage: the verbs grey out when nothing is picked", {
    description = "고른 엔트리가 없을 때 두 버튼이 사라지지 않고 회색이 되는가",
    run = function()
        local NAME = "Storage verbs"

        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F7" })

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "보관함 패널을 못 얻었다 - 탭 번호나 LoadAddOn을 볼 것")
        end

        local verbs = {
            { button = panel.Preview.AddButton,  name = "[Add to My Setup]" },
            { button = panel.Preview.CopyButton, name = "[Create Share Code]" },
        }
        for _, verb in ipairs(verbs) do
            if not verb.button then
                return Fail(NAME, format("%s 버튼이 없다 - XML의 parentKey를 볼 것", verb.name))
            end
        end

        local entry = DebindPrivate.Store.CreateEntry()
        AddTeardown(function()
            panel:SelectEntry(nil)
            DebindPrivate.Store.DeleteEntry(entry.id)
        end)

        -- **켜지는 쪽을 먼저 본다.** 이것이 없으면 아래의 통과가 "둘 다 원래 꺼져 있다"로도
        -- 똑같이 설명된다.
        panel:SelectEntry(entry)
        if #panel:EnumerateListedActions() == 0 then
            return Fail(NAME, "전제가 깨졌다 - 방금 만든 엔트리에 액션이 하나도 없다")
        end
        if not panel.Preview.SelectAllCheck:IsShown() then
            return Fail(NAME, "액션이 있는 엔트리를 골랐는데 [select all]이 없다")
        end
        for _, verb in ipairs(verbs) do
            if not verb.button:IsEnabled() then
                return Fail(NAME, format("전부 틱된 엔트리를 골랐는데 %s이 회색이다", verb.name))
            end
        end

        panel:SelectEntry(nil)
        if panel.Preview.SelectAllCheck:IsShown() then
            return Fail(NAME, "아무것도 안 골랐는데 [select all]이 서 있다")
        end
        for _, verb in ipairs(verbs) do
            if not verb.button:IsShown() then
                return Fail(NAME, format("%s이 없어졌다 - 회색이 되어야 한다", verb.name))
            end
            if verb.button:IsEnabled() then
                return Fail(NAME, format("아무것도 안 골랐는데 %s을 누를 수 있다", verb.name))
            end
        end

        return Pass(NAME, "고르면 둘 다 켜지고, 놓으면 선 채로 회색이 된다")
    end,
})

--- **Leaving the tab is not the same as picking a different entry** (2026-08-23, 소유자). What is
--- ticked and which layers are open are the reader's answers, and `OnShow` used to throw both away
--- and start the entry over - so a glance at Overview undid however many clicks they had spent
--- setting up what to bring.
---
--- **What makes keeping them safe is that the tables do not move.** A tick is keyed by the action
--- table itself, and both walks that open a stored payload write into the tables rather than
--- replacing them (`GetEntryPayload`, `MigrateLayer`). Nothing headless can see that, because what
--- is being asked is what two frame scripts do in sequence.
RegisterTest("Storage: a tab change keeps what is ticked and what is open", {
    description = "탭을 떠났다 돌아오면 틱과 펼침이 그대로 남는가",
    run = function()
        local NAME = "Storage view state"

        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-ALT-F8" })
        InsertAction({ type = Constants.SPELL, value = 589, key = "CTRL-ALT-F9" })

        local panel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        if not panel or not panel.SelectEntry then
            return Fail(NAME, "보관함 패널을 못 얻었다 - 탭 번호나 LoadAddOn을 볼 것")
        end

        -- **창을 세우고 시작한다.** 패널 `OnShow`가 창의 콜백 버스에 등록하는데, 그 버스는
        -- `DebindFrameMixin:OnLoad`가 만들고 그것을 부르는 것은 창의 첫 `OnShow`다. 안 세우고
        -- 부르면 `DebindFrame.Event`가 nil이다.
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
            return Fail(NAME, format("전제가 깨졌다 - 액션 %d개, 레이어 %s",
                #listed, tostring(layer and layer.key)))
        end

        -- 고른 직후는 전부 틱에 전부 접힘이다. 읽는 사람이 손댈 만한 것을 하나씩 뒤집는다.
        local untickedAction = listed[1]
        panel:ToggleAction(untickedAction)
        panel:ToggleLayerCollapsed(layer.key)
        if panel.selected[untickedAction] or panel:IsLayerCollapsed(layer.key) then
            return Fail(NAME, "전제가 깨졌다 - 손댄 것이 그 자리에서 안 뒤집혔다")
        end

        -- 탭을 떠났다가 돌아온다. 창이 패널을 갈아끼울 때 도는 것이 이 둘이다.
        panel:OnHide()
        panel:OnShow()

        if panel:GetSelectedEntry() ~= entry then
            return Fail(NAME, "돌아왔더니 고른 엔트리가 바뀌었다")
        end
        if panel.selected[untickedAction] then
            return Fail(NAME, "풀어둔 틱이 다시 켜져 있다")
        end
        if panel:IsLayerCollapsed(layer.key) then
            return Fail(NAME, "펴둔 레이어가 다시 접혔다")
        end

        -- 나머지가 그대로 남았는지까지 본다. 위의 둘만 보면 "전부 꺼졌다"도 통과한다.
        local stillTicked = 0
        for _, action in ipairs(panel:EnumerateListedActions()) do
            if panel.selected[action] then
                stillTicked = stillTicked + 1
            end
        end
        if stillTicked ~= #listed - 1 then
            return Fail(NAME, format("틱이 %d개 남아야 하는데 %d개다", #listed - 1, stillTicked))
        end

        return Pass(NAME, format("틱 %d개와 펼친 레이어가 탭을 건너서 남았다", stillTicked))
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
    description = "탭 셋이 각자 자기 패널로 풀리는가 - 하나로 몰리거나 MissingPanel로 떨어지지 않는가",
    run = function()
        local NAME = "Panels resolve"

        local seen = {}
        for _, id in ipairs({ OVERVIEW_PANEL_ID, SWITCHES_PANEL_ID, STORAGE_PANEL_ID }) do
            local panel = DebindFrame:ResolvePanel(id)
            if not panel then
                return Fail(NAME, format("%d번 탭이 패널을 못 얻었다 - PANELS의 panelKey나 TOC를 볼 것", id))
            end
            if panel == DebindFrame.MissingPanel then
                return Fail(NAME, format("%d번 탭이 MissingPanel로 떨어졌다", id))
            end
            -- The whole point of the move: they are the frame's children rather than something
            -- reparented on the first press.
            if panel:GetParent() ~= DebindFrame then
                return Fail(NAME, format("%d번 패널의 부모가 창이 아니다", id))
            end
            if seen[panel] then
                return Fail(NAME, format("%d번 탭이 %d번과 같은 패널을 준다", id, seen[panel]))
            end
            seen[panel] = id
        end

        return Pass(NAME, "탭 4개가 서로 다른 패널 4개로")
    end,
})

-- **The width is a `KeyValue` in the XML and nothing checks it.** It used to be read back out of
-- `GetWidth()` in `OnLoad`, which worked only while the panel stood unanchored at load; pinned to
-- the host on four sides that read answers with the window's own width - the value fed back - and
-- every tab would quietly settle on one size. Turning the KeyValue back into a `<Size>` restores
-- exactly that failure, with no error anywhere.
RegisterTest("Panels: the window takes each tab's own width", {
    description = "탭을 옮기면 창 폭이 그 패널이 요구한 값으로 실제로 바뀌는가",
    run = function()
        local NAME = "Panel width"

        -- **The pair is Overview and Switches.** It was Overview and the export tab until the two
        -- sharing tabs became one that has two columns -- which asks for Overview's own width, and
        -- two panels legitimately wanting the same number leave this nothing to measure.
        local overview = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        local narrow = DebindFrame:ResolvePanel(SWITCHES_PANEL_ID)
        if not overview or not narrow then
            return Fail(NAME, "패널을 못 얻었다")
        end
        if not overview.preferredWidth or not narrow.preferredWidth then
            return Fail(NAME, format("폭을 안 들고 있다 (overview=%s, switches=%s)",
                tostring(overview.preferredWidth), tostring(narrow.preferredWidth)))
        end
        if overview.preferredWidth == narrow.preferredWidth then
            return Fail(NAME, format(
                "두 패널이 같은 폭(%d)을 요구한다 - 창 폭을 되읽고 있을 수 있다",
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
            return Fail(NAME, format("창이 안 따라간다 - switches %d(기대 %d), overview %d(기대 %d)",
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
    description = "끌어다 놓은 창이 탭을 옮겨 폭이 바뀌어도 왼쪽 변이 그대로인가",
    run = function()
        local NAME = "Left edge"

        local overview = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        local narrow = DebindFrame:ResolvePanel(SWITCHES_PANEL_ID)
        if not overview or not narrow then
            return Fail(NAME, "패널을 못 얻었다")
        end
        -- Two tabs of the same width would leave nothing to measure, and this would pass on any
        -- anchor at all. **Switches is the narrow one**; the storage tab asks for Overview's width.
        if overview.preferredWidth == narrow.preferredWidth then
            return Fail(NAME, format("두 탭이 같은 폭(%s)을 요구한다", tostring(overview.preferredWidth)))
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
            return Fail(NAME, "OnDragStop이 없다 - 창이 끌리지 않는다")
        end
        dragStop(DebindFrame)

        local before = DebindFrame:GetLeft()
        DebindFrame:SelectPanel(SWITCHES_PANEL_ID)
        local after = DebindFrame:GetLeft()
        if not before or not after then
            return Fail(NAME, "창의 왼쪽 변을 못 읽었다")
        end
        -- Within a pixel: `GetLeft` reads back what the frame ended up at, and the UI scale is in
        -- the middle of that (the tab width test above says the same thing).
        if math.abs(after - before) > 1 then
            return Fail(NAME, format("왼쪽 변이 %.0f에서 %.0f로 움직였다", before, after))
        end

        return Pass(NAME, format("%.0f 그대로 (폭 %d -> %d)",
            before, overview.preferredWidth, narrow.preferredWidth))
    end,
})

-- **The panel is always there; what can be missing is what it reads.** `EnsureStore` asks whether
-- `DebindPrivate.Store` was handed over, not whether the addon is loaded - the addon can be in
-- memory having handed over nothing, and every caller dereferences that table. Asking
-- `IsAddOnLoaded` reads as the natural thing to write (it was, first), and it turns this fallback
-- into an error on the tab.
RegisterTest("Panels: no store means no panel, not an error", {
    description = "Store를 못 얻으면 ResolvePanel이 nil을 내서 MissingPanel이 서는가",
    run = function()
        local NAME = "Store missing"

        local saved = DebindPrivate.Store
        if not saved then
            return Fail(NAME, "시작부터 Store가 없다 - 이 테스트가 잴 것이 없다")
        end
        AddTeardown(function() DebindPrivate.Store = saved end)

        DebindPrivate.Store = nil
        local storagePanel = DebindFrame:ResolvePanel(STORAGE_PANEL_ID)
        local overviewPanel = DebindFrame:ResolvePanel(OVERVIEW_PANEL_ID)
        DebindPrivate.Store = saved

        if storagePanel ~= nil then
            return Fail(NAME, "Store가 없는데 보관함 패널을 내줬다 - 그 뒤에서 nil을 인덱싱한다")
        end
        -- Overview reads none of it, so it must not be dragged down with them.
        if overviewPanel == nil then
            return Fail(NAME, "Store와 무관한 오버뷰까지 막혔다")
        end

        return Pass(NAME, "임포트는 막히고 오버뷰는 선다")
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
    description = "목록의 켜기/끄기 단추가 실제로 그 스위치를 건 키를 붙였다 뗐다 하는가",
    run = function()
        local NAME = "Switch row toggle"
        local KEY = "CTRL-SHIFT-F7"
        local SWITCH = "$rowtoggle"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 이 단추가 비활성이라 판정이 안 선다")
        end

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            DebindPrivate.db.char.switches[SWITCH] = nil
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.MANUAL, value = false }

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
            return Fail(NAME, format("목록에 그 스위치의 행이 없다. 이름들: [%s]", names))
        end
        if not row.ToggleButton:IsEnabled() then
            return Fail(NAME, "직접 켜고 끄는 스위치인데 단추가 비활성이다")
        end

        -- **Pressed, not called.** `OnToggleClick` reached directly would pass on a row whose XML
        -- lost its `OnClick`, which is exactly the wiring this test is here for.
        row.ToggleButton:Click()

        local whenOn = GetBindingAction(KEY, true) or ""
        if whenOn:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("켰는데 키가 %q다 - 값이 코드젠까지 안 갔다", whenOn))
        end

        row.ToggleButton:Click()

        local whenOff = GetBindingAction(KEY, true) or ""
        if whenOff ~= "" then
            return Fail(NAME, format("껐는데 키가 %q로 남았다", whenOff))
        end

        return Pass(NAME, "눌러서 켜짐 -> 걸림 / 다시 눌러 꺼짐 -> 빠짐")
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
    description = "식 편집 상자가 지금 식을 들고 열리는가",
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
            return Fail(NAME, "상자가 안 떴다")
        end
        local editBox = dialog:GetEditBox()
        if not editBox then
            return Fail(NAME, "상자에 편집칸이 없다 - 클라이언트가 이름을 또 바꿨다")
        end
        local text = editBox:GetText()
        if text ~= EXPR then
            return Fail(NAME, format("상자가 %q를 들고 열렸다 - 적어둔 식이 안 실렸다", text))
        end

        return Pass(NAME, format("%q", text))
    end,
})

-- **The button that replaced the portrait's dropdown** (3c, §6-C of
-- `devdocs/redesigning-custom-states.md`). Making a switch was a menu on the window's title bar
-- until now; it is this button, the condition menu and an on/off/toggle action's own menu, and all
-- three go through `DebindUI.ShowNewSwitchBox`.
--
-- **Pressed and typed into, not called.** `ShowNewSwitchBox` reached directly passes on a panel
-- whose XML lost the `OnClick`, and `SetText` without the box's own accept path passes on a dialog
-- whose button does nothing. Both of those are the wiring this test is here for.
RegisterTest("Switches tab: the New switch button makes one", {
    description = "목록 아래 단추가 상자를 띄우고, 적어 넣은 이름으로 스위치가 생기는가",
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
            return Fail(NAME, "전제가 깨졌다. 그 이름의 스위치가 이미 있다")
        end

        local panel = OpenSwitchesTab()
        if not panel.NewButton then
            return Fail(NAME, "패널에 NewButton이 없다. XML이 안 실렸다")
        end
        if not panel.NewButton:IsEnabled() then
            return Fail(NAME, "단추가 비활성이다")
        end

        panel.NewButton:Click()

        local _, dialog = StaticPopup_Visible("GENERIC_INPUT_BOX")
        if not dialog then
            return Fail(NAME, "단추를 눌렀는데 상자가 안 떴다")
        end
        local editBox = dialog:GetEditBox()
        if not editBox then
            return Fail(NAME, "상자에 편집칸이 없다. 클라이언트가 이름을 또 바꿨다")
        end
        -- **The box opens empty, and `$` is drawn beside it.** The sigil is furniture now: it
        -- cannot be typed over, deleted or doubled, and what the reader types is joined to it by
        -- the caller. So the box holding anything at all is the failure, and the switch coming out
        -- named `$madehere` below is what says the two were joined.
        if editBox:GetText() ~= "" then
            return Fail(NAME, format("상자가 %q를 들고 열렸다. 빈 채로 열려야 한다",
                editBox:GetText()))
        end

        if not TypeInto(editBox, strsub(SWITCH, 2)) then
            return Fail(NAME, "편집칸에 OnTextChanged가 없다")
        end
        -- **[Done] is pressed, not the callback called.** The button stays disabled until the box
        -- has text in it (`StaticPopup_StandardNonEmptyTextHandler`), so pressing it is also what
        -- says `TypeInto` reached the handler a hand would have.
        local accept = dialog:GetButton1()
        if not accept:IsEnabled() then
            return Fail(NAME, "이름을 적었는데 [완료]가 비활성이다")
        end
        accept:Click()

        if not DebindPrivate.Switches[SWITCH] then
            local names = table.concat(DebindPrivate.GetSwitchNames(), " ")
            return Fail(NAME, format("스위치가 안 생겼다. 있는 것: [%s]", names))
        end

        -- The list has to have heard about it. Making one fires `OnSwitchesChanged` and the panel
        -- rebuilds off that, so a row missing here is that callback not reaching an open tab.
        local row = WaitUntil(function() return SwitchRow(panel, SWITCH) end, 2)
        if not row then
            return Fail(NAME, "스위치는 생겼는데 목록에 행이 안 섰다")
        end

        return Pass(NAME, SWITCH .. " 생성 + 목록에 행")
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
    description = "오버라이드 행들이 그려지고, 읽는 액션이 있을 때 이기는 행에만 표시가 붙는가",
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
        DebindPrivate.Switches[SWITCH] = { mode = MODES.MANUAL, value = false }

        local layerKey = DebindPrivate.GetSwitchLayerKey(
            DebindPrivate.GetLayerID(C_SpecializationInfo.GetSpecialization(), true))
        if not layerKey then
            return Fail(NAME, "이 캐릭터 이 전문화의 레이어 키가 안 나온다")
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
                "행이 %d개다 - 얹은 오버라이드 하나와 계정 전체 하나, 둘이 나와야 한다", drawn))
        end

        -- Nothing binds `$rowlayers` yet, so it is outside the compile and no row is the live
        -- answer to anything.
        local function ReadTicks()
            local marked, unmarked = {}, {}
            for _, row in ipairs(rows) do
                if not row.Check then
                    return nil, "행에 Check가 없다 - 템플릿이 parentKey를 잃었다"
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
                "아무 액션도 안 읽는 스위치인데 %d행에 표시가 붙었다 [%s] - 이길 자리는 있어도 "
                .. "그 값을 걷어가는 곳이 없다", #marked, table.concat(marked, " ")))
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
            return Fail(NAME, format("표시된 행이 %d개다 [%s] - 이기는 행은 언제나 하나다",
                #marked, table.concat(marked, " ")))
        end
        if marked[1] ~= layerKey then
            return Fail(NAME, format(
                "%q에 표시가 붙었다 - 이기는 것은 %q인데 목록이 반대로 말한다", marked[1], layerKey))
        end
        if #unmarked == 0 then
            return Fail(NAME, "안 이기는 행이 하나도 안 그려졌다 - 어디가 다른지 볼 수가 없다")
        end

        return Pass(NAME, format("%d행, 안 읽힐 때 표시 없음 -> 읽히면 %s", #rows, marked[1]))
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
--- when the tick moved onto the action (`devdocs/building-export-import.md` 12절).
---
--- **`HandleEscape` rather than a key.** A run unbinds the game's own bindings, so a real ESCAPE
--- measures the runner as much as the window; and this function is split out from the key plumbing
--- to be the order on its own, which is exactly what is being asked here.
RegisterTest("Escape: the sharing dialogs close before the window", {
    description = "공유 다이얼로그가 떠 있으면 ESC가 창 대신 그 다이얼로그부터 한 칸씩 닫는가",
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

        -- 둘 다 세운다.
        DebindCopyFrame:ShowText("DEBIND-TEST")
        DebindPasteFrame:Open()

        local steps = {
            { frame = DebindPasteFrame, name = "붙여넣기 창" },
            { frame = DebindCopyFrame,  name = "복사 창" },
        }
        for _, step in ipairs(steps) do
            if not step.frame:IsShown() then
                return Fail(NAME, format("%s을 세우지도 못했다", step.name))
            end
        end

        for i, step in ipairs(steps) do
            if not DebindFrame:HandleEscape() then
                return Fail(NAME, format("%d번째 ESC를 아무도 안 먹었다", i))
            end
            if step.frame:IsShown() then
                return Fail(NAME, format("ESC %d번째가 %s을 안 닫았다", i, step.name))
            end
            -- **여기서 창이 닫히면 그게 이 테스트가 지키는 버그다.** 다이얼로그만 주인 없이 남는다.
            if not DebindFrame:IsShown() then
                return Fail(NAME, format("%s을 닫아야 할 ESC가 창을 닫았다", step.name))
            end
            -- 한 번에 한 칸. 아직 차례가 아닌 것까지 데려가면 한 번 누르고 두 개가 사라진다.
            for j = i + 1, #steps do
                if not steps[j].frame:IsShown() then
                    return Fail(NAME, format("%s을 닫는 ESC가 %s까지 데려갔다", step.name, steps[j].name))
                end
            end
        end

        -- 그리고 셋이 없어진 **뒤에야** 창이 닫힌다. 이 줄이 없으면 위의 통과는 "ESC가 아무것도
        -- 안 한다"로도 똑같이 설명된다.
        if not DebindFrame:HandleEscape() then
            return Fail(NAME, "다이얼로그가 다 닫힌 뒤의 ESC를 아무도 안 먹었다")
        end
        if DebindFrame:IsShown() then
            return Fail(NAME, "다이얼로그가 다 닫혔는데 창이 ESC에 안 닫힌다")
        end

        return Pass(NAME, "가져오기, 붙여넣기, 복사, 그다음 창 순으로 한 칸씩 물러났다")
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
    description = "전환이 States와 창이 읽는 값을 함께 뒤집는지 (연속 두 번)",
    run = function()
        local NAME = "Custom state toggle"
        local KEY = "ALT-F7"
        local MODES = Constants.SWITCH_MODES

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 리빌드가 미뤄져서 판정이 안 선다")
        end

        local saved = DebindPrivate.Switches["$state4"]
        AddTeardown(function()
            DebindPrivate.Switches["$state4"] = saved
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        local options = { mode = MODES.MANUAL, value = false }
        DebindPrivate.Switches["$state4"] = options

        -- Registered through a condition. What this test looks at is the toggle, not registration,
        -- and if a broken registration turned this one red as well neither could be read off the
        -- result. Macrotext rather than a spell because it binds whoever the character is.
        InsertAction({ type = Constants.MACROTEXT, value = "/say toggle test", key = KEY, ["$state4"] = false })
        ApplyBindings()

        local st = ReadSecureState("$state4")
        if not (st and st.present) then
            return Fail(NAME, "전제가 깨졌다 - 조건으로 쓴 상태도 States에 없다")
        end
        if st.value ~= false then
            return Fail(NAME, format("전제가 깨졌다 - 저장값은 꺼짐인데 States는 %s다", tostring(st.value)))
        end

        local frame = DebindPrivate.SwitchesUpdaterFrame
        frame:SetAttribute("$state4", "toggle")
        st = ReadSecureState("$state4")
        if not (st and st.value == true) then
            return Fail(NAME, "첫 전환이 States를 안 뒤집었다")
        end

        frame:SetAttribute("$state4", "toggle")
        st = ReadSecureState("$state4")
        if not (st and st.value == false) then
            return Fail(NAME, "두 번째 전환이 안 먹었다 - 같은 속성값을 다시 쓴 것이 안 통한다")
        end

        -- The mirror arrives on `C_Timer.After(0)` (`OnSwitchChanged`, `Misc.lua`). It is what
        -- the window reads, so a mirror that does not follow leaves the restricted side right and
        -- the screen lying.
        coroutine.yield(0)
        if options.value ~= false then
            return Fail(NAME, format("창이 읽는 값이 안 따라왔다 (options.value=%s)", tostring(options.value)))
        end

        return Pass(NAME, "꺼짐 -> 켜짐 -> 꺼짐, 미러까지")
    end,
})

-- **이름이 `$state1`~`$state5`를 벗어난 첫 자리.** 코드젠이 `SWITCH_INDICES`에 없는 이름을
-- 문 앞에서 돌려보냈고, 그래서 조건에 그런 이름이 있어도 굽히는 것이 아무것도 없었다. 문이
-- 사라진 뒤에 이름을 가르는 것은 정의가 있느냐 하나뿐이다.
--
-- 셋을 한 자리에서 본다. 켜짐이 없으면 꺼짐은 "원래 아무것도 안 걸린다"와 구분이 안 되고,
-- 꺼짐이 없으면 켜짐은 "조건을 아예 안 본다"와 구분이 안 된다.
RegisterTest("Switch condition on a name outside the five", {
    description = "$state1~5 밖의 이름이 조건으로 서는지, 정의가 없으면 안 나가는지",
    run = function()
        local NAME = "Free switch name"
        local KEY = "CTRL-SHIFT-F10"
        local UNDEFINED_KEY = "CTRL-SHIFT-F11"
        local MODES = Constants.SWITCH_MODES

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 리빌드가 미뤄져서 판정이 안 선다")
        end

        -- 슬롯만 갈아끼우는 이유는 위 `Undefined $state inside a state's own expression`의
        -- 주석에 있다. `$burst`는 사용자 프로필에 있을 리 없지만, 있어도 되돌아간다.
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
                "정의해둔 $burst가 켜져 있는데 %q - 다섯 밖의 이름이 코드젠까지 안 갔다", whenOn))
        end

        DebindPrivate.SetSwitchValue("$burst", false)
        ApplyBindings()

        local whenOff = GetBindingAction(KEY, true) or ""
        if whenOff ~= "" then
            return Fail(NAME, format(
                "$burst가 꺼졌는데 키가 %q로 남았다 - 이름은 갔는데 값이 안 비교된다", whenOff))
        end

        -- 정의가 없는 이름. 조건을 통째로 떨어뜨리면 그 액션은 **넓어져서** 나가므로,
        -- 여기서 나는 실패는 "안 걸린다"가 아니라 "조건 없이 걸린다"다.
        local whenUndefined = GetBindingAction(UNDEFINED_KEY, true) or ""
        if whenUndefined ~= "" then
            return Fail(NAME, format(
                "정의 없는 이름을 건 액션이 %q로 나갔다 - 조건이 사라져 상시 발동한다", whenUndefined))
        end

        -- **막는 겹이 둘이다.** 마커가 그 액션을 `KeyMap`에서 빼고(행이 빨개지고 툴팁이 이름을
        -- 적는다), 그 아래에서 코드젠이 조건을 거짓으로 굽는다. 위 한 줄은 둘 중 하나만 살아
        -- 있어도 초록이고, **어느 쪽이 막았는지는 여기서 물을 일이 아니다** - 마커가 무엇을
        -- 답하는지는 순수 함수라 `tests/issue_spec.lua`가 본다. 여기가 답하는 것은 그 답이
        -- 실제로 키를 안 걸게 하느냐다(`BuildKeyMap`의 게이트).

        -- **전투 중에 밟는 길.** 위 둘은 `ApplyBindings()`가 도는 비보안 리빌드인데, 전투
        -- 중에는 그것이 미뤄지므로 값이 바뀌었을 때 키를 다시 정하는 것은 제한 환경 쪽이다:
        -- `SetSwitch` -> `DirtyFlags` -> `state-unitexists` -> 제한 환경의 `UpdateBindings`.
        -- 그 길이 이 이름을 알려면 코드젠이 `bindings.updateFlags`에 이름을 실었어야 하고,
        -- 안 실렸으면 전투가 끝날 때까지 키가 안 살아난다.
        --
        -- 기다리지 않는다. `SetAttribute`가 핸들러를 그 자리에서 돌리고 제한 환경의
        -- `SetBindingClick`은 즉시 건다(`devdocs/when-a-change-takes-effect.md`).
        DebindPrivate.SwitchesUpdaterFrame:SetAttribute("$burst", true)

        local afterToggle = GetBindingAction(KEY, true) or ""
        if afterToggle:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format(
                "리빌드 없이 켰는데 키가 %q다 - 전투 중이면 안 살아난다", afterToggle))
        end

        return Pass(NAME, "$burst 켜짐 -> 걸림 / 꺼짐 -> 빠짐 / 미정의 -> 마커 붙고 빠짐 / 리빌드 없이 켜짐")
    end,
})

-- Test Cases: 레이어 오버라이드 (§4-6 ~ §4-9)
--
-- 정의는 계정 것이고 **동작만 레이어에서 덮인다.** 어느 답이 이기는지는 `tests/switch_spec.lua`가
-- 표를 되읽어서 보고, 그 답이 실제로 키까지 가느냐는 `tests/boundkey_spec.lua`가 본다 -
-- `ApplySwitchResets`가 값을 다시 걸고, 코드젠이 이긴 행의 `mode`와 `expr`을 굽고, 상태 루프가
-- 그 키를 잡는 사슬 전체다.
--
-- **여기 남는 것은 하나뿐이다.** 아래를 보라.
-----------------------------------------------------------

-- **오버라이드가 어느 이름 아래 쌓이느냐.** 캐릭터 레이어의 키에 이 캐릭터가 안 들어 있으면
-- 다음 캐릭터가 남의 답을 자기 것으로 읽는다.
--
-- **헤드리스가 이것만 못 본다.** 같은 문자열을 `tests/switch_spec.lua`가 보지만 그쪽 GUID는
-- shim이 지어낸 것이라, 스펙이 확인하는 것은 자기가 심은 값이 돌아왔다는 것뿐이다. 진짜
-- `UnitGUID`로 지은 키가 맞는지는 클라이언트만 답한다.
RegisterTest("Switch override: the layer key carries this character", {
    description = "이 캐릭터·이 전문화의 오버라이드 키에 진짜 GUID가 들어 있는가",
    run = function()
        local NAME = "Switch override layer key"

        local layerKey = DebindPrivate.GetSwitchLayerKey(
            DebindPrivate.GetLayerID(C_SpecializationInfo.GetSpecialization(), true))
        if not layerKey then
            return Fail(NAME, "이 캐릭터 이 전문화의 레이어 키가 안 나온다")
        end

        local guid = UnitGUID("player")
        if not layerKey:find(guid, 1, true) then
            return Fail(NAME, format(
                "캐릭터 레이어의 키가 %q다 - %q가 없으면 다음 캐릭터가 남의 답을 읽는다",
                layerKey, guid))
        end

        -- **반쪽 대조.** 직업 레이어의 키에는 캐릭터가 들어 있으면 안 된다. 없으면 위 한 줄은
        -- "모든 레이어 키에 GUID가 붙는다"와 구분이 안 되고, 그러면 같은 직업의 다른 캐릭터가
        -- 공유해야 할 답을 못 읽는다.
        local classKey = DebindPrivate.GetSwitchLayerKey(
            DebindPrivate.GetLayerID(C_SpecializationInfo.GetSpecialization(), false))
        if classKey and classKey:find(guid, 1, true) then
            return Fail(NAME, format(
                "직업 레이어의 키가 %q다 - 캐릭터가 들어가면 같은 직업끼리 답을 못 나눈다",
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
RegisterTest("Custom target survives a rebuild", {
    description = "지정한 @custom1이 리빌드 뒤에도 남는지",
    run = function()
        local NAME = "Custom target survives"
        local KEY = "CTRL-F6"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 지정도 리빌드도 미뤄져서 판정이 안 선다")
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
            return Fail(NAME, format("전제가 깨졌다 - 대상 지정 액션이 키에 안 걸렸다 (%q)", action))
        end

        DebindPrivate.UnitWatch:SetAttribute("custom1", "player")
        local u = ReadSecureUnit("custom1")
        if not (u and u.value == "player") then
            return Fail(NAME, format("전제가 깨졌다 - 지정이 UnitAliasMap에 안 들어갔다 (%s)",
                u and format("%q", u.value) or "답 없음"))
        end

        ApplyBindings()
--
-- **여기 남는 이유는 그 셋이 아니라 마지막 한 줄이다.** 셋은 `tests/boundkey_spec.lua`가 볼
-- 수 있다. 못 보는 것은 **전투 중에 밟는 길**이다: `SwitchesUpdaterFrame`에 속성을 쓰면
-- 클라이언트가 `_onattributechanged`를 부르고 거기서 키가 다시 걸리는데, 하네스는 속성을
-- 저장만 하고 그 핸들러를 안 부른다. 스펙이 본문을 손으로 부르면 재는 것이 "본문이 맞느냐"로
-- 바뀌고, 여기서 묻는 것은 **쓰기가 핸들러를 부르느냐**다.

        u = ReadSecureUnit("custom1")
        if not u then
            return Fail(NAME, "보안 환경이 답을 안 줬다")
        end
        if u.value ~= "player" then
            return Fail(NAME, format("리빌드가 지정한 대상을 지웠다 (%q) - 지정 액션은 별칭을 등록시키지 않는다",
                u.value))
        end

        return Pass(NAME, "리빌드 뒤에도 custom1 = player")
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

-- **The 0.2s beat runs only where there is something to measure**
-- (`devdocs/trimming-the-restricted-hot-paths.md`, item 3). A profile with no conditions at all
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
    description = "잴 것이 없으면 0.2초 박자를 놓고, 조건 하나가 다시 걸게 하는지",
    run = function()
        local NAME = "State poll registration"
        local PLAIN = "CTRL-SHIFT-F10"
        local CONDITIONAL = "CTRL-SHIFT-F11"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 리빌드가 미뤄져서 판정이 안 선다")
        end

        local driver = DebindPrivate.BindingDriver
        if not driver then return Fail(NAME, "BindingDriver가 없다") end

        -- One conditional action left behind by an earlier test and the beat is registered for
        -- reasons of its own. An empty layer is this test's premise, and it leaves one behind.
        CleanupActions()
        AddTeardown(CleanupActions)

        InsertAction({ type = Constants.SPELL, value = 585, key = PLAIN })
        ApplyBindings()

        if UnitWatchRegistered(driver) then
            return Fail(NAME, "조건이 하나도 없는 프로필인데 0.2초 박자가 걸려 있다")
        end

        local bound = GetBindingAction(PLAIN, true) or ""
        if bound:sub(1, 6) ~= "CLICK " then
            return Fail(NAME, format("박자를 놓았더니 키가 안 걸렸다 (%q)", bound))
        end

        -- **A different key.** Put on the same one, the unconditional action already covers the
        -- condition space, so the key stays fixed-wiring -- and a key like that registers no axis
        -- in `_measuredStates`. The condition would be in the profile with nothing measured for
        -- it, and this test would go quietly meaningless.
        InsertAction({ type = Constants.SPELL, value = 585, key = CONDITIONAL, combat = true })
        ApplyBindings()

        if not UnitWatchRegistered(driver) then
            return Fail(NAME, "전투 조건을 넣었는데 0.2초 박자가 안 돌아왔다")
        end

        return Pass(NAME, "잴 것에 따라 등록이 붙었다 떨어진다")
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
            units = { hover = {} },
            frameTypes = Constants.FRAMETYPE_GROUP,
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

--
-- **And that door is why this stays.** The write lands on the UnitWatch header, and
-- `tests/restricted.lua` replays **only the driver's** bodies -- every other header has its own
-- managed environment in the game, and replaying its bodies into the driver's would put their
-- globals in the wrong table. So the one thing this measures is the one thing that harness declines
-- to have an opinion about.
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

-- 등록이 풀린 프레임에 커서가 들어갔을 때.
--
-- 해제는 래퍼를 떼지 않는다 (`FrameRegistry.lua`의 `_hoverWrapped`). 뗄 수 있는 것은 맨 위
-- 래퍼뿐이고 그것이 우리 것이라는 보장이 없어서인데, 그래서 등록이 풀린 프레임에서도 우리
-- `setup_onenter`가 계속 돈다. 거기서 무엇을 하느냐가 해제의 실체다.
--
-- 그냥 물러나면 안 된다. 마우스 포커스는 한 번에 하나이므로 **추적 안 하는 프레임 안에 커서가
-- 있다는 것 자체가 우리가 마지막으로 적어둔 프레임 안에는 없다는 증거다.** 그래서 슬롯을
-- 비운다. `OnLeave` 유실의 청소이기도 하다.
--
-- **여기 남는 이유.** 값 쪽은 `tests/hover_spec.lua`가 같은 두 스니펫을 돌려 이미 본다. 이
-- 테스트가 더 보는 것은 하나다: 감싼 스크립트 안에서 `RunAttribute`로 다른 본문을 부르는 것을
-- **진짜 샌드박스가 받아주는가.** 안 받아주면 오류도 로그도 없이 그 갈래만 죽는다.
RegisterTest("Hover slot: a deregistered frame stands the slot down", {
    description = "등록이 풀린 프레임에 들어가면 hover 슬롯이 비는가",
    run = function()
        local NAME = "Deregistered frame"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 해제가 막힌다")
        end

        -- hover 조건이 있어야 hover 축이 측정되고 이 슬롯이 읽을 값을 갖는다.
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
            return Fail(NAME, "전제가 깨졌다. UnregisterFrame이 행을 안 지웠다")
        end

        HoverEnter(tracked)
        AddTeardown(function() HoverLeave(tracked) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("진입 후 hover=%s, player여야 한다", tostring(GetHoverUnit())))
        end

        -- 래퍼가 그대로 붙어 있으므로 여기도 우리 본문이 돈다.
        --
        -- **기다리지 않는다.** `SecureHandlerExecute`는 본문을 돌리고 나서 돌아오고, 슬롯이
        -- 안 비는 것이 바로 이 테스트가 찾는 결함이다. 기다리면 폴링이 정리한 값을 읽고
        -- 통과할 수 있다.
        HoverEnter(dropped)

        if GetHoverUnit() ~= nil then
            return Fail(NAME, format(
                "추적 안 하는 프레임에 들어갔는데 hover=%s. 옛 프레임이 슬롯에 남았다",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "등록이 풀린 프레임 진입이 슬롯을 비운다")
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

-- **A registered frame gets the release edge and nothing else.** That edge is the one a frame's
-- own actions run on: `SECURE_ACTIONS.menu` acts on the release and returns while `down` is true,
-- so a frame missing it loses its unit menu outright, with no error to say so. `target` does not
-- gate on the edge, which is why targeting went on working and hid that through several releases.
-- Neither is tied to a button, since `Enum.ClickBindingInteraction.Target` and `.OpenContextMenu`
-- are both movable in Blizzard's click binding window, which is why this asks for the whole
-- release edge rather than one button's.
--
-- The press edge is asked about too, and it has to be absent. `UpdateRegisteredClicks` runs on
-- frames another addon owns, and registering an edge that addon never asked for runs its own
-- `OnClick` a second time per click. `unitframeUseMouseDown` registered that edge, and this is
-- what it was removed over.
--
-- The registration call is captured on a frame the test owns, because there is no API that asks a
-- frame which clicks it is registered for. Shadowing the method on our own frame leaves every
-- other frame alone, and the real one is still called.
RegisterTest("Click-cast: a registered frame keeps the release edge and only that one", {
    description = "등록한 프레임이 뗄 때 엣지만 갖는가",
    run = function()
        local NAME = "Click edges"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 RegisterForClicks가 막힌다")
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
            return Fail(NAME, "등록 자체가 안 돌았다")
        end

        local function Registered(...)
            for i = 1, select("#", ...) do
                local want = select(i, ...)
                for _, got in ipairs(captured) do
                    if got == want then return true end
                end
            end
            return false
        end

        local seen = table.concat(captured, " ")

        if not Registered("AnyUp") then
            return Fail(NAME, format(
                "[%s] 에 떼는 엣지가 없다. 유닛 메뉴가 도는 자리가 그 엣지뿐이라 메뉴가 걸린 "
                .. "버튼이 죽는다", seen))
        end

        if Registered("AnyDown", "LeftButtonDown", "RightButtonDown", "MiddleButtonDown") then
            return Fail(NAME, format(
                "[%s] 에 누르는 엣지가 있다. 유닛프레임 애드온이 요청한 적 없는 엣지라 그쪽 "
                .. "OnClick이 클릭 한 번에 두 번 돈다", seen))
        end

        return Pass(NAME, seen)
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
    description = "클릭캐스팅 전용 키가 상태 루프 표에서 빠지고도 조건 판정은 그대로인가",
    run = function()
        local NAME = "Click-cast only"
        local KEY = "BUTTON3"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 프레임 등록과 래핑이 막힌다")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "다시 굽기 실패: " .. tostring(err))
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
        if not m then return Fail(NAME, "제한 환경이 답을 안 보냈다") end

        -- 긍정 쪽을 먼저 본다. "상태 구동이 아님"은 레코드가 아예 안 나간 키도 참이다.
        if not m.clickCast then
            return Fail(NAME, "ClickCastKeys에 없다 - 빠진 게 아니라 레코드가 안 나갔다")
        end
        if m.stateDriven then
            return Fail(NAME, "StateDrivenBindings에 들어 있다 - 키를 잡는 레코드가 하나도 "
                .. "없는데 상태 루프가 매 틱 훑는다")
        end

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end
        local target = targets[1]

        -- 레코드가 호버를 조건으로 들고 있고 클릭캐스팅 경로는 그것을 캐시가 아니라 프레임에서
        -- 읽으므로, 커서가 실제로 그 위에 있어야 한다.
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
            return Fail(NAME, "전투로 두고도 안 골랐다 - 등록을 끊으면서 판정까지 끊겼다")
        end

        local ran2, miss = judge(false)
        if not ran2 then return Fail(NAME, tostring(miss)) end
        if miss ~= nil then
            return Fail(NAME, format("비전투인데 %s를 골랐다 - combat 조건을 안 보고 있다",
                tostring(miss)))
        end

        return Pass(NAME, format("clickCast만, 전투에서 %s / 비전투에서 없음", tostring(hit)))
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
    description = "죽었다고 주입하면 죽음 조건 바인딩이 실제로 걸리는가",
    run = function()
        local NAME = "Dead injection"
        local KEY = "CTRL-SHIFT-F10"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 주입 결과와 실제가 구분되지 않는다")
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
            units = { hover = {} },
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

-- **Kept here.** `tests/eval_spec.lua` runs the same `EVAL_SNIPPET` against the same records,
-- so what this adds is the two things it cannot reach: a body the sandbox really compiled, and
-- `GetBindingAction` agreeing that the key arrives under the name we bound.
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
            if got.conditions.combat ~= want then
                return Fail(NAME, format("combat=%s 인데 combat=%s 레코드(%d번)를 골랐다",
                    tostring(want), tostring(got.conditions.combat), idx))
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

-- **The click bakes the macro body** (`devdocs/trimming-the-restricted-hot-paths.md`, item 2).
-- A body that goes on a button is baked by nobody when a state moves, and by the click that
-- picks that button.
--
-- The value itself is headless (`tests/hover_spec.lua`). **What is answerable only here is
-- whether that write goes through**: inside the wrapper it sets an attribute on a protected
-- frame, and the game reads the same name a moment later. If it does not go through, nothing
-- raises and the old body fires.
RegisterTest("Click bakes the deferred macro body", {
    description = "@hover 매크로 본문을 클릭이 굽는지 (제한 환경의 SetAttribute가 통하는지)",
    run = function()
        local NAME = "Deferred macrotext"
        local KEY = "CTRL-SHIFT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 리빌드가 미뤄져서 판정이 안 선다")
        end

        AddTeardown(CleanupActions)

        local frame, why = CreateTestUnitFrame("player", "unit")
        if not frame then
            return Fail(NAME, "테스트 프레임 등록이 거절됐다: " .. tostring(why))
        end

        InsertAction({ type = Constants.MACROTEXT, value = "/cast [@hover] Debind", key = KEY })
        ApplyBindings()

        local binding = GetNthBinding(KEY, 1)
        local button = binding and binding.clickbutton
        if not button then
            return Fail(NAME, "전제가 깨졌다 - 이 액션에 클릭 버튼 이름이 안 붙었다")
        end

        SetFrameUnit(frame, "player")
        HoverEnter(frame)
        WaitForHoverSlot(true)

        -- **Nobody should have baked it yet.** What is here is what `StampBinding` wrote, and
        -- `@hover` still standing in it is the proof that the poll does not touch this body.
        local raw = DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. button)
        if not (raw and raw:find("@hover", 1, true)) then
            return Fail(NAME, format("전제가 깨졌다 - 클릭 전에 본문이 벌써 %q다", tostring(raw)))
        end

        local ok, evalWhy = EvalClickTimeKey(KEY)
        if not ok then
            return Fail(NAME, evalWhy)
        end
        WaitForWinner()

        local baked = DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. button)
        if not (baked and baked:find("@player", 1, true)) then
            return Fail(NAME, format("클릭이 본문을 안 구웠다 (%q)", tostring(baked)))
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
    -- 평평하게 적고 한 자리에서 옮긴다. `InsertAction`이 하는 것과 같은 함수다.
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

-- **Both places, deliberately.** The same sweep runs headless (`tests/eval_spec.lua`), and this
-- one is the anchor: four axes over seven records is where an interpretation of the restricted
-- environment and the real one would part, and there is no other way to find out that they
-- have (`going-headless-outside-the-ui.md` §9).
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

-- **Both places, deliberately.** The second anchor (§9). The headless twin is in
-- `tests/eval_spec.lua`; keeping this one is what would show the two sides parting.
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
-- Test Cases: The macro store as an input
-----------------------------------------------------------

-- **A `MACRO` action naming a macro that does not exist is left out of the build entirely**
-- (`GetMissingMacroName` -> `BINDING_ISSUE_MISSING_MACRO` -> `BuildKeyMap`), which makes the macro
-- store an input to what the keys are. Nothing was watching it: create the macro and the row stops
-- being red -- the window says nothing is wrong -- while the key stays dead until something
-- unrelated rebuilds, or a `/reload`. `UPDATE_MACROS` is registered for that.
--
-- **It makes a real macro rather than faking one.** Overriding `GetMacroInfo` would measure whether
-- a rebuild reads the store, which was never in doubt; what broke is that **no rebuild happens**,
-- and the only thing that starts one is the client's own event. A stub cannot send it.
--
-- Deleting it belongs to the runner, so it goes however this ends.
RegisterTest("Macro store: creating the missing macro revives the key", {
    description = "없는 매크로를 만들면 리로드 없이 그 키가 살아나는가",
    run = function()
        local NAME = "Macro revive"
        local KEY = "CTRL-SHIFT-F6"
        local MACRO = "DebindTestRevive"

        if InCombatLockdown() then
            return Fail(NAME, "전투 중에는 매크로를 만들 수 없다")
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
            return Fail(NAME, format("매크로가 없는데 키가 이미 잡혀 있다: %q", before))
        end

        -- **Asked of the store, not of the return value.** `CreateMacro` raises when there is no
        -- room, and `0` back would pass a plain `not` check anyway - `0` is true in Lua. Either way
        -- the answer wanted here is whether the macro is now there.
        pcall(CreateMacro, MACRO, 132219, "/say debtest")
        if GetMacroIndexByName(MACRO) == 0 then
            return Fail(NAME, "매크로를 못 만들었다 - 매크로 칸이 다 찼을 수 있다")
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
                "매크로를 만들었는데 키가 아직 죽어 있다 (%q) - UPDATE_MACROS를 아무도 안 듣는다",
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
    description = "자기보다 새 프로필 앞에서 창이 안 열리고, /deb reset 1단계가 아무것도 안 지우는가",
    run = function()
        local NAME = "Stand down"

        -- **The negative first.** `/deb reset` in ordinary operation must fall through to the
        -- window, not wipe the account, and asking before the flag is up is the only way to see
        -- that the guard inside the handler is the thing answering.
        if DebindPrivate.HandleNewerProfileReset({ "reset" }) then
            return Fail(NAME, "물러선 상태가 아닌데 /deb reset이 먹혔다. 상시 초기화 명령이 돼 있다")
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
            return Fail(NAME, "물러선 상태에서 창이 열렸다. 여기서 넣는 바인딩은 저장이 안 된다")
        end

        -- The compartment button is a second door into the same call, and it is the one a user
        -- reaches for when a slash command looks broken.
        Debind_CompartmentFunc()
        if DebindFrame:IsShown() then
            return Fail(NAME, "구획 버튼으로는 창이 열렸다")
        end

        local before = _G.DebindVars
        if not DebindPrivate.HandleNewerProfileReset({ "reset" }) then
            return Fail(NAME, "물러선 상태인데 /deb reset을 아무도 안 받았다")
        end
        if _G.DebindVars ~= before then
            return Fail(NAME, "1단계가 저장된 표를 갈아치웠다. 확인을 묻기도 전에 지워진다")
        end

        -- A word that is not the token must not count as one. `confirm` is the only second word,
        -- and anything else has to land back on the first step.
        if not DebindPrivate.HandleNewerProfileReset({ "reset", "yes" }) then
            return Fail(NAME, "두 번째 낱말이 다르니 명령 자체가 안 받아졌다")
        end
        if _G.DebindVars ~= before then
            return Fail(NAME, "confirm이 아닌 낱말에도 지워졌다")
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
