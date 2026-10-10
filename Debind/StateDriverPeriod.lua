local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

--[[
    **The period of Blizzard's state driver manager**, which is the tail-key beat's period
    (`zeroing-the-beat-period-where-it-is-needed.md` §3, §4).

    The `updatetime` attribute is shared with every addon and only moves a local in
    `SecureStateDriver.lua`. **The reader's period reaches it through a rebuild alone**: a slider
    writing it by itself would part the period from the bodies a rebuild bakes for that period. The
    one other write is a 0 put back over somebody else's period while 0 is held (`Revert`).

    **0 is held for the rest of the session once written** (owner, 2026-10-11). Nothing here puts
    the manager back from 0: a reload does, since the attribute is not saved and every addon sets
    its own period and events again on load. A reader moving off 0 is told to reload
    (`IsReloadRequired`).
]]

local StateDriverPeriod = {};
DebindPrivate.StateDriverPeriod = StateDriverPeriod;

local DEFAULT = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;

local manager = SecureStateDriverManager;

--- True from the rebuild that wrote 0 until the session ends.
local heldAtZero = false;
--- The non-zero period a rebuild last wrote, nil where none stands.
local written = nil;
--- What the attribute held before `written` first went on. nil was not a period: the manager
--- ignores a nil write, so putting nil back would leave ours in force.
local prior = nil;
--- A foreign write the hook could not undo in a lockdown, owed at `PLAYER_REGEN_ENABLED`.
local revertPending = false;
local wrapped = false;

--- **The wrap's whole body.** An error here throws out of `CallRestrictedClosure` before the
--- handler under it runs, and with it the driver registration of whoever was setting an attribute
--- at that moment (`RestrictedExecution.lua`), so nothing else goes in. A nil write is let through:
--- the handler under it returns on a nil value first.
local HOLD_ZERO_SNIPPET = [[
if (name == "updatetime" and value and value ~= 0) then
    return false
end
]];

--- The period the reader chose. A stored value outside the slider's range reads as the default,
--- which is "leave the manager alone".
function StateDriverPeriod.Chosen()
    local options = DebindPrivate.Options;
    local value = options and options.stateDriverPeriod;
    if (type(value) ~= "number" or value < 0 or value >= DEFAULT) then
        return DEFAULT;
    end
    return value;
end

function StateDriverPeriod.HeldAtZero()
    return heldAtZero;
end

--- The period a rebuild writes, nil for none (§3). **Only where the beat runs**: with no beat,
--- nothing of ours waits on the manager. The default is not written either, since it is what
--- Blizzard set.
function StateDriverPeriod.Wanted(beats)
    if (heldAtZero) then
        return 0;
    end
    local chosen = StateDriverPeriod.Chosen();
    if (beats and chosen < DEFAULT) then
        return chosen;
    end
    return nil;
end

--- Takes a foreign non-zero period back to 0 and wraps the manager's handler so it cannot land
--- again (§4). **Not wrapped up front** because nobody was found writing it (66 addons searched,
--- 2026-10-11), and a wrap enters the restricted environment on every driver anyone registers.
local function Revert()
    revertPending = false;
    manager:SetAttribute("updatetime", 0);
    if (not wrapped) then
        wrapped = true;
        SecureHandlerWrapScript(manager, "OnAttributeChanged", DebindPrivate.BindingDriver,
            HOLD_ZERO_SNIPPET);
    end
end

--- **Runs after Blizzard's handler**, so the foreign period is already in force when this sees it.
--- A write out of a lockdown is undone inside the same `SetAttribute` call, before any frame
--- passes. The manager is protected, so a write in a lockdown can only come from a snippet holding
--- it as a frame ref, and that one waits for the fight to end.
---
--- **After the wrap this may never run again**: the wrap swaps the script with `SetScript`, which
--- is believed to drop hooks. From then on the wrap's own body is what keeps 0.
local function OnManagerAttributeChanged(_, name, value)
    if (name ~= "updatetime" or not value or value == 0) then
        return;
    end
    if (Constants.DEBUG) then
        DebindPrivate.DisplayMessage(format("|cnRED_FONT_COLOR:updatetime set to %s by:|r %s",
            tostring(value), debugstack(3, 2, 0)));
    end
    if (InCombatLockdown()) then
        revertPending = true;
    else
        Revert();
    end
end

--- Writes the plan's period (§4). Called by every rebuild, out of a lockdown.
---
--- **A non-zero period puts back what was there**, once nothing wants it: the value before ours,
--- and 0.2 where that was nil. Somebody's write over ours is not listened for, but it is theirs:
--- it stays where nothing new is wanted, and it is what goes back where a new period goes over it.
function StateDriverPeriod.Apply(wanted)
    if (heldAtZero) then
        return;
    end
    if (wanted == 0) then
        heldAtZero = true;
        written, prior = nil, nil;
        manager:SetAttribute("updatetime", 0);
        manager:HookScript("OnAttributeChanged", OnManagerAttributeChanged);
    elseif (wanted) then
        local current = manager:GetAttribute("updatetime");
        if (written == nil or current ~= written) then
            prior = current;
        end
        if (wanted ~= written) then
            manager:SetAttribute("updatetime", wanted);
            written = wanted;
        end
    elseif (written ~= nil) then
        if (manager:GetAttribute("updatetime") == written) then
            manager:SetAttribute("updatetime", prior or DEFAULT);
        end
        written, prior = nil, nil;
    end
end

--- What the hook could not do in a lockdown.
function StateDriverPeriod.OutOfCombat()
    if (revertPending) then
        Revert();
    end
end
