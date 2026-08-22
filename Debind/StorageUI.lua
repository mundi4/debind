local _, DebindPrivate = ...;

local LLL           = DebindPrivate.L;
local DebindUI      = DebindPrivate.DebindUI;

--- The addon that keeps the store, parked here when it loads (`EnsureStore` in `DebindUI.lua`).
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

--- The main window's Storage tab. Two columns: the entries on the left, the one that is picked on
--- the right.
---
--- **It was two tabs.** Making a string and taking one in pointed opposite ways at the same thing,
--- and the thing is what they had in common: a payload is not a step on the way in or out any more
--- but an item that sits in a list, gets edited, and is used again (12절 of
--- `devdocs/building-export-import.md`). So there are four verbs on one screen -- make one from
--- this profile, take one in from a string, put one into the profile, turn one into a string --
--- and all four act on a row of the same list.
---
--- **Nothing in this file touches the profile except through the store.** An entry sits outside it
--- until it is added, which is the decision the whole design turns on: once actions are in the
--- profile they scatter, and the group identity the string arrived with is held nowhere.
---
--- **The right column shows what a payload holds, not what the profile holds.** Everything it
--- names comes out of the payload's own addresses and the payload's own manifest -- a label built
--- from this character would caption somebody else's layers with this reader's class and name
--- (`GetLayerLabel`, and 3절 on why the bring dialog needed labels of its own).

--- One row of the left column: two lines and a delete button.
local ENTRY_ROW_HEIGHT   = 44;

--- The right column, which is the export list's three rungs.
local PREVIEW_ROW_HEIGHT = 28;
local LAYER_HEIGHT       = 26;
local ROW_INDENT         = 10;

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
-- Tri-state
--
-- **No new art was needed.** The addon list solves the same problem (`AddonList.lua`'s
-- `TriStateCheckbox_SetState`) by dimming its check, and everything below is built out of stock
-- atlases the same way.
--------------------------------------------------------------------------------

local STATE_NONE       = 0;
local STATE_SOME       = 1;
local STATE_ALL        = 2;

--- **The middle state gets its own mark, not a faded tick.** The addon list settles for dimming its
--- check (`TriStateCheckbox_SetState`), but a dimmer tick is still a tick: at a glance it says "all
--- of them", which is the one thing this state must not say. Shape carries further than shade, so
--- the dash is what changes.
local CHECK_ALL        = "checkmark-minimal";
local CHECK_SOME       = "common-icon-minus";

--- How much of the box the mark fills. Neither atlas is drawn to sit inside `checkbox-minimal` -
--- at their own sizes the tick overflows the box and the dash is unrelated to it again - so the
--- size comes from the button and both marks take the same share of it. One number to move.
local MARK_SCALE       = 1;

--- **The dash gets its own share, smaller.** The two atlases are drawn to different margins:
--- `checkmark-minimal` carries whitespace inside its canvas and `common-icon-minus` runs edge to
--- edge, so giving them the same box makes the dash come out looking like the larger mark.
local SOME_MARK_SCALE  = 0.55;

local function SetMark(checkButton, atlas)
    local mark = checkButton:GetCheckedTexture();
    local size = checkButton:GetWidth()
        * (atlas == CHECK_SOME and SOME_MARK_SCALE or MARK_SCALE);
    -- `false`, not `true`: the atlas must not take the size back, or the `SetSize` below is undone.
    mark:SetAtlas(atlas, false);
    mark:SetSize(size, size);
end

--- **Every checkbox in this panel goes through here once, tri-state or not.**
---
--- The template's checked texture carries no anchors of its own, so it stretches to fill the whole
--- button - and a `SetSize` on something pinned on both sides does nothing. Pinning one point is
--- what puts the size under our control.
---
--- **Centred on the box art, not on the button.** The box is drawn at its atlas size while the
--- button is whatever the XML asked for, so those two are only the same rectangle by accident.
local function NormalizeCheckMark(checkButton)
    local mark = checkButton:GetCheckedTexture();
    mark:ClearAllPoints();
    mark:SetPoint("CENTER", checkButton:GetNormalTexture(), "CENTER");
    SetMark(checkButton, CHECK_ALL);
end

--- Puts a checkbox's caption inside its hit area.
---
--- A word sitting against a box is read as part of the control, so it has to behave like one.
--- Called again whenever the caption changes - the reach has to follow the text, not the text it
--- happened to have at load.
local function ExtendHitRectOverLabel(checkButton)
    checkButton:SetHitRectInsets(0, -(checkButton.Text:GetStringWidth() + 4), 0, 0);
end

local function SetTriState(checkButton, state)
    if (state == STATE_NONE) then
        checkButton:SetChecked(false);
        return;
    end

    checkButton:SetChecked(true);
    SetMark(checkButton, state == STATE_SOME and CHECK_SOME or CHECK_ALL);
end

--- What a set of actions adds up to, and how many of them are picked. `nil` for an empty set --
--- callers decide whether that reads as "none" (a layer with nothing in it) or as nothing at all.
---
--- **The count comes back with the state because everything that draws one draws the other**: a
--- layer header prints `(n/m)` beside its box and the top row prints its own total beside its box.
local function CombineState(actions, selected)
    local selectedCount = 0;
    for i = 1, #actions do
        if (selected[actions[i]]) then
            selectedCount = selectedCount + 1;
        end
    end

    if (#actions == 0) then
        return nil, 0;
    elseif (selectedCount == 0) then
        return STATE_NONE, 0;
    elseif (selectedCount == #actions) then
        return STATE_ALL, selectedCount;
    end
    return STATE_SOME, selectedCount;
end


--------------------------------------------------------------------------------
-- One entry in the list
--------------------------------------------------------------------------------

DebindStorageEntryRowMixin = {};

--- The class the entry says it came from, or nil.
---
--- **Read off the payload, which is what the drawer stores.** The record carried a copy of this
--- while the drawer stored the string instead, because reading it meant decoding
--- (`DebindStorage/Import.lua`).
local function EntryClass(entry)
    if (not entry.payload) then
        return nil;
    end
    return entry.payload.class;
end

--- The row's top line: **the date it arrived, and for now nothing else.**
---
--- **The date, not how old it is.** A relative age answers "is this the one I just pasted", which
--- is only a question for a minute or two; a list that piles up is read by when things came in.
local function EntryDate(entry)
    local when = date("*t", entry.received);
    return FormatShortDate(when.day, when.month, when.year);
end

--- The class the string says it came from, in that class's colour, or nil when it says nothing.
---
--- `GetClassColorObj` answers nil for a token it does not know. A payload carrying a class name
--- this client has never heard of is turned away long before here (`PayloadIsImpossible`), but the
--- fallback costs one `or`.
local function EntryClassText(entry)
    local class = EntryClass(entry);
    if (not class) then
        return nil;
    end

    local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class;
    local color = GetClassColorObj(class) or NORMAL_FONT_COLOR;
    return color:WrapTextInColorCode(name);
end

--- What to call one entry in a sentence. The delete prompt is the one place there is: it names
--- what is about to go, inside a line of prose, with no second line to put anything on.
---
--- **The date alone would not do here.** The row, its tooltip and the bring dialog can all lead
--- with the date because the class is a line away in each of them; a prompt asking whether to
--- remove "8/18/2026" has nowhere to put the rest, and two strings pasted the same day would read
--- identically at the one moment there is no undo.
local function EntryLabel(entry)
    local class = EntryClassText(entry);
    local stamp = EntryDate(entry);
    if (not class) then
        return stamp;
    end
    return format(LLL["IMPORT_ENTRY_LINE"], class, stamp);
end
--- Who made it, or what it came from.
---
--- **A row made here says which character**, which is the one thing that tells two of your own
--- backups apart -- they carry the same class and often the same date. A row that came from a
--- string cannot say it: the string does not carry a character name and is not meant to
--- (`devdocs/building-export-import.md` 3절), so it falls back to the class, which is the only
--- thing about its sender that does travel.
local function EntryTitle(entry)
    if (entry.character) then
        return entry.character;
    end
    return EntryClassText(entry) or EntryDate(entry);
end

function DebindStorageEntryRowMixin:Init(elementData)
    self.elementData = elementData;
    local entry = elementData.entry;

    self.Name:SetText(EntryTitle(entry));

    -- **The date goes on the lower line, in front of the counts.** The top line says whose it is
    -- and this one says what is in it and when it turned up.
    local counts = format(LLL["IMPORT_ENTRY_COUNTS"], Store().CountEntry(entry));
    self.Counts:SetText(format(LLL["IMPORT_ENTRY_LINE"], EntryDate(entry), counts));

    -- **No pin, because nothing sweeps.** A pin takes an entry out of a clear-out, and there is no
    -- clear-out: nothing appends but a paste or a make, and only this row's delete button ever
    -- removes one. A control that exempts you from something that does not happen is a control
    -- that does nothing. The design for that is not rejected -- it is waiting on a clear-out that
    -- **asks** rather than sweeps, which is the one thing this list may not do silently
    -- (`devdocs/building-export-import.md`).

    -- **Deleting asks first, and names what goes.** An entry is the only copy of a string somebody
    -- sent: once the list lets go of it the way back is to ask them for it again. The main window
    -- asks the same way before deleting an action, and for the same reason -- there is no undo,
    -- which is what separates these two from move and copy.
    self.DeleteButton:SetScript("OnClick", function()
        StaticPopup_ShowCustomGenericConfirmation({
            text = LLL["IMPORT_DELETE_CONFIRM"],
            text_arg1 = EntryLabel(entry),
            callback = function()
                Store().DeleteEntry(entry.id);
                DebindFrame:NotifyStoreChanged();
            end,
            acceptText = YES,
            cancelText = NO,
            showAlert = true,
            referenceKey = "DebindDeleteEntry",
        });
    end);

    self:UpdateSelectionDisplay();
end

function DebindStorageEntryRowMixin:UpdateSelectionDisplay()
    self.SelectedHighlight:SetShown(
        DebindStoragePanel:GetSelectedEntry() == self.elementData.entry);
end

--- **Pressing a row picks it; nothing else.** It used to open a dialog and start an import, which
--- is a row that acts rather than a row that is chosen -- and there was nothing to choose it *for*
--- until there was a second column to read (12절). What the entry then does is on the buttons under
--- the column that shows it, where the reader can see what they are about to hand over.
function DebindStorageEntryRowMixin:OnClick()
    DebindStoragePanel:SelectEntry(self.elementData.entry);
end

function DebindStorageEntryRowMixin:OnEnter()
    local entry = self.elementData.entry;

    -- **The row's own two lines, in the same order.** A tooltip that regroups them reads as being
    -- about something else.
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, EntryTitle(entry));

    local counts = format(LLL["IMPORT_ENTRY_COUNTS"], Store().CountEntry(entry));
    GameTooltip_AddNormalLine(GameTooltip,
        format(LLL["IMPORT_ENTRY_LINE"], EntryDate(entry), counts));

    -- **The realm belongs here rather than on the row.** It only ever separates two characters of
    -- the same name, which is rare enough that the list should not spend a line on it and precise
    -- enough that the tooltip must not drop it.
    if (entry.realm) then
        GameTooltip_AddNormalLine(GameTooltip, entry.realm);
    end

    -- The class, for a row whose title is a character name and therefore does not say it.
    if (entry.character) then
        local class = EntryClassText(entry);
        if (class) then
            GameTooltip_AddNormalLine(GameTooltip, class);
        end
    end

    -- **What the reader called it, which is the only thing here a person wrote.** No caption in
    -- front of it: it is their own words, and a label on them would be the tooltip explaining the
    -- reader to themselves.
    if (entry.name and entry.name ~= "") then
        GameTooltip_AddNormalLine(GameTooltip, entry.name);
    end

    GameTooltip:Show();
end

function DebindStorageEntryRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- The preview: one entry's payload, by layer
--
-- **The same three rungs the export list had** - everything, layer, action - over a payload
-- instead of over the profile. What is ticked here is what a string carries and what `Add` places
-- (`FilterPayload`, `PlanImport`), and the tick is not written down: it is a different answer
-- every time the entry is used (12절).
--------------------------------------------------------------------------------

--- An empty list, not nil: the tooltip reads nil as "use your default two lines".
local NO_INSTRUCTIONS = {};

DebindStoragePreviewRowMixin = {};

function DebindStoragePreviewRowMixin:Init(elementData)
    self.elementData = elementData;

    local action = elementData.action;
    local name, icon = DebindUI.NameAndIconForAction(action);

    self.Name:SetText(name or "");
    DebindUI.SetActionIcon(self.Icon, icon);
    self.Key:SetText(action.key and DebindPrivate.GetKeyDisplayText(action.key) or "");

    -- The line marks where one key's group ends and the next begins. The first row under a layer
    -- gets none: the layer's own divider is already the line there, and two rules on top of each
    -- other read as a heavier rule, not as two boundaries.
    self.GroupBorder:SetShown(elementData.startsGroup and not elementData.firstInLayer);

    self:UpdateSelectionDisplay();
end

function DebindStoragePreviewRowMixin:UpdateSelectionDisplay()
    self.SelectedHighlight:SetShown(DebindStoragePanel.selected[self.elementData.action] == true);
end

function DebindStoragePreviewRowMixin:OnClick()
    DebindStoragePanel:ToggleAction(self.elementData.action);
    self:UpdateSelectionDisplay();
end

--- The same tooltip the other lists draw, rather than a name and a key written out here.
---
---   * the scope line is on, because this list mixes layers in one scroll and a long group's
---     header scrolls out of sight.
---   * inactive is suppressed, because **this list does not use colour to say it**: nothing here
---     turns on whether an action runs right now, and none of it is in this profile at all.
---   * no instruction line: a left click here ticks rather than selects, and there is no
---     right-click menu.
---
--- **The layer label takes the payload's class.** Every word in it would otherwise be built out of
--- this character (`GetLayerLabel`), so a mage's entry would caption its own layers "Druid".
function DebindStoragePreviewRowMixin:OnEnter()
    local elementData = self.elementData;
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    DebindPrivate.AddActionToTooltip(GameTooltip, elementData.action, {
        suppressInactive = true,
        instructionKeys = NO_INSTRUCTIONS,
        layerLabel = elementData.layerLabel,
    });
    GameTooltip:Show();
end

function DebindStoragePreviewRowMixin:OnLeave()
    DebindPrivate.HideActionTooltip(GameTooltip);
end

--- A layer header: the game's own collapsible list header (`ListHeaderThreeSliceTemplate`), with a
--- tri-state checkbox added on the left.
---
--- The quiet bar, not the quest log's `ListHeaderVisualTemplate`: a layer is the divider this list
--- is cut on rather than the thing being chosen, and the louder art reads as the latter.
---
--- The bar carries **two** gestures and they are split by area: the checkbox selects the layer,
--- everything else collapses it, and the bar's right-hand cap says which way it currently sits.
DebindStoragePreviewLayerMixin = {};

function DebindStoragePreviewLayerMixin:OnLoad()
    -- Clear of the checkbox. `ListHeaderThreeSliceMixin` owns the text's anchor and hands out this
    -- call for moving it, so the offset lives here instead of a second anchor in the XML.
    self:AdjustTextOffset(22, 0);

    -- One colour for both states, which is what every three-slice header in the client does. The
    -- bar's own HIGHLIGHT layer answers the mouse, and a title that changed colour alongside it
    -- would be a second answer to the one question. Neither call paints: `SetHeaderText` does.
    self:SetTitleColor(false, NORMAL_FONT_COLOR);
    self:SetTitleColor(true, NORMAL_FONT_COLOR);

    NormalizeCheckMark(self.Check);

    self.Check:SetScript("OnClick", function()
        DebindStoragePanel:ToggleLayer(self.elementData.actions);
        self:UpdateSelectionDisplay();
    end);
end

function DebindStoragePreviewLayerMixin:Init(elementData)
    self.elementData = elementData;
    self:UpdateCollapsedState(DebindStoragePanel:IsLayerCollapsed(elementData.key));
    self:UpdateSelectionDisplay();
end

--- **The header carries a fraction, and the box beside it carries a shape.** All / some / none is
--- what the tick can say, and "some" is exactly the state a reader has to open the layer to make
--- sense of - so the layer that is half picked answers the question where it is asked.
---
--- Written here rather than in `Init` because the left-hand number moves with every tick, and a
--- header drawn once would go on saying what the selection used to be.
function DebindStoragePreviewLayerMixin:UpdateSelectionDisplay()
    local actions = self.elementData.actions;
    local state, selectedCount = CombineState(actions, DebindStoragePanel.selected);

    self:SetHeaderText(format(LLL["EXPORT_LAYER_HEADER"],
        self.elementData.label, selectedCount, #actions));
    SetTriState(self.Check, state or STATE_NONE);
end

--- The bar collapses. Selecting is the checkbox's job and it swallows its own clicks, so a click
--- arriving here is always about showing and hiding.
function DebindStoragePreviewLayerMixin:OnClick()
    DebindStoragePanel:ToggleLayerCollapsed(self.elementData.key);
end

function DebindStoragePreviewLayerMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.elementData.label);
    GameTooltip_AddNormalLine(GameTooltip,
        format(LLL["EXPORT_LAYER_COUNT"], #self.elementData.actions));
    GameTooltip:Show();
end

function DebindStoragePreviewLayerMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------

DebindStoragePanelMixin = {};

--- One layer's actions, ordered the way the list draws them.
---
--- Ordered by name, **with a key's actions kept together**. Those two pull against each other and
--- both are wanted: the main list settled on name order because a single-layer list has no
--- standing to claim firing order, and this list inherits that; but the group is the thing that
--- travels, so it has to be visible as one block. Ordering the groups by the name of their first
--- action gives a list that reads alphabetically and still has boundaries that mean something.
local function SortLayerActions(actions)
    local groups, byKey = {}, {};

    for i = 1, #actions do
        local action = actions[i];
        local name = strlower(DebindUI.NameAndIconForAction(action) or "");
        local group;

        if (action.key == nil) then
            -- Keyless actions are singletons: nothing binds two of them together.
            group = { key = nil, actions = {}, sortName = name };
            groups[#groups + 1] = group;
        else
            group = byKey[action.key];
            if (not group) then
                group = { key = action.key, actions = {}, sortName = name };
                byKey[action.key] = group;
                groups[#groups + 1] = group;
            elseif (name < group.sortName) then
                group.sortName = name;
            end
        end

        group.actions[#group.actions + 1] = { action = action, sortName = name };
    end

    for i = 1, #groups do
        sort(groups[i].actions, function(lhs, rhs) return lhs.sortName < rhs.sortName; end);
    end

    -- `CompareKeys` breaks the tie so two groups whose first action has the same name do not swap
    -- places between rebuilds. `sort` is not stable.
    sort(groups, function(lhs, rhs)
        if (lhs.sortName ~= rhs.sortName) then
            return lhs.sortName < rhs.sortName;
        end
        if (lhs.key == nil or rhs.key == nil) then
            return rhs.key ~= nil;
        end
        return DebindPrivate.CompareKeys(lhs.key, rhs.key);
    end);

    return groups;
end

--- The key a layer group is collapsed and counted under.
---
--- A `layerID` where the address has one. **Where it has none it is one bucket, not one per
--- address**: what lands there is a specialization number past the end of a real class, which only
--- a hand-made string carries, and splitting those apart would put a header on the screen for each
--- of somebody's typos.
local ELSEWHERE = "elsewhere";

--- A number above every real `layerID`, so the bucket with no layer sorts last.
local ELSEWHERE_ORDER = 100;

--- What there is to show for one payload, before anything is collapsed.
---
--- **Every count the panel prints comes out of this**, and so does what a press hands over: the
--- header fractions, the [select all] total, which rows can be ticked, and the set `FilterPayload`
--- and `PlanImport` are given. One list is what makes those the same answer rather than the same
--- idea written twice -- the fault being guarded against is the panel saying 12 while the string
--- carries 9 (`devdocs/building-export-import.md` 2절).
---
--- **The address is walked, not translated.** `ForEachPayloadLayer` hands out the same three
--- coordinates the profile is keyed by, so nothing here has to know whose payload it is except to
--- write the label -- which is exactly the one argument `GetLayerLabel` takes.
local function BuildPreviewLayers(payload)
    local buckets, order = {}, {};

    Store().ForEachPayloadLayer(payload, function(list, scope, class, spec)
        local layerID = DebindUI.GetLayerIDForAddress(scope, spec);
        local key = layerID or ELSEWHERE;

        local bucket = buckets[key];
        if (not bucket) then
            bucket = {
                key = key,
                -- Sorted by `layerID` so the preview reads in the profile's own order: general,
                -- then the class by specialization, then the character.
                sortKey = layerID or ELSEWHERE_ORDER,
                label = layerID
                    and DebindUI.GetLayerLabel(layerID, class or payload.class)
                    or LLL["STORAGE_PREVIEW_ELSEWHERE"],
                actions = {},
            };
            buckets[key] = bucket;
            order[#order + 1] = bucket;
        end

        for _, action in ipairs(list) do
            bucket.actions[#bucket.actions + 1] = action;
        end
    end);

    sort(order, function(lhs, rhs) return lhs.sortKey < rhs.sortKey; end);

    for _, bucket in ipairs(order) do
        local rows, firstInLayer = {}, true;
        for _, group in ipairs(SortLayerActions(bucket.actions)) do
            for index, entry in ipairs(group.actions) do
                rows[#rows + 1] = {
                    action = entry.action,
                    layerLabel = bucket.label,
                    startsGroup = index == 1,
                    firstInLayer = firstInLayer,
                };
                firstInLayer = false;
            end
        end
        bucket.rows = rows;
    end

    return order;
end

function DebindStoragePanelMixin:OnLoad()
    -- **What this panel asks the frame to be** is a `KeyValue` in the XML, read by `SelectPanel`.
    -- Two columns now, so it asks for Overview's width rather than a single list's.

    self.CreateButton:SetText(LLL["STORAGE_CREATE"]);
    self.ImportButton:SetText(LLL["STORAGE_IMPORT"]);
    self.AddButton:SetText(ADD);
    self.CopyButton:SetText(LLL["STORAGE_COPY"]);
    self.Preview.SelectAllCheck.Text:SetText(LLL["EXPORT_SELECT_ALL"]);

    --- Which entry the right column is showing. **Held by reference**, so deleting the row it
    --- points at has to clear it and nothing else has to be reconciled.
    self.selectedEntry = nil;

    --- Which of that entry's actions are ticked, keyed by the action table itself.
    ---
    --- **Not kept anywhere.** It is a different answer every time the entry is used, and one
    --- written down is one that comes back a week later and hands over something the reader did
    --- not pick (3절, and the same reason the bring dialog's four lines were never stored).
    self.selected = {};

    --- Which layer headers are shut. A view state and nothing else: a collapsed layer still counts,
    --- still ticks, and still travels.
    self.collapsed = {};

    self:InitializeScrollBoxes();

    -- **The chrome widgets get their scripts here.** XML's `method=` looks the name up on the
    -- element's *own* mixin, so naming the panel's method on a plain Blizzard template finds
    -- nothing. List rows are the other way round: those carry a mixin.
    self.CreateButton:SetScript("OnClick", function() self:OnCreateClicked(); end);
    self.ImportButton:SetScript("OnClick", function() DebindPasteFrame:Open(); end);
    self.AddButton:SetScript("OnClick", function() self:OnAddClicked(); end);
    self.CopyButton:SetScript("OnClick", function() self:OnCopyClicked(); end);
    self.Preview.SelectAllCheck:SetScript("OnClick", function() self:OnSelectAllClicked(); end);

    NormalizeCheckMark(self.Preview.SelectAllCheck);

    -- **This panel is the bus's first registrant** (`FRAME_EVENTS` in `DebindUI.lua`). An entry can
    -- be made from a screen that is not this one -- the overview's key group menu -- so the list
    -- redraws on the event rather than on the presses it happens to own.
    DebindFrame:RegisterCallback(DebindFrame.Event.OnStoreChanged, self.RefreshEntries, self);
end

function DebindStoragePanelMixin:InitializeScrollBoxes()
    local entryView = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);
    entryView:SetElementFactory(function(factory)
        factory("DebindStorageEntryRowTemplate", function(frame, data) frame:Init(data); end);
    end);
    entryView:SetElementExtentCalculator(function() return ENTRY_ROW_HEIGHT; end);
    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, entryView);

    local previewView = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);
    previewView:SetElementFactory(function(factory, elementData)
        if (elementData.isLayer) then
            factory("DebindStoragePreviewLayerTemplate",
                function(frame, data) frame:Init(data); end);
        else
            factory("DebindStoragePreviewRowTemplate",
                function(frame, data) frame:Init(data); end);
        end
    end);
    previewView:SetElementExtentCalculator(function(_, elementData)
        return elementData.isLayer and LAYER_HEIGHT or PREVIEW_ROW_HEIGHT;
    end);
    previewView:SetElementIndentCalculator(function(elementData)
        return elementData.isLayer and 0 or ROW_INDENT;
    end);
    ScrollUtil.InitScrollBoxListWithScrollBar(self.Preview.ScrollBox, self.Preview.ScrollBar,
        previewView);
end


--------------------------------------------------------------------------------
-- The two columns
--------------------------------------------------------------------------------

--- Newest first. The list is read from the top by someone who just made or pasted something, and
--- what they are looking for is almost always that.
function DebindStoragePanelMixin:RefreshEntries()
    local list = {};
    for _, entry in ipairs(Store().GetEntries()) do
        list[#list + 1] = { entry = entry };
    end
    sort(list, function(lhs, rhs) return lhs.entry.id > rhs.entry.id; end);

    -- **A selection can outlive its row.** Deleting the entry the right column is showing leaves
    -- this holding a table that is in nothing, so the check is here rather than at the delete: the
    -- overview's key group menu removes nothing, but it is the same list and one guard is enough
    -- for whatever else ever writes to it.
    if (self.selectedEntry and not Store().GetEntry(self.selectedEntry.id)) then
        self:SelectEntry(nil);
    end

    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(LLL["IMPORT_DRAWER_EMPTY"]);
    self.ScrollBox.EmptyText:SetShown(#list == 0);

    self:UpdateEntrySelectionDisplay();
end

function DebindStoragePanelMixin:UpdateEntrySelectionDisplay()
    self.ScrollBox:ForEachFrame(function(frame)
        frame:UpdateSelectionDisplay();
    end);
end

function DebindStoragePanelMixin:GetSelectedEntry()
    return self.selectedEntry;
end

--- Picks the entry the right column shows, and **starts its selection over**.
---
--- Everything ticked, because handing over what is in front of you should cost a glance and a
--- button; the boxes are there for the reader who wants less (2절). Nothing carries across from
--- the entry that was showing a moment ago -- two entries do not share an action table, so a
--- leftover tick could not survive anyway, and wiping says so rather than relying on it.
function DebindStoragePanelMixin:SelectEntry(entry)
    self.selectedEntry = entry;
    wipe(self.selected);
    wipe(self.collapsed);
    self.previewLayers = nil;

    if (entry) then
        local payload, reason = Store().GetEntryPayload(entry);
        if (payload) then
            self.previewLayers = BuildPreviewLayers(payload);
            self:SelectAll(true);
        else
            -- **The row stays.** An entry this cannot read is one there is nothing left to do with
            -- but delete, and the delete button is on the row -- so the failure belongs in the
            -- column that was going to show it rather than in a message that takes the row away.
            self.previewReason = LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"];
        end
    end

    if (self.previewLayers) then
        self.previewReason = nil;
    end

    self:UpdateEntrySelectionDisplay();
    self:RefreshPreview();
end

--- The rows actually drawn. **Collapsing hides, it does not untick** - a collapsed layer's actions
--- still travel and still count toward the header and the total. That is why the two lists are
--- separate: everything that asks "what is picked" reads `previewLayers`, and only drawing reads
--- this one.
function DebindStoragePanelMixin:BuildPreviewDisplayList()
    local list = {};

    for _, layer in ipairs(self.previewLayers or {}) do
        list[#list + 1] = {
            isLayer = true,
            key = layer.key,
            label = layer.label,
            actions = layer.actions,
        };
        if (not self:IsLayerCollapsed(layer.key)) then
            for _, row in ipairs(layer.rows) do
                list[#list + 1] = row;
            end
        end
    end

    return list;
end

--- Redraws the right column from the layers already built. Collapsing does not re-read the entry.
---
--- **Three things it can be showing**, and the empty line says which: nothing picked, an entry
--- that cannot be read, or an entry with nothing in it.
function DebindStoragePanelMixin:RefreshPreview()
    local list = self:BuildPreviewDisplayList();
    self.Preview.ScrollBox:SetDataProvider(CreateDataProvider(list), true);

    local emptyText;
    if (not self.selectedEntry) then
        emptyText = LLL["STORAGE_NOTHING_PICKED"];
    elseif (self.previewReason) then
        emptyText = self.previewReason;
    elseif (#list == 0) then
        emptyText = LLL["EXPORT_EMPTY"];
    end

    self.Preview.ScrollBox.EmptyText:SetText(emptyText or "");
    self.Preview.ScrollBox.EmptyText:SetShown(emptyText ~= nil);

    self:UpdateSelectionState();
end

function DebindStoragePanelMixin:IsLayerCollapsed(key)
    return self.collapsed[key] == true;
end

function DebindStoragePanelMixin:ToggleLayerCollapsed(key)
    self.collapsed[key] = not self.collapsed[key] or nil;
    self:RefreshPreview();
end

--- Every action in the preview, collapsed layers included.
function DebindStoragePanelMixin:EnumerateListedActions()
    local actions = {};
    for _, layer in ipairs(self.previewLayers or {}) do
        for _, action in ipairs(layer.actions) do
            actions[#actions + 1] = action;
        end
    end
    return actions;
end


--------------------------------------------------------------------------------
-- Ticking
--------------------------------------------------------------------------------

--- Redraws the boxes without rebuilding the list. Rebuilding would drop the scroll position, and
--- ticking is the one gesture where the row you just touched must stay under the cursor.
function DebindStoragePanelMixin:UpdateSelectionState()
    self.Preview.ScrollBox:ForEachFrame(function(frame)
        if (frame.UpdateSelectionDisplay) then
            frame:UpdateSelectionDisplay();
        end
    end);

    local listed = self:EnumerateListedActions();
    local state, selectedCount = CombineState(listed, self.selected);

    SetTriState(self.Preview.SelectAllCheck, state or STATE_NONE);
    self.Preview.SelectAllCheck.Text:SetText(selectedCount > 0
        and format(LLL["EXPORT_SELECT_ALL_COUNT"], selectedCount)
        or LLL["EXPORT_SELECT_ALL"]);
    ExtendHitRectOverLabel(self.Preview.SelectAllCheck);
    self.Preview.SelectAllCheck:SetShown(#listed > 0);

    -- **Both verbs read the same number**, which is the point of the tick being on the action: one
    -- of them writes a string and the other writes into the profile, and what they take is the
    -- same set.
    self.AddButton:SetEnabled(selectedCount > 0);
    self.CopyButton:SetEnabled(selectedCount > 0);
end

--- A string already on screen describes a set that no longer exists, so it goes.
---
--- **Not in `UpdateSelectionState`.** That runs for collapsing too, and collapsing changes nothing
--- about what would go out -- dropping the string there would contradict the rule the collapse
--- makes two functions away.
local function DropStaleString()
    DebindCopyFrame:Hide();
end

function DebindStoragePanelMixin:SelectAll(selected)
    DropStaleString();
    local listed = self:EnumerateListedActions();
    for i = 1, #listed do
        self.selected[listed[i]] = selected or nil;
    end
    self:UpdateSelectionState();
end

function DebindStoragePanelMixin:ToggleAction(action)
    DropStaleString();
    self.selected[action] = not self.selected[action] or nil;
    self:UpdateSelectionState();
end

--- A layer toggles as a whole, and "some" counts as off -- one more click gets all of it, which is
--- what the middle state is asking for.
function DebindStoragePanelMixin:ToggleLayer(actions)
    DropStaleString();
    local turnOn = CombineState(actions, self.selected) ~= STATE_ALL;
    for i = 1, #actions do
        self.selected[actions[i]] = turnOn or nil;
    end
    self:UpdateSelectionState();
end

function DebindStoragePanelMixin:OnSelectAllClicked()
    -- Read the state we drew, not the checkbox's own `GetChecked` -- the middle state is drawn as
    -- checked, so the button's idea of its value says "on" for a partial selection and the click
    -- would clear everything when the reader meant to complete it.
    self:SelectAll(CombineState(self:EnumerateListedActions(), self.selected) ~= STATE_ALL);
end


--------------------------------------------------------------------------------
-- The four verbs
--------------------------------------------------------------------------------

--- The profile becomes an entry.
---
--- **Nothing is picked first.** Everything this character has is already the answer, and a screen
--- asking which part would put a step in front of the one press. Narrowing is what the entry is
--- for afterwards: rows can be deleted out of it, and what is handed over is ticked at the moment
--- it is handed over (12절).
---
--- **It goes through the bus**, even though this panel is the one that pressed it. The other maker
--- is the overview's key group menu, and one path is what keeps the two from drifting.
function DebindStoragePanelMixin:OnCreateClicked()
    local entry = Store().CreateEntry();
    DebindFrame:NotifyStoreChanged();

    -- **Landed on, not just listed.** A new row at the top of a list the reader is already looking
    -- at is easy to miss, and the right column standing empty beside it says nothing happened.
    self:SelectEntry(entry);
end

--- An entry's ticked actions go into the profile, badged.
---
--- **The message afterwards is not decoration.** Everything that lands is quarantined and greyed
--- out, so from the reader's side the screen barely moves: without a line saying what happened and
--- where to go next, a press that did a lot looks like a press that did nothing.
function DebindStoragePanelMixin:OnAddClicked()
    local entry = self.selectedEntry;
    if (not entry) then
        return;
    end

    local placed, skipped = Store().CommitEntry(entry, { selection = self.selected });

    if (not placed) then
        DebindPrivate.DisplayMessage(LLL[REASON_TEXT[skipped] or "IMPORT_FAILED_DAMAGED"], 1, 0, 0);
        return;
    end

    DebindPrivate.DisplayMessage(format(LLL["IMPORT_COMMITTED"], placed));
    -- Layers a newer schema invented and this one cannot place. Said separately because it is the
    -- one case where the count above is not the whole string. **Actions the reader unticked are
    -- not in here** - they said no, which is not this version having nowhere to put it.
    if (skipped and skipped > 0) then
        DebindPrivate.DisplayMessage(format(LLL["IMPORT_COMMITTED_SKIPPED"], skipped), 1, 0.5, 0);
    end

    DebindFrame:NotifyProfileChanged();
end

--- What `EncodeExportPayload` can answer, and the sentence for each.
---
--- **One entry, and the table is still worth having.** A reason with no sentence has to come out as
--- something other than a locale key on the reader's screen, and that cannot be arranged after an
--- `L` lookup -- `L`'s metatable answers a missing key with the key itself, so `L[...] or ...` can
--- never reach its right-hand side.
local EXPORT_FAILED_TEXT = {
    LIBS_MISSING = "EXPORT_FAILED_LIBS_MISSING",
};

function DebindStoragePanelMixin:OnCopyClicked()
    local entry = self.selectedEntry;
    if (not entry) then
        return;
    end

    local str, reason = Store().ExportEntry(entry, self.selected);
    if (not str) then
        -- A missing library means a broken install rather than anything the reader did. It is not
        -- a string to copy, so it does not go in the dialog that exists for copying.
        local key = EXPORT_FAILED_TEXT[reason] or REASON_TEXT[reason];
        DebindPrivate.DisplayMessage(key and LLL[key] or tostring(reason), 1, 0, 0);
        return;
    end

    DebindCopyFrame:ShowText(str);
end


--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function DebindStoragePanelMixin:OnShow()
    self:RefreshEntries();

    -- **The entry that was showing is re-read rather than kept drawn.** Its payload can have been
    -- migrated by something else since (`GetEntryPayload` walks a stored payload forward in place),
    -- and its actions are the tables the tick set is keyed by -- so the set would be pointing at
    -- the copies of a walk that has been.
    self:SelectEntry(self.selectedEntry);
end

function DebindStoragePanelMixin:OnHide()
    -- **The list is not thrown away**, unlike the tick set: an entry is plain stored data whose
    -- whole purpose is to survive being closed and a `/reload` after that.
    --
    -- The paste box does go. It is half-typed input, and unlike a finished string what it holds is
    -- not yet worth anything to anybody: a string outliving its tab is useful, an unfinished paste
    -- floating over Overview is not.
    DebindPasteFrame:Hide();

    -- **Through the pair, because a row's tooltip sets a minimum width.** This is for the case
    -- where a row's own `OnLeave` does not run -- the panel going away under the cursor -- and that
    -- is exactly the case where nothing else would put the width back. A bare `Hide()` left every
    -- later tooltip in the session 140 wide.
    DebindPrivate.HideActionTooltip(GameTooltip);
    GameTooltip:Hide();

    -- **The copy dialog is deliberately left up.** A finished string outlives the tab it came from:
    -- going to Overview to check something should not take away the text you were about to paste.
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
    local entry, reason = Store().ImportEntry(self.Input.EditBox:GetText(),
        name ~= "" and name or nil);

    if (not entry) then
        self.ErrorHolder.Text:SetText(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"]);
        return;
    end

    self:Hide();
    DebindStoragePanel:Refresh();
end


--------------------------------------------------------------------------------
-- The copy dialog
--------------------------------------------------------------------------------

DebindCopyFrameMixin = {};

function DebindCopyFrameMixin:OnLoad()
    self:InitDialog(LLL["EXPORT_COPY_TITLE"]);
    self.CloseDialogButton:SetScript("OnClick", function() self:Hide(); end);

    local editBox = self.Output.EditBox;
    editBox:SetFontObject(ChatFontNormal);

    -- **Editing is not blocked here, on purpose.** There was a guard that put the string back on
    -- every keystroke, and it was guarding the wrong end: it cannot cover a paste that was copied
    -- half way, or a string somebody wrote by hand, so the import side has to be safe against any
    -- string whatever this dialog does. Once it is, an edited string is one more string it turns
    -- away, and this is a text box the reader is allowed to treat as a text box.
    editBox:SetScript("OnEscapePressed", function()
        editBox:ClearFocus();
        self:Hide();
    end);
end

--- Puts the string up, selected, with the cursor already in it: the whole dialog exists so that
--- Ctrl-C is the only thing left to do.
function DebindCopyFrameMixin:ShowText(text)
    self.Output.EditBox:SetText(text);
    self:Show();
    self.Output.EditBox:SetFocus();
    self.Output.EditBox:HighlightText();
end
