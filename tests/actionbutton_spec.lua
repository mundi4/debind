-- The action button action: what a press on one fires, asked without the game
-- (`devdocs/dropping-the-game-fallback.md` §4). The page and slot tables are pure arithmetic over
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

    -- The bar buttons a flyout slot is handed to. Before the first rebuild, which is when the
    -- stamp looks them up.
    for _, name in ipairs({ "ActionButton3", "OverrideActionBarButton3", "MultiBarBottomLeftButton5",
        "ExtraActionButton1", "StanceButton3" }) do
        _G[name] = frames.newFrame("CheckButton", name, nil, "ActionBarButtonTemplate");
    end

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
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
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

    -- **A flyout slot goes to the real bar button** (§4-4): `type=action` would open the flyout on
    -- our button and fail on `GetPopupDirection`.
    test("a flyout slot is handed to the bar button that shows it", function()
        local state = interp.state;
        state.actions[3] = "flyout";
        local button = Press("F1");
        check(button, "nothing fired");
        check(clickFrame:GetAttribute("*type-" .. button) == "click",
            "type " .. tostring(clickFrame:GetAttribute("*type-" .. button)));
        check(clickFrame:GetAttribute("*clickbutton-" .. button) == _G.ActionButton3,
            "clicks " .. tostring(clickFrame:GetAttribute("*clickbutton-" .. button)));

        -- The skinned override bar shows its own buttons, on the override page.
        state.actions[3] = nil;
        state.overridebar = true;
        state.actions[207] = "flyout";
        _G.OverrideActionBar:Show();
        button = Press("F1");
        check(button and clickFrame:GetAttribute("*clickbutton-" .. button) == _G.OverrideActionBarButton3,
            "under the override bar it clicks "
            .. tostring(button and clickFrame:GetAttribute("*clickbutton-" .. button)));
        _G.OverrideActionBar:Hide();

        state.actions[207] = nil;
        state.actions[65] = "flyout";
        button = Press("F2");
        check(button and clickFrame:GetAttribute("*clickbutton-" .. button) == _G.MultiBarBottomLeftButton5,
            "the fixed bar clicks " .. tostring(button and clickFrame:GetAttribute("*clickbutton-" .. button)));
        interp:resetState();
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

    -- The pet and stance rows draw what their own bar shows, not a main bar slot.
    test("pet and stance rows take their icon from their own bar", function()
        local stanceIcon = _G.GetShapeshiftFormInfo;
        local petInfo = _G.GetPetActionInfo;
        _G.GetShapeshiftFormInfo = function(i) if (i == 3) then return 136116, false, true, 768; end end
        _G.GetPetActionInfo = function(i) if (i == 3) then return "PET_ACTION_ATTACK", "PET_ATTACK_TEXTURE", true; end end
        _G.PET_ATTACK_TEXTURE = "Interface\\Icons\\Ability_GhoulFrenzy";
        _G.BINDING_NAME_SHAPESHIFTBUTTON3 = "Special Action Button 3";
        _G.BINDING_NAME_BONUSACTIONBUTTON3 = "Secondary Action Button 3";

        local _, stance = DebindPrivate.DebindUI.NameAndIconForAction(
            { type = Constants.ACTIONBUTTON, value = "SHAPESHIFTBUTTON3" });
        local _, pet = DebindPrivate.DebindUI.NameAndIconForAction(
            { type = Constants.ACTIONBUTTON, value = "BONUSACTIONBUTTON3" });
        _G.GetShapeshiftFormInfo, _G.GetPetActionInfo = stanceIcon, petInfo;

        check(stance == 136116, "stance icon " .. tostring(stance));
        check(pet == "Interface\\Icons\\Ability_GhoulFrenzy", "pet icon " .. tostring(pet));
    end);

    -- The row says what the client's own keybinding panel says.
    test("the row is named with the client's binding name", function()
        _G.BINDING_NAME_ACTIONBUTTON3 = "Action Button 3";
        local name = DebindPrivate.DebindUI.NameAndIconForAction(
            { type = Constants.ACTIONBUTTON, value = "ACTIONBUTTON3" });
        check(name == "Action Button 3", "name " .. tostring(name));
    end);

    return T;
end
