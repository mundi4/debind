-- The switches' runtime: the frame a key or a macro turns one with, and the report the restricted
-- side sends back when one moves. The definitions are **not** here: `ResolveSwitchDefinition`
-- reads them out of the profile and lives with it (`Profile.lua`).
local _, DebindPrivate             = ...;
local L                            = DebindPrivate.L;
local Constants                    = DebindPrivate.Constants;

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

local _changedSwitches = {};

--- The line a switch prints when it moves, and **the only place it is written**. A key, a macro
--- and the button on the Switches tab all turn the same switch, and a second copy of these two
--- tests would be a second answer to "does this print" for one of them.
---
--- **Whether it moved is the caller's to know.** The report coming back out of the restricted side
--- carries no such thing -- a rebuild pushes the stored values in and they are reported straight
--- back (`BuildSwitchesSnippet`) -- so the caller that can tell an echo from a change is the one
--- holding the value it moved from.
---
--- **Only a switch this character works by hand announces itself.** A computed one answers a
--- conditional, so its value moves with the world rather than with anything the user did, and
--- there is nobody to read the line. Which kind it is is the winning layer's answer
--- (`ResolveSwitchAnswer`) and not the account-wide definition's: a layer can override manual with
--- an expression and the other way round.
function DebindPrivate.AnnounceSwitchChange(name, value)
    if (not DebindPrivate.SwitchMessagesEnabled()) then
        return;
    end
    if (DebindPrivate.ResolveSwitchAnswer(name) ~= Constants.SWITCH_MODES.MANUAL) then
        return;
    end

    local valueText = value and L["SWITCH_CHANGED_MESSAGE_ON"] or L["SWITCH_CHANGED_MESSAGE_OFF"];
    DebindPrivate.DisplayMessage(format(L["SWITCH_CHANGED_MESSAGE"], name, valueText));
end

--- What the restricted side reported back, folded into the stored definitions.
---
--- **It walks what changed, not the five numbers.** A macro can name any switch
--- (`/click DebindSwitch $burst-on`, above), so names outside the five have always been able to
--- arrive here -- the number loop simply never looked at them.
---
--- **A name nothing defines is left alone rather than defined.** There is no row to write the
--- value into and making one here would be the load-time repair §9-3 of
--- `redesigning-custom-states.md` rules out. The switch still works for this session: the
--- value lives in the restricted environment's `States`, and what is missing is only the memory of
--- it across a reload.
---
--- **The remembered value goes on the character, the live one on the definition**, and both are
--- `SetSwitchValue`'s to write (`Profile.lua`). The definition is account-wide, and while the
--- memory sat there too "remember" meant "remember what the character who logged out last left"
--- (§5 of `redesigning-custom-states.md`). **Which of these reports becomes a memory is
--- decided there and not here**: a report carrying the value the definition already holds is a
--- reset this side pushed a moment ago coming back round, and it is the one that must not be
--- remembered (§4-9).
---
--- What is left here is what only this path knows: that the value came from outside, and whether
--- it moved the switch.
---
--- **What the line is worth saying about is a report that moved the switch**, and the switch's
--- value is what it moved from. Every rebuild pushes the stored values in and the restricted side
--- reports them straight back (`BuildSwitchesSnippet`), so without that test a login says one line
--- per switch -- the §4-9 echo again, from the side that prints rather than the side that
--- remembers.
---
--- **Nothing is broadcast any more.** `SWITCH_CHANGED` went on 2026-08-22. A listener on it
--- meant every switch value had to be right the moment it moved, and that reachability is what
--- kept a computed switch from being worked out lazily
--- (`trimming-the-restricted-hot-paths.md`). The Switches tab reads `GetSwitchValue`,
--- which `SetSwitchValue` above still fills in, so what it lost was a reason to redraw rather
--- than the value to draw.
local function SwitchesChangedCallback()
    for name, newValue in pairs(_changedSwitches) do
        if (DebindPrivate.ResolveSwitchDefinition(name)) then
            local moved = DebindPrivate.GetSwitchValue(name) ~= newValue;
            DebindPrivate.SetSwitchValue(name, newValue);

            if (moved) then
                DebindPrivate.AnnounceSwitchChange(name, newValue);
            end
        end
    end
    wipe(_changedSwitches);
end

function DebindPrivate.OnSwitchChanged(name, value)
    if (not next(_changedSwitches)) then
        C_Timer.After(0, SwitchesChangedCallback);
    end

    _changedSwitches[name] = value;
end
