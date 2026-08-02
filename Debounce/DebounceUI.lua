local _, DebouncePrivate     = ...;
DebouncePrivate.DebounceUI   = {};

local NUM_SPECS              = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));
local Constants              = DebouncePrivate.Constants;
local LLL                    = DebouncePrivate.L;
local DebounceUI             = DebouncePrivate.DebounceUI;

local MACRO_NAME_CHAR_LIMIT  = 32;
local MACRO_CHAR_LIMIT       = 1000;
-- 상세 패널이 열리면 프레임이 그만큼 넓어진다. 좌측 목록은 폭이 고정이라 그대로 있는다.
-- (맵 창의 minimizedWidth + questLogWidth와 같은 방식)
local FRAME_WIDTH_COLLAPSED  = 440;
local FRAME_WIDTH_EXPANDED   = 770;
local DISABLED_FONT_COLOR    = _G.DISABLED_FONT_COLOR;
local ERROR_COLOR            = _G.ERROR_COLOR;
local WARNING_FONT_COLOR     = CreateColor(1, 0.5, 0, 1);
local INACTIVE_COLOR         = _G.INACTIVE_COLOR;
local FILTERED_ALPHA         = 0.3;

local luatype                = type;
local dump                   = DebouncePrivate.dump;
local GetBindingIssue        = DebouncePrivate.GetBindingIssue;
local IsKeyInvalidForAction  = DebouncePrivate.IsKeyInvalidForAction
local GetSpellNameAndIconID  = DebouncePrivate.GetSpellNameAndIconID;
local GetSpellTabNameAndIcon = DebouncePrivate.GetSpellTabNameAndIcon;
local InCombatLockdown       = InCombatLockdown;
local QUESTION_MARK_ICON_NUM = 134400;
local TEMP_MACRO_NAME        = "zzDbncTmpMcr"

local _selectedTab           = 1;
local _selectedSideTab       = 1;
-- 목록 안에서의 재배치는 없앴다(Phase 3). 남은 드래그는 두 가지뿐이다:
--   _draggingElement - 행을 집어 탭에 떨궈 레이어를 옮기는 것
--   _pickedupInfo    - 주문/매크로를 커서에 집어와 목록에 떨구는 것(항상 맨 뒤에 추가)
-- 그래서 고스트(플레이스홀더)도 그 위치 계산도 필요 없다.
local _draggingElement;
local _pickedupInfo;
-- 상세 패널이 보여주는 액션. elementData가 아니라 action 테이블을 들고 있는 이유는
-- elementData가 Refresh마다 새로 만들어지기 때문이다 (DebounceFrameMixin:Refresh).
local _selectedAction;
local _newlyInsertedActions  = {};

DebounceUI.ActionMenuRootTag = "DEBOUNCE_ACTION_ROOT";

local _macrotextIconCache    = {};
local function GetMacrotextIcon(macrotext)
	if (macrotext == nil or macrotext == "") then
		return QUESTION_MARK_ICON_NUM;
	end

	-- for line in string.gmatch(macrotext, "[^\r\n]+") do
	-- 	-- Trim trailing whitespace from each line
	-- 	line = string.gsub(line, "%s+$", "")

	-- 	local val = SecureCmdOptionParse(line);
	-- 	-- if (string.sub(line, 1, 12):lower() == "#showtooltip") then
	-- 	-- 	val = string.sub(line, 13):gsub("%s+", ""):match("%s*(.*)");
	-- 	-- elseif (string.sub(line, 1, 1) == "/") then
	-- 	-- 	val = string.match(line, "%s+(.*)")
	-- 	-- end
	-- 	if (val and val:len() > 0) then
	-- 		local _, icon = GetSpellNameAndIconID(val);
	-- 		if (icon == nil) then
	-- 			_, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(val);
	-- 		end
	-- 		return icon;
	-- 	end
	-- end

	if (_macrotextIconCache[macrotext]) then
		return _macrotextIconCache[macrotext];
	end
	if (InCombatLockdown()) then
		return nil;
	end
	if (MacroFrame and MacroFrame:IsShown()) then
		return nil;
	end

	local ret;
	if (not GetMacroInfo(TEMP_MACRO_NAME)) then
		local cnt1, cnt2 = GetNumMacros();
		local isCharacterSpecific;
		if (cnt1 >= MAX_ACCOUNT_MACROS) then
			if (cnt2 >= MAX_CHARACTER_MACROS) then
				return nil;
			end
			isCharacterSpecific = true;
		end
		CreateMacro(TEMP_MACRO_NAME, QUESTION_MARK_ICON_NUM, macrotext, isCharacterSpecific);
	else
		EditMacro(TEMP_MACRO_NAME, nil, nil, macrotext);
	end

	_, ret = GetMacroInfo(TEMP_MACRO_NAME);
	DeleteMacro(TEMP_MACRO_NAME);
	_macrotextIconCache[macrotext] = ret;
	return ret;
end

local function ClearMacrotextIconCache()
	if (DebounceFrame:IsShown()) then
		return;
	end
	if (DebounceOverviewFrame:IsShown()) then
		return;
	end
	wipe(_macrotextIconCache);
end

local BINDING_TYPE_NAMES   = {
	[Constants.SPELL] = LLL["TYPE_SPELL"],
	[Constants.ITEM] = LLL["TYPE_ITEM"],
	[Constants.MACRO] = LLL["TYPE_MACRO"],
	[Constants.MACROTEXT] = LLL["TYPE_MACROTEXT"],
	[Constants.MOUNT] = LLL["TYPE_MOUNT"],
	[Constants.TARGET] = LLL["TYPE_TARGET"],
	[Constants.FOCUS] = LLL["TYPE_FOCUS"],
	[Constants.TOGGLEMENU] = LLL["TYPE_TOGGLEMENU"],
	[Constants.COMMAND] = LLL["TYPE_COMMAND"],
	[Constants.WORLDMARKER] = LLL["TYPE_WORLDMARKER"],
	[Constants.SETCUSTOM] = LLL["TYPE_SETCUSTOM"],
	[Constants.SETSTATE] = LLL["TYPE_SETSTATE"],
	[Constants.UNUSED] = LLL["TYPE_UNUSED"],
};

local UNIT_FRAME_REACTIONS = {
	"HELP",
	"HARM",
	"OTHER",
};

local UNIT_FRAME_TYPES     = {
	"PLAYER",
	"PET",
	"GROUP",
	"TARGET",
	"BOSS",
	"ARENA",
	"UNKNOWN",
};

local UNIT_INFO            = {
	player = {
		name = LLL["UNIT_PLAYER"],
		unitexists = false,
	},
	pet = {
		name = LLL["UNIT_PET"],
		checkedUnit = false,
	},
	target = {
		name = LLL["UNIT_TARGET"],
		--spell = false,
		--item = false,
		--target = false,
	},
	focus = {
		name = LLL["UNIT_FOCUS"],
		focus = false,
	},
	mouseover = {
		name = LLL["UNIT_MOUSEOVER"],
		togglemenu = false, -- doesn't work!
	},
	tank = {
		name = LLL["UNIT_TANK"],
		tooltipTitle = LLL["UNIT_ROLE_DESC"],
		type = "role",
	},
	healer = {
		name = LLL["UNIT_HEALER"],
		tooltipTitle = LLL["UNIT_ROLE_DESC"],
		type = "role",
	},
	maintank = {
		name = LLL["UNIT_MAINTANK"],
		tooltipTitle = LLL["UNIT_ROLE_DESC"],
		type = "role",
	},
	mainassist = {
		name = LLL["UNIT_MAINASSIST"],
		tooltipTitle = LLL["UNIT_ROLE_DESC"],
		type = "role",
	},
	custom1 = {
		name = LLL["UNIT_CUSTOM1"],
		type = "custom",
	},
	custom2 = {
		name = LLL["UNIT_CUSTOM2"],
		type = "custom",
	},
	hover = {
		name = LLL["UNIT_HOVER"],
		-- spell = false,
		-- item = false,
		tooltipTitle = LLL["UNIT_HOVER_DESC"],
		tooltipWarning = DebouncePrivate.CliqueDetected and ERROR_COLOR:WrapTextInColorCode(LLL["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"]) or nil,
		unitexists = false,
	},
	none = {
		name = LLL["UNIT_NONE"],
		tooltipTitle = LLL["UNIT_NONE_DESC"],
		target = false,
		focus = false,
		togglemenu = false,
		unitexists = false,
	},
};

local _keyInfoCache        = {};
local _mods                = {
	LALT = true,
	RALT = true,
	ALT = true,
	LCTRL = true,
	RCTRL = true,
	CTRL = true,
	LSHIFT = true,
	RSHIFT = true,
	SHIFT = true,
	META = true,
}
local function _GetKeyInfo(key)
	if (_keyInfoCache[key]) then
		return _keyInfoCache[key];
	end
	local sa = { strsplit("-", key) };
	local keyInfo = {};
	keyInfo.key = key;
	if (#sa > 0 and not _mods[sa[#sa]]) then
		keyInfo.lastKey = GetConvertedKeyOrButton(tremove(sa, #sa));
	end
	keyInfo.mods = sa;

	_keyInfoCache[key] = keyInfo;
	return keyInfo;
end

local function _CreateKeyChordStringUsingMetaKeyState(key, useLeftRight)
	local chord = {};
	-- 순서: ALT-CTRL-SHIFT

	if useLeftRight and IsLeftAltKeyDown() then
		table.insert(chord, "LALT");
	elseif useLeftRight and IsRightAltKeyDown() then
		table.insert(chord, "RALT");
	elseif IsAltKeyDown() then
		table.insert(chord, "ALT");
	end

	if useLeftRight and IsLeftControlKeyDown() then
		table.insert(chord, "LCTRL");
	elseif useLeftRight and IsRightControlKeyDown() then
		table.insert(chord, "RCTRL");
	elseif IsControlKeyDown() then
		table.insert(chord, "CTRL");
	end

	if useLeftRight and IsLeftShiftKeyDown() then
		table.insert(chord, "LSHIFT");
	elseif useLeftRight and IsRightShiftKeyDown() then
		table.insert(chord, "RSHIFT");
	elseif IsShiftKeyDown() then
		table.insert(chord, "SHIFT");
	end

	if IsMetaKeyDown() then
		table.insert(chord, "META");
	end

	if not IsMetaKey(key) then
		table.insert(chord, key);
	end

	local preventSort = true;
	return CreateKeyChordStringFromTable(chord, preventSort);
end

local GetActionBarTypeLabel;
do
	local _bonusbarLabels;
	function GetActionBarTypeLabel(index)
		if (_bonusbarLabels == nil) then
			_bonusbarLabels = {
				[0] = LLL["DEFAULT"],
				[5] = GetFlyoutInfo(229),
			};
			if (Constants.PLAYER_CLASS == "DRUID") then
				_bonusbarLabels[1] = GetSpellNameAndIconID(768);
				_bonusbarLabels[3] = GetSpellNameAndIconID(5487);
				_bonusbarLabels[4] = GetSpellNameAndIconID(24858);
			elseif (Constants.PLAYER_CLASS == "ROGUE") then
				_bonusbarLabels[1] = GetSpellNameAndIconID(1784);
			end
			for i = 0, Constants.MAX_BONUS_ACTIONBAR_OFFSET do
				local text = _bonusbarLabels[i];
				_bonusbarLabels[i] = format("[bonusbar:%d]", i);
				if (text) then
					_bonusbarLabels[i] = format("%s (%s)", _bonusbarLabels[i], text);
				end
			end
		end
		return _bonusbarLabels[index];
	end
end

local function GetLayerID(tab, sideTab)
	tab = tab or _selectedTab;
	sideTab = sideTab or _selectedSideTab;
	local isCharacterSpecific = tab == 2;
	local spec = sideTab >= 2 and sideTab - 2 or nil;
	return DebouncePrivate.GetLayerID(spec, isCharacterSpecific);
end

local function GetTabLabel(tabID)
	if (tabID == 1) then
		return LLL["SHARED_BINDINGS"];
	else
		return format(LLL["CHARACTER_SPECIFIC_BINDINGS"], UnitName("player"));
	end
end

local function GetSideTabaLabel(sideTabID)
	if (sideTabID == 1) then
		return LLL["GENERAL"];
	elseif (sideTabID == 2) then
		return UnitClass("player");
	else
		local _, specName = C_SpecializationInfo.GetSpecializationInfo(sideTabID - 2);
		return specName;
	end
end

local function DoesAncestryIncludeMouseFocus(ancestry)
	local mouseFoci = GetMouseFoci();
	for _, mouseFocus in ipairs(mouseFoci) do
		if (DoesAncestryInclude(ancestry, mouseFocus)) then -- and (mouseFocus:GetObjectType() ~= "Button")
			return true;
		end
	end
	return false;
end

local function TryCloseAnyDialog()
	if (DebounceIconSelectorFrame:Close() and DebounceMacroFrame:Close() and DebounceDetailPanel:Close()) then
		return true;
	end
	return false;
end

--- 상세 패널은 상설이고 저장을 미루는 상태가 없으므로(키도 순서도 즉시 반영) 잠금과
--- 무관하다. 잠그는 건 여전히 팝업인 둘뿐이다.
local function IsEditingAction(action)
	if (DebounceIconSelectorFrame:IsShown() and (action == nil or (DebounceIconSelectorFrame.elementData and DebounceIconSelectorFrame.elementData.action == action))) then
		return true;
	end
	if (DebounceMacroFrame:IsShown() and (action == nil or (DebounceMacroFrame.elementData and DebounceMacroFrame.elementData.action == action))) then
		return true;
	end
	return false;
end

local function IsEditDropdownShown(elementData)
	if (DebounceFrame.contextMenu) then
		if (elementData == nil or DebounceFrame.contextMenuData == elementData) then
			return true;
		end
	end
	return false;
end

local function IsDraggingElement(elementData)
	if (elementData ~= nil) then
		return _draggingElement == elementData;
	else
		return _draggingElement ~= nil;
	end
end

local function GetDraggingElement()
	return _draggingElement;
end

local function GetActionTypeAndValueFromCursorInfo()
	local type, value;
	local cursorType, cursorInfo1, _, cursorInfo3 = GetCursorInfo();

	if (cursorType) then
		if (cursorType == "spell") then
			type, value = Constants.SPELL, cursorInfo3;
		elseif (cursorType == "macro") then
			---@diagnostic disable-next-line: param-type-mismatch
			local macroName = GetMacroInfo(cursorInfo1);
			type, value = Constants.MACRO, macroName;
		elseif (cursorType == "item") then
			type, value = Constants.ITEM, cursorInfo1;
		elseif (cursorType == "mount") then
			if (cursorInfo1 == 268435455) then
				cursorInfo1 = 0;
			end
			type, value = Constants.MOUNT, cursorInfo1;
		end
		return type, value;
	end
end

local function NameAndIconFromElementData(elementData)
	local action;
	local type;
	local value;
	local skipTypeName;
	if (elementData.action) then
		action = elementData.action;
		type = action.type;
		value = action.value;
	else
		action = elementData;
		type = action.type;
		value = action.value;
	end

	local actionName, actionIcon;
	if (type == Constants.SPELL) then
		local baseSpellID = C_SpellBook.FindBaseSpellByID(value) or value;
		local overrideID = C_SpellBook.FindSpellOverrideByID(baseSpellID) or baseSpellID;
		actionName, actionIcon = GetSpellNameAndIconID(overrideID);
	elseif (type == Constants.MACRO) then
		local macroName;
		macroName, actionIcon = GetMacroInfo(value);
		if (not macroName) then
			macroName = value;
			actionIcon = QUESTION_MARK_ICON_NUM;
		end
		actionName = macroName;
	elseif (type == Constants.MACROTEXT) then
		actionName = action.name;
		actionIcon = action.icon
		if (actionIcon == QUESTION_MARK_ICON_NUM) then
			actionIcon = GetMacrotextIcon(action.value) or actionIcon;
		end
	elseif (type == Constants.ITEM) then
		local name = C_Item.GetItemNameByID(value);
		local icon = C_Item.GetItemIconByID(value);
		actionName = name;
		actionIcon = icon;
	elseif (type == Constants.MOUNT) then
		local name, icon;
		if (value == 0 or value == 268435455) then
			name, icon = GetSpellNameAndIconID(150544);
		elseif (value) then
			name, _, icon = C_MountJournal.GetMountInfoByID(value);
		end
		actionName = name;
		actionIcon = icon;
	elseif (type == Constants.SETCUSTOM) then
		actionName = LLL["TYPE_SETCUSTOM" .. value];
		actionIcon = 1505950;
		skipTypeName = true;
	elseif (type == Constants.SETSTATE) then
		local mode, stateIndex = DebouncePrivate.GetSetCustomStateModeAndIndex(value);

		if (mode == "on") then
			actionName = format(LLL["TYPE_SETSTATE_ON_NUM"], stateIndex);
		elseif (mode == "off") then
			actionName = format(LLL["TYPE_SETSTATE_OFF_NUM"], stateIndex);
		elseif (mode == "toggle") then
			actionName = format(LLL["TYPE_SETSTATE_TOGGLE_NUM"], stateIndex);
		end
		actionIcon = 254885;
		skipTypeName = true;
	elseif (type == Constants.COMMAND) then
		actionName = _G["BINDING_NAME_" .. value] or value;
		actionIcon = "A:NPE_Icon"
	elseif (type == Constants.TARGET) then
		actionName = BINDING_TYPE_NAMES[Constants.TARGET];
		actionIcon = 132212;
		skipTypeName = true;
	elseif (type == Constants.FOCUS) then
		actionName = LLL["TYPE_FOCUS"];
		actionIcon = 132212;
		skipTypeName = true;
	elseif (type == Constants.TOGGLEMENU) then
		actionName = LLL["TYPE_TOGGLEMENU"];
		actionIcon = 134331;
		skipTypeName = true;
	elseif (type == Constants.WORLDMARKER) then
		actionName = _G["WORLD_MARKER" .. value];
		actionIcon = 4238933;
		skipTypeName = true;
	elseif (type == Constants.UNUSED) then
		actionName = BINDING_TYPE_NAMES[Constants.UNUSED];
		actionIcon = "INTERFACE\\RAIDFRAME\\ReadyCheck-NotReady";
		skipTypeName = true;
	else
		actionName = action.name or LLL["UNNAMED_ACTION"];
		actionIcon = action.icon or QUESTION_MARK_ICON_NUM;
	end

	if (not skipTypeName) then
		local typeName = BINDING_TYPE_NAMES[action.type]; -- rawget(LLL, action.type);
		if (typeName) then
			actionName = format(LLL["BINDING_TITLE"], typeName or "?", actionName or "?");
		end
	end
	actionName = actionName or "?";
	return actionName, actionIcon or QUESTION_MARK_ICON_NUM;
end

local function ColoredNameAndIconFromElementData(elementData)
	local name, icon = NameAndIconFromElementData(elementData);
	local action = elementData.action;
	if (action.key == nil or DebouncePrivate.IsInactiveAction(action)) then
		name = DISABLED_FONT_COLOR:WrapTextInColorCode(name);
	elseif (GetBindingIssue(action)) then
		name = ERROR_COLOR:WrapTextInColorCode(name);
	end
	return name, icon;
end



local function DeleteElementData(elementData)
	if (DebounceIconSelectorFrame:IsShown() and DebounceIconSelectorFrame.action == elementData.action) then
		DebounceIconSelectorFrame:Close(true);
	end

	if (_selectedAction == elementData.action) then
		DebounceFrame:SetSelectedAction(nil, true);
	end

	DebounceFrame.dataProvider:Remove(elementData);
	for i, elem in DebounceFrame.dataProvider:Enumerate() do
		elem.index = i;
	end

	local layer = DebouncePrivate.GetProfileLayer(elementData.layer);
	layer:Remove(elementData.action);
	DebouncePrivate.UpdateBindings();
end

local ShowDeleteConfirmationPopup, HideDeleteConfirmationPopup;
do
	local _deletePopupData;
	function ShowDeleteConfirmationPopup(elementData)
		HideDeleteConfirmationPopup();

		local function onAccept()
			DeleteElementData(elementData);
		end

		local name = NameAndIconFromElementData(elementData);
		_deletePopupData = {
			text = LLL["DELETE_CONFIRM_MESSAGE"],
			text_arg1 = name or LLL["UNNAMED_ACTION"],
			callback = onAccept,
			acceptText = YES,
			cancelText = NO,
			showAlert = true,
			referenceKey = "DebounceDeleteConfirmation",
		};

		StaticPopup_ShowCustomGenericConfirmation(_deletePopupData);
		DebounceFrame:UpdateButtons();
	end

	function HideDeleteConfirmationPopup()
		if (_deletePopupData) then
			StaticPopup_Hide("GENERIC_CONFIRMATION", _deletePopupData);
			_deletePopupData = nil;
		end
	end
end

local ShowSaveOrDiscardPopup, HideSaveOrDiscardPopup, IsHideOrDiscardPopupShown;
do
	local _saveOrDiscardData;

	function ShowSaveOrDiscardPopup(elementData)
		HideSaveOrDiscardPopup();

		local function onAccept()
			DebounceDetailPanel:OkayButton_OnClick();
		end

		local function onCancel()
			DebounceDetailPanel:CancelButton_OnClick();
		end

		local name = NameAndIconFromElementData(elementData);
		_saveOrDiscardData = {
			text = LLL["SAVE_OR_DISCARD_MESSAGE"],
			text_arg1 = name or LLL["UNNAMED_ACTION"],
			callback = onAccept,
			cancelCallback = onCancel,
			acceptText = LLL["SAVE"],
			cancelText = LLL["DISCARD"],
			showAlert = true,
			referenceKey = "DebounceSaveOrDiscard",
		};

		StaticPopup_ShowCustomGenericConfirmation(_saveOrDiscardData);
	end

	function HideSaveOrDiscardPopup()
		if (_saveOrDiscardData) then
			StaticPopup_Hide("GENERIC_CONFIRMATION", _saveOrDiscardData);
			_saveOrDiscardData = nil;
			DebounceFrame:UpdateButtons();
		end
	end

	function IsHideOrDiscardPopupShown()
		return StaticPopup_FindVisible("GENERIC_CONFIRMATION", _saveOrDiscardData) ~= nil;
	end
end

local ShowInputBox, HideInputBox;
do
	local _shownInputBoxes = {};

	function ShowInputBox(data)
		_shownInputBoxes[data] = true;
		StaticPopup_ShowCustomGenericInputBox(data);
		if (data.currentValue) then
			local popup = StaticPopup_FindVisible("GENERIC_INPUT_BOX", data);
			if (popup) then
				popup.editBox:SetText(data.currentValue);
			end
		end
	end

	function HideInputBox(data)
		_shownInputBoxes[data] = nil;
		StaticPopup_Hide("GENERIC_INPUT_BOX", data);
	end

	function HideAllInputBoxes()
		for data in pairs(_shownInputBoxes) do
			StaticPopup_Hide("GENERIC_INPUT_BOX", data);
		end
		wipe(_shownInputBoxes);
	end
end

local function MoveAction(elementData, destLayerID, copying)
	local fromLayerID = elementData.layer;
	assert(fromLayerID == GetLayerID());

	local action = elementData.action;

	if (fromLayerID == destLayerID) then
		assert(copying, "cannot move to same layer");
	else
		if (not copying) then
			local fromLayer = DebouncePrivate.GetProfileLayer(fromLayerID);
			fromLayer:Remove(action);
		end
	end

	local insertIndex;
	if (copying and fromLayerID == destLayerID) then
		insertIndex = elementData.index + 1;
	end

	action = CopyTable(elementData.action);
	local destLayer = DebouncePrivate.GetProfileLayer(destLayerID);
	destLayer:Insert(action, insertIndex, not copying);

	DebouncePrivate.UpdateBindings();

	-- 목록은 레이어 배열을 그대로 그리므로(정렬 비교자 없음) 손으로 끼워넣지 않고 다시 만든다.
	DebounceFrame:Refresh(true);

	if (fromLayerID == destLayerID) then
		local newElementData = DebounceFrame:FindElementDataByActionInfo(action);
		if (newElementData) then
			DebounceFrame.ScrollBox:ScrollToElementData(newElementData);
		end
	end
end

local ShowLineTooltip;
do
	local _lines = {};
	local GameTooltip = GameTooltip;
	local LEFT_OFFSET = 10;
	local action;

	local function addErrorLine(message, wrap, leftOffset)
		GameTooltip_AddErrorLine(GameTooltip, message, wrap or false, leftOffset or LEFT_OFFSET);
	end

	local function addLabelLine(label, hasError)
		GameTooltip_AddBlankLineToTooltip(GameTooltip);
		if (hasError) then
			GameTooltip_AddErrorLine(GameTooltip, format(LLL["LINE_TOOLTIP_CONDITION_LABEL"], label));
		else
			GameTooltip_AddHighlightLine(GameTooltip, format(LLL["LINE_TOOLTIP_CONDITION_LABEL"], label));
		end
	end

	local function addValueLine(value, error, wrap, leftOffset)
		if (error) then
			GameTooltip_AddErrorLine(GameTooltip, value, wrap or false, leftOffset or LEFT_OFFSET);
		else
			GameTooltip_AddNormalLine(GameTooltip, value, wrap or false, leftOffset or LEFT_OFFSET);
		end
		if (type(error) == "string") then
			GameTooltip_AddErrorLine(GameTooltip, "(" .. LLL["BINDING_ERROR_" .. error] .. ")", wrap or false, leftOffset or LEFT_OFFSET);
		end
	end

	local function addValueLines(lines, error, wrap, leftOffset)
		local fn = error and GameTooltip_AddErrorLine or GameTooltip_AddNormalLine;
		for i = 1, #lines do
			fn(GameTooltip, lines[i], wrap or false, leftOffset or LEFT_OFFSET);
		end
		if (type(error) == "string") then
			GameTooltip_AddErrorLine(GameTooltip, "(" .. LLL["BINDING_ERROR_" .. error] .. ")", wrap or false, leftOffset or LEFT_OFFSET);
		end
	end

	--- instructionKeys를 주면 맨 아래 안내 줄을 그것으로 대신한다(로케일 키 배열).
	function ShowLineTooltip(owner, anchor, elementData, isOverview, instructionKeys)
		GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT");
		---@diagnostic disable-next-line: redundant-parameter
		GameTooltip:SetMinimumWidth(140, true);

		action = elementData.action;
		action._dirty = true;

		local isInactive = not isOverview and DebouncePrivate.IsInactiveAction(action);
		local hasIssues = GetBindingIssue(action) ~= nil;

		local name = ColoredNameAndIconFromElementData(elementData);
		GameTooltip_SetTitle(GameTooltip, name);

		do
			addLabelLine(LLL["KEY"]);

			if (action.key) then
				local keyText = GetBindingText(action.key);
				local error;
				if (isInactive) then
					keyText = INACTIVE_COLOR:WrapTextInColorCode(keyText);
				else
					error = hasIssues and GetBindingIssue(action, "key") or nil;
				end
				addValueLine(keyText, error);
			else
				addValueLine(INACTIVE_COLOR:WrapTextInColorCode(LLL["NOT_BOUND"]));
			end
		end

		if (action.unit ~= nil) then
			addLabelLine(LLL["TARGET_UNIT"]);
			local error = hasIssues and GetBindingIssue(action, "unit");
			local unitStr = UNIT_INFO[action.unit] and UNIT_INFO[action.unit].name or LLL[action.unit];
			addValueLine(unitStr, error);
		end

		if (action.hover ~= nil) then
			addLabelLine(LLL["CONDITION_HOVER"]);
			local error = hasIssues and GetBindingIssue(action, "hover");
			if (action.hover) then
				wipe(_lines);
				local reactions = action.reactions or Constants.REACTION_ALL;
				local frameTypes = action.frameTypes or Constants.FRAMETYPE_ALL;

				local s;
				if (reactions == Constants.REACTION_ALL) then
					s = LLL["ALL"];
				elseif (reactions == 0) then
					s = LLL["NOT_SELECTED"];
				else
					s = "";
					for i = 1, #UNIT_FRAME_REACTIONS do
						local flag = Constants["REACTION_" .. UNIT_FRAME_REACTIONS[i]];
						if (bit.band(reactions, flag) == flag) then
							if (s ~= "") then
								s = s .. ", ";
							end
							s = s .. LLL["REACTION_" .. UNIT_FRAME_REACTIONS[i]];
						end
					end
				end
				s = format("|cnWHITE_FONT_COLOR:%s:|r %s", LLL["CONDITION_REACTIONS"], s);
				addValueLine(s, hasIssues and GetBindingIssue(action, "reactions") and true or false, true);

				s = nil;
				if (frameTypes == Constants.FRAMETYPE_ALL) then
					s = LLL["ALL"];
				elseif (frameTypes == 0) then
					s = LLL["NOT_SELECTED"];
				else
					s = "";
					for i = 1, #UNIT_FRAME_TYPES do
						local flag = Constants["FRAMETYPE_" .. UNIT_FRAME_TYPES[i]];
						if (bit.band(frameTypes, flag) == flag) then
							if (s ~= "") then
								s = s .. ", ";
							end
							s = s .. LLL["FRAMETYPE_" .. UNIT_FRAME_TYPES[i]];
						end
					end
				end
				s = format("|cnWHITE_FONT_COLOR:%s:|r %s", LLL["CONDITION_FRAMETYPES"], s);
				addValueLine(s, hasIssues and GetBindingIssue(action, "frameTypes") and true or false, true);

				if (action.ignoreHoverUnit) then
					addValueLine(LLL["IGNORE_HOVER_UNIT"]);
				end
			else
				addValueLine(LLL["CONDITION_HOVER_NO"], error);
			end
			if (error) then
				addErrorLine(LLL["BINDING_ERROR_" .. error]);
			end
		end

		if (action.checkedUnits) then
			local first = true;
			for checkedUnit, value in pairs(action.checkedUnits) do
				if (checkedUnit ~= "@" or (action.unit and action.unit ~= "none")) then
					if (first) then
						addLabelLine(LLL["CONDITION_UNITS"]);
						first = false;
					end

					local error = hasIssues and GetBindingIssue(action, "checkedUnits");
					local unitStr;
					if (checkedUnit == "@") then
						unitStr = format(LLL["SELECTED_TARGET_UNIT"], UNIT_INFO[action.unit].name);
					else
						unitStr = UNIT_INFO[checkedUnit].name;
					end
					--addValueLine(unitStr);
					if (value == true) then
						addValueLine(unitStr .. " - " .. LLL["CONDITION_UNIT_EXISTS"], error);
					elseif (value == "help") then
						addValueLine(unitStr .. " - " .. LLL["CONDITION_UNIT_HELP"], error);
					elseif (value == "harm") then
						addValueLine(unitStr .. " - " .. LLL["CONDITION_UNIT_HARM"], error);
					else
						addValueLine(unitStr .. " - " .. LLL["CONDITION_UNIT_DOES_NOT_EXIST"], error);
					end
				end
			end
		end

		if (action.groups ~= nil) then
			addLabelLine(LLL["CONDITION_GROUP"]);

			if (action.groups == 0) then
				addValueLine(LLL["BINDING_ERROR_GROUPS_NONE_SELECTED"], true);
			else
				wipe(_lines);
				for _, groupType in ipairs({ "NONE", "PARTY", "RAID" }) do
					local flag = Constants["GROUP_" .. groupType];
					if (bit.band(action.groups, flag) == flag) then
						tinsert(_lines, LLL["GROUP_" .. groupType]);
					end
				end
				local error = hasIssues and GetBindingIssue(action, "groups");
				addValueLines(_lines, error);
			end
		end

		if (action.combat ~= nil) then
			addLabelLine(LLL["CONDITION_COMBAT"]);
			local error = hasIssues and GetBindingIssue(action, "combat");
			addValueLine(action.combat == true and LLL["CONDITION_COMBAT_YES"] or LLL["CONDITION_COMBAT_NO"], error);
		end

		if (action.stealth ~= nil) then
			local error = hasIssues and GetBindingIssue(action, "stealth");
			addLabelLine(LLL["CONDITION_STEALTH"]);
			addValueLine(action.stealth == true and LLL["CONDITION_STEALTH_YES"] or LLL["CONDITION_STEALTH_NO"], error);
		end

		if (action.known) then
			local error = hasIssues and GetBindingIssue(action, "known");
			addLabelLine(LLL["CONDITION_KNOWN"]);
			addValueLine(LLL["CONDITION_KNOWN_YES"], error);
			-- if (action.known == true) then
			-- else
			-- 	addValueLine(LLL["CONDITION_KNOWN_UNKNOWN"], error);
			-- end
		end

		if (action.forms ~= nil) then
			addLabelLine(LLL["CONDITION_SHAPESHIFT"]);
			if (action.forms == 0) then
				addValueLine(LLL["BINDING_ERROR_FORMS_NONE_SELECTED"], true);
			else
				wipe(_lines);
				local error = hasIssues and GetBindingIssue(action, "forms");
				for i = 0, 10 do
					local flag = 2 ^ i;
					if (bit.band(action.forms, flag) ~= 0) then
						if (i == 0) then
							tinsert(_lines, format("[form:%d] (%s)", i, LLL["NO_SHAPESHIFT"]));
						else
							local _, _, _, spellID = GetShapeshiftFormInfo(i);
							local spellName = spellID and GetSpellNameAndIconID(spellID);
							if (spellName) then
								tinsert(_lines, format("[form:%d] (%s)", i, spellName));
							else
								tinsert(_lines, format("[form:%d]", i));
							end
						end
					end
				end
				addValueLines(_lines, error);
			end
		end

		if (action.bonusbars ~= nil) then
			addLabelLine(LLL["CONDITION_BONUSBAR"]);
			if (action.bonusbars == 0) then
				addValueLine(LLL["BINDING_ERROR_BONUSBARS_NONE_SELECTED"], true);
			else
				wipe(_lines);
				local error = hasIssues and GetBindingIssue(action, "bonusbars");
				for i = 0, Constants.MAX_BONUS_ACTIONBAR_OFFSET do
					local flag = 2 ^ i;
					if (bit.band(action.bonusbars, flag) ~= 0) then
						local label = GetActionBarTypeLabel(i);
						if (label) then
							tinsert(_lines, label);
						end
					end
				end
				addValueLines(_lines, error);
			end
		end

		if (action.specialbar ~= nil) then
			local error = hasIssues and GetBindingIssue(action, "specialbar");
			addLabelLine(LLL["CONDITION_SPECIALBAR"]);
			addValueLine(action.specialbar == true and LLL["CONDITION_SPECIALBAR_YES"] or LLL["CONDITION_SPECIALBAR_NO"], error);
		end

		if (action.extrabar ~= nil) then
			local error = hasIssues and GetBindingIssue(action, "extrabar");
			addLabelLine(LLL["CONDITION_EXTRABAR"]);
			addValueLine(action.extrabar == true and LLL["CONDITION_EXTRABAR_YES"] or LLL["CONDITION_EXTRABAR_NO"], error);
		end

		if (action.pet ~= nil) then
			local error = hasIssues and GetBindingIssue(action, "pet");
			addLabelLine(LLL["CONDITION_PET"]);
			addValueLine(action.pet == true and LLL["CONDITION_PET_YES"] or LLL["CONDITION_PET_NO"], error);
		end

		if (action.petbattle ~= nil) then
			local error = hasIssues and GetBindingIssue(action, "petbattle");
			addLabelLine(LLL["CONDITION_PETBATTLE"]);
			addValueLine(action.petbattle == true and LLL["CONDITION_PETBATTLE_YES"] or LLL["CONDITION_PETBATTLE_NO"], error);
		end

		for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
			local state = "$state" .. stateIndex;
			if (action[state] ~= nil) then
				addLabelLine(format(LLL["CUSTOM_STATE_NUM"], stateIndex));
				addValueLine(action[state] == true and LLL["CONDITION_CUSTOM_STATE_YES"] or LLL["CONDITION_CUSTOM_STATE_NO"]);
			end
		end

		if (action.priority and action.priority ~= Constants.DEFAULT_PRIORITY) then
			addLabelLine(LLL["PRIORITY"]);
			addValueLine(LLL["PRIORITY" .. action.priority]);
		end

		if (instructionKeys) then
			if (#instructionKeys > 0) then
				GameTooltip_AddBlankLineToTooltip(GameTooltip);
				for _, instructionKey in ipairs(instructionKeys) do
					GameTooltip_AddInstructionLine(GameTooltip, LLL[instructionKey]);
				end
			end
		elseif (not isOverview) then
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddInstructionLine(GameTooltip, LLL["LINE_TOOLTIP_INSTRUCTION_MESSAGE1"]);
			GameTooltip_AddInstructionLine(GameTooltip, LLL["LINE_TOOLTIP_INSTRUCTION_MESSAGE2"]);
			GameTooltip_AddInstructionLine(GameTooltip, LLL["LINE_TOOLTIP_INSTRUCTION_MESSAGE3"]);
		else
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddInstructionLine(GameTooltip, LLL["OVERVIEW_LINE_TOOLTIP_INSTRUCTION_MESSAGE1"]);
		end

		GameTooltip:Show();
	end
end

local function DoesActionMatchFilter(action)
	if (not DebounceFrame.SearchBox.filterText) then
		return true;
	end

	local filters = DebounceFrame.SearchBox.filters;
	if (not filters or #filters == 0) then
		return true;
	end

	local name, icon = NameAndIconFromElementData(action);
	for _, filterText in ipairs(filters) do
		local match;
		if (name and strfind(name:lower(), filterText, 1, true)) then
			match = true;
		end

		if (not match) then
			if (strfind(action.type:lower(), filterText, 1, true)) then
				match = true;
			end
		end

		if (not match) then
			if (action.type == Constants.MACROTEXT) then
				if (action.value and strfind(action.value:lower(), filterText, 1, true)) then
					match = true;
				end
			end
		end

		if (not match) then
			if (filterText:sub(1, 1) == "@") then
				local unit = filterText:sub(2);
				if (action.unit and strfind(action.unit, unit, 1, true)) then
					match = true;
				elseif (action.checkedUnits) then
					for checkedUnit, _ in pairs(action.checkedUnits) do
						if (strfind(checkedUnit, unit, 1, true)) then
							match = true;
						end
					end
				end
			end
		end

		if (not match) then
			if (action.key) then
				local keyText = GetBindingText(action.key);
				if (strfind(keyText:lower(), filterText, 1, true)) then
					match = true;
				end
			end
		end

		if (not match) then
			return false;
		end
	end

	return true;
end


DebounceLineMixin = {};

function DebounceLineMixin:Init(elementData)
	self:RegisterForClicks("AnyUp");
	self:RegisterForDrag("LeftButton");
	--self:EnableMouseWheel(true);
	self:Update();
end

function DebounceLineMixin:Update()
	local elementData = self:GetElementData();
	local action = elementData.action;
	action._dirty = true;

	local isInactive = DebouncePrivate.IsInactiveAction(action);
	local issue = not isInactive and GetBindingIssue(action) or nil;

	local name, icon = ColoredNameAndIconFromElementData(elementData);
	if (DebouncePrivate.DEBUG) then
		name = format("%s (%d)", name, elementData.index)
	end
	self.Name:SetText(name);

	if (luatype(icon) == "string" and icon:sub(1, 2) == "A:") then
		self.Icon:SetAtlas(icon:sub(3));
	else
		self.Icon:SetTexture(icon);
	end

	if (action.key) then
		local s = GetBindingText(action.key);
		local color;
		if (isInactive) then
			color = INACTIVE_COLOR;
		elseif (issue and GetBindingIssue(action, "key")) then
			color = ERROR_COLOR;
		end
		if (color) then
			s = color:WrapTextInColorCode(s);
		end
		self.BindingText:SetText(s);
	else
		self.BindingText:SetText("");
	end

	if (action.unit) then
		local s = format("@%s", UNIT_INFO[action.unit] and UNIT_INFO[action.unit].name or LLL[action.unit]);
		local color;
		if (isInactive) then
			color = INACTIVE_COLOR;
		elseif (issue and GetBindingIssue(action, "unit")) then
			color = ERROR_COLOR;
		end
		if (color) then
			s = color:WrapTextInColorCode(s);
		end
		self.InfoText:SetText(s);
	else
		self.InfoText:SetText("");
	end

	if (DebouncePrivate.IsConditionalAction(action)) then
		if (isInactive) then
			self.QuestionMark:SetVertexColor(INACTIVE_COLOR:GetRGBA());
			self.QuestionMark:SetDesaturated(true);
		elseif (issue and (GetBindingIssue(action, "hover")
				or GetBindingIssue(action, "groups")
				or GetBindingIssue(action, "forms")
				or GetBindingIssue(action, "bonusbars")
				or GetBindingIssue(action, "specialbar")
				or GetBindingIssue(action, "combat")
				or GetBindingIssue(action, "known")
				or GetBindingIssue(action, "stealth")
				or GetBindingIssue(action, "pet")
				or GetBindingIssue(action, "petbattle"))
			) then
			self.QuestionMark:SetVertexColor(ERROR_COLOR:GetRGBA());
			self.QuestionMark:SetDesaturated(false);
		else
			self.QuestionMark:SetVertexColor(1, 1, 1);
			self.QuestionMark:SetDesaturated(false);
		end
		self.QuestionMark:Show();
	else
		self.QuestionMark:Hide();
	end

	local professionQuality = action.type == Constants.ITEM and C_TradeSkillUI.GetItemReagentQualityByItemInfo(action.value);
	if (professionQuality) then
		if (not self.ProfessionQualityOverlay) then
			self.ProfessionQualityOverlay = self:CreateTexture(nil, "Overlay");
			self.ProfessionQualityOverlay:SetPoint("TOPLEFT", self.Icon, "TOPLEFT", -3, 2);
			self.ProfessionQualityOverlay:SetDrawLayer("OVERLAY", 7);
		end
		local atlas = ("Professions-Icon-Quality-Tier%d-Inv"):format(professionQuality);
		self.ProfessionQualityOverlay:SetAtlas(atlas, TextureKitConstants.UseAtlasSize);
		self.ProfessionQualityOverlay:Show();
	elseif (self.ProfessionQualityOverlay) then
		self.ProfessionQualityOverlay:Hide();
	end

	self.Icon:SetDesaturated(false);
	-- 끌고 있는 행은 elementData가 아니라 action으로 맞춘다. Refresh가 elementData를
	-- 새로 만들어도 강조가 유지된다.
	self.SelectedHighlight:SetShown(_selectedAction == action
		or IsEditingAction(action)
		or IsEditDropdownShown(elementData)
		or (_draggingElement ~= nil and _draggingElement.action == action)
		or (DebounceOverviewFrame:IsShown() and DebounceOverviewFrame.hoveredAction == action));

	if (GameTooltip:GetOwner() == self) then
		self:OnEnter();
	end

	if (DoesActionMatchFilter(action)) then
		self:SetAlpha(1);
	else
		self:SetAlpha(FILTERED_ALPHA);
	end
end

function DebounceLineMixin:OnEnter()
	ShowLineTooltip(self, "ANCHOR_RIGHT", self:GetElementData(), false);
end

function DebounceLineMixin:OnLeave()
	---@diagnostic disable-next-line: redundant-parameter
	GameTooltip:SetMinimumWidth(0, false);
	GameTooltip:Hide();
end

function DebounceLineMixin:OnClick(buttonName)
	if (buttonName == "LeftButton" and GetActionTypeAndValueFromCursorInfo()) then
		DebounceFrame.ScrollBox:OnClick();
		return;
	end

	local elementData = self:GetElementData();
	-- 끌던 행을 목록 위에 다시 놓는 것은 아무 일도 아니다(같은 레이어 안에서는 재배치가 없다).
	-- 드래그만 끝낸다. 레이어를 옮기려면 탭에 떨궈야 한다.
	if (buttonName == "LeftButton" and IsDraggingElement(elementData)) then
		DebounceFrame:ClearMouse();
		return;
	end

	if (buttonName == "RightButton") then
		if (false and DebouncePrivate.DEBUG and IsControlKeyDown()) then
			if (IsEditingAction(elementData.action)) then
				return;
			end
			if (IsEditDropdownShown(elementData)) then
				securecall("CloseMenus");
			end
			if (IsAltKeyDown() or IsShiftKeyDown()) then
				DeleteElementData(elementData);
			else
				ShowDeleteConfirmationPopup(elementData);
			end
		else
			-- CTRL-우클릭 = 매크로 편집기 지름길
			if (IsControlKeyDown() and elementData.action.type == Constants.MACROTEXT) then
				if (IsEditingAction(elementData.action)) then
					return;
				end
				if (not TryCloseAnyDialog()) then
					return;
				end
				DebounceMacroFrame:ShowEdit(elementData);
				return;
			end

			if (not TryCloseAnyDialog()) then
				return;
			end

			DebounceFrame:ShowEditDropdown(self);
		end
		return;
	end

	-- 좌클릭 = 선택. 상세 패널이 이 액션을 단축키 탭으로 열어 보여준다.
	-- (예전에는 여기서 키 지정 팝업을 띄웠다. 이제 탭이 그 자리를 대신한다.)
	DebounceFrame:SetSelectedAction(elementData.action);
end

function DebounceLineMixin:OnDragStart()
	if (not TryCloseAnyDialog()) then
		return;
	end

	DebounceFrame:StartDragging(self:GetElementData());
end

function DebounceLineMixin:OnDragStop()
end

function DebounceLineMixin:OnReceiveDrag()
	DebounceFrame:OnReceiveDrag();
end

DebounceTabMixin = {};

function DebounceTabMixin:OnLoad()
end

function DebounceTabMixin:OnClick()
	if (not TryCloseAnyDialog()) then
		return;
	end

	local id = self:GetID();
	if (_selectedTab ~= id) then
		DebounceIconSelectorFrame:Hide();

		PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
		self:GetParent():SetTab(id);
	end
end

function DebounceTabMixin:OnEnter()
	local id = self:GetID();
	local text = GetTabLabel(id);
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(text);

	-- TODO add instruction line. "you can drop here to add/move into this tab"

	GameTooltip:Show();
end

function DebounceTabMixin:OnLeave()
	GameTooltip:Hide();
end

function DebounceTabMixin:OnReceiveDrag()
	local layerID = GetLayerID(self:GetID(), _selectedSideTab);
	DebounceFrame:OnReceiveDrag(layerID);
end

function DebounceTabMixin:IsActive()
	return _selectedTab == self:GetID();
end

DebounceSideTabMixin = {};

function DebounceSideTabMixin:OnClick()
	if (not TryCloseAnyDialog()) then
		return;
	end

	local id = self:GetID();
	if (_selectedSideTab ~= id) then
		PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);

		_selectedSideTab = id;

		DebounceFrame:UpdateSideTabs();
		DebounceFrame:Refresh();
	else
		self:SetChecked(true);
	end
end

function DebounceSideTabMixin:OnEnter()
	local id = self:GetID();
	local text = GetSideTabaLabel(id);
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	if (self.isOffSpec) then
		GameTooltip:SetText(format(LLL["INACTIVE_SPEC_LABEL"], text));
	else
		GameTooltip:SetText(text);
	end

	-- TODO add instruction line. "you can drop here to add/move into this tab"

	GameTooltip:Show();
end

function DebounceSideTabMixin:OnLeave()
	GameTooltip:Hide();
end

function DebounceSideTabMixin:OnDisable()
	self:GetNormalTexture():SetDesaturated(true);
end

function DebounceSideTabMixin:OnEnable()
	self:GetNormalTexture():SetDesaturated(self.isOffSpec);
end

function DebounceSideTabMixin:OnReceiveDrag()
	local layerID = GetLayerID(_selectedTab, self:GetID());
	DebounceFrame:OnReceiveDrag(layerID);
end

function DebounceSideTabMixin:IsActive()
	return _selectedSideTab == self:GetID();
end

DebouncePortraitMixin = {};

function DebouncePortraitMixin:SetSelectedState(isSelected)
	self.Frame:SetDesaturated(not isSelected);
	self.UnselectedFrame:SetShown(not isSelected);
end

function DebouncePortraitMixin:OnLoad()
	self:SetSelectedState(false);
	self.Portrait:SetTexture(self.PortraitTexture);
	if (self.TooltipTitle) then
		self.TooltipTitle = rawget(LLL, self.TooltipTitle) or _G[self.TooltipTitle] or self.TooltipTitle;
		self.TooltipText = rawget(LLL, self.TooltipText);
	end
	if (self.MenuFunc) then
		self:SetupMenu(DebounceUI[self.MenuFunc]);
	end
end

function DebouncePortraitMixin:OnMenuOpened(menu)
	DropdownButtonMixin.OnMenuOpened(self, menu);
	self:SetSelectedState(true);
end

function DebouncePortraitMixin:OnMenuClosed(menu)
	DropdownButtonMixin.OnMenuOpened(self, menu);
	self:SetSelectedState(false);
end

function DebouncePortraitMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
		self.initialized = true;
	end
end

function DebouncePortraitMixin:OnEnter()
	if (self.TooltipTitle) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, self.TooltipTitle);
		if (self.TooltipText) then
			GameTooltip_AddNormalLine(GameTooltip, self.TooltipText);
		end
		GameTooltip:Show();
	end
end

function DebouncePortraitMixin:OnLeave()
	GameTooltip:Hide();
end

function DebouncePortraitMixin:OnEnable()
	self.Portrait:SetDesaturated(false);
end

function DebouncePortraitMixin:OnDisable()
	self.Portrait:SetDesaturated(true);
end

DebounceFrameMixin = {};

function DebounceFrameMixin:InitializeSideTabs()
	self.SideTabs = self.SideTabsFrame.Tabs;
	for i, tab in ipairs(self.SideTabs) do
		local name, icon;
		if (i == 1) then
			name, icon = GetSpellTabNameAndIcon(1);
			tab.spec = nil;
		elseif (i == 2) then
			name, icon = GetSpellTabNameAndIcon(2);
			tab.spec = 0;
		else
			local spec = i - 2;
			tab.spec = spec;
			if (spec > NUM_SPECS) then
				tab.notUsed = true;
				tab:Hide();
				break;
			end
			_, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(spec);
		end
		tab:SetNormalTexture(icon);
		tab.tooltip = name;
		tab:Show();
	end
end

function DebounceFrameMixin:UpdateSideTabs()
	local currentSpec = C_SpecializationInfo.GetSpecialization();
	self.currentSpec = currentSpec;

	local tabOrders = { 1, 2 };
	if (currentSpec and currentSpec <= NUM_SPECS) then
		tinsert(tabOrders, currentSpec + 2);
	end

	for i = 1, NUM_SPECS do
		if (i ~= currentSpec) then
			tinsert(tabOrders, i + 2);
		end
	end

	local prevTab;
	for i = 1, #tabOrders do
		local tabID = tabOrders[i];
		local tab = self.SideTabs[tabID];

		if (tabID == 2 and _selectedTab == 2) then
			tab:Hide();
		else
			tab.isOffSpec = tabID > 2 and currentSpec ~= (tabID - 2);
			tab:GetNormalTexture():SetDesaturated(tab.isOffSpec);
			tab:SetChecked(_selectedSideTab == tabID);

			if (prevTab) then
				if (tab.isOffSpec and not prevTab.isOffSpec) then
					tab:SetPoint("TOP", prevTab, "BOTTOM", 0, -40);
				else
					tab:SetPoint("TOP", prevTab, "BOTTOM", 0, -17);
				end
			end

			tab:Show();
			prevTab = tab;
		end
	end
end

function DebounceFrameMixin:UpdateEmptyText()
	if (self.dataProvider:GetSize() == 0) then
		-- if (self.SearchBox.filters) then
		-- 	self.ScrollBox.EmptyText:SetText(LLL["NO_ACTIONS_MATCHING_FILTER"]);
		-- else
		-- 	self.ScrollBox.EmptyText:SetText(LLL["NO_ACTIONS_IN_THIS_TAB"]);
		-- end
		self.ScrollBox.EmptyText:SetText(LLL["NO_ACTIONS_IN_THIS_TAB"]);
		self.ScrollBox.EmptyText:Show();
	else
		self.ScrollBox.EmptyText:Hide();
	end
end

function DebounceFrameMixin:UpdateActionCounts()
	for tabId, tab in ipairs(self.Tabs) do
		local sum = 0;

		for sideTabId, sideTab in ipairs(self.SideTabs) do
			if (sideTab:IsShown()) then
				local layerId = GetLayerID(tabId, sideTabId);
				local layer = DebouncePrivate.GetProfileLayer(layerId);
				local count;
				if (self.SearchBox.filters) then
					count = 0;
					for i, action in layer:Enumerate() do
						if (DoesActionMatchFilter(action)) then
							count = count + 1;
						end
					end
				else
					count = layer:GetNumActions();
				end
				if (tabId == _selectedTab) then
					sideTab.Count:SetText(count);
					if (count > 0 and self.SearchBox.filters) then
						sideTab.Count:SetTextColor(GREEN_FONT_COLOR:GetRGB());
					else
						sideTab.Count:SetTextColor(1, 1, 1);
					end
				end
				sum = sum + count;
			end
		end

		local label;
		if (sum > 0 and self.SearchBox.filters) then
			label = GetTabLabel(tabId) .. " |cnGREEN_FONT_COLOR:(" .. sum .. ")|r";
		else
			label = GetTabLabel(tabId) .. " (" .. sum .. ")";
		end

		tab:SetText(label);
		PanelTemplates_TabResize(tab, 0)
	end
end

-- 커서에 집어온 주문/매크로를 놓는 동작은 드래그가 아니라 **클릭**이다. 그래서 클릭도
-- OnReceiveDrag로 보낸다. 폴백이 아니라 pickup의 정규 경로다.
local function ScrollBox_OnClick(self)
	if (GetActionTypeAndValueFromCursorInfo()) then
		self:OnReceiveDrag();
	end
end

local function ScrollBox_OnReceiveDrag(self)
	DebounceFrame:OnReceiveDrag();
end

function DebounceFrameMixin:InitializeScrollBox()
	local padding = 7;
	local bottomPadding = 40;
	local spacing = 4;
	local view = CreateScrollBoxListLinearView(padding, bottomPadding, padding, padding, spacing);

	view:SetElementInitializer("DebounceLineTemplate", function(button, elementData)
		button:Init(elementData);
	end);

	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);

	self.ScrollBox.OnClick = ScrollBox_OnClick;
	self.ScrollBox.OnReceiveDrag = ScrollBox_OnReceiveDrag;

	self.ScrollBox:RegisterForClicks("AnyUp");
	self.ScrollBox:SetScript("OnClick", self.ScrollBox.OnClick);
	self.ScrollBox:SetScript("OnReceiveDrag", self.ScrollBox.OnReceiveDrag);
end

function DebounceFrameMixin:InitializeButtons()
	self.OverviewPortrait:SetScript("OnClick", function()
		DebounceOverviewFrame:Toggle();
	end)
end

function DebounceFrameMixin:OnLoad()
	self.initialized = true;

	self:SetPortraitToAsset(133015);
	self:SetPropagateKeyboardInput(true);

	for i, tab in ipairs(self.Tabs) do
		tab:SetText(GetTabLabel(i));
		PanelTemplates_TabResize(tab, 0)
	end
	PanelTemplates_SetNumTabs(self, #self.Tabs);
	PanelTemplates_SetTab(self, _selectedTab);

	self:InitializeScrollBox();
	self:InitializeSideTabs();
	self:InitializeButtons();

	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", function()
		self:StartMoving();
	end);
	self:SetScript("OnDragStop", function()
		self:StopMovingOrSizing();
		self:SetUserPlaced(false);
		-- 좌상단을 저장한다. 상세 패널 때문에 폭이 바뀌므로 중심을 저장하면 창이 옆으로 흐른다.
		DebouncePrivate.db.global.ui.anchorPos = { x = self:GetLeft(), y = self:GetTop() };
	end);

	self.keyFilter = "";
	self.SearchBox:SetScript("OnTextChanged", self.SearchBox_OnTextChanged);
	self.SearchBox:SetScript("OnEditFocusLost", self.SearchBox_OnFocusLost);

	DebouncePrivate.db.global.ui = DebouncePrivate.db.global.ui or {};
	self:ClearAllPoints();
	local pos = DebouncePrivate.db.global.ui.anchorPos;
	if (pos) then
		self:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", pos.x, pos.y);
	else
		self:SetPoint("CENTER", "UIParent", 0, 0);
	end

	self:SetWidth(FRAME_WIDTH_COLLAPSED);
	self.DetailPanel:Hide();
end

--- 폭이 바뀌기 전에 좌상단 고정으로 바꾼다. CENTER로 앵커된 상태에서 폭을 늘리면
--- 창이 양쪽으로 번져서 좌측 목록이 밀린다.
function DebounceFrameMixin:AnchorToTopLeft()
	local left, top = self:GetLeft(), self:GetTop();
	if (not left or not top) then
		return;
	end
	self:ClearAllPoints();
	self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top);
end

--- 상세 패널을 열고 닫으면서 프레임 폭을 맞춘다.
function DebounceFrameMixin:SetDetailShown(shown)
	if (shown == self.DetailPanel:IsShown()) then
		return;
	end
	self:AnchorToTopLeft();
	self.DetailPanel:SetShown(shown);
	self:SetWidth(shown and FRAME_WIDTH_EXPANDED or FRAME_WIDTH_COLLAPSED);
end

function DebounceFrameMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
	end

	self:Refresh();
	self:UpdateSideTabs();
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
	self:RegisterEvent("CURSOR_CHANGED");

	DebouncePrivate.RegisterCallback(self, "OnBindingsUpdated");

	local type, value = GetActionTypeAndValueFromCursorInfo();
	if (type) then
		_pickedupInfo = { type = type, value = value };
		self:OnPickup();
	end
end

function DebounceFrameMixin:OnHide()
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE);
	self.SearchBox:SetText("");

	HideSaveOrDiscardPopup();
	HideDeleteConfirmationPopup();

	if (self.iconDataProvider) ~= nil then
		self.iconDataProvider:Release();
		self.iconDataProvider = nil;
	end

	self:UnregisterEvent("PLAYER_REGEN_DISABLED");
	self:UnregisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
	self:UnregisterEvent("CURSOR_CHANGED");
	self:UnregisterEvent("GLOBAL_MOUSE_UP");
	self:UnregisterEvent("GLOBAL_MOUSE_DOWN");

	DebouncePrivate.UnregisterCallback(self, "OnBindingsUpdated");

	if (IsDraggingElement()) then
		_draggingElement = nil;
		DebounceActionPlacerFrame:Hide();
	end
	_pickedupInfo = nil;
	ClearMacrotextIconCache();
end

function DebounceFrameMixin:OnEvent(event, arg1)
	if (event == "GLOBAL_MOUSE_UP") then
		-- 탭 위에 놓았다면 탭의 OnReceiveDrag가 먼저 처리한다. 여기까지 왔다는 건
		-- 아무 데도 안 떨궜다는 뜻이라 그냥 드래그를 끝낸다.
		if (arg1 == "LeftButton" and IsDraggingElement()) then
			self:ClearMouse();
		end
	elseif (event == "GLOBAL_MOUSE_DOWN") then
		if (arg1 == "RightButton") then
			if (IsDraggingElement() or GetActionTypeAndValueFromCursorInfo()) then
				self:ClearMouse();
				return;
			end
		end
	elseif (event == "CURSOR_CHANGED") then
		local type, value = GetActionTypeAndValueFromCursorInfo();
		if (type) then
			_pickedupInfo = { type = type, value = value };
			self:OnPickup();
		elseif (_pickedupInfo) then
			_pickedupInfo = nil;
			self:ClearMouse();
		end
	elseif (event == "PLAYER_REGEN_DISABLED") then
		self:OnEnterCombat();
	elseif (event == "PLAYER_REGEN_ENABLED") then
		self:OnLeaveCombat();
	elseif (event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED") then
		self:Update();
		self:UpdateSideTabs();
	end
end

function DebounceFrameMixin:OnKeyDown(input)
	if (input == "ESCAPE") then
		self:SetPropagateKeyboardInput(false);

		if (Menu.GetManager():HandleESC()) then
			return;
		end

		if (IsDraggingElement() or GetActionTypeAndValueFromCursorInfo()) then
			self:ClearMouse();
			return;
		end

		-- 캡처 오버레이가 떠 있으면 그것부터 접는다. 오버레이도 자기 ESC를 처리하지만
		-- 마우스가 패널 밖에 있으면 키가 여기로 먼저 오므로 양쪽에 둔다.
		if (DebounceDetailPanel:IsCapturingKey()) then
			DebounceDetailPanel:CancelKeyCapture();
			return;
		end

		-- ESC는 한 단계씩 물러난다: 선택 해제(패널 접힘) -> 창 닫기.
		-- 패널에는 저장을 미루는 상태가 없으므로 잃을 게 없다(매크로 편집기는 팝업이고
		-- 자기 ESC를 자기가 처리한다).
		if (_selectedAction) then
			self:SetSelectedAction(nil);
			return;
		end

		self:Hide();
		return;
	end

	self:SetPropagateKeyboardInput(true);
end

function DebounceFrameMixin:OnEnterCombat()
	-- 캡처 중이면 접는다. 전투 중에는 SetPropagateKeyboardInput이 taint라 키를 받을 수 없다.
	-- 선택은 그대로 둔다 - 전투가 끝나고 창이 다시 뜨면 보던 액션이 그대로 있어야 한다.
	DebounceDetailPanel:CancelKeyCapture(true);

	if (DebounceIconSelectorFrame:IsShown()) then
		DebounceIconSelectorFrame:CancelButton_OnClick();
	end

	-- 상세 패널의 편집 중인 내용은 일부러 안 버린다. 전투가 끝나고 프레임이 다시 뜨면
	-- 그대로 이어서 편집할 수 있다.

	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:Hide();
end

function DebounceFrameMixin:OnLeaveCombat()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED");
	self:Show();
end

function DebounceFrameMixin:OnBindingsUpdated(_, skipped)
	self:Update();
end

--- 정렬 방식을 바꿨을 때 목록을 다시 그린다.
--- 이름순은 **표시 순서일 뿐**이라 발동 순서와 무관하다. 그걸 모르면 목록 맨 위에 있는 게
--- 먼저 나가는 줄 안다. 계정당 딱 한 번 알린다.
function DebounceUI.NotifyMainListSortChanged(mode)
	if (mode == "name" and not DebouncePrivate.Options.nameSortNoticeShown) then
		DebouncePrivate.Options.nameSortNoticeShown = true;
		StaticPopup_ShowCustomGenericConfirmation({
			text = LLL["SORT_LIST_BY_NAME_NOTICE"],
			acceptText = OKAY,
			showAlert = true,
			referenceKey = "DebounceNameSortNotice",
		});
	end
	DebounceFrame:Refresh();
end

-- 배열 위치(index)는 이제 사용자가 만지는 것이 아니라 삽입 순서일 뿐이다. 그래서 목록을
-- 배열 그대로 그리지 않고 정렬해서 보여준다.
--   키순  - 키로 묶고, 한 키 안에서는 **실제 발동 순서**대로. 한 레이어만 보므로
--           layerRank는 상수이고 (priority, hover, isConditional, index)만 남는다.
--   이름순 - 표시 순서일 뿐이다. 발동 순서와 무관하다는 걸 사용자에게 한 번 알린다.
local function BuildSortedElements(layer, layerID)
	local elements = {};
	for i, action in layer:Enumerate() do
		elements[i] = {
			action = action,
			layer = layerID,
			index = i,
			order = {
				priority = action.priority,
				hover = action.hover,
				isConditional = DebouncePrivate.IsConditionalAction(action),
				layerRank = 0,
				index = i,
			},
		};
	end

	if (DebouncePrivate.Options.mainListSort == "name") then
		for _, elementData in ipairs(elements) do
			elementData.sortName = strlower(NameAndIconFromElementData(elementData) or "");
		end
		sort(elements, function(lhs, rhs)
			if (lhs.sortName ~= rhs.sortName) then
				return lhs.sortName < rhs.sortName;
			end
			return lhs.index < rhs.index;
		end);
	else
		sort(elements, function(lhs, rhs)
			local lhsKey, rhsKey = lhs.action.key, rhs.action.key;
			if (lhsKey ~= rhsKey) then
				-- 키 없는 액션은 맨 위로. 고쳐야 할 것들이라 눈에 띄어야 한다.
				if (not lhsKey) then
					return true;
				elseif (not rhsKey) then
					return false;
				end
				return DebouncePrivate.CompareKeys(lhsKey, rhsKey);
			end
			return DebouncePrivate.CompareActionOrder(lhs.order, rhs.order);
		end);
	end

	return elements;
end

function DebounceFrameMixin:Refresh(retainScrollPosition)
	HideDeleteConfirmationPopup();

	local dataProvider = CreateDataProvider();
	local layerID = GetLayerID();
	local layer = DebouncePrivate.GetProfileLayer(layerID);

	for _, elementData in ipairs(BuildSortedElements(layer, layerID)) do
		dataProvider:Insert(elementData);
	end

	self.dataProvider = dataProvider;
	self.ScrollBox:SetDataProvider(dataProvider, retainScrollPosition and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition);

	-- 선택은 "지금 보이는 목록의 한 줄"이다. 레이어 탭을 바꾸거나 액션이 사라지면 풀린다.
	if (_selectedAction and not self:FindElementDataByActionInfo(_selectedAction)) then
		self:SetSelectedAction(nil, true);
	end

	local title = format(LLL["DEBOUNCE_TITLE_FORMAT"], GetTabLabel(_selectedTab), GetSideTabaLabel(_selectedSideTab));
	self:SetTitle(title);
	self:UpdateActionCounts();
	self:UpdateEmptyText();
end

--- 상세 패널이 보여줄 액션을 바꾼다.
--- 패널에 저장 안 된 변경이 있으면 거부하고 false를 돌려준다(force면 버리고 진행).
function DebounceFrameMixin:SetSelectedAction(action, force)
	if (_selectedAction == action) then
		return true;
	end

	if (not DebounceDetailPanel:Close(force)) then
		return false;
	end

	_selectedAction = action;
	DebounceDetailPanel:OnSelectionChanged();
	self:SetDetailShown(action ~= nil);
	self:Update();
	return true;
end

function DebounceFrameMixin:GetSelectedAction()
	return _selectedAction;
end

function DebounceFrameMixin:FindElementDataByActionInfo(action)
	local index, elementData = self.dataProvider:FindByPredicate(function(e) return e.action == action; end);
	return elementData, index;
end

function DebounceFrameMixin:AddNewAction(type, value, name, icon, props)
	PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP);

	local layerID = GetLayerID();
	local layer = DebouncePrivate.GetProfileLayer(layerID);
	local action = {
		type = type,
		value = value,
		name = name,
		icon = icon,
	};
	if (props) then
		for k, v in pairs(props) do
			action[k] = v;
		end
	end
	layer:Insert(action);

	-- 목록이 정렬돼 있으므로 새 액션이 맨 뒤에 붙는다는 보장이 없다. 다시 만들고 찾아간다.
	self:Refresh(true);

	local elementData = self:FindElementDataByActionInfo(action);
	if (elementData) then
		self.ScrollBox:ScrollToElementData(elementData);
	end
	self:Update();

	return elementData;
end

function DebounceFrameMixin:Update()
	self:UpdateButtons();
	DebounceDetailPanel:Refresh();

	self.ScrollBox:ForEachFrame(function(button)
		button:Update();
	end);

	self:UpdateEmptyText();

	self.ScrollBoxBackground.Highlight:SetShown(_pickedupInfo or _draggingElement)
end

function DebounceFrameMixin:UpdateButtons()
	local enableButtons = not IsEditingAction();

	for i = 1, #self.Tabs do
		PanelTemplates_SetTabEnabled(self, i, enableButtons);
	end

	for _, tab in ipairs(self.SideTabs) do
		tab:SetEnabled(enableButtons);
	end

	self.AddPortrait:SetEnabled(enableButtons);
	self.CustomStatesPortrait:SetEnabled(enableButtons);
	self.OptionsPortrait:SetEnabled(enableButtons);
	self.SearchBox:SetEnabled(enableButtons);
end

function DebounceFrameMixin:SetTab(id)
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
	_selectedTab = id;
	PanelTemplates_SetTab(self, _selectedTab);
	self:UpdateSideTabs();

	if (not self.SideTabs[_selectedSideTab]:IsShown()) then
		_selectedSideTab = 1;
		self:UpdateSideTabs();
	end

	self:Refresh();
end

function DebounceFrameMixin:ShowEditDropdown(button, atButton)
	local elementData = button:GetElementData();
	local menu = MenuUtil.CreateContextMenu(button, DebounceUI.SetupEditDropdownMenu, elementData);
	self.contextMenu = menu;
	if (menu) then
		self.contextMenuData = elementData;
		menu:SetClosedCallback(function()
			self.contextMenu = nil;
			self.contextMenuData = nil;
		end);
	end
	self:Update();
end

function DebounceFrameMixin:OnPickup()
	self:ClearMouse(true);
	self:RegisterEvent("GLOBAL_MOUSE_UP");
	self:RegisterEvent("GLOBAL_MOUSE_DOWN");
	self:Update();
end

function DebounceFrameMixin:ClearMouse(pickingUp)
	if (_draggingElement) then
		_draggingElement = nil;
		DebounceActionPlacerFrame:Hide();
	end
	if (not pickingUp and _pickedupInfo) then
		_pickedupInfo = nil;
		ClearCursor();
	end

	self:UnregisterEvent("GLOBAL_MOUSE_UP");
	self:UnregisterEvent("GLOBAL_MOUSE_DOWN");
	if (not pickingUp) then
		self:Update();
	end
end

function DebounceFrameMixin:StartDragging(elementData)
	_draggingElement = elementData;

	local name, icon = ColoredNameAndIconFromElementData(elementData);
	DebounceActionPlacerFrame.Name:SetText(name);
	DebounceActionPlacerFrame.Icon:SetTexture(icon);
	DebounceActionPlacerFrame:Show();

	self:RegisterEvent("GLOBAL_MOUSE_UP");
	self:RegisterEvent("GLOBAL_MOUSE_DOWN");
	self:Update();
end

function DebounceFrameMixin:CanReceiveDrag()
	return IsDraggingElement() or GetActionTypeAndValueFromCursorInfo();
end

function DebounceFrameMixin:OnReceiveDrag(destLayerID)
	if (not self:CanReceiveDrag()) then
		return;
	end

	local action, prevLayerID;
	local draggingElement = GetDraggingElement();
	if (draggingElement) then
		action = draggingElement.action;
		prevLayerID = draggingElement.layer;
	else
		local type, value = GetActionTypeAndValueFromCursorInfo();
		action = { type = type, value = value };
	end

	destLayerID = destLayerID or GetLayerID();

	-- 이미 있던 행을 같은 레이어에 다시 놓는 것은 아무 일도 아니다. 예전에는 여기서
	-- 플레이스홀더 위치로 재배치했지만 목록 안 재배치는 없앴다.
	if (prevLayerID == destLayerID) then
		self:ClearMouse();
		return;
	end

	local destLayer = DebouncePrivate.GetProfileLayer(destLayerID);

	if (prevLayerID) then
		DebouncePrivate.GetProfileLayer(prevLayerID):Remove(action);
	end

	-- 항상 맨 뒤에 붙인다. 떨어진 위치는 의미가 없다.
	destLayer:Insert(action, nil);
	if (_newlyInsertedActions[destLayerID] == nil) then
		_newlyInsertedActions[destLayerID] = action;
	end

	self:ClearMouse();
	DebouncePrivate.UpdateBindings();
	self:Refresh(true);

	-- 목록이 정렬돼 있으므로 새 액션이 어디로 갈지 모른다. 찾아서 보여준다.
	if (destLayerID == GetLayerID()) then
		local elementData = self:FindElementDataByActionInfo(action);
		if (elementData) then
			self.ScrollBox:ScrollToElementData(elementData);
		end
	end
end

function DebounceFrameMixin:RefreshIconDataProvider()
	if (self.iconDataProvider == nil) then
		self.iconDataProvider = CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook);
	end
	return self.iconDataProvider;
end

function DebounceFrameMixin:SearchBox_OnTextChanged(userInput)
	InputBoxInstructions_OnTextChanged(self);

	local filterText = string.match(self:GetText(), "^%s*(.-)%s*$"):lower();
	if (filterText == "") then
		filterText = nil;
	end

	if (self.filterText ~= filterText) then
		self.filterText = filterText;

		if (filterText) then
			local words = {}
			for word in string.gmatch(filterText, "%S+") do
				table.insert(words, word)
			end
			self.filters = words;
		else
			self.filters = nil;
		end
		DebounceFrame:Refresh();
	end
end

function DebounceFrameMixin:SearchBox_OnFocusLost()
	SearchBoxTemplate_OnEditFocusLost(self);
	local rawText = self:GetText();
	local trimmedText = string.match(rawText, "^%s*(.-)%s*$"):lower();
	if (rawText ~= trimmedText) then
		self:SetText(trimmedText);
	end
end

function DebounceFrameMixin:SearchBoxClearButton_OnClick()
	DebounceFrame.keyFilter = "";
	SearchBoxTemplateClearButton_OnClick(self);
end

DebounceIconSelectorFrameMixin = {};

function DebounceIconSelectorFrameMixin:OnLoad()
end

function DebounceIconSelectorFrameMixin:OnShow()
	if (self.mode == IconSelectorPopupFrameModes.Edit) then
		if (not self.elementData) then
			self:Hide();
			return;
		end

		self.elementData = DebounceFrame:FindElementDataByActionInfo(self.elementData.action);
		if (not self.elementData) then
			self.elementData = nil;
			self:Hide();
			return;
		end
	end

	if (not self.initialized) then
		self.initialized = true;
		IconSelectorPopupFrameTemplateMixin.OnLoad(self);
		self.BorderBox.EditBoxHeaderText:SetText(format(LLL["MACRO_POPUP_TEXT"], MACRO_NAME_CHAR_LIMIT));
		self.BorderBox.IconSelectorEditBox:SetMaxLetters(MACRO_NAME_CHAR_LIMIT);
	end
	IconSelectorPopupFrameTemplateMixin.OnShow(self);
	self.BorderBox.IconSelectorEditBox:SetFocus();

	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN);
	self.iconDataProvider = DebounceFrame:RefreshIconDataProvider();
	self:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All);
	self:Update();
	self.BorderBox.IconSelectorEditBox:OnTextChanged();

	local function OnIconSelected(selectionIndex, icon)
		self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon);

		-- Index is not yet set, but we know if an icon in IconSelector was selected it was in the list, so set directly.
		self.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconDescription:SetText(ICON_SELECTION_CLICK);
		self.BorderBox.SelectedIconArea.SelectedIconText.SelectedIconDescription:SetFontObject(GameFontHighlightSmall);
	end
	self.IconSelector:SetSelectedCallback(OnIconSelected);

	DebounceFrame:Update();
end

function DebounceIconSelectorFrameMixin:OnHide()
	IconSelectorPopupFrameTemplateMixin.OnHide(self);
	self.elementData = nil;
	DebounceFrame:Update();
end

function DebounceIconSelectorFrameMixin:Update()
	-- Determine whether we're creating a new macro or editing an existing one
	if (self.mode == IconSelectorPopupFrameModes.New) then
		self.BorderBox.IconSelectorEditBox:SetText("");
		local initialIndex = 1;
		self.IconSelector:SetSelectedIndex(initialIndex);
		self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(self:GetIconByIndex(initialIndex));
	elseif (self.mode == IconSelectorPopupFrameModes.Edit) then
		local action = self.elementData.action;
		local name, icon = action.name, action.icon;
		self.BorderBox.IconSelectorEditBox:SetText(name);
		self.BorderBox.IconSelectorEditBox:HighlightText();
		self.IconSelector:SetSelectedIndex(self:GetIndexOfIcon(icon));
		self.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(icon);
	end

	local getSelection = GenerateClosure(self.GetIconByIndex, self);
	local getNumSelections = GenerateClosure(self.GetNumIcons, self);
	self.IconSelector:SetSelectionsDataProvider(getSelection, getNumSelections);
	self.IconSelector:ScrollToSelectedIndex();

	self:SetSelectedIconText();
end

function DebounceIconSelectorFrameMixin:CancelButton_OnClick()
	if (self.mode == IconSelectorPopupFrameModes.Edit) then
		DebounceMacroFrame:ShowEdit(self.elementData);
	end
	IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self);
end

function DebounceIconSelectorFrameMixin:OkayButton_OnClick()
	local iconTexture = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture();
	local text = self.BorderBox.IconSelectorEditBox:GetText();
	text = string.gsub(text, "\"", "");

	local elementData;
	if (self.mode == IconSelectorPopupFrameModes.New) then
		elementData = DebounceFrame:AddNewAction(Constants.MACROTEXT, "", text, iconTexture);
	else
		elementData = self.elementData;
		elementData.action.name = text;
		elementData.action.icon = iconTexture;
	end

	DebounceFrame:Update();
	DebounceMacroFrame:ShowEdit(elementData);
	IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self);
end

function DebounceIconSelectorFrameMixin:HasUnsavedChanges()
	if (self:IsShown() and self.mode == IconSelectorPopupFrameModes.Edit) then
		local newName = string.gsub(self.BorderBox.IconSelectorEditBox:GetText(), "\"", "");
		local newIcon = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture();
		if (self.elementData.action.name ~= newName or self.elementData.action.icon ~= newIcon) then
			return true;
		end
	end
	return false;
end

function DebounceIconSelectorFrameMixin:Close(force)
	if (self:IsShown()) then
		if (not force and self:HasUnsavedChanges()) then
			DebouncePrivate.DisplayMessage(LLL["CONFIRM_CURRENT_CHANGE_FIRST"]);
			return false;
		end
		self:CancelButton_OnClick();
	end
	return true;
end

DebounceMacroFrameMixin = {}

function DebounceMacroFrameMixin:OnLoad()
	self.BorderBox.ScrollFrame.EditBox:SetMaxLetters(MACRO_CHAR_LIMIT);

	self.OkayButton:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.GS_TITLE_OPTION_OK);
		self:OkayButton_OnClick();
	end);

	self.CancelButton:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.GS_TITLE_OPTION_OK);
		self:CancelButton_OnClick();
	end);

	self.initialized = true;
end

function DebounceMacroFrameMixin:ShowEdit(elementData, cancelFunc)
	self:Hide();

	if (self.elementData ~= elementData) then
		self.tempText = nil;
	end
	self.elementData = elementData;
	self.cancelFunc = cancelFunc;
	self.orginalText = elementData.action.value;

	local action = elementData.action;
	local name, icon = action.name, action.icon;
	self.BorderBox.SelectedMacroName:SetText(name);
	self.BorderBox.SelectedMacroButton.Icon:SetTexture(icon);

	local text = self.tempText or action.value;
	self.BorderBox.ScrollFrame.EditBox:SetText(text);

	self:Show();
end

function DebounceMacroFrameMixin:UpdateButtons()
	self.OkayButton:SetEnabled(self.cancelFunc ~= nil or self:HasUnsavedChanges());
end

function DebounceMacroFrameMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
	end

	self:UpdateButtons();
	DebounceFrame:Update();
end

function DebounceMacroFrameMixin:OnHide()
	DebounceFrame:Update();
	HideSaveOrDiscardPopup();
end

function DebounceMacroFrameMixin:OnKeyDown(key)
	if (key == "ESCAPE") then
		self:SetPropagateKeyboardInput(false);
		if (self:HasUnsavedChanges()) then
			ShowSaveOrDiscardPopup(self.elementData);
		else
			self:CancelButton_OnClick();
			return;
		end
	else
		self:SetPropagateKeyboardInput(true);
	end
end

function DebounceMacroFrameMixin:EditButton_OnClick()
	local text = self.BorderBox.ScrollFrame.EditBox:GetText();
	self.tempText = text;
	DebounceIconSelectorFrame.mode = IconSelectorPopupFrameModes.Edit;
	DebounceIconSelectorFrame.elementData = self.elementData;
	DebounceIconSelectorFrame:Show();
	self:Hide();
end

function DebounceMacroFrameMixin:OkayButton_OnClick()
	if (self:HasUnsavedChanges()) then
		local text = self.BorderBox.ScrollFrame.EditBox:GetText();
		self.elementData.action.value = text;
		self.orginalText = text;
		DebouncePrivate.UpdateBindings();
	end
	self:Hide();
	self.elementData = nil;
	self.tempText = nil;
	self.cancelFunc = nil;
end

function DebounceMacroFrameMixin:CancelButton_OnClick()
	if (self.cancelFunc) then
		self.cancelFunc();
	end
	self:Hide();
	self.elementData = nil;
	self.tempText = nil;
	self.cancelFunc = nil;
end

function DebounceMacroFrameMixin:OnTextChanged(editBox)
	ScrollingEdit_OnTextChanged(editBox, editBox:GetParent());
	self.BorderBox.CharLimitText:SetFormattedText(LLL["MACROFRAME_CHAR_LIMIT"], editBox:GetNumLetters(), MACRO_CHAR_LIMIT);
	self:UpdateButtons();
end

function DebounceMacroFrameMixin:HasUnsavedChanges()
	local text = self.BorderBox.ScrollFrame.EditBox:GetText();
	return text ~= self.orginalText;
end

function DebounceMacroFrameMixin:Close(force)
	if (self:IsShown()) then
		if (not force and self:HasUnsavedChanges()) then
			DebouncePrivate.DisplayMessage(LLL["CONFIRM_CURRENT_CHANGE_FIRST"]);
			return false;
		end
		self:CancelButton_OnClick();
	end
	return true;
end

local function GetKeyWarningText(action, key)
	if (not key) then
		return nil;
	end
	local issue = IsKeyInvalidForAction(action, key);
	if (issue) then
		return LLL["BINDING_ERROR_" .. issue];
	end
end

DebounceDetailPanelMixin = {};

function DebounceDetailPanelMixin:OnLoad()
	local keyArea = self.ContentArea.KeyArea;

	-- 단축키 문자열은 "Ctrl+Shift+Alt+마우스 버튼 3"까지 간다. 어떤 폭을 잡아도 넘칠 수
	-- 있고, UIPanelButtonTemplate의 ButtonText는 CENTER 앵커 하나뿐이라 폭이 없다 -
	-- 폭이 없는 FontString은 말줄임 없이 버튼 밖으로 그대로 삐져나온다. 양쪽을 물려
	-- 폭을 주면 한 줄로 잘리고 …가 붙는다. 잘린 전문은 툴팁이 말한다.
	local keyText = keyArea.KeyButton:GetFontString();
	keyText:ClearAllPoints();
	keyText:SetPoint("LEFT", 6, -1);
	keyText:SetPoint("RIGHT", -6, -1);
	keyText:SetWordWrap(false);

	self:InitializeCaptureOverlay();
	self:InitializeOrderScrollBox();

	self.initialized = true;
	self:Refresh();
end

function DebounceDetailPanelMixin:InitializeCaptureOverlay()
	local overlay = self.ContentArea.CaptureOverlay;

	-- 휠과 게임패드는 XML 스크립트만 달아선 안 온다. 프레임에서 따로 켜야 한다.
	overlay:EnableMouseWheel(true);
	if (overlay.EnableGamePadButton) then
		overlay:EnableGamePadButton(true);
	end

	overlay.Prompt:SetText(LLL["DETAIL_CAPTURE_PROMPT"]);
	overlay.Hint:SetText(LLL["DETAIL_KEY_CAPTURE_HINT"]);
	overlay.UnbindButton:SetText(LLL["DETAIL_UNBIND_KEY"]);
	overlay.CancelButton:SetText(CANCEL);
end

--- 선택이 바뀌었다. 사용자가 일부러 연 캡처는 그 액션의 것이었으므로 여기서 버린다.
--- 새 액션에 키가 없으면 IsCapturingKey가 알아서 참이 된다.
function DebounceDetailPanelMixin:OnSelectionChanged()
	self.captureRequested = nil;
	self:Refresh();
end

function DebounceDetailPanelMixin:Refresh()
	if (not self.initialized) then
		return;
	end

	-- 선택이 없으면 패널 자체가 안 보인다(프레임이 접힌다). 그릴 게 없다.
	local action = _selectedAction;
	if (action) then
		self:RefreshKeybind(action);
	end
end

--- 다른 것으로 넘어가기 전에 부르는 계약. 이 패널은 저장을 미루는 상태가 없다 - 키도
--- 순서도 누르는 즉시 반영된다. 그래서 막을 일이 없고, 진행 중인 캡처만 접는다.
---
--- 선택은 건드리지 않는다(keepSelection). 부르는 쪽이 이미 선택을 바꾸는 중이다.
function DebounceDetailPanelMixin:Close()
	self:CancelKeyCapture(true);
	return true;
end

--- layerID를 사람이 읽는 라벨로. 탭 라벨을 그대로 쓴다 - 직업명·특성명·캐릭터명이라
--- 새로 배울 게 없다. GetLayerID(spec, isCharacterSpecific)의 역방향이다.
local function GetLayerLabel(layerID)
	local scope, sideTab;
	if (layerID >= 7) then
		local spec = layerID - 7;
		scope = UnitName("player");
		sideTab = spec > 0 and spec + 2 or 1;
	else
		scope = LLL["SHARED_BINDINGS"];
		sideTab = layerID == 1 and 1 or layerID;
	end
	return format(LLL["ORDER_LAYER_LABEL"], scope, GetSideTabaLabel(sideTab));
end

--- 행 아래줄에 붙일 조각들. 색만으로 구분하지 않도록 전부 낱말을 쓴다.
local function BuildOrderSubText(row, layerLabel)
	local parts = {};
	if (layerLabel) then
		parts[#parts + 1] = layerLabel;
	end
	-- GetBindingIssue는 도달불가도 이슈로 친다(Misc.lua:266). 둘 다 붙이면 같은 말이 두 번
	-- 나오므로 더 구체적인 쪽만 쓴다. 자세한 이유는 행 툴팁의 단축키 줄에 있다.
	if (row.unreachable) then
		parts[#parts + 1] = ERROR_COLOR:WrapTextInColorCode(LLL["ORDER_FLAG_UNREACHABLE"]);
	elseif (row.issue) then
		parts[#parts + 1] = ERROR_COLOR:WrapTextInColorCode(LLL["ORDER_FLAG_ISSUE"]);
	end
	if (row.hover ~= nil) then
		parts[#parts + 1] = LLL["ORDER_FLAG_HOVER"];
	end
	if (row.isConditional) then
		parts[#parts + 1] = LLL["ORDER_FLAG_CONDITIONAL"];
	end
	return table.concat(parts, " \194\183 ");
end

-- 순서 리스트의 행은 좌측 목록의 선택을 옮기지 않는다. 순서만 만지려던 사용자가
-- 컨텍스트를 잃기 때문이다. 클릭이 하는 일은 우선순위 지정이고, 툴팁이 그걸 말한다.
local ORDER_LINE_TOOLTIP_INSTRUCTIONS = { "ORDER_LINE_TOOLTIP_INSTRUCTION" };

--- 우선순위를 저장하고 되비춘다. 기본값이면 nil로 지운다(Profile.lua의 CleanUpDB 규칙).
local function SetActionPriority(action, priority)
	local stored = DebouncePrivate.PriorityToStored(priority);
	if (action.priority == stored) then
		return false;
	end

	action.priority = stored;
	action._dirty = true;
	DebouncePrivate.UpdateBindings();
	-- 목록이 키 그룹 안 발동 순서로 정렬돼 있으므로 왼쪽 자리도 바뀐다.
	DebounceFrame:Refresh(true);
	DebounceFrame:Update();
	return true;
end

--- 절대 지정. 우클릭 메뉴의 CreatePriorityMenu(DropDownMenus.lua)를 리스트 안으로 옮긴 것이다.
--- 남의 액션을 건드리는 건 상대 이동보다 더 의도적이어야 하므로 값을 직접 고르게 한다.
local function ShowOrderPriorityMenu(owner, action)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:CreateTitle(LLL["PRIORITY"]);
		for i = Constants.MIN_PRIORITY, Constants.MAX_PRIORITY do
			rootDescription:CreateRadio(LLL["PRIORITY" .. i],
				function()
					return (action.priority or Constants.DEFAULT_PRIORITY) == i;
				end,
				function()
					SetActionPriority(action, i);
					-- 순서가 바뀌면 이 행이 다른 자리로 간다. 열어둔 채로 두면 헷갈린다.
					return MenuResponse.Close;
				end
			);
		end
	end);
end

DebounceOrderLineMixin = {};

function DebounceOrderLineMixin:Init()
	self:Update();
end

function DebounceOrderLineMixin:Update()
	local elementData = self:GetElementData();
	local row = elementData.row;

	-- 왼쪽 목록과 같은 색 규칙: 문제 있으면 빨강, 비활성이면 회색.
	local name, icon = ColoredNameAndIconFromElementData(row);
	self.Name:SetText(name);
	if (luatype(icon) == "string" and icon:sub(1, 2) == "A:") then
		self.Icon:SetAtlas(icon:sub(3));
	else
		self.Icon:SetTexture(icon);
	end

	self.SubText:SetText(BuildOrderSubText(row, elementData.layerLabel));

	-- 기본값은 안 쓴다. 손댄 것만 보이게 해야 무엇이 특별한지가 드러난다.
	if (row.priority ~= Constants.DEFAULT_PRIORITY) then
		self.PriorityText:SetText(LLL["PRIORITY" .. row.priority]);
	else
		self.PriorityText:SetText("");
	end

	-- 지금 보고 있는 액션은 왼쪽 목록의 선택과 같은 하이라이트로 띄운다. 순위 숫자도
	-- 같이 밝아져서 강조가 배경 하나에만 걸려 있지 않다.
	local isCurrent = elementData.isCurrent;
	self.SelectedHighlight:SetShown(isCurrent);
	self.RankText:SetText(isCurrent
		and HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(elementData.rank)
		or tostring(elementData.rank));
end

function DebounceOrderLineMixin:OnEnter()
	ShowLineTooltip(self, "ANCHOR_LEFT", self:GetElementData().row, true, ORDER_LINE_TOOLTIP_INSTRUCTIONS);
end

function DebounceOrderLineMixin:OnLeave()
	---@diagnostic disable-next-line: redundant-parameter
	GameTooltip:SetMinimumWidth(0, false);
	GameTooltip:Hide();
end

function DebounceOrderLineMixin:OnClick()
	-- 캡처 중에는 리스트가 아직 가정일 뿐이다(새 키 미리보기). 만지게 두지 않는다.
	if (DebounceDetailPanel:IsCapturingKey()) then
		return;
	end
	ShowOrderPriorityMenu(self, self:GetElementData().row.action);
end

--- 상대 이동 버튼. 비활성일 때는 무엇이 순서를 정하고 있는지와 그걸 어디서 바꾸는지가
--- 툴팁에 뜬다. 리스트 위 한 줄은 요약이고 여기가 전문이다.
--- 맨 위/맨 아래라 못 움직이는 건 설명할 게 없다. 리스트를 보면 이미 거기 있다.
--- 나머지(우선순위·조건·스코프가 갈렸다)만 왜 막혔는지 말해줄 값어치가 있다.
local function NeedsBlockExplanation(reason)
	return reason ~= nil and reason ~= "ALREADY_FIRST" and reason ~= "ALREADY_LAST";
end

local function OrderMoveButton_OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, LLL[button.titleKey]);
	if (button:IsEnabled()) then
		GameTooltip_AddNormalLine(GameTooltip, LLL[button.descKey]);
	elseif (button.reasonKey) then
		GameTooltip_AddErrorLine(GameTooltip, LLL[button.reasonKey]);
		local fix = rawget(LLL, button.reasonKey .. "_FIX");
		if (fix) then
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddNormalLine(GameTooltip, fix);
		end
	end
	GameTooltip:Show();
end

function DebounceDetailPanelMixin:InitializeOrderScrollBox()
	local orderArea = self.ContentArea.OrderArea;
	-- 이동 버튼은 단축키 줄 오른쪽 끝에 있다. 만지는 대상은 순서지만 자리는 KeyArea다.
	local keyArea = self.ContentArea.KeyArea;
	local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 2);
	view:SetElementInitializer("DebounceOrderLineTemplate", function(button, elementData)
		button:Init(elementData);
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(orderArea.ScrollBox, orderArea.ScrollBar, view);

	SquareButton_SetIcon(keyArea.MoveUpButton, "UP");
	SquareButton_SetIcon(keyArea.MoveDownButton, "DOWN");

	keyArea.MoveUpButton.titleKey = "ORDER_MOVE_UP";
	keyArea.MoveUpButton.descKey = "ORDER_MOVE_UP_DESC";
	keyArea.MoveDownButton.titleKey = "ORDER_MOVE_DOWN";
	keyArea.MoveDownButton.descKey = "ORDER_MOVE_DOWN_DESC";

	for _, button in ipairs({ keyArea.MoveUpButton, keyArea.MoveDownButton }) do
		button:SetScript("OnEnter", OrderMoveButton_OnEnter);
		button:SetScript("OnLeave", GameTooltip_Hide);
	end

	keyArea.MoveUpButton:SetScript("OnClick", function()
		self:ApplyOrderMove(self.moveUpInsertIndex);
	end);
	keyArea.MoveDownButton:SetScript("OnClick", function()
		self:ApplyOrderMove(self.moveDownInsertIndex);
	end);
end

--- 편집 중인 액션을 자기 레이어 배열 안에서 한 칸 옮긴다. 배열 자리는 순서 말고는
--- 아무 데도 안 쓰이므로(목록은 정렬해서 그린다) 부작용이 없다.
function DebounceDetailPanelMixin:ApplyOrderMove(insertIndex)
	local action = _selectedAction;
	if (not action or insertIndex == nil) then
		return;
	end

	local layer = self.moveLayer;
	if (not layer or not layer:Remove(action)) then
		return;
	end
	layer:Insert(action, insertIndex);

	action._dirty = true;
	DebouncePrivate.UpdateBindings();
	DebounceFrame:Refresh(true);
	DebounceFrame:Update();
	PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP);
end

--- 상대 이동 버튼의 상태를 계산한다. rows는 이미 발동 순서로 정렬돼 있다.
---
--- 버튼이 만지는 건 레이어 배열의 자리(index)뿐이다. 그건 순서 말고는 아무 뜻도 없는
--- 유일한 축이라, 눌러도 조건이나 스코프나 우선순위가 따라 바뀌지 않는다. 나머지 축에서
--- 갈렸으면 비활성으로 두고 **어느 속성이 정하고 있는지**만 말한다 - 그 속성들은 각자
--- 자기 편집기(우선순위 메뉴 / 조건 편집 / 레이어 이동)에서 바뀌어야 한다.
function DebounceDetailPanelMixin:UpdateOrderMoveButtons(rows, currentIndex)
	local keyArea = self.ContentArea.KeyArea;
	local up, upReason, down, downReason;

	if (currentIndex and not self:IsCapturingKey()) then
		up, upReason = DebouncePrivate.ComputeIndexMove(rows, currentIndex, -1);
		down, downReason = DebouncePrivate.ComputeIndexMove(rows, currentIndex, 1);
	end

	self.moveUpInsertIndex = up;
	self.moveDownInsertIndex = down;
	-- 이동은 이 액션이 실제로 사는 레이어의 배열 안에서 일어난다. 선택된 탭이 아니라
	-- 수집된 행에서 가져온다(축 검사가 이웃과 같은 레이어임을 이미 보장한다).
	self.moveLayer = currentIndex and rows[currentIndex].layer or nil;

	keyArea.MoveUpButton.reasonKey = upReason and ("ORDER_BLOCKED_" .. upReason) or nil;
	keyArea.MoveDownButton.reasonKey = downReason and ("ORDER_BLOCKED_" .. downReason) or nil;
	keyArea.MoveUpButton:SetEnabled(up ~= nil);
	keyArea.MoveDownButton:SetEnabled(down ~= nil);

	-- 순서가 없으면(키 없음/비활성 특성) 버튼도 없다. 리스트와 같이 나타나고 같이 사라진다.
	keyArea.MoveUpButton:SetShown(currentIndex ~= nil);
	keyArea.MoveDownButton:SetShown(currentIndex ~= nil);

	-- 비활성 버튼은 눌러도 반응이 없으니 마우스를 올려볼 이유를 안 만든다. 설명이 필요한
	-- 동안만 (i)를 달아 "여기 설명이 있다"고 말한다. 이유 자체는 툴팁이 말한다.
	keyArea.MoveUpButton.InfoBadge:SetShown(up == nil and NeedsBlockExplanation(upReason));
	keyArea.MoveDownButton.InfoBadge:SetShown(down == nil and NeedsBlockExplanation(downReason));
end

--- 인셋이 비었을 때 왜 비었는지 말한다. 리스트 위 상태 문장이 사라지면서 그 몫도 여기로
--- 왔다 - 순위는 행의 번호와 하이라이트가 이미 말하고 있고, 문장이 필요한 건 **아무것도
--- 그릴 게 없을 때**뿐이다.
function DebounceDetailPanelMixin:SetEmptyText(textKey)
	local emptyText = self.ContentArea.EmptyText;
	emptyText:SetText(textKey and LLL[textKey] or "");
	emptyText:SetShown(textKey ~= nil);
end

--- 이 키에 걸린 액션 전부를 실제 발동 순서로 그린다.
--- 키는 누르는 즉시 반영되므로 여기 나오는 건 항상 실제 결과다.
function DebounceDetailPanelMixin:RefreshOrderList(action)
	local orderArea = self.ContentArea.OrderArea;
	local key = action.key;

	-- 키가 없으면 오버레이가 패널을 덮고 있다. 뒤에 남는 건 아무도 못 보므로 비워만 둔다.
	if (not key) then
		self:UpdateOrderMoveButtons(nil, nil);
		orderArea:Hide();
		self:SetEmptyText(nil);
		return;
	end
	orderArea:Show();

	local rows = DebouncePrivate.CollectActionsForKey(key);

	local currentIndex, mixedLayers;
	for i, row in ipairs(rows) do
		if (row.action == action) then
			currentIndex = i;
		end
		if (i > 1 and row.layerID ~= rows[i - 1].layerID) then
			mixedLayers = true;
		end
	end

	self:UpdateOrderMoveButtons(rows, currentIndex);

	orderArea.ScrollBox:SetShown(currentIndex ~= nil);
	orderArea.ScrollBar:SetShown(currentIndex ~= nil);
	if (not currentIndex) then
		-- 비활성 특성의 레이어에 있는 액션이다. 경쟁 상대가 지금 것이 아니라서 순위를
		-- 계산할 수 없다. 거짓 순서를 보여주느니 못 한다고 말한다.
		self:SetEmptyText("ORDER_SCOPE_INACTIVE");
		return;
	end
	self:SetEmptyText(nil);

	local dataProvider = CreateDataProvider();
	for i, row in ipairs(rows) do
		dataProvider:Insert({
			row = row,
			rank = i,
			isCurrent = i == currentIndex,
			-- 같은 레이어는 정렬상 항상 붙어 있다. 섞였을 때만, 바뀌는 첫 행에만 단다.
			layerLabel = (mixedLayers and (i == 1 or rows[i - 1].layerID ~= row.layerID))
				and GetLayerLabel(row.layerID) or nil,
		});
	end

	orderArea.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.DiscardScrollPosition);
	orderArea.ScrollBox:ScrollToElementDataIndex(currentIndex, ScrollBoxConstants.AlignNearest);
end

--- 단축키 줄은 캡처 여부와 무관하게 늘 같은 모습이다. 캡처 중에는 오버레이가 덮으므로
--- 바꿔봐야 안 보이고, 안 바꾸면 취소했을 때 아무것도 안 움직인다.
--- 높이는 실제로 그린 만큼만 잡는다 - 남기면 그만큼 순서 리스트가 줄어든다.
function DebounceDetailPanelMixin:RefreshKeybind(action)
	local keyArea = self.ContentArea.KeyArea;
	local key = action.key;

	-- 키가 없을 때의 문구는 없다. 그 상태에서는 오버레이가 이 줄을 덮고 있다.
	keyArea.KeyButton:SetText(key and GetBindingText(key) or "");

	local warning = GetKeyWarningText(action, key);
	keyArea.WarningText:SetText(warning or "");

	-- 경고가 붙을 때만 늘어난다. 그건 크롬이 아니라 내용이라 밀려도 된다.
	local height = 30;
	if (warning) then
		height = height + keyArea.WarningText:GetStringHeight() + 6;
	end
	keyArea:SetHeight(height);

	self:RefreshCaptureOverlay(key);
	self:RefreshOrderList(action);
end

--- 해제 버튼은 지울 키가 있을 때만 있고, 없으면 취소 버튼이 그 자리로 올라온다 -
--- 빈 자리를 남기면 버튼 하나가 떠 있는 꼴이 된다.
function DebounceDetailPanelMixin:RefreshCaptureOverlay(key)
	local overlay = self.ContentArea.CaptureOverlay;
	local capturing = self:IsCapturingKey();
	overlay:SetShown(capturing);
	if (not capturing) then
		return;
	end

	-- 패널 안의 모든 것 위로 올린다. ContentArea가 useParentLevel이라 부모를 따라
	-- 레벨이 움직이므로, 한 번 박아두지 않고 띄울 때마다 다시 잡는다.
	overlay:SetFrameLevel(self.ContentArea:GetFrameLevel() + 5);

	overlay.UnbindButton:SetShown(key ~= nil);
	overlay.CancelButton:ClearAllPoints();
	if (key) then
		overlay.CancelButton:SetPoint("TOP", overlay.UnbindButton, "BOTTOM", 0, -6);
	else
		overlay.CancelButton:SetPoint("TOP", overlay.Hint, "BOTTOM", 0, -20);
	end
end

--- 오버레이가 떠 있는가. **저장된 상태가 아니라 계산되는 값이다.**
---
--- 키가 없는 액션은 이 패널이 보여줄 게 없으므로(순서도 없다) 언제나 여기에 걸린다.
--- 그래서 "키 없는 액션이 선택됐는데 오버레이가 없는" 상태는 표현할 수가 없다 -
--- 어느 경로로 키가 없어지든(우클릭 해제, 다른 창) 다음 그리기에서 자동으로 맞는다.
---
--- captureRequested는 **키가 있는 액션에서 사용자가 일부러 연 경우**만 뜻한다.
function DebounceDetailPanelMixin:IsCapturingKey()
	local action = _selectedAction;
	if (not action) then
		return false;
	end
	return action.key == nil or self.captureRequested == true;
end

function DebounceDetailPanelMixin:KeyButton_OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, LLL["KEY"]);
	-- 버튼에서 잘렸을 수 있으므로 전문을 여기 낸다.
	local key = _selectedAction and _selectedAction.key;
	if (key) then
		GameTooltip_AddHighlightLine(GameTooltip, GetBindingText(key));
	end
	GameTooltip_AddNormalLine(GameTooltip, LLL["DETAIL_KEY_BUTTON_DESC"]);
	GameTooltip:Show();
end

function DebounceDetailPanelMixin:StartKeyCapture()
	if (not _selectedAction or self:IsCapturingKey()) then
		return;
	end

	self.captureRequested = true;
	self:Refresh();
	DebounceFrame:Update();
end

--- 오버레이를 접는다.
---
--- 키가 없는 액션이면 접을 수가 없다(IsCapturingKey가 계속 참이다). 그건 버그가 아니라
--- 규칙이다 - 뒤에 보여줄 게 없으니 오버레이가 곧 그 액션의 화면이다. 그래서 나가는
--- 길은 **선택을 푸는 것**이고, 패널이 접히면서 목록으로 돌아간다.
---
--- keepSelection은 선택을 바꾸는 중인 쪽(Close)이 쓴다. 그때 선택을 또 건드리면
--- 접혔다 펴지는 왕복이 생긴다.
function DebounceDetailPanelMixin:CancelKeyCapture(keepSelection)
	if (not self:IsCapturingKey()) then
		return;
	end
	self.captureRequested = nil;

	local action = _selectedAction;
	if (action and not action.key) then
		if (keepSelection) then
			return;
		end
		-- SetSelectedAction이 Close를 거쳐 여기로 돌아오지만 그때는 선택이 이미 비어서 멈춘다.
		DebounceFrame:SetSelectedAction(nil);
		return;
	end

	self:Refresh();
	DebounceFrame:Update();
end

--- 단축키 해제. 패널에는 해제 버튼이 둘(단축키 줄 / 오버레이 안) 있고 **둘 다 여기로
--- 온다.** 같은 동작이 어디서 눌렸느냐에 따라 다른 결과를 내면 안 된다.
---
--- 키를 지우면 이 액션은 "키 없는 액션"이 되어 오버레이가 다시 걸리므로, 해제와 동시에
--- 선택을 푼다. 취소·ESC가 나가는 자리와 같다.
function DebounceDetailPanelMixin:UnbindKey()
	if (not _selectedAction) then
		return;
	end
	self.captureRequested = nil;
	self:SetActionKey(nil);
	DebounceFrame:SetSelectedAction(nil);
end

--- 키를 저장하고 되비춘다. 목록이 키순으로 정렬돼 있으므로 왼쪽 자리도 바뀐다.
function DebounceDetailPanelMixin:SetActionKey(key)
	local action = _selectedAction;
	if (not action or action.key == key) then
		return false;
	end

	action.key = key;
	action._dirty = true;
	DebouncePrivate.UpdateBindings();
	DebounceFrame:Refresh(true);
	DebounceFrame:Update();
	return true;
end

--- 오버레이가 떠 있어도 마우스는 딴 데 있을 수 있다. 그래서 **마우스가 오버레이 위에**
--- 있을 때만 키를 가로챈다. 아니면 그대로 흘려보낸다(검색창 입력 등). 안내 문구가
--- "마우스를 여기 두고"라고 말하는 게 이 조건이다.
---
--- ESC만 예외로 마우스와 무관하게 항상 닫는다. 그래서 ESC는 단축키가 될 수 없다.
---
--- 전투 중 SetPropagateKeyboardInput은 taint지만, 전투에 들어가면 DebounceFrame이 숨고
--- (OnEnterCombat) 캡처도 같이 취소되므로 여기까지 오지 않는다.
function DebounceDetailPanelMixin:KeyCapture_OnKeyDown(overlay, key)
	if (key == "ESCAPE") then
		overlay:SetPropagateKeyboardInput(false);
		self:CancelKeyCapture();
		return;
	end

	if (self:IsCapturingKey() and DoesAncestryIncludeMouseFocus(overlay)) then
		overlay:SetPropagateKeyboardInput(false);
		self:KeyCapture_ProcessInput(key);
	else
		overlay:SetPropagateKeyboardInput(true);
	end
end

--- 누르는 즉시 반영한다. 키 버튼을 눌러 캡처에 들어온 것 자체가 이미 의도적이고,
--- 되돌리려면 다시 누르면 된다. 그래서 확인 단계가 없다 - 아래 순서 리스트가
--- 가정이 아니라 실제 결과를 보여준다.
function DebounceDetailPanelMixin:KeyCapture_ProcessInput(input)
	if (not self:IsCapturingKey()) then
		return;
	end
	if (IsMetaKey(input) or input == "UNKNOWN") then
		return;
	end

	local key = GetConvertedKeyOrButton(input);
	key = _CreateKeyChordStringUsingMetaKeyState(key);

	self.captureRequested = nil;
	if (not self:SetActionKey(key)) then
		-- 같은 키를 다시 눌렀다. 바뀐 건 없지만 캡처는 끝났다.
		self:Refresh();
		DebounceFrame:Update();
	end
end

--------------------------------------------------------------------------------

DebounceOverviewFrameMixin = {}

function DebounceOverviewFrameMixin:OnLoad()
	self.initialized = true;

	local title = format(LLL["DEBOUNCE_OVERVIEW_TITLE"]);
	self:SetTitle(title);
	self:SetPortraitToAsset(133015);

	DebouncePrivate.db.global.overviewui = DebouncePrivate.db.global.overviewui or {};
	self:ClearAllPoints();
	local pos = DebouncePrivate.db.global.overviewui.pos;
	if (pos) then
		self:SetPoint("CENTER", "UIParent", "BOTTOMLEFT", pos.x, pos.y);
	else
		self:SetPoint("CENTER", "UIParent", 0, 0);
	end

	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", function()
		self:StartMoving();
	end);

	self:SetScript("OnDragStop", function()
		self:StopMovingOrSizing();
		self:SetUserPlaced(false);
		local x, y = self:GetCenter();
		DebouncePrivate.db.global.overviewui.pos = { x = x, y = y };
	end);

	self:RegisterEvent("PLAYER_REGEN_ENABLED");

	self:InitializeScrollBox();
end

function DebounceOverviewFrameMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
	end

	self:Refresh();

	DebouncePrivate.RegisterCallback(self, "OnBindingsUpdated");

	DebounceFrame.OverviewPortrait:SetSelectedState(true);
end

function DebounceOverviewFrameMixin:OnHide()
	DebounceFrame.OverviewPortrait:SetSelectedState(false);
	ClearMacrotextIconCache();
end

function DebounceOverviewFrameMixin:OnEvent(event)
	-- if (event == "PLAYER_REGEN_ENABLED") then
	-- end
	if (not InCombatLockdown()) then
		self:SetPropagateKeyboardInput(true);
	end
end

function DebounceOverviewFrameMixin:OnBindingsUpdated(...)
	self:Refresh(true);
end

DebounceOverviewHeaderMixin = {};

function DebounceOverviewHeaderMixin:Init()
	local elementData = self:GetElementData();
	self.Name:SetText(GetBindingText(elementData.key), false);
end

DebounceOverviewLineMixin = {};

function DebounceOverviewLineMixin:Init()
	self:Update();
end

function DebounceOverviewLineMixin:OnEnter()
	ShowLineTooltip(self, "ANCHOR_CURSOR_RIGHT", self:GetElementData(), true);
	if (DebounceOverviewFrame.hoveredAction ~= self:GetElementData().action) then
		DebounceOverviewFrame.hoveredAction = self:GetElementData().action;
		DebounceFrame:Update();
	end
end

function DebounceOverviewLineMixin:OnLeave()
	if (DebounceOverviewFrame.hoveredAction ~= nil) then
		DebounceOverviewFrame.hoveredAction = nil;
		DebounceFrame:Update();
	end
	---@diagnostic disable-next-line: redundant-parameter
	GameTooltip:SetMinimumWidth(0, false);
	GameTooltip:Hide();
end

function DebounceOverviewLineMixin:OnClick()
	if (InCombatLockdown()) then
		return;
	end

	local matchedLayer;
	local elementData = self:GetElementData();
	for _, layer in DebouncePrivate.EnumerateProfileLayers() do
		for _, action in layer:Enumerate() do
			if (action == elementData.action) then
				matchedLayer = layer;
				break;
			end
		end
	end

	if (matchedLayer) then
		DebounceFrame:Show();
		if (matchedLayer.isCharacterSpecific) then
			DebounceFrame:SetTab(2);
		else
			DebounceFrame:SetTab(1);
		end
		if (matchedLayer.spec) then
			DebounceFrame.SideTabs[matchedLayer.spec + 2]:Click();
		else
			DebounceFrame.SideTabs[1]:Click();
		end

		local index, elementDataFound = DebounceFrame.dataProvider:FindByPredicate(function(elementData2)
			return elementData2.action == elementData.action;
		end)

		DebounceFrame.ScrollBox:ScrollToNearest(index);
	end
end

function DebounceOverviewLineMixin:Update()
	local elementData = self:GetElementData();
	local action = elementData.action;

	local name, icon = ColoredNameAndIconFromElementData(elementData);

	self.Name:SetText(name);
	if (luatype(icon) == "string" and icon:sub(1, 2) == "A:") then
		self.Icon:SetAtlas(icon:sub(3));
	else
		self.Icon:SetTexture(icon);
	end

	local professionQuality = action.type == Constants.ITEM and C_TradeSkillUI.GetItemReagentQualityByItemInfo(action.value);
	if (professionQuality) then
		if (not self.ProfessionQualityOverlay) then
			self.ProfessionQualityOverlay = self:CreateTexture(nil, "Overlay");
			self.ProfessionQualityOverlay:SetPoint("TOPLEFT", self.Icon, "TOPLEFT", -3, 2);
			self.ProfessionQualityOverlay:SetDrawLayer("OVERLAY", 7);
		end
		local atlas = ("Professions-Icon-Quality-Tier%d-Inv"):format(professionQuality);
		self.ProfessionQualityOverlay:SetAtlas(atlas, TextureKitConstants.UseAtlasSize);
		self.ProfessionQualityOverlay:Show();
	elseif (self.ProfessionQualityOverlay) then
		self.ProfessionQualityOverlay:Hide();
	end

	local bindingText = GetBindingText(action.key);
	self.BindingText:SetText(bindingText or "");

	if (action.unit) then
		self.UnitText:SetText(UNIT_INFO[action.unit] and UNIT_INFO[action.unit].name or LLL[action.unit]);
		self.UnitText:Show();
	else
		self.UnitText:Hide();
	end


	if (DebouncePrivate.IsConditionalAction(action)) then
		self.QuestionMark:Show();
	else
		self.QuestionMark:Hide();
	end
end

function DebounceOverviewFrameMixin:Refresh(retainScrollPosition)
	local dataProvider = CreateDataProvider();
	local keyMap = DebouncePrivate.GetKeyMap();

	local keyArr = {};
	for key, _ in pairs(keyMap) do
		keyArr[#keyArr + 1] = key;
	end

	sort(keyArr, DebouncePrivate.CompareKeys);

	for _, key in ipairs(keyArr) do
		local actionArray = keyMap[key];
		for i = 1, #actionArray do
			local action = actionArray[i];
			local elementData = { action = action };
			dataProvider:Insert(elementData);
		end
	end

	self.dataProvider = dataProvider;
	self.ScrollBox:SetDataProvider(dataProvider, retainScrollPosition and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition);
end

function DebounceOverviewFrameMixin:InitializeScrollBox()
	local padding = 7;
	local spacing = 2;
	local view = CreateScrollBoxListLinearView(padding, padding, padding, padding, spacing);

	view:SetElementInitializer("DebounceOverviewLineTemplate", function(button, elementData)
		button:Init(elementData);
	end);

	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

-- Taint warning!
-- 전투 중에 SetPropagateKeyboardInput을 호출하면 taint 발생함. 적절한 방법을 찾을 수가 없다.
function DebounceOverviewFrameMixin:OnKeyDown(input)
	if (input == "ESCAPE") then
		self:Hide();
		if (not InCombatLockdown()) then
			self:SetPropagateKeyboardInput(false);
		end
	else
		if (not InCombatLockdown()) then
			self:SetPropagateKeyboardInput(true);
		end
	end
end

function DebounceOverviewFrameMixin:Toggle()
	if (self:IsShown()) then
		self:Hide();
	else
		self:Show();
	end
end

function DebounceUI.GetSelectedTab()
	return _selectedTab;
end

function DebounceUI.GetSelectedSideTab()
	return _selectedSideTab;
end

DebounceStateDriverUpdateThrottleSliderMixin = {};

function DebounceStateDriverUpdateThrottleSliderMixin:OnLoad()
	self.Slider:SetAccessorFunction(function()
		return DebouncePrivate.Options.stateDriverUpdateThrottle or 0.2;
	end);

	self.Slider:SetMutatorFunction(function(value)
		value = floor(value * 1000 + 1) / 1000;
		DebouncePrivate.Options.stateDriverUpdateThrottle = value;
		DebouncePrivate.ApplyOptions("stateDriverUpdateThrottle");
	end);

	self.Slider:RegisterPropertyChangeHandler("OnValueChanged", function(slider, value, isMouse)
		self.ValueText.Text:SetText(format("%.2f", value):gsub("%.?0+$", ""));
	end);

	self.Slider:UpdateVisibleState();
end

function DebounceStateDriverUpdateThrottleSliderMixin:UpdateVisibleState()
	self.Slider:UpdateVisibleState();
end

-- temp
DebounceUI.UNIT_INFO = UNIT_INFO;
DebounceUI.BINDING_TYPE_NAMES = BINDING_TYPE_NAMES;
DebounceUI.GetLayerID = GetLayerID;
DebounceUI.GetTabLabel = GetTabLabel;
DebounceUI.GetSideTabaLabel = GetSideTabaLabel;
DebounceUI.MoveAction = MoveAction;
DebounceUI.ShowDeleteConfirmationPopup = ShowDeleteConfirmationPopup;
DebounceUI.NameAndIconFromElementData = NameAndIconFromElementData;
DebounceUI.ShowInputBox = ShowInputBox
