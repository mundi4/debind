local _, DebindPrivate      = ...;
local LLL                   = DebindPrivate.L;
local DebindUI              = DebindPrivate.DebindUI;

local dump                  = DebindPrivate.dump

--- The four dropdowns other files open.
local ActionMenu                              = DebindPrivate.ActionMenu;
local ActionMenus                             = ActionMenu.ActionMenus;
local CreateConvertToMacroTextMenuItem        = ActionMenu.CreateConvertToMacroTextMenuItem;
local EditMacroTextMenuItem                   = ActionMenu.EditMacroTextMenuItem;
local CreateSetSwitchMenuItem                 = ActionMenu.CreateSetSwitchMenuItem;
local CreateAssignKeyMenuItem                 = ActionMenu.CreateAssignKeyMenuItem;
local CreateUnbindMenuItem                    = ActionMenu.CreateUnbindMenuItem;
local CreateTargetUnitMenuItem                = ActionMenu.CreateTargetUnitMenuItem;
local CreateCastingMenu                       = ActionMenu.CreateCastingMenu;
local CreateKeepInBindingContextMenuItem      = ActionMenu.CreateKeepInBindingContextMenuItem;
local CreateImportanceMenu                    = ActionMenu.CreateImportanceMenu;
local CreateApproveImportMenuItem             = ActionMenu.CreateApproveImportMenuItem;
local CreateRejectImportMenuItem              = ActionMenu.CreateRejectImportMenuItem;
local CreateMoveCopyMenu                      = ActionMenu.CreateMoveCopyMenu;
local CreateBlockedMenuItem                   = ActionMenu.CreateBlockedMenuItem;
local CreateOrderMenuItems                    = ActionMenu.CreateOrderMenuItems;
local CreateDeleteMenu                        = ActionMenu.CreateDeleteMenu;
local GetTabList                              = ActionMenu.GetTabList;
local SetInstructionTooltip                   = ActionMenu.SetInstructionTooltip;

--------------------------------------------------------------------------------
-- The switches menu that used to hang off the portrait
--------------------------------------------------------------------------------
--- **It is gone, and the tab is where it went** (stage 3c, `devdocs/legacy/redesigning-custom-states.md`
--- §6-B). `SetupSwitchesDropdownMenu` stood here and edited `mode`, `resetValue`, `expr` and
--- `displayMessage` on five offered names, which is the whole of what a row's menu on the
--- `Switches` tab does now, only over however many switches the reader has made, with renaming
--- and deleting beside it and a list that can be scrolled.
---
--- **Two doors saying "switch" is what closed this one.** Making one was here and everything else
--- about one was there, and the button carried no label to point at from the empty list.
---
--- The two things this file kept are the two that belong to an action rather than to a switch:
--- hanging a condition on one (`CreateSwitchConditionMenu`) and saying which one an on/off/toggle
--- action works (`CreateSetSwitchMenuItem`).

--------------------------------------------------------------------------------
-- The options menu that used to hang off the title bar's gear
--------------------------------------------------------------------------------
--- **It is gone, and the window's settings tab is where it went** (`Debind/SettingsTab.lua`).
--- `SetupOptionsDropdownMenu` stood here with the same items.
---
--- Two of the items were things a menu cannot do: the boxes that only take effect at the next
--- login had nowhere but a tooltip to say so, and the throttle was a slider template wedged into a
--- dropdown.

--------------------------------------------------------------------------------
-- The four that are still here
--------------------------------------------------------------------------------

--- The menu a row of either list opens, **over one row or over the rows the reader picked.**
--- `ctx` is `{ actions, layer, otherLayers, inOrderList }`, and a single row is a selection of one
--- (`devdocs/editing-many-actions-at-once.md`).
---
--- **One menu and not two.** The row menu and the selection menu used to be separate, the second
--- holding keys, move, copy, accept, reject and delete on the grounds that a condition means
--- something different on each action. It does not: `[combat]` is the same question on every
--- action it is hung on, and hanging one condition on the several actions a key splits between is
--- what setting a key up in this addon consists of. What really cannot go on many at once is
--- locked where it stands (`OnlyOneReason`, `HowManyAccept`).
---
--- **The picked rows can live in several layers**, since the order list picks across all of them.
--- `ctx.layer` is then the broadest of them and `ctx.otherLayers` counts the rest; "already lives
--- here" only has an answer when that count is nil.
function DebindUI.SetupActionDropdownMenu(dropdown, rootDescription, ctx)
    local actions = ctx.actions;
    local anyArrived = DebindPrivate.AnyArrivedAction(actions);

    -- **One row is named, several are counted.** The count answers "is this the set I meant", which
    -- is asked before any item is read. `NameAndIconForAction` hands back three values, so it is
    -- taken into a local first: passed straight on, the icon lands in `CreateTitle`'s colour slot.
    if (#actions == 1) then
        local title = DebindUI.NameAndIconForAction(actions[1]);
        rootDescription:CreateTitle(title);
    else
        rootDescription:CreateTitle(format(LLL["BULK_MENU_TITLE"], #actions));
    end

    -- **Which layer is being touched.** This menu deletes actions and changes conditions, and
    -- nothing else in it said where those actions live.
    --
    -- **The line is a plain title, and the badge is the only thing that colours it.** The reach
    -- of the layer is not a colour any more: it is a standing property of every action in this
    -- window, so a colour spent on it says the same thing on nearly every menu that opens, and a
    -- mark that is always on marks nothing. Where a shared layer actually costs something is the
    -- one entry that reaches every character on the account, and that entry carries the warning
    -- in words (`IMPORTANCE_SHARED_WARNING`).
    --
    -- The blue is a state and not a property, which is why it keeps the slot. It is on for as
    -- long as the reader has not answered, it comes off the moment they do, and it is the same
    -- blue the row's name and its dot already wear. Passing no colour lands on the client's own
    -- title gold (`MenuUtil.CreateTitle`), which is what the name line above already uses.
    --
    -- **Layers mixed, the broadest is named and the rest counted**, in the `+N` the key group menu's
    -- title uses. A shared layer is always the broadest one present, and reaching it unawares is
    -- what this line is here to prevent.
    if (ctx.layer) then
        local label = DebindUI.GetLayerLabel(ctx.layer);
        if (ctx.otherLayers) then
            label = format("%s %s", label, format(LLL["OVERVIEW_KEY_HEADER_MORE"], ctx.otherLayers));
        end
        rootDescription:CreateTitle(label, anyArrived and DebindUI.IMPORTED_FONT_COLOR or nil);
    end

    rootDescription:SetTag(DebindUI.ActionMenuRootTag, 1);

    -- **Something that arrived is edited like anything else, and its two answers come first.** The
    -- import leaves what came in drawn and editable until the reader takes the badge off
    -- (`DebindStorage/Import.lua`), and accepting is the moment it starts firing, so fitting its
    -- conditions to this character is safer done before than after. The two build themselves out of
    -- the way when nothing picked carries a badge.
    CreateApproveImportMenuItem(rootDescription, actions);
    CreateRejectImportMenuItem(rootDescription, actions);

    -- **First, because on a fresh one it is the only thing worth doing.** The picker adds an
    -- on/off/toggle action with no target (§6-C), so the reader arrives here at a red row that
    -- does nothing, and what fixes it is this box.
    CreateSetSwitchMenuItem(rootDescription, ctx);

    CreateConvertToMacroTextMenuItem(rootDescription, ctx);

    EditMacroTextMenuItem(rootDescription, ctx);

    CreateAssignKeyMenuItem(rootDescription, ctx);

    CreateUnbindMenuItem(rootDescription, ctx);

    CreateOrderMenuItems(rootDescription, ctx);

    CreateTargetUnitMenuItem(rootDescription, ctx);

    CreateCastingMenu(rootDescription, ctx);

    --
    -- Conditions
    --
    rootDescription:CreateDivider();
    rootDescription:CreateTitle(LLL["CONDITIONS"]);

    --- **This list is the order the condition groups are drawn in.** One name is one node; moving
    --- a group is moving its name here. Whether a node stands at all is its own `shown`.
    local conditionNodes = {
        "UNITS", "GROUP", "SELFLIFE", "SPEC", "KNOWN",
        "COMBAT", "SHAPESHIFT", "STEALTH", "ACTIONBAR", "MISC", "SWITCHES",
    };
    for i = 1, #conditionNodes do
        ActionMenus:Build(rootDescription, conditionNodes[i], ctx);
    end

    --
    -- Other Options
    --
    rootDescription:CreateDivider();
    rootDescription:CreateTitle(LLL["OTHER_OPTIONS"]);

    CreateKeepInBindingContextMenuItem(rootDescription, ctx);

    CreateImportanceMenu(rootDescription, ctx);

    -- **One badged action stops move and copy.** What arrived carries the order its sender designed,
    -- and that order lives in `seq` inside one (layer, key, arrival) group - so a move hands out a
    -- fresh number at the back of a different group and the ranking is gone with no sign of it
    -- (`SetKeyForActions`, which exists to keep exactly that). A copy is worse than quiet:
    -- `MoveAction` copies the action whole, badge and all, so what came in once is waiting twice.
    --
    -- **Dead, rather than live and aimed at the rest.** Moving the five that can move and leaving
    -- the two that cannot is a result nobody was told about, and move has no confirmation box to
    -- tell them in. What the block costs instead is one click on a row the list already draws in
    -- blue, and the reason says so.
    --
    -- **Three reasons.** With every picked row waiting there is nothing to take out of the selection,
    -- so the way out is [Accept]; one row somebody right-clicked is not a pick at all.
    local blockedReason;
    if (anyArrived) then
        if (#actions == 1) then
            blockedReason = LLL["MOVE_BLOCKED_IMPORTED"];
        elseif (ActionMenu.AllActions(ctx, function(action) return action.arrivalID ~= nil; end)) then
            blockedReason = LLL["BULK_BLOCKED_ALL_IMPORTED"];
        else
            blockedReason = LLL["BULK_BLOCKED_SOME_IMPORTED"];
        end
    end

    if (blockedReason) then
        CreateBlockedMenuItem(rootDescription, LLL["MOVE_TO"], blockedReason);
        CreateBlockedMenuItem(rootDescription, LLL["COPY_TO"], blockedReason);
    else
        local function Apply(destLayerID, isCopy)
            DebindUI.MoveActions(actions, destLayerID, isCopy);
        end
        local fromLayerID = ctx.otherLayers == nil and ctx.layer or nil;
        CreateMoveCopyMenu(rootDescription, false, fromLayerID, Apply);
        CreateMoveCopyMenu(rootDescription, true, fromLayerID, Apply);
    end

    -- **Delete takes badged rows with the rest.** Nothing is relocated and nothing duplicated, so
    -- neither reason above reaches it; what it does to an arrival is what [Reject] does, and a reader
    -- who picked a dozen rows to be rid of has said which they meant.
    CreateDeleteMenu(rootDescription, ctx);
end

--- Right-clicking a key group's heading in the left column. **One item, and it is the one thing
--- the whole group can be told at once**: which key it goes on.
---
--- Everything else that menu above offers is about a single action -- an order is a place
--- between two rows -- and the heading does not stand for any one of them. The conditions the
--- layer list's menu hangs on several actions at once are left out here too, and so are move,
--- copy and delete: the heading is a **reading** of the column rather than a selection the reader
--- made, so anything written through it lands on rows nobody picked.
---
--- **The title names the set the way the menu above names a row: by what is in it.** The first
--- action's name, then how many follow -- `Charge +1` (`OVERVIEW_KEY_HEADER_MORE`).
--- The key is not repeated into it: the bar the menu opened off is still on screen with the key
--- written on it, and what a title has to answer is which of several near-identical bars was
--- hit -- these rows are 26px and the cursor lands one off more often than it sounds.
---
--- The first action is the first in firing order, so it is both the row directly under the bar
--- and the one the key actually casts. The heading picks it for that reason and so does this.
---
--- **`key` is the target and `action` is only the title's subject.** The list can be rebuilt
--- while this menu stands, so what it holds has to survive that: the key is a value, and the set
--- is collected from it at the moment the item is pressed rather than carried in from here.
--- **`actions` is what the heading is drawn over, and the two halves need it differently.** The
--- key items ignore it and ask the profile again on the press; the import items have to decide
--- **whether to stand up at all** while the menu is being built, so they read it. That is a
--- snapshot, and the right one: what the reader is looking at.
---
--- **No delete.** A heading is a reading of the column rather than something the reader picked,
--- so a delete here takes rows nobody selected - which is the same line the edit menu's other
--- items are kept out on (`reworking-the-overview.md`).
function DebindUI.SetupKeyGroupDropdownMenu(dropdown, rootDescription, key, action, extraCount, actions, arrivalID)
    if (key ~= nil) then
        -- 로컬에 한 번 받는 이유는 위 메뉴와 같다 - 셋을 돌려주므로 그대로 넘기면 아이콘이
        -- `CreateTitle`의 **색** 자리로 들어간다.
        local title = DebindUI.NameAndIconForAction(action);
        -- 하나뿐이면 개수를 안 쓴다. 머리글이 `+0`을 안 쓰는 것과 같은 이유로, 셀 것이 없다는
        -- 말을 굳이 하는 자리다.
        if (extraCount and extraCount > 0) then
            title = format("%s %s", title, format(LLL["OVERVIEW_KEY_HEADER_MORE"], extraCount));
        end
        -- **A heading over an arrival wears the arrival's blue**, the same as the row's menu
        -- title and for the same reason: the three items under it are a different three, and
        -- the colour is what says which kind of heading this is before they are read.
        rootDescription:CreateTitle(title, arrivalID and DebindUI.IMPORTED_FONT_COLOR or nil);

        -- **The same three words as the row's item** (`ACTION_SET_KEY`), and a key of its own all
        -- the same. What differs is how much of the column each one reaches, and neither label
        -- says so - a label saying it would set this menu's width. The tooltips are where the two
        -- part, and one string stretched across both positions would fit neither
        -- (`devdocs/writing-user-facing-text.md`).
        --
        -- **The set is collected on the press, not when the menu is built.** That is the only
        -- moment the answer is worth anything: the menu may have stood open through a rebuild,
        -- and this walk reaches every layer of the character rather than what the column happens
        -- to be drawing.
        local function CreateAssignKeyItem()
            local description = rootDescription:CreateButton(
                LLL[arrivalID and "ACTION_SET_KEY_ACCEPT" or "KEY_HEADER_SET_KEY"],
                function()
                    DebindUI.BeginKeyCapture(DebindPrivate.CollectKeyGroupActions(key, arrivalID));
                end);
            SetInstructionTooltip(description,
                LLL[arrivalID and "KEY_HEADER_SET_KEY_ACCEPT_DESC" or "KEY_HEADER_SET_KEY_DESC"]);
        end

        -- **A heading over an arrival gets the row's three, in the row's order** (2026-08-23,
        -- 소유자). The reader pointing at a heading and pointing at a row of it are asking about
        -- different amounts, not about different things, so the answers on offer have to be the
        -- same ones in the same order or the two menus teach two models of one feature.
        --
        -- **[Unbind] is not among them.** Giving the set a key accepts it and so does taking the
        -- key off inside that window (`DebindUI.BeginKeyCapture`); an item that only scatters
        -- the set and leaves it waiting is the one answer this heading has no use for.
        if (arrivalID) then
            CreateApproveImportMenuItem(rootDescription, actions);
            CreateAssignKeyItem();
            CreateRejectImportMenuItem(rootDescription, actions);
            return;
        end

        -- **One item, and taking the key off is not a second one** (2026-08-23, 소유자). It stood
        -- here as the other end of the same axis, and the window this item opens has that end on
        -- it: [Unbind Key] is a button on the capture dialog, over the same set, asking the same
        -- question. A menu item beside it was the one door in this window that could scatter a
        -- set without the reader having gone to decide its key.
        CreateAssignKeyItem();
    else
        -- **The pile at the bottom, and only when something in it arrived.** Its heading names a
        -- state rather than a key, so neither key item belongs: giving them all one key would
        -- invent a set the reader never made, and there is nothing to unbind. Accepting does
        -- neither - taking twelve is twelve separate answers and leaves no new relationship - so
        -- it is the one pair that can stand here.
        rootDescription:CreateTitle(LLL["OVERVIEW_NO_KEY"]);
    end

    -- **Only where the reader can see them.** A key group is collected past the screen, but these
    -- are the rows drawn under this heading - and the pile is narrowed row by row, so a badge
    -- filtered out of the column is not something a menu opened on it may touch.
    --
    -- **Only the keyless pile reaches this now.** A heading over an arrival answers above, with
    -- the same three the row's menu offers; here the heading names a state rather than a key, so
    -- what is under it is any number of unrelated arrivals and the count is the only thing that
    -- says how many the press would take.
    if (DebindPrivate.AnyArrivedAction(actions)) then
        CreateApproveImportMenuItem(rootDescription, actions, true);
        CreateRejectImportMenuItem(rootDescription, actions, true);
    end
end

--- The row above the two columns, on either mouse button. **Two items, and they are the two
--- buttons that used to stand there** (`DebindFrameMixin:ShowPendingImportsDropdown`).
---
--- **The counts came off the two labels** (2026-08-19, 소유자). They read "Accept all %d" while
--- they were buttons on that row, where the number stood in for the confirmation box [Accept all]
--- does not get. The button this menu opens off carries it now, reads the same
--- `CollectArrivedActions`, and stays on screen for as long as the menu does - so the number is
--- one widget away rather than gone, and there is no second place keeping it in step.
---
--- **The two `_DESC` strings are hung as tooltips rather than dropped.** They were written for
--- exactly this scope - everything still waiting, wherever it went - which is what stops them
--- being the row-scoped `ORDER_ACCEPT_DESC` / `REJECT_IMPORT_DESC` the menus above borrow. The
--- items keep them because "wherever it went" is the one fact the reader cannot see from here.
---
--- **Neither item is conditional.** Every other import item in this file builds itself out of
--- the way when nothing it aims at carries a badge; these do not need to, because the button
--- that opens this menu is itself hidden at zero (`UpdatePendingImports`).
function DebindUI.SetupPendingImportsDropdownMenu(dropdown, rootDescription)
    local description = rootDescription:CreateButton(LLL["APPROVE_ALL_IMPORT"], function()
        DebindFrame:ApproveAllImported();
    end);
    SetInstructionTooltip(description, LLL["APPROVE_ALL_IMPORT_DESC"]);

    description = rootDescription:CreateButton(LLL["REJECT_ALL_IMPORT"], function()
        DebindFrame:RejectAllImported();
    end);
    SetInstructionTooltip(description, LLL["REJECT_ALL_IMPORT_DESC"]);
end

--- Right-clicking a row of the spell picker. **The whole menu is the destination list** -
--- there is nothing else to ask about an entry that is not an action yet.
---
--- Left click still adds to the open tab, so this menu is the shortcut, not the only way:
--- filling one tab is a click each, and the one action that belongs somewhere else no longer
--- costs a trip to the main window and back.
---
--- The destination list is `GetTabList`'s - the same one move and copy show. The tab you are
--- looking at stays in it and stays enabled; adding there is exactly what left click does, and
--- dropping the row would make the list a different shape in this menu than in the other two.
function DebindUI.SetupSpellPickerDropdownMenu(dropdown, rootDescription, entry)
    rootDescription:CreateTitle(entry.name);
    rootDescription:CreateTitle(LLL["SPELL_PICKER_ADD_TO"]);

    local currentLayerID = DebindUI.GetLayerID();

    local func = function(args)
        DebindFrame:AddNewAction(entry.type, entry.value, nil, nil, entry.props, args[1]);
    end

    for _, tabInfo in ipairs(GetTabList()) do
        rootDescription:CreateButton(
            tabInfo.layerID == currentLayerID and format(LLL["CURRENT_TAB_SUFFIX"], tabInfo.label) or tabInfo.label,
            func,
            { tabInfo.layerID }
        );
    end
end
