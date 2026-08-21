local _, DebindPrivate = ...;

local Constants        = DebindPrivate.Constants;
local LLL              = DebindPrivate.L;
local DebindUI         = DebindPrivate.DebindUI;

local ROW_HEIGHT       = 28;

--- The four answers a switch can give, in the order the menu offers them.
---
--- **One row of a menu is one answer, and `mode` is not one of them.** A definition stores this as
--- two fields, manual or an expression, and what a manual one resets to. But those two are a
--- single question to the person reading: *what is this switch when I log in, and can I press it?*
--- Splitting them put "Set Manually" on screen with the answer to the second half two levels down
--- (§4-6 of `devdocs/redesigning-custom-states.md`).
---
--- `resetValue = nil` is an answer and not an absence: it means "come back the way this character
--- left it", which is why `key` exists at all: a table cannot hold a nil to compare against.
local ANSWERS = {
    { key = "on",       label = "SWITCH_ANSWER_ON",       desc = "SWITCH_ANSWER_ON_DESC" },
    { key = "off",      label = "SWITCH_ANSWER_OFF",      desc = "SWITCH_ANSWER_OFF_DESC" },
    { key = "remember", label = "SWITCH_ANSWER_REMEMBER", desc = "SWITCH_ANSWER_REMEMBER_DESC" },
    -- The expression's own words, which the settings menu on the portrait already uses for the
    -- same choice. Reuse here is real: it is one rule, and a second key for it would be a second
    -- thing to translate that can then disagree inside one window.
    { key = "expr",     label = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL",
                        desc  = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC" },
};

--- Which of the four this definition is giving right now.
local function AnswerFor(definition)
    if (definition.mode == Constants.SWITCH_MODES.EXPR) then
        return "expr";
    end
    if (definition.resetValue == true) then
        return "on";
    end
    if (definition.resetValue == false) then
        return "off";
    end
    return "remember";
end

--- Redraws the rows that are up, from wherever the change was made.
---
--- **The menu is not a child of the row**, so nothing it does reaches the list on its own. Picking
--- an answer changes both columns a row draws for it (what it comes up as, and whether the toggle
--- can be pressed at all), and without this the row goes on showing the answer it had until
--- something else redraws it.
local function RefreshPanelRows()
    if (DebindSwitchesPanel:IsShown()) then
        DebindSwitchesPanel:UpdateRows();
    end
end

--- Writes one of the four back. **Both fields, every time**, because the four are one axis: coming
--- from the expression answer and setting only `resetValue` would leave a switch that computes
--- itself *and* claims to come up on.
local function SetAnswer(name, answerKey)
    local definition = DebindPrivate.ResolveSwitchDefinition(name);
    if (not definition) then
        return;
    end

    if (answerKey == "expr") then
        definition.mode = Constants.SWITCH_MODES.EXPR;
    else
        definition.mode = Constants.SWITCH_MODES.MANUAL;
        if (answerKey == "on") then
            definition.resetValue = true;
        elseif (answerKey == "off") then
            definition.resetValue = false;
        else
            definition.resetValue = nil;
        end
    end

    DebindPrivate.UpdateBindings();
    RefreshPanelRows();
end


--------------------------------------------------------------------------------
-- A row
--------------------------------------------------------------------------------

DebindSwitchRowMixin = {};

--- The arrow. `UIPanelSquareButton` carries no icon of its own, so the art is picked in code, the
--- way the main list's move buttons pick theirs. It is set here rather than in the factory below,
--- because a row is built once and bound to many switches.
function DebindSwitchRowMixin:OnLoad()
    SquareButton_SetIcon(self.MenuButton, "DOWN");
end

function DebindSwitchRowMixin:Init(elementData)
    self.switchName = elementData.name;
    self:Update();
end

--- Draws the row from the definition. **Read fresh every time** rather than kept on the row: a
--- switch's value is changed by keys, by macros and by the expression loop, none of which come
--- through this panel.
function DebindSwitchRowMixin:Update()
    local name = self.switchName;
    local definition = DebindPrivate.ResolveSwitchDefinition(name);
    if (not definition) then
        return;
    end

    -- **The `$` is shown, not stripped.** It is what the user has to type in a macro body, and
    -- this list is the only place they can read it off (§6-B).
    self.Name:SetText(name);

    local answerKey = AnswerFor(definition);
    for _, answer in ipairs(ANSWERS) do
        if (answer.key == answerKey) then
            self.Setting:SetText(LLL[answer.label]);
            break;
        end
    end

    local isOn = definition.value and true or false;
    self.ToggleButton:SetText(isOn and LLL["CUSTOM_STATE_ON"] or LLL["CUSTOM_STATE_OFF"]);

    -- **Two different reasons to be dead, and only one of them is temporary.** A computed switch
    -- has no press at all, since the expression decides it and pressing would be overwritten on
    -- the next pass. A manual one is only out of reach until the fight ends.
    self.ToggleButton:SetEnabled(answerKey ~= "expr" and not InCombatLockdown());
end

function DebindSwitchRowMixin:OnClick(button)
    if (button == "RightButton") then
        self:OnMenuClick();
    end
end

function DebindSwitchRowMixin:OnMenuClick()
    DebindUI.ShowSwitchMenu(self.MenuButton, self.switchName);
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
    local definition = DebindPrivate.ResolveSwitchDefinition(self.switchName);
    if (not definition) then
        return;
    end

    GameTooltip:SetOwner(self.ToggleButton, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.switchName);
    if (AnswerFor(definition) == "expr") then
        GameTooltip_AddErrorLine(GameTooltip, LLL["SWITCH_TOGGLE_IS_AUTOMATIC"]);
    elseif (InCombatLockdown()) then
        GameTooltip_AddErrorLine(GameTooltip, LLL["SWITCH_TOGGLE_IN_COMBAT"]);
    else
        GameTooltip_AddInstructionLine(GameTooltip, LLL["SWITCH_TOGGLE_INSTRUCTION"]);
    end
    GameTooltip:Show();
end

--- What this switch is for, on the row itself.
---
--- **The counts are the reason this tooltip exists.** A definition is account-wide and this list is
--- not, so the three distances are the only place a reader is told how far the switch reaches:
--- what deleting it would touch (the account), what this character could reach by changing
--- specialization, and what it is doing for them at this moment.
---
--- Three lines rather than one, because the gap between them is the answer. All three equal means
--- a switch this character alone uses; a wide first number and a zero last one is one that belongs
--- to somebody else's specialization, and the reader cannot tell those apart from a single total.
function DebindSwitchRowMixin:OnEnter()
    local definition = DebindPrivate.ResolveSwitchDefinition(self.switchName);
    if (not definition) then
        return;
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.switchName);
    if (AnswerFor(definition) == "expr") then
        GameTooltip_AddNormalLine(GameTooltip, definition.expr or "");
    end

    local account, character, live = DebindPrivate.CountSwitchReferences(self.switchName);
    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    GameTooltip_AddNormalLine(GameTooltip, LLL["SWITCH_USED_BY_HEADER"]);
    GameTooltip_AddColoredLine(GameTooltip, format(LLL["SWITCH_USED_ACCOUNT"], account),
        NORMAL_FONT_COLOR);
    GameTooltip_AddColoredLine(GameTooltip, format(LLL["SWITCH_USED_CHARACTER"], character),
        NORMAL_FONT_COLOR);
    GameTooltip_AddColoredLine(GameTooltip, format(LLL["SWITCH_USED_LIVE"], live),
        NORMAL_FONT_COLOR);

    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    GameTooltip_AddInstructionLine(GameTooltip, LLL["SWITCH_MENU_INSTRUCTION"]);
    GameTooltip:Show();
end

function DebindSwitchRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- The row's menu
--------------------------------------------------------------------------------

do
    --- Asking for the name, with the `$` already in the box.
    ---
    --- **The box opens on the name as it is**, not empty and not without the `$`: what is being
    --- edited is the exact string a macro body has to say, and a reader who is handed an empty box
    --- has to guess whether the sigil is part of it.
    local function ShowRenameBox(name)
        DebindUI.ShowInputBox({
            text = LLL["SWITCH_RENAME_PROMPT"],
            callback = function(value)
                local ok, reason = DebindPrivate.RenameSwitch(name, strtrim(value));
                if (not ok and reason) then
                    -- Said in chat rather than in a second dialog. The window is still open on
                    -- the row that did not change, so the sentence has somewhere to be read
                    -- against, and a dialog answering a dialog is a stack of two.
                    DebindPrivate.DisplayMessage(LLL[reason]);
                    return;
                end
                DebindPrivate.UpdateBindings();
            end,
            maxLetters = 32,
            currentValue = name,
        });
    end

    --- **The question carries the count**, and that is the whole of what makes it answerable. The
    --- definition is account-wide while this list shows one character's reach, so deleting from a
    --- priest can take a druid's conditions with it, and this line is the only place that
    --- asymmetry is ever on screen (§6-B).
    local function ShowDeleteConfirmation(name)
        StaticPopup_ShowCustomGenericConfirmation({
            text = LLL["SWITCH_DELETE_CONFIRM"],
            text_arg1 = name,
            text_arg2 = DebindPrivate.CountSwitchReferences(name),
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

    local function SetupSwitchMenu(_, rootDescription, name)
        rootDescription:CreateTitle(name);

        for _, answer in ipairs(ANSWERS) do
            local description = rootDescription:CreateRadio(LLL[answer.label], function()
                local definition = DebindPrivate.ResolveSwitchDefinition(name);
                return definition ~= nil and AnswerFor(definition) == answer.key;
            end, function()
                SetAnswer(name, answer.key);
                -- The expression answer is the one that needs a second thing said, so it asks
                -- for it on the spot. The other three are finished the moment they are picked.
                if (answer.key == "expr") then
                    DebindUI.ShowSwitchExpressionBox(name);
                end
                return MenuResponse.Refresh;
            end);
            DebindUI.SetInstructionTooltip(description, LLL[answer.desc]);
        end

        -- Editing the expression again once it is the answer. Without this the only way back into
        -- the box is picking a different answer and picking this one again, which throws the
        -- expression away on the way past.
        local definition = DebindPrivate.ResolveSwitchDefinition(name);
        if (definition and AnswerFor(definition) == "expr") then
            rootDescription:CreateButton(LLL["CUSTOM_STATE_EDIT_VALUE"], function()
                DebindUI.ShowSwitchExpressionBox(name);
            end);
        end

        rootDescription:CreateDivider();
        rootDescription:CreateCheckbox(LLL["CUSTOM_STATE_DISPLAY_MESSAGE"], function()
            local options = DebindPrivate.ResolveSwitchDefinition(name);
            return options ~= nil and options.displayMessage == true;
        end, function()
            local options = DebindPrivate.ResolveSwitchDefinition(name);
            if (options) then
                options.displayMessage = not options.displayMessage;
            end
            return MenuResponse.Refresh;
        end);

        rootDescription:CreateDivider();
        rootDescription:CreateButton(LLL["SWITCH_RENAME"], function()
            ShowRenameBox(name);
        end);
        rootDescription:CreateButton(LLL["DELETE"], function()
            ShowDeleteConfirmation(name);
        end);
    end

    function DebindUI.ShowSwitchMenu(owner, name)
        MenuUtil.CreateContextMenu(owner, SetupSwitchMenu, name);
    end

    --- The macro conditional box. **The same one the portrait's settings menu opens**, down to the
    --- prompt: two boxes asking for one string in two wordings is two syntaxes to a reader who
    --- cannot see that it is one field.
    function DebindUI.ShowSwitchExpressionBox(name)
        local definition = DebindPrivate.ResolveSwitchDefinition(name);
        DebindUI.ShowInputBox({
            text = LLL["CUSTOM_STATE_EDIT_VALUE_DESC"],
            callback = function(value)
                value = strtrim(value);
                if (value == "") then
                    value = nil;
                end
                local options = DebindPrivate.ResolveSwitchDefinition(name);
                if (not options) then
                    return;
                end
                options.expr = value;
                DebindPrivate.UpdateBindings();
                -- The row draws the expression in its tooltip, so it is one of the two columns
                -- this can change.
                RefreshPanelRows();
            end,
            maxLetters = 100,
            currentValue = definition and definition.expr,
        });
    end
end


--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

DebindSwitchesPanelMixin = {};

function DebindSwitchesPanelMixin:OnLoad()
    self:InitializeScrollBox();
end

function DebindSwitchesPanelMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory)
        factory("DebindSwitchRowTemplate", function(frame, data) frame:Init(data); end);
    end);

    view:SetElementExtentCalculator(function()
        return ROW_HEIGHT;
    end);

    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

--- Rebuilds the list from the definitions.
---
--- **Nothing is cached between refreshes.** The set changes from three places outside this panel
--- (the settings menu on the portrait, a rename here, a switch deleted here) and the values change
--- from many more, so a list kept across a redraw would be a second answer to a question the
--- profile already answers.
function DebindSwitchesPanelMixin:RefreshRows()
    local names = DebindPrivate.GetSwitchNames();
    local list = {};
    for _, name in ipairs(names) do
        list[#list + 1] = { name = name };
    end

    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(LLL["SWITCHES_EMPTY"]);
    self.ScrollBox.EmptyText:SetShown(#list == 0);
end

--- Redraws the rows that are up, without rebuilding the list. What a value change needs.
function DebindSwitchesPanelMixin:UpdateRows()
    self.ScrollBox:ForEachFrame(function(frame)
        frame:Update();
    end);
end

function DebindSwitchesPanelMixin:OnShow()
    self:RefreshRows();

    -- **Three things move this list while it is up, and none of them is this panel.** A key or a
    -- macro flips a value, the expression loop computes one, and the settings menu on the portrait
    -- can make a switch without this tab hearing about it. Subscribing is what makes the list say
    -- what is true rather than what was true when the tab was opened.
    DebindPrivate.RegisterCallback(self, "SWITCH_CHANGED");
    DebindPrivate.RegisterCallback(self, "OnSwitchesChanged");
    self:RegisterEvent("PLAYER_REGEN_DISABLED");
    self:RegisterEvent("PLAYER_REGEN_ENABLED");
end

function DebindSwitchesPanelMixin:OnHide()
    DebindPrivate.UnregisterCallback(self, "SWITCH_CHANGED");
    DebindPrivate.UnregisterCallback(self, "OnSwitchesChanged");
    self:UnregisterEvent("PLAYER_REGEN_DISABLED");
    self:UnregisterEvent("PLAYER_REGEN_ENABLED");
    GameTooltip:Hide();
end

--- Combat is the only thing this panel watches the game for, and it watches it for one widget:
--- the toggle is a plain button, so it stands down for the fight (§6-B).
function DebindSwitchesPanelMixin:OnEvent()
    self:UpdateRows();
end

function DebindSwitchesPanelMixin:SWITCH_CHANGED()
    self:UpdateRows();
end

function DebindSwitchesPanelMixin:OnSwitchesChanged()
    self:RefreshRows();
end
