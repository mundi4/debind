local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local WaitUntil = Dev.WaitUntil
local Scratch = Dev.Scratch
local RequestReload = Dev.RequestReload
local AddTeardown = Dev.AddTeardown
local PeriodKit = Dev.PeriodKit
local InsertAction = Dev.InsertAction
local CleanupActions = Dev.CleanupActions
local ApplyBindings = Dev.ApplyBindings
local HoldUnmatchedKeys = Dev.HoldUnmatchedKeys
local IsOurClick = Dev.IsOurClick
local MockBody = Dev.MockBody
local SetMockState = Dev.SetMockState
local watchMisses = Dev.watchMisses
local EnableProbes = Dev.EnableProbes
local ReadSecureState = Dev.ReadSecureState
local UNIT_TOKEN_ABSENT = Dev.UNIT_TOKEN_ABSENT
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local SetFrameUnit = Dev.SetFrameUnit
local HoverEnter = Dev.HoverEnter
local HoverLeave = Dev.HoverLeave

-----------------------------------------------------------
-- Test Cases: Secure Handler Health
-----------------------------------------------------------

-- Whether a rebuild really reaches the secure environment. Cut, nothing raises and the bindings
-- freeze in the state last applied: the keys keep sending something out and only the state changes
-- stop, so the user has no words for it beyond "sometimes it does not work". The point is to make a
-- silent fault loud.
RegisterTest("Secure update path", {
    description = "UpdateBindings reaches the restricted environment, measured by a switch it pushes in arriving there",
    run = function()
        local NAME = "Secure update path"
        local SWITCH = "$securepath"

        if InCombatLockdown() then
            return Fail(NAME, "UpdateBindings is deferred in combat, so nothing can be judged")
        end

        local driver = DebindPrivate.BindingDriver
        if not driver then return Fail(NAME, "no BindingDriver") end

        -- **A switch is what a rebuild pushes across on its own**, in the snippet that closes the
        -- rebuild (`BuildSwitchesSnippet`). So `States` carrying it is the proof that the snippets
        -- this rebuild built were executed, and reading it back needs no wait: a
        -- `SecureHandlerExecute` runs where it is called.
        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        AddTeardown(CleanupActions)
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true }
        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-SHIFT-F10", [SWITCH] = true })
        ApplyBindings()

        local state = ReadSecureState(SWITCH)
        if not (state and state.present) then
            return Fail(NAME,
                "the switch this rebuild pushed in never arrived in States, so the rebuild's snippets never ran and the bindings have stopped updating")
        end
        if state.value ~= true then
            return Fail(NAME, "the switch arrived off where the rebuild pushed it on")
        end

        return Pass(NAME, "what the rebuild pushed in is there")
    end,
})

--- A frame of the kit's own on an attribute driver that always answers `"a"`, put back to `0` by its
--- handler, so `ticks` counts the manager's ticks. What lets a test wait for "the manager has run"
--- without a fixed wait.
local beatWitness
local function BeatWitness()
    if not beatWitness then
        beatWitness = CreateFrame("Frame", nil, nil, "SecureHandlerAttributeTemplate")
        beatWitness:SetAttribute("_onattributechanged", [[
            if (name == "witness" and value ~= 0) then
                self:SetAttribute("witness", 0)
                self:SetAttribute("ticks", (self:GetAttribute("ticks") or 0) + 1)
            end
        ]])
        RegisterAttributeDriver(beatWitness, "witness", "a")
    end
    return beatWitness
end

--- How many rebuilds have run since the first ask. A hook on `DebindPrivate.UpdateBindings`, which a
--- queued rebuild reaches through the table as well (`Debind.lua`'s `UpdateBindingsTimerCallback`);
--- put on once, since `hooksecurefunc` cannot be taken off.
local rebuilds
local function RebuildCount()
    if not rebuilds then
        rebuilds = 0
        hooksecurefunc(DebindPrivate, "UpdateBindings", function() rebuilds = rebuilds + 1 end)
    end
    return rebuilds
end

--- Waits for `pred` after a value was moved with no rebuild behind it, and answers whether the
--- beat is what moved the key. **A rebuild in the wait judges every key itself**, so one that ran
--- leaves the answer saying nothing about the beat, and that is a failure with its own reason.
local function WaitOnBeat(pred)
    local from = RebuildCount()
    local ok = WaitUntil(pred, 2)
    if RebuildCount() ~= from then
        return false, "a rebuild ran during the wait, so the beat is not shown to have moved the key"
    end
    return ok, nil
end

-- **With `giveBackWhenNoActionRuns` off, the beat runs only while a key holds a tail.** It is a
-- Blizzard attribute driver that always answers `"a"` on the driver's beat attribute
-- (`trimming-the-tail-key-beat.md` 5-1), and the unit watch that used to carry it is never
-- registered. A profile with a computed switch and a measured condition but no tail is the case
-- worth asking about: it would have brought the 0.2s pass back under an older rule. On, the default,
-- each of these keys is let go where its condition fails and so is on the beat with no tail
-- ("Key given back: ..." below), so this case holds the keys (`HoldUnmatchedKeys`).
--
-- **Headless cannot see this.** It is Blizzard's manager writing the attribute, and nothing a spec
-- runs stands in for the manager. Whether the beat is running is asked of the attribute itself: put
-- to a value the manager would not write, it stays so through two manager ticks without a tail,
-- and is written again with one. On `"a"` that attribute is the beat's own, put to nil; through
-- `state-visibility` it is `statehidden`, put to true (`BeatSignal.lua`).
--
-- **It asks whether the key is still bound, in the same breath**, or a rebuild that quietly stopped
-- binding anything would read as the quietest possible pass.
RegisterTest("The driver is off Blizzard's beat", {
    description = "With giveBackWhenNoActionRuns off and no tail, the beat attribute is never written and the unit watch stays off, and the key still binds; a tail brings the beat",
    run = function()
        local NAME = "Beat registration"
        local KEY = "CTRL-SHIFT-F11"
        local SWITCH = "$pollbeat"
        local BEAT = DebindPrivate.JUDGE_BEAT_ATTRIBUTE

        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat, so nothing can be judged")
        end

        local driver = DebindPrivate.BindingDriver
        if not driver then return Fail(NAME, "no BindingDriver") end

        CleanupActions()
        AddTeardown(CleanupActions)

        local saved = DebindPrivate.Switches[SWITCH]
        AddTeardown(function()
            DebindPrivate.Switches[SWITCH] = saved
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        DebindPrivate.Switches[SWITCH] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" }
        HoldUnmatchedKeys()
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, [SWITCH] = true })
        InsertAction({ type = Constants.SPELL, value = 585, key = "CTRL-SHIFT-F12", combat = true })
        ApplyBindings()

        if UnitWatchRegistered(driver) then
            return Fail(NAME, "something registered the unit watch on the driver")
        end

        local bound = GetBindingAction(KEY, true) or ""
        if not IsOurClick(bound) then
            return Fail(NAME, format("the key did not bind (%q)", bound))
        end

        local attribute, unwritten = BEAT, nil
        if DebindPrivate.BeatSignal.comes then
            attribute, unwritten = "statehidden", true
        end

        -- Two ticks: the first may be the one already under way when the attribute was cleared.
        local witness = BeatWitness()
        local function WaitTicks(n)
            local from = witness:GetAttribute("ticks") or 0
            return WaitUntil(function() return (witness:GetAttribute("ticks") or 0) >= from + n end, 2)
        end
        driver:SetAttribute(attribute, unwritten)
        if not WaitTicks(2) then
            return Fail(NAME, "the manager did not tick for the witness")
        end
        if driver:GetAttribute(attribute) ~= unwritten then
            return Fail(NAME, format("with no tail %s was written (%s)", attribute, tostring(driver:GetAttribute(attribute))))
        end

        -- **The other half**: a tail on the key, and the beat comes.
        InsertAction({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = KEY })
        ApplyBindings()
        driver:SetAttribute(attribute, unwritten)
        if not WaitUntil(function() return driver:GetAttribute(attribute) ~= unwritten end, 2) then
            return Fail(NAME, format("with a tail %s was never written", attribute))
        end

        return Pass(NAME, "no beat without a tail, a beat with one, and the key is bound")
    end,
})

-- **Whether this client's manager writes `statehidden` on every tick** (`BeatSignal.lua`), which
-- is what the beat through `state-visibility` stands on. Headless runs a stand-in for the manager
-- of each kind (`beatsignal_spec.lua`); which kind this client is, only the client answers. Then
-- the session's own check, and a rebuild with a tail putting the beat on that signal and the
-- manager carrying it to the driver.
RegisterTest("Beat: the manager writes state-visibility on every tick", {
    description = "A check of the kit's own answers that it comes, the login's check agreed, and the beat moves to state-visibility and arrives",
    run = function()
        local NAME = "Beat signal"
        local KEY = "CTRL-SHIFT-F11"
        if InCombatLockdown() then
            return Fail(NAME, "a driver cannot be registered in combat")
        end

        local answer
        local probe = DebindPrivate.BeatSignal.Check(function(comes) answer = comes end)
        -- A check with no answer keeps its drivers and its OnUpdate for the rest of the session.
        AddTeardown(function()
            probe.frame:SetScript("OnUpdate", nil)
            probe.Release()
        end)
        if not WaitUntil(function() return answer ~= nil end, 3) then
            return Fail(NAME, "the check had no answer in 3 seconds")
        end
        if answer ~= true then
            return Fail(NAME, "this client's manager does not write statehidden on every tick")
        end
        if not WaitUntil(function() return DebindPrivate.BeatSignal.comes ~= nil end, 3) then
            return Fail(NAME, "the login's check had no answer")
        end
        if DebindPrivate.BeatSignal.comes ~= true then
            return Fail(NAME, "the login's check answered no where the kit's answered yes")
        end

        local driver = DebindPrivate.BindingDriver
        CleanupActions()
        AddTeardown(CleanupActions)
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        InsertAction({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = KEY })
        ApplyBindings()
        if not (driver:GetAttribute("_onattributechanged") or ""):find('^if %(name == "statehidden"%)') then
            return Fail(NAME, "the rebuild did not put the beat on statehidden")
        end
        driver:SetAttribute("statehidden", true)
        if not WaitUntil(function() return driver:GetAttribute("statehidden") == nil end, 2) then
            return Fail(NAME, "the manager never wrote statehidden on the driver")
        end
        return Pass(NAME, "it comes, and the beat arrives through state-visibility")
    end,
})

--- The period the isolated reader answers for one case (`SetIsolated`). Answers the setter.
function PeriodKit.Swap()
    AddTeardown(function() PeriodKit.chosen = nil end)
    return function(value) PeriodKit.chosen = value end
end

--- The manager's ticks per frame over `n` frames, counted on `BeatWitness`. **From the first tick**,
--- since a period just written waits for the timer the old one left (`SecureStateDriver.lua`).
function PeriodKit.TicksPerFrame(n)
    local witness = BeatWitness()
    local first = witness:GetAttribute("ticks") or 0
    if not WaitUntil(function() return (witness:GetAttribute("ticks") or 0) > first end, 1) then
        return 0
    end
    local from = witness:GetAttribute("ticks")
    for _ = 1, n do
        coroutine.yield(0)
    end
    return ((witness:GetAttribute("ticks") or 0) - from) / n
end

-- **Only the game has the manager.** Headless records what a rebuild writes to a shell
-- (`period_spec.lua`); whether Blizzard's attribute holds it is asked here.
RegisterTest("Period: a chosen period is written and taken off", {
    description = "A non-zero period goes on with a beat and comes off to 0.2 whatever was there before, and a period somebody wrote over ours stays",
    run = function()
        local NAME = "Period written"
        local KEY = "CTRL-SHIFT-F11"
        local DEFAULT = Constants.STATE_DRIVER_UPDATETIME_DEFAULT
        local manager = SecureStateDriverManager
        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat")
        end

        local before = manager:GetAttribute("updatetime")
        AddTeardown(function()
            if not InCombatLockdown() then
                manager:SetAttribute("updatetime", before or DEFAULT)
                if before == nil then
                    manager:SetAttribute("updatetime", nil)
                end
            end
        end)
        CleanupActions()
        AddTeardown(CleanupActions)
        local choose = PeriodKit.Swap()
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        InsertAction({ type = Constants.GIVEBACK, key = KEY })

        local function Period()
            return manager:GetAttribute("updatetime")
        end

        -- Ours comes off to 0.2 whatever was there before (owner, 2026-10-11).
        manager:SetAttribute("updatetime", 0.17)
        choose(0.1)
        ApplyBindings()
        if Period() ~= 0.1 then
            return Fail(NAME, format("0.1 with a beat left %s", tostring(Period())))
        end
        choose(nil)
        ApplyBindings()
        if Period() ~= DEFAULT then
            return Fail(NAME, format("ours came off to %s", tostring(Period())))
        end

        choose(0.1)
        ApplyBindings()
        manager:SetAttribute("updatetime", 0.15)
        choose(nil)
        ApplyBindings()
        if Period() ~= 0.15 then
            return Fail(NAME, format("a period written over ours became %s", tostring(Period())))
        end
        return Pass(NAME, "written, taken off to 0.2, and left alone where somebody else wrote")
    end,
})

-- **Only the game runs the manager and the wrap.** Headless calls the hook by hand and records the
-- wrap without running it (`period_spec.lua`). What is asked here: the manager ticks every frame
-- on 0, a foreign period is undone before it costs a frame and cannot land again, and **the wrap
-- gate** -- a driver another addon registers from its own code still resolves under the wrap.
-- `CallRestrictedClosure` refuses insecure callers, and if this goes red every addon's driver
-- registration in a session holding 0 is broken, so the wrap does not ship. Then **0 comes off**
-- the way a rebuild takes it off, after the wrap and the events registered under it: the period
-- goes back to 0.2, Blizzard's events and the ones addons asked for come back, the gate holds again
-- after those registrations, and a foreign period goes through the wrap now that the 0 is not ours.
--
-- **A failure ends the session.** A wrap that cannot be taken off and a manager that has stopped
-- taking drivers outlive any rebuild, and the cases after would go red over this one. The message
-- crosses in `Scratch()` and is reported on the other side.
RegisterTest("Period: 0 comes and goes, and holds against a foreign period", {
    description = "0 with a beat makes the manager tick every frame with no event on it, and one registered later comes off; a foreign 0.2 goes back to 0 at once and again after the wrap; a driver registered from addon code under the wrap resolves; 0 comes off to 0.2 with every event back, the gate holds again and a foreign period goes through",
    crossesReload = true,
    run = function(phase)
        local NAME = "Period zero"
        local KEY = "CTRL-SHIFT-F11"
        local FRAMES = 20
        local DEFAULT = Constants.STATE_DRIVER_UPDATETIME_DEFAULT
        local manager = SecureStateDriverManager
        local scratch = Scratch()
        if phase == "failed" then
            local failure = scratch.periodZeroFailure
            scratch.periodZeroFailure = nil
            return Fail(NAME, failure)
        end
        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat")
        end

        -- **Which call, if any, puts a forbidden aspect on the manager**, asked at the four points
        -- where one of ours could: once our events came off, once the wrap went on, once our hook
        -- took off an event registered after it, and once 0 came off and put the events back. Every
        -- report carries the answers. The value can
        -- be secret, so it is turned into text inside the pcall.
        local aspects = {}
        local function NoteAspects(where)
            local ok, answer = pcall(function() return tostring(manager:HasAnyForbiddenAspects()) end)
            aspects[#aspects + 1] = format("%s=%s", where, ok and answer or ("error: " .. tostring(answer)))
        end
        local function Abort(message)
            scratch.periodZeroFailure = format("%s [forbidden aspects: %s]", message,
                #aspects > 0 and table.concat(aspects, ", ") or "none asked yet")
            return RequestReload("failed")
        end

        CleanupActions()
        AddTeardown(CleanupActions)
        local choose = PeriodKit.Swap()
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        InsertAction({ type = Constants.GIVEBACK, key = KEY })
        -- The events this case puts on the manager come back when 0 comes off, and are this case's
        -- to take away again.
        local TEST_EVENTS = { "PLAYER_STARTED_MOVING", "UNIT_HEALTH", "PLAYER_STOPPED_MOVING", "UNIT_POWER_UPDATE" }
        AddTeardown(function()
            for _, event in ipairs(TEST_EVENTS) do
                manager:UnregisterEvent(event)
            end
        end)
        AddTeardown(function()
            if not InCombatLockdown() then
                manager:SetAttribute("updatetime", DEFAULT)
            end
        end)
        BeatWitness()
        choose(0)
        ApplyBindings()
        if manager:GetAttribute("updatetime") ~= 0 then
            return Abort(format("0 with a beat left %s", tostring(manager:GetAttribute("updatetime"))))
        end
        if not DebindPrivate.StateDriverPeriod.ZeroedByUs() then
            return Abort("0 was written and is not counted as ours")
        end
        NoteAspects("events off")

        -- **The manager's events come off at 0, and later ones as they land**
        -- (`zeroing-the-beat-period-where-it-is-needed.md` §5-2). Blizzard's twelve are the ones
        -- this can name (`SecureStateDriver.lua`). The hooks on its methods must leave them secure,
        -- or Blizzard's own calls through them would carry our taint.
        for _, event in ipairs({ "MODIFIER_STATE_CHANGED", "ACTIONBAR_PAGE_CHANGED",
            "UPDATE_BONUS_ACTIONBAR", "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "UPDATE_STEALTH",
            "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_DISABLED",
            "PLAYER_REGEN_ENABLED", "UNIT_PET", "GROUP_ROSTER_UPDATE" }) do
            if manager:IsEventRegistered(event) then
                return Abort(format("%s is still on the manager at 0", event))
            end
        end
        manager:RegisterEvent("PLAYER_STARTED_MOVING")
        if manager:IsEventRegistered("PLAYER_STARTED_MOVING") then
            return Abort("an event registered at 0 stayed on the manager")
        end
        manager:RegisterUnitEvent("UNIT_HEALTH", "player")
        if manager:IsEventRegistered("UNIT_HEALTH") then
            return Abort("a unit event registered at 0 stayed on the manager")
        end
        for _, method in ipairs({ "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "UnregisterAllEvents" }) do
            local secure, taintedBy = issecurevariable(manager, method)
            if not secure then
                return Abort(format("the manager's %s is tainted by %s", method, tostring(taintedBy)))
            end
        end

        -- One frame of slack for where the witness's tick falls against the count.
        local rate = PeriodKit.TicksPerFrame(FRAMES)
        if rate < (FRAMES - 1) / FRAMES then
            return Abort(format("on 0 the manager ticked %.2f times a frame", rate))
        end

        -- **The wrap is asked for by itself.** The hook alone keeps the period at 0 too, so a wrap
        -- the client refused would leave every check below green. Every method that registers or
        -- unregisters an event is documented as adding the `EventRegistrations` forbidden aspect,
        -- and `SecureHandlerWrapScript` refuses a frame with any (`SecureHandlers.lua`); whether
        -- what TakeEventsOff called puts one on the manager is this line's to answer. pcall'd so a
        -- refusal raised out of the hook crosses the reload like any failure.
        --
        -- **A wrap from earlier in the session is already on** and does not come off, so a second
        -- run asks only that it is still the one standing.
        local wasWrapped = DebindPrivate.StateDriverPeriod.Wrapped()
        local unwrapped = manager:GetScript("OnAttributeChanged")
        local wrote, wrapErr = pcall(manager.SetAttribute, manager, "updatetime", 0.2)
        if not wrote then
            return Abort("the first foreign 0.2 raised: " .. tostring(wrapErr))
        end
        if manager:GetAttribute("updatetime") ~= 0 and not wasWrapped then
            return Abort(format("a foreign 0.2 was left at %s", tostring(manager:GetAttribute("updatetime"))))
        end
        if not wasWrapped and manager:GetScript("OnAttributeChanged") == unwrapped then
            return Abort("a foreign 0.2 put no wrap on the manager")
        end
        if not DebindPrivate.StateDriverPeriod.Wrapped() then
            return Abort("a foreign 0.2 left the wrap off")
        end
        NoteAspects("wrapped")
        -- The wrap keeps the handler from running, not the attribute from being stored, so only the
        -- ticks can say what period is running now.
        wrote, wrapErr = pcall(manager.SetAttribute, manager, "updatetime", 0.2)
        if not wrote then
            return Abort("the second foreign 0.2 raised: " .. tostring(wrapErr))
        end
        rate = PeriodKit.TicksPerFrame(FRAMES)
        if rate < (FRAMES - 1) / FRAMES then
            return Abort(format("after a second foreign 0.2 the manager ticked %.2f times a frame", rate))
        end

        -- **Events registered after the wrap, then the gate.** This is the order a session meets:
        -- an addon loading late or changing a setting registers an event on the wrapped manager, and
        -- our hook takes it off from addon code. The wrap's body runs on every write to the manager
        -- and `CallRestrictedClosure` refuses an owner carrying a forbidden aspect, so an aspect added
        -- here would break every driver registered from then on, which is what the gate asks.
        local registered, registerErr = pcall(function()
            manager:RegisterEvent("PLAYER_STOPPED_MOVING")
            manager:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        end)
        if not registered then
            return Abort("an event registered after the wrap raised: " .. tostring(registerErr))
        end
        NoteAspects("event after wrap")
        if manager:IsEventRegistered("PLAYER_STOPPED_MOVING") then
            return Abort("an event registered after the wrap stayed on the manager")
        end
        if manager:IsEventRegistered("UNIT_POWER_UPDATE") then
            return Abort("a unit event registered after the wrap stayed on the manager")
        end

        -- Whether an error in the wrapped handler comes out of `SetAttribute` is not known here, so
        -- one that does is caught and crosses like any other failure; one that does not is seen by
        -- the attribute check.
        local function Gate(when)
            local gate = CreateFrame("Frame")
            AddTeardown(function()
                if not InCombatLockdown() then
                    UnregisterAttributeDriver(gate)
                end
            end)
            local ok, err = pcall(RegisterAttributeDriver, gate, "state-gate", "x")
            if not ok then
                return format("registering a driver from addon code %s raised: %s", when, tostring(err))
            end
            if gate:GetAttribute("state-gate") ~= "x" then
                return format("a driver registered from addon code %s resolved to %s", when,
                    tostring(gate:GetAttribute("state-gate")))
            end
        end
        local closed = Gate("under the wrap")
        if closed then
            return Abort(closed)
        end

        -- **0 comes off** the way a rebuild takes it off: the beat is still there and the period
        -- chosen is the default. The events go back on through insecure calls on the wrapped
        -- manager, which is the other order an aspect could arrive in.
        choose(nil)
        local restored, restoreErr = pcall(DebindPrivate.UpdateBindings)
        if not restored then
            return Abort("taking 0 off raised: " .. tostring(restoreErr))
        end
        NoteAspects("restored")
        if DebindPrivate.StateDriverPeriod.ZeroedByUs() then
            return Abort("0 still counts as ours after it came off")
        end
        if manager:GetAttribute("updatetime") ~= DEFAULT then
            return Abort(format("0 came off to %s", tostring(manager:GetAttribute("updatetime"))))
        end
        for _, event in ipairs(DebindPrivate.StateDriverPeriod.BLIZZARD_EVENTS) do
            if not manager:IsEventRegistered(event) then
                return Abort(format("Blizzard's %s did not come back", event))
            end
        end
        for _, event in ipairs(TEST_EVENTS) do
            if not manager:IsEventRegistered(event) then
                return Abort(format("%s, registered while 0 stood, did not come back", event))
            end
        end
        -- **The period running, not the attribute.** The foreign 0.2 the wrap stopped left the
        -- attribute reading 0.2 already, so only the ticks say whether the 0.2 put back landed.
        rate = PeriodKit.TicksPerFrame(FRAMES)
        if rate >= 0.5 then
            return Abort(format("after 0 came off the manager still ticked %.2f times a frame", rate))
        end
        closed = Gate("after 0 came off")
        if closed then
            return Abort(closed)
        end

        -- The wrap stays, and with the 0 no longer ours it lets a foreign period through.
        wrote, wrapErr = pcall(manager.SetAttribute, manager, "updatetime", 0.15)
        if not wrote then
            return Abort("a foreign 0.15 after 0 came off raised: " .. tostring(wrapErr))
        end
        rate = PeriodKit.TicksPerFrame(FRAMES)
        if rate >= 0.5 then
            return Abort(format("a foreign 0.15 after 0 came off still ticked %.2f times a frame", rate))
        end

        return Pass(NAME, "forbidden aspects " .. table.concat(aspects, ", "))
    end,
})

-- **The loop runs on Blizzard's beat** (`handing-the-rest-of-a-key-to-the-game.md` 2-5). What a
-- tail key is bound to in each state is headless (`tests/judgment_spec.lua`,
-- `tests/judgmentloop_spec.lua`), where the beat is a spec writing the attribute. What is left for
-- the client is that the unit watch on the driver delivers it at all, and that the restricted
-- `SetBinding` and `ClearBinding` take.
RegisterTest("Tail: the beat takes the key and hands it back to the command", {
    description = "A key holding a command under a combat action follows the injected combat on the beat alone",
    run = function()
        local NAME = "Tail beat"
        local KEY = "CTRL-SHIFT-F12"
        local COMMAND = "TOGGLEWORLDMAP"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        InsertAction({ type = Constants.COMMAND, value = COMMAND, key = KEY })
        ApplyBindings()

        -- Ends in a rebuild, whose own pass judges the key at peace.
        SetMockState("combat", false)
        local bound = GetBindingAction(KEY, true) or ""
        if bound ~= COMMAND then
            return Fail(NAME, format("at peace the key answers %q, it should be the command", bound))
        end

        -- **Written past `SetMockState`, which ends in a rebuild.** A rebuild judges every tail key
        -- itself, so only a value moved with none behind it is one the beat has to carry.
        SecureHandlerExecute(DebindPrivate.BindingDriver, MockBody("combat", true))
        local moved, why = WaitOnBeat(function() return IsOurClick(GetBindingAction(KEY, true)) end)
        if not moved then
            return Fail(NAME, why or format("no beat took the key in combat, it answers %q",
                GetBindingAction(KEY, true) or ""))
        end

        SecureHandlerExecute(DebindPrivate.BindingDriver, MockBody("combat", false))
        moved, why = WaitOnBeat(function() return GetBindingAction(KEY, true) == COMMAND end)
        if not moved then
            return Fail(NAME, why or format("no beat handed the key back at peace, it answers %q",
                GetBindingAction(KEY, true) or ""))
        end

        return Pass(NAME, "the beat took the key in combat and handed it back to the command")
    end,
})

-- **Under a period of 0, the beat judges the pointed frame** (§5-1 of
-- `zeroing-the-beat-period-where-it-is-needed.md`). Which way the key goes at each move is headless
-- (`tests/judgmentloop_spec.lua`, and `tests/judgment_spec.lua`'s run at 0). What only the client
-- shows is the hover bodies reading `ZeroedByUs` in the real restricted environment, and the
-- manager's beat taking each move after them: a body that fails there raises nothing, and the key
-- stays where the last wake left it. The frame's unit going under a still cursor is in it, since
-- under 0 that and the cursor leaving reach the beat the same way.
RegisterTest("Tail: under a period of 0 the beat follows the cursor on a unit frame", {
    description = "With the period at 0, entering and leaving a unit frame bind nothing by themselves, and the beat takes the key over the friendly frame, lets it go when its unit goes and comes back, and lets it go when the cursor leaves",
    run = function()
        local NAME = "Tail pointed at 0"
        local KEY = "CTRL-SHIFT-F12"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end

        CleanupActions()
        AddTeardown(CleanupActions)
        local choose = PeriodKit.Swap()
        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { unitframe = { reaction = Constants.REACTION_HELP } },
        })
        choose(0)
        ApplyBindings()
        if not DebindPrivate.StateDriverPeriod.ZeroedByUs() then
            return Fail(NAME, "the rebuild did not write 0, so the case would measure the ordinary bodies")
        end

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end
        local function Ours() return IsOurClick(GetBindingAction(KEY, true)) end
        if Ours() then
            return Fail(NAME, "with no frame under the cursor the key is held")
        end

        -- **Asked before any frame passes**: `HoverEnter` runs the body before it returns, and the
        -- ordinary one would have judged by then.
        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        if Ours() then
            return Fail(NAME, "entering the frame took the key by itself, so the body ran its ordinary form")
        end
        local moved, why = WaitOnBeat(Ours)
        if not moved then
            return Fail(NAME, why or "no beat took the key over the friendly frame")
        end

        SetFrameUnit(frame, UNIT_TOKEN_ABSENT)
        moved, why = WaitOnBeat(function() return not Ours() end)
        if not moved then
            return Fail(NAME, why or "no beat let the key go when the frame's unit went")
        end
        SetFrameUnit(frame, "player")
        moved, why = WaitOnBeat(Ours)
        if not moved then
            return Fail(NAME, why or "no beat took the key back when the frame's unit came back")
        end

        HoverLeave(frame)
        if not Ours() then
            return Fail(NAME, "leaving the frame let the key go by itself, so the body ran its ordinary form")
        end
        moved, why = WaitOnBeat(function() return not Ours() end)
        if not moved then
            return Fail(NAME, why or "no beat let the key go after the cursor left")
        end

        return Pass(NAME, "enter and leave wrote the slot alone, and the beat took, released, took back and released the key")
    end,
})

-- **A key whose one action is conditional, with nothing under it** (`giving-keys-back-when-no-action-runs.md`).
-- The same beat as the case above, with the giveback the rebuild puts at the key's end standing where
-- the command stood. Which way the key goes in each state is headless (`tests/judgmentloop_spec.lua`
-- N1); what is left for the client is that a key judged only because of that end is on the beat at
-- all, and that the restricted `ClearBinding` lets it go and a later `SetBindingClick` takes it again.
-- **Then `giveBackWhenNoActionRuns` off** (`HoldUnmatchedKeys`), and the same key held at peace:
-- without it, a key that something other than `giveBackWhenNoActionRuns` let go passes.
RegisterTest("Key given back: a lone conditional action lets its key go and takes it back", {
    description = "A key whose only action is a combat one is let go at peace and taken in combat, twice, on the beat alone, and held at peace with giveBackWhenNoActionRuns off",
    run = function()
        local NAME = "Lone conditional"
        local KEY = "CTRL-SHIFT-F12"
        local driver = DebindPrivate.BindingDriver

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        ApplyBindings()
        local function Ours() return IsOurClick(GetBindingAction(KEY, true)) end

        -- Ends in a rebuild, whose own pass judges the key at peace.
        SetMockState("combat", false)
        if Ours() then
            return Fail(NAME, "at peace the rebuild held the key")
        end

        -- **Past `SetMockState`, which ends in a rebuild**: only a value moved with none behind it is
        -- one the beat has to carry. Twice, so a key let go once is shown to come back.
        for round = 1, 2 do
            SecureHandlerExecute(driver, MockBody("combat", true))
            local moved, why = WaitOnBeat(Ours)
            if not moved then
                return Fail(NAME, format("round %d: %s", round, why or format(
                    "no beat took the key in combat, it answers %q", GetBindingAction(KEY, true) or "")))
            end
            SecureHandlerExecute(driver, MockBody("combat", false))
            moved, why = WaitOnBeat(function() return not Ours() end)
            if not moved then
                return Fail(NAME, format("round %d: %s", round, why or "no beat let the key go at peace"))
            end
        end

        HoldUnmatchedKeys()
        ApplyBindings()
        if not Ours() then
            return Fail(NAME, format("with giveBackWhenNoActionRuns off the key is let go at peace, it answers %q",
                GetBindingAction(KEY, true) or ""))
        end

        return Pass(NAME, "let go at peace and taken in combat, twice, on the beat; held with giveBackWhenNoActionRuns off")
    end,
})

-- **The watch in the restricted environment** (`WatchFragments`, `implementing-the-cuts-inside-the-
-- beat-handler.md` Q2). Which key the loop binds at every point and after every one-column move is
-- headless (`tests/judgment_spec.lua`). What only the client shows is the watch's text parsed there
-- and its fragments written and joined there: a body that fails at it raises nothing and leaves
-- every carried column where it stood. Two words moved one after the other with no rebuild, then
-- two beats with nothing moved, and the development check (`PROBE.WatchCheck`) reporting no column
-- that moved on a beat the watch let pass.
RegisterTest("Tail: the watch follows two state words one after the other", {
    description = "With no rebuild, combat and then stealth move a tail key through the watch, a quiet beat leaves it, and the watch's check finds no column it missed",
    run = function()
        local NAME = "Tail watch"
        local KEY = "CTRL-SHIFT-F12"
        local COMMAND = "TOGGLEWORLDMAP"
        local driver = DebindPrivate.BindingDriver

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = true })
        InsertAction({ type = Constants.COMMAND, value = COMMAND, key = KEY, stealth = true })
        InsertAction({ type = Constants.GIVEBACK, key = KEY })
        ApplyBindings()
        -- Each ends in a rebuild, whose pass judges the key with neither held.
        SetMockState("combat", false)
        SetMockState("stealth", false)
        local function Bound() return GetBindingAction(KEY, true) or "" end
        if IsOurClick(Bound()) or Bound() == COMMAND then
            return Fail(NAME, format("with neither held the key answers %q, it should be let go", Bound()))
        end

        local witness = BeatWitness()
        local function WaitTicks(n)
            local from = witness:GetAttribute("ticks") or 0
            return WaitUntil(function() return (witness:GetAttribute("ticks") or 0) >= from + n end, 2)
        end

        -- **Past `SetMockState`, which ends in a rebuild**: only a value moved with none behind it
        -- is one the watch has to see.
        SecureHandlerExecute(driver, MockBody("combat", true))
        local moved, why = WaitOnBeat(function() return IsOurClick(Bound()) end)
        if not moved then
            return Fail(NAME, why or format("in combat no beat took the key, it answers %q", Bound()))
        end
        SecureHandlerExecute(driver, MockBody("stealth", true))
        SecureHandlerExecute(driver, MockBody("combat", false))
        moved, why = WaitOnBeat(function() return Bound() == COMMAND end)
        if not moved then
            return Fail(NAME, why or format("stealthed at peace no beat moved the key, it answers %q", Bound()))
        end
        if not WaitTicks(2) then
            return Fail(NAME, "the manager did not tick for the witness")
        end
        if Bound() ~= COMMAND then
            return Fail(NAME, format("a quiet beat moved the key to %q", Bound()))
        end
        if #watchMisses > 0 then
            return Fail(NAME, format("the watch let a beat pass with column %d moved", watchMisses[1]))
        end
        return Pass(NAME, "two words moved the key through the watch, and a quiet beat held it")
    end,
})

-- **The units on the watch** (Q3 of `implementing-the-cuts-inside-the-beat-handler.md`). Which key
-- the loop binds at every point, a token moved under a wake included, is headless
-- (`tests/judgment_spec.lua`). What only the client shows is an alias's fragment built from its token
-- where the wake writes it, and a development build asking each unit's fragment beside its own
-- `unit` (`PROBE.ParseUnit`): a body that fails at either raises nothing and leaves the key where it
-- stood. One fixed unit and one alias pointed at it, so a life held for the player moves both.
RegisterTest("Tail: the units' watch follows a token and a life", {
    description = "With no rebuild, pointing @custom1 at the player takes its tail key, and holding the player dead lets go of both that key and one on the player, through the watch",
    run = function()
        local NAME = "Tail units"
        local KEY, KEY2 = "CTRL-SHIFT-F12", "CTRL-SHIFT-F11"
        local driver, unitWatch = DebindPrivate.BindingDriver, DebindPrivate.UnitWatch

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end
        local previous = DebindPrivate.Units and DebindPrivate.Units.custom1
        AddTeardown(function()
            if not InCombatLockdown() then
                unitWatch:SetAttribute("custom1", previous or "none")
            end
        end)
        unitWatch:SetAttribute("custom1", "none")

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, units = { custom1 = { dead = false } } })
        InsertAction({ type = Constants.GIVEBACK, key = KEY })
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY2, units = { player = { dead = false } } })
        InsertAction({ type = Constants.GIVEBACK, key = KEY2 })
        ApplyBindings()
        -- Ends in a rebuild, whose pass judges both keys with the player alive.
        SetMockState("player-dead", false)
        local function Taken(key) return IsOurClick(GetBindingAction(key, true)) end
        if Taken(KEY) then
            return Fail(NAME, "with @custom1 pointing at nothing its key is taken")
        end
        if not Taken(KEY2) then
            return Fail(NAME, "with the player alive the key on the player is not taken")
        end

        local witness = BeatWitness()
        local function WaitTicks(n)
            local from = witness:GetAttribute("ticks") or 0
            return WaitUntil(function() return (witness:GetAttribute("ticks") or 0) >= from + n end, 2)
        end

        -- The token moves under the alias's wake.
        unitWatch:SetAttribute("custom1", "player")
        local moved, why = WaitOnBeat(function() return Taken(KEY) end)
        if not moved then
            return Fail(NAME, why or "@custom1 pointed at the player and its key was not taken")
        end
        -- Past `SetMockState`, which ends in a rebuild: only a beat moves the keys from here.
        SecureHandlerExecute(driver, MockBody("player-dead", true))
        moved, why = WaitOnBeat(function() return not Taken(KEY) and not Taken(KEY2) end)
        if not moved then
            return Fail(NAME, why or format("the player held dead and no beat let go: @custom1's key %s, the player's %s",
                tostring(Taken(KEY)), tostring(Taken(KEY2))))
        end
        if not WaitTicks(2) then
            return Fail(NAME, "the manager did not tick for the witness")
        end
        if Taken(KEY) or Taken(KEY2) then
            return Fail(NAME, "a quiet beat took a key back")
        end
        SecureHandlerExecute(driver, MockBody("player-dead", false))
        moved, why = WaitOnBeat(function() return Taken(KEY) and Taken(KEY2) end)
        if not moved then
            return Fail(NAME, why or "the player alive again and no beat took both keys back")
        end
        if #watchMisses > 0 then
            return Fail(NAME, format("the watch let a beat pass with column %d moved", watchMisses[1]))
        end
        return Pass(NAME, "a token and a life moved both keys through the units' watch")
    end,
})

-- **The loop measures the form by the call** (`Constants.MEASURED_BY`, Q2d of
-- `implementing-the-cuts-inside-the-beat-handler.md`). Which key that binds, the press and the loop
-- alike, is headless (`tests/judgment_spec.lua`). What only the client shows is the beat's body
-- calling `GetShapeshiftForm()` and turning it into the cell there, under a watch whose fragments
-- are still the word's: a body that fails at it raises nothing and the key stays where it was.
RegisterTest("Tail: the form moves the key by the call", {
    description = "With no rebuild, the form held at 1 and then 2 moves a tail key through the beat's call, a quiet beat leaves it, and the watch's check finds no column it missed",
    run = function()
        local NAME = "Tail form"
        local KEY = "CTRL-SHIFT-F12"
        local COMMAND = "TOGGLEWORLDMAP"
        local driver = DebindPrivate.BindingDriver

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, forms = 2 ^ 1 })
        InsertAction({ type = Constants.COMMAND, value = COMMAND, key = KEY, forms = 2 ^ 2 })
        InsertAction({ type = Constants.GIVEBACK, key = KEY })
        ApplyBindings()
        -- Ends in a rebuild, whose pass judges the key in no form.
        SetMockState("form", 0)
        local function Bound() return GetBindingAction(KEY, true) or "" end
        if IsOurClick(Bound()) or Bound() == COMMAND then
            return Fail(NAME, format("in no form the key answers %q, it should be let go", Bound()))
        end

        local witness = BeatWitness()
        local function WaitTicks(n)
            local from = witness:GetAttribute("ticks") or 0
            return WaitUntil(function() return (witness:GetAttribute("ticks") or 0) >= from + n end, 2)
        end

        -- Past `SetMockState`, which ends in a rebuild: only a beat moves the key from here.
        SecureHandlerExecute(driver, MockBody("form", 1))
        local moved, why = WaitOnBeat(function() return IsOurClick(Bound()) end)
        if not moved then
            return Fail(NAME, why or format("in form 1 no beat took the key, it answers %q", Bound()))
        end
        SecureHandlerExecute(driver, MockBody("form", 2))
        moved, why = WaitOnBeat(function() return Bound() == COMMAND end)
        if not moved then
            return Fail(NAME, why or format("in form 2 no beat moved the key, it answers %q", Bound()))
        end
        if not WaitTicks(2) then
            return Fail(NAME, "the manager did not tick for the witness")
        end
        if Bound() ~= COMMAND then
            return Fail(NAME, format("a quiet beat moved the key to %q", Bound()))
        end
        if #watchMisses > 0 then
            return Fail(NAME, format("the watch let a beat pass with column %d moved", watchMisses[1]))
        end
        return Pass(NAME, "the form moved the key through the beat's call, and a quiet beat held it")
    end,
})

-- **`flyable` is measured behind `nocombat`, after the watch** (`MeasureGates`). Which key that
-- binds at every point is headless (`tests/judgment_spec.lua`); what only the client shows is the
-- generated gate running in the restricted environment, where one that does not attach leaves the
-- key quietly where it was. In combat the zone turning flyable moves nothing, and the beat combat
-- ends in takes the key.
RegisterTest("Tail: flyable in combat waits behind nocombat", {
    description = "A mount key on [nocombat,flyable]: flyable turning on in combat leaves the key, and the beat combat ends in takes it, with no rebuild",
    run = function()
        local NAME = "Tail flyable gate"
        local KEY = "CTRL-SHIFT-F12"
        local driver = DebindPrivate.BindingDriver

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, combat = false, flyable = true })
        InsertAction({ type = Constants.GIVEBACK, key = KEY })
        ApplyBindings()
        SetMockState("combat", false)
        -- Ends in a rebuild, whose pass judges the key out of combat on the ground.
        SetMockState("flyable", false)
        local function Taken() return IsOurClick(GetBindingAction(KEY, true)) end
        if Taken() then
            return Fail(NAME, "on the ground the key is taken")
        end
        -- The watch's text as the restricted side holds it: `combat` is in it and `flyable` is not.
        local text
        driver.DebindTestJudgeText = function(_, value) text = value end
        AddTeardown(function() driver.DebindTestJudgeText = nil end)
        SecureHandlerExecute(driver, [[self:CallMethod("DebindTestJudgeText", Judge and Judge.text or "")]])
        if not (text or ""):find("combat", 1, true) or text:find("flyable", 1, true) then
            return Fail(NAME, format("the watch is not combat without flyable: %q", tostring(text)))
        end

        local witness = BeatWitness()
        local function WaitTicks(n)
            local from = witness:GetAttribute("ticks") or 0
            return WaitUntil(function() return (witness:GetAttribute("ticks") or 0) >= from + n end, 2)
        end

        -- Past `SetMockState`, which ends in a rebuild: only a beat moves the key from here.
        SecureHandlerExecute(driver, MockBody("combat", true))
        SecureHandlerExecute(driver, MockBody("flyable", true))
        if not WaitTicks(2) then
            return Fail(NAME, "the manager did not tick for the witness")
        end
        if Taken() then
            return Fail(NAME, "in combat the zone turning flyable took the key")
        end
        SecureHandlerExecute(driver, MockBody("combat", false))
        local moved, why = WaitOnBeat(Taken)
        if not moved then
            return Fail(NAME, why or "combat ended where it can fly and no beat took the key")
        end
        if #watchMisses > 0 then
            return Fail(NAME, format("the watch let a beat pass with column %d moved", watchMisses[1]))
        end
        return Pass(NAME, "flyable in combat moved nothing, and the beat combat ended in took the key")
    end,
})

-- **The loop composes a computed switch's text only when a name it reads moves**
-- (`trimming-the-tail-key-beat.md` 8-6). Which key that binds is headless
-- (`tests/judgment_spec.lua`); what is left for the client is that the bodies composing and clearing
-- the texts run in the restricted environment, where one that does not attach leaves the key
-- quietly where it was. A switch set by hand under two computed ones walks all of it on one wake:
-- the wake clears the first text, and the first switch flipping clears the second.
RegisterTest("Tail: a switch set by hand moves the key through two computed switches", {
    description = "Setting a switch by hand rebinds a tail key read through two computed switches, on its wake and with no rebuild",
    run = function()
        local NAME = "Tail computed switch"
        local KEY = "CTRL-SHIFT-F12"
        local COMMAND = "TOGGLEWORLDMAP"
        local HAND, FIRST, SECOND = "$tailhand", "$tailfirst", "$tailsecond"
        local MODES = Constants.SWITCH_MODES

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end

        local saved = {}
        for _, name in ipairs({ HAND, FIRST, SECOND }) do
            saved[name] = DebindPrivate.Switches[name] or false
        end
        local savedStored = DebindPrivate.GetRememberedSwitch(HAND)
        AddTeardown(function()
            for name, definition in pairs(saved) do
                DebindPrivate.Switches[name] = definition or nil
            end
            DebindPrivate.SetRememberedSwitch(HAND, savedStored)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)
        DebindPrivate.Switches[HAND] = { mode = MODES.MANUAL }
        DebindPrivate.Switches[FIRST] = { mode = MODES.EXPR, expr = "[" .. HAND .. "]" }
        DebindPrivate.Switches[SECOND] = { mode = MODES.EXPR, expr = "[" .. FIRST .. "]" }
        DebindPrivate.SetRememberedSwitch(HAND, nil)

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, [SECOND] = true })
        InsertAction({ type = Constants.COMMAND, value = COMMAND, key = KEY })
        ApplyBindings()

        local bound = GetBindingAction(KEY, true) or ""
        if bound ~= COMMAND then
            return Fail(NAME, format("with %s unset the key answers %q, it should be the command", HAND, bound))
        end

        -- **Nothing is waited on**: the attribute write runs `SetSwitch`, and its wake binds on the
        -- spot. A beat between could not stand in for it, since nothing but the wake clears the text.
        DebindPrivate.SwitchesUpdaterFrame:SetAttribute(HAND, true)
        bound = GetBindingAction(KEY, true) or ""
        if not IsOurClick(bound) then
            return Fail(NAME, format("%s went on and the key answers %q, it should be ours", HAND, bound))
        end

        DebindPrivate.SwitchesUpdaterFrame:SetAttribute(HAND, false)
        bound = GetBindingAction(KEY, true) or ""
        if bound ~= COMMAND then
            return Fail(NAME, format("%s went off and the key answers %q, it should be the command", HAND, bound))
        end

        return Pass(NAME, "the switch's wake took the key and handed it back, through both computed switches")
    end,
})

-- **A pet battle is pushed to the loop, not measured on the beat** (`trimming-the-tail-key-beat.md`
-- 3-3). What the events push is headless (`tests/judgment_spec.lua`); what is left for the client is
-- that `SetPetBattle` and the wake it runs work in the restricted environment. The two keys share
-- one `bartakeover` column, so it parses the bars beside the pushed battle; a column that only asks
-- about a battle writes a literal instead, and that body is run headless (`judgment_spec.lua`'s pet
-- battle cases). A battle cannot be started on demand, so the value is pushed the way the events
-- push it.
RegisterTest("Tail: a pushed pet battle moves the key on its wake", {
    description = "SetPetBattle rebinds a key on Pet Battles and one on None with no beat, and SeedPetBattle puts the world's value back",
    run = function()
        local NAME = "Tail pet battle"
        local BATTLE_KEY = "CTRL-SHIFT-F12"
        local BAR_KEY = "CTRL-SHIFT-F11"
        local COMMAND = "TOGGLEWORLDMAP"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        if SecureCmdOptionParse("[petbattle][vehicleui][possessbar][overridebar][shapeshift] 1") == "1" then
            return Fail(NAME, "run out of a pet battle and on the usual bar")
        end

        local driver = DebindPrivate.BindingDriver
        AddTeardown(function()
            if not InCombatLockdown() then
                DebindPrivate.SeedPetBattle()
            end
        end)

        InsertAction({ type = Constants.SPELL, value = 585, key = BATTLE_KEY,
            bartakeover = Constants.BARTAKEOVER_PETBATTLE })
        InsertAction({ type = Constants.COMMAND, value = COMMAND, key = BATTLE_KEY })
        InsertAction({ type = Constants.SPELL, value = 585, key = BAR_KEY,
            bartakeover = Constants.BARTAKEOVER_NONE })
        InsertAction({ type = Constants.COMMAND, value = COMMAND, key = BAR_KEY })
        ApplyBindings()

        local function Bound(key)
            local bound = GetBindingAction(key, true) or ""
            return IsOurClick(bound) and "ours" or bound
        end
        if Bound(BATTLE_KEY) ~= COMMAND or Bound(BAR_KEY) ~= "ours" then
            return Fail(NAME, format("out of a battle the keys answer %q and %q, they should be the command and ours",
                Bound(BATTLE_KEY), Bound(BAR_KEY)))
        end

        -- **Nothing is waited on**: the beat no longer reads a battle, so only the wake can move these.
        SecureHandlerExecute(driver, [[self:RunAttribute("SetPetBattle", true)]])
        if Bound(BATTLE_KEY) ~= "ours" or Bound(BAR_KEY) ~= COMMAND then
            return Fail(NAME, format("in a pushed battle the keys answer %q and %q, they should be ours and the command",
                Bound(BATTLE_KEY), Bound(BAR_KEY)))
        end

        SecureHandlerExecute(driver, [[self:RunAttribute("SetPetBattle", false)]])
        if Bound(BATTLE_KEY) ~= COMMAND or Bound(BAR_KEY) ~= "ours" then
            return Fail(NAME, format("after a pushed close the keys answer %q and %q, they should be the command and ours",
                Bound(BATTLE_KEY), Bound(BAR_KEY)))
        end

        -- **The login's seed puts the world back over a value pushed from here**, which its own
        -- record of what it pushed never saw.
        SecureHandlerExecute(driver, [[self:RunAttribute("SetPetBattle", true)]])
        DebindPrivate.SeedPetBattle()
        if Bound(BATTLE_KEY) ~= COMMAND or Bound(BAR_KEY) ~= "ours" then
            return Fail(NAME, format("after the seed the keys answer %q and %q, they should be the command and ours",
                Bound(BATTLE_KEY), Bound(BAR_KEY)))
        end

        return Pass(NAME, "the pushed battle took both keys over on the wake and gave them back, and the seed put the world back")
    end,
})
