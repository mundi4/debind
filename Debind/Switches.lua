-- TODO
-- Move whatever belongs to switches over here where it can go. The definitions are **not** here:
-- `ResolveSwitchDefinition` reads them out of the profile and lives with it (`Profile.lua`), and
-- this file cannot hold it anyway - it builds a secure frame when it is read, so the headless
-- runner does not load it (`tests/run.lua`) and two of that function's callers are specs.
local _, DebindPrivate             = ...;

-- **The global name is out there in stored macro bodies.** A user types it (`/click DebindSwitch
-- $state1-on`) and [Convert to macro text] writes it (`MacroText.lua`), so a new name means the
-- ladder rewriting every stored body, as `Migration.lua`'s `dbver <= 7` step did from
-- `DebindStates`. A line copied into the game's own macro window is out of the ladder's reach.
local SwitchesUpdaterFrame         = CreateFrame("Button", "DebindSwitch", nil, "SecureFrameTemplate,SecureHandlerClickTemplate,SecureHandlerAttributeTemplate");
DebindPrivate.SwitchesUpdaterFrame = SwitchesUpdaterFrame;

SecureHandlerSetFrameRef(SwitchesUpdaterFrame, "debind_driver", DebindPrivate.BindingDriver);
SecureHandlerExecute(SwitchesUpdaterFrame, [=[
    debind_driver = self:GetFrameRef("debind_driver")
]=]);

SwitchesUpdaterFrame:SetAttribute("_onattributechanged", [==[
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


-- **A number is a shorthand for a name.** A user can type `/click DebindSwitch 3` in a macro
-- body, so a numeric button becomes `$state3` here. This is the only door it comes through.
-- Everything that sets an attribute on this frame either passes the `$` guard below or is a
-- stored switch name (`*attribute-name-` in `UpdateBindings.lua`), so `_onattributechanged`
-- never sees a bare number.
--
-- **It does not know there are five, and does not need to.** A name nothing defines still lands
-- in `States` when `SetSwitch` runs, and nothing can be conditioned on it:
-- `GetUndefinedSwitchCondition` marks such an action and `Debind.lua` keeps it out of `KeyMap`,
-- so no record carrying that name is ever built.

-- TODO validate the switch name.
SwitchesUpdaterFrame:SetAttribute("_onclick", [==[
    local switch, type = strsplit("-", button, 2)
    if (not type or type == "") then
        type = "toggle"
    end

    local num = tonumber(switch)
    if (num) then
        switch = "$state"..num
    end

    if (type and switch and strsub(switch, 1, 1) == "$") then
        if (type == "on") then
            self:SetAttribute(switch, true)
        elseif (type == "off") then
            self:SetAttribute(switch, false)
        elseif (type == "toggle") then
            self:SetAttribute(switch, "toggle")
        end
    end
]==]);
