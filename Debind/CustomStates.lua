---@diagnostic disable: redundant-parameter

-- TODO
-- CustomStates에 관련된 것들은 되도록 이쪽으로 분리할 것.
local _, DebindPrivate                 = ...;
local Constants                          = DebindPrivate.Constants;

local CustomStatesUpdaterFrame           = CreateFrame("Button", "DebindStates", nil, "SecureFrameTemplate,SecureHandlerClickTemplate,SecureHandlerAttributeTemplate");
DebindPrivate.CustomStatesUpdaterFrame = CustomStatesUpdaterFrame;

SecureHandlerSetFrameRef(CustomStatesUpdaterFrame, "debind_driver", DebindPrivate.BindingDriver);
SecureHandlerExecute(CustomStatesUpdaterFrame, [=[
    debind_driver = self:GetFrameRef("debind_driver")
]=]);

CustomStatesUpdaterFrame:SetAttribute("_onattributechanged", format([==[
    local num = tonumber(name)
    if (num) then
        name = "$state"..num
    end

    if (value == nil or value == "" or value == "toggle" or value == "TOGGLE") then
        debind_driver:RunAttribute("ToggleCustomState", name)
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

    debind_driver:RunAttribute("SetCustomState", name, value and true or false)
]==]), Constants.MAX_NUM_CUSTOM_STATES);


-- TODO validate the state name.
CustomStatesUpdaterFrame:SetAttribute("_onclick", format([==[
    local MAX_NUM_CUSTOM_STATES = %d
    
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
]==]), Constants.MAX_NUM_CUSTOM_STATES);

function DebindPrivate.GetCustomStateOptions(stateIndex)
    if (type(stateIndex) ~= "number") then
        stateIndex = Constants.CUSTOM_STATE_INDICES[stateIndex];
    end

    if (stateIndex <= Constants.MAX_NUM_CUSTOM_STATES) then
        return DebindPrivate.CustomStates[stateIndex];
    end
end
