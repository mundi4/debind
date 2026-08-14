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
    self.CommitButton:SetScript("OnClick", function() self:Commit(); end);
    self.CommitButton:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, button:GetText());
        GameTooltip_AddNormalLine(GameTooltip, LLL["IMPORT_COMMIT_DESC"]);
        GameTooltip:Show();
    end);
    self.CommitButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

    -- Nothing to switch off for a string that arrived without keys, and a box there would suggest
    -- otherwise. `hasKeys` was counted at paste time so drawing a row never decodes the string.
    --
    -- **Missing means unknown, and unknown shows it.** A batch stored before that field existed has
    -- no answer, and hiding the control for those made the option look unbuilt on every row already
    -- in the drawer. Offering it on a keyless batch costs nothing - `stripKeys` has no key to drop -
    -- while hiding it on a batch that has keys costs the feature.
    local strip = self.StripKeysButton;
    local hasKeys = batch.hasKeys ~= false;
    strip:SetShown(hasKeys);
    if (hasKeys) then
        strip.Label:SetText(LLL["EXPORT_STRIP_KEYS"]);
        -- The label is outside the frame, so pressing the words only ticks the box if the hit rect
        -- reaches over them. Locales disagree about how far, so the string is asked.
        strip:SetHitRectInsets(-(strip.Label:GetStringWidth() + 4), 0, 0, 0);
        strip:SetChecked(batch.stripKeys == true);
        strip:SetScript("OnClick", function(button)
            batch.stripKeys = button:GetChecked() or nil;
        end);
        strip:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
            GameTooltip_SetTitle(GameTooltip, LLL["EXPORT_STRIP_KEYS"]);
            GameTooltip_AddNormalLine(GameTooltip, LLL["IMPORT_STRIP_KEYS_DESC"]);
            GameTooltip:Show();
        end);
        strip:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    end

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

--- Puts this batch into the profile, badged.
---
--- **The message afterwards is not decoration.** Everything that just landed is quarantined and
--- greyed out, so from the reader's side the screen barely moves: without a line saying what
--- happened and where to go next, a press that did a lot looks like a press that did nothing.
function DebindShareBatchRowMixin:Commit()
    local batch = self.elementData.batch;
    local placed, skipped = DebindShare.CommitBatch(batch);

    if (not placed) then
        DebindPrivate.DisplayMessage(LLL[REASON_TEXT[skipped] or "IMPORT_FAILED_DAMAGED"], 1, 0, 0);
        return;
    end

    DebindPrivate.DisplayMessage(format(LLL["IMPORT_COMMITTED"], placed));
    -- Layers a newer schema invented and this one cannot place. Said separately because it is the
    -- one case where the count above is not the whole string.
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
    -- The paste dialog does go. It is a box with half-typed input in it, and unlike the export
    -- tab's copy dialog what it holds is not yet worth anything to anybody: a finished string
    -- outliving its tab is useful, an unfinished paste floating over Overview is not.
    DebindSharePasteFrame:Hide();
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
