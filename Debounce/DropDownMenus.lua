local _, DebouncePrivate    = ...;
local Constants             = DebouncePrivate.Constants;
local LLL                   = DebouncePrivate.L;
local DebounceUI            = DebouncePrivate.DebounceUI;

local dump                  = DebouncePrivate.dump

local BINDING_TYPE_NAMES    = DebounceUI.BINDING_TYPE_NAMES;
local SEPARATOR             = { isSeparator = true, };
local ARRAY_MARKER          = {};
-- 유닛 순서는 Conditions.lua가 갖는다 - 툴팁·조건 탭도 같은 순서를 써야 한다.
local SORTED_UNIT_LIST      = DebouncePrivate.SORTED_UNIT_LIST;
local USE_CHECKED_VALUE     = {};


local BINDING_CATEGORIES;
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

local function _isSelected(data)
    local targetObj = data.targetObj;
    local value = data.value;
    if (value == USE_CHECKED_VALUE) then
        return targetObj[data.key] and true or false;
    else
        return targetObj[data.key] == value;
    end
end

local function _setSelected(data)
    local targetObj = data.targetObj;
    local value = data.value;
    if (value == USE_CHECKED_VALUE) then
        targetObj[data.key] = not targetObj[data.key];
    else
        targetObj[data.key] = value;
    end
    DebouncePrivate.UpdateBindings();
    return MenuResponse.Refresh;
end

local function SetInstrcutionTooltip(description, text)
    description:SetTooltip(function(tooltip, elementDescription)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
        GameTooltip_AddInstructionLine(tooltip, text);
    end);
end

local function SetErrorTooltip(description, text)
    description:SetTooltip(function(tooltip, elementDescription)
        GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
        GameTooltip_AddErrorLine(tooltip, text);
    end);
end


--------------------------------------------------------------------------------
-- AddDropDown_Initialize
--------------------------------------------------------------------------------
local function BuildBindingCategories()
    if (BINDING_CATEGORIES) then
        return;
    end

    local bindingsCategories = {};
    local nextOrder = 1;
    local function AddBindingCategory(key)
        if not bindingsCategories[key] then
            bindingsCategories[key] = { order = nextOrder, bindings = {} };
            nextOrder = nextOrder + 1;
        end
    end

    AddBindingCategory(BINDING_HEADER_MOVEMENT);
    AddBindingCategory(BINDING_HEADER_INTERFACE);
    -- AddBindingCategory(BINDING_HEADER_ACTIONBAR);
    -- AddBindingCategory(BINDING_HEADER_MULTIACTIONBAR);
    AddBindingCategory(BINDING_HEADER_CHAT);
    AddBindingCategory(BINDING_HEADER_TARGETING);
    AddBindingCategory(BINDING_HEADER_RAID_TARGET);
    AddBindingCategory(BINDING_HEADER_VEHICLE);
    AddBindingCategory(BINDING_HEADER_CAMERA);
    AddBindingCategory(BINDING_HEADER_MISC);
    AddBindingCategory(BINDING_HEADER_OTHER);

    local ignoredCategories = {
        -- BINDING_HEADER_ACTIONBAR = true,
        -- BINDING_HEADER_ACTIONBAR2 = true,
        -- BINDING_HEADER_ACTIONBAR3 = true,
        -- BINDING_HEADER_ACTIONBAR4 = true,
        -- BINDING_HEADER_ACTIONBAR5 = true,
        -- BINDING_HEADER_ACTIONBAR6 = true,
        -- BINDING_HEADER_ACTIONBAR7 = true,
        -- BINDING_HEADER_ACTIONBAR8 = true,
        -- BINDING_HEADER_MULTIACTIONBAR = true,
    };

    for bindingIndex = 1, GetNumBindings() do
        local action, cat = GetBinding(bindingIndex);
        if not cat then
            tinsert(bindingsCategories[BINDING_HEADER_OTHER].bindings, { bindingIndex, action, _G["BINDING_NAME_" .. action] });
        else
            if (not ignoredCategories[cat] and cat ~= "ADDONS") then
                cat = _G[cat] or cat;
                AddBindingCategory(cat);
                if strsub(action, 1, 6) == "HEADER" then
                    --tinsert(bindingsCategories[cat].bindings, KeybindingSpacer);
                else
                    tinsert(bindingsCategories[cat].bindings, { bindingIndex, action, _G["BINDING_NAME_" .. action] });
                end
            end
        end
    end

    BINDING_CATEGORIES = {};
    for cat, bindingCategory in pairs(bindingsCategories) do
        BINDING_CATEGORIES[bindingCategory.order] = { cat = cat, bindings = bindingCategory.bindings };
    end
end

function DebounceUI.SetupAddDropdownMenu(dropdown, rootDescription)
    BuildBindingCategories();

    --GenerateMenu(dropdown, rootDescription, rootMenu);
    local description;

    description = rootDescription:CreateButton(BINDING_TYPE_NAMES[Constants.MACROTEXT], function()
        DebounceIconSelectorFrame.mode = IconSelectorPopupFrameModes.New;
        DebounceIconSelectorFrame:Show();
    end);
    SetInstrcutionTooltip(description, LLL["TYPE_MACROTEXT_DESC"]);

    description = rootDescription:CreateButton(BINDING_TYPE_NAMES[Constants.SETCUSTOM]);
    SetInstrcutionTooltip(description, LLL["TYPE_SETCUSTOM_DESC"]);
    for i = 1, 2 do
        local childDescription = description:CreateButton(LLL["TYPE_SETCUSTOM" .. i], function()
            DebounceFrame:AddNewAction(Constants.SETCUSTOM, i);
        end);
    end

    description = rootDescription:CreateButton(BINDING_TYPE_NAMES[Constants.SETSTATE]);
    SetInstrcutionTooltip(description, LLL["TYPE_SETSTATE_DESC"]);
    for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
        local childDescription = description:CreateButton(format(LLL["CUSTOM_STATE_NUM"], stateIndex));
        childDescription:CreateButton(LLL["CUSTOM_STATE_TOGGLE"], function()
            DebounceFrame:AddNewAction(Constants.SETSTATE, bit.bor(Constants.SETCUSTOM_MODE_TOGGLE, stateIndex));
        end);
        childDescription:CreateButton(LLL["CUSTOM_STATE_TURN_ON"], function()
            DebounceFrame:AddNewAction(Constants.SETSTATE, bit.bor(Constants.SETCUSTOM_MODE_ON, stateIndex));
        end);
        childDescription:CreateButton(LLL["CUSTOM_STATE_TURN_OFF"], function()
            DebounceFrame:AddNewAction(Constants.SETSTATE, bit.bor(Constants.SETCUSTOM_MODE_OFF, stateIndex));
        end);
    end

    description = rootDescription:CreateButton(BINDING_TYPE_NAMES[Constants.COMMAND]);
    for i = 1, #BINDING_CATEGORIES do
        local bindingCategory = BINDING_CATEGORIES[i];
        local childDescription = description:CreateButton(bindingCategory.cat);
        for j = 1, #bindingCategory.bindings do
            local binding = bindingCategory.bindings[j];
            childDescription:CreateButton(binding[3], function()
                DebounceFrame:AddNewAction(Constants.COMMAND, binding[2]);
            end);
        end
    end

    description = rootDescription:CreateButton(LLL["MISC"]);
    for _, type in ipairs({ Constants.TARGET, Constants.FOCUS, Constants.TOGGLEMENU }) do
        local childDescription = description:CreateButton(BINDING_TYPE_NAMES[type]);
        for _, unit in ipairs(SORTED_UNIT_LIST) do
            local unitInfo = DebounceUI.UNIT_INFO[unit];
            if (unitInfo[type] ~= false) then
                childDescription:CreateButton(unitInfo.name, function()
                    DebounceFrame:AddNewAction(type, nil, nil, nil, { unit = unit });
                end);
            end
        end
    end

    do
        local childDescription = description:CreateButton(BINDING_TYPE_NAMES[Constants.WORLDMARKER]);
        for i = 1, NUM_WORLD_RAID_MARKERS do
            local index = WORLD_RAID_MARKER_ORDER[i];
            childDescription:CreateButton(_G["WORLD_MARKER" .. index], function()
                DebounceFrame:AddNewAction(Constants.WORLDMARKER, index);
            end);
        end
    end

    do
        local childDescription = description:CreateButton(BINDING_TYPE_NAMES[Constants.UNUSED], function()
            DebounceFrame:AddNewAction(Constants.UNUSED);
        end);
        SetInstrcutionTooltip(childDescription, LLL["TYPE_UNUSED_DESC"]);
    end
end

--------------------------------------------------------------------------------
-- CustomStatesDropDown
--------------------------------------------------------------------------------
function DebounceUI.SetupCustomStatesDropdownMenu(dropdown, rootDescription)
    --GenerateMenu(dropdown, rootDescription, rootMenu);

    for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
        local stateOptions = DebouncePrivate.GetCustomStateOptions(stateIndex);
        local stateDescription = rootDescription:CreateButton(format(LLL["CUSTOM_STATE_NUM"], stateIndex));
        stateDescription:CreateTitle(MenuUtil.GetElementText(stateDescription));

        do
            local manualDescription = stateDescription:CreateRadio(LLL["CUSTOM_STATE_MODE_MANUAL"], _isSelected, _setSelected, { targetObj = stateOptions, key = "mode", value = Constants.CUSTOM_STATE_MODES.MANUAL });
            SetInstrcutionTooltip(manualDescription, LLL["CUSTOM_STATE_MODE_MANUAL_INSTRUCTION"]);

            manualDescription:CreateTitle(MenuUtil.GetElementText(manualDescription));
            manualDescription:CreateRadio(LLL["CUSTOM_STATE_ON"], _isSelected, _setSelected, { targetObj = stateOptions, key = "value", value = true });
            manualDescription:CreateRadio(LLL["CUSTOM_STATE_OFF"], _isSelected, _setSelected, { targetObj = stateOptions, key = "value", value = false });

            manualDescription:CreateDivider();
            manualDescription:CreateTitle(LLL["CUSTOM_STATE_INITIAL_VALUE"]);

            manualDescription:CreateRadio(LLL["CUSTOM_STATE_REMEMBER"], _isSelected, _setSelected, { targetObj = stateOptions, key = "initialValue", value = nil });
            manualDescription:CreateRadio(LLL["CUSTOM_STATE_LOGIN_ON"], _isSelected, _setSelected, { targetObj = stateOptions, key = "initialValue", value = true });
            manualDescription:CreateRadio(LLL["CUSTOM_STATE_LOGIN_OFF"], _isSelected, _setSelected, { targetObj = stateOptions, key = "initialValue", value = false });
        end

        do
            local conditionalDescription = stateDescription:CreateRadio(LLL["CUSTOM_STATE_MODE_MACRO_CONDITIONAL"], _isSelected, _setSelected,
                { targetObj = stateOptions, key = "mode", value = Constants.CUSTOM_STATE_MODES.MACRO_CONDITIONAL });
            SetInstrcutionTooltip(conditionalDescription, LLL["CUSTOM_STATE_MODE_MACRO_CONDITIONAL_DESC"]);

            conditionalDescription:CreateTitle(MenuUtil.GetElementText(conditionalDescription));
            conditionalDescription:CreateButton(LLL["CUSTOM_STATE_EDIT_VALUE"], function()
                DebounceUI.ShowInputBox({
                    text = LLL["CUSTOM_STATE_EDIT_VALUE_DESC"],
                    callback = function(value)
                        value = strtrim(value);
                        if (value == "") then
                            value = nil;
                        end
                        stateOptions.expr = value;
                        if (stateOptions.mode == Constants.CUSTOM_STATE_MODES.MACRO_CONDITIONAL) then
                            DebouncePrivate.UpdateBindings();
                        end
                    end,
                    maxLetters = 100,
                    currentValue = stateOptions.expr,
                });
            end);
        end

        stateDescription:CreateDivider();
        stateDescription:CreateCheckbox(LLL["CUSTOM_STATE_DISPLAY_MESSAGE"], _isSelected, _setSelected, { targetObj = stateOptions, key = "displayMessage", value = USE_CHECKED_VALUE });
    end
end

--------------------------------------------------------------------------------
-- OptionsDropDown
--------------------------------------------------------------------------------
function DebounceUI.SetupOptionsDropdownMenu(dropdown, rootDescription)
    do
        -- 목록의 배열 순서는 더 이상 사용자가 만지는 것이 아니라서(재배치 드래그를 없앴다)
        -- 무엇으로 정렬해 보여줄지를 여기서 고른다.
        local sortDescription = rootDescription:CreateButton(LLL["SORT_LIST_BY"]);

        local function CreateSortRadio(mode, label, desc)
            local radio = sortDescription:CreateRadio(label, function()
                return (DebouncePrivate.Options.mainListSort or "key") == mode;
            end, function()
                DebouncePrivate.Options.mainListSort = (mode ~= "key") and mode or nil;
                DebounceUI.NotifyMainListSortChanged(mode);
                return MenuResponse.Refresh;
            end);
            SetInstrcutionTooltip(radio, desc);
        end

        CreateSortRadio("key", LLL["SORT_LIST_BY_KEY"], LLL["SORT_LIST_BY_KEY_DESC"]);
        CreateSortRadio("name", LLL["SORT_LIST_BY_NAME"], LLL["SORT_LIST_BY_NAME_DESC"]);
    end

    do
        local unitframeDescription = rootDescription:CreateButton(LLL["UNITFRAME_OPTIONS"]);
        if (DebouncePrivate.CliqueDetected) then
            SetErrorTooltip(unitframeDescription, LLL["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"]);
            unitframeDescription:SetEnabled(false);
        end

        local useMouseDownDescription = unitframeDescription:CreateCheckbox(LLL["UNITFRAME_TRIGGER_ON_MOUSE_DOWN"], function()
            return DebouncePrivate.Options.unitframeUseMouseDown;
        end, function()
            DebouncePrivate.Options.unitframeUseMouseDown = not DebouncePrivate.Options.unitframeUseMouseDown;
            DebouncePrivate.ApplyOptions("unitframeUseMouseDown");
            return MenuResponse.Refresh;
        end);
        SetInstrcutionTooltip(useMouseDownDescription, LLL["UNITFRAME_TRIGGER_ON_MOUSE_DOWN_DESC"]);

        unitframeDescription:CreateDivider();

        local framesDescription = unitframeDescription:CreateButton(LLL["BLIZZARD_UNIT_FRAMES"]);
        for _, frameType in ipairs({ "player", "pet", "target", "party", "raid", "boss", "arena" }) do
            framesDescription:CreateCheckbox(LLL["BLIZZARD_UNIT_FRAMES_" .. strupper(frameType)], function()
                return DebouncePrivate.Options.blizzframes[frameType] ~= false;
            end, function()
                DebouncePrivate.Options.blizzframes[frameType] = not (DebouncePrivate.Options.blizzframes[frameType] ~= false);
                DebouncePrivate.UpdateBlizzardFrames();
                return MenuResponse.Refresh;
            end);
        end
    end

    do
        local specialUnitsDescription = rootDescription:CreateButton(LLL["SPECIAL_UNITS"]);
        local excludePlayerDescription = specialUnitsDescription:CreateButton(LLL["EXCLUDE_PLAYER"]);
        SetInstrcutionTooltip(excludePlayerDescription, LLL["EXCLUDE_PLAYER_DESC"]);
        for _, unit in ipairs({ "tank", "healer", "maintank", "mainassist" }) do
            excludePlayerDescription:CreateCheckbox(DebounceUI.UNIT_INFO[unit].name, function()
                return DebouncePrivate.Options.excludePlayer and DebouncePrivate.Options.excludePlayer[unit];
            end, function()
                if (not DebouncePrivate.Options.excludePlayer) then
                    DebouncePrivate.Options.excludePlayer = {};
                end
                DebouncePrivate.Options.excludePlayer[unit] = not DebouncePrivate.Options.excludePlayer[unit];
                local header = DebouncePrivate.GetUnitWatchHeader(unit);
                if (header) then
                    header:SetAttribute("showPlayer", not DebouncePrivate.Options.excludePlayer[unit]);
                end
                return MenuResponse.Refresh;
            end);
        end
    end

    do
        local stateDriverUpdateThrottleDescription = rootDescription:CreateButton(LLL["STATE_DRIVER_UPDATE_THROTTLE"]);
        -- stateDriverUpdateThrottleDescription:CreateCheckbox(LLL["STATE_DRIVER_UPDATE_THROTTLE_DISABLE"], function()
        --     return DebouncePrivate.Options.removeStateDriverUpdateThrottle and true or false;
        -- end, function()
        --     DebouncePrivate.Options.removeStateDriverUpdateThrottle = (not DebouncePrivate.Options.removeStateDriverUpdateThrottle) or nil;
        --     DebouncePrivate.ApplyOptions("removeStateDriverUpdateThrottle");
        --     return MenuResponse.Refresh;
        -- end);
        SetInstrcutionTooltip(stateDriverUpdateThrottleDescription, LLL["STATE_DRIVER_UPDATE_THROTTLE_DESC"]);
        stateDriverUpdateThrottleDescription:SetTooltip(function(tooltip, elementDescription)
            GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(elementDescription));
            GameTooltip_AddInstructionLine(tooltip, LLL["STATE_DRIVER_UPDATE_THROTTLE_DESC"]);
            GameTooltip_AddBlankLineToTooltip(tooltip);
            GameTooltip_AddErrorLine(tooltip, LLL["STATE_DRIVER_UPDATE_THROTTLE_WARNING"]);
        end);

        local sliderDescription = stateDriverUpdateThrottleDescription:CreateTemplate("DebounceStateDriverUpdateThrottleSliderTemplate");
        sliderDescription:AddInitializer(function(frame, description, menu)
            frame:UpdateVisibleState();
        end)
    end

    do
        local addCustomTargetMenusToUnitPopupDescription = rootDescription:CreateCheckbox(LLL["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP"], function()
            return DebouncePrivate.Options.addCustomTargetMenusToUnitPopup and true or false;
        end, function()
            DebouncePrivate.Options.addCustomTargetMenusToUnitPopup = (not DebouncePrivate.Options.addCustomTargetMenusToUnitPopup) or nil;
            DebouncePrivate.ApplyOptions("addCustomTargetMenusToUnitPopup");
            return MenuResponse.Refresh;
        end);
        SetInstrcutionTooltip(addCustomTargetMenusToUnitPopupDescription, LLL["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP_DESC"]);
    end

    -- do
    --     local sliderDescription = rootDescription:CreateTemplate("DebounceStateDriverUpdateThrottleSliderTemplate");
    --     sliderDescription:AddInitializer(function(frame, description, menu)
    --         frame:OnAttach();
    --     end)
    -- end
end

--------------------------------------------------------------------------------
-- EditDropDown_Initialize
--------------------------------------------------------------------------------
do
    local _dropdown, _elementData, _action;

    -- 조건이나 대상이 바뀌면 isConditional/hover가 바뀌어 발동 순서가 움직인다. 목록은
    -- 그 순서대로 그려지므로 다시 만들어야 왼쪽 자리와 상세 패널이 실제 결과를 보여준다.
    local function onActionValueChanged()
        DebounceUI.NotifyActionChanged(_action);
        return MenuResponse.Refresh;
    end

    local function actionValueEquals(args)
        local key, value = args.key, args.value;
        if (value == USE_CHECKED_VALUE) then
            return _action[key] and true or false;
        else
            return _action[key] == value;
        end
    end

    local function setActionValue(args)
        local key, value = args.key, args.value;
        if (value == USE_CHECKED_VALUE) then
            _action[key] = not _action[key];
            onActionValueChanged();
            return MenuResponse.Refresh;
        elseif (_action[key] ~= value) then
            _action[key] = value;
            onActionValueChanged();
            return MenuResponse.Refresh;
        end
    end

    local function _hasBit(data)
        local targetObj = data.targetObj or _action;
        local current = targetObj[data.key] or data.defaultValue or 0;
        return bit.band(current, data.value) == data.value;
    end

    local function _toggleBit(data)
        local targetObj = data.targetObj or _action;
        local current = targetObj[data.key] or data.defaultValue or 0;
        targetObj[data.key] = bit.bxor(current, data.value);
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
            elseif (key) then
                err = DebouncePrivate.GetBindingIssue(_action, key);
            end

            if (err) then
                color = ERROR_COLOR;
                err = rawget(LLL, err) or rawget(LLL, "BINDING_ERROR_" .. err) or error;
            else
                local active = isActive;
                if (active) then
                    if (type(active) == "function") then
                        active = active(key);
                    end
                elseif (key) then
                    active = _action[key] ~= nil;
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

    local function CreateUnitConditionSubmenu(parentDescription, label, unit)
        local optionsDescription = CreateActionMenuItemGroup(parentDescription, label, nil,
            function()
                return _action.checkedUnits and _action.checkedUnits[unit] ~= nil;
            end,
            -- error
            function()
                return DebouncePrivate.GetBindingIssue(_action, "checkedUnits", nil, unit);
            end,
            nil, true);

        local titleDescription = optionsDescription:CreateTitle(MenuUtil.GetElementText(optionsDescription));
        if (unit == "@") then
            optionsDescription:AddInitializer(function(button, elementDescription, menu)
                if (_action.unit and _action.unit ~= "none") then
                    button.fontString:SetText(format(LLL["SELECTED_TARGET_UNIT"], DebounceUI.UNIT_INFO[_action.unit].name));
                else
                    button.fontString:SetText(LLL["SELECTED_TARGET_UNIT_EMPTY"]);
                end
            end);
            optionsDescription:SetEnabled(function()
                return _action.unit and _action.unit ~= "none" and true or false;
            end);

            titleDescription:AddInitializer(function(button, elementDescription, menu)
                if (_action.unit and _action.unit ~= "none") then
                    button.fontString:SetText(format(LLL["SELECTED_TARGET_UNIT"], DebounceUI.UNIT_INFO[_action.unit].name));
                else
                    button.fontString:SetText(LLL["SELECTED_TARGET_UNIT_EMPTY"]);
                end
            end);
        end

        optionsDescription:CreateRadio(LLL["DISABLE"],
            function()
                return not _action.checkedUnits or _action.checkedUnits[unit] == nil;
            end,
            function()
                if (_action.checkedUnits) then
                    _action.checkedUnits[unit] = nil;
                    if (not next(_action.checkedUnits)) then
                        _action.checkedUnits = nil;
                    end
                end
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );

        optionsDescription:CreateRadio(LLL["CONDITION_UNIT_EXISTS"],
            function()
                return _action.checkedUnits and _action.checkedUnits[unit] == true;
            end,
            function()
                _action.checkedUnits = _action.checkedUnits or {};
                _action.checkedUnits[unit] = true;
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );

        optionsDescription:CreateRadio(LLL["CONDITION_UNIT_HELP"],
            function()
                return _action.checkedUnits and _action.checkedUnits[unit] == "help";
            end,
            function()
                _action.checkedUnits = _action.checkedUnits or {};
                _action.checkedUnits[unit] = "help";
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );

        optionsDescription:CreateRadio(LLL["CONDITION_UNIT_HARM"],
            function()
                return _action.checkedUnits and _action.checkedUnits[unit] == "harm";
            end,
            function()
                _action.checkedUnits = _action.checkedUnits or {};
                _action.checkedUnits[unit] = "harm";
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );

        optionsDescription:CreateRadio(LLL["CONDITION_UNIT_DOES_NOT_EXIST"],
            function()
                return _action.checkedUnits and _action.checkedUnits[unit] == false;
            end,
            function()
                _action.checkedUnits = _action.checkedUnits or {};
                _action.checkedUnits[unit] = false;
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );

        return optionsDescription;
    end

    local function hoverConditionIsOn()
        if (DebouncePrivate.CliqueDetected) then
            return false;
        end
        return _action.hover and true or false;
    end

    -- 매크로텍스트 변환과 매크로 편집은 상세 패널의 내용 탭으로 갔다.
    -- 행을 고르면 그 탭이 바로 그 UI다.

    local function CreateUnbindMenuItem(parentDescription)
        local description = parentDescription:CreateButton(LLL["UNBIND"], function()
            _action.key = nil;
            onActionValueChanged();
            return MenuResponse.Refresh;
        end);
        description:SetEnabled(function()
            return _action.key ~= nil;
        end);
    end

    local function CreateTargetUnitMenuItem(parentDescription)
        if not (_action.type == Constants.SPELL or _action.type == Constants.ITEM or _action.type == Constants.TARGET or _action.type == Constants.FOCUS or _action.type == Constants.TOGGLEMENU) then
            return;
        end

        local description = CreateActionMenuItemGroup(parentDescription, "TARGET_UNIT", "unit");

        if (not (_action.type == Constants.TARGET or _action.type == Constants.FOCUS or _action.type == Constants.TOGGLEMENU)) then
            description:CreateRadio(LLL["UNIT_DISABLE"], actionValueEquals, setActionValue, { key = "unit", value = nil });
        end

        for _, unit in ipairs(SORTED_UNIT_LIST) do
            local unitInfo = DebounceUI.UNIT_INFO[unit];
            if (unitInfo[_action.type] ~= false) then
                local unitDescription = description:CreateRadio(unitInfo.name, actionValueEquals, setActionValue, { key = "unit", value = unit });

                -- TODO locale 파일 업데이트 할 것.
                -- local instructionTooltip = rawget(LLL, "TARGET_UNIT_" .. strupper(unit) .. "_DESC") or (unitInfo.type and "TARGET_UNIT_" .. strupper(unitInfo.type) .. "_DESC");
                -- if (instructionTooltip) then
                --     SetInstrcutionTooltip(optionDescription, instructionTooltip);
                -- end

                if (unitInfo.tooltipTitle) then
                    SetInstrcutionTooltip(unitDescription, unitInfo.tooltipTitle);
                end
            end
        end

        description:CreateDivider();
        local childDescription;

        childDescription = description:CreateCheckbox(LLL["ONLY_IF_UNIT_EXISTS"],
            function()
                return _action.checkedUnits and _action.checkedUnits["@"];
            end,
            function()
                local value = not _action.checkedUnits;
                if (_action.checkedUnits and _action.checkedUnits["@"]) then
                    _action.checkedUnits["@"] = nil;
                    if (not next(_action.checkedUnits)) then
                        _action.checkedUnits = nil;
                    end
                else
                    _action.checkedUnits = _action.checkedUnits or {};
                    _action.checkedUnits["@"] = true;
                end
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );
        childDescription:SetEnabled(function()
            return _action.unit and _action.unit ~= "none" and _action.unit ~= "player" and true or false;
        end);

        local function initializer(frame, elementDescription, menu)
            frame.leftTexture1:SetPoint("LEFT", 15, 0);
        end

        local function isEnabled()
            return _action.unit and _action.unit ~= "none" and _action.unit ~= "player" and _action.checkedUnits and _action.checkedUnits["@"] and true or false;
        end


        childDescription = description:CreateRadio(LLL["REACTION_ALL"],
            function()
                return _action.checkedUnits and _action.checkedUnits["@"] == true;
            end,
            function()
                _action.checkedUnits = _action.checkedUnits or {};
                _action.checkedUnits["@"] = true;
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );
        childDescription:AddInitializer(initializer);
        childDescription:SetEnabled(isEnabled);

        childDescription = description:CreateRadio(LLL["REACTION_HELP"],
            function()
                return _action.checkedUnits and _action.checkedUnits["@"] == "help";
            end,
            function()
                _action.checkedUnits = _action.checkedUnits or {};
                _action.checkedUnits["@"] = "help";
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );
        childDescription:AddInitializer(initializer);
        childDescription:SetEnabled(isEnabled);

        childDescription = description:CreateRadio(LLL["REACTION_HARM"],
            function()
                return _action.checkedUnits and _action.checkedUnits["@"] == "harm";
            end,
            function()
                _action.checkedUnits = _action.checkedUnits or {};
                _action.checkedUnits["@"] = "harm";
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );
        childDescription:AddInitializer(initializer);
        childDescription:SetEnabled(isEnabled);

        return description;
    end

    --
    -- 조건 메뉴는 "채우기"와 "어디에 매다는가"가 분리돼 있다. 상세 패널의 조건 탭은
    -- 자기 컨텍스트 메뉴의 뿌리에 바로 채우고, 우클릭 메뉴는 하위 메뉴 버튼에 채운다.
    -- 채우는 쪽은 예전부터 _action 업밸류에 기대고 있으므로 그대로 두고 껍데기만 열었다.
    --

    local function PopulateHoverMenu(description)
        local disable, yes, no = AppendDisableYesNo(description, "CONDITION_HOVER", "hover");
        if (DebouncePrivate.CliqueDetected) then
            yes:SetEnabled(false);
            no:SetEnabled(false);
        end


        description:CreateDivider();
        description:CreateTitle(LLL["CONDITION_REACTIONS"]);

        AppendCheckboxes(description, "reactions", {
                { text = LLL["REACTION_HELP"],  value = Constants["REACTION_HELP"] },
                { text = LLL["REACTION_HARM"],  value = Constants["REACTION_HARM"] },
                { text = LLL["REACTION_OTHER"], value = Constants["REACTION_OTHER"] },
            }, function(elementDescription)
                elementDescription:SetEnabled(hoverConditionIsOn);
            end,
            (Constants["REACTION_HELP"]
                + Constants["REACTION_HARM"]
                + Constants["REACTION_OTHER"])
        );

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
        SetInstrcutionTooltip(ignoreHoverUnit, LLL["IGNORE_HOVER_UNIT_DESC"]);
        ignoreHoverUnit:SetEnabled(hoverConditionIsOn);
    end

    local function PopulateUnitConditionMenu(description)
        description:CreateRadio(LLL["DISABLE_ALL"],
            function()
                return not _action.checkedUnits;
            end,
            function()
                _action.checkedUnits = nil;
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        );

        -- 지정한 대상("@")도 여기서 만진다. 대상 메뉴의 체크박스와 같은 값이고, 대상이
        -- 없으면 스스로 비활성이 된다. 조건 탭에서 이 조건을 열었을 때 "@"만 손댈 수 없는
        -- 구멍이 생기지 않도록 같이 낸다.
        CreateUnitConditionSubmenu(description, "SELECTED_TARGET_UNIT_EMPTY", "@");

        for _, unit in ipairs(SORTED_UNIT_LIST) do
            if (not (unit == "player" or unit == "none")) then
                local unitInfo = DebounceUI.UNIT_INFO[unit];
                if (unitInfo.checkedUnit ~= false) then
                    CreateUnitConditionSubmenu(description, unitInfo.name, unit);
                end
            end
        end
    end

    local function PopulateGroupConditionMenu(description)
        AppendDisable(description, "CONDITION_GROUP", "groups");
        AppendCheckboxes(description, "groups", {
            { text = LLL["GROUP_NONE"],  value = Constants.GROUP_NONE },
            { text = LLL["GROUP_PARTY"], value = Constants.GROUP_PARTY },
            { text = LLL["GROUP_RAID"],  value = Constants.GROUP_RAID },
        });
    end

    local function PopulateIsKnownConditionMenu(description)
        description:CreateCheckbox(
            LLL["CONDITION_KNOWN_YES"],
            function ()
                return _action.known == true;
            end,
            function ()
                if _action.known then
                    _action.known = nil;
                else
                    _action.known = true;
                end
                onActionValueChanged();
                return MenuResponse.Refresh;
            end
        )
    end

    local function PopulateCombatConditionMenu(description)
        AppendDisableYesNo(description, "CONDITION_COMBAT", "combat");
    end

    local function PopulateShapeshiftConditionMenu(description)
        AppendDisable(description, "CONDITION_SHAPESHIFT", "forms");
        AppendCheckboxes(description, "forms", range(0, 10, function(formId)
            return { text = DebouncePrivate.GetShapeshiftFormLabel(formId), value = 2 ^ formId };
        end));
    end

    local function PopulateStealthConditionMenu(description)
        AppendDisableYesNo(description, "CONDITION_STEALTH", "stealth");
    end

    local function PopulatePetConditionMenu(description)
        AppendDisableYesNo(description, "CONDITION_PET", "pet");
    end

    local function PopulatePetBattleConditionMenu(description)
        AppendDisableYesNo(description, "CONDITION_PETBATTLE", "petbattle");
    end

    local function PopulateBonusbarConditionMenu(description)
        AppendDisable(description, "CONDITION_BONUSBAR", "bonusbars");
        AppendCheckboxes(description, "bonusbars", range(0, Constants.MAX_BONUS_ACTIONBAR_OFFSET, function(offset)
            return { text = DebouncePrivate.GetActionBarTypeLabel(offset), value = 2 ^ offset };
        end));
    end

    local function PopulateSpecialbarConditionMenu(description)
        AppendDisableYesNo(description, "CONDITION_SPECIALBAR", "specialbar");
    end

    local function PopulateExtrabarConditionMenu(description)
        AppendDisableYesNo(description, "CONDITION_EXTRABAR", "extrabar");
    end

    local function PopulateCustomStateConditionMenu(description, stateIndex)
        AppendDisableYesNo(description, "CONDITION_CUSTOM_STATE", "$state" .. stateIndex);
    end

    --
    -- 조건 탭이 부를 수 있도록 서술자에 끼워 넣는다. 뿌리에 바로 채우므로 제목은 여기서 단다.
    --
    do
        local function Register(key, populate, arg)
            DebouncePrivate.SetConditionMenuBuilder(key, function(descriptor, rootDescription, action)
                _dropdown = nil;
                _elementData = nil;
                _action = action;
                rootDescription:CreateTitle(descriptor.label);
                populate(rootDescription, arg);
            end);
        end

        Register("hover", PopulateHoverMenu);
        Register("checkedUnits", PopulateUnitConditionMenu);
        Register("groups", PopulateGroupConditionMenu);
        Register("combat", PopulateCombatConditionMenu);
        Register("stealth", PopulateStealthConditionMenu);
        Register("known", PopulateIsKnownConditionMenu);
        Register("forms", PopulateShapeshiftConditionMenu);
        Register("bonusbars", PopulateBonusbarConditionMenu);
        Register("specialbar", PopulateSpecialbarConditionMenu);
        Register("extrabar", PopulateExtrabarConditionMenu);
        Register("pet", PopulatePetConditionMenu);
        Register("petbattle", PopulatePetBattleConditionMenu);
        for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
            Register("$state" .. stateIndex, PopulateCustomStateConditionMenu, stateIndex);
        end
    end

    --
    -- 우클릭 메뉴의 하위 메뉴들. 위의 채우기를 그대로 쓴다.
    --

    local function CreateHoverMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_HOVER", "hover", nil,
            DebouncePrivate.CliqueDetected and LLL["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"] or nil);
        PopulateHoverMenu(description);
    end

    local function CreateUnitConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_UNITS", "checkedUnits",
            -- isActive
            function()
                if (_action.checkedUnits) then
                    for k, _ in pairs(_action.checkedUnits) do
                        if (k ~= "@") then
                            return true;
                        end
                    end
                end
                return false;
            end
        );
        PopulateUnitConditionMenu(description);
    end

    local function CreateGroupConditionMenu(rootDescription)
        PopulateGroupConditionMenu(CreateActionMenuItemGroup(rootDescription, "CONDITION_GROUP", "groups"));
    end

    local function CreateIsKnownConditionMenu(rootDescription)
        if (_action.type ~= Constants.SPELL) then
            return;
        end
        PopulateIsKnownConditionMenu(CreateActionMenuItemGroup(rootDescription, "CONDITION_KNOWN", "known"));
    end

    local function CreateCombatConditionMenu(rootDescription)
        PopulateCombatConditionMenu(CreateActionMenuItemGroup(rootDescription, "CONDITION_COMBAT", "combat"));
    end

    local function CreateShapeshiftConditionMenu(rootDescription)
        PopulateShapeshiftConditionMenu(CreateActionMenuItemGroup(rootDescription, "CONDITION_SHAPESHIFT", "forms"));
    end

    local function CreateStealthConditionMenu(rootDescription)
        PopulateStealthConditionMenu(CreateActionMenuItemGroup(rootDescription, "CONDITION_STEALTH", "stealth"));
    end

    local function CreatePetConditionMenu(rootDescription)
        PopulatePetConditionMenu(CreateActionMenuItemGroup(rootDescription, "CONDITION_PET", "pet"));
    end

    local function CreatePetBattleConditionMenu(rootDescription)
        PopulatePetBattleConditionMenu(CreateActionMenuItemGroup(rootDescription, "CONDITION_PETBATTLE", "petbattle"));
    end

    local function CreateActionbarConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_ACTIONBARS", nil,
            -- isActive
            function()
                return _action.bonusbars ~= nil or _action.bars ~= nil or _action.specialbar ~= nil or _action.extrabar ~= nil;
            end
        );

        PopulateBonusbarConditionMenu(CreateActionMenuItemGroup(description, "CONDITION_BONUSBAR", "bonusbars"));
        PopulateSpecialbarConditionMenu(CreateActionMenuItemGroup(description, "CONDITION_SPECIALBAR", "specialbar"));
        PopulateExtrabarConditionMenu(CreateActionMenuItemGroup(description, "CONDITION_EXTRABAR", "extrabar"));
    end

    local function CreateCustomStateConditionMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "CONDITION_CUSTOM_STATES", nil,
            -- isActive
            function()
                for i = 1, Constants.MAX_NUM_CUSTOM_STATES do
                    if (_action["$state" .. i] ~= nil) then
                        return true;
                    end
                end
                return false;
            end
        );

        for i = 1, Constants.MAX_NUM_CUSTOM_STATES do
            PopulateCustomStateConditionMenu(
                CreateActionMenuItemGroup(description, format(LLL["CUSTOM_STATE_NUM"], i), "$state" .. i), i);
        end
    end

    local function CreatePriorityMenu(rootDescription)
        local description = CreateActionMenuItemGroup(rootDescription, "PRIORITY", "priority",
            -- isActive
            function()
                return _action.priority ~= nil and _action.priority ~= Constants.DEFAULT_PRIORITY;
            end
        );

        for i = 1, 5 do
            local value = i;
            if (value == Constants.DEFAULT_PRIORITY) then
                value = nil;
            end
            description:CreateRadio(LLL["PRIORITY" .. i],
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

    local function CreateMoveCopyMenu(rootDescription, isCopy)
        if (TAB_LIST == nil) then
            TAB_LIST = {};
            for tabID = 1, #DebounceFrame.Tabs do
                local tabLabel = DebounceUI.GetTabLabel(tabID);
                if (tabLabel) then
                    for sideTabID = 1, #DebounceFrame.SideTabs do
                        local sideTabLabel = DebounceUI.GetSideTabaLabel(sideTabID);
                        if (sideTabLabel) then
                            tinsert(TAB_LIST, {
                                tabID = tabID,
                                sideTabID = sideTabID,
                                label = format("%s - %s", tabLabel, sideTabLabel),
                                isCurrentTab = tabID == DebounceUI.GetSelectedTab() and sideTabID == DebounceUI.GetSelectedSideTab(),
                            });
                        end
                    end
                end
            end
        end


        local optionsDescription = rootDescription:CreateButton(isCopy and LLL["COPY_TO"] or LLL["MOVE_TO"]);
        optionsDescription:CreateTitle(MenuUtil.GetElementText(optionsDescription));

        local func = function(args)
            local tabID = args[1];
            local sideTabID = args[2];
            local toLayerIndex = DebounceUI.GetLayerID(tabID, sideTabID);
            DebounceUI.MoveAction(_elementData, toLayerIndex, isCopy);
        end

        for _, tabInfo in ipairs(TAB_LIST) do
            if (isCopy or tabInfo.tabID ~= DebounceUI.GetSelectedTab() or tabInfo.sideTabID ~= DebounceUI.GetSelectedSideTab()) then
                local label = tabInfo.label;
                if (tabInfo.tabID == DebounceUI.GetSelectedTab() and tabInfo.sideTabID == DebounceUI.GetSelectedSideTab()) then
                    label = LLL["CURRENT_TAB"];
                end
                optionsDescription:CreateButton(
                    label,
                    func,
                    { tabInfo.tabID, tabInfo.sideTabID }
                );
            end
        end
    end

    local function CreateDeleteMenu(rootDescription)
        rootDescription:CreateButton(LLL["DELETE"], function()
            DebounceUI.ShowDeleteConfirmationPopup(_elementData);
        end);
    end



    function DebounceUI.SetupEditDropdownMenu(dropdown, rootDescription, elementData)
        _dropdown = dropdown;
        _elementData = elementData;
        _action = elementData.action;

        -- GenerateMenu(dropdown, rootDescription, rootMenu, elementData.action);
        -- if true then
        --     return;
        -- end

        local description;
        local title = DebounceUI.NameAndIconFromElementData(elementData);
        rootDescription:CreateTitle(title);
        rootDescription:SetTag(DebounceUI.ActionMenuRootTag, 1);

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

        CreateCustomStateConditionMenu(rootDescription);

        --
        -- Other Options
        --
        rootDescription:CreateDivider();
        rootDescription:CreateTitle(LLL["OTHER_OPTIONS"]);

        CreatePriorityMenu(rootDescription);

        CreateMoveCopyMenu(rootDescription, false);

        CreateMoveCopyMenu(rootDescription, true);

        CreateDeleteMenu(rootDescription);
    end
end
