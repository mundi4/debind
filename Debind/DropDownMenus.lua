local _, DebindPrivate    = ...;
local Constants             = DebindPrivate.Constants;
local LLL                   = DebindPrivate.L;
local DebindUI            = DebindPrivate.DebindUI;

local dump                  = DebindPrivate.dump
local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;

local ARRAY_MARKER          = {};
-- 선택 창의 명령 탭도 같은 목록을 건다. 사본을 하나 더 두면 갈라진다 (`ActionDisplay.lua`).
local SORTED_UNIT_LIST      = DebindUI.SORTED_UNIT_LIST;
local USE_CHECKED_VALUE     = {};

-- The hover condition and the unit conditions draw their reaction boxes from this one list. Two
-- copies drift the day a reaction is added.
local REACTION_ITEMS        = {
    { text = LLL["REACTION_HELP"],  value = Constants.REACTION_HELP },
    { text = LLL["REACTION_HARM"],  value = Constants.REACTION_HARM },
    { text = LLL["REACTION_OTHER"], value = Constants.REACTION_OTHER },
};

--- The life radios. **`value` is what gets stored, verbatim** -- the first row clears the `dead`
--- field, so it carries no `value` at all (a table cannot hold a `nil` one).
---
--- It says `Disable`, the same word every other three-way radio here opens with. The row is not a
--- third value to pick from; it is this axis constraining nothing, which is what every other
--- first row means too.
local LIFE_ITEMS            = {
    { text = LLL["DISABLE"] },
    { text = LLL["LIFE_ALIVE"], value = false },
    { text = LLL["LIFE_DEAD"],  value = true },
};


local BONUSBAR_NAMES;
local TAB_LIST;


local function range(startIndex, endIndex, func)
    local arr = {};
    for i = startIndex, endIndex do
        local t, eof = func(i);
        if (t ~= nil) then
            tinsert(arr, func(i));
        end
        if (eof) then
            break;
        end
    end
    arr[ARRAY_MARKER] = true;
    return arr;
end

--- A menu item's tooltip: its own label as the title, one instruction line under it.
---
--- Shared out because the Switches tab builds a menu of its own with the same items in it
--- (`SwitchesUI.lua`), and two copies of this would be two answers to "what does a menu item's
--- tooltip look like" in one window.
function DebindUI.SetInstructionTooltip(description, text)
    description:SetTooltip(function(tooltip, elementDescription)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
        GameTooltip_AddInstructionLine(tooltip, text);
    end);
end
local SetInstructionTooltip = DebindUI.SetInstructionTooltip;

local function SetErrorTooltip(description, text)
    description:SetTooltip(function(tooltip, elementDescription)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
        GameTooltip_AddErrorLine(tooltip, text);
    end);
end


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
-- OptionsDropDown
--------------------------------------------------------------------------------
-- 정렬 항목은 여기 없다. 목록 순서는 이름순으로 굳었고, 남은 하나(단축키로 묶을지)는
-- 목록 바로 위의 체크박스다 - 목록의 생김새만 바꾸는 것이라 결과가 보이는 자리에 있어야
-- 한다. 이유는 DebindUI.lua의 `BuildSortedElements`에.
function DebindUI.SetupOptionsDropdownMenu(dropdown, rootDescription)
    do
        local unitframeDescription = rootDescription:CreateButton(LLL["UNITFRAME_OPTIONS"]);
        if (DebindPrivate.CliqueDetected) then
            SetErrorTooltip(unitframeDescription, LLL["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"]);
            unitframeDescription:SetEnabled(false);
        end

        --- The three answers, and `nil` among them is one of them and not the absence of one:
        --- it is "whatever the game does", which `ApplyOptions` reads off the CVar. So the radio
        --- compares against `data.value` rather than testing for a value being there at all.
        local edgeDescription = unitframeDescription:CreateButton(LLL["UNITFRAME_CLICK_EDGE"]);
        SetInstructionTooltip(edgeDescription,
            format(LLL["UNITFRAME_CLICK_EDGE_DESC"], ACTION_BUTTON_USE_KEY_DOWN));

        local function clickEdgeIs(data)
            return DebindPrivate.Options.unitframeUseMouseDown == data.value;
        end

        local function setClickEdge(data)
            DebindPrivate.Options.unitframeUseMouseDown = data.value;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
            return MenuResponse.Refresh;
        end

        edgeDescription:CreateRadio(LLL["UNITFRAME_CLICK_EDGE_GAME"], clickEdgeIs, setClickEdge, {});
        edgeDescription:CreateRadio(LLL["UNITFRAME_CLICK_EDGE_DOWN"], clickEdgeIs, setClickEdge, { value = true });
        edgeDescription:CreateRadio(LLL["UNITFRAME_CLICK_EDGE_UP"], clickEdgeIs, setClickEdge, { value = false });

        unitframeDescription:CreateDivider();

        local framesDescription = unitframeDescription:CreateButton(LLL["BLIZZARD_UNIT_FRAMES"]);
        for _, frameType in ipairs({ "player", "pet", "target", "party", "raid", "boss", "arena" }) do
            framesDescription:CreateCheckbox(LLL["BLIZZARD_UNIT_FRAMES_" .. strupper(frameType)], function()
                return DebindPrivate.Options.blizzframes[frameType] ~= false;
            end, function()
                DebindPrivate.Options.blizzframes[frameType] = not (DebindPrivate.Options.blizzframes[frameType] ~= false);
                DebindPrivate.UpdateBlizzardFrames();
                return MenuResponse.Refresh;
            end);
        end
    end

    do
        local specialUnitsDescription = rootDescription:CreateButton(LLL["SPECIAL_UNITS"]);
        local excludePlayerDescription = specialUnitsDescription:CreateButton(LLL["EXCLUDE_PLAYER"]);
        SetInstructionTooltip(excludePlayerDescription, LLL["EXCLUDE_PLAYER_DESC"]);
        for _, unit in ipairs({ "tank", "healer", "maintank", "mainassist" }) do
            excludePlayerDescription:CreateCheckbox(DebindUI.UNIT_INFO[unit].name, function()
                return DebindPrivate.Options.excludePlayer and DebindPrivate.Options.excludePlayer[unit];
            end, function()
                if (not DebindPrivate.Options.excludePlayer) then
                    DebindPrivate.Options.excludePlayer = {};
                end
                DebindPrivate.Options.excludePlayer[unit] = not DebindPrivate.Options.excludePlayer[unit];
                local header = DebindPrivate.GetUnitWatchHeader(unit);
                if (header) then
                    header:SetAttribute("showPlayer", not DebindPrivate.Options.excludePlayer[unit]);
                end
                return MenuResponse.Refresh;
            end);
        end
    end

    do
        local stateDriverUpdateThrottleDescription = rootDescription:CreateButton(LLL["STATE_DRIVER_UPDATE_THROTTLE"]);
        -- stateDriverUpdateThrottleDescription:CreateCheckbox(LLL["STATE_DRIVER_UPDATE_THROTTLE_DISABLE"], function()
        --     return DebindPrivate.Options.removeStateDriverUpdateThrottle and true or false;
        -- end, function()
        --     DebindPrivate.Options.removeStateDriverUpdateThrottle = (not DebindPrivate.Options.removeStateDriverUpdateThrottle) or nil;
        --     DebindPrivate.ApplyOptions("removeStateDriverUpdateThrottle");
        --     return MenuResponse.Refresh;
        -- end);
        SetInstructionTooltip(stateDriverUpdateThrottleDescription, LLL["STATE_DRIVER_UPDATE_THROTTLE_DESC"]);
        stateDriverUpdateThrottleDescription:SetTooltip(function(tooltip, elementDescription)
            GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
            GameTooltip_AddInstructionLine(tooltip, LLL["STATE_DRIVER_UPDATE_THROTTLE_DESC"]);
            GameTooltip_AddBlankLineToTooltip(tooltip);
            GameTooltip_AddErrorLine(tooltip, LLL["STATE_DRIVER_UPDATE_THROTTLE_WARNING"]);
        end);

        local sliderDescription = stateDriverUpdateThrottleDescription:CreateTemplate("DebindStateDriverUpdateThrottleSliderTemplate");
        sliderDescription:AddInitializer(function(frame, description, menu)
            frame:UpdateVisibleState();
        end)
    end

    -- **[Remove Duplicate Actions] stood here, behind a divider, and is a button on the portrait
    -- row now** (`CleanUpPortrait`). It was the one item in this menu that did something rather
    -- than remembering something, and that was always the awkward part: everything else here is a
    -- setting the reader leaves switched. What decided it is that the button can be grey. A menu
    -- item cannot say "there is nothing to clean up" without being opened and read, so it was
    -- always pressable and answered in a line; a button in the open says it by being lit or not,
    -- and paying for that sweep on every gesture is a price only the button's own row owes.

    -- do
    --     local sliderDescription = rootDescription:CreateTemplate("DebindStateDriverUpdateThrottleSliderTemplate");
    --     sliderDescription:AddInitializer(function(frame, description, menu)
    --         frame:OnAttach();
    --     end)
    -- end
end

--- The destination list every "where does this go" menu reads. Move, copy, and the picker's
--- "add to" all take the same one - two copies drift the day a tab is added.
---
--- 목록은 **레이어**의 목록이지 탭 좌표의 목록이 아니다.
---
--- 같은 레이어를 두 좌표가 가리키는 일이 실재한다: 캐릭터 전용 탭에서 (탭2, 사이드탭1)과
--- (탭2, 사이드탭2)가 **둘 다 레이어 7**이다. 그래서 layerID로 접는다 - 안 접으면 같은
--- 곳으로 가는 항목이 이름만 다르게 둘 나오고, "이동"으로 그 둘째를 고르면
--- `MoveAction`의 `assert(copying, "cannot move to same layer")`에 걸린다.
--- 남는 이름은 사이드탭1 쪽인데, 화면에서 레이어 7이 실제로 서 있는 자리가 거기다
--- (`UpdateSideTabs`가 탭2에서 사이드탭2를 숨긴다).
local function GetTabList()
    if (TAB_LIST == nil) then
        TAB_LIST = {};
        local seenLayers = {};
        for tabID = 1, #DebindLayerPanel.Tabs do
            local tabLabel = DebindUI.GetTabLabel(tabID);
            if (tabLabel) then
                for sideTabID = 1, #DebindLayerPanel.SideTabs do
                    local sideTabLabel = DebindUI.GetSideTabLabel(sideTabID);
                    if (sideTabLabel) then
                        local layerID = DebindUI.GetLayerID(tabID, sideTabID);
                        if (not seenLayers[layerID]) then
                            seenLayers[layerID] = true;
                            tinsert(TAB_LIST, {
                                layerID = layerID,
                                label = format("%s - %s", tabLabel, sideTabLabel),
                            });
                        end
                    end
                end
            end
        end
    end
    return TAB_LIST;
end

--------------------------------------------------------------------------------
-- EditDropDown_Initialize
--------------------------------------------------------------------------------
do
    local _elementData, _action;

    --- The edit menu has changed one of the action's values.
    ---
    --- **It does not look at which value.** Conditions, importance and hover are steps in the
    --- ordering, so changing one changes what this action is up against -- and rather than work out
    --- which step moved, the key group is always renumbered. If nothing moved the renumber moves
    --- nothing (`Profile.lua`'s `RenumberKeyGroup`). Working it out would mean seeing the action
    --- before and after, and putting that pair of snapshots across the dozen call sites in this menu
    --- means missing one someday.
    local function onActionValueChanged()
        DebindPrivate.RenumberKeyGroupForAction(_action);
        DebindPrivate.UpdateBindings();
        return MenuResponse.Refresh;
    end

    --- 이 키가 사는 표. 조건은 `_action.conditions` 안이고 나머지는 액션 자신이다.
    --- 어느 이름이 조건인지는 `Constants.IsConditionField`가 답한다.
    ---
    --- **참조를 붙들어 두지 않고 부를 때마다 푼다.** 조건 표는 첫 조건이 걸릴 때 생기고
    --- 마지막 조건이 풀릴 때 없어진다. 메뉴를 세울 때 잡아두면 그 사이에 표가 갈려서
    --- 사라진 표에 쓰게 된다 - `units`가 같은 함정을 갖고 있고 그 자리에 적혀 있다.
    ---
    --- `create`가 거짓이면 없는 표를 만들지 않는다. 읽기만 하는 쪽이 조건 하나 없는 액션에
    --- 표를 만들어 두면, 조건이 하나도 없는데 조건부로 분류된다(`IsConditionalBinding`).
    local function TableFor(action, key, create)
        if (not Constants.IsConditionField(key)) then
            return action;
        end
        local conditions = action.conditions;
        if (conditions == nil and create) then
            conditions = {};
            action.conditions = conditions;
        end
        return conditions;
    end

    --- 이 액션의 유닛 조건 표. 없으면 nil이고, 만들지 않는다.
    local function UnitConditionsOf(action)
        return action.conditions and action.conditions.units;
    end

    --- 조건을 하나 지운 뒤. **빈 표는 안 남긴다** - 있느냐를 게이트로 쓰는 자리가 여럿이라
    --- (`IsConditionalBinding`, `CleanUpDB`) 조건이 없는 액션이 조건부가 된다.
    local function PruneConditions(action)
        if (action.conditions and next(action.conditions) == nil) then
            action.conditions = nil;
        end
    end

    local function actionValueEquals(args)
        local key, value = args.key, args.value;
        local tbl = TableFor(_action, key);
        if (value == USE_CHECKED_VALUE) then
            return tbl ~= nil and tbl[key] and true or false;
        else
            return (tbl and tbl[key]) == value;
        end
    end

    local function setActionValue(args)
        local key, value = args.key, args.value;
        if (value == USE_CHECKED_VALUE) then
            local tbl = TableFor(_action, key, true);
            tbl[key] = not tbl[key];
            PruneConditions(_action);
            -- The checkbox branch goes through the same place. Neither field that comes this way
            -- today (`ignoreHoverUnit`, `keepInBindingContext`) is a step in the ordering, so the
            -- renumber moves nothing -- but the day one that is arrives here, that group alone
            -- would quietly keep the old symptom.
            return onActionValueChanged();
        else
            -- 값이 안 바뀌면 아무것도 안 한다. `nil`을 고를 때 표를 만들었다가 곧바로
            -- 거두는 일도 없어야 해서, 표는 실제로 쓸 때만 만든다.
            local tbl = TableFor(_action, key);
            if ((tbl and tbl[key]) ~= value) then
                if (value == nil) then
                    if (tbl) then
                        tbl[key] = nil;
                        PruneConditions(_action);
                    end
                else
                    TableFor(_action, key, true)[key] = value;
                end
                return onActionValueChanged();
            end
        end
    end

    local function _hasBit(data)
        local targetObj = data.targetObj or TableFor(_action, data.key);
        local current = (targetObj and targetObj[data.key]) or data.defaultValue or 0;
        return bit.band(current, data.value) == data.value;
    end

    local function _toggleBit(data)
        local targetObj = data.targetObj or TableFor(_action, data.key, true);
        local current = targetObj[data.key] or data.defaultValue or 0;
        targetObj[data.key] = bit.bxor(current, data.value);
        PruneConditions(_action);
        onActionValueChanged();
        return MenuResponse.Refresh;
    end

    local function AppendDisable(description, prefix, property)
        local text = rawget(LLL, prefix .. "_DISABLE") or LLL["DISABLE"];
        return description:CreateRadio(text, actionValueEquals, setActionValue, { key = property, value = nil });
    end

    local function AppendYesNo(description, prefix, property)
        local yes = description:CreateRadio(rawget(LLL, prefix .. "_YES") or YES, actionValueEquals, setActionValue, { key = property, value = true });
        local no = description:CreateRadio(rawget(LLL, prefix .. "_NO") or NO, actionValueEquals, setActionValue, { key = property, value = false });
        return yes, no;
    end

    local function AppendDisableYesNo(description, prefix, property)
        local disable = AppendDisable(description, prefix, property);
        local yes, no = AppendYesNo(description, prefix, property);
        return disable, yes, no;
    end

    local function AppendCheckboxes(parentDescription, key, items, callback, defaultValue)
        for _, item in ipairs(items) do
            local isSelected, setSelected = item.isSelected, item.setSelected;
            if (isSelected == nil) then
                isSelected = _hasBit;
            end
            if (setSelected == nil) then
                setSelected = _toggleBit;
            end
            local description = parentDescription:CreateCheckbox(item.text, isSelected, setSelected, { key = key, value = item.value, defaultValue = defaultValue });
            if (callback) then
                callback(description, item);
            end
        end
    end

    local function CreateActionMenuItemGroup(parentDescription, text, key, isActive, error, instruction, skipTitle)
        local txt = rawget(LLL, text);
        if (txt) then
            if (not instruction) then
                instruction = rawget(LLL, text .. "_DESC");
            end
        else
            txt = text;
        end

        local description = parentDescription:CreateButton(txt);
        description:AddInitializer(function(button, elementDescription, menu)
            local color = HIGHLIGHT_FONT_COLOR;
            local err;
            if (error) then
                if (type(error) == "function") then
                    err = error(key);
                else
                    err = error;
                end
            elseif (key and Constants.BINDING_ISSUE_CATEGORIES[key]) then
                -- **묶음 키가 곧 이슈 갈래인 것은 아니다.** 이 메뉴가 쓰는 키 중 절반은
                -- 그 이름의 검사가 없다(`combat`, `known`, `stealth`, `pet`, `extrabar`,
                -- 커스텀 상태, 중요도). 그냥 물으면 언제나 nil이라 지금과 답이 같지만,
                -- 없는 갈래를 묻는 것 자체가 DEBUG에서 걸린다.
                err = DebindPrivate.GetBindingIssue(_action, key);
            end

            if (err) then
                color = ERROR_COLOR;
                -- **마지막 폴백은 `err`이지 `error`가 아니다.** 이슈 코드로 온 것은 위 두
                -- 조회가 문장으로 바꿔주는데, 이미 완성된 문장으로 온 것은 둘 다 못 찾는다.
                -- 거기서 `error`로 떨어지면 **함수를 넘긴 호출자에게 함수가 그대로 나간다** -
                -- 이름을 문장에 찍어 넣어야 하는 갈래(스위치 조건)가 그 경우다.
                err = rawget(LLL, err) or rawget(LLL, "BINDING_ERROR_" .. err) or err;
            else
                local active = isActive;
                if (active) then
                    if (type(active) == "function") then
                        active = active(key);
                    end
                elseif (key) then
                    -- **`TableFor`를 거친다.** 조건은 `_action.conditions` 안이라 최상단을
                    -- 보면 언제나 nil이고, 그러면 조건이 걸린 묶음이 하나도 안 파래진다.
                    -- 조건이 아닌 키(`priority`)는 그대로 액션에서 읽힌다.
                    local tbl = TableFor(_action, key);
                    active = tbl ~= nil and tbl[key] ~= nil;
                end

                if (active) then
                    color = BLUE_FONT_COLOR;
                end
            end

            button.fontString:SetTextColor(color:GetRGB());

            elementDescription:SetTooltip(function(tooltip, elementDescription)
                local first = true;
                if (instruction) then
                    GameTooltip_AddInstructionLine(tooltip, instruction);
                    first = false;
                end

                if (err) then
                    if (not first) then
                        GameTooltip_AddBlankLineToTooltip(tooltip);
                    end
                    GameTooltip_AddErrorLine(tooltip, err);
                end
            end);
        end);

        if (not skipTitle) then
            description:QueueTitle(MenuUtil.GetElementText(description));
        end

        return description;
    end

    --- Read and write one unit condition, one field per axis (`Profile.lua`'s `dbver <= 4` step).
    ---
    --- Three radios at the top of the submenu line up with the three shapes storage has: no key
    --- (unconstrained), a table (exists, plus whatever axes it names), `false` (absent). Every
    --- axis is one field inside that table, so a new axis adds a block to the menu and leaves
    --- these accessors alone.
    ---
    --- The axis widgets all read the table off `_action` at click time rather than capturing it.
    --- `units` is nil until the first condition is set, so a reference grabbed while the
    --- menu was being built goes stale the moment the user turns one on.
    local function GetUnitConditionReaction(unit)
        local value = UnitConditionsOf(_action) and UnitConditionsOf(_action)[unit];
        if (type(value) ~= "table") then
            return nil;
        end
        return value.reaction;
    end

    --- Which of the three radios above is on, `nil` where no condition was ever made.
    ---
    --- **The reading is `UnitConditionForBinding`'s and not a second one.** This used to spell the
    --- same fork out again -- scalars first, then `off`, then `exists == false` -- with a comment
    --- saying the two had to agree, which nothing could check: that function is reached by the
    --- headless specs and this file is not (`tests/run.lua`). The day they parted, the screen would
    --- have said [when there is one] while the binding meant [when there is not], and only somebody
    --- pressing the key would have found out. `ActionTooltip.lua` reads unit conditions the same
    --- way, for the same reason.
    ---
    --- **`off` is the one thing that function cannot answer.** It conflates a turned-off condition
    --- with an absent one, answering `nil` for both, which is right for a binding and wrong for a
    --- menu: this screen has to keep showing the axes a reader turned off but did not throw away.
    --- So it is asked here, ahead of the shared reading.
    local function UnitConditionMode(unit)
        local units = UnitConditionsOf(_action);
        local value = units and units[unit];
        if (value == nil) then
            return nil;
        end
        if (type(value) == "table" and value.off) then
            return "off";
        end
        if (DebindPrivate.UnitConditionForBinding(value) == false) then
            return "absent";
        end
        return "exists";
    end

    local function UnitConditionIsExists(unit)
        return UnitConditionMode(unit) == "exists";
    end

    --- 조건이 실제로 걸려 있는가. 꺼진 채로 축만 기억하는 것은 조건이 아니다 - 묶음을 파랗게
    --- 칠하는 자리들이 이걸 물어야 **끈 조건 때문에 "걸려 있음"으로 보이지** 않는다.
    local function UnitConditionIsOn(unit)
        local mode = UnitConditionMode(unit);
        return mode == "exists" or mode == "absent";
    end

    local function GetUnitConditionDead(unit)
        local value = UnitConditionsOf(_action) and UnitConditionsOf(_action)[unit];
        if (type(value) ~= "table") then
            return nil;
        end
        return value.dead;
    end

    --- 위쪽 라디오 셋이 쓰는 것. **`exists`만 바꾸고 축은 건드리지 않는다** - [사용 안 함]으로
    --- 옮겼다가 되돌리면 골라둔 반응·생사가 그대로 있어야 한다. 무시하는 것은
    --- `Misc.UnitConditionForBinding`이 한다.
    ---
    --- 끈 자리에 기억할 축이 하나도 없으면 키를 지운다. 안 그러면 아무것도 안 고른 유닛의
    --- 빈 표가 프로필에 쌓인다.
    local function SetUnitConditionMode(unit, mode)
        local units = UnitConditionsOf(_action);
        local cond = units and units[unit];
        if (type(cond) ~= "table") then
            cond = {};
        end
        -- **`and false or`로 쓰지 말 것.** 그 관용구는 `false`를 못 돌려준다 - 참일 때
        -- `true and false`가 `false`가 되고 그게 다시 `or`의 왼쪽이라 오른쪽이 나온다.
        -- 그렇게 쓴 동안 [없을 때]가 아무것도 안 적어서 [있을 때]와 같은 값이 됐다.
        cond.off = (mode == "off") or nil;
        if (mode == "absent") then
            cond.exists = false;
        else
            cond.exists = nil;
        end

        if (mode == "off" and cond.reaction == nil and cond.dead == nil) then
            -- 기억할 축이 하나도 없다. 빈 표를 남기면 아무것도 안 고른 유닛이 프로필에 쌓인다.
            if (units) then
                units[unit] = nil;
                if (not next(units)) then
                    _action.conditions.units = nil;
                    PruneConditions(_action);
                end
            end
        else
            if (units == nil) then
                units = {};
                TableFor(_action, "units", true).units = units;
            end
            units[unit] = cond;
        end

        onActionValueChanged();
        return MenuResponse.Refresh;
    end

    --- Write one axis. Every caller is gated on the `exists` radio, so the table is already there.
    local function SetUnitConditionAxis(unit, axis, value)
        local cond = UnitConditionsOf(_action) and UnitConditionsOf(_action)[unit];
        if (type(cond) ~= "table") then
            return;
        end
        cond[axis] = value;
        onActionValueChanged();
        return MenuResponse.Refresh;
    end

    --- The reaction boxes. Storage is a mask, but **all-on is never written** -- that says the
    --- same thing as constraining nothing, and one condition stored two ways is two different
    --- boxes to the solver (`Misc.lua` normalizes `reactions`/`frameTypes` for the same reason).
    ---
    --- 0 **is** written. Choosing nothing is not something to normalize away; it is an issue, and
    --- `GetBindingIssue`'s zero-mask branch reports it where the user set it.
    local function UnitConditionReactionChecked(unit, value)
        local reaction = GetUnitConditionReaction(unit);
        if (reaction == nil) then
            return true;
        end
        return bit.band(reaction, value) == value;
    end

    local function ToggleUnitConditionReaction(unit, value)
        local mask = bit.bxor(GetUnitConditionReaction(unit) or Constants.REACTION_ALL, value);
        if (mask == Constants.REACTION_ALL) then
            mask = nil;
        end
        return SetUnitConditionAxis(unit, "reaction", mask);
    end

    local function CreateUnitConditionSubmenu(parentDescription, label, unit)
        local optionsDescription = CreateActionMenuItemGroup(parentDescription, label, nil,
            function()
                return UnitConditionIsOn(unit);
            end,
            -- error
            function()
                return DebindPrivate.GetBindingIssue(_action, "units", nil, unit);
            end,
            nil, true);

        local titleDescription = optionsDescription:CreateTitle(MenuUtil.GetElementText(optionsDescription));
        if (unit == "@") then
            -- 여는 줄은 `Only if...`로 두고, **어느 유닛에 거는 조건인지는 안쪽 제목이 말한다.**
            -- 바깥 줄까지 대상 이름으로 바꾸면 바로 위 라디오 목록이 방금 고른 그 이름을 한 번
            -- 더 되뇌게 된다.
            --
            -- `player`가 빠지는 이유는 다른 것과 같다: 자기 자신은 늘 있으므로 걸 조건이 없다.
            optionsDescription:SetEnabled(function()
                return _action.unit and _action.unit ~= "none" and _action.unit ~= "player"
                    and true or false;
            end);

            titleDescription:AddInitializer(function(button, elementDescription, menu)
                if (_action.unit and _action.unit ~= "none") then
                    button.fontString:SetText(format(LLL["SELECTED_TARGET_UNIT"], DebindUI.UNIT_INFO[_action.unit].name));
                else
                    button.fontString:SetText(LLL["SELECTED_TARGET_UNIT_EMPTY"]);
                end
            end);
        end

        optionsDescription:CreateRadio(LLL["DISABLE"],
            function()
                local mode = UnitConditionMode(unit);
                return mode == nil or mode == "off";
            end,
            function()
                return SetUnitConditionMode(unit, "off");
            end
        );

        -- The three above are exclusive; the axis blocks below are alive only while `exists` is
        -- picked. Same arrangement the hover menu gets from `hoverConditionIsOn`.
        optionsDescription:CreateRadio(LLL["CONDITION_UNIT_EXISTS"],
            function()
                return UnitConditionIsExists(unit);
            end,
            function()
                return SetUnitConditionMode(unit, "exists");
            end
        );

        local absentDescription = optionsDescription:CreateRadio(LLL["CONDITION_UNIT_DOES_NOT_EXIST"],
            function()
                return UnitConditionMode(unit) == "absent";
            end,
            function()
                return SetUnitConditionMode(unit, "absent");
            end
        );

        -- `"@"`는 이 액션이 **겨누는** 대상이다. 없는 유닛은 겨눌 수 없으니 "없을 때"라는 말이
        -- 설 자리가 없다. 줄을 빼지 않고 잠그는 이유는, 다른 유닛과 같은 메뉴라는 것이 보여야
        -- 여기만 다른 문법이라고 읽지 않기 때문이다.
        if (unit == "@") then
            absentDescription:SetEnabled(false);
        end

        local function axisIsEnabled()
            return UnitConditionIsExists(unit);
        end

        optionsDescription:CreateDivider();
        optionsDescription:CreateTitle(LLL["CONDITION_REACTIONS"]);

        for _, item in ipairs(REACTION_ITEMS) do
            local reactionDescription = optionsDescription:CreateCheckbox(item.text,
                function()
                    return UnitConditionReactionChecked(unit, item.value);
                end,
                function()
                    return ToggleUnitConditionReaction(unit, item.value);
                end
            );
            reactionDescription:SetEnabled(axisIsEnabled);
        end

        optionsDescription:CreateDivider();
        optionsDescription:CreateTitle(LLL["CONDITION_LIFE"]);

        -- A two-valued axis gets radios. **What the UI can produce is exactly what storage can
        -- hold**, so the "neither box ticked" a checkbox pair would open up -- a condition no unit
        -- can satisfy -- never comes into existence. Reactions have three values and so need
        -- somewhere to pick a subset; that group stores its 0 and lets `GetBindingIssue` catch it.
        -- This is where the two axes part.
        for _, item in ipairs(LIFE_ITEMS) do
            local lifeDescription = optionsDescription:CreateRadio(item.text,
                function()
                    return GetUnitConditionDead(unit) == item.value;
                end,
                function()
                    return SetUnitConditionAxis(unit, "dead", item.value);
                end
            );
            lifeDescription:SetEnabled(axisIsEnabled);
        end

        return optionsDescription;
    end

    local function hoverConditionIsOn()
        if (DebindPrivate.CliqueDetected) then
            return false;
        end
        return UnitConditionIsExists("hover");
    end

    local function CreateConvertToMacroTextMenuItem(parentDescription)
        if (DebindPrivate.CanConvertToMacroText(_action)) then
            parentDescription:CreateButton(LLL["CONVERT_TO_MACRO_TEXT"], function()
                -- 되돌릴 액션을 지금 붙잡아 둔다. _elementData는 다음 행의 메뉴가 열릴
                -- 때마다 갈아끼워지는 파일 단위 값이라, [취소]를 누르는 시점에 읽으면
                -- **엉뚱한 액션을 비우고 그 자리에 이 액션의 원본을 덮어쓴다.**
                local action = _action;
                local original = CopyTable(action);
                if (DebindPrivate.ConvertToMacroText(action)) then
                    onActionValueChanged();
                    local cancelFunc = function()
                        wipe(action);
                        MergeTable(action, original);
                        onActionValueChanged();
                    end
                    DebindMacroFrame:Open(action, cancelFunc);
                end
            end);
        end
    end

    -- .." (CTRL-|A:NPE_RightClick:16:16|a)"
    local function EditMacroTextMenuItem(parentDescription)
        if (_action.type == Constants.MACROTEXT) then
            parentDescription:CreateButton(LLL["EDIT_MACRO"], function()
                DebindMacroFrame:Open(_elementData.action);
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
    local function CreateSetSwitchMenuItem(parentDescription)
        if (not Constants.SETSTATE_MODES[_action.type]) then
            return;
        end

        -- The box goes red for both of this action's two ways of being wrong, and the sentence has
        -- to say which. Passed in rather than left to the `states` category, which would find the
        -- right issue code and then print `BINDING_ERROR_UNDEFINED_STATE` with its `%s` unfilled.
        local description = CreateActionMenuItemGroup(parentDescription, "TYPE_SETSTATE", nil,
            -- isActive: a target is what makes this action finished, not a condition on it.
            function()
                return type(_action.value) == "string";
            end,
            function()
                local value = _action.value;
                if (type(value) ~= "string") then
                    return LLL["BINDING_ERROR_SWITCH_NONE_SELECTED"];
                end
                if (not DebindPrivate.ResolveSwitchDefinition(value)) then
                    return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], value);
                end
            end,
            LLL["TYPE_SETSTATE_DESC"]);

        -- **Plus whatever this action already names**, on the same rule the condition list keeps:
        -- a deleted switch has to stay pickable here or the row that names it cannot be read back
        -- off the menu at all. Unlike a condition it cannot simply be taken off, because an action
        -- with no target is the unfinished state rather than a clean one. What this offers is the
        -- way to point it somewhere else.
        local switchNames = DebindPrivate.GetSwitchNames();
        local current = _action.value;
        if (type(current) == "string" and not DebindPrivate.ResolveSwitchDefinition(current)) then
            switchNames[#switchNames + 1] = current;
            sort(switchNames);
        end

        for _, stateName in ipairs(switchNames) do
            local stateDescription = description:CreateRadio(stateName, function()
                return _action.value == stateName;
            end, function()
                -- **The stored name goes with it.** `NameAndIconForAction` builds the row's text
                -- from the type and the target every time it draws, so that follows on its own.
                -- But an action that came in from a shared string can be carrying `action.name`,
                -- and that one would go on saying `Toggle $burst` after the target moved
                -- (`ACTION_FIELDS`, §6-C).
                _action.value = stateName;
                _action.name = nil;
                return onActionValueChanged();
            end);
            if (not DebindPrivate.ResolveSwitchDefinition(stateName)) then
                SetErrorTooltip(stateDescription,
                    format(LLL["BINDING_ERROR_UNDEFINED_STATE"], stateName));
            end
        end

        -- Making one from here, for the reason the condition menu grew the same item: the reader
        -- is already looking at the thing they want the switch for.
        do
            local action = _action;
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
        description:CreateTitle(LLL["SWITCH_ACTION_TITLE"]);

        for _, verb in ipairs(SETSTATE_VERBS) do
            description:CreateRadio(LLL[verb.label], function()
                return _action.type == verb.type;
            end, function()
                _action.type = verb.type;
                _action.name = nil;
                return onActionValueChanged();
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
    local function CreateAssignKeyMenuItem(parentDescription)
        local description = parentDescription:CreateButton(LLL["ACTION_SET_KEY"], function()
            DebindUI.BeginKeyCapture({ _action });
        end);
        SetInstructionTooltip(description, LLL["ACTION_SET_KEY_DESC"]);
    end

    local function CreateUnbindMenuItem(parentDescription)
        local description = parentDescription:CreateButton(LLL["UNBIND"], function()
            -- Not `_action.key = nil` on its own: taking the key away drops the ordering number
            -- with it and renumbers the group being left, and that rule lives in `Profile.lua`.
            DebindPrivate.ClearActionKey(_action);
            onActionValueChanged();
            -- 목록이 키로 묶여 있던 시절에는 이 행이 "키 없음" 묶음으로 건너뛰어서, 메뉴만
            -- 남고 행은 화면 밖으로 사라졌다. 지금은 이름순이라 키를 지워도 행이 제자리다 -
            -- 그래도 화면 밖에 있을 수는 있으므로(스크롤) 짚어주는 것은 그대로 둔다.
            DebindLayerPanel:ScrollActionIntoView(_action);
            return MenuResponse.Refresh;
        end);
        description:SetEnabled(function()
            return _action.key ~= nil;
        end);
    end

    local function CreateTargetUnitMenuItem(parentDescription)
        -- 목록은 `Constants.TYPES_WITH_UNIT` 하나뿐이다. `GetBindingInfoForAction`이
        -- 바인딩을 만들 때 보는 것과 **같은 값**이라야 한다 - 갈리면 여기서 고를 수 있는
        -- 대상이 저기서 조용히 지워진다(실제로 그랬다).
        if (not Constants.TYPES_WITH_UNIT[_action.type]) then
            return;
        end

        -- 펫 명령은 타입만으로 안 갈린다. 대상을 쓰는 건 **공격 하나뿐이고**
        -- (`PetAttack(target)`), 나머지 핸들러는 조건의 참·거짓만 보고 target을 버린다.
        -- 이동 지정은 지면을 찍는 명령이라 유닛이 들어갈 자리가 아니다(`Misc.lua` 참고).
        -- 안 쓰는 것에 메뉴를 띄우면 그 설정이 무언가를 한다고 읽힌다.
        if (_action.type == Constants.PETACTION and not DebindPrivate.PetActionTakesUnit(_action.value)) then
            return;
        end

        local description = CreateActionMenuItemGroup(parentDescription, "TARGET_UNIT", "unit");

        if (not (_action.type == Constants.TARGET or _action.type == Constants.FOCUS or _action.type == Constants.TOGGLEMENU)) then
            description:CreateRadio(LLL["UNIT_DISABLE"], actionValueEquals, setActionValue, { key = "unit", value = nil });
        end

        for _, unit in ipairs(SORTED_UNIT_LIST) do
            local unitInfo = DebindUI.UNIT_INFO[unit];
            if (unitInfo[_action.type] ~= false) then
                local unitDescription = description:CreateRadio(unitInfo.name, actionValueEquals, setActionValue, { key = "unit", value = unit });

                -- TODO locale 파일 업데이트 할 것.
                -- local instructionTooltip = rawget(LLL, "TARGET_UNIT_" .. strupper(unit) .. "_DESC") or (unitInfo.type and "TARGET_UNIT_" .. strupper(unitInfo.type) .. "_DESC");
                -- if (instructionTooltip) then
                --     SetInstructionTooltip(optionDescription, instructionTooltip);
                -- end

                if (unitInfo.tooltipTitle) then
                    SetInstructionTooltip(unitDescription, unitInfo.tooltipTitle);
                end
            end
        end

        -- 겨누는 대상에 거는 조건은 **다른 유닛과 같은 메뉴**를 쓴다. 여기만 체크박스 + 좁은
        -- 프리셋이던 시절에는 같은 것을 두 문법으로 말했고, 축이 하나 늘 때마다 이 목록이
        -- 네 줄씩 길어졌다. 서브메뉴로 접으면 대상 목록은 대상만 남는다.
        description:CreateDivider();
        CreateUnitConditionSubmenu(description, "ONLY_IF", "@");

        return description;
    end

    --- 이 메뉴가 만지는 것은 `units["hover"]`다 - **호버한 프레임의 유닛도 유닛이다**
    --- (`Profile.lua`의 `dbver <= 4`). 옛 `hover`/`reactions` 두 필드는 없어졌고, 그 이름들은
    --- 이제 파생값이라(`Misc.DeriveHoverFields`) 이슈 category로는 그대로 쓴다.
    ---
    --- `frameTypes`와 `ignoreHoverUnit`은 여전히 액션 루트에 있다. 그건 유닛이 아니라
    --- **프레임**을 말하는 값이라 접을 축이 아니었다.
    local function CreateHoverMenu(parentDescription)
        local description = CreateActionMenuItemGroup(parentDescription, "CONDITION_HOVER", "hover",
            function()
                return UnitConditionIsOn("hover");
            end,
            DebindPrivate.CliqueDetected and LLL["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"] or nil);

        -- Clique를 켜 두면 hover 조건은 어차피 동작하지 않는다. 그래도 메뉴를 잠그지는
        -- 않는다 - 이미 켜 둔 값을 [사용 안 함]으로 지우러 들어갈 수 있어야 하기 때문이다.
        -- 대신 값이 있느냐로 색을 가른다: **값이 남아 있으면 고쳐야 할 것**이라 빨강(위에서
        -- 칠한 ERROR_COLOR 그대로)이고, 값이 없으면 지금 고를 수 없는 항목일 뿐이라
        -- 회색이다 - 켠 적도 없는 조건을 오류로 붉히면 고칠 것이 있는 줄 알게 된다.
        -- 그룹이 제 초기화에서 색을 칠하므로 그 뒤에 덧칠하는 초기화를 하나 더 건다.
        if (DebindPrivate.CliqueDetected) then
            description:AddInitializer(function(button)
                if (not UnitConditionIsOn("hover")) then
                    button.fontString:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
                end
            end);
        end

        -- 유닛 서브메뉴의 라디오 셋과 같은 세 상태다. 글자만 이 자리의 말로 쓴다 -
        -- 여기서는 "존재"가 곧 "마우스를 올리고 있음"이다.
        description:CreateRadio(rawget(LLL, "CONDITION_HOVER_DISABLE") or LLL["DISABLE"],
            function()
                local mode = UnitConditionMode("hover");
                return mode == nil or mode == "off";
            end,
            function()
                return SetUnitConditionMode("hover", "off");
            end
        );

        local yes = description:CreateRadio(LLL["CONDITION_HOVER_YES"],
            function()
                return UnitConditionIsExists("hover");
            end,
            function()
                return SetUnitConditionMode("hover", "exists");
            end
        );

        local no = description:CreateRadio(LLL["CONDITION_HOVER_NO"],
            function()
                return UnitConditionMode("hover") == "absent";
            end,
            function()
                return SetUnitConditionMode("hover", "absent");
            end
        );

        if (DebindPrivate.CliqueDetected) then
            yes:SetEnabled(false);
            no:SetEnabled(false);
        end


        description:CreateDivider();
        description:CreateTitle(LLL["CONDITION_REACTIONS"]);

        for _, item in ipairs(REACTION_ITEMS) do
            local reactionDescription = description:CreateCheckbox(item.text,
                function()
                    return UnitConditionReactionChecked("hover", item.value);
                end,
                function()
                    return ToggleUnitConditionReaction("hover", item.value);
                end
            );
            reactionDescription:SetEnabled(hoverConditionIsOn);
        end

        description:CreateDivider();
        description:CreateTitle(LLL["CONDITION_LIFE"]);

        for _, item in ipairs(LIFE_ITEMS) do
            local lifeDescription = description:CreateRadio(item.text,
                function()
                    return GetUnitConditionDead("hover") == item.value;
                end,
                function()
                    return SetUnitConditionAxis("hover", "dead", item.value);
                end
            );
            lifeDescription:SetEnabled(hoverConditionIsOn);
        end

        description:CreateDivider();
        description:CreateTitle(LLL["CONDITION_FRAMETYPES"]);

        AppendCheckboxes(description, "frameTypes", {
                { text = LLL["FRAMETYPE_PLAYER"],  value = Constants["FRAMETYPE_PLAYER"] },
                { text = LLL["FRAMETYPE_PET"],     value = Constants["FRAMETYPE_PET"] },
                { text = LLL["FRAMETYPE_GROUP"],   value = Constants["FRAMETYPE_GROUP"] },
                { text = LLL["FRAMETYPE_TARGET"],  value = Constants["FRAMETYPE_TARGET"] },
                { text = LLL["FRAMETYPE_BOSS"],    value = Constants["FRAMETYPE_BOSS"] },
                { text = LLL["FRAMETYPE_ARENA"],   value = Constants["FRAMETYPE_ARENA"] },
                { text = LLL["FRAMETYPE_UNKNOWN"], value = Constants["FRAMETYPE_UNKNOWN"] },
            }, function(elementDescription)
                elementDescription:SetEnabled(hoverConditionIsOn);
            end,
            (Constants["FRAMETYPE_PLAYER"]
                + Constants["FRAMETYPE_PET"]
                + Constants["FRAMETYPE_GROUP"]
                + Constants["FRAMETYPE_TARGET"]
                + Constants["FRAMETYPE_BOSS"]
                + Constants["FRAMETYPE_ARENA"]
                + Constants["FRAMETYPE_UNKNOWN"])
        );

        description:CreateDivider();
        local ignoreHoverUnit = description:CreateCheckbox(LLL["IGNORE_HOVER_UNIT"], actionValueEquals, setActionValue, { key = "ignoreHoverUnit", value = USE_CHECKED_VALUE });
        SetInstructionTooltip(ignoreHoverUnit, LLL["IGNORE_HOVER_UNIT_DESC"]);
        ignoreHoverUnit:SetEnabled(hoverConditionIsOn);
    end

    local function CreateUnitConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_UNITS", "units",
            -- isActive. `"@"`와 `"hover"`는 제 메뉴가 따로 있어서 여기서 안 센다 - 이 묶음이
            -- 안 보여주는 조건 때문에 파랗게 뜨면 어디를 고쳐야 하는지가 안 보인다.
            function()
                if (UnitConditionsOf(_action)) then
                    for unit, value in pairs(UnitConditionsOf(_action)) do
                        if (unit ~= "@" and unit ~= "hover" and UnitConditionIsOn(unit)) then
                            return true;
                        end
                    end
                end
                return false;
            end
        );

        --- 이 메뉴가 답할 수 있는 유닛인가. `"@"`는 대상 메뉴가, `"hover"`는 hover 메뉴가
        --- 편집한다 - 여기서 건드리면 **안 보여주는 조건이 여기서 바뀐다.**
        local function isListedUnit(unit)
            return unit ~= "@" and unit ~= "hover";
        end

        local function listedUnitsWithCondition()
            local units;
            if (UnitConditionsOf(_action)) then
                for unit in pairs(UnitConditionsOf(_action)) do
                    if (isListedUnit(unit) and UnitConditionIsOn(unit)) then
                        units = units or {};
                        tinsert(units, unit);
                    end
                end
            end
            return units;
        end

        description:CreateRadio(LLL["DISABLE_ALL"],
            function()
                return listedUnitsWithCondition() == nil;
            end,
            function()
                -- **끄기만 한다.** 골라둔 반응·생사는 그 자리에 남는다 - 되돌렸을 때 처음부터
                -- 다시 고르게 만들 이유가 없다.
                --
                -- 이름을 먼저 모으는 이유: 끄는 쪽이 기억할 축이 없는 항목을 지우고, 마지막
                -- 하나가 지워지면 `units` 자체가 nil이 된다. 그 표를 돌면서 하면
                -- 순회하던 표가 사라진다.
                local units = listedUnitsWithCondition();
                if (units) then
                    for i = 1, #units do
                        SetUnitConditionMode(units[i], "off");
                    end
                end
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );

        -- if (_action.type == Constants.SPELL or _action.type == Constants.ITEM or _action.type == Constants.TARGET or _action.type == Constants.FOCUS or _action.type == Constants.TOGGLEMENU) then
        --     CreateUnitConditionSubmenu(description, "SELECTED_TARGET_UNIT_EMPTY", "@");
        -- end

        for _, unit in ipairs(SORTED_UNIT_LIST) do
            -- `"hover"` is out. `Hovering Over Unit Frame` edits the very same key now, and it is
            -- the one that stays because `frameTypes` and `ignoreHoverUnit` only fit there --
            -- those describe the frame, not the unit on it. Two rows onto one key would be two
            -- ways to say one thing again, which is what the fold just removed.
            if (not (unit == "player" or unit == "none" or unit == "hover")) then
                local unitInfo = DebindUI.UNIT_INFO[unit];
                if (unitInfo.checkedUnit ~= false) then
                    CreateUnitConditionSubmenu(description, unitInfo.name, unit);
                end
            end
        end
    end

    local function CreateGroupConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_GROUP", "groups");
        AppendDisable(description, "CONDITION_GROUP", "groups");
        AppendCheckboxes(description, "groups", {
            { text = LLL["GROUP_NONE"],  value = Constants.GROUP_NONE },
            { text = LLL["GROUP_PARTY"], value = Constants.GROUP_PARTY },
            { text = LLL["GROUP_RAID"],  value = Constants.GROUP_RAID },
        });
    end

    local function CreateIsKnownConditionMenu(rootDescription)
        if (_action.type ~= Constants.SPELL) then
            return;
        end
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_KNOWN", "known");
        description:CreateCheckbox(
            LLL["CONDITION_KNOWN_YES"],
            function ()
                return _action.conditions ~= nil and _action.conditions.known == true;
            end,
            function ()
                if (_action.conditions and _action.conditions.known) then
                    _action.conditions.known = nil;
                    PruneConditions(_action);
                else
                    TableFor(_action, "known", true).known = true;
                end
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        )
    end

    local function CreateCombatConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_COMBAT", "combat");
        AppendDisableYesNo(description, "CONDITION_COMBAT", "combat");
    end

    local function CreateShapeshiftConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_SHAPESHIFT", "forms");
        AppendDisable(description, "CONDITION_SHAPESHIFT", "forms");
        AppendCheckboxes(description, "forms", range(0, 10, function(formId)
            local shapeshiftName;
            if (formId == 0) then
                shapeshiftName = LLL["NO_SHAPESHIFT"];
            else
                local _, _, _, spellID = GetShapeshiftFormInfo(formId);
                shapeshiftName = spellID and GetSpellNameAndIconID(spellID) or nil;
            end
            local label = format("[form:%d]", formId);
            if (shapeshiftName) then
                label = format("%s (%s)", label, shapeshiftName);
            end
            return { text = label, value = 2 ^ formId };
        end));
    end

    local function CreateStealthConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_STEALTH", "stealth");
        AppendDisableYesNo(description, "CONDITION_STEALTH", "stealth");
    end

    local function CreatePetConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_PET", "pet");
        AppendDisableYesNo(description, "CONDITION_PET", "pet");
    end

    local function CreatePetBattleConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_PETBATTLE", "petbattle");
        AppendDisableYesNo(description, "CONDITION_PETBATTLE", "petbattle");
    end

    local function CreateActionbarConditionMenu(rootDescription)
        if (BONUSBAR_NAMES == nil) then
            BONUSBAR_NAMES = {
                [0] = LLL["DEFAULT"],
                [5] = GetFlyoutInfo(229)
            };
            if (Constants.PLAYER_CLASS == "DRUID") then
                BONUSBAR_NAMES[1] = GetSpellNameAndIconID(768);
                BONUSBAR_NAMES[3] = GetSpellNameAndIconID(5487);
                BONUSBAR_NAMES[4] = GetSpellNameAndIconID(24858);
            elseif (Constants.PLAYER_CLASS == "ROGUE") then
                BONUSBAR_NAMES[1] = GetSpellNameAndIconID(1784);
            end
        end

        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_ACTIONBARS", nil,
            -- isActive
            function()
                -- `_action.bars`는 아무도 안 쓰는 필드였다. `KEYS_TO_SAVE`에 없어 늘 nil이라
                -- 이 절은 죽어 있었고, 나머지 셋이 같은 답을 낸다.
                local c = _action.conditions;
                return c ~= nil and (c.bonusbars ~= nil or c.specialbar ~= nil or c.extrabar ~= nil);
            end
        );

        local bonusbarDescription = CreateActionMenuItemGroup(description, "CONDITION_BONUSBAR", "bonusbars");
        AppendDisable(bonusbarDescription, "CONDITION_BONUSBAR", "bonusbars");
        AppendCheckboxes(bonusbarDescription, "bonusbars", range(0, Constants.MAX_BONUSBAR_OFFSET, function(offset)
            local name = BONUSBAR_NAMES[offset];
            local label = format("[bonusbar:%d]", offset);
            if (name) then
                label = format("%s (%s)", label, name);
            end
            return { text = label, value = 2 ^ offset };
        end));

        local specialbarDescription = CreateActionMenuItemGroup(description, "CONDITION_SPECIALBAR", "specialbar");
        AppendDisableYesNo(specialbarDescription, "CONDITION_SPECIALBAR", "specialbar");

        local extrabarDescription = CreateActionMenuItemGroup(description, "CONDITION_EXTRABAR", "extrabar");
        AppendDisableYesNo(extrabarDescription, "CONDITION_EXTRABAR", "extrabar");
    end

    local function CreateSwitchConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_CUSTOM_STATES", nil,
            -- isActive
            -- **조건 표에 스위치 이름이 하나라도 있느냐.** 다섯 번호를 돌던 자리인데, 이 갈래가
            -- 켜져 보이느냐는 액션에 실제로 걸린 것을 따라가야 한다 - 다섯 밖의 이름이 걸린
            -- 액션이 "조건 없음"으로 보이면 그 조건을 지울 자리가 화면에서 사라진다.
            function()
                local conditions = _action.conditions;
                if (conditions) then
                    for name in pairs(conditions) do
                        if (Constants.IsSwitchName(name)) then
                            return true;
                        end
                    end
                end
                return false;
            end,
            -- error
            -- **다른 조건 묶음과 같은 자리다.** 저쪽은 갈래 이름이 곧 이슈 갈래라 헬퍼가
            -- 알아서 `GetBindingIssue(_action, key)`를 묻는데, 스위치 조건은 갈래 키가 아니라
            -- **이름마다 따로**라 물을 키가 없다. 그래서 답을 여기서 만들어 넘긴다.
            --
            -- **본문 오타로는 안 빨개진다.** `GetUndefinedSwitch`는 매크로 본문과
            -- 켜기/끄기/전환의 대상까지 같이 답하므로, 그걸 쓰면 조건은 멀쩡한데 이 칸이
            -- 빨개져서 고칠 곳을 엉뚱한 데로 가리킨다. 조건만 보는 문이 따로 있다.
            function()
                local name = _action and DebindPrivate.GetUndefinedSwitchCondition(_action);
                if (name) then
                    return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], name);
                end
            end,
            -- 설명은 **명시적으로** 찍어 넘긴다. 안 넘기면 `CONDITION_CUSTOM_STATES_DESC`를
            -- 찾아가는데, 그건 `CUSTOM_STATES_DESC`와 글자 하나 다르지 않은 문단이었다. 같은
            -- 말을 로케일마다 두 번 번역하게 만드는 자리라 키를 없애고 이쪽으로 붙였다.
            -- 저쪽 키는 초상화의 스위치 단추 툴팁이었고, 3c가 그 단추를 걷은 뒤로는
            -- `Switches` 탭 자신의 툴팁이다(`DebindUI.lua`의 `PANELS`).
            LLL["CUSTOM_STATES_DESC"]
        );

        -- **Only switches that exist** (2026-08-21, 소유자). A condition on a name nothing defines
        -- matches on neither `true` nor `false`, so the key it is on never fires. Offering a name to
        -- hang one on was offering a dead end.
        --
        -- **The dead end is marked, and that is not a reason to offer it.** `GetUndefinedSwitch`
        -- reads condition keys as well as bodies and targets, so such an action goes red and drops
        -- out of `KeyMap` (`Misc.lua`). The mark is there for the ways a name goes undefined *after*
        -- the condition was hung - a switch deleted, a string from someone else - and a list that
        -- lets the reader build one on purpose is a list that manufactures work for it.
        --
        -- **Making one is at the bottom of this list**, which is not the same thing: a name typed
        -- there gets a definition before the condition goes on, so nothing here ever hangs a
        -- condition on a name nothing defines.
        --
        -- **Plus whatever this action already names**, defined or not, because taking a condition
        -- off is done here and nowhere else. A switch deleted while an action still names it would
        -- otherwise leave that condition on the action with no way to reach it, which is worse than
        -- the dead end this list just stopped offering.
        local switchNames = DebindPrivate.GetSwitchNames();
        local conditions = _action and _action.conditions;
        if (conditions) then
            for name in pairs(conditions) do
                if (Constants.IsSwitchName(name) and not DebindPrivate.ResolveSwitchDefinition(name)) then
                    switchNames[#switchNames + 1] = name;
                end
            end
            sort(switchNames);
        end

        -- **이름마다 자기 답을 낸다.** 헬퍼가 `error(key)`로 그 묶음의 키를 넘겨주므로 함수
        -- 하나면 되고, 줄마다 클로저를 만들 이유가 없다. 위 묶음이 빨개지는 것은 "이 액션에
        -- 끊긴 조건이 있다"이고, 여기가 빨개지는 것은 **어느 것인지**다.
        local function UndefinedSwitchError(name)
            if (not DebindPrivate.ResolveSwitchDefinition(name)) then
                return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], name);
            end
        end

        for _, stateName in ipairs(switchNames) do
            local stateDescription = CreateActionMenuItemGroup(description, stateName, stateName,
                nil, -- isActive: 키로 조건 표를 읽는 기본 판정이 맞다
                UndefinedSwitchError);
            AppendDisableYesNo(stateDescription, "CONDITION_CUSTOM_STATE", stateName);
        end

        -- **만드는 자리가 여기에도 있다** (§6-2). 조건을 걸려고 이 메뉴를 연 사람은 이미
        -- "이 액션이 언제 나갈지"를 생각하고 있고, 그 자리에서 스위치가 없다는 것을 안다.
        -- 창을 닫고 탭으로 건너가서 만들고 돌아와 다시 이 메뉴를 여는 왕복이 이 기능을 아무도
        -- 안 쓰는 이유로 지목된 하나다.
        --
        -- **만들고 나서 그 조건을 바로 켠다.** 만들기만 하면 방금 지나온 자리를 한 번 더
        -- 지나야 하고, 이름을 적은 사람이 원한 것은 정의가 아니라 이 액션에 걸린 조건이다.
        if (_action) then
            local action = _action;
            local newDescription = description:CreateButton(LLL["SWITCH_CREATE"], function()
                DebindUI.ShowNewSwitchBox(function(name)
                    action.conditions = action.conditions or {};
                    action.conditions[name] = true;
                    -- **`onActionValueChanged`가 아니라 손으로 편다.** 저건 파일 단위 `_action`을
                    -- 읽는데, 팝업이 답할 때쯤에는 그 값이 다른 행의 메뉴 것으로 바뀌어 있을 수
                    -- 있다. 조건이 하나 붙으면 순서 규칙이 달라지므로 번호는 다시 매겨야 한다.
                    DebindPrivate.RenumberKeyGroupForAction(action);
                    DebindPrivate.UpdateBindings();
                end);
            end);
            SetInstructionTooltip(newDescription, LLL["SWITCH_CREATE_DESC"]);
        end
    end

    --- 집 편집기 같은 바인딩 컨텍스트가 가져간 키는 기본적으로 우리가 내준다. 편집기가
    --- 자기 버튼과 안내 문구에 그 키를 그려주기 때문에, 우리가 먹으면 화면에 떠 있는
    --- 단축키가 안 먹는 상태가 된다. 그래도 그 키를 쓰겠다는 유저를 위한 통로다.
    local function CreateKeepInBindingContextMenuItem(rootDescription)
        local description = rootDescription:CreateCheckbox(LLL["KEEP_IN_BINDING_CONTEXT"], actionValueEquals,
            setActionValue, { key = "keepInBindingContext", value = USE_CHECKED_VALUE });
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
    local function CreateImportanceMenu(rootDescription)
        -- `rawget`이라 없으면 nil이다(로케일 표의 __index를 건너뛴다). 이어붙이기 전에
        -- 갈라서 둔다 - 번역본 한 줄이 빠졌다고 메뉴가 통째로 터지면 안 된다.
        local instruction = rawget(LLL, "IMPORTANCE_DESC");
        local layer = _elementData.layer and DebindPrivate.GetProfileLayer(_elementData.layer);
        if (layer and not layer.isCharacterSpecific) then
            local warning = LLL["IMPORTANCE_SHARED_WARNING"];
            instruction = instruction and (instruction .. "|n|n" .. warning) or warning;
        end

        local description = CreateActionMenuItemGroup(rootDescription, "IMPORTANCE", "priority",
            -- isActive
            function()
                return _action.priority ~= nil and _action.priority ~= Constants.DEFAULT_IMPORTANCE;
            end,
            nil, instruction
        );

        for i = Constants.MIN_IMPORTANCE, Constants.MAX_IMPORTANCE do
            -- 저장할 값으로 바꾸는 것은 Ordering.lua 한 군데다. 기본값을 nil로 접는 규칙이
            -- 여기에도 손으로 적혀 있었는데, 같은 규칙이 두 군데 있으면 한쪽만 바뀐다.
            local value = DebindPrivate.ImportanceToStored(i);
            description:CreateRadio(LLL["IMPORTANCE" .. i],
                function()
                    return _action.priority == value or _action.priority == i;
                end,
                function()
                    _action.priority = value;
                    onActionValueChanged();
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
        optionsDescription:CreateTitle(MenuUtil.GetElementText(optionsDescription));

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
                SetErrorTooltip(description, LLL["MOVE_TO_CURRENT_TAB_BLOCKED"]);
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

    local function CreateDeleteMenu(rootDescription)
        rootDescription:CreateButton(LLL["DELETE"], function()
            DebindUI.ShowDeleteConfirmationPopup(_elementData);
        end);
    end



    function DebindUI.SetupEditDropdownMenu(dropdown, rootDescription, elementData)
        _elementData = elementData;
        _action = elementData.action;

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
            if (_action.arrivalID) then
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
        if (_action.arrivalID) then
            CreateAssignKeyMenuItem(rootDescription);
            CreateApproveImportMenuItem(rootDescription, { _action });
            CreateRejectImportMenuItem(rootDescription, { _action });
            return;
        end

        -- **First, because on a fresh one it is the only thing worth doing.** The picker adds an
        -- on/off/toggle action with no target (§6-C), so the reader arrives here at a red row that
        -- does nothing, and what fixes it is this box.
        CreateSetSwitchMenuItem(rootDescription);

        CreateConvertToMacroTextMenuItem(rootDescription);

        EditMacroTextMenuItem(rootDescription);

        CreateAssignKeyMenuItem(rootDescription);

        CreateUnbindMenuItem(rootDescription);

        CreateTargetUnitMenuItem(rootDescription);

        --
        -- Special Conditions
        --
        rootDescription:CreateDivider();
        rootDescription:CreateTitle(LLL["SPECIAL_CONDITIONS"]);

        CreateHoverMenu(rootDescription);

        CreateUnitConditionMenu(rootDescription);

        CreateGroupConditionMenu(rootDescription);

        CreateIsKnownConditionMenu(rootDescription);

        CreateCombatConditionMenu(rootDescription);

        CreateShapeshiftConditionMenu(rootDescription);

        CreateStealthConditionMenu(rootDescription);

        CreatePetConditionMenu(rootDescription);

        CreatePetBattleConditionMenu(rootDescription);

        CreateActionbarConditionMenu(rootDescription);

        CreateSwitchConditionMenu(rootDescription);

        --
        -- Other Options
        --
        rootDescription:CreateDivider();
        rootDescription:CreateTitle(LLL["OTHER_OPTIONS"]);

        CreateKeepInBindingContextMenuItem(rootDescription);

        CreateImportanceMenu(rootDescription);

        CreateMoveCopyMenu(rootDescription, false, _elementData.layer, function(destLayerID, isCopy)
            DebindUI.MoveAction(_elementData, destLayerID, isCopy);
        end);

        CreateMoveCopyMenu(rootDescription, true, _elementData.layer, function(destLayerID, isCopy)
            DebindUI.MoveAction(_elementData, destLayerID, isCopy);
        end);

        CreateDeleteMenu(rootDescription);
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
        -- 편집 메뉴가 쓰는 것들이다. 이 메뉴는 안 쓰므로 비워둔다 - 남아 있으면 여기서
        -- 지나간 값을 다음 편집 메뉴가 물려받는다(`SetupBulkDropdownMenu`와 같은 이유).
        _elementData = nil;
        _action = nil;

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
        -- 편집 메뉴가 쓰는 것들이다. 이 메뉴는 안 쓰므로 비워둔다 - 남아 있으면 여기서
        -- 지나간 값을 다음 편집 메뉴가 물려받는다(`SetupOrderDropdownMenu`와 같은 이유).
        _elementData = nil;
        _action = nil;

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
        -- 단일 메뉴가 쓰는 것들이다. 벌크에서는 겨눈 것이 하나가 아니므로 비워둔다 - 남아
        -- 있으면 이 메뉴가 안 쓰는 값을 다음 단일 메뉴가 물려받는다.
        _elementData = nil;
        _action = nil;

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
        -- 편집 메뉴가 쓰는 것들이다. 이 메뉴는 안 쓰므로 비워둔다 - 남아 있으면 여기서
        -- 지나간 값을 다음 편집 메뉴가 물려받는다(`SetupBulkDropdownMenu`와 같은 이유).
        _elementData = nil;
        _action = nil;

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
        -- 편집 메뉴가 쓰는 것들이다. 이 메뉴는 안 쓰므로 비워둔다 - 남아 있으면 여기서
        -- 지나간 값을 다음 편집 메뉴가 물려받는다(`SetupBulkDropdownMenu`와 같은 이유).
        _elementData = nil;
        _action = nil;

        rootDescription:CreateTitle(entry.name);
        rootDescription:CreateTitle(LLL["SPELL_PICKER_ADD_TO"]);

        local currentLayerID = DebindUI.GetLayerID();

        local func = function(args)
            -- The row's own click carries this guard too: combat can start while the menu stands.
            if (InCombatLockdown()) then
                return;
            end
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
end
