local _, DebindPrivate = ...;

local LLL           = DebindPrivate.L;
local DebindUI      = DebindPrivate.DebindUI;
local Constants     = DebindPrivate.Constants;
local CountText     = DebindPrivate.CountText;

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
--- `building-export-import.md`). So there are four verbs on one screen -- make one from
--- this profile, take one in from a string, put one into the profile, turn one into a string --
--- and all four act on a row of the same list.
---
--- **Nothing in this file touches the profile except through the store.** An entry sits outside it
--- until it is added, which is the decision the whole design turns on: once actions are in the
--- profile they scatter, and the group identity the string arrived with is held nowhere.
---
--- **The right column shows what a payload holds, not what the profile holds.** Everything it
--- names comes out of the payload's own cells, `layers` and `switches` -- a label built from this
--- character would caption another class's layers with this reader's class (`GetLayerLabel`).

--- One row of the left column: two lines and a delete button.
local ENTRY_ROW_HEIGHT   = 46;

--- The right column, which is the export list's three rungs.
local PREVIEW_ROW_HEIGHT = 28;
local LAYER_HEIGHT       = 26;
--- The air between two groups, as an element of its own. Overview's `KEY_GROUP_GAP`.
local PREVIEW_GROUP_GAP  = 1;
local PREVIEW_ROW_INDENT = 18;
local PREVIEW_KEY_TEXT_WIDTH   = 120;
local PREVIEW_LAYER_TEXT_WIDTH = 180;

local PREVIEW_VIEWS = { "layer", "key" };
local PREVIEW_VIEW_LABELS = { layer = "STORAGE_VIEW_LAYER", key = "SORT_BY_KEY" };

--- **Which failures the reader can tell apart, which is fewer than the decoder reports.**
--- `DecodeExportString` answers with eight reasons because each is a different step; a reader has
--- three things they might do about it -- check what they pasted, update, paste it again -- and a
--- message per step would spread those three over eight sentences that all end the same way.
local REASON_TEXT   = {
    NOT_A_STRING          = "IMPORT_FAILED_NOT_OURS",
    NOT_A_DEBIND_STRING   = "IMPORT_FAILED_NOT_OURS",
    -- Made by a newer Debind. Both of these mean the same thing to the reader even though one is
    -- the envelope and the other the payload inside it.
    UNSUPPORTED_ENVELOPE  = "IMPORT_FAILED_TOO_NEW",
    PAYLOAD_TOO_NEW       = "IMPORT_FAILED_TOO_NEW",
    -- **The other direction, and the advice is opposite.** "Update and try again" is what the line
    -- above says, and saying it here would tell a reader to do the thing they have already done -
    -- this is a string from *before* the payload version they are on. Nothing they can do fixes it,
    -- so the sentence says that instead of asking.
    PAYLOAD_TOO_OLD       = "IMPORT_FAILED_TOO_OLD",
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
--- **Camelot has no `common-icon-minus`** (69977), and there the dash is `common-button-list-minus`,
--- a 13x4 bar. That one is drawn to its own proportions below; the first is drawn square, as it was
--- sized for.
local CHECK_SOME, CHECK_SOME_INFO = DebindPrivate.Client.FirstAtlas("common-icon-minus",
    "common-button-list-minus");
local SOME_MARK_ASPECT = (CHECK_SOME ~= "common-icon-minus" and CHECK_SOME_INFO)
    and CHECK_SOME_INFO.height / CHECK_SOME_INFO.width or 1;

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
    mark:SetSize(size, atlas == CHECK_SOME and size * SOME_MARK_ASPECT or size);
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

--- A character's name, with its realm only where that is not this one: what `Ambiguate(full,
--- "none")` does, and the client's way everywhere it names a player. Camelot's realms are one per
--- ruleset (`ClassicBetaPvE2`, `ClassicBetaPvP2` on the beta), so a character of another ruleset
--- shows its realm there too. **In the client's form** where it does: `FULL_PLAYER_NAME` is what
--- the friends list joins the two with and every locale carries it.
local function NameWithRealm(name, realm)
    if (type(realm) ~= "string" or realm == "") then
        return name;
    end
    local here = GetNormalizedRealmName and GetNormalizedRealmName();
    if (here and realm == here) then
        return name;
    end
    return format(FULL_PLAYER_NAME, name, realm);
end

--- The class the entry came from, or nil.
---
--- **Read off the payload's cells, which carry their class as a key** (`reshaping-stored-layers.md`
--- 1-1). The one class every cell names but `GENERAL`; none where there is none, and none where
--- there are several, since then no one of them is where it came from. A payload holding only the
--- general layer says nothing about a class, and its row is drawn without one, as a Clique one is.
local function EntryClass(entry)
    if (type(entry.payload) ~= "table") then
        return nil;
    end
    local found, several = nil, false;
    Store().ForEachPayloadLayer(entry.payload, function(_, _, class)
        if (type(class) == "string" and class ~= "GENERAL") then
            several = several or (found ~= nil and found ~= class);
            found = class;
        end
    end);
    return not several and found or nil;
end

--- The row's second line leads with this: **the date it arrived, and for now nothing else.**
---
--- **The date, not how old it is.** A relative age answers "is this the one I just pasted", which
--- is only a question for a minute or two; a list that piles up is read by when things came in.
local function EntryDate(entry)
    local when = date("*t", entry.received);
    return FormatShortDate(when.day, when.month, when.year);
end

--- A moment to the minute, for the tooltip (소유자, 2026-09-28): two entries made the same day are
--- told apart by the time.
local function DateTimeText(stamp)
    local when = date("*t", stamp);
    return format(LLL["IMPORT_ENTRY_LINE"], FormatShortDate(when.day, when.month, when.year),
        date("%H:%M", stamp));
end

--- A character key of a payload by name: what `characters` says, in the client's form, or its
--- number where an older string named nobody.
local function CharacterName(owner, identity)
    if (type(identity) == "table" and type(identity.name) == "string") then
        return NameWithRealm(identity.name, identity.realm);
    end
    return format(LLL["STORAGE_ADD_CHARACTER_UNNAMED"], tostring(owner));
end

--- `payload.characters`, or an empty table for a payload without one.
local function PayloadCharacters(entry)
    local payload = entry.payload;
    return type(payload) == "table" and type(payload.characters) == "table" and payload.characters or {};
end

--- The longest `payload.name` a row draws (`PlainText`). A row is one line wide.
local NAME_MAX_CHARS = 48;
--- The longest `payload.description` the tooltip draws.
local DESCRIPTION_MAX_CHARS = 300;

--- `DescribePayload` of an entry, for an entry whose payload may not be a table.
local function DescribeEntry(entry)
    return Store().DescribePayload(type(entry.payload) == "table" and entry.payload or {});
end

--- What an entry holds, counted, as one list: how many classes and characters when `held` is
--- given, each left out at 0 (소유자, 2026-09-29), then keys and actions. Every count on this
--- screen is one `COUNT_*` string; this is where the entry's are put together.
local function EntryCounts(entry, held)
    local parts = {};
    if (held) then
        for _, noun in ipairs({ "classes", "characters" }) do
            if (#held[noun] > 0) then
                parts[#parts + 1] = CountText(noun, #held[noun]);
            end
        end
    end
    local keys, actions = Store().CountEntry(entry);
    parts[#parts + 1] = CountText("keys", keys);
    parts[#parts + 1] = CountText("actions", actions);
    return table.concat(parts, LIST_DELIMITER);
end

--- The colour a row's title is drawn in: the one scope's (the class's, or `ACCOUNT_COLOR` for
--- general alone), else the class every cell shares, else none.
---
--- `GetClassColorObj` answers nil for a token it does not know, and a payload's class keys can be
--- one this client has never heard of, so the colour falls back.
local function TitleColor(entry, held)
    local only = held.only;
    if (only and only.kind == "general") then
        return DebindUI.ACCOUNT_COLOR;
    end
    local class = only and only.class or EntryClass(entry);
    return class and (GetClassColorObj(class) or NORMAL_FONT_COLOR) or nil;
end

--- What the row is called: its name, or `STORAGE_ENTRY_UNNAMED`, in `TitleColor`.
---
--- **A name nobody gave is drawn, never stored** (소유자, 2026-09-28): `payload.name` holds only what
--- a person typed, and its absence is itself what the row shows.
---
--- **Not called by what it holds** (소유자, 2026-09-29). The second line says how many classes and
--- characters, so a title made of the same counts said them twice on one row.
---
--- **No class icon** (소유자, 2026-09-28). The colour stays. `held` is `DescribeEntry`'s, for a
--- caller that has it already.
local function EntryName(entry, held)
    local payload = type(entry.payload) == "table" and entry.payload or {};
    local text = Store().PlainText(payload.name, NAME_MAX_CHARS) or LLL["STORAGE_ENTRY_UNNAMED"];
    local color = TitleColor(entry, held or DescribeEntry(entry));
    return color and color:WrapTextInColorCode(text) or text;
end

--- What to call one entry in a sentence. The delete prompt is the one place there is: it names
--- what is about to go, inside a line of prose, with no second line to put anything on.
---
--- **It calls the entry what the row calls it** (2026-08-23, 소유자). The reader is pointing at a
--- row when they press delete, so a prompt that answers with a different name is asking about
--- something else as far as they can tell. It used to spell the class where the row says which
--- character, which made every one of your own backups read as a prompt about somebody else's.
---
--- **The date is what the prompt adds**, because the row keeps it on a second line and this has
--- only the one. Without it two entries from the same character read identically at the one moment
--- there is no undo.
local function EntryLabel(entry)
    return format(LLL["IMPORT_ENTRY_LINE"], EntryName(entry), EntryDate(entry));
end

function DebindStorageEntryRowMixin:Init(elementData)
    self.elementData = elementData;
    local entry = elementData.entry;

    local held = DescribeEntry(entry);
    self.Name:SetText(EntryName(entry, held));

    self.Counts:SetText(format(LLL["IMPORT_ENTRY_LINE"], EntryDate(entry), EntryCounts(entry, held)));

    -- **Where it came from, as a picture beside the words and never in them** (소유자, 2026-09-28):
    -- a name given later replaces the words and leaves this. Our own rows show nothing.
    --
    -- Clique draws its icon from its own folder rather than the game's files, so it is asked for
    -- through Clique's TOC and is there only while Clique is installed. Without it the question
    -- mark stands in, which is what the client's own addon list shows for an addon with no icon.
    local fromClique = type(entry.payload) == "table" and entry.payload.fromAddon == Store().FROM_ADDON_CLIQUE;
    if (fromClique) then
        self.SourceIcon:SetTexture(C_AddOns.GetAddOnMetadata("Clique", "IconTexture")
            or Constants.QUESTION_MARK_ICON);
    end
    self.SourceIcon:SetShown(fromClique);
    -- No `ClearAllPoints`: it would drop the `RIGHT` point the XML hangs off the delete button.
    if (fromClique) then
        self.Name:SetPoint("LEFT", self.SourceIcon, "RIGHT", 4, 0);
    else
        self.Name:SetPoint("LEFT", 10, 7);
    end

    -- **No pin, because nothing sweeps.** A pin takes an entry out of a clear-out, and there is no
    -- clear-out: nothing appends but a paste or a make, and only this row's delete button ever
    -- removes one. A control that exempts you from something that does not happen is a control
    -- that does nothing. The design for that is not rejected -- it is waiting on a clear-out that
    -- **asks** rather than sweeps, which is the one thing this list may not do silently
    -- (`building-export-import.md`).

    -- **Deleting asks first, and names what goes.** An entry is the only copy of a string somebody
    -- sent: once the list lets go of it the way back is to ask them for it again. The main window
    -- asks the same way before deleting an action, and for the same reason -- there is no undo,
    -- which is what separates these two from move and copy.
    self.DeleteButton:SetScript("OnClick", function()
        StaticPopup_ShowCustomGenericConfirmation({
            text = LLL["IMPORT_DELETE_CONFIRM"],
            text_arg1 = EntryLabel(entry),
            callback = function()
                DebindEntryTextFrame:CloseFor(entry);
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
--- **Pressing the picked row lets it go.** One row is showing at a time, so without this there is
--- no way back to nothing once anything has been picked - and the empty column is a real state
--- rather than a gap, since the two buttons under it turn off with it.
---
--- **The right button opens the row's menu instead**, and picks nothing: the one item in it is about
--- the row, not about what the right column shows.
function DebindStorageEntryRowMixin:OnClick(button)
    local entry = self.elementData.entry;
    if (button == "RightButton") then
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateButton(LLL["STORAGE_ENTRY_EDIT"], function()
                DebindEntryTextFrame:Open(entry);
            end);
        end);
        return;
    end
    if (DebindStoragePanel:GetSelectedEntry() == entry) then
        entry = nil;
    end
    DebindStoragePanel:SelectEntry(entry);
end

function DebindStorageEntryRowMixin:OnEnter()
    local entry = self.elementData.entry;

    local payload = type(entry.payload) == "table" and entry.payload or {};
    local held = DescribeEntry(entry);

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, EntryName(entry, held));

    local description = Store().PlainText(payload.description, DESCRIPTION_MAX_CHARS, true);
    if (description) then
        GameTooltip_AddHighlightLine(GameTooltip, description);
        GameTooltip_AddBlankLineToTooltip(GameTooltip);
    end

    -- **Where it came from, and not which character made it** (owner, 2026-09-28): what is in it
    -- says that, in the class and character lines below. Whose data it is comes first, since
    -- another addon's row is that whichever way it arrived.
    local fromClique = payload.fromAddon == Store().FROM_ADDON_CLIQUE;
    local madeHere = not fromClique and entry.receivedFrom == Store().RECEIVED_FROM_PROFILE;
    if (fromClique) then
        GameTooltip_AddNormalLine(GameTooltip, LLL["STORAGE_ENTRY_SOURCE_CLIQUE"]);
    elseif (madeHere) then
        GameTooltip_AddNormalLine(GameTooltip, LLL["STORAGE_ENTRY_SOURCE_MADE"]);
    elseif (entry.receivedFrom == Store().RECEIVED_FROM_STRING) then
        GameTooltip_AddNormalLine(GameTooltip, LLL["STORAGE_ENTRY_SOURCE_PASTED"]);
    end

    -- **Two moments, which are one only for a row made here.** `created` travels in the string and
    -- `received` is when it reached this list. A string from before `created` existed has no
    -- moment of making to show (owner, 2026-09-28).
    if (type(payload.created) == "number") then
        GameTooltip_AddNormalLine(GameTooltip,
            format(LLL["STORAGE_ENTRY_MADE"], DateTimeText(payload.created)));
    end
    if (not madeHere) then
        GameTooltip_AddNormalLine(GameTooltip,
            format(LLL["STORAGE_ENTRY_RECEIVED"], DateTimeText(entry.received)));
    end

    -- **Whose layers are in it** (소유자, 2026-09-28): the title names them only while there is one.
    if (#held.classes > 0) then
        local names = {};
        for i, class in ipairs(held.classes) do
            local color = GetClassColorObj(class) or NORMAL_FONT_COLOR;
            names[i] = color:WrapTextInColorCode(Constants.CLASS_NAMES[class] or class);
        end
        GameTooltip_AddNormalLine(GameTooltip,
            format(LLL["STORAGE_ENTRY_CLASSES"], table.concat(names, LIST_DELIMITER)));
    end
    if (#held.characters > 0) then
        local characters, names = PayloadCharacters(entry), {};
        for i, owner in ipairs(held.characters) do
            names[i] = CharacterName(owner, characters[owner]);
        end
        GameTooltip_AddNormalLine(GameTooltip,
            format(LLL["STORAGE_ENTRY_CHARACTERS"], table.concat(names, LIST_DELIMITER)));
    end
    if (held.anonymous) then
        GameTooltip_AddNormalLine(GameTooltip, LLL["STORAGE_ENTRY_ANONYMOUS"]);
    end

    -- Without the classes and characters, which the two lines above already name.
    GameTooltip_AddNormalLine(GameTooltip, EntryCounts(entry));

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
-- (`FilterPayload`, `PlanArrival`), and the tick is not written down: it is a different answer
-- every time the entry is used (12절).
--------------------------------------------------------------------------------

--- An empty list, not nil: the tooltip reads nil as "use your default two lines".
local NO_INSTRUCTIONS = {};

DebindStoragePreviewRowMixin = {};

function DebindStoragePreviewRowMixin:OnLoad()
    self.Check:EnableMouse(false);
    NormalizeCheckMark(self.Check);
end

function DebindStoragePreviewRowMixin:Init(elementData)
    self.elementData = elementData;

    local action = elementData.action;
    local name, icon = DebindUI.NameAndIconForAction(action);

    self.Name:SetText(name or "");
    DebindUI.SetActionIcon(self.Icon, icon);
    -- The key view's header already says the key, so the right-hand column says the layer instead
    -- (`grouping-the-storage-preview-by-key.md` 3절).
    local maxWidth;
    if (elementData.layerText) then
        maxWidth = PREVIEW_LAYER_TEXT_WIDTH;
        self.Key:SetText(elementData.layerText);
    else
        maxWidth = PREVIEW_KEY_TEXT_WIDTH;
        self.Key:SetText(action.key and DebindPrivate.GetKeyDisplayText(action.key) or "");
    end
    self.Key:SetWidth(math.min(self.Key:GetUnboundedStringWidth(), maxWidth));

    self:UpdateSelectionDisplay();
end

function DebindStoragePreviewRowMixin:UpdateSelectionDisplay()
    self.Check:SetChecked(DebindStoragePanel.selected[self.elementData.action] == true);
end

--- The row's menu: taking things out of the entry, which is the only edit an entry has (12절).
---
--- **Two items, because the tick set is not always what the reader means.** Ticking is what goes
--- out, and it starts as everything -- so the set is a poor stand-in for "this one", and an entry
--- opened and right-clicked would offer to delete all of it under a count nobody chose.
---
--- **One action never asks; two or more do** (2026-08-22, 소유자). A menu is enough hands not to
--- arrive at by accident, which is the whole of the case for one; what it is not enough of is a
--- second look at a number the reader did not choose. Ticking starts as everything, so the count on
--- that second item is usually the whole entry.
---
--- That is the line 4절 drew between [accept all] and [reject all], from the same reading: a label
--- carrying a count is warning enough only while the count is small.
local function SetupPreviewRowMenu(_, rootDescription, action)
    rootDescription:CreateButton(LLL["STORAGE_DELETE_ACTION"], function()
        DebindStoragePanel:DeleteActions({ [action] = true });
    end);

    local selected = DebindStoragePanel.selected;
    local count = 0;
    for _ in pairs(selected) do
        count = count + 1;
    end

    local description = rootDescription:CreateButton(
        format(LLL["STORAGE_DELETE_SELECTED"], count), function()
            if (count < 2) then
                DebindStoragePanel:DeleteActions(selected);
                return;
            end
            StaticPopup_ShowCustomGenericConfirmation({
                text = LLL["STORAGE_DELETE_SELECTED_CONFIRM"],
                text_arg1 = CountText("actions", count),
                callback = function() DebindStoragePanel:DeleteActions(selected); end,
                acceptText = YES,
                cancelText = NO,
                showAlert = true,
                referenceKey = "DebindDeleteEntryActions",
            });
        end);
    -- Nothing ticked is not an error to explain, it is an item with nothing to act on.
    description:SetEnabled(count > 0);
end

function DebindStoragePreviewRowMixin:OnClick(button)
    if (button == "RightButton") then
        MenuUtil.CreateContextMenu(self, SetupPreviewRowMenu, self.elementData.action);
        return;
    end

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

DebindStoragePreviewLayerMixin = {};

--- Dressed the way `DebindKeyHeaderMixin:OnLoad` dresses Overview's, so the two read as one kind of
--- bar.
function DebindStoragePreviewLayerMixin:OnLoad()
    self:SetTitleColor(false, HIGHLIGHT_FONT_COLOR);
    self:SetTitleColor(true, HIGHLIGHT_FONT_COLOR);

    self:GetNormalTexture():SetDesaturated(true);
    self:GetNormalTexture():SetAlpha(0.5);
    self:GetHighlightTexture():SetDesaturated(true);

    -- Only the left end moves. `AdjustTextOffset` would carry the right one along with it, into the
    -- fold button it is anchored to.
    self.ButtonText:SetPoint("LEFT", self.Check, "RIGHT", 4, 1);

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

function DebindStoragePreviewLayerMixin:OnClick()
    DebindStoragePanel:ToggleLayerCollapsed(self.elementData.key);
end

function DebindStoragePreviewLayerMixin:OnEnter()
    ListHeaderMixin.OnEnter(self);

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, self.elementData.label);
    GameTooltip_AddNormalLine(GameTooltip,
        CountText("actions", #self.elementData.actions));
    GameTooltip:Show();
end

function DebindStoragePreviewLayerMixin:OnLeave()
    ListHeaderMixin.OnLeave(self);
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
--- travels, so it has to stand together. Ordering the groups by the name of their first action
--- gives a list that reads alphabetically and still keeps each key's actions in one run.
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

--- One payload cell as the preview draws it: the key it is bucketed under inside its owner, where
--- it sorts there (general, this class, other classes by name, then what has no place), the header
--- under the owner, the full label a row carries, and its place in the firing order
--- (`layerRank, specRank`) for the key view.
---
--- **The class and spec are the ones `ImportAddress` answers where it answers**, which is where Add
--- to My Bindings puts them. The payload's own coordinates drew a camelot reader a Fire layer for a
--- retail mage's string that the press then folded into the class layer.
---
--- **The spec is the number itself, whatever this character is playing**
--- (`grouping-the-storage-preview-by-key.md` 2절): an entry need not be this character's, and
--- actions of two specializations never compete in the game. What has no place ranks after general.
---
--- **Where it has no layer it is one bucket per owner, not one per address**: a specialization
--- number past the end of a real class, or one the class has no name for, is something only a
--- hand-made string carries, and a header for each would put somebody's typos on screen.
local function PreviewLayerOf(owner, class, spec, ownerLabel, ownerName)
    local toScope, toClass, toSpec = Store().ImportAddress(owner, class, spec);
    local scope;
    if (toScope) then
        scope, class, spec = toScope, toClass or class, toSpec or spec;
    elseif (toClass == "OTHER_CLASS") then
        -- Without an address the second value is the reason, not a class.
        scope = "character";
    end
    local layerID = scope and DebindUI.GetLayerIDForAddress(scope, spec);
    if (layerID == 1) then
        class = nil;
    end
    local label, _, side;
    if (layerID) then
        label, _, side = DebindUI.GetColoredLayerLabel(layerID, class, ownerName);
    end
    if (not label) then
        -- **A class nobody can play here gets a bucket of its own name**, not the typo bucket: it
        -- is the other game type's class and the string is fine (2026-09-25, owner).
        local text = LLL[toClass == "UNKNOWN_CLASS" and "STORAGE_PREVIEW_UNKNOWN_CLASS"
            or "STORAGE_PREVIEW_ELSEWHERE"];
        return "~" .. tostring(toClass), toClass == "UNKNOWN_CLASS" and "3" or "4", text,
            ownerName and format(LLL["ORDER_LAYER_LABEL"], ownerLabel, text) or text, 6, 0;
    end
    local sortKey = layerID == 1 and "0"
        or ((class == Constants.PLAYER_CLASS and "1" or "2") .. class .. format("%02d", layerID));
    return tostring(class) .. "|" .. layerID, sortKey, side, label,
        DebindPrivate.GetLayerScopeRank(layerID), spec;
end

--- The key view (`grouping-the-storage-preview-by-key.md`), in the order Overview's [Sort] by key
--- stands a layer's actions (`DebindUI.CompareByKey`): keys in key order, each in firing order, and
--- the keyless ones last by name.
---
--- **Sorted as the actions would land** (`BuildAction`), not as the string wrote them. The whitelist
--- drops a key or an importance of the wrong type, which is what the comparators cannot read, and
--- what is dropped is what the press would drop too.
---
--- **The stored number is taken out of the record and put into the walk's index instead.** Two
--- characters' actions tie up to that number, and it is counted in each character's own layer, so
--- compared across them it interleaves the two on numbers that mean nothing side by side. Walked
--- owner by owner and each layer by that number, the index keeps an owner's actions together and
--- keeps the number's order inside each. Equal numbers keep the order the layer stores them in.
local function BuildPreviewKeyGroups(ownerOrder)
    local items = {};
    for _, group in ipairs(ownerOrder) do
        for _, bucket in ipairs(group.layers) do
            local built = {};
            for position, source in ipairs(bucket.actions) do
                local action = Store().BuildAction(source);
                built[position] = { source = source, action = action, position = position,
                                    seq = tonumber(action.seq) or math.huge };
            end
            sort(built, function(lhs, rhs)
                if (lhs.seq ~= rhs.seq) then
                    return lhs.seq < rhs.seq;
                end
                return lhs.position < rhs.position;
            end);
            for _, entry in ipairs(built) do
                local order = DebindPrivate.MakeOrderRecord(entry.action,
                    bucket.place.layerRank, bucket.place.specRank);
                order.seq = nil;
                items[#items + 1] = {
                    action = entry.action,
                    source = entry.source,
                    place = bucket.place,
                    order = order,
                    sortName = strlower(DebindUI.NameAndIconForAction(entry.source) or ""),
                    index = #items + 1,
                };
            end
        end
    end
    sort(items, DebindUI.CompareByKey);

    local groups, current = {}, nil;
    for _, item in ipairs(items) do
        local key = item.action.key;
        if (not current or current.key ~= key) then
            current = {
                key = key,
                id = "key|" .. tostring(key),
                label = key and DebindPrivate.GetKeyDisplayText(key) or LLL["OVERVIEW_NO_KEY"],
                actions = {},
                rows = {},
            };
            groups[#groups + 1] = current;
        end
        current.actions[#current.actions + 1] = item.source;
        current.rows[#current.rows + 1] = {
            action = item.source,
            layerLabel = item.place.label,
            layerText = item.place.label,
        };
    end
    return groups;
end

--- What there is to show for one payload, before anything is collapsed: the owners, each with its
--- layers (`reshaping-stored-layers.md` 6-2), and the same layers flat.
---
--- **Every count the panel prints comes out of this**, and so does what a press hands over: the
--- header fractions, the [select all] total, which rows can be ticked, and the set `FilterPayload`
--- and `PlanArrival` are given. One list is what makes those the same answer rather than the same
--- idea written twice -- the fault being guarded against is the panel saying 12 while the string
--- carries 9 (`building-export-import.md` 2절).
---
--- **Grouped by whose cells they are**, account first and then each character, so one owner's
--- layers stand together.
local function BuildPreviewLayers(payload)
    local owners, ownerOrder = {}, {};
    local identities = type(payload.characters) == "table" and payload.characters or {};

    Store().ForEachPayloadLayer(payload, function(list, owner, class, spec)
        local group = owners[owner];
        if (not group) then
            local account = owner == Store().ACCOUNT_OWNER;
            local name = not account and CharacterName(owner, identities[owner]) or nil;
            local _, label = DebindUI.GetColoredLayerLabel(
                DebindUI.GetLayerIDForAddress(account and "general" or "character", 0),
                not account and class or nil, name);
            group = {
                key = "owner|" .. tostring(owner), label = label, name = name,
                sortKey = account and "0" or ((owner == DebindPrivate.playerGUID and "1" or "2") .. name),
                actions = {}, layers = {}, byKey = {},
            };
            owners[owner] = group;
            ownerOrder[#ownerOrder + 1] = group;
        end

        local layerKey, layerSort, header, rowLabel, layerRank, specRank =
            PreviewLayerOf(owner, class, spec, group.label, group.name);
        local bucket = group.byKey[layerKey];
        if (not bucket) then
            bucket = {
                key = group.key .. "|" .. layerKey, sortKey = layerSort, label = header, actions = {},
                -- What a row says about where it sits: its owner and its layer, since the row sits
                -- under both in one view and under a key in the other.
                place = { label = rowLabel, layerRank = layerRank, specRank = specRank },
            };
            group.byKey[layerKey] = bucket;
            group.layers[#group.layers + 1] = bucket;
        end

        for _, action in ipairs(list) do
            bucket.actions[#bucket.actions + 1] = action;
            group.actions[#group.actions + 1] = action;
        end
    end);

    sort(ownerOrder, function(lhs, rhs) return lhs.sortKey < rhs.sortKey; end);

    local flat = {};
    for _, group in ipairs(ownerOrder) do
        group.byKey = nil;
        sort(group.layers, function(lhs, rhs) return lhs.sortKey < rhs.sortKey; end);
        for _, bucket in ipairs(group.layers) do
            local rows = {};
            for _, sorted in ipairs(SortLayerActions(bucket.actions)) do
                for _, entry in ipairs(sorted.actions) do
                    rows[#rows + 1] = {
                        action = entry.action,
                        layerLabel = bucket.place.label,
                    };
                end
            end
            bucket.rows = rows;
            flat[#flat + 1] = bucket;
        end
    end

    return flat, ownerOrder;
end

--- The Clique profiles, one row each, with who uses it and how many actions it becomes.
local function AddCliqueProfiles(parent)
    for _, profile in ipairs(Store().CliqueProfiles(_G.CliqueDB3)) do
        local description = parent:CreateButton(profile.name, function()
            DebindStoragePanel:OnCliqueProfileClicked(profile);
        end);
        local _, count = Store().PayloadFromCliqueBindings(profile.bindings);
        local users = #profile.characters > 0
            and format(LLL["STORAGE_CLIQUE_PROFILE_USERS"], table.concat(profile.characters, ", "))
            or LLL["STORAGE_CLIQUE_PROFILE_NO_USERS"];
        description:SetTooltip(function(tooltip)
            GameTooltip_SetTitle(tooltip, profile.name);
            GameTooltip_AddNormalLine(tooltip, users);
            GameTooltip_AddNormalLine(tooltip, CountText("actions", count));
        end);
    end
end

--- Where a new entry comes from, behind the [+] (`importing-clique-profiles.md` §1). **The press
--- asks rather than making one**, which puts a step in front of making from this character. That is
--- fine: making an entry is not something done often (2026-09-24, 소유자).
---
--- **From Clique is always there**, and greyed where Clique is not loaded. It is read straight out of
--- Clique's own saved variables, which exist only while that addon is loaded.
local function SetupCreateMenu(_, rootDescription)
    rootDescription:CreateButton(LLL["STORAGE_CREATE_FROM_CHARACTER"], function()
        DebindStoragePanel:OnCreateClicked();
    end);
    rootDescription:CreateButton(LLL["STORAGE_CREATE_FROM_ACCOUNT"], function()
        DebindStoragePanel:OnCreateClicked(true);
    end);
    rootDescription:CreateButton(LLL["STORAGE_CREATE_FROM_CODE"], function()
        DebindPasteFrame:Open();
    end);

    local clique = rootDescription:CreateButton(LLL["STORAGE_CREATE_FROM_CLIQUE"]);
    if (DebindPrivate.CliqueDetected and _G.CliqueDB3) then
        AddCliqueProfiles(clique);
    else
        -- The error line, which is what the action menus give a greyed item (`CreateBlockedMenuItem`).
        clique:SetEnabled(false);
        DebindPrivate.MenuKit.SetErrorTooltip(clique, LLL["STORAGE_CREATE_FROM_CLIQUE_UNAVAILABLE"]);
    end
end

function DebindStoragePanelMixin:OnLoad()
    -- **What this panel asks the frame to be** is a `KeyValue` in the XML, read by `SelectPanel`.
    -- Two columns now, so it asks for Overview's width rather than a single list's.

    self.Preview.AddButton:SetText(LLL["STORAGE_ADD"]);
    self.Preview.CopyButton:SetText(LLL["STORAGE_COPY"]);
    DynamicResizeButton_Resize(self.Preview.AddButton);
    DynamicResizeButton_Resize(self.Preview.CopyButton);

    DebindUI.SetListColumnHeader(self.Preview, DebindUI.LIST_HEADER_HEIGHT);
    self.Preview.ViewDropdown:SetText(VIEW);
    self.Preview.ViewDropdown:SetupMenu(function(_, rootDescription)
        for _, view in ipairs(PREVIEW_VIEWS) do
            rootDescription:CreateRadio(LLL[PREVIEW_VIEW_LABELS[view]], function()
                return self:GetPreviewView() == view;
            end, function()
                self:SetPreviewView(view);
            end);
        end
        -- The collections journals keep their check all / uncheck all in the filter menu the same way
        -- (`Blizzard_MountCollection.lua`).
        rootDescription:CreateDivider();
        rootDescription:CreateButton(LLL["STORAGE_EXPAND_ALL"], function()
            self:SetAllCollapsed(false);
        end);
        rootDescription:CreateButton(LLL["STORAGE_COLLAPSE_ALL"], function()
            self:SetAllCollapsed(true);
        end);
    end);

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
    -- **The one place the word is explained** (2026-08-23, 소유자). It is the portrait's two tooltip
    -- lines now (`STORAGE_CREATE_TOOLTIP`, `STORAGE_CREATE_INSTRUCTION`), declared in the XML rather
    -- than written out here. The list names payloads all over itself and nothing on screen says what
    -- one is; a tooltip is read by somebody who stopped to ask, which is exactly who needs it.
    self.PortraitRow.CreatePortrait:SetScript("OnClick", function(button)
        MenuUtil.CreateContextMenu(button, SetupCreateMenu);
    end);
    self.Preview.AddButton:SetScript("OnClick", function() self:OnAddClicked(); end);
    self.Preview.CopyButton:SetScript("OnClick", function() self:OnCopyClicked(); end);
    -- The template's own `OnEnter` shows a disabled button's tooltip (`DisabledTooltipButtonMixin`),
    -- and only reaches a disabled button that is let take the cursor.
    self.Preview.CopyButton:SetMotionScriptsWhileDisabled(true);
    self.Preview.SelectAllCheck:SetScript("OnClick", function() self:OnSelectAllClicked(); end);

    NormalizeCheckMark(self.Preview.SelectAllCheck);

    -- **The bus is not registered with here.** ⚠ `DebindFrame` has no `OnLoad` in its XML - the
    -- window builds itself on the first `OnShow` and not before - while this runs when the file is
    -- read, which is login. `DebindFrame.Event` does not exist yet at that moment and reaching for
    -- it is an error rather than a nil registration, which is at least loud. `OnShow` below is
    -- where it goes, and that is the pattern Blizzard's own `CallbackRegistrantTemplate` describes.
end

function DebindStoragePanelMixin:InitializeScrollBoxes()
    local entryView = CreateScrollBoxListLinearView(2, 2, 2, 2, 3);
    entryView:SetElementFactory(function(factory)
        factory("DebindStorageEntryRowTemplate", function(frame, data) frame:Init(data); end);
    end);
    entryView:SetElementExtentCalculator(function() return ENTRY_ROW_HEIGHT; end);
    local listContent = self.List.ContentArea;
    ScrollUtil.InitScrollBoxListWithScrollBar(listContent.ScrollBox, listContent.ScrollBar, entryView);

    local previewView = CreateScrollBoxListLinearView(2, 2, 2, 2, 3);
    previewView:SetElementFactory(function(factory, elementData)
        if (elementData.isLayer) then
            factory("DebindStoragePreviewLayerTemplate",
                function(frame, data) frame:Init(data); end);
        elseif (elementData.isSpacer) then
            factory("Frame");
        else
            factory("DebindStoragePreviewRowTemplate",
                function(frame, data) frame:Init(data); end);
        end
    end);
    previewView:SetElementExtentCalculator(function(_, elementData)
        if (elementData.isSpacer) then
            return PREVIEW_GROUP_GAP;
        end
        return elementData.isLayer and LAYER_HEIGHT or PREVIEW_ROW_HEIGHT;
    end);
    previewView:SetElementIndentCalculator(function(elementData)
        return (elementData.isLayer or elementData.isSpacer) and 0 or PREVIEW_ROW_INDENT;
    end);
    local previewContent = self.Preview.ContentArea;
    ScrollUtil.InitScrollBoxListWithScrollBar(previewContent.ScrollBox, previewContent.ScrollBar,
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

    local scrollBox = self.List.ContentArea.ScrollBox;
    scrollBox:SetDataProvider(CreateDataProvider(list), true);
    scrollBox.EmptyText:SetText(LLL["IMPORT_DRAWER_EMPTY"]);
    scrollBox.EmptyText:SetShown(#list == 0);

    self:UpdateEntrySelectionDisplay();
end

function DebindStoragePanelMixin:UpdateEntrySelectionDisplay()
    self.List.ContentArea.ScrollBox:ForEachFrame(function(frame)
        frame:UpdateSelectionDisplay();
    end);
end

function DebindStoragePanelMixin:GetSelectedEntry()
    return self.selectedEntry;
end

--- Reads the entry that is showing and builds the layers again.
---
--- **The view state is not touched here.** What is ticked and what is collapsed are the reader's
--- answers rather than anything the payload decides, so cutting actions out of an entry can come
--- through this and keep them. Picking an entry throws them away on purpose, and does it itself.
function DebindStoragePanelMixin:RebuildPreviewLayers()
    self.previewLayers = nil;
    self.previewOwners = nil;
    self.previewKeys = nil;
    self.previewReason = nil;

    local entry = self.selectedEntry;
    if (not entry) then
        return;
    end

    local payload, reason = Store().GetEntryPayload(entry);
    if (payload) then
        self.previewLayers, self.previewOwners = BuildPreviewLayers(payload);
        return;
    end

    -- **The row stays.** An entry this cannot read is one there is nothing left to do with but
    -- delete, and the delete button is on the row, so the failure belongs in the column that was
    -- going to show it rather than in a message that takes the row away.
    self.previewReason = LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"];
end

--- The key view's groups (`BuildPreviewKeyGroups`), **built the first time that view asks for
--- them** after the layers were. They cost a binding per action, which the layer view has no use
--- for.
function DebindStoragePanelMixin:PreviewKeys()
    if (not self.previewKeys and self.previewOwners) then
        self.previewKeys = BuildPreviewKeyGroups(self.previewOwners);
    end
    return self.previewKeys or {};
end

--- Picks the entry the right column shows, and **starts its selection over**.
---
--- Everything ticked, because handing over what is in front of you should cost a glance and a
--- button; the boxes are there for the reader who wants less (2절). Nothing carries across from
--- the entry that was showing a moment ago -- two entries do not share an action table, so a
--- leftover tick could not survive anyway, and wiping says so rather than relying on it.
---
--- **This is the one door that clears the view state.** Coming back to a tab is not picking again
--- (`OnShow`), and cutting actions out of the entry that is showing is not either
--- (`RebuildPreviewLayers`).
function DebindStoragePanelMixin:SelectEntry(entry)
    -- The add dialog answers for the entry that was picked when it opened (소유자, 2026-09-24), and
    -- the name dialog goes with it, unsaved (소유자, 2026-09-29).
    if (entry ~= self.selectedEntry) then
        DebindAddFrame:CloseDialog();
        DebindEntryTextFrame:CloseDialog();
    end
    self.selectedEntry = entry;
    wipe(self.selected);
    wipe(self.collapsed);

    self:RebuildPreviewLayers();

    if (self.previewLayers) then
        self:SelectAll(true);
    end

    self:UpdateEntrySelectionDisplay();
    self:RefreshPreview(true);
end

--- No spacer at all when the gap is 0: the view takes an element of extent 0 for the end of the
--- data (`ScrollBoxListStrideMixin:CalculateDataIndices`) and draws nothing after it.
local function AddGroupGap(list)
    if (PREVIEW_GROUP_GAP > 0) then
        list[#list + 1] = { isSpacer = true };
    end
end

--- The rows actually drawn. **Collapsing hides, it does not untick** - a collapsed layer's actions
--- still travel and still count toward the header and the total. That is why the two lists are
--- separate: everything that asks "what is picked" reads `previewLayers`, and only drawing reads
--- this one.
---
--- **Headings stand in one rung.** A layer's heading names its owner, since nothing above it does.
function DebindStoragePanelMixin:BuildPreviewDisplayList()
    local list = {};

    if (self:GetPreviewView() == "key") then
        for i, keyGroup in ipairs(self:PreviewKeys()) do
            if (i > 1) then
                AddGroupGap(list);
            end
            list[#list + 1] = {
                isLayer = true,
                key = keyGroup.id,
                label = keyGroup.label,
                actions = keyGroup.actions,
            };
            if (not self:IsLayerCollapsed(keyGroup.id)) then
                for _, row in ipairs(keyGroup.rows) do
                    list[#list + 1] = row;
                end
            end
        end
        return list;
    end

    for _, owner in ipairs(self.previewOwners or {}) do
        for _, layer in ipairs(owner.layers) do
            if (#list > 0) then
                AddGroupGap(list);
            end
            list[#list + 1] = {
                isLayer = true,
                key = layer.key,
                label = layer.place.label,
                actions = layer.actions,
            };
            if (not self:IsLayerCollapsed(layer.key)) then
                for _, row in ipairs(layer.rows) do
                    list[#list + 1] = row;
                end
            end
        end
    end

    return list;
end

--- Redraws the right column from the layers already built. Collapsing does not re-read the entry.
---
--- **Three things it can be showing**, and the empty line says which: nothing picked, an entry
--- that cannot be read, or an entry with nothing in it.
function DebindStoragePanelMixin:RefreshPreview(resetScroll)
    local list = self:BuildPreviewDisplayList();
    local scrollBox = self.Preview.ContentArea.ScrollBox;
    -- `retainScrollPosition` is a boolean, so this is its negation rather than an `and`/`or`
    -- picking between the two constants: `DiscardScrollPosition` is `false`.
    scrollBox:SetDataProvider(CreateDataProvider(list), not resetScroll);

    local emptyText;
    if (not self.selectedEntry) then
        emptyText = LLL["STORAGE_NOTHING_PICKED"];
    elseif (self.previewReason) then
        emptyText = self.previewReason;
    elseif (#list == 0) then
        emptyText = LLL["EXPORT_EMPTY"];
    end

    scrollBox.EmptyText:SetText(emptyText or "");
    scrollBox.EmptyText:SetShown(emptyText ~= nil);

    self:UpdateSelectionState();
end

--- Which way the right column is grouped. **Kept across sessions**, the way Overview keeps its
--- [Sort] (`binSort`).
function DebindStoragePanelMixin:GetPreviewView()
    local main = DebindPrivate.UIVars and DebindPrivate.UIVars.main;
    return main and main.storageView == "key" and "key" or "layer";
end

function DebindStoragePanelMixin:SetPreviewView(view)
    local main = DebindPrivate.UIVars.main or {};
    DebindPrivate.UIVars.main = main;
    main.storageView = view ~= "layer" and view or nil;
    self:RefreshPreview();
end

function DebindStoragePanelMixin:IsLayerCollapsed(key)
    return self.collapsed[key] == true;
end

function DebindStoragePanelMixin:ToggleLayerCollapsed(key)
    self.collapsed[key] = not self.collapsed[key] or nil;
    self:RefreshPreview();
end

function DebindStoragePanelMixin:SetAllCollapsed(collapsed)
    wipe(self.collapsed);
    if (collapsed) then
        for _, elementData in ipairs(self:BuildPreviewDisplayList()) do
            if (elementData.isLayer) then
                self.collapsed[elementData.key] = true;
            end
        end
    end
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
    self.Preview.ContentArea.ScrollBox:ForEachFrame(function(frame)
        if (frame.UpdateSelectionDisplay) then
            frame:UpdateSelectionDisplay();
        end
    end);

    local listed = self:EnumerateListedActions();
    local state, selectedCount = CombineState(listed, self.selected);

    SetTriState(self.Preview.SelectAllCheck, state or STATE_NONE);
    -- **A state, not a verb.** One box picks everything up and puts everything down, so a label
    -- naming either is wrong whenever the other is what a click would do. Both numbers, because one
    -- on its own reads as the total.
    self.Preview.SelectAllCheck.Text:SetText(
        format(LLL["EXPORT_SELECTED_COUNT"], selectedCount, #listed));
    ExtendHitRectOverLabel(self.Preview.SelectAllCheck);
    self.Preview.SelectAllCheck:SetShown(#listed > 0);

    -- **Both read the same number**, which is the point of the tick being on the action: one writes
    -- a string and the other writes into the profile, and what they take is the same set.
    --
    -- **Greyed out rather than taken away** (2026-08-23, 소유자). They used to go with the column,
    -- on the grounds that nothing picked means an empty right column; a control that disappears
    -- takes with it the answer to "what can I do here", which is what the reader is asking on the
    -- screen where nothing is picked yet.
    self.Preview.AddButton:SetEnabled(selectedCount > 0);
    -- **Another addon's data does not go out as a string** (`ExportEntry`), and a grey button with
    -- no reason reads as broken.
    local entry = self.selectedEntry;
    local foreign = entry ~= nil and Store().IsForeignPayload(entry.payload);
    self.Preview.CopyButton:SetDisabledState(selectedCount == 0 or foreign,
        foreign and format(LLL["STORAGE_COPY_FOREIGN"], LLL["STORAGE_ADD"]) or nil);
end

--- A string already on screen describes a set that no longer exists, so it goes. **So does the add
--- dialog**: whether it asks about specializations was read off the ticks it opened on, and a
--- question it left out would be answered by a default the reader never saw.
---
--- **Not in `UpdateSelectionState`.** That runs for collapsing too, and collapsing changes nothing
--- about what would go out -- dropping the string there would contradict the rule the collapse
--- makes two functions away.
local function DropStaleDialogs()
    DebindCopyFrame:CloseDialog();
    DebindAddFrame:CloseDialog();
end
--- Cuts a set of actions out of the entry that is showing, and draws what is left.
---
--- **The set is copied before anything is removed.** The usual caller hands over `self.selected`
--- itself, and the tick set is cleared of what went, so without the copy that loop would be
--- emptying the table it is walking.
---
--- **What the reader set up survives the cut** (2026-08-22, 소유자). Only the actions that are gone
--- leave the tick set. What is collapsed, where the column is scrolled to and what is still ticked
--- are all answers they gave, and re-picking the entry, which is how this used to redraw, took all
--- three back. The tick set is the sharp one: it is what `Copy` and `Add` read, so handing it back
--- as everything makes the next press send what nobody picked.
---
--- A layer that has just lost its last action goes with it, so the headers cannot outlive their
--- rows (`RemoveEntryActions`).
function DebindStoragePanelMixin:DeleteActions(actions)
    local entry = self.selectedEntry;
    if (not entry) then
        return;
    end

    local doomed = {};
    for action in pairs(actions) do
        doomed[action] = true;
    end

    if (Store().RemoveEntryActions(entry, doomed) == 0) then
        return;
    end

    for action in pairs(doomed) do
        self.selected[action] = nil;
    end

    DropStaleDialogs();
    self:RebuildPreviewLayers();
    self:RefreshPreview();

    -- The row's counts are drawn from the payload, so the left column is stale too.
    self:RefreshEntries();
end


function DebindStoragePanelMixin:SelectAll(selected)
    DropStaleDialogs();
    local listed = self:EnumerateListedActions();
    for i = 1, #listed do
        self.selected[listed[i]] = selected or nil;
    end
    self:UpdateSelectionState();
end

function DebindStoragePanelMixin:ToggleAction(action)
    DropStaleDialogs();
    self.selected[action] = not self.selected[action] or nil;
    self:UpdateSelectionState();
end

--- A layer toggles as a whole, and "some" counts as off -- one more click gets all of it, which is
--- what the middle state is asking for.
function DebindStoragePanelMixin:ToggleLayer(actions)
    DropStaleDialogs();
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
function DebindStoragePanelMixin:OnCreateClicked(wholeAccount)
    local entry = wholeAccount and Store().CreateAccountEntry() or Store().CreateEntry();
    DebindFrame:NotifyStoreChanged();

    -- **Landed on, not just listed.** A new row at the top of a list the reader is already looking
    -- at is easy to miss, and the right column standing empty beside it says nothing happened.
    self:SelectEntry(entry);
end

--- A Clique profile becomes an entry, all of it in General, since the file names no layer
--- (`importing-clique-profiles.md` §3). Where it goes is asked when it is added.
function DebindStoragePanelMixin:OnCliqueProfileClicked(profile)
    local payload = Store().PayloadFromCliqueBindings(profile.bindings, Constants.GAME_TYPE);
    -- The profile's own name and nothing wrapped round it: that it came from Clique is the row's
    -- icon and the tooltip's to say.
    local entry, reason = Store().StorePayload(payload, profile.name);
    if (not entry) then
        DebindPrivate.DisplayMessage(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"], 1, 0, 0);
        return;
    end
    DebindFrame:NotifyStoreChanged();
    self:SelectEntry(entry);
end

--- [Add to My Bindings]: the dialog that asks how, and for a Clique entry where
--- (`importing-clique-profiles.md` §3), since the file names no layer and no class for its
--- specialization numbers.
function DebindStoragePanelMixin:OnAddClicked()
    local entry = self.selectedEntry;
    if (not entry) then
        return;
    end

    local payload = entry.payload;
    local fromClique = payload and payload.fromAddon == Store().FROM_ADDON_CLIQUE;
    DebindAddFrame:Open({
        fromClique = fromClique,
        hasSpecs = fromClique and self:SelectionHasCliqueSpecs(),
        choices = payload and not fromClique and Store().AddChoices(payload, self.selected) or nil,
        identities = payload and payload.characters,
        onAccept = function(accept, layer, specs, parts)
            self:CommitSelected(entry, accept, layer, specs, parts);
        end,
    });
end

--- Whether any ticked action still carries a specialization restriction once one that ticks every
--- specialization of this class counts as none (`CliqueActionHasSpecs`). That is when the dialog
--- asks about them at all.
function DebindStoragePanelMixin:SelectionHasCliqueSpecs()
    for action in pairs(self.selected) do
        if (Store().CliqueActionHasSpecs(action)) then
            return true;
        end
    end
    return false;
end

--- An entry's ticked actions go into the profile.
---
--- **Both buttons land the same way**, badged, and `accept` says whether to take the badges off
--- again on the spot. It used to be a flag that reached down into the plan and left the badge off,
--- which put the actions live on the sender's keys with nothing asked -- and where the reader
--- already used one of those keys, that is a merge they never chose. Accepting is the path that
--- asks about exactly that, so the second button goes through it (2026-08-23, 소유자).
---
--- **The message afterwards is not decoration.** What lands is quarantined and greyed out, so from
--- the reader's side the screen barely moves: without a line saying what happened and where to go
--- next, a press that did a lot looks like a press that did nothing.
---
--- **Which line depends on what the approval did, not on what was asked for.** A key nobody uses is
--- accepted where it stands and the actions are live; an occupied one puts a prompt up, and until
--- it is answered the true thing to say is what the other button's line says.
function DebindStoragePanelMixin:CommitSelected(entry, accept, layer, specs, parts)
    local placed, skipped, actions = Store().CommitEntry(entry, {
        selection = self.selected,
        layer = layer,
        specs = specs,
        parts = parts,
    });

    -- **The second return is a reason code while the first is nil, and a count once it is not.**
    -- `CommitEntry` answers a failure the way the rest of `Import.lua` does (`nil, reason`), so one
    -- slot carries both and `placed` is the only thing telling them apart. This early return is what
    -- keeps a reason code out of the count below.
    if (not placed) then
        local reason = skipped;
        DebindPrivate.DisplayMessage(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"], 1, 0, 0);
        return;
    end

    local accepted = accept and DebindFrame:ApproveArrivals(actions);

    DebindPrivate.DisplayMessage(format(
        LLL[accepted and "IMPORT_COMMITTED_KEYED" or "IMPORT_COMMITTED"], CountText("actions", placed)));
    -- Layers a newer payload version invented and this one cannot place. Said separately because it is the
    -- one case where the count above is not the whole string. **Actions the reader unticked are
    -- not in here** - they said no, which is not this version having nowhere to put it.
    if (skipped and skipped > 0) then
        DebindPrivate.DisplayMessage(format(LLL["IMPORT_COMMITTED_SKIPPED"],
            CountText("actions", skipped)), 1, 0.5, 0);
    end
    -- **Nothing brings a switch in with the actions** (`importing-switches-apart-from-actions.md`
    -- 2-3), so the ones landing red are named here, while the reader still knows which press did it.
    local missing = DebindPrivate.UndefinedSwitchNames(actions);
    if (#missing > 0) then
        DebindPrivate.DisplayMessage(format(LLL["IMPORT_COMMITTED_MISSING_SWITCHES"],
            table.concat(missing, ", ")), 1, 0.5, 0);
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
    FOREIGN_PAYLOAD = "STORAGE_COPY_FOREIGN",
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
        -- `STORAGE_COPY_FOREIGN` points at the add button by its label; the others take nothing.
        DebindPrivate.DisplayMessage(key and format(LLL[key], LLL["STORAGE_ADD"]) or tostring(reason),
            1, 0, 0);
        return;
    end

    DebindCopyFrame:ShowText(str);
end


--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function DebindStoragePanelMixin:OnShow()
    -- **This panel is the bus's first registrant** (`FRAME_EVENTS` in `DebindUI.lua`). An entry can
    -- be made from a screen that is not this one -- the overview's key group menu -- so the list
    -- redraws on the event rather than on the presses it happens to own.
    --
    -- **Here rather than in `OnLoad`**, because the window declares its events in an `OnLoad` that
    -- does not run until it is first opened. Getting here at all means the window is up, so the
    -- registry is up too.
    --
    -- Registering again on every show costs nothing: an owner holds one callback per event and a
    -- second registration replaces the first (`CallbackRegistry.lua`).
    DebindFrame:RegisterCallback(DebindFrame.Event.OnStoreChanged, self.RefreshEntries, self);

    self:RefreshEntries();

    -- **The entry that was showing is read again, and what the reader set up stays** (2026-08-23,
    -- 소유자). The layers are rebuilt because which layer an address belongs to is this character's
    -- answer and it can have moved while the tab was away, and because a payload gets walked
    -- forward as it is opened (`GetEntryPayload`).
    --
    -- **The ticks and the folds survive that.** Both walks write into the stored tables rather than
    -- replacing them (`MigrateLayer`) and the preview holds those same tables, so the set that is
    -- keyed by them still points at what is on screen. Going through `SelectEntry` instead threw
    -- both away, which made every tab change an undo of the reader's last few clicks.
    self:RebuildPreviewLayers();
    self:RefreshPreview();
end

function DebindStoragePanelMixin:OnHide()
    -- **Off the bus while hidden.** Redrawing a column nobody is looking at is work for nothing,
    -- and `OnShow` reads the list again anyway - so nothing is missed by not listening. The pair of
    -- these two is what `CallbackRegistrantTemplate` is.
    DebindFrame:UnregisterCallback(DebindFrame.Event.OnStoreChanged, self);

    -- **Nothing the reader set up is thrown away here**, and `OnShow` no longer throws it away
    -- either: an entry is plain stored data whose whole purpose is to survive being closed, and
    -- which of it is ticked and which layers are open are answers worth the same until the reader
    -- picks a different entry. Only a `/reload` ends them, since they live on the panel.
    --
    -- **The paste box does go, but not from here.** This script also runs when something sweeps the
    -- window out of `UISpecialFrames` and it goes straight back up, and dropping a half-typed
    -- string because the reader opened their spellbook is the thing that sweep must not do. Leaving
    -- the tab and closing the window are the two that mean it, and each says so where it happens
    -- (`DebindFrameMixin:SelectPanel`, `DebindFrameMixin:OnHide`).

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
        self:CloseDialog();
    end);

    self.AcceptButton:SetScript("OnClick", function() self:Accept(); end);
    self.CancelButton:SetScript("OnClick", function() self:CloseDialog(); end);
end

--- **Clearing belongs to opening, not to showing.** In `OnShow` it throws away a half-typed string
--- every time `CloseSpecialWindows` sweeps this dialog and `DebindDialogMixin:OnDialogHide` puts it
--- back. This is the only way the dialog opens, so the move covers the same ground.
function DebindPasteFrameMixin:Open()
    -- **The add dialog goes first.** It takes the first rung of the ESC ladder, so standing it
    -- under this one would have ESC close the dialog the reader is not looking at.
    DebindAddFrame:CloseDialog();
    self.Input.EditBox:SetText("");
    self.NameBox:SetText("");
    self.ErrorHolder.Text:SetText("");
    self.AcceptButton:SetEnabled(false);
    self:Show();
    self.Input.EditBox:SetFocus();
end

--- **A refusal stays in this dialog.** The string is someone else's input and every step of reading
--- it is allowed to fail, so the one place a failure can be acted on is the one still holding the
--- text that caused it. Closing first and reporting into the chat frame would leave the reader with
--- a message and nothing to fix.
function DebindPasteFrameMixin:Accept()
    local text = self.Input.EditBox:GetText();
    local name = strtrim(self.NameBox:GetText());
    -- **A Clique code left unnamed stays unnamed.** It carries no profile name, and what the row
    -- shows in its place is drawn rather than stored (`EntryName`).
    local entry, reason = Store().ImportEntry(text, name ~= "" and name or nil);

    if (not entry) then
        self.ErrorHolder.Text:SetText(LLL[REASON_TEXT[reason] or "IMPORT_FAILED_DAMAGED"]);
        return;
    end

    self:CloseDialog();

    -- **Through the bus, and then landed on.** The list is the same list every other way in feeds,
    -- and the row would be easy to miss at the top of one the reader is already looking at.
    DebindFrame:NotifyStoreChanged();
    DebindStoragePanel:SelectEntry(entry);
end


--------------------------------------------------------------------------------
-- Naming and describing an entry
--------------------------------------------------------------------------------

--- The row menu's one item (`showing-what-an-entry-holds.md` 4절): a name and a description, both
--- optional, in one dialog rather than one each. The paste dialog's shape, since that one already
--- has a line for a name beside a box that takes line breaks.
DebindEntryTextFrameMixin = {};

function DebindEntryTextFrameMixin:OnLoad()
    self:InitDialog(LLL["STORAGE_ENTRY_EDIT"]);
    self.NameBox.Label:SetText(LLL["IMPORT_PASTE_NAME"]);
    self.InputLabel:SetText(LLL["STORAGE_ENTRY_EDIT_DESCRIPTION"]);
    self.AcceptButton:SetText(SAVE);

    -- **The same limits the row and the tooltip draw to** (`PlainText`), so what is typed is what
    -- shows. Longer, and the rest would be kept and never seen.
    self.NameBox:SetMaxLetters(NAME_MAX_CHARS);
    local editBox = self.Input.EditBox;
    editBox:SetMaxLetters(DESCRIPTION_MAX_CHARS);
    editBox:SetFontObject(ChatFontNormal);
    editBox:SetScript("OnEscapePressed", function()
        editBox:ClearFocus();
        self:CloseDialog();
    end);
    self.NameBox:SetScript("OnEscapePressed", function()
        self.NameBox:ClearFocus();
        self:CloseDialog();
    end);
    self.NameBox:SetScript("OnEnterPressed", function() self:Accept(); end);

    self.AcceptButton:SetScript("OnClick", function() self:Accept(); end);
    self.CancelButton:SetScript("OnClick", function() self:CloseDialog(); end);
end

--- Opens on the entry's current text, the name selected so the first keystroke replaces it.
function DebindEntryTextFrameMixin:Open(entry)
    DebindAddFrame:CloseDialog();
    DebindPasteFrame:CloseDialog();
    local payload = type(entry.payload) == "table" and entry.payload or {};
    self.entry = entry;
    self.NameBox:SetText(type(payload.name) == "string" and payload.name or "");
    self.Input.EditBox:SetText(type(payload.description) == "string" and payload.description or "");
    self:Show();
    self.NameBox:SetFocus();
    self.NameBox:HighlightText();
end

--- The dialog answers for the entry it was opened on, so one that is gone takes it down.
function DebindEntryTextFrameMixin:CloseFor(entry)
    if (self.entry == entry) then
        self:CloseDialog();
    end
end

function DebindEntryTextFrameMixin:Accept()
    local entry = self.entry;
    self:CloseDialog();
    if (entry and Store().SetEntryText(entry, self.NameBox:GetText(), self.Input.EditBox:GetText())) then
        DebindFrame:NotifyStoreChanged();
    end
end


--------------------------------------------------------------------------------
-- Adding an entry
--------------------------------------------------------------------------------

--- How an entry's ticked actions go in, and for a Clique entry where and what becomes of its
--- specialization numbers (`importing-clique-profiles.md` §3).
---
--- **Two axes, two dropdowns**: the specialization answer does not depend on the layer except that
--- General has only one, and a single list of every pair would run to lines that hide it.
---
--- **Only this character's class and this character.** What is added has to be checkable on the
--- spot, and another class's or another character's layer cannot be looked at from here (소유자).
DebindAddFrameMixin = {};

local CLIQUE_LAYERS = { "general", "class", "character" };
--- In the order offered, the first being the default: a specialization's actions belong on its own
--- layer, which is how this addon is meant to be used (소유자, 2026-09-24).
local CLIQUE_SPECS = { "layers", "convert", "drop" };

--- **The window's own name for each layer**, so the dialog says what the layer list on the left
--- says once the actions are there.
local function AddLayerLabel(layer)
    return (DebindUI.GetColoredLayerLabel(DebindUI.GetLayerIDForAddress(layer, 0)));
end

local CLIQUE_SPEC_LABELS = {
    layers = "STORAGE_ADD_SPECS_LAYERS",
    convert = "STORAGE_ADD_SPECS_CONVERT",
    drop = "STORAGE_ADD_SPECS_DROP",
};

--- A character key of the payload as the dropdown shows it: its character layer's label. Always
--- this class.
local function CharacterChoiceLabel(owner, identity)
    return (DebindUI.GetColoredLayerLabel(DebindUI.GetLayerIDForAddress("character", 0), nil,
        CharacterName(owner, identity)));
end

local function SetButtonTooltip(button, text)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        GameTooltip_SetTitle(GameTooltip, button:GetText());
        GameTooltip_AddNormalLine(GameTooltip, text);
        GameTooltip:Show();
    end);
    button:SetScript("OnLeave", GameTooltip_Hide);
end

function DebindAddFrameMixin:OnLoad()
    self:InitDialog(LLL["STORAGE_ADD"]);
    self.CharacterLabel:SetText(LLL["STORAGE_ADD_CHARACTER"]);
    self.LayerLabel:SetText(LLL["STORAGE_ADD_LAYER"]);
    self.SpecsLabel:SetText(LLL["STORAGE_ADD_SPECS"]);
    self.PendingButton:SetText(LLL["STORAGE_ADD_QUARANTINED"]);
    self.AcceptedButton:SetText(LLL["STORAGE_ADD_ACCEPTED"]);
    SetButtonTooltip(self.PendingButton, LLL["STORAGE_ADD_QUARANTINED_DESC"]);
    SetButtonTooltip(self.AcceptedButton, LLL["STORAGE_ADD_ACCEPTED_DESC"]);

    self.GeneralCheck.Text:SetText(AddLayerLabel("general"));
    self.ClassCheck.Text:SetText(AddLayerLabel("class"));
    for _, check in ipairs({ self.GeneralCheck, self.ClassCheck }) do
        NormalizeCheckMark(check);
        ExtendHitRectOverLabel(check);
        check:SetScript("OnClick", function() self:Refresh(); end);
    end

    self.CharacterDropdown:SetupMenu(function(_, rootDescription)
        for _, owner in ipairs(self.characters or {}) do
            rootDescription:CreateRadio(CharacterChoiceLabel(owner, self.identities and self.identities[owner]),
                function() return self.character == owner; end,
                function()
                    self.character = owner;
                    self:Refresh();
                end);
        end
        rootDescription:CreateRadio(NONE, function() return self.character == nil; end, function()
            self.character = nil;
            self:Refresh();
        end);
    end);

    self.LayerDropdown:SetupMenu(function(_, rootDescription)
        for _, layer in ipairs(CLIQUE_LAYERS) do
            rootDescription:CreateRadio(AddLayerLabel(layer), function()
                return self.layer == layer;
            end, function()
                self.layer = layer;
                self:Refresh();
            end);
        end
    end);

    self.SpecsDropdown:SetupMenu(function(_, rootDescription)
        local className = Constants.CLASS_NAMES[Constants.PLAYER_CLASS];
        for _, specs in ipairs(CLIQUE_SPECS) do
            local label = format(LLL[CLIQUE_SPEC_LABELS[specs]], className);
            local description = rootDescription:CreateRadio(label, function()
                return self:SpecsAnswer() == specs;
            end, function()
                self.specs = specs;
                self:Refresh();
            end);
            if (specs == "layers") then
                description:SetTooltip(function(tooltip, elementDescription)
                    GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
                    GameTooltip_AddNormalLine(tooltip, LLL["STORAGE_ADD_SPECS_LAYERS_DESC"]);
                end);
            end
        end
    end);

    self.PendingButton:SetScript("OnClick", function() self:Accept(false); end);
    self.AcceptedButton:SetScript("OnClick", function() self:Accept(true); end);
    self.CancelButton:SetScript("OnClick", function() self:CloseDialog(); end);
end

--- What the specialization dropdown stands on: the reader's pick, except on General.
function DebindAddFrameMixin:SpecsAnswer()
    if (self.layer == "general") then
        return "drop";
    end
    return self.specs;
end

--- Stacks what is shown from the top of `ContentArea` and fits the dialog's height to it.
function DebindAddFrameMixin:Layout()
    local GROUP_GAP, LABEL_GAP = 16, 6;
    local width = self.ContentArea:GetWidth();
    local y = 0;
    local function Stack(region, gap, keepWidth)
        if (not region:IsShown()) then
            return;
        end
        region:ClearAllPoints();
        region:SetPoint("TOPLEFT", self.ContentArea, "TOPLEFT", 0, -(y + gap));
        if (not keepWidth) then
            region:SetWidth(width);
        end
        y = y + gap + (region.GetStringHeight and region:GetStringHeight() or region:GetHeight());
    end
    Stack(self.Text, 0);
    Stack(self.GeneralCheck, GROUP_GAP, true);
    Stack(self.ClassCheck, self.GeneralCheck:IsShown() and 0 or GROUP_GAP, true);
    Stack(self.CharacterLabel, GROUP_GAP);
    Stack(self.CharacterDropdown, LABEL_GAP);
    Stack(self.LayerLabel, GROUP_GAP);
    Stack(self.LayerDropdown, LABEL_GAP);
    -- The red text on General says "this layer", so it hangs off the dropdown that picked it.
    Stack(self.SpecsText, self.layer == "general" and LABEL_GAP or GROUP_GAP);
    Stack(self.SpecsLabel, GROUP_GAP);
    Stack(self.SpecsDropdown, LABEL_GAP);
    -- `ContentArea`'s insets (40 above, 25 below) and the button row under the stack.
    self:SetHeight(40 + y + 24 + self.AcceptedButton:GetHeight() + 25);
end

--- **On General the specialization text turns red and says they are removed**, and the question
--- under it goes: there is one answer and nothing to pick (소유자, 2026-09-24).
function DebindAddFrameMixin:Refresh()
    local general = self.layer == "general";
    self.CharacterDropdown:GenerateMenu();
    self.LayerDropdown:GenerateMenu();
    self.SpecsDropdown:GenerateMenu();
    self.SpecsText:SetText(LLL[general and "STORAGE_ADD_SPECS_GENERAL" or "STORAGE_ADD_SPECS_TEXT"]);
    self.SpecsText:SetTextColor((general and RED_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB());
    self.SpecsLabel:SetShown(self.asksSpecs and not general);
    self.SpecsDropdown:SetShown(self.asksSpecs and not general);

    -- Nothing picked is nothing to add, and a press that adds nothing only says so afterwards.
    local parts = self:Parts();
    local any = self.fromClique or (parts and (parts.general or parts.class or parts.character ~= nil));
    self.PendingButton:SetEnabled(any);
    self.AcceptedButton:SetEnabled(any);
    self:Layout();
end

--- What the two boxes and the dropdown answer, in `PlanArrival`'s `options.parts` shape. Nil for a
--- Clique entry, which is asked where to go instead.
function DebindAddFrameMixin:Parts()
    if (self.fromClique) then
        return nil;
    end
    return {
        general = self.GeneralCheck:IsShown() and self.GeneralCheck:GetChecked(),
        class = self.ClassCheck:IsShown() and self.ClassCheck:GetChecked(),
        character = self.character,
    };
end

--- `opts.fromClique` puts up the layer question; `opts.hasSpecs` is whether any ticked action still
--- carries a specialization restriction (`CliqueActionHasSpecs`). **Without one the specialization
--- question is not asked at all**, rather than asked about nothing.
---
--- Any other entry is asked what to take (`AddChoices` in `opts.choices`): a box for the general
--- layer and one for this class's where the ticked actions have any, and the character dropdown
--- where there is a character of this class to pick. `opts.identities` is the payload's
--- `characters`, for the names. `opts.onAccept(accept, layer, specs, parts)`.
function DebindAddFrameMixin:Open(opts)
    self.onAccept = opts.onAccept;
    self.fromClique = opts.fromClique;
    self.layer = "class";
    self.specs = CLIQUE_SPECS[1];
    self.Text:SetText(LLL[opts.fromClique and "STORAGE_ADD_CLIQUE_TEXT" or "STORAGE_ADD_TEXT"]);
    self.LayerLabel:SetShown(opts.fromClique);
    self.LayerDropdown:SetShown(opts.fromClique);
    self.asksSpecs = opts.fromClique and opts.hasSpecs;
    self.SpecsText:SetShown(self.asksSpecs);

    local choices = not opts.fromClique and opts.choices or nil;
    self.identities = opts.identities;
    self.characters = choices and choices.characters or {};
    self.character = choices and choices.character;
    self.GeneralCheck:SetShown(choices and choices.general or false);
    self.ClassCheck:SetShown(choices and choices.class or false);
    self.GeneralCheck:SetChecked(true);
    self.ClassCheck:SetChecked(true);
    self.CharacterLabel:SetShown(#self.characters > 0);
    self.CharacterDropdown:SetShown(#self.characters > 0);

    self:Show();
    self:Refresh();
end

function DebindAddFrameMixin:Accept(accept)
    local onAccept = self.onAccept;
    self.onAccept = nil;
    local parts = self:Parts();
    self:CloseDialog();
    if (onAccept) then
        onAccept(accept, self.layer, self:SpecsAnswer(), parts);
    end
end


--------------------------------------------------------------------------------
-- The copy dialog
--------------------------------------------------------------------------------

DebindCopyFrameMixin = {};

function DebindCopyFrameMixin:OnLoad()
    self:InitDialog(LLL["EXPORT_COPY_TITLE"]);
    self.CloseDialogButton:SetScript("OnClick", function() self:CloseDialog(); end);

    local editBox = self.Output.EditBox;
    editBox:SetFontObject(ChatFontNormal);

    -- **Editing is not blocked here, on purpose.** There was a guard that put the string back on
    -- every keystroke, and it was guarding the wrong end: it cannot cover a paste that was copied
    -- half way, or a string somebody wrote by hand, so the import side has to be safe against any
    -- string whatever this dialog does. Once it is, an edited string is one more string it turns
    -- away, and this is a text box the reader is allowed to treat as a text box.
    editBox:SetScript("OnEscapePressed", function()
        editBox:ClearFocus();
        self:CloseDialog();
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
