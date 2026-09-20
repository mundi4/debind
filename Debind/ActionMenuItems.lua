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
local OnActionsChanged               = ActionMenu.OnActionsChanged;
local AllActions                     = ActionMenu.AllActions;
local AnyAction                      = ActionMenu.AnyAction;
local HowManyAccept                  = ActionMenu.HowManyAccept;
local OnlyOneReason                  = ActionMenu.OnlyOneReason;
local CreateRadio                    = ActionMenu.CreateRadio;
local CreateCheckbox                 = ActionMenu.CreateCheckbox;
local actionValueEquals              = ActionMenu.actionValueEquals;
local setActionValue                 = ActionMenu.setActionValue;
local SORTED_UNIT_LIST               = ActionMenu.SORTED_UNIT_LIST;
local USE_CHECKED_VALUE              = ActionMenu.USE_CHECKED_VALUE;
local GetTabList                     = ActionMenu.GetTabList;
local CastKeyChoiceOf                = ActionMenu.CastKeyChoiceOf;
local CastKeyChoiceIs                = ActionMenu.CastKeyChoiceIs;
local SetCastKeyChoice               = ActionMenu.SetCastKeyChoice;
local CastAutomaticIs                = ActionMenu.CastAutomaticIs;
local SetCastAutomatic               = ActionMenu.SetCastAutomatic;
local HoverCastChoiceIs              = ActionMenu.HoverCastChoiceIs;
local SetHoverCastChoice             = ActionMenu.SetHoverCastChoice;
local SetHoverCastMode               = ActionMenu.SetHoverCastMode;
local NormalCastIsOn                 = ActionMenu.NormalCastIsOn;
local ToggleNormalCast               = ActionMenu.ToggleNormalCast;
local SetInstructionTooltip          = ActionMenu.SetInstructionTooltip;
local SetErrorTooltip                = ActionMenu.SetErrorTooltip;


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

--- The reason a node every selected action has to be able to take stands locked, or nil.
local function SomeCannotReason(acceptance)
    if (acceptance == "some") then
        return LLL["MENU_BLOCKED_SOME_CANNOT"];
    end
end

--- 타입과 값을 그 자리에서 바꾼다. 확인 창이 먼저 서고, 승낙해야 선택 창이 바꾸기 모드로 뜬다
--- (`changing-what-an-action-does.md`).
---
--- **여러 줄을 한꺼번에 받는다.** 조건을 여러 액션에 한 번에 거는 것이 이 애드온에서 키 하나를
--- 세우는 일 자체인데, 액션을 바꾸는 것만 한 줄씩 할 이유가 없다.
---
--- **도착한 액션도 받는다.** 옮기기와 복사를 막는 것은 `seq`가 (레이어, 키, 도착) 그룹 안에서
--- 다시 매겨져 보낸 사람의 순서가 사라지기 때문인데, 바꾸기는 `seq`를 안 건드린다.
local function CreateReplaceActionMenuItem(parentDescription, ctx)
    parentDescription:CreateButton(LLL["REPLACE_ACTION"], function()
        DebindUI.BeginReplaceActions(ctx.actions);
    end);
end

--- **One action at a time**: the body it opens on is that action's own. Over several rows it stands
--- locked as long as any of them could be converted.
local function CreateConvertToMacroTextMenuItem(parentDescription, ctx)
    if (not AnyAction(ctx, DebindPrivate.CanConvertToMacroText)) then
        return;
    end
    local reason = OnlyOneReason(ctx);
    if (reason) then
        CreateBlockedMenuItem(parentDescription, LLL["CONVERT_TO_MACRO_TEXT"], reason);
        return;
    end
    parentDescription:CreateButton(LLL["CONVERT_TO_MACRO_TEXT"], function()
        local action = ctx.actions[1];
        local original = CopyTable(action);
        if (DebindPrivate.ConvertToMacroText(action)) then
            OnActionsChanged({ action });
            local cancelFunc = function()
                wipe(action);
                MergeTable(action, original);
                OnActionsChanged({ action });
            end
            DebindMacroFrame:Open(action, cancelFunc);
        end
    end);
end

local function IsMacroText(action)
    return action.type == Constants.MACROTEXT;
end

-- .." (CTRL-|A:NPE_RightClick:16:16|a)"
local function EditMacroTextMenuItem(parentDescription, ctx)
    if (not AnyAction(ctx, IsMacroText)) then
        return;
    end
    local reason = OnlyOneReason(ctx);
    if (reason) then
        CreateBlockedMenuItem(parentDescription, LLL["EDIT_MACRO"], reason);
        return;
    end
    parentDescription:CreateButton(LLL["EDIT_MACRO"], function()
        DebindMacroFrame:Open(ctx.actions[1]);
    end);
end

--- The three verbs, top to bottom. `Constants.SETSTATE_MODES` is a lookup and would order this
--- differently on every client; a menu whose rows move is one the hand cannot learn.
local SETSTATE_VERBS = {
    { type = Constants.SETSTATE_ON,     label = "SWITCH_ACTION_ON" },
    { type = Constants.SETSTATE_OFF,    label = "SWITCH_ACTION_OFF" },
    { type = Constants.SETSTATE_TOGGLE, label = "SWITCH_ACTION_TOGGLE" },
};

local function IsSetStateAction(action)
    return Constants.SETSTATE_MODES[action.type] ~= nil;
end

--- The stored name goes with every target or verb change. `NameAndIconForAction` builds the row's
--- text from the type and the target every time it draws, so that follows on its own. But an action
--- that came in from a shared string can be carrying `action.name`, and that one would go on saying
--- `Toggle $burst` after the target moved (`ACTION_FIELDS`, §6-C).
local function WriteSetState(actions, field, value)
    for _, action in ipairs(actions) do
        action[field] = value;
        action.name = nil;
    end
    return OnActionsChanged(actions);
end

--- Which switch an on/off/toggle action works, and what it does to it.
---
--- **This is what the picker stopped asking** (§6-C of `redesigning-custom-states.md`).
--- The special tab offered three rows per switch, so choosing one there was the only way to
--- say which, and changing your mind afterwards meant deleting the action and adding another.
--- It had to be here regardless: deleting a switch leaves every action that named it pointing
--- at nothing, and this is where those get repointed rather than thrown away.
---
--- **Two axes in one box, because they are one sentence.** "Turn `$burst` on" is what the row
--- says it does, and a reader who has the verb in one menu and the target in another has to
--- hold half of it in their head while they open the other.
local function CreateSetSwitchMenuItem(parentDescription, ctx)
    local acceptance = HowManyAccept(ctx, IsSetStateAction);
    if (acceptance == "none") then
        return;
    end

    -- The box goes red for both of this action's two ways of being wrong, and the sentence has
    -- to say which. Passed in rather than left to the `states` category, which would find the
    -- right issue code and then print `BINDING_ERROR_UNDEFINED_STATE` with its `%s` unfilled.
    local description = ActionMenus:BuildNode(parentDescription, {
        label = "TYPE_SETSTATE",
        instruction = LLL["TYPE_SETSTATE_DESC"],
        blocked = function()
            return SomeCannotReason(acceptance);
        end,
        valueOf = function(action)
            return { type = action.type, value = action.value };
        end,
        -- a target is what makes this action finished, not a condition on it.
        isActive = function()
            return AnyAction(ctx, function(action)
                return type(action.value) == "string";
            end);
        end,
        issue = function()
            for _, action in ipairs(ctx.actions) do
                local value = action.value;
                if (type(value) ~= "string") then
                    return LLL["BINDING_ERROR_SWITCH_NONE_SELECTED"];
                end
                if (not DebindPrivate.ResolveSwitchDefinition(value)) then
                    return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], value);
                end
            end
        end,
    }, ctx);
    if (acceptance ~= "all") then
        return description;
    end

    -- **Plus whatever any selected action already names**, on the same rule the condition list
    -- keeps: a deleted switch has to stay pickable here or the row that names it cannot be read
    -- back off the menu at all. Unlike a condition it cannot simply be taken off, because an action
    -- with no target is the unfinished state rather than a clean one. What this offers is the way
    -- to point it somewhere else.
    local switchNames = DebindPrivate.GetSwitchNames();
    local listed = {};
    for _, name in ipairs(switchNames) do
        listed[name] = true;
    end
    for _, action in ipairs(ctx.actions) do
        local current = action.value;
        if (type(current) == "string" and not listed[current]
                and not DebindPrivate.ResolveSwitchDefinition(current)) then
            listed[current] = true;
            switchNames[#switchNames + 1] = current;
        end
    end
    sort(switchNames);

    for _, stateName in ipairs(switchNames) do
        local stateDescription = CreateRadio(description, ctx,stateName, function()
            return AllActions(ctx, function(action)
                return action.value == stateName;
            end);
        end, function()
            return WriteSetState(ctx.actions, "value", stateName);
        end);
        if (not DebindPrivate.ResolveSwitchDefinition(stateName)) then
            SetErrorTooltip(stateDescription,
                format(LLL["BINDING_ERROR_UNDEFINED_STATE"], stateName));
        end
    end

    -- Making one from here, for the reason the condition menu grew the same item: the reader
    -- is already looking at the thing they want the switch for.
    do
        local actions = ctx.actions;
        local newDescription = description:CreateButton(LLL["SWITCH_CREATE"], function()
            DebindUI.ShowNewSwitchBox(function(name)
                WriteSetState(actions, "value", name);
            end);
        end);
        SetInstructionTooltip(newDescription, LLL["SWITCH_CREATE_DESC"]);
    end

    description:CreateDivider();
    MenuKit.CreateTitle(description, LLL["SWITCH_ACTION_TITLE"]);

    for _, verb in ipairs(SETSTATE_VERBS) do
        CreateRadio(description, ctx,LLL[verb.label], function()
            return AllActions(ctx, function(action)
                return action.type == verb.type;
            end);
        end, function()
            return WriteSetState(ctx.actions, "type", verb.type);
        end);
    end

    return description;
end

--- The bin's own way to give these actions a key, and the same one the overview's rows offer
--- (`DebindUI.BeginKeyCapture`). It stands right beside [Unbind] because the two are the ends
--- of one axis - what key is this on - and a menu that can take a key away but not give one back
--- sends the reader off to a mode for the other half.
---
--- **It does not replace the binding mode.** That one is still how ten keys get set in a row:
--- it stays on, aims at whatever the cursor is over, and takes back everything on [Cancel]. This
--- is the one-off, on a target that was picked before any key was pressed. **Both shapes stay**,
--- and what each of them answers is in `asking-for-a-key.md`.
---
--- **A selection gets a string of its own.** `ACTION_SET_KEY_DESC` opens on "this action" and a
--- sentence stretched across both positions fits neither (`writing-user-facing-text.md`).
--- **Over one arrival the label says the other half**: giving it a key accepts it
--- (`DebindFrameMixin:SetActionKey`), and a plain label had the reader expecting the key to move and
--- nothing else.
local function CreateAssignKeyMenuItem(parentDescription, ctx)
    local arrived = #ctx.actions == 1 and ctx.actions[1].arrivalID ~= nil;
    local description = parentDescription:CreateButton(
        LLL[arrived and "ACTION_SET_KEY_ACCEPT" or "ACTION_SET_KEY"], function()
            DebindUI.BeginKeyCapture(ctx.actions);
        end);
    local descKey = "BULK_SET_KEY_DESC";
    if (#ctx.actions == 1) then
        descKey = arrived and "ACTION_SET_KEY_ACCEPT_DESC" or "ACTION_SET_KEY_DESC";
    end
    SetInstructionTooltip(description, LLL[descKey]);
end

--- **Through `UnbindActions` for one action as for many.** Taking the key away drops the ordering
--- number with it and renumbers the group being left, which lives in `Profile.lua`; and a selection
--- that would scatter a key group asks first. One action scatters nothing, so it goes straight through.
---
--- **A selection with no real key in it has nothing to take off** (`DebindPrivate.AnyRealKey`),
--- which is the answer the capture dialog's own [Unbind key] button already gives.
local function CreateUnbindMenuItem(parentDescription, ctx)
    local description = parentDescription:CreateButton(LLL["UNBIND"], function()
        DebindUI.UnbindActions(ctx.actions);
    end);
    description:SetEnabled(DebindPrivate.AnyRealKey(ctx.actions));
end

local function IsAimingOnlyType(action)
    return action.type == Constants.TARGET or action.type == Constants.FOCUS
        or action.type == Constants.TOGGLEMENU;
end

local function CreateTargetUnitMenuItem(parentDescription, ctx)
    -- **The same test `GetBindingInfoForAction` keeps a unit on.** Apart, a target picked here is
    -- quietly wiped there, which has happened. A pet command is the case the type alone cannot
    -- settle: only the attack uses a target, and a menu on the rest reads as a setting that does
    -- something.
    local acceptance = HowManyAccept(ctx, DebindPrivate.ActionTakesUnit);
    if (acceptance == "none") then
        return;
    end

    local description = ActionMenus:BuildNode(parentDescription, {
        label = "TARGET_UNIT",
        key = "unit",
        blocked = function()
            return SomeCannotReason(acceptance);
        end,
    }, ctx);
    if (acceptance ~= "all") then
        return description;
    end

    -- A target or focus action has to aim at something, so [None] is only offered where no selected
    -- action is one of those.
    if (not AnyAction(ctx, IsAimingOnlyType)) then
        CreateRadio(description, ctx,LLL["UNIT_DISABLE"], actionValueEquals, setActionValue, { ctx = ctx, key = "unit", value = nil });
    end

    for _, unit in ipairs(SORTED_UNIT_LIST) do
        local unitInfo = DebindUI.UNIT_INFO[unit];
        local offered = AllActions(ctx, function(action)
            return unitInfo[action.type] ~= false;
        end);
        if (offered) then
            local unitDescription = CreateRadio(description, ctx,unitInfo.name, actionValueEquals, setActionValue, { ctx = ctx, key = "unit", value = unit });
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

--- The four presses an action can stand on, and where it goes on each
--- (`which-action-a-key-runs.md` §6).
---
--- **On every action, not only one that takes a target.** Every action has all three twins (§3), so
--- a held key reaches a macro or a mount as well, and taking one out of that press is the same
--- choice there.
local function CreateCastingMenu(parentDescription, ctx)
    local function everyUnitPicked()
        return AllActions(ctx, DebindPrivate.ActionHasPickedUnit);
    end

    --- **The note on the first row and the reason the second stands locked are one sentence.** A
    --- picked unit is not moved by any of these presses (`ActionHasPickedUnit`), so "cast on that
    --- unit" and "cast as usual" are the same cast there, and the first row's label is the half
    --- that stops being literal.
    local function pickedReason()
        if (everyUnitPicked()) then
            return LLL["CAST_KEY_TARGET_PICKED"];
        end
    end

    local description = ActionMenus:BuildNode(parentDescription, {
        label = "CASTING",
        key = "casting",
    }, ctx);

    for _, row in ipairs({
        {
            row = "selfCastKey",
            label = AUTO_SELF_CAST_KEY_TEXT,
            instruction = LLL["CASTING_SELF_CAST_KEY_DESC"],
            cast = "CASTING_SELF_CAST",
            usual = "CASTING_SELF_USUAL_DESC",
            enabled = DebindPrivate.SelfCastEnabled,
        },
        {
            row = "focusCastKey",
            label = FOCUS_CAST_KEY_TEXT,
            instruction = LLL["CASTING_FOCUS_CAST_KEY_DESC"],
            cast = "CASTING_FOCUS_CAST",
            usual = "CASTING_FOCUS_USUAL_DESC",
            enabled = DebindPrivate.FocusCastEnabled,
        },
    }) do
        -- **The account's box takes the whole row.** With the key turned off in the settings the
        -- tier is not built at all, so none of the three answers means anything
        -- (`which-action-a-key-runs.md` §6). What is stored here is kept and waits.
        local rowDescription = ActionMenus:BuildNode(description, {
            label = row.label,
            instruction = row.instruction,
            blocked = function()
                if (not row.enabled()) then
                    return LLL["CAST_KEY_OFF_ACCOUNT_WIDE"];
                end
            end,
            isActive = function()
                return AnyAction(ctx, function(action)
                    return CastKeyChoiceOf(action, row.row) ~= "cast";
                end);
            end,
            valueOf = function(action)
                return CastKeyChoiceOf(action, row.row);
            end,
        }, ctx);

        if (row.enabled()) then
            local function Choice(text, choice)
                return CreateRadio(rowDescription, ctx, text,
                    function()
                        return CastKeyChoiceIs(ctx, row.row, choice);
                    end,
                    function()
                        return SetCastKeyChoice(ctx, row.row, choice);
                    end);
            end

            -- **Off is first on all three rows.** Which of them is the default differs, and a reader
            -- looking for the same value on the next row down should not have to read the list again.
            SetInstructionTooltip(Choice(LLL["CASTING_OFF"], "skip"), LLL["CASTING_SKIP_DESC"]);

            SetInstructionTooltip(Choice(LLL[row.cast], "cast"), LLL[row.cast .. "_DESC"], pickedReason);

            local usual = Choice(LLL["CASTING_AS_USUAL"], "usual");
            usual:SetEnabled(function()
                return not everyUnitPicked();
            end);
            SetInstructionTooltip(usual, LLL[row.usual], pickedReason);
        end
    end

    -- **Three answers over three modes.** Which unit the pointed press means is this action's to say
    -- (§6), and that question does not exist for a key that names its own unit.
    --
    -- **The bare left and right click take the whole row.** Both values are pinned there, the mode to
    -- Unit Frames and the answer to the pointed unit, because a click on a unit frame is the only
    -- press those keys can serve (§7).
    local hoverDescription = ActionMenus:BuildNode(description, {
        label = "POINTED_UNIT_CAST",
        instruction = LLL["CASTING_HOVER_CAST_DESC"],
        blocked = function()
            if (AllActions(ctx, function(action)
                    return DebindPrivate.IsBareWorldClick(action.key);
                end)) then
                return LLL["CASTING_HOVER_BARE_CLICK"];
            end
        end,
        isActive = function()
            return AnyAction(ctx, function(action)
                local casting = action.casting;
                return casting ~= nil
                    and (casting.hoverCast ~= nil or casting.hoverCastMode ~= nil);
            end);
        end,
        -- **Both values, because the radios under this row are not nodes.** `NodeValueText` reads
        -- this one answer for the whole row, so a mode alone would call two actions equal when only
        -- their answer differs.
        valueOf = function(action)
            local casting = action.casting;
            if (casting == nil) then
                return nil;
            end
            return { mode = casting.hoverCastMode, aim = casting.hoverCast };
        end,
    }, ctx);

    do
        local function Choice(text, choice)
            return CreateRadio(hoverDescription, ctx, text,
                function()
                    return HoverCastChoiceIs(ctx, choice);
                end,
                function()
                    return SetHoverCastChoice(ctx, choice);
                end);
        end

        SetInstructionTooltip(Choice(LLL["CASTING_OFF"], nil), LLL["CASTING_HOVER_OFF_DESC"]);

        SetInstructionTooltip(Choice(LLL["CASTING_POINTED_CAST"], "cast"), LLL["CASTING_POINTED_CAST_DESC"],
            pickedReason);

        local usual = Choice(LLL["CASTING_AS_USUAL"], "usual");
        usual:SetEnabled(function()
            return not everyUnitPicked();
        end);
        SetInstructionTooltip(usual, LLL["CASTING_HOVER_USUAL_DESC"], pickedReason);

        hoverDescription:CreateDivider();
    end

    for _, mode in ipairs({
        { account = true,      label = "CASTING_HOVER_ACCOUNT" },
        { value = "unitframe", label = "POINTED_UNIT_CAST_FRAMES",    desc = "POINTED_UNIT_CAST_FRAMES_DESC" },
        { value = "mouseover", label = "POINTED_UNIT_CAST_MOUSEOVER", desc = "POINTED_UNIT_CAST_MOUSEOVER_DESC" },
    }) do
        local modeDescription = CreateRadio(hoverDescription, ctx, LLL[mode.label],
            actionValueEquals,
            function()
                return SetHoverCastMode(ctx, mode.value);
            end,
            { ctx = ctx, key = "casting.hoverCastMode", value = mode.value });
        if (mode.account) then
            -- **It names the mode that is set right now.** The row says where the answer comes
            -- from; a reader who has to open the settings to find out what it is has been sent
            -- away to read one word.
            local current = "POINTED_UNIT_CAST_FRAMES";
            if (DebindPrivate.AccountHoverCastMode() == "mouseover") then
                current = "POINTED_UNIT_CAST_MOUSEOVER";
            end
            SetInstructionTooltip(modeDescription,
                format(LLL["CASTING_HOVER_ACCOUNT_DESC"], LLL[current]));
        else
            SetInstructionTooltip(modeDescription, LLL[mode.desc]);
        end
    end

    local normal = CreateCheckbox(description, ctx, LLL["CASTING_NORMAL"],
        function()
            return NormalCastIsOn(ctx);
        end,
        function()
            return ToggleNormalCast(ctx);
        end);
    SetInstructionTooltip(normal, LLL["CASTING_NORMAL_DESC"]);

    description:CreateDivider();

    -- The four things the game does around a cast on its own, each set for this action alone and
    -- put back the moment the press is over.
    --
    -- **Not set is the game's own setting**, so a reader who never opens these rows keeps exactly
    -- what the game gives everybody else
    -- (`setting-the-clients-cast-automatics-per-action.md` §2).
    local function automaticsReason()
        local reason = AllActions(ctx, function(action)
            return DebindPrivate.CastAutomaticsBlockedReason(action) ~= nil;
        end) and DebindPrivate.CastAutomaticsBlockedReason(ctx.actions[1]);
        if (reason == "gamemacro") then
            return LLL["AUTOMATIC_GAME_MACRO"];
        elseif (reason == "presshold") then
            return LLL["AUTOMATIC_PRESS_AND_HOLD"];
        end
    end

    for _, row in ipairs({
        { row = "autoSelfCast", instruction = LLL["AUTOMATIC_SELF_CAST_DESC"] },
        { row = "autoUnshift", instruction = LLL["AUTOMATIC_CANCEL_FORM_DESC"] },
        { row = "autoDismount", instruction = LLL["AUTOMATIC_DISMOUNT_DESC"] },
        { row = "autoDismountFlying", instruction = LLL["AUTOMATIC_DISMOUNT_FLYING_DESC"] },
    }) do
        local rowDescription = ActionMenus:BuildNode(description, {
            label = DebindPrivate.CastAutomaticLabel(row.row),
            instruction = row.instruction,
            blocked = automaticsReason,
            isActive = function()
                return AnyAction(ctx, function(action)
                    return DebindPrivate.CastAutomaticOf(action, row.row) ~= nil;
                end);
            end,
            valueOf = function(action)
                return DebindPrivate.CastAutomaticOf(action, row.row);
            end,
        }, ctx);

        local function Choice(text, choice)
            return CreateRadio(rowDescription, ctx, text,
                function()
                    return CastAutomaticIs(ctx, row.row, choice);
                end,
                function()
                    return SetCastAutomatic(ctx, row.row, choice);
                end);
        end

        SetInstructionTooltip(Choice(LLL["AUTOMATIC_GAME_SETTING"], nil),
            LLL["AUTOMATIC_GAME_SETTING_DESC"]);
        Choice(LLL["AUTOMATIC_ON"], true);
        Choice(LLL["AUTOMATIC_OFF"], false);
    end

    description:CreateDivider();
    MenuKit.CreateHelpButton(description, "cast-options", LLL["HELP_CAST_OPTIONS_TITLE"]);
end

--- Importance is **the value with the widest reach** in this menu, on both axes: it reorders every
--- key this action is on (not only this one), and on a shared layer it does so for every character
--- on the account.
---
--- The title line's warning can only say the first of those. The second is written nowhere on
--- screen, and the reader who came to this list is thinking about this key's order, which is exactly
--- where it misses. So it rides the item's tooltip, where it is read while the hand is on the radio.
---
--- **One action at a time.** Raised on a dozen at once, their order among themselves stays put while
--- their order against everything left unpicked turns over, on keys the reader is not looking at.
local function CreateImportanceMenu(rootDescription, ctx)
    -- `rawget`이라 없으면 nil이다(로케일 표의 __index를 건너뛴다). 이어붙이기 전에
    -- 갈라서 둔다 - 번역본 한 줄이 빠졌다고 메뉴가 통째로 터지면 안 된다.
    local instruction = rawget(LLL, "IMPORTANCE_DESC");
    local layer = ctx.layer and DebindPrivate.GetProfileLayer(ctx.layer);
    if (layer and not layer.isCharacterSpecific) then
        local warning = LLL["IMPORTANCE_SHARED_WARNING"];
        instruction = instruction and (instruction .. "|n|n" .. warning) or warning;
    end

    local description = ActionMenus:BuildNode(rootDescription, {
        label = "IMPORTANCE",
        key = "priority",
        instruction = instruction,
        blocked = OnlyOneReason,
        isActive = function()
            local action = ctx.actions[1];
            return action.priority ~= nil and action.priority ~= Constants.DEFAULT_IMPORTANCE;
        end,
    }, ctx);
    if (OnlyOneReason(ctx)) then
        return;
    end

    for i = Constants.MIN_IMPORTANCE, Constants.MAX_IMPORTANCE do
        -- 저장할 값으로 바꾸는 것은 Ordering.lua 한 군데다. 기본값을 nil로 접는 규칙이
        -- 여기에도 손으로 적혀 있었는데, 같은 규칙이 두 군데 있으면 한쪽만 바뀐다.
        local value = DebindPrivate.ImportanceToStored(i);
        CreateRadio(description, ctx,LLL["IMPORTANCE" .. i],
            function()
                local action = ctx.actions[1];
                return action.priority == value or action.priority == i;
            end,
            function()
                ctx.actions[1].priority = value;
                return OnActionsChanged(ctx.actions);
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

--- `Run Sooner` and `Run Later`, only on a menu opened over the order list (`ctx.inOrderList`). The
--- layer list draws one layer by name, so where an action stands among the others on its key is not
--- a question that list shows.
---
--- **An arrival alone gets none.** It does not fire, so a place earlier or later settles nothing; the
--- arrows on its row give way to the accept button for the same reason (`UpdateMoveButtons`).
local function CreateOrderMenuItems(rootDescription, ctx)
    if (not ctx.inOrderList) then
        return;
    end
    if (#ctx.actions == 1 and ctx.actions[1].arrivalID ~= nil) then
        return;
    end

    local function CreateMoveItem(direction, titleKey, descKey)
        local reason = OnlyOneReason(ctx);
        if (reason) then
            CreateBlockedMenuItem(rootDescription, LLL[titleKey], reason);
            return;
        end

        local action = ctx.actions[1];
        local description = rootDescription:CreateButton(LLL[titleKey], function()
            local neighborRow = DebindPrivate.ComputeOrderSwapForAction(action, direction);
            DebindUI.ApplyOrderSwap(action, neighborRow and neighborRow.action);
        end);

        local neighbor, blocked = DebindPrivate.ComputeOrderSwapForAction(action, direction);
        description:SetEnabled(neighbor ~= nil);
        if (neighbor) then
            SetInstructionTooltip(description, LLL[descKey]);
        else
            SetErrorTooltip(description, LLL["ORDER_BLOCKED_" .. blocked]);
        end
    end

    CreateMoveItem(-1, "ORDER_MOVE_UP", "ORDER_MOVE_UP_DESC");
    CreateMoveItem(1, "ORDER_MOVE_DOWN", "ORDER_MOVE_DOWN_DESC");
end

--- **Off without deleting.** The action keeps its conditions, its importance and its place in the
--- key, and drops out of the rebuild ahead of every other filter (`Debind.lua:286`). The key is
--- still held for every other action on it, and goes back to the game only when none is left. It is
--- the way out of "this action never runs" that does not mean turning a press back on
--- (`which-action-a-key-runs.md` §6).
local function CreateDisableMenuItem(rootDescription, ctx)
    local description = CreateCheckbox(rootDescription, ctx, LLL["ACTION_DISABLED"], actionValueEquals,
        setActionValue, { ctx = ctx, key = "disabled", value = USE_CHECKED_VALUE });
    SetInstructionTooltip(description, LLL["ACTION_DISABLED_DESC"]);
end

local function CreateDeleteMenu(rootDescription, ctx)
    rootDescription:CreateButton(LLL["DELETE"], function()
        DebindUI.ShowDeleteConfirmationPopup(ctx.actions);
    end);
end

--- What the entry points stand up (`DropDownMenus.lua`).
ActionMenu.CreateReplaceActionMenuItem        = CreateReplaceActionMenuItem;
ActionMenu.CreateConvertToMacroTextMenuItem   = CreateConvertToMacroTextMenuItem;
ActionMenu.EditMacroTextMenuItem              = EditMacroTextMenuItem;
ActionMenu.CreateSetSwitchMenuItem            = CreateSetSwitchMenuItem;
ActionMenu.CreateAssignKeyMenuItem            = CreateAssignKeyMenuItem;
ActionMenu.CreateUnbindMenuItem               = CreateUnbindMenuItem;
ActionMenu.CreateTargetUnitMenuItem           = CreateTargetUnitMenuItem;
ActionMenu.CreateCastingMenu                  = CreateCastingMenu;
ActionMenu.CreateImportanceMenu               = CreateImportanceMenu;
ActionMenu.CreateApproveImportMenuItem        = CreateApproveImportMenuItem;
ActionMenu.CreateRejectImportMenuItem         = CreateRejectImportMenuItem;
ActionMenu.CreateMoveCopyMenu                 = CreateMoveCopyMenu;
ActionMenu.CreateBlockedMenuItem              = CreateBlockedMenuItem;
ActionMenu.CreateOrderMenuItems               = CreateOrderMenuItems;
ActionMenu.CreateDisableMenuItem              = CreateDisableMenuItem;
ActionMenu.CreateDeleteMenu                   = CreateDeleteMenu;
