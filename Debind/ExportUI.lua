local _, DebindPrivate = ...;

local LLL              = DebindPrivate.L;
local DebindUI         = DebindPrivate.DebindUI;

--- The addon that builds and keeps the strings, parked here when it loads (`EnsureStore` in
--- `DebindUI.lua`).
---
--- **Read at call time, never at file scope.** This file is read at login and that one is not: it
--- is load on demand, and the whole reason it was split off is that nothing of it is touched until
--- a reader opens one of these two tabs. A local taken up here would be `nil` forever.
---
--- Nothing below guards the result, because everything that calls it is reached from a panel that
--- `ResolvePanel` refused to show until the load succeeded.
---
--- ⚠ **`OnLoad` is not one of those places.** These frames are built when this file is read, which
--- is login, and that is *before* any of it. `ImportUI.lua` broke exactly there in the move.
local function Store()
    return DebindPrivate.Store;
end

--- The export panel: the main window's Export tab.
---
--- One list, three rungs: everything -> layer -> action. Everything starts selected, because the
--- common case is "send all of it" and that should cost a glance and a button.
---
--- **Only the first two rungs are checkboxes.** An action is shown picked by lighting its row, the
--- way the main window shows a selected row. Boxes all the way down made three columns of them and
--- left no way to tell a layer's box from an action's at a glance.
---
--- **The axis is the layer, and the panel has to say so.** A key's behaviour is computed across
--- layers, so what this panel can honestly promise is *the contents of these layers* -- if the
--- receiving side arranges its layers one notch differently, the same actions on the same keys
--- behave differently with nothing missing and nothing overwritten. `devdocs/building-export-import.md`.
---
--- Nothing here validates. A broken action exports as it sits; the far side shows it in red and
--- the user deletes it. That single rule is what removes every question about spells, macros and
--- specs the reader might not have. Where red text cannot in fact see the breakage, `Export.lua`
--- carries the answer in the format instead.
---
--- The one thing that is still a window is the copy dialog at the bottom of this file. A generated
--- string outlives the tab it came from: switching to Overview to check something should not take
--- away the text you were about to paste.

local ROW_HEIGHT       = 28;
local LAYER_HEIGHT     = 26;
local ROW_INDENT       = 10;


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
local CHECK_ALL          = "checkmark-minimal";
local CHECK_SOME         = "common-icon-minus";

--- How much of the box the mark fills. Neither atlas is drawn to sit inside `checkbox-minimal` -
--- at their own sizes the tick overflows the box and the dash is unrelated to it again - so the
--- size comes from the button and both marks take the same share of it. One number to move.
local MARK_SCALE         = 1;

--- **The dash gets its own share, smaller.** The two atlases are drawn to different margins:
--- `checkmark-minimal` carries whitespace inside its canvas and `common-icon-minus` runs edge to
--- edge, so giving them the same box makes the dash come out looking like the larger mark.
local SOME_MARK_SCALE    = 0.55;

local function SetMark(checkButton, atlas)
    local mark = checkButton:GetCheckedTexture();
    local size = checkButton:GetWidth()
        * (atlas == CHECK_SOME and SOME_MARK_SCALE or MARK_SCALE);
    -- `false`, not `true`: the atlas must not take the size back, or the `SetSize` below is undone.
    mark:SetAtlas(atlas, false);
    mark:SetSize(size, size);
end

--- **Every checkbox in this window goes through here once, tri-state or not.**
---
--- The template's checked texture carries no anchors of its own, so it stretches to fill the whole
--- button - and a `SetSize` on something pinned on both sides does nothing. Pinning one point is
--- what puts the size under our control. Doing this only where the mark gets swapped left the rest
--- of the window drawing its ticks at another size in another place, which is worse than either
--- shape on its own: the boxes stop looking like the same control.
---
--- **Centred on the box art, not on the button.** The box is drawn at its atlas size while the
--- button is whatever the XML asked for, so those two are only the same rectangle by accident.
--- Centring on the button leaves the mark sitting off to one side of the box it belongs in.
local function NormalizeCheckMark(checkButton)
    local mark = checkButton:GetCheckedTexture();
    mark:ClearAllPoints();
    mark:SetPoint("CENTER", checkButton:GetNormalTexture(), "CENTER");
    SetMark(checkButton, CHECK_ALL);
end

--- Puts a checkbox's caption inside its hit area.
---
--- A word sitting against a box is read as part of the control, so it has to behave like one. On
--- its own the box is a 24px target, which is a small thing to ask someone to hit for a setting
--- whose name is right there. Called again whenever the caption changes - the reach has to follow
--- the text, not the text it happened to have at load.
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
--- Counting apart from the walk that decides the mark is one question answered in two places.
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
-- Rows
--------------------------------------------------------------------------------

--- An empty list, not nil: the tooltip reads nil as "use your default two lines".
local NO_INSTRUCTIONS = {};

--- What `EncodeExportPayload` can answer, and the sentence for each.
---
--- **One entry, and the table is still worth having.** A reason with no sentence has to come out
--- as something other than a locale key on the reader's screen, and that cannot be arranged after
--- an `L` lookup (see where this is read).
local EXPORT_FAILED_TEXT = {
    LIBS_MISSING = "EXPORT_FAILED_LIBS_MISSING",
};

DebindExportRowMixin = {};

function DebindExportRowMixin:Init(elementData)
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

function DebindExportRowMixin:UpdateSelectionDisplay()
    self.SelectedHighlight:SetShown(DebindExportPanel.selected[self.elementData.action] == true);
end

function DebindExportRowMixin:OnClick()
    DebindExportPanel:ToggleAction(self.elementData.action);
    self:UpdateSelectionDisplay();
end

--- The same tooltip the other two lists draw, rather than a name and a key written out here.
---
--- **What is being picked is the whole action**, and a name plus a key does not say what leaves
--- with it. Three lines of it were also a second place holding the words for "no key" and for a
--- key group's synthetic number, and a second place is a place to drift.
---
---   * the scope line is on, because this list mixes layers in one scroll and a long group's
---     header scrolls out of sight. That is the same reason the order list carries it.
---   * inactive is suppressed, because **this list does not use colour to say it**: the rows draw
---     an uncoloured name, and a tooltip greying the key under one of them would be the two
---     halves of one row disagreeing. Nothing here turns on whether an action runs right now.
---   * no instruction line, which is what this row has always had. The shared default would be
---     two lies: a left click here ticks rather than selects, and there is no right-click menu.
function DebindExportRowMixin:OnEnter()
    local elementData = self.elementData;
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    DebindPrivate.AddActionToTooltip(GameTooltip, elementData.action, {
        offWorld = DebindUI.IsLayerOffWorld(elementData.layerID),
        suppressInactive = true,
        instructionKeys = NO_INSTRUCTIONS,
        layerLabel = DebindUI.GetLayerLabel(elementData.layerID),
    });
    GameTooltip:Show();
end

function DebindExportRowMixin:OnLeave()
    DebindPrivate.HideActionTooltip(GameTooltip);
end


--------------------------------------------------------------------------------
-- Layers
--------------------------------------------------------------------------------

--- A layer header: the game's own collapsible list header (`ListHeaderThreeSliceTemplate`, what
--- the cooldown manager's settings and the currency tab use), with a tri-state checkbox added on
--- the left.
---
--- The quiet bar, not the quest log's `ListHeaderVisualTemplate`: a layer is the divider this
--- list is cut on rather than the thing being chosen, and the louder art reads as the latter.
---
--- The bar carries **two** gestures and they are split by area: the checkbox selects the layer,
--- everything else collapses it, and the bar's right-hand cap says which way it currently sits.
DebindExportLayerMixin = {};

function DebindExportLayerMixin:OnLoad()
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
        DebindExportPanel:ToggleLayer(self.elementData.actions);
        self:UpdateSelectionDisplay();
    end);
end

function DebindExportLayerMixin:Init(elementData)
    self.elementData = elementData;
    self:UpdateCollapsedState(DebindExportPanel:IsLayerCollapsed(elementData.layerID));
    self:UpdateSelectionDisplay();
end

--- **The header carries a fraction, and the box beside it carries a shape.** All / some / none is
--- what the tick can say, and "some" is exactly the state a reader has to open the layer to make
--- sense of - so the layer that is half picked answers the question where it is asked, and a shut
--- one does not have to be opened to be read.
---
--- Written here rather than in `Init` because the left-hand number moves with every tick, and a
--- header drawn once would go on saying what the selection used to be.
function DebindExportLayerMixin:UpdateSelectionDisplay()
    local actions = self.elementData.actions;
    local state, selectedCount = CombineState(actions, DebindExportPanel.selected);

    self:SetHeaderText(format(LLL["EXPORT_LAYER_HEADER"],
        DebindUI.GetLayerLabel(self.elementData.layerID), selectedCount, #actions));
    SetTriState(self.Check, state or STATE_NONE);
end

--- The bar collapses. Selecting is the checkbox's job and it swallows its own clicks, so a click
--- arriving here is always about showing and hiding.
function DebindExportLayerMixin:OnClick()
    DebindExportPanel:ToggleLayerCollapsed(self.elementData.layerID);
end

function DebindExportLayerMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, DebindUI.GetLayerLabel(self.elementData.layerID));
    GameTooltip_AddNormalLine(GameTooltip,
        format(LLL["EXPORT_LAYER_COUNT"], #self.elementData.actions));
    GameTooltip:Show();
end

function DebindExportLayerMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

DebindExportPanelMixin = {};

function DebindExportPanelMixin:OnLoad()
    -- **What this panel asks the frame to be** is a `KeyValue` in the XML, read by `SelectPanel`
    -- when this tab is chosen. The frame is free to be a different width per tab, and the panel
    -- that knows what it needs is the one that should say: Overview wants two columns, this is one
    -- list.

    self.SelectAllCheck.Text:SetText(LLL["EXPORT_SELECT_ALL"]);
    self.GenerateButton:SetText(LLL["EXPORT_GENERATE"]);

    --- Which actions go. Keyed by the action table itself, so it survives the list being rebuilt
    --- and never has to be reconciled with an index.
    self.selected = {};

    --- Which layer headers are shut, by layerID. A view state and nothing else: a collapsed layer
    --- still exports.
    self.collapsed = {};

    self:InitializeScrollBox();

    -- **No ESC, no drag, no title here.** This is a panel inside the main frame, and all three of
    -- those are that frame's. It used to register with `UISpecialFrames` as a standalone window;
    -- doing so now would mean ESC closes the whole window from one of its three tabs and not the
    -- other two.

    -- **The chrome widgets get their scripts here.** XML's `method=` looks the name up on the
    -- element's *own* mixin, so naming the frame's method on a plain Blizzard template finds
    -- nothing. List rows are the other way round: those carry a mixin, so `method=` is right there.
    self.SelectAllCheck:SetScript("OnClick", function() self:OnSelectAllClicked(); end);
    self.GenerateButton:SetScript("OnClick", function() self:OnGenerateClicked(); end);

    NormalizeCheckMark(self.SelectAllCheck);
end

function DebindExportPanelMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory, elementData)
        if (elementData.isLayer) then
            factory("DebindExportLayerTemplate", function(frame, data) frame:Init(data); end);
        else
            factory("DebindExportRowTemplate", function(frame, data) frame:Init(data); end);
        end
    end);

    view:SetElementExtentCalculator(function(_, elementData)
        return elementData.isLayer and LAYER_HEIGHT or ROW_HEIGHT;
    end);

    view:SetElementIndentCalculator(function(elementData)
        return elementData.isLayer and 0 or ROW_INDENT;
    end);

    ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end


--------------------------------------------------------------------------------
-- Building the list
--------------------------------------------------------------------------------

--- One layer's actions, ordered the way the list draws them.
---
--- Ordered by name, **with a key's actions kept together**. Those two pull against each other and
--- both are wanted: the main list settled on name order because a single-layer list has no
--- standing to claim firing order, and this window inherits that; but the group is the thing this
--- window actually sends, so it has to be visible as one block. Ordering the groups by the name
--- of their first action gives a list that reads alphabetically and still has boundaries that
--- mean something.
local function SortLayerActions(actions)
    local groups, byKey = {}, {};

    for i = 1, #actions do
        local action = actions[i];
        local name = strlower(DebindUI.NameAndIconForAction(action) or "");
        local group;

        if (action.key == nil) then
            -- Keyless actions are singletons. In a profile nothing binds two of them together --
            -- whatever group they arrived in dissolved when they were placed.
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

    -- `CompareKeys` breaks the tie so two groups whose first action has the same name do not
    -- swap places between rebuilds. `sort` is not stable.
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

--- What there is to show, before anything is collapsed. Built once per open.
---
--- **Inactive specs are opened too.** The data is already there - class layers sit under
--- `classes[class]` per spec, so a Balance druid can read their Feral layer without switching.
--- A window that only showed the live spec would make the user relog to share half their setup.
---
--- **Every count this window prints comes out of this list** - the layer headers, the [select all]
--- total, which rows can be ticked - so what it collects has to be exactly what would leave. Two
--- things keep that true rather than agreed:
---
---   * `IsExportable`, the same question the payload asks, so a badged action is not listed and not
---     counted. A layer holding nothing else drops out with them, and a profile holding nothing
---     else falls to `EXPORT_EMPTY`.
---   * `EnumerateAllProfileLayers`, which is the walk the payload makes. This used to ask
---     `GetProfileLayer` for 1..11 by hand -- the same eleven layers in the game, and **not** the
---     same under `/debtest`, where a run is isolated to a layer of its own by replacing that
---     enumerator. Two walks over "the eleven layers" is a split waiting for one of them to change.
function DebindExportPanelMixin:BuildLayers()
    local layers = {};

    for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
        local actions, rows = {}, {};
        for _, action in layer:Enumerate() do
            if (Store().IsExportable(action)) then
                actions[#actions + 1] = action;
            end
        end

        local firstInLayer = true;
        for _, group in ipairs(SortLayerActions(actions)) do
            for index, entry in ipairs(group.actions) do
                rows[#rows + 1] = {
                    action = entry.action,
                    layerID = layer.layerID,
                    startsGroup = index == 1,
                    firstInLayer = firstInLayer,
                };
                firstInLayer = false;
            end
        end

        if (#actions > 0) then
            layers[#layers + 1] = { layerID = layer.layerID, actions = actions, rows = rows };
        end
    end

    return layers;
end

--- The rows actually drawn. **Collapsing hides, it does not deselect** - a collapsed layer's
--- actions still export, and still count toward the header and the total. That is why the two
--- lists are separate: everything that asks "what is selected" reads `self.layers`, and only
--- drawing reads this one.
function DebindExportPanelMixin:BuildDisplayList()
    local list = {};

    for _, layer in ipairs(self.layers) do
        list[#list + 1] = { isLayer = true, layerID = layer.layerID, actions = layer.actions };
        if (not self:IsLayerCollapsed(layer.layerID)) then
            for _, row in ipairs(layer.rows) do
                list[#list + 1] = row;
            end
        end
    end

    return list;
end

--- Redraws from the layers already built. Collapsing does not re-read the profile.
function DebindExportPanelMixin:RefreshRows()
    local list = self:BuildDisplayList();
    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(LLL["EXPORT_EMPTY"]);
    self.ScrollBox.EmptyText:SetShown(#list == 0);
    self:UpdateSelectionState();
end

function DebindExportPanelMixin:IsLayerCollapsed(layerID)
    return self.collapsed[layerID] == true;
end

function DebindExportPanelMixin:ToggleLayerCollapsed(layerID)
    self.collapsed[layerID] = not self.collapsed[layerID] or nil;
    self:RefreshRows();
end

--- Every action in the window, collapsed layers included.
function DebindExportPanelMixin:EnumerateListedActions()
    local actions = {};
    for _, layer in ipairs(self.layers or {}) do
        for _, action in ipairs(layer.actions) do
            actions[#actions + 1] = action;
        end
    end
    return actions;
end


--------------------------------------------------------------------------------
-- Selection
--------------------------------------------------------------------------------

--- Redraws the checkboxes without rebuilding the list. Rebuilding would drop the scroll position,
--- and ticking a box is the one gesture where the row you just touched must stay under the cursor.
function DebindExportPanelMixin:UpdateSelectionState()
    self.ScrollBox:ForEachFrame(function(frame)
        if (frame.UpdateSelectionDisplay) then
            frame:UpdateSelectionDisplay();
        end
    end);

    local listed = self:EnumerateListedActions();
    local state, selectedCount = CombineState(listed, self.selected);

    SetTriState(self.SelectAllCheck, state or STATE_NONE);
    self.SelectAllCheck.Text:SetText(selectedCount > 0
        and format(LLL["EXPORT_SELECT_ALL_COUNT"], selectedCount)
        or LLL["EXPORT_SELECT_ALL"]);
    ExtendHitRectOverLabel(self.SelectAllCheck);

    self.GenerateButton:SetEnabled(selectedCount > 0);

end

--- A string already on screen describes a selection that no longer exists, so it goes.
---
--- **Not in `UpdateSelectionState`.** Redrawing runs for collapsing too, and collapsing changes
--- nothing about what would be exported - throwing the string away there would contradict the one
--- rule this window makes about collapsing, in the same file, two functions apart.
local function DropStaleString()
    DebindCopyFrame:Hide();
end

function DebindExportPanelMixin:SelectAll(selected)
    DropStaleString();
    local listed = self:EnumerateListedActions();
    for i = 1, #listed do
        self.selected[listed[i]] = selected or nil;
    end
    self:UpdateSelectionState();
end

function DebindExportPanelMixin:ToggleAction(action)
    DropStaleString();
    self.selected[action] = not self.selected[action] or nil;
    self:UpdateSelectionState();
end

--- A layer toggles as a whole, and "some" counts as off -- one more click gets all of it, which
--- is what the middle state is asking for.
function DebindExportPanelMixin:ToggleLayer(actions)
    DropStaleString();
    local turnOn = CombineState(actions, self.selected) ~= STATE_ALL;
    for i = 1, #actions do
        self.selected[actions[i]] = turnOn or nil;
    end
    self:UpdateSelectionState();
end

function DebindExportPanelMixin:OnSelectAllClicked()
    -- Read the state we drew, not the checkbox's own `GetChecked` -- the middle state is drawn as
    -- checked, so the button's idea of its value says "on" for a partial selection and the click
    -- would clear everything when the user meant to complete it.
    self:SelectAll(CombineState(self:EnumerateListedActions(), self.selected) ~= STATE_ALL);
end


--------------------------------------------------------------------------------
-- The string
--------------------------------------------------------------------------------

function DebindExportPanelMixin:OnGenerateClicked()
    local str, reason = Store().ExportSelection(self.selected);

    if (not str) then
        -- The one failure that can reach here is a missing library, which means a broken install
        -- rather than anything the user did. It is not a string to copy, so it does not go in the
        -- dialog that exists for copying.
        -- **The fallback has to sit outside `L`, not after it.** `L`'s metatable answers a missing
        -- key with the key itself, so `L[...] or ...` can never reach its right-hand side and a
        -- reason nobody wrote a sentence for would print as `EXPORT_FAILED_SOMETHING`. Asking a
        -- plain table first is what `ImportUI.lua` does, for the same reason.
        local key = EXPORT_FAILED_TEXT[reason];
        DebindPrivate.DisplayMessage(key and LLL[key] or tostring(reason), 1, 0, 0);
        return;
    end

    DebindCopyFrame:ShowText(str);
end


--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function DebindExportPanelMixin:OnShow()
    -- **Selected before drawn, not after.** Default is everything ticked - sending the lot should
    -- cost opening the window and reading it - and if the list goes up first, every row that gets
    -- built in the gap draws itself against an empty selection. Redrawing afterwards only reaches
    -- the frames that exist by then, so whatever was built in that gap keeps an empty box while
    -- the header and the count above it say everything is selected.
    self.layers = self:BuildLayers();
    self:SelectAll(true);

    -- **Everything starts shut.** Open, the list is one long run of actions and the layers - the
    -- axis this panel is actually built on - are lost in it. Shut, the first screen is the whole
    -- shape of what is about to be sent, and opening one is how you go look at it.
    for _, layer in ipairs(self.layers) do
        self.collapsed[layer.layerID] = true;
    end
    self:RefreshRows();

    -- **No sound.** There was one here when this was a window that got opened. Switching tabs is
    -- the frame's gesture now, and one tab of three announcing itself is worse than none.
end

function DebindExportPanelMixin:OnHide()
    -- The selection is not kept. It names action tables that can be edited or deleted from the
    -- Overview tab while this one is away, and a stale set of references would quietly export
    -- something else. Rebuilding it costs a walk over the layers, which is what `OnShow` does.
    wipe(self.selected);
    wipe(self.collapsed);
    self.layers = nil;

    -- **Through the pair, because a row's tooltip sets a minimum width.** This line is here for
    -- the case where the row's own `OnLeave` does not run - the panel going away under the cursor
    -- - and that is exactly the case where nothing else would put the width back. A bare `Hide()`
    -- here left every later tooltip in the session 140 wide.
    DebindPrivate.HideActionTooltip(GameTooltip);

    -- **The copy dialog is deliberately left up.** A finished string outlives the tab it came from:
    -- going to Overview to check something should not take away the text you were about to paste.
    -- Coming back drops it, but by the existing rule rather than this one -- `OnShow` rebuilds the
    -- selection, and a string that no longer describes the selection is stale (`DropStaleString`).
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
