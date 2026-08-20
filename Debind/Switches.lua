-- TODO
-- Move whatever belongs to switches over here where it can go. The definitions are **not** here:
-- `ResolveSwitchDefinition` reads them out of the profile and lives with it (`Profile.lua`), and
-- this file cannot hold it anyway - it builds a secure frame when it is read, so the headless
-- runner does not load it (`tests/run.lua`) and two of that function's callers are specs.
local _, DebindPrivate             = ...;

-- **The global name stays `DebindStates`.** A user types it in a macro body
-- (`/click DebindStates $state1-on`, `Misc.lua`) and `Legacy.lua` rewrites pre-rename bodies to
-- it, so it is a name that is already out there rather than one this file is free to pick.
local SwitchesUpdaterFrame         = CreateFrame("Button", "DebindStates", nil, "SecureFrameTemplate,SecureHandlerClickTemplate,SecureHandlerAttributeTemplate");
DebindPrivate.SwitchesUpdaterFrame = SwitchesUpdaterFrame;

SecureHandlerSetFrameRef(SwitchesUpdaterFrame, "debind_driver", DebindPrivate.BindingDriver);
SecureHandlerExecute(SwitchesUpdaterFrame, [=[
    debind_driver = self:GetFrameRef("debind_driver")
]=]);

-- **번호는 이름의 약칭일 뿐이다.** 사용자가 매크로에 `/click DebindStates 3`이라고 칠 수 있어서
-- 숫자를 `$state3`으로 편다. 다섯이라는 개수를 아는 것은 아니고 알 필요도 없다 - 이름을
-- 모르는 스위치에 `SetSwitch`를 하면 `States`에 값이 앉고, 그것을 조건으로 건 바인딩은
-- `States[name] ~= v`에서 어긋나 안 나간다.
SwitchesUpdaterFrame:SetAttribute("_onattributechanged", [==[
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
]==]);


-- TODO validate the switch name.
SwitchesUpdaterFrame:SetAttribute("_onclick", [==[
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
]==]);
