local _, Dev = ...

-- DebindTest, the in-game test kit: this harness, the cases under `Tests/`, and the runner.
-- Usage: /debtest opens the list. Every run is a button in it -- plain, the one that includes the
-- tests which end the session, and the one that reloads first and runs on the other side.
-- Requires DEBUG mode (DebindPrivate must be exposed as global)
--
-- **What is in the kit is what needs the game.** Twenty-nine cases came down to the headless specs
-- when the harness learned to read UpdateBindings.lua and to run the restricted environment
-- (going-headless-outside-the-ui.md): the binding types, the twelve condition families,
-- priority ordering, the three Split: cases, the four Issue: ones and the four macro text ones.
-- Every one of them asked a question about a value, and a question about a value is answered
-- more cheaply -- and on every commit -- by npm test.
--
-- **`Events.lua` runs headless now** (2026-08-23). Everything but `ADDON_LOADED` and `PLAYER_LOGIN`
-- is registered **inside** `Events.PLAYER_LOGIN`, so an addon that was loaded and never logged in
-- hears nothing -- which is the shape every spec ran in, and the reason no event handler had ever
-- been exercised outside the game. `wow_frames.fireEvent` delivers one now. The macro-store case
-- kept only its client half in the kit: sending `UPDATE_MACROS` is the one part no harness can do.
--
-- **Two more came down on the re-read that followed** (2026-08-23). Both were kept by a line
-- naming `GetBindingAction`, which had stopped being a reason a few hours earlier: whether a
-- fixed-wired key is ever handed back, and the state loop's own sweep over four axes. The press
-- sweep **stays** -- it is §9's anchor and is meant to be in both places.
--
-- **Nine more came down that were never blocked by anything** (2026-08-23). Every one asked what
-- `BuildKeyMap` hands out for a key, which the harness has been able to answer since 2026-08-21;
-- what kept them in the kit was a line above each saying otherwise. `tests/keymap_spec.lua` and two
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
-- between the layers and a great many cases in the kit were on the wrong side of it; the restricted
-- `SetBindingClick` and `GetBindingAction` share one table now (`tests/wow_frames.lua`), and
-- `tests/boundkey_spec.lua` is what asks it. **A justification naming what the harness cannot load
-- has to be re-read against `tests/run.lua` before it is believed** -- that list has grown twice.
--
-- What stayed asks something only a client can answer: a snippet the sandbox really compiled, a
-- frame under a real cursor, Blizzard's own registries, a dialog the client builds, a real macro
-- store, a reload. **Each of those carries a line above it saying which of these it is and why**,
-- so the next reader does not have to work out again why that one is still in the game.

-- **Debind's tables are handed over at `ADDON_LOADED`, not read at load.** This addon loads ahead
-- of Debind (`DebindDev.toc` says why), so while the kit's files run there is no `DebindPrivate`
-- to read. Each file registers a handler that sets its own upvalues, and `TestRunner.lua` calls
-- them all at that moment. Anything a file would build at load time out of `Constants` is built
-- in its handler instead (`BuildConstantTables`).
--
-- Some tests find a menu entry by its wording, which is what `private.L` is taken for. Found by
-- position instead, they quietly press something else the day one more entry appears.
local debindLoadedHandlers = {}

function Dev.OnDebindLoaded(handler)
    tinsert(debindLoadedHandlers, handler)
end

function Dev.DebindLoaded(private)
    for _, handler in ipairs(debindLoadedHandlers) do
        handler(private)
    end
end

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

-----------------------------------------------------------
-- Test Framework
-----------------------------------------------------------

local tests = {}

local testOrder = {}

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
--   * `UpdateBindings` runs its own snippets through `SecureHandlerExecute` on the way out, so a
--     rebuild leaves nothing behind to finish. That is why `SetMockState` needs no wait after it:
--     it ends in a rebuild.
--
-- Two things do take time, and each has a helper that stops the moment it happens rather than
-- spending a fixed sum:
--
--   * a **queued** rebuild -- `QueueUpdateBindings` defers to `C_Timer.After(0)`, so that one
--     lands a frame later. `WaitForIdle`.
--   * an event the client has to deliver, such as a state driver attribute resolving after a
--     vehicle takes the bar. `WaitUntil`.
--
-- **There is no fixed-duration wait left in the kit, and adding one back needs an argument.**
-- The runner still understands a duration -- `coroutine.yield(seconds)` -- so the door is there;
-- what is gone is the helper that made walking through it look routine. A number here means
-- "I could not name what I am waiting for", and every one that was here turned out to be waiting
-- for something that had already happened. `reading-back-what-you-just-set.md` has the
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

    -- **The pick is the runner's to clear, for the reason above.** It outlives the actions it holds:
    -- a heading's right-click folds the pick onto its group and leaves it standing on purpose, so
    -- that an unbind from there can be put back, and nothing prunes it while the window is shut.
    -- Every test after one of those then started with somebody else's two rows in the set.
    --
    -- **After the teardowns**, so a test that closes the window does it first.
    local ok, err = pcall(DebindLayerPanel.SetSelectedAction, DebindLayerPanel, nil)
    if not ok then
        print(format("|cffff8800[DebindTest]|r clearing the pick failed: %s", tostring(err)))
    end
end

--- ESCAPE as the main window actually meets it, in the four steps the client takes.
---
--- **A real key press is not available here.** A run unbinds the game's own bindings, so pressing
--- ESCAPE would measure the runner as much as the window. Calling `CloseSpecialWindows` is not it
--- either -- it would carry off every registered frame in the client, Blizzard's included.
---
--- So the sweep is spelled out for our own frames only, and that is what makes this worth more
--- than calling `HandleEscape`: the plain `Hide` calls carry no stamp, which is exactly the shape
--- `CloseSpecialWindows` leaves behind, and each frame's `OnHide` has to recognise it as somebody
--- else's close and put itself back (`DebindDialogMixin:OnDialogHide`,
--- `DebindFrameMixin:OnHide`). The dialogs go first because `pairs` over `UISpecialFrames` gives
--- no order and this is the half where the window is still up when a dialog is swept.
---
--- `GetTime()` holds still for the whole frame, so the stamp `OnKeyDown` leaves is still current
--- by the time the window's `OnHide` reads it.
---
--- **That same frame is why a test standing the window up has to yield first.** `CloseWindow`
--- stamps `closeAt = GetTime()` and `DebindFrameMixin:OnHide` reads "deliberate" off it, so a
--- teardown that closed the window leaves that stamp current for everything the runner steps
--- through next -- and it steps through as many as it can without giving up the frame
--- (`while run and Step() do end`). The next test's `Hide` is then read as its own close: the
--- window stays down and the ladder never walks. Nobody can reach that order by hand, since it
--- means reopening the window in the same frame it was closed in.
---
--- So a test that shows the window and expects a `Hide` to come back opens with
--- `coroutine.yield(0)`. One frame, once, at the top.
local function PressEscape()
    DebindFrame:OnKeyDown("ESCAPE")
    DebindAddFrame:Hide()
    DebindPasteFrame:Hide()
    DebindCopyFrame:Hide()
    DebindMessageFrame:Hide()
    DebindFrame:Hide()
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
local offSpecLayer

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

--- A second test layer, standing for **another specialization's**.
---
--- What makes a layer another specialization's is the `specRank` the all-layers walk hands out
--- beside it, so the value rides on the layer here and the stand-in below reads it off
--- (`Profile.lua`'s `EnumerateAllProfileLayers` computes the real one). The live walk never yields
--- this layer at all, which is the other half of what "not this specialization" means.
---
--- **Off by default.** Every test that counts rows on a key counts what the walks yield, so a
--- second layer standing in every run would change those counts from under tests that never asked
--- for one. `UseOffSpecLayer` turns it on for the test that wants it and the teardown takes it out.
local function GetOffSpecLayer()
    if not offSpecLayer then
        local real = assert(DebindPrivate.GetProfileLayer(1), "the profile is not up yet")
        offSpecLayer = setmetatable({
            layerID = 101,
            actions = {},
            -- Any non-zero index will do: what the comparator reads is whether it ties with the
            -- rows around it, not which specialization it names.
            testSpecRank = 2,
        }, getmetatable(real))
    end
    return offSpecLayer
end

--- The narrowest layer in force here, on the character side or the class side.
---
--- **Not `GetLayerID(GetSpecialization(), ...)`.** A character still in the initial
--- specialization is handed `Constants.INITIAL_SPEC_INDEX`, which has no layer and trips
--- `GetLayerID`'s range assert; a class of one specialization has a layer for it that nothing
--- opens (`GetOpenableLayerIDs`). Either way the shared layer is the narrowest one.
local function NarrowestLayerHere(isCharacterSpecific)
    local spec = C_SpecializationInfo.GetSpecialization() or 0
    if spec > DebindPrivate.SpecLayerCount(select(3, UnitClass("player"))) then
        spec = 0
    end
    return DebindPrivate.GetLayerID(spec, isCharacterSpecific)
end


-----------------------------------------------------------
-- Test Helpers: The game's own bindings
-----------------------------------------------------------

-- **Nothing here writes to the game's binding table, and nothing may.**
--
-- The kit used to unbind every key the tester had at the start of a run and put them back at the
-- end with `LoadBindings`. That destroyed a tester's keybindings on 2026-09-08: the settings panel
-- tests open `SettingsPanel`, and `SettingsPanelMixin:OnHide` calls `SaveBindings` unconditionally
-- (`Blizzard_SettingsPanel.lua`), so closing it wrote the emptied set to disk and the restore
-- afterwards faithfully read that emptied set back. The comment justifying the blackout said
-- "nothing is written to disk until someone calls `SaveBindings`, and this addon never does" --
-- true of us and never true of the client.
--
-- **The reason it was there does not survive reading either.** It said a test key could fire the
-- tester's own spell. Addon code cannot press a key or click a secure action button at all, and no
-- test tries: what the kit does is run `EVAL_SNIPPET` and read the winner. The only place the
-- tester's table can be seen is `GetBindingAction(KEY, true)`, and while our override stands it is
-- our override that answers -- so a stray binding of theirs can make an assertion fail where it
-- should have passed, and can never make one pass where it should have failed.
--
-- So the collision is reported and nothing is touched. A run on a board that binds one of these is
-- a run that says so.

--- The keys the kit binds, as shapes. A modifier plus a function key covers most of them, and
--- `BUTTON1`/`BUTTON3` are the mouse buttons the click-cast tests use.
---
--- **This is a list, and it goes stale.** An earlier version of this comment claimed the shape was
--- derived so a test reaching for a new key would be covered for free; it was not true the day it
--- was written, since `BUTTON3` was already in use. What being wrong costs is one missing line of
--- warning, so it stays cheap rather than exact.
local function LooksLikeATestKey(key)
    if (type(key) ~= "string") then
        return false;
    end
    if (strfind(key, "BUTTON%d+$")) then
        return true;
    end
    return strfind(key, "F%d+$") ~= nil
        and (strfind(key, "^CTRL%-") or strfind(key, "^ALT%-")) ~= nil;
end

--- Says which of the tester's own keys could be read by a test, once per run.
---
--- **Read only.** `GetBindingKey` and `GetBinding` answer from the table; nothing here writes.
local function ReportOverlappingBindings()
    local clashes = {}
    for i = 1, GetNumBindings() do
        local command = GetBinding(i)
        if command then
            for j = 1, select("#", GetBindingKey(command)) do
                local key = select(j, GetBindingKey(command))
                if LooksLikeATestKey(key) then
                    clashes[#clashes + 1] = format("%s (%s)", key, command)
                end
            end
        end
    end

    if #clashes > 0 then
        print(format("|cffff8800[DebindTest]|r %d of your own binding(s) sit on keys this kit reads: %s. Nothing was changed; an assertion that expects one of these to be unbound will fail.",
            #clashes, table.concat(clashes, ", ")))
    end
    return #clashes
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
--- What the reader had the Hover Cast mode set to before the run.
---
--- **It is isolated for the same reason the layers are.** A case that writes its own `casting` and
--- expects the frame's unit gets `mouseover` instead on a profile set to Mouseover, and the case
--- never mentioned a mode.
local realPointedUnitCast

--- The list the three stand-ins walk. Held here so a test can add the off-spec layer to it while
--- the run is already isolated (`UseOffSpecLayer`).
local isolatedLayers

--- The option's own reader while a run is isolated, and the one value it answers from
--- (`HoldUnmatchedKeys`).
local realGiveBackWhenNoActionRuns
local holdUnmatchedKeys = false
--- The same for the state driver period, which answers the default unless a case chose one
--- (`PeriodKit.Swap`). **A table rather than locals**: `chosen` is written from `Tests/Beat.lua`,
--- which also hangs `Swap` and `TicksPerFrame` on it, and an upvalue cannot be written from another
--- file.
local PeriodKit = {}

local function SetIsolated(isolated)
    if isolated then
        -- **Wrapped, because this is a report and the run is not.** It only reads, but a run that
        -- could not start because a report raised would be the tail wagging the dog.
        pcall(ReportOverlappingBindings)

        if not realEnumerate then
            realEnumerate = DebindPrivate.EnumerateProfileLayers
            realEnumerateAll = DebindPrivate.EnumerateAllProfileLayers
            realPointedUnitCast = {
                hoverCastMode = DebindPrivate.Options.hoverCastMode,
            }
            DebindPrivate.Options.hoverCastMode = nil
            -- **On, whatever the tester runs with and whatever the shipped default is**, and swapped
            -- like the layer walk rather than written: `Options` is the saved table, and a run that
            -- crosses a reload would save a value written here over the tester's own. A key whose
            -- actions all fail is given back or held by this option, and a case that reaches such a
            -- key expects it given back unless it asks for held (`HoldUnmatchedKeys`). A run that
            -- followed the tester or the default would turn the rest of those cases red.
            realGiveBackWhenNoActionRuns = DebindPrivate.GiveBackWhenNoActionRuns
            DebindPrivate.GiveBackWhenNoActionRuns = function()
                return not holdUnmatchedKeys
            end
            -- A tester's own 0 would hold the session at 0 from the first case with a beat.
            PeriodKit.real = DebindPrivate.StateDriverPeriod.Chosen
            DebindPrivate.StateDriverPeriod.Chosen = function()
                return PeriodKit.chosen or Constants.STATE_DRIVER_UPDATETIME_DEFAULT
            end
            isolatedLayers = { GetTestLayer() }
            local only = isolatedLayers
            -- **The live walk yields the first layer alone**, whatever else is in the list. That is
            -- what an off-spec layer is: stored, and not among what this specialization runs.
            DebindPrivate.EnumerateProfileLayers = function()
                return function(tbl, index)
                    index = index + 1
                    if index == 1 and tbl[index] then
                        return index, tbl[index]
                    end
                end, only, 0
            end
            -- Scope 5 for both, so the layer step can never decide a pair; the specialization comes
            -- off the layer. 5 is what the layer they were cloned from would answer (`GetTestLayer`
            -- takes the general layer's metatable). What matters is that they are answered at all:
            -- a nil scope would reach the comparator.
            DebindPrivate.EnumerateAllProfileLayers = function()
                return function(tbl, index)
                    index = index + 1
                    if tbl[index] then
                        return index, tbl[index], 5, tbl[index].testSpecRank or 0
                    end
                end, only, 0
            end

            realFindLayerID = DebindPrivate.FindLayerID
            DebindPrivate.FindLayerID = function(action)
                if action == nil then
                    return nil
                end
                for _, layer in ipairs(only) do
                    for _, candidate in layer:Enumerate() do
                        if candidate == action then
                            return layer.layerID, layer
                        end
                    end
                end
                -- Not the test layer's. Falls through to the real walk so a test that reaches for
                -- something the tester actually owns is answered rather than quietly told "nowhere".
                return realFindLayerID(action)
            end
        end
    else
        if realEnumerate then
            DebindPrivate.EnumerateProfileLayers = realEnumerate
            DebindPrivate.EnumerateAllProfileLayers = realEnumerateAll
            DebindPrivate.FindLayerID = realFindLayerID
            DebindPrivate.Options.hoverCastMode = realPointedUnitCast.hoverCastMode
            DebindPrivate.GiveBackWhenNoActionRuns = realGiveBackWhenNoActionRuns
            realGiveBackWhenNoActionRuns = nil
            holdUnmatchedKeys = false
            DebindPrivate.StateDriverPeriod.Chosen = PeriodKit.real
            PeriodKit.real = nil
            PeriodKit.chosen = nil
            realEnumerate = nil
            realEnumerateAll = nil
            realFindLayerID = nil
            realPointedUnitCast = nil
            isolatedLayers = nil
        end
    end

    if not InCombatLockdown() then
        DebindPrivate.UpdateBindings()
    end
end

--- Moves the conditions into `action.conditions`.
---
--- Tests write conditions flat: `InsertAction({ ..., combat = true })`. The stored shape is
--- nested, so planting one flat leaves the condition
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

--- **A test action stores no Hover Cast value, which means the usual target**, and with Normal Cast
--- on that stands as one record and no pointed twin (`deciding-what-a-press-runs.md` §7). What the cases
--- need from it is one record per action: with a twin standing in front, every case that counts
--- records on a key would see each of its own actions twice. A case about the pointed press asks for
--- the unit it points at itself.
---
--- **The function stays where the writing used to be.** Every insertion goes through it, so the day
--- a test action needs a value again there is one place to put it.
local function DefaultCasting(action)
    return action
end

local function InsertAction(action)
    local layer = GetTestLayer()
    layer:Insert(NestConditions(DefaultCasting(action)))
    -- The layer is what hands out the order number. Without one, actions sharing a condition all
    -- carry a nil `seq`, nothing settles which fires first, and a test expecting insertion order
    -- moves with whatever the sort happens to do.
    layer:PlaceInKeyGroup(action)
    return action
end

--- Puts the off-spec layer into the run, and hands back a second `InsertAction` that plants into
--- it. Call it from a test's `run`; the teardown takes the layer back out.
---
--- The two layers tie on every ordering step above `specRank`, so a key holding rows from both is
--- exactly the case the overview draws for another specialization: the rows stand together in one
--- list and the comparator splits them on which specialization they belong to.
local function UseOffSpecLayer()
    local layer = GetOffSpecLayer()
    isolatedLayers[#isolatedLayers + 1] = layer
    AddTeardown(function()
        wipe(layer.actions)
        for i = #isolatedLayers, 2, -1 do
            isolatedLayers[i] = nil
        end
    end)
    return function(action)
        layer:Insert(NestConditions(DefaultCasting(action)))
        layer:PlaceInKeyGroup(action)
        return action
    end
end

--- Empties the layers wholesale. Nothing else is in them, so there is nothing to be careful about.
local function CleanupActions()
    wipe(GetTestLayer().actions)
    wipe(GetOffSpecLayer().actions)
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

--- `giveBackWhenNoActionRuns` off for one case: one that asks the press on a key none of whose actions
--- runs rather than who has it, or one about a key with the option off
--- (`giving-keys-back-when-no-action-runs.md`). **Nothing saved is written**: the isolated reader
--- answers from this flag (`SetIsolated`), and the teardown puts it back for the cases after.
local function HoldUnmatchedKeys()
    holdUnmatchedKeys = true
    AddTeardown(function()
        holdUnmatchedKeys = false
    end)
end

--- Whether a `GetBindingAction(key, true)` answer is a click on our button.
---
--- **Not any `"CLICK "`.** A key given back answers whatever else is bound to it, and a tester's
--- other addons bind keys to buttons of their own the same way, so a prefix check reads their key
--- as ours.
local function IsOurClick(bound)
    local ours = "CLICK " .. DebindPrivate.DefaultClickFrame:GetName() .. ":"
    return bound ~= nil and bound:sub(1, #ours) == ours
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

--- Every action puts a self twin and a focus twin on its key, in the key's first two tiers
--- (`implementing-focus-and-self-cast.md` §3-4). A press with no modifier held never
--- reaches them, so the tests that ask about that press count and place bindings without them.
local function IsModifierTwin(binding)
    return binding.castModifier == Constants.CASTMOD_SELF or binding.castModifier == Constants.CASTMOD_FOCUS
end

local function GetKeyBindingsWithoutTwins(key)
    local bindings = GetKeyBindings(key)
    if not bindings then
        return nil
    end
    local out = {}
    for i = 1, #bindings do
        if not IsModifierTwin(bindings[i]) then
            out[#out + 1] = bindings[i]
        end
    end
    return out
end

--- Where the binding at `index` on the key stands without the twins. nil for a twin, so a test
--- expecting a place fails on one.
local function PlaceWithoutTwins(key, index)
    local bindings = GetKeyBindings(key)
    if not index or not bindings or not bindings[index] or IsModifierTwin(bindings[index]) then
        return nil
    end
    local place = 0
    for i = 1, index do
        if not IsModifierTwin(bindings[i]) then
            place = place + 1
        end
    end
    return place
end

--- The order `BuildKeyMap` ended up with, as a string of spell ids. Records the solver dropped
--- are not in it, which is the point of asking here rather than asking the drawing side.
---
--- **Without the self and focus twins**, whose tiers keep the order of the originals.
local function KeyMapOrder(key)
    local bindings = GetKeyBindingsWithoutTwins(key)
    if not bindings then
        return "<none>"
    end
    local out = {}
    for i = 1, #bindings do
        out[#out + 1] = tostring(bindings[i].value)
    end
    return table.concat(out, " ")
end

--- Which `KeyMap` binding an emitted record index stands for, or `"block"` for one the emission put
--- in (`WithBlocks`).
---
--- **Read off what the emission says it sent** (`EmittedRecords`), not worked out here. The emitted
--- list is not `KeyMap`'s: blocks go in where the cast keys are on, and a binding the builder drops
--- makes no record. A copy of that layout kept here missed both.
local function BindingIndexForEmitted(key, index)
    local emitted = key and type(index) == "number" and DebindPrivate.EmittedRecords[key]
    local binding = emitted and emitted[index]
    if not binding then
        return index
    end
    local bindings = GetKeyBindings(key) or {}
    for i = 1, #bindings do
        if bindings[i] == binding then
            return i
        end
    end
    return "block"
end

--- The same, and `"block"` too where the `KeyMap` binding is one: a `GIVEBACK` or `COMMAND` binds
--- as a BLOCK (`FillBinding`), and winning a press with it fires nothing either.
local function BindingIndexForRecord(key, index)
    local mapped = BindingIndexForEmitted(key, index)
    local bindings = type(mapped) == "number" and GetKeyBindings(key)
    if bindings and bindings[mapped] and bindings[mapped].type == Constants.BLOCK then
        return "block"
    end
    return mapped
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
-- **The press is where the override sits**, because the press is where a state is measured
-- (`PROBE.MockState` in `EVAL_SNIPPET`). It lands after the real call and before the value is
-- compared, so the measurement runs exactly as it always does and only the answer differs.
--
-- Debind carries none of this. The probe expands to nothing for anyone without this addon, and
-- the body is then the one a real user runs.
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
        if (not MockParseWords) then MockParseWords = newtable() end
        if (not MockUnitWords) then MockUnitWords = newtable() end
        if (not MockModifiedClicks) then MockModifiedClicks = newtable() end
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

--- Tokens that always hold and never hold, for a mocked word written into an expression before it
--- is parsed. `bar:99` is the cheapest always-false token measured (`trimming-the-tail-key-beat.md`
--- 7-1, M) and no action bar page is 99.
local MOCK_TRUE, MOCK_FALSE = "nobar:99", "bar:99"

--- What one token of a state expression answers with `state` held at `value`, or nil where the
--- token is not about that state. The forms are `StateAlternatives`' in `ConditionText.lua`.
local function TokenAnswer(state, value, token)
    local negated = token:sub(1, 2) == "no"
    local word, arg = (negated and token:sub(3) or token):match("^(%a+):?(.*)$")
    local function listed()
        for n in arg:gmatch("[^/]+") do
            if tonumber(n) == value then return true end
        end
        return false
    end
    local answer
    if state == "skyriding" then
        if word == "bonusbar" and arg == tostring(Constants.BONUSBAR_SKYRIDING) then answer = value end
    elseif state == "form" then
        if word == "form" then answer = listed() end
    elseif state == "bonusbar" then
        if word == "bonusbar" then answer = listed() end
    elseif state == "group" then
        if word == "group" then
            if arg == "raid" then
                answer = value == Constants.GROUP_RAID
            else
                answer = value ~= Constants.GROUP_NONE
            end
        end
    elseif word == state and arg == "" then
        answer = value
    end
    if answer == nil then return nil end
    return (answer and not negated) or (not answer and negated)
end

--- The body that holds `state` at `value` (nil releases it), for the press's measured axes and for
--- a parsed expression alike.
---
--- **A parse cannot be reached by `PROBE.MockState`**, which overrides a local between the
--- measurement and the comparison; a parsed word has no local. So every token the rebuild has
--- written that is about `state` is put in `MockParseWords` as an always-true or always-false token,
--- and `PROBE.SecureCmdOptionParse` hands that table to `rtgsub` as the replacement -- a token not in
--- it stays as written. The tokens are the rebuild's own (`StateExpressionTokens`), since `form:0/1`
--- and the like can only be answered by reading what they list.
local function MockBody(state, value)
    local parts = { format([[MockStatesMap[%q] = %s]], state, value == nil and "nil" or ToLiteral(value)) }
    -- **A unit's life is parsed** (`PROBE.ParseUnit`), where the word is the same for every unit
    -- and only the `@` beside it says whose. So it is held per unit, in the table the dev form picks
    -- by the `unit` local beside the parse, the press's and the loop's classifying parse alike.
    local deadUnit = state:match("^(.+)%-dead$")
    if deadUnit then
        if value == nil then
            parts[#parts + 1] = format([[MockUnitWords[%q] = nil]], deadUnit)
        else
            parts[#parts + 1] = format([[MockUnitWords[%q] = newtable()]], deadUnit)
            parts[#parts + 1] = format([[MockUnitWords[%q].dead = %q]], deadUnit, value and MOCK_TRUE or MOCK_FALSE)
            parts[#parts + 1] = format([[MockUnitWords[%q].nodead = %q]], deadUnit, value and MOCK_FALSE or MOCK_TRUE)
        end
        return table.concat(parts, " ")
    end
    local tokens = {}
    for token in pairs(DebindPrivate.StateExpressionTokens()) do tokens[#tokens + 1] = token end
    -- The bare word too, for a `PROBE.SecureCmdOptionParse` written by hand (`[combat]`).
    tokens[#tokens + 1], tokens[#tokens + 2] = state, "no" .. state
    for _, token in ipairs(tokens) do
        local answer = value ~= nil and TokenAnswer(state, value, token)
        if value == nil then
            if TokenAnswer(state, 0, token) ~= nil or TokenAnswer(state, true, token) ~= nil then
                parts[#parts + 1] = format([[MockParseWords[%q] = nil]], token)
            end
        elseif answer ~= nil then
            parts[#parts + 1] = format([[MockParseWords[%q] = %q]], token, answer and MOCK_TRUE or MOCK_FALSE)
        end
    end
    return table.concat(parts, " ")
end

--- Forces `state` to `value` at the press. `nil` releases it.
---
--- **`EnableProbes()` has to have been called**, because the line that reads this table is
--- `PROBE.MockState` and that is in the body only while probes are on. Without it the press
--- measures the real state and the mock is not wrong so much as absent.
---
--- It ends in a rebuild, which is what every caller that re-reads a binding array afterwards
--- leans on.
local function SetMockState(state, value)
    PlantMockTable()

    mockStates[state] = value

    SecureHandlerExecute(DebindPrivate.BindingDriver, MockBody(state, value))

    -- Releasing is registered the moment something is held, so a test that fails in the middle
    -- does not leave the game believing it is in combat.
    AddTeardown(function()
        mockStates[state] = nil
        SecureHandlerExecute(DebindPrivate.BindingDriver, MockBody(state, nil))

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

--- Has every press answer `IsModifiedClick(name)` true, as with that cast key held. Needs
--- `EnableProbes()` for the reason `SetMockState` does; let go by the teardown it registers.
local function SetMockModifiedClick(name)
    PlantMockTable()
    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[MockModifiedClicks[%q] = true]], name))
    AddTeardown(function()
        SecureHandlerExecute(DebindPrivate.BindingDriver, format([[MockModifiedClicks[%q] = nil]], name))
    end)
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
--- The key the last evaluation ran for, so a reported record index can be read as a `KeyMap` one.
local lastEvalKey
--- The unit the last evaluation settled on, as the snippet reported it.
local lastEvalUnit

--- What `PROBE.Winner(i)` becomes while probing. `debind_driver` rather than `self`, because the
--- wrapper runs with the click frame as `self` and the method lives on the driver.
--- What `PROBE.MockState(x)` becomes while probing. The argument is the local **and** the state name, which
--- is why they are spelled the same in `EVAL_SNIPPET`. `MockUnitGroup` takes the unit instead, and
--- reads the `<unit>-group` name `SetMockState` is given.
---
--- `~= nil` and an `if`, not `and`/`or`: most of these axes are booleans, and a false held value
--- would fall straight through an `and`/`or` to the measured one.
local PROBE_DEV = {
    Winner = [[debind_driver:CallMethod("DebindTestWinner", %s)]],
    Unit = [[debind_driver:CallMethod("DebindTestUnit", %s)]],
    MockState = [[if (MockStatesMap["%1$s"] ~= nil) then %1$s = MockStatesMap["%1$s"] end]],
    MockUnitGroup = [[if (MockStatesMap[%1$s .. "-group"] ~= nil) then group = MockStatesMap[%1$s .. "-group"] end]],
    -- Each word of the expression is looked up in `MockParseWords` and replaced when it is there
    -- (`MockBody`). One expression, so it stands wherever the call did; the count is dropped.
    -- **`rtgsub`, not `gsub`**: the restricted environment's `gsub` is the plain one and refuses a
    -- restricted table as the replacement (`RestrictedInfrastructure.lua`, `RestrictedTable_rtgsub`).
    SecureCmdOptionParse = [[SecureCmdOptionParse((rtgsub(%s, "%%a[%%w:/]*", MockParseWords)))]],
    -- The same, with the words held for the `unit` local beside it (`MockBody`, `<unit>-dead`).
    ParseUnit = [[SecureCmdOptionParse((rtgsub(%s, "%%a[%%w:/]*", MockUnitWords[unit] or MockParseWords)))]],
    -- A beat the watch let pass, its columns measured again (`JudgeWatchCheck`). `self` is the
    -- driver: this stands in the beat's own handler.
    WatchCheck = [[self:RunAttribute("JudgeWatchCheck")]],
    -- A cast key held at the press (`SetMockModifiedClick`). Only ever answers true over the real
    -- one: what a test has to stand up is a key held, which it cannot do with its hands.
    IsModifiedClick = [[(MockModifiedClicks[%1$s] or IsModifiedClick(%1$s))]],
}

--- The columns the watch's check found moved on a beat the watch let pass (`DebindTestWatchMiss`).
local watchMisses = {}

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
        probeReports[#probeReports + 1] = BindingIndexForRecord(lastEvalKey, index)
    end

    --- 그 누름이 겨눈 대상. **어디에 얹히는지는 경로마다 달라서** 프레임에서 읽으면 안 된다 -
    --- 감싼 버튼은 캐스트 프레임에, 나머지는 눌린 프레임의 맨이름 `unit`에 선다.
    DebindPrivate.BindingDriver.DebindTestUnit = function(_, unit)
        lastEvalUnit = unit
    end

    DebindPrivate.BindingDriver.DebindTestWatchMiss = function(_, column)
        watchMisses[#watchMisses + 1] = column
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
        wipe(watchMisses)
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
--- The same decision under the button name a binding carries, for a press that arrives on one of
--- a key's self or focus chords (`@<key>#<tier>`). `key` is the key whose records the result
--- indexes into.
local function EvalClickTimeButton(key, button)
    wipe(probeReports)
    lastEvalKey = key
    lastEvalUnit = nil
    SecureHandlerExecute(DebindPrivate.BindingDriver, format(
        [[self:RunAttribute("EvalClickTimeKey", %q)]], button))
    return true
end

local function EvalClickTimeKey(key)
    local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[key]
    if not button then
        return false, format("%s is not a click-time key (not in ClickTimeKeys)", key)
    end
    return EvalClickTimeButton(key, button)
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
    -- The key comes back off the button and the modifier, which is all a frame click carries.
    lastEvalKey = nil
    for key in pairs(DebindPrivate.KeyMap) do
        local button, prefix = DebindPrivate.GetMouseButtonAndPrefix(key)
        if button == n and DebindPrivate.GetModifierIndex(prefix) == mod then
            lastEvalKey = key
        end
    end
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

local function LastEvalUnit()
    return lastEvalUnit
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

--- The `KeyMap` index the snippet last reported as the winner, or nil if it reported none or a
--- block won. A block winning is the press doing nothing, which is what nil already means to every
--- caller.
local function LastWinner()
    local got = probeReports[#probeReports]
    if got == "block" then
        return nil
    end
    return got
end

--- Waits for the winner report to arrive and answers with it.
---
--- In practice it is already there: the snippet reports through `CallMethod`, which is called
--- rather than queued, so the report lands inside the `SecureHandlerExecute` that ran the
--- evaluation. The wait is what covers the other case -- **no report at all**, which is how
--- "nothing matched" looks from here and is indistinguishable from a slow one. Only that case
--- costs the limit, and a sweep is mostly hits.
local function WaitForWinner(limit)
    WaitUntil(function() return probeReports[#probeReports] end, limit)
    return LastWinner()
end

--- Which of the two tables a key's record list ended up in.
---
--- **The split is the one thing nothing else here can see.** The click tests cover what a press
--- decides, and they pass whichever table the key landed in.
---
--- Asked of the restricted environment rather than of the source that built it. Reading the
--- generated snippet back would only confirm that the generator wrote what the generator meant to
--- write.
---
--- Read the answer with `WaitForMembership`.
local lastMembership
local function ReadKeyMembership(key)
    local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[key]
    local mouseButton, mousePrefix = DebindPrivate.GetMouseButtonAndPrefix(key)
    lastMembership = nil
    DebindPrivate.BindingDriver.DebindTestMembership = function(_, clickTime, clickCast)
        lastMembership = { clickTime = clickTime, clickCast = clickCast }
    end

    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[
        self:CallMethod("DebindTestMembership", %s, %s)
    ]],
        button and format([[ClickTimeKeys[%q] ~= nil]], button) or "false",
        mouseButton and format([[ClickCastKeys[%d] ~= nil and ClickCastKeys[%d][%d] ~= nil]],
            mouseButton, mouseButton, DebindPrivate.GetModifierIndex(mousePrefix)) or "false"))
    return true
end

--- `{ clickTime = bool, clickCast = bool }` from the last `ReadKeyMembership`,
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

--- What the restricted environment holds for a switch: `{ present = bool, value = bool }`.
---
--- **`present` is the half that cannot be got any other way.** `States` carries a switch only
--- once a rebuild has registered it, and a switch that was never registered is indistinguishable
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
local function ReadSecureState(name)
    local answer
    DebindPrivate.BindingDriver.DebindTestSecureState = function(_, present, value)
        answer = { present = present, value = value }
    end

    SecureHandlerExecute(DebindPrivate.BindingDriver, format([[
        self:CallMethod("DebindTestSecureState", States[%1$q] ~= nil, States[%1$q] == true)
    ]], name))

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
-- what makes the hover slot reachable at all: the frame is where `unit` is read from, when the
-- cursor arrives and again at every press, so a frame we can write to is a hover state we can
-- set. Nothing is faked -- the attribute read, the registration, and the reaction lookup are the
-- shipped ones.
--
-- **Frames are never destroyed in WoW**, so they are reused by name across runs. Teardown stands
-- the addon down off the frame rather than disposing of it (`StandDownTestFrame`).
local UNIT_TOKEN_ABSENT = "debindtest_absent"

local testFrameCount = 0

--- The frames a stand-down is being staged for, and the header that is standing on them.
---
--- **One hook for all of them.** `hooksecurefunc` cannot be taken off, so booking one per call
--- would pile a hook on the global for every frame the kit ever tears down.
local standDownTargets = setmetatable({}, { __mode = "k" })
local standDownHooked = false

local standDownHeader

--- Makes a frame lose its row, which is the whole of what a teardown has to undo.
---
--- **A fight is the only way left.** Nothing in the addon takes a row back any more
--- (`taking-every-unit-frame-with-one-blacklist.md` §1-5), and `StandDown` is what
--- is left: wrapping over us **inside our own wrap** is the definition of one, so that is what this
--- stages. Writing `ccframes[frame] = nil` here instead would leave the restricted side holding a
--- row for a frame the insecure side has forgotten.
---
--- **Leaving the row instead is not an option**, because frames are reused by name across runs: the
--- next run's registration of the same frame would stop at the row this run left and measure the
--- kind that run asked for.
local function StandDownTestFrame(frame)
    if InCombatLockdown() then
        return
    end

    if not standDownHooked then
        standDownHooked = true
        hooksecurefunc("SecureHandlerWrapScript", function(wrapped, script, header)
            local theirs = standDownTargets[wrapped]
            if theirs and script == "OnEnter" and header == DebindPrivate.BindingDriver then
                standDownTargets[wrapped] = nil
                SecureHandlerWrapScript(wrapped, "OnEnter", theirs, "-- theirs, on top again")
            end
        end)
    end

    standDownHeader = standDownHeader or _G.DebindTestStandDownHeader
        or CreateFrame("Frame", "DebindTestStandDownHeader", UIParent, "SecureHandlerBaseTemplate")

    standDownTargets[frame] = standDownHeader
    SecureHandlerWrapScript(frame, "OnEnter", standDownHeader, "-- theirs")
    standDownTargets[frame] = nil
end

--- The frame on its own, with nothing of ours on it. **What the addon does to a frame is what
--- several cases are measuring**, so they need one it has never seen; the rest go through
--- `CreateTestUnitFrame`, which is this plus the registration.
local function MakeTestUnitFrame(unit)
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

    AddTeardown(function()
        StandDownTestFrame(frame)
        frame:Hide()
    end)

    return frame, name
end

--- A frame under a name no earlier run used, for the cases whose name has to match a pattern.
--- **A fixed name only holds for the first run of a session**: the registration that run measured
--- stays on the frame, so the next run is handed one we already know about.
local function FreshNamedFrame(prefix)
    testFrameCount = testFrameCount + 1
    local name = prefix .. testFrameCount
    return CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate"), name
end

local function CreateTestUnitFrame(unit, frameType)
    local frame, name = MakeTestUnitFrame(unit)

    DebindPrivate.RegisterFrame(frame, frameType or "group")

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
--- changed": neither enter nor leave fires while the cursor sits still, and what a press reads is
--- this attribute.
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
    local answer = ReadSecureUnit("unitframe")
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
--- `SecureHandlerExecute` and the mirror is written before the call returns. **Nothing else moves
--- the slot any more**: a unit changing under a still cursor is read off the frame at the call
--- (`GetUnitFrameUnit`), and nothing runs between presses to touch the slot.
local function WaitForHoverSlot(filled, limit)
    return WaitUntil(function() return (GetHoverUnit() ~= nil) == filled end, limit)
end

local fakeHeader

local function FakeHeader()
    if not fakeHeader then
        fakeHeader = _G.DebindTestFakeHeader
            or CreateFrame("Frame", "DebindTestFakeHeader", UIParent, "SecureHandlerBaseTemplate")
        function fakeHeader:ReportHovered(value)
            fakeHeader.__hovered = value
        end
        function fakeHeader:ReportPost(value)
            fakeHeader.__post = value
        end
    end
    return fakeHeader
end

-----------------------------------------------------------
-- Test Helpers: The window
-----------------------------------------------------------

--- Puts text into an edit box. **`SetText` alone does not run `OnTextChanged`.** That script, which
--- does run when a person types, is what turns [Cancel] on and off in the macro editor and what sets
--- the search term in the search box, so skipping it makes everything measured with it a different
--- act from the one a person performs.
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

local function LeftColumnProvider()
    return DebindResultPanel.ContentArea.ScrollBox:GetDataProvider()
end

--- The first drawn element of the left column `predicate` answers for, and its index.
local function FindLeftElement(predicate)
    for index, elementData in LeftColumnProvider():EnumerateEntireRange() do
        if predicate(elementData) then
            return elementData, index
        end
    end
end

local function LeftRowOf(action)
    return FindLeftElement(function(e) return e.row and e.row.action == action end)
end

local function OpenOverviewWithNothingPicked()
    DebindFrame:Show()
    AddTeardown(function() DebindFrame:CloseWindow() end)
    DebindLayerPanel:SetSelectedAction(nil)
    DebindResultPanel:RefreshKeyboard()
end

--- The storage tab's seat in `PANELS` (`DebindUI.lua`). That table is a local over there, so this
--- is the one thing here that has to be kept in step by hand -- the storage tests' check for
--- `SelectEntry` on the panel is what says so out loud rather than quietly measuring the wrong
--- panel.
local STORAGE_PANEL_ID = 3

--- The other three seats in `PANELS`, kept in step by hand for the reason `STORAGE_PANEL_ID` gives:
--- that table is a local in `DebindUI.lua`. "Panels: every tab resolves to a panel of its own" is
--- what says so out loud for the tabs - ids that answer with different panels cannot all be
--- pointing at the wrong seat - and "Settings: the gear opens the settings tab" for the gear's.
---
--- **Switches sits second, ahead of sharing.** There were four seats while making a string and
--- taking one in were separate tabs; they are one now. Numbers that drift here do not error: they
--- measure a different panel and pass.
--- **Settings is a seat with no tab**, reached by the gear (`SETTINGS_PANEL` in `DebindUI.lua`),
--- and it is the only panel left that asks for a width of its own: the two width tests among the
--- "Panels:" cases need two panels that disagree, and the three tabs all ask for the same number
--- now.
local OVERVIEW_PANEL_ID, SWITCHES_PANEL_ID, SETTINGS_PANEL_ID = 1, 2, 4

-----------------------------------------------------------
-- What the other files of the kit read
-----------------------------------------------------------

Dev.tests = tests
Dev.testOrder = testOrder
Dev.RegisterTest = RegisterTest
Dev.Pass = Pass
Dev.Fail = Fail
Dev.WaitUntil = WaitUntil
Dev.DB = DB
Dev.Scratch = Scratch
Dev.RELOAD_REQUEST = RELOAD_REQUEST
Dev.RequestReload = RequestReload
Dev.teardowns = teardowns
Dev.AddTeardown = AddTeardown
Dev.RunTeardowns = RunTeardowns
Dev.PressEscape = PressEscape
Dev.GetTestLayer = GetTestLayer
Dev.GetOffSpecLayer = GetOffSpecLayer
Dev.NarrowestLayerHere = NarrowestLayerHere
Dev.PeriodKit = PeriodKit
Dev.SetIsolated = SetIsolated
Dev.NestConditions = NestConditions
Dev.DefaultCasting = DefaultCasting
Dev.InsertAction = InsertAction
Dev.UseOffSpecLayer = UseOffSpecLayer
Dev.CleanupActions = CleanupActions
Dev.WaitForIdle = WaitForIdle
Dev.ApplyBindings = ApplyBindings
Dev.HoldUnmatchedKeys = HoldUnmatchedKeys
Dev.IsOurClick = IsOurClick
Dev.GetKeyBindings = GetKeyBindings
Dev.GetNthBinding = GetNthBinding
Dev.GetKeyBindingsWithoutTwins = GetKeyBindingsWithoutTwins
Dev.PlaceWithoutTwins = PlaceWithoutTwins
Dev.KeyMapOrder = KeyMapOrder
Dev.MockBody = MockBody
Dev.SetMockState = SetMockState
Dev.GetMockState = GetMockState
Dev.SetMockModifiedClick = SetMockModifiedClick
Dev.probeReports = probeReports
Dev.LastEvalUnit = LastEvalUnit
Dev.watchMisses = watchMisses
Dev.EnableProbes = EnableProbes
Dev.EvalClickTimeButton = EvalClickTimeButton
Dev.EvalClickTimeKey = EvalClickTimeKey
Dev.EvalClickCast = EvalClickCast
Dev.LastEvalAnswer = LastEvalAnswer
Dev.WaitForEvalAnswer = WaitForEvalAnswer
Dev.LastWinner = LastWinner
Dev.WaitForWinner = WaitForWinner
Dev.ReadKeyMembership = ReadKeyMembership
Dev.WaitForMembership = WaitForMembership
Dev.ReadRoleMap = ReadRoleMap
Dev.WaitForRoleMap = WaitForRoleMap
Dev.ReadSecureState = ReadSecureState
Dev.ReadSecureUnit = ReadSecureUnit
Dev.UNIT_TOKEN_ABSENT = UNIT_TOKEN_ABSENT
Dev.StandDownTestFrame = StandDownTestFrame
Dev.MakeTestUnitFrame = MakeTestUnitFrame
Dev.FreshNamedFrame = FreshNamedFrame
Dev.CreateTestUnitFrame = CreateTestUnitFrame
Dev.SetFrameUnit = SetFrameUnit
Dev.HoverEnter = HoverEnter
Dev.HoverLeave = HoverLeave
Dev.GetHoverUnit = GetHoverUnit
Dev.WaitForHoverSlot = WaitForHoverSlot
Dev.FakeHeader = FakeHeader
Dev.TypeInto = TypeInto
Dev.LeftColumnProvider = LeftColumnProvider
Dev.FindLeftElement = FindLeftElement
Dev.LeftRowOf = LeftRowOf
Dev.OpenOverviewWithNothingPicked = OpenOverviewWithNothingPicked
Dev.STORAGE_PANEL_ID = STORAGE_PANEL_ID
Dev.OVERVIEW_PANEL_ID = OVERVIEW_PANEL_ID
Dev.SWITCHES_PANEL_ID = SWITCHES_PANEL_ID
Dev.SETTINGS_PANEL_ID = SETTINGS_PANEL_ID
