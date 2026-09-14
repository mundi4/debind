local _, DebindPrivate      = ...;
local Constants             = DebindPrivate.Constants;
local LLL                   = DebindPrivate.L;
local DebindUI              = DebindPrivate.DebindUI;
local MenuKit               = DebindPrivate.MenuKit;

local dump                  = DebindPrivate.dump

--- The edit menu's items that are not conditions.
---
--- **Not nodes, because a node is a group row.** These are buttons and checkboxes with no colour,
--- no issue and no submenu; making them nodes would need a second kind in the kit.
local ActionMenu                     = DebindPrivate.ActionMenu;
local ActionMenus                    = ActionMenu.ActionMenus;
local OnActionValueChanged           = ActionMenu.OnActionValueChanged;
local actionValueEquals              = ActionMenu.actionValueEquals;
local setActionValue                 = ActionMenu.setActionValue;
local SORTED_UNIT_LIST               = ActionMenu.SORTED_UNIT_LIST;
local USE_CHECKED_VALUE              = ActionMenu.USE_CHECKED_VALUE;
local GetTabList                     = ActionMenu.GetTabList;
local SetInstructionTooltip          = ActionMenu.SetInstructionTooltip;
local SetErrorTooltip                = ActionMenu.SetErrorTooltip;


--- Smart Cast (`devdocs/adding-spec-resolved-actions.md` §10).
---
--- Only the types Smart Cast may be set on get the item at all
--- (`Constants.TYPES_WITH_SMART_CAST`).
local function CreateSmartCastMenuItem(parentDescription, ctx)
    if (not Constants.TYPES_WITH_SMART_CAST[ctx.action.type]) then
        return;
    end

    local description = parentDescription:CreateCheckbox(LLL["SMART_CAST"], actionValueEquals,
        setActionValue, { ctx = ctx, key = "smartCast", value = USE_CHECKED_VALUE });

    description:SetEnabled(DebindPrivate.SmartCastEnabled);
    SetInstructionTooltip(description, LLL["SMART_CAST_DESC"], function()
        if (not DebindPrivate.SmartCastEnabled()) then
            return LLL["SMART_CAST_DISABLED_ACCOUNT_WIDE"];
        end
    end);

    ActionMenus:MarkNew("SMART_CAST", description);
end

local function CreateConvertToMacroTextMenuItem(parentDescription, ctx)
    if (DebindPrivate.CanConvertToMacroText(ctx.action)) then
        parentDescription:CreateButton(LLL["CONVERT_TO_MACRO_TEXT"], function()
            local action = ctx.action;
            local original = CopyTable(action);
            if (DebindPrivate.ConvertToMacroText(action)) then
                OnActionValueChanged(ctx.action);
                local cancelFunc = function()
                    wipe(action);
                    MergeTable(action, original);
                    OnActionValueChanged(ctx.action);
                end
                DebindMacroFrame:Open(action, cancelFunc);
            end
        end);
    end
end

-- .." (CTRL-|A:NPE_RightClick:16:16|a)"
local function EditMacroTextMenuItem(parentDescription, ctx)
    if (ctx.action.type == Constants.MACROTEXT) then
        parentDescription:CreateButton(LLL["EDIT_MACRO"], function()
            DebindMacroFrame:Open(ctx.elementData.action);
        end);
    end
end

--- The three verbs, top to bottom. `Constants.SETSTATE_MODES` is a lookup and would order this
--- differently on every client; a menu whose rows move is one the hand cannot learn.
local SETSTATE_VERBS = {
    { type = Constants.SETSTATE_ON,     label = "SWITCH_ACTION_ON" },
    { type = Constants.SETSTATE_OFF,    label = "SWITCH_ACTION_OFF" },
    { type = Constants.SETSTATE_TOGGLE, label = "SWITCH_ACTION_TOGGLE" },
};

--- Which switch an on/off/toggle action works, and what it does to it.
---
--- **This is what the picker stopped asking** (§6-C of `devdocs/legacy/redesigning-custom-states.md`).
--- The special tab offered three rows per switch, so choosing one there was the only way to
--- say which, and changing your mind afterwards meant deleting the action and adding another.
--- It had to be here regardless: deleting a switch leaves every action that named it pointing
--- at nothing, and this is where those get repointed rather than thrown away.
---
--- **Two axes in one box, because they are one sentence.** "Turn `$burst` on" is what the row
--- says it does, and a reader who has the verb in one menu and the target in another has to
--- hold half of it in their head while they open the other.
local function CreateSetSwitchMenuItem(parentDescription, ctx)
    if (not Constants.SETSTATE_MODES[ctx.action.type]) then
        return;
    end

    -- The box goes red for both of this action's two ways of being wrong, and the sentence has
    -- to say which. Passed in rather than left to the `states` category, which would find the
    -- right issue code and then print `BINDING_ERROR_UNDEFINED_STATE` with its `%s` unfilled.
    local description = ActionMenus:BuildNode(parentDescription, {
        label = "TYPE_SETSTATE",
        instruction = LLL["TYPE_SETSTATE_DESC"],
        -- a target is what makes this action finished, not a condition on it.
        isActive = function()
            return type(ctx.action.value) == "string";
        end,
        issue = function()
            local value = ctx.action.value;
            if (type(value) ~= "string") then
                return LLL["BINDING_ERROR_SWITCH_NONE_SELECTED"];
            end
            if (not DebindPrivate.ResolveSwitchDefinition(value)) then
                return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], value);
            end
        end,
    }, ctx);

    -- **Plus whatever this action already names**, on the same rule the condition list keeps:
    -- a deleted switch has to stay pickable here or the row that names it cannot be read back
    -- off the menu at all. Unlike a condition it cannot simply be taken off, because an action
    -- with no target is the unfinished state rather than a clean one. What this offers is the
    -- way to point it somewhere else.
    local switchNames = DebindPrivate.GetSwitchNames();
    local current = ctx.action.value;
    if (type(current) == "string" and not DebindPrivate.ResolveSwitchDefinition(current)) then
        switchNames[#switchNames + 1] = current;
        sort(switchNames);
    end

    for _, stateName in ipairs(switchNames) do
        local stateDescription = description:CreateRadio(stateName, function()
            return ctx.action.value == stateName;
        end, function()
            -- **The stored name goes with it.** `NameAndIconForAction` builds the row's text
            -- from the type and the target every time it draws, so that follows on its own.
            -- But an action that came in from a shared string can be carrying `action.name`,
            -- and that one would go on saying `Toggle $burst` after the target moved
            -- (`ACTION_FIELDS`, §6-C).
            ctx.action.value = stateName;
            ctx.action.name = nil;
            return OnActionValueChanged(ctx.action);
        end);
        if (not DebindPrivate.ResolveSwitchDefinition(stateName)) then
            SetErrorTooltip(stateDescription,
                format(LLL["BINDING_ERROR_UNDEFINED_STATE"], stateName));
        end
    end

    -- Making one from here, for the reason the condition menu grew the same item: the reader
    -- is already looking at the thing they want the switch for.
    do
        local action = ctx.action;
        local newDescription = description:CreateButton(LLL["SWITCH_CREATE"], function()
            DebindUI.ShowNewSwitchBox(function(name)
                action.value = name;
                action.name = nil;
                DebindPrivate.RenumberKeyGroupForAction(action);
                DebindPrivate.UpdateBindings();
            end);
        end);
        SetInstructionTooltip(newDescription, LLL["SWITCH_CREATE_DESC"]);
    end

    description:CreateDivider();
    MenuKit.CreateTitle(description, LLL["SWITCH_ACTION_TITLE"]);

    for _, verb in ipairs(SETSTATE_VERBS) do
        description:CreateRadio(LLL[verb.label], function()
            return ctx.action.type == verb.type;
        end, function()
            ctx.action.type = verb.type;
            ctx.action.name = nil;
            return OnActionValueChanged(ctx.action);
        end);
    end

    return description;
end

--- The bin's own way to give this action a key, and the same one the overview's rows offer
--- (`DebindUI.BeginKeyCapture`). It stands right beside [Unbind] because the two are the ends
--- of one axis - what key is this on - and a menu that can take a key away but not give one back
--- sends the reader off to a mode for the other half.
---
--- **It does not replace the binding mode.** That one is still how ten keys get set in a row:
--- it stays on, aims at whatever the cursor is over, and takes back everything on [Cancel]. This
--- is the one-off, on a target that was picked before any key was pressed. **Both shapes stay**,
--- and what each of them answers is in `devdocs/legacy/asking-for-a-key.md`.
local function CreateAssignKeyMenuItem(parentDescription, ctx)
    local description = parentDescription:CreateButton(LLL["ACTION_SET_KEY"], function()
        DebindUI.BeginKeyCapture({ ctx.action });
    end);
    SetInstructionTooltip(description, LLL["ACTION_SET_KEY_DESC"]);
end

local function CreateUnbindMenuItem(parentDescription, ctx)
    local description = parentDescription:CreateButton(LLL["UNBIND"], function()
        -- Not `ctx.action.key = nil` on its own: taking the key away drops the ordering number
        -- with it and renumbers the group being left, and that rule lives in `Profile.lua`.
        DebindPrivate.ClearActionKey(ctx.action);
        OnActionValueChanged(ctx.action);
        -- 목록이 키로 묶여 있던 시절에는 이 행이 "키 없음" 묶음으로 건너뛰어서, 메뉴만
        -- 남고 행은 화면 밖으로 사라졌다. 지금은 이름순이라 키를 지워도 행이 제자리다 -
        -- 그래도 화면 밖에 있을 수는 있으므로(스크롤) 짚어주는 것은 그대로 둔다.
        DebindLayerPanel:ScrollActionIntoView(ctx.action);
        return MenuResponse.Refresh;
    end);
    description:SetEnabled(function()
        return ctx.action.key ~= nil;
    end);
end

local function CreateTargetUnitMenuItem(parentDescription, ctx)
    -- **The same test `GetBindingInfoForAction` keeps a unit on.** Apart, a target picked here is
    -- quietly wiped there, which has happened. A pet command is the case the type alone cannot
    -- settle: only the attack uses a target, and a menu on the rest reads as a setting that does
    -- something.
    if (not DebindPrivate.ActionTakesUnit(ctx.action)) then
        return;
    end

    local description = ActionMenus:BuildNode(parentDescription,
        { label = "TARGET_UNIT", key = "unit" }, ctx);

    if (not (ctx.action.type == Constants.TARGET or ctx.action.type == Constants.FOCUS or ctx.action.type == Constants.TOGGLEMENU)) then
        description:CreateRadio(LLL["UNIT_DISABLE"], actionValueEquals, setActionValue, { ctx = ctx, key = "unit", value = nil });
    end

    for _, unit in ipairs(SORTED_UNIT_LIST) do
        local unitInfo = DebindUI.UNIT_INFO[unit];
        if (unitInfo[ctx.action.type] ~= false) then
            local unitDescription = description:CreateRadio(unitInfo.name, actionValueEquals, setActionValue, { ctx = ctx, key = "unit", value = unit });
            -- **Every entry here says it, not just the menu row above.** A reader can arrive on
            -- one of these from the action's own tooltip without ever hovering the parent, and the
            -- fact only bites once something is picked. It rides the entry's own sentence rather
            -- than standing up a second instruction line, which is what costs a tooltip its shape.
            local fixed = LLL["TARGET_UNIT_FIXED"];
            SetInstructionTooltip(unitDescription,
                unitInfo.tooltipTitle and (unitInfo.tooltipTitle .. "|n|n" .. fixed) or fixed);
        end
    end

    return description;
end

--- **On every action, not only one that takes a target.** Every action has both twins
--- (`devdocs/implementing-focus-and-self-cast.md` §3-4), so a held key reaches a macro or a mount as
--- well, and taking one out of that press is the same choice there.
local function CreateIgnoreCastKeyMenuItems(parentDescription, ctx)
    for _, box in ipairs({
        { key = "ignoreSelfCastKey", label = "IGNORE_SELF_CAST_KEY", enabled = DebindPrivate.SelfCastEnabled },
        { key = "ignoreFocusCastKey", label = "IGNORE_FOCUS_CAST_KEY", enabled = DebindPrivate.FocusCastEnabled },
    }) do
        local ignore = parentDescription:CreateCheckbox(LLL[box.label], actionValueEquals, setActionValue,
            { ctx = ctx, key = box.key, value = USE_CHECKED_VALUE });
        ignore:SetEnabled(box.enabled);
        local says = (Constants.CAST_KEY_IGNORE == Constants.CAST_KEY_IGNORE_AIM) and "_AIM_DESC" or "_DESC";
        SetInstructionTooltip(ignore, LLL[box.label .. says], function()
            if (not box.enabled()) then
                return LLL["CAST_KEY_OFF_ACCOUNT_WIDE"];
            end
        end);
    end
end

--- 집 편집기 같은 바인딩 컨텍스트가 가져간 키는 기본적으로 우리가 내준다. 편집기가
--- 자기 버튼과 안내 문구에 그 키를 그려주기 때문에, 우리가 먹으면 화면에 떠 있는
--- 단축키가 안 먹는 상태가 된다. 그래도 그 키를 쓰겠다는 유저를 위한 통로다.
local function CreateKeepInBindingContextMenuItem(rootDescription, ctx)
    local description = rootDescription:CreateCheckbox(LLL["KEEP_IN_BINDING_CONTEXT"], actionValueEquals,
        setActionValue, { ctx = ctx, key = "keepInBindingContext", value = USE_CHECKED_VALUE });
    SetInstructionTooltip(description, LLL["KEEP_IN_BINDING_CONTEXT_DESC"]);
end

--- 중요도는 이 메뉴에서 **파장이 가장 넓은 값**이다. 축이 둘 다 넓다: 이 액션이 걸린
--- **모든 키**의 순서를 바꾸고(이 키만이 아니다), 공유 레이어면 **이 계정의 모든
--- 캐릭터**에서 그렇게 된다.
---
--- 제목 줄의 경고는 첫째 축까지밖에 못 말한다("여기서 바꾸면 모든 캐릭터"). 둘째 축은
--- 화면 어디에도 안 적혀 있고, 하필 이 목록에 온 사람의 머릿속은 "이 키의 순서"에 가
--- 있어서 정확히 어긋나는 자리다. 그래서 고르는 손이 라디오 위에 있는 순간 읽히도록
--- 항목 툴팁에 붙인다.
local function CreateImportanceMenu(rootDescription, ctx)
    -- `rawget`이라 없으면 nil이다(로케일 표의 __index를 건너뛴다). 이어붙이기 전에
    -- 갈라서 둔다 - 번역본 한 줄이 빠졌다고 메뉴가 통째로 터지면 안 된다.
    local instruction = rawget(LLL, "IMPORTANCE_DESC");
    local layer = ctx.elementData.layer and DebindPrivate.GetProfileLayer(ctx.elementData.layer);
    if (layer and not layer.isCharacterSpecific) then
        local warning = LLL["IMPORTANCE_SHARED_WARNING"];
        instruction = instruction and (instruction .. "|n|n" .. warning) or warning;
    end

    local description = ActionMenus:BuildNode(rootDescription, {
        label = "IMPORTANCE",
        key = "priority",
        instruction = instruction,
        isActive = function()
            return ctx.action.priority ~= nil and ctx.action.priority ~= Constants.DEFAULT_IMPORTANCE;
        end,
    }, ctx);

    for i = Constants.MIN_IMPORTANCE, Constants.MAX_IMPORTANCE do
        -- 저장할 값으로 바꾸는 것은 Ordering.lua 한 군데다. 기본값을 nil로 접는 규칙이
        -- 여기에도 손으로 적혀 있었는데, 같은 규칙이 두 군데 있으면 한쪽만 바뀐다.
        local value = DebindPrivate.ImportanceToStored(i);
        description:CreateRadio(LLL["IMPORTANCE" .. i],
            function()
                return ctx.action.priority == value or ctx.action.priority == i;
            end,
            function()
                ctx.action.priority = value;
                OnActionValueChanged(ctx.action);
                return MenuResponse.Refresh;
            end
        );
    end
end

--- Taking the badge off imported actions, which is what makes them fire.
---
--- **This is the only way out of quarantine, so it cannot be hidden when it does not apply.**
--- It is left out entirely when nothing in the selection carries a badge - a greyed-out row
--- would be a permanent fixture in a menu that is already long, saying nothing about anything
--- the reader owns. Every other entry here is about a property they can set; this one is about
--- where the action came from, and most actions came from nowhere.
---
--- Takes a list either way, so the single and the bulk menu hand it the same shape.
--- **What this takes, where the reader did not pick it.** A heading stands over rows nobody
--- selected, so the item names the subset it gathers rather than pointing at the rows - the
--- wording and why it is not "these %d" are in `enUS.lua`.
---
--- One is its own string rather than the count with a 1 in it, and the plain labels are not the
--- fallback: over a heading they read as all of it.
local function ImportItemLabel(count, oneKey, countedKey)
    if (count == 1) then
        return LLL[oneKey];
    end
    return format(LLL[countedKey], count);
end

--- `counted` turns the label into the counted form (`ImportItemLabel`). The menus where the
--- reader pointed at one thing leave it off.
local function CreateApproveImportMenuItem(rootDescription, actions, counted)
    local badged = {};
    for _, action in ipairs(actions) do
        if (action and action.arrivalID) then
            badged[#badged + 1] = action;
        end
    end
    if (#badged == 0) then
        return;
    end

    local label = LLL["APPROVE_IMPORT"];
    if (counted) then
        label = ImportItemLabel(#badged, "KEY_HEADER_APPROVE_ONE", "KEY_HEADER_APPROVE");
    end

    local description = rootDescription:CreateButton(label, function()
        DebindUI.ApproveArrivedActions(badged);
    end);
    -- **The accept button's own words** (`DebindOrderLineMixin:OnAcceptEnter`). One operation with
    -- two entrances has one explanation, and the labels differing is what the two positions need
    -- rather than a difference in what happens.
    --
    -- **It is only hung when one action is aimed at.** The string is written for a single arrival
    -- - "this one" - which stops being true the moment the bulk menu hands this a set.
    --
    -- **And which of the two it is depends on that action's key**, the same as on the button:
    -- one arrived on a key and starts firing here, the other arrived without one and does not.
    if (#badged == 1) then
        SetInstructionTooltip(description,
            LLL[badged[1].key ~= nil and "ORDER_ACCEPT_DESC" or "ORDER_ACCEPT_NO_KEY_DESC"]);
    end
end

--- The other answer to the same question, on the same terms as the one above: only built when
--- something in the selection carries a badge, and it takes a list either way.
---
--- **It is not the delete item wearing a different word.** That one asks about an action of the
--- reader's own and is final; this asks about something that arrived, and the string it arrived
--- in is still in the drawer - which is what its prompt says, and what makes it the reversible
--- half of this pair. Accepting is the half that cannot be undone.
local function CreateRejectImportMenuItem(rootDescription, actions, counted)
    local badged = {};
    for _, action in ipairs(actions) do
        if (action and action.arrivalID) then
            badged[#badged + 1] = action;
        end
    end
    if (#badged == 0) then
        return;
    end

    local label = LLL["REJECT_IMPORT"];
    if (counted) then
        label = ImportItemLabel(#badged, "KEY_HEADER_REJECT_ONE", "KEY_HEADER_REJECT");
    end

    local description = rootDescription:CreateButton(label, function()
        DebindUI.ShowRejectImportConfirmationPopup(badged);
    end);
    -- Hung on the same terms as the item above, and written for one row for the same reason.
    -- There was no string to borrow here: the left column's row carries no reject button, so this
    -- half of the pair had never been explained anywhere a single action was the subject.
    if (#badged == 1) then
        SetInstructionTooltip(description, LLL["REJECT_IMPORT_DESC"]);
    end
end

--- 겨누는 것이 하나든 여럿이든 목적지 목록은 **같은 하나**다(`GetTabList`). 그래서 대상을
--- 밖에서 받는다: `fromLayerID`는 "이미 여기 산다"를 판정하는 데만 쓰이고, `applyFunc`가
--- 실제로 옮긴다.
local function CreateMoveCopyMenu(rootDescription, isCopy, fromLayerID, applyFunc)
    local optionsDescription = rootDescription:CreateButton(isCopy and LLL["COPY_TO"] or LLL["MOVE_TO"]);
    MenuKit.CreateTitle(optionsDescription, MenuUtil.GetElementText(optionsDescription));

    local func = function(args)
        applyFunc(args[1], isCopy);
    end

    -- **"지금 이 액션이 사는 레이어"이지 "지금 보고 있는 탭"이 아니다.** 오버뷰 탭에서는
    -- 행마다 레이어가 다르므로 화면으로는 답할 수 없고, 레이어 탭에서는 둘이 같은 값이라
    -- 달라지는 것이 없다.
    --
    -- 지금 사는 탭도 **이름 그대로** 세우고 뒤에만 표시를 붙인다. "현재 탭"이라고만 적으면
    -- 그 줄만 다른 종류의 이름이 돼서 목록에서 어디에 끼어 있는지가 안 읽히는데, 오버뷰
    -- 탭에서 여는 메뉴는 그 답이 화면에 없다 - 행마다 레이어가 다르다.
    for _, tabInfo in ipairs(GetTabList()) do
        local isSameLayer = tabInfo.layerID == fromLayerID;
        local description = optionsDescription:CreateButton(
            isSameLayer and format(LLL["CURRENT_TAB_SUFFIX"], tabInfo.label) or tabInfo.label,
            func,
            { tabInfo.layerID }
        );

        -- 제자리로는 못 옮긴다(`MoveAction`의 `assert(copying, ...)`). 빼지 않고 회색으로
        -- 세워 두는 이유는 목록이 두 메뉴에서 **같은 모양**이어야 해서다 - 한 줄이 빠지면
        -- 나머지가 한 칸씩 올라와, 같은 탭이 이동과 복사에서 다른 높이에 선다.
        if (isSameLayer and not isCopy) then
            description:SetEnabled(false);
            SetErrorTooltip(description, LLL["MOVE_TO_CURRENT_LAYER_BLOCKED"]);
        end
    end
end

--- An item that stands only to say it cannot be taken, and why.
---
--- **It is built as a leaf even where the live one is a submenu.** A destination list nobody can
--- open is a list with no reason to exist, and the arrow on a parent that never opens promises a
--- step that is not there. What the reader loses is nothing they could have used; what they get
--- is the same shape this menu already uses for a blocked destination.
local function CreateBlockedMenuItem(rootDescription, text, reason)
    local description = rootDescription:CreateButton(text);
    description:SetEnabled(false);
    SetErrorTooltip(description, reason);
    return description;
end

local function CreateDeleteMenu(rootDescription, ctx)
    rootDescription:CreateButton(LLL["DELETE"], function()
        DebindUI.ShowDeleteConfirmationPopup(ctx.elementData);
    end);
end

--- What the six entry points stand up (`DropDownMenus.lua`).
ActionMenu.CreateSmartCastMenuItem            = CreateSmartCastMenuItem;
ActionMenu.CreateConvertToMacroTextMenuItem   = CreateConvertToMacroTextMenuItem;
ActionMenu.EditMacroTextMenuItem              = EditMacroTextMenuItem;
ActionMenu.CreateSetSwitchMenuItem            = CreateSetSwitchMenuItem;
ActionMenu.CreateAssignKeyMenuItem            = CreateAssignKeyMenuItem;
ActionMenu.CreateUnbindMenuItem               = CreateUnbindMenuItem;
ActionMenu.CreateTargetUnitMenuItem           = CreateTargetUnitMenuItem;
ActionMenu.CreateIgnoreCastKeyMenuItems       = CreateIgnoreCastKeyMenuItems;
ActionMenu.CreateKeepInBindingContextMenuItem = CreateKeepInBindingContextMenuItem;
ActionMenu.CreateImportanceMenu               = CreateImportanceMenu;
ActionMenu.CreateApproveImportMenuItem        = CreateApproveImportMenuItem;
ActionMenu.CreateRejectImportMenuItem         = CreateRejectImportMenuItem;
ActionMenu.CreateMoveCopyMenu                 = CreateMoveCopyMenu;
ActionMenu.CreateBlockedMenuItem              = CreateBlockedMenuItem;
ActionMenu.CreateDeleteMenu                   = CreateDeleteMenu;
