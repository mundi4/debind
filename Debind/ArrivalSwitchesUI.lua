local _, DebindPrivate = ...;

local LLL       = DebindPrivate.L;
local DebindUI  = DebindPrivate.DebindUI;

--- The tallest the list grows before it scrolls.
local MAX_LIST_HEIGHT = 320;
local HEADER_HEIGHT   = 26;
local ROW_HEIGHT      = 24;
--- `ContentArea`'s insets (40 above, 25 below), the gaps around the list, and the button row.
local CHROME_HEIGHT   = 40 + 12 + 12 + 22 + 25;

DebindArrivalSwitchesFrameMixin = {};

function DebindArrivalSwitchesFrameMixin:OnLoad()
    self:InitDialog(LLL["ARRIVAL_SWITCHES_TITLE"]);
    self.Text:SetText(LLL["ARRIVAL_SWITCHES_TEXT"]);
    self.headers, self.rows = {}, {};
    self.AcceptButton:SetScript("OnClick", function() self:Finish(true); end);
    self.CancelButton:SetScript("OnClick", function() self:Finish(false); end);
end

--- Whoever opened it is told only on [OK]. Any other way out -- [Cancel], ESC, the window being
--- swept away -- answers nothing, and the flow that opened it stops there with nothing written
--- (6-1).
function DebindArrivalSwitchesFrameMixin:Finish(accepted)
    local onAnswer = self.onAnswer;
    self.onAnswer = nil;
    local choices = self.choices;
    self:CloseDialog();
    if (accepted and onAnswer) then
        onAnswer(choices);
    end
end

local function RowTooltip(frame)
    local row, item = frame.row, frame.item;
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, LLL[row.mine and "ARRIVAL_SWITCH_OVERWRITE" or "ARRIVAL_SWITCH_FILL"]);
    local mine = row.mine or DebindPrivate.ArrivalRowBelow(item.name, row.layerID, frame.answers);
    if (mine) then
        GameTooltip_AddNormalLine(GameTooltip, format("%s: %s",
            LLL[row.mine and "ARRIVAL_SWITCH_MINE" or "ARRIVAL_SWITCH_MINE_BELOW"],
            HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(
                DebindUI.DescribeSwitchRow(mine.mode, mine.resetValue, mine.expr))));
    end
    GameTooltip_AddNormalLine(GameTooltip, format("%s: %s", LLL["ARRIVAL_SWITCH_INCOMING"],
        HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(
            DebindUI.DescribeSwitchRow(row.incoming.mode, row.incoming.resetValue, row.incoming.expr))));
    local used = DebindPrivate.CountSwitchReferences(item.name);
    GameTooltip_AddBlankLineToTooltip(GameTooltip);
    GameTooltip_AddNormalLine(GameTooltip, format(LLL["ARRIVAL_SWITCH_USED"], used));
    GameTooltip:Show();
end

function DebindArrivalSwitchesFrameMixin:AcquireHeader(index)
    local header = self.headers[index];
    if (not header) then
        header = CreateFrame("Frame", nil, self.Scroll.Child);
        header:SetHeight(HEADER_HEIGHT);
        header.Name = header:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
        header.Name:SetPoint("LEFT", 0, 0);
        header.RenameButton = CreateFrame("Button", nil, header, "UIPanelButtonTemplate");
        header.RenameButton:SetSize(110, 22);
        header.RenameButton:SetPoint("RIGHT", 0, 0);
        header.Renamed = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        header.Renamed:SetPoint("LEFT", header.Name, "RIGHT", 8, 0);
        header.Renamed:SetPoint("RIGHT", header.RenameButton, "LEFT", -8, 0);
        header.Renamed:SetJustifyH("LEFT");
        self.headers[index] = header;
    end
    return header;
end

function DebindArrivalSwitchesFrameMixin:AcquireRow(index)
    local row = self.rows[index];
    if (not row) then
        row = CreateFrame("Frame", nil, self.Scroll.Child);
        row:SetHeight(ROW_HEIGHT);
        row.Check = CreateFrame("CheckButton", nil, row, "MinimalCheckboxArtTemplate");
        row.Check:SetSize(24, 24);
        row.Check:SetPoint("LEFT", 16, 0);
        row.Check.Text = row.Check:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
        row.Check.Text:SetPoint("LEFT", row.Check, "RIGHT", 4, 0);
        DebindUI.NormalizeCheckMark(row.Check);
        -- The mark carries the tooltip, so it is a frame that takes the mouse.
        row.Mark = CreateFrame("Frame", nil, row);
        row.Mark:SetSize(120, ROW_HEIGHT);
        row.Mark:SetPoint("RIGHT", 0, 0);
        row.Mark.Text = row.Mark:CreateFontString(nil, "ARTWORK", "GameFontNormal");
        row.Mark.Text:SetPoint("RIGHT", 0, 0);
        row.Mark:SetScript("OnEnter", RowTooltip);
        row.Mark:SetScript("OnLeave", GameTooltip_Hide);
        self.rows[index] = row;
    end
    return row;
end

--- The names a rename in this window may not take: the other items' new names.
function DebindArrivalSwitchesFrameMixin:TakenNames(except)
    local taken = {};
    for item, choice in pairs(self.choices) do
        if (item ~= except and choice.rename) then
            taken[choice.rename] = true;
        end
    end
    return taken;
end

--- [Rename] asks for a name and checks it here; [Undo Rename] puts the switch back to being
--- asked about, with its rows unticked (6-3).
function DebindArrivalSwitchesFrameMixin:ToggleRename(item)
    local choice = self.choices[item];
    if (choice.rename) then
        self.choices[item] = { checked = {} };
        self:Layout();
        return;
    end
    DebindUI.ShowInputBox({
        text = LLL["SWITCH_RENAME_PROMPT"],
        currentValue = strsub(item.name, 2),
        maxLetters = 31,
        prefix = "$",
        callback = function(value)
            local name, reason = DebindPrivate.CheckArrivalRename("$" .. strtrim(value), self.answers,
                self:TakenNames(item), item.arrivalIDs);
            if (not name) then
                DebindPrivate.DisplayMessage(LLL[reason]);
                return;
            end
            self.choices[item] = { rename = name };
            self:Layout();
        end,
    });
end

function DebindArrivalSwitchesFrameMixin:Layout()
    for _, header in ipairs(self.headers) do
        header:Hide();
    end
    for _, row in ipairs(self.rows) do
        row:Hide();
    end

    local child = self.Scroll.Child;
    local width = self.ContentArea:GetWidth() - 24;
    child:SetWidth(width);
    local y, rowIndex = 0, 0;
    for index, item in ipairs(self.items) do
        local choice = self.choices[item];
        local header = self:AcquireHeader(index);
        header:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y);
        header:SetWidth(width);
        header.Name:SetText(item.name);
        header.Renamed:SetText(choice.rename and format(LLL["ARRIVAL_SWITCH_RENAMED"], choice.rename) or "");
        header.RenameButton:SetText(LLL[choice.rename and "ARRIVAL_SWITCH_RENAME_UNDO" or "SWITCH_RENAME"]);
        header.RenameButton:SetScript("OnClick", function() self:ToggleRename(item); end);
        header:Show();
        y = y + HEADER_HEIGHT;

        for _, entry in ipairs(item.rows) do
            rowIndex = rowIndex + 1;
            local row = self:AcquireRow(rowIndex);
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y);
            row:SetWidth(width);
            row.Check.Text:SetText(DebindUI.GetColoredLayerLabel(entry.layerID) or "");
            DebindUI.ExtendHitRectOverLabel(row.Check);
            -- **Renamed, every row comes in under the new name**, so the rows stay on screen ticked
            -- and greyed: hidden, the switch would read as skipped.
            row.Check:SetChecked(choice.rename ~= nil or (choice.checked and choice.checked[entry.layerID]) or false);
            row.Check:SetEnabled(choice.rename == nil);
            row.Check:SetScript("OnClick", function(check)
                choice.checked[entry.layerID] = check:GetChecked() or nil;
            end);
            row.Mark.Text:SetText(LLL[entry.mine and "ARRIVAL_SWITCH_OVERWRITE" or "ARRIVAL_SWITCH_FILL"]);
            row.Mark.Text:SetTextColor(((entry.mine and WARNING_FONT_COLOR) or NORMAL_FONT_COLOR):GetRGB());
            row.Mark.row, row.Mark.item, row.Mark.answers = entry, item, self.answers;
            row:Show();
            y = y + ROW_HEIGHT;
        end
        y = y + 6;
    end

    child:SetHeight(math.max(y, 1));
    local listHeight = math.min(y, MAX_LIST_HEIGHT);
    self.Scroll:ClearAllPoints();
    self.Scroll:SetPoint("TOPLEFT", self.Text, "BOTTOMLEFT", 0, -12);
    self.Scroll:SetPoint("RIGHT", self.ContentArea, "RIGHT", -20, 0);
    self.Scroll:SetHeight(listHeight);
    self:SetHeight(CHROME_HEIGHT + self.Text:GetStringHeight() + listHeight);
end

--- `items` from `ClassifyArrivalSwitches`, `answers` the flow's table (read for what is already
--- taken and what a layer answers now), `onAnswer(choices)` on [OK]. `fromBindMode` marks a window
--- a key press in bind mode put up, the one kind leaving the mode takes down.
function DebindArrivalSwitchesFrameMixin:Open(items, answers, onAnswer, fromBindMode)
    self.items, self.answers, self.onAnswer = items, answers, onAnswer;
    self.fromBindMode = fromBindMode;
    self.choices = {};
    for _, item in ipairs(items) do
        self.choices[item] = { checked = {} };
    end
    self:Show();
    self:Layout();
end

--- **The front gate of every way an arrival is accepted** (6-1): accepting it, giving it a key,
--- and a key in bind mode. Works out what the actions' switches need, puts the window up for each
--- step that has questions, and hands `onPass(answers)` the held answers once every step has been
--- answered. A cancel at any step ends the flow and nothing is called.
---
--- `answers` is handed on even when nothing was asked: it can still hold switches to make.
---
--- **An [OK] for actions that changed meanwhile ends the flow as a cancel would** (`ArrivalBadgesHold`).
function DebindUI.SettleArrivalSwitches(actions, onPass, fromBindMode)
    local answers = DebindPrivate.NewArrivalAnswers();
    local steps, byArrival = DebindPrivate.ArrivalSwitchSteps(actions);
    local snapshot = DebindPrivate.SnapshotArrivalBadges(actions);
    local index = 0;
    local function NextStep()
        index = index + 1;
        local step = steps[index];
        if (not step) then
            onPass(answers);
            return;
        end
        local items = DebindPrivate.ClassifyArrivalSwitches(byArrival, step, answers);
        if (#items == 0) then
            NextStep();
            return;
        end
        DebindArrivalSwitchesFrame:Open(items, answers, function(choices)
            if (not DebindPrivate.ArrivalBadgesHold(snapshot)) then
                return;
            end
            DebindPrivate.AnswerArrivalSwitches(answers, items, choices);
            NextStep();
        end, fromBindMode);
    end
    NextStep();
end

--- Is the window up. Bind mode reads it to stop taking keys while it is.
function DebindUI.IsSettlingArrivalSwitches()
    return DebindArrivalSwitchesFrame:IsShown();
end

--- The window's [Cancel], from outside it: ESC, the main window closing, and bind mode ending
--- (`onlyFromBindMode`, which leaves a window anything else put up).
function DebindUI.CancelArrivalSwitches(onlyFromBindMode)
    if (DebindArrivalSwitchesFrame:IsShown()
            and (not onlyFromBindMode or DebindArrivalSwitchesFrame.fromBindMode)) then
        DebindArrivalSwitchesFrame:Finish(false);
    end
end
