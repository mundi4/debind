local _, DebindPrivate = ...;

local LLL           = DebindPrivate.L;

--- The addon that keeps the drawer, parked here when it loads (`EnsureStore` in `DebindUI.lua`).
---
--- **Read at call time and never at file scope.** This file is read at login and that one is load
--- on demand, so a local taken up here would be `nil` forever.
---
--- Nothing below guards the result, because everything that calls it is reached from a panel that
--- `ResolvePanel` refused to show until the load succeeded.
---
--- ⚠ **`OnLoad` is not one of those places.** These frames are built when this file is read, which
--- is login, and that is *before* any of it. It held while this file belonged to the other addon -
--- then `OnLoad` ran inside its load - and the addon boundary move quietly broke it: what an
--- `OnLoad` asked the store for came back `nil`, at login, with nothing said about it.
local function Store()
    return DebindPrivate.Store;
end

--- The main window's Import tab.
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
    -- **The other direction, and the advice is opposite.** "Update and try again" is what the line
    -- above says, and saying it here would tell a reader to do the thing they have already done -
    -- this is a string from *before* the schema they are on. Nothing they can do fixes it, so the
    -- sentence says that instead of asking.
    SCHEMA_TOO_OLD        = "IMPORT_FAILED_TOO_OLD",
    -- It began as one of ours and stopped being readable partway. Far and away the likeliest cause
    -- is a copy that lost its tail, which is worth saying because the fix is to copy it again.
    BAD_ENCODING          = "IMPORT_FAILED_DAMAGED",
    BAD_COMPRESSION       = "IMPORT_FAILED_DAMAGED",
    BAD_PAYLOAD           = "IMPORT_FAILED_DAMAGED",
    -- It read fine and holds something Debind cannot make, which means it was edited after it was
    -- created (`DebindStorage/Import.lua`). A separate code because that is not the same fact as
    -- the three above, and the same line because the reader's answer to all four is the same: the
    -- string in front of them is not usable and the one to have is a fresh one.
    IMPOSSIBLE_PAYLOAD    = "IMPORT_FAILED_DAMAGED",
    -- Nothing the reader did. The addon's own libraries did not load.
    LIBS_MISSING          = "IMPORT_FAILED_LIBS_MISSING",
    -- Not a failure to read it. Everything picked turned out to have nowhere to go, which one
    -- ordinary case reaches: a string from a character whose class has specializations this one
    -- does not (`ImportAddress`).
    NOTHING_TO_PLACE      = "IMPORT_NOTHING_PLACED",
};


--------------------------------------------------------------------------------
-- The lines the reader is offered
--------------------------------------------------------------------------------

--- **These sit on the private table because the other addon asks as well.** `PlanImport` is handed
--- the lines the reader left ticked and has to know which one each address falls on, so it reads
--- `ImportLineFor` back out of here (`DebindStorage/Import.lua`).
---
--- They used to stand next to the payload walk they call, which left one half of a line over there
--- and the other half here, where each one is given its name (`LINE_LABELS`). A dialog built out
--- of something other than lines was a change to two addons, one of them load on demand.

--- What the bring dialog puts a checkbox on, in the order the window's own tab strip stands in.
---
--- **Four lines, not one per layer.** The spec layers ride along on the line above them rather than
--- standing on their own: a string from a four-spec class would otherwise open with ten rows, and
--- ticking spec 3 but not spec 2 is a decision nobody arrives wanting to make. What is worth
--- separating is the two things that differ in *who they reach* -- everything on this account
--- versus this one character.
local IMPORT_LINES  = {
    "shared.general",
    "shared.class",
    "character.general",
    "character.spec",
};

--- Which line an address belongs to, or nil for one no line covers.
function DebindPrivate.ImportLineFor(scope, spec)
    if (scope == "general") then
        return "shared.general";
    elseif (scope == "class") then
        return "shared.class";
    elseif (scope == "character") then
        return (spec or 0) > 0 and "character.spec" or "character.general";
    end
    return nil;
end

--- Which of the four lines this payload actually has something on, in `IMPORT_LINES` order.
---
--- **Only what can land counts.** A line the string does not carry, and a line whose every action
--- has nowhere to go, are the same thing to the reader: a checkbox that reads as a choice and does
--- nothing either way. A payload with no line at all is one there is no question to ask about.
---
--- **Counted over actions, not groups.** A group is a key now and a key crosses layers, so one
--- group can put actions on two lines and there is no number of groups a line owns.
---
--- `class` rides along on the class line, taken from the descriptors rather than from
--- `payload.class`: the label has to name the class the actions are actually going to. It is absent
--- when the line holds more than one, which the export cannot produce and a hand-made string can.
function DebindPrivate.CollectImportLines(payload)
    local counts, classLine = {}, nil;

    Store().ForEachPayloadLayer(payload, function(list, scope, class, spec)
        -- **The address is vetted first**, the same order `PlanImport` reads them in. `ImportAddress`
        -- is the only place `spec` is checked for being a number at all, and the line function
        -- compares it against 0 -- asked the other way round, a payload keyed `char = { ["2"] = … }`
        -- raises where the reader can only see a dead button.
        if (Store().ImportAddress(scope, class, spec)) then
            local line = DebindPrivate.ImportLineFor(scope, spec);
            if (line) then
                counts[line] = (counts[line] or 0) + #list;
                if (line == "shared.class") then
                    if (classLine == nil) then
                        classLine = class;
                    elseif (classLine ~= class) then
                        classLine = false;
                    end
                end
            end
        end
    end);

    local lines = {};
    for _, line in ipairs(IMPORT_LINES) do
        -- **Zero is not "some".** An empty layer list adds nothing to the count, and `if (count)`
        -- would stand the checkbox up anyway -- 0 is true in Lua. The reader would tick a line that
        -- places nothing and be answered with an error by the dialog that just offered it.
        if ((counts[line] or 0) > 0) then
            lines[#lines + 1] = {
                line = line,
                actionCount = counts[line],
                class = line == "shared.class" and classLine or nil,
            };
        end
    end
    return lines;
end

--------------------------------------------------------------------------------
-- One batch in the drawer
--------------------------------------------------------------------------------

DebindImportBatchRowMixin = {};

--- The class the batch says it came from, or nil.
---
--- **Read off the payload, which is what the drawer stores.** The record carried a copy of this
--- while the drawer stored the string instead, because reading it meant decoding
--- (`DebindStorage/Import.lua`).
local function BatchClass(batch)
    if (not batch.payload) then
        return nil;
    end
    return batch.payload.class;
end

--- The row's top line: **the date it arrived, and for now nothing else.**
---
--- **The date, not how old it is.** A relative age answers "is this the one I just pasted", which
--- is only a question for a minute or two; a list that piles up is read by when things came in.
local function BatchDate(batch)
    local when = date("*t", batch.received);
    return FormatShortDate(when.day, when.month, when.year);
end

--- The class the string says it came from, in that class's colour, or nil when it says nothing.
---
--- `GetClassColorObj` answers nil for a token it does not know. A payload carrying a class name
--- this client has never heard of is turned away long before here (`PayloadIsImpossible`), but the
--- fallback costs one `or`.
local function BatchClassText(batch)
    local class = BatchClass(batch);
    if (not class) then
        return nil;
    end

    local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class;
    local color = GetClassColorObj(class) or NORMAL_FONT_COLOR;
    return color:WrapTextInColorCode(name);
end

--- What to call one batch in a sentence. The delete prompt is the one place there is: it names
--- what is about to go, inside a line of prose, with no second line to put anything on.
---
--- **The date alone would not do here.** The row, its tooltip and the bring dialog can all lead
--- with the date because the class is a line away in each of them; a prompt asking whether to
--- remove "8/18/2026" has nowhere to put the rest, and two strings pasted the same day would read
--- identically at the one moment there is no undo.
local function BatchLabel(batch)
    local class = BatchClassText(batch);
    local stamp = BatchDate(batch);
    if (not class) then
        return stamp;
    end
    return format(LLL["IMPORT_BATCH_LINE"], class, stamp);
end

function DebindImportBatchRowMixin:Init(elementData)
    self.elementData = elementData;
    local batch = elementData.batch;

    self.Name:SetText(BatchDate(batch));

    -- **The class goes on the lower line, in front of the counts.** Both halves say what is in the
    -- string rather than what the reader did with it, so they read as one line; the date on its own
    -- above is the only thing that orders the list.
    local counts = format(LLL["IMPORT_BATCH_COUNTS"], Store().CountBatch(batch));
    local class = BatchClassText(batch);
    self.Counts:SetText(class and format(LLL["IMPORT_BATCH_LINE"], class, counts) or counts);

    -- **No pin, because nothing sweeps.** A pin takes a batch out of a clear-out, and there is no
    -- clear-out: `AddBatch` appends and only this row's delete button ever removes one. A control
    -- that exempts you from something that does not happen is a control that does nothing, and the
    -- sentence beside it ("cleared out after about a month") was the drawer promising a behaviour
    -- it does not have. The design for that is not rejected -- it is waiting on a clear-out that
    -- **asks** rather than sweeps, which is the one thing this drawer may not do silently
    -- (`devdocs/building-export-import.md`).

    -- **Deleting asks first, and names what goes.** A batch is the only copy of a string somebody
    -- sent: once the drawer lets go of it the way back is to ask them for it again. The main
    -- window asks the same way before deleting an action, and for the same reason -- there is no
    -- undo, which is what separates these two from move and copy.
    self.DeleteButton:SetScript("OnClick", function()
        StaticPopup_ShowCustomGenericConfirmation({
            text = LLL["IMPORT_DELETE_CONFIRM"],
            text_arg1 = BatchLabel(batch),
            callback = function()
                -- **The dialog goes first, because it holds this batch by reference.** Deleting a
                -- row only takes it out of the drawer; the open dialog's copy still decodes and
                -- still commits, so [accept] after this would import in full the batch they just
                -- confirmed removing - and leave no row to take it back from.
                DebindBringFrame:DismissFor(batch);
                Store().DeleteBatch(batch.id);
                DebindImportPanel:Refresh();
            end,
            acceptText = YES,
            cancelText = NO,
            showAlert = true,
            referenceKey = "DebindDeleteBatch",
        });
    end);
end

--- Asks what to bring in, and from where.
---
--- **The string is read here rather than in the dialog**, so a batch that cannot be decoded any
--- more is turned down where it was pressed instead of opening a window with nothing in it.
function DebindImportBatchRowMixin:OnClick()
    self:Bring();
end

function DebindImportBatchRowMixin:Bring()
    local batch = self.elementData.batch;

    local payload, reason = Store().GetBatchPayload(batch);
    if (not payload) then
        DebindPrivate.DisplayMessage(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"], 1, 0, 0);
        return;
    end

    local lines = DebindPrivate.CollectImportLines(payload);
    if (#lines == 0) then
        -- Nothing in it has anywhere to go. There is no question to ask, so the answer is given
        -- straight rather than through a dialog with no lines on it.
        DebindPrivate.DisplayMessage(LLL["IMPORT_NOTHING_PLACED"], 1, 0, 0);
        return;
    end

    DebindBringFrame:Open(batch, lines);
end

function DebindImportBatchRowMixin:OnEnter()
    local batch = self.elementData.batch;

    -- **The row's own two lines, in the same order.** The title is the date and the line under it
    -- is the class beside the counts, which is what the row itself draws - a tooltip that regroups
    -- them reads as being about something else.
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, BatchDate(batch));

    local counts = format(LLL["IMPORT_BATCH_COUNTS"], Store().CountBatch(batch));
    local class = BatchClassText(batch);
    GameTooltip_AddNormalLine(GameTooltip,
        class and format(LLL["IMPORT_BATCH_LINE"], class, counts) or counts);

    -- **What the reader called it, which is the only thing here a person wrote.** It was the row's
    -- title and could not stay there: it is optional, and the stand-in it fell back to named
    -- nothing. Here being absent costs the tooltip a line rather than the list its only way to tell
    -- rows apart.
    --
    -- No caption in front of it. It is the reader's own words, and a label on them would be the
    -- tooltip explaining the reader to themselves.
    if (batch.name and batch.name ~= "") then
        GameTooltip_AddNormalLine(GameTooltip, batch.name);
    end

    -- **What the row does, since nothing on it says so any more.** A labelled button carried this
    -- and named the act in its own text; a row that answers a click has to say what the click is
    -- for somewhere, and the tooltip is where this list already explains itself.
    GameTooltip_AddInstructionLine(GameTooltip, LLL["IMPORT_COMMIT_DESC"]);

    GameTooltip:Show();
end

function DebindImportBatchRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- Bringing one in
--------------------------------------------------------------------------------

DebindBringFrameMixin = {};

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

--- **This dialog is the one that grows**, so its height is added up rather than written in the XML.
--- Where the rows *start* is not part of that sum: they hang off `ContentArea`, which every dialog
--- places against (`DebindDialogTemplate`). Only the two numbers this dialog actually owns are here.
---
--- `CHROME_HEIGHT` is everything above and below the rows, **written as its parts** because it was
--- a single number and the number was three short: the rows run down from `ContentArea`'s top and
--- the buttons sit on its bottom, so anything missing from this sum comes out of the space between
--- them. At 84 there was none left and the buttons touched the last checkbox.
---
--- The two insets are `DebindDialogTemplate`'s and have to be repeated here rather than measured:
--- `ContentArea` is placed in XML, so at the moment this runs its height is the old one.
local ROW_PITCH       = 24;
local CONTENT_TOP     = 40;   -- ContentArea's top inset
local CONTENT_BOTTOM  = 25;   -- its bottom inset, which is the margin under the buttons
local BUTTON_HEIGHT   = 22;
local BUTTON_GAP      = 16;   -- between the last row and the buttons
local CHROME_HEIGHT   = CONTENT_TOP + CONTENT_BOTTOM + BUTTON_HEIGHT + BUTTON_GAP;

function DebindBringFrameMixin:OnLoad()
    self:InitDialog();

    self.AcceptButton:SetText(LLL["IMPORT_COMMIT"]);
    self.AcceptButton:SetScript("OnClick", function() self:Accept(); end);

    self.CancelButton:SetText(CANCEL);
    self.CancelButton:SetScript("OnClick", function() self:Hide(); end);
end

--- The line checkboxes. Four at most (`IMPORT_LINES`), and made once: which of them are shown is
--- the string's to say, but how many there could ever be is not.
---
--- **Made on the first open and not in `OnLoad`**, which is login: four frames for a reader who
--- never opens this tab are four frames nobody asked for, and this addon is arranged around not
--- paying for sharing until somebody shares. The only way here is a row in the drawer.
local function EnsureLineButtons(self)
    if (self.lineButtons) then
        return;
    end

    self.lineButtons = {};
    for i = 1, #IMPORT_LINES do
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
end

--- Stands the dialog up for one press of [Bring it in].
---
--- **Everything is reset every time.** The answers here live exactly as long as the press that
--- opens it - that is the whole reason this is a dialog and not two checkboxes on the row - so a
--- tick left over from last time would be the failure this replaced.
function DebindBringFrameMixin:Open(batch, lines)
    EnsureLineButtons(self);
    self.batch = batch;

    self.Title:SetText(format(LLL["IMPORT_BRING_TITLE"], BatchDate(batch)));

    --- **The class line names the class its actions are going to**, which is the descriptor's and
    --- not `payload.class`. The two agree in anything this addon builds; a hand-made string can
    --- disagree, and then the sender's class over somebody else's layer is the wrong one to print.
    --- The character line has no class of its own to read - specializations belong to whoever sent
    --- it - so that one falls back to what the string says about the sender.
    local function ClassName(entry)
        local class = entry.class or BatchClass(batch);
        if (not class) then
            return "";
        end
        return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class;
    end

    local function Place(region, y)
        region:ClearAllPoints();
        region:SetPoint("TOPLEFT", self.ContentArea, "TOPLEFT", 0, y);
    end

    local rows = 0;
    local y = 0;
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
            Place(button, y);
            y = y - ROW_PITCH;
            rows = rows + 1;
        end
    end

    self:UpdateAcceptButton();
    self:SetHeight(rows * ROW_PITCH + CHROME_HEIGHT);
    self:Show();
    self:Raise();
end

--- Which lines were left ticked, as the set `PlanImport` filters on.
function DebindBringFrameMixin:SelectedLines()
    local selected = {};
    for _, button in ipairs(self.lineButtons) do
        if (button:IsShown() and button:GetChecked()) then
            selected[button.line] = true;
        end
    end
    return selected;
end

--- Shuts the dialog if it is standing on `batch`, and does nothing otherwise.
---
--- **The answers in here belong to one press of one row's button**, and a row that is going away
--- has no press left to belong to. `DebindImportPanelMixin:OnHide` closes it for the same
--- reason when the whole tab leaves.
function DebindBringFrameMixin:DismissFor(batch)
    if (self:IsShown() and self.batch == batch) then
        self:Hide();
    end
end

function DebindBringFrameMixin:UpdateAcceptButton()
    self.AcceptButton:SetEnabled(next(self:SelectedLines()) ~= nil);
end

--- Puts the batch into the profile, badged.
---
--- **The message afterwards is not decoration.** Everything that just landed is quarantined and
--- greyed out, so from the reader's side the screen barely moves: without a line saying what
--- happened and where to go next, a press that did a lot looks like a press that did nothing.
function DebindBringFrameMixin:Accept()
    local batch = self.batch;
    local placed, skipped = Store().CommitBatch(batch, {
        lines = self:SelectedLines(),
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

    DebindImportPanel:Refresh();

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

DebindImportPanelMixin = {};

function DebindImportPanelMixin:OnLoad()
    -- **What this panel asks the frame to be** is a `KeyValue` in the XML, read by `SelectPanel`.
    -- It is the export panel's width: the two tabs are lists of the same shape and a reader moving
    -- between them should not have the window change size under them.

    self.PasteButton:SetText(LLL["IMPORT_PASTE"]);
    self.PasteButton:SetScript("OnClick", function() DebindPasteFrame:Open(); end);

    self:InitializeScrollBox();
end

function DebindImportPanelMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory)
        factory("DebindImportBatchRowTemplate", function(frame, data) frame:Init(data); end);
    end);
    view:SetElementExtentCalculator(function() return ROW_HEIGHT; end);

    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

--- Newest first. The drawer is read from the top by someone who just pasted something, and what
--- they are looking for is almost always what they just put in.
function DebindImportPanelMixin:Refresh()
    local batches = Store().GetBatches();

    local list = {};
    for _, batch in ipairs(batches) do
        list[#list + 1] = { batch = batch };
    end
    sort(list, function(lhs, rhs) return lhs.batch.id > rhs.batch.id; end);

    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(LLL["IMPORT_DRAWER_EMPTY"]);
    self.ScrollBox.EmptyText:SetShown(#list == 0);
end

function DebindImportPanelMixin:OnShow()
    self:Refresh();
end

function DebindImportPanelMixin:OnHide()
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
    DebindPasteFrame:Hide();
    DebindBringFrame:Hide();
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- Pasting one in
--------------------------------------------------------------------------------

DebindPasteFrameMixin = {};

function DebindPasteFrameMixin:OnLoad()
    self:InitDialog(LLL["IMPORT_PASTE_TITLE"]);
    self.InputLabel:SetText(LLL["IMPORT_PASTE_INPUT_LABEL"]);
    self.NameBox.Label:SetText(LLL["IMPORT_PASTE_NAME"]);
    self.AcceptButton:SetText(LLL["IMPORT_PASTE_ACCEPT"]);

    -- The placeholder inside the box, which the template hands out a setter for. The `instructions`
    -- KeyValue would do it in the XML, but it resolves a **global** name and ours is an `L` key.
    InputScrollFrame_SetInstructions(self.Input, LLL["IMPORT_PASTE_INSTRUCTIONS"]);

    local editBox = self.Input.EditBox;
    editBox:SetFontObject(ChatFontNormal);

    -- **The template's own handler runs first, and dropping it is not free.** It is the only thing
    -- that hides `Instructions` (`self.Instructions:SetShown(self:GetText() == "")`), and it also
    -- re-measures the scroll range and updates the character count. Replacing it outright - which
    -- this did until the placeholder above was added and the two met - left the grey sentence
    -- drawn on top of the pasted string for as long as the dialog stood.
    --
    -- **Not `InputBoxInstructions_OnTextChanged`**, which is the search boxes' one
    -- (`DebindUI.lua`, `SpellPicker.lua`). That is a different template with a different region.
    --
    -- Ours after it: typing clears the last refusal, because leaving it up would have the dialog
    -- explaining a string that is no longer the one in the box.
    editBox:SetScript("OnTextChanged", function(box, isUserInput)
        InputScrollFrame_OnTextChanged(box, isUserInput);
        self.ErrorHolder.Text:SetText("");
        self.AcceptButton:SetEnabled(strtrim(box:GetText()) ~= "");
    end);
    editBox:SetScript("OnEscapePressed", function()
        editBox:ClearFocus();
        self:Hide();
    end);

    self.AcceptButton:SetScript("OnClick", function() self:Accept(); end);
    self.CancelButton:SetScript("OnClick", function() self:Hide(); end);
end

function DebindPasteFrameMixin:Open()
    self:Show();
    self.Input.EditBox:SetFocus();
end

function DebindPasteFrameMixin:OnShow()
    self.Input.EditBox:SetText("");
    self.NameBox:SetText("");
    self.ErrorHolder.Text:SetText("");
    self.AcceptButton:SetEnabled(false);
end

--- **A refusal stays in this dialog.** The string is someone else's input and every step of reading
--- it is allowed to fail, so the one place a failure can be acted on is the one still holding the
--- text that caused it. Closing first and reporting into the chat frame would leave the reader with
--- a message and nothing to fix.
function DebindPasteFrameMixin:Accept()
    local name = strtrim(self.NameBox:GetText());
    local batch, reason = Store().AddBatch(self.Input.EditBox:GetText(),
        name ~= "" and name or nil);

    if (not batch) then
        self.ErrorHolder.Text:SetText(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"]);
        return;
    end

    self:Hide();
    DebindImportPanel:Refresh();
end
