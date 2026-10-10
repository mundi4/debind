-- The action button action: what a press on one fires, asked without the game
-- (`dropping-the-game-fallback.md` §4). The page and slot tables are pure arithmetic over
-- what the bar functions answer, so they come down here; that a slot really fires is the probe log.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    -- The eval hook is DEBUG-only.
    if (ctx and ctx.shipped) then
        return T;
    end

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    -- The stance button a stance action clicks. Before the first rebuild, which is when the stamp
    -- looks it up.
    _G.StanceButton3 = frames.newFrame("CheckButton", "StanceButton3", nil, "StanceButtonTemplate");

    -- The flyouts a slot can hold, in the book before the first rebuild, which is when their
    -- openers are made: one with a slot, one this character has not learned, and one a
    -- profession holds, past every skill line.
    shim.world.flyouts[66] = { name = "Call Pet", slots = { 883 } };
    shim.world.spells[883] = { name = "Call Pet 1" };
    shim.world.flyouts[67] = { name = "Unlearned", slots = { 884 }, known = false };
    shim.world.spells[884] = { name = "Unlearned 1" };
    shim.world.bookFlyouts = { 66, 67 };
    shim.world.flyouts[69] = { name = "Wormholes", slots = { 885 } };
    shim.world.spells[885] = { name = "Wormhole 1" };
    shim.world.professions = { { name = "Engineering", spells = { 886, { flyoutID = 69 } } } };

    local GUID = "Player-1-TESTGUID";
    local interp;
    local seq = 0;

    local function action(t)
        seq = seq + 1;
        t.type = Constants.ACTIONBUTTON;
        t.seq = seq;
        return t;
    end

    local function Bind(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = {
                account = { GENERAL = { [0] = actions } },
                [GUID] = { [Constants.PLAYER_CLASS] = {} },
            },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
        interp.state.actionBarPage = 1;
    end

    local clickFrame = DebindPrivate.DefaultClickFrame;

    --- The button a press ends at, and the slot written for it.
    local function Press(key)
        local _, button = interp:evalKey(key);
        if (not button) then
            return nil;
        end
        return button, clickFrame:GetAttribute("*action-" .. button);
    end

    Bind({
        action({ value = "ACTIONBUTTON3", key = "F1" }),
        action({ value = "MULTIACTIONBAR1BUTTON5", key = "F2" }),
        action({ value = "EXTRAACTIONBUTTON1", key = "F3" }),
        action({ value = "BONUSACTIONBUTTON3", key = "F4" }),
        action({ value = "SHAPESHIFTBUTTON3", key = "F5" }),
    });

    -- **The page is picked in `ActionBarController_UpdateAll`'s order** (§4-1), and a bonus bar
    -- only counts on page 1.
    test("the main bar button fires its slot on the page the bar controller would pick", function()
        local state = interp.state;
        local cases = {
            { "plain page 1", {}, 3 },
            { "page 2", { actionBarPage = 2 }, 15 },
            { "bonus bar on page 1", { bonusactionbar = true, bonusIndex = 7 }, 75 },
            { "bonus bar on page 2", { bonusactionbar = true, bonusIndex = 7, actionBarPage = 2 }, 15 },
            { "temporary shapeshift", { shapeshiftbar = true, bonusactionbar = true, bonusIndex = 7 }, 195 },
            { "override bar", { overridebar = true, shapeshiftbar = true }, 207 },
            { "vehicle bar", { vehiclebar = true, overridebar = true }, 183 },
        };
        for _, case in ipairs(cases) do
            interp:resetState();
            state.actionBarPage = 1;
            for k, v in pairs(case[2]) do
                state[k] = v;
            end
            local button, slot = Press("F1");
            check(button, case[1] .. ": nothing fired");
            check(clickFrame:GetAttribute("*type-" .. button) == "action",
                case[1] .. ": type " .. tostring(clickFrame:GetAttribute("*type-" .. button)));
            check(slot == case[3], case[1] .. ": slot " .. tostring(slot));
        end
        interp:resetState();
    end);

    -- **A fixed page bar does not follow a replaced bar** (§4-3): `MultiBarBottomLeft` is page 6.
    test("a fixed page bar fires the same slot whatever the main bar shows", function()
        local _, plain = Press("F2");
        interp.state.overridebar = true;
        local _, override = Press("F2");
        check(plain == 65, "plain: " .. tostring(plain));
        check(override == 65, "under an override bar: " .. tostring(override));
        interp:resetState();
    end);

    -- **The extra action button does nothing while there is none** (§4-2), the check the
    -- `EXTRAACTIONBUTTON1` binding makes, and its page is the one the rebuild asked for.
    test("the extra action button fires only while it is up", function()
        check(Press("F3") == nil, "a press fired with no extra action button");
        interp.state.extrabar = true;
        local _, slot = Press("F3");
        check(slot == 217, "slot " .. tostring(slot));
        interp:resetState();
    end);

    -- **The press does nothing rather than passing on** (§4-2): an action under the extra action
    -- button on the same key stays unfired, because the check runs after the winner is settled.
    test("a check that fails does not hand the press to the next action", function()
        Bind({
            action({ value = "EXTRAACTIONBUTTON1", key = "F6" }),
            action({ value = "ACTIONBUTTON3", key = "F6" }),
        });
        check(Press("F6") == nil, "the action under the extra action button fired");
        Bind({
            action({ value = "ACTIONBUTTON3", key = "F1" }),
            action({ value = "MULTIACTIONBAR1BUTTON5", key = "F2" }),
            action({ value = "EXTRAACTIONBUTTON1", key = "F3" }),
            action({ value = "BONUSACTIONBUTTON3", key = "F4" }),
            action({ value = "SHAPESHIFTBUTTON3", key = "F5" }),
        });
    end);

    -- **A flyout slot opens our own flyout** (`ACTION_SLOT_SNIPPET`): Blizzard's bar button shows
    -- nothing while a bar addon hides it, and `type=action` fails on `GetPopupDirection`.
    test("a flyout slot clicks the opener of the flyout it holds", function()
        local state = interp.state;
        local opener = DebindPrivate.GetFlyoutOpener(66);
        check(opener, "flyout 66 has no opener to compare with");
        local function Clicks(key)
            local button = Press(key);
            return button and clickFrame:GetAttribute("*type-" .. button) == "click"
                and clickFrame:GetAttribute("*clickbutton-" .. button) or nil;
        end

        state.actions[3] = { "flyout", 66 };
        local main = Clicks("F1");
        check(main == opener, "the main bar clicks " .. tostring(main));

        -- On the override page, where the main bar's slot moves to.
        state.actions[3] = nil;
        state.overridebar = true;
        state.actions[207] = { "flyout", 66 };
        local override = Clicks("F1");
        check(override == opener, "under an override bar it clicks " .. tostring(override));

        state.actions[207] = nil;
        state.overridebar = false;
        state.actions[65] = { "flyout", 66 };
        local fixed = Clicks("F2");
        check(fixed == opener, "the fixed bar clicks " .. tostring(fixed));

        state.actions[65] = { "flyout", 69 };
        local profession = Clicks("F2");
        check(profession and profession == DebindPrivate.GetFlyoutOpener(69),
            "a profession's flyout clicks " .. tostring(profession));

        -- A flyout not learned, and one the book does not hold, open nothing, as
        -- `SpellFlyout:Toggle` does.
        state.actions[65] = nil;
        state.actions[3] = { "flyout", 67 };
        check(Press("F1") == nil, "an unlearned flyout fired");
        state.actions[3] = { "flyout", 68 };
        check(Press("F1") == nil, "a flyout outside the book fired");
        interp:resetState();
    end);

    -- **A flyout whose slots change carries the new ones** (`RebuildFlyout`). What did not change
    -- is not written again, so this is the case that still has to be: a slot that moved, one that
    -- came, and one that went.
    test("a flyout rebuilt after its slots change carries the new spells", function()
        local opener = DebindPrivate.GetFlyoutOpener(66);
        check(opener, "flyout 66 has no opener");
        local holder;
        for _, entry in ipairs(frames.recorder.entries) do
            if (entry.kind == "SetFrameRef" and entry.frame == opener and entry.name == "holder") then
                holder = entry.ref;
            end
        end
        check(holder, "the opener was never handed its holder");
        local function Casts()
            local out, n = {}, 0;
            for _, child in ipairs({ holder:GetChildren() }) do
                if (child:GetAttribute("type") == "spell") then
                    n = n + 1;
                    out[n] = child:IsShown() and child:GetAttribute("spell") or false;
                end
            end
            return table.concat({ tostring(out[1] or false), tostring(out[2] or false),
                tostring(out[3] or false) }, ",");
        end
        local function Expected()
            local slots = DebindPrivate.GetFlyoutCastableSlots(66);
            return table.concat({ tostring(slots[1] and slots[1].cast or false),
                tostring(slots[2] and slots[2].cast or false),
                tostring(slots[3] and slots[3].cast or false) }, ",");
        end
        local function SpellsChanged()
            check(frames.fireEvent("SPELLS_CHANGED") > 0, "nothing is listening for SPELLS_CHANGED");
        end

        local first = Casts();
        check(first == Expected(), "at first " .. first);

        shim.world.spells[887] = { name = "Call Pet 2" };
        shim.world.flyouts[66].slots = { 887, 883 };
        SpellsChanged();
        local grown = Casts();
        check(grown == Expected() and grown ~= first, "after a slot came " .. grown);

        shim.world.flyouts[66].slots = { 883 };
        SpellsChanged();
        local shrunk = Casts();
        check(shrunk == first, "after it went " .. shrunk);
    end);

    -- **The openers go out only while an action button action reaches a slot**, this rebuild's
    -- actions and not every one stamped earlier in the session.
    test("a rebuild with no action button action on a slot sends no flyout opener", function()
        local function SendsOpeners(actions)
            local mark = frames.mark();
            Bind(actions);
            for _, entry in ipairs(frames.since(mark)) do
                if (type(entry.body) == "string" and entry.body:find("FlyoutOpeners[", 1, true)) then
                    return true;
                end
            end
            return false;
        end
        check(SendsOpeners({ action({ value = "ACTIONBUTTON3", key = "F1" }) }),
            "a main bar button sent no opener");
        check(not SendsOpeners({ action({ value = "BONUSACTIONBUTTON3", key = "F4" }) }),
            "after it went, a pet bar button alone still sent openers");
        Bind({
            action({ value = "ACTIONBUTTON3", key = "F1" }),
            action({ value = "MULTIACTIONBAR1BUTTON5", key = "F2" }),
            action({ value = "EXTRAACTIONBUTTON1", key = "F3" }),
            action({ value = "BONUSACTIONBUTTON3", key = "F4" }),
            action({ value = "SHAPESHIFTBUTTON3", key = "F5" }),
        });
    end);

    -- **The pet bar's slot never moves, so nothing is worked out at the press** beyond the check the
    -- `BONUSACTIONBUTTONn` binding makes: `SECURE_ACTIONS.pet` is `CastPetAction(action, unit)`.
    test("a pet bar button casts its pet action, and only with a pet", function()
        check(Press("F4") == nil, "a press fired with no pet");
        shim.world.units = { pet = { id = "pet" } };
        local button = Press("F4");
        shim.world.units = {};
        check(button, "nothing fired with a pet");
        check(clickFrame:GetAttribute("*type-" .. button) == "pet",
            "type " .. tostring(clickFrame:GetAttribute("*type-" .. button)));
        check(clickFrame:GetAttribute("*action-" .. button) == 3,
            "action " .. tostring(clickFrame:GetAttribute("*action-" .. button)));
    end);

    -- **A stance button is pressed rather than cast** (§4 of the fallback document): its `OnClick` is
    -- `StanceBar:Select(n)`, which is `CastShapeshiftForm(n)`, the call the `SHAPESHIFTBUTTONn`
    -- binding makes. It aims at nothing, so it takes no target.
    test("a stance button clicks the stance bar's button", function()
        local button = Press("F5");
        check(button, "nothing fired");
        check(clickFrame:GetAttribute("*type-" .. button) == "click",
            "type " .. tostring(clickFrame:GetAttribute("*type-" .. button)));
        check(clickFrame:GetAttribute("*clickbutton-" .. button) == _G.StanceButton3,
            "clicks " .. tostring(clickFrame:GetAttribute("*clickbutton-" .. button)));

        check(not DebindPrivate.ActionTakesUnit({ type = Constants.ACTIONBUTTON, value = "SHAPESHIFTBUTTON3" }),
            "a stance button takes a target");
        check(DebindPrivate.ActionTakesUnit({ type = Constants.ACTIONBUTTON, value = "BONUSACTIONBUTTON3" }),
            "a pet bar button lost its target");
    end);

    -- The row says what the client's own keybinding panel says.
    test("the row is named with the client's binding name", function()
        _G.BINDING_NAME_ACTIONBUTTON3 = "Action Button 3";
        local name = DebindPrivate.DebindUI.NameAndIconForAction(
            { type = Constants.ACTIONBUTTON, value = "ACTIONBUTTON3" });
        check(name == "Action Button 3", "name " .. tostring(name));
    end);

    -- **In a pet battle the main bar's buttons press the battle's** (2026-10-10, owner), the turn
    -- the binding's own `ActionButtonDown` takes there. The battle reaches the press through its
    -- events, as in the game, and so do the buttons.
    local function InPetBattle()
        Bind({
            action({ value = "ACTIONBUTTON1", key = "F1" }),
            action({ value = "ACTIONBUTTON3", key = "F3" }),
            action({ value = "ACTIONBUTTON4", key = "F4" }),
            action({ value = "ACTIONBUTTON5", key = "F5" }),
            action({ value = "ACTIONBUTTON7", key = "F7" }),
            action({ value = "MULTIACTIONBAR1BUTTON5", key = "F2" }),
        });

        local function Event(event)
            local mark = frames.mark();
            check(frames.fireEvent(event) > 0, "nothing is listening for " .. event);
            frames.drainTimers();
            interp:replay(frames.since(mark));
        end
        local function Clicks(key)
            local button = Press(key);
            return button and clickFrame:GetAttribute("*type-" .. button) == "click"
                and clickFrame:GetAttribute("*clickbutton-" .. button) or nil;
        end

        -- A battle with no buttons to press, which is a client without the UI.
        Event("PET_BATTLE_OPENING_START");
        check(Press("F1") == nil, "a press in a battle with no buttons fired");
        Event("PET_BATTLE_CLOSE");

        local bottom = {
            abilityButtons = {},
            SwitchPetButton = frames.newFrame("CheckButton"),
            CatchButton = frames.newFrame("Button"),
        };
        for i = 1, 3 do
            bottom.abilityButtons[i] = frames.newFrame("CheckButton");
        end
        _G.PetBattleFrame = { BottomFrame = bottom };

        Event("PET_BATTLE_OPENING_START");
        check(Clicks("F1") == bottom.abilityButtons[1], "1 clicks " .. tostring(Clicks("F1")));
        check(Clicks("F3") == bottom.abilityButtons[3], "3 clicks " .. tostring(Clicks("F3")));
        check(Clicks("F4") == bottom.SwitchPetButton, "4 clicks " .. tostring(Clicks("F4")));
        check(Clicks("F5") == bottom.CatchButton, "5 clicks " .. tostring(Clicks("F5")));
        check(Press("F7") == nil, "7 fired in a battle");
        local _, fixed = Press("F2");
        check(fixed == 65, "a fixed page bar in a battle: slot " .. tostring(fixed));

        -- What was stamped is not the rebuild's to clear.
        Bind({
            action({ value = "ACTIONBUTTON1", key = "F1" }),
        });
        check(Clicks("F1") == bottom.abilityButtons[1], "after a rebuild 1 clicks " .. tostring(Clicks("F1")));

        Event("PET_BATTLE_CLOSE");
        local button, slot = Press("F1");
        check(button and clickFrame:GetAttribute("*type-" .. button) == "action" and slot == 1,
            "after the battle: " .. tostring(button and clickFrame:GetAttribute("*type-" .. button))
            .. " slot " .. tostring(slot));
    end

    -- **A login in a battle stamps what is already there** (`SeedPetBattle`): the switch and catch
    -- buttons come with the XML and do not wait for the event that brings the ability buttons.
    local function LoginInPetBattle()
        Bind({
            action({ value = "ACTIONBUTTON4", key = "F4" }),
        });
        local bottom = {
            SwitchPetButton = frames.newFrame("CheckButton"),
            CatchButton = frames.newFrame("Button"),
        };
        _G.PetBattleFrame = { BottomFrame = bottom };

        local parse = _G.SecureCmdOptionParse;
        _G.SecureCmdOptionParse = function(expr)
            if (expr == "[petbattle] 1") then
                return "1";
            end
            return parse(expr);
        end
        local mark = frames.mark();
        local ok, err = pcall(DebindPrivate.SeedPetBattle);
        _G.SecureCmdOptionParse = parse;
        check(ok, tostring(err));
        interp:replay(frames.since(mark));

        local button = Press("F4");
        check(button and clickFrame:GetAttribute("*clickbutton-" .. button) == bottom.SwitchPetButton,
            "4 clicks " .. tostring(button and clickFrame:GetAttribute("*clickbutton-" .. button)));

        mark = frames.mark();
        DebindPrivate.SeedPetBattle();
        interp:replay(frames.since(mark));
    end

    --- Cleared on a failure too, or the specs after these find a pet battle UI.
    local function WithPetBattleUI(fn)
        return function()
            local ok, err = pcall(fn);
            _G.PetBattleFrame = nil;
            if (not ok) then
                error(err, 0);
            end
        end
    end

    test("in a pet battle the main bar's buttons press the battle's", WithPetBattleUI(InPetBattle));
    test("a login in a pet battle stamps the buttons already there", WithPetBattleUI(LoginInPetBattle));

    return T;
end
