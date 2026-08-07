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
local GetSpellNameAndIconID  = DebouncePrivate.GetSpellNameAndIconID;
local GetSpellTabNameAndIcon = DebouncePrivate.GetSpellTabNameAndIcon;
local InCombatLockdown       = InCombatLockdown;
local QUESTION_MARK_ICON_NUM = 134400;
local TEMP_MACRO_NAME        = "zzDbncTmpMcr"

--- 탭 1·2는 레이어 좌표의 절반이다(나머지 절반이 사이드탭). **탭 3은 그 축 밖이다** -
--- 활성 레이어 전부를 키로 묶어 한 목록에 놓는 읽기 위주의 뷰라 대응하는 레이어가 없다.
--- 그래서 `GetLayerID`에 이 번호를 넘기면 안 되고, 넘길 뻔한 자리마다 `IsOverviewTab`이 서 있다.
local OVERVIEW_TAB           = 3;

local _selectedTab           = 1;
local _selectedSideTab       = 1;
-- 이 창의 행은 끌 수 없다. 목록 안 재배치도(Phase 3), 탭에 떨궈 레이어를 옮기는 것도
-- 없앴다 - 후자는 우클릭 `Move to`가 더 잘 하고, 드래그는 행을 집게 해놓고 목록은 안
-- 받으니 매번 창을 덮어 "여기 아니다"라고 말해야 했다.
--
-- 남은 것은 하나, **게임이 커서에 집어준 것**을 받는 길이다. 주문책·액션바·가방에서 끌어온
-- 것을 목록이나 탭에 떨구면 그 레이어 맨 뒤에 붙는다. 아이템처럼 스펠 선택 창에 없는
-- 타입은 이 길로만 들어온다.
local _pickedupInfo;
-- 상세 패널이 보여주는 액션. elementData가 아니라 action 테이블을 들고 있는 이유는
-- elementData가 Refresh마다 새로 만들어지기 때문이다 (DebounceFrameMixin:Refresh).
local _selectedAction;

--- 오버뷰 탭에서 **필터가 빼지 못하는 액션들.**
---
--- 문제 필터를 켠 채로 그 행의 문제를 고치면 조건에서 벗어난다. 거기서 빼버리면 `Refresh`가
--- "선택이 목록에 없다"며 선택을 풀고 상세 패널이 접힌다 - **방금 한 일의 결과를 볼 자리가
--- 사라진다.** 그래서 사용자가 손대고 있는 액션은 붙들어 둔다(흐리게 그린다).
---
--- **"고쳐진 것을 보여주는 표"가 아니다. "발밑"의 표다.** 남을 고쳐서 곁다리로 나아진 행은
--- 그냥 사라져야 한다 - 사라지는 것 자체가 "이제 문제가 아니다"라는 신호고, 탭 라벨의
--- 숫자가 같이 줄어든다. 둘을 한 표에 섞으면 흐린 행이 끝없이 쌓인다.
---
--- 채우는 곳: `SetSelectedAction`, `ShowEditDropdown`(낙관적으로 - 아래 그 함수 주석).
--- 비우는 곳: **사용자가 뷰를 바꾼 순간뿐이다** - 필터 토글, 탭 이동, 창 열기.
--- `OnBindingsUpdated`에서는 절대 비우지 않는다. 그게 이 표가 살려야 할 바로 그 순간이다.
local _overviewRemembered    = {};

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
		-- 예전엔 `MAX_ACCOUNT_MACROS` 전역을 그대로 썼는데 **그런 전역은 없다.** 여기서
		-- 숫자와 nil을 비교하다 터지고 있었고, 오류를 삼키는 애드온을 쓰면 이 함수만
		-- 조용히 죽어서 매크로텍스트 아이콘이 영영 물음표로 남는다.
		local maxAccountMacros, maxCharacterMacros = DebouncePrivate.GetMacroSlotLimits();
		local isCharacterSpecific;
		if (cnt1 >= maxAccountMacros) then
			if (cnt2 >= maxCharacterMacros) then
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
	wipe(_macrotextIconCache);
end

local BINDING_TYPE_NAMES   = {
	[Constants.SPELL] = LLL["TYPE_SPELL"],
	[Constants.ITEM] = LLL["TYPE_ITEM"],
	[Constants.MACRO] = LLL["TYPE_MACRO"],
	[Constants.MACROTEXT] = LLL["TYPE_MACROTEXT"],
	[Constants.MOUNT] = LLL["TYPE_MOUNT"],
	[Constants.PETACTION] = LLL["TYPE_PETACTION"],
	[Constants.FLYOUT] = LLL["TYPE_FLYOUT"],
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
		-- `none`은 "대상 없음"이 아니다. **실행할 때 타겟 입력을 받게 하는 것**이다 -
		-- 지금 대상이 있든 없든 상관없이 대상 지정 모드로 들어가고, 사용자가 찍는다.
		-- 자동 자기시전도 안 걸린다. 그게 와우 동작이고 이 항목의 설명(UNIT_NONE_DESC)이다.
		--
		-- 그래서 **시전에만 있는 개념**이다. 소환수 명령은 대상 지정 모드로 들어가는 시전이
		-- 아니라 그냥 실행되는 명령이라, 받을 입력이 없다.
		--
		-- **게임에서 확인함(2026-08-05).** 같은 조건절을 두 명령에 넣어 비교했다:
		--   `/cast [@none] 화염구`   → 된다 (타겟 입력을 받는다)
		--   `/petattack [@none]`     → 안 된다
		-- 조건절 자체는 멀쩡하고 **명령 쪽이 안 받는다.** 추론이 아니라 실측이다.
		petaction = false,
		unitexists = false,
	},
};

--- 대상 목록을 **보여줄 순서.** `UNIT_INFO`는 해시라 순서가 없어서 이 배열이 필요하다.
---
--- 여기 있는 것이 곧 목록이다 - `UNIT_INFO`에만 있고 여기 없는 유닛은 어느 메뉴에도
--- 안 나온다. 어느 타입이 어느 유닛을 받는지는 `UNIT_INFO[unit][type] ~= false`가 따로 답한다.
---
--- **`DebounceUI`에 둔 것은 두 곳이 쓰기 때문이다.** [추가] 드롭다운(`DropDownMenus.lua`)과
--- 선택 창의 기타 탭(`ActionCatalog.lua`)이 같은 목록을 걸어야 한다 - 한때 `TYPES_WITH_UNIT`이
--- 두 파일에 복사돼 있다가 한쪽만 고쳐져서 펫 명령의 대상이 조용히 지워진 적이 있다.
local SORTED_UNIT_LIST     = {
	"player",
	"pet",
	"target",
	"focus",
	"mouseover",
	"tank",
	"healer",
	"maintank",
	"mainassist",
	"custom1",
	"custom2",
	"hover",
	"none",
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

--- 지금 보고 있는(또는 물어본) 탭이 오버뷰인가. 이 탭에는 대응하는 레이어가 없다.
local function IsOverviewTab(tab)
	return (tab or _selectedTab) == OVERVIEW_TAB;
end

--- **오버뷰 탭을 넘기면 터진다.** 조용히 레이어 하나를 골라 주면 그게 더 나쁘다 -
--- 액션이 엉뚱한 레이어에 생기거나 지워지고, 화면에는 아무 표시도 안 난다. 부르기 전에
--- `IsOverviewTab`으로 갈라서는 것이 이 함수를 쓰는 쪽의 계약이다.
local function GetLayerID(tab, sideTab)
	tab = tab or _selectedTab;
	sideTab = sideTab or _selectedSideTab;
	assert(tab ~= OVERVIEW_TAB, "overview tab has no layer");
	local isCharacterSpecific = tab == 2;
	local spec = sideTab >= 2 and sideTab - 2 or nil;
	return DebouncePrivate.GetLayerID(spec, isCharacterSpecific);
end

--- GetLayerID의 역방향. 레이어가 어느 탭 좌표에 사는지 돌려준다.
---
--- 레이어 7은 (nil, true)와 (0, true) 양쪽에서 나오지만 - 탭2에는 "직업 공용"에 해당하는
--- 사이드탭이 없어서 UpdateSideTabs가 사이드탭2를 숨긴다 - 되돌릴 때는 사이드탭 1을 준다.
--- 탭2에서 레이어 7이 실제로 서 있는 자리가 그것이다.
local function GetLayerTabs(layerID)
	if (layerID >= 7) then
		local spec = layerID - 7;
		return 2, spec > 0 and spec + 2 or 1;
	end
	return 1, layerID == 1 and 1 or layerID;
end

--- 탭 라벨은 **낱말 하나**다. 예전에는 "공유 바인딩" / "%s 전용 바인딩"이었는데, 탭이
--- 셋이 되면서 줄에 안 들어간다. "바인딩"은 어느 탭에서나 참이라 셋을 가르는 일을 안 하고,
--- 창 제목이 같은 값을 한 번 더 말하므로 뜻도 안 잃는다.
local function GetTabLabel(tabID)
	if (tabID == 1) then
		return LLL["SHARED_BINDINGS"];
	elseif (tabID == OVERVIEW_TAB) then
		return LLL["OVERVIEW"];
	else
		return UnitName("player");
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

--- layerID를 사람이 읽는 라벨로. 탭 라벨을 그대로 쓴다 - 직업명·특성명·캐릭터명이라
--- 새로 배울 게 없다. 좌표는 GetLayerTabs가 낸다.
---
--- 레이어가 섞이는 목록의 행 툴팁이 쓴다(순서 리스트, 오버뷰 탭). 거기서는 범위가 아이콘
--- 두 칸으로만 나오므로 낱말로 확인할 길이 이것뿐이다.
local function GetLayerLabel(layerID)
	local tab, sideTab = GetLayerTabs(layerID);
	local scope = tab == 2 and UnitName("player") or LLL["SHARED_BINDINGS"];
	return format(LLL["ORDER_LAYER_LABEL"], scope, GetSideTabaLabel(sideTab));
end

--- 오버뷰 목록에 있고 없고를 정하는 **두 값.** 그 밖의 편집은 이 둘을 못 건드리므로 행을
--- 사라지게 할 수 없다 - 매크로 본문도, 이름도, 아이콘도 여기 안 들어온다.
---
--- 조건이 새로 생겨도 안 썩는다. 필드를 나열하지 않고 `GetBindingIssue`에게 묻기 때문이다.
local function GetOverviewMembership(action)
	return action.key, GetBindingIssue(action);
end

local function RememberOverviewAction(action)
	if (action) then
		_overviewRemembered[action] = true;
	end
end

local function ForgetOverviewAction(action)
	_overviewRemembered[action] = nil;
end

--- 뷰가 바뀌었다. 붙들고 있던 것을 전부 놓는다.
local function ForgetOverviewActions()
	wipe(_overviewRemembered);
end

--- 오버뷰 탭의 필터 둘. 둘 다 **기본은 끔**이고, 켠 사람만 `true`가 저장된다.
---
--- **기본값이 가장 넓은 상태여야 한다.** 필터 버튼의 X는 "기본으로 되돌린다"인데, 기본이
--- 좁은 쪽이면 그 버튼이 **결과를 좁히는** 물건이 된다. 필터를 지우는 자리에서 목록이
--- 줄어드는 것은 어느 화면에서도 말이 안 된다.
---
--- 그래서 키 없는 액션도 기본으로 보인다(맨 위 "단축키 없음" 그룹). 레이어 탭이 이미
--- 그 자리에 그것들을 모아 두고 있어서 새로 배울 것도 없다. 키 필터를 켜면 이 탭이
--- 원래 답하던 질문 하나로 좁혀진다 - **"지금 내 키보드가 어떻게 생겼나."**
local function IsBoundOnlyEnabled()
	return DebouncePrivate.Options.overviewBoundOnly == true;
end

local function IsProblemsOnlyEnabled()
	return DebouncePrivate.Options.overviewProblemsOnly == true;
end

local function AreOverviewFiltersDefault()
	return not IsBoundOnlyEnabled() and not IsProblemsOnlyEnabled();
end

--- 활성 레이어를 한 번 훑어 (액션 -> 그 액션이 사는 레이어, 그 레이어에서의 자리)를 만든다.
---
--- `CollectActionsForKey`가 발동 순서는 주지만 **자리 번호는 안 준다.** 우클릭 메뉴의
--- 복사(`MoveAction`의 `elementData.index + 1`)와 삭제가 그 번호로 프로필을 만지므로,
--- 레이어 탭의 행이 들고 다니는 것과 같은 값이 오버뷰 탭의 행에도 있어야 한다.
--- 손으로 세면 두 목록이 서로 다른 뜻의 index를 들게 된다.
local function CollectActiveLayerPositions()
	local layerOf, indexOf = {}, {};
	for _, layer in DebouncePrivate.EnumerateProfileLayers() do
		for i, action in layer:Enumerate() do
			layerOf[action] = layer.layerID;
			indexOf[action] = i;
		end
	end
	return layerOf, indexOf;
end

--- 오버뷰 탭 라벨에 붙는 숫자. **개수가 아니라 문제의 수다.**
---
--- 앞의 두 탭은 "여기 몇 개 들었나"를 세는데, 이 탭에서 그 숫자는 새 정보가 아니다 -
--- 활성 레이어를 전부 담으므로 대체로 앞의 둘을 합친 값이고, 그 값을 알아야 할 일이 없다.
--- 그래서 자리를 바꿔 쓴다: **고쳐야 할 것이 있는가**. 없으면 숫자 자체가 안 붙는다.
---
--- 문제 필터와 무관하게 센다. 필터는 화면을 거르는 것이고 이 숫자는 경고라, 필터를 껐다고
--- 경고가 사라지면 안 된다. 검색도 안 본다 - 같은 이유다.
---
--- 목록을 만들지 않고 센다. 이 값은 **어느 탭을 보고 있든** 필요한데 목록은 고른 탭의 것
--- 하나만 만든다.
local function CountOverviewProblems()
	local layerOf = CollectActiveLayerPositions();
	local count = 0;
	for action in pairs(layerOf) do
		if (action.key and GetBindingIssue(action)) then
			count = count + 1;
		end
	end
	return count;
end

--- "이 캐릭터"를 말하는 그림. **텍스처에 직접 건다** - 없을 때 대신 무엇을 걸지가 이
--- 함수의 절반이라, 경로만 돌려주면 부르는 쪽이 그 판단을 못 한다.
---
--- 진짜 초상화를 쓴다. `SetPortraitTexture`는 블리자드 트리 전역이 쓰는 살아 있는 API라
--- 종족이 늘어도 따라온다.
---
--- **종족 흉상(`Interface\CharacterFrame\TemporaryPortrait-<성별>-<종족>`)을 쓰다 뺐다.**
--- 그 이름은 블리자드 UI 트리 전체에서 참조가 **0건**이라 누가 최신 상태로 유지해 주는지
--- 알 수 없고, 드락티르·토석민처럼 뒤에 나온 종족에 파일이 있는지 확인할 방법이 없다.
--- 없으면 텍스처가 비는데 아이콘 칸은 **켜진 채로** 남아서 이름 앞이 이유 없이 밀린다 -
--- XML 주석이 "빈 칸은 남기지 않는다"고 못 박은 바로 그 모양이 된다. 장비가 나오고 14px에서
--- 뭉개지는 건 이 초상화의 단점이 맞지만, **반쯤의 종족에서 아무것도 안 보이는 것보다 낫다.**
---
--- 직업 아이콘(`GetClassAtlas`)도 후보였는데 **안 된다.** 사이드탭 2번(공유/직업)이 이미
--- 주문서의 직업 스킬라인 아이콘을 쓰고 있어서, 같은 줄에 직업 그림이 두 개 서면 어느 쪽이
--- "이 캐릭터"고 어느 쪽이 "직업 레이어"인지 구분이 안 된다. 이 아이콘이 하는 일이 정확히
--- 그 구분이다.
local function SetPlayerCharacterIcon(texture)
	SetPortraitTexture(texture, "player");
end

--- 사이드탭 아이콘. 사이드탭 줄과 순서 목록의 행이 **같은 그림**을 써야 하므로 한 군데서
--- 낸다 - 어긋나면 사용자가 왼쪽에서 배운 그림이 오른쪽에서 다른 뜻이 된다.
--- **아이콘 하나만 돌려준다.** `GetSpecializationInfo`는 `select(4, …)`에서도 세 개를
--- 뱉으므로(icon, role, primaryStat) 그대로 흘리면 `Texture:SetTexture(icon, role, primaryStat)`가
--- 되어 뒤 둘이 wrapMode 인자로 먹힌다. 사이드탭은 `SetNormalTexture`라 인자를 하나만 받아
--- 티가 안 났고, 순서 목록의 레이어 아이콘에서만 드러난다.
local function GetSideTabIcon(sideTabID)
	if (sideTabID <= 2) then
		local _, icon = GetSpellTabNameAndIcon(sideTabID);
		return icon;
	end
	local icon = select(4, C_SpecializationInfo.GetSpecializationInfo(sideTabID - 2));
	return icon;
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
---
--- **주문 선택 창도 여기 없다.** 일부러다 - 그 창은 대상을 안 고르고 메인 창에서 열려 있는
--- 레이어에 넣는다. 여기 넣으면 탭이 잠겨서 대상을 바꿀 방법이 사라진다.
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

--- 대화상자를 닫고 이 행의 elementData를 **다시 집어** 준다. 목록에 없어졌으면 nil.
---
--- 닫는 길에는 매크로 본문 저장이 딸려 오고, 그게 `UpdateBindings` → `OnBindingsUpdated`
--- → `Refresh(true)`로 이어져 목록이 통째로 새로 지어진다. 그 뒤로는 붙들 데가 없다:
---
--- - 프레임에서 다시 읽으면 - 블리자드가 프레임을 반납하면서 `frame.GetElementData`를
---   지운다(`ScrollBoxListViewMixin:UnassignAccessors`). 다시 잡히더라도 그 프레임이 이제
---   **다른 행**을 그리고 있을 수 있다 - 우클릭 메뉴가 엉뚱한 액션을 겨눈다.
--- - 미리 잡아둔 것을 그냥 쓰면 - 액션은 맞지만 `layer`/`index`가 옛 목록의 값이다.
---   그걸로 옮기거나 복사하면 자리가 어긋난다.
---
--- 그래서 **액션만** 들고 건넌다. 액션 테이블은 목록을 다시 지어도 그대로이므로 건너편에서
--- 지금 목록의 elementData를 다시 찾을 수 있다. 이미 `IsEditDropdownShown`과 끌고 있는 행의
--- 강조가 같은 이유로 action을 열쇠로 쓰고 있다.
local function CloseDialogsAndRefetchElementData(button)
	local elementData = button:GetElementData();
	local action = elementData and elementData.action;
	if (not action) then
		return nil;
	end

	if (not TryCloseAnyDialog()) then
		return nil;
	end

	return DebounceFrame:FindElementDataByActionInfo(action);
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
		elseif (cursorType == "flyout") then
			-- 액션바의 플라이아웃 칸을 끌어다 놓는 길. 주문서에서 끌면 `"spell"`로 오므로
			-- 여기 걸리는 것은 이미 바에 올라가 있는 플라이아웃뿐이다.
			type, value = Constants.FLYOUT, cursorInfo1;
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
	elseif (type == Constants.PETACTION) then
		-- 이름·아이콘은 **저장돼 있다.** 다른 타입과 달리 여기서 다시 풀 수가 없다 - 펫
		-- 명령의 이름과 아이콘은 소환수 주문서에 있고, 펫이 없으면 그 주문서가 통째로
		-- 비어서 물어볼 데가 없다. 프로필 목록은 펫이 없을 때도 그려져야 한다.
		actionName = action.name;
		actionIcon = action.icon;
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
	elseif (type == Constants.FLYOUT) then
		-- 저장된 것은 flyoutID 하나뿐이다. 이름도 아이콘도 여기서 다시 푼다 - 아이콘은
		-- 주문책이 그 플라이아웃 칸에 그리는 그림이고, 주문서를 훑어야 나온다(`Misc.lua` 참고).
		--
		-- 오프스펙을 허용하는 인자를 켜둔다. 여기는 **그리는** 쪽이라, 다른 특성에서 걸어둔
		-- 플라이아웃도 이름과 그림이 나와야 목록에서 한 줄을 차지할 수 있다.
		actionName, actionIcon = DebouncePrivate.GetFlyoutNameAndIcon(value, true);
	elseif (type == Constants.UNUSED) then
		actionName = BINDING_TYPE_NAMES[Constants.UNUSED];
		-- **되돌리기지 금지가 아니다.** 빨간 X(`ReadyCheck-NotReady`)를 쓰던 자리인데, 그
		-- 그림은 "막는다·아무 일도 안 한다"로 읽혀서 툴팁과 반대말을 했다 - 키는 그대로
		-- 눌리고 WoW 바인딩이 시키는 일을 한다. 블리자드가 "기본값으로 되돌리기"에 쓰는
		-- 화살표를 그대로 빌려온다(쿨다운 뷰어의 변경 취소, 커스터마이즈의 카메라 초기화).
		actionIcon = "A:common-icon-undo";
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

--- 이름 바꾸기 따위의 입력 팝업. **띄우기만 한다.**
---
--- 한때 여기 `_shownInputBoxes` 표와 `HideInputBox` · `HideAllInputBoxes`가 같이 있었는데
--- 둘 다 **부르는 데가 없었다.** 그러면 표는 채워지기만 하고 절대 안 비워지는 자루가 된다 -
--- 팝업을 열 때마다 한 칸씩 늘고 세션 내내 남았다. 게다가 `HideAllInputBoxes`는 `local`이
--- 빠져 있어서 전역까지 하나 새고 있었다(윗줄의 선언에 그 이름이 없다).
---
--- 닫는 일은 팝업 자신이 한다(확인·취소·ESC). 우리가 강제로 닫아야 할 자리가 생기면 그때
--- 표를 다시 만들면 되고, 그 전까지는 없는 편이 정확하다.
local function ShowInputBox(data)
	StaticPopup_ShowCustomGenericInputBox(data);
	if (data.currentValue) then
		local popup = StaticPopup_FindVisible("GENERIC_INPUT_BOX", data);
		if (popup) then
			popup.editBox:SetText(data.currentValue);
		end
	end
end

local function MoveAction(elementData, destLayerID, copying)
	local fromLayerID = elementData.layer;
	-- 레이어 탭에서는 목록 전체가 한 레이어라 행의 레이어가 화면의 레이어와 같아야 한다 -
	-- 어긋나면 elementData가 낡은 것이고, 그걸로 프로필을 만지면 엉뚱한 레이어가 바뀐다.
	-- **오버뷰 탭에는 그 불변식이 없다**(행마다 레이어가 다르다). 거기서는 행이 들고 온
	-- 값이 유일한 진실이고, 그 값은 목록을 만들 때 프로필에서 직접 읽은 것이다.
	assert(IsOverviewTab() or fromLayerID == GetLayerID());

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
	-- 순서 번호는 새로 받는다. 복사본은 원본과 같은 번호를 들고 태어나므로 그대로 두면
	-- 두 액션이 동률이 되고, 다른 레이어로 옮긴 것이면 번호 자체가 저쪽 레이어의 값이라
	-- 뜻이 없다. 둘 다 "이 레이어의 맨 뒤"가 답이다.
	destLayer:PlaceLast(action);

	DebouncePrivate.UpdateBindings();

	-- 목록은 정렬해서 그리므로 손으로 끼워넣지 않고 다시 만든다.
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
	local suppressedCategory;

	--- 이 툴팁이 쓰는 유일한 이슈 조회.
	---
	--- 다른 특성의 순서를 보고 있으면 **도달 불가만 뺀다.** 그 판정은 지금 이 특성으로 만든
	--- 키 맵에서 나오므로 저쪽 세계에서는 참이 아니다. 행은 이미 그렇게 계산돼 있는데
	--- (`CollectActionsForKey`) 툴팁만 매번 새로 물어서, **행에는 ⚠가 없는데 툴팁은 빨간
	--- 글씨로 도달 불가라고 적는** 상태였다. 같은 데이터가 같은 화면에서 두 말을 하면 안 된다.
	local function GetIssue(category)
		return GetBindingIssue(action, category, suppressedCategory);
	end

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
	---
	--- layerLabel을 주면 범위 줄을 하나 더 넣는다. **레이어가 섞이는 목록만** 이걸 준다
	--- (순서 목록, 오버뷰 탭) - 거기서는 범위가 아이콘 두 칸으로만 나오므로 낱말로 확인할
	--- 길이 여기밖에 없다. 레이어 탭의 목록은 안 준다: 한 레이어만 그리고 그 이름이 창
	--- 제목에 있다.
	---
	--- suppressInactive는 "이 목록에서는 비활성이라는 말이 뜻이 없다"는 표시다. 순서 목록의
	--- 다른 특성 뷰가 그렇다 - 그 세계에서는 전부 활성이므로 회색으로 죽이면 거짓말이 된다.
	function ShowLineTooltip(owner, anchor, elementData, suppressInactive, instructionKeys, layerLabel)
		GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT");
		---@diagnostic disable-next-line: redundant-parameter
		GameTooltip:SetMinimumWidth(140, true);

		action = elementData.action;
		action._dirty = true;
		-- 순서 목록의 행만 이 표시를 달고 온다(다른 특성 탭). 나머지 호출자는 지금 이
		-- 특성의 사실을 그리므로 뺄 것이 없다.
		suppressedCategory = elementData.simulated and "unreachable" or nil;

		local isInactive = not suppressInactive and DebouncePrivate.IsInactiveAction(action);
		local hasIssues = GetIssue() ~= nil;

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
					error = hasIssues and GetIssue("key") or nil;
				end
				addValueLine(keyText, error);
			else
				-- 단축키 버튼과 같은 말을 쓴다(RefreshKeybind). 한때 여기만 따로 번역된 키를
				-- 들고 있어서, 로케일에 따라 같은 창 안에서 두 낱말이 될 수 있었다.
				addValueLine(INACTIVE_COLOR:WrapTextInColorCode(LLL["DETAIL_NO_KEY"]));
			end
		end

		if (action.unit ~= nil) then
			addLabelLine(LLL["TARGET_UNIT"]);
			local error = hasIssues and GetIssue("unit");
			local unitStr = UNIT_INFO[action.unit] and UNIT_INFO[action.unit].name or LLL[action.unit];
			addValueLine(unitStr, error);
		end

		if (action.hover ~= nil) then
			addLabelLine(LLL["CONDITION_HOVER"]);
			local error = hasIssues and GetIssue("hover");
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
				addValueLine(s, hasIssues and GetIssue("reactions") and true or false, true);

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
				addValueLine(s, hasIssues and GetIssue("frameTypes") and true or false, true);

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

					local error = hasIssues and GetIssue("checkedUnits");
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
				local error = hasIssues and GetIssue("groups");
				addValueLines(_lines, error);
			end
		end

		if (action.combat ~= nil) then
			addLabelLine(LLL["CONDITION_COMBAT"]);
			local error = hasIssues and GetIssue("combat");
			addValueLine(action.combat == true and LLL["CONDITION_COMBAT_YES"] or LLL["CONDITION_COMBAT_NO"], error);
		end

		if (action.stealth ~= nil) then
			local error = hasIssues and GetIssue("stealth");
			addLabelLine(LLL["CONDITION_STEALTH"]);
			addValueLine(action.stealth == true and LLL["CONDITION_STEALTH_YES"] or LLL["CONDITION_STEALTH_NO"], error);
		end

		if (action.known) then
			local error = hasIssues and GetIssue("known");
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
				local error = hasIssues and GetIssue("forms");
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
				local error = hasIssues and GetIssue("bonusbars");
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
			local error = hasIssues and GetIssue("specialbar");
			addLabelLine(LLL["CONDITION_SPECIALBAR"]);
			addValueLine(action.specialbar == true and LLL["CONDITION_SPECIALBAR_YES"] or LLL["CONDITION_SPECIALBAR_NO"], error);
		end

		if (action.extrabar ~= nil) then
			local error = hasIssues and GetIssue("extrabar");
			addLabelLine(LLL["CONDITION_EXTRABAR"]);
			addValueLine(action.extrabar == true and LLL["CONDITION_EXTRABAR_YES"] or LLL["CONDITION_EXTRABAR_NO"], error);
		end

		if (action.pet ~= nil) then
			local error = hasIssues and GetIssue("pet");
			addLabelLine(LLL["CONDITION_PET"]);
			addValueLine(action.pet == true and LLL["CONDITION_PET_YES"] or LLL["CONDITION_PET_NO"], error);
		end

		if (action.petbattle ~= nil) then
			local error = hasIssues and GetIssue("petbattle");
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

		-- 중요도 바로 밑에 둔다. 둘 다 순서를 정하는 값이고, 조건들과는 성질이 다르다.
		if (layerLabel) then
			addLabelLine(LLL["SCOPE"]);
			addValueLine(layerLabel);
		end

		if (instructionKeys) then
			if (#instructionKeys > 0) then
				GameTooltip_AddBlankLineToTooltip(GameTooltip);
				for _, instructionKey in ipairs(instructionKeys) do
					GameTooltip_AddInstructionLine(GameTooltip, LLL[instructionKey]);
				end
			end
		else
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddInstructionLine(GameTooltip, LLL["LINE_TOOLTIP_INSTRUCTION_MESSAGE1"]);
			GameTooltip_AddInstructionLine(GameTooltip, LLL["LINE_TOOLTIP_INSTRUCTION_MESSAGE2"]);
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


--- 이름 칸의 폭과, 레이어 아이콘이 켜졌을 때 그 시작점이 밀리는 거리. **XML의 값에서
--- 나온다** - 폭은 Name의 Size, 밀리는 거리는 아이콘 크기(14)와 간격(5, 3)의 합이다.
--- 저쪽을 고치면 여기도 고쳐야 하므로 계산을 한 자리에 모아둔다.
local LINE_NAME_WIDTH = 430;
local LAYER_ICON_NAME_OFFSET = { [1] = 19, [2] = 36 };

DebounceLineMixin = {};

function DebounceLineMixin:Init(elementData)
	self:RegisterForClicks("AnyUp");
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

	-- 레이어 아이콘은 오버뷰 탭에서만 켜진다(XML 주석에 이유가 있다). 규칙은 순서 리스트와
	-- 같고 - 좁혀진 축마다 하나씩, 빈 칸은 안 남김 - 그래서 이름의 왼쪽 앵커도 여기서 다시
	-- 잡는다. 아이콘이 없으면 XML이 잡아둔 자리 그대로다.
	local shown = 0;
	if (elementData.showLayerIcons and elementData.layer) then
		local tab, sideTab = GetLayerTabs(elementData.layer);
		if (tab == 2) then
			shown = shown + 1;
			SetPlayerCharacterIcon(self.LayerIcons[shown]);
		end
		if (sideTab >= 2) then
			shown = shown + 1;
			self.LayerIcons[shown]:SetTexture(GetSideTabIcon(sideTab));
		end
	end
	for i = 1, #self.LayerIcons do
		self.LayerIcons[i]:SetShown(i <= shown);
	end

	-- 폭도 같이 줄인다. 이 칸은 오른쪽 앵커 없이 고정 폭으로 서 있어서(XML), 시작점만
	-- 밀면 **끝점이 같이 밀려** 같은 줄 오른쪽의 InfoText(@대상) 아래로 들어간다.
	-- 아이콘이 먹은 만큼을 빼면 오른쪽 끝은 아이콘이 없을 때와 같은 자리에 선다.
	local nameOffset = LAYER_ICON_NAME_OFFSET[shown] or 0;
	self.Name:ClearAllPoints();
	if (shown > 0) then
		self.Name:SetPoint("LEFT", self.LayerIcons[shown], "RIGHT", 5, 0);
	else
		self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 5, 7);
	end
	self.Name:SetWidth(LINE_NAME_WIDTH - nameOffset);

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
	-- 강조는 elementData가 아니라 action으로 맞춘다. Refresh가 elementData를 새로 만들어도
	-- 강조가 유지된다.
	self.SelectedHighlight:SetShown(_selectedAction == action or IsEditingAction(action));

	-- 메뉴 대상은 선택과 다른 텍스처를 쓴다(XML 참고). 한 행이 둘 다일 수 있으므로 서로를
	-- 지우지 않는다.
	self.MenuHighlight:SetShown(IsEditDropdownShown(elementData));

	if (GameTooltip:GetOwner() == self) then
		self:OnEnter();
	end

	-- 흐린 행은 두 가지다: 검색어에 안 맞거나, **조건 밖인데 고른 것이라 남아 있거나**
	-- (오버뷰 탭의 문제 필터 - BuildOverviewElements 참고). 둘 다 "목록에는 있는데 지금
	-- 보려던 것은 아니다"라 같은 표시를 쓴다.
	if (elementData.filteredOut or not DoesActionMatchFilter(action)) then
		self:SetAlpha(FILTERED_ALPHA);
	else
		self:SetAlpha(1);
	end
end

function DebounceLineMixin:OnEnter()
	-- 범위 줄은 레이어가 섞이는 목록에서만 붙인다. 레이어 탭에서는 창 제목이 이미 말했다.
	local elementData = self:GetElementData();
	local layerLabel = elementData.showLayerIcons and elementData.layer and GetLayerLabel(elementData.layer) or nil;
	ShowLineTooltip(self, "ANCHOR_RIGHT", elementData, false, nil, layerLabel);
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

			elementData = CloseDialogsAndRefetchElementData(self);
			if (not elementData) then
				return;
			end

			DebounceFrame:ShowEditDropdown(self, elementData);
		end
		return;
	end

	-- 좌클릭 = 선택. 상세 패널이 이 액션을 단축키 탭으로 열어 보여준다.
	-- (예전에는 여기서 키 지정 팝업을 띄웠다. 이제 탭이 그 자리를 대신한다.)
	DebounceFrame:SetSelectedAction(elementData.action);
end

--- 행은 끌 수 없지만(`RegisterForDrag` 없음) **받기는** 한다. 커서에 든 것을 놓는 것은
--- 어느 행에 놓든 같은 일이라 프레임으로 넘긴다.
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

	-- 오버뷰 탭만 설명을 단다. 앞의 둘은 라벨이 곧 뜻이지만("공유" / 캐릭터 이름) 이건
	-- 낱말만으로는 무엇의 오버뷰인지 알 수 없고, 눌러보기 전에 알 자리가 여기밖에 없다.
	if (IsOverviewTab(id)) then
		GameTooltip_AddNormalLine(GameTooltip, LLL["OVERVIEW_DESC"]);

		-- 라벨의 빨간 숫자가 무엇인지 말한다. 숫자만으로는 개수인지 문제인지 알 수 없고,
		-- 앞의 두 탭이 같은 자리에 **개수**를 적고 있어서 더 그렇다. 한 줄 띄워서 붙인다 -
		-- 위는 이 탭이 무엇인가고, 이건 지금 상태다.
		local problems = CountOverviewProblems();
		if (problems > 0) then
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddErrorLine(GameTooltip, format(LLL["OVERVIEW_PROBLEM_COUNT"], problems));
		end
	end

	-- TODO add instruction line. "you can drop here to add/move into this tab"

	GameTooltip:Show();
end

function DebounceTabMixin:OnLeave()
	GameTooltip:Hide();
end

--- 오버뷰 탭은 받지 않는다. 레이어가 아니라서 넣을 데가 없다(DebounceFrameMixin:OnReceiveDrag).
--- 조용히 돌아서도 되는 이유는 커서가 그대로 남기 때문이다 - 옆 탭에 떨구면 된다.
function DebounceTabMixin:OnReceiveDrag()
	local id = self:GetID();
	if (IsOverviewTab(id)) then
		return;
	end
	local layerID = GetLayerID(id, _selectedSideTab);
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
	-- 위 함수를 복사해 오면서 `OnMenuOpened`가 그대로 남아 있었다. 화면은 아래 줄이 맞춰줘서
	-- 멀쩡했지만, 기본 믹스인 쪽은 **메뉴가 영영 열려 있는 것으로 알고** 있었다.
	DropdownButtonMixin.OnMenuClosed(self, menu);
	self:SetSelectedState(false);
end

function DebouncePortraitMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
		self.initialized = true;
	end
end

--- 꺼져 있어도 뜬다(XML의 `motionScriptsWhileDisabled`). 이유가 붙어 있으면 맨 아래에
--- 따로 적는다 - 위의 두 줄은 이 버튼이 **원래 무엇인가**를 말하고, 이건 **지금 왜 안
--- 되는가**라 성질이 다르다. 이유가 없는 채로 꺼진 것도 있다(아이콘 선택기가 떠 있는 동안
--- 전부 잠긴다). 그때는 원래 툴팁만 뜬다 - 그 상황은 화면에 팝업이 떠 있어서 스스로 설명된다.
function DebouncePortraitMixin:OnEnter()
	if (self.TooltipTitle) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, self.TooltipTitle);
		if (self.TooltipText) then
			GameTooltip_AddNormalLine(GameTooltip, self.TooltipText);
		end
		if (self.disabledReason and not self:IsEnabled()) then
			GameTooltip_AddBlankLineToTooltip(GameTooltip);
			GameTooltip_AddErrorLine(GameTooltip, self.disabledReason);
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
		local name;
		if (i == 1) then
			name = GetSpellTabNameAndIcon(1);
			tab.spec = nil;
		elseif (i == 2) then
			name = GetSpellTabNameAndIcon(2);
			tab.spec = 0;
		else
			local spec = i - 2;
			tab.spec = spec;
			if (spec > NUM_SPECS) then
				tab.notUsed = true;
				tab:Hide();
				break;
			end
			name = select(2, C_SpecializationInfo.GetSpecializationInfo(spec));
		end
		tab:SetNormalTexture(GetSideTabIcon(i));
		tab.tooltip = name;
		tab:Show();
	end
end

--- 오버뷰 탭에는 사이드탭이 없다. 그 목록은 활성 레이어를 **전부** 담으므로 고를 것이
--- 없고, 하나를 체크해 두면 그게 무엇을 거르는 것처럼 보인다.
---
--- `_selectedSideTab`은 **건드리지 않는다.** 오버뷰를 들렀다 레이어 탭으로 돌아온 사람은
--- 떠날 때 보던 사이드탭으로 돌아와야 한다.
function DebounceFrameMixin:UpdateSideTabs()
	local currentSpec = C_SpecializationInfo.GetSpecialization();
	self.currentSpec = currentSpec;

	if (IsOverviewTab()) then
		for _, tab in ipairs(self.SideTabs) do
			tab:Hide();
		end
		return;
	end

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

--- **검색을 보지 않는다.** 이 목록의 검색은 거르는 것이 아니라 흐리게 하는 것이라
--- (`DebounceLineMixin:Update`의 `FILTERED_ALPHA`), 안 맞는 행도 dataProvider에는 그대로
--- 있다. 그러니 크기가 0인 것은 **탭이 비었다는 뜻 하나뿐**이고, 검색어로 0건이 되는
--- 일은 여기까지 오지도 않는다.
---
--- 여기에 `if (SearchBox.filters)` 분기를 달지 말 것. 그러면 빈 탭에서 검색창에 글자가
--- 있다는 이유만으로 "검색어에 맞는 액션이 없다"고 말하는데, 그건 사실이 아니고 - 탭이
--- 빈 것이다 - 하라는 일도 틀린다(지울 것은 검색어가 아니라 채울 액션이 없는 것이다).
--- 한때 그 분기가 주석으로 남아 있어서 빠뜨린 것처럼 보였다. 목록을 거르던 시절의 것이다.
---
--- 오버뷰 탭은 예외가 하나 있다. **거기서는 필터가 목록을 실제로 비운다** - 흐리게 하는
--- 검색과 달리 문제 없는 행을 아예 안 넣기 때문이다. 그래서 "빈 목록"이 두 가지 뜻을
--- 갖고, 둘은 정반대다: 걸린 키가 하나도 없거나(할 일이 있다), 문제가 하나도 없거나(없다).
--- 같은 문장으로 말하면 후자가 고장으로 읽힌다.
function DebounceFrameMixin:UpdateEmptyText()
	if (self.dataProvider:GetSize() == 0) then
		-- 켜진 필터 중 **더 좁은 쪽**을 말한다. 둘 다 켜져 있으면 "문제가 없다"가 맞다 -
		-- 키까지 좁혀 봤는데 남은 것이 없다는 뜻이라 앞의 조건은 새 정보가 아니다.
		local text;
		if (not IsOverviewTab()) then
			text = LLL["NO_ACTIONS_IN_THIS_TAB"];
		elseif (IsProblemsOnlyEnabled()) then
			text = LLL["OVERVIEW_NO_PROBLEMS"];
		elseif (IsBoundOnlyEnabled()) then
			text = LLL["OVERVIEW_NO_BOUND_ACTIONS"];
		else
			text = LLL["OVERVIEW_EMPTY"];
		end
		self.ScrollBox.EmptyText:SetText(text);
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
--
-- 오버뷰 탭은 이 계산을 통째로 안 탄다. 세는 것도 다르고(문제의 수), 없으면 아무것도 안
-- 붙는다. 사이드탭도 안 건드린다 - 그 탭에서는 숨어 있다.
function DebounceFrameMixin:UpdateActionCounts()
	for tabId, tab in ipairs(self.Tabs) do
		local label = GetTabLabel(tabId);

		if (IsOverviewTab(tabId)) then
			-- 이 탭의 숫자는 개수가 아니라 **경고**다(CountOverviewProblems). 그래서 0이면
			-- "(0)"이 아니라 아무것도 안 붙는다 - 앞의 두 탭과 같은 모양으로 0을 적으면
			-- 같은 종류의 값으로 읽히고, 고칠 것이 없다는 사실이 숫자 한 칸을 차지할 이유도 없다.
			local problems = CountOverviewProblems();
			if (problems > 0) then
				label = label .. " |cnRED_FONT_COLOR:(" .. problems .. ")|r";
			end
		else
			local sum = 0;
			local countedLayers = {};
			for sideTabId, sideTab in ipairs(self.SideTabs) do
				if (sideTabId <= 2 + NUM_SPECS) then
					local layerId = GetLayerID(tabId, sideTabId);
					local layer = DebouncePrivate.GetProfileLayer(layerId);
					local count;
					if (self.SearchBox.filters) then
						count = 0;
						for _, action in layer:Enumerate() do
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

			if (sum > 0 and self.SearchBox.filters) then
				label = label .. " |cnGREEN_FONT_COLOR:(" .. sum .. ")|r";
			else
				label = label .. " (" .. sum .. ")";
			end
		end

		tab:SetText(label);
		PanelTemplates_TabResize(tab, 0)
	end
end

-- 커서에 집어온 주문/매크로를 놓는 동작은 드래그가 아니라 **클릭**이다. 그래서 클릭도
-- OnReceiveDrag로 보낸다. 폴백이 아니라 pickup의 정규 경로다.
--- 목록을 단축키로 묶어 그릴지. 기본은 켬이다 - 저장값이 nil이면 켜진 것으로 읽고,
--- 끈 사람만 false를 남긴다. 무엇이 묶이고 무엇이 안 묶이는지는 BuildSortedElements에 있다.
local function IsGroupByKeyEnabled()
	return DebouncePrivate.Options.mainListGroupByKey ~= false;
end

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
	-- [+]는 이제 **창을 연다.** 예전에는 여기 드롭다운이 매달려 있었는데, 그 안에 있던
	-- 항목이 전부 주문 선택 창으로 옮겨갔다(주문·매크로·탈것·장난감은 목록으로, 명령과
	-- 애드온 고유 액션은 각자 탭으로, 매크로 텍스트는 그 창의 버튼으로).
	self.AddPortrait:SetScript("OnClick", function()
		DebounceSpellPickerFrame:Toggle();
	end)

	-- 옵션 메뉴가 아니라 목록 바로 위에 산다. 바꾸는 것이 목록의 생김새뿐이라 누른 결과가
	-- 같은 화면에 보여야 하고, 메뉴 안에 넣으면 그 결과를 보려고 메뉴를 닫아야 한다.
	local groupByKey = self.GroupByKeyCheckButton;
	groupByKey.Text:SetText(LLL["GROUP_BY_KEY"]);

	-- 라벨 앵커를 다시 잡는다. UICheckButtonTemplate은 라벨을 체크박스 오른쪽에 **x=-2**로
	-- 당겨 붙이는데, 그 값은 32x32 기준이다 - 그 크기에서는 텍스처 안쪽 여백이 그만큼
	-- 있어서 당겨야 간격이 맞는다. 우리는 24x24로 줄여 썼고(검색창이 30 높이라 32는 줄에서
	-- 튄다) 여백도 같이 줄어서 -2가 라벨을 상자에 붙여버렸다.
	local labelGap = 4;
	groupByKey.Text:ClearAllPoints();
	groupByKey.Text:SetPoint("LEFT", groupByKey, "RIGHT", labelGap, 0);

	-- 라벨도 눌리게 한다. 템플릿은 상자만 받으므로 라벨 폭만큼 히트 영역을 오른쪽으로
	-- 늘려야 한다 - 블리자드도 같은 자리에서 같은 한 줄을 쓴다(Blizzard_Calendar.lua:3798).
	-- 폭은 로케일마다 다르니 재서 쓴다. SetText 뒤라 이미 잰 값이 나온다.
	groupByKey:SetHitRectInsets(0, -(labelGap + groupByKey.Text:GetStringWidth()), 0, 0);
	groupByKey:SetChecked(IsGroupByKeyEnabled());
	groupByKey:SetScript("OnClick", function(button)
		local checked = button:GetChecked();

		-- 기본값(켬)일 때는 아무것도 안 남긴다. 끈 사람만 false를 저장한다.
		--
		-- **`a and false or nil` 꼴로 쓰지 말 것.** `false or nil`이 늘 nil이라 어느 가지로 가든
		-- nil이 나온다 - 끈 것이 저장되지 않아 체크박스만 움직이고 목록은 그대로였다.
		-- 관용구로 nil과 false를 갈라낼 수 없으므로 여기는 if로 쓴다.
		if (checked) then
			DebouncePrivate.Options.mainListGroupByKey = nil;
		else
			DebouncePrivate.Options.mainListGroupByKey = false;
		end

		PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF);
		-- 스크롤 위치를 버리지 않는다. 버리면 목록이 맨 위로 튀는데, 묶는 선을 그었다 지웠다
		-- 하는 것뿐인 조작치고는 대가가 크다.
		self:Refresh(true);

		-- 그래도 줄들은 새로 놓인다. 고른 게 있으면 따라간다 -
		-- 아니면 "선택은 그대로인데 화면에는 없는" 상태가 되고, 그건 선택이 풀린 것처럼 보인다.
		if (_selectedAction) then
			self:ScrollActionIntoView(_selectedAction);
		end
	end);

	-- 여기가 "묶는다는 게 무슨 뜻이냐"를 답할 유일한 자리다. 그룹 헤더는 툴팁을 띄우지
	-- 않고(이벤트를 밑의 ScrollBox로 통과시킨다), 목록을 그릴 때마다 알림창을 띄울 수도
	-- 없다 - 묶기가 기본값이라 그건 처음 창을 여는 모든 사람에게 뜬다.
	groupByKey:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, LLL["GROUP_BY_KEY"]);
		GameTooltip_AddNormalLine(GameTooltip, LLL["GROUP_BY_KEY_DESC"]);
		GameTooltip_AddInstructionLine(GameTooltip, LLL["GROUP_BY_KEY_ORDER_HINT"]);
		GameTooltip:Show();
	end);
	groupByKey:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);

	self:InitializeFilterDropdown();
end

--- 오버뷰 탭의 필터 둘. 값을 읽고 쓰는 규칙은 `IsBoundOnlyEnabled` 주변에 있다.
---
--- **필터를 만지는 것은 뷰를 바꾸는 것이다.** 그래서 값이 바뀔 때마다 붙들고 있던 것을
--- 전부 놓는다 - 사용자가 "이것만 보여줘"라고 말한 참에 조건 밖의 행을 흐리게 남겨두면
--- 화면이 방금 받은 지시를 어기는 것이 된다. 고른 액션이 새 조건에 안 맞으면 `Refresh`가
--- 선택까지 푼다.
function DebounceFrameMixin:InitializeFilterDropdown()
	local function Apply()
		ForgetOverviewActions();
		-- 스크롤 위치는 버린다. 묶기 토글과 달리 이건 **목록의 내용을 바꾸므로** 지키던
		-- 자리에 다른 것이 와 있다.
		self:Refresh();
		if (_selectedAction) then
			self:ScrollActionIntoView(_selectedAction);
		end
	end

	self.FilterDropdown:SetupMenu(function(_, rootDescription)
		-- 저장하는 것은 **기본이 아닌 쪽뿐이다.** 둘 다 기본이 끔이라 켠 것만 남는다.
		local function Toggle(option)
			if (DebouncePrivate.Options[option]) then
				DebouncePrivate.Options[option] = nil;
			else
				DebouncePrivate.Options[option] = true;
			end
			Apply();
		end

		rootDescription:CreateCheckbox(LLL["OVERVIEW_FILTER_BOUND_ONLY"],
			IsBoundOnlyEnabled,
			function() Toggle("overviewBoundOnly"); end);

		rootDescription:CreateCheckbox(LLL["OVERVIEW_FILTER_PROBLEMS_ONLY"],
			IsProblemsOnlyEnabled,
			function() Toggle("overviewProblemsOnly"); end);
	end);

	-- 기본값이 아니면 버튼 오른쪽 위에 X가 뜬다. **템플릿이 이미 다 갖고 있다**
	-- (`WowDropdownFilterBehaviorMixin`) - 우리가 줄 것은 "지금 기본값인가"와 "되돌려라"
	-- 둘뿐이다. 주문 선택 창이 같은 자리에서 같은 짝을 쓴다.
	self.FilterDropdown:SetIsDefaultCallback(AreOverviewFiltersDefault);
	self.FilterDropdown:SetDefaultCallback(function()
		DebouncePrivate.Options.overviewBoundOnly = nil;
		DebouncePrivate.Options.overviewProblemsOnly = nil;
		Apply();
	end);
end

--- 목록 위의 컨트롤은 탭마다 다르다. 묶기 체크박스는 레이어 탭에만(오버뷰 목록은 언제나
--- 키로 묶여 있다 - 거기서 묶기는 선택이 아니라 목록의 뜻이다), 필터 버튼은 오버뷰 탭에만.
function DebounceFrameMixin:UpdateListControls()
	local overview = IsOverviewTab();
	self.GroupByKeyCheckButton:SetShown(not overview);
	self.FilterDropdown:SetShown(overview);
end

--- 블리자드 패널이 가운데나 전체를 차지하고 있으면 ESC는 그쪽 것이다.
---
--- 예전에는 물어볼 일이 없었다 - 우리 창이 UISpecialFrames에 있어서 area가 "center"/"full"인
--- 패널이 열리는 순간 이미 닫혔으니까. 이제는 거기서 빠졌으므로 공존하고, 여기서 안
--- 물러나면 마이크로 버튼으로 연 게임메뉴가 ESC로 안 닫힌다(우리 창이 키를 먼저 먹는다).
--- 게임메뉴는 `area="center"` 패널이다(UIPanelWindows.lua:4).
local function BlizzardOwnsEscape()
	return GetUIPanel("center") ~= nil or GetUIPanel("fullscreen") ~= nil;
end

function DebounceFrameMixin:OnLoad()
	self.initialized = true;

	--- ESC는 이 창이 직접 받는다(XML의 enableKeyboard). 블리자드가 내주는 두 자리를
	--- **둘 다 안 쓴다.**
	---
	--- `UISpecialFrames`: 그물이 ESC 전용이 아니다. `CloseSpecialWindows`를 태우는 게 ESC만이
	--- 아니라서 - area="center" 패널을 여는 것만으로도 ShowUIPanel -> CloseWindows ->
	--- CloseSpecialWindows를 지나간다 - P로 주문서를 열면 우리 창이 같이 닫혔다. 하필
	--- 주문을 끌어다 바인딩하려고 여는 창이다.
	---
	--- `RegisterGameMenuEscHandler`(12.1): ESC 전용이라 그 문제는 없는데, **등록하는 것만으로
	--- 블리자드의 ESC 경로가 우리 taint를 뒤집어쓴다.** 그 함수가 하는 일이
	--- `table.insert(handlers, …)` + `table.sort(handlers, …)`이고 둘 다 우리 실행 경로에서
	--- 돈다(Blizzard_GameMenuEsc.lua:76-97). 그러면 `handlers`의 모든 칸이 더러워지고,
	--- `TryHandleGameMenuEsc`가 그걸 `securecallfunction` **바깥에서** 읽는다(:100-101) -
	--- 읽는 순간 ToggleGameMenu 자신의 경로가 더러워진다. 그 뒤 `Casting`(4) 우선순위의
	--- 블리자드 핸들러가 부르는 `SpellStopCasting()`이 보호된 함수라 막힌다:
	---
	---     [ADDON_ACTION_FORBIDDEN] AddOn 'Debounce' tried to call 'SpellStopCasting()'
	---     [C]: in function 'SpellStopCasting'
	---     [Blizzard_Game/Shared/Game.lua]:7
	---     [C]: in function 'securecallfunction'
	---     [Blizzard_GameMenuEsc/Blizzard_GameMenuEsc.lua]:101 -> :110 ToggleGameMenu
	---
	--- 스택에 우리 함수가 하나도 없고 터지는 것도 블리자드 자기 핸들러다. 우리가 한 일은
	--- 목록에 줄 하나 넣은 것뿐인데 **그 세션 내내** ESC가 시전을 못 끊는다 - 창을 닫아도,
	--- 전투 중이라 창이 스스로 숨은 뒤에도 그대로다. UISpecialFrames가 20년째 안전한 이유가
	--- 여기서 갈린다: 저쪽은 더러워진 테이블을 `securecall("CloseSpecialWindows")`
	--- **안에서** 읽는다(UIParentPanelManager.lua:1084).
	---
	--- 그래서 키보드다. 창이 떠 있는 동안만 ESC를 받고 블리자드 자료구조에는 아무것도 안
	--- 쓴다. 딸린 이득: UISpecialFrames에 없으니 P로 주문서를 열어도 이 창은 그대로다.
	--- 딸린 비용: 게임메뉴가 이 창과 공존하게 되므로 그때는 물러나야 한다(OnKeyDown, 그리고
	--- 바로 아래 GameMenuFrame.Shown).
	self:SetPropagateKeyboardInput(true);

	--- 게임메뉴와는 **공존하지 않는다.** 반대 방향은 이미 막혀 있었다 - 메뉴가 떠 있으면
	--- 이 창이 안 열리고, 왜 안 열리는지 말까지 해준다(`Public.lua:83`). 이쪽만 비어 있어서
	--- 마이크로 버튼으로 메뉴를 열면 창이 남았다. 한쪽만 막은 규칙은 규칙이 아니다.
	---
	--- UISpecialFrames로 되돌리면 이것도 닫히지만 **그물이 너무 넓다** - P로 주문서를 여는
	--- 것까지 같이 닫는다(E-5). 여기서 필요한 건 "게임메뉴 하나"이고, 반대 방향 가드도
	--- `GameMenuFrame:IsShown()` 하나를 본다. 좁은 규칙에는 좁은 신호로 답한다.
	---
	--- **EventRegistry는 애드온이 써도 되게 지어져 있다** - `RegisterGameMenuEscHandler`와
	--- 갈리는 지점이 여기다(위 문단). 콜백 테이블을 `secureexecuterange`로 돌고 콜백마다
	--- `securecallfunction`을 씌운다(`CallbackRegistry.lua:198-214`). 등록으로 더러워진 칸을
	--- 읽는 것도, 우리 콜백이 도는 것도 전부 secure 경계 **안**이라 부른 쪽 경로가 안 더러워진다.
	--- 블리자드 자기 코드도 같은 이벤트를 같은 목적으로 쓴다(`Blizzard_HousingInspectModeUI.lua:26`).
	EventRegistry:RegisterCallback("GameMenuFrame.Shown", self.Hide, self);

	self:SetPortraitToAsset(133015);

	for i, tab in ipairs(self.Tabs) do
		tab:SetText(GetTabLabel(i));
		PanelTemplates_TabResize(tab, 0)
	end
	PanelTemplates_SetNumTabs(self, #self.Tabs);

	-- 오버뷰 탭은 **오른쪽 끝에 따로 선다.** 앞의 둘과 다른 종류라(레이어가 아니다) 사슬에
	-- 붙여 놓으면 셋이 같은 축의 선택지로 읽힌다. 사이를 벌려 놓으면 그것만으로 다른
	-- 종류임이 보인다.
	--
	-- **`PanelTemplates_SetNumTabs` 뒤여야 한다.** 그 안의 `PanelTemplates_AnchorTabs`가
	-- 2번 탭부터 앞 탭의 오른쪽에 사슬로 붙이므로(`SharedUIPanelTemplates.lua:465-471`),
	-- XML에 뭘 적어도 거기서 덮인다.
	--
	-- 기준은 **왼쪽 목록 인셋의 오른쪽 끝**이지 창의 오른쪽이 아니다. 상세 패널이 열리면
	-- 창은 넓어지지만 인셋은 그대로다 - 창에 붙이면 이 탭이 상세 패널 밑으로 따라가는데,
	-- 탭이 바꾸는 것은 왼쪽 목록이라 그 자리는 거짓말이다.
	--
	-- 점 둘로 잡는다: 세로는 1번 탭과 같은 줄, 가로는 인셋의 오른쪽 끝. 폭은
	-- `PanelTemplates_TabResize`가 글자에 맞춰 잡고(개수가 붙었다 떨어졌다 한다) 오른쪽이
	-- 고정이므로 왼쪽으로 자란다.
	self.Tab3:ClearAllPoints();
	self.Tab3:SetPoint("TOP", self.Tab1, "TOP", 0, 0);
	self.Tab3:SetPoint("RIGHT", self.ScrollBoxBackground, "RIGHT", 0, 0);

	PanelTemplates_SetTab(self, _selectedTab);

	self:InitializeScrollBox();
	self:InitializeSideTabs();
	self:InitializeButtons();
	self:UpdateListControls();

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
	self.SearchBox:SetScript("OnEditFocusGained", self.SearchBox_OnFocusGained);

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

	-- 창을 새로 여는 것도 뷰를 바꾸는 것이다. 지난번에 붙들고 있던 것을 들고 오지 않는다.
	-- (선택은 남아 있을 수 있고, 그건 `Refresh` 끝에서 다시 붙든다.)
	ForgetOverviewActions();

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

	-- 주문 선택 창의 수명은 여기 묶여 있다. X 버튼도, ESC도, 전투 진입(OnEnterCombat이
	-- self:Hide()로 끝난다)도 전부 이 경로로 오므로 한 줄이 셋을 다 덮는다.
	-- 반대 방향은 없다 - 그 창을 닫아도 이 창은 남는다.
	DebounceSpellPickerFrame:Hide();

	-- 아이콘 선택기도 같이 닫는다. **자식이라 저절로 닫히지 않는다** - 부모가 숨으면
	-- 그리기만 멈추고 `IsShown()`은 참으로 남는다. 그 사이 팝업의 OnHide가 돌면서
	-- `onAccepted`를 지우는데, 창을 다시 열면 팝업이 그대로 돌아온다(New 모드에는 OnShow
	-- 가드가 없다). 그 상태로 확인을 누르면 이름도 본문도 없는 액션이 생기고 편집기는
	-- 안 열린다 - 콜백이 이미 죽었기 때문이다.
	--
	-- 전투 진입은 `OnEnterCombat`이 따로 취소하고 있었지만, 게임 메뉴가 열려서 이 창이
	-- 숨는 길(`GameMenuFrame.Shown`)은 그 자리를 지나지 않는다. 여기서 한 번에 덮는다.
	DebounceIconSelectorFrame:Close(true);

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
	self:UnregisterEvent("GLOBAL_MOUSE_DOWN");

	DebouncePrivate.UnregisterCallback(self, "OnBindingsUpdated");

	_pickedupInfo = nil;
	-- 글로우는 위 상태를 보고 켜지는데, 그걸 지웠다고 저절로 꺼지지는 않는다. 여기서
	-- 안 끄면 다음에 창을 열 때 목록이 빛나고 있다 - 창을 닫는 것도, 전투에 끌려들어가는
	-- 것도 커서에 뭘 든 채로 일어난다.
	self:UpdateDropHighlight();
	ClearMacrotextIconCache();
end

function DebounceFrameMixin:OnEvent(event, arg1)
	if (event == "GLOBAL_MOUSE_DOWN") then
		if (arg1 == "RightButton") then
			if (GetActionTypeAndValueFromCursorInfo()) then
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

--- ESC 한 번에 한 칸씩 물러난다. 소비했으면 true.
---
--- 부르는 곳은 아래 OnKeyDown 하나뿐인데 따로 빼둔 건 **이 순서가 이 창의 계약**이기
--- 때문이다 - 전파 처리와 섞여 있으면 어느 줄이 순서고 어느 줄이 키 배관인지 안 보인다.
function DebounceFrameMixin:HandleEscape()
	if (GetActionTypeAndValueFromCursorInfo()) then
		self:ClearMouse();
		return true;
	end

	-- 매크로 탭에는 따로 처리할 게 없다. 편집칸에 포커스가 있으면 ESC가 포커스만 풀고
	-- (여기까지 안 온다), 한 번 더 누르면 아래 선택 해제로 간다 - 그때 본문이 저장된다.

	-- 키를 듣는 중이면 그것부터 그만둔다.
	--
	-- 보통은 여기까지 안 온다 - 듣는 중에는 버튼이 마우스 위치와 무관하게 키를 먼저
	-- 받고 전파를 끊는다. 그래도 남겨두는 건 **물러나는 순서** 때문이다. 이 갈래가
	-- 없으면 어쩌다 여기로 온 ESC가 아래 선택 해제로 내려가서, 한 번 누른 것이
	-- 캡처를 끝내고 패널까지 접는다.
	if (DebounceDetailPanel:IsCapturingKey()) then
		DebounceDetailPanel:CancelKeyCapture();
		return true;
	end

	-- 아이콘 선택기가 떠 있으면 그것부터 물러난다. 팝업이니 자기 ESC를 자기가 처리할
	-- 것 같지만 아니다 - IconSelectorPopupFrameTemplate은 키보드를 켜지도, ESC를
	-- 받지도, UISpecialFrames에 들지도 않는다. 그래서 여기서 안 세우면 팝업을 띄워둔
	-- 채로 선택이 풀리고, 한 번 더 누르면 팝업만 남기고 창이 닫힌다.
	if (DebounceIconSelectorFrame:IsShown()) then
		DebounceIconSelectorFrame:Close();
		return true;
	end

	-- 주문 선택 창도 여기서 닫는다. 그 창이 스스로 ESC를 처리하지 **못한다** - 그 창이
	-- 열려 있는 동안은 이 창도 반드시 열려 있고(수명이 묶여 있다), 이 사다리가 먼저 돈다.
	-- 저쪽을 UISpecialFrames에 넣어도 닿지 않는 자리라 계획서와 달리 사다리 한 칸으로 넣었다.
	if (DebounceSpellPickerFrame:IsShown()) then
		DebounceSpellPickerFrame:Hide();
		return true;
	end

	-- ESC는 한 단계씩 물러난다: 선택 해제(패널 접힘) -> 창 닫기.
	-- 패널에는 저장을 미루는 상태가 없으므로 잃을 게 없다.
	if (_selectedAction) then
		self:SetSelectedAction(nil);
		return true;
	end

	self:Hide();
	return true;
end

--- ESC가 들어오는 유일한 자리. 블리자드 쪽에 아무것도 등록하지 않는 대가로 전파를 손수
--- 여닫는다(OnLoad 참고).
function DebounceFrameMixin:OnKeyDown(input)
	-- 전투 중 `SetPropagateKeyboardInput`은 taint다. 전투에 들어가면 `OnEnterCombat`이 창을
	-- 숨기므로 보통은 여기까지 오지 않지만, **전투가 시작된 그 프레임에 눌린 키는
	-- PLAYER_REGEN_DISABLED보다 먼저 들어올 수 있다.** `KeyButton_OnKeyDown`이 막는 것과
	-- 같은 한 프레임이고, 같은 방식으로 막는다 - 아무것도 안 하고 물러난다. 그 키를 먹게
	-- 되지만 창은 바로 다음 프레임에 사라진다.
	if (InCombatLockdown()) then
		return;
	end

	if (input == "ESCAPE") then
		-- 블리자드 패널이 떠 있으면 여기서 물러난다. 우리 창은 키보드를 켜둔 채라 ESC를
		-- 언제나 먼저 받는데, 그걸 그대로 먹으면 마이크로 버튼으로 연 게임메뉴를 ESC로
		-- 닫을 수 없다. 물러나면 블리자드가 자기 순서대로 처리한다.
		if (BlizzardOwnsEscape()) then
			self:SetPropagateKeyboardInput(true);
			return;
		end

		self:SetPropagateKeyboardInput(false);

		-- 12.1에서는 블리자드가 Menu 우선순위에서 먼저 해준다. 12.0에는 그 자리가 없다.
		if (Menu.GetManager():HandleESC()) then
			return;
		end

		self:HandleEscape();
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
--- 키 없이 앉아 있게 된다. 오버뷰 탭에서는 그 액션이 목록에서 통째로 빠져야 하므로 더 그렇다.
--- 스크롤 자리는 지킨다 - 방금 만진 줄이 눈앞에서 사라지면 안 된다.
function DebounceFrameMixin:OnBindingsUpdated(_, skipped)
	self:Refresh(true);
	self:Update();
end

-- 목록의 줄 순서는 **언제나 이름순**이고, 남은 선택은 "키 경계에 선을 그을 것인가" 하나다.
--
-- 예전에는 키순/이름순 두 모드였고 키순은 한 키 안을 발동 순서로 그렸다. 그 순서는 말할
-- 자격이 없는 순서였다: 이 목록은 **한 레이어만** 보여준다(그래서 layerRank가 상수였다).
-- 더 구체적인 레이어의 액션이 같은 키를 전부 이기고 있어도 여기엔 안 나오므로, 화면에
-- 보이는 위아래가 실제로 무엇이 먼저 나가는지와 어긋날 수 있었다. 진짜 순서는 레이어를
-- 가로질러 모으는 상세 패널 단축키 탭에 있다(CollectActionsForKey).
--
-- 그래서 묶기는 정렬 모드가 아니라 토글이다. **그룹 안도 이름순이다** - 선을 긋는 일이지
-- 순서를 바꾸는 일이 아니라서, 목록 어디에도 "위에 있는 게 먼저 나간다"가 없다.
local function CompareByName(lhs, rhs)
	if (lhs.sortName ~= rhs.sortName) then
		return lhs.sortName < rhs.sortName;
	end
	-- 이름이 같은 줄은 실재한다(같은 주문을 조건만 달리해 두 번 넣는 것이 정상이다).
	-- table.sort는 불안정하므로 여기서 받쳐주지 않으면 새로 그릴 때마다 자리가 바뀐다.
	return lhs.index < rhs.index;
end

local function CompareByKeyThenName(lhs, rhs)
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
	return CompareByName(lhs, rhs);
end

local function BuildSortedElements(layer, layerID)
	local elements = {};
	for i, action in layer:Enumerate() do
		elements[i] = {
			action = action,
			layer = layerID,
			index = i,
			sortName = strlower(NameAndIconForAction(action) or ""),
		};
	end

	if (not IsGroupByKeyEnabled()) then
		sort(elements, CompareByName);
		return elements;
	end

	sort(elements, CompareByKeyThenName);

	-- 키가 바뀌는 자리마다 헤더를 끼운다.
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

	return grouped;
end

--- 키 없는 액션 그룹. 있으면 목록 **맨 위**에 헤더 하나와 함께 얹는다 - 레이어 탭이 이미
--- 그 자리에 놓고 있어서(`CompareByKeyThenName`) 새로 배울 것이 없다.
---
--- 두 가지 이유로 온다. **키 필터를 끈 것**(= "키를 아직 안 건 게 뭐가 남았지"를 묻는 중),
--- 또는 **붙들고 있는 것**(= 방금 그 액션의 단축키를 해제했다 - 손댄 것은 발밑에서
--- 사라지지 않는다). 후자는 필터가 켜져 있어도 오고, 흐리게 그려진다.
---
--- 이 그룹 안은 이름순이다. 시도 순서가 없는 액션들이라 정할 순서가 없다.
local function AppendUnboundGroup(elements, layerOf, indexOf, boundOnly, problemsOnly)
	local rows = {};
	for action in pairs(layerOf) do
		if (action.key == nil) then
			local kept = not boundOnly and (not problemsOnly or GetBindingIssue(action));
			if (kept or _overviewRemembered[action]) then
				rows[#rows + 1] = {
					action = action,
					layer = layerOf[action],
					index = indexOf[action],
					showLayerIcons = true,
					filteredOut = not kept or nil,
					sortName = strlower(NameAndIconForAction(action) or ""),
				};
			end
		end
	end

	if (#rows == 0) then
		return elements;
	end

	sort(rows, function(lhs, rhs)
		if (lhs.sortName ~= rhs.sortName) then
			return lhs.sortName < rhs.sortName;
		end
		-- 이름이 같은 줄은 실재한다. table.sort가 불안정하므로 받쳐준다 - 안 그러면 다시
		-- 그릴 때마다 자리가 바뀐다. 레이어 순서를 쓴다(`CompareByName`은 표시 순번을 쓴다).
		return (lhs.layer or 0) < (rhs.layer or 0);
	end);

	elements[#elements + 1] = { isHeader = true };
	for _, row in ipairs(rows) do
		elements[#elements + 1] = row;
	end
	return elements;
end

--- 오버뷰 탭의 목록. **활성 레이어에서 키가 걸린 액션 전부**를 키로 묶고, 그룹 안은 실제
--- 발동 순서로 놓는다.
---
--- 레이어 탭의 목록은 순서를 말할 자격이 없다(위 CompareByName의 주석). 한 레이어만
--- 그리므로 더 구체적인 레이어가 같은 키를 이기고 있어도 화면에 안 나오기 때문이다.
--- **이 탭은 그 조건이 없다** - 활성 레이어를 전부 담으므로 한 키에 걸린 것이 여기 다
--- 있고, 그래서 세로 순서가 곧 시도 순서다. 순서를 내는 것은 `CollectActionsForKey`로,
--- 상세 패널의 순서 리스트와 **같은 함수**다. 두 화면이 다른 답을 낼 길이 없다.
---
--- 키 없는 액션은 **자기 헤더 아래 따로, 맨 위에** 선다(`AppendUnboundGroup`). 키 그룹
--- 안에 섞이지 않으므로 위의 "세로 순서 = 시도 순서"를 깨지 않는다 - 그 헤더가 이미
--- "이건 키가 아니다"라고 말한다. 오프스펙 액션을 안 넣는 이유가 여기서 갈린다: 저쪽은
--- 키 그룹 **안에** 들어가서 그 주장을 거짓으로 만든다.
---
--- 엔진의 `GetKeyMap()`은 안 쓴다. 그쪽은 이슈가 있는 액션과 도달 불가 액션을 빼고
--- 넘겨주는데(`Debounce.lua`의 BuildKeyMap), **여기서는 그것들이야말로 보여줄 대상**이다.
local function BuildOverviewElements(boundOnly, problemsOnly)
	local layerOf, indexOf = CollectActiveLayerPositions();

	local keySeen, keyArr = {}, {};
	for action, _ in pairs(layerOf) do
		local key = action.key;
		if (key and not keySeen[key]) then
			keySeen[key] = true;
			keyArr[#keyArr + 1] = key;
		end
	end

	sort(keyArr, DebouncePrivate.CompareKeys);

	local elements = AppendUnboundGroup({}, layerOf, indexOf, boundOnly, problemsOnly);
	for _, key in ipairs(keyArr) do
		-- 헤더는 **뒤에 실제로 행이 붙을 때만** 남긴다. 필터가 그룹을 통째로 비울 수 있는데,
		-- 행 없는 키 이름만 늘어선 목록은 "이 키들에 문제가 있다"로 읽힌다.
		local headerIndex = #elements + 1;
		elements[headerIndex] = { isHeader = true, key = key };

		for _, row in ipairs(DebouncePrivate.CollectActionsForKey(key)) do
			-- 붙들고 있는 행은 필터가 못 뺀다(`_overviewRemembered`). 흐리게 그린다
			-- (아래 `filteredOut`) - 검색에 안 맞는 행과 같은 표시라, "지금 조건 밖인데
			-- 네가 손대고 있어서 남아 있다"가 새로 배울 것 없이 읽힌다.
			local kept = not problemsOnly or row.issue;
			if (kept or _overviewRemembered[row.action]) then
				elements[#elements + 1] = {
					action = row.action,
					layer = layerOf[row.action],
					index = indexOf[row.action],
					showLayerIcons = true,
					filteredOut = not kept or nil,
				};
			end
		end

		if (#elements == headerIndex) then
			elements[headerIndex] = nil;
		end
	end

	return elements;
end

function DebounceFrameMixin:Refresh(retainScrollPosition)
	HideDeleteConfirmationPopup();

	local dataProvider = CreateDataProvider();
	local elements;
	if (IsOverviewTab()) then
		elements = BuildOverviewElements(IsBoundOnlyEnabled(), IsProblemsOnlyEnabled());
	else
		local layerID = GetLayerID();
		elements = BuildSortedElements(DebouncePrivate.GetProfileLayer(layerID), layerID);
	end

	for _, elementData in ipairs(elements) do
		dataProvider:Insert(elementData);
	end

	self.dataProvider = dataProvider;
	self.ScrollBox:SetDataProvider(dataProvider, retainScrollPosition and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition);

	-- 선택은 "지금 보이는 목록의 한 줄"이다. 레이어 탭을 바꾸거나 액션이 사라지면 풀린다.
	if (_selectedAction and not self:FindElementDataByActionInfo(_selectedAction)) then
		self:SetSelectedAction(nil);
	end

	-- 살아남은 선택은 언제나 붙들려 있다. **비운 직후를 위한 줄이다** - 뷰를 바꾸는 자리들이
	-- 표를 비우고 여기로 오는데, 그때 들고 온 선택이 새 화면에도 있으면 그건 여전히 발밑이다.
	-- (선택을 새로 고르는 길은 `SetSelectedAction`이 따로 붙든다 - 그쪽은 Refresh를 안 지난다.)
	RememberOverviewAction(_selectedAction);

	-- 제목은 탭 좌표를 낱말로 다시 말한다. 오버뷰 탭에는 좌표의 뒷칸이 없다 - 사이드탭이
	-- 없으니 넣을 값이 없고, 억지로 "전체" 따위를 만들어 넣으면 그게 고를 수 있는 값처럼 보인다.
	local title;
	if (IsOverviewTab()) then
		title = format(LLL["DEBOUNCE_TITLE_FORMAT_SINGLE"], GetTabLabel(_selectedTab));
	else
		title = format(LLL["DEBOUNCE_TITLE_FORMAT"], GetTabLabel(_selectedTab), GetSideTabaLabel(_selectedSideTab));
	end
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
	-- 고른 것은 곧 발밑이다. 상세 패널이 만지는 것은 언제나 이 액션이고(키 지정, 순서 이동)
	-- 그 편집으로 필터를 벗어나도 행이 남아야 한다. **여기서 붙들어야 한다** - 이 함수는
	-- `Refresh`를 안 지나므로 저쪽 끝의 같은 줄이 대신해 주지 않는다.
	RememberOverviewAction(action);
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

--- 액션이 사는 행을 화면 안으로 데려온다. **이미 다 보이면 아무것도 하지 않는다** -
--- 화면을 옮기는 것은 사용자가 보던 자리를 빼앗는 일이라, 필요할 때만 해야 한다.
---
--- 목록이 키로 묶여 있으면 단축키를 바꾼 행이 다른 그룹으로 **건너뛴다.** 방금 무엇을
--- 바꿨는지 확인할 수 있는 유일한 행이 스크롤 밖으로 사라지면 목록은 아무 일도 일어나지
--- 않은 것처럼 보인다. 묶기를 껐다 켜는 것도 같은 이유로 여기를 지난다 - 그때는 목록
--- 전체가 새로 놓이므로 보던 행이 어디로든 갈 수 있다.
---
--- 위로 벗어났을 때는 바로 위 헤더까지 데려온다. 행만 맨 위에 붙이면 이 행이 어느 키에
--- 속하는지 말해주는 줄이 화면 밖 한 칸 위에 남는데, 그게 방금 바꾼 바로 그 키다. 아래로
--- 벗어난 경우는 AlignEnd(행을 아래 끝에 맞춤)라 헤더가 자연히 위쪽에 따라 들어온다.
--- 묶기를 껐으면 앞줄이 헤더가 아니므로 이 갈래는 저절로 안 탄다.
function DebounceFrameMixin:ScrollActionIntoView(action)
	local elementData, index = self:FindElementDataByActionInfo(action);
	if (not elementData) then
		return;
	end

	local scrollBox = self.ScrollBox;
	local previous = index > 1 and self.dataProvider:Find(index - 1) or nil;
	if (previous and previous.isHeader and scrollBox:GetExtentUntil(index) < scrollBox:GetDerivedScrollOffset()) then
		scrollBox:ScrollToElementDataIndex(index - 1, ScrollBoxConstants.AlignBegin);
	else
		-- AlignNearest. 보이면 그대로 두고, 벗어난 쪽으로만 딱 그만큼 움직인다.
		scrollBox:ScrollToNearest(index);
	end
end

--- 순서 목록이 가리키는 액션으로 화면을 옮긴다. 그 액션이 사는 탭을 열고, 왼쪽 목록에서
--- 골라 상세 패널까지 그 액션의 것으로 바꾼다.
---
--- 순서 목록이 남의 액션을 여기서 고치지 않고 데려다 주는 이유는, 고치려면 그 액션의
--- 맥락 - 자기 탭, 자기 이웃, 자기 순서 목록 - 이 필요하기 때문이다. 순서만 만지려던
--- 사람이 보고 있지도 않은 레이어를 팝업 하나로 바꾸는 것이 이 화면에서 가장 나기 쉬운
--- 사고고, 그 팝업에는 그게 어디 것인지 말해주는 게 아무것도 없다.
---
--- 돌아오는 길은 대개 열려 있다. 같은 키의 순서 목록이라 방금 떠나온 액션도 거기 들어
--- 있다. (다른 특성의 레이어로 건너뛰면 그쪽 목록은 현재 특성 기준으로 계산되므로 안
--- 보일 수 있다.)
--- **오버뷰 탭에서는 탭을 안 옮긴다.** 그 목록에는 활성 레이어가 전부 있으므로 찾아갈
--- 액션이 이미 화면에 있고, 그런데도 레이어 탭으로 보내면 데려다 준 것이 아니라 보던
--- 것을 빼앗은 것이 된다. 목록에 없으면(문제 필터가 걸러낸 행) 평소대로 옮긴다.
function DebounceFrameMixin:GoToAction(action, layerID)
	if (not TryCloseAnyDialog()) then
		return;
	end

	if (IsOverviewTab() and self:FindElementDataByActionInfo(action)) then
		self:SetSelectedAction(action);
		self:ScrollActionIntoView(action);
		return;
	end

	local tab, sideTab = GetLayerTabs(layerID);
	-- 사이드탭을 **먼저** 넣는다. SetTab이 사이드탭 갱신과 Refresh까지 하는데, 그 안의
	-- "안 보이는 사이드탭이면 1로" 가드가 새 좌표를 보고 판단해야 한다.
	_selectedSideTab = sideTab;
	self:SetTab(tab);

	self:SetSelectedAction(action);

	local elementData = self:FindElementDataByActionInfo(action);
	if (elementData) then
		self.ScrollBox:ScrollToElementData(elementData);
	end
end

--- **오버뷰 탭에서는 못 만든다.** 새 액션이 어느 레이어에 태어날지 그 탭은 답이 없다
--- (`GetLayerID` 참고). [+] 버튼은 거기서 꺼져 있지만 그것만으로는 안 막힌다 - 주문 선택
--- 창은 열어둔 채 탭을 옮겨 다니는 창이라, 오버뷰로 옮긴 뒤에 저쪽에서 한 줄을 누르면
--- 여기로 온다. 조용히 물러서지 않고 왜 안 되는지 말한다.
function DebounceFrameMixin:AddNewAction(type, value, name, icon, props)
	if (IsOverviewTab()) then
		DebouncePrivate.DisplayMessage(LLL["OVERVIEW_CANNOT_ADD"], 1, 0, 0);
		return nil;
	end

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
	-- 새 액션도 순서 규칙을 똑같이 지난다. 지금 오는 것들은 키 없이 태어나므로 번호를 안
	-- 받고(SetActionKey가 걸 때 준다), props에 키가 실려 오면 여기서 맨 뒤 번호를 받는다.
	layer:PlaceLast(action);

	-- 목록이 정렬돼 있으므로 새 액션이 맨 뒤에 붙는다는 보장이 없다. 다시 만들고 찾아간다.
	self:Refresh(true);

	-- 곧바로 선택한다. 방금 생긴 액션은 키를 정해야 쓸모가 생기는데, 선택이 상세 패널을
	-- 열어 그 자리로 데려간다. 커서에서 떨궈 만든 것과 **같은 대접**이어야 한다
	-- (OnReceiveDrag) - 선택 창에서 고른 것만 아무 데도 안 데려가면 같은 일을 하는 두 길이
	-- 다르게 끝난다. 찾기보다 먼저 하는 것도 같은 이유다: 패널이 열리면서 프레임이
	-- 넓어지므로 스크롤은 그 뒤에 잡아야 맞는다.
	self:SetSelectedAction(action);

	local elementData = self:FindElementDataByActionInfo(action);
	if (elementData) then
		self.ScrollBox:ScrollToElementData(elementData);
	end
	self:Update();

	return elementData;
end

function DebounceFrameMixin:Update()
	-- **한 번도 안 연 창일 수 있다.** 이 창의 XML에는 OnLoad가 없어서 `OnShow`를 거쳐야
	-- `OnLoad`가 돌고, 그전까지는 사이드탭도 ScrollBox의 뷰도 dataProvider도 없다 -
	-- 아래 세 줄이 그 셋을 차례로 만진다.
	--
	-- 여기서 세우지 않는다 - 아무도 안 보고 있는 창을 그리는 일이다. 한 번이라도 열렸으면
	-- 닫혀 있어도 계속 최신으로 둔다(다시 열 때 옛 화면이 스치면 안 된다).
	if (not self.initialized) then
		return;
	end

	self:UpdateButtons();
	DebounceDetailPanel:Refresh();

	self.ScrollBox:ForEachFrame(function(button)
		button:Update();
	end);

	self:UpdateEmptyText();

	self:UpdateDropHighlight();
end

--- 커서에 뭔가 들려 있는 동안 목록 인셋이 빛난다 - "여기가 받는다". 생김새와 자리는 XML에.
function DebounceFrameMixin:UpdateDropHighlight()
	self.ScrollBoxBackground.Highlight:SetShown(_pickedupInfo ~= nil);
end

--- 아이콘 선택기가 떠 있는 동안 잠기는 것들.
---
--- 주문 선택 창은 **여기 없다.** 그 창의 쓸모가 "열어둔 채 탭을 옮겨 다니며 골라 넣는
--- 것"이라, 잠그는 목록에 넣으면 스스로를 못 쓰게 만든다.
function DebounceFrameMixin:UpdateButtons()
	local enableButtons = not IsEditingAction();

	for i = 1, #self.Tabs do
		PanelTemplates_SetTabEnabled(self, i, enableButtons);
	end

	-- `SideTabs`는 `InitializeSideTabs`가 채우고 그건 `OnLoad`에서만 돈다. 창이 한 번도
	-- 안 열린 세션에서는 nil인데, 그런 경로는 `Update`의 `initialized` 가드에서 막힌다.
	for _, tab in ipairs(self.SideTabs) do
		tab:SetEnabled(enableButtons);
	end

	-- 오버뷰 탭에서는 [+]가 갈 데가 없다. 새 액션이 어느 레이어에 태어날지 이 탭은 답을
	-- 못 하므로(GetLayerID 참고) 아예 못 누르게 한다 - 눌러서 아무 일도 안 나는 것보다 낫다.
	--
	-- **탭이 바뀌는 즉시 여기를 지나야 한다.** 이 값은 탭의 함수인데 나머지는 편집 상태의
	-- 함수라, 다음 `Update`를 기다리면 버튼만 한 박자 늦게 따라온다(`SetTab` 참고).
	--
	-- 끄기만 하면 회색 버튼 하나가 이유 없이 죽어 있는 것으로 보인다. 이유는 툴팁이 말한다
	-- (`DebouncePortraitMixin:OnEnter`) - 그래서 이 버튼은 꺼져 있어도 마우스를 받는다.
	local overview = IsOverviewTab();
	self.AddPortrait:SetEnabled(enableButtons and not overview);
	self.AddPortrait.disabledReason = overview and LLL["OVERVIEW_CANNOT_ADD"] or nil;
	self.CustomStatesPortrait:SetEnabled(enableButtons);
	self.OptionsPortrait:SetEnabled(enableButtons);
	self.SearchBox:SetEnabled(enableButtons);
	self.GroupByKeyCheckButton:SetEnabled(enableButtons);
	self.FilterDropdown:SetEnabled(enableButtons);
end

function DebounceFrameMixin:SetTab(id)
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
	_selectedTab = id;
	PanelTemplates_SetTab(self, _selectedTab);
	self:UpdateSideTabs();

	-- 오버뷰 탭에서는 사이드탭이 전부 숨어 있으므로 이 가드를 지나면 안 된다. 지나면
	-- 고른 것을 1로 되돌리는데, 그건 **레이어 탭으로 돌아왔을 때** 보던 자리를 잃는 것이다.
	if (not IsOverviewTab() and not self.SideTabs[_selectedSideTab]:IsShown()) then
		_selectedSideTab = 1;
		self:UpdateSideTabs();
	end

	-- 주문 선택 창은 **여기서 닫는다.** 그 창의 쓸모가 "열어둔 채 탭을 옮겨 다니며 골라
	-- 넣는 것"이라 탭 전환에 안 닫는 것이 규칙인데(`UpdateButtons`의 잠금 목록에도 없다),
	-- 오버뷰 탭에는 넣을 데가 없어서 그 쓸모가 통째로 없어진다. 열어둔 채로 두면 고를 수는
	-- 있는데 누르면 거절당하는 창이 남는다 - 거절은 마지막 그물이지 화면이 할 말이 아니다.
	if (IsOverviewTab()) then
		DebounceSpellPickerFrame:Hide();
	end

	-- 탭 이동도 뷰를 바꾸는 것이다. 앞 탭에서 붙들고 있던 것을 들고 오지 않는다 - 그건
	-- 발밑이 아니라 남의 기억이다. 지금 고른 액션은 `Refresh` 끝에서 다시 붙든다.
	ForgetOverviewActions();

	self:UpdateListControls();
	-- [+]의 상태는 **탭의 함수**라 다음 Update를 기다리면 안 된다. Refresh는 목록만 다시
	-- 만들고 버튼은 안 건드린다.
	self:UpdateButtons();
	self:Refresh();
end

--- 구획 버튼 우클릭이 여기로 온다(Public.lua). 창을 여는 일은 저쪽이 하고, 여기는 탭만 옮긴다.
function DebounceFrameMixin:ShowOverviewTab()
	if (_selectedTab ~= OVERVIEW_TAB) then
		self:SetTab(OVERVIEW_TAB);
	end
end

--- elementData를 주면 버튼 대신 그것으로 연다. 순서 목록이 자기 행 대신 **왼쪽 목록이
--- 만든** elementData를 넘기기 위한 통로다 - 메뉴가 읽는 layer/index는 저쪽 소유의 값이라
--- 모양을 흉내내면 저쪽이 바뀔 때 조용히 어긋난다.
function DebounceFrameMixin:ShowEditDropdown(button, elementData)
	elementData = elementData or button:GetElementData();
	local action = elementData.action;

	-- **낙관적으로 붙든다.** 이 메뉴는 닫힐 때가 아니라 **누르는 즉시** 적용되고
	-- (`DropDownMenus.lua`의 `_setSelected`가 그 자리에서 `UpdateBindings`를 부른다) 그때
	-- 목록이 다시 지어진다. 열 때 이미 붙들려 있지 않으면, 체크박스를 누른 그 순간 행이
	-- 사라지고 사용자는 없어진 행의 메뉴를 계속 만지게 된다.
	--
	-- 대신 아무것도 안 바뀌었으면 닫을 때 놓는다(아래). 열었다 그냥 닫은 것까지 붙들고
	-- 있을 이유는 없다.
	local beforeKey, beforeIssue = GetOverviewMembership(action);
	RememberOverviewAction(action);

	local menu = MenuUtil.CreateContextMenu(button, DebounceUI.SetupEditDropdownMenu, elementData);
	self.contextMenu = menu;
	self.contextMenuAction = menu and action or nil;
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

			-- 목록에 있고 없고를 정하는 두 값이 그대로면 붙들 이유가 없었다. 고른 액션은
			-- 예외다 - 그건 메뉴와 무관하게 발밑이고, 여기서 놓으면 그 뒤 상세 패널의
			-- 편집에서 행이 사라진다.
			if (action ~= _selectedAction) then
				local afterKey, afterIssue = GetOverviewMembership(action);
				if (afterKey == beforeKey and afterIssue == beforeIssue) then
					ForgetOverviewAction(action);
				end
			end

			self:Update();
		end);
	end
	self:Update();
end

function DebounceFrameMixin:OnPickup()
	-- 우클릭으로 커서를 비우는 것만 듣는다. 예전에는 여기서 `ClearMouse(true)`로 진행 중인
	-- 행 드래그를 먼저 끊었는데, 이제 커서에 드는 길이 하나라 끊을 것이 없다.
	self:RegisterEvent("GLOBAL_MOUSE_DOWN");
	self:Update();
end

function DebounceFrameMixin:ClearMouse()
	if (_pickedupInfo) then
		_pickedupInfo = nil;
		ClearCursor();
	end

	self:UnregisterEvent("GLOBAL_MOUSE_DOWN");
	self:Update();
end

--- 게임이 커서에 집어준 것을 받는다. **우리 행은 끌 수 없으므로** 여기 오는 것은 항상
--- 밖에서 온 새 액션이다 - 주문책·액션바·가방에서 끌어왔거나 집어와서 클릭한 것.
---
--- `destLayerID`는 탭에 떨궜을 때 그 탭이 넘긴다. 없으면 지금 보고 있는 레이어다.
---
--- **오버뷰 탭에서는 받지 않는다.** 목적지를 물으면 답이 없다 - 그 목록은 레이어 다섯을
--- 한꺼번에 그린 것이라 "여기"라는 자리가 없다. 어느 하나를 골라 넣으면 액션은 사용자가
--- 고르지 않은 레이어에 태어나고, 화면에는 그 사실이 아무 데도 안 적힌다.
function DebounceFrameMixin:OnReceiveDrag(destLayerID)
	local type, value = GetActionTypeAndValueFromCursorInfo();
	if (not type) then
		return;
	end

	if (destLayerID == nil and IsOverviewTab()) then
		DebouncePrivate.DisplayMessage(LLL["OVERVIEW_CANNOT_ADD"], 1, 0, 0);
		return;
	end

	local action = { type = type, value = value };
	destLayerID = destLayerID or GetLayerID();

	-- 여기서부터 프로필이 바뀐다. 갈아엎기 전에 상세 패널을 떠나보낸다 - 이 패널은 잠그지
	-- 않는 대신 **떠나는 쪽이 저장한다**로 돼 있고(Close 참고), 드롭도 떠나는 것이다.
	--
	-- 없어도 본문 자체는 살아남는다. 편집하던 액션이 목록에서 빠지면 Refresh가 선택을 풀면서
	-- 저장하고, 남으면 RefreshMacroTab이 대상이 같아서 편집칸을 안 건드린다. 그런데 그건
	-- 서로 무관한 가드 둘이 맞물린 결과라 규칙으로 삼을 수 없고, 실제로 두 가지가 샌다 -
	-- UpdateBindings가 저장 전 본문으로 한 번 헛돌고(아래에서 부르고 저장이 또 부른다),
	-- 키를 듣는 중이었다면 캡처가 안 끊긴 채 목록만 갈린다.
	DebounceDetailPanel:Close();

	local destLayer = DebouncePrivate.GetProfileLayer(destLayerID);

	-- 항상 맨 뒤에 붙인다. 떨어진 위치는 의미가 없다.
	destLayer:Insert(action, nil);
	destLayer:PlaceLast(action);

	self:ClearMouse();
	DebouncePrivate.UpdateBindings();
	self:Refresh(true);

	-- 목록이 정렬돼 있으므로 새 액션이 어디로 갈지 모른다. 찾아서 보여준다.
	--
	-- 곧바로 선택도 한다. 방금 생긴 액션은 키를 정해야 쓸모가 생기는데, 선택이 상세 패널을
	-- 열어 그 자리로 데려간다. 다른 탭에 떨궜으면 여기 오지 않는다 - 보이지도 않는 행을
	-- 선택할 수 없다.
	-- 오버뷰 탭을 보는 채로 **다른 탭에** 떨군 경우가 있다. 그때 `GetLayerID()`는 물어볼
	-- 수 없는 값이라(터진다) 먼저 갈라선다 - 어차피 다른 탭에 넣은 것이라 여기 목록에 없다.
	if (not IsOverviewTab() and destLayerID == GetLayerID()) then
		self:SetSelectedAction(action);
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

--- 검색창이 키보드를 가져가면 듣기는 끝난다.
---
--- 안 끝내면 한 키가 두 군데로 들어간다(SetBindingMode 참고). 둘 중 검색창을 살리는 쪽을
--- 고른 이유는 **포커스가 사용자의 의사표시**이기 때문이다 - 검색창을 눌렀다는 건 지금
--- 하려는 일이 타이핑이라는 뜻이다. 반대로 고르면(캡처를 살리고 타이핑을 막으면) 글자가
--- 안 들어가는 검색창이 남는데, 그건 고장으로 읽힌다.
---
--- self는 EditBox다(스크립트로 걸린다).
function DebounceFrameMixin:SearchBox_OnFocusGained()
	SearchBoxTemplate_OnEditFocusGained(self);
	DebounceDetailPanel:CancelKeyCapture();
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
--- 왼쪽 목록(`DebounceLineMixin:Update`)과 **같은 판정기**를 쓴다. `IsKeyInvalidForAction`만
--- 부르면 도달불가(`BINDING_ISSUE_UNREACHABLE`)가 통째로 빠진다 - 목록에서는 단축키가 빨갛고
--- 경고 아이콘까지 붙은 행인데, 그 행을 클릭해서 연 상세 패널은 아무 말도 안 하게 된다.
--- 단축키를 설명해야 할 화면이 목록보다 덜 아는 일은 없어야 한다.
---
--- 키가 없으면 `GetBindingIssue`의 "key" 갈래가 알아서 아무것도 안 짚는다.
local function GetKeyWarningText(action)
	local issue = GetBindingIssue(action, "key");
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

--- 행 아래줄. 순서를 정하는 값 중 **index를 뺀 나머지가 전부** 여기 아니면 이름 줄의
--- 아이콘에 있다. 어느 것도 화면 밖에 두지 않는 게 규칙이다 - 이 목록의 일은 "왜 이
--- 순서인가"를 보여주는 것인데, 값 하나가 안 보이면 그게 정확히 사람이 못 푸는 자리가 된다.
---
--- 조각의 순서는 비교자와 같다(Ordering.lua의 CompareActionOrder): 중요도 → 호버 → 조건.
--- 왼쪽 정렬이라 모든 행이 같은 x에서 시작하므로, 두 행을 위아래로 놓으면 **처음 달라지는
--- 낱말이 곧 갈린 축**이다. GetDecidingOrderAxis가 하는 계산을 눈이 그대로 따라간다.
---
--- 중요도는 기본값이어도 적는다(5단 값이라 "없음"이 값이 아니다). 호버와 조건은 참·거짓
--- 하나뿐이라 켜졌을 때만 적는다 - 꺼진 것까지 낱말로 쓰면 대부분의 행이 "호버 아님 ·
--- 조건 없음"으로 채워져서 정작 켜진 행이 안 튄다.
---
--- 색만으로 구분하지 않도록 전부 낱말을 쓴다.
local function BuildOrderSubText(row)
	local parts = { LLL["PRIORITY" .. row.priority] };

	-- 정렬이 보는 건 hover가 nil이냐 아니냐 하나뿐이다. false는 "마우스오버가 **아닐 때만**"을
	-- 명시한 조건이라 nil과 다르고 true와 같은 칸에 선다(Ordering.lua 주석). 그래서 낱말도
	-- "호버 액션"이 아니라 "호버 조건이 걸려 있다"여야 한다 - 어느 쪽인지는 툴팁이 말한다.
	if (row.hover ~= nil) then
		parts[#parts + 1] = LLL["ORDER_FLAG_HOVER"];
	end
	if (row.isConditional) then
		parts[#parts + 1] = LLL["ORDER_FLAG_CONDITIONAL"];
	end

	-- 오류는 순서 축이 아니다. 맨 뒤에 두어 위의 셋과 섞이지 않게 한다.
	-- GetBindingIssue는 도달불가도 이슈로 친다(Misc.lua:266). 둘 다 붙이면 같은 말이 두 번
	-- 나오므로 더 구체적인 쪽만 쓴다. 자세한 이유는 행 툴팁의 단축키 줄에 있다.
	if (row.unreachable) then
		parts[#parts + 1] = ERROR_COLOR:WrapTextInColorCode(LLL["ORDER_FLAG_UNREACHABLE"]);
	elseif (row.issue) then
		parts[#parts + 1] = ERROR_COLOR:WrapTextInColorCode(LLL["ORDER_FLAG_ISSUE"]);
	end

	return table.concat(parts, " \194\183 ");
end

-- 이 목록의 행은 **왼쪽 목록의 행과 같은 제스처를 받는다**: 좌클릭은 고르고, 우클릭은
-- 편집 메뉴다. 여기서 "고른다"는 그 액션으로 간다는 뜻이고(GoToAction), 그건 왼쪽 목록에서
-- 행을 고르는 것과 같은 일이다 - 상세 패널이 그 액션의 것으로 바뀐다.
--
-- **어느 행이냐로 갈리지 않는다.** 한때 갈렸다: 보고 있는 액션의 행만 편집 메뉴를 주고
-- 나머지는 "가기" 하나만 줬다. 근거는 *"보고 있지도 않은 레이어를 팝업 하나로 바꾸는 사고"*
-- 였는데, 그 근거는 **레이어 탭에서만 우연히 성립했다** - 거기서는 "지금 보고 있는 액션"과
-- "지금 보고 있는 레이어의 액션"이 같은 값이었기 때문이다. 오버뷰 탭에서 그 우연이 깨졌다:
-- 모든 행이 남의 레이어이고, 그런데도 **같은 액션을 왼쪽 목록에서 우클릭하면 전체 메뉴가
-- 열린다.** 한 창의 두 목록이 같은 액션에 다른 메뉴를 주는 것은 규칙이 아니라 덜 만들어진
-- 것으로 읽힌다.
--
-- 대신 어디를 만지는 것인지는 **말로 붙인다.** 행 툴팁의 '범위' 줄과 이름 앞 레이어
-- 아이콘이 그 액션이 어디 사는지 이미 말하고 있다.
local ORDER_LINE_TOOLTIP_INSTRUCTIONS = { "ORDER_LINE_TOOLTIP_INSTRUCTION" };
local ORDER_LINE_GOTO_INSTRUCTIONS = { "ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO", "ORDER_LINE_TOOLTIP_INSTRUCTION" };

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

	self.SubText:SetText(BuildOrderSubText(row));

	-- 레이어는 이름 앞의 아이콘이 맡는다. **좁혀진 축마다 하나씩, 왼쪽부터** 채운다
	-- (XML 주석에 이유가 있다). 둘 다 없으면 레이어 1, 즉 모든 캐릭터·모든 전문화다.
	local tab, sideTab = GetLayerTabs(row.layerID);
	local shown = 0;
	if (tab == 2) then
		shown = shown + 1;
		SetPlayerCharacterIcon(self.LayerIcons[shown]);
	end
	if (sideTab >= 2) then
		shown = shown + 1;
		self.LayerIcons[shown]:SetTexture(GetSideTabIcon(sideTab));
	end
	for i = 1, #self.LayerIcons do
		self.LayerIcons[i]:SetShown(i <= shown);
	end

	-- 이름은 **마지막으로 켜진 아이콘 바로 뒤**에 붙는다. 안 켜진 아이콘은 자리도 안
	-- 차지한다 - 예약해두면 아이콘이 적은 행마다 이름 앞이 비고, 그 구멍은 아무 뜻도
	-- 없으면서 제일 먼저 눈에 들어온다.
	self.Name:ClearAllPoints();
	if (shown > 0) then
		self.Name:SetPoint("LEFT", self.LayerIcons[shown], "RIGHT", 5, 0);
	else
		self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 6, 8);
	end
	self.Name:SetPoint("RIGHT", self, "RIGHT", -6, 8);

	-- 지금 보고 있는 액션은 왼쪽 목록의 선택과 같은 하이라이트로 띄운다.
	self.SelectedHighlight:SetShown(elementData.isCurrent);
end

function DebounceOrderLineMixin:OnEnter()
	local elementData = self:GetElementData();
	ShowLineTooltip(self, "ANCHOR_LEFT", elementData.row, true,
		elementData.isCurrent and ORDER_LINE_TOOLTIP_INSTRUCTIONS or ORDER_LINE_GOTO_INSTRUCTIONS,
		GetLayerLabel(elementData.row.layerID));
end

function DebounceOrderLineMixin:OnLeave()
	---@diagnostic disable-next-line: redundant-parameter
	GameTooltip:SetMinimumWidth(0, false);
	GameTooltip:Hide();
end

function DebounceOrderLineMixin:OnClick(buttonName)
	-- 캡처 중에는 리스트가 아직 가정일 뿐이다(새 키 미리보기). 만지게 두지 않는다.
	if (DebounceDetailPanel:IsCapturingKey()) then
		return;
	end

	local elementData = self:GetElementData();
	local row = elementData.row;

	if (buttonName == "LeftButton") then
		-- 이미 보고 있는 행이면 갈 데가 없다. 부르면 선택을 다시 넣느라 패널만 한 번
		-- 깜빡인다.
		if (not elementData.isCurrent) then
			DebounceFrame:GoToAction(row.action, row.layerID);
		end
		return;
	end

	-- 가운데 버튼 따위는 아무것도 아니다. 등록이 `AnyUp`이라 여기까지 오므로 이름으로 막는다.
	if (buttonName ~= "RightButton") then
		return;
	end

	-- **우클릭도 그 행으로 간 다음에 연다.** 편집 메뉴가 만지는 액션은 왼쪽 목록에 있어야
	-- 한다 - `MoveAction`의 assert도, 매크로 편집기의 이름/아이콘 버튼도, `Refresh`가 선택을
	-- 유지하는 것도 전부 그 전제 위에 서 있다. 이 목록은 레이어를 가로지르므로 그 전제가
	-- 저절로 참이 아니고, 어기면 메뉴는 열리는데 항목을 고르면 오류가 나거나 아무 일도
	-- 안 일어난다.
	--
	-- 데려다 놓는 것은 새 동작이 아니다. 예전에는 남의 행에서 열리는 메뉴에 **"가기"
	-- 하나뿐**이었으므로, 가는 것이 원래 이 자리의 뜻이다. 클릭 한 번이 줄었을 뿐이다.
	if (not elementData.isCurrent) then
		DebounceFrame:GoToAction(row.action, row.layerID);
		-- 대화상자가 막아섰으면(`TryCloseAnyDialog`) 화면은 아직 딴 데 있다.
		if (DebounceFrame:GetSelectedAction() ~= row.action) then
			return;
		end
	end

	-- 왼쪽 목록이 이 액션의 elementData를 갖고 있다. 메뉴가 원래 받도록 지어진 그 테이블을
	-- 그대로 넘긴다 - 모양을 흉내내면 저쪽이 바뀔 때 조용히 어긋난다.
	local mainElementData = DebounceFrame:FindElementDataByActionInfo(row.action);
	if (mainElementData) then
		DebounceFrame:ShowEditDropdown(self, mainElementData);
	end
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
		self:ApplyOrderMove(self.moveUpNeighbor);
	end);
	controls.MoveDownButton:SetScript("OnClick", function()
		self:ApplyOrderMove(self.moveDownNeighbor);
	end);

	controls.BlockedHelp:SetScript("OnEnter", OrderBlockedHelp_OnEnter);
	controls.BlockedHelp:SetScript("OnLeave", OrderBlockedHelp_OnLeave);
end

--- 편집 중인 액션을 한 칸 옮긴다. **이웃과 순서 번호를 맞바꾸는 것이 전부다.**
---
--- 배열은 안 건드린다. 배열 자리는 이제 순서에 아무 영향이 없고(목록은 정렬해서 그린다),
--- 순서를 정하는 것은 액션이 들고 있는 seq다.
---
--- 번호가 없는 쪽이 있으면 물러난다. 키가 걸린 액션은 마이그레이션과 CleanUpDB가 번호를
--- 보장하므로 정상 경로로는 못 오는 자리지만, 여기서 nil을 맞바꾸면 **둘 다 번호를 잃고**
--- 순서가 조용히 무너진다.
function DebounceDetailPanelMixin:ApplyOrderMove(neighborRow)
	local action = _selectedAction;
	if (not action or not neighborRow) then
		return;
	end

	local neighbor = neighborRow.action;
	if (not neighbor or action.seq == nil or neighbor.seq == nil) then
		return;
	end

	action.seq, neighbor.seq = neighbor.seq, action.seq;

	neighbor._dirty = true;
	action._dirty = true;
	DebouncePrivate.UpdateBindings();
	DebounceFrame:Refresh(true);
	DebounceFrame:Update();
	PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP);
end

--- 상대 이동 버튼의 상태를 계산한다. rows는 이미 발동 순서로 정렬돼 있다.
---
--- 버튼이 만지는 건 순서 번호(seq)뿐이다. 그건 순서 말고는 아무 뜻도 없는 유일한 축이라,
--- 눌러도 조건이나 스코프나 우선순위가 따라 바뀌지 않는다. 나머지 축에서 갈렸으면
--- 비활성으로 두고 **어느 속성이 정하고 있는지**만 말한다 - 그 속성들은 각자 자기
--- 편집기(우선순위 메뉴 / 조건 편집 / 레이어 이동)에서 바뀌어야 한다.
function DebounceDetailPanelMixin:UpdateOrderMoveButtons(rows, currentIndex)
	local controls = self.ContentArea.OrderArea.Controls;
	local up, upReason, down, downReason;

	if (currentIndex and not self:IsCapturingKey()) then
		up, upReason = DebouncePrivate.ComputeOrderSwap(rows, currentIndex, -1);
		down, downReason = DebouncePrivate.ComputeOrderSwap(rows, currentIndex, 1);
	end

	-- 맞바꿀 이웃 행을 그대로 들고 있는다. 레이어는 따로 안 들고 다닌다 - 축 검사가
	-- 이웃과 같은 레이어임을 이미 보장했고, 맞바꾸기는 배열을 안 건드린다.
	self.moveUpNeighbor = up;
	self.moveDownNeighbor = down;

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
	--
	-- 오버뷰 탭에는 사이드탭이 없고, 그 목록의 모든 행이 **지금 이 특성의 활성 레이어**에서
	-- 왔다. 그러니 물어볼 다른 세계가 없다 - nil이 곧 "지금"이다. 사이드탭 값은 레이어
	-- 탭에서 떠날 때의 것이 그대로 남아 있으므로, 여기서 그걸 읽으면 화면에 있지도 않은
	-- 특성의 순서를 보여준다.
	local viewedSpec = not IsOverviewTab() and _selectedSideTab >= 3 and (_selectedSideTab - 2) or nil;
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

	-- 키가 없으면 **구역은 남기고 안쪽만 접는다.**
	--
	-- 통째로 숨기지 않는 이유는 키 지정이 바로 위 KeyArea에서 일어나기 때문이다. 없던 구역이
	-- 통째로 튀어나오는 것보다, 접혀 있던 것이 펴지는 편이 덜 놀랍고 순서를 보는 자리가
	-- 어디인지도 미리 알려준다. 남는 헤더와 설명 줄(ORDER_DESC_NO_KEY)이 왜 비었는지 말한다.
	--
	-- 예전에는 이 액션 하나를 흑백으로 그려 자리를 채웠다. 옮길 것도 누를 것도 없는 행이었고,
	-- 그 행을 만들려면 CollectActionsForKey의 레코드 모양을 손으로 흉내내야 했다(Profile.lua) -
	-- 어느 필드를 넣고 뺄지가 규칙이 되어 저쪽이 바뀌면 조용히 어긋나는 자리였다.
	if (not key) then
		orderArea.Controls:Hide();
		-- 목록을 비워서 프레임을 풀에 돌려준다. 숨기기만 하면 다음에 다시 펼 때 옛 내용이
		-- 한 프레임 스쳐 보인다.
		orderArea.ScrollBox:SetDataProvider(CreateDataProvider(), ScrollBoxConstants.DiscardScrollPosition);
		orderArea.ScrollBox:Hide();
		-- 이동 상태도 같이 지운다. 여기서 `UpdateOrderMoveButtons`를 안 지나므로 그냥 두면
		-- **앞서 보던 액션의 이웃**이 남는다. 지금은 버튼이 숨겨져 있어 누를 수가 없지만,
		-- 그 가정이 깨지는 날 엉뚱한 액션과 순서를 맞바꾼다.
		self.moveUpNeighbor = nil;
		self.moveDownNeighbor = nil;
		return;
	end

	orderArea.Controls:Show();
	orderArea.ScrollBox:Show();

	local rows = DebouncePrivate.CollectActionsForKey(key, viewedSpec);

	local currentIndex;
	for i, row in ipairs(rows) do
		if (row.action == action) then
			currentIndex = i;
			break;
		end
	end

	self:UpdateOrderMoveButtons(rows, currentIndex);

	-- 레이어를 어떻게 보여줄지는 행이 혼자 정한다. 예전에는 여기서 "섞였는가"를 재서
	-- 바뀌는 첫 행에만 라벨을 달았는데, 아이콘이 늘 서 있는 지금은 그 계산도 그 분기도
	-- 필요 없다 - 어떤 행엔 붙고 어떤 행엔 안 붙는 이유를 사용자가 알아낼 일도 없어졌다.
	local dataProvider = CreateDataProvider();
	for i, row in ipairs(rows) do
		dataProvider:Insert({
			row = row,
			isCurrent = i == currentIndex,
		});
	end

	orderArea.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.DiscardScrollPosition);
	-- 편집 중인 액션은 이제 반드시 목록 안에 있다(그 액션이 사는 레이어를 훑었으므로).
	-- 그래도 없으면 스크롤만 건드리지 않는다 - 목록 자체는 이 키의 사실이라 보여줄 값어치가 있다.
	if (currentIndex) then
		orderArea.ScrollBox:ScrollToElementDataIndex(currentIndex, ScrollBoxConstants.AlignNearest);
	end
end

--- 단축키 줄은 캡처 여부와 무관하게 늘 같은 값을 보여준다. 듣고 있다는 표시는
--- SetBindingMode가 버튼 위에 켜는 하이라이트 하나가 맡는다 - 값까지 바꿔놓으면 취소했을 때
--- 되돌릴 것이 생기고, 안 바꾸면 취소가 아무것도 안 움직인다.
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

	local warning = GetKeyWarningText(action);
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
		-- 편집칸이 키보드 포커스를 들고 있으면 **양쪽이 다 받는다.** 포커스 잡힌 EditBox와
		-- 키보드를 켠 이 버튼에 같은 키가 각각 들어가서, 한 번 누른 것이 검색어에도 들어가고
		-- 단축키도 바꾼다 - 한 번의 입력이 두 가지 일을 한다.
		--
		-- 마우스 위치는 상관이 없다. 키보드는 마우스가 패널 밖에 있어도 이 버튼에 들어온다
		-- (잡히지 않는 건 클릭뿐이다). 그래서 "패널 위에서만 듣는다"로는 막을 수 없고,
		-- 듣기 시작할 때 포커스를 거두는 수밖에 없다. 반대 방향(듣는 중에 검색창을 클릭)은
		-- SearchBox_OnFocusGained이 캡처를 끝내는 것으로 막는다.
		local focus = GetCurrentKeyBoardFocus();
		if (focus) then
			focus:ClearFocus();
		end

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

--- 키를 저장하고 되비춘다. 목록이 키순으로 정렬돼 있으므로 왼쪽 자리도 바뀐다 - 그 자리가
--- 화면 밖이면 따라간다. 목록이 움직이는 이유가 사용자가 방금 누른 키 하나뿐이라, 어디로
--- 갔는지 보여주는 편이 놀래키는 것보다 낫다.
---
--- 순서 번호는 **처음 키를 걸 때** 받는다. 그 시점의 맨 뒤라, 새로 건 바인딩은 언제나
--- 기존 것들 뒤에서 시작한다.
---
--- 한때 이 자리에 번호가 없었고 순서의 마지막 단계가 레이어 배열의 자리를 읽었다. 그래서
--- 방금 만든 액션은 배열 끝이라 뒤로 붙고, 예전부터 배열 앞에 있던 액션(키를 뗐다가 다시
--- 거는 경우)은 기존 것들 위로 끼어들었다 - 같은 조작인데 결과가 달랐다.
---
--- 키를 떼도 번호는 남긴다. 그래야 잠깐 뗐다 다시 걸었을 때 사용자가 ↑↓로 정해둔 자리로
--- 돌아온다. 번호가 남아 있으면 여기서 새로 주지 않는 이유가 그것이다.
function DebounceDetailPanelMixin:SetActionKey(key)
	local action = _selectedAction;
	if (not action or action.key == key) then
		return false;
	end

	if (key ~= nil and action.seq == nil) then
		local _, layer = DebouncePrivate.FindLayerID(action);
		if (layer) then
			action.seq = layer:GetNextSeq();
		end
	end

	action.key = key;
	action._dirty = true;
	DebouncePrivate.UpdateBindings();
	DebounceFrame:Refresh(true);
	DebounceFrame:ScrollActionIntoView(action);
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
---
--- `macroOriginalText`는 여기서만 정해진다. [취소]가 돌아갈 자리이므로 편집이 사는 동안
--- (= 이 액션이 선택돼 있는 동안) 움직이지 않는다.
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
---
--- 견주는 것은 **액션에 들어 있는 값**이지 `macroOriginalText`가 아니다. 저 둘은 편집이
--- 시작된 직후에만 같고, 그 뒤로는 뜻이 갈린다 - 하나는 "지금 저장된 것", 하나는
--- "[취소]가 돌아갈 자리"다. 여기서 `macroOriginalText`를 덮으면 탭을 한 번 왕복하는
--- 것만으로 돌아갈 자리가 사라진다(떠날 때마다 자동 저장이 돌기 때문이다).
function DebounceDetailPanelMixin:SaveMacroText()
	local action = self.macroAction;
	if (not action) then
		return;
	end

	local text = self.ContentArea.MacroArea.Editor.ScrollFrame.EditBox:GetText();
	if (text == (action.value or "")) then
		return;
	end

	action.value = text;
	action._dirty = true;
	DebouncePrivate.UpdateBindings();
end

--- [취소] = **이 액션을 연 뒤로** 고친 것을 버린다. 탭을 왕복했든 아니든 같다.
---
--- 팝업이었을 때는 "닫으면서 버린다"였는데 탭에는 닫는다는 게 없다. 그래서 본문만 열었을
--- 때로 되돌리고 그 자리에 남는다.
---
--- 되돌릴 곳은 **두 군데**다. 편집칸과 액션 - 탭을 떠날 때마다 자동 저장이 돌기 때문에
--- 버려야 할 본문이 이미 `action.value`에 들어가 있을 수 있다. 편집칸만 되돌리면 [취소]가
--- 아무 일도 안 한 것처럼 보이고, 원래 본문은 되찾을 길이 없어진다.
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
		local original = self.macroOriginalText or "";
		self.ContentArea.MacroArea.Editor.ScrollFrame.EditBox:SetText(original);
		if ((action.value or "") ~= original) then
			action.value = original;
			action._dirty = true;
			DebouncePrivate.UpdateBindings();
		end
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
DebounceUI.SORTED_UNIT_LIST = SORTED_UNIT_LIST;
DebounceUI.BINDING_TYPE_NAMES = BINDING_TYPE_NAMES;
DebounceUI.GetLayerID = GetLayerID;
DebounceUI.IsOverviewTab = IsOverviewTab;
DebounceUI.GetTabLabel = GetTabLabel;
DebounceUI.GetSideTabaLabel = GetSideTabaLabel;
DebounceUI.GetLayerLabel = GetLayerLabel;
DebounceUI.MoveAction = MoveAction;
DebounceUI.ShowDeleteConfirmationPopup = ShowDeleteConfirmationPopup;
DebounceUI.NameAndIconForAction = NameAndIconForAction;
DebounceUI.ShowInputBox = ShowInputBox
