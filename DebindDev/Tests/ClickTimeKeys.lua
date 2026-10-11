local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local CleanupActions = Dev.CleanupActions
local ApplyBindings = Dev.ApplyBindings
local IsOurClick = Dev.IsOurClick
local GetKeyBindings = Dev.GetKeyBindings
local GetNthBinding = Dev.GetNthBinding
local GetKeyBindingsWithoutTwins = Dev.GetKeyBindingsWithoutTwins
local PlaceWithoutTwins = Dev.PlaceWithoutTwins
local SetMockState = Dev.SetMockState
local EnableProbes = Dev.EnableProbes
local EvalClickTimeButton = Dev.EvalClickTimeButton
local EvalClickTimeKey = Dev.EvalClickTimeKey
local LastEvalUnit = Dev.LastEvalUnit
local LastWinner = Dev.LastWinner
local WaitForWinner = Dev.WaitForWinner
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local SetFrameUnit = Dev.SetFrameUnit
local HoverEnter = Dev.HoverEnter
local HoverLeave = Dev.HoverLeave
local GetHoverUnit = Dev.GetHoverUnit
local WaitForHoverSlot = Dev.WaitForHoverSlot

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

        InsertAction({ type = Constants.USESLOT, value = SLOT, key = KEY })
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
            local records = GetKeyBindingsWithoutTwins(KEY)
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
            local place = PlaceWithoutTwins(KEY, idx)
            local got = place and records[place]
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
                local records = GetKeyBindingsWithoutTwins(KEY)
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

                local place = PlaceWithoutTwins(KEY, idx)
                local got = place and records[place]
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

-- **The click bakes the macro body** (`trimming-the-restricted-hot-paths.md`, item 2).
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
    description = "The click bakes an @unitframe macro body, which is also whether SetAttribute carries in the restricted environment",
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
        -- `StampBinding` writes no attribute at all (`ButtonAttributes.lua`). The click further down
        -- bakes `*macrotext-` itself, so on a second run in one session the same body would come
        -- back to a button still carrying what the first run's click baked -- and the assertion
        -- would read that instead of what `StampBinding` wrote. In play nothing is wrong with
        -- that: every press composes the body afresh before running it.
        macroBodySeq = macroBodySeq + 1
        local body = format("/cast [@unitframe] Debind%d", macroBodySeq)

        -- **The usual target with Normal Cast off, so the press over the frame reaches this action's
        -- twin** and nothing else of it, while the twin still aims where the original would.
        InsertAction({ type = Constants.MACROTEXT, value = body, key = KEY,
            casting = { hoverCast = "usual", normalCast = false } })
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
        -- `@unitframe` still standing in it is the proof that nothing bakes this body before a click.
        local raw = DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. button)
        if not (raw and raw:find("@unitframe", 1, true)) then
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

-- **Needs the game.** The headless keymap spec sees the two records Hover Cast puts on a key;
-- which of them a real press over a real registered frame reaches is decided by the click path
-- reading the frame under the cursor, and only the client has one.
RegisterTest("Hover twin: over a frame the key picks the twin, off it the original", {
    description = "Hover Cast가 켜지면 개체창 위에서 쌍둥이가, 밖에서는 원본이 받는다",
    run = function()
        local NAME = "Hover twin"
        local KEY = "CTRL-ALT-F6"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and rebuilding are both blocked in combat")
        end

        local probesOk, perr = EnableProbes()
        if not probesOk then return Fail(NAME, perr) end

        -- **The pointed unit is this action's own value.** The default, the usual target, makes no
        -- twin. With no mode written it follows the settings tab, which this run holds at Unit Frames
        -- (`SetIsolated`).
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY,
            casting = { hoverCast = "cast" } })
        ApplyBindings()

        -- **Four records**: the self and focus twins stand ahead of the hover twin and the original
        -- (`implementing-focus-and-self-cast.md` §3-4), and a press with no modifier held
        -- reaches only the last two. The winner comes back as a place in all four.
        local records = GetKeyBindings(KEY)
        if not records or #records ~= 4 then
            return Fail(NAME, format("the premise is gone: %d record(s) on the key, there should be 4",
                records and #records or 0))
        end
        local TWIN, ORIGINAL = 3, 4
        if not (records[TWIN].unit == "unitframe" and records[ORIGINAL].unit == nil) then
            return Fail(NAME, format("the premise is gone: units are %s / %s, the twin should come before the original",
                tostring(records[TWIN].unit), tostring(records[ORIGINAL].unit)))
        end

        local bound = GetBindingAction(KEY, true) or ""
        if not IsOurClick(bound) then
            return Fail(NAME, format("the key is %q, it never reached codegen", bound))
        end

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)
        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local over = WaitForWinner()
        if over ~= TWIN then
            return Fail(NAME, format("over the frame the winner is %s, it should be %d (the twin)", tostring(over), TWIN))
        end

        -- **The other half.** Without it a key that always picks the twin passes.
        HoverLeave(frame)
        if GetHoverUnit() ~= nil then
            return Fail(NAME, format("hover=%s after leaving, the slot did not clear", tostring(GetHoverUnit())))
        end

        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local off = WaitForWinner()
        if off ~= ORIGINAL then
            return Fail(NAME, format("off the frame the winner is %s, it should be %d (the original)", tostring(off), ORIGINAL))
        end

        return Pass(NAME, format("over the frame: %d (twin) / off it: %d (original)", TWIN, ORIGINAL))
    end,
})

-- **Needs the game.** Which record the condition leaves to the next action is headless
-- (`tests/eval_spec.lua`); what only the client shows is [when there is none] on the frame's unit
-- being answered by a real frame under the cursor. Alone on the key, the action then answers nothing
-- over the frame and fires off it.
RegisterTest("Pointed unit [none]: over a frame the action does not run, off it it does", {
    description = "개체창에 [없을 때]를 건 액션은 개체창 위에서 안 나가고, 밖에서는 나간다",
    run = function()
        local NAME = "Pointed unit [none]"
        local KEY = "CTRL-ALT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and rebuilding are both blocked in combat")
        end

        local probesOk, perr = EnableProbes()
        if not probesOk then return Fail(NAME, perr) end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY,
            conditions = { units = { unitframe = { exists = false } } } })
        ApplyBindings()

        local ORIGINAL
        for i, record in ipairs(GetKeyBindings(KEY) or {}) do
            if record.castModifier == Constants.CASTMOD_NONE and record.type ~= Constants.BLOCK then
                if record.hoverTwin or ORIGINAL then
                    return Fail(NAME, format("the premise is gone: a second record at %d on a press with no key held", i))
                end
                ORIGINAL = i
            end
        end
        if not ORIGINAL then
            return Fail(NAME, "the premise is gone: the original is not on the key")
        end

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("over the frame #%d fired, the condition should answer nothing", LastWinner()))
        end

        -- **The other half.** Without it a key that never fires passes.
        HoverLeave(frame)
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local off = WaitForWinner()
        if off ~= ORIGINAL then
            return Fail(NAME, format("off the frame the winner is %s, it should be %d (the original)",
                tostring(off), ORIGINAL))
        end

        return Pass(NAME, format("over the frame: nothing / off it: %d", ORIGINAL))
    end,
})

-- **Needs the game.** Which twin a chord picks is headless (`tests/castchord_spec.lua`); what only the
-- client can show is that it takes our binding on a chord built from its own Self Cast and Focus Cast
-- settings, and that the snippet picks the tier from the name that binding carries
-- (`handing-the-rest-of-a-key-to-the-game.md` 2-3). A table the sandbox does not hold raises inside
-- the snippet, and the key does nothing with nothing said.
--
-- What no press made from here can show is the client sending a real chord to that binding. The
-- binding table is asked instead, which is what the press reads.
RegisterTest("Self and focus cast: the chord's own binding picks the twin at the press", {
    description = "게임 설정의 조합키로 만든 조합 키가 우리 버튼에 걸리고, 그 버튼 이름이 self·focus 쌍둥이를 고른다",
    -- **The premise is the tester's game options, which a test may not write** (the binding table
    -- rule in `TestHarness.lua`). Without two different cast keys there is nothing to assert, so
    -- the run is skipped with what the options hold rather than failed.
    applies = function()
        local selfMod, focusMod = GetModifiedClick("SELFCAST"), GetModifiedClick("FOCUSCAST")
        if selfMod == "NONE" or focusMod == "NONE" or selfMod == focusMod then
            return false, format("needs two different cast keys in the game's options; it has SELFCAST %s, "
                .. "FOCUSCAST %s", tostring(selfMod), tostring(focusMod))
        end
        return true
    end,
    run = function()
        local NAME = "Cast chord at the press"
        local KEY = "NUMPADDIVIDE"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end

        local probesOk, perr = EnableProbes()
        if not probesOk then return Fail(NAME, perr) end

        local selfMod, focusMod = GetModifiedClick("SELFCAST"), GetModifiedClick("FOCUSCAST")

        -- **No target picked**, since a held key moves nothing else. The original then settles on no
        -- unit at all, so its row reads the winner's own `unit` rather than what the press reported.
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        ApplyBindings()

        local records = GetKeyBindings(KEY)
        if not records or #records ~= 3 then
            return Fail(NAME, format("the premise is gone: %d record(s) on the key, there should be 3",
                records and #records or 0))
        end

        local clickFrame = DebindPrivate.DefaultClickFrame:GetName()
        local seen = {}
        for _, case in ipairs({
            { Constants.CASTMOD_SELF, "player", selfMod .. "-" .. KEY },
            { Constants.CASTMOD_FOCUS, "focus", focusMod .. "-" .. KEY },
            { Constants.CASTMOD_NONE, nil, KEY },
        }) do
            if GetBindingAction(case[3]) ~= "" and case[1] ~= Constants.CASTMOD_NONE then
                return Fail(NAME, format("the premise is gone: the game has %s bound to %s", case[3],
                    GetBindingAction(case[3])))
            end
            local bound = GetBindingAction(case[3], true) or ""
            local button = strmatch(bound, "^CLICK " .. clickFrame .. ":(.+)$")
            if not button then
                return Fail(NAME, format("%s is bound to %q, not to our button", case[3], bound))
            end

            local ran, rerr = EvalClickTimeButton(KEY, button)
            if not ran then return Fail(NAME, rerr) end
            local got = WaitForWinner()
            if got == nil then
                return Fail(NAME, format("%s (%s): nothing won -- if `ClickTimeTiers` is not in the "
                    .. "restricted environment the snippet stops there", case[3], button))
            end

            local record = records[got]
            if not record or record.castModifier ~= case[1] then
                return Fail(NAME, format("%s: record %d won, which carries %s", case[3], got,
                    tostring(record and record.castModifier)))
            end

            local unit
            if case[2] then
                unit = LastEvalUnit()
                if unit ~= case[2] then
                    return Fail(NAME, format("%s: the press settled on %s, it should be %s",
                        case[3], tostring(unit), case[2]))
                end
            elseif record.unit ~= nil then
                return Fail(NAME, format("%s: the winner carries %s, it should carry no unit",
                    case[3], tostring(record.unit)))
            end
            seen[#seen + 1] = format("%s->#%d@%s", case[3], got, tostring(unit))
        end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})

-- **Needs the game.** Which body each twin composes is headless (`tests/eval_spec.lua`); what only the
-- client can show is that the composition runs inside the restricted environment after the unit is
-- settled and lands on the button the press fires. A body that reads `unit` before it is declared
-- composes `@target` on every press, and the key still fires.
RegisterTest("@@ in a macro body: the held modifier's unit is written in at the press", {
    description = "조합키 값마다 매크로 본문의 @@가 player, focus, target으로 구워진다",
    run = function()
        local NAME = "@@ at the press"
        local KEY = "CTRL-ALT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "nothing can be rebaked in combat")
        end

        local probesOk, perr = EnableProbes()
        if not probesOk then return Fail(NAME, perr) end

        InsertAction({ type = Constants.MACROTEXT, value = "/cast [@@] Renew", key = KEY })
        ApplyBindings()

        local seen = {}
        for _, case in ipairs({
            { Constants.CASTMOD_SELF, "/cast [@player]Renew" },
            { Constants.CASTMOD_FOCUS, "/cast [@focus]Renew" },
            { Constants.CASTMOD_NONE, "/cast [@target]Renew" },
        }) do
            SetMockState("castModifier", case[1])

            local ran, rerr = EvalClickTimeKey(KEY)
            if not ran then return Fail(NAME, rerr) end
            local got = WaitForWinner()
            if got == nil then
                return Fail(NAME, format("modifier %d: nothing won", case[1]))
            end

            local records = GetKeyBindings(KEY)
            local record = records and records[got]
            local button = record and record.clickbutton
            local body = button and DebindPrivate.DefaultClickFrame:GetAttribute("*macrotext-" .. button)
            if body ~= case[2] then
                return Fail(NAME, format("modifier %d: the body is %s, it should be %q", case[1],
                    body and format("%q", body) or "missing", case[2]))
            end
            seen[#seen + 1] = format("%d->%s", case[1], body)
        end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})
