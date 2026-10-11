local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local bor = bit.bor
local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local NestConditions = Dev.NestConditions
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local GetKeyBindingsWithoutTwins = Dev.GetKeyBindingsWithoutTwins
local PlaceWithoutTwins = Dev.PlaceWithoutTwins
local SetMockState = Dev.SetMockState
local GetMockState = Dev.GetMockState
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local WaitForWinner = Dev.WaitForWinner

-----------------------------------------------------------
-- Test Cases: Many records on one key, many axes at once
-----------------------------------------------------------

-- One condition on one key answers "does it look at the condition at all". Every other case in
-- the kit stops there. What a real profile looks like is the next question and nothing was asking
-- it: **a key carrying half a dozen records, each naming several axes, and exactly one of them
-- has to win.**
--
-- What is asked below is the press: which record the click-time snippet picks.
--
-- **The axes are chosen for the shapes they compare, not for their number.** `combat` and
-- `stealth` are equality; `groups` is a bitmask whose measured value is already the bit;
-- `forms` is a bitmask whose measured value is a *form number* that both paths raise to a power
-- of two after measuring -- so a mock lands on the number and the comparison happens on the bit,
-- and getting that boundary wrong is a fault no single-axis test can produce.

--- The states swept, in the order the cross product is taken. Every value here has to be one the
--- press can be forced to through `PROBE.MockState`, which only an axis measured under its own
--- name allows (so no unit axis, no `known`, no switch -- see `SetMockState`).
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

    local emitted = GetKeyBindingsWithoutTwins(key)
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

-- Seven records, and the last is unconditional, so every combination has a record to pick and the
-- only thing left to decide is *which* one, at the press. Exactly the path being measured.
--
-- Every record is a macrotext so that all seven are clickable and none can be dropped for having
-- no way to be bound.
local CLICKTIME_SWEEP

--- The three tables above read `Constants`, which is not there when this file loads: this addon
--- is ahead of Debind in the load order (`DebindDev.toc`). So they are built at Debind's
--- `ADDON_LOADED` instead, which is still long before any test runs.
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
Dev.OnDebindLoaded(BuildConstantTables)

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
            local emitted = GetKeyBindingsWithoutTwins(KEY)
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

            local got = PlaceWithoutTwins(KEY, WaitForWinner())
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
