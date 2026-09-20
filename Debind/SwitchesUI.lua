local _, DebindPrivate = ...;

local Constants        = DebindPrivate.Constants;
local LLL              = DebindPrivate.L;
local DebindUI         = DebindPrivate.DebindUI;

--- What the counts in the row tooltip are pushed in by. **In code and not in the strings**: it is
--- layout, and a translator handed leading spaces will lose them or double them.
local INDENT            = "   ";

local ROW_HEIGHT        = 28;
--- A group heading. The height Overview's heading stands at, because it is the same bar.
local HEADER_ROW_HEIGHT = 26;
--- How far a row hangs in from the heading above it. Overview's `ORDER_LINE_INDENT`.
local ROW_INDENT        = 10;
--- The air above a heading, as an element of its own. Overview's `KEY_GROUP_GAP`.
local GROUP_GAP         = 8;
--- A row on the second face of the right column. Shorter than a switch row: these are read down
--- rather than acted on, and there can be a great many of them.
local USAGE_ROW_HEIGHT  = 20;

--- The root's own layer, which is `GetLayerID(nil, false)`. It is drawn like the overrides and
--- edited like them, and it is the one row that is always there and cannot be taken away (§4-6 of
--- `redesigning-custom-states.md`): the definition itself is that answer, which is why it
--- is the one layer `GetSwitchLayerKey` gives no key for.
local ROOT_LAYER_ID     = 1;

local TAB_SETTINGS      = 1;
local TAB_USAGE         = 2;

--- The two halves the list is drawn in, in the order they stand. **Both headings are drawn even
--- where one half is empty**: the two sit in the same place every time, and which half a switch is
--- in is read off where it stands rather than off a heading that comes and goes.
---
--- **The split is "does anything anywhere on the account name it"**, which is what a reader about
--- to delete one is asking. It was "is this switch in the compile" until now, and that is our own
--- optimisation talking: a switch only another specialization reads is not one the reader has
--- nothing to fix before deleting (`reworking-the-switches-tab.md`).
local GROUPS = {
    { header = "SWITCHES_GROUP_USED",   used = true },
    { header = "SWITCHES_GROUP_UNUSED", used = false },
};

--- The three answers one layer can give, in the order the radios stand in.
---
--- **"Says nothing" is one of them and not an empty row.** A layer that answers nothing is an
--- ordinary state with a row of its own behind it, holding the expression and the starting value
--- the reader typed, so picking another answer and coming back loses nothing
--- (`ClearSwitchOverride`).
local ANSWERS = {
    { key = "unset",  label = "SWITCH_ANSWER_UNSET",  desc = "SWITCH_ANSWER_UNSET_DESC" },
    { key = "manual", label = "SWITCH_ANSWER_MANUAL", desc = "SWITCH_ANSWER_MANUAL_DESC" },
    -- The expression's own words. The key kept its `CUSTOM_STATE_` name from when the settings
    -- menu on the portrait used it for the same choice, and that menu is gone (3c); the string is
    -- one rule, and a second key for it would be a second thing to translate that can then
    -- disagree inside one window.
    { key = "auto",   label = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL",
                      desc  = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC" },
};

--- What a hand-worked switch comes up as, in the order the radios stand in.
---
--- `remember` is an answer and not an absence: it means "come back the way this character left
--- it", which is `resetValue == nil`, and a table cannot hold a nil to compare against.
local START_VALUES = {
    { key = "on",       label = "SWITCH_ANSWER_ON",       desc = "SWITCH_ANSWER_ON_DESC" },
    { key = "off",      label = "SWITCH_ANSWER_OFF",      desc = "SWITCH_ANSWER_OFF_DESC" },
    { key = "remember", label = "SWITCH_ANSWER_REMEMBER", desc = "SWITCH_ANSWER_REMEMBER_DESC" },
};

--- Which of the three starting values a manual answer is.
local function StartValueFor(resetValue)
    if (resetValue == true) then
        return "on";
    end
    if (resetValue == false) then
        return "off";
    end
    return "remember";
end

--- Puts the words on a radio and stretches the button out over them.
---
--- **`UIRadioButtonTemplate`'s label is a FontString anchored outside the 16px button**, so without
--- this the words are dead to the mouse and only the circle can be hit. The client stretches the
--- hit rect over its own check labels with the same call (`Blizzard_Calendar.lua`). The 5 is the
--- gap the template anchors the label at.
---
--- **Called again whenever the words change**, because the rect is measured off them. The template
--- also hands the label `GameFontNormalSmall`, which is a dropdown row's font; these are rows of a
--- panel and take the panel's.
local function SetRadioText(radio, text)
    radio.text:SetFontObject(GameFontNormal);
    radio.text:SetText(text);
    radio:SetHitRectInsets(0, -radio.text:GetStringWidth() - 5, 0, 0);
end

--- Every layer the right column can be read and written at, the root first. **The root is in the
--- list**: it is a row the reader edits like the others, and leaving it out would put the
--- account-wide answer behind a different control from the ones that override it.
local function LayerChoices(out)
    out = out or {};
    out[1] = ROOT_LAYER_ID;
    local overridable = DebindPrivate.GetOverridableLayerIDs();
    for i = 1, #overridable do
        out[i + 1] = overridable[i];
    end
    return out;
end

--- Which layer is deciding this switch here, as a `layerID`.
---
--- **Worked out rather than stored**, because it moves without anything on screen changing: a
--- specialization change hands the same rows a different answer.
local function WinningLayerID(name)
    local _, _, _, winner = DebindPrivate.ResolveSwitchAnswer(name);
    if (not winner) then
        return ROOT_LAYER_ID;
    end
    local layerIDs = DebindPrivate.GetOverridableLayerIDs();
    for i = 1, #layerIDs do
        if (DebindPrivate.GetSwitchLayerKey(layerIDs[i]) == winner) then
            return layerIDs[i];
        end
    end
    return ROOT_LAYER_ID;
end

--- The classes and characters that name this switch somewhere this client cannot reach, by name,
--- sorted.
---
--- **A class row and a character row ask for different things.** A class layer is reachable from
--- any character of that class; a character's own layers need that character. So the two are named
--- and not counted: what the reader does about one is log in there.
---
--- **The names come from the profile and not from `GetLayerLabel`.** That one names only the
--- character who is logged in and spells every other one "character" -- it has nothing else to go
--- on, since a shared string carries no character name (`building-export-import.md` 3절). What is
--- in our own file does: `RefreshIdentity` writes `name` and `class` on every login.
local function UsageElsewhere(usage)
    local names = {};
    if (not usage) then
        return names;
    end
    for classKey in pairs(usage.classes) do
        names[#names + 1] = Constants.CLASS_NAMES[classKey] or classKey;
    end
    local characters = DebindPrivate.db.global.characters or {};
    for guid in pairs(usage.characters) do
        local entry = characters[guid];
        names[#names + 1] = entry and entry.name or guid;
    end
    sort(names);
    return names;
end

--- Is anything anywhere on the account naming this switch? `CollectSwitchUsage` files an entry only
--- for a name it found somewhere, so the entry existing is the whole answer.
local function IsUsed(usage, name)
    return usage[name] ~= nil;
end

--- Which switches are in the first half, as one value to compare against.
---
--- **Not a count.** One switch gaining a reference while another loses its last one leaves the
--- count where it was and moves two rows.
local function UsedSignature(usage, names)
    local parts = {};
    for _, name in ipairs(names) do
        if (IsUsed(usage, name)) then
            parts[#parts + 1] = name;
        end
    end
    return table.concat(parts, "\30");
end


--------------------------------------------------------------------------------
-- A switch's row
--------------------------------------------------------------------------------

DebindSwitchRowMixin = {};

function DebindSwitchRowMixin:Init(elementData)
    self.switchName = elementData.name;
    self.panel = elementData.panel;
    self:Update();
end

--- Draws the row from the definition. **Read fresh every time** rather than kept on the row: a
--- switch's value is changed by keys, by macros and by the expression loop, none of which come
--- through this panel.
---
--- **Nothing about the layers is on this row.** That is the right column's whole job since the tab
--- was split in two; what is left here is the switch itself, its name and what it is right now
--- where that can be measured.
---
--- `inCombat` arrives only from the regen dispatch, which is the one place the flag cannot answer
--- (`DebindSwitchesPanelMixin:OnEvent`). Nil means "ask".
function DebindSwitchRowMixin:Update(inCombat)
    local name = self.switchName;
    local definition = DebindPrivate.ResolveSwitchDefinition(name);
    if (not definition) then
        return;
    end

    -- **A switch worked out from its expression has no value to draw and no press to offer.** It
    -- is computed at a press and at no other moment (`COMPUTE_SWITCHES_SNIPPET`), so a value drawn
    -- here would read as what the switch is now, which nothing has measured since -- and the press
    -- cannot be offered either, since the next one overwrites it.
    local automatic = DebindPrivate.ResolveSwitchAnswer(name) == Constants.SWITCH_MODES.EXPR;
    local isOn = definition.value and true or false;

    self.ToggleButton:SetShown(not automatic);
    self.Status:SetShown(automatic);
    if (automatic) then
        self.Status:SetText(LLL["SWITCH_AUTOMATIC"]);
    end

    self.SelectedHighlight:SetShown(self.panel and self.panel.selectedName == name);

    -- **The `$` is shown, not stripped.** It is what the user has to type in a macro body, and
    -- this list is the only place they can read it off (§6-B).
    --
    -- **What it is sits beside the name, and what the button does is on the button.** The one
    -- label used to be both: it read "On" while the switch was on, in the place a label says what
    -- pressing will do. In one string rather than two font strings, so the state lands right
    -- after however long the name is, and a name too long for the row clips the pair together.
    if (automatic) then
        self.Name:SetText(name);
    else
        self.Name:SetText(name .. "  " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(
            isOn and LLL["CUSTOM_STATE_ON"] or LLL["CUSTOM_STATE_OFF"]));
        self.ToggleButton:SetText(isOn and LLL["SWITCH_TURN_OFF"] or LLL["SWITCH_TURN_ON"]);

        -- Out of reach until the fight ends, and that is the only reason left for a button that is
        -- drawn at all.
        if (inCombat == nil) then
            inCombat = InCombatLockdown();
        end
        self.ToggleButton:SetEnabled(not inCombat);
    end
    self.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB());
end

function DebindSwitchRowMixin:OnClick()
    if (self.panel) then
        self.panel:SelectSwitch(self.switchName);
    end
end

--- Turning it on or off by hand.
---
--- **Through `SetSwitchValue`, not by writing the field.** A switch set to come back the way it was
--- left keeps that answer on the character, so a toggle that only writes the definition holds until
--- the next load and then goes back to what the character remembers, which looks like the button
--- working and the switch forgetting.
function DebindSwitchRowMixin:OnToggleClick()
    local definition = DebindPrivate.ResolveSwitchDefinition(self.switchName);
    if (not definition) then
        return;
    end
    DebindPrivate.SetSwitchValue(self.switchName, not definition.value);
    DebindPrivate.UpdateBindings();
    self:Update();
end

function DebindSwitchRowMixin:OnToggleEnter()
    GameTooltip:SetOwner(self.ToggleButton, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.switchName);
    if (InCombatLockdown()) then
        GameTooltip_AddErrorLine(GameTooltip, LLL["SWITCH_TOGGLE_IN_COMBAT"]);
    else
        GameTooltip_AddInstructionLine(GameTooltip, LLL["SWITCH_TOGGLE_INSTRUCTION"]);
    end
    GameTooltip:Show();
end

--- What this switch is for, on the row itself.
---
--- **A summary and no further**, which is the whole reason the right column exists. The places
--- themselves are a list to work down and a tooltip goes away when the cursor does; what belongs
--- here is what a reader scanning the list wants before picking one -- how much of this character
--- it touches, and which other classes and characters they would have to log in to.
function DebindSwitchRowMixin:OnEnter()
    local mode, _, expr = DebindPrivate.ResolveSwitchAnswer(self.switchName);
    if (not mode) then
        return;
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.switchName);
    if (mode == Constants.SWITCH_MODES.EXPR) then
        GameTooltip_AddNormalLine(GameTooltip, expr or "");

        -- **The name, because the line above it is a row of conditions** and nothing in it looks
        -- any different once one of them stops meaning anything. It is the one reference to a
        -- switch that no action carries, so nothing else on screen goes red for it.
        local undefined = DebindPrivate.GetUndefinedSwitchInExpr(expr, self.switchName);
        if (undefined) then
            GameTooltip_AddErrorLine(GameTooltip,
                format(LLL["BINDING_ERROR_UNDEFINED_STATE"], undefined));
        end
    end

    local usage = self.panel and self.panel.usage and self.panel.usage[self.switchName];
    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    if (not usage) then
        GameTooltip_AddNormalLine(GameTooltip, LLL["SWITCH_USAGE_EMPTY"]);
        GameTooltip:Show();
        return;
    end

    -- **Label left, number right.** The two are a column to compare, and a number baked into the
    -- sentence lands wherever each translation happens to end. It also takes the specifier out of
    -- the locale string, so a translator is not holding one.
    GameTooltip_AddColoredDoubleLine(GameTooltip, LLL["SWITCH_USAGE_HERE"], #usage.here,
        NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR);
    GameTooltip_AddColoredDoubleLine(GameTooltip, LLL["SWITCH_USAGE_EXPRS"], #usage.exprs,
        NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR);

    -- **Names and not a number.** The reader cannot count their way to these: what they have to do
    -- about one is log in there, so the answer is which class and which character.
    local elsewhere = UsageElsewhere(usage);
    if (#elsewhere > 0) then
        GameTooltip_AddNormalLine(GameTooltip, LLL["SWITCH_USAGE_ELSEWHERE"]);
        for i = 1, #elsewhere do
            GameTooltip_AddHighlightLine(GameTooltip, INDENT .. elsewhere[i]);
        end
    end
    GameTooltip:Show();
end

function DebindSwitchRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- A row on the right column's second face
--------------------------------------------------------------------------------

DebindSwitchUsageRowMixin = {};

function DebindSwitchUsageRowMixin:Init(elementData)
    self.Name:SetText(elementData.text);
    self.Key:SetText(elementData.key or "");
    self.tooltip = elementData.tooltip;
end

--- **Only where the row was cut off.** These rows say nothing a tooltip could add, so the one
--- reason to open one is a name too long for the column.
function DebindSwitchUsageRowMixin:OnEnter()
    if (not self.Name:IsTruncated()) then
        return;
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.Name:GetText());
    GameTooltip:Show();
end

function DebindSwitchUsageRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- A group's heading
--------------------------------------------------------------------------------

DebindSwitchGroupHeaderMixin = {};

--- **The mouse comes off.** The template is a button and Overview's heading uses that, but there
--- is nothing under these words to pick: without this the bar lights up under the cursor and
--- offers a press that does nothing.
---
--- **White in both states**, for the reason Overview's heading is: the template greys the title
--- until the cursor is on it, and the cursor never reaches this one.
function DebindSwitchGroupHeaderMixin:OnLoad()
    self:SetTitleColor(false, HIGHLIGHT_FONT_COLOR);
    self:SetTitleColor(true, HIGHLIGHT_FONT_COLOR);

    self:GetNormalTexture():SetDesaturated(true);
    self:GetNormalTexture():SetAlpha(0.5);

    -- The fold the template hangs on every heading. Nothing here folds.
    self.CollapseButton:Hide();
    self:EnableMouse(false);
end

function DebindSwitchGroupHeaderMixin:Init(elementData)
    self:SetHeaderText(LLL[elementData.header]);
end


--------------------------------------------------------------------------------
-- Making a switch
--------------------------------------------------------------------------------

--- Asking for a name and making the switch. `onCreated` is handed the name, and is not called
--- when nothing was made.
---
--- **The name handed over is the one `CreateSwitch` filed, not the one that was typed.** The
--- case is folded on the way in, and the two callers that pass an `onCreated` write the name
--- straight onto an action - a condition key, an on/off/toggle target. Given the typed
--- spelling, `$Burst` would go on an action that nothing defines a switch for, so the row goes
--- red and stops binding at all (`GetUndefinedSwitch`) while the list shows `$burst` made and
--- well.
---
--- **Three places open this box**: the button under this list, the condition menu, and an
--- on/off/toggle action's own menu (`DropDownMenus.lua`). That is the whole point of stage
--- 3c: making a switch belongs wherever the reader turns out to need one, not on a trip to a
--- tab they have to know about first (§6-2 of `redesigning-custom-states.md`).
---
--- **Renaming is not one of these any more.** It is the field at the top of the right column, and
--- a dialog asking for a name the panel is already showing is a second place to read it.
function DebindUI.ShowNewSwitchBox(onCreated)
    DebindUI.ShowInputBox({
        text = LLL["SWITCH_CREATE_PROMPT"],
        callback = function(value)
            -- The second answer is the name it was filed under, or the locale key it refused
            -- with.
            local ok, answer = DebindPrivate.CreateSwitch("$" .. strtrim(value));
            if (not ok) then
                if (answer) then
                    DebindPrivate.DisplayMessage(LLL[answer]);
                end
                return;
            end
            if (onCreated) then
                onCreated(answer);
            end
            -- No redraw here: `CreateSwitch` fires `OnSwitchesChanged`, and the panel rebuilds
            -- its list off that whenever it is up.
            DebindPrivate.UpdateBindings();
        end,
        -- One less than a stored name allows, because the sigil is not typed here.
        maxLetters = 31,
        -- **The sigil is beside the box, not in it.** The rule is in the prompt above, but a
        -- reader handed an empty field still has to act on a sentence rather than on the box;
        -- the glyph says the same thing where it applies, and cannot be typed over.
        prefix = "$",
    });
end


--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

DebindSwitchesPanelMixin = {};

function DebindSwitchesPanelMixin:OnLoad()
    self.usage = {};
    self.detailTab = TAB_SETTINGS;
    self.layerID = ROOT_LAYER_ID;
    self:InitializeScrollBox();
    self:InitializeUsageScrollBox();
    self:InitializeDetail();
end

function DebindSwitchesPanelMixin:OnNewClick()
    DebindUI.ShowNewSwitchBox();
end

function DebindSwitchesPanelMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory, elementData)
        if (elementData.spacer) then
            factory("Frame");
        elseif (elementData.header) then
            factory("DebindSwitchGroupHeaderTemplate", function(frame) frame:Init(elementData); end);
        else
            factory("DebindSwitchRowTemplate", function(frame) frame:Init(elementData); end);
        end
    end);

    view:SetElementExtentCalculator(function(_, elementData)
        if (elementData.spacer) then
            return GROUP_GAP;
        end
        if (elementData.header) then
            return HEADER_ROW_HEIGHT;
        end
        return ROW_HEIGHT;
    end);

    -- The inset Overview's order list puts its rows at under the same heading
    -- (`ORDER_LINE_INDENT`). Two lists in one window that hang rows off the same bar by different
    -- amounts read as two kinds of bar.
    view:SetElementIndentCalculator(function(elementData)
        if (elementData.spacer or elementData.header) then
            return 0;
        end
        return ROW_INDENT;
    end);

    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

function DebindSwitchesPanelMixin:InitializeUsageScrollBox()
    local usage = self.Detail.Usage;
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory, elementData)
        if (elementData.spacer) then
            factory("Frame");
        elseif (elementData.header) then
            factory("DebindSwitchGroupHeaderTemplate", function(frame) frame:Init(elementData); end);
        else
            factory("DebindSwitchUsageRowTemplate", function(frame) frame:Init(elementData); end);
        end
    end);

    view:SetElementExtentCalculator(function(_, elementData)
        if (elementData.spacer) then
            return GROUP_GAP;
        end
        if (elementData.header) then
            return HEADER_ROW_HEIGHT;
        end
        return USAGE_ROW_HEIGHT;
    end);

    view:SetElementIndentCalculator(function(elementData)
        if (elementData.spacer or elementData.header) then
            return 0;
        end
        return ROW_INDENT;
    end);

    ScrollUtil.InitScrollBoxListWithScrollBar(usage.ScrollBox, usage.ScrollBar, view);
end

--- The words on the right column that never change, and the two controls that are wired once.
function DebindSwitchesPanelMixin:InitializeDetail()
    local detail = self.Detail;
    local settings = detail.Settings;

    detail.TabSystem:SetTabSelectedCallback(function(tabID)
        self.detailTab = tabID;
        self:RefreshDetail();
    end);
    detail.TabSystem:AddTab(LLL["SWITCH_TAB_SETTINGS"]);
    detail.TabSystem:AddTab(LLL["SWITCH_TAB_USAGE"]);
    detail.TabSystem:SetTabVisuallySelected(TAB_SETTINGS);

    detail.Background.EmptyText:SetText(LLL["SWITCHES_DETAIL_EMPTY"]);

    settings.NameSigil:SetText("$");
    settings.NameLabel:SetText(LLL["SWITCH_NAME_LABEL"]);
    settings.LayerLabel:SetText(LLL["SWITCH_LAYER_PICKER"]);
    settings.StartLabel:SetText(LLL["SWITCH_START_VALUE"]);

    for _, answer in ipairs(ANSWERS) do
        local radio = settings[self:RadioKeyFor(answer.key)];
        SetRadioText(radio, LLL[answer.label]);
        radio.tooltipTitle = LLL[answer.label];
        radio.tooltipText = LLL[answer.desc];
        self:WireTooltip(radio);
    end
    for _, start in ipairs(START_VALUES) do
        local radio = settings[self:StartRadioKeyFor(start.key)];
        SetRadioText(radio, LLL[start.label]);
        radio.tooltipTitle = LLL[start.label];
        radio.tooltipText = LLL[start.desc];
        self:WireTooltip(radio);
    end

    settings.LayerDropdown:SetupMenu(function(_, rootDescription)
        self:BuildLayerMenu(rootDescription);
    end);
    -- **The closed button says the layer's name and nothing else.** The mark on the winning entry
    -- belongs in the list, where the reader is comparing the layers against each other; on the
    -- button it would ride along after the name as though it were part of it.
    settings.LayerDropdown:SetSelectionText(function()
        return DebindUI.GetLayerLabel(self.layerID);
    end);
    settings.LayerDropdown.tooltipTitle = LLL["SWITCH_LAYER_PICKER"];
    settings.LayerDropdown.tooltipText = LLL["SWITCH_OVERRIDE_DESC"];
    self:WireTooltip(settings.LayerDropdown);
end

--- Which radio carries which answer. The three are separate frames rather than a pool, because
--- their places are laid out in the XML along with what hangs under each of them.
function DebindSwitchesPanelMixin:RadioKeyFor(answerKey)
    if (answerKey == "unset") then
        return "UnsetRadio";
    elseif (answerKey == "manual") then
        return "ManualRadio";
    end
    return "AutoRadio";
end

function DebindSwitchesPanelMixin:StartRadioKeyFor(startKey)
    if (startKey == "on") then
        return "StartOnRadio";
    elseif (startKey == "off") then
        return "StartOffRadio";
    end
    return "StartRememberRadio";
end

--- The tooltip a control on this column opens, from `tooltipTitle` and `tooltipText` on it.
---
--- **It shows while the control is disabled too.** Half of these are greyed by the answer above
--- them, and a control that cannot be pressed is exactly the one a reader wants to ask about.
--- **Whatever the control already had runs first.** The dropdown's own `OnEnter` is what lights
--- its artwork (`ButtonStateBehaviorMixin`), so replacing the script outright leaves a control that
--- never reacts to the cursor while its tooltip works perfectly.
function DebindSwitchesPanelMixin:WireTooltip(frame)
    frame:SetMotionScriptsWhileDisabled(true);
    local priorEnter = frame:GetScript("OnEnter");
    local priorLeave = frame:GetScript("OnLeave");
    frame:SetScript("OnEnter", function(owner, ...)
        if (priorEnter) then
            priorEnter(owner, ...);
        end
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, owner.tooltipTitle);
        GameTooltip_AddNormalLine(GameTooltip, owner.tooltipText);
        GameTooltip:Show();
    end);
    frame:SetScript("OnLeave", function(owner, ...)
        if (priorLeave) then
            priorLeave(owner, ...);
        end
        GameTooltip:Hide();
    end);
end


--------------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------------

--- Rebuilds the list from the definitions, in two halves.
---
--- **The profile is walked once here and both columns read that one answer**
--- (`CollectSwitchUsage`). Asking per switch measured 293ms on an account of twenty characters and
--- forty switches, and asking once is 6ms (`reworking-the-switches-tab.md`). Nothing is cached
--- between refreshes either: a switch's places move from an action edited on any layer, a macro
--- body, an import and a tab copy, and a cache with four doors into it says the wrong thing the
--- first time one of them is missed.
function DebindSwitchesPanelMixin:RefreshRows()
    local names = DebindPrivate.GetSwitchNames();
    self.usage = DebindPrivate.CollectSwitchUsage();

    local list = {};
    -- **No headings at all where there is not one switch.** That is the one case the two halves
    -- say nothing about, and the empty text below is the whole of what the tab has to say then.
    if (#names > 0) then
        for index, group in ipairs(GROUPS) do
            -- Air between the two halves, as its own element (Overview's `KEY_GROUP_GAP`). Not
            -- above the first: the list already stands off the top of its box.
            if (index > 1) then
                list[#list + 1] = { spacer = true };
            end
            list[#list + 1] = { header = group.header };
            for _, name in ipairs(names) do
                if (IsUsed(self.usage, name) == group.used) then
                    list[#list + 1] = { name = name, panel = self };
                end
            end
        end
    end

    self.usedSignature = UsedSignature(self.usage, names);

    -- **The picked switch is settled before the rows are handed over**, so a row drawing its own
    -- lit state has the answer by the time it is built.
    self:ResolveSelection(names);

    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(LLL["SWITCHES_EMPTY"]);
    self.ScrollBox.EmptyText:SetShown(#names == 0);

    self:RefreshDetail();
end

--- Keeps the picked switch where it still exists, and moves on where it does not.
---
--- **The next name takes its place**, which is where the reader was looking: deleting one is what
--- this tab is mostly for, and sending them back to an empty column after every delete makes them
--- pick again to carry on.
function DebindSwitchesPanelMixin:ResolveSelection(names)
    if (not self.selectedName) then
        return;
    end
    for i = 1, #names do
        if (names[i] == self.selectedName) then
            return;
        end
    end
    -- Gone. `GetSwitchNames` is sorted, so the first name past the one that left is whatever has
    -- moved up into its place. Past the end of the list, that is the last row.
    for i = 1, #names do
        if (names[i] > self.selectedName) then
            self:SetSelection(names[i]);
            return;
        end
    end
    self:SetSelection(names[#names]);
end

function DebindSwitchesPanelMixin:SetSelection(name)
    if (self.selectedName == name) then
        return;
    end
    -- **The fields let go before the pick moves, not after.** Letting go is what writes a field
    -- back (`OnNameCommitted`), and it writes it to whichever switch the panel is pointing at --
    -- so clearing focus after the move renames the switch that was just clicked to what was half
    -- typed for the one before it.
    self.Detail.Settings.NameBox:ClearFocus();
    self.Detail.Settings.ExprBox:ClearFocus();

    self.selectedName = name;
    -- **The dropdown opens on the layer in force**, every time a different switch is picked. It is
    -- where the answer the reader is looking at comes from, and the layer they were reading on the
    -- switch before says nothing about this one.
    self.layerID = name and WinningLayerID(name) or ROOT_LAYER_ID;
end

function DebindSwitchesPanelMixin:SelectSwitch(name)
    self:SetSelection(name);
    self:UpdateRows();
    self:RefreshDetail();
end

--- Redraws the rows that are up, without rebuilding the list. What a value change needs.
--- `inCombat` is given only from the regen dispatch, where the flag cannot be asked (`OnEvent`).
--- Everywhere else it is nil and each row asks for itself.
function DebindSwitchesPanelMixin:UpdateRows(inCombat)
    self.ScrollBox:ForEachFrame(function(frame)
        -- A heading has nothing on it that moves, so it carries no `Update` to call.
        if (frame.Update) then
            frame:Update(inCombat);
        end
    end);
end


--------------------------------------------------------------------------------
-- The right column
--------------------------------------------------------------------------------

--- **Nothing here moves when a value moves.** The right column holds settings, and the one widget
--- on it that read a value was a second copy of the toggle already on the row. So this runs off a
--- pick, a rebuild and a specialization change, and the value loop leaves it alone.
function DebindSwitchesPanelMixin:RefreshDetail()
    local detail = self.Detail;
    local name = self.selectedName;

    detail.Background.EmptyText:SetShown(name == nil);
    detail.TabSystem:SetShown(name ~= nil);
    detail.Settings:SetShown(name ~= nil and self.detailTab == TAB_SETTINGS);
    detail.Usage:SetShown(name ~= nil and self.detailTab == TAB_USAGE);

    if (not name) then
        return;
    end
    if (self.detailTab == TAB_SETTINGS) then
        self:RefreshSettings();
    else
        self:RefreshUsage();
    end
end

--- The layer list, with the one in force marked.
---
--- **The mark is on the entry and not next to the dropdown**, because what it answers is "where
--- did the answer I am reading come from" while the reader is walking the list. The picked layer
--- and the one in force come apart the moment they read down it, and this is the way back.
function DebindSwitchesPanelMixin:BuildLayerMenu(rootDescription)
    local name = self.selectedName;
    if (not name) then
        return;
    end
    local winner = WinningLayerID(name);
    local choices = LayerChoices();
    for i = 1, #choices do
        local layerID = choices[i];
        local label = DebindUI.GetLayerLabel(layerID);
        if (layerID == winner) then
            -- **A mark, not a word.** `checkmark-minimal` is what this addon already puts on "this
            -- one" (`StorageUI.lua`), and the radio's own tick beside it says which layer is being
            -- read, which is a different question.
            label = label .. "  " .. CreateAtlasMarkup("checkmark-minimal", 12, 12);
        end
        rootDescription:CreateRadio(label, function()
            return self.layerID == layerID;
        end, function()
            self.layerID = layerID;
            self.Detail.Settings.ExprBox:ClearFocus();
            self:RefreshSettings();
            return MenuResponse.Refresh;
        end);
    end
end

function DebindSwitchesPanelMixin:RefreshSettings()
    local name = self.selectedName;
    if (not name) then
        return;
    end
    local settings = self.Detail.Settings;
    local layerID = self.layerID or ROOT_LAYER_ID;
    local layerKey = DebindPrivate.GetSwitchLayerKey(layerID);
    local isRoot = layerKey == nil;

    -- **Not while it is being typed into.** A rebuild arrives from a key press or the expression
    -- loop at any moment, and putting the stored name back would eat what is half typed.
    if (not settings.NameBox:HasFocus()) then
        settings.NameBox:SetText(strsub(name, 2));
    end

    settings.LayerDropdown:GenerateMenu();

    -- **`GetSwitchAnswerAt` for what this layer decides and `GetSwitchHeldAt` for what it is
    -- holding**, and they are not the same question: a layer that has stopped answering still
    -- keeps the expression and the starting value that were typed into it, and reading the second
    -- through the first would make a row that says nothing say something.
    local mode, resetValue = DebindPrivate.GetSwitchAnswerAt(name, layerKey);
    local heldReset, heldExpr = DebindPrivate.GetSwitchHeldAt(name, layerKey);

    -- The root is the answer everything falls back to. It cannot be taken away (§4-6), so it is
    -- the one layer with nothing to say no at.
    settings.UnsetRadio:SetShown(not isRoot);
    settings.UnsetRadio:SetChecked(mode == nil);
    settings.ManualRadio:SetChecked(mode == Constants.SWITCH_MODES.MANUAL);
    settings.AutoRadio:SetChecked(mode == Constants.SWITCH_MODES.EXPR);

    self:RefreshUnsetNote(name, isRoot, mode);

    -- **What is remembered stays on screen while the answer is off.** Hidden, picking the answer
    -- again would put a starting value or an expression back that the reader has not seen since
    -- they typed it.
    local manualHere = mode == Constants.SWITCH_MODES.MANUAL;
    local startKey;
    if (manualHere) then
        startKey = StartValueFor(resetValue);
    elseif (heldReset == true) then
        startKey = "on";
    elseif (heldReset == false) then
        startKey = "off";
    end
    for _, start in ipairs(START_VALUES) do
        local radio = settings[self:StartRadioKeyFor(start.key)];
        radio:SetChecked(startKey == start.key);
        radio:SetEnabled(manualHere);
        radio.text:SetTextColor((manualHere and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB());
    end
    settings.StartLabel:SetTextColor(
        (manualHere and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB());

    local autoHere = mode == Constants.SWITCH_MODES.EXPR;
    if (not settings.ExprBox:HasFocus()) then
        settings.ExprBox:SetText(heldExpr or "");
    end
    settings.ExprBox:SetEnabled(autoHere);

    -- **This is the only place a dead name inside an expression is ever shown.** Every other
    -- reference to a switch rides on an action, which goes red and drops out of `KeyMap`; an
    -- expression belongs to a definition and reaches neither (`GetUndefinedSwitchInExpr` in
    -- `Misc.lua`). Deleting a switch leaves its references where they are on purpose
    -- (`DeleteSwitch`), and this is what makes that promise true for the one kind that is not an
    -- action.
    --
    -- **Asked only where the expression is the answer.** A layer keeps the words it was given
    -- after the reader moves it off that answer (`SetSwitchAnswer`), so asking regardless would
    -- redden a box over a name it has stopped reading.
    local undefined;
    if (autoHere) then
        undefined = DebindPrivate.GetUndefinedSwitchInExpr(heldExpr, name);
    end
    if (undefined) then
        settings.ExprBox:SetTextColor(ERROR_COLOR:GetRGB());
    elseif (autoHere) then
        settings.ExprBox:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
    else
        settings.ExprBox:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
    end
end

--- The layer answering instead, as a tag after "not set here".
---
--- **Only where the layer really says nothing.** Where it answers, the layer this would name can be
--- the layer itself, and "not set here (here)" says nothing.
function DebindSwitchesPanelMixin:RefreshUnsetNote(name, isRoot, mode)
    local radio = self.Detail.Settings.UnsetRadio;
    local label = LLL["SWITCH_ANSWER_UNSET"];
    if (isRoot or mode ~= nil) then
        SetRadioText(radio, label);
        return;
    end

    local note = format(LLL["SWITCH_ANSWER_UNSET_BY"],
        DebindUI.GetLayerLabel(WinningLayerID(name)));
    SetRadioText(radio, format("%s  %s", label, GRAY_FONT_COLOR:WrapTextInColorCode(note)));
end

--- Every place that names the picked switch, in three groups.
---
--- **The third group is "you would have to log in there to fix it"**, which is not the same as
--- "somebody else owns it": another character of this class is split between the first group and
--- the third, because what it has on the class layers is reachable from here.
function DebindSwitchesPanelMixin:RefreshUsage()
    local name = self.selectedName;
    local usage = self.usage[name];
    local list = {};

    local function AddGroup(header, rows)
        if (#rows == 0) then
            return;
        end
        if (#list > 0) then
            list[#list + 1] = { spacer = true };
        end
        list[#list + 1] = { header = header };
        for i = 1, #rows do
            list[#list + 1] = rows[i];
        end
    end

    AddGroup("SWITCH_USAGE_HERE", self:ActionRows(usage));
    AddGroup("SWITCH_USAGE_EXPRS", self:ExprRows(usage));
    AddGroup("SWITCH_USAGE_ELSEWHERE", self:ElsewhereRows(usage));

    local scrollBox = self.Detail.Usage.ScrollBox;
    scrollBox:SetDataProvider(CreateDataProvider(list), true);
    scrollBox.EmptyText:SetText(LLL["SWITCH_USAGE_EMPTY"]);
    scrollBox.EmptyText:SetShown(#list == 0);
end

--- The layers this character can open, as a set. **A stored layer can be outside it**: an import
--- writes into the specialization slots of whatever class the string came from
--- (`StoredActionsAt`), so a druid's fourth specialization can be sitting in a three-spec class's
--- file. There is no way to reach one from this client, and `GetLayerLabel` has no name for it.
local function OpenableLayers()
    local set = { [ROOT_LAYER_ID] = true };
    local layerIDs = DebindPrivate.GetOverridableLayerIDs();
    for i = 1, #layerIDs do
        set[layerIDs[i]] = true;
    end
    return set;
end

function DebindSwitchesPanelMixin:ActionRows(usage)
    local rows = {};
    if (not usage) then
        return rows;
    end
    local openable = OpenableLayers();
    for i = 1, #usage.here do
        local place = usage.here[i];
        if (openable[place.layerID]) then
            local actionName = DebindUI.NameAndIconForAction(place.action);
            rows[#rows + 1] = {
                text = format("%s  %s", actionName,
                    GRAY_FONT_COLOR:WrapTextInColorCode(DebindUI.GetLayerLabel(place.layerID))),
                -- **The key, because the tab the reader goes to fix this is laid out by key.** The
                -- same spell on two keys is two rows here and two rows there, and a name alone
                -- cannot say which of them this is.
                key = place.action.key and DebindPrivate.GetKeyDisplayText(place.action.key) or nil,
            };
        end
    end
    return rows;
end

function DebindSwitchesPanelMixin:ExprRows(usage)
    local rows = {};
    if (not usage) then
        return rows;
    end
    local openable = OpenableLayers();
    for i = 1, #usage.exprs do
        local place = usage.exprs[i];
        if (openable[place.layerID]) then
            -- **The layer as well as the name.** An expression is one per layer, so a switch
            -- naming this one from two of its layers is two places to go and edit.
            rows[#rows + 1] = {
                text = format("%s  %s", place.name,
                    GRAY_FONT_COLOR:WrapTextInColorCode(DebindUI.GetLayerLabel(place.layerID))),
            };
        end
    end
    return rows;
end

function DebindSwitchesPanelMixin:ElsewhereRows(usage)
    local rows = {};
    local names = UsageElsewhere(usage);
    for i = 1, #names do
        rows[#rows + 1] = { text = names[i] };
    end
    return rows;
end


--------------------------------------------------------------------------------
-- What the right column writes back
--------------------------------------------------------------------------------

--- Writes one of the three answers at the picked layer, and the rebuild that makes it true.
---
--- **The rebuild is what applies it**, not just stores it: it is where the new answer reaches the
--- value at the layer it has moved to (`ApplySwitchResets`), so the toggle is showing the result
--- of this press by the time the column is redrawn.
function DebindSwitchesPanelMixin:OnAnswerClick(answerKey)
    local name = self.selectedName;
    if (not name) then
        return;
    end
    local layerKey = DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID);
    local MODES = Constants.SWITCH_MODES;

    if (answerKey == "unset") then
        -- The root cannot stop answering, and its radio is not drawn. A press that got here
        -- anyway would be asking for the one thing the cascade cannot do without.
        if (layerKey == nil) then
            return;
        end
        DebindPrivate.ClearSwitchOverride(name, layerKey);
    elseif (answerKey == "manual") then
        -- **What it was holding, not a fresh default.** Somebody coming back to this answer after
        -- trying the other two has not asked to lose the starting value they picked.
        local heldReset = DebindPrivate.GetSwitchHeldAt(name, layerKey);
        DebindPrivate.SetSwitchAnswer(name, layerKey, MODES.MANUAL, heldReset);
    else
        DebindPrivate.SetSwitchAnswer(name, layerKey, MODES.EXPR, nil);
    end

    DebindPrivate.UpdateBindings();
    self:RefreshSettings();
    self:UpdateRows();
end

function DebindSwitchesPanelMixin:OnStartValueClick(startKey)
    local name = self.selectedName;
    if (not name) then
        return;
    end
    local layerKey = DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID);
    local resetValue;
    if (startKey == "on") then
        resetValue = true;
    elseif (startKey == "off") then
        resetValue = false;
    end
    DebindPrivate.SetSwitchAnswer(name, layerKey, Constants.SWITCH_MODES.MANUAL, resetValue);
    DebindPrivate.UpdateBindings();
    self:RefreshSettings();
    self:UpdateRows();
end

--- Renaming, from the field the name is read in.
---
--- **It says no in chat rather than in a dialog.** The field is still on screen holding what was
--- typed, so the sentence has somewhere to be read against, and the name goes back to what it was.
function DebindSwitchesPanelMixin:OnNameCommitted()
    local name = self.selectedName;
    local box = self.Detail.Settings.NameBox;
    if (not name) then
        return;
    end
    local typed = "$" .. strtrim(box:GetText());
    if (typed == name) then
        return;
    end

    local ok, reason = DebindPrivate.RenameSwitch(name, typed);
    if (not ok) then
        if (reason) then
            DebindPrivate.DisplayMessage(LLL[reason]);
        end
        box:SetText(strsub(name, 2));
        return;
    end
    -- **The name it was filed under, not the one that was typed.** `RenameSwitch` folds the case,
    -- and the column would otherwise go on pointing at a name nothing defines.
    self.selectedName = strlower(typed);
    DebindPrivate.UpdateBindings();
end

function DebindSwitchesPanelMixin:OnNameCancelled()
    local box = self.Detail.Settings.NameBox;
    if (self.selectedName) then
        box:SetText(strsub(self.selectedName, 2));
    end
    box:ClearFocus();
end

--- The macro conditional the picked layer works the switch out from.
---
--- **One layer's, the picked one.** A switch computed one way in this specialization and another
--- way everywhere else is two expressions, and a field that always wrote the root would quietly
--- overwrite the wrong one.
function DebindSwitchesPanelMixin:OnExprCommitted()
    local name = self.selectedName;
    local box = self.Detail.Settings.ExprBox;
    if (not name) then
        return;
    end
    local layerKey = DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID);
    local value = strtrim(box:GetText());
    if (value == "") then
        value = nil;
    end
    local _, heldExpr = DebindPrivate.GetSwitchHeldAt(name, layerKey);
    if (value == heldExpr) then
        return;
    end
    if (not DebindPrivate.SetSwitchExpression(name, layerKey, value)) then
        return;
    end
    DebindPrivate.UpdateBindings();
    self:RefreshSettings();
    self:UpdateRows();
end

function DebindSwitchesPanelMixin:OnExprCancelled()
    local box = self.Detail.Settings.ExprBox;
    local name = self.selectedName;
    if (name) then
        local _, heldExpr = DebindPrivate.GetSwitchHeldAt(name,
            DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID));
        box:SetText(heldExpr or "");
    end
    box:ClearFocus();
end

function DebindSwitchesPanelMixin:OnExprEnter()
    local box = self.Detail.Settings.ExprBox;
    GameTooltip:SetOwner(box, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, LLL["CUSTOM_STATE_EDIT_VALUE"]);
    GameTooltip_AddNormalLine(GameTooltip, LLL["CUSTOM_STATE_EDIT_VALUE_DESC"]);
    GameTooltip:Show();
end

--- **The question carries what goes with it**, and that is the whole of what makes it answerable.
--- The definition is account-wide while this tab shows one character's reach, so deleting from a
--- priest can take a druid's conditions *and* a druid's layer settings with it, and this is the
--- only place either asymmetry is ever on screen (§6-B).
---
--- **The sentence is put together here rather than handed to the popup in pieces.** The dialog
--- formats with exactly two arguments (`SharedDialogDefs.lua`), so a third number has nowhere
--- to go; a finished string with no specifiers left in it goes through the same call unharmed.
--- Nothing that lands in it can carry a `%` of its own - a switch name is `$` and word
--- characters (`IsValidSwitchName`) and the rest are numbers.
function DebindSwitchesPanelMixin:OnDeleteClick()
    local name = self.selectedName;
    if (not name) then
        return;
    end
    local text = format(LLL["SWITCH_DELETE_CONFIRM"], name,
        DebindPrivate.CountSwitchReferences(name));
    local overrides = DebindPrivate.CountSwitchOverrides(name);
    if (overrides > 0) then
        text = text .. "\n" .. format(LLL["SWITCH_DELETE_CONFIRM_OVERRIDES"], overrides);
    end

    StaticPopup_ShowCustomGenericConfirmation({
        text = text,
        callback = function()
            DebindPrivate.DeleteSwitch(name);
            DebindPrivate.UpdateBindings();
        end,
        acceptText = YES,
        cancelText = NO,
        showAlert = true,
        referenceKey = "DebindSwitchDelete",
    });
end


--------------------------------------------------------------------------------
-- What moves the panel
--------------------------------------------------------------------------------

function DebindSwitchesPanelMixin:OnShow()
    self:RefreshRows();

    -- **Three things move this list while it is up, and none of them is this panel.** A key or a
    -- macro flips a value, the expression loop computes one, and the action menus can make a switch
    -- with the reader standing on another tab. Watching for them is what makes the list say what is
    -- true rather than what was true when the tab was opened.
    --
    -- **The first two are pulled and the third is pushed.** A value moving used to arrive as
    -- `SWITCH_CHANGED`; that event is gone, because anything listening to it made every switch
    -- value have to be current the instant it moved
    -- (`trimming-the-restricted-hot-paths.md`). The set of switches changing is a different
    -- question, it is rare, and it still arrives.
    self.seenSerial = DebindPrivate.switchValueSerial;
    DebindPrivate.RegisterCallback(self, "OnSwitchesChanged");
    -- **A fifth, and it is what the two halves are read off.** Which places name a switch moves
    -- with every action edited anywhere, and nothing above says when that happened.
    DebindPrivate.RegisterCallback(self, "OnBindingsUpdated");
    self:RegisterEvent("PLAYER_REGEN_DISABLED");
    self:RegisterEvent("PLAYER_REGEN_ENABLED");
    -- **A fourth, and it is the one the right column was built for.** Changing specialization
    -- moves which layer is in force and can move every value with it. Neither of the two above
    -- covers it: the counter only moves where a value moved, and a switch that was already on in
    -- both specializations moves nothing while the layer deciding it has changed.
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
end

function DebindSwitchesPanelMixin:OnHide()
    DebindPrivate.UnregisterCallback(self, "OnSwitchesChanged");
    DebindPrivate.UnregisterCallback(self, "OnBindingsUpdated");
    self:UnregisterEvent("PLAYER_REGEN_DISABLED");
    self:UnregisterEvent("PLAYER_REGEN_ENABLED");
    self:UnregisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
    GameTooltip:Hide();
end

--- Combat is one of the two things this panel watches the game for, and it watches it for one
--- widget: the row's toggle is a plain button, so it stands down for the fight (§6-B). The other is
--- a specialization change, which redraws rather than merely updating - the answer in effect moves.
---
--- **The event says whether a fight is on, and `InCombatLockdown()` answers a different question.**
--- The lockdown has not begun when `PLAYER_REGEN_DISABLED` arrives: the flag answers false and a
--- protected write still lands (`reading-back-what-you-just-set.md`). A row reading the
--- flag from inside this dispatch drew the toggle enabled at the moment it had to go dead, so the
--- answer is carried down instead.
function DebindSwitchesPanelMixin:OnEvent(event)
    if (event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED") then
        self:RefreshRows();
    else
        self:UpdateRows(event == "PLAYER_REGEN_DISABLED");
    end
end

--- **The list pulls the values.** What a row draws is `definition.value`, which the report out of
--- the restricted environment still fills in; what went away is the event that used to say when.
---
--- **A counter, not a clock.** Redrawing on a beat would repaint every row for nothing most of
--- the time; `switchValueSerial` moves only where a value really moved (`Profile.lua`), so this
--- is one comparison a frame and a redraw exactly when there is something to redraw. That makes
--- it as prompt as the event was.
function DebindSwitchesPanelMixin:OnUpdate()
    local serial = DebindPrivate.switchValueSerial;
    if (self.seenSerial == serial) then
        return;
    end
    self.seenSerial = serial;
    self:UpdateRows();
end

function DebindSwitchesPanelMixin:OnSwitchesChanged()
    self:RefreshRows();
end

--- **Only where a switch changed halves.** Every rebuild arrives here, and the toggles run one on
--- every press: rebuilding the list each time would throw the rows away under the hand that
--- pressed one, for a value change that never moves a switch between the halves.
---
--- **Walking the profile is the price of asking.** Which half a switch is in is read off the
--- places that name it and nothing announces when one of those moved, so the one walk
--- (`CollectSwitchUsage`, 6ms on a large account) is what the comparison is made of.
function DebindSwitchesPanelMixin:OnBindingsUpdated()
    local usage = DebindPrivate.CollectSwitchUsage();
    if (UsedSignature(usage, DebindPrivate.GetSwitchNames()) ~= self.usedSignature) then
        self:RefreshRows();
    else
        self.usage = usage;
        self:RefreshDetail();
    end
end
