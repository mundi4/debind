-- Probe_ActionBars.lua
-- One-shot probe and proof of concept for `.zzz/dropping-the-game-fallback.md` §4 and §5: pressing
-- an action bar button from the restricted environment through every kind of replaced bar
-- (vehicle, possession, override, temporary shapeshift, bonus bar) and through a pet battle.
-- Written to be carried once through all of them, so it records more than the question needs.
--
-- Three parts.
--
-- **The insecure view.** Sampled once a second and on the next frame after any action bar event:
-- the `Has...ActionBar` answers, every page index, the macro conditionals, which bars and buttons
-- are shown, the slot each button points at next to the slot §4 would compute, and what those
-- slots hold.
--
-- **The restricted view.** A header of our own measures the same state inside the restricted
-- environment and reports it through `CallMethod`: out of combat on every poll, in combat through a
-- state driver on the bar conditionals, and on every press of the button below. The two views are
-- stored side by side, so a function that answers differently in there shows up.
--
-- **The press.** `DebindDevABPButton` sits at the top of the screen and is built the way Debind's
-- `DefaultClickFrame` is (`Debind.lua`, `SecureBindings.lua`): a `SecureActionButtonTemplate`
-- registered for both edges, `OnClick` wrapped by the header, every route stamped as `*type-<name>`
-- from the insecure side, and the pre body returning the name to fire. The wrapper measures, picks
-- the button a Blizzard binding would pick (`OverrideActionBarButton1` while `OverrideActionBar` is
-- shown, `ActionButton1` otherwise), and returns the route the mouse button names:
--   LeftButton    `abpAB` / `abpOB`  `type=click` on that button
--   MiddleButton  `abpMacro`         `type=macro`, `/click <name> LeftButton true` then without
--   RightButton   `abpSlot`          `type=action` on the slot §4 computes, no button at all
--   Button4       `abpPB`            `type=click` on the first pet battle ability button
-- What changes per press (`*macrotext-abpMacro`, `*action-abpSlot`) is written by the pre body, the
-- way Debind bakes a winner's macro body at the click.
--
-- **A handle cannot be `clickbutton`.** `SetAttribute` in the restricted environment takes one,
-- but `SECURE_ACTIONS.click` gets the handle back and calls `HasAccessConstraints` on it, which a
-- handle does not have (`SecureTemplates.lua:564`, 2026-09-14). The frames are set insecurely.
--
-- `/abp bind [left|middle|right]` takes over the keys bound to `ACTIONBUTTON1` the way Debind
-- would, sending the chosen mouse button. While bound, a pet battle releases those keys on
-- `PET_BATTLE_OPENING_START` and takes them back on `PET_BATTLE_CLOSE`, or on leaving combat when
-- the close came in lockdown.
--
-- Every change prints the fields that moved and appends the whole sample, with the events that led
-- up to it, to `DebindDevDB.actionBarProbe`.
--
--   /abp                         print the current sample in full
--   /abp bind [left|middle|right]  take over the ACTIONBUTTON1 keys (default right)
--   /abp unbind                  give them back
--   /abp wipe                    drop the stored log
--
-- Answer found, delete the file and its TOC line.

local SAMPLE_PERIOD = 1;
local LOG_CAP = 2000;
local TAG = "|cff66ccff[ABP]|r ";

local AB = C_ActionBar;

local function Mark(value)
    if (value == nil) then
        return "-";
    end
    if (type(value) == "boolean") then
        return value and "T" or "F";
    end
    return tostring(value);
end

--- A function this build does not have answers "?" rather than raising.
local function Call(fn, ...)
    if (type(fn) ~= "function") then
        return "?";
    end
    return Mark((fn(...)));
end

local function Join(...)
    local parts = {};
    for i = 1, select("#", ...) do
        parts[i] = Mark((select(i, ...)));
    end
    return table.concat(parts, ":");
end

local function Shown(name)
    local frame = _G[name];
    if (not frame) then
        return "x";
    end
    return Join(frame:IsShown(), frame:IsVisible());
end

local function Attribute(name, attribute)
    local frame = _G[name];
    if (not frame) then
        return "x";
    end
    return Mark(frame:GetAttribute(attribute));
end

local function Condition(text)
    return SecureCmdOptionParse(text) and "T" or "F";
end

--- Whether a slot has an action, and `GetActionInfo`'s type, id and subtype.
local function Slot(slot)
    if (type(slot) ~= "number" or type(GetActionInfo) ~= "function") then
        return "-";
    end
    local kind, id, subType = GetActionInfo(slot);
    return Join(Call(AB.HasAction, slot), kind, id, subType);
end

--- The page §4 would pick, in `ActionBarController_UpdateAll`'s order. Pet battle is left out: that
--- branch never reads a page.
local function PredictedPage()
    if (AB.HasVehicleActionBar()) then
        return AB.GetVehicleBarIndex();
    elseif (AB.HasOverrideActionBar()) then
        return AB.GetOverrideBarIndex();
    elseif (AB.HasTempShapeshiftActionBar()) then
        return AB.GetTempShapeshiftBarIndex();
    elseif (AB.HasBonusActionBar() and AB.GetActionBarPage() == 1) then
        return AB.GetBonusBarIndex();
    end
    return AB.GetActionBarPage();
end

--- Shown, visible, the slot the button points at, "=" or "!" against the predicted slot, and what
--- the slot holds.
local function Button(name, index)
    local frame = _G[name .. index];
    if (not frame) then
        return "x";
    end
    local predicted = index + (PredictedPage() - 1) * 12;
    local match = frame.action == nil and "-" or (frame.action == predicted and "=" or "!");
    return Join(frame:IsShown(), frame:IsVisible(), frame.action, match) .. " " .. Slot(frame.action);
end

local function PetBattleButton(key, index)
    local bottom = PetBattleFrame and PetBattleFrame.BottomFrame;
    local frame = bottom and bottom[key];
    if (index and frame) then
        frame = frame[index];
    end
    if (not frame) then
        return "x";
    end
    return Join(frame:IsShown(), frame:IsVisible(), frame:GetID(), frame:IsEnabled());
end

-- State shared with the proof of concept below, declared here so the fields can read it.
local secureView = { poll = "-", state = "-", click = "-", extra = "-" };
local poc = { bound = false, route = "RightButton", keys = "", released = false, petRef = "-",
    closeLockdown = "-", bindError = "-" };

local FIELDS = {};

local function Add(name, fn)
    FIELDS[#FIELDS + 1] = { name, fn };
end

Add("combat", function() return Mark(InCombatLockdown() and true or false) end);
Add("cvar ActionButtonUseKeyDown", function() return Mark(GetCVar("ActionButtonUseKeyDown")) end);
Add("controllerState", function() return Call(ActionBarController_GetCurrentActionBarState) end);

Add("hasVehicle", function() return Call(AB.HasVehicleActionBar) end);
Add("hasOverride", function() return Call(AB.HasOverrideActionBar) end);
Add("hasTempShape", function() return Call(AB.HasTempShapeshiftActionBar) end);
Add("hasBonus", function() return Call(AB.HasBonusActionBar) end);
Add("bonusOffset", function() return Call(AB.GetBonusBarOffset) end);
Add("possessVisible", function() return Call(AB.IsPossessBarVisible) end);
Add("hasExtra", function() return Call(AB.HasExtraActionBar) end);
Add("petHasActionBar", function() return Call(PetHasActionBar) end);
Add("inPetBattle", function() return Call(C_PetBattles.IsInBattle) end);

Add("page", function() return Call(AB.GetActionBarPage) end);
Add("predictedPage", function() return Mark(PredictedPage()) end);
Add("vehicleIndex", function() return Call(AB.GetVehicleBarIndex) end);
Add("overrideIndex", function() return Call(AB.GetOverrideBarIndex) end);
Add("tempShapeIndex", function() return Call(AB.GetTempShapeshiftBarIndex) end);
Add("bonusIndex", function() return Call(AB.GetBonusBarIndex) end);
Add("extraIndex", function() return Call(AB.GetExtraBarIndex) end);
Add("multiCastIndex", function() return Call(AB.GetMultiCastBarIndex) end);

Add("vehicleSkin", function() return Call(UnitVehicleSkin, "player") end);
Add("overrideSkin", function() return Call(AB.GetOverrideBarSkin) end);
Add("inVehicle", function() return Call(UnitInVehicle, "player") end);
Add("vehicleUI", function() return Call(UnitHasVehicleUI, "player") end);
Add("vehiclePlayerFrameUI", function() return Call(UnitHasVehiclePlayerFrameUI, "player") end);
Add("controllingVehicle", function() return Call(UnitControllingVehicle, "player") end);
Add("vehicleSeats", function() return Call(UnitVehicleSeatCount, "player") end);
Add("canExitVehicle", function() return Call(CanExitVehicle) end);
Add("shapeshiftForm", function() return Join(Call(GetShapeshiftForm), Call(GetNumShapeshiftForms)) end);

Add("[vehicleui]", function() return Condition("[vehicleui]") end);
Add("[overridebar]", function() return Condition("[overridebar]") end);
Add("[possessbar]", function() return Condition("[possessbar]") end);
Add("[shapeshift]", function() return Condition("[shapeshift]") end);
Add("[bonusbar]", function() return Condition("[bonusbar]") end);
Add("[bonusbar:5]", function() return Condition("[bonusbar:5]") end);
Add("[canexitvehicle]", function() return Condition("[canexitvehicle]") end);
Add("[extrabar]", function() return Condition("[extrabar]") end);
Add("[petbattle]", function() return Condition("[petbattle]") end);

Add("MainActionBar.actionpage", function() return Attribute("MainActionBar", "actionpage") end);
Add("OverrideActionBar.actionpage", function() return Attribute("OverrideActionBar", "actionpage") end);

Add("MainActionBar", function() return Shown("MainActionBar") end);
Add("OverrideActionBar", function() return Shown("OverrideActionBar") end);
Add("PossessActionBar", function() return Shown("PossessActionBar") end);
Add("StanceBar", function() return Shown("StanceBar") end);
Add("PetActionBar", function() return Shown("PetActionBar") end);
Add("ExtraActionBarFrame", function() return Shown("ExtraActionBarFrame") end);
Add("MainMenuBarVehicleLeaveButton", function() return Shown("MainMenuBarVehicleLeaveButton") end);
Add("PetBattleFrame", function() return Shown("PetBattleFrame") end);

for i = 1, 12 do
    Add("ActionButton" .. i, function() return Button("ActionButton", i) end);
end
for i = 1, 6 do
    Add("OverrideActionBarButton" .. i, function() return Button("OverrideActionBarButton", i) end);
end
Add("ExtraActionButton1", function()
    local frame = ExtraActionButton1;
    if (not frame) then
        return "x";
    end
    return Join(frame:IsShown(), frame:IsVisible(), frame.action) .. " " .. Slot(frame.action);
end);

-- The predicted page read slot by slot, so a page whose buttons are hidden still says what a press
-- would fire.
for i = 1, 12 do
    Add("predictedSlot" .. i, function()
        local slot = i + (PredictedPage() - 1) * 12;
        return Mark(slot) .. " " .. Slot(slot);
    end);
end

for i = 1, (NUM_POSSESS_SLOTS or 2) do
    Add("PossessButton" .. i, function()
        local shown = Shown("PossessButton" .. i);
        if (type(GetPossessInfo) ~= "function") then
            return shown;
        end
        return shown .. " " .. Join(GetPossessInfo(i));
    end);
end

Add("PetBattle.activePet", function()
    if (not C_PetBattles.IsInBattle()) then
        return "-";
    end
    return Join(C_PetBattles.GetActivePet(Enum.BattlePetOwner.Ally),
        C_PetBattles.GetActivePet(Enum.BattlePetOwner.Enemy));
end);
for i = 1, 3 do
    Add("PetBattleAbility" .. i, function()
        local shown = PetBattleButton("abilityButtons", i);
        if (not C_PetBattles.IsInBattle()) then
            return shown;
        end
        local pet = C_PetBattles.GetActivePet(Enum.BattlePetOwner.Ally);
        return shown .. " " .. Join(C_PetBattles.GetAbilityInfo(Enum.BattlePetOwner.Ally, pet, i));
    end);
end
Add("PetBattleSwitch", function() return PetBattleButton("SwitchPetButton") end);
Add("PetBattleCatch", function() return PetBattleButton("CatchButton") end);

for i = 1, 5 do
    Add("key ACTIONBUTTON" .. i, function() return Join(GetBindingKey("ACTIONBUTTON" .. i)) end);
end

Add("secure.poll", function() return secureView.poll end);
Add("secure.state", function() return secureView.state end);
Add("secure.click", function() return secureView.click end);
Add("secure.extra", function() return secureView.extra end);
Add("poc.bound", function() return Join(poc.bound, poc.route, poc.keys, poc.bindError) end);
Add("poc.released", function() return Mark(poc.released) end);
Add("poc.petRef", function() return poc.petRef end);
Add("poc.closeLockdown", function() return poc.closeLockdown end);

--- A field that raises reads as its error, so one bad call does not cost the rest of the sample.
local function Sample()
    local sample = {};
    for i = 1, #FIELDS do
        local field = FIELDS[i];
        local ok, value = pcall(field[2]);
        sample[field[1]] = ok and value or ("ERR " .. tostring(value));
    end
    return sample;
end

local function Line(sample, only)
    local parts = {};
    for i = 1, #FIELDS do
        local name = FIELDS[i][1];
        if (not only or only[name]) then
            parts[#parts + 1] = name .. "=" .. sample[name];
        end
    end
    return table.concat(parts, "  ");
end

local last;
local pendingEvents = {};

--- One list, in the order things happened: full samples (`kind = "sample"`) and every line the
--- probe prints (`kind = "line"`), errors included. The log is read outside the game, so a line
--- that only reached the chat frame is a line nobody gets to read.
local function Append(entry)
    DebindDevDB = DebindDevDB or {};
    local log = DebindDevDB.actionBarProbe;
    if (not log) then
        log = {};
        DebindDevDB.actionBarProbe = log;
    end
    entry.at = date("%Y-%m-%d %H:%M:%S");
    entry.time = GetTime();
    log[#log + 1] = entry;
    while (#log > LOG_CAP) do
        table.remove(log, 1);
    end
end

local function Store(sample)
    sample.kind = "sample";
    sample.events = table.concat(pendingEvents, ", ");
    Append(sample);
end

local function Log(text)
    print(TAG .. text);
    Append({ kind = "line", text = text });
end

---------------------------------------------------------------------------------------------------
-- The restricted side
---------------------------------------------------------------------------------------------------

local header = CreateFrame("Frame", "DebindDevABPHeader", UIParent,
    "SecureHandlerBaseTemplate,SecureHandlerStateTemplate");

--- Measures and reports. The caller declares `h` (the header handle) and `source`. Leaves `target`,
--- `slot` and `petbattle` declared for whatever is spliced after it.
local MEASURE = [==[
    local ab1, ob1, mab, oab = h:GetFrameRef("ab1"), h:GetFrameRef("ob1"), h:GetFrameRef("mab"), h:GetFrameRef("oab")
    local which, page
    if (HasVehicleActionBar()) then
        which, page = "vehicle", GetVehicleBarIndex()
    elseif (HasOverrideActionBar()) then
        which, page = "override", GetOverrideBarIndex()
    elseif (HasTempShapeshiftActionBar()) then
        which, page = "tempshape", GetTempShapeshiftBarIndex()
    elseif (HasBonusActionBar() and GetActionBarPage() == 1) then
        which, page = "bonus", GetBonusBarIndex()
    else
        which, page = "page", GetActionBarPage()
    end
    local slot = 1 + (page - 1) * 12
    local slotType = GetActionInfo(slot)
    local target = ab1
    if (oab and oab:IsShown()) then
        target = ob1
    end
    local petbattle = SecureCmdOptionParse("[petbattle]") and true or false
    h:CallMethod("Report", source, which, page, slot, HasAction(slot) and true or false, slotType,
        GetActionBarPage(), GetBonusBarOffset(), HasExtraActionBar() and true or false, petbattle,
        ab1 and ab1:IsShown(), ab1 and ab1:IsVisible(), mab and mab:GetAttribute("actionpage"),
        ob1 and ob1:IsShown(), ob1 and ob1:IsVisible(), oab and oab:IsShown(),
        oab and oab:GetAttribute("actionpage"), target and target:GetName(),
        h:GetFrameRef("pb1") and true or false)
]==];

local POLL_BODY = "local h, source = self, 'poll'\n" .. MEASURE;

local STATE_BODY = "local h, source = self, 'state:' .. tostring(newstate)\n" .. MEASURE;

local PRESS_BODY = "local h, source = owner, 'click:' .. tostring(button) .. ':' .. tostring(down)\n"
    .. MEASURE .. [==[
    if (button == "LeftButton") then
        if (target == ob1) then
            return "abpOB"
        end
        return "abpAB"
    elseif (button == "MiddleButton") then
        local name = target:GetName()
        self:SetAttribute("*macrotext-abpMacro", "/click " .. name .. " LeftButton true\n/click " .. name .. " LeftButton")
        return "abpMacro"
    elseif (button == "RightButton") then
        -- `SECURE_ACTIONS.action` opens a flyout with `SpellFlyout:Toggle(self, ...)`, which calls
        -- `GetPopupDirection` on the firing button (`SpellFlyout.lua:260`). This one is a bare
        -- `SecureActionButtonTemplate` without it, so a flyout slot goes to the real bar button.
        if (slotType == "flyout") then
            if (target == ob1) then
                return "abpOB"
            end
            return "abpAB"
        end
        self:SetAttribute("*action-abpSlot", slot)
        return "abpSlot"
    elseif (button == "Button4" and petbattle) then
        return "abpPB"
    end
    return false
]==];

--- The second button: the extra action button, by the same three routes. Only while
--- `HasExtraActionBar()` is true, which is the check the `EXTRAACTIONBUTTON1` binding makes
--- (`ExtraActionBar.lua:63-66`). The slot is baked at login because `GetExtraBarIndex` is not in
--- the restricted environment.
local EXTRA_BODY = [==[
    local h, source = owner, 'extra:' .. tostring(button) .. ':' .. tostring(down)
    local ex1, exf = h:GetFrameRef("ex1"), h:GetFrameRef("exf")
    local has = HasExtraActionBar() and true or false
    local slot = self:GetAttribute("*action-abpEXSlot")
    local slotType = slot and GetActionInfo(slot)
    h:CallMethod("Report", source, has, SecureCmdOptionParse("[extrabar]") and true or false,
        exf and exf:IsShown(), exf and exf:IsVisible(), ex1 and ex1:IsShown(), ex1 and ex1:IsVisible(),
        slot, slot and HasAction(slot) and true or false, slotType)
    if (not has) then
        return false
    end
    if (button == "LeftButton") then
        return "abpEX"
    elseif (button == "MiddleButton") then
        return "abpEXMacro"
    elseif (button == "RightButton") then
        if (slotType == "flyout") then
            return "abpEX"
        end
        return "abpEXSlot"
    end
    return false
]==];

local button = CreateFrame("Button", "DebindDevABPButton", UIParent, "SecureActionButtonTemplate");
button:SetSize(90, 22);
button:SetPoint("TOP", UIParent, "TOP", 0, -2);
button:RegisterForClicks("AnyUp", "AnyDown");
button:SetAttribute("*type-abpAB", "click");
button:SetAttribute("*type-abpOB", "click");
button:SetAttribute("*type-abpPB", "click");
button:SetAttribute("*type-abpMacro", "macro");
button:SetAttribute("*type-abpSlot", "action");
do
    local background = button:CreateTexture(nil, "BACKGROUND");
    background:SetAllPoints();
    background:SetColorTexture(0.1, 0.3, 0.5, 0.8);
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    label:SetPoint("CENTER");
    label:SetText("ABP  L M R 4");
end

local extraButton = CreateFrame("Button", "DebindDevABPExtraButton", UIParent, "SecureActionButtonTemplate");
extraButton:SetSize(90, 22);
extraButton:SetPoint("LEFT", button, "RIGHT", 4, 0);
extraButton:RegisterForClicks("AnyUp", "AnyDown");
extraButton:SetAttribute("*type-abpEX", "click");
extraButton:SetAttribute("*type-abpEXMacro", "macro");
extraButton:SetAttribute("*macrotext-abpEXMacro",
    "/click ExtraActionButton1 LeftButton true\n/click ExtraActionButton1 LeftButton");
extraButton:SetAttribute("*type-abpEXSlot", "action");
do
    local background = extraButton:CreateTexture(nil, "BACKGROUND");
    background:SetAllPoints();
    background:SetColorTexture(0.5, 0.3, 0.1, 0.8);
    local label = extraButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    label:SetPoint("CENTER");
    label:SetText("EXTRA  L M R");
end

--- Blizzard's buttons reach the header at login: `DebindDev` loads ahead of Debind but after the
--- interface's own addons, so every frame named here exists by then.
local function SetRefs()
    local refs = { ab1 = "ActionButton1", ob1 = "OverrideActionBarButton1", mab = "MainActionBar",
        oab = "OverrideActionBar", ex1 = "ExtraActionButton1", exf = "ExtraActionBarFrame" };
    for label, name in pairs(refs) do
        local frame = _G[name];
        if (frame) then
            local ok, err = pcall(SecureHandlerSetFrameRef, header, label, frame);
            if (not ok) then
                Log("SetFrameRef " .. name .. " failed: " .. tostring(err));
            end
        else
            Log("no frame " .. name);
        end
    end
    button:SetAttribute("*clickbutton-abpAB", ActionButton1);
    button:SetAttribute("*clickbutton-abpOB", OverrideActionBarButton1);
    extraButton:SetAttribute("*clickbutton-abpEX", ExtraActionButton1);
    extraButton:SetAttribute("*action-abpEXSlot", 1 + (C_ActionBar.GetExtraBarIndex() - 1) * 12);
end

local Tick;
local scheduled = false;

local function Schedule(reason)
    if (reason) then
        pendingEvents[#pendingEvents + 1] = reason;
    end
    if (not scheduled) then
        scheduled = true;
        C_Timer.After(0, function()
            scheduled = false;
            Tick();
        end);
    end
end

function header:Report(source, ...)
    local kind = source:match("^(%a+)") or source;
    secureView[kind] = source .. " " .. Join(...);
    -- A press is logged every time. Two presses in the same state report the same thing, and the
    -- change-only sample would say nothing for the second.
    if (kind == "click" or kind == "extra") then
        Log("wrapper " .. secureView[kind]);
    end
    if (kind ~= "poll") then
        Schedule("secure " .. source);
    end
end

--- Each stage a press goes through after the wrapper, so a press that does nothing shows where it
--- stopped: our button finishing its click, the Blizzard button it handed to finishing its own, and
--- what finally fired.
local function HookPress()
    button:HookScript("PostClick", function(_, mouseButton, down)
        Log("probe button PostClick " .. Join(mouseButton, down,
            button:GetAttribute("*action-abpSlot"), button:GetAttribute("*macrotext-abpMacro")));
    end);
    for _, name in ipairs({ "ActionButton1", "OverrideActionBarButton1", "ExtraActionButton1" }) do
        local frame = _G[name];
        if (frame) then
            frame:HookScript("PostClick", function(_, mouseButton, down)
                Log(name .. " PostClick " .. Join(mouseButton, down, frame.action) .. " "
                    .. Slot(frame.action));
            end);
        end
    end
    hooksecurefunc("UseAction", function(slot, unit, mouseButton, isKeyPress)
        Log("UseAction " .. Join(slot, unit, mouseButton, isKeyPress) .. " " .. Slot(slot));
    end);
    -- A pet ability goes out through these and never through `UseAction`, so without them a pet
    -- battle press leaves no trace of whether it fired.
    for _, name in ipairs({ "UseAbility", "UseTrap", "ChangePet", "SkipTurn" }) do
        hooksecurefunc(C_PetBattles, name, function(...)
            Log("C_PetBattles." .. name .. " " .. Join(...));
        end);
    end
    hooksecurefunc(C_Macro, "RunMacroText", function(text, mouseButton)
        Log("RunMacroText " .. Join(mouseButton) .. " " .. (tostring(text):gsub("\n", " | ")));
    end);

    -- Errors go in the same list, whoever raised them, so a press that failed reads as a failure in
    -- the log and not as a press that did nothing. The handler that was there still gets them.
    local previous = geterrorhandler();
    seterrorhandler(function(message, ...)
        pcall(Log, "error " .. tostring(message));
        return previous(message, ...);
    end);
end

---------------------------------------------------------------------------------------------------
-- Taking the ACTIONBUTTON1 keys, and letting them go for a pet battle
---------------------------------------------------------------------------------------------------

local ROUTES = { left = "LeftButton", middle = "MiddleButton", right = "RightButton" };

local function BindKeys()
    ClearOverrideBindings(button);
    local keys = { GetBindingKey("ACTIONBUTTON1") };
    for i = 1, #keys do
        SetOverrideBindingClick(button, true, keys[i], button:GetName(), poc.route);
    end
    poc.keys = table.concat(keys, ",");
    poc.released = false;
end

local function ReleaseKeys()
    ClearOverrideBindings(button);
    poc.released = true;
end

local retakeOnRegen = false;

local events = CreateFrame("Frame");

local function OnPetBattleOpen()
    if (poc.bound) then
        if (InCombatLockdown()) then
            poc.bindError = "open in lockdown";
        else
            ReleaseKeys();
        end
    end
    -- The ability buttons are made by Blizzard's own handler for this event, which may run after
    -- this one. One frame later they are there either way.
    C_Timer.After(0, function()
        local bottom = PetBattleFrame and PetBattleFrame.BottomFrame;
        local first = bottom and bottom.abilityButtons and bottom.abilityButtons[1];
        if (not first) then
            poc.petRef = "no button";
        elseif (InCombatLockdown()) then
            poc.petRef = "lockdown";
        else
            local ok, err = pcall(SecureHandlerSetFrameRef, header, "pb1", first);
            poc.petRef = ok and "ok" or ("ERR " .. tostring(err));
            button:SetAttribute("*clickbutton-abpPB", first);
            -- Whether the Button4 route reaches the ability button at all, and whether it was
            -- enabled then: a disabled button swallows the click, which reads the same as a route
            -- that does not work.
            if (not first.abpHooked) then
                first.abpHooked = true;
                first:HookScript("PostClick", function(self, mouseButton, down)
                    Log("PetBattleAbility1 PostClick " .. Join(mouseButton, down, self:IsEnabled()));
                end);
            end
        end
        Schedule("petRef");
    end);
end

local function OnPetBattleClose()
    poc.closeLockdown = Mark(InCombatLockdown() and true or false);
    if (poc.bound) then
        if (InCombatLockdown()) then
            retakeOnRegen = true;
        else
            BindKeys();
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Sampling
---------------------------------------------------------------------------------------------------

function Tick()
    if (not InCombatLockdown()) then
        local ok, err = pcall(SecureHandlerExecute, header, POLL_BODY);
        if (not ok) then
            secureView.poll = "ERR " .. tostring(err);
        end
    end

    local sample = Sample();

    if (last == nil) then
        Log("start  " .. Line(sample));
        last = sample;
        Store(CopyTable(sample));
        wipe(pendingEvents);
        return;
    end

    local changed, was = {}, {};
    for i = 1, #FIELDS do
        local name = FIELDS[i][1];
        if (sample[name] ~= last[name]) then
            changed[name] = true;
            was[#was + 1] = name .. " was " .. last[name];
        end
    end
    if (#was == 0) then
        wipe(pendingEvents);
        return;
    end

    Log(format("[%s]  %s  (%s)", table.concat(pendingEvents, ", "), Line(sample, changed),
        table.concat(was, ", ")));
    last = sample;
    Store(CopyTable(sample));
    wipe(pendingEvents);
end

local EVENTS = {
    "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_POSSESS_BAR",
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_EXTRA_ACTIONBAR",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
    "VEHICLE_UPDATE",
    "PET_BATTLE_OPENING_START",
    "PET_BATTLE_OPENING_DONE",
    "PET_BATTLE_OVER",
    "PET_BATTLE_CLOSE",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "UPDATE_BINDINGS",
};

local function OnEvent(_, event, unit)
    if ((event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and unit ~= "player") then
        return;
    end
    if (event == "PET_BATTLE_OPENING_START") then
        OnPetBattleOpen();
    elseif (event == "PET_BATTLE_CLOSE") then
        OnPetBattleClose();
    elseif (event == "PLAYER_REGEN_ENABLED" and retakeOnRegen) then
        retakeOnRegen = false;
        BindKeys();
    end
    Schedule(event);
end

events:RegisterEvent("PLAYER_LOGIN");
events:SetScript("OnEvent", function(self, event)
    -- Not before login: `DebindDevDB` is replaced by the saved table on ADDON_LOADED, and anything
    -- stored ahead of that would go with the table it went into.
    if (event ~= "PLAYER_LOGIN") then
        return;
    end

    SetRefs();
    header:SetAttribute("_onstate-abp", STATE_BODY);
    RegisterStateDriver(header, "abp",
        "[petbattle]petbattle;[vehicleui]vehicleui;[overridebar]overridebar;[possessbar]possessbar;"
        .. "[shapeshift]shapeshift;[bonusbar]bonusbar;[extrabar]extrabar;[combat]combat;none");
    SecureHandlerWrapScript(button, "OnClick", header, PRESS_BODY);
    SecureHandlerWrapScript(extraButton, "OnClick", header, EXTRA_BODY);
    HookPress();

    for i = 1, #EVENTS do
        pcall(self.RegisterEvent, self, EVENTS[i]);
    end
    self:SetScript("OnEvent", OnEvent);

    local elapsed = 0;
    self:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta;
        if (elapsed < SAMPLE_PERIOD) then
            return;
        end
        elapsed = 0;
        Tick();
    end);
end);

SLASH_DEBINDABP1 = "/abp";
SlashCmdList.DEBINDABP = function(msg)
    local command, arg = strsplit(" ", strlower(strtrim(msg or "")), 2);
    if (command == "wipe") then
        if (DebindDevDB) then
            DebindDevDB.actionBarProbe = nil;
        end
        print(TAG .. "stored log dropped");
    elseif (command == "bind" or command == "unbind") then
        if (InCombatLockdown()) then
            print(TAG .. "not in combat");
            return;
        end
        if (command == "bind") then
            poc.route = ROUTES[arg or "right"] or "RightButton";
            poc.bound = true;
            poc.bindError = "-";
            BindKeys();
        else
            poc.bound = false;
            ClearOverrideBindings(button);
            poc.keys = "";
            poc.released = false;
        end
        Schedule("/abp " .. command);
    else
        Tick();
        print(TAG .. Line(Sample()));
    end
end;
