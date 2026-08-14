local _, DebindShare = ...;

local DebindPrivate = DebindShare.DebindPrivate;
local LLL           = DebindPrivate.L;

--- The workbench: the main window's Import tab.
---
--- **What is here is the drawer** received strings pile up in. Opening a batch and deciding where
--- it goes is the next slice, so a row does not lead anywhere yet.
---
--- Nothing in this file touches the profile. A batch sits outside it until it is committed, which
--- is the decision the whole design turns on -- once actions are in the profile they scatter, and
--- the group identity the string arrived with is held nowhere. `devdocs/building-export-import.md`.

local ROW_HEIGHT    = 44;

--- **Which failures the reader can tell apart, which is fewer than the decoder reports.**
--- `DecodeExportString` answers with eight reasons because each is a different step; a reader has
--- three things they might do about it -- check what they pasted, update, paste it again -- and a
--- message per step would spread those three over eight sentences that all end the same way.
local REASON_TEXT   = {
    NOT_A_STRING          = "IMPORT_FAILED_NOT_OURS",
    NOT_A_DEBIND_STRING   = "IMPORT_FAILED_NOT_OURS",
    -- Made by a newer Debind. Both of these mean the same thing to the reader even though one is
    -- the envelope and the other the schema.
    UNSUPPORTED_ENVELOPE  = "IMPORT_FAILED_TOO_NEW",
    UNSUPPORTED_SCHEMA    = "IMPORT_FAILED_TOO_NEW",
    -- It began as one of ours and stopped being readable partway. Far and away the likeliest cause
    -- is a copy that lost its tail, which is worth saying because the fix is to copy it again.
    BAD_ENCODING          = "IMPORT_FAILED_DAMAGED",
    BAD_COMPRESSION       = "IMPORT_FAILED_DAMAGED",
    BAD_PAYLOAD           = "IMPORT_FAILED_DAMAGED",
    -- Nothing the reader did. The addon's own libraries did not load.
    LIBS_MISSING          = "IMPORT_FAILED_LIBS_MISSING",
    -- Not a failure to read it. Everything picked turned out to have nowhere to go, which one
    -- ordinary case reaches: a string from a character whose class has specializations this one
    -- does not (`ImportAddress`).
    NOTHING_TO_PLACE      = "IMPORT_NOTHING_PLACED",
};


--------------------------------------------------------------------------------
-- One batch in the drawer
--------------------------------------------------------------------------------

DebindShareBatchRowMixin = {};

--- What to call a batch. The source is free text the user typed at paste time and may be empty.
local function BatchTitle(batch)
    if (batch.source and batch.source ~= "") then
        return batch.source;
    end
    return LLL["IMPORT_BATCH_UNNAMED"];
end

function DebindShareBatchRowMixin:Init(elementData)
    self.elementData = elementData;
    local batch = elementData.batch;

    self.Name:SetText(BatchTitle(batch));
    self.Counts:SetText(format(LLL["IMPORT_BATCH_COUNTS"], batch.groupCount or 0,
        batch.actionCount or 0));

    self:UpdateAge();

    -- **The label says which of the two this press is**, because the second one is not a repeat of
    -- the first: it puts a second copy in. Leaving the button reading the same both times would
    -- make "did that work?" and "do it again" the same gesture.
    self.CommitButton:SetText(batch.committed and LLL["IMPORT_COMMIT_AGAIN"] or LLL["IMPORT_COMMIT"]);
    self.CommitButton:SetScript("OnClick", function() self:Bring(); end);
    self.CommitButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, button:GetText());
        GameTooltip_AddNormalLine(GameTooltip, LLL["IMPORT_COMMIT_DESC"]);
        GameTooltip:Show();
    end);
    self.CommitButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

    self.PinButton:SetChecked(batch.pinned == true);
    self.PinButton:SetScript("OnClick", function(button)
        batch.pinned = button:GetChecked() or nil;
        self:UpdateAge();
    end);
    self.PinButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, LLL["IMPORT_BATCH_PIN"]);
        GameTooltip_AddNormalLine(GameTooltip, LLL["IMPORT_BATCH_PIN_DESC"]);
        GameTooltip:Show();
    end);
    self.PinButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

    -- **Deleting asks first, and names what goes.** A batch is the only copy of a string somebody
    -- sent: once the drawer lets go of it the way back is to ask them for it again. The main
    -- window asks the same way before deleting an action, and for the same reason -- there is no
    -- undo, which is what separates these two from move and copy.
    self.DeleteButton:SetScript("OnClick", function()
        StaticPopup_ShowCustomGenericConfirmation({
            text = LLL["IMPORT_DELETE_CONFIRM"],
            text_arg1 = BatchTitle(batch),
            callback = function()
                DebindShare.DeleteBatch(batch.id);
                DebindShareImportPanel:Refresh();
            end,
            acceptText = YES,
            cancelText = NO,
            showAlert = true,
            referenceKey = "DebindShareDeleteBatch",
        });
    end);
    self.DeleteButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, LLL["IMPORT_BATCH_DELETE"]);
        GameTooltip:Show();
    end);
    self.DeleteButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);
end

--- How old it is, and how long it has left when that is worth saying.
---
--- **The two are one line because they are the same fact from either end.** A drawer that showed
--- only the age would leave the reader to work out when it goes; one that showed only the countdown
--- would stop saying anything at all the moment a batch is pinned.
function DebindShareBatchRowMixin:UpdateAge()
    local batch = self.elementData.batch;
    -- A floor of one minute, because `SecondsToTime(0)` answers with nothing at all and a row that
    -- says how old everything else is should not go blank for the one just added.
    local age = SecondsToTime(max(time() - batch.received, 60), true);

    local remaining = DebindShare.GetSecondsUntilExpiry(batch);
    if (remaining == nil) then
        self.Age:SetText(format(LLL["IMPORT_BATCH_AGE_PINNED"], age));
        self.Age:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
    elseif (remaining <= 0) then
        self.Age:SetText(LLL["IMPORT_BATCH_EXPIRED"]);
        self.Age:SetTextColor(ERROR_COLOR:GetRGB());
    elseif (DebindShare.IsExpiringSoon(batch)) then
        self.Age:SetText(format(LLL["IMPORT_BATCH_AGE_EXPIRING"], age,
            SecondsToTime(remaining, true)));
        self.Age:SetTextColor(DebindPrivate.DebindUI.WARNING_FONT_COLOR:GetRGB());
    else
        self.Age:SetText(format(LLL["IMPORT_BATCH_AGE"], age));
        self.Age:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
    end
end

--- Asks what to bring in, and from where.
---
--- **The string is read here rather than in the dialog**, so a batch that cannot be decoded any
--- more is turned down where it was pressed instead of opening a window with nothing in it.
function DebindShareBatchRowMixin:Bring()
    local batch = self.elementData.batch;

    local payload, reason = DebindShare.GetBatchPayload(batch);
    if (not payload) then
        DebindPrivate.DisplayMessage(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"], 1, 0, 0);
        return;
    end

    local lines = DebindShare.CollectImportLines(payload);
    if (#lines == 0) then
        -- Nothing in it has anywhere to go. There is no question to ask, so the answer is given
        -- straight rather than through a dialog with no lines on it.
        DebindPrivate.DisplayMessage(LLL["IMPORT_NOTHING_PLACED"], 1, 0, 0);
        return;
    end

    DebindShareBringFrame:Open(batch, lines);
end

function DebindShareBatchRowMixin:OnEnter()
    local batch = self.elementData.batch;

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, BatchTitle(batch));
    GameTooltip_AddNormalLine(GameTooltip, format(LLL["IMPORT_BATCH_COUNTS"],
        batch.groupCount or 0, batch.actionCount or 0));

    -- The sender's class is the only thing about them the string itself carries, and it is worth
    -- saying: it decides whether the class layers in there have anywhere of their own to land.
    if (batch.class) then
        local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[batch.class];
        GameTooltip_AddNormalLine(GameTooltip,
            format(LLL["IMPORT_BATCH_FROM_CLASS"], className or batch.class));
    end

    GameTooltip:Show();
end

function DebindShareBatchRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- Bringing one in
--------------------------------------------------------------------------------

DebindShareBringFrameMixin = {};

--- What each line is called.
---
--- **These name what is in the string, not where it goes**, which is why none of the window's own
--- label helpers can be used. `GetLayerLabel` and `GetSideTabaLabel` build every word out of *this*
--- character - `UnitName("player")`, `UnitClass("player")`, `GetSpecializationInfo` - so a mage's
--- string would stand a line reading "Druid" over the mage layer it is actually going to, and the
--- character lines would carry the reader's own name for somebody else's character.
---
--- The class comes from the string (`payload.class`, the only thing about the sender it carries).
--- The character has no name in it at all and is not supposed to: a string pasted into a public
--- channel must not ship a name the sender never typed. So that line is called by its scope.
local LINE_LABELS   = {
    ["shared.general"]     = "IMPORT_BRING_LINE_SHARED_GENERAL",
    ["shared.class"]       = "IMPORT_BRING_LINE_SHARED_CLASS",
    ["character.general"]  = "IMPORT_BRING_LINE_CHARACTER_GENERAL",
    ["character.spec"]     = "IMPORT_BRING_LINE_CHARACTER_SPEC",
};

--- Vertical geometry. The dialog grows with how many lines the string stood, so these are what the
--- height is added up from rather than numbers spread through the layout.
local TOP_INSET    = 34;
local SIDE_INSET   = 16;
local ROW_PITCH    = 24;
local GROUP_GAP    = 16;
local BOTTOM_INSET = 44;

function DebindShareBringFrameMixin:OnLoad()
    self.AcceptButton:SetText(LLL["IMPORT_COMMIT"]);
    self.AcceptButton:SetScript("OnClick", function() self:Accept(); end);

    self.CancelButton:SetText(CANCEL);
    self.CancelButton:SetScript("OnClick", function() self:Hide(); end);

    self.StripKeysButton.Label:SetText(LLL["EXPORT_STRIP_KEYS"]);
    -- The label is outside the frame, so pressing the words only ticks the box if the hit rect
    -- reaches over them. Locales disagree about how far, so the string is asked.
    self.StripKeysButton:SetHitRectInsets(0,
        -(self.StripKeysButton.Label:GetStringWidth() + 4), 0, 0);
    self.StripKeysButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, LLL["EXPORT_STRIP_KEYS"]);
        GameTooltip_AddNormalLine(GameTooltip, LLL["IMPORT_STRIP_KEYS_DESC"]);
        GameTooltip:Show();
    end);
    self.StripKeysButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

    -- The line checkboxes. Four at most (`IMPORT_LINES`), and made once: which of them are shown
    -- is the string's to say, but how many there could ever be is not.
    self.lineButtons = {};
    for i = 1, #DebindShare.IMPORT_LINES do
        local button = CreateFrame("CheckButton", nil, self, "MinimalCheckboxArtTemplate");
        button:SetSize(22, 22);
        button.Label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
        button.Label:SetPoint("LEFT", button, "RIGHT", 2, 0);
        -- **Nothing ticked is not an answer.** With every line off the press would place nothing and
        -- report it as a failure, so the button says so before it is pressed instead.
        button:SetScript("OnClick", function() self:UpdateAcceptButton(); end);
        button:Hide();
        self.lineButtons[i] = button;
    end

    self:RegisterForDrag("LeftButton");
    self:SetScript("OnDragStart", self.StartMoving);
    self:SetScript("OnDragStop", self.StopMovingOrSizing);

    -- ESC closes this and nothing else. `UISpecialFrames` cannot do that -- `CloseSpecialWindows`
    -- hides **every** shown frame in the list, so one press would take the window behind this with
    -- it. Every other key keeps going, or the keyboard stops answering while this is up.
    self:EnableKeyboard(true);
    self:SetScript("OnKeyDown", function(_, key)
        -- `SetPropagateKeyboardInput` is taint in combat. Entering combat hides the window behind
        -- this and takes the dialog with it (`DebindShareImportPanelMixin:OnHide`), so this is
        -- normally unreachable - but **a key pressed on the frame combat starts can arrive before
        -- PLAYER_REGEN_DISABLED.** The same one frame `DebindFrameMixin:OnKeyDown` blocks, blocked
        -- the same way: do nothing and stand down. That key is eaten and the dialog is gone next
        -- frame.
        if (InCombatLockdown()) then
            return;
        end

        local ours = key == "ESCAPE";
        self:SetPropagateKeyboardInput(not ours);
        if (ours) then
            self:Hide();
        end
    end);
end

--- Stands the dialog up for one press of [Bring it in].
---
--- **Everything is reset every time.** The answers here live exactly as long as the press that
--- opens it - that is the whole reason this is a dialog and not two checkboxes on the row - so a
--- tick left over from last time would be the failure this replaced.
function DebindShareBringFrameMixin:Open(batch, lines)
    self.batch = batch;

    self.TitleText:SetText(format(LLL["IMPORT_BRING_TITLE"], BatchTitle(batch)));

    --- **The class line names the class its actions are going to**, which is the descriptor's and
    --- not `payload.class`. The two agree in anything this addon builds; a hand-made string can
    --- disagree, and then the sender's class over somebody else's layer is the wrong one to print.
    --- The character line has no class of its own to read - specializations belong to whoever sent
    --- it - so that one falls back to what the string says about the sender.
    local function ClassName(entry)
        local class = entry.class or batch.class;
        if (not class) then
            return "";
        end
        return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class;
    end

    local function Place(region, x, y)
        region:ClearAllPoints();
        region:SetPoint("TOPLEFT", self, "TOPLEFT", x, y);
    end

    local y = -TOP_INSET;
    for i, button in ipairs(self.lineButtons) do
        local entry = lines[i];
        button:SetShown(entry ~= nil);
        if (entry) then
            button.line = entry.line;
            button.Label:SetText(format(LLL[LINE_LABELS[entry.line]], ClassName(entry)));
            -- The label is outside the frame, so pressing the words only ticks the box if the hit
            -- rect reaches over them. Locales disagree about how far, so the string is asked.
            button:SetHitRectInsets(0, -(button.Label:GetStringWidth() + 4), 0, 0);
            -- **Everything, by default.** Bringing all of it is what the reader came to do; the
            -- boxes are there for the one who wants less, and asking the other one to tick four
            -- things first would make the dialog a toll.
            button:SetChecked(true);
            Place(button, SIDE_INSET, y);
            y = y - ROW_PITCH;
        end
    end

    -- **Missing means unknown, and unknown shows it.** A batch stored before `hasKeys` existed has
    -- no answer, and hiding the control for those made the option look unbuilt on every row already
    -- in the drawer. Offering it on a keyless batch costs nothing - there is no key to drop - while
    -- hiding it on a batch that has keys costs the feature.
    local hasKeys = batch.hasKeys ~= false;
    self.StripKeysButton:SetShown(hasKeys);
    if (hasKeys) then
        y = y - GROUP_GAP;
        self.StripKeysButton:SetChecked(false);
        Place(self.StripKeysButton, SIDE_INSET, y);
        y = y - ROW_PITCH;
    end

    self:UpdateAcceptButton();
    self:SetHeight(-y + BOTTOM_INSET);
    self:Show();
    self:Raise();
end

--- Which lines were left ticked, as the set `PlanImport` filters on.
function DebindShareBringFrameMixin:SelectedLines()
    local selected = {};
    for _, button in ipairs(self.lineButtons) do
        if (button:IsShown() and button:GetChecked()) then
            selected[button.line] = true;
        end
    end
    return selected;
end

function DebindShareBringFrameMixin:UpdateAcceptButton()
    self.AcceptButton:SetEnabled(next(self:SelectedLines()) ~= nil);
end

--- Puts the batch into the profile, badged.
---
--- **The message afterwards is not decoration.** Everything that just landed is quarantined and
--- greyed out, so from the reader's side the screen barely moves: without a line saying what
--- happened and where to go next, a press that did a lot looks like a press that did nothing.
function DebindShareBringFrameMixin:Accept()
    local batch = self.batch;
    local placed, skipped = DebindShare.CommitBatch(batch, {
        lines = self:SelectedLines(),
        stripKeys = self.StripKeysButton:IsShown() and self.StripKeysButton:GetChecked() or nil,
    });

    self:Hide();

    if (not placed) then
        DebindPrivate.DisplayMessage(LLL[REASON_TEXT[skipped] or "IMPORT_FAILED_DAMAGED"], 1, 0, 0);
        return;
    end

    DebindPrivate.DisplayMessage(format(LLL["IMPORT_COMMITTED"], placed));
    -- Layers a newer schema invented and this one cannot place. Said separately because it is the
    -- one case where the count above is not the whole string. **Lines the reader unticked are not
    -- in here** - they said no, which is not this version having nowhere to put it.
    if (skipped and skipped > 0) then
        DebindPrivate.DisplayMessage(format(LLL["IMPORT_COMMITTED_SKIPPED"], skipped), 1, 0.5, 0);
    end

    DebindShareImportPanel:Refresh();

    -- **Overview has to be rebuilt too, and nothing else is going to do it.** The reader is
    -- standing on the Import tab, so the lists behind it were built before any of this existed;
    -- going back only shows the panel again (`SelectPanel`), it does not re-read the profile.
    -- Without this the actions that just landed are missing from Overview - and so is the strip
    -- that is the only way to accept them - until something unrelated happens to refresh it.
    --
    -- `UpdateBindings` is deliberately not called. Everything placed is badged and `BuildKeyMap`
    -- skips badged actions, so a rebuild here would spend the work to arrive at the key map that
    -- is already up. The bindings change when the reader accepts, not when they import.
    DebindFrame:Refresh(true);
    DebindFrame:Update();
end


--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

DebindShareImportPanelMixin = {};

function DebindShareImportPanelMixin:OnLoad()
    -- **What this panel asks the frame to be**, read by `SelectPanel`. Taken from the XML so the
    -- number lives with the rest of the geometry, and read now because after the frame takes
    -- delivery `GetWidth` answers with the host's width, which is this value fed back.
    --
    -- It is the export panel's width. The two tabs are lists of the same shape and a reader moving
    -- between them should not have the window change size under them.
    self.preferredWidth = self:GetWidth();

    self.PasteButton:SetText(LLL["IMPORT_PASTE"]);
    self.PasteButton:SetScript("OnClick", function() DebindSharePasteFrame:Open(); end);

    self:InitializeScrollBox();
end

function DebindShareImportPanelMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory)
        factory("DebindShareBatchRowTemplate", function(frame, data) frame:Init(data); end);
    end);
    view:SetElementExtentCalculator(function() return ROW_HEIGHT; end);

    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

--- Newest first. The drawer is read from the top by someone who just pasted something, and what
--- they are looking for is almost always what they just put in.
function DebindShareImportPanelMixin:Refresh()
    local batches = DebindShare.GetBatches();

    local list = {};
    for _, batch in ipairs(batches) do
        list[#list + 1] = { batch = batch };
    end
    sort(list, function(lhs, rhs) return lhs.batch.id > rhs.batch.id; end);

    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(LLL["IMPORT_DRAWER_EMPTY"]);
    self.ScrollBox.EmptyText:SetShown(#list == 0);

    self.HeaderHolder.Text:SetText(#list > 0 and format(LLL["IMPORT_DRAWER_COUNT"], #list) or "");
end

function DebindShareImportPanelMixin:OnShow()
    self:Refresh();
end

function DebindShareImportPanelMixin:OnHide()
    -- **Nothing is thrown away here.** The export panel drops its selection on hide because it
    -- holds references to live action tables that can be deleted while it is away; a batch is the
    -- opposite -- plain stored data whose whole purpose is to survive being closed, and a
    -- `/reload` after that.
    --
    -- The two dialogs do go. The paste box is half-typed input, and unlike the export tab's copy
    -- dialog what it holds is not yet worth anything to anybody: a finished string outliving its
    -- tab is useful, an unfinished paste floating over Overview is not. The bring dialog is the
    -- stronger case - its answers belong to one press of one row's button, and a row that is no
    -- longer on screen has no press to belong to.
    DebindSharePasteFrame:Hide();
    DebindShareBringFrame:Hide();
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- Pasting one in
--------------------------------------------------------------------------------

DebindSharePasteFrameMixin = {};

function DebindSharePasteFrameMixin:OnLoad()
    self.TitleText:SetText(LLL["IMPORT_PASTE_TITLE"]);
    self.SourceBox.Label:SetText(LLL["IMPORT_PASTE_SOURCE"]);
    self.AcceptButton:SetText(LLL["IMPORT_PASTE_ACCEPT"]);

    self:RegisterForDrag("LeftButton");
    self:SetScript("OnDragStart", self.StartMoving);
    self:SetScript("OnDragStop", self.StopMovingOrSizing);

    local editBox = self.Input.EditBox;
    editBox:SetFontObject(ChatFontNormal);

    -- Typing clears the last refusal. Leaving it up would have the dialog explaining a string that
    -- is no longer the one in the box.
    editBox:SetScript("OnTextChanged", function()
        self.ErrorHolder.Text:SetText("");
        self.AcceptButton:SetEnabled(strtrim(editBox:GetText()) ~= "");
    end);
    editBox:SetScript("OnEscapePressed", function()
        editBox:ClearFocus();
        self:Hide();
    end);

    self.AcceptButton:SetScript("OnClick", function() self:Accept(); end);

    -- ESC closes this one on its own. It is a dialog rather than a panel, so unlike the tabs it has
    -- a close of its own to be.
    tinsert(UISpecialFrames, self:GetName());
end

function DebindSharePasteFrameMixin:Open()
    self:Show();
    self.Input.EditBox:SetFocus();
end

function DebindSharePasteFrameMixin:OnShow()
    self.Input.EditBox:SetText("");
    self.SourceBox:SetText("");
    self.ErrorHolder.Text:SetText("");
    self.AcceptButton:SetEnabled(false);
end

--- **A refusal stays in this dialog.** The string is someone else's input and every step of reading
--- it is allowed to fail, so the one place a failure can be acted on is the one still holding the
--- text that caused it. Closing first and reporting into the chat frame would leave the reader with
--- a message and nothing to fix.
function DebindSharePasteFrameMixin:Accept()
    local source = strtrim(self.SourceBox:GetText());
    local batch, reason = DebindShare.AddBatch(self.Input.EditBox:GetText(),
        source ~= "" and source or nil);

    if (not batch) then
        self.ErrorHolder.Text:SetText(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"]);
        return;
    end

    self:Hide();
    DebindShareImportPanel:Refresh();
end
