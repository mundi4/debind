local _, DebouncePrivate     = ...;
DebouncePrivate.DebounceUI   = {};

local NUM_SPECS              = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));
local Constants              = DebouncePrivate.Constants;
local LLL                    = DebouncePrivate.L;
local DebounceUI             = DebouncePrivate.DebounceUI;

local MACRO_NAME_CHAR_LIMIT  = 32;
local MACRO_CHAR_LIMIT       = 1000;
-- 폭은 하나다. 두 열(결과 | 통)이 늘 같이 서 있고 접히지 않는다 - 이유는 XML의
-- DetailPanel 주석에.
-- 4 + 350(결과) + 16 + 405(통) + 20(스크롤바) = 795.
local FRAME_WIDTH            = 795;
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

	-- 매크로 슬롯에 들어가는 것은 **원문이 아니라 `$상태`를 걷어낸 사본이다.** 원문을 그대로
	-- 넣으면 와우 파서가 자기가 모르는 옵션마다 대화창에 "Unknown macro option: $state1"을
	-- 찍는다 - 아이콘 하나 뽑자고 사용자 채팅창을 더럽히는 셈이다. 캐시 키는 원문 그대로.
	local text = DebouncePrivate.StripCustomStateConditions(macrotext);

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
		CreateMacro(TEMP_MACRO_NAME, QUESTION_MARK_ICON_NUM, text, isCharacterSpecific);
	else
		EditMacro(TEMP_MACRO_NAME, nil, nil, text);
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

local function GetLayerID(tab, sideTab)
	tab = tab or _selectedTab;
	sideTab = sideTab or _selectedSideTab;
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
	if (DebounceIconSelectorFrame:Close() and DebounceMacroFrame:Close() and DebounceDetailPanel:Close()) then
		return true;
	end
	return false;
end

--- 상세 패널에는 저장을 미루는 상태가 없다 - 키도 순서도 즉시 반영된다. 그래서 패널은
--- 아무것도 잠그지 않는다. 잠그는 건 팝업인 아이콘 선택기뿐이다.
---
--- **매크로 창도 여기 없다.** 창으로 돌아왔지만 모드가 아니라 보기인 것은 그대로다 - 열어둔
--- 채로 다른 액션을 고르거나 레이어를 옮겨도 되고, 그때마다 떠나는 쪽에서 저장된다.
---
--- **주문 선택 창도 여기 없다.** 일부러다 - 그 창은 대상을 안 고르고 메인 창에서 열려 있는
--- 레이어에 넣는다. 여기 넣으면 탭이 잠겨서 대상을 바꿀 방법이 사라진다.
local function IsEditingAction(action)
	if (DebounceIconSelectorFrame:IsShown() and (action == nil or DebounceIconSelectorFrame.editAction == action)) then
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
	-- **행이 들고 온 레이어를 믿는다.** 한때 여기서 화면이 보고 있는 레이어와 같은지
	-- 확인했는데, 그건 "메뉴는 왼쪽 목록에서만 열린다"가 참이던 시절의 검사다. 지금은
	-- 순서 목록에서도 열리고 오버뷰 탭은 레이어를 섞어 담으므로, 화면의 레이어는 이
	-- 액션과 아무 상관이 없다. 값 자체는 목록을 만들 때 프로필에서 직접 읽은 것이다.
	assert(fromLayerID, "MoveAction: elementData has no layer");

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
				-- 행의 단축키 칸과 같은 말을 쓴다(DebounceLineMixin:UpdateKeyButton). 한때 여기만 따로 번역된 키를
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

	-- 행은 풀에서 나오므로 앞서 그리던 행의 상태를 들고 온다. 커서가 지금 이 행 위에
	-- 있는지를 다시 물어서 맞춘다 - 이미 올라가 있는 프레임에는 OnEnter가 다시 안 온다.
	self:UpdateKeyButton(self:IsMouseMotionFocus());

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
	self:UpdateKeyButton(true);
end

function DebounceLineMixin:OnLeave()
	---@diagnostic disable-next-line: redundant-parameter
	GameTooltip:SetMinimumWidth(0, false);
	GameTooltip:Hide();
	self:UpdateKeyButton(false);
end

--- 단축키 칸의 버튼을 띄우고 내린다.
---
--- **듣는 중에는 안 내린다.** 마우스는 캡처와 상관없이 움직이고(키보드는 커서가 어디 있든
--- 이 버튼에 들어온다), 여기서 숨기면 OnHide가 자기 캡처를 끝내버린다 - 커서를 옆으로
--- 치우기만 해도 듣기가 끊긴다.
function DebounceLineMixin:UpdateKeyButton(hovered)
	local button = self.KeyButton;
	if (DebounceDetailPanel.captureButton == button) then
		return;
	end

	local elementData = self:GetElementData();
	local action = elementData and elementData.action;
	if (not hovered or not action) then
		button:Hide();
		self.BindingText:Show();
		return;
	end

	-- 우클릭 해제를 첫 호버부터 받는다. `SetBindingMode`도 같은 값으로 되돌리지만 그건
	-- 한 번이라도 들은 뒤의 이야기고, UIPanelButtonTemplate의 기본은 좌클릭뿐이다.
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp");

	-- 글자와 버튼은 같은 자리다. 둘이 겹쳐 보이지 않게 글자를 내린다.
	button:SetText(action.key and GetBindingText(action.key) or LLL["DETAIL_NO_KEY"]);
	self.BindingText:Hide();
	button:Show();
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
				DebounceMacroFrame:Open(elementData.action);
				return;
			end

			-- **메뉴를 여는 행이 곧 고른 행이다.** 선택은 화면이 "지금 이 액션 이야기 중"이라고
			-- 말하는 표시인데, 메뉴가 남의 행에서 열리면 그 말과 메뉴가 가리키는 것이 어긋난다.
			-- 상세 패널은 A를 보여주는데 방금 연 메뉴는 B를 지우려는 상태가 실제로 생긴다.
			--
			-- 좌클릭과 같은 함수를 지난다 - 이미 고른 행이면 저쪽이 일찍 돌아선다.
			--
			-- **집어오는 것보다 먼저다.** 이 호출은 상세 패널을 닫고, 그 길에 매크로 본문
			-- 저장이 딸려 오면 목록이 통째로 다시 지어진다 - 먼저 집으면 그 테이블이 낡는다.
			-- 아래 함수가 존재하는 이유가 정확히 그 문제다(`CloseDialogsAndRefetchElementData`).
			DebounceFrame:SetSelectedAction(elementData.action);

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
	local id = self:GetID();
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

		-- 사이드탭도 탭과 같은 이동이다 - 바뀌는 것은 레이어 하나뿐이지만 목록이 통째로
		-- 갈리는 것은 같다. 고른 것을 놓는 이유도 같다(`DebounceFrameMixin:SetTab`).
		DebounceFrame:SetSelectedAction(nil);

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
--
-- 오버뷰 탭은 이 계산을 통째로 안 탄다. 세는 것도 다르고(문제의 수), 없으면 아무것도 안
-- 붙는다. 사이드탭도 안 건드린다 - 그 탭에서는 숨어 있다.
function DebounceFrameMixin:UpdateActionCounts()
	for tabId, tab in ipairs(self.Tabs) do
		local label = GetTabLabel(tabId);

		do
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
	self.SearchBox:SetScript("OnEditFocusGained", self.SearchBox_OnFocusGained);

	DebouncePrivate.db.global.ui = DebouncePrivate.db.global.ui or {};
	self:ClearAllPoints();
	local pos = DebouncePrivate.db.global.ui.anchorPos;
	if (pos) then
		self:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", pos.x, pos.y);
	else
		self:SetPoint("CENTER", "UIParent", 0, 0);
	end

	self:SetWidth(FRAME_WIDTH);
end

function DebounceFrameMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
	end

	self:Refresh();
	-- **`Update`까지 와야 왼쪽 열이 그려진다.** `Refresh`는 오른쪽 목록만 다시 짓고, 왼쪽은
	-- 선택이 아니라 프로필 전체를 보므로 여기서 같이 깨워야 한다. 예전에는 선택이 없으면
	-- 왼쪽이 접혀 있어서 이 줄이 없어도 티가 안 났다.
	self:Update();
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
	-- 매크로 본문은 여기서 저장된다. 매크로 창은 이 창의 자식이라 부모가 숨으면 같이
	-- 숨지만, 그 저장을 부모-자식 관계에 맡기지 않는다 - 여기서 명시적으로 닫는다.
	DebounceMacroFrame:Close();
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

function DebounceFrameMixin:Refresh(retainScrollPosition)
	HideDeleteConfirmationPopup();

	local dataProvider = CreateDataProvider();
	local layerID = GetLayerID();
	local elements = BuildSortedElements(DebouncePrivate.GetProfileLayer(layerID), layerID);

	for _, elementData in ipairs(elements) do
		dataProvider:Insert(elementData);
	end

	self.dataProvider = dataProvider;
	self.ScrollBox:SetDataProvider(dataProvider, retainScrollPosition and ScrollBoxConstants.RetainScrollPosition or ScrollBoxConstants.DiscardScrollPosition);

	-- 선택은 **액션이 없어졌을 때만** 풀린다.
	--
	-- 예전 규칙은 "지금 보이는 목록에 없으면 푼다"였다. 그때는 편집이 왼쪽 목록에서만
	-- 시작됐으니 둘이 같은 말이었는데, 지금은 순서 목록에서 **다른 레이어의 액션**을
	-- 편집할 수 있다. 그 규칙을 그대로 두면 매크로 편집기를 열자마자 다음 재구성이 선택을
	-- 풀어 패널이 접힌다 - 화면에 안 보인다는 이유로 방금 열어준 편집을 뺏는 것이다.
	--
	-- 뷰가 바뀌어서 선택을 놓는 것은 `SetTab`이 따로 한다. 여기는 "그 액션이 아직
	-- 프로필에 있나"만 본다.
	if (_selectedAction and not DebouncePrivate.FindLayerID(_selectedAction)) then
		self:SetSelectedAction(nil);
	end

	-- 제목은 탭 좌표를 낱말로 다시 말한다.
	self:SetTitle(format(LLL["DEBOUNCE_TITLE_FORMAT"], GetTabLabel(_selectedTab), GetSideTabaLabel(_selectedSideTab)));
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
	-- 매크로 창이 열려 있으면 대상도 같이 옮긴다. 떠나는 액션의 본문은 그 안에서 저장된다
	-- (`Refresh` → `macroAction ~= action` → `Save`). 창이 닫혀 있으면 아무 일도 안 한다.
	DebounceMacroFrame:Refresh();
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
	-- 새 액션도 순서 규칙을 똑같이 지난다. 지금 오는 것들은 키 없이 태어나므로 번호를 안
	-- 받고(SetActionKey가 걸 때 준다), props에 키가 실려 오면 여기서 맨 뒤 번호를 받는다.
	layer:PlaceLast(action);

	-- 목록이 정렬돼 있으므로 새 액션이 맨 뒤에 붙는다는 보장이 없다. 다시 만들고 찾아간다.
	self:Refresh(true);

	-- 곧바로 선택한다. 방금 생긴 액션은 키를 정해야 쓸모가 생기는데, 선택이 왼쪽 열을
	-- 그 액션으로 채운다. 커서에서 떨궈 만든 것과 **같은 대접**이어야 한다
	-- (OnReceiveDrag) - 선택 창에서 고른 것만 아무 데도 안 데려가면 같은 일을 하는 두 길이
	-- 다르게 끝난다.
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
	DebounceMacroFrame:Refresh();

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

	self.AddPortrait:SetEnabled(enableButtons);
	self.CustomStatesPortrait:SetEnabled(enableButtons);
	self.OptionsPortrait:SetEnabled(enableButtons);
	self.SearchBox:SetEnabled(enableButtons);
	self.GroupByKeyCheckButton:SetEnabled(enableButtons);
end

function DebounceFrameMixin:SetTab(id)
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);

	-- **고른 것을 여기서 놓는다.** 탭을 옮기면 그 액션은 새 목록에 없고, 그러면 상세 패널만
	-- 화면 어디에도 없는 액션을 붙들고 열려 있게 된다 - 왼쪽에는 짚어줄 행이 없으니 그 패널이
	-- 무엇을 고치는 중인지 말해줄 것이 아무것도 없고, 거기서 키를 바꾸면 안 보이는 레이어가
	-- 바뀐다. `Refresh`의 "액션이 없어졌을 때만 푼다"가 이 자리를 안 본다(그쪽 주석 참고).
	--
	-- 탭이 실제로 바뀔 때만이다. `GoToAction`은 같은 탭에도 이 함수를 부르고 곧바로 목표
	-- 액션을 고르는데, 거기서 놓았다 다시 잡으면 패널이 한 번 접혔다 펴진다.
	if (_selectedTab ~= id) then
		self:SetSelectedAction(nil);
	end

	_selectedTab = id;
	PanelTemplates_SetTab(self, _selectedTab);
	self:UpdateSideTabs();

	if (not self.SideTabs[_selectedSideTab]:IsShown()) then
		_selectedSideTab = 1;
		self:UpdateSideTabs();
	end

	-- 주문 선택 창은 **여기서 닫는다.** 그 창의 쓸모가 "열어둔 채 탭을 옮겨 다니며 골라
	-- 넣는 것"이라 탭 전환에 안 닫는 것이 규칙인데(`UpdateButtons`의 잠금 목록에도 없다),
	-- [+]의 상태는 **탭의 함수**라 다음 Update를 기다리면 안 된다. Refresh는 목록만 다시
	-- 만들고 버튼은 안 건드린다.
	self:UpdateButtons();
	self:Refresh();
end

--- elementData를 주면 버튼 대신 그것으로 연다. 순서 목록이 자기 행 대신 **왼쪽 목록이
--- 만든** elementData를 넘기기 위한 통로다 - 메뉴가 읽는 layer/index는 저쪽 소유의 값이라
--- 모양을 흉내내면 저쪽이 바뀔 때 조용히 어긋난다.
function DebounceFrameMixin:ShowEditDropdown(button, elementData)
	elementData = elementData or button:GetElementData();
	local action = elementData.action;

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

	local action = { type = type, value = value };
	destLayerID = destLayerID or GetLayerID();

	-- 여기서부터 프로필이 바뀐다. 갈아엎기 전에 상세 패널을 떠나보낸다 - 이 패널은 잠그지
	-- 않는 대신 **떠나는 쪽이 저장한다**로 돼 있고(Close 참고), 드롭도 떠나는 것이다.
	--
	-- 없어도 본문 자체는 살아남는다. 편집하던 액션이 목록에서 빠지면 Refresh가 선택을 풀면서
	-- 저장하고, 남으면 매크로 창의 Refresh가 대상이 같아서 편집칸을 안 건드린다. 그런데 그건
	-- 서로 무관한 가드 둘이 맞물린 결과라 규칙으로 삼을 수 없고, 실제로 두 가지가 샌다 -
	-- UpdateBindings가 저장 전 본문으로 한 번 헛돌고(아래에서 부르고 저장이 또 부른다),
	-- 키를 듣는 중이었다면 캡처가 안 끊긴 채 목록만 갈린다.
	DebounceMacroFrame:Close();
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
	if (destLayerID == GetLayerID()) then
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
	self.editAction = nil;
	self.onAccepted = onAccepted;
	self:Show();
end

--- 이미 있는 액션의 이름·아이콘만 고친다. `onAccepted`는 없어도 된다 - 팝업 아래 화면이
--- 그대로 살아 있으면 확인 뒤에 갈 데가 없다.
function DebounceIconSelectorFrameMixin:OpenForAction(action, onAccepted)
	self.mode = IconSelectorPopupFrameModes.Edit;
	self.editAction = action;
	self.onAccepted = onAccepted;
	self:Show();
end

function DebounceIconSelectorFrameMixin:OnShow()
	if (self.mode == IconSelectorPopupFrameModes.Edit) then
		if (not self.editAction) then
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
	self.editAction = nil;
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
		local action = self.editAction;
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
		self.editAction.name = text;
		self.editAction.icon = iconTexture;
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
		if (not self.editAction) then
			return false;
		end
		if (self.editAction.name ~= newName or self.editAction.icon ~= newIcon) then
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

DebounceDetailPanelMixin = {};

--- 왼쪽 열. 보여주는 것은 하나다 - **지금 이 키보드가 어떻게 생겼나.**
---
--- 활성 레이어에서 키가 걸린 액션 전부를 키로 묶고, 그룹 안은 발동 순서로 놓는다. 통(오른쪽)이
--- 한 번에 한 레이어만 보여주므로 "이 키에 뭐가 다 걸렸나"에 답할 자리가 따로 필요하고,
--- 그 자리가 여기다. 넣으면 여기 나타나는 것이 레이어가 무엇을 하는지에 대한 설명이다.
---
--- **키 없는 액션은 안 담는다.** 이 열의 문장이 "지금 키보드"라서 아직 키가 아닌 것은
--- 그 문장 밖이고, 오른쪽 통이 이미 전부를 들고 있어서 잃는 것도 없다.
---
--- 한때 매크로 편집기가 두 번째 탭이었다. 되돌린 이유는 `DebounceMacroFrame` 주석에 있다.
function DebounceDetailPanelMixin:OnLoad()
	self.ContentArea.EmptyText:SetText(LLL["DETAIL_EMPTY"]);

	local header = self.ContentArea.OrderArea.ColumnHeader;
	header.PriorityLabel:SetText(LLL["ORDER_COL_PRIORITY"]);
	header.HoverLabel:SetText(LLL["ORDER_COL_HOVER"]);
	header.CondLabel:SetText(LLL["ORDER_COL_CONDITIONAL"]);
	header.LayerLabel:SetText(LLL["ORDER_COL_LAYER"]);

	self:InitializeOrderScrollBox();

	self.initialized = true;
	self:Refresh();
end

--- 선택이 바뀌었다. 듣던 중이었다면 그 액션의 것이었으므로 여기서 끝낸다.
function DebounceDetailPanelMixin:OnSelectionChanged()
	self:SetBindingMode(false);
	self:Refresh();
end

function DebounceDetailPanelMixin:Refresh()
	if (not self.initialized) then
		return;
	end
	self:RefreshKeyboard();
end

--- 다른 것으로 넘어가기 전에 부르는 계약. 이 패널은 저장을 미루는 상태가 **없다** - 키도
--- 순서도 누르는 즉시 반영된다. 그래서 아무것도 막지 않고 언제나 true다.
---
--- 매크로 본문은 여기 없다. 그건 창(`DebounceMacroFrame`)이 자기 몫으로 들고 있다 -
--- `TryCloseAnyDialog`가 둘 다 부른다.
---
--- 선택은 건드리지 않는다. 부르는 쪽이 이미 선택을 바꾸는 중이다.
function DebounceDetailPanelMixin:Close()
	self:CancelKeyCapture();
	return true;
end

--- 켜짐/꺼짐 두 칸이 쓰는 표시. 점 하나가 자리를 안 옮기므로 세로로 읽힌다.
--- 꺼진 칸도 비워두지 않는다 - 빈 칸은 "값이 없다"로 읽히는데 여기서는 "아니다"가 값이다.
local COLUMN_ON  = "|cnGREEN_FONT_COLOR:" .. string.char(226,151,143) .. "|r";
local COLUMN_OFF = "|cnDISABLED_FONT_COLOR:" .. string.char(194,183) .. "|r";

-- 명시적 선택**이어야 하고, 좌클릭은 습관적으로 눌러보는 버튼이다.
local ORDER_LINE_GOTO_INSTRUCTIONS = { "ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO" };

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

	-- 중요도는 기본값이어도 적는다. 5단 값이라 "없음"이 값이 아니고, 이 칸이 비면 표의
	-- 첫 칸이 행마다 있다 없다 한다.
	self.PriorityText:SetText(LLL["PRIORITY" .. row.priority]);

	-- 정렬이 보는 건 hover가 nil이냐 아니냐 하나뿐이다. false는 "마우스오버가 **아닐 때만**"을
	-- 명시한 조건이라 nil과 다르고 true와 같은 칸에 선다(Ordering.lua 주석).
	self.HoverText:SetText(row.hover ~= nil and COLUMN_ON or COLUMN_OFF);
	self.CondText:SetText(row.isConditional and COLUMN_ON or COLUMN_OFF);

	-- 층 칸. **좁혀진 축마다 아이콘 하나씩**이고, 둘 다 없으면 레이어 1(모든 캐릭터·모든
	-- 전문화)이다. 표라서 자리는 예약해 둔다 - 안 켜진 칸이 비어 있는 것이 곧 답이다.
	-- **칸마다 축이 정해져 있다.** 왼쪽 칸은 캐릭터 전용인가, 오른쪽 칸은 직업·전문화로
	-- 좁혔는가. 목록이던 시절에는 켜진 것만 왼쪽부터 채웠는데, 표에서는 그러면 같은 그림이
	-- 행마다 다른 칸에 서서 세로로 읽을 수가 없다.
	local tab, sideTab = GetLayerTabs(row.layerID);
	if (tab == 2) then
		SetPlayerCharacterIcon(self.LayerIcons[1]);
	end
	self.LayerIcons[1]:SetShown(tab == 2);

	if (sideTab >= 2) then
		self.LayerIcons[2]:SetTexture(GetSideTabIcon(sideTab));
	end
	self.LayerIcons[2]:SetShown(sideTab >= 2);

	-- 지금 보고 있는 액션은 왼쪽 목록의 선택과 같은 하이라이트로 띄운다.
	self.SelectedHighlight:SetShown(elementData.isCurrent);
end

function DebounceOrderLineMixin:OnEnter()
	local elementData = self:GetElementData();
	ShowLineTooltip(self, "ANCHOR_LEFT", elementData.row, true,
		ORDER_LINE_GOTO_INSTRUCTIONS, GetLayerLabel(elementData.row.layerID));
end

function DebounceOrderLineMixin:OnLeave()
	---@diagnostic disable-next-line: redundant-parameter
	GameTooltip:SetMinimumWidth(0, false);
	GameTooltip:Hide();
end

--- 결과 목록의 행을 누르면 **그 액션이 사는 통으로 데려간다.**
---
--- 이 목록은 사영이다 - 행마다 다른 레이어에서 왔고, 여기서 편집을 열면 "어디 붙은
--- 액션인지 모르는 채로" 만지는 일이 된다. 대신 통을 그 레이어로 옮기고 행을 짚어주면,
--- 그 다음 손질은 전부 통 쪽의 규칙대로 일어난다.
---
--- 좌우 클릭이 같은 일을 한다. 여기서 나뉠 뜻이 없기 때문이다 - 편집 메뉴는 도착한 뒤에
--- 열면 되고, 우클릭만 데려가게 두면 좌클릭이 아무 반응도 없는 목록이 된다.
function DebounceOrderLineMixin:OnClick()
	-- 캡처 중에는 이 목록이 아직 옛 키의 것이다. 곧 갈아치워질 화면에서 떠나지 않는다.
	if (DebounceDetailPanel:IsCapturingKey()) then
		return;
	end

	local row = self:GetElementData().row;
	DebounceFrame:GoToAction(row.action, row.layerID);
end

function DebounceDetailPanelMixin:InitializeOrderScrollBox()
	local orderArea = self.ContentArea.OrderArea;
	local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 2);
	-- 헤더와 행이 섞이므로 템플릿을 하나로 못 박지 못한다. 오른쪽 목록과 같은 방식이고,
	-- 키 헤더도 **같은 템플릿**이다 - 한 창의 두 목록이 키를 다른 그림으로 가르면 안 된다.
	view:SetElementFactory(function(factory, elementData)
		if (elementData.isHeader) then
			factory("DebounceKeyHeaderTemplate", function(frame)
				frame:Init(elementData);
			end);
		else
			factory("DebounceOrderLineTemplate", function(button)
				button:Init(elementData);
			end);
		end
	end);
	ScrollUtil.InitScrollBoxListWithScrollBar(orderArea.ScrollBox, orderArea.ScrollBar, view);
end

--- 활성 레이어에서 키가 걸린 액션 전부. 키로 묶고, 그룹 안은 발동 순서다.
---
--- 순서를 내는 것은 `CollectActionsForKey`로, 이 애드온에서 순서를 말하는 자리가 그 함수
--- 하나뿐이다 - 두 화면이 다른 답을 낼 길이 없다.
---
--- 특성은 **지금 것**으로 고정이다. 오른쪽에서 오프스펙 레이어를 열어도 여기는 안 따라간다.
--- 이 열의 문장이 "지금 이 키보드"라서, 따라가면 그 문장이 화면마다 달라진다. 대신
--- 오프스펙 액션을 만졌을 때 여기가 조용한 것 자체가 "이건 지금 안 돈다"를 말한다.
local function BuildKeyboardElements()
	local keySeen, keyArr = {}, {};
	for _, layer in DebouncePrivate.EnumerateProfileLayers() do
		for _, action in layer:Enumerate() do
			local key = action.key;
			if (key and not keySeen[key]) then
				keySeen[key] = true;
				keyArr[#keyArr + 1] = key;
			end
		end
	end

	sort(keyArr, DebouncePrivate.CompareKeys);

	local elements = {};
	for _, key in ipairs(keyArr) do
		elements[#elements + 1] = { isHeader = true, key = key };
		for _, row in ipairs(DebouncePrivate.CollectActionsForKey(key)) do
			elements[#elements + 1] = {
				row = row,
				isCurrent = row.action == _selectedAction,
			};
		end
	end
	return elements;
end

--- 왼쪽 열을 다시 그린다.
---
--- 선택은 목록을 **거르지 않는다.** 목록은 언제나 키보드 전부이고, 선택이 하는 일은 그 행을
--- 짚는 것 하나뿐이다(`isCurrent`).
function DebounceDetailPanelMixin:RefreshKeyboard()
	local orderArea = self.ContentArea.OrderArea;
	local elements = BuildKeyboardElements();

	-- 걸린 키가 하나도 없으면 구역을 통째로 내린다. 머리줄만 남기면 칸 이름 넷이 아무것도
	-- 안 이고 서 있는 표가 되는데, 그건 비었다는 사실보다 눈에 먼저 들어온다.
	if (#elements == 0) then
		orderArea:Hide();
		self.ContentArea.EmptyText:Show();
		return;
	end

	self.ContentArea.EmptyText:Hide();
	orderArea:Show();

	local dataProvider = CreateDataProvider();
	local selectedIndex;
	for i, elementData in ipairs(elements) do
		if (elementData.isCurrent) then
			selectedIndex = i;
		end
		dataProvider:Insert(elementData);
	end
	orderArea.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition);

	if (selectedIndex) then
		orderArea.ScrollBox:ScrollToElementDataIndex(selectedIndex, ScrollBoxConstants.AlignNearest);
	end
end

--- 지금 단축키를 듣고 있는가.
---
--- **사용자가 버튼을 눌러서 들어온 상태만** 참이다. 예전에는 키가 없는 액션이면 무조건
--- 참이었는데, 그러면 사용자가 연 적 없는 모드가 열려서 다른 모든 동작이 "지금 캡처하면
--- 안 된다"를 따로 판단해야 했다. 지금은 버튼 하나의 상태라 그럴 일이 없다.
function DebounceDetailPanelMixin:IsCapturingKey()
	return self.bindingMode == true;
end


--- 듣는 표시. 블리자드 단축키 버튼이 쓰는 것과 같은 텍스처다(CustomBindingButtonTemplate).
--- 행 버튼은 풀에서 나오므로 XML에 못 박지 못하고, 처음 듣는 순간 한 번 만든다.
local function EnsureCaptureHighlight(button)
	if (not button.SelectedHighlight) then
		local selected = button:CreateTexture(nil, "OVERLAY");
		selected:SetTexture("Interface\\Buttons\\UI-Silver-Button-Select");
		selected:SetBlendMode("ADD");
		selected:SetAllPoints(button);
		selected:Hide();
		button.SelectedHighlight = selected;
	end
	return button.SelectedHighlight;
end

--- 과녁을 듣는 상태로 넣고 뺀다.
---
--- 듣는 동안에만 키보드·휠·게임패드를 켠다. 평소에는 좌/우클릭만 받으므로 목록에 버튼이
--- 몇 개 떠 있어도 키보드를 먹지 않는다.
function DebounceDetailPanelMixin:SetBindingMode(active, button)
	active = (active and _selectedAction ~= nil) or false;
	if (self:IsCapturingKey() == active) then
		return;
	end
	self.bindingMode = active or nil;

	-- 켤 때는 부르는 쪽이 준 과녁을, 끌 때는 **켰던 그 과녁**을 되돌린다. 행 버튼은 풀에서
	-- 나오므로 그 사이에 다른 행을 그리고 있을 수 있는데, 여기서 다시 찾으면 엉뚱한 행의
	-- 키보드를 끄고 원래 행은 켠 채로 남는다.
	if (active) then
		self.captureButton = button;
	end
	button = self.captureButton;
	if (not active) then
		self.captureButton = nil;
	end
	if (not button) then
		return;
	end
	EnsureCaptureHighlight(button);
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


--- 목록 행의 단축키 칸. 패널 버튼과 **같은 기계**로 들어간다 - 같은 일이 두 자리에 있으므로
--- 결과가 갈릴 길이 없어야 한다.
---
--- 먼저 그 행을 고른다. 캡처는 `_selectedAction`에 쓰므로, 고르지 않으면 커서가 얹힌 행과
--- 키가 걸리는 액션이 어긋난다.
function DebounceDetailPanelMixin:RowKeyButton_OnClick(button, mouseButton)
	if (self:IsCapturingKey()) then
		self:KeyButton_OnInput(mouseButton);
		return;
	end

	local elementData = button:GetParent():GetElementData();
	local action = elementData and elementData.action;
	if (not action) then
		return;
	end
	DebounceFrame:SetSelectedAction(action);

	if (mouseButton == "RightButton") then
		self:UnbindKey();
		return;
	end
	self:SetBindingMode(true, button);
end

function DebounceDetailPanelMixin:RowKeyButton_OnEnter(button)
	local elementData = button:GetParent():GetElementData();
	local action = elementData and elementData.action;

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, LLL["KEY"]);
	local key = action and action.key;
	if (key) then
		GameTooltip_AddHighlightLine(GameTooltip, GetBindingText(key));
	end
	GameTooltip_AddNormalLine(GameTooltip, LLL["DETAIL_KEY_BUTTON_DESC"]);
	GameTooltip_AddNormalLine(GameTooltip, LLL["DETAIL_KEY_BUTTON_UNBIND_DESC"]);
	GameTooltip:Show();
end

--- **이 과녁이 듣고 있을 때만** 끝낸다. 행은 풀에서 돌아가므로, 조건 없이 끄면 스크롤로
--- 사라진 남의 행이 지금 듣고 있는 행의 캡처를 뺏는다.
function DebounceDetailPanelMixin:CancelKeyCaptureFor(button)
	if (self.captureButton == button) then
		self:SetBindingMode(false);
	end
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
-- 매크로 편집 창
--
-- 저장 규칙은 기본 매크로 창(Blizzard_MacroUI.lua)을 그대로 따른다: **떠날 때 저장.**
-- 거기서는 다른 매크로를 고르거나, 창이 닫히거나, 이름/아이콘 편집기를 열면 SaveMacro()가
-- 묻지 않고 불린다. 여기도 같고, 버리는 길은 [취소] 버튼 하나뿐이다.
--
-- 그래서 저장을 미루는 상태가 없다. HasUnsavedChanges / 저장-버림 팝업 / Close(force)
-- 계약은 이 창이 탭이던 시절에 이미 사라졌고, 창으로 돌아왔다고 되살리지 않는다.
--
-- **대상은 선택된 액션이다.** 창이 자기 대상을 따로 들고 있지 않으므로 왼쪽 목록의 강조가
-- 곧 "지금 무엇을 고치고 있나"이고, 다른 행을 고르면 그 액션의 본문이 올라온다(떠나는
-- 쪽은 저장된다). 탭이던 시절의 규칙 그대로다.
--
-- 편집 대상(macroAction)은 **창이 열려 있는 동안만** 산다. OnHide가 저장하고 비운다.
--------------------------------------------------------------------------------

DebounceMacroFrameMixin = {};

function DebounceMacroFrameMixin:OnLoad()
	-- 편집칸은 보이는 만큼만 크고, 넘치는 본문은 스크롤로 간다(기본 매크로 창도 편집칸과
	-- 스크롤 영역이 같은 크기다). 창 크기를 XML에 박아두더라도 여기서 한 번 맞춰야
	-- ScrollFrame의 실제 크기를 따라간다.
	local editor = self.Editor;
	editor.ScrollFrame.EditBox:SetMaxLetters(MACRO_CHAR_LIMIT);
	editor.ScrollFrame:SetScript("OnSizeChanged", function(scrollFrame, width, height)
		scrollFrame.EditBox:SetSize(width, height);
	end);

	-- 버튼 글자는 우클릭 메뉴의 것과 같은 것을 쓴다. 같은 동작이 두 자리에 있으므로 이름도
	-- 같아야 한다.
	self.ConvertPrompt.ConvertButton:SetText(LLL["CONVERT_TO_MACRO_TEXT"]);
end

--- 이 액션으로 창을 연다.
---
--- 창은 선택된 액션만 그리므로 **편집 대상을 선택으로 옮긴다.** 진입점(CTRL-우클릭,
--- 우클릭 메뉴, 매크로텍스트 변환)이 선택과 무관한 행을 가리킬 수 있기 때문이다.
---
--- 매크로텍스트가 아닌 액션으로도 열린다 - 그때는 편집기 자리에 "여기로 바꿀 수 있다"가
--- 대신 들어선다. 열리는 길이 셋인데 그중 하나(변환)가 바로 그 상태에서 시작한다.
---
--- cancelFunc는 매크로텍스트 변환이 [취소]에서 원래 액션으로 되돌리는 데 쓴다. 본문을
--- 올리면서 지워지므로(앞 편집의 것이다) 그 뒤에 건다.
function DebounceMacroFrameMixin:Open(action, cancelFunc)
	if (not action) then
		return false;
	end
	DebounceFrame:SetSelectedAction(action);

	self:Show();
	self:Refresh();
	self.macroCancelFunc = cancelFunc;

	DebounceFrame:Update();
	return true;
end

--- 창을 닫는다. 저장은 OnHide가 한다 - 닫는 길이 여럿이라(X 버튼, `TryCloseAnyDialog`,
--- 메인 창이 닫히면서 딸려 감) 한 군데로 모아야 한 번도 안 새어 나간다.
---
--- 언제나 true다. 이 창은 아무것도 막지 않는다.
function DebounceMacroFrameMixin:Close()
	if (self:IsShown()) then
		self:Hide();
	end
	return true;
end

function DebounceMacroFrameMixin:OnHide()
	self:Save();
	self:ClearEdit();
	DebounceFrame:Update();
end

--- 본문을 편집칸에 올린다. **대상이 바뀔 때만** 부른다 - Refresh는 자주 도는데 거기서
--- 매번 넣으면 타이핑이 지워진다.
---
--- `macroOriginalText`는 여기서만 정해진다. [취소]가 돌아갈 자리이므로 편집이 사는 동안
--- (= 이 액션이 선택돼 있는 동안) 움직이지 않는다.
function DebounceMacroFrameMixin:LoadText(action)
	self.macroAction = action;
	self.macroCancelFunc = nil;
	self.macroOriginalText = action.value or "";
	self.Editor.ScrollFrame.EditBox:SetText(self.macroOriginalText);
end

--- 편집 상태만 비운다. 화면 갱신은 부르는 쪽이 한다.
function DebounceMacroFrameMixin:ClearEdit()
	self.macroAction = nil;
	self.macroCancelFunc = nil;
	self.macroOriginalText = nil;
end

--- 실제로 바뀌었을 때만 쓴다. 기본 매크로 창의 textChanged 검사와 같은 뜻이다.
---
--- 견주는 것은 **액션에 들어 있는 값**이지 `macroOriginalText`가 아니다. 저 둘은 편집이
--- 시작된 직후에만 같고, 그 뒤로는 뜻이 갈린다 - 하나는 "지금 저장된 것", 하나는
--- "[취소]가 돌아갈 자리"다. 여기서 `macroOriginalText`를 덮으면 대상을 한 번 바꿔 갔다
--- 오는 것만으로 돌아갈 자리가 사라진다(떠날 때마다 자동 저장이 돌기 때문이다).
function DebounceMacroFrameMixin:Save()
	local action = self.macroAction;
	if (not action) then
		return;
	end

	local text = self.Editor.ScrollFrame.EditBox:GetText();
	if (text == (action.value or "")) then
		return;
	end

	action.value = text;
	action._dirty = true;
	DebouncePrivate.UpdateBindings();
end

--- [취소] = **이 액션을 연 뒤로** 고친 것을 버린다. 창은 닫지 않는다.
---
--- 되돌릴 곳은 **두 군데**다. 편집칸과 액션 - 대상을 바꿀 때마다 자동 저장이 돌기 때문에
--- 버려야 할 본문이 이미 `action.value`에 들어가 있을 수 있다. 편집칸만 되돌리면 [취소]가
--- 아무 일도 안 한 것처럼 보이고, 원래 본문은 되찾을 길이 없어진다.
---
--- 매크로텍스트 변환으로 들어왔다면 되돌릴 것이 본문이 아니라 **액션 자체**다(cancelFunc).
--- 되돌린 액션은 더 이상 매크로텍스트가 아니므로 편집기 자리에 "변환할까?" 안내가 대신
--- 들어선다. 창은 그대로 둔다 - 되돌린 결과를 볼 자리가 여기이기 때문이다.
function DebounceMacroFrameMixin:Cancel_OnClick()
	local action = self.macroAction;
	if (not action) then
		return;
	end
	PlaySound(SOUNDKIT.GS_TITLE_OPTION_OK);

	local cancelFunc = self.macroCancelFunc;
	if (cancelFunc) then
		-- 먼저 비운다. 안 그러면 되돌린 액션 위에 방금 버린 본문이 다시 저장된다.
		self:ClearEdit();
		cancelFunc();
	else
		local original = self.macroOriginalText or "";
		self.Editor.ScrollFrame.EditBox:SetText(original);
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
--- 이 창은 **열어둔 채로** 팝업이 그 위에 뜬다. 그래서 돌아왔을 때 본문이 그대로 있고,
--- 예전에 본문을 들고 다니던 tempText 곡예가 통째로 필요 없어졌다.
function DebounceMacroFrameMixin:EditNameIcon_OnClick()
	local action = self.macroAction;
	if (not action) then
		return;
	end
	self:Save();

	-- 확인을 눌러도 갈 데가 없다. 이 창이 팝업 아래에 그대로 열려 있고, 새 이름·아이콘은
	-- 팝업이 닫히면서 도는 Update가 되비춘다.
	DebounceIconSelectorFrame:OpenForAction(action);
end

function DebounceMacroFrameMixin:Text_OnTextChanged(editBox)
	ScrollingEdit_OnTextChanged(editBox, editBox:GetParent());
	self.Editor.CharLimitText:SetFormattedText(
		LLL["MACROFRAME_CHAR_LIMIT"], editBox:GetNumLetters(), MACRO_CHAR_LIMIT);
end

--- 매크로텍스트로 바꾼다. 우클릭 메뉴의 [매크로 텍스트로 전환]과 **같은 동작**이다
--- (DropDownMenus.lua의 CreateConvertToMacroTextMenuItem). 같은 일이 두 자리에 있으므로
--- 되돌리는 방법도 같다 - 바꾸기 전 액션을 통째로 떠서 [취소]에 매단다.
function DebounceMacroFrameMixin:Convert_OnClick()
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
	self:Open(action, function()
		wipe(action);
		MergeTable(action, original);
		action._dirty = true;
		DebouncePrivate.UpdateBindings();
	end);

	DebounceFrame:Refresh(true);
	DebounceFrame:Update();
end

--- 창을 되비춘다. 이름·아이콘은 매번, 본문은 대상이 바뀌었을 때만.
--- 아이콘 선택기를 다녀오면 여기서 새 이름·아이콘이 반영된다.
---
--- 선택이 없어지면 닫는다. 대상이 없는 편집기는 보여줄 것도 저장할 것도 없다.
function DebounceMacroFrameMixin:Refresh()
	if (not self:IsShown()) then
		return;
	end

	local action = _selectedAction;
	if (not action) then
		self:Close();
		return;
	end

	local isMacroText = action.type == Constants.MACROTEXT;
	self.Editor:SetShown(isMacroText);
	self.ConvertPrompt:SetShown(not isMacroText);

	if (not isMacroText) then
		-- 편집기가 아니므로 들고 있을 본문도 없다. 앞의 것이 남아 있으면 떠나는 것이니
		-- 저장부터.
		self:Save();
		self:ClearEdit();

		local canConvert = DebouncePrivate.CanConvertToMacroText(action);
		self.ConvertPrompt.Message:SetText(
			LLL[canConvert and "MACRO_TAB_CONVERT_DESC" or "MACRO_TAB_NOT_CONVERTIBLE"]);
		self.ConvertPrompt.ConvertButton:SetShown(canConvert);
		return;
	end

	if (self.macroAction ~= action) then
		self:Save();
		self:LoadText(action);
	end

	self.Editor.SelectedMacroName:SetText(action.name or "");
	self.Editor.SelectedMacroButton.Icon:SetTexture(action.icon);
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
-- 경고색은 한 군데서 낸다. 드롭다운 메뉴도 같은 주황을 써야 하는데, 사본을 하나 더 두면
-- 한쪽만 바뀐다.
DebounceUI.WARNING_FONT_COLOR = WARNING_FONT_COLOR;
DebounceUI.GetLayerID = GetLayerID;
DebounceUI.GetTabLabel = GetTabLabel;
DebounceUI.GetSideTabaLabel = GetSideTabaLabel;
DebounceUI.GetLayerLabel = GetLayerLabel;
DebounceUI.MoveAction = MoveAction;
DebounceUI.ShowDeleteConfirmationPopup = ShowDeleteConfirmationPopup;
DebounceUI.NameAndIconForAction = NameAndIconForAction;
DebounceUI.ShowInputBox = ShowInputBox
