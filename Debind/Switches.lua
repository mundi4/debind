---@diagnostic disable: redundant-parameter

-- TODO
-- Move whatever belongs to switches over here where it can go.
local _, DebindPrivate             = ...;
local Constants                    = DebindPrivate.Constants;

-- **The global name stays `DebindStates`.** A user types it in a macro body
-- (`/click DebindStates $state1-on`, `Misc.lua`) and `Legacy.lua` rewrites pre-rename bodies to
-- it, so it is a name that is already out there rather than one this file is free to pick.
local SwitchesUpdaterFrame         = CreateFrame("Button", "DebindStates", nil, "SecureFrameTemplate,SecureHandlerClickTemplate,SecureHandlerAttributeTemplate");
DebindPrivate.SwitchesUpdaterFrame = SwitchesUpdaterFrame;

SecureHandlerSetFrameRef(SwitchesUpdaterFrame, "debind_driver", DebindPrivate.BindingDriver);
SecureHandlerExecute(SwitchesUpdaterFrame, [=[
    debind_driver = self:GetFrameRef("debind_driver")
]=]);

SwitchesUpdaterFrame:SetAttribute("_onattributechanged", format([==[
    local num = tonumber(name)
    if (num) then
        name = "$state"..num
    end

    if (value == nil or value == "" or value == "toggle" or value == "TOGGLE") then
        debind_driver:RunAttribute("ToggleSwitch", name)
        return
    end

    if (
        value == "false" or
        value == "FALSE" or
        value == "f" or
        value == "F" or
        value == "off" or
        value == "OFF" or
        value == "0" or
        value == 0
    ) then
        value = false
    end

    debind_driver:RunAttribute("SetSwitch", name, value and true or false)
]==]), Constants.MAX_NUM_SWITCHES);


-- TODO validate the switch name.
SwitchesUpdaterFrame:SetAttribute("_onclick", format([==[
    local MAX_NUM_SWITCHES = %d
    
    local state, type = strsplit("-", button, 2)
    if (not type or type == "") then
        type = "toggle"
    end

    local num = tonumber(state)
    if (num) then
        state = "$state"..num
    end

    if (type and state and strsub(state, 1, 1) == "$") then
        if (type == "on") then
            self:SetAttribute(state, true)
        elseif (type == "off") then
            self:SetAttribute(state, false)
        elseif (type == "toggle") then
            self:SetAttribute(state, "toggle")
        end
    end
]==]), Constants.MAX_NUM_SWITCHES);

function DebindPrivate.GetSwitchOptions(stateIndex)
    if (type(stateIndex) ~= "number") then
        stateIndex = Constants.SWITCH_INDICES[stateIndex];
    end

    if (stateIndex <= Constants.MAX_NUM_SWITCHES) then
        return DebindPrivate.Switches[stateIndex];
    end
end
