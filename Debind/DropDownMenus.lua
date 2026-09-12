local _, DebindPrivate      = ...;
local LLL                   = DebindPrivate.L;
local DebindUI              = DebindPrivate.DebindUI;

local dump                  = DebindPrivate.dump

--- The six dropdowns other files open.
local ActionMenu                              = DebindPrivate.ActionMenu;
local ActionMenus                             = ActionMenu.ActionMenus;
local CreateSmartCastMenuItem                 = ActionMenu.CreateSmartCastMenuItem;
local CreateConvertToMacroTextMenuItem        = ActionMenu.CreateConvertToMacroTextMenuItem;
local EditMacroTextMenuItem                   = ActionMenu.EditMacroTextMenuItem;
local CreateSetSwitchMenuItem                 = ActionMenu.CreateSetSwitchMenuItem;
local CreateAssignKeyMenuItem                 = ActionMenu.CreateAssignKeyMenuItem;
local CreateUnbindMenuItem                    = ActionMenu.CreateUnbindMenuItem;
local CreateTargetUnitMenuItem                = ActionMenu.CreateTargetUnitMenuItem;
local CreateKeepInBindingContextMenuItem      = ActionMenu.CreateKeepInBindingContextMenuItem;
local CreateImportanceMenu                    = ActionMenu.CreateImportanceMenu;
local CreateApproveImportMenuItem             = ActionMenu.CreateApproveImportMenuItem;
local CreateRejectImportMenuItem              = ActionMenu.CreateRejectImportMenuItem;
local CreateMoveCopyMenu                      = ActionMenu.CreateMoveCopyMenu;
local CreateBlockedMenuItem                   = ActionMenu.CreateBlockedMenuItem;
local CreateDeleteMenu                        = ActionMenu.CreateDeleteMenu;
local GetTabList                              = ActionMenu.GetTabList;
local SetInstructionTooltip                   = ActionMenu.SetInstructionTooltip;
local SetErrorTooltip                         = ActionMenu.SetErrorTooltip;

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
--- **It is gone, and the game's own settings window is where it went**
--- (`Debind/Options.lua`, `devdocs/legacy/moving-global-options-to-the-settings-panel.md`).
--- `SetupOptionsDropdownMenu` stood here with the same items in the same order.
---
--- What closed it is that everything in it is an **account** setting, so it was never about the
--- window it hung on -- and two of the items were things a menu cannot do: the boxes that only
--- take effect at the next login had nowhere but a tooltip to say so, and the throttle was a
--- slider template wedged into a dropdown. The settings window has a place for both, and brings
--- search and a Defaults button that this menu never had.

--------------------------------------------------------------------------------
-- The six that are still here
--------------------------------------------------------------------------------

function DebindUI.SetupEditDropdownMenu(dropdown, rootDescription, elementData)
    local ctx = { elementData = elementData, action = elementData.action };

    -- GenerateMenu(dropdown, rootDescription, rootMenu, elementData.action);
    -- if true then
    --     return;
    -- end

    local title = DebindUI.NameAndIconForAction(elementData.action);
    rootDescription:CreateTitle(title);

    -- **Which layer's action is being touched.** This menu deletes actions and changes
    -- conditions, and nothing else in it said where that action lives.
    --
    -- It used to need no asking. The menu opened in one list only, and that list was always a
    -- single layer, so the answer stood in the window's title. Neither holds now - **the
    -- overview tab holds five layers in one list.**
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
    -- The words stay bare. An icon and "all characters" were once hung here together, and one
    -- title line carrying a picture, a position and a consequence read as none of the three.
    if (elementData.layer) then
        local color;
        if (ctx.action.arrivalID) then
            color = DebindUI.IMPORTED_FONT_COLOR;
        end
        rootDescription:CreateTitle(DebindUI.GetLayerLabel(elementData.layer), color);
    end

    rootDescription:SetTag(DebindUI.ActionMenuRootTag, 1);

    -- **A badged action gets a key, accept and reject, and nothing else.** The badge keeps it out
    -- of the build (`BuildKeyMap`), so every other entry below sets a property on something that
    -- does not fire - a condition, a target, a priority, all settled before the one question this
    -- row is actually waiting on.
    --
    -- **Move and copy are the two that do harm rather than nothing.** `MoveAction` copies the
    -- action whole and the badge rides along, so copying makes a second thing to accept and
    -- moving files one away in a layer the reader was not looking at.
    --
    -- Delete goes because reject is this row's delete and says the truer thing - what arrived is
    -- still in the drawer, which is what makes it the reversible half (`CreateRejectImportMenuItem`).
    --
    -- **The key stands above the pair because it is the third answer to their question.** Naming
    -- the key is the reader saying yes and the badge comes off with it (`SetActionKey`), so the
    -- three items are: take it and put it somewhere, take it where it lies, throw it back.
    --
    -- [Accept] keeps its place under it rather than being made redundant. What it leaves behind
    -- is the action live on the key it came in on, which is what the reader is saying yes to
    -- (`ApproveArrivedActions`). It used to leave it parked on a number the build skipped; the
    -- number is gone and so is that half-state.
    --
    -- **It also takes this row out of the set it arrived in**, and that is why the left column's
    -- row menu does not carry it: over there the set is drawn as a group with a heading, and the
    -- heading is where its key belongs (`DebindUI.SetupOrderDropdownMenu`).
    if (ctx.action.arrivalID) then
        CreateAssignKeyMenuItem(rootDescription, ctx);
        CreateApproveImportMenuItem(rootDescription, { ctx.action });
        CreateRejectImportMenuItem(rootDescription, { ctx.action });
        return;
    end

    -- **First, because on a fresh one it is the only thing worth doing.** The picker adds an
    -- on/off/toggle action with no target (§6-C), so the reader arrives here at a red row that
    -- does nothing, and what fixes it is this box.
    CreateSetSwitchMenuItem(rootDescription, ctx);

    CreateConvertToMacroTextMenuItem(rootDescription, ctx);

    EditMacroTextMenuItem(rootDescription, ctx);

    CreateAssignKeyMenuItem(rootDescription, ctx);

    CreateUnbindMenuItem(rootDescription, ctx);

    CreateTargetUnitMenuItem(rootDescription, ctx);

    CreateSmartCastMenuItem(rootDescription, ctx);

    --
    -- Conditions
    --
    rootDescription:CreateDivider();
    rootDescription:CreateTitle(LLL["CONDITIONS"]);

    --- **This list is the order the condition groups are drawn in.** One name is one node; moving
    --- a group is moving its name here. Whether a node stands at all is its own `shown`.
    local conditionNodes = {
        "HOVER", "UNITS", "GROUP", "SELFLIFE", "SPEC", "KNOWN",
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

    CreateMoveCopyMenu(rootDescription, false, ctx.elementData.layer, function(destLayerID, isCopy)
        DebindUI.MoveAction(ctx.elementData, destLayerID, isCopy);
    end);

    CreateMoveCopyMenu(rootDescription, true, ctx.elementData.layer, function(destLayerID, isCopy)
        DebindUI.MoveAction(ctx.elementData, destLayerID, isCopy);
    end);

    CreateDeleteMenu(rootDescription, ctx);
end

--- 오버뷰 목록(`DebindOrderLineMixin`)의 행에서 우클릭으로 여는 메뉴. **순서 두 항목뿐이다.**
---
--- 화살표 버튼과 **같은 판정·같은 문자열**을 쓴다. 순서 규칙을 말하는 문장이 이 애드온에
--- 두 군데 생기면 하나가 낡는데, 낡은 쪽이 거짓말을 해도 잡아줄 검사가 없다.
---
--- 못 누르는 항목도 **세워 둔다.** 회색으로 서 있는 두 줄이 "여기서 순서를 만질 수 있다"를
--- 말하고, 지금 안 되는 이유는 그 툴팁이 댄다 - 빼버리면 메뉴가 통째로 비어서 우클릭이
--- 고장 난 것처럼 보인다.
---
--- 대상은 액션 하나다. 행이 아니라 액션으로 받는 이유는 `ComputeOrderSwapForAction`
--- 주석에 - 요약하면 메뉴가 떠 있는 동안 목록이 낡을 수 있어서다.
function DebindUI.SetupOrderDropdownMenu(dropdown, rootDescription, action)
    -- 어느 행에서 열었는지. 28px 한 줄짜리 목록이라 커서가 한 칸 어긋난 채로 여는 일이
    -- 실제로 있고, 그때 이 제목이 아니면 잘못 옮긴 것을 옮기고 나서야 안다.
    --
    -- **로컬에 한 번 받는다.** `NameAndIconForAction`은 셋을 돌려주는데(이름·아이콘·본디
    -- 이름), 그대로 넘기면 아이콘 파일 ID가 `CreateTitle`의 두 번째 인자인 **색** 자리로
    -- 들어가서 메뉴가 열리는 순간 터진다(`MenuUtil.lua`의 `useColor`).
    --
    -- **The blue an arrival wears follows it into the menu** (2026-08-23, 소유자). The row's
    -- name and its dot are already that colour (`DebindUI.IMPORTED_FONT_COLOR`), and this menu
    -- offers a different three items on a row that has one - so the title saying which kind of
    -- row it opened over is the same answer as why the items are what they are. Passing no
    -- colour lands on the client's title gold, which is what every other row gets.
    local title = DebindUI.NameAndIconForAction(action);
    rootDescription:CreateTitle(title, action.arrivalID and DebindUI.IMPORTED_FONT_COLOR or nil);

    local function CreateMoveMenuItem(direction, titleKey, descKey)
        local description = rootDescription:CreateButton(LLL[titleKey], function()
            -- **행이 아니라 그 안의 액션을 넘긴다.** `CollectActionsForKey`가 짓는 행에는
            -- `seq` **사본**이 실려 있어서(Profile.lua), 행째로 주면 맞바꾸는 것이 사본
            -- 둘이 된다 - 터지지도 않고 프로필도 그대로인 채 소리만 난다.
            local neighborRow = DebindPrivate.ComputeOrderSwapForAction(action, direction);
            DebindUI.ApplyOrderSwap(action, neighborRow and neighborRow.action);
        end);

        -- 여는 시점의 답으로 켜고 끈다. 누를 때 다시 묻는 값과 어긋날 수 있는 자리지만,
        -- 그때는 맞바꿀 이웃이 nil이라 `ApplyOrderSwap`이 물러난다.
        local neighbor, reason = DebindPrivate.ComputeOrderSwapForAction(action, direction);
        description:SetEnabled(neighbor ~= nil);

        if (neighbor) then
            SetInstructionTooltip(description, LLL[descKey]);
        else
            SetErrorTooltip(description, LLL["ORDER_BLOCKED_" .. reason]);
        end
    end

    --- **This row and nothing else** (`DebindUI.BeginKeyCapture`). The whole set is the
    --- heading's operation and the heading is where it now lives
    --- (`DebindUI.SetupKeyGroupDropdownMenu`) - one menu per thing the reader pointed at, and
    --- what is pointed at here is a line.
    ---
    --- It used to be the set's item, standing in this menu because the heading took no clicks at
    --- all. That is no longer true of the heading, and leaving the set's operation on a row left
    --- the two menus offering the same thing while the reader had pointed at different things.
    ---
    --- **Splitting the set is the thing this can do that the reader will not see coming**, so
    --- the tooltip is where the warning went (`ACTION_SET_KEY_DESC`). It is a real operation and
    --- not a mistake - one action of four moving to its own key is how a condition gets its own
    --- shortcut - but a key's actions are told apart by conditions, so a set coming apart looks
    --- like nothing at all until both halves fire.
    --- **On something that arrived, the label says the other half** (2026-08-23, 소유자). Giving
    --- an arrival a key accepts it (`DebindFrameMixin:SetActionKey`), and until the label said
    --- so the reader pressed this expecting the key to move and nothing else. The three words
    --- are still the act's name, so the item stays the same item wherever it is offered; the
    --- clause is only true here.
    local function CreateAssignKeyItem()
        local arrived = action.arrivalID ~= nil;
        local description = rootDescription:CreateButton(
            LLL[arrived and "ACTION_SET_KEY_ACCEPT" or "ACTION_SET_KEY"], function()
                DebindUI.BeginKeyCapture({ action });
            end);
        SetInstructionTooltip(description,
            LLL[arrived and "ACTION_SET_KEY_ACCEPT_DESC" or "ACTION_SET_KEY_DESC"]);
    end

    -- **A badged action gets accept and reject instead of the ordering items**, the same swap
    -- the row itself makes (`UpdateMoveButtons`). While the badge is on this action does not
    -- fire, so a place earlier or later settles nothing; what can be done to it here is take it
    -- or throw it back.
    --
    -- Not two dead items with a reason, which is what this menu does elsewhere: **why** they
    -- would be dead is an import matter and not an ordering rule, and `ORDER_BLOCKED_*` exists
    -- to teach the ordering rules.
    --
    -- **The key item stands here too** (2026-08-19, owner's decision). It was left out for a
    -- while on the reading that a key for one row splits the arrival it came in and accepts only
    -- that row. Both halves of that are true and neither is a reason to withhold it: splitting a
    -- set by giving one of its rows a key is an operation this menu already offers everywhere
    -- else, and giving a key **is** accepting, which is the answer the reader came to this menu
    -- for. Taking the whole arrival at once is still the heading's item.
    -- **The plain answer first, then the same answer with a key picked, then the other one**
    -- (2026-08-23, 소유자). The key item led, from when it was the odd one out here; the two
    -- accepts belong side by side, since the second is the first with one thing decided along
    -- the way, and [Reject] is the end of the list because it is the answer that goes the other
    -- way.
    if (action.arrivalID) then
        CreateApproveImportMenuItem(rootDescription, { action });
        CreateAssignKeyItem();
        CreateRejectImportMenuItem(rootDescription, { action });
        return;
    end

    -- **A line between the key and the order** (2026-08-23, 소유자). Which key this is on and
    -- where it stands among the actions sharing that key are two questions, and the second one
    -- only exists once the first is answered. Run together they read as three settings of one
    -- kind.
    CreateAssignKeyItem();
    rootDescription:CreateDivider();
    CreateMoveMenuItem(-1, "ORDER_MOVE_UP", "ORDER_MOVE_UP_DESC");
    CreateMoveMenuItem(1, "ORDER_MOVE_DOWN", "ORDER_MOVE_DOWN_DESC");
end

--- Right-clicking a key group's heading in the left column. **One item, and it is the one thing
--- the whole group can be told at once**: which key it goes on.
---
--- Everything else that menu above offers is about a single action -- an order is a place
--- between two rows, a condition means something different on each of them -- and the heading
--- does not stand for any one of them. `SetupBulkDropdownMenu` keeps the same line for the same
--- reason, and takes move/copy/delete because those do go one at a time. They are left out here
--- on purpose: the heading is a **reading** of the column rather than a selection the reader
--- made, so a delete on it would take rows nobody picked.
---
--- **The title names the set the way the menu above names a row: by what is in it.** The first
--- action's name, then how many follow -- `Charge +1`, which is the summary the heading itself
--- draws once it is folded (`DebindKeyHeaderMixin:UpdateSummary`, `OVERVIEW_KEY_HEADER_MORE`).
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

--- 여럿을 고른 채로 연 메뉴. **이동·복사·삭제 셋뿐이다.**
---
--- 단일 메뉴의 나머지(키·조건·중요도)는 여기 안 넣는다. 그 값들은 한꺼번에 걸 수 있는
--- 것이 아니다 - 조건은 액션마다 뜻이 다르고, 중요도는 이 액션이 걸린 **모든 키**와 공유
--- 레이어면 이 계정의 **모든 캐릭터**까지 건드린다(`IMPORTANCE_SHARED_WARNING`). 그런 것을
--- 열 줄에 한 번에 거는 통로는 되돌릴 수도 없다.
---
--- 고른 것은 전부 **같은 레이어**에 있다. 오른쪽 목록이 한 레이어만 담기 때문이고
--- (`DebindLayerPanelMixin:Refresh`), 그래서 "이미 여기 산다"를 화면의 레이어로 답할 수 있다.
---
--- **One badged action in the selection stops move and copy.** What arrived carries the order its
--- sender designed, and that order lives in `seq` inside one (layer, key) group - so a move hands
--- out a fresh number at the back of a different group and the ranking is gone with no sign of it
--- (`SetKeyForActions`, which exists to keep exactly that). A copy is worse than quiet:
--- `MoveAction` copies the action whole, badge and all, so what came in once is waiting twice.
---
--- **Delete is not in that, and takes the badged rows with the rest.** Neither reason reaches it:
--- nothing is relocated, so there is no ranking left to lose, and nothing is duplicated. What it
--- does to an arrival is what [Reject] does, and a reader who picked a dozen rows to be rid of
--- has said which they meant.
---
--- **Dead, rather than live and aimed at the rest.** Moving the five that can move and leaving
--- the two that cannot is a result nobody was told about, and move has no confirmation box to
--- tell them in - it is exempt on the grounds that what it does can be undone, which stops being
--- true once the reader cannot say which five went. The warning would have to live in a tooltip,
--- and a tooltip is read by choice: nothing that costs the reader something when it goes unread
--- belongs in one. What the block costs instead is one click on a row the list already draws in
--- blue, and the reason says so.
---
--- **Two reasons and not one.** With none of them movable there is nothing to take out of the
--- selection, so that wording would be pointing at a door that is not there; the way out is
--- [Accept], two items down.
---
--- [Accept] and [Reject] need no branch of their own - they aim at the badged ones and build
--- themselves out of the way when there are none.
function DebindUI.SetupBulkDropdownMenu(dropdown, rootDescription, actions)
    -- **The title counts what was picked, not what the three items reach.** It answers "is this
    -- the set I meant", which is asked before any item is read and is about the selection itself.
    rootDescription:CreateTitle(format(LLL["BULK_MENU_TITLE"], #actions));

    -- **The key pair is here because the window below it takes 1..n** (`DebindUI.BeginKeyCapture`,
    -- which the row menu and the heading menu also open, each handing in an array). What kept the
    -- rest of the single menu out of this one was that a value cannot be hung on a dozen actions
    -- at once - a condition means something different on each of them - and a key is the one
    -- thing that does not work that way: one key over a selection is a selection on one key,
    -- which is this addon's ordinary state rather than a compromise.
    --
    -- **Giving and taking stay side by side**, the same as on a row: they are the two ends of one
    -- axis, and a menu that can take a key away but not give one back sends the reader elsewhere
    -- for the other half.
    -- **A third scope gets a third string.** `ACTION_SET_KEY_DESC` opens on "this action" and
    -- `KEY_HEADER_SET_KEY_DESC` on "under this heading", and neither is what the reader is looking
    -- at here. The two were split for this reason to begin with - a sentence stretched across
    -- positions fits none of them (`devdocs/writing-user-facing-text.md`).
    local description = rootDescription:CreateButton(LLL["ACTION_SET_KEY"], function()
        DebindUI.BeginKeyCapture(actions);
    end);
    SetInstructionTooltip(description, LLL["BULK_SET_KEY_DESC"]);

    -- **A selection with no real key in it has nothing to take off** (`DebindPrivate.AnyRealKey`),
    -- which is the answer the dialog's own [Unbind Key] button already gives.
    description = rootDescription:CreateButton(LLL["UNBIND"], function()
        DebindUI.UnbindActions(actions);
    end);
    description:SetEnabled(DebindPrivate.AnyRealKey(actions));

    -- Which of the two reasons the pair below wears, and `nil` for the selection that wears
    -- neither. Counting rather than stopping at the first one is what tells them apart.
    local badgedCount = 0;
    for i = 1, #actions do
        if (actions[i].arrivalID) then
            badgedCount = badgedCount + 1;
        end
    end
    local blockedReason;
    if (badgedCount == #actions) then
        blockedReason = LLL["BULK_BLOCKED_ALL_IMPORTED"];
    elseif (badgedCount > 0) then
        blockedReason = LLL["BULK_BLOCKED_SOME_IMPORTED"];
    end

    if (blockedReason) then
        CreateBlockedMenuItem(rootDescription, LLL["MOVE_TO"], blockedReason);
        CreateBlockedMenuItem(rootDescription, LLL["COPY_TO"], blockedReason);
    else
        local fromLayerID = DebindUI.GetLayerID();
        CreateMoveCopyMenu(rootDescription, false, fromLayerID, function(destLayerID, isCopy)
            DebindUI.MoveActions(actions, destLayerID, isCopy);
        end);
        CreateMoveCopyMenu(rootDescription, true, fromLayerID, function(destLayerID, isCopy)
            DebindUI.MoveActions(actions, destLayerID, isCopy);
        end);
    end

    CreateApproveImportMenuItem(rootDescription, actions);
    CreateRejectImportMenuItem(rootDescription, actions);

    rootDescription:CreateButton(LLL["DELETE"], function()
        DebindUI.ShowBulkDeleteConfirmationPopup(actions);
    end);
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
