local _, DebindPrivate = ...;

local Constants        = DebindPrivate.Constants;
local LLL              = DebindPrivate.L;
local DebindUI         = DebindPrivate.DebindUI;

--- What the counts under "Actions using it" are pushed in by. **In code and not in the strings**:
--- it is layout, and a translator handed leading spaces will lose them or double them.
local INDENT           = "   ";

local ROW_HEIGHT       = 28;
--- A layer row. Shorter than a switch row on purpose: the list is a switch with its layers under
--- it, and two rows of the same height read as two switches.
local LAYER_ROW_HEIGHT = 20;

--- The root's own layer, which is `GetLayerID(nil, false)`. It is drawn like the overrides and
--- edited like them, and it is the one row that is always there and cannot be taken away (§4-6 of
--- `devdocs/redesigning-custom-states.md`): the definition itself is that answer, which is why it
--- is the one layer `GetSwitchLayerKey` gives no key for.
local ROOT_LAYER_ID    = 1;

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
    -- The expression's own words. The key kept its `CUSTOM_STATE_` name from when the settings
    -- menu on the portrait used it for the same choice, and that menu is gone (3c); the string is
    -- one rule, and a second key for it would be a second thing to translate that can then
    -- disagree inside one window.
    { key = "expr",     label = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL",
                        desc  = "CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC" },
};

--- Which of the four an answer is.
---
--- **It takes the answer, not the definition.** A definition holds the root's answer, and since
--- stage 4 the one in effect may be a layer's instead (`ResolveSwitchAnswer`). Handed a definition,
--- this would draw the root's words on a row a specialization is overriding.
local function AnswerFor(mode, resetValue)
    if (mode == Constants.SWITCH_MODES.EXPR) then
        return "expr";
    end
    if (resetValue == true) then
        return "on";
    end
    if (resetValue == false) then
        return "off";
    end
    return "remember";
end

local function AnswerLabel(mode, resetValue)
    local answerKey = AnswerFor(mode, resetValue);
    for _, answer in ipairs(ANSWERS) do
        if (answer.key == answerKey) then
            return LLL[answer.label];
        end
    end
    return "";
end

--- Which of the four one layer is giving, or nil where it says nothing. The menu's radios read
--- this, and **nothing ticked is the honest answer for a layer with no override**.
local function AnswerKeyAt(name, layerKey)
    local mode, resetValue = DebindPrivate.GetSwitchAnswerAt(name, layerKey);
    if (not mode) then
        return nil;
    end
    return AnswerFor(mode, resetValue);
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

--- Rebuilds the list, which is what an answer needs and a value does not: **giving a layer an
--- answer puts a row on the list that was not there**, and taking one away removes it.
local function RefreshPanelList()
    if (DebindSwitchesPanel:IsShown()) then
        DebindSwitchesPanel:RefreshRows();
    end
end

--- Writes one of the four back, at one layer. `layerKey` nil is the root row.
local function SetAnswer(name, layerKey, answerKey)
    local MODES = Constants.SWITCH_MODES;
    if (answerKey == "expr") then
        DebindPrivate.SetSwitchAnswer(name, layerKey, MODES.EXPR, nil);
    elseif (answerKey == "on") then
        DebindPrivate.SetSwitchAnswer(name, layerKey, MODES.MANUAL, true);
    elseif (answerKey == "off") then
        DebindPrivate.SetSwitchAnswer(name, layerKey, MODES.MANUAL, false);
    else
        DebindPrivate.SetSwitchAnswer(name, layerKey, MODES.MANUAL, nil);
    end

    -- **The rebuild is what makes the answer true**, not just stored: it is where the new answer
    -- gets applied to the value where it has moved (`ApplySwitchResets`), so the toggle column on
    -- the row above is showing the result of this press by the time the list is redrawn.
    DebindPrivate.UpdateBindings();
    RefreshPanelList();
end


--------------------------------------------------------------------------------
-- A switch's row
--------------------------------------------------------------------------------

DebindSwitchRowMixin = {};

function DebindSwitchRowMixin:Init(elementData)
    self.switchName = elementData.name;
    self:Update();
end

--- Draws the row from the definition. **Read fresh every time** rather than kept on the row: a
--- switch's value is changed by keys, by macros and by the expression loop, none of which come
--- through this panel.
---
--- **What it comes up as is not on this row any more.** That answer belongs to a layer since stage
--- 4 and there can be several, so it is drawn once per layer on the rows underneath. What is left
--- here is the switch itself: its name, and what it is right now.
function DebindSwitchRowMixin:Update()
    local name = self.switchName;
    local definition = DebindPrivate.ResolveSwitchDefinition(name);
    if (not definition) then
        return;
    end

    -- **Nothing reads it, so there is no state to draw.** The value on the definition is a memory
    -- for the next reload, not what the switch is: the live one lives in the restricted
    -- environment and only tracked names are there. Drawing "Off" here would be a claim about
    -- something that has none, and pressing it would move a stored number, print nothing, and
    -- change no binding.
    local tracked = DebindPrivate.IsSwitchTracked(name);
    local isOn = definition.value and true or false;

    self.ToggleButton:SetShown(tracked);
    self.Untracked:SetShown(not tracked);
    if (not tracked) then
        self.Untracked:SetText(LLL["SWITCH_NOT_TRACKED"]);
    end

    -- **The `$` is shown, not stripped.** It is what the user has to type in a macro body, and
    -- this list is the only place they can read it off (§6-B).
    --
    -- **What it is sits beside the name, and what the button does is on the button.** The one
    -- label used to be both: it read "On" while the switch was on, in the place a label says what
    -- pressing will do. In one string rather than two font strings, so the state lands right
    -- after however long the name is, and a name too long for the row clips the pair together.
    if (tracked) then
        self.Name:SetText(name .. "  " .. HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(
            isOn and LLL["CUSTOM_STATE_ON"] or LLL["CUSTOM_STATE_OFF"]));
    else
        self.Name:SetText(name);
    end
    self.Name:SetTextColor((tracked and NORMAL_FONT_COLOR or DISABLED_FONT_COLOR):GetRGB());

    if (not tracked) then
        return;
    end

    self.ToggleButton:SetText(isOn and LLL["SWITCH_TURN_OFF"] or LLL["SWITCH_TURN_ON"]);

    -- **Two more reasons to be dead, and only one of them is temporary.** A computed switch
    -- has no press at all, since the expression decides it and pressing would be overwritten on
    -- the next pass. A manual one is only out of reach until the fight ends.
    --
    -- **Asked of the answer in effect**, not of the root: a switch computed on this specialization
    -- and pressed on every other one is exactly what an override is for.
    local mode = DebindPrivate.ResolveSwitchAnswer(name);
    self.ToggleButton:SetEnabled(mode ~= Constants.SWITCH_MODES.EXPR and not InCombatLockdown());
end

function DebindSwitchRowMixin:OnClick(button)
    if (button == "RightButton") then
        self:OnMenuClick();
    end
end

function DebindSwitchRowMixin:OnMenuClick()
    DebindUI.ShowSwitchMenu(self, self.switchName);
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
    local mode = DebindPrivate.ResolveSwitchAnswer(self.switchName);
    if (not mode) then
        return;
    end

    GameTooltip:SetOwner(self.ToggleButton, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.switchName);
    if (mode == Constants.SWITCH_MODES.EXPR) then
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
    local mode, _, expr = DebindPrivate.ResolveSwitchAnswer(self.switchName);
    if (not mode) then
        return;
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.switchName);
    if (mode == Constants.SWITCH_MODES.EXPR) then
        GameTooltip_AddNormalLine(GameTooltip, expr or "");
    end

    -- **On the row and not on the toggle**, because when this is the thing to say the toggle is
    -- not drawn, and a hidden frame is never entered. The one that is always here has to carry it.
    if (not DebindPrivate.IsSwitchTracked(self.switchName)) then
        GameTooltip_AddBlankLineToTooltip(GameTooltip);
        GameTooltip_AddErrorLine(GameTooltip, LLL["SWITCH_NOT_TRACKED"]);
        GameTooltip_AddNormalLine(GameTooltip, LLL["SWITCH_NOT_TRACKED_WHY"]);
    end

    local account, character, live = DebindPrivate.CountSwitchReferences(self.switchName);
    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    GameTooltip_AddNormalLine(GameTooltip, LLL["SWITCH_USED_BY_HEADER"]);
    -- **Label left, number right.** The three are a column to compare, and a number baked into the
    -- sentence lands wherever each translation happens to end. It also takes the specifier out of
    -- the locale string, so a translator is not holding one.
    GameTooltip_AddColoredDoubleLine(GameTooltip, INDENT .. LLL["SWITCH_USED_ACCOUNT"], account,
        NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR);
    GameTooltip_AddColoredDoubleLine(GameTooltip, INDENT .. LLL["SWITCH_USED_CHARACTER"], character,
        NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR);
    GameTooltip_AddColoredDoubleLine(GameTooltip, INDENT .. LLL["SWITCH_USED_LIVE"], live,
        NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR);

    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    GameTooltip_AddInstructionLine(GameTooltip, LLL["SWITCH_MENU_INSTRUCTION"]);
    GameTooltip:Show();
end

function DebindSwitchRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- A layer's row, under the switch it answers for
--------------------------------------------------------------------------------

--- One layer's answer for the switch above it. The root is one of these too.
---
--- ⚠ **These are a situation list and not an order list**, which is the trap in stacking them
--- vertically (§6-B). Bindings on one key fall through to the next when the one above does not
--- match; layers here do not - one wins and the rest are simply not in use. That is why every row
--- carries its layer's name and why the winner is marked: `Oreo / Balance` means "when I am this
--- character in this specialization", never "first choice".
DebindSwitchLayerRowMixin = {};

function DebindSwitchLayerRowMixin:Init(elementData)
    self.switchName = elementData.name;
    self.layerID = elementData.layerID;
    self.layerKey = elementData.layerKey;
    self:Update();
end

function DebindSwitchLayerRowMixin:Update()
    local mode, resetValue = DebindPrivate.GetSwitchAnswerAt(self.switchName, self.layerKey);
    if (not mode) then
        return;
    end

    self.Layer:SetText(DebindUI.GetLayerLabel(self.layerID));
    self.Setting:SetText(AnswerLabel(mode, resetValue));

    -- **The winner is worked out here rather than stored on the row**, because it moves without
    -- the list changing: a specialization change hands the same rows a different answer.
    local _, _, _, winner = DebindPrivate.ResolveSwitchAnswer(self.switchName);

    -- **Greyed except the one that wins.** Nothing on any of these rows is pressed to turn the
    -- switch on, and in the switch row's weight they read as more things to click. But which one
    -- is actually in force is the answer somebody opened the list for, so it keeps its colour and
    -- the rest step back behind it.
    --
    -- **The tick says the same thing as the colour, so neither survives the switch going
    -- untracked.** Which layer wins is still true, but it decides a value nothing collects, and a
    -- tick under a greyed switch is the one mark on screen that reads as live. It is not lost
    -- either way: the tooltip on every row says whether that layer is the winning one.
    local inForce = winner == self.layerKey and DebindPrivate.IsSwitchTracked(self.switchName);
    self.Check:SetShown(inForce);

    local color = inForce and HIGHLIGHT_FONT_COLOR or DISABLED_FONT_COLOR;
    self.Layer:SetTextColor(color:GetRGB());
    self.Setting:SetTextColor(color:GetRGB());
end

function DebindSwitchLayerRowMixin:OnClick(button)
    if (button == "RightButton") then
        DebindUI.ShowSwitchLayerMenu(self, self.switchName, self.layerID, self.layerKey);
    end
end

function DebindSwitchLayerRowMixin:OnEnter()
    local mode, _, expr = DebindPrivate.GetSwitchAnswerAt(self.switchName, self.layerKey);
    if (not mode) then
        return;
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, DebindUI.GetLayerLabel(self.layerID));
    if (mode == Constants.SWITCH_MODES.EXPR) then
        GameTooltip_AddNormalLine(GameTooltip, expr or "");
    end

    local _, _, _, winner = DebindPrivate.ResolveSwitchAnswer(self.switchName);
    if (winner == self.layerKey) then
        GameTooltip_AddNormalLine(GameTooltip, LLL["SWITCH_LAYER_WINNING"]);
    else
        -- **Said out loud, because a row that does nothing looks exactly like one that does.**
        -- The tick marks the winner, and its absence is the whole of what marks the rest.
        GameTooltip_AddColoredLine(GameTooltip, LLL["SWITCH_LAYER_LOSING"], GRAY_FONT_COLOR);
    end

    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    GameTooltip_AddInstructionLine(GameTooltip, LLL["SWITCH_LAYER_MENU_INSTRUCTION"]);
    GameTooltip:Show();
end

function DebindSwitchLayerRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- The menus
--------------------------------------------------------------------------------

do
    --- Asking for the name, with the sigil drawn beside the box rather than sitting in it.
    ---
    --- **The box opens on the part that varies.** `$` is on every switch name and on nothing else,
    --- so it is furniture: shown so the reader knows the shape, kept outside the field so it cannot
    --- be deleted, doubled, or left off. What comes back is joined below.
    local function ShowRenameBox(name)
        DebindUI.ShowInputBox({
            text = LLL["SWITCH_RENAME_PROMPT"],
            callback = function(value)
                local ok, reason = DebindPrivate.RenameSwitch(name, "$" .. strtrim(value));
                if (not ok and reason) then
                    -- Said in chat rather than in a second dialog. The window is still open on
                    -- the row that did not change, so the sentence has somewhere to be read
                    -- against, and a dialog answering a dialog is a stack of two.
                    DebindPrivate.DisplayMessage(LLL[reason]);
                    return;
                end
                DebindPrivate.UpdateBindings();
            end,
            -- One less than a stored name allows, because the sigil is not typed here.
            maxLetters = 31,
            prefix = "$",
            currentValue = strsub(name, 2),
        });
    end

    --- **The question carries the counts**, and that is the whole of what makes it answerable. The
    --- definition is account-wide while this list shows one character's reach, so deleting from a
    --- priest can take a druid's conditions *and* a druid's layer settings with it, and this is the
    --- only place either asymmetry is ever on screen (§6-B).
    ---
    --- **The sentence is put together here rather than handed to the popup in pieces.** The dialog
    --- formats with exactly two arguments (`SharedDialogDefs.lua`), so a third number has nowhere
    --- to go; a finished string with no specifiers left in it goes through the same call unharmed.
    --- Nothing that lands in it can carry a `%` of its own - a switch name is `$` and word
    --- characters (`IsValidSwitchName`) and the rest are numbers.
    local function ShowDeleteConfirmation(name)
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

    --- The four answers, as radios, for one layer. Shared by the two places that offer them: the
    --- submenu that **makes** an override, and the row menu that **edits** one.
    ---
    --- **Nothing is ticked where the layer has no override yet**, which is the state the submenu
    --- opens in. A tick there would be the root's answer wearing the layer's name.
    local function CreateAnswerRadios(description, name, layerKey)
        for _, answer in ipairs(ANSWERS) do
            local radio = description:CreateRadio(LLL[answer.label], function()
                return AnswerKeyAt(name, layerKey) == answer.key;
            end, function()
                SetAnswer(name, layerKey, answer.key);
                -- The expression answer is the one that needs a second thing said, so it asks
                -- for it on the spot. The other three are finished the moment they are picked.
                if (answer.key == "expr") then
                    DebindUI.ShowSwitchExpressionBox(name, layerKey);
                end
                return MenuResponse.Refresh;
            end);
            DebindUI.SetInstructionTooltip(radio, LLL[answer.desc]);
        end
    end

    local function SetupSwitchMenu(_, rootDescription, name)
        rootDescription:CreateTitle(name);

        -- **Where an override is made**, and the only place: once a layer has one it has a row of
        -- its own on the list, and that row's menu is where it is edited. Two doors into one
        -- setting is two places to look for it.
        local overrideDescription = rootDescription:CreateButton(LLL["SWITCH_OVERRIDE"]);
        DebindUI.SetInstructionTooltip(overrideDescription, LLL["SWITCH_OVERRIDE_DESC"]);
        local layerIDs = DebindPrivate.GetOverridableLayerIDs();
        for i = 1, #layerIDs do
            local layerKey = DebindPrivate.GetSwitchLayerKey(layerIDs[i]);
            if (layerKey) then
                CreateAnswerRadios(
                    overrideDescription:CreateButton(DebindUI.GetLayerLabel(layerIDs[i])),
                    name, layerKey);
            end
        end

        rootDescription:CreateDivider();
        -- **Not one of the four, so it is not on a layer.** It says whether a change is worth a
        -- line in chat, which is about the switch and not about where the switch is being used.
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

    --- One layer row's menu: what this layer says, and taking it back.
    ---
    --- **The root has no [Remove].** That row is not an override, it is the value everything else
    --- falls back to, and §4-6 built the whole cascade on it always being there - the conditions
    --- naming this switch would have nowhere to land without it (§6-B).
    local function SetupSwitchLayerMenu(_, rootDescription, name, layerID, layerKey)
        rootDescription:CreateTitle(DebindUI.GetLayerLabel(layerID));
        CreateAnswerRadios(rootDescription, name, layerKey);

        -- Editing the expression again once it is the answer. Without this the only way back into
        -- the box is picking a different answer and picking this one again, which throws the
        -- expression away on the way past.
        if (AnswerKeyAt(name, layerKey) == "expr") then
            rootDescription:CreateButton(LLL["CUSTOM_STATE_EDIT_VALUE"], function()
                DebindUI.ShowSwitchExpressionBox(name, layerKey);
            end);
        end

        rootDescription:CreateDivider();
        -- **Our own words, not the client's `REMOVE`.** That global reads "Remove" in English
        -- and 추방 in Korean, which is what you do to somebody in your group.
        --
        -- **Shown greyed on the root rather than left out.** The root is not an override and has
        -- nothing to remove, but a menu that is one item shorter there reads as a menu that
        -- forgot: the reader compares it against the one they opened a row above.
        local removeDescription = rootDescription:CreateButton(LLL["SWITCH_OVERRIDE_REMOVE"], function()
            DebindPrivate.ClearSwitchOverride(name, layerKey);
            DebindPrivate.UpdateBindings();
            RefreshPanelList();
        end);
        removeDescription:SetEnabled(layerKey ~= nil);
    end

    function DebindUI.ShowSwitchLayerMenu(owner, name, layerID, layerKey)
        MenuUtil.CreateContextMenu(owner, SetupSwitchLayerMenu, name, layerID, layerKey);
    end

    --- Asking for a name and making the switch. `onCreated` is handed the name, and is not called
    --- when nothing was made.
    ---
    --- **Three places open this box**: the button under this list, the condition menu, and an
    --- on/off/toggle action's own menu (`DropDownMenus.lua`). That is the whole point of stage
    --- 3c: making a switch belongs wherever the reader turns out to need one, not on a trip to a
    --- tab they have to know about first (§6-2 of `devdocs/redesigning-custom-states.md`).
    ---
    --- It reads like `ShowRenameBox` on purpose, down to saying no in chat rather than in a second
    --- dialog: the two are one gesture, and `CreateSwitch` and `RenameSwitch` answer with the same
    --- two refusals in the same shape.
    function DebindUI.ShowNewSwitchBox(onCreated)
        DebindUI.ShowInputBox({
            text = LLL["SWITCH_CREATE_PROMPT"],
            callback = function(value)
                local name = "$" .. strtrim(value);
                local ok, reason = DebindPrivate.CreateSwitch(name);
                if (not ok) then
                    if (reason) then
                        DebindPrivate.DisplayMessage(LLL[reason]);
                    end
                    return;
                end
                if (onCreated) then
                    onCreated(name);
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

    --- The macro conditional box. **One box, wherever the expression is edited from**: the answer
    --- row that picks the expression opens it, and so does the [Edit] item under that row once it
    --- is picked. Two boxes asking for one string in two wordings is two syntaxes to a reader who
    --- cannot see that it is one field.
    ---
    --- **It edits one layer's expression**, the one whose answer was picked. A switch computed one
    --- way on this specialization and another way everywhere else is two expressions, and a box
    --- that always wrote the root would quietly overwrite the wrong one.
    function DebindUI.ShowSwitchExpressionBox(name, layerKey)
        local _, _, expr = DebindPrivate.GetSwitchAnswerAt(name, layerKey);
        DebindUI.ShowInputBox({
            text = LLL["CUSTOM_STATE_EDIT_VALUE_DESC"],
            callback = function(value)
                value = strtrim(value);
                if (value == "") then
                    value = nil;
                end
                if (not DebindPrivate.SetSwitchExpression(name, layerKey, value)) then
                    return;
                end
                DebindPrivate.UpdateBindings();
                -- The row draws the expression in its tooltip, so it is one of the two columns
                -- this can change.
                RefreshPanelRows();
            end,
            maxLetters = 100,
            currentValue = expr,
        });
    end
end


--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

DebindSwitchesPanelMixin = {};

function DebindSwitchesPanelMixin:OnLoad()
    self:InitializeScrollBox();
    -- `text=` in the XML names a global, and ours are in `L` (the export panel's button is set the
    -- same way, for the same reason).
    self.NewButton:SetText(LLL["SWITCH_CREATE_BUTTON"]);
end

function DebindSwitchesPanelMixin:OnNewClick()
    DebindUI.ShowNewSwitchBox();
end

function DebindSwitchesPanelMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory, elementData)
        if (elementData.layerID) then
            factory("DebindSwitchLayerRowTemplate", function(frame) frame:Init(elementData); end);
        else
            factory("DebindSwitchRowTemplate", function(frame) frame:Init(elementData); end);
        end
    end);

    view:SetElementExtentCalculator(function(_, elementData)
        return elementData.layerID and LAYER_ROW_HEIGHT or ROW_HEIGHT;
    end);

    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

--- Rebuilds the list from the definitions: a switch, then the layers that answer for it.
---
--- **Only the layers that say something, plus the root.** A row per layer whether it had an
--- override or not would be eleven rows for a switch that is the same everywhere, and the reader
--- would have to read all of them to find out that none of them differ.
---
--- **Every specialization, not the one being played**, which is why the winner is marked rather
--- than being the only row drawn. What the list answers without a click is *where is this
--- different*, and a list that hid the other specializations could not answer it (§6-B).
---
--- **The layers another character or another class overrides are not here and cannot be.** They are
--- in the account file all the same, which is what the delete question counts (`ShowDeleteConfirmation`).
---
--- **Nothing is cached between refreshes.** The set changes from a rename here, a switch deleted
--- here, an override made or removed here, and a switch made anywhere the new-switch box is
--- reachable from. The values change from more places still, so a list kept across a redraw would
--- be a second answer to a question the profile already answers.
function DebindSwitchesPanelMixin:RefreshRows()
    local layerIDs = DebindPrivate.GetOverridableLayerIDs();
    local list = {};

    for _, name in ipairs(DebindPrivate.GetSwitchNames()) do
        list[#list + 1] = { name = name };
        for i = 1, #layerIDs do
            local layerKey = DebindPrivate.GetSwitchLayerKey(layerIDs[i]);
            if (layerKey and DebindPrivate.GetSwitchAnswerAt(name, layerKey)) then
                list[#list + 1] = { name = name, layerID = layerIDs[i], layerKey = layerKey };
            end
        end
        -- The root, last and always. `layerKey` is left nil, which is what every door into a
        -- definition's own answer takes for "the root" (`GetSwitchAnswerAt`).
        list[#list + 1] = { name = name, layerID = ROOT_LAYER_ID };
    end

    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(format(LLL["SWITCHES_EMPTY"], LLL["SWITCH_CREATE_BUTTON"]));
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
    -- macro flips a value, the expression loop computes one, and the action menus can make a switch
    -- with the reader standing on another tab. Subscribing is what makes the list say what is true
    -- rather than what was true when the tab was opened.
    DebindPrivate.RegisterCallback(self, "SWITCH_CHANGED");
    DebindPrivate.RegisterCallback(self, "OnSwitchesChanged");
    self:RegisterEvent("PLAYER_REGEN_DISABLED");
    self:RegisterEvent("PLAYER_REGEN_ENABLED");
    -- **A fourth, and it is the one this list was rebuilt for.** Changing specialization moves the
    -- tick from one layer row to another and can move every value with it, and neither of the two
    -- callbacks above is fired by a switch whose value did not happen to change.
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
end

function DebindSwitchesPanelMixin:OnHide()
    DebindPrivate.UnregisterCallback(self, "SWITCH_CHANGED");
    DebindPrivate.UnregisterCallback(self, "OnSwitchesChanged");
    self:UnregisterEvent("PLAYER_REGEN_DISABLED");
    self:UnregisterEvent("PLAYER_REGEN_ENABLED");
    self:UnregisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
    GameTooltip:Hide();
end

--- Combat is one of the two things this panel watches the game for, and it watches it for one
--- widget: the toggle is a plain button, so it stands down for the fight (§6-B). The other is a
--- specialization change, which redraws rather than merely updating - the answer in effect moves.
function DebindSwitchesPanelMixin:OnEvent(event)
    if (event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED") then
        self:RefreshRows();
    else
        self:UpdateRows();
    end
end

function DebindSwitchesPanelMixin:SWITCH_CHANGED()
    self:UpdateRows();
end

function DebindSwitchesPanelMixin:OnSwitchesChanged()
    self:RefreshRows();
end
