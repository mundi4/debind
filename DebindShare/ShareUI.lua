local _, DebindShare = ...;

local DebindPrivate    = DebindShare.DebindPrivate;
local LLL              = DebindPrivate.L;
local DebindUI         = DebindPrivate.DebindUI;

--- The export window.
---
--- One list, three rungs: everything -> layer -> action. Everything starts selected, because the
--- common case is "send all of it" and that should cost a glance and a button.
---
--- **Only the first two rungs are checkboxes.** An action is shown picked by lighting its row, the
--- way the main window shows a selected row. Boxes all the way down made three columns of them and
--- left no way to tell a layer's box from an action's at a glance.
---
--- **The axis is the layer, and the window has to say so.** A key's behaviour is computed across
--- layers, so what this window can honestly promise is *the contents of these layers* -- if the
--- receiving side arranges its layers one notch differently, the same actions on the same keys
--- behave differently with nothing missing and nothing overwritten. `.zzz/export-import.md`.
---
--- Nothing here validates. A broken action exports as it sits; the far side shows it in red and
--- the user deletes it. That single rule is what removes every question about spells, macros and
--- specs the reader might not have. Where red text cannot in fact see the breakage, `Export.lua`
--- carries the answer in the format instead.

--- Draw order: `MEDIUM` + toplevel, the same as the main window and the spell picker, so whichever
--- was clicked last comes forward and the HIGH popups stay above all three.
local ROW_HEIGHT       = 28;
local LAYER_HEIGHT     = 26;


--------------------------------------------------------------------------------
-- Tri-state
--
-- **No new art was needed, which is what open question 6 in `.zzz/export-import.md` was about.**
-- The addon list solves the same problem (`AddonList.lua`'s `TriStateCheckbox_SetState`) by dimming
-- its check, and everything below is built out of stock atlases the same way.
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

--- What a set of actions adds up to. `nil` for an empty set -- callers decide whether that reads
--- as "none" (a layer with nothing in it) or as nothing at all.
local function CombineState(actions, selected)
    local anySelected, anyUnselected;
    for i = 1, #actions do
        if (selected[actions[i]]) then
            anySelected = true;
        else
            anyUnselected = true;
        end
    end

    if (not anySelected and not anyUnselected) then
        return nil;
    elseif (anySelected and anyUnselected) then
        return STATE_SOME;
    elseif (anySelected) then
        return STATE_ALL;
    end
    return STATE_NONE;
end


--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

DebindShareRowMixin = {};

function DebindShareRowMixin:Init(elementData)
    self.elementData = elementData;

    local action = elementData.action;
    local name, icon = DebindUI.NameAndIconForAction(action);

    self.Name:SetText(name or "");
    DebindUI.SetActionIcon(self.Icon, icon);
    self.Key:SetText(action.key and GetBindingText(action.key) or "");

    -- The line marks where one key's group ends and the next begins. The first row under a layer
    -- gets none: the layer's own divider is already the line there, and two rules on top of each
    -- other read as a heavier rule, not as two boundaries.
    self.GroupBorder:SetShown(elementData.startsGroup and not elementData.firstInLayer);

    self:UpdateSelectionDisplay();
end

function DebindShareRowMixin:UpdateSelectionDisplay()
    self.SelectedHighlight:SetShown(DebindShareFrame.selected[self.elementData.action] == true);
end

function DebindShareRowMixin:OnClick()
    DebindShareFrame:ToggleAction(self.elementData.action);
    self:UpdateSelectionDisplay();
end

function DebindShareRowMixin:OnEnter()
    local action = self.elementData.action;
    local name = DebindUI.NameAndIconForAction(action);

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, name or "");
    if (action.key) then
        GameTooltip_AddHighlightLine(GameTooltip, GetBindingText(action.key));
    else
        GameTooltip_AddNormalLine(GameTooltip, LLL["EXPORT_ROW_NO_KEY"]);
    end
    GameTooltip:Show();
end

function DebindShareRowMixin:OnLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- Layers
--------------------------------------------------------------------------------

--- A layer header: the game's own collapsible list header (`ListHeaderVisualTemplate`, what the
--- quest log uses), with a tri-state checkbox added on the left.
---
--- The bar carries **two** gestures and they are split by area: the checkbox selects the layer,
--- everything else collapses it, and the `+`/`-` on the right says which way it currently sits.
DebindShareLayerMixin = {};

function DebindShareLayerMixin:OnLoad()
    -- Clear of the checkbox. `ListHeaderVisualMixin` owns the text's anchor and hands out this
    -- call for moving it, so the offset lives here instead of a second anchor in the XML.
    self:AdjustTextOffset(22, 0);

    NormalizeCheckMark(self.Check);

    self.Check:SetScript("OnClick", function()
        DebindShareFrame:ToggleLayer(self.elementData.actions);
        self:UpdateSelectionDisplay();
    end);
end

function DebindShareLayerMixin:Init(elementData)
    self.elementData = elementData;
    self:SetHeaderText(DebindUI.GetLayerLabel(elementData.layerID));
    self:GetCollapseButton():UpdateCollapsedState(DebindShareFrame:IsLayerCollapsed(elementData.layerID));
    self:UpdateSelectionDisplay();
end

function DebindShareLayerMixin:UpdateSelectionDisplay()
    SetTriState(self.Check, CombineState(self.elementData.actions, DebindShareFrame.selected)
        or STATE_NONE);
end

--- The bar collapses. Selecting is the checkbox's job and it swallows its own clicks, so a click
--- arriving here is always about showing and hiding.
function DebindShareLayerMixin:OnClick()
    DebindShareFrame:ToggleLayerCollapsed(self.elementData.layerID);
end

function DebindShareLayerMixin:OnEnter()
    self:CheckHighlightTitle(true);

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, DebindUI.GetLayerLabel(self.elementData.layerID));
    GameTooltip_AddNormalLine(GameTooltip,
        format(LLL["EXPORT_LAYER_COUNT"], #self.elementData.actions));
    GameTooltip:Show();
end

function DebindShareLayerMixin:OnLeave()
    self:CheckHighlightTitle(false);
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

DebindShareFrameMixin = {};

function DebindShareFrameMixin:OnLoad()
    self:SetTitle(LLL["EXPORT_TITLE"]);
    self:SetPortraitToAsset(133015);

    self.SelectAllCheck.Text:SetText(LLL["EXPORT_SELECT_ALL"]);
    self.StripKeysCheck.Text:SetText(LLL["EXPORT_STRIP_KEYS"]);
    self.GenerateButton:SetText(LLL["EXPORT_GENERATE"]);

    --- Which actions go. Keyed by the action table itself, so it survives the list being rebuilt
    --- and never has to be reconciled with an index.
    self.selected = {};

    --- Which layer headers are shut, by layerID. A view state and nothing else: a collapsed layer
    --- still exports.
    self.collapsed = {};

    self:InitializeScrollBox();

    -- **This window does not hang off the main one.** It is opened from there but outlives it, so
    -- ESC has to be its own business. `UISpecialFrames` is how a standalone window says that, and
    -- it costs nothing: registration only, no keyboard capture, nothing of Blizzard's changed.
    tinsert(UISpecialFrames, self:GetName());

    -- **The chrome widgets get their scripts here.** XML's `method=` looks the name up on the
    -- element's *own* mixin, so naming the frame's method on a plain Blizzard template finds
    -- nothing. List rows are the other way round: those carry a mixin, so `method=` is right there.
    self.SelectAllCheck:SetScript("OnClick", function() self:OnSelectAllClicked(); end);
    self.StripKeysCheck:SetScript("OnClick", function() self:OnStripKeysClicked(); end);
    self.StripKeysCheck:SetScript("OnEnter", function() self:OnStripKeysEnter(); end);
    self.StripKeysCheck:SetScript("OnLeave", function() self:OnStripKeysLeave(); end);
    self.GenerateButton:SetScript("OnClick", function() self:OnGenerateClicked(); end);

    NormalizeCheckMark(self.SelectAllCheck);
    NormalizeCheckMark(self.StripKeysCheck);
    ExtendHitRectOverLabel(self.StripKeysCheck);

    self:RegisterForDrag("LeftButton");
    self:SetScript("OnDragStart", function() self:StartMoving(); end);
    self:SetScript("OnDragStop", function()
        self:StopMovingOrSizing();
        self:SetUserPlaced(false);
    end);
end

function DebindShareFrameMixin:InitializeScrollBox()
    local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);

    view:SetElementFactory(function(factory, elementData)
        if (elementData.isLayer) then
            factory("DebindShareLayerTemplate", function(frame, data) frame:Init(data); end);
        else
            factory("DebindShareRowTemplate", function(frame, data) frame:Init(data); end);
        end
    end);

    view:SetElementExtentCalculator(function(_, elementData)
        return elementData.isLayer and LAYER_HEIGHT or ROW_HEIGHT;
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
function DebindShareFrameMixin:BuildLayers()
    local layers = {};

    for layerID = 1, 11 do
        local layer = DebindPrivate.GetProfileLayer(layerID);
        if (layer and layer:GetNumActions() > 0) then
            local actions, rows = {}, {};
            for _, action in layer:Enumerate() do
                actions[#actions + 1] = action;
            end

            local firstInLayer = true;
            for _, group in ipairs(SortLayerActions(actions)) do
                for index, entry in ipairs(group.actions) do
                    rows[#rows + 1] = {
                        action = entry.action,
                        layerID = layerID,
                        startsGroup = index == 1,
                        firstInLayer = firstInLayer,
                    };
                    firstInLayer = false;
                end
            end

            layers[#layers + 1] = { layerID = layerID, actions = actions, rows = rows };
        end
    end

    return layers;
end

--- The rows actually drawn. **Collapsing hides, it does not deselect** - a collapsed layer's
--- actions still export, and still count toward the header and the total. That is why the two
--- lists are separate: everything that asks "what is selected" reads `self.layers`, and only
--- drawing reads this one.
function DebindShareFrameMixin:BuildDisplayList()
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
function DebindShareFrameMixin:RefreshRows()
    local list = self:BuildDisplayList();
    self.ScrollBox:SetDataProvider(CreateDataProvider(list), true);
    self.ScrollBox.EmptyText:SetText(LLL["EXPORT_EMPTY"]);
    self.ScrollBox.EmptyText:SetShown(#list == 0);
    self:UpdateSelectionState();
end

function DebindShareFrameMixin:IsLayerCollapsed(layerID)
    return self.collapsed[layerID] == true;
end

function DebindShareFrameMixin:ToggleLayerCollapsed(layerID)
    self.collapsed[layerID] = not self.collapsed[layerID] or nil;
    self:RefreshRows();
end

--- Every action in the window, collapsed layers included.
function DebindShareFrameMixin:EnumerateListedActions()
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
function DebindShareFrameMixin:UpdateSelectionState()
    self.ScrollBox:ForEachFrame(function(frame)
        if (frame.UpdateSelectionDisplay) then
            frame:UpdateSelectionDisplay();
        end
    end);

    local listed = self:EnumerateListedActions();
    local selectedCount = 0;
    for i = 1, #listed do
        if (self.selected[listed[i]]) then
            selectedCount = selectedCount + 1;
        end
    end

    SetTriState(self.SelectAllCheck, CombineState(listed, self.selected) or STATE_NONE);
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
    DebindShareCopyFrame:Hide();
end

function DebindShareFrameMixin:SelectAll(selected)
    DropStaleString();
    local listed = self:EnumerateListedActions();
    for i = 1, #listed do
        self.selected[listed[i]] = selected or nil;
    end
    self:UpdateSelectionState();
end

function DebindShareFrameMixin:ToggleAction(action)
    DropStaleString();
    self.selected[action] = not self.selected[action] or nil;
    self:UpdateSelectionState();
end

--- A layer toggles as a whole, and "some" counts as off -- one more click gets all of it, which
--- is what the middle state is asking for.
function DebindShareFrameMixin:ToggleLayer(actions)
    DropStaleString();
    local turnOn = CombineState(actions, self.selected) ~= STATE_ALL;
    for i = 1, #actions do
        self.selected[actions[i]] = turnOn or nil;
    end
    self:UpdateSelectionState();
end

function DebindShareFrameMixin:OnSelectAllClicked()
    -- Read the state we drew, not the checkbox's own `GetChecked` -- the middle state is drawn as
    -- checked, so the button's idea of its value says "on" for a partial selection and the click
    -- would clear everything when the user meant to complete it.
    self:SelectAll(CombineState(self:EnumerateListedActions(), self.selected) ~= STATE_ALL);
end

--- Toggling this changes what the string would contain, so a string already on screen stops being
--- the one this window would produce.
function DebindShareFrameMixin:OnStripKeysClicked()
    DropStaleString();
end

function DebindShareFrameMixin:OnStripKeysEnter()
    GameTooltip:SetOwner(self.StripKeysCheck, "ANCHOR_RIGHT");
    GameTooltip_SetTitle(GameTooltip, LLL["EXPORT_STRIP_KEYS"]);
    GameTooltip_AddNormalLine(GameTooltip, LLL["EXPORT_STRIP_KEYS_DESC"]);
    GameTooltip:Show();
end

function DebindShareFrameMixin:OnStripKeysLeave()
    GameTooltip:Hide();
end


--------------------------------------------------------------------------------
-- The string
--------------------------------------------------------------------------------

function DebindShareFrameMixin:OnGenerateClicked()
    local str, reason = DebindShare.ExportSelection(self.selected, {
        stripKeys = self.StripKeysCheck:GetChecked(),
    });

    if (not str) then
        -- The one failure that can reach here is a missing library, which means a broken install
        -- rather than anything the user did. It is not a string to copy, so it does not go in the
        -- dialog that exists for copying.
        DebindPrivate.DisplayMessage(LLL["EXPORT_FAILED_" .. tostring(reason)] or tostring(reason),
            1, 0, 0);
        return;
    end

    DebindShareCopyFrame:ShowText(str);
end


--------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------

function DebindShareFrameMixin:OnShow()
    -- **Selected before drawn, not after.** Default is everything ticked - sending the lot should
    -- cost opening the window and reading it - and if the list goes up first, every row that gets
    -- built in the gap draws itself against an empty selection. Redrawing afterwards only reaches
    -- the frames that exist by then, so whatever was built in that gap keeps an empty box while
    -- the header and the count above it say everything is selected.
    self.layers = self:BuildLayers();
    self:SelectAll(true);

    -- **Everything starts shut.** Open, the list is one long run of actions and the layers - the
    -- axis this window is actually built on - are lost in it. Shut, the first screen is the whole
    -- shape of what is about to be sent, and opening one is how you go look at it.
    for _, layer in ipairs(self.layers) do
        self.collapsed[layer.layerID] = true;
    end
    self:RefreshRows();

    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
end

function DebindShareFrameMixin:OnHide()
    -- The selection is not kept. It describes actions that can be edited or deleted while this is
    -- closed, and a stale set of table references would quietly export something else.
    wipe(self.selected);
    wipe(self.collapsed);
    self.layers = nil;
    DebindShareCopyFrame:Hide();
    GameTooltip:Hide();
end

function DebindShareFrameMixin:Toggle()
    self:SetShown(not self:IsShown());
end


--------------------------------------------------------------------------------
-- The copy dialog
--------------------------------------------------------------------------------

DebindShareCopyFrameMixin = {};

function DebindShareCopyFrameMixin:OnLoad()
    self.TitleText:SetText(LLL["EXPORT_COPY_TITLE"]);

    self:RegisterForDrag("LeftButton");
    self:SetScript("OnDragStart", self.StartMoving);
    self:SetScript("OnDragStop", self.StopMovingOrSizing);

    local editBox = self.Output.EditBox;
    editBox:SetFontObject(ChatFontNormal);

    -- Nobody types here. An edited string is a broken string, and the break would only show up on
    -- whoever it was pasted to.
    editBox:SetScript("OnChar", function() editBox:SetText(self.text or ""); end);
    editBox:SetScript("OnEscapePressed", function()
        editBox:ClearFocus();
        self:Hide();
    end);

    tinsert(UISpecialFrames, self:GetName());
end

--- Puts the string up, selected, with the cursor already in it: the whole dialog exists so that
--- Ctrl-C is the only thing left to do.
function DebindShareCopyFrameMixin:ShowText(text)
    self.text = text;
    self.Output.EditBox:SetText(text);
    self:Show();
    self.Output.EditBox:SetFocus();
    self.Output.EditBox:HighlightText();
end
