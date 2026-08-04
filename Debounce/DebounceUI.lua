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
	if (DebounceIconSelectorFrame:Close() and DebounceDetailPanel:Close()) then
		return true;
	end
	return false;
end

--- 상세 패널에는 저장을 미루는 상태가 없다 - 키도 순서도 즉시 반영되고, 매크로 본문은
--- 떠날 때 저장된다. 그래서 패널은 아무것도 잠그지 않는다. 잠그는 건 팝업인 아이콘
--- 선택기뿐이다.
---
--- 매크로 편집은 여기 없다. 탭이 되면서 **모드가 아니라 보기**가 됐다 - 매크로 탭을 열어둔
--- 채로 다른 액션을 고르거나 레이어를 옮겨도 되고, 그때마다 떠나는 쪽에서 저장된다.
local function IsEditingAction(action)
	if (DebounceIconSelectorFrame:IsShown() and (action == nil or (DebounceIconSelectorFrame.elementData and DebounceIconSelectorFrame.elementData.action == action))) then
		return true;
	end
	return false;
end

-- 열린 메뉴의 대상은 elementData가 아니라 action으로 기억한다. 메뉴가 떠 있는 동안 Refresh가
-- 돌면 elementData는 새로 만들어지고, 그걸 붙들고 있으면 대상을 놓친다.
local function IsEditDropdownShown(elementData)
	if (DebounceFrame.contextMenu) then
		if (elementData == nil or DebounceFrame.contextMenuAction == elementData.action) then
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

--- 액션 하나를 받는다. 목록 elementData를 그대로 넘기지 말 것 - 부르는 쪽이 `.action`을
--- 꺼내서 넘긴다. 아래 색칠하는 쪽도 같은 계약이다.
local function NameAndIconForAction(action)
	local type = action.type;
	local value = action.value;
	local skipTypeName;

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

	-- 세 번째 반환값은 **타입을 안 붙인 이름**이다. 타입을 따로 보여주는 자리(상세 패널의
	-- 인포 인셋)에서 쓴다 - 안 그러면 "Wrath (Spell)" 옆에 "Spell"이 또 붙는다.
	local bareName = actionName or "?";
	if (not skipTypeName) then
		local typeName = BINDING_TYPE_NAMES[action.type]; -- rawget(LLL, action.type);
		if (typeName) then
			actionName = format(LLL["BINDING_TITLE"], typeName or "?", actionName or "?");
		end
	end
	actionName = actionName or "?";
	return actionName, actionIcon or QUESTION_MARK_ICON_NUM, bareName;
end

--- skipCategory는 **그 행이 스스로 보여주는** 이슈 계열이다. 이름은 다른 데서 안 보이는
--- 문제만 물들인다 - 단축키 칸이 이미 빨간데 이름까지 빨개지면 행 전체가 잘못된 것으로
--- 읽힌다. 도달불가는 이 행의 잘못이 아니라 다른 행 때문에 생기는 것이라 더 그렇다.
--- 단축키를 따로 안 보여주는 쪽(오버뷰, 툴팁 제목)은 안 넘기면 예전 그대로다.
local function ColoredNameAndIconForAction(action, skipCategory)
	local name, icon = NameAndIconForAction(action);
	if (action.key == nil or DebouncePrivate.IsInactiveAction(action)) then
		name = DISABLED_FONT_COLOR:WrapTextInColorCode(name);
	elseif (GetBindingIssue(action, nil, skipCategory)) then
		name = ERROR_COLOR:WrapTextInColorCode(name);
	end
	return name, icon;
end



local function DeleteElementData(elementData)
	-- 선택기가 들고 있는 건 elementData다. .action이라는 필드는 아무도 넣어주지 않아서
	-- 늘 nil이었고, 그래서 이 가드는 한 번도 걸린 적이 없다 - 지우는 액션을 편집기가
	-- 열어둔 채였다면 그 위에 이름·아이콘을 써 넣는다. 지워진 테이블에.
	if (IsEditingAction(elementData.action)) then
		DebounceIconSelectorFrame:Close(true);
	end

	if (_selectedAction == elementData.action) then
		DebounceFrame:SetSelectedAction(nil);
	end

	local layer = DebouncePrivate.GetProfileLayer(elementData.layer);
	layer:Remove(elementData.action);
	DebouncePrivate.UpdateBindings();

	-- 목록을 프로필에서 다시 만든다. 예전에는 provider에서 그 행만 빼고 index를 다시 매겼는데,
	-- 그러면 한 키의 마지막 행을 지웠을 때 그룹 헤더가 홀로 남는다. 게다가 그 index는 배열
	-- 위치가 아니라 **표시 순서**라서 정렬이 쓰는 order.index와 뜻이 달랐다. 다시 만드는 쪽이
	-- 액션을 추가하거나 옮길 때 이미 하는 일이기도 하다.
	DebounceFrame:Refresh(true);
end

local ShowDeleteConfirmationPopup, HideDeleteConfirmationPopup;
do
	local _deletePopupData;
	function ShowDeleteConfirmationPopup(elementData)
		HideDeleteConfirmationPopup();

		local function onAccept()
			DeleteElementData(elementData);
		end

		local name = NameAndIconForAction(elementData.action);
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

		local name = ColoredNameAndIconForAction(action);
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

	local name, icon = NameAndIconForAction(action);
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

	local name, icon = ColoredNameAndIconForAction(action, "key");
	if (DebouncePrivate.DEBUG) then
		name = format("%s (%d)", name, elementData.index)
	end
	self.Name:SetText(name);

	if (luatype(icon) == "string" and icon:sub(1, 2) == "A:") then
		self.Icon:SetAtlas(icon:sub(3));
	else
		self.Icon:SetTexture(icon);
	end

	local keyIssue = issue and GetBindingIssue(action, "key") or nil;
	if (action.key) then
		local s = GetBindingText(action.key);
		local color;
		if (isInactive) then
			color = INACTIVE_COLOR;
		elseif (keyIssue) then
			color = ERROR_COLOR;
		end
		if (color) then
			s = color:WrapTextInColorCode(s);
		end
		self.BindingText:SetText(s);
	else
		self.BindingText:SetText("");
	end

	-- 단축키 문제는 단축키 옆에서 말한다. 색만으로는 색맹에 안 걸리고, 어느 칸이 문제인지도
	-- 말해주지 못한다. BindingText는 폭이 고정된 칸이라 오른쪽 끝에 걸면 글자에서 한참
	-- 떨어지므로 글자 길이를 재서 바로 뒤에 붙인다.
	self.KeyWarning:SetShown(keyIssue ~= nil);
	if (keyIssue) then
		self.KeyWarning:ClearAllPoints();
		self.KeyWarning:SetPoint("LEFT", self.BindingText, "LEFT", self.BindingText:GetStringWidth() + 4, 0);
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
		or (_draggingElement ~= nil and _draggingElement.action == action)
		or (DebounceOverviewFrame:IsShown() and DebounceOverviewFrame.hoveredAction == action));

	-- 메뉴 대상은 선택과 다른 텍스처를 쓴다(XML 참고). 한 행이 둘 다일 수 있으므로 서로를
	-- 지우지 않는다.
	self.MenuHighlight:SetShown(IsEditDropdownShown(elementData));

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
				DebounceDetailPanel:EditMacroText(elementData.action);
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

--- 단축키 정렬에서 한 키의 묶음이 시작되는 자리에 놓이는 줄.
---
--- 행에서 단축키 글자를 빼지는 않는다. 헤더는 스크롤에 밀려 화면 밖으로 나가는데(이 목록은
--- 고정 헤더가 아니다) 그러면 무슨 키인지 알 수 없는 행들만 남는다.
DebounceKeyHeaderMixin = {};

function DebounceKeyHeaderMixin:Init(elementData)
	if (elementData.key) then
		self.Label:SetText(GetBindingText(elementData.key));
	else
		-- 키가 없는 것은 키의 한 종류가 아니라 상태다. 그래서 낱말로 쓰고 흐리게 둔다.
		self.Label:SetText(DISABLED_FONT_COLOR:WrapTextInColorCode(LLL["KEY_GROUP_UNBOUND"]));
	end
end

--- DebounceFrameMixin:Update가 목록의 모든 프레임에 이걸 부른다. 헤더가 말하는 것은 키뿐이고
--- 키가 바뀌면 목록이 통째로 다시 그려지므로 여기서 할 일이 없다.
function DebounceKeyHeaderMixin:Update()
end

--- 상세 패널의 탭. 블리자드 기본 UpdateTabWidth는 자동 폭이던 Text를 GetWidth()가 돌려준
--- 값으로 못박는다. 그 값이 실제 문자열 폭보다 반올림 한 톨이라도 모자라면 그 자리에서
--- 말줄임이 되고, 폭이 고정됐으니 영영 그대로다. 글자 수와 무관한 복불복이라 "Macro" 같은
--- 짧은 라벨이 잘리고 긴 라벨은 멀쩡하기도 한다.
---
--- 폭 계산 자체는 블리자드와 같다. 못박는 줄만 빼고, 문자열 폭도 못박힌 값에 갇히지 않는
--- GetStringWidth로 읽는다. 우리는 min/maxTabWidth를 걸지 않으므로 그 부분은 옮기지 않았다.
local TAB_SIDE_EXTRA_SPACING = 20;

DebounceDetailTabMixin = {};

function DebounceDetailTabMixin:UpdateTabWidth()
	self.Text:SetWidth(0);

	local width = self.Left:GetWidth() + self.Right:GetWidth() + TAB_SIDE_EXTRA_SPACING;
	local textWidth = self.Text:GetStringWidth() + (self.textPadding or 0);
	if (width < textWidth) then
		width = textWidth + 10;
	end

	self:SetTabWidth(width);
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

-- 탭 라벨의 개수는 "그 탭이 가진 액션 수"이지 "지금 화면에 뭐가 보이는가"가 아니다.
-- 그래서 셀 대상을 sideTab:IsShown()으로 고르면 안 된다. 사이드탭의 가시성은
-- _selectedTab의 함수이고(UpdateSideTabs: 탭2가 선택되면 사이드탭2를 숨긴다), 그걸
-- 빌려 쓰면 "지금 고른 탭"의 사정이 **모든 탭**의 개수에 새어 들어간다. 실제로
-- 탭1을 보는 동안 탭2 라벨은 레이어 7을 두 번 셌고, 탭2를 보는 동안 탭1 라벨은
-- 레이어 2(공용/직업)를 통째로 빠뜨렸다 - 탭을 클릭하기만 해도 남의 개수가 변했다.
--
-- 대신 레이어 집합에서 직접 센다. 존재하는 사이드탭(1..2+NUM_SPECS)을 layerID로
-- 옮기고, 같은 layerID가 두 번 나오면 한 번만 센다. 중복은 실재한다: 캐릭터 전용
-- 탭에서는 GetLayerID가 (nil, true)와 (0, true) 양쪽에 7을 준다. 사이드탭2가 탭2에서
-- 숨는 것도 바로 그 중복 때문이니, 여기서 layerID로 거르는 건 숨김 규칙을 흉내내는
-- 게 아니라 숨김의 원인을 그대로 다시 말하는 것이다 - 화면이 어떻든 답이 같다.
--
-- 없는 특성을 NUM_SPECS로 거르는 것도 프레임 상태(notUsed)를 안 믿기 때문이다.
-- InitializeSideTabs는 첫 초과 사이드탭에서 break하므로 그 뒤 사이드탭에는 notUsed가
-- 붙지 않는다. 그런 사이드탭을 GetLayerID에 넘기면 Profile의 assert에 걸린다.
function DebounceFrameMixin:UpdateActionCounts()
	for tabId, tab in ipairs(self.Tabs) do
		local sum = 0;
		local countedLayers = {};

		for sideTabId, sideTab in ipairs(self.SideTabs) do
			if (sideTabId <= 2 + NUM_SPECS) then
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

				-- 사이드탭 숫자는 그 사이드탭이 여는 레이어를 그대로 보여준다. 중복이라
				-- 합계에서 빠지는 쪽(탭2의 사이드탭2)도 자기 숫자는 맞게 들고 있어야
				-- 한다 - 어느 쪽을 숨길지는 UpdateSideTabs의 사정이고, 여기가 그걸
				-- 앞질러 정하면 숨김 규칙이 바뀔 때 보이는 숫자가 비게 된다.
				if (tabId == _selectedTab) then
					sideTab.Count:SetText(count);
					if (count > 0 and self.SearchBox.filters) then
						sideTab.Count:SetTextColor(GREEN_FONT_COLOR:GetRGB());
					else
						sideTab.Count:SetTextColor(1, 1, 1);
					end
				end

				if (not countedLayers[layerId]) then
					countedLayers[layerId] = true;
					sum = sum + count;
				end
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

	-- 헤더와 행이 섞이므로 템플릿을 하나로 못 박지 못한다. 팩토리가 elementData를 보고 고른다.
	view:SetElementFactory(function(factory, elementData)
		if (elementData.isHeader) then
			factory("DebounceKeyHeaderTemplate", function(frame)
				frame:Init(elementData);
			end);
		else
			factory("DebounceLineTemplate", function(button)
				button:Init(elementData);
			end);
		end
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

--- 게임메뉴가 뜰 때는 언제나 열린 창을 먼저 다 닫는다(ESC는 CloseAllWindows가 먼저 먹고,
--- 마이크로 버튼은 CloseAllWindows 후 ShowUIPanel을 부른다). 그 그물이 UISpecialFrames이므로
--- 여기 등록하지 않으면 게임메뉴와 창이 공존하게 되고, 그 상태에서 ESC를 우리가 가로챈다.
local function RegisterAsSpecialFrame(name)
	for _, value in ipairs(UISpecialFrames) do
		if (value == name) then
			return;
		end
	end
	tinsert(UISpecialFrames, name);
end

function DebounceFrameMixin:OnLoad()
	self.initialized = true;

	RegisterAsSpecialFrame("DebounceFrame");

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

	HideDeleteConfirmationPopup();

	-- 창이 닫히는 것도 "떠나는" 것이다. 기본 매크로 창의 OnHide와 같이, 편집 중이던
	-- 매크로 본문은 여기서 저장된다.
	DebounceDetailPanel:Close();

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
	-- 덮개는 위 두 상태를 보고 켜지는데, 그걸 지웠다고 저절로 내려가지는 않는다. 여기서
	-- 안 내리면 다음에 창을 열 때 목록을 덮은 채 "탭으로 옮겨라"라고 말하고 있다 - 창을
	-- 닫는 것도, 전투에 끌려들어가는 것도 드래그 도중에 일어난다.
	self:UpdateDropOverlay();
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

		-- 매크로 탭에는 따로 처리할 게 없다. 편집칸에 포커스가 있으면 ESC가 포커스만 풀고
		-- (여기까지 안 온다), 한 번 더 누르면 아래 선택 해제로 간다 - 그때 본문이 저장된다.

		-- 키를 듣는 중이면 그것부터 그만둔다. 버튼도 자기 ESC를 처리하지만 마우스가 패널
		-- 밖에 있으면 키가 여기로 먼저 오므로 양쪽에 둔다.
		if (DebounceDetailPanel:IsCapturingKey()) then
			DebounceDetailPanel:CancelKeyCapture();
			return;
		end

		-- 아이콘 선택기가 떠 있으면 그것부터 물러난다. 팝업이니 자기 ESC를 자기가 처리할
		-- 것 같지만 아니다 - IconSelectorPopupFrameTemplate은 키보드를 켜지도, ESC를
		-- 받지도, UISpecialFrames에 들지도 않는다. 그래서 여기서 안 세우면 팝업을 띄워둔
		-- 채로 선택이 풀리고, 한 번 더 누르면 팝업만 남기고 창이 닫힌다.
		if (DebounceIconSelectorFrame:IsShown()) then
			DebounceIconSelectorFrame:Close();
			return;
		end

		-- ESC는 한 단계씩 물러난다: 선택 해제(패널 접힘) -> 창 닫기.
		-- 패널에는 저장을 미루는 상태가 없으므로 잃을 게 없다.
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
	DebounceDetailPanel:CancelKeyCapture();

	if (DebounceIconSelectorFrame:IsShown()) then
		DebounceIconSelectorFrame:CancelButton_OnClick();
	end

	-- 매크로 본문은 아래 Hide()가 OnHide를 태우면서 저장된다.

	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:Hide();
end

function DebounceFrameMixin:OnLeaveCombat()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED");
	self:Show();
end

--- 목록은 키순으로 묶여 있으므로 키가 바뀌면 **다시 짜야** 한다. Update는 있는 줄을 그
--- 자리에서 고쳐 그릴 뿐이라, 우클릭 메뉴로 단축키를 푼 액션이 여전히 옛 키 헤더 밑에
--- 키 없이 앉아 있게 된다(오버뷰는 같은 이벤트에서 다시 짜므로 두 목록이 어긋난다).
--- 스크롤 자리는 지킨다 - 방금 만진 줄이 눈앞에서 사라지면 안 된다.
function DebounceFrameMixin:OnBindingsUpdated(_, skipped)
	self:Refresh(true);
	self:Update();
end

-- 물어보는 게 아니라 알리기만 하는 창이라 버튼이 하나뿐이다. GENERIC_CONFIRMATION은
-- 취소 버튼이 늘 붙는 데다 OnAccept에서 data.callback을 무조건 호출해서 (콜백이 없으면
-- 확인을 누르는 순간 에러) 이런 알림창에는 맞지 않는다.
StaticPopupDialogs["DEBOUNCE_NAME_SORT_NOTICE"] = {
	text = LLL["SORT_LIST_BY_NAME_NOTICE"],
	button1 = OKAY,
	showAlert = 1,
	hideOnEscape = 1,
	whileDead = 1,
	timeout = 0,
};

--- 정렬 방식을 바꿨을 때 목록을 다시 그린다.
--- 이름순은 **표시 순서일 뿐**이라 발동 순서와 무관하다. 그걸 모르면 목록 맨 위에 있는 게
--- 먼저 나가는 줄 안다. 계정당 딱 한 번 알린다.
function DebounceUI.NotifyMainListSortChanged(mode)
	if (mode == "name" and not DebouncePrivate.Options.nameSortNoticeShown) then
		DebouncePrivate.Options.nameSortNoticeShown = true;
		StaticPopup_Show("DEBOUNCE_NAME_SORT_NOTICE");
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
			elementData.sortName = strlower(NameAndIconForAction(elementData.action) or "");
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

		-- 키가 바뀌는 자리마다 헤더를 끼운다. 이름순에는 안 넣는다 - 그쪽은 묶음이 아니라
		-- 표시 순서일 뿐이라 그을 경계가 없다.
		--
		-- 헤더 elementData에는 action이 없다. 액션으로 찾는 쪽(FindElementDataByActionInfo)이
		-- 자연히 비켜가므로 선택·스크롤 경로는 헤더를 몰라도 된다.
		local grouped = {};
		local lastKey, started;
		for _, elementData in ipairs(elements) do
			local key = elementData.action.key;
			if (not started or key ~= lastKey) then
				grouped[#grouped + 1] = { isHeader = true, key = key, layer = layerID };
				lastKey, started = key, true;
			end
			grouped[#grouped + 1] = elementData;
		end
		elements = grouped;
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
		self:SetSelectedAction(nil);
	end

	local title = format(LLL["DEBOUNCE_TITLE_FORMAT"], GetTabLabel(_selectedTab), GetSideTabaLabel(_selectedSideTab));
	self:SetTitle(title);
	self:UpdateActionCounts();
	self:UpdateEmptyText();
end

--- 상세 패널이 보여줄 액션을 바꾼다. 언제나 성공한다.
---
--- 예전에는 패널이 저장 안 된 변경을 들고 거부할 수 있어서 false와 force가 있었다. 지금
--- 패널에는 미루는 저장이 없으므로(Close 참고) 거부할 일이 없다. 돌려주는 true는 부르는
--- 쪽의 옛 코드를 위해 남긴 것이다.
function DebounceFrameMixin:SetSelectedAction(action)
	if (_selectedAction == action) then
		return true;
	end

	DebounceDetailPanel:Close();

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

	self:UpdateDropOverlay();
end

--- 드래그 중에는 창 안쪽을 덮는다.
---
--- 목적은 "어느 줄에 떨궈야 하나"를 물을 수 없게 만드는 것이다 - 이 창은 떨어진 위치를
--- 보지 않는다. 행이 보이면 행마다 툴팁이 뜨고 각각이 목적지처럼 보인다.
---
--- 글로우는 **받을 때만** 켠다. 우리 행을 끄는 중이면 목적지는 탭이고, 같은 레이어에 다시
--- 놓는 것은 아무 일도 아니라서 OnReceiveDrag가 그냥 돌아선다. 그때 빛내면 "여기 떨궈라"
--- 해놓고 안 받는 꼴이 된다. 대신 안내문이 어디로 가야 하는지 말한다.
function DebounceFrameMixin:UpdateDropOverlay()
	local overlay = self.DropOverlay;
	local pickedUp = _pickedupInfo ~= nil;
	local shown = pickedUp or IsDraggingElement();

	overlay:SetShown(shown);
	if (not shown) then
		return;
	end

	-- 상세 패널이 useParentLevel이라 레벨이 부모를 따라 움직인다. 한 번 박아두지 않고
	-- 띄울 때마다 다시 잡는다(캡처 오버레이가 같은 이유로 그렇게 한다).
	overlay:SetFrameLevel(self:GetFrameLevel() + 100);

	overlay.Glow:SetShown(pickedUp);
	overlay.Prompt:SetText(pickedUp and LLL["LIST_DROP_PROMPT_ADD"] or LLL["LIST_DROP_PROMPT_MOVE"]);
end

--- 커서에 집어온 것을 놓는 동작은 드래그가 아니라 **클릭**이다. ScrollBox가 그랬던 것과
--- 같은 이유로 덮개도 클릭을 드롭으로 보낸다.
function DebounceFrameMixin:DropOverlay_OnMouseUp(button)
	if (button == "LeftButton" and GetActionTypeAndValueFromCursorInfo()) then
		self:OnReceiveDrag();
	end
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
	self.contextMenuAction = menu and elementData.action or nil;
	if (menu) then
		-- 메뉴가 닫혔다는 것을 알려주는 것은 이 콜백뿐이다. 여기서 다시 그리지 않으면 강조가
		-- 남은 채로 다음 Update를 기다리는데, 메뉴를 그냥 닫기만 한 경우 그 Update는 오지 않는다.
		--
		-- 앞서 열려 있던 메뉴는 새 메뉴가 열리면서 닫히므로, 늦게 도착한 콜백이 새 메뉴의
		-- 상태를 지우지 않도록 자기 것인지 확인한다.
		menu:SetClosedCallback(function()
			if (self.contextMenu ~= menu) then
				return;
			end
			self.contextMenu = nil;
			self.contextMenuAction = nil;
			self:Update();
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

	local name, icon = ColoredNameAndIconForAction(elementData.action);
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
	--
	-- 밖에서 끌어온 것은 곧바로 선택한다. 방금 생긴 액션은 키를 정해야 쓸모가 생기는데,
	-- 선택이 상세 패널을 열어 그 자리로 데려간다. 레이어를 옮긴 것은 이미 있던 액션이고
	-- 목적지가 다른 탭이라 여기 오지 않는다(같은 레이어면 위에서 돌아섰다).
	if (destLayerID == GetLayerID()) then
		if (not prevLayerID) then
			self:SetSelectedAction(action);
		end
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

--- 팝업을 여는 입구. 예전엔 호출자가 `mode`/`elementData`를 직접 꽂고 `Show()`를 불렀고,
--- 확인을 누르면 이 팝업이 매크로 편집기를 **직접** 열었다 - "나는 매크로에서 열렸다"가
--- 코드에 박혀 있었다. 이제 확인 뒤에 할 일은 연 쪽이 준다(`EditMacroText`의 `cancelFunc`과
--- 같은 모양). 콜백은 확인을 눌렀을 때만, 대상 elementData를 들고 불린다.
function DebounceIconSelectorFrameMixin:OpenForNewMacro(onAccepted)
	self.mode = IconSelectorPopupFrameModes.New;
	self.elementData = nil;
	self.onAccepted = onAccepted;
	self:Show();
end

--- 이미 있는 액션의 이름·아이콘만 고친다. `onAccepted`는 없어도 된다 - 팝업 아래 화면이
--- 그대로 살아 있으면 확인 뒤에 갈 데가 없다.
function DebounceIconSelectorFrameMixin:OpenForAction(elementData, onAccepted)
	self.mode = IconSelectorPopupFrameModes.Edit;
	self.elementData = elementData;
	self.onAccepted = onAccepted;
	self:Show();
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
	-- 블리자드의 OnShow/OnHide는 IconSelectorPopupFramesShown를 짝으로 올리고 내린다.
	-- 위에서 조기 반환하며 Hide한 경우에는 이 줄에 닿지 못하므로, OnHide도 짝이 없다는
	-- 것을 알아야 한다. 이 표시가 그 짝을 맞춘다.
	self.popupCounted = true;
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
	-- 짝이 있을 때만 내린다. OnShow가 조기 반환하며 Hide한 경로에서 그냥 부르면 올린 적
	-- 없는 카운터를 내려서 음수로 만들고, 그때부터 **진짜 열려 있는 블리자드 선택기에도**
	-- IsAnyIconSelectorPopupFrameShown()이 거짓을 답한다. 우리 창을 여닫을 때마다 더
	-- 내려가므로 세션이 끝날 때까지 돌아오지 않는다.
	if (self.popupCounted) then
		self.popupCounted = nil;
		IconSelectorPopupFrameTemplateMixin.OnHide(self);
	end
	self.elementData = nil;
	-- 취소로 닫혔든, OnShow가 대상을 못 찾아 도로 숨겼든 콜백은 죽는다. 확인을 누른 경우엔
	-- OkayButton_OnClick이 이미 꺼내 갔다.
	self.onAccepted = nil;
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

--- 편집 모드로 왔다면 매크로 오버레이가 이 팝업 아래에 그대로 열려 있다. 되돌릴 게 없다 -
--- 이름·아이콘을 안 건드렸으니 패널도 그대로다.
function DebounceIconSelectorFrameMixin:CancelButton_OnClick()
	IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self);
end

function DebounceIconSelectorFrameMixin:OkayButton_OnClick()
	local iconTexture = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture();
	local text = self.BorderBox.IconSelectorEditBox:GetText();
	text = string.gsub(text, "\"", "");

	local isNew = self.mode == IconSelectorPopupFrameModes.New;
	local elementData;
	if (isNew) then
		elementData = DebounceFrame:AddNewAction(Constants.MACROTEXT, "", text, iconTexture);
	else
		elementData = self.elementData;
		elementData.action.name = text;
		elementData.action.icon = iconTexture;
	end

	-- 이름이 바뀌면 이름순 정렬에서 자리가 바뀐다. Update는 있는 줄을 그 자리에서 고쳐
	-- 그릴 뿐이라 방금 바꾼 이름이 옛 자리에 남는다.
	DebounceFrame:Refresh(true);
	DebounceFrame:Update();

	-- 다음에 무엇이 열릴지는 이 팝업이 정하지 않는다. 연 쪽이 안다. 먼저 꺼내 두는 건
	-- 콜백이 이 창을 닫아도 OnHide가 같은 콜백을 두 번 부르지 않게 하려는 것이다.
	local onAccepted = self.onAccepted;
	self.onAccepted = nil;
	if (onAccepted and elementData) then
		onAccepted(elementData);
	end
	IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self);
end

function DebounceIconSelectorFrameMixin:HasUnsavedChanges()
	if (self:IsShown() and self.mode == IconSelectorPopupFrameModes.Edit) then
		local newName = string.gsub(self.BorderBox.IconSelectorEditBox:GetText(), "\"", "");
		local newIcon = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture();
		-- elementData는 OnHide에서 비워지는데 mode는 남는다. 부모 창이 팝업을 띄운 채로
		-- 숨으면 "보이는 상태 + Edit + elementData 없음"이 실제로 생긴다.
		if (not self.elementData) then
			return false;
		end
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

--- 탭은 **내용이 있는 것만** 단다. 조건 편집은 아직 패널로 오지 않았으므로 탭도 없다 -
--- 눌러서 빈 화면이 나오는 탭은 없는 것만 못하다.
---
--- 매크로 탭은 액션 종류를 안 가리고 늘 있다. 매크로텍스트가 아닌 액션에도 할 말이 있기
--- 때문이다("여기로 바꿀 수 있다" 또는 "바꿀 수 없다").
local DETAIL_TAB_KEY = 1;
local DETAIL_TAB_MACRO = 2;

function DebounceDetailPanelMixin:OnLoad()
	self.TabSystem:AddTab(LLL["DETAIL_TAB_KEY"]);
	self.TabSystem:AddTab(LLL["DETAIL_TAB_MACRO"]);
	self.TabSystem:SetTabSelectedCallback(function(tabID) self:SetTab(tabID); end);
	self.selectedTabID = DETAIL_TAB_KEY;
	self.TabSystem:SetTabVisuallySelected(DETAIL_TAB_KEY);

	local keyArea = self.ContentArea.KeyArea;

	-- 단축키 버튼이 곧 입력받이다. 듣는 중 표시는 블리자드 단축키 버튼이 쓰는 것과 같은
	-- 텍스처다(CustomBindingButtonTemplate).
	local selected = keyArea.KeyButton:CreateTexture(nil, "OVERLAY");
	selected:SetTexture("Interface\\Buttons\\UI-Silver-Button-Select");
	selected:SetBlendMode("ADD");
	selected:SetAllPoints(keyArea.KeyButton);
	selected:Hide();
	keyArea.KeyButton.SelectedHighlight = selected;
	keyArea.KeyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp");

	-- 단축키 문자열은 "Ctrl+Shift+Alt+마우스 버튼 3"까지 간다. 어떤 폭을 잡아도 넘칠 수
	-- 있고, UIPanelButtonTemplate의 ButtonText는 CENTER 앵커 하나뿐이라 폭이 없다 -
	-- 폭이 없는 FontString은 말줄임 없이 버튼 밖으로 그대로 삐져나온다. 양쪽을 물려
	-- 폭을 주면 한 줄로 잘리고 …가 붙는다. 잘린 전문은 툴팁이 말한다.
	local keyText = keyArea.KeyButton:GetFontString();
	keyText:ClearAllPoints();
	keyText:SetPoint("LEFT", 6, -1);
	keyText:SetPoint("RIGHT", -6, -1);
	keyText:SetWordWrap(false);


	-- 편집칸은 보이는 만큼만 크고, 넘치는 본문은 스크롤로 간다(기본 매크로 창도 편집칸과
	-- 스크롤 영역이 같은 크기다). 팝업이었을 때는 둘 다 XML에 박혀 있었는데, 탭이 되면서
	-- 패널 크기를 따라가야 한다.
	local editor = self.ContentArea.MacroArea.Editor;
	editor.ScrollFrame.EditBox:SetMaxLetters(MACRO_CHAR_LIMIT);
	editor.ScrollFrame:SetScript("OnSizeChanged", function(scrollFrame, width, height)
		scrollFrame.EditBox:SetSize(width, height);
	end);

	-- 버튼 글자는 우클릭 메뉴의 것과 같은 것을 쓴다. 같은 동작이 두 자리에 있으므로 이름도
	-- 같아야 한다.
	self.ContentArea.MacroArea.ConvertPrompt.ConvertButton:SetText(LLL["CONVERT_TO_MACRO_TEXT"]);

	self:InitializeOrderScrollBox();

	self.initialized = true;
	self:Refresh();
end

--- 선택이 바뀌었다. 듣던 중이었다면 그 액션의 것이었으므로 여기서 끝낸다.
function DebounceDetailPanelMixin:OnSelectionChanged()
	self:SetBindingMode(false);
	self:Refresh();
end

--- 탭을 고른다. 떠나는 탭은 자기 것을 정리한다 - 매크로 탭은 본문을 저장하고, 키 탭은
--- 듣던 키를 그만둔다. 나가는 길이 어디로 가든 같아야 하므로 여기 한 군데에만 둔다.
function DebounceDetailPanelMixin:SetTab(tabID)
	if (self.selectedTabID == tabID) then
		return;
	end

	if (self.selectedTabID == DETAIL_TAB_MACRO) then
		self:SaveMacroText();
	elseif (self.selectedTabID == DETAIL_TAB_KEY) then
		self:SetBindingMode(false);
	end

	self.selectedTabID = tabID;
	self.TabSystem:SetTabVisuallySelected(tabID);
	self:Refresh();
end

function DebounceDetailPanelMixin:Refresh()
	if (not self.initialized) then
		return;
	end

	local action = _selectedAction;
	if (not action) then
		-- 선택이 없으면 패널이 접힌다. 다음에 펴질 때를 위해 내용은 내려둔다.
		self.ContentArea.MacroArea:Hide();
		return;
	end

	local onMacroTab = self.selectedTabID == DETAIL_TAB_MACRO;
	self.ContentArea.KeyArea:SetShown(not onMacroTab);
	self.ContentArea.OrderArea:SetShown(not onMacroTab);
	self.ContentArea.MacroArea:SetShown(onMacroTab);

	if (onMacroTab) then
		self:RefreshMacroTab(action);
	else
		self:RefreshKeybind(action);
	end
end

--- 다른 것으로 넘어가기 전에 부르는 계약. 이 패널은 저장을 미루는 상태가 없다 - 키도
--- 순서도 누르는 즉시 반영되고, 매크로 본문은 **떠날 때 저장된다**(기본 매크로 창과
--- 같다). 그래서 아무것도 막지 않고 언제나 true다.
---
--- 선택은 건드리지 않는다. 부르는 쪽이 이미 선택을 바꾸는 중이다.
---
--- 마지막 Refresh를 빠뜨리면 안 된다. ClearMacroEdit는 편집 상태만 비우고 화면은 그대로
--- 두므로, 그 사이에 편집기가 **본문을 띄운 채 macroAction만 nil인** 상태가 된다. 그
--- 상태에서 친 글자는 SaveMacroText가 그냥 버리고, 다음 Update가 저장본으로 덮어쓴다.
--- 부르는 쪽이 곧바로 다시 그릴 것 같지만 아닌 길이 있다 - TryCloseAnyDialog가 이걸
--- "가도 되나?" 탐침으로 쓰는데, 이미 골라둔 탭을 다시 누르면 그 뒤로 아무 일도 안 한다.
function DebounceDetailPanelMixin:Close()
	self:CancelKeyCapture();
	self:SaveMacroText();
	self:ClearMacroEdit();
	self:Refresh();
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
	local name, icon = ColoredNameAndIconForAction(row.action);
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

	-- 지금 보고 있는 액션은 왼쪽 목록의 선택과 같은 하이라이트로 띄운다.
	self.SelectedHighlight:SetShown(elementData.isCurrent);

	-- 흑백은 여기서 정한다. 행 프레임은 풀에서 돌려쓰므로, 미리보기에서 회색이 된 프레임이
	-- 그대로 살아 있는 목록에 다시 나올 수 있다. 밖에서 한 번 칠하고 마는 방식으로는
	-- 그 프레임까지 되돌릴 수가 없다.
	self.Icon:SetDesaturated(elementData.desaturated or false);
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

--- 마우스가 이미 버튼 위에 있으면 OnEnter가 다시 안 불린다. 그러면 연타할 때 툴팁이
--- 방금 바뀐 상태가 아니라 **처음 올렸던 순간**의 상태를 계속 말한다 - 한 칸 올려서
--- 맨 위가 됐는데도 "한 칸 더 올릴 수 있다"고 떠 있는 식이다. 상태를 다시 계산했으면
--- 그 자리에서 툴팁도 다시 그린다.
local function RefreshOrderMoveTooltip(button)
	if (button:IsMouseMotionFocus()) then
		OrderMoveButton_OnEnter(button);
	end
end

--- 끝이라 못 움직이는 것과 규칙 때문에 못 움직이는 것은 다르다. 앞엣것은 설명할 게 없다 -
--- 맨 위에 있는 걸 더 올릴 수 없다는 건 비활성 버튼 그 자체로 이미 말이 된다.
local ORDER_END_REASONS = { ALREADY_FIRST = true, ALREADY_LAST = true };

--- 막힌 이유 한 덩어리를 툴팁에 붙인다. 위아래가 같은 이유로 막혔으면 한 번만 쓴다.
local function AddOrderBlockedReason(reasonKey, seen)
	if (not reasonKey or seen[reasonKey]) then
		return;
	end
	-- 앞에 이미 한 덩어리가 있으면 사이를 띄운다.
	if (next(seen)) then
		GameTooltip_AddBlankLineToTooltip(GameTooltip);
	end
	seen[reasonKey] = true;

	GameTooltip_AddErrorLine(GameTooltip, LLL[reasonKey]);
	local fix = rawget(LLL, reasonKey .. "_FIX");
	if (fix) then
		GameTooltip_AddBlankLineToTooltip(GameTooltip);
		GameTooltip_AddNormalLine(GameTooltip, fix);
	end
end

--- 화면에 있는 건 **질문**이고 답은 여기 있다. 이유를 화면에 늘어놓지 않는 이유는,
--- 위와 아래가 서로 다른 이유로 막힐 수 있어서 한 줄에 안 들어가기 때문이다.
local function OrderBlockedHelp_OnEnter(button)
	-- 흐린 글씨로 두면 두 번 진다 - 안 읽히고, 누를 수 있는 것으로도 안 보인다.
	-- 금색으로 두고 올라오면 밝힌다(와우에서 누를 수 있는 글자의 관례).
	button.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, button.Text:GetText());

	local seen = {};
	AddOrderBlockedReason(button.upReasonKey, seen);
	AddOrderBlockedReason(button.downReasonKey, seen);

	GameTooltip:Show();
end

local function OrderBlockedHelp_OnLeave(button)
	button.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB());
	GameTooltip_Hide();
end

function DebounceDetailPanelMixin:InitializeOrderScrollBox()
	local orderArea = self.ContentArea.OrderArea;
	local controls = orderArea.Controls;
	local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 2);
	view:SetElementInitializer("DebounceOrderLineTemplate", function(button, elementData)
		button:Init(elementData);
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(orderArea.ScrollBox, orderArea.ScrollBar, view);

	orderArea.Header.Label:SetText(LLL["ORDER"]);

	SquareButton_SetIcon(controls.MoveUpButton, "UP");
	SquareButton_SetIcon(controls.MoveDownButton, "DOWN");

	controls.MoveUpButton.titleKey = "ORDER_MOVE_UP";
	controls.MoveUpButton.descKey = "ORDER_MOVE_UP_DESC";
	controls.MoveDownButton.titleKey = "ORDER_MOVE_DOWN";
	controls.MoveDownButton.descKey = "ORDER_MOVE_DOWN_DESC";

	for _, button in ipairs({ controls.MoveUpButton, controls.MoveDownButton }) do
		button:SetScript("OnEnter", OrderMoveButton_OnEnter);
		button:SetScript("OnLeave", GameTooltip_Hide);
	end

	controls.MoveUpButton:SetScript("OnClick", function()
		self:ApplyOrderMove(self.moveUpInsertIndex);
	end);
	controls.MoveDownButton:SetScript("OnClick", function()
		self:ApplyOrderMove(self.moveDownInsertIndex);
	end);

	controls.BlockedHelp:SetScript("OnEnter", OrderBlockedHelp_OnEnter);
	controls.BlockedHelp:SetScript("OnLeave", OrderBlockedHelp_OnLeave);
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
	local controls = self.ContentArea.OrderArea.Controls;
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

	controls.MoveUpButton.reasonKey = upReason and ("ORDER_BLOCKED_" .. upReason) or nil;
	controls.MoveDownButton.reasonKey = downReason and ("ORDER_BLOCKED_" .. downReason) or nil;
	controls.MoveUpButton:SetEnabled(up ~= nil);
	controls.MoveDownButton:SetEnabled(down ~= nil);

	-- 버튼은 늘 서 있는다. 순서가 없으면(키 없음/비활성 특성) 비활성으로 남을 뿐이다 -
	-- 나타났다 사라지면 키를 지정하는 순간 줄이 통째로 움직인다.
	controls.MoveUpButton:Show();
	controls.MoveDownButton:Show();

	-- 맨 위/맨 아래라서 못 움직이는 건 설명할 것이 없다 - 비활성 버튼이 그 자체로
	-- "지금은 안 된다"를 말한다. 규칙 때문에 막힌 것만 아래 질문 줄이 받는다.
	self:UpdateOrderBlockedHelp(upReason, downReason);

	-- 방금 계산한 상태를 마우스가 올라가 있는 버튼의 툴팁에도 반영한다. 이걸 빠뜨리면
	-- 연타할 때 툴팁이 처음 올렸던 순간의 말을 계속 한다(위 함수 주석 참고).
	RefreshOrderMoveTooltip(controls.MoveUpButton);
	RefreshOrderMoveTooltip(controls.MoveDownButton);
end

--- 버튼이 **규칙 때문에** 죽어 있을 때만 그 옆에 질문 한 줄을 띄운다.
---
--- 비활성 버튼의 툴팁에 이미 같은 설명이 있지만, 비활성 버튼에 마우스를 올려보는 사람은
--- 거의 없다. 이 애드온에서 순서 규칙을 가르치는 문장이 거기 하나뿐이라, 화면으로 꺼낸다.
---
--- 화면에 내는 건 이유가 아니라 **질문**이다. 위와 아래가 서로 다른 이유로 막힐 수 있어서
--- 이유를 그대로 쓰면 한 줄에 안 들어가고, 늘 떠 있으면 잔소리가 된다.
function DebounceDetailPanelMixin:UpdateOrderBlockedHelp(upReason, downReason)
	local help = self.ContentArea.OrderArea.Controls.BlockedHelp;

	local blockedUp = upReason ~= nil and not ORDER_END_REASONS[upReason];
	local blockedDown = downReason ~= nil and not ORDER_END_REASONS[downReason];

	local questionKey;
	if (blockedUp and blockedDown) then
		questionKey = "ORDER_MOVE_BLOCKED";
	elseif (blockedUp) then
		questionKey = "ORDER_MOVE_BLOCKED_UP";
	elseif (blockedDown) then
		questionKey = "ORDER_MOVE_BLOCKED_DOWN";
	end

	help.upReasonKey = blockedUp and ("ORDER_BLOCKED_" .. upReason) or nil;
	help.downReasonKey = blockedDown and ("ORDER_BLOCKED_" .. downReason) or nil;

	-- 문장이 사라지는데 마우스가 그 위에 있었으면 툴팁이 남는다. 숨기기 **전에** 거둔다 -
	-- 숨은 뒤에는 IsMouseMotionFocus가 거짓이라 물어볼 수가 없다.
	if (questionKey == nil and help:IsMouseMotionFocus()) then
		GameTooltip_Hide();
	end

	help.Text:SetText(questionKey and LLL[questionKey] or "");
	-- 밝힌 채로 숨었다가 다시 나오면 마우스가 없는데도 밝은 채다. 그릴 때마다 되돌린다.
	help.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB());
	help:SetShown(questionKey ~= nil);

	-- 이동 버튼과 같은 이유로, 이미 올라가 있는 마우스에는 OnEnter가 다시 안 온다.
	if (questionKey and help:IsMouseMotionFocus()) then
		OrderBlockedHelp_OnEnter(help);
	end
end

--- 이 키에 걸린 액션 전부를 발동 순서로 그린다.
---
--- 다른 특성 탭을 보고 있으면 **그 특성이었을 때의** 순서를 그린다. 예전에는 그럴 때
--- "계산할 수 없다"고 말하고 빈 상자를 보여줬는데, 그건 사실이 아니었다 - 순서를 정하는
--- 값들은 전부 저장돼 있어서 지금 무슨 특성이든 계산이 된다. 못 했던 건 레이어를 훑는
--- 함수가 현재 특성을 안에서 물어봤기 때문이다. 이제 물어볼 수 있으므로 막다른 골목이 없다.
---
--- 대신 그 세계에서는 살아 있는 표시(도달 불가)를 붙이지 않는다. CollectActionsForKey가
--- 그 판단을 한다.
function DebounceDetailPanelMixin:RefreshOrderList(action)
	local orderArea = self.ContentArea.OrderArea;
	local key = action.key;

	orderArea:Show();

	-- 어느 특성의 세계를 보고 있나. 사이드탭 1·2(일반/직업)는 어느 특성에서도 활성이라
	-- 물어볼 게 없다 - 그 액션의 경쟁 상대는 지금 특성 기준이 맞다.
	local viewedSpec = _selectedSideTab >= 3 and (_selectedSideTab - 2) or nil;
	local simulated = viewedSpec ~= nil and viewedSpec ~= C_SpecializationInfo.GetSpecialization();

	-- 설명 줄은 **지금 화면이 참인지**에 따라 갈린다. 키가 없으면 아무것도 안 돌아가므로
	-- "위에서부터 시도한다"고 말하면 거짓말이고, 다른 특성의 순서라면 어느 특성인지 말해야
	-- 한다 - 안 그러면 지금 눌러도 이렇게 된다고 읽힌다.
	if (not key) then
		orderArea.DescLine.Text:SetText(LLL["ORDER_DESC_NO_KEY"]);
	elseif (simulated) then
		orderArea.DescLine.Text:SetText(format(LLL["ORDER_DESC_OTHER_SPEC"], GetSideTabaLabel(_selectedSideTab)));
	else
		orderArea.DescLine.Text:SetText(LLL["ORDER_DESC"]);
	end
	-- 줄 수가 문장마다 다르다. 아래 컨트롤과 리스트가 이 줄에 매달려 있으므로, 재서 잡지
	-- 않으면 두 줄짜리 문장이 버튼 위로 겹친다.
	orderArea.DescLine:SetHeight(orderArea.DescLine.Text:GetStringHeight());

	if (not key) then
		-- 키가 없어도 화면 **모양은 그대로** 둔다. 이 액션 하나를 그려놓고 전체를 죽여둔다 -
		-- 키를 주는 순간 자리가 새로 생기지 않고 색만 돌아온다. 지금 것은 실제 발동 순서가
		-- 아니므로 흑백으로 둔다.
		-- 안내문은 안 쓴다. 행을 그리는 자리와 겹친다 - 키가 없다는 건 버튼의 "Assign a Key"와
		-- 흑백으로 죽은 행이 이미 말한다.
		self:UpdateOrderMoveButtons(nil, nil);

		local preview = CreateDataProvider();
		preview:Insert({
			-- 행은 CollectActionsForKey가 주는 레코드와 같은 모양이어야 한다(Profile.lua).
			-- 빠진 필드는 "그 속성이 없다"로 읽히는데, 여기 액션은 키만 없을 뿐 나머지는
			-- 이미 정해져 있다 - 키를 주는 순간 없던 표시가 튀어나오면 안 된다.
			-- unreachable만 뺀다. 그건 정말로 키를 기준으로 정해지는 값이다.
			-- issue는 아니다 - 그룹·변신·보너스바 미선택처럼 키와 아무 상관 없는 것들이
			-- 같은 자리에서 나오므로, 통째로 빼면 키를 주는 순간 없던 표시가 튀어나온다.
			-- 그래서 키 항목만 빼고 묻는다.
			row = {
				action = action,
				layerID = GetLayerID(),
				priority = action.priority or Constants.DEFAULT_PRIORITY,
				hover = action.hover,
				isConditional = DebouncePrivate.IsConditionalAction(action),
				issue = DebouncePrivate.GetBindingIssue(action, nil, "key"),
			},
			rank = 1,
			isCurrent = true,
			-- 흑백으로 돌린다. 알파를 내리면 색이 남아 "그냥 흐린 목록"으로 읽힌다.
			-- 행이 자기 데이터를 보고 칠하므로 프레임을 돌려써도 따라오지 않는다.
			desaturated = true,
		});
		orderArea.ScrollBox:SetDataProvider(preview, ScrollBoxConstants.DiscardScrollPosition);
		return;
	end

	local rows = DebouncePrivate.CollectActionsForKey(key, viewedSpec);

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
	-- 편집 중인 액션은 이제 반드시 목록 안에 있다(그 액션이 사는 레이어를 훑었으므로).
	-- 그래도 없으면 스크롤만 건드리지 않는다 - 목록 자체는 이 키의 사실이라 보여줄 값어치가 있다.
	if (currentIndex) then
		orderArea.ScrollBox:ScrollToElementDataIndex(currentIndex, ScrollBoxConstants.AlignNearest);
	end
end

--- 단축키 줄은 캡처 여부와 무관하게 늘 같은 모습이다. 캡처 중에는 오버레이가 덮으므로
--- 바꿔봐야 안 보이고, 안 바꾸면 취소했을 때 아무것도 안 움직인다.
--- 높이는 실제로 그린 만큼만 잡는다 - 남기면 그만큼 순서 리스트가 줄어든다.
function DebounceDetailPanelMixin:RefreshKeybind(action)
	local keyArea = self.ContentArea.KeyArea;
	local key = action.key;

	keyArea.Header.Label:SetText(LLL["KEY"]);
	-- 덮개가 없어졌으므로 이 줄이 늘 보인다. 말은 블리자드 단축키 버튼의 것을 그대로 쓰되
	-- (사용자가 단축키 창에서 이미 보고 있다) 흐리게는 하지 않는다. 거기서는 안 걸린 키가
	-- 정상이지만 - 키마다 바인딩을 둘씩 넣는 사람은 없다 - 여기 액션은 사용자가 직접 만든
	-- 것이라 키가 없으면 아무 일도 안 하는 물건이다. 흐리게 하면 그게 괜찮아 보인다.
	-- 무엇을 하라는지는 툴팁이 말한다.
	keyArea.KeyButton:SetText(key and GetBindingText(key) or LLL["DETAIL_NO_KEY"]);

	-- 안내는 지금 필요한 것만 말한다. 키가 없으면 "어떻게 거는가"가, 있으면 "어떻게
	-- 바꾸고 푸는가"가 궁금한 것이다. 둘 다 적으면 한 줄에 안 들어간다.
	keyArea.HintText:SetText(LLL[key and "DETAIL_KEY_HINT" or "DETAIL_KEY_HINT_NO_KEY"]);

	local warning = GetKeyWarningText(action, key);
	keyArea.WarningText:SetText(warning or "");

	-- 높이는 **재서** 잡는다. 안내도 경고도 몇 줄이 될지 여기서 알 수가 없다 - 패널 폭과
	-- 번역에 따라 달라진다. 숫자로 박아두면 긴 문장이 인셋 밖으로 나가거나(짧게 잡으면)
	-- 순서 리스트를 그만큼 잡아먹는다(넉넉히 잡으면).
	-- 50 = 헤더 16 + 4 + 단축키 버튼 26 + 4. 그 아래는 글자가 차지하는 만큼이다.
	local height = 50 + keyArea.HintText:GetStringHeight();
	if (warning) then
		height = height + keyArea.WarningText:GetStringHeight() + 4;
	end
	keyArea:SetHeight(height + 2);

	self:RefreshOrderList(action);
end

--- 지금 단축키를 듣고 있는가.
---
--- **사용자가 버튼을 눌러서 들어온 상태만** 참이다. 예전에는 키가 없는 액션이면 무조건
--- 참이었는데, 그러면 사용자가 연 적 없는 모드가 열려서 다른 모든 동작이 "지금 캡처하면
--- 안 된다"를 따로 판단해야 했다. 지금은 버튼 하나의 상태라 그럴 일이 없다.
function DebounceDetailPanelMixin:IsCapturingKey()
	return self.bindingMode == true;
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
	-- 키가 없을 때도 낸다. 툴팁은 처음 한 번 읽고 마는 것이라, 그때 안 보이면 영영 모른다.
	GameTooltip_AddNormalLine(GameTooltip, LLL["DETAIL_KEY_BUTTON_UNBIND_DESC"]);
	GameTooltip:Show();
end

--- 버튼을 듣는 상태로 넣고 뺀다.
---
--- 듣는 동안에만 키보드·휠·게임패드를 켠다. 평소에는 좌/우클릭만 받으므로 이 패널이 상설로
--- 떠 있어도 키보드를 먹지 않는다.
function DebounceDetailPanelMixin:SetBindingMode(active)
	active = (active and _selectedAction ~= nil) or false;
	if (self:IsCapturingKey() == active) then
		return;
	end
	self.bindingMode = active or nil;

	local button = self.ContentArea.KeyArea.KeyButton;
	button.SelectedHighlight:SetShown(active);
	button:EnableKeyboard(active);
	button:EnableMouseWheel(active);
	if (button.EnableGamePadButton) then
		button:EnableGamePadButton(active);
	end
	if (active) then
		-- 듣는 중에도 **떼는 순간**을 받는다. 누르는 순간으로 바꾸면 안 된다 - 그러면 키를
		-- 잡으면서 듣기가 꺼지고, 꺼지는 길에 등록이 up으로 되돌아가면서 아직 떼지도 않은
		-- 그 클릭의 나머지 반쪽이 **새 클릭처럼** 다시 들어온다(우클릭은 지정 직후 스스로
		-- 해제되고, 좌클릭은 지정하자마자 다시 듣기로 들어간다).
		--
		-- 들고 나는 자리를 양쪽 다 up으로 맞춰두면 그 반쪽이 아예 생기지 않는다. 한 번
		-- 누르면 up은 한 번뿐이고, 그 하나를 처리하면서 바꾼 등록은 다음 클릭부터 듣는다.
		-- 블리자드의 단축키 버튼도 상태 전환을 전부 뗄 때 한다(CustomBindingButtonMixin).
		--
		-- 여기서 AnyUp인 이유는 BUTTON3/4/5도 단축키가 되기 때문이다. 안 듣는 동안에는
		-- 좌/우클릭만 받으므로 가운데 버튼이 엉뚱한 데서 먹히지 않는다.
		button:RegisterForClicks("AnyUp");
	else
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
		-- 여기서 SetPropagateKeyboardInput(true)로 되돌리면 안 된다. ESC로 빠져나오는 그
		-- 순간에 다시 켜지면서 **같은 ESC가 프레임까지 흘러가 창을 닫는다.** 키보드 자체를
		-- 끄므로 이 값은 어차피 다음에 들을 때까지 아무 일도 하지 않는다.
	end

	self:Refresh();
	DebounceFrame:Update();
end

--- 좌클릭 = 지정 시작, 우클릭 = 해제. 듣는 중이면 뗀 버튼이 곧 단축키다.
---
--- 들어오는 클릭도 나가는 클릭도 전부 up이다(SetBindingMode 참고). 그래서 "이 클릭은
--- 방금 처리한 그 클릭의 나머지 반쪽인가"를 따로 기억할 필요가 없다.
function DebounceDetailPanelMixin:KeyButton_OnClick(button, mouseButton)
	if (self:IsCapturingKey()) then
		self:KeyButton_OnInput(mouseButton);
		return;
	end
	if (mouseButton == "RightButton") then
		self:UnbindKey();
		return;
	end
	self:SetBindingMode(true);
end

function DebounceDetailPanelMixin:KeyButton_OnKeyDown(button, key)
	if (not self:IsCapturingKey()) then
		button:SetPropagateKeyboardInput(true);
		return;
	end
	-- 전투 중 SetPropagateKeyboardInput은 taint다. 전투에 들어가면 창이 숨고 OnHide가
	-- 듣기를 끄므로 보통은 여기까지 오지 않지만, 전투가 시작된 바로 그 프레임에 눌린 키는
	-- PLAYER_REGEN_DISABLED보다 먼저 들어올 수 있다. 그 한 프레임을 여기서 막는다.
	if (InCombatLockdown()) then
		return;
	end
	button:SetPropagateKeyboardInput(false);
	if (key == "ESCAPE") then
		self:SetBindingMode(false);
		return;
	end
	self:KeyButton_OnInput(key);
end

--- 키보드·마우스·휠·게임패드가 모두 지나는 길목.
function DebounceDetailPanelMixin:KeyButton_OnInput(input)
	if (not self:IsCapturingKey()) then
		return;
	end
	if (IsMetaKey(input) or input == "UNKNOWN") then
		return;
	end

	local key = GetConvertedKeyOrButton(input);
	key = _CreateKeyChordStringUsingMetaKeyState(key);

	self:SetBindingMode(false);
	self:SetActionKey(key);
end

--- 듣기를 그만둔다. 선택은 건드리지 않는다.
---
--- 예전에는 키 없는 액션에서 오버레이가 늘 걸려 있어서 "선택을 푸는 것"이 유일한 출구였고,
--- 그래서 선택을 지킬지 말지를 인자로 받았다. 듣는 상태가 사용자가 연 것이 되면서 그냥
--- 나오면 되므로 인자도 사라졌다.
function DebounceDetailPanelMixin:CancelKeyCapture()
	self:SetBindingMode(false);
end

--- 단축키 해제. 단축키 버튼 우클릭과 우클릭 메뉴가 **둘 다 여기로 온다.** 같은 동작이
--- 어디서 눌렸느냐에 따라 다른 결과를 내면 안 된다.
---
--- 선택은 그대로 둔다. 키가 없어도 패널은 그 액션을 계속 보여준다 - 키를 지우자마자
--- 목록으로 튕겨나가면 방금 무엇을 한 건지 볼 자리가 없다.
function DebounceDetailPanelMixin:UnbindKey()
	if (not _selectedAction) then
		return;
	end
	self:SetBindingMode(false);
	self:SetActionKey(nil);
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


--------------------------------------------------------------------------------
-- 매크로 탭
--
-- 저장 규칙은 기본 매크로 창(Blizzard_MacroUI.lua)을 그대로 따른다: **떠날 때 저장.**
-- 거기서는 다른 매크로를 고르거나, 창이 닫히거나, 이름/아이콘 편집기를 열면 SaveMacro()가
-- 묻지 않고 불린다. 여기서는 그 목록에 **다른 탭으로 가는 것**이 하나 더 붙는다. 버리는
-- 길은 [취소] 버튼 하나뿐이다.
--
-- 그래서 이 패널에는 저장을 미루는 상태가 없다. HasUnsavedChanges / 저장-버림 팝업 /
-- Close(force) 계약이 전부 사라졌다 - 그것들이 존재하던 유일한 이유가 매크로 편집기였다.
--
-- 편집 대상(macroAction)은 **선택이 살아 있는 동안만** 산다. Close가 저장하고 비우므로,
-- 다음에 매크로 탭을 그릴 때 Refresh가 그 액션의 본문을 새로 올린다.
--------------------------------------------------------------------------------

--- 매크로 탭을 연다.
---
--- 패널은 선택된 액션만 그리므로 **편집 대상을 선택으로 옮긴다.** 진입점(CTRL-우클릭,
--- 우클릭 메뉴, 매크로텍스트 변환)이 선택과 무관한 행을 가리킬 수 있기 때문이다.
---
--- 탭이 이미 매크로였으면 SetTab이 아무것도 하지 않으므로 Refresh를 직접 부른다. 본문을
--- 올리는 건 언제나 Refresh 한 군데다 - 여는 길이 셋인데 채우는 자리가 여럿이면 어긋난다.
---
--- cancelFunc는 매크로텍스트 변환이 [취소]에서 원래 액션으로 되돌리는 데 쓴다. 본문을
--- 올리면서 지워지므로(앞 편집의 것이다) 그 뒤에 건다.
function DebounceDetailPanelMixin:EditMacroText(action, cancelFunc)
	if (not action or action.type ~= Constants.MACROTEXT) then
		return false;
	end
	DebounceFrame:SetSelectedAction(action);

	self:SetTab(DETAIL_TAB_MACRO);
	self:Refresh();
	self.macroCancelFunc = cancelFunc;

	DebounceFrame:Update();
	return true;
end

--- 본문을 편집칸에 올린다. **대상이 바뀔 때만** 부른다 - Refresh는 자주 도는데 거기서
--- 매번 넣으면 타이핑이 지워진다.
function DebounceDetailPanelMixin:LoadMacroText(action)
	self.macroAction = action;
	self.macroCancelFunc = nil;
	self.macroOriginalText = action.value or "";
	self.ContentArea.MacroArea.Editor.ScrollFrame.EditBox:SetText(self.macroOriginalText);
end

--- 편집 상태만 비운다. 화면 갱신은 부르는 쪽이 한다.
function DebounceDetailPanelMixin:ClearMacroEdit()
	self.macroAction = nil;
	self.macroCancelFunc = nil;
	self.macroOriginalText = nil;
end

--- 실제로 바뀌었을 때만 쓴다. 기본 매크로 창의 textChanged 검사와 같은 뜻이다.
function DebounceDetailPanelMixin:SaveMacroText()
	local action = self.macroAction;
	if (not action) then
		return;
	end

	local text = self.ContentArea.MacroArea.Editor.ScrollFrame.EditBox:GetText();
	if (text == self.macroOriginalText) then
		return;
	end

	action.value = text;
	action._dirty = true;
	self.macroOriginalText = text;
	DebouncePrivate.UpdateBindings();
end

--- [취소] = 이 탭에서 고친 것을 버린다.
---
--- 팝업이었을 때는 "닫으면서 버린다"였는데 탭에는 닫는다는 게 없다. 그래서 본문만 열었을
--- 때로 되돌리고 그 자리에 남는다.
---
--- 매크로텍스트 변환으로 들어왔다면 되돌릴 것이 본문이 아니라 **액션 자체**다(cancelFunc).
--- 되돌린 액션은 더 이상 매크로텍스트가 아니므로 편집기 자리에 "변환할까?" 안내가 대신
--- 들어선다. 탭은 그대로 둔다 - 탭은 모드가 아니라 보기라서 사용자가 옮기기 전까지 있던
--- 자리에 있는다.
function DebounceDetailPanelMixin:MacroCancel_OnClick()
	local action = self.macroAction;
	if (not action) then
		return;
	end
	PlaySound(SOUNDKIT.GS_TITLE_OPTION_OK);

	local cancelFunc = self.macroCancelFunc;
	if (cancelFunc) then
		-- 먼저 비운다. 안 그러면 되돌린 액션 위에 방금 버린 본문이 다시 저장된다.
		self:ClearMacroEdit();
		cancelFunc();
	else
		self.ContentArea.MacroArea.Editor.ScrollFrame.EditBox:SetText(self.macroOriginalText or "");
	end

	self:Refresh();
	DebounceFrame:Refresh(true);
	DebounceFrame:Update();
end

--- 이름/아이콘 편집기로 간다. 기본 매크로 창도 이 시점에 저장한다(MacroEditButton_OnClick).
---
--- 탭은 **열어둔 채로** 팝업이 그 위에 뜬다. 그래서 돌아왔을 때 본문이 그대로 있고,
--- 예전에 본문을 들고 다니던 tempText 곡예가 통째로 필요 없어졌다.
function DebounceDetailPanelMixin:MacroEditNameIcon_OnClick()
	local action = self.macroAction;
	if (not action) then
		return;
	end
	self:SaveMacroText();

	local elementData = DebounceFrame:FindElementDataByActionInfo(action);
	if (not elementData) then
		return;
	end

	-- 확인을 눌러도 갈 데가 없다. 매크로 탭이 이 팝업 아래에 그대로 열려 있고, 새 이름·아이콘은
	-- 팝업이 닫히면서 도는 Update가 되비춘다.
	DebounceIconSelectorFrame:OpenForAction(elementData);
end

function DebounceDetailPanelMixin:MacroText_OnTextChanged(editBox)
	ScrollingEdit_OnTextChanged(editBox, editBox:GetParent());
	self.ContentArea.MacroArea.Editor.CharLimitText:SetFormattedText(
		LLL["MACROFRAME_CHAR_LIMIT"], editBox:GetNumLetters(), MACRO_CHAR_LIMIT);
end

--- 매크로텍스트로 바꾼다. 우클릭 메뉴의 [매크로 텍스트로 전환]과 **같은 동작**이다
--- (DropDownMenus.lua의 CreateConvertToMacroTextMenuItem). 같은 일이 두 자리에 있으므로
--- 되돌리는 방법도 같다 - 바꾸기 전 액션을 통째로 떠서 [취소]에 매단다.
function DebounceDetailPanelMixin:MacroConvert_OnClick()
	local action = _selectedAction;
	if (not action or not DebouncePrivate.CanConvertToMacroText(action)) then
		return;
	end

	local original = CopyTable(action);
	if (not DebouncePrivate.ConvertToMacroText(action)) then
		return;
	end

	action._dirty = true;
	DebouncePrivate.UpdateBindings();

	-- 액션 테이블은 그대로 두고 내용만 되돌린다. 목록의 elementData가 이 테이블을 들고 있다.
	self:EditMacroText(action, function()
		wipe(action);
		MergeTable(action, original);
		action._dirty = true;
		DebouncePrivate.UpdateBindings();
	end);

	DebounceFrame:Refresh(true);
	DebounceFrame:Update();
end

--- 매크로 탭을 되비춘다. 이름·아이콘은 매번, 본문은 대상이 바뀌었을 때만.
--- 아이콘 선택기를 다녀오면 여기서 새 이름·아이콘이 반영된다.
function DebounceDetailPanelMixin:RefreshMacroTab(action)
	local macroArea = self.ContentArea.MacroArea;
	local isMacroText = action.type == Constants.MACROTEXT;

	macroArea.Editor:SetShown(isMacroText);
	macroArea.ConvertPrompt:SetShown(not isMacroText);

	if (not isMacroText) then
		-- 편집기가 아니므로 들고 있을 본문도 없다. 앞의 것이 남아 있으면 떠나는 것이니
		-- 저장부터(선택을 바꾸는 길은 Close를 지나므로 보통 이미 저장돼 있다).
		self:SaveMacroText();
		self:ClearMacroEdit();

		local canConvert = DebouncePrivate.CanConvertToMacroText(action);
		macroArea.ConvertPrompt.Message:SetText(
			LLL[canConvert and "MACRO_TAB_CONVERT_DESC" or "MACRO_TAB_NOT_CONVERTIBLE"]);
		macroArea.ConvertPrompt.ConvertButton:SetShown(canConvert);
		return;
	end

	if (self.macroAction ~= action) then
		self:SaveMacroText();
		self:LoadMacroText(action);
	end

	macroArea.Editor.SelectedMacroName:SetText(action.name or "");
	macroArea.Editor.SelectedMacroButton.Icon:SetTexture(action.icon);
end

--------------------------------------------------------------------------------

DebounceOverviewFrameMixin = {}

function DebounceOverviewFrameMixin:OnLoad()
	self.initialized = true;

	RegisterAsSpecialFrame("DebounceOverviewFrame");

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

	-- 이 줄도 단축키를 따로 보여주므로 메인 목록과 같은 규칙을 쓴다. 안 넘기면 키 문제로
	-- 이름 전체가 빨개져서, 같은 액션을 두 화면이 서로 다른 범인으로 가리킨다.
	local name, icon = ColoredNameAndIconForAction(action, "key");

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

	-- 이름에서 뺀 만큼 여기서 말한다. 키 문제는 키 옆에서.
	local bindingText = GetBindingText(action.key);
	if (bindingText and GetBindingIssue(action, "key")) then
		bindingText = ERROR_COLOR:WrapTextInColorCode(bindingText);
	end
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
	elseif (not GameMenuFrame:IsShown()) then
		-- 게임메뉴가 떠 있으면 열지 않는다. DebouncePublic:ToggleUI()와 같은 이유다.
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
DebounceUI.NameAndIconForAction = NameAndIconForAction;
DebounceUI.ShowInputBox = ShowInputBox
