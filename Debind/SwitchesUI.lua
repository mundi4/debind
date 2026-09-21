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
--- The air above a heading, as an element of its own. Overview's `KEY_GROUP_GAP`.
local GROUP_GAP         = 8;
--- A row on the right column that is a name and nothing else. Shorter than a switch row: these
--- are read down rather than acted on, and there can be a great many of them.
local USAGE_ROW_HEIGHT  = 24;
local ACTION_ROW_HEIGHT = 46;

--- The root's own layer, which is `GetLayerID(nil, false)`. It is drawn like the overrides and
--- edited like them, and it is the one row that is always there and cannot be taken away (§4-6 of
--- `redesigning-custom-states.md`): the definition itself is that answer, which is why it
--- is the one layer `GetSwitchLayerKey` gives no key for.
local ROOT_LAYER_ID     = 1;

--- **Kept the same as the `<Size>` on `DebindSwitchSettingsTemplate`.** A linear view is asked for
--- an element's extent before there is a frame to measure, so the two cannot come apart.
local SETTINGS_EXTENT   = 348;

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

--- The three answers one layer can give, in the order they stand in the mode dropdown.
---
--- **"Says nothing" is not one of them** (2026-09-20, 소유자). A layer the reader wants to stop
--- deciding is one they take away, and the row's own delete does that; an answer that did the same
--- thing would be a second control for one job. `ignore` is not that answer: the layer goes on
--- deciding, and what goes away is the condition on everything that reads the switch
--- (`IsSwitchIgnored`).
local ANSWERS = {
    { key = Constants.SWITCH_MODES.MANUAL, label = "SWITCH_ANSWER_MANUAL",
                                           desc  = "SWITCH_ANSWER_MANUAL_DESC" },
    -- The expression's own words. The key kept its `CUSTOM_STATE_` name from when the settings
    -- menu on the portrait used it for the same choice, and that menu is gone (3c); the string is
    -- one rule, and a second key for it would be a second thing to translate that can then
    -- disagree inside one window.
    { key = Constants.SWITCH_MODES.EXPR,   label = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL",
                                           desc  = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC" },
    { key = Constants.SWITCH_MODES.IGNORE, label = "SWITCH_ANSWER_IGNORE",
                                           desc  = "SWITCH_ANSWER_IGNORE_DESC" },
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

--- The label on the closed dropdown, for a key out of either list above.
local function LabelIn(list, key)
    for _, entry in ipairs(list) do
        if (entry.key == key) then
            return entry.label;
        end
    end
    return nil;
end

local function LabelForMode(mode)
    return LabelIn(ANSWERS, mode);
end

local function LabelForStartValue(startKey)
    return LabelIn(START_VALUES, startKey);
end

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

--- Which layers this switch is already set at, keyed by `layerID`.
---
--- **The root is always one of them**: it is a row the reader edits like the others and it cannot
--- be missing (§4-6), which is why `GetSwitchLayerKey` gives it no key and it is put in here by
--- hand.
local function LayersThatDecide(name)
    local set = { [ROOT_LAYER_ID] = true };
    local overridable = DebindPrivate.GetOverridableLayerIDs();
    for i = 1, #overridable do
        local layerID = overridable[i];
        local layerKey = DebindPrivate.GetSwitchLayerKey(layerID);
        -- A row that is there answers, so an answer here is the whole of "this layer has a row".
        if (layerKey and DebindPrivate.GetSwitchAnswerAt(name, layerKey)) then
            set[layerID] = true;
        end
    end
    return set;
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

--- Where the account has this switch written down, one row apiece: the account-wide layer, then a
--- row per class, then a row per character.
---
--- **These are not the places this client cannot reach.** This character's own class and its own
--- layers stand here too. What the rows answer is where the name is written, and the same
--- reference is in `here` as well, so the two numbers are not meant to be added
--- (`CollectSwitchUsage`). Split the other way, a switch named once on the account-wide layer read
--- as "this character only".
---
--- **The names come from the profile and not from `GetLayerLabel`.** That one names only the
--- character who is logged in and spells every other one "character" -- it has nothing else to go
--- on, since a shared string carries no character name (`building-export-import.md` 3절). What is
--- in our own file does: `RefreshIdentity` writes `name` and `class` on every login.
---
--- **A character is drawn in its class's colour, and so is a class.** Both rows answer "which
--- class", and two colour rules for one fact is two things to learn.
local function AccountRows(usage)
    local rows = {};
    if (not usage) then
        return rows;
    end

    local function RowFor(label, color, bucket)
        return {
            text = color:WrapTextInColorCode(label),
            actions = bucket.actions,
            exprs = bucket.exprs,
        };
    end

    -- **The account-wide layer is not a class and takes the one colour no class owns**
    -- (2026-09-21, 소유자). White is a priest, gold is close enough to a rogue to be read as one,
    -- and grey is what this window paints something that is off.
    local general = usage.general;
    if (general.actions + general.exprs > 0) then
        rows[#rows + 1] = RowFor(DebindUI.GetLayerLabel(ROOT_LAYER_ID),
            ITEM_QUALITY_COLORS[Enum.ItemQuality.Artifact].color, general);
    end

    local function Sorted(built)
        sort(built, function(a, b) return a.label < b.label; end);
        for i = 1, #built do
            rows[#rows + 1] = RowFor(built[i].label, built[i].color, built[i].bucket);
        end
    end

    local classes = {};
    for classKey, bucket in pairs(usage.classes) do
        classes[#classes + 1] = {
            label = Constants.CLASS_NAMES[classKey] or classKey,
            color = GetClassColorObj(classKey) or NORMAL_FONT_COLOR,
            bucket = bucket,
        };
    end
    Sorted(classes);

    local stored = DebindPrivate.db.global.characters or {};
    local characters = {};
    for guid, bucket in pairs(usage.characters) do
        local entry = stored[guid];
        characters[#characters + 1] = {
            label = entry and entry.name or guid,
            color = entry and GetClassColorObj(entry.class) or HIGHLIGHT_FONT_COLOR,
            bucket = bucket,
        };
    end
    Sorted(characters);

    return rows;
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

    -- **Only a hand-worked switch has a value to draw and a press to offer**, and the other two
    -- answers say so in words where the toggle would be.
    --
    -- A computed one is worked out at a press and at no other moment
    -- (`COMPUTE_SWITCHES_SNIPPET`), so a value drawn here would read as what the switch is now,
    -- which nothing has measured since -- and the press cannot be offered either, since the next
    -- one overwrites it. An ignored one has a value that nothing reads, which is worse: it would
    -- be a toggle that works, on a switch that changes nothing.
    local mode = DebindPrivate.ResolveSwitchAnswer(name);
    local manual = mode == Constants.SWITCH_MODES.MANUAL;
    local isOn = definition.value and true or false;

    self.ToggleButton:SetShown(manual);
    self.Status:SetShown(not manual);
    if (mode == Constants.SWITCH_MODES.EXPR) then
        self.Status:SetText(LLL["SWITCH_AUTOMATIC"]);
    elseif (not manual) then
        self.Status:SetText(LLL["SWITCH_IGNORED"]);
    end

    self.SelectedHighlight:SetShown(self.panel and self.panel.selectedName == name);

    -- **The `$` is shown, not stripped.** It is what the user has to type in a macro body, and
    -- this list is the only place they can read it off (§6-B).
    --
    -- **What it is sits beside the name, and what the button does is on the button.** The one
    -- label used to be both: it read "On" while the switch was on, in the place a label says what
    -- pressing will do. In one string rather than two font strings, so the state lands right
    -- after however long the name is, and a name too long for the row clips the pair together.
    if (not manual) then
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
--- **Through the attribute frame, which is the door a macro body already uses**
--- (`Switches.lua`). What a press reads is the restricted side's `States`, and this side cannot
--- write it: the only line that puts a value in there is the one a rebuild emits
--- (`BuildSwitchesSnippet`). Setting the value here and asking for a rebuild to carry it over is
--- what this used to do, and a rebuild is the most expensive thing the addon does for a value that
--- no binding is built out of.
---
--- **Nothing is written on this side at all.** `SetSwitch` reports the value back out and that
--- report is what fills the definition and what this character remembers (`OnSwitchChanged`,
--- `Misc.lua`), so the row redraws off the value counter like every other mover.
---
--- **The value, and not `"toggle"`.** The flip has to be made against the value the row is
--- drawing, because the restricted side may hold none: `States` is only ever filled for a switch
--- some binding reads (`IsSwitchTracked`), and this list is half made of switches nothing reads.
--- Asked to toggle one of those, that side flips a `nil` and lands on on, so a switch that was
--- already on stayed on and took two presses to go off.
---
--- **Which is why the value is written here and not left to the report.** `SetSwitch` reports back
--- through `C_Timer.After(0)` (`OnSwitchChanged`, `Misc.lua`), so a second press inside the same
--- frame would read the value the first one has not yet been told about and write it again. Going
--- through `SetSwitchValue` is what also keeps it on the character: a switch set to come back the
--- way it was left reads that memory at the next load, and a press that only reached the
--- restricted side would be forgotten there.
---
--- The report still arrives and turns back at that function's echo guard, having nothing left to
--- move.
function DebindSwitchRowMixin:OnToggleClick()
    local definition = DebindPrivate.ResolveSwitchDefinition(self.switchName);
    if (not definition) then
        return;
    end

    local value = not definition.value;
    DebindPrivate.SetSwitchValue(self.switchName, value);
    DebindPrivate.SwitchesUpdaterFrame:SetAttribute(self.switchName, value);
    -- **Said here because the report can no longer say it.** The line goes out where a switch
    -- moved, and the line above is what moves it, so what comes back is an echo
    -- (`AnnounceSwitchChange`).
    DebindPrivate.AnnounceSwitchChange(self.switchName, value);
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

    -- **The tally under them counts the two lines above again.** They answer different questions:
    -- how much of this character the switch touches, and how far it reaches at all.
    local account = AccountRows(usage);
    if (#account > 0) then
        GameTooltip_AddBlankLineToTooltip(GameTooltip);
        GameTooltip_AddNormalLine(GameTooltip, LLL["SWITCH_USAGE_ACCOUNT"]);
        for i = 1, #account do
            local row = account[i];
            GameTooltip_AddColoredDoubleLine(GameTooltip, INDENT .. row.text,
                row.actions + row.exprs, HIGHLIGHT_FONT_COLOR, HIGHLIGHT_FONT_COLOR);
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

--- **The number is everything written in that place**, actions and other switches' expressions
--- together, because the row answers how much of the switch lives there. Which of the two is in
--- the tooltip, and only where there is anything to tell apart.
function DebindSwitchUsageRowMixin:Init(elementData)
    self.Name:SetText(elementData.text);
    self.actions = elementData.actions;
    self.exprs = elementData.exprs;
    if (self.actions) then
        self.Key:SetText(self.actions + self.exprs);
    else
        self.Key:SetText("");
    end
end

--- **Two reasons to open one**: the number is made of two kinds of reference, or the name was cut
--- off by the column.
function DebindSwitchUsageRowMixin:OnEnter()
    local split = self.exprs and self.exprs > 0 and self.actions > 0;
    if (not split and not self.Name:IsTruncated()) then
        return;
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.Name:GetText());
    if (split) then
        GameTooltip_AddColoredDoubleLine(GameTooltip, LLL["SWITCH_USAGE_ACTIONS"], self.actions,
            NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR);
        GameTooltip_AddColoredDoubleLine(GameTooltip, LLL["SWITCH_USAGE_EXPRS"], self.exprs,
            NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR);
    end
    GameTooltip:Show();
end

function DebindSwitchUsageRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- A row for one of this character's actions
--------------------------------------------------------------------------------

DebindSwitchUsageActionMixin = {};

function DebindSwitchUsageActionMixin:Init(elementData)
    self.action = elementData.action;
    self.layerID = elementData.layer;

    DebindUI.FillActionLine(self, elementData.action, elementData.layer);

    self.Marks:Hide();

    -- **The layer, which the Overview's own row leaves empty.** There the reader already knows
    -- which layer they are looking at; here the rows come from several.
    self.InfoText2:SetText(GRAY_FONT_COLOR:WrapTextInColorCode(
        DebindUI.GetLayerLabel(elementData.layer)));
end

--- **The one thing this row does.** The action is edited on the Overview tab, and this list is
--- what a reader empties before deleting a switch, so the row carries them over rather than
--- offering the edit here (`GoToAction`).
---
--- A left click and no menu: the row has exactly one thing to do, and a menu holding one item
--- costs two presses for it. It is also a gesture nobody would look for, since the only rows in
--- this window that open a menu are Overview's.
function DebindSwitchUsageActionMixin:OnClick()
    DebindFrame:GoToAction(self.action, self.layerID);
end

--- **Not the Overview row's tooltip**, which is the whole account of an action: its conditions,
--- its order, what is wrong with it. The reader is not deciding anything about the action here,
--- they are on their way to it.
function DebindSwitchUsageActionMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, (DebindUI.NameAndIconForAction(self.action)));
    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    GameTooltip_AddInstructionLine(GameTooltip, LLL["SWITCH_USAGE_GOTO"]);
    GameTooltip:Show();
end

function DebindSwitchUsageActionMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- A tab over the right column
--------------------------------------------------------------------------------

DebindSwitchDetailTabMixin = {};

--- **The art is brought to the button's own height**, which is what makes this a size rather than
--- a scale: a scaled tab takes its label down with it, and the row this one stands in reads the
--- window's other tabs' text at full size.
---
--- **One factor over all nine pieces, not one height.** The picked tab's art is a taller atlas
--- than the rest (`uiframe-activetab-*` against `uiframe-tab-*`), and that difference is how the
--- row says which tab is picked. Setting them all to the same number takes it away.
---
--- The unpicked side is the reference, so the button's height is the height of a tab that is not
--- picked. Only the height is set: the sides keep their width, and the middle's comes from its
--- anchors.
---
--- **Before the template's own `Init`**, which measures the sides to floor the tab's width.
function DebindSwitchDetailTabMixin:Init(tabID, tabText)
    -- The atlas heights, before anything here has moved them. A tab out of the pool is initialized
    -- again, and a factor over an already scaled piece compounds.
    if (not self.artHeights) then
        self.artHeights = {};
        for i, texture in ipairs(self.RotatedTextures) do
            self.artHeights[i] = texture:GetHeight();
        end
        self.artReference = self.Left:GetHeight();
    end

    local factor = self:GetHeight() / self.artReference;
    for i, texture in ipairs(self.RotatedTextures) do
        texture:SetHeight(self.artHeights[i] * factor);
    end
    TabSystemButtonMixin.Init(self, tabID, tabText);
end

--- **The window's bottom tabs' width, in place of the tab system's own.**
--- `TabSystemButtonMixin:UpdateTabWidth` floors every tab at the side art plus 20, so a short
--- label comes out 20 wider here than the same label does on the bottom row. Both rows draw the
--- same atlases, and the gap is the one thing that would say they are two kinds of tab.
---
--- The template's part names are the ones `PanelTemplates_TabResize` reads (`Text`, `Left`,
--- `Right`), so the bottom row's own call is what goes here.
function DebindSwitchDetailTabMixin:UpdateTabWidth()
    PanelTemplates_TabResize(self, 0);
end


--------------------------------------------------------------------------------
-- The settings block
--------------------------------------------------------------------------------

DebindSwitchSettingsMixin = {};

--- **`settingsFrame` is nil whenever the list is not holding this block**, and everything that
--- writes to the block goes through it.
function DebindSwitchSettingsMixin:Init(panel)
    self.panel = panel;
    panel.settingsFrame = self;
    if (not self.wired) then
        self.wired = true;
        panel:SetupSettings(self);
    end
    panel:RefreshSettings();
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
--- **Renaming goes through the box beside this one** (`ShowRenameSwitchBox`), which is the same
--- dialog with the same rule in it and a different call behind the button.
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

--- Asking for a new name for a switch that is already there. `onRenamed` is handed the name it was
--- filed under, for the same reason the box above hands one over.
---
--- **The field opens holding the current name.** Most renames are an edit to what is there rather
--- than a name thought up from nothing, and an empty field makes the reader type the part they
--- were keeping.
function DebindUI.ShowRenameSwitchBox(name, onRenamed)
    DebindUI.ShowInputBox({
        text = LLL["SWITCH_RENAME_PROMPT"],
        currentValue = strsub(name, 2),
        callback = function(value)
            local typed = "$" .. strtrim(value);
            local ok, reason = DebindPrivate.RenameSwitch(name, typed);
            if (not ok) then
                if (reason) then
                    DebindPrivate.DisplayMessage(LLL[reason]);
                end
                return;
            end
            if (onRenamed) then
                -- **`RenameSwitch` answers whether it moved, not what it filed**, unlike
                -- `CreateSwitch` beside it. The fold is the same one and it is done here.
                onRenamed(strlower(typed));
            end
        end,
        maxLetters = 31,
        prefix = "$",
    });
end


--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

DebindSwitchesPanelMixin = {};

function DebindSwitchesPanelMixin:OnLoad()
    self.usage = {};
    self.layerID = ROOT_LAYER_ID;
    self:InitializeScrollBox();
    self:InitializeDetailScrollBox();
    self:InitializeDetailTabs();
end

--- **The switch that was just made is the one the reader is about to set up**, so the column opens
--- on it rather than leaving them to find it in a list they just made longer.
---
--- **Through the strip and not `PickDetailTab`.** Only `SetTab` moves the artwork, and a settings
--- block under a tab that still looks like the other one says the press went somewhere else.
function DebindSwitchesPanelMixin:OnNewClick()
    DebindUI.ShowNewSwitchBox(function(name)
        self:SelectSwitch(name);
        self.Detail.TabSystem:SetTab(self.settingsTabID);
    end);
end

function DebindSwitchesPanelMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(2, 2, 2, 2, 3);

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

    local content = self.List.ContentArea;
    ScrollUtil.InitScrollBoxListWithScrollBar(content.ScrollBox, content.ScrollBar, view);
end

function DebindSwitchesPanelMixin:InitializeDetailScrollBox()
    local detail = self.Detail;
    local view = CreateScrollBoxListLinearView(2, 2, 2, 2, 3);

    view:SetElementFactory(function(factory, elementData)
        if (elementData.spacer) then
            factory("Frame");
        elseif (elementData.settings) then
            factory("DebindSwitchSettingsTemplate", function(frame) frame:Init(self); end);
        elseif (elementData.header) then
            factory("DebindSwitchGroupHeaderTemplate", function(frame) frame:Init(elementData); end);
        elseif (elementData.action) then
            factory("DebindSwitchUsageActionTemplate", function(frame) frame:Init(elementData); end);
        else
            factory("DebindSwitchUsageRowTemplate", function(frame) frame:Init(elementData); end);
        end
    end);

    -- Scrolling far enough down releases the block, and a refresh reaching a released frame
    -- writes onto a widget nobody can see.
    --
    -- **The field lets go while the panel is still holding the block.** The view resets a frame
    -- before the pool hides it, and hiding is what takes focus off the field: dropping the block
    -- first would leave `OnExprCommitted` with nothing to read and file nothing.
    view:SetElementResetter(function(frame)
        if (frame == self.settingsFrame) then
            frame.ExprBox:ClearFocus();
            self.settingsFrame = nil;
        end
    end);

    view:SetElementExtentCalculator(function(_, elementData)
        if (elementData.spacer) then
            return GROUP_GAP;
        end
        if (elementData.settings) then
            return SETTINGS_EXTENT;
        end
        if (elementData.header) then
            return HEADER_ROW_HEIGHT;
        end
        if (elementData.action) then
            return ACTION_ROW_HEIGHT;
        end
        return USAGE_ROW_HEIGHT;
    end);

    local content = detail.ContentArea;
    ScrollUtil.InitScrollBoxListWithScrollBar(content.ScrollBox, content.ScrollBar, view);
end

--- The two faces of the right column.
---
--- **The tab is picked here and nothing under it is swapped.** `TabSystemOwnerTemplate` shows one
--- frame per tab, and both of these are lists in the one scroll box, so what a press moves is which
--- rows are handed to it.
function DebindSwitchesPanelMixin:InitializeDetailTabs()
    local tabs = self.Detail.TabSystem;
    self.settingsTabID = tabs:AddTab(LLL["SWITCH_TAB_SETTINGS"]);
    self.usageTabID = tabs:AddTab(LLL["SWITCH_TAB_USAGE"]);
    tabs:SetTabSelectedCallback(function(tabID)
        self:PickDetailTab(tabID);
    end);
    tabs:SetTab(self.settingsTabID);
end

--- **The expression field lets go first**, the same rule the layer dropdown goes by
--- (`PickLayer`): letting go is what writes it back, and the press that moves the tab is also what
--- takes the block off the list.
function DebindSwitchesPanelMixin:PickDetailTab(tabID)
    local box = self:ExprBox();
    if (box) then
        box:ClearFocus();
    end
    self.detailTabID = tabID;
    self:RefreshDetail();
end

--- **Called from the block's own `Init`, not from the panel's `OnLoad`.** The list's pool makes
--- the block the first time a switch is picked, so there is no frame to wire before that.
function DebindSwitchesPanelMixin:SetupSettings(settings)
    settings.NameLabel:SetText(LLL["SWITCH_NAME_LABEL"]);
    settings.LayerLabel:SetText(LLL["SWITCH_LAYER_PICKER"]);
    settings.StartLabel:SetText(LLL["SWITCH_START_VALUE"]);
    settings.ExprLabel:SetText(LLL["SWITCH_EXPR_LABEL"]);
    settings.ModeLabel:SetText(LLL["SWITCH_MODE_LABEL"]);
    settings.RenameButton:SetText(LLL["SWITCH_RENAME"]);

    settings.LayerDropdown:SetupMenu(function(_, rootDescription)
        self:BuildLayerMenu(rootDescription);
    end);

    -- **The two lists are built the same way and differ only in what one press writes**, so the
    -- tooltip on each entry is the one the radio beside it used to carry.
    settings.ModeDropdown:SetupMenu(function(_, rootDescription)
        for _, answer in ipairs(ANSWERS) do
            local entry = rootDescription:CreateRadio(LLL[answer.label], function()
                return self:CurrentMode() == answer.key;
            end, function()
                self:SetMode(answer.key);
                return MenuResponse.CloseAll;
            end);
            entry:SetTooltip(function(tooltip)
                GameTooltip_SetTitle(tooltip, LLL[answer.label]);
                GameTooltip_AddNormalLine(tooltip, LLL[answer.desc]);
            end);
        end
    end);
    settings.ModeDropdown:SetSelectionText(function()
        return LLL[LabelForMode(self:CurrentMode())];
    end);

    settings.StartDropdown:SetupMenu(function(_, rootDescription)
        for _, start in ipairs(START_VALUES) do
            local entry = rootDescription:CreateRadio(LLL[start.label], function()
                return self:CurrentStartValue() == start.key;
            end, function()
                self:SetStartValue(start.key);
                return MenuResponse.CloseAll;
            end);
            entry:SetTooltip(function(tooltip)
                GameTooltip_SetTitle(tooltip, LLL[start.label]);
                GameTooltip_AddNormalLine(tooltip, LLL[start.desc]);
            end);
        end
    end);
    settings.StartDropdown:SetSelectionText(function()
        return LLL[LabelForStartValue(self:CurrentStartValue())];
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

--- The picked layer's own answer, for the two dropdowns that read it.
function DebindSwitchesPanelMixin:CurrentMode()
    local name = self.selectedName;
    if (not name) then
        return nil;
    end
    return (DebindPrivate.GetSwitchAnswerAt(name,
        DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID)));
end

--- **Which of the three the row is on, whichever answer it gives.** The starting value outlives a
--- move to another answer (`SetSwitchAnswer` leaves it alone), so the dropdown goes on showing what
--- it will come back to.
function DebindSwitchesPanelMixin:CurrentStartValue()
    local name = self.selectedName;
    if (not name) then
        return nil;
    end
    local _, resetValue = DebindPrivate.GetSwitchAnswerAt(name,
        DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID));
    return StartValueFor(resetValue);
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
        for _, group in ipairs(GROUPS) do
            list[#list + 1] = { header = group.header };
            for _, name in ipairs(names) do
                if (IsUsed(self.usage, name) == group.used) then
                    list[#list + 1] = { name = name, panel = self };
                end
            end
            -- **Air under a group's last row, not over the next heading** (2026-09-21, 소유자).
            -- The gap belongs to the group that just ended, and a heading at the top of the list
            -- would otherwise be the one row that stands differently from the rest.
            list[#list + 1] = { spacer = true };
        end
    end

    self.usedSignature = UsedSignature(self.usage, names);

    -- **The picked switch is settled before the rows are handed over**, so a row drawing its own
    -- lit state has the answer by the time it is built.
    self:ResolveSelection(names);

    local scrollBox = self.List.ContentArea.ScrollBox;
    scrollBox:SetDataProvider(CreateDataProvider(list), true);
    scrollBox.EmptyText:SetText(LLL["SWITCHES_EMPTY"]);
    scrollBox.EmptyText:SetShown(#names == 0);

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

--- **Nil while the block is off the list**, which every caller has to take.
function DebindSwitchesPanelMixin:ExprBox()
    local settings = self.settingsFrame;
    return settings and settings.ExprBox;
end

function DebindSwitchesPanelMixin:SetSelection(name)
    if (self.selectedName == name) then
        return;
    end
    -- **The field lets go before the pick moves, not after.** Letting go is what writes it back
    -- (`OnExprCommitted`), and it writes to whichever switch the panel is pointing at -- so
    -- clearing focus after the move files what was half typed for the switch before it under the
    -- one that was just clicked.
    local box = self:ExprBox();
    if (box) then
        box:ClearFocus();
    end

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
    self.List.ContentArea.ScrollBox:ForEachFrame(function(frame)
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
    local scrollBox = self.Detail.ContentArea.ScrollBox;
    local name = self.selectedName;

    -- The box stands empty rather than folding away, and the tabs over it do fold: there is
    -- nothing behind either face to go to.
    self.Detail.TabSystem:SetShown(name ~= nil);

    local list, empty;
    if (not name) then
        list, empty = {}, LLL["SWITCHES_DETAIL_EMPTY"];
    elseif (self.detailTabID == self.usageTabID) then
        list, empty = self:UsageList(), LLL["SWITCH_USAGE_EMPTY"];
    else
        list = { { settings = true } };
    end

    scrollBox.EmptyText:SetShown(empty ~= nil and #list == 0);
    if (empty) then
        scrollBox.EmptyText:SetText(empty);
    end

    -- **Kept only where the same tab is being drawn again.** A redraw arrives on every rebuild and
    -- throwing the reader back to the top of a long list of places would be its own bug; the tab
    -- moving is the one case where the offset means nothing.
    local sameTab = self.drawnTabID == self.detailTabID;
    self.drawnTabID = self.detailTabID;
    scrollBox:SetDataProvider(CreateDataProvider(list), sameTab);
end

--- Every layer this character reaches, and which of them decides this switch.
---
--- **The colour is on the entry and not next to the dropdown**, because what it answers is "where
--- did the answer I am reading come from" while the reader is walking the list. The picked layer
--- and the one in force come apart the moment they read down it, and this is the way back.
---
--- **Taking a row away is in the row.** It was a button beside the dropdown, which put the layer it
--- would take away one control over from the layer it named; the layout dropdown in HUD edit mode
--- is the client's own answer to the same shape (`EditModeManager.lua`).
---
--- **Making one is the last row and its submenu, and nothing above it writes.** Picking off the
--- list used to make the row it named, so a reader walking down to see where the switch is decided
--- left a row behind at every layer they passed (2026-09-20, 소유자).
function DebindSwitchesPanelMixin:BuildLayerMenu(rootDescription)
    local name = self.selectedName;
    if (not name) then
        return;
    end
    local winner = WinningLayerID(name);
    local decidesAt = LayersThatDecide(name);

    local function AddLayer(layerID)
        local label = DebindUI.GetLayerLabel(layerID);
        if (layerID == winner) then
            -- The colour the action menus put on the one that is in force (`MenuKit.lua`). The
            -- radio's own tick beside it says which layer is being read, which is a different
            -- question, so the two cannot share a mark.
            label = BLUE_FONT_COLOR:WrapTextInColorCode(label);
        end

        local radio = rootDescription:CreateRadio(label, function()
            return self.layerID == layerID;
        end, function()
            self:PickLayer(layerID);
            return MenuResponse.CloseAll;
        end);

        -- The root cannot be taken away (§4-6 of `redesigning-custom-states.md`).
        if (layerID == ROOT_LAYER_ID) then
            return;
        end
        radio:AddInitializer(function(button, _, menu)
            local cancelButton = MenuTemplates.AttachAutoHideCancelButton(button);
            -- **Hooked rather than `SetUtilityButtonTooltipText`**, which puts up a title and
            -- nothing else: what goes with the row is the half a reader cannot see from the list.
            MenuUtil.HookTooltipScripts(cancelButton, function(tooltip)
                GameTooltip_SetTitle(tooltip, LLL["SWITCH_OVERRIDE_REMOVE"]);
                GameTooltip_AddNormalLine(tooltip, LLL["SWITCH_OVERRIDE_REMOVE_DESC"]);
            end);
            -- **`GearButtonAnchor`, which is the row's right edge.** `CancelButtonAnchor` is the
            -- place left of a gear button, and there is no gear here.
            MenuTemplates.SetUtilityButtonAnchor(cancelButton, MenuVariants.GearButtonAnchor,
                button);
            MenuTemplates.SetUtilityButtonClickHandler(cancelButton, function()
                self:RemoveOverrideAt(layerID);
                menu:Close();
            end);
        end);
    end

    -- **In the order the window's own tabs stand.** Every other list of layers in the window runs
    -- that way (`GetOverridableLayerIDs`).
    AddLayer(ROOT_LAYER_ID);
    local overridable = DebindPrivate.GetOverridableLayerIDs();
    local unset = {};
    for i = 1, #overridable do
        if (decidesAt[overridable[i]]) then
            AddLayer(overridable[i]);
        else
            unset[#unset + 1] = overridable[i];
        end
    end

    if (#unset == 0) then
        return;
    end
    rootDescription:CreateDivider();
    -- The client's own row for the same gesture, colour and [+] and all: the layout dropdown's
    -- `HUD_EDIT_MODE_NEW_LAYOUT` takes the atlas as its one argument.
    local newRow = rootDescription:CreateButton(
        format(LLL["SWITCH_OVERRIDE_NEW"], CreateAtlasMarkup("editmode-new-layout-plus")));
    for i = 1, #unset do
        local layerID = unset[i];
        newRow:CreateButton(DebindUI.GetLayerLabel(layerID), function()
            self:CreateOverrideAt(layerID);
            return MenuResponse.CloseAll;
        end);
    end
end

--- Reading the answers at another layer.
---
--- **The expression field lets go first.** Letting go is what writes it back
--- (`OnExprCommitted`), and it writes to whichever layer the panel is pointing at, so moving the
--- pick first would file what was half typed for one layer under another.
function DebindSwitchesPanelMixin:PickLayer(layerID)
    local box = self:ExprBox();
    if (box) then
        box:ClearFocus();
    end
    self.layerID = layerID;
    self:RefreshSettings();
end

--- Starts deciding this switch at a layer that was not deciding it, and reads it there.
function DebindSwitchesPanelMixin:CreateOverrideAt(layerID)
    local name = self.selectedName;
    local layerKey = DebindPrivate.GetSwitchLayerKey(layerID);
    if (not name or layerKey == nil) then
        return;
    end
    DebindPrivate.SetSwitchAnswer(name, layerKey, DebindPrivate.SWITCH_DEFAULTS.mode, nil);

    DebindPrivate.UpdateBindings();
    self:PickLayer(layerID);
    self:UpdateRows();
end

--- Takes one layer's row away, from the row in the list that names it.
---
--- **The pick follows it when it was the layer being read**, because that layer is not in the list
--- any more: a dropdown naming a layer no row stands at would be the only thing on screen saying
--- the press worked.
function DebindSwitchesPanelMixin:RemoveOverrideAt(layerID)
    local name = self.selectedName;
    if (not name) then
        return;
    end

    StaticPopup_ShowCustomGenericConfirmation({
        text = format(LLL["SWITCH_OVERRIDE_REMOVE_CONFIRM"], DebindUI.GetLayerLabel(layerID), name),
        callback = function()
            if (not DebindPrivate.RemoveSwitchOverride(name,
                    DebindPrivate.GetSwitchLayerKey(layerID))) then
                return;
            end
            DebindPrivate.UpdateBindings();
            if (self.layerID == layerID) then
                self:PickLayer(WinningLayerID(name));
            else
                self:RefreshSettings();
            end
            self:UpdateRows();
        end,
        acceptText = YES,
        cancelText = NO,
        showAlert = true,
        referenceKey = "DebindSwitchOverrideRemove",
    });
end

--- **Does nothing while the block is off the list.** Coming back onto it runs this again
--- (`DebindSwitchSettingsMixin:Init`).
function DebindSwitchesPanelMixin:RefreshSettings()
    local name = self.selectedName;
    local settings = self.settingsFrame;
    if (not name or not settings) then
        return;
    end
    local layerID = self.layerID or ROOT_LAYER_ID;
    local layerKey = DebindPrivate.GetSwitchLayerKey(layerID);

    settings.NameText:SetText(name);
    settings.LayerDropdown:GenerateMenu();

    -- The starting value is not read here: the dropdown that shows it reads the same row when it
    -- builds its own list, and two reads of one row is one of them going stale.
    --
    -- **Every layer in the list has a row**, so this always answers. The ones that have none are in
    -- the submenu under the last entry, and picking one there makes the row before the panel is
    -- pointed at it (`CreateOverrideAt`).
    local mode, _, expr = DebindPrivate.GetSwitchAnswerAt(name, layerKey);

    settings.ModeDropdown:GenerateMenu();

    -- **Both blocks stand whichever answer is picked**, the one that is not answering greyed. The
    -- starting value and the expression are kept when another answer is chosen
    -- (`SetSwitchAnswer`), and hiding the block would put one of them back on screen at a press
    -- the reader has not seen since they typed it.
    local manualHere = mode == Constants.SWITCH_MODES.MANUAL;
    settings.StartDropdown:GenerateMenu();
    settings.StartDropdown:SetEnabled(manualHere);
    settings.StartLabel:SetTextColor(
        (manualHere and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB());

    local autoHere = mode == Constants.SWITCH_MODES.EXPR;
    settings.ExprLabel:SetTextColor(
        (autoHere and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB());
    if (not settings.ExprBox:HasFocus()) then
        settings.ExprBox:SetText(expr or "");
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
        undefined = DebindPrivate.GetUndefinedSwitchInExpr(expr, name);
    end
    if (undefined) then
        settings.ExprBox:SetTextColor(ERROR_COLOR:GetRGB());
    elseif (autoHere) then
        settings.ExprBox:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
    else
        settings.ExprBox:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
    end
end

--- **The first two groups are not a partition and are not meant to be added.** The first is what
--- this character can open and fix, as rows to go to; the second is where the name is written
--- across the account, as a tally that counts those same references again (`AccountRows`).
---
--- The third is the switches whose expression names this one, and only the ones on a layer this
--- character can open: the rest are inside the tally above.
function DebindSwitchesPanelMixin:UsageList()
    local usage = self.usage[self.selectedName];
    local list = {};

    local function AddGroup(header, rows)
        if (#rows == 0) then
            return;
        end
        list[#list + 1] = { header = header };
        for i = 1, #rows do
            list[#list + 1] = rows[i];
        end
        -- The left column's rule: the air belongs under the group that just ended.
        list[#list + 1] = { spacer = true };
    end

    AddGroup("SWITCH_USAGE_HERE", self:ActionRows(usage));
    AddGroup("SWITCH_USAGE_ACCOUNT", AccountRows(usage));
    AddGroup("SWITCH_USAGE_EXPRS", self:ExprRows(usage));
    return list;
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
            -- **`layer`, because that is the key the row reads** (`DebindLineMixin:Update`).
            rows[#rows + 1] = { action = place.action, layer = place.layerID };
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



--------------------------------------------------------------------------------
-- What the right column writes back
--------------------------------------------------------------------------------

--- **The rebuild is what applies it**, not just stores it: it is where the new mode reaches the
--- value at the layer it has moved to (`ApplySwitchResets`).
function DebindSwitchesPanelMixin:SetMode(mode)
    local name = self.selectedName;
    if (not name) then
        return;
    end
    local layerKey = DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID);
    local _, resetValue = DebindPrivate.GetSwitchAnswerAt(name, layerKey);
    DebindPrivate.SetSwitchAnswer(name, layerKey, mode, resetValue);

    DebindPrivate.UpdateBindings();
    self:RefreshSettings();
    self:UpdateRows();
end

function DebindSwitchesPanelMixin:SetStartValue(startKey)
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

--- Renaming, through the box that asks for a name.
---
--- **The same box making one opens** (`ShowNewSwitchBox`), so the rule about what a name may hold
--- is read in one place and refused in one place.
function DebindSwitchesPanelMixin:OnRenameClick()
    local name = self.selectedName;
    if (not name) then
        return;
    end
    DebindUI.ShowRenameSwitchBox(name, function(renamed)
        -- **The name it was filed under, not the one that was typed.** `RenameSwitch` folds the
        -- case, and the column would otherwise go on pointing at a name nothing defines.
        self.selectedName = renamed;
        DebindPrivate.UpdateBindings();
    end);
end

--- The macro conditional the picked layer works the switch out from.
---
--- **One layer's, the picked one.** A switch computed one way in this specialization and another
--- way everywhere else is two expressions, and a field that always wrote the root would quietly
--- overwrite the wrong one.
function DebindSwitchesPanelMixin:OnExprCommitted()
    local name = self.selectedName;
    local box = self:ExprBox();
    if (not name or not box) then
        return;
    end
    local layerKey = DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID);
    local value = strtrim(box:GetText());
    if (value == "") then
        value = nil;
    end
    local _, _, storedExpr = DebindPrivate.GetSwitchAnswerAt(name, layerKey);
    if (value == storedExpr) then
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
    local box = self:ExprBox();
    if (not box) then
        return;
    end
    local name = self.selectedName;
    if (name) then
        local _, _, storedExpr = DebindPrivate.GetSwitchAnswerAt(name,
            DebindPrivate.GetSwitchLayerKey(self.layerID or ROOT_LAYER_ID));
        box:SetText(storedExpr or "");
    end
    box:ClearFocus();
end

function DebindSwitchesPanelMixin:OnExprEnter()
    local box = self:ExprBox();
    if (not box) then
        return;
    end
    GameTooltip:SetOwner(box, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, LLL["SWITCH_EXPR_LABEL"]);
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
    local text = format(LLL["SWITCH_DELETE_CONFIRM"], name);
    local references = DebindPrivate.CountSwitchReferences(name);
    if (references > 0) then
        text = text .. "\n" .. format(LLL["SWITCH_DELETE_CONFIRM_ACTIONS"], references);
    end
    if (DebindPrivate.CountSwitchOverrides(name) > 0) then
        text = text .. "\n" .. LLL["SWITCH_DELETE_CONFIRM_OVERRIDES"];
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

    -- **Three things move this list while it is up.** A key or a macro flips a value, the
    -- expression loop computes one, and the action menus can make a switch with the reader standing
    -- on another tab. Watching for them is what makes the list say what is true rather than what
    -- was true when the tab was opened.
    --
    -- **The row's own toggle is the first of those and not a fourth.** It writes the same attribute
    -- a macro body writes (`OnToggleClick`), so the value comes back the same way and this list
    -- finds out about its own press the way it finds out about anybody else's.
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

--- **Only where a switch changed halves.** Every rebuild arrives here, including the ones set off
--- from the other tabs while this one is up, and rebuilding the list on each would throw the rows
--- away under a reader who is standing in them for a change that moved no switch between the
--- halves.
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
