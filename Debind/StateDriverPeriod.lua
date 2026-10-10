local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

--[[
    **The period of Blizzard's state driver manager**, which is the tail-key beat's period
    (`zeroing-the-beat-period-where-it-is-needed.md` §3, §4).

    The `updatetime` attribute is shared with every addon and only moves a local in
    `SecureStateDriver.lua`. **The reader's period reaches it through a rebuild alone**: a slider
    writing it by itself would part the period from the bodies a rebuild bakes for that period. The
    one other write is a 0 put back over somebody else's period while ours stands (`Revert`).

    **Whatever we put on comes off to 0.2**, Blizzard's default, unless the reader chose another
    non-zero period (owner, 2026-10-11). Nothing remembers what was there before: none of 66 addons
    searched writes `updatetime`, so what was there is 0.2 in practice.

    **0 is more than a period.** While a 0 of ours stands, the manager carries no events and a
    foreign period is put back to 0; both come undone when it comes off.
]]

local StateDriverPeriod = {};
DebindPrivate.StateDriverPeriod = StateDriverPeriod;

local DEFAULT = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;

local manager = SecureStateDriverManager;

--- **We made the period 0**, from the rebuild that wrote it to the one that takes it off. Not the
--- same as the period being 0: one another addon wrote is not ours to hold. `ZeroedByUs` is the
--- same answer on the restricted side, for the wrap.
local zeroedByUs = false;
--- The non-zero period a rebuild last wrote, nil where none stands.
local written = nil;
--- A foreign write the hook could not undo in a lockdown, owed at `PLAYER_REGEN_ENABLED`.
local revertPending = false;
local wrapped = false;
local hooked = false;

--- **The wrap's whole body.** An error here throws out of `CallRestrictedClosure` before the
--- handler under it runs, and with it the driver registration of whoever was setting an attribute
--- at that moment (`RestrictedExecution.lua`), so nothing else goes in. A nil write is let through:
--- the handler under it returns on a nil value first. The wrap cannot be taken off again, since
--- unwrapping takes the top one whoever put it there, so it asks `ZeroedByUs` on every write.
local HOLD_ZERO_SNIPPET = [[
if (ZeroedByUs and name == "updatetime" and value and value ~= 0) then
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

function StateDriverPeriod.ZeroedByUs()
    return zeroedByUs;
end

--- Whether the wrap went on in this session. It does not come off.
function StateDriverPeriod.Wrapped()
    return wrapped;
end

--- The period a rebuild writes, nil for none (§3). **Only where the beat runs**: with no beat,
--- nothing of ours waits on the manager. The default is not written either, since it is what
--- Blizzard set.
function StateDriverPeriod.Wanted(beats)
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
    if (not zeroedByUs or name ~= "updatetime" or not value or value == 0) then
        return;
    end
    if (Constants.DEBUG) then
        DebindPrivate.DisplayMessage(format("|cnRED_FONT_COLOR:updatetime set to %s by:|r %s",
            tostring(value), debugstack(2, 4, 0)));
    end
    if (InCombatLockdown()) then
        revertPending = true;
    else
        Revert();
    end
end

--- Blizzard's own, registered when `SecureStateDriver.lua` loads, ahead of every addon.
local BLIZZARD_EVENTS = {
    "MODIFIER_STATE_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORM", "UPDATE_STEALTH", "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PET",
    "GROUP_ROSTER_UPDATE",
};
StateDriverPeriod.BLIZZARD_EVENTS = BLIZZARD_EVENTS;
local isBlizzardEvent = {};
for _, event in ipairs(BLIZZARD_EVENTS) do
    isBlizzardEvent[event] = true;
end

--- **What addons have asked the manager to listen to** since this file loaded, ours included: event
--- to `true`, or to the units of a `RegisterUnitEvent`. The frame cannot be asked which events it
--- holds, so this is kept from the hooks below, and it is what goes back on when a 0 of ours comes
--- off. An addon loaded ahead of this one that registered there is not in it.
---
--- **Blizzard's are fixed, not kept** (owner, 2026-10-11): going back from 0 puts every one of
--- `BLIZZARD_EVENTS` back as Blizzard registered it, so an addon's call on one of those names --
--- narrowing it to a unit, or taking it off -- is not followed.
local asked = {};
--- True while this file registers or unregisters for 0, so its own calls leave `asked` alone.
local acting = false;

--- **An event on the manager does nothing at 0** but `timer = 0`, and the timer is spent on every
--- frame anyway, so all that is left of one is the call (§5-2). Whoever registers one while a 0 of
--- ours stands -- another addon loading, or one changing its settings -- has it taken off as it
--- lands, and put back with the rest when the 0 comes off. The methods are not protected, so this
--- works in a fight as well.
---
--- **Only through the frame's own methods.** A call through a method fetched off the metatable, or
--- one cached before these hooks went on, is not seen; nothing was found doing either.
---
--- A foreign period that lands in a fight runs with no event on the manager until `Revert` can
--- put 0 back, so every driver resolves on that period alone for the rest of the fight. Only a
--- snippet holding the manager can write it then, and none was found (§4).
local function OnRegister(_, event, ...)
    if (acting) then
        return;
    end
    -- **The last call wins**, which is what the client is believed to do: `RegisterUnitEvent` over a
    -- `RegisterEvent` narrows it to those units, and `RegisterEvent` over a unit one widens it
    -- again. Not measured. Were the client to merge them, going back from 0 would put on a narrower
    -- registration than there was.
    if (not isBlizzardEvent[event]) then
        asked[event] = select("#", ...) > 0 and { ... } or true;
    end
    if (zeroedByUs) then
        acting = true;
        manager:UnregisterEvent(event);
        acting = false;
        if (Constants.DEBUG) then
            DebindPrivate.DisplayMessage(format("|cnRED_FONT_COLOR:%s taken off the state driver, registered by:|r %s",
                tostring(event), debugstack(2, 4, 0)));
        end
    end
end

local function OnUnregister(_, event)
    if (not acting and not isBlizzardEvent[event]) then
        asked[event] = nil;
    end
end

local function OnUnregisterAll()
    if (not acting) then
        wipe(asked);
    end
end

--- **On at load rather than when 0 is written**, so `asked` holds what was registered before then.
--- **`RegisterAllEvents` is not watched**: what it registered is not put back when 0 comes off, and
--- one made while a 0 of ours stands is left on. An addon putting every event on the manager has no business
--- there worth keeping (owner, 2026-10-11).
hooksecurefunc(manager, "RegisterEvent", OnRegister);
hooksecurefunc(manager, "RegisterUnitEvent", OnRegister);
hooksecurefunc(manager, "UnregisterEvent", OnUnregister);
hooksecurefunc(manager, "UnregisterAllEvents", OnUnregisterAll);

--- **All of them, Blizzard's and every addon's.** Which addon had registered which cannot be asked
--- of the frame, so only the later ones are named in a DEBUG build.
---
--- **One registered ahead of the hooks is lost for good**: it is taken off here and is not in
--- `asked` to be put back. Only an addon loaded ahead of this one can have done that, and nothing
--- can be done for it (owner, 2026-10-11).
local function TakeEventsOff()
    acting = true;
    manager:UnregisterAllEvents();
    acting = false;
end

local function PutEventsBack()
    acting = true;
    for _, event in ipairs(BLIZZARD_EVENTS) do
        manager:RegisterEvent(event);
    end
    for event, units in pairs(asked) do
        if (units == true) then
            manager:RegisterEvent(event);
        else
            manager:RegisterUnitEvent(event, unpack(units));
        end
    end
    acting = false;
end

--- Writes the plan's period (§4). Called by every rebuild, out of a lockdown.
---
--- **Ours comes off to 0.2** once nothing wants it, unless somebody wrote over it: that period is
--- theirs and stays. Their write is not listened for, so a new period of ours goes over it.
function StateDriverPeriod.Apply(wanted)
    if (wanted == 0) then
        if (zeroedByUs) then
            return;
        end
        zeroedByUs = true;
        written = nil;
        SecureHandlerExecute(DebindPrivate.BindingDriver, "ZeroedByUs = true");
        manager:SetAttribute("updatetime", 0);
        if (not hooked) then
            hooked = true;
            manager:HookScript("OnAttributeChanged", OnManagerAttributeChanged);
        end
        TakeEventsOff();
        return;
    end

    if (zeroedByUs) then
        -- **The flag first**: the wrap would keep the period written next from landing. Where the
        -- wrap stopped a foreign 0.2, the attribute already reads 0.2 while the manager runs on 0,
        -- so this write is of the value already there; a wrapped `OnAttributeChanged` still runs on
        -- such a write ("Unchanged attribute writes still raise a wrapped handler" in the kit).
        zeroedByUs = false;
        revertPending = false;
        SecureHandlerExecute(DebindPrivate.BindingDriver, "ZeroedByUs = false");
        manager:SetAttribute("updatetime", wanted or DEFAULT);
        written = wanted;
        PutEventsBack();
    elseif (wanted) then
        if (wanted ~= written) then
            manager:SetAttribute("updatetime", wanted);
            written = wanted;
        end
    elseif (written ~= nil) then
        if (manager:GetAttribute("updatetime") == written) then
            manager:SetAttribute("updatetime", DEFAULT);
        end
        written = nil;
    end
end

--- What the hook could not do in a lockdown. A 0 of ours that came off in the meantime owes nothing.
function StateDriverPeriod.OutOfCombat()
    if (revertPending and zeroedByUs) then
        Revert();
    end
end
