local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local NarrowestLayerHere = Dev.NarrowestLayerHere
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local HoldUnmatchedKeys = Dev.HoldUnmatchedKeys
local IsOurClick = Dev.IsOurClick
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local LastWinner = Dev.LastWinner
local WaitForWinner = Dev.WaitForWinner
local ReadSecureState = Dev.ReadSecureState
local ReadSecureUnit = Dev.ReadSecureUnit

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
-- What it does not prove: that a real keypress arrives. `tests/boundkey_spec.lua` asks that, with
-- `GetBindingAction` ("an action that only sets a switch still registers it").
RegisterTest("Switch toggle flips the value", {
    description = "The toggle flips States and what the window reads together, twice running",
    run = function()
        local NAME = "Switch toggle"
        local KEY = "ALT-F7"
        local MODES = Constants.SWITCH_MODES

        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat, so nothing can be judged")
        end

        local saved = DebindPrivate.Switches["$state4"]
        AddTeardown(function()
            DebindPrivate.Switches["$state4"] = saved
            DebindPrivate.SetRememberedSwitch("$state4", nil)
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
        -- and if a broken registration marked this one as well neither could be read off the
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

        -- The mirror arrives on `C_Timer.After(0)` (`OnSwitchChanged`). It is what
        -- the window reads, so a mirror that does not follow leaves the restricted side right and
        -- the screen lying.
        coroutine.yield(0)
        local value = DebindPrivate.GetSwitchValue("$state4")
        if value ~= false then
            return Fail(NAME, format("what the window reads did not follow (value=%s)", tostring(value)))
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
-- `SwitchesUpdaterFrame` has the client call `_onattributechanged`, which sets the switch the press
-- reads, while the harness stores the attribute and never calls that handler. A spec calling the body by
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

        -- **Only the slot is swapped.** `DebindPrivate.Switches` is the saved table itself
        -- (`BindDerivedTables`), so writing into a definition's fields would edit the tester's own
        -- profile; a swapped slot leaves one reference to put back. `$burst` will not be in a user's
        -- profile, and is put back even if it is.
        local saved = DebindPrivate.Switches["$burst"]
        local savedStored = DebindPrivate.GetRememberedSwitch("$burst")
        AddTeardown(function()
            DebindPrivate.Switches["$burst"] = saved
            DebindPrivate.SetRememberedSwitch("$burst", savedStored)
            if not InCombatLockdown() then
                DebindPrivate.UpdateBindings()
            end
        end)

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        -- Both keys are asked at the press, which a key given back would not reach.
        HoldUnmatchedKeys()
        InsertAction({ type = Constants.SPELL, value = 585, key = KEY, ["$burst"] = true })
        InsertAction({ type = Constants.SPELL, value = 585, key = UNDEFINED_KEY, ["$nodefinition"] = true })

        -- **Defined once and then flipped**, rather than re-planted on either side. A switch's value
        -- is kept beside its definition rather than on it (`SetSwitchValue`), so writing `value` into
        -- the definition does not turn one on -- and flipping it is what the reader does anyway.
        DebindPrivate.Switches["$burst"] = { mode = MODES.MANUAL }
        DebindPrivate.SetSwitchValue("$burst", true)
        ApplyBindings()

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if WaitForWinner() == nil then
            return Fail(NAME, "$burst is defined and on and the key fires nothing, a name outside the five never reached codegen")
        end

        DebindPrivate.SetSwitchValue("$burst", false)
        ApplyBindings()

        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format(
                "$burst went off and the key still fires #%d, the name got through and the value is not compared", LastWinner()))
        end

        -- A name with no definition. Dropping the condition outright sends that action out
        -- **wider**, so a failure here reads as "fires with no condition".
        --
        -- **Two layers hold it back.** The marker takes that action out of `KeyMap` (the row is
        -- marked and the tooltip writes the name), and under it codegen bakes the condition as false.
        -- The press below does nothing with either one alive, and **which of the two held it is not
        -- a question for here**: what the marker answers is a pure function, so
        -- `tests/issue_spec.lua` looks at that.
        --
        -- **The key is still ours**, since the action is on a live layer (`Debind.lua`'s
        -- `KeysOnLiveLayers`) and `HoldUnmatchedKeys` is on, so what is asked is the press and not
        -- whether the key is bound.
        local whenUndefined = GetBindingAction(UNDEFINED_KEY, true) or ""
        if not IsOurClick(whenUndefined) then
            return Fail(NAME, format(
                "an action on an undefined name handed its key back: %q", whenUndefined))
        end
        ran, rerr = EvalClickTimeKey(UNDEFINED_KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format(
                "an action on an undefined name fires #%d, the condition is gone and it fires always", LastWinner()))
        end

        -- **The path walked in combat.** The two above are the insecure rebuild `ApplyBindings()`
        -- runs, and in combat that is deferred, so what carries a value that moves is the restricted
        -- side alone: the attribute write runs `SetSwitch`, and the press reads `States`.
        --
        -- Nothing is waited on. `SetAttribute` runs the handler on the spot
        -- (`reading-back-what-you-just-set.md`).
        DebindPrivate.SwitchesUpdaterFrame:SetAttribute("$burst", true)

        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if WaitForWinner() == nil then
            return Fail(NAME, "turned on with no rebuild and the key fires nothing, in combat it would never come back")
        end

        return Pass(NAME, "$burst on: fires / off: nothing / undefined: held, fires nothing / on with no rebuild: fires")
    end,
})

-- **The specialization condition, at the key.** It never reaches the restricted side:
-- `BuildKeyMap` reads the specialization being played and leaves the bindings it rules out of the
-- key map (`Specs.lua`'s `SpecConditionHolds`).
--
-- **What the client answers here the harness cannot.** `tests/specid_spec.lua` runs the whole set
-- of cases against ids the shim was told to report; the ids read here are the ones the game hands
-- out for the character being played, including the initial specialization's, which carries an id
-- of its own that no class names and that exists nowhere but in a client.
--
-- A specialization cannot be changed from a test, so the change and the rebuild it pulls are the
-- spec's. What is left is the pair: the set holding this specialization fires, the set leaving it
-- out does not. With `giveBackWhenNoActionRuns` on, as the kit runs it, the second key is not held at all;
-- off, **both keys are ours** (`Debind.lua`'s `KeysOnLiveLayers`), so the press is what tells them
-- apart.
-- **Both halves, because on its own "fires nothing" also describes a key nothing was ever put on.**
RegisterTest("Spec condition: the specialization the character is on decides the key", {
    description = "A binding whose specialization mask holds this one fires; one whose mask leaves it out does not hold the key, and with giveBackWhenNoActionRuns off holds it and fires nothing",
    -- **A class of one specialization has nothing to leave out** (every camelot class), so the
    -- second key cannot be built there.
    applies = function()
        if #DebindPrivate.EnumerateClassSpecs(select(3, UnitClass("player"))) < 2 then
            return false, "this class has one specialization"
        end
        return true
    end,
    run = function()
        local NAME = "Spec condition"
        local INSIDE = "CTRL-SHIFT-F6"
        local OUTSIDE = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "rebuilds are deferred in combat, so nothing can be judged")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        local spec = C_SpecializationInfo.GetSpecialization()
        if not spec then
            return Fail(NAME, "the client has not settled a specialization yet")
        end
        local classID = select(3, UnitClass("player"))

        -- **Every other class is written out at zero on both keys.** A class with no mask holds
        -- nothing, so the zeros say what leaving the class out would say anyway; they are spelled
        -- out because what this case turns on is that the two conditions differ by the played
        -- class's mask and by nothing else.
        local function Narrowed(mask)
            local specs = { [classID] = mask }
            local catalog = DebindPrivate.ClassSpecCatalog()
            for i = 1, #catalog do
                if (catalog[i].id ~= classID) then
                    specs[catalog[i].id] = 0
                end
            end
            return specs
        end

        -- Every specialization of this class but the one being played, so the second key differs
        -- from the first by which numbers the mask holds and by nothing else. The whole class
        -- rather than one other number, because a class sitting in its initial specialization has
        -- only the named ones to leave it out.
        local others = 0
        local classSpecs = DebindPrivate.EnumerateClassSpecs(classID);
        for i = 1, #classSpecs do
            if (classSpecs[i].index ~= spec) then
                others = others + Constants.SpecIndexFlag(classSpecs[i].index);
            end
        end
        if others == 0 then
            return Fail(NAME, "this class has no second specialization to leave this one out with")
        end

        InsertAction({ type = Constants.SPELL, value = 585, key = INSIDE,
            specs = Narrowed(Constants.SpecIndexFlag(spec)) })
        InsertAction({ type = Constants.SPELL, value = 585, key = OUTSIDE, specs = Narrowed(others) })
        ApplyBindings()

        local inside = GetBindingAction(INSIDE, true) or ""
        if not IsOurClick(inside) then
            return Fail(NAME, format("the mask holds %d and the key is %q", spec, inside))
        end
        local ran, rerr = EvalClickTimeKey(INSIDE)
        if not ran then return Fail(NAME, rerr) end
        if WaitForWinner() == nil then
            return Fail(NAME, format("the mask holds %d and the press fires nothing", spec))
        end

        -- With the option on, as the kit runs it, the key whose only action is left out is not held.
        local outside = GetBindingAction(OUTSIDE, true) or ""
        if IsOurClick(outside) then
            return Fail(NAME, format("the mask leaves %d out and the key was held with the option on: %q",
                spec, outside))
        end

        HoldUnmatchedKeys()
        ApplyBindings()
        outside = GetBindingAction(OUTSIDE, true) or ""
        if not IsOurClick(outside) then
            return Fail(NAME, format("the mask leaves %d out and the key was handed back: %q", spec, outside))
        end
        ran, rerr = EvalClickTimeKey(OUTSIDE)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("the mask leaves %d out and the press fires #%d", spec, LastWinner()))
        end

        return Pass(NAME, format("number %d: fires / left out: held, fires nothing", spec))
    end,
})

-- Test Cases: layer overrides (§4-6 to §4-9)
--
-- The definition is the account's and **only the behaviour is covered over by a layer.** Which
-- answer wins is read back off the table by `tests/switch_spec.lua`, and whether that answer really
-- reaches the key is `tests/boundkey_spec.lua`: the whole chain of `ApplySwitchResets` setting the
-- value again, codegen baking the winning row's `mode` and `expr`, and the press firing the key.
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

        local layerKey = DebindPrivate.GetSwitchLayerKey(NarrowestLayerHere(true))
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
        local classKey = DebindPrivate.GetSwitchLayerKey(NarrowestLayerHere(false))
        if classKey and classKey:find(guid, 1, true) then
            return Fail(NAME, format(
                "the class layer's key is %q, with the character in it the same class cannot share an answer",
                classKey))
        end

        return Pass(NAME, format("char=%q / class=%q", layerKey, tostring(classKey)))
    end,
})

-- **Holds down why the custom-target action owes no registration.** A switch's value lives in
-- `States`, which a rebuild wipes and refills from the registered ones only -- registration is what
-- carries the value across. A custom target's value lives in `UnitAliasMap` and UnitWatch's
-- `unitMap`, and nobody wipes either after they are created at load, so unlike the switch action
-- the target action has nothing to register.
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
-- **What this holds that the harness does not** is the real rebuild. `tests/restricted.lua` replays
-- UnitWatch's bodies too now, in an environment of their own, so what a custom target settles on is
-- answered there -- but on a recording of the prologue rather than on the game running it.
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
        if not IsOurClick(action) then
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
