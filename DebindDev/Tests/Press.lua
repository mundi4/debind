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
local WaitForIdle = Dev.WaitForIdle
local ApplyBindings = Dev.ApplyBindings
local IsOurClick = Dev.IsOurClick
local GetNthBinding = Dev.GetNthBinding
local GetKeyBindingsWithoutTwins = Dev.GetKeyBindingsWithoutTwins
local SetMockState = Dev.SetMockState
local SetMockModifiedClick = Dev.SetMockModifiedClick
local probeReports = Dev.probeReports
local EnableProbes = Dev.EnableProbes
local EvalClickTimeKey = Dev.EvalClickTimeKey
local LastWinner = Dev.LastWinner
local WaitForWinner = Dev.WaitForWinner
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local HoverEnter = Dev.HoverEnter
local HoverLeave = Dev.HoverLeave
local GetHoverUnit = Dev.GetHoverUnit
local WaitForHoverSlot = Dev.WaitForHoverSlot

-- **A block wins its key and does nothing**, which is what a command or an unused saved before the
-- tail actions came back is migrated to (`handing-the-rest-of-a-key-to-the-game.md` 2-8). Which
-- record wins is headless; what is left for the client is that the block goes through the real
-- wrapper and reports, and that the key is ours rather than the game's while it does nothing.
RegisterTest("Block: the key is ours and the press does nothing", {
    description = "A block stands on its key: bound to our button, firing nothing",
    run = function()
        local NAME = "Block"
        local KEY = "CTRL-SHIFT-F12"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({ type = Constants.BLOCK, key = KEY })
        ApplyBindings()

        local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY]
        local bound = GetBindingAction(KEY, true) or ""
        if not button or bound ~= "CLICK " .. DebindPrivate.DefaultClickFrame:GetName() .. ":" .. button then
            return Fail(NAME, format("the key answers %q, it should be our button", bound))
        end

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        -- **A report has to arrive at all.** A block winning reads as nil below, and so does a
        -- wrapper that never ran.
        if #probeReports == 0 then
            return Fail(NAME, "the press reported no winner, so the block never ran")
        end
        if LastWinner() ~= nil then
            return Fail(NAME, format("the press fired #%d", LastWinner()))
        end

        return Pass(NAME, "bound to our button, and the block won the press")
    end,
})

-- **`rtgsub` is what carries the mock into a parse**, and that it takes a restricted table as the
-- replacement is the client's to show: the plain `gsub` a body also has refuses one.
RegisterTest("Mock: a held state reaches a parsed expression", {
    description = "SetMockState puts a word's answer into PROBE.SecureCmdOptionParse, both forms of it, and releasing it hands the parse back to the world",
    run = function()
        local NAME = "Mock parse"

        if InCombatLockdown() then
            return Fail(NAME, "probes are rebaked out of combat only")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        local driver = DebindPrivate.BindingDriver
        local function Ask(expr)
            SecureHandlerExecute(driver, DebindPrivate.BakeSnippet(format(
                [[self:SetAttribute("debtest-parse", PROBE.SecureCmdOptionParse(%q) or "-")]], expr)))
            return driver:GetAttribute("debtest-parse")
        end
        AddTeardown(function()
            if not InCombatLockdown() then
                driver:SetAttribute("debtest-parse", nil)
            end
        end)

        SetMockState("combat", true)
        if Ask("[combat] c; n") ~= "c" or Ask("[nocombat] c; n") ~= "n" then
            return Fail(NAME, format("held in combat, [combat] answered %q and [nocombat] %q",
                Ask("[combat] c; n"), Ask("[nocombat] c; n")))
        end

        SetMockState("combat", false)
        if Ask("[combat] c; n") ~= "n" or Ask("[nocombat] c; n") ~= "c" then
            return Fail(NAME, format("held at peace, [combat] answered %q and [nocombat] %q",
                Ask("[combat] c; n"), Ask("[nocombat] c; n")))
        end

        -- Held in combat and then released: out of combat, the world says peace again.
        SetMockState("combat", true)
        SetMockState("combat", nil)
        if Ask("[nocombat] c; n") ~= "c" then
            return Fail(NAME, format("released, [nocombat] still answered %q", Ask("[nocombat] c; n")))
        end

        return Pass(NAME, "a held state reached the parse both ways and let go of it")
    end,
})

-- **A chord another addon holds with an override is left to it** (`handing-the-rest-of-a-key-to-the-game.md`
-- 2-4). The decision is headless (`tests/castchord_spec.lua` N7a); what is left for the client is
-- that `GetBindingAction(key, true)` reports somebody else's override at all, which is the one
-- thing the decision reads.
RegisterTest("Cast chord: another addon's override on it is left to that addon", {
    description = "With an override of another owner on the focus chord, the rebuild does not bind that chord",
    applies = function()
        if not DebindPrivate.FocusCastEnabled() then
            return false, "Focus Cast Key is off"
        end
        local mod = GetModifiedClick("FOCUSCAST")
        if mod ~= "ALT" and mod ~= "CTRL" and mod ~= "SHIFT" then
            return false, "the game has no focus cast modifier"
        end
        if GetBindingAction(mod .. "-F11") ~= "" then
            return false, mod .. "-F11 is bound in the game, so the chord is left either way"
        end
        return true
    end,
    run = function()
        local NAME = "Chord left to an override"
        local KEY = "F11"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end

        local chord = GetModifiedClick("FOCUSCAST") .. "-" .. KEY
        local target = DebindTestOverrideTarget or CreateFrame("Button", "DebindTestOverrideTarget")
        local owner = CreateFrame("Frame")
        AddTeardown(function()
            ClearOverrideBindings(owner)
        end)

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY })
        ApplyBindings()
        local bound = GetBindingAction(chord, true) or ""
        if not IsOurClick(bound) then
            return Fail(NAME, format("with nothing else on it %s answers %q, it should be our button",
                chord, bound))
        end

        SetOverrideBindingClick(owner, false, chord, target:GetName())
        ApplyBindings()
        bound = GetBindingAction(chord, true) or ""
        if bound ~= "CLICK " .. target:GetName() .. ":LeftButton" then
            return Fail(NAME, format("with another owner's override %s answers %q", chord, bound))
        end

        return Pass(NAME, format("%s was ours alone and left to the other owner's override", chord))
    end,
})

local function CastKeysInForce()
    local selfMod, focusMod = DebindPrivate.CastKeyModifiers()
    return { SELFCAST = selfMod, FOCUSCAST = focusMod }
end

--- Every chord a cast key in force makes of `key`, one modifier at a time and all together.
local function CastChordsOfKey(key)
    local all, chords = {}, {}
    for _, mod in pairs(CastKeysInForce()) do
        chords[#chords + 1] = DebindPrivate.JoinKeyModifiers({ [mod] = true }, key)
        all[mod] = true
    end
    chords[#chords + 1] = DebindPrivate.JoinKeyModifiers(all, key)
    return chords
end

-- **A tier with no twin gets no chord** (`picking-the-cast-tier-like-an-action-button.md` §3).
-- Which chords a rebuild binds and what a held press then does are headless (`castchord_spec.lua`
-- N18); what is left for the client is that the game's binding table holds none of them, and that
-- the press body reading the cast keys on the bare key compiles and still sends the original.
RegisterTest("Cast chord: a tier with no twin leaves its chord to fall onto the key", {
    description = "With every action skipping both cast keys, no cast key chord is ours and the bare key sends the original",
    applies = function()
        if not next(CastKeysInForce()) then
            return false, "no cast key is on in both the settings tab and the game"
        end
        -- A chord the game binds is left to it whatever the twins, so it could not tell.
        for _, chord in ipairs(CastChordsOfKey("F11")) do
            if GetBindingAction(chord) ~= "" then
                return false, chord .. " is bound in the game, so the chord is left either way"
            end
        end
        return true
    end,
    run = function()
        local NAME = "Twinless chords"
        local KEY = "F11"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then return Fail(NAME, probesErr) end

        InsertAction({ type = Constants.SPELL, value = 585, key = KEY,
            casting = { selfCastKey = "skip", focusCastKey = "skip" } })
        ApplyBindings()

        local bare = GetBindingAction(KEY, true) or ""
        if not IsOurClick(bare) then
            return Fail(NAME, format("%s answers %q, it should be our button", KEY, bare))
        end
        local chords = CastChordsOfKey(KEY)
        for _, chord in ipairs(chords) do
            local bound = GetBindingAction(chord, true) or ""
            if IsOurClick(bound) then
                return Fail(NAME, format("%s is ours: %q", chord, bound))
            end
        end

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local winner = WaitForWinner()
        local record = winner and GetNthBinding(KEY, winner)
        if not record or (record.castModifier or Constants.CASTMOD_NONE) ~= Constants.CASTMOD_NONE then
            return Fail(NAME, format("the bare key sent %s", tostring(record and record.castModifier)))
        end
        return Pass(NAME, format("%s is not ours and the bare key sent the original",
            table.concat(chords, ", ")))
    end,
})

-- **A cast key that shows on the bare key picks the tier the way an action button does**
-- (`picking-the-cast-tier-like-an-action-button.md` §2). Every combination is headless
-- (`castchord_spec.lua`); a test cannot hold a key, so the Self Cast Key is made to show through
-- `PROBE.IsModifiedClick`, and what is left for the client is that its own `IsModifiedClick` and
-- the branch reading it run in the real restricted environment.
RegisterTest("Cast tier: a Self Cast Key on the bare key picks the self twin", {
    description = "With the Self Cast Key showing, a key with a self twin sends it and a key without one sends nothing",
    applies = function()
        if not CastKeysInForce().SELFCAST then
            return false, "the Self Cast Key is not on in both the settings tab and the game"
        end
        return true
    end,
    run = function()
        local NAME = "Self Cast Key on the bare key"
        local TWIN, NO_TWIN = "F11", "F12"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local probesOk, probesErr = EnableProbes()
        if not probesOk then return Fail(NAME, probesErr) end

        InsertAction({ type = Constants.SPELL, value = 585, key = TWIN })
        InsertAction({ type = Constants.SPELL, value = 585, key = NO_TWIN, casting = { selfCastKey = "skip" } })
        ApplyBindings()

        -- The report itself rather than `LastWinner`, which answers nil for a tier's closing block
        -- as well: that is where a press sent to a tier with no twin would end.
        local function Tier(key)
            local ran, rerr = EvalClickTimeKey(key)
            if not ran then return nil, rerr end
            local winner = probeReports[#probeReports]
            if winner == nil or winner == "block" then
                return winner or "nothing"
            end
            local record = GetNthBinding(key, winner)
            return record and (record.castModifier or Constants.CASTMOD_NONE)
        end

        local plain, perr = Tier(TWIN)
        if plain ~= Constants.CASTMOD_NONE then
            return Fail(NAME, format("nothing held, %s sent %s", TWIN, tostring(perr or plain)))
        end

        SetMockModifiedClick("SELFCAST")
        local twin, terr = Tier(TWIN)
        if twin ~= Constants.CASTMOD_SELF then
            return Fail(NAME, format("Self Cast Key held, %s sent %s", TWIN, tostring(terr or twin)))
        end
        local none, nerr = Tier(NO_TWIN)
        if none ~= "nothing" then
            return Fail(NAME, format("Self Cast Key held, %s with no self twin sent %s", NO_TWIN,
                tostring(nerr or none)))
        end
        return Pass(NAME, "nothing held sends the original, held sends the self twin or nothing")
    end,
})

--- The slot `command`'s bar button shows right now, worked out on the insecure side in
--- `ActionBarController_UpdateAll`'s order.
local function ShownActionSlot(command)
    local AB = C_ActionBar
    local info = Constants.ACTION_BUTTON_COMMANDS[command]
    local page = info.page or (info.extra and AB.GetExtraBarIndex())
    if not page then
        if AB.HasVehicleActionBar() then
            page = AB.GetVehicleBarIndex()
        elseif AB.HasOverrideActionBar() then
            page = AB.GetOverrideBarIndex()
        elseif AB.HasTempShapeshiftActionBar() then
            page = AB.GetTempShapeshiftBarIndex()
        elseif AB.HasBonusActionBar() and AB.GetActionBarPage() == 1 then
            page = AB.GetBonusBarIndex()
        else
            page = AB.GetActionBarPage()
        end
    end
    return info.index + (page - 1) * 12
end

-- **The action button action works its slot out in the client** (`dropping-the-game-fallback.md`
-- §4). The page table is headless (`tests/actionbutton_spec.lua`); what is left for the client is
-- that the snippet compiles against the real bar functions and lands on the slot the bar controller
-- would pick.
RegisterTest("Action button: the press writes the slot the bar shows", {
    description = "An action button action writes *action- with the slot its bar button would fire",
    run = function()
        local NAME = "Action button slot"
        local cases = {
            { key = "CTRL-ALT-F9", command = "ACTIONBUTTON1" },
            { key = "CTRL-ALT-F10", command = "MULTIACTIONBAR1BUTTON1" },
        }
        if HasExtraActionBar() then
            cases[#cases + 1] = { key = "CTRL-ALT-F11", command = "EXTRAACTIONBUTTON1" }
        end

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end

        for _, case in ipairs(cases) do
            InsertAction({ type = Constants.ACTIONBUTTON, value = case.command, key = case.key })
        end
        -- The stance and pet buttons are baked at the rebuild; what the client answers is that the
        -- bar button names they rest on exist.
        InsertAction({ type = Constants.ACTIONBUTTON, value = "SHAPESHIFTBUTTON1", key = "CTRL-ALT-F12" })
        InsertAction({ type = Constants.ACTIONBUTTON, value = "BONUSACTIONBUTTON1", key = "CTRL-SHIFT-F9" })
        ApplyBindings()

        local clickFrame = DebindPrivate.DefaultClickFrame
        for _, case in ipairs(cases) do
            local binding = GetKeyBindingsWithoutTwins(case.key)
            binding = binding and binding[1]
            if not binding or not binding.clickbutton then
                return Fail(NAME, case.command .. " has no button on its key")
            end
            local expected = ShownActionSlot(case.command)
            local attribute = "*action-" .. binding.clickbutton
            clickFrame:SetAttribute(attribute, nil)

            local ran, rerr = EvalClickTimeKey(case.key)
            if not ran then return Fail(NAME, rerr) end

            -- A flyout slot opens our flyout and writes nothing, so only a plain one is asked.
            if GetActionInfo(expected) ~= "flyout" then
                local slot = clickFrame:GetAttribute(attribute)
                if slot ~= expected then
                    return Fail(NAME, format("%s wrote slot %s, the bar shows %d",
                        case.command, tostring(slot), expected))
                end
            end
        end

        local stance = GetKeyBindingsWithoutTwins("CTRL-ALT-F12")
        stance = stance and stance[1]
        if not stance or not stance.clickbutton
                or clickFrame:GetAttribute("*clickbutton-" .. stance.clickbutton) ~= _G.StanceButton1 then
            return Fail(NAME, "the stance button does not click StanceButton1")
        end
        local pet = GetKeyBindingsWithoutTwins("CTRL-SHIFT-F9")
        pet = pet and pet[1]
        if not pet or not pet.clickbutton
                or clickFrame:GetAttribute("*type-" .. pet.clickbutton) ~= "pet"
                or clickFrame:GetAttribute("*action-" .. pet.clickbutton) ~= 1 then
            return Fail(NAME, "the pet bar button is not pet action 1")
        end

        return Pass(NAME, format("%d buttons wrote the slot their bar shows", #cases))
    end,
})

--- The first action button command whose shown slot holds a flyout this character knows, and that
--- flyout's id. The tester's bars are read and never written, so a board with none has no case.
local function FindShownFlyoutSlot()
    local commands = {}
    for command, info in pairs(Constants.ACTION_BUTTON_COMMANDS) do
        if not info.pet and not info.stance and not info.extra then
            commands[#commands + 1] = command
        end
    end
    table.sort(commands)
    for _, command in ipairs(commands) do
        local kind, flyoutID = GetActionInfo(ShownActionSlot(command))
        if kind == "flyout" and select(4, GetFlyoutInfo(flyoutID)) then
            return command, flyoutID
        end
    end
end

-- **A flyout slot opens our own flyout.** Which button a press names is headless
-- (`tests/actionbutton_spec.lua`); what is left for the client is that the restricted
-- `GetActionInfo` hands the flyout's id over, that the real spellbook walk gave that flyout an
-- opener, and that the press answers with the button clicking it. Opening the flyout is the opener's
-- `_onclick`, which a click from the kit never runs.
RegisterTest("Action button: a flyout slot answers with our flyout's opener", {
    description = "An action button action on a slot holding a flyout answers with the click frame button that clicks that flyout's opener",
    applies = function()
        if not FindShownFlyoutSlot() then
            return false, "no slot the bars show holds a flyout this character knows"
        end
        return true
    end,
    run = function()
        local NAME = "Action button flyout slot"
        local KEY = "CTRL-ALT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        local command, flyoutID = FindShownFlyoutSlot()
        if not command then
            return Fail(NAME, "the flyout slot went away before the run")
        end

        local driver = DebindPrivate.BindingDriver
        AddTeardown(function()
            driver.DebindTestFlyoutAnswer = nil
        end)

        InsertAction({ type = Constants.ACTIONBUTTON, value = command, key = KEY })
        ApplyBindings()

        local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY]
        if not button then
            return Fail(NAME, command .. " has no button on its key")
        end
        local opener = DebindPrivate.GetFlyoutOpener(flyoutID)
        if not opener then
            return Fail(NAME, format("flyout %d is known but has no opener", flyoutID))
        end

        -- **The name the press answers with**, which `EvalClickTimeKey` drops.
        local answer
        driver.DebindTestFlyoutAnswer = function(_, name)
            answer = name
        end
        SecureHandlerExecute(driver, format([[
            self:CallMethod("DebindTestFlyoutAnswer", self:RunAttribute("EvalClickTimeKey", %q))
        ]], button))

        local clickFrame = DebindPrivate.DefaultClickFrame
        local clicks = answer and clickFrame:GetAttribute("*type-" .. answer) == "click"
            and clickFrame:GetAttribute("*clickbutton-" .. answer)
        if clicks ~= opener then
            return Fail(NAME, format("%s on flyout %d answered %s, which clicks %s", command, flyoutID,
                tostring(answer), tostring(clicks and (clicks:GetName() or clicks))))
        end
        return Pass(NAME, format("%s answers with flyout %d's opener", command, flyoutID))
    end,
})

-- **In a pet battle the main bar's buttons press the battle's.** Which button a press names is
-- headless (`tests/actionbutton_spec.lua`); what is left for the client is that the real battle
-- frames go onto the click frame from insecure code, that their names reach the restricted
-- environment, and that the press reads the pushed battle there and answers with one of them. A
-- battle cannot be opened on demand, so the stamp is called and the battle pushed the way the
-- events do both.
RegisterTest("Action button: a pushed pet battle hands the press to the battle's button", {
    description = "The pet battle buttons are stamped onto the click frame, and in a pushed battle ACTIONBUTTON4 answers with the switch button's name",
    applies = function()
        if not (PetBattleFrame and PetBattleFrame.BottomFrame) then
            return false, "this client has no pet battle UI"
        end
        return true
    end,
    run = function()
        local NAME = "Action button pet battle"
        local KEY = "CTRL-ALT-F9"

        if InCombatLockdown() then
            return Fail(NAME, "a rebuild is refused in combat, so nothing would be bound")
        end
        if SecureCmdOptionParse("[petbattle] 1") == "1" then
            return Fail(NAME, "run out of a pet battle")
        end

        local driver = DebindPrivate.BindingDriver
        AddTeardown(function()
            driver.DebindTestPetBattleButtons = nil
            driver.DebindTestPetBattleAnswer = nil
            if not InCombatLockdown() then
                DebindPrivate.SeedPetBattle()
            end
        end)

        InsertAction({ type = Constants.ACTIONBUTTON, value = "ACTIONBUTTON4", key = KEY })
        ApplyBindings()
        DebindPrivate.StampPetBattleButtons()

        -- The ability buttons exist only once this session has had a battle.
        local bottom = PetBattleFrame.BottomFrame
        local ability = bottom.abilityButtons or {}
        local frames = { ability[1], ability[2], ability[3], bottom.SwitchPetButton, bottom.CatchButton }
        local clickFrame = DebindPrivate.DefaultClickFrame
        local names
        driver.DebindTestPetBattleButtons = function(_, ...)
            names = { ... }
        end
        SecureHandlerExecute(driver, [[self:CallMethod("DebindTestPetBattleButtons", PetBattleButtons[1],
            PetBattleButtons[2], PetBattleButtons[3], PetBattleButtons[4], PetBattleButtons[5])]])
        if not names then
            return Fail(NAME, "the restricted environment answered nothing for PetBattleButtons")
        end
        local stamped = 0
        for n = 1, 5 do
            if frames[n] then
                local name = names[n]
                if not name or clickFrame:GetAttribute("*type-" .. name) ~= "click"
                        or clickFrame:GetAttribute("*clickbutton-" .. name) ~= frames[n] then
                    return Fail(NAME, format("pet battle button %d is not on the click frame (name %s)", n, tostring(name)))
                end
                stamped = stamped + 1
            end
        end

        local binding = GetKeyBindingsWithoutTwins(KEY)
        binding = binding and binding[1]
        local button = DebindPrivate.ClickTimeKeys and DebindPrivate.ClickTimeKeys[KEY]
        if not binding or not binding.clickbutton or not button then
            return Fail(NAME, "ACTIONBUTTON4 has no button on its key")
        end

        -- **The name the press answers with**, which `EvalClickTimeKey` drops: a press that cancels
        -- and one that names the switch button leave the same attributes behind.
        local answer
        driver.DebindTestPetBattleAnswer = function(_, name, switch)
            answer = { name = name, switch = switch }
        end
        local function Answer()
            answer = nil
            SecureHandlerExecute(driver, format([[
                local name = self:RunAttribute("EvalClickTimeKey", %q)
                self:CallMethod("DebindTestPetBattleAnswer", name, PetBattleButtons[4])
            ]], button))
            return answer
        end

        SecureHandlerExecute(driver, [[self:RunAttribute("SetPetBattle", true)]])
        local inBattle = Answer()
        if not inBattle or not inBattle.switch or inBattle.name ~= inBattle.switch then
            return Fail(NAME, format("in a pushed battle the press answered %s, the switch button is %s",
                tostring(inBattle and inBattle.name), tostring(inBattle and inBattle.switch)))
        end

        SecureHandlerExecute(driver, [[self:RunAttribute("SetPetBattle", false)]])
        local outOfBattle = Answer()
        if not outOfBattle or outOfBattle.name ~= binding.clickbutton then
            return Fail(NAME, format("out of the battle the press answered %s, its own button is %s",
                tostring(outOfBattle and outOfBattle.name), tostring(binding.clickbutton)))
        end

        return Pass(NAME, format("%d battle buttons stamped, and the pushed battle sent the press to the switch button", stamped))
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

        SetMockState("combat", false)
        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if #probeReports == 0 then
            return Fail(NAME, "the rebaked wrapper reported nothing, so it did not run")
        end
        if LastWinner() ~= nil then
            return Fail(NAME, format("at peace and #%d fired after the rebake", LastWinner()))
        end

        SetMockState("combat", true)
        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if WaitForWinner() == nil then
            return Fail(NAME, "the condition does not take after the rebake")
        end

        return Pass(NAME, "judging is unchanged with the probes on")
    end,
})

-- The condition rides the unit column (`t.units["unitframe"]`) instead of its own pair of record
-- fields. What that has to keep doing is decide the press: a hover-conditioned keyboard key fires
-- only while the cursor is on a matching frame.
RegisterTest("Hover condition decides the press through the unit column", {
    description = "The hover condition still decides the press now that it lives in the unit column",
    run = function()
        local NAME = "Hover ownership"
        local KEY = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { unitframe = { reaction = Constants.REACTION_HELP } },
        })
        ApplyBindings()

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        -- Registering a frame can leave a rebuild queued behind it, and that one lands a frame
        -- later. Everything else on this path has already happened.
        WaitForIdle()

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format(
                "#%d fired before any hover. the hover condition may have been left out of the emission", LastWinner()))
        end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("hover=%s after entering, it should be player", tostring(GetHoverUnit())))
        end

        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        local hovering = WaitForWinner()
        if hovering == nil then
            return Fail(NAME, "put on a friendly frame and nothing fired. t.units[\"unitframe\"] did not match")
        end

        HoverLeave(frame)
        WaitForHoverSlot(false)

        ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if LastWinner() ~= nil then
            return Fail(NAME, format("#%d still fired after leave", LastWinner()))
        end

        return Pass(NAME, format("hover -> #%d, leave -> nothing", hovering))
    end,
})

-- `frameTypes` is stored as an axis of the pointed frame's unit condition and still reaches the
-- restricted side as a record field of its own, carrying its own "is there a frame at all" guard.
-- What this pins is that the guard narrows: a frame of the wrong kind must not fire the key.
RegisterTest("Hover frame types still narrow on their own", {
    description = "A frame type limit narrows even while carrying its own existence check",
    run = function()
        local NAME = "Hover frame types"
        local KEY = "CTRL-SHIFT-F7"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "rebake failed: " .. tostring(probesErr))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { unitframe = { frameTypes = Constants.FRAMETYPE_BOSS } },
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

        local ran, rerr = EvalClickTimeKey(KEY)
        if not ran then return Fail(NAME, rerr) end
        if #probeReports == 0 then
            return Fail(NAME, "the press reported nothing, so nothing below was judged")
        end
        if LastWinner() ~= nil then
            return Fail(NAME, format(
                "limited to boss and #%d fired on a group frame. frameTypes did not take", LastWinner()))
        end

        return Pass(NAME, "does not fire where the type fails to match")
    end,
})
