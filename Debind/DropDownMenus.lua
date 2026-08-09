local _, DebindPrivate    = ...;
local Constants             = DebindPrivate.Constants;
local LLL                   = DebindPrivate.L;
local DebindUI            = DebindPrivate.DebindUI;

local dump                  = DebindPrivate.dump
local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;

local SEPARATOR             = { isSeparator = true, };
local ARRAY_MARKER          = {};
-- 선택 창의 명령 탭도 같은 목록을 건다. 사본을 하나 더 두면 갈라진다 (`DebindUI.lua`).
local SORTED_UNIT_LIST      = DebindUI.SORTED_UNIT_LIST;
local USE_CHECKED_VALUE     = {};


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
    DebindPrivate.UpdateBindings();
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
-- CustomStatesDropDown
--------------------------------------------------------------------------------
function DebindUI.SetupCustomStatesDropdownMenu(dropdown, rootDescription)
    --GenerateMenu(dropdown, rootDescription, rootMenu);

    for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
        local stateOptions = DebindPrivate.GetCustomStateOptions(stateIndex);
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
                DebindUI.ShowInputBox({
                    text = LLL["CUSTOM_STATE_EDIT_VALUE_DESC"],
                    callback = function(value)
                        value = strtrim(value);
                        if (value == "") then
                            value = nil;
                        end
                        stateOptions.expr = value;
                        if (stateOptions.mode == Constants.CUSTOM_STATE_MODES.MACRO_CONDITIONAL) then
                            DebindPrivate.UpdateBindings();
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

        local useMouseDownDescription = unitframeDescription:CreateCheckbox(LLL["UNITFRAME_TRIGGER_ON_MOUSE_DOWN"], function()
            return DebindPrivate.Options.unitframeUseMouseDown;
        end, function()
            DebindPrivate.Options.unitframeUseMouseDown = not DebindPrivate.Options.unitframeUseMouseDown;
            DebindPrivate.ApplyOptions("unitframeUseMouseDown");
            return MenuResponse.Refresh;
        end);
        SetInstrcutionTooltip(useMouseDownDescription, LLL["UNITFRAME_TRIGGER_ON_MOUSE_DOWN_DESC"]);

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
        SetInstrcutionTooltip(excludePlayerDescription, LLL["EXCLUDE_PLAYER_DESC"]);
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
        SetInstrcutionTooltip(stateDriverUpdateThrottleDescription, LLL["STATE_DRIVER_UPDATE_THROTTLE_DESC"]);
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

    do
        local addCustomTargetMenusToUnitPopupDescription = rootDescription:CreateCheckbox(LLL["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP"], function()
            return DebindPrivate.Options.addCustomTargetMenusToUnitPopup and true or false;
        end, function()
            DebindPrivate.Options.addCustomTargetMenusToUnitPopup = (not DebindPrivate.Options.addCustomTargetMenusToUnitPopup) or nil;
            DebindPrivate.ApplyOptions("addCustomTargetMenusToUnitPopup");
            return MenuResponse.Refresh;
        end);
        SetInstrcutionTooltip(addCustomTargetMenusToUnitPopupDescription, LLL["ADD_CUSTOM_TARGET_MENUS_TO_UNIT_POPUP_DESC"]);
    end

    -- do
    --     local sliderDescription = rootDescription:CreateTemplate("DebindStateDriverUpdateThrottleSliderTemplate");
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

    local function onActionValueChanged()
        _action._dirty = true;
        DebindPrivate.UpdateBindings();
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
            DebindPrivate.UpdateBindings();
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
                err = DebindPrivate.GetBindingIssue(_action, key);
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
                return DebindPrivate.GetBindingIssue(_action, "checkedUnits", nil, unit);
            end,
            nil, true);

        local titleDescription = optionsDescription:CreateTitle(MenuUtil.GetElementText(optionsDescription));
        if (unit == "@") then
            optionsDescription:AddInitializer(function(button, elementDescription, menu)
                if (_action.unit and _action.unit ~= "none") then
                    button.fontString:SetText(format(LLL["SELECTED_TARGET_UNIT"], DebindUI.UNIT_INFO[_action.unit].name));
                else
                    button.fontString:SetText(LLL["SELECTED_TARGET_UNIT_EMPTY"]);
                end
            end);
            optionsDescription:SetEnabled(function()
                return _action.unit and _action.unit ~= "none" and true or false;
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
        if (DebindPrivate.CliqueDetected) then
            return false;
        end
        return _action.hover and true or false;
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

    local function CreateUnbindMenuItem(parentDescription)
        local description = parentDescription:CreateButton(LLL["UNBIND"], function()
            _action.key = nil;
            onActionValueChanged();
            -- 목록이 키로 묶여 있던 시절에는 이 행이 "키 없음" 묶음으로 건너뛰어서, 메뉴만
            -- 남고 행은 화면 밖으로 사라졌다. 지금은 이름순이라 키를 지워도 행이 제자리다 -
            -- 그래도 화면 밖에 있을 수는 있으므로(스크롤) 짚어주는 것은 그대로 둔다.
            DebindFrame:ScrollActionIntoView(_action);
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

    local function CreateHoverMenu(parentDescription)
        local description = CreateActionMenuItemGroup(parentDescription, "CONDITION_HOVER", "hover", nil, DebindPrivate.CliqueDetected and LLL["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"] or nil);

        -- Clique를 켜 두면 hover 조건은 어차피 동작하지 않는다. 그래도 메뉴를 잠그지는
        -- 않는다 - 이미 켜 둔 값을 [사용 안 함]으로 지우러 들어갈 수 있어야 하기 때문이다.
        -- 대신 값이 있느냐로 색을 가른다: **값이 남아 있으면 고쳐야 할 것**이라 빨강(위에서
        -- 칠한 ERROR_COLOR 그대로)이고, 값이 없으면 지금 고를 수 없는 항목일 뿐이라
        -- 회색이다 - 켠 적도 없는 조건을 오류로 붉히면 고칠 것이 있는 줄 알게 된다.
        -- 그룹이 제 초기화에서 색을 칠하므로 그 뒤에 덧칠하는 초기화를 하나 더 건다.
        if (DebindPrivate.CliqueDetected) then
            description:AddInitializer(function(button)
                if (_action.hover == nil) then
                    button.fontString:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
                end
            end);
        end

        local disable, yes, no = AppendDisableYesNo(description, "CONDITION_HOVER", "hover");
        if (DebindPrivate.CliqueDetected) then
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

        -- if (_action.type == Constants.SPELL or _action.type == Constants.ITEM or _action.type == Constants.TARGET or _action.type == Constants.FOCUS or _action.type == Constants.TOGGLEMENU) then
        --     CreateUnitConditionSubmenu(description, "SELECTED_TARGET_UNIT_EMPTY", "@");
        -- end

        for _, unit in ipairs(SORTED_UNIT_LIST) do
            if (not (unit == "player" or unit == "none")) then
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
                return _action.bonusbars ~= nil or _action.bars ~= nil or _action.specialbar ~= nil or _action.extrabar ~= nil;
            end
        );

        local bonusbarDescription = CreateActionMenuItemGroup(description, "CONDITION_BONUSBAR", "bonusbars");
        AppendDisable(bonusbarDescription, "CONDITION_BONUSBAR", "bonusbars");
        AppendCheckboxes(bonusbarDescription, "bonusbars", range(0, Constants.MAX_BONUS_ACTIONBAR_OFFSET, function(offset)
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
            end,
            nil, -- error
            -- 설명은 **명시적으로** 넘긴다. 안 넘기면 `CONDITION_CUSTOM_STATES_DESC`를
            -- 찾아가는데, 그건 사용자 지정 상태 버튼의 툴팁(CUSTOM_STATES_DESC)과 글자
            -- 하나 다르지 않은 문단이었다 - 같은 말을 로케일마다 두 번 번역하게 만드는
            -- 자리라 키를 없애고 이쪽으로 붙였다.
            LLL["CUSTOM_STATES_DESC"]
        );

        for i = 1, Constants.MAX_NUM_CUSTOM_STATES do
            local stateDescription = CreateActionMenuItemGroup(description, format(LLL["CUSTOM_STATE_NUM"], i), "$state" .. i);
            AppendDisableYesNo(stateDescription, "CONDITION_CUSTOM_STATE", "$state" .. i);
        end
    end

    --- 집 편집기 같은 바인딩 컨텍스트가 가져간 키는 기본적으로 우리가 내준다. 편집기가
    --- 자기 버튼과 안내 문구에 그 키를 그려주기 때문에, 우리가 먹으면 화면에 떠 있는
    --- 단축키가 안 먹는 상태가 된다. 그래도 그 키를 쓰겠다는 유저를 위한 통로다.
    local function CreateKeepInBindingContextMenuItem(rootDescription)
        local description = rootDescription:CreateCheckbox(LLL["KEEP_IN_BINDING_CONTEXT"], actionValueEquals,
            setActionValue, { key = "keepInBindingContext", value = USE_CHECKED_VALUE });
        SetInstrcutionTooltip(description, LLL["KEEP_IN_BINDING_CONTEXT_DESC"]);
    end

    --- 중요도는 이 메뉴에서 **파장이 가장 넓은 값**이다. 축이 둘 다 넓다: 이 액션이 걸린
    --- **모든 키**의 순서를 바꾸고(이 키만이 아니다), 공유 레이어면 **이 계정의 모든
    --- 캐릭터**에서 그렇게 된다.
    ---
    --- 제목 줄의 경고는 첫째 축까지밖에 못 말한다("여기서 바꾸면 모든 캐릭터"). 둘째 축은
    --- 화면 어디에도 안 적혀 있고, 하필 이 목록에 온 사람의 머릿속은 "이 키의 순서"에 가
    --- 있어서 정확히 어긋나는 자리다. 그래서 고르는 손이 라디오 위에 있는 순간 읽히도록
    --- 항목 툴팁에 붙인다.
    local function CreatePriorityMenu(rootDescription)
        -- `rawget`이라 없으면 nil이다(로케일 표의 __index를 건너뛴다). 이어붙이기 전에
        -- 갈라서 둔다 - 번역본 한 줄이 빠졌다고 메뉴가 통째로 터지면 안 된다.
        local instruction = rawget(LLL, "PRIORITY_DESC");
        local layer = _elementData.layer and DebindPrivate.GetProfileLayer(_elementData.layer);
        if (layer and not layer.isCharacterSpecific) then
            local warning = LLL["PRIORITY_SHARED_WARNING"];
            instruction = instruction and (instruction .. "|n|n" .. warning) or warning;
        end

        local description = CreateActionMenuItemGroup(rootDescription, "PRIORITY", "priority",
            -- isActive
            function()
                return _action.priority ~= nil and _action.priority ~= Constants.DEFAULT_PRIORITY;
            end,
            nil, instruction
        );

        for i = Constants.MIN_PRIORITY, Constants.MAX_PRIORITY do
            -- 저장할 값으로 바꾸는 것은 Ordering.lua 한 군데다. 기본값을 nil로 접는 규칙이
            -- 여기에도 손으로 적혀 있었는데, 같은 규칙이 두 군데 있으면 한쪽만 바뀐다.
            local value = DebindPrivate.PriorityToStored(i);
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

    --- 목적지 목록은 **레이어**의 목록이지 탭 좌표의 목록이 아니다.
    ---
    --- 같은 레이어를 두 좌표가 가리키는 일이 실재한다: 캐릭터 전용 탭에서 (탭2, 사이드탭1)과
    --- (탭2, 사이드탭2)가 **둘 다 레이어 7**이다. 그래서 layerID로 접는다 - 안 접으면 같은
    --- 곳으로 가는 항목이 이름만 다르게 둘 나오고, "이동"으로 그 둘째를 고르면
    --- `MoveAction`의 `assert(copying, "cannot move to same layer")`에 걸린다.
    --- 남는 이름은 사이드탭1 쪽인데, 화면에서 레이어 7이 실제로 서 있는 자리가 거기다
    --- (`UpdateSideTabs`가 탭2에서 사이드탭2를 숨긴다).
    --- 겨누는 것이 하나든 여럿이든 목적지 목록은 **같은 하나**다. 그래서 대상을 밖에서 받는다:
    --- `fromLayerID`는 "이미 여기 산다"를 판정하는 데만 쓰이고, `applyFunc`가 실제로 옮긴다.
    --- 목록을 두 벌 두면 탭이 하나 늘 때 한쪽만 따라온다.
    local function CreateMoveCopyMenu(rootDescription, isCopy, fromLayerID, applyFunc)
        if (TAB_LIST == nil) then
            TAB_LIST = {};
            local seenLayers = {};
            for tabID = 1, #DebindFrame.Tabs do
                local tabLabel = DebindUI.GetTabLabel(tabID);
                if (tabLabel) then
                    for sideTabID = 1, #DebindFrame.SideTabs do
                        local sideTabLabel = DebindUI.GetSideTabaLabel(sideTabID);
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


        local optionsDescription = rootDescription:CreateButton(isCopy and LLL["COPY_TO"] or LLL["MOVE_TO"]);
        optionsDescription:CreateTitle(MenuUtil.GetElementText(optionsDescription));

        local func = function(args)
            applyFunc(args[1], isCopy);
        end

        -- **"지금 이 액션이 사는 레이어"이지 "지금 보고 있는 탭"이 아니다.** 오버뷰 탭에서는
        -- 행마다 레이어가 다르므로 화면으로는 답할 수 없고, 레이어 탭에서는 둘이 같은 값이라
        -- 달라지는 것이 없다.
        for _, tabInfo in ipairs(TAB_LIST) do
            local isSameLayer = tabInfo.layerID == fromLayerID;
            if (isCopy or not isSameLayer) then
                optionsDescription:CreateButton(
                    isSameLayer and LLL["CURRENT_TAB"] or tabInfo.label,
                    func,
                    { tabInfo.layerID }
                );
            end
        end
    end

    local function CreateDeleteMenu(rootDescription)
        rootDescription:CreateButton(LLL["DELETE"], function()
            DebindUI.ShowDeleteConfirmationPopup(_elementData);
        end);
    end



    function DebindUI.SetupEditDropdownMenu(dropdown, rootDescription, elementData)
        _dropdown = dropdown;
        _elementData = elementData;
        _action = elementData.action;

        -- GenerateMenu(dropdown, rootDescription, rootMenu, elementData.action);
        -- if true then
        --     return;
        -- end

        local description;
        local title = DebindUI.NameAndIconForAction(elementData.action);
        rootDescription:CreateTitle(title);

        -- **어느 레이어의 액션을 만지는 중인가.** 이 메뉴는 액션을 지우고 조건을 바꾸는데,
        -- 그 액션이 어디 사는지 말하는 것이 여기 말고는 없었다.
        --
        -- 예전에는 물어볼 필요가 없었다. 메뉴가 열리는 곳이 왼쪽 목록뿐이었고 그 목록은
        -- 언제나 한 레이어라 답이 창 제목에 있었다. 지금은 둘 다 아니다 - **오버뷰 탭은
        -- 다섯 레이어를 한 목록에 담는다.**
        --
        -- **공유 레이어면 경고색으로 그린다.** 여기서 무엇을 바꾸든 이 계정의 **모든
        -- 캐릭터**가 따라 바뀌는데, 그 결과는 화면이 보여줄 수조차 없다 - `InitDB`가
        -- 레이어로 짓는 것은 `db.characters[playerGUID]` 하나뿐이라, 다른 캐릭터의 몫은
        -- 같은 계정 파일에 올라와 있어도 `LayerArray`에 들어오지 않는다.
        --
        -- 글자는 좌표 그대로 둔다. 한때 아이콘과 "모든 캐릭터"를 같이 붙였는데, 제목 줄
        -- 하나에 그림·좌표·결과가 겹쳐서 어느 것도 안 읽혔다. 색이 "조심"을 말하고, 무엇을
        -- 조심해야 하는지는 그걸 만질 수 있는 자리(중요도 툴팁)가 말한다.
        --
        -- 캐릭터 전용이면 노랑이다. 이름 줄(금색)과 달라야 두 줄짜리 제목으로 안 읽힌다 -
        -- 둘은 서로 다른 것을 말한다(무엇을 만지는가 / 어디를 만지는가).
        if (elementData.layer) then
            local layer = DebindPrivate.GetProfileLayer(elementData.layer);
            local shared = layer and not layer.isCharacterSpecific;
            rootDescription:CreateTitle(DebindUI.GetLayerLabel(elementData.layer),
                shared and DebindUI.WARNING_FONT_COLOR or YELLOW_FONT_COLOR);
        end

        rootDescription:SetTag(DebindUI.ActionMenuRootTag, 1);

        CreateConvertToMacroTextMenuItem(rootDescription);

        EditMacroTextMenuItem(rootDescription);

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

        CreateKeepInBindingContextMenuItem(rootDescription);

        CreatePriorityMenu(rootDescription);

        CreateMoveCopyMenu(rootDescription, false, _elementData.layer, function(destLayerID, isCopy)
            DebindUI.MoveAction(_elementData, destLayerID, isCopy);
        end);

        CreateMoveCopyMenu(rootDescription, true, _elementData.layer, function(destLayerID, isCopy)
            DebindUI.MoveAction(_elementData, destLayerID, isCopy);
        end);

        CreateDeleteMenu(rootDescription);
    end

    --- 여럿을 고른 채로 연 메뉴. **이동·복사·삭제 셋뿐이다.**
    ---
    --- 단일 메뉴의 나머지(키·조건·중요도)는 여기 안 넣는다. 그 값들은 한꺼번에 걸 수 있는
    --- 것이 아니다 - 조건은 액션마다 뜻이 다르고, 중요도는 이 액션이 걸린 **모든 키**와 공유
    --- 레이어면 이 계정의 **모든 캐릭터**까지 건드린다(`PRIORITY_SHARED_WARNING`). 그런 것을
    --- 열 줄에 한 번에 거는 통로는 되돌릴 수도 없다.
    ---
    --- 고른 것은 전부 **같은 레이어**에 있다. 오른쪽 목록이 한 레이어만 담기 때문이고
    --- (`DebindFrameMixin:Refresh`), 그래서 "이미 여기 산다"를 화면의 레이어로 답할 수 있다.
    function DebindUI.SetupBulkDropdownMenu(dropdown, rootDescription, actions)
        _dropdown = dropdown;
        -- 단일 메뉴가 쓰는 것들이다. 벌크에서는 겨눈 것이 하나가 아니므로 비워둔다 - 남아
        -- 있으면 이 메뉴가 안 쓰는 값을 다음 단일 메뉴가 물려받는다.
        _elementData = nil;
        _action = nil;

        rootDescription:CreateTitle(format(LLL["BULK_MENU_TITLE"], #actions));

        local fromLayerID = DebindUI.GetLayerID();

        CreateMoveCopyMenu(rootDescription, false, fromLayerID, function(destLayerID, isCopy)
            DebindUI.MoveActions(actions, destLayerID, isCopy);
        end);

        CreateMoveCopyMenu(rootDescription, true, fromLayerID, function(destLayerID, isCopy)
            DebindUI.MoveActions(actions, destLayerID, isCopy);
        end);

        rootDescription:CreateButton(LLL["DELETE"], function()
            DebindUI.ShowBulkDeleteConfirmationPopup(actions);
        end);
    end
end
