local _, DebindPrivate     = ...;

local NUM_SPECS              = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));
local Constants              = DebindPrivate.Constants;
local LLL                    = DebindPrivate.L;
local DebindUI             = DebindPrivate.DebindUI;

local MACRO_NAME_CHAR_LIMIT  = 32;
local MACRO_CHAR_LIMIT       = 1000;
-- 폭은 하나다. 두 열(결과 | 통)이 늘 같이 서 있고 접히지 않는다 - 이유는 XML의
-- OverviewPanel 주석에.
-- 4 + 405(결과) + 22(왼쪽 스크롤바) + 405(통) + 31(오른쪽 스크롤바) = 867.
--
-- 스크롤바 자리 둘은 **바 굵기(MinimalScrollBar = 8)가 아니라 그 뒤에 남는 여백**으로
-- 정한다. 16/20이었을 때 바의 오른쪽 끝이 각각 3px, 7px 남기고 벽에 닿아서, 바가 벽에
-- 기대 선 것처럼 보였다. 블리자드의 ClickBindingUI는 같은 바 뒤에 18을 남긴다
-- (프레임 440, 인셋 -31, 바 +5) - 오른쪽은 그 값을 그대로 쓴다. 왼쪽은 벽이 창틀이 아니라
-- 인셋 모서리라 9로 족하다.
--
-- 두 바가 각자 인셋에서 +5에 서는 규칙은 안 건드렸다(XML의 ScrollBar 주석).
--
-- **두 열은 같은 폭이고, 그 값은 다른 탭들의 것이다.** 스위치·가져오기·내보내기 패널은
-- 폭 440에 인셋 4/-31이라 검은 자리가 405로 서고, 오버뷰만 380이던 동안에는 탭을 옮길 때
-- 목록이 눈에 띄게 줄었다 - 같은 창의 같은 자리에 서는 목록들이다. 결과 열을 더 넓게 두던
-- 이유(이름이 한 줄에 서는 표라 폭이 곧 글자 수)는 통이 405로 같이 넓어지면서 없어졌다.
local FRAME_WIDTH            = 867;
local DISABLED_FONT_COLOR    = _G.DISABLED_FONT_COLOR;
local ERROR_COLOR            = _G.ERROR_COLOR;
local INACTIVE_COLOR         = _G.INACTIVE_COLOR;

local dump                   = DebindPrivate.dump;
local GetBindingIssue        = DebindPrivate.GetBindingIssue;
local IsIssueMinor           = DebindPrivate.IsIssueMinor;
local GetSpellTabNameAndIcon = DebindPrivate.GetSpellTabNameAndIcon;

-- Three files above this one, taken once each. `ActionDisplay.lua` owns what an action is called and
-- the blue an imported one wears, `LayerDisplay.lua` owns what a layer is called and the icon beside
-- it, and `ActionTooltip.lua` owns the block that goes up on hover. All three load before this file
-- and none of them knows the window exists.
local IMPORTED_FONT_COLOR            = DebindUI.IMPORTED_FONT_COLOR;
local UNIT_INFO                      = DebindUI.UNIT_INFO;
local NameAndIconForAction           = DebindUI.NameAndIconForAction;
local ColoredNameAndIconForAction    = DebindUI.ColoredNameAndIconForAction;
local SetActionIcon                  = DebindUI.SetActionIcon;

local GetLayerTabs                   = DebindUI.GetLayerTabs;
local GetTabLabel                    = DebindUI.GetTabLabel;
local GetSideTabaLabel               = DebindUI.GetSideTabaLabel;
local GetLayerShortName              = DebindUI.GetLayerShortName;
local GetLayerLabel                  = DebindUI.GetLayerLabel;
local IsLayerOffWorld                = DebindUI.IsLayerOffWorld;
local GetSideTabIcon                 = DebindUI.GetSideTabIcon;

local AddActionToTooltip             = DebindPrivate.AddActionToTooltip;
local HideActionTooltip              = DebindPrivate.HideActionTooltip;

local _selectedTab           = 1;
local _selectedSideTab       = 1;
-- The window's tab (Overview/Import/Export). A different rank from the two above: those are
-- "which layer is Overview looking at, inside itself", this is "what is the window showing at
-- all". Like them it lives for the session only and is not saved - close and reopen and you are
-- on the tab you left.
local _selectedPanel         = 1;
-- 이 창의 행은 끌 수 없다. 목록 안 재배치도(Phase 3), 탭에 떨궈 레이어를 옮기는 것도
-- 없앴다 - 후자는 우클릭 `Move to`가 더 잘 하고, 드래그는 행을 집게 해놓고 목록은 안
-- 받으니 매번 창을 덮어 "여기 아니다"라고 말해야 했다.
--
-- 남은 것은 하나, **게임이 커서에 집어준 것**을 받는 길이다. 주문책·액션바·가방에서 끌어온
-- 것을 목록이나 탭에 떨구면 그 레이어 맨 뒤에 붙는다. 아이템처럼 스펠 선택 창에 없는
-- 타입은 이 길로만 들어온다.
local _pickedupInfo;
-- **앵커.** SHIFT가 범위를 재는 기준점이고, 동시에 왼쪽 열이 짚는 행(`isCurrent`)이자 순서
-- ↑↓가 붙는 행이자 매크로 창이 여는 액션이다.
--
-- **둘을 한 변수로 둔 이유는 앵커가 화면에 보여야 하기 때문이다.** 기준점이 아무 데도 안
-- 그려져 있으면 SHIFT-클릭 결과를 눌러보기 전에는 알 수 없다. 합쳐두면 왼쪽 열이 짚고 있는
-- 그 행이 곧 기준점이라, 따로 그릴 것이 없다.
--
-- 옮기는 것은 **SHIFT 없는 좌클릭**이다(CTRL은 옮긴다 - 집합에서 빼는 경우까지). SHIFT가
-- 안 옮기는 덕에 범위를 다시 잴 수 있다: 2를 누르고 SHIFT로 8을 찍은 뒤 5를 찍으면 2-5가
-- 된다. SHIFT도 옮기게 두면 저 마지막 클릭이 5-8이 되어 범위를 줄일 길이 없어진다.
--
-- elementData가 아니라 action 테이블을 들고 있는 이유는 elementData가 Refresh마다 새로
-- 만들어지기 때문이다 (DebindLayerPanelMixin:Refresh).
local _selectedAction;

--- **벌크 대상 집합.** 앵커와는 다른 것이다 - 앵커는 "지금 이야기 중인 행" 하나이고, 이쪽은
--- "이동·복사·삭제가 손댈 것들"이다. 오른쪽 목록의 강조와 멀티 메뉴만 이걸 본다.
---
--- 앵커가 이 집합 밖에 있을 수 있다: CTRL-클릭으로 앵커 행 자신을 집합에서 빼면 그렇게 된다.
--- 고치지 않는다 - "선택은 아닌데 지금 보고 있는 것"이 맞는 말이고, 왼쪽 열의 `isCurrent`는
--- 원래 선택이 아니라 이야기 중인 행이라는 뜻이었다.
---
--- 액션 테이블을 키로 든다. elementData를 들면 Refresh 한 번에 집합 전체가 낡는다.
local _selection             = {};
local _selectionCount        = 0;

--- 오른쪽 목록의 검색어. 소문자로, 빈 문자열이면 nil이다(`ClearSearch` / OnTextChanged).
---
--- **왼쪽 열은 안 거른다.** 저기서 행을 빼면 순서 설명이 거짓말이 된다 - 각 행의 글자는
--- "이 행이 **바로 아래 행을** 이긴 이유"이고 그 계산은 키 그룹 전체로 하므로(`BuildKeyboardElements`),
--- 몇 줄을 걷어내면 남은 문장이 화면에 없는 행을 가리킨다. 왼쪽은 이미 선택으로 답한다 -
--- 오른쪽에서 찾은 행을 누르면 저쪽이 그 행을 짚고 그리로 스크롤한다.
local _searchText;

--- 오버뷰에서 접혀 있는 키 그룹. 키 자체로 물으며, 키가 없는 맨 아래 덩어리는 `KEYLESS_GROUP`이
--- 대신 선다 - nil은 테이블 키가 못 되고, 고유 테이블이면 진짜 키와 부딪힐 길이 없다.
---
--- **A file local for the same reason `_searchText` is one**, and 보기 상태일 뿐이라 저장하지
--- 않는다 - 접힌 그룹도 그대로 발동한다. 목록을 다시 그리는 것 말고는 아무것도 안 건드린다.
local KEYLESS_GROUP = {};
local _collapsedKeys = {};

--- 액션의 그룹을 `_collapsedKeys`가 쓰는 이름으로 바꾼다. 키가 없다는 것도 그룹 하나이고,
--- nil은 테이블 키가 못 되므로 고유 테이블이 그 자리에 선다.
---
--- **`arrivalID`까지 넣는다.** 한 키 위에 내 세트와 도착분이 나란히 서고 머리글도 둘이라, 키만
--- 이름으로 삼으면 한쪽을 접었을 때 다른 쪽까지 같이 접힌다.
local function CollapseKeyFor(key, arrivalID)
	if (key == nil) then
		return KEYLESS_GROUP;
	end
	return key .. "/" .. tostring(arrivalID);
end

--- 왼쪽 열의 필터. **값별 포함 체크박스**라 켜진 값만 통과한다 - 블리자드 수집품 창의
--- 「수집됨 / 수집 안 됨」과 같은 모양이고, 한 축을 다 끄면 막지 않고 0개를 낸다. 아무 값도 안
--- 받겠다고 한 것이므로 그게 정직한 답이다.
---
--- 축이 둘이고 값은 서로 겹치지 않는다:
---   특성 - 활성 / 비활성
---   키   - 있음(진짜 키) / 없음(수락은 했는데 키를 안 줌) / Pending(아직 수락도 안 함)
---
--- **키 축의 셋이 겹칠 수 있다.** 배지 달린 것도 실키를 들고 있어서(`devdocs/building-export-import.md`
--- 12절) Pending과 「단축키 있음」이 같은 액션을 가리킬 수 있다. 축마다 따로 묻고 통과하면
--- 남기는 것이 그래서 맞다 - 한 축이 다른 축을 대신 답하게 만들면, 도착분을 보려고 Pending만
--- 켠 사람이 키 축에서 그것을 다시 잃는다.
---
--- **저장하지 않는다.** 걸려 있다는 사실은 드롭다운의 리셋 버튼이 말한다(`UIResetButtonTemplate`은
--- 기본값이 아닐 때만 뜬다).
local _filters = {
	activeSpec   = true,
	inactiveSpec = true,
	keyed        = true,
	unkeyed      = true,
	pending      = true,
};

--- The row the left column has been asked to put on screen the next time it is built. Four places
--- set it and `RefreshKeyboard` spends it. **The group it is in is unfolded** as part of that - a
--- folded group draws no rows at all, so there would be nothing to scroll to.
---
--- **Drawing and showing are two jobs.** Every rebuild used to scroll to the selected row, and with
--- that the group holding the selection could not be folded - the fold click asks for a rebuild and
--- the rebuild drags the row back. So it is only set at a moment that means "show me".
---
--- **A row, even where a whole set moved.** A second request that took a key and put the heading on
--- screen was built and taken back out: the column marks one thing at a time and that mark lives on
--- rows (`isCurrent`), so a heading scrolled to is a heading the reader still has to pick out of the
--- others. Revealing the set's first row instead brings the heading along anyway - `RevealRow` is
--- built to - and the highlight under it says which one. The alternative was a second selection
--- state on a window whose selection already means something else (what the panel on the right
--- draws, what a bulk operation acts on), with no answer for when it would clear.
local _revealAction;

DebindUI.ActionMenuRootTag = "DEBIND_ACTION_ROOT";

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

--- Handed out because the key capture dialog is the second place an arriving input has to become a
--- chord (`KeyCapture.lua`). What makes it one function and not two is the *state* half: which
--- modifiers count is read from the keyboard at the instant the input lands, so a second copy would
--- be a second answer to "what was held down", and the two would drift the first time left and right
--- modifiers are treated differently on one side only.
DebindPrivate.CreateKeyChordStringUsingMetaKeyState = _CreateKeyChordStringUsingMetaKeyState;

local function GetLayerID(tab, sideTab)
	tab = tab or _selectedTab;
	sideTab = sideTab or _selectedSideTab;
	local isCharacterSpecific = tab == 2;
	local spec = sideTab >= 2 and sideTab - 2 or nil;
	return DebindPrivate.GetLayerID(spec, isCharacterSpecific);
end

--- 사이드탭 툴팁의 설명 줄. **탭과 사이드탭을 같이 받는다** - 사이드탭 혼자서는 문장이 안
--- 나온다. "일반"은 탭1에서 계정 전체이고 탭2에서는 이 캐릭터 하나인데, 사이드탭 아이콘은
--- 두 경우에 똑같이 생겼다.
---
--- 문장은 세 마디다: **누가 쓰는가**, **무엇보다 우선하는가**, 그리고 **언제 그 말이 안
--- 맞는가.** 셋째가 없으면 앞의 둘이 거짓말이 된다 - 레이어는 실행 순서의 네 번째 축이라
--- (`PRIORITY_DESC`: 중요도 → 마우스 올림 → 조건 → 탭 → 순서), 조건이 붙은 공유/일반 액션이
--- 조건 없는 공유/야성 액션보다 먼저 실행된다. 중요도를 건드렸으면 더 그렇다.
---
--- 그 절이 왜 조건과 중요도만 세는지, 왜 이 길이를 받아들이는지는 로케일 쪽 주석에 있다
--- (enUS의 `LAYER_DESC_*` 위).
---
--- 지는 쪽은 **`GetLayerLabel`로 부른다** - 낱말 하나가 아니라 "공유 / 드루이드" 꼴이다.
--- 툴팁 제목이 그 형식이라 참조도 같아야 화면에서 찾을 수 있다. 한때 "직업보다 우선"이라고
--- 적었는데, `LAYER_SHORT_CLASS`("직업"/"Class")는 **어느 탭에도 안 적혀 있는 이름**이다 -
--- 그 탭의 제목은 "공유 / 드루이드"다. 영어에서는 "Beats Druid."가 "드루이드를 이긴다"로도
--- 읽혀서 더 나빴다. 그래서 이 함수가 `GetLayerLabel`을 부르지, 짧은 이름을 안 쓴다.
---
--- 탭2에는 사이드탭2(직업)가 없다 - UpdateSideTabs가 숨긴다 - 그래서 그 조합은 안 적는다.
local function GetSideTabDescription(sideTabID, tabID)
	tabID = tabID or _selectedTab;
	if (tabID == 2) then
		if (sideTabID == 1) then
			return LLL["LAYER_DESC_CHARACTER_GENERAL"];
		end
		-- **The losing layer is not passed.** This is the narrowest of the five, so it beats
		-- every other one rather than the one below it, and the line says "everywhere else"
		-- instead of naming any. English then takes no argument at all -- the tooltip title
		-- already reads "Oreo / Balance" -- while Korean still needs the spec name, so the one
		-- value goes out and each locale uses it or does not.
		return format(LLL["LAYER_DESC_CHARACTER_SPEC"], GetSideTabaLabel(sideTabID));
	end
	if (sideTabID == 1) then
		return LLL["LAYER_DESC_SHARED_GENERAL"];
	end
	if (sideTabID == 2) then
		return format(LLL["LAYER_DESC_SHARED_CLASS"],
			GetSideTabaLabel(2), GetLayerLabel(GetLayerID(1, 1)));
	end
	return format(LLL["LAYER_DESC_SHARED_SPEC"],
		GetSideTabaLabel(2), GetSideTabaLabel(sideTabID), GetLayerLabel(GetLayerID(1, 2)));
end

local function TryCloseAnyDialog()
	if (DebindIconSelectorFrame:Close() and DebindMacroFrame:Close() and DebindResultPanel:Close()) then
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
--- **주문 선택 창도 여기 없다.** 일부러다 - 그 창의 클릭은 메인 창에서 열려 있는 레이어에
--- 넣는다. 여기 넣으면 탭이 잠겨서 대상을 바꿀 방법이 사라진다. (우클릭 메뉴가 탭을 지목하는
--- 길을 하나 더 냈지만, 그건 클릭 한 번에 넣는 길을 대신하지 못한다.)
local function IsEditingAction(action)
	if (DebindIconSelectorFrame:IsShown() and (action == nil or DebindIconSelectorFrame.editAction == action)) then
		return true;
	end
	return false;
end

-- 열린 메뉴의 대상은 elementData가 아니라 action으로 기억한다. 메뉴가 떠 있는 동안 Refresh가
-- 돌면 elementData는 새로 만들어지고, 그걸 붙들고 있으면 대상을 놓친다.
local function IsEditDropdownShown(elementData)
	if (DebindFrame.contextMenu) then
		if (elementData == nil or DebindFrame.contextMenuAction == elementData.action) then
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

	return DebindLayerPanel:FindElementDataByActionInfo(action);
end

local function GetActionTypeAndValueFromCursorInfo()
	local type, value;
	local cursorType, cursorInfo1, _, cursorInfo3 = GetCursorInfo();

	if (cursorType) then
		if (cursorType == "spell") then
			type, value = Constants.SPELL, cursorInfo3;
		elseif (cursorType == "macro") then
			-- **The cursor carries a slot number, and an action may only carry a name**
			-- (`GetMissingMacroName`). A number is a position in a name-ordered list, so
			-- storing it binds whatever later comes to sit in that slot, with nothing going
			-- red because nothing broke.
			--
			-- No name, no action. That means the macro was deleted between the pickup and
			-- the drop, and refusing the drop beats building a `MACRO` with no name in it.
			---@diagnostic disable-next-line: param-type-mismatch
			local macroName = GetMacroInfo(cursorInfo1);
			if (macroName) then
				type, value = Constants.MACRO, macroName;
			end
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

--- 아래에서 정의된다. **오른쪽 목록과 탭 숫자가 왼쪽 열의 판정을 그대로 쓴다** - 두 열이
--- "무엇이 있는가"에 다른 답을 내면 안 되고, 그러려면 판정이 한 군데여야 한다. 그 한 군데가
--- 저 함수들이라 여기서는 이름만 세워둔다.
local BuildKeyboardElements, CollectVisibleActions;

--- 이 액션 하나가 필터를 통과하나. **두 축을 모두** 통과해야 한다(`_filters`).
---
--- `specRank`는 0이면 지금 도는 세계의 것이다 - 활성 특성과 특성 없는 레이어가 여기 든다.
--- 값을 내는 곳은 `EnumerateAllProfileLayers`고, 부르는 쪽이 이미 손에 들고 있다.
---
--- 키 축은 셋 중 하나로만 떨어진다. 배지를 먼저 보는 것이 순서인데, 배지가 붙은 것은 언제나
--- 합성 번호 위에 있어서(`_filters` 주석) 아래 두 갈래와 다툴 일이 없기 때문이다.
local function ActionPassesFilters(action, specRank)
	if ((specRank or 0) == 0) then
		if (not _filters.activeSpec) then
			return false;
		end
	elseif (not _filters.inactiveSpec) then
		return false;
	end

	if (action.arrivalID ~= nil) then
		return _filters.pending == true;
	end
	if (type(action.key) == "string") then
		return _filters.keyed == true;
	end
	return _filters.unkeyed == true;
end

--- 검색어가 이 이름에 걸리나. 검색어가 없으면 전부 걸린다.
---
--- **색코드를 씌우기 전 이름으로 맞춘다.** 화면에 그려지는 문자열은 `|cff...|r`로 감싸이는
--- 경우가 있어서(`ColoredNameAndIconForAction`), 그걸로 맞추면 사용자가 안 친 여덟 글자가
--- 검색 대상에 들어간다.
local function NameMatchesSearch(name)
	if (_searchText == nil) then
		return true;
	end
	return strfind(strlower(name or ""), _searchText, 1, true) ~= nil;
end

--- 지금 무엇이든 좁혀져 있나. 값 하나라도 꺼져 있거나 검색어가 있으면 참이다.
---
--- 탭 숫자의 색이 이 답을 쓴다. 좁혀져 있을 때만 초록/회색으로 갈라서 "찾는 게 여기 있다"를
--- 말하고, 안 좁혀져 있으면 전부 흰색이다 - 늘 색이 갈리면 그 의미가 사라진다.
local function IsNarrowed()
	if (_searchText ~= nil) then
		return true;
	end
	for _, on in pairs(_filters) do
		if (not on) then
			return true;
		end
	end
	return false;
end

--- The actions the left column stands while something is narrowing, or nil.
---
--- **nil is "all of them".** With nothing ticked off and no search text there is no reason to walk
--- the whole profile to build a set, and the callers read that value as "nothing to filter by".
---
--- **One update builds this once, and hands it down.** It is expensive: `BuildKeyboardElements`
--- walks every layer, and every key group it finds is a `CollectActionsForKey` that rebuilds a
--- binding per row. So the three that filter by it (`PruneSelectionToBinFilter`, `Refresh`,
--- `UpdateActionCounts`) take it as an argument, and each of them defaults to calling this only for
--- the callers that pass nothing. The lifetime is the call stack, so there is no rule about when it
--- goes stale. The default costs nothing in the case it mostly runs in: not narrowed, where this
--- returns nil without building.
---
--- **`RefreshKeyboard` is not one of the three and keeps its own build.** What it wants is the
--- element list rather than the set, and it has to run after `_revealAction` has unfolded a group,
--- which is after the update handed this out.
local function NarrowedVisibleActions()
	if (not IsNarrowed()) then
		return nil;
	end
	return CollectVisibleActions();
end

--- 이 레이어에서 **지금 셀 만한** 액션이 몇인가. 탭과 사이드탭의 숫자가 이걸 쓴다.
---
--- **왼쪽 열에 실제로 서는 것만 센다.** 숫자와 목록이 갈리면 "(3)"이라고 쓰인 탭이 두 줄로
--- 열린다. 필터가 그룹 단위로 판정되므로 액션 하나씩 다시 재면 반드시 갈린다 - 그룹이 통째로
--- 살아남은 자리에서 저쪽은 매치된 하나만 셀 것이기 때문이다.
---
--- 아무것도 안 걸려 있으면 레이어에 그냥 물어본다. 걸을 것이 없는데 훑을 이유가 없다.
local function CountActionsInLayer(layer, visible)
	if (visible == nil) then
		return layer:GetNumActions();
	end

	local count = 0;
	for _, action in layer:Enumerate() do
		if (visible[action]) then
			count = count + 1;
		end
	end
	return count;
end



local function DeleteElementData(elementData)
	-- 선택기가 들고 있는 건 elementData다. .action이라는 필드는 아무도 넣어주지 않아서
	-- 늘 nil이었고, 그래서 이 가드는 한 번도 걸린 적이 없다 - 지우는 액션을 편집기가
	-- 열어둔 채였다면 그 위에 이름·아이콘을 써 넣는다. 지워진 테이블에.
	if (IsEditingAction(elementData.action)) then
		DebindIconSelectorFrame:Close(true);
	end

	if (_selectedAction == elementData.action) then
		DebindLayerPanel:SetSelectedAction(nil);
	end

	local layer = DebindPrivate.GetProfileLayer(elementData.layer);
	local key, arrivalID = elementData.action.key, elementData.action.arrivalID;
	layer:Remove(elementData.action);
	layer:RenumberKeyGroup(key, arrivalID);
	DebindPrivate.UpdateBindings();

	-- 목록을 프로필에서 다시 만든다. 예전에는 provider에서 그 행만 빼고 index를 다시 매겼는데,
	-- 그러면 한 키의 마지막 행을 지웠을 때 그룹 헤더가 홀로 남는다. 게다가 그 index는 배열
	-- 위치가 아니라 **표시 순서**라서 정렬이 쓰는 order.index와 뜻이 달랐다. 다시 만드는 쪽이
	-- 액션을 추가하거나 옮길 때 이미 하는 일이기도 하다.
	DebindLayerPanel:Refresh(true);
end

--- Deletes every one of them, wherever it lives.
---
--- **It does not go through the list.** It used to look each action up with
--- `FindElementDataByActionInfo` and skip it when that came back nil, which quietly meant "only
--- what is drawn right now": that provider holds one layer - the open tab - and only the rows the
--- search and [Only what came in] left in it. Given the badges of a whole import, which routinely
--- span layers, it deleted the handful on screen and reported nothing about the rest.
---
--- The layer is asked for per action instead (`FindLayerID`), which is the same question the row
--- was answering and one that no filter can change the answer to.
---
--- **One rebuild at the end, not one per action.** Deleting through `DeleteElementData` ran
--- `UpdateBindings` and a full `Refresh` for every row; a couple of hundred of those is a freeze,
--- and the intermediate lists were never looked at.
local function DeleteActions(actions)
	local removed = false;
	-- The (layer, key) each deleted action was in. Renumbering has to happen after the removal and
	-- an action that is gone cannot be asked for its layer any more, so they are collected on the
	-- way through. One call can empty several keys across several layers.
	local touched = {};
	for _, action in ipairs(actions) do
		if (IsEditingAction(action)) then
			DebindIconSelectorFrame:Close(true);
		end
		if (_selectedAction == action) then
			DebindLayerPanel:SetSelectedAction(nil);
		end
		local _, layer = DebindPrivate.FindLayerID(action);
		if (layer and layer:Remove(action)) then
			removed = true;
			if (action.key ~= nil) then
				local groups = touched[layer];
				if (groups == nil) then
					groups = {};
					touched[layer] = groups;
				end
				groups[action.key .. "/" .. tostring(action.arrivalID)] =
					{ key = action.key, arrivalID = action.arrivalID };
			end
		end
	end

	for layer, groups in pairs(touched) do
		for _, group in pairs(groups) do
			layer:RenumberKeyGroup(group.key, group.arrivalID);
		end
	end

	if (removed) then
		DebindPrivate.UpdateBindings();
		DebindLayerPanel:Refresh(true);
	end

	-- 앵커가 지워진 것 중에 있었으면 선택을 풀어야 하고, 밖에 있었으면 집합에 죽은 테이블이
	-- 남으므로 여기서 접는다. 둘 다 이 한 줄이 처리한다.
	DebindLayerPanel:SetSelectedAction(DebindFrame:GetSelectedAction());
end

local ShowDeleteConfirmationPopup, ShowBulkDeleteConfirmationPopup, HideDeleteConfirmationPopup;
local ShowRemoveDuplicatesConfirmationPopup;
local ShowRejectImportConfirmationPopup;
do
	local _deletePopupData;

	--- 벌크 삭제의 확인. **이름 대신 개수로 묻는다** - 열몇 개를 나열하면 팝업이 화면을 덮고,
	--- 그렇다고 몇 개만 적으면 나머지를 숨긴 채로 묻는 꼴이 된다.
	---
	--- 확인을 건너뛰지 않는 이유는 되돌리기가 없기 때문이다. 이동·복사는 확인 없이 즉시인데
	--- (되돌릴 수 있거나 파괴적이지 않다) 이것만 다르다.
	function ShowBulkDeleteConfirmationPopup(actions)
		HideDeleteConfirmationPopup();

		_deletePopupData = {
			text = LLL["DELETE_CONFIRM_MESSAGE_MULTIPLE"],
			text_arg1 = #actions,
			callback = function()
				DeleteActions(actions);
			end,
			acceptText = YES,
			cancelText = NO,
			showAlert = true,
			referenceKey = "DebindDeleteConfirmation",
		};

		StaticPopup_ShowCustomGenericConfirmation(_deletePopupData);
		DebindFrame:UpdateButtons();
	end

	--- Rejecting what came in, one or all of it.
	---
	--- **A separate popup from the delete above, because the sentence is what makes it pressable.**
	--- Deleting your own action is final; this is not, and saying so is the whole difference: the
	--- string these came from is still in the drawer, so the way back is to bring it in again. The
	--- reader cannot know that from the button, and without it this reads as the destructive half
	--- of the pair when it is in fact the reversible one - accepting is what cannot be undone.
	---
	--- Counts rather than names, for the reason the bulk popup above counts.
	function ShowRejectImportConfirmationPopup(actions)
		HideDeleteConfirmationPopup();

		_deletePopupData = {
			text = LLL["REJECT_IMPORT_CONFIRM"],
			text_arg1 = #actions,
			callback = function()
				DeleteActions(actions);
				-- **The narrowing is not touched.** [Pending] is a tick in the filter dropdown now,
				-- and a tick does not clear itself: with the last badge gone the lists draw empty,
				-- which is what was asked for, and the dropdown's reset button is standing there
				-- saying so. Three paths used to drop it here for the reader.
			end,
			acceptText = YES,
			cancelText = NO,
			showAlert = true,
			referenceKey = "DebindDeleteConfirmation",
		};

		StaticPopup_ShowCustomGenericConfirmation(_deletePopupData);
		DebindFrame:UpdateButtons();
	end

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
			referenceKey = "DebindDeleteConfirmation",
		};

		StaticPopup_ShowCustomGenericConfirmation(_deletePopupData);
		DebindFrame:UpdateButtons();
	end

	function HideDeleteConfirmationPopup()
		if (_deletePopupData) then
			StaticPopup_Hide("GENERIC_CONFIRMATION", _deletePopupData);
			_deletePopupData = nil;
		end
	end

	--- Removing the duplicates the sweep found. **Its own popup rather than the bulk delete's**,
	--- because the sentence is the difference: the bulk one asks about rows the reader picked and
	--- can see, and this one asks about rows they have not looked at, in layers that may not be on
	--- screen. What makes it pressable is that nothing is lost -- every one of these has a twin
	--- staying behind -- and only its own wording can say that.
	function ShowRemoveDuplicatesConfirmationPopup(actions)
		HideDeleteConfirmationPopup();

		_deletePopupData = {
			text = LLL["REMOVE_DUPLICATES_CONFIRM"],
			text_arg1 = #actions,
			callback = function()
				DeleteActions(actions);
			end,
			acceptText = YES,
			cancelText = NO,
			showAlert = true,
			referenceKey = "DebindDeleteConfirmation",
		};

		StaticPopup_ShowCustomGenericConfirmation(_deletePopupData);
		DebindFrame:UpdateButtons();
	end
end


--- [Remove duplicate actions], from the options menu.
---
--- **The walk happens on the press, not when the menu opens.** Greying the item out would mean
--- sweeping every layer every time somebody opens that menu to change something else, and what it
--- would buy is one press. Pressing it on a clean profile answers in a line.
---
--- **The count is the whole of the question.** A duplicate is by definition indistinguishable from
--- the one that stays -- that is what a matching signature means -- so there is no per-row fact the
--- reader could act on differently, and a list of names would be the same name over and over. That
--- is a different case from the preview's rows, where marking was turned down for showing something
--- uncertain (`devdocs/building-export-import.md` 12절); a count of exact matches is not uncertain.
---
--- It asks because nothing here is undoable, which is the rule the bulk delete beside it keeps.
function DebindUI.RemoveDuplicateActions()
	local duplicates = DebindPrivate.CollectDuplicateActions();
	if (#duplicates == 0) then
		DebindPrivate.DisplayMessage(LLL["REMOVE_DUPLICATES_NONE"]);
		return;
	end
	ShowRemoveDuplicatesConfirmationPopup(duplicates);
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
--- **The box is reached through the dialog's accessor, not by a field name.** `popup.editBox` was
--- the field before the dialog became `GameDialogMixin`, and it has been `EditBox` behind
--- `GetEditBox()` since (`Blizzard_StaticPopup_Game/GameDialog.lua`). Indexing the old name gave
--- nil and errored on the line below, which nothing caught for as long as it did because this
--- branch only runs when a caller passes a value to open on.
---
--- Highlighted after filling, so the first keystroke replaces it. The box opens on the current
--- value to be read *or* typed over, and without this the second of those costs a select-all.
--- `prefix` draws a glyph to the left of the box that is **not part of what is typed**. A switch
--- name always begins with `$` and nothing else may, so the reader types `burst` and the caller
--- joins the two; a sigil that is furniture cannot be deleted, doubled, or left off.
---
--- **The dialog is shared, so the glyph is cleared on every call and again when it hides.** It
--- belongs to no addon in particular: text left on it would sit in front of the next generic
--- input box anybody opens, ours or the client's own. Held beside the box rather than on it --
--- writing a field onto a frame the client recycles is how two addons find out they chose the
--- same name.
local _inputPrefixes = setmetatable({}, { __mode = "k" });

local function InputPrefix(editBox)
	local fontString = _inputPrefixes[editBox];
	if (not fontString) then
		fontString = editBox:GetParent():CreateFontString(nil, "OVERLAY", "GameFontHighlight");
		-- Into the box's own left inset, not against its frame edge: `InputBoxTemplate` starts its
		-- text some way in, so anchoring to the edge leaves a gap the offset cannot see.
		fontString:SetPoint("RIGHT", editBox, "LEFT", 1, 0);
		_inputPrefixes[editBox] = fontString;
		-- Additive, and once per box: the dialog outlives any one use of it.
		editBox:HookScript("OnHide", function()
			fontString:SetText("");
		end);
	end
	return fontString;
end

local function ShowInputBox(data)
	StaticPopup_ShowCustomGenericInputBox(data);

	local popup = StaticPopup_FindVisible("GENERIC_INPUT_BOX", data);
	local editBox = popup and popup:GetEditBox();
	if (not editBox) then
		return;
	end

	InputPrefix(editBox):SetText(data.prefix or "");

	if (data.currentValue) then
		editBox:SetText(data.currentValue);
		editBox:HighlightText();
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
			local fromLayer = DebindPrivate.GetProfileLayer(fromLayerID);
			local fromKey, fromArrival = action.key, action.arrivalID;
			fromLayer:Remove(action);
			fromLayer:RenumberKeyGroup(fromKey, fromArrival);
		end
	end

	local insertIndex;
	if (copying and fromLayerID == destLayerID) then
		insertIndex = elementData.index + 1;
	end

	action = CopyTable(elementData.action);
	local destLayer = DebindPrivate.GetProfileLayer(destLayerID);
	destLayer:Insert(action, insertIndex, not copying);
	-- The ordering number is handed out fresh. A copy is born holding the original's, which would
	-- leave the two tied; one moved from another layer holds a number belonging to that group, which
	-- means nothing here. "The back of this key group" is the answer to both.
	destLayer:PlaceInKeyGroup(action);

	DebindPrivate.UpdateBindings();

	-- 목록은 정렬해서 그리므로 손으로 끼워넣지 않고 다시 만든다.
	DebindLayerPanel:Refresh(true);

	if (fromLayerID == destLayerID) then
		DebindLayerPanel:ScrollActionIntoView(action);
	end
end

--- 고른 것 전부를 옮기거나 복사한다.
---
--- 하나씩 `MoveAction`을 지난다. 그 함수가 레이어에서 빼고 넣고 순서 번호를 다시 주는 규칙을
--- 전부 들고 있어서, 벌크가 자기 몫으로 다시 적으면 같은 규칙이 두 군데 살게 된다.
---
--- **elementData는 액션마다 그때그때 다시 찾는다.** `MoveAction`이 한 번 돌 때마다 `Refresh`가
--- 목록을 새로 지어서, 미리 모아둔 elementData는 둘째부터 낡은 layer/index를 들고 있다.
---
--- 목적지에 이미 사는 것은 건너뛴다(이동일 때). 그 항목은 메뉴에서 회색으로 세워만 두므로
--- (`CreateMoveCopyMenu`) 눌러서 여기 오지는 않지만, 막지 않으면 그런 한 줄이 `MoveAction`의
--- `assert(copying, ...)`에 걸려 **벌크 전체가 중간에 멈춘다** - 앞의 절반만 옮겨진 채로.
---
--- 옮긴 뒤에는 선택을 접는다. `MoveAction`이 액션 테이블을 복사해서 넣으므로(`CopyTable`)
--- 집합이 들고 있던 테이블은 어느 레이어에도 없는 것이 된다. 복사는 원본이 그대로 남으므로
--- 접지 않는다 - 사용자가 고른 것은 원본이고, 사본으로 옮겨주면 방금 무엇을 골랐는지가 틀어진다.
local function MoveActions(actions, destLayerID, copying)
	for _, action in ipairs(actions) do
		local elementData = DebindLayerPanel:FindElementDataByActionInfo(action);
		if (elementData and (copying or elementData.layer ~= destLayerID)) then
			MoveAction(elementData, destLayerID, copying);
		end
	end

	if (not copying) then
		DebindLayerPanel:SetSelectedAction(nil);
	end
end

--- Takes the badge off, which is what lets these actions reach a key.
---
--- **Accepting is a move, not a field edit.** An arrival sits on `(key, arrivalID)` and accepting it
--- lands it on `(key, nil)`, which is a key group the reader may already have things in -- so it
--- goes through `SetKeyForActions`, the one path that carries a set's own order across and stands it
--- behind whatever the destination already held. Clearing the field on each action instead would
--- leave the sender's `seq` interleaved with the reader's and quietly reorder what fires first.
---
--- **What lands on `nil` is not a move.** An arrival that came in on no key has no group to join, so
--- the badge simply comes off and it stays in the unbound pile.
---
--- **`contested` is the reader's answer, and it only ever names keys both sides want.** One of three
--- things, and each is one of the buttons: nil where nothing collided or the reader chose to merge
--- (both sets end up on the key and the order decides), `"mine"` where the arrivals on those keys
--- step aside, `"theirs"` where the reader's own actions on those keys lose them. Keys outside it
--- are untouched by the answer: an arrival on a free key lands on it whichever button was pressed.
---
--- **`occupants` is only read for `"theirs"`**, and the caller gathers it from the same walk that
--- decided there was a question to ask -- so the set the prompt counted is the set that moves.
---
--- **The narrowing is left alone.** [Pending] is a tick in the filter dropdown now, and a tick is
--- the reader's to clear. Accepting the lot while it is the only value ticked on the key axis ends
--- on an empty list, which is exactly what that state asks for; the dropdown's reset button is on
--- screen the whole time.
local function ApproveArrivedActions(actions, occupants, contested, answer)
	if (answer == "theirs" and occupants) then
		DebindPrivate.ClearKeyForActions(occupants);
	end

	-- Grouped, because `SetKeyForActions` takes a set and the order inside it is the thing being
	-- carried. **`(key, arrivalID)`**, so two arrivals that came in on one key do not become one
	-- ranking on the way through.
	local groups, order = {}, {};
	for _, action in ipairs(actions) do
		-- **Keeping mine means this one arrives with no key**, not that it does not arrive: the
		-- reader pressed accept, so the badge comes off either way and what steps aside is the key.
		-- It lands in the unbound pile, which is the state a badge used to leave everything in and
		-- the reason this answer exists at all.
		if (answer == "mine" and action.key ~= nil and contested and contested[action.key]) then
			action.key = nil;
			action.seq = nil;
			action.arrivalID = nil;
		elseif (action.key == nil) then
			action.arrivalID = nil;
		else
			local groupID = action.key .. "/" .. tostring(action.arrivalID);
			local group = groups[groupID];
			if (group == nil) then
				group = { key = action.key };
				groups[groupID] = group;
				order[#order + 1] = groupID;
			end
			group[#group + 1] = action;
		end
	end
	for i = 1, #order do
		local group = groups[order[i]];
		DebindPrivate.SetKeyForActions(group, group.key);
	end

	-- **What just left the list leaves the selection with it.** `arrivalID` is one of the fields the
	-- filters read, so accepting rows while [Pending] is the only key value ticked drops them off
	-- screen while the strip still counts them - "2 selected" over a list with nothing highlighted,
	-- and the search box stays hidden because the two share that slot. Every other path that
	-- changes what the filters show prunes first, and this was the one that did not.
	--- One set for the whole update, because the two below it ask the same question of the same
	--- profile and building it is a walk over every layer (`NarrowedVisibleActions`). Nothing
	--- between here and the last of them touches what the answer is made of: `UpdateBindings`
	--- writes the key map and not `key` or `arrivalID`, which are the two fields the filters read.

	local visible = NarrowedVisibleActions();
	DebindFrame:PruneSelectionToBinFilter(visible);

	DebindPrivate.UpdateBindings();
	DebindLayerPanel:Refresh(true, visible);
	DebindFrame:Update();
end


DebindLineMixin = {};

function DebindLineMixin:Init(elementData)
	self:RegisterForClicks("AnyUp");
	--self:EnableMouseWheel(true);
	self:Update();
end

function DebindLineMixin:Update()
	local elementData = self:GetElementData();
	local action = elementData.action;

	local isInactive = DebindPrivate.IsInactiveAction(action);
	local issue = not isInactive and GetBindingIssue(action) or nil;

	local name, icon = ColoredNameAndIconForAction(action, "key");
	self.Name:SetText(name);

	SetActionIcon(self.Icon, icon);

	-- **아직 안 만진 것.** 지금 그 뜻을 갖는 것은 가져왔지만 승인 전인 액션 하나뿐이다
	-- (XML 주석 참고). 그 액션은 `BuildKeyMap`이 건너뛰므로 이름이 이미 회색인데, 회색은
	-- "키 없음"도 뜻하므로 둘을 가르는 것이 이 표시다.
	--
	-- 자리를 안 먹으므로 이름 앵커는 안 건드린다 - 아이콘 위 빈 자리에만 걸린다.
	self.NewDot:SetShown(action.arrivalID ~= nil);

	local keyIssue = issue and GetBindingIssue(action, "key") or nil;
	local keyIssueIsMinor = keyIssue ~= nil and IsIssueMinor(keyIssue);
	if (action.key) then
		local s = DebindPrivate.GetKeyDisplayText(action.key);
		local color;
		if (isInactive) then
			color = INACTIVE_COLOR;
		elseif (keyIssue and not keyIssueIsMinor) then
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
	--
	-- **A minor problem keeps the mark and loses its colour.** Dropping it would leave the row
	-- saying nothing at all about the key, and the reason this mark exists in the first place is
	-- that colour alone does not reach a colour-blind reader. Desaturating is how the question mark
	-- a few lines down already steps back.
	self.KeyWarning:SetShown(keyIssue ~= nil);
	if (keyIssue) then
		self.KeyWarning:SetDesaturated(keyIssueIsMinor);
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

	if (DebindPrivate.IsConditionalAction(action)) then
		if (isInactive) then
			self.QuestionMark:SetVertexColor(INACTIVE_COLOR:GetRGBA());
			self.QuestionMark:SetDesaturated(true);
		-- **`combat`/`known`/`stealth`/`pet`은 여기 있었고 없는 갈래였다.** `GetBindingIssue`에
		-- 그 이름의 검사가 없어서 네 번 다 nil이었고, 남은 여섯이 같은 판단을 이미 내리고 있어
		-- 증상이 없었다. 읽는 사람만 그 조건들에 모순 검사가 있다고 읽었다.
		elseif (issue and (GetBindingIssue(action, "hover")
				or GetBindingIssue(action, "groups")
				or GetBindingIssue(action, "forms")
				or GetBindingIssue(action, "bonusbars")
				or GetBindingIssue(action, "specialbar")
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
	--
	-- **앵커가 아니라 집합을 본다.** 벌크로 고른 것이 전부 같은 표시를 받아야 하고, 반대로
	-- CTRL-클릭으로 앵커 행을 집합에서 뺐으면 여기서는 강조가 사라지는 것이 맞다 - 그 행은
	-- 이동·복사·삭제가 손대지 않는다. 왼쪽 열은 계속 그 행을 짚는데, 저쪽이 말하는 것은
	-- "고른 것"이 아니라 "지금 이야기 중인 행"이라 어긋나지 않는다.
	self.SelectedHighlight:SetShown(DebindFrame:IsActionSelected(action) or IsEditingAction(action));

	-- 메뉴 대상은 선택과 다른 텍스처를 쓴다(XML 참고). 한 행이 둘 다일 수 있으므로 서로를
	-- 지우지 않는다.
	self.MenuHighlight:SetShown(IsEditDropdownShown(elementData));

	if (GameTooltip:GetOwner() == self) then
		self:OnEnter();
	end

	-- **휠은 지정 모드가 켜진 동안에만 이 행의 것이다.** 평소에 켜두면 목록을 굴릴 수가
	-- 없다 - 행이 화면을 덮고 있으니 휠이 전부 행으로 들어간다. 행은 풀에서 나오므로
	-- 여기서 매번 맞춘다. 모드를 켜고 끌 때 목록 전체가 Update를 받는다(SetBindingMode).
	self:EnableMouseWheel(DebindFrame:IsCapturingKey());

	self:SetAlpha(1);
end

--- **지정 모드 중에는 안내 줄을 갈아 끼운다.** 평소의 세 줄이 그 모드에서는 전부 거짓이다 -
--- 좌클릭도 우클릭도 이 행의 것이 아니라 눌린 키 그 자체가 되고(`DebindLineMixin:OnClick`이
--- `BindMode_OnInput`으로 넘긴다), 선택은 아예 멈춘다. CTRL/SHIFT는 그냥 수식어 키다.
---
--- 비우지 않고 그 모드의 말을 넣는 이유는, **가리키고 있는 이 행이 곧 대상**이기 때문이다.
--- 오버레이(`BIND_MODE_OVERLAY`)는 "오른쪽에서 행동을 가리키라"고 말하는데 그건 아직 안
--- 가리킨 사람에게 하는 말이고, 이미 가리키는 중이면 남은 물음은 "그래서 지금 뭘 누르나"
--- 하나다. 그 답이 나올 자리는 커서가 있는 여기다.
---
--- ESC(지우개)는 여기 안 넣는다. 오버레이가 그 말을 계속 띄우고 있고, 이 줄은 커서를 옮길
--- 때마다 다시 읽히는 자리라 규칙을 둘씩 얹으면 정작 누르라는 말이 묻힌다.
local BIND_MODE_INSTRUCTIONS = { "LINE_TOOLTIP_INSTRUCTION_BIND" };

function DebindLineMixin:OnEnter()
	local elementData = self:GetElementData();
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	AddActionToTooltip(GameTooltip, elementData.action, {
		offWorld = IsLayerOffWorld(elementData.layer),
		instructionKeys = DebindFrame:IsCapturingKey() and BIND_MODE_INSTRUCTIONS or nil,
	});
	GameTooltip:Show();
end

--- 휠. 모드가 켜진 동안에만 이 스크립트가 살아 있다(Update의 EnableMouseWheel).
---
--- 행 위에서만 키가 된다 - 목록의 빈 자리나 스크롤바 위에서는 평소대로 굴러간다. 모드를
--- 켠 채로도 목록을 볼 수 있어야 하고, 그 통로를 남기는 값이 이것뿐이다.
function DebindLineMixin:OnMouseWheel(delta)
	DebindFrame:BindMode_OnInput(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN", self);
end

function DebindLineMixin:OnLeave()
	HideActionTooltip(GameTooltip);
end

function DebindLineMixin:OnClick(buttonName)
	-- **While the mode is on, every input over this row is a key.** Left and right click are
	-- legitimate bindings too (they go with the hover condition), so no exception is made for them.
	-- Selecting and the menu stop for that time - which is why the mode is turned on and off
	-- explicitly, and the lit toggle in the portrait row is what says it is on.
	if (DebindFrame:IsCapturingKey()) then
		DebindFrame:BindMode_OnInput(buttonName, self);
		return;
	end

	if (buttonName == "LeftButton" and GetActionTypeAndValueFromCursorInfo()) then
		DebindLayerPanel.ScrollBox:OnClick();
		return;
	end

	local elementData = self:GetElementData();

	if (buttonName == "RightButton") then
		if (false and DebindPrivate.DEBUG and IsControlKeyDown()) then
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
		elseif (DebindFrame:GetSelectionCount() > 1 and DebindFrame:IsActionSelected(elementData.action)) then
			-- **고른 것 위에서 연 메뉴는 고른 것 전부를 겨눈다.** 탐색기와 같은 규칙이고,
			-- 아래 단일 경로의 계약("메뉴를 여는 행이 곧 고른 행이다")을 깨지 않는다 - 이 행도
			-- 고른 것 중 하나라, 메뉴가 가리키는 것과 강조된 것이 여전히 같다.
			--
			-- 고른 것 **밖에서** 우클릭하면 아래로 내려가 선택이 그 행 하나로 접힌다. 남의 행에서
			-- 열린 메뉴가 안 보이는 다른 행들을 지우는 일이 없어야 한다.
			--
			-- 여기서 elementData를 다시 집지 않는 이유: 대상은 이 행이 아니라 집합이고, 집합은
			-- 액션 테이블을 열쇠로 들고 있어서 목록이 다시 지어져도 살아남는다.
			if (not TryCloseAnyDialog()) then
				return;
			end
			DebindFrame:ShowBulkDropdown(self);
		else
			-- **메뉴를 여는 행이 곧 고른 행이다.** 선택은 화면이 "지금 이 액션 이야기 중"이라고
			-- 말하는 표시인데, 메뉴가 남의 행에서 열리면 그 말과 메뉴가 가리키는 것이 어긋난다.
			-- 상세 패널은 A를 보여주는데 방금 연 메뉴는 B를 지우려는 상태가 실제로 생긴다.
			--
			-- 좌클릭과 같은 함수를 지난다. 이미 고른 행이면 저쪽이 고르는 일은 건너뛰지만,
			-- 왼쪽 열에서 그 행을 다시 찾아주기는 한다 - 메뉴가 열리는 행이 어디 있는지는
			-- 처음 고를 때나 다시 누를 때나 똑같이 보여야 한다.
			--
			-- **집어오는 것보다 먼저다.** 이 호출은 상세 패널을 닫고, 그 길에 매크로 본문
			-- 저장이 딸려 오면 목록이 통째로 다시 지어진다 - 먼저 집으면 그 테이블이 낡는다.
			-- 아래 함수가 존재하는 이유가 정확히 그 문제다(`CloseDialogsAndRefetchElementData`).
			DebindLayerPanel:SetSelectedAction(elementData.action);

			elementData = CloseDialogsAndRefetchElementData(self);
			if (not elementData) then
				return;
			end

			DebindFrame:ShowEditDropdown(self, elementData);
		end
		return;
	end

	-- 좌클릭 = 선택. 수식어가 붙으면 **집합**을 손보고, 붙지 않으면 이 행 하나로 접는다.
	--
	-- **앵커는 SHIFT가 없는 갈래에서만 옮긴다.** CTRL로 집합에서 빼는 경우까지 옮기는데,
	-- 앵커는 "고른 행"이 아니라 "다음 범위를 잴 자리"이기 때문이다. SHIFT는 그 자리를 읽기만
	-- 하므로 옮기지 않는다 - 그래야 같은 기준점에서 범위를 다시 잴 수 있다.
	--
	-- **SHIFT를 먼저 본다.** CTRL+SHIFT는 범위를 더하는 것이라 SHIFT 갈래에 속하는데, CTRL을
	-- 먼저 보면 그 조합이 토글로 새어 들어간다.
	if (IsShiftKeyDown()) then
		DebindLayerPanel:SelectRangeTo(elementData.action, IsControlKeyDown());
	elseif (IsControlKeyDown()) then
		DebindLayerPanel:ToggleActionSelected(elementData.action);
	else
		DebindLayerPanel:SetSelectedAction(elementData.action);
	end
end

--- 행은 끌 수 없지만(`RegisterForDrag` 없음) **받기는** 한다. 커서에 든 것을 놓는 것은
--- 어느 행에 놓든 같은 일이라 프레임으로 넘긴다.
function DebindLineMixin:OnReceiveDrag()
	DebindFrame:OnReceiveDrag();
end

--- 단축키 정렬에서 한 키의 묶음이 시작되는 자리에 놓이는 줄.
---
--- 행에서 단축키 글자를 빼지는 않는다. 헤더는 스크롤에 밀려 화면 밖으로 나가는데(이 목록은
--- 고정 헤더가 아니다) 그러면 무슨 키인지 알 수 없는 행들만 남는다.
--- 키 헤더의 높이, 곧 `ListHeaderThreeSliceTemplate` 아트의 제 높이. 여기서 벗어나면 띠가
--- 프레임 위아래로 삐져나오거나 잘린다 - 아트가 위에서부터 제 크기로 붙기 때문이다.
---
--- 첫 헤더만 낮게 세우던 규칙이 여기서 없어졌다. 그건 위쪽 절반이 여백이던 시절의 것으로,
--- 목록 첫 줄에서는 그 여백이 인셋 위에 뚫린 구멍이 됐다. 여백이 아니라 띠가 서는 지금은
--- 첫 줄도 가를 것이 없기는 마찬가지고, 구멍도 나지 않는다.
local KEY_HEADER_HEIGHT = 26;
-- 각 목록의 행 높이. 뷰가 프레임을 만들기 전에 자리부터 잡으므로 XML의 Size를 대신 여기
-- 적어둔다 - 어긋나면 스크롤 길이가 틀어진다.
local LINE_HEIGHT = 46;
local ORDER_LINE_HEIGHT = 28;

DebindDialogMixin = {};

--- The behaviour half of `DebindDialogTemplate`. Called from each dialog's own `OnLoad`.
---
--- **Dragged from anywhere on itself.** The chrome these wear has no title bar to grab, so without
--- this a dialog is nailed to the middle of the screen on top of whatever it is asking about.
---
--- **A dialog that says it does not move is left alone**, and `movable=` on the frame is where that
--- is said - there is no second flag for it. The one that says so is the key capture dialog, where
--- dragging and pressing the left mouse button are the same gesture (`KeyCapture.xml`).
---
--- **ESC through `UISpecialFrames`, which is the game's net and not ours.** What reads that table is
--- `CloseSpecialWindows`, and the ESCAPE **binding** is what calls it. So this covers exactly the
--- case where nothing is standing in front of the binding: a dialog still up with the main window
--- gone, which the copy dialog is built to be (`DebindExportPanelMixin:OnHide`). While that window
--- is up it takes ESCAPE before any binding runs and closes these itself, one rung each
--- (`DebindFrameMixin:HandleEscape`). The key capture dialog needs neither, being the one that
--- enables the keyboard and answers its own ESC.
---
--- One of them used to hand-roll this with `SetPropagateKeyboardInput`, which is taint in combat
--- and needed a guard for a frame that cannot be up in combat anyway.
---
--- Registered once per dialog and they are never destroyed, so nothing has to come back out.
function DebindDialogMixin:InitDialog(title)
	if (title) then
		self.Title:SetText(title);
	end

	if (self:IsMovable()) then
		self:RegisterForDrag("LeftButton");
		self:SetScript("OnDragStart", self.StartMoving);
		self:SetScript("OnDragStop", self.StopMovingOrSizing);
	end

	tinsert(UISpecialFrames, self:GetName());
end

DebindKeyHeaderMixin = {};

--- What one key group is called, and the only place that is decided.
---
--- The header below writes it, and so does everything that has to name the same set somewhere else
--- -- what the overlay says it is listening for, and what the prompt says the key is being taken
--- from. One thing has one name per screen, and a second copy of this drifts from the column.
---
--- Plain text. The colours belong to the position: the header greys the unbound pile and tints an
--- arrival group, and a prompt in the middle of the screen does neither.
local function KeyGroupLabel(key, from)
	if (key ~= nil) then
		return DebindPrivate.GetKeyDisplayText(key, from);
	end
	return LLL["OVERVIEW_NO_KEY"];
end

--- 글자색은 두 상태 모두 흰색으로 못박는다. 템플릿의 기본은 금색인데, 금색은 이 창에서
--- "누를 수 있는 것"과 "값"이 쓰는 색이라 머리글이 그 색이면 키 이름이 행보다 세게 읽힌다 -
--- 여기서 세야 할 것은 키가 아니라 그 밑에 몇 줄이 달렸는가다. 칠하는 것은 `SetHeaderText`고
--- 이 두 줄은 무엇으로 칠할지만 정해 둔다.
function DebindKeyHeaderMixin:OnLoad()
	self:SetTitleColor(false, HIGHLIGHT_FONT_COLOR);
	self:SetTitleColor(true, HIGHLIGHT_FONT_COLOR);

	-- **키가 자기 글자만큼만 차지하게 푼다.** 템플릿은 이 칸을 끝 조각까지 늘여 놓는데, 그러면
	-- 뒤에 붙는 요약이 언제나 띠 끝에서 시작한다. 왼쪽만 남기면 폭이 글자를 따라가고 요약이
	-- 키 바로 뒤에 선다. x=10은 템플릿이 쓰던 값 그대로다.
	self.Name:ClearAllPoints();
	self.Name:SetPoint("LEFT", 10, 0);

	-- **줄바꿈을 끈다.** 안 끄면 긴 이름이 잘리는 대신 둘째 줄로 넘어가 띠 밖으로 삐져나온다 -
	-- 이 칸은 높이가 한 줄이다. 끄면 `…`로 잘리고, 덤으로 템플릿에 이미 달려 있는 잘림 툴팁이
	-- 살아난다(`ListHeaderMixin:CheckUpdateTooltip`이 `IsTruncated`를 본다).
	self.ActionName:SetWordWrap(false);
end

--- 뷰가 프레임 폭을 잡는 것은 `Init` **뒤**일 수 있다. 폭을 재서 쓰는 계산이라 그때 다시 한다.
function DebindKeyHeaderMixin:OnSizeChanged()
	if (self.elementData) then
		self:LayoutSummary();
	end
end

--- 키 뒤에 붙는 요약의 자리를 잡는다. `Charge +1`.
---
--- **잘려도 되는 것은 이름 하나뿐이다.** 무슨 키인가와 몇 개 더 있는가는 둘 다 안 읽히면
--- 머리글이 할 말을 못 한다. 그래서 이름 칸의 폭을 **미리 깎아** 개수가 설 자리를 남긴다 -
--- 개수를 띠 끝에 못 박는 길도 있었지만, 그러면 짧은 이름에서 개수가 이름과 한참 떨어져 서서
--- `Charge +1`이 한 마디로 안 읽힌다.
---
--- `min`이 두 경우를 다 처리한다. 짧으면 제 폭이 이겨서 상자가 글자에 딱 맞고 개수가 바로 뒤에
--- 붙고, 길면 깎은 폭이 이겨서 `…`로 잘린다.
---
--- **`SetWidth(0)`은 "폭 없음"이 아니라 "제 폭대로"다.** 그래서 자리가 안 나오면 폭을 0으로
--- 두는 대신 아예 감춘다 - 안 그러면 자리가 없다고 판정한 바로 그 글자가 제 폭으로 펼쳐진다.
local SUMMARY_MIN_WIDTH = 24;

function DebindKeyHeaderMixin:LayoutSummary()
	local name = self.ActionName;
	if (not name:IsShown()) then
		return;
	end

	-- 끝 조각은 `useAtlasSize`라 제 폭을 들고 있다. 오른쪽 여백 4는 글자가 그 조각에 닿지
	-- 않게 하는 값이다.
	-- 빼는 값들은 전부 XML에 적힌 자리다: 키의 왼쪽 오프셋 10, 끝 조각에 안 닿을 오른쪽 여백 4,
	-- 그리고 키와 이름 사이 4(`ActionName`의 앵커).
	local available = self:GetWidth() - self.Right:GetWidth() - 10 - 4
		- self.Name:GetUnboundedStringWidth() - 4;

	local count = self.ExtraCount;
	if (count:IsShown()) then
		available = available - count:GetUnboundedStringWidth() - 4;
	end

	-- **Narrow is not hidden.** This used to hide both fields when the space fell under a minimum,
	-- and it could not undo it: the guard above returns before anything measures again, and the
	-- only thing that shows them is `UpdateSummary`, which the resize path does not go through. One
	-- narrow moment stripped a pooled heading for good, and widening the window did not bring it
	-- back. It is clamped instead, so a tight heading truncates to `…` and grows again on its own.
	name:SetWidth(max(SUMMARY_MIN_WIDTH, min(name:GetUnboundedStringWidth(), available)));
end

--- The whole bar is the fold button. This template carries no control of its own and **the end
--- cap is the indicator** (`Options_ListExpand_Right` <-> `_Expanded`), so letting only that piece
--- be pressed would part what is visible from what is clickable.
---
--- Right opens the group's menu, and it is the same bar it has always been: nothing was added to
--- the art for it, and the fold keeps the button the reader already presses.
function DebindKeyHeaderMixin:OnClick(button)
	if (button == "RightButton") then
		self:OpenKeyGroupMenu();
		return;
	end

	local groupKey = CollapseKeyFor(self.elementData.key, self.elementData.arrivalID);
	_collapsedKeys[groupKey] = not _collapsedKeys[groupKey] or nil;
	DebindResultPanel:RefreshKeyboard();
end

--- What this heading's menu would be built over, or `nil` where it would come up empty.
---
--- **The actions rather than the rows**, because that is what every item takes, and because the two
--- callers below are answering one question between them: is there a menu here.
---
--- A key group always has one. **A pile only has one when something in it arrived** - neither key
--- item belongs over rows that share nothing (giving them all one key invents a set the reader never
--- made, and there is nothing to take off), which leaves the import pair as the only thing that can
--- stand there. What puts a badge in that pile is an action the sender had on no key: it lands on
--- none here either, so it is loose rather than a group of its own.
local function HeaderMenuActions(elementData)
	local rows = elementData.rows;
	if (not rows or not rows[1]) then
		return nil;
	end

	local actions = {};
	for i = 1, #rows do
		actions[i] = rows[i].action;
	end

	if (elementData.key == nil and not DebindPrivate.AnyArrivedAction(actions)) then
		return nil;
	end
	return actions;
end

--- **One line, and it names the right-click.** That gesture is the only thing on this bar nothing
--- points at, and since the row menu stopped carrying the set's own items there is no other way in
--- to them - the whole reason the heading was once rejected as a place to put them.
---
--- **Folding is left out.** Not knowing it costs the reader nothing: the column opens expanded, so a
--- fold they never find leaves every action and every operation reachable. Not knowing the
--- right-click costs them the menu. That is the test for a line here, and it is why the row's tooltip
--- legitimately names both of its gestures while this one names one.
---
--- **The line is hung on exactly the headings that open something**, which is why the same predicate
--- answers for the tooltip and for the click (`HeaderMenuActions`). A tooltip promising a menu that
--- never comes is worse than no tooltip, and the two conditions written out twice is how they end up
--- disagreeing - the pile at the bottom went from opening nothing to opening one pair inside a day.
---
--- The template's own tooltip is being overridden and it had a job: the full title when the title is
--- cut (`ListHeaderMixin:CheckUpdateTooltip`). The title line here does that job. Its other two -
--- highlighting the title, lighting the end cap - are why the inherited handler is called first
--- rather than reimplemented.
function DebindKeyHeaderMixin:OnEnter()
	ListHeaderMixin.OnEnter(self);

	local elementData = self.elementData;
	if (elementData == nil or not HeaderMenuActions(elementData)) then
		return;
	end

	-- 색은 안 물려준다. 머리글의 파랑·회색·빨강은 **그 자리에서** 이 그룹이 어디 서 있는지를
	-- 말하는 것이고, 툴팁은 그 물음에 답하는 자리가 아니다(메뉴 제목과 같은 규칙).
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, KeyGroupLabel(elementData.key));
	GameTooltip_AddInstructionLine(GameTooltip, LLL["KEY_HEADER_TOOLTIP_INSTRUCTION"]);
	GameTooltip:Show();
end

function DebindKeyHeaderMixin:OnLeave()
	ListHeaderMixin.OnLeave(self);
	GameTooltip:Hide();
end

--- The menu for the group this heading stands over.
---
--- **What identifies the group is `(key, arrivalID)`**, so that pair is what the menu carries. The
--- menu can still be standing when the column is rebuilt, and a pair of values is not a place in a
--- list that has been thrown away since - the actions are collected from it at the moment the item
--- is pressed, which also reaches past this screen (`CollectKeyGroupActions` walks every layer).
---
--- The first row rides along for the **title** and for nothing else. That one is not interchangeable:
--- it is first in firing order, which is what the heading calls the set by.
---
--- Which headings open at all, and what over, is `HeaderMenuActions`. **The list is worked out here
--- rather than in the menu** because the import items decide whether to stand up while the menu is
--- being built, and what they must read is what is drawn under this bar right now.
function DebindKeyHeaderMixin:OpenKeyGroupMenu()
	local elementData = self.elementData;
	local actions = HeaderMenuActions(elementData);
	if (actions == nil) then
		return;
	end

	-- The title names the set the way the heading does (`UpdateSummary`): the first action, and how
	-- many more there are. Only that second number is counted here.
	MenuUtil.CreateContextMenu(self, DebindUI.SetupKeyGroupDropdownMenu,
		elementData.key, actions[1], #actions - 1, actions, elementData.arrivalID);
end

function DebindKeyHeaderMixin:Init(elementData)
	self.elementData = elementData;
	self:UpdateCollapsedState(elementData.collapsed == true);

	if (elementData.arrivalID ~= nil) then
		-- **An arrival, waiting to be taken.** It is on the key it was sent on, so the key is what
		-- names it -- and that key is routinely one the reader already uses, which is why the group
		-- is `(key, arrivalID)` and this heading is not the same heading as theirs
		-- (`devdocs/building-export-import.md` 12절). What separates two of them on screen is the
		-- summary beside the key (`UpdateSummary`) and the tint here.
		--
		-- **Tinted rather than greyed.** Grey is "nothing here runs, and that is fine"; this one is
		-- waiting on the reader, which is work.
		self:SetHeaderText(IMPORTED_FONT_COLOR:WrapTextInColorCode(KeyGroupLabel(elementData.key)));
	elseif (elementData.key) then
		-- **키는 걸려 있는데 지금 아무것도 안 나가는 그룹은 흐리다.** 멤버가 전부 다른 특성
		-- 것이면 그렇게 된다 - 이 열은 오프스펙도 그리므로 그런 그룹이 실제로 서 있고, 색이
		-- 없으면 눌리는 키와 안 눌리는 키가 같은 무게로 읽힌다. 행이 같은 사유로 자기 이름을
		-- 흐리게 하는 것과 한 규칙이다(`ColoredNameAndIconForAction`).
		--
		-- **Red where something in it is waiting to be fixed.** The two cannot both be true - a
		-- broken row is still in the build, so a group holding one is not all-inactive - and they
		-- are saying different things about the group: grey is "nothing here runs, and that is
		-- fine", red is "something here would run and does not".
		--
		-- **Blue wins over both, and does so by never meeting them**: an arrival is its own group
		-- (`arrivalID`), so it takes the branch above even when it sits on this very key. That is the
		-- order the reason column already keeps - accepting comes before fixing, since what arrived
		-- is not ours to fix until it is taken.
		local label = KeyGroupLabel(elementData.key);
		if (elementData.hasError) then
			label = ERROR_COLOR:WrapTextInColorCode(label);
		elseif (elementData.allInactive) then
			label = DISABLED_FONT_COLOR:WrapTextInColorCode(label);
		end
		self:SetHeaderText(label);
	else
		-- 키가 없는 것은 키의 한 종류가 아니라 상태다. 그래서 낱말로 쓰고 흐리게 둔다.
		--
		-- **The client's own words**, through the same key the row's shortcut cell uses. Writing a
		-- second wording here is how the same window came to say two things once already - the
		-- tooltip comment on that cell has the history.
		self:SetHeaderText(DISABLED_FONT_COLOR:WrapTextInColorCode(KeyGroupLabel()));
	end

	self:UpdateSummary();
end

--- Says what the group holds: the first action's name, and how many more there are.
---
--- **Folded or not, the heading says the same thing.** It used to summarise only while folded, on
--- the reading that the rows below already name themselves. What that cost was a heading that
--- changed shape as it was pressed, and a count that vanished exactly when the reader had opened
--- the group to compare it against what was inside.
---
--- The first action is **the first in firing order** (the order `CollectActionsForKey` settles).
--- That is what actually goes out when the key is pressed, so if only one of them can be shown it
--- has to be that one.
---
--- With only one there is no count. `+0` goes out of its way to say there is nothing to count, and
--- the room goes back to the name standing longer.
function DebindKeyHeaderMixin:UpdateSummary()
	local elementData = self.elementData;
	local rows = elementData.rows;
	if (not rows or #rows == 0) then
		self.ActionName:Hide();
		self.ExtraCount:Hide();
		return;
	end

	-- **키 없는 덩어리는 개수만 말한다.** 키 그룹에서 첫 이름이 뜻을 갖는 것은 그게 이 키를
	-- 눌렀을 때 실제로 나가는 것이기 때문인데, 여기는 아무것도 안 나가고 차례도 발동 순서가
	-- 아니라 이름순이라 첫째가 그냥 가나다순 첫 글자다. 대표로 세울 근거가 없다.
	--
	-- **`+N`을 안 쓴다.** 같은 자리에 같은 모양으로 서지만 산수가 다르다 - 저쪽 `+1`은 "이름 댄
	-- 것 말고 하나 더"이고 여기는 총수다. 부호를 떼는 것이 그 둘을 가른다.
	--
	-- 앵커를 갈래마다 다시 잡는 것은 프레임이 풀에서 나오기 때문이다. 이름 칸에 매달린 채로
	-- 이름만 숨기면 앞 요소가 남긴 폭만큼 개수가 밀려 선다.
	local keyless = elementData.key == nil;
	self.ExtraCount:ClearAllPoints();

	if (keyless) then
		self.ActionName:Hide();
		self.ExtraCount:SetPoint("LEFT", self.Name, "RIGHT", 4, 0);
		self.ExtraCount:SetFormattedText(LLL["OVERVIEW_NO_KEY_COUNT"], #rows);
		self.ExtraCount:Show();
	else
		-- **타입은 떼고 이름만.** 세 번째 반환값이 그것이다 - 같은 이유로 상세 패널의 인포
		-- 인셋도 이 값을 쓴다. 이 줄에서는 자리가 더 무거운 이유이기도 한데, "Wrath (주문)"의
		-- 괄호 절반이 잘리는 자리를 차지하면 정작 잘리는 것은 이름 쪽이 된다.
		local _, _, bareName = NameAndIconForAction(rows[1].action);
		self.ActionName:SetText(bareName or "");
		self.ActionName:SetWidth(0);
		self.ActionName:Show();

		self.ExtraCount:SetPoint("LEFT", self.ActionName, "RIGHT", 4, 0);
		if (#rows > 1) then
			self.ExtraCount:SetFormattedText(LLL["OVERVIEW_KEY_HEADER_MORE"], #rows - 1);
			self.ExtraCount:Show();
		else
			self.ExtraCount:Hide();
		end
	end

	-- **줄이 통째로 흐려진다.** 키만 흐리고 요약을 금색으로 두면 한 줄이 안 나간다는 말과
	-- 나간다는 말을 같이 하게 된다. 금색은 폰트가 들고 있으므로 되돌릴 때도 명시해야 한다.
	--
	-- 키 없는 덩어리는 언제나 흐리다 - 키가 없으니 한 줄도 빌드에 안 들어간다. 머리글 글자가
	-- 이미 `DISABLED`로 감싸여 나오므로 개수만 금색이면 한 줄이 두 말을 한다.
	--
	-- **Red does not travel the same way, on purpose.** Grey is true of every member at once, which
	-- is what lets it take the whole line; a problem belongs to one row, and this summary names the
	-- first action only. Painting that name red would accuse whichever action happens to fire first
	-- of a fault that may be three rows down.
	local r, g, b = NORMAL_FONT_COLOR:GetRGB();
	if (keyless or elementData.allInactive) then
		r, g, b = DISABLED_FONT_COLOR:GetRGB();
	end
	self.ActionName:SetTextColor(r, g, b);
	self.ExtraCount:SetTextColor(r, g, b);

	self:LayoutSummary();
end

--- DebindFrameMixin:Update가 목록의 모든 프레임에 이걸 부른다. 헤더가 말하는 것은 키뿐이고
--- 키가 바뀌면 목록이 통째로 다시 그려지므로 여기서 할 일이 없다.
function DebindKeyHeaderMixin:Update()
end

--- The window's tab row. One row per tab, and `id` is the seat - the XML's `id=` and the order
--- here have to agree, because `parentArray="Tabs"` fills the array by declaration order.
---
--- **Every panel is this addon's own now**, so all three arrive by `panelKey`. Two of them used to
--- be built by the load-on-demand addon, which is why they could not be XML children of the frame
--- and had to be fetched by global name and reparented. Moving the UI over here closed that road
--- (`devdocs/building-export-import.md`).
---
--- `needsStore` is what is left of the split, and it asks about **data** rather than about the
--- panel. Import reads the drawer, Export walks the profile through `IsExportable`, and both of
--- those still live in the addon that is loaded on demand.
--- Overview's seat. Named because two places outside the tab row have to name it: the first
--- selection at load, and anything that has to put the reader back somewhere its work is visible.
local OVERVIEW_PANEL = 1;

local STORE_ADDON = "DebindStorage";

local PANELS = {
	{ title = "OVERVIEW",     desc = "OVERVIEW_DESC",      panelKey = "OverviewPanel" },
	-- **Ahead of the sharing pair, and the only seat that is not about actions.** It reads the
	-- switch definitions, which are ordinary profile data, so it needs nothing loaded on demand.
	{ title = "CUSTOM_STATES", desc = "CUSTOM_STATES_DESC", panelKey = "SwitchesPanel" },
	-- **One seat where there were two.** Making a string and taking one in are the same list read
	-- in two directions, and what they had in common is the list (12절 of
	-- `devdocs/building-export-import.md`).
	{ title = "STORAGE_TITLE", desc = "STORAGE_MENU_DESC", panelKey = "StoragePanel", needsStore = true },
};

--- Brings in the addon that builds the strings and keeps the drawer. Does nothing if it is here.
---
--- **The private table is parked on `_G` only for the length of `LoadAddOn`.** The first file over
--- there grabs it inside that window and hands its own table back as `DebindPrivate.Store`, which
--- is what the two panels reach the model through. `DebindCliqueFake` crosses the same way.
---
--- It asks `IsAddOnLoaded`. It once named a frame over there instead, which answers "was that one
--- frame built", not "is the addon in" - and every frame it could have named now belongs to this
--- addon, so that test would answer yes on a login where the other one never loaded at all.
--- **What is asked is whether the handover happened, not whether the addon is in.** `Store` is set
--- inside the parking window below and nowhere else, so an addon somebody else's `LoadAddOn`
--- brought in is in memory having been handed nothing - and every caller dereferences that table.
--- Asking `IsAddOnLoaded` there answers yes and turns the `MissingPanel` fallback into an error on
--- the tab. Reloading it is not an option either: `LoadAddOn` on something already loaded returns
--- at once without re-running a line, so the answer is no and the reader gets the panel that says
--- so. (Only a release build can reach this. `Constants.DEBUG` parks the table for good.)
local function EnsureStore()
	if (DebindPrivate.Store) then
		return true;
	end

	local prev = _G.DebindPrivate;
	_G.DebindPrivate = DebindPrivate;
	C_AddOns.LoadAddOn(STORE_ADDON);
	_G.DebindPrivate = prev;

	return DebindPrivate.Store ~= nil;
end

DebindPanelTabMixin = {};

function DebindPanelTabMixin:OnClick()
	if (not TryCloseAnyDialog()) then
		return;
	end
	DebindFrame:SelectPanel(self:GetID());
end

--- The label is one word, so **this is the only place the tab can say what it opens.**
---
--- The template already has an `OnEnter` (it shows the name when the text is truncated) and this
--- replaces it - our tooltip carries that name as its title anyway, so nothing is lost.
function DebindPanelTabMixin:OnEnter()
	local entry = PANELS[self:GetID()];
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, LLL[entry.title]);
	GameTooltip_AddNormalLine(GameTooltip, LLL[entry.desc]);
	GameTooltip:Show();
end

function DebindPanelTabMixin:OnLeave()
	GameTooltip:Hide();
end

DebindTabMixin = {};

function DebindTabMixin:OnLoad()
end

function DebindTabMixin:OnClick()
	if (not TryCloseAnyDialog()) then
		return;
	end

	local id = self:GetID();
	if (_selectedTab ~= id) then
		DebindIconSelectorFrame:Hide();

		PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
		-- Named, not walked up to. The parent is `LayerPanel` now, and the tab is not asking the
		-- box it sits in to switch - it is telling the window. `OnReceiveDrag` below already
		-- addressed the window this way.
		DebindFrame:SetTab(id);
	end
end

--- 제목은 탭 글자에서 **개수를 뺀 것**이다. `GetTabLabel`이 그 값이고, 화면의 "(12)"는
--- `UpdateActionCounts`가 뒤에 붙인다 - 툴팁에서 다시 셀 일이 아니다.
function DebindTabMixin:OnEnter()
	local id = self:GetID();
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, GetTabLabel(id));
	GameTooltip_AddNormalLine(GameTooltip, LLL[id == 2 and "TAB_DESC_CHARACTER" or "TAB_DESC_SHARED"]);

	-- TODO add instruction line. "you can drop here to add/move into this tab"

	GameTooltip:Show();
end

function DebindTabMixin:OnLeave()
	GameTooltip:Hide();
end

function DebindTabMixin:OnReceiveDrag()
	local id = self:GetID();
	local layerID = GetLayerID(id, _selectedSideTab);
	DebindFrame:OnReceiveDrag(layerID);
end

function DebindTabMixin:IsActive()
	return _selectedTab == self:GetID();
end

DebindSideTabMixin = {};

function DebindSideTabMixin:OnClick()
	if (not TryCloseAnyDialog()) then
		return;
	end

	local id = self:GetID();
	if (_selectedSideTab ~= id) then
		PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);

		-- 사이드탭도 탭과 같은 이동이다 - 바뀌는 것은 레이어 하나뿐이지만 목록이 통째로
		-- 갈리는 것은 같다. 고른 것을 놓는 이유도 같다(`DebindFrameMixin:SetTab`).
		DebindLayerPanel:SetSelectedAction(nil);

		_selectedSideTab = id;

		DebindLayerPanel:UpdateSideTabs();
		DebindLayerPanel:Refresh();
		-- `Refresh` rebuilds the list; `Update` is what re-reads it. Without this the strip and
		-- the multi-select tip keep describing the tab we just left - a tip anchored under a list
		-- that is now empty, or no tip at all on a list that just filled up.
		DebindFrame:Update();
	else
		self:SetChecked(true);
	end
end

--- 제목은 사이드탭 이름 혼자가 아니라 **레이어 이름 전체**다("공유 / 야성"). 이 줄이 서 있는
--- 곳이 세로 탭이라, 그 사람이 보고 있는 것은 아이콘 하나와 숫자 하나뿐이다 - 어느 쪽 탭에
--- 딸린 세로 탭인지가 화면에 안 적혀 있고, 아래 설명 줄의 "일반보다 우선"도 그걸 알아야
--- 읽힌다. `GetLayerLabel`을 쓰므로 순서 목록의 행 툴팁과 같은 이름이 뜬다.
function DebindSideTabMixin:OnEnter()
	local id = self:GetID();
	local text = GetLayerLabel(GetLayerID(_selectedTab, id));
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	if (self.isOffSpec) then
		text = format(LLL["INACTIVE_SPEC_LABEL"], text);
	end
	GameTooltip_SetTitle(GameTooltip, text);
	GameTooltip_AddNormalLine(GameTooltip, GetSideTabDescription(id));

	-- **Last, not before the description.** The line it qualifies has to be read first, and
	-- Blizzard puts the "when does this apply" line at the bottom of a tooltip -- `Requires
	-- Level 40` sits there. Not coloured: red is for a condition that failed, and this one has
	-- not failed, it is simply not now.
	if (self.isOffSpec) then
		GameTooltip_AddNormalLine(GameTooltip, LLL["INACTIVE_SPEC_DESC"]);
	end

	-- TODO add instruction line. "you can drop here to add/move into this tab"

	GameTooltip:Show();
end

function DebindSideTabMixin:OnLeave()
	GameTooltip:Hide();
end

function DebindSideTabMixin:OnDisable()
	self:GetNormalTexture():SetDesaturated(true);
end

function DebindSideTabMixin:OnEnable()
	self:GetNormalTexture():SetDesaturated(self.isOffSpec);
end

function DebindSideTabMixin:OnReceiveDrag()
	local layerID = GetLayerID(_selectedTab, self:GetID());
	DebindFrame:OnReceiveDrag(layerID);
end

function DebindSideTabMixin:IsActive()
	return _selectedSideTab == self:GetID();
end

DebindPortraitMixin = {};

function DebindPortraitMixin:SetSelectedState(isSelected)
	self.Frame:SetDesaturated(not isSelected);
	self.UnselectedFrame:SetShown(not isSelected);
end

function DebindPortraitMixin:OnLoad()
	self:SetSelectedState(false);
	-- File, ID or atlas behind the `A:` prefix - the same convention the action lists use, and the
	-- only one of the three that has no keyboard art of its own.
	SetActionIcon(self.Portrait, self.PortraitTexture);
	-- **Both lines keep what they are given when it is not a key.** This runs on the first `OnShow`,
	-- which is later than it looks: the frame's `InitializeButtons` has already been through, and the
	-- bind mode toggle's two fields are written there (`UpdateBindModeButton`) as finished text. The
	-- text line without its tail dropped that to nil, and the toggle's tooltip lost its second line
	-- until the mode was toggled once.
	if (self.TooltipTitle) then
		self.TooltipTitle = rawget(LLL, self.TooltipTitle) or _G[self.TooltipTitle] or self.TooltipTitle;
		self.TooltipText = rawget(LLL, self.TooltipText) or self.TooltipText;
	end
	if (self.MenuFunc) then
		self:SetupMenu(DebindUI[self.MenuFunc]);
	end
end

function DebindPortraitMixin:OnMenuOpened(menu)
	DropdownButtonMixin.OnMenuOpened(self, menu);
	self:SetSelectedState(true);
end

function DebindPortraitMixin:OnMenuClosed(menu)
	-- 위 함수를 복사해 오면서 `OnMenuOpened`가 그대로 남아 있었다. 화면은 아래 줄이 맞춰줘서
	-- 멀쩡했지만, 기본 믹스인 쪽은 **메뉴가 영영 열려 있는 것으로 알고** 있었다.
	DropdownButtonMixin.OnMenuClosed(self, menu);
	self:SetSelectedState(false);
end

function DebindPortraitMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
		self.initialized = true;
	end
end

--- 꺼져 있어도 뜬다(XML의 `motionScriptsWhileDisabled`). 이유가 붙어 있으면 맨 아래에
--- 따로 적는다 - 위의 두 줄은 이 버튼이 **원래 무엇인가**를 말하고, 이건 **지금 왜 안
--- 되는가**라 성질이 다르다. 이유가 없는 채로 꺼진 것도 있다(아이콘 선택기가 떠 있는 동안
--- 전부 잠긴다). 그때는 원래 툴팁만 뜬다 - 그 상황은 화면에 팝업이 떠 있어서 스스로 설명된다.
function DebindPortraitMixin:OnEnter()
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

function DebindPortraitMixin:OnLeave()
	GameTooltip:Hide();
end

function DebindPortraitMixin:OnEnable()
	self.Portrait:SetDesaturated(false);
end

function DebindPortraitMixin:OnDisable()
	self.Portrait:SetDesaturated(true);
end

--- **`LayerPanel` has a mixin and `OverviewPanel` does not**, and the difference is what each one
--- is. The outer container earns its keep by existing - hiding it hides everything inside it,
--- whatever the `Update*` passes decide to switch back on - and nothing about that needs a method.
--- The right column is not that: it builds a list, it owns the side tabs beside it and the two tabs
--- under it, and every one of those is answerable without asking the window anything.
---
--- **The selection did not move with the three gestures that write it.** `SetSelectedAction`,
--- `ToggleActionSelected` and `SelectRangeTo` are things done to rows in this column, so they sit
--- on the panel; what they write is read by the left column as well, so it stays the window's and
--- comes back out through `GetSelectedAction` and its neighbours.
---
--- `.zzz/resolved.md` holds a 2026-08-14 measurement that dropped this same move. What it counted
--- was whether the `self.LayerPanel.` prefix got shorter, and the answer was +1. That is no longer
--- the question `breaking-up-debindui.md` asks, which is which of the two columns a method is about.
DebindLayerPanelMixin = {};
DebindFrameMixin = {};

function DebindLayerPanelMixin:InitializeSideTabs()
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
function DebindLayerPanelMixin:UpdateSideTabs()
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

--- 크기가 0인 것은 **탭이 비었다는 뜻 하나뿐**이다. 검색은 없앴다.
---
--- 오버뷰 탭은 예외가 하나 있다. **거기서는 필터가 목록을 실제로 비운다** - 흐리게 하는
--- 검색과 달리 문제 없는 행을 아예 안 넣기 때문이다. 그래서 "빈 목록"이 두 가지 뜻을
--- 갖고, 둘은 정반대다: 걸린 키가 하나도 없거나(할 일이 있다), 문제가 하나도 없거나(없다).
--- 같은 문장으로 말하면 후자가 고장으로 읽힌다.
function DebindFrameMixin:UpdateEmptyText()
	if (self.LayerPanel.dataProvider:GetSize() == 0) then
		-- **While something is filtering it says a different thing.** The usual line is "there are
		-- no actions here, drag one in"; if the list is empty only because something was filtered
		-- out, that line is a lie and it hands out the wrong next step on top of being one.
		--
		-- 필터가 검색보다 앞선다. 둘 다 걸려 있으면 원인이 둘인데, 필터 쪽은 **꺼진 값이 무엇인지
		-- 드롭다운을 열면 바로 보이는** 쪽이라 다음 걸음이 있다. 검색은 친 글자를 이미 알고 있으니
		-- 그 문장이 새로 말해주는 것이 없다.
		local emptyKey = "NO_ACTIONS_IN_THIS_TAB";
		if (not self:AreFiltersDefault()) then
			emptyKey = "NO_ACTIONS_MATCH_FILTERS";
		elseif (_searchText) then
			emptyKey = "NO_SEARCH_RESULTS";
		end
		self.LayerPanel.ScrollBox.EmptyText:SetText(LLL[emptyKey]);
		self.LayerPanel.ScrollBox.EmptyText:Show();
	else
		self.LayerPanel.ScrollBox.EmptyText:Hide();
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
function DebindLayerPanelMixin:UpdateActionCounts(visible)
	-- **While something is filtering, the number becomes how many got through, and turns green.**
	--
	-- Leave the number alone and the tab lies - "(12)" is pressed and the list has two rows in it -
	-- and which tab holds the name being looked for still takes pressing them one at a time. That
	-- is the only useful question this number can answer while something is filtering.
	--
	-- Recolouring is the mark that **the number means something else right now**. Count a different
	-- thing in the same place in the same shape and clearing the filter reads as actions having
	-- appeared. **Zero is grey.** Green means "what you are after is in here", so green on tabs
	-- that have none takes that meaning away - an eye running down the tab row should have the
	-- colour do the discarding for it.
	--
	-- **Which tab did the thing that arrived land in** is a question only this row can answer. The
	-- left column draws off-spec actions but not which layer holds one, and one entry routinely
	-- splits across layers; the number beside each side tab is where that lands.
	--
	-- **What is counted is what the left column draws** (`NarrowedVisibleActions`), not what passes
	-- action by action. The filters judge a key group whole, so counting one action at a time would
	-- disagree with the list on every group that survived on one member's account.
	visible = visible or NarrowedVisibleActions();
	local narrowed = visible ~= nil;

	for tabId, tab in ipairs(self.Tabs) do
		local label = GetTabLabel(tabId);

		do
			local sum = 0;
			local countedLayers = {};
			for sideTabId, sideTab in ipairs(self.SideTabs) do
				if (sideTabId <= 2 + NUM_SPECS) then
					local layerId = GetLayerID(tabId, sideTabId);
					local layer = DebindPrivate.GetProfileLayer(layerId);
					local count = CountActionsInLayer(layer, visible);

					-- 사이드탭 숫자는 그 사이드탭이 여는 레이어를 그대로 보여준다. 중복이라
					-- 합계에서 빠지는 쪽(탭2의 사이드탭2)도 자기 숫자는 맞게 들고 있어야
					-- 한다 - 어느 쪽을 숨길지는 UpdateSideTabs의 사정이고, 여기가 그걸
					-- 앞질러 정하면 숨김 규칙이 바뀔 때 보이는 숫자가 비게 된다.
					if (tabId == _selectedTab) then
						sideTab.Count:SetText(count);
						if (not narrowed) then
							sideTab.Count:SetTextColor(1, 1, 1);
						elseif (count > 0) then
							sideTab.Count:SetTextColor(GREEN_FONT_COLOR:GetRGB());
						else
							sideTab.Count:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
						end
					end

					if (not countedLayers[layerId]) then
						countedLayers[layerId] = true;
						sum = sum + count;
					end
				end
			end

			-- 탭 글자는 한 덩어리라 숫자만 물들이려면 색 코드를 끼워 넣어야 한다. 사이드탭은
			-- 숫자가 제 FontString이라 위에서 색을 직접 준다.
			local text = "(" .. sum .. ")";
			if (narrowed) then
				local color = (sum > 0) and GREEN_FONT_COLOR or DISABLED_FONT_COLOR;
				text = color:WrapTextInColorCode(text);
			end
			label = label .. " " .. text;
		end

		tab:SetText(label);
		PanelTemplates_TabResize(tab, 0)
	end
end

-- 커서에 집어온 주문/매크로를 놓는 동작은 드래그가 아니라 **클릭**이다. 그래서 클릭도
-- OnReceiveDrag로 보낸다. 폴백이 아니라 pickup의 정규 경로다.
--- 목록을 단축키로 묶어 그릴지. 기본은 켬이다 - 저장값이 nil이면 켜진 것으로 읽고,
--- 끈 사람만 false를 남긴다. 무엇이 묶이고 무엇이 안 묶이는지는 BuildSortedElements에 있다.
local function ScrollBox_OnClick(self)
	if (GetActionTypeAndValueFromCursorInfo()) then
		self:OnReceiveDrag();
	end
end

local function ScrollBox_OnReceiveDrag(self)
	DebindFrame:OnReceiveDrag();
end

function DebindLayerPanelMixin:InitializeScrollBox()
	local padding = 7;
	local bottomPadding = 40;
	local spacing = 4;
	local view = CreateScrollBoxListLinearView(padding, bottomPadding, padding, padding, spacing);

	-- 이 목록에는 행 한 종류뿐이다. 키 헤더는 왼쪽 열에만 있다 - 여기서 키로 묶는 것은
	-- 없앴고, 발동 순서를 말하는 자리는 처음부터 저쪽 하나였다.
	view:SetElementInitializer("DebindLineTemplate", function(button, elementData)
		button:Init(elementData);
	end);
	view:SetElementExtent(LINE_HEIGHT);

	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);

	self.ScrollBox.OnClick = ScrollBox_OnClick;
	self.ScrollBox.OnReceiveDrag = ScrollBox_OnReceiveDrag;

	self.ScrollBox:RegisterForClicks("AnyUp");
	self.ScrollBox:SetScript("OnClick", self.ScrollBox.OnClick);
	self.ScrollBox:SetScript("OnReceiveDrag", self.ScrollBox.OnReceiveDrag);
end

function DebindFrameMixin:InitializeButtons()
	-- [+]는 이제 **창을 연다.** 예전에는 여기 드롭다운이 매달려 있었는데, 그 안에 있던
	-- 항목이 전부 주문 선택 창으로 옮겨갔다(주문·매크로·탈것·장난감은 목록으로, 명령과
	-- 애드온 고유 액션은 각자 탭으로, 매크로 텍스트는 그 창의 버튼으로).
	self.OverviewPanel.AddPortrait:SetScript("OnClick", function()
		DebindSpellPickerFrame:Toggle();
	end)

	-- 지정 모드 토글. 켜고 끄는 것은 XML의 OnClick이고, 여기는 처음 한 번의 툴팁이다.
	--
	-- 툴팁 자체는 포트레잇 템플릿이 그린다(`DebindPortraitMixin:OnEnter`) - 여기서 하는 일은
	-- 그 믹스인이 읽을 두 필드를 지금 상태에 맞춰 두는 것뿐이다. 앞서 이 자리에 있던
	-- SetScript 두 개는 그래서 없어졌다: 툴팁을 직접 그리면 못 누를 때 이유를 붙이는
	-- `disabledReason` 갈래가 이 버튼에서만 빠진다.
	self:UpdateBindModeButton();

	-- 값이 실제로 달라졌을 때만 목록을 짓는다. `SetText`는 같은 글자로도 이 스크립트를 부른다.
	self.OverviewPanel.SearchBox:SetScript("OnTextChanged", function(editBox)
		InputBoxInstructions_OnTextChanged(editBox);

		local text = strtrim(editBox:GetText()):lower();
		if (text == "") then
			text = nil;
		end
		if (_searchText ~= text) then
			_searchText = text;
			-- **걸러져 나간 것은 벌크 대상에서 뺀다.** 안 빼면 "2 selected"라고 적혀 있는데
			-- 이동·삭제는 보이는 하나만 손대는 상태가 된다 - `GetSelectedActions`가 목록을
			-- 훑으므로 안 보이는 것은 어차피 안 넘어간다. 개수가 늘 사실이어야 한다.
			--
			-- **앵커는 안 건드린다.** 그건 "벌크 대상"이 아니라 "지금 이야기 중인 행"이고,
			-- 왼쪽 열이 그것을 보고 있다. 검색어를 쳤다고 보던 자리를 뺏지 않는다.
			--
			-- 매크로 편집 창은 반대다. 걸러져 나간 행 위에 떠 있을 자리가 없으므로 `Refresh`가
			-- 닫는다. 앵커가 남는 것과 어긋나 보이지만, 하나는 화면이 짚는 자리고 하나는 그 행이
			-- 있어야 뜻이 서는 창이다.
			--
			-- One set for the two below, built here because this is the top of the update. The
			-- keystroke that lands on this line is the reason it is not built three times over
			-- (`NarrowedVisibleActions`).
			local visible = NarrowedVisibleActions();
			self:PruneSelectionToBinFilter(visible);
			-- 스크롤 자리는 안 지킨다. 목록의 길이 자체가 달라지므로 지켜봐야 엉뚱한 데를
			-- 보게 되고, 검색은 맨 위부터 읽는 동작이다.
			self.LayerPanel:Refresh(false, visible);
			self:Update();
		end
	end);
	self.OverviewPanel.SearchBox:SetScript("OnEditFocusGained", SearchBoxTemplate_OnEditFocusGained);
	self.OverviewPanel.SearchBox:SetScript("OnEditFocusLost", SearchBoxTemplate_OnEditFocusLost);

	self:InitializeFilterDropdown();

	-- What came in and has not been answered. One button now, and the narrowing that used to stand
	-- beside it is a tick in the left column's filter dropdown (`_filters.pending`).
	--
	-- **The title is the button's own text, not the locale key.** The label carries a `%d`, so
	-- reading the key here would put the placeholder on screen. Asking the button also means the
	-- number in the tooltip is the number under the cursor, with no second place to keep it in step.
	--
	-- **The body says what the state is, and the instruction line says how to leave it.** They were
	-- one sentence per button while there were two buttons, each explaining its own verb; a label
	-- that names the state instead has to explain the state, and the two verbs moved into the menu
	-- along with the sentences that describe them.
	self.OverviewPanel.PendingImports:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, button:GetText());
		GameTooltip_AddNormalLine(GameTooltip, LLL["IMPORT_PENDING_DESC"]);
		GameTooltip_AddInstructionLine(GameTooltip, LLL["IMPORT_PENDING_INSTRUCTION"]);
		GameTooltip:Show();
	end);
	self.OverviewPanel.PendingImports:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
end

--- 왼쪽 열 위의 필터 드롭다운. **축마다 값이 한 줄씩**이고 사이에 구분선이 선다.
---
--- 값별로 펼치는 것이 이 메뉴의 형태다. 탈것 창의 「수집됨 / 수집 안 됨」이 같은 모양이고, 거기
--- 체크는 전부 "이것도 보여줘"라 극성이 하나다 - 「비활성 전문화」 하나만 두면 그 체크만 반대로
--- 넓히는 뜻이 되어 이웃과 어긋난다.
---
--- 오른쪽 위 x는 **템플릿이 이미 갖고 있다**(`WowDropdownFilterBehaviorMixin`). 우리가 줄 것은
--- "지금 기본값인가"와 "기본값으로 되돌려라" 둘뿐이고, 주문 선택 창이 같은 자리에서 같은 둘을
--- 준다.
local FILTER_MENU = {
	{ "activeSpec",   "FILTER_ACTIVE_SPEC"   },
	{ "inactiveSpec", "FILTER_INACTIVE_SPEC" },
	false,
	{ "keyed",        "FILTER_KEYED"         },
	{ "unkeyed",      "FILTER_UNKEYED"       },
	{ "pending",      "FILTER_PENDING"       },
};

function DebindFrameMixin:InitializeFilterDropdown()
	local dropdown = self.OverviewPanel.FilterDropdown;

	dropdown:SetupMenu(function(_, rootDescription)
		for _, entry in ipairs(FILTER_MENU) do
			if (not entry) then
				rootDescription:CreateDivider();
			else
				local name = entry[1];
				rootDescription:CreateCheckbox(LLL[entry[2]],
					function() return self:GetFilter(name); end,
					function() self:SetFilter(name, not self:GetFilter(name)); end);
			end
		end
	end);

	dropdown:SetIsDefaultCallback(function()
		return self:AreFiltersDefault();
	end);
	dropdown:SetDefaultCallback(function()
		self:ResetFilters();
	end);
end

--- 필터 값 하나를 켜고 끈다. 드롭다운의 체크 하나가 이 함수 하나에 대응한다.
---
--- **끄는 것을 막지 않는다.** 한 축의 값을 전부 끄면 목록이 빈다 - 아무 값도 안 받겠다고 한
--- 것이므로 그게 정직한 답이고, 블리자드 수집품 창도 같은 자리에서 막지 않는다. 되돌리는 길은
--- 드롭다운의 리셋 버튼이다.
function DebindFrameMixin:SetFilter(name, on)
	on = on and true or false;
	if (_filters[name] == on) then
		return;
	end
	_filters[name] = on;

	-- The same tidying that typing in the search box does, and the same one set for the two of
	-- them, for the reasons written there (`OnTextChanged`).
	local visible = NarrowedVisibleActions();
	self:PruneSelectionToBinFilter(visible);
	self.LayerPanel:Refresh(false, visible);
	self:Update();
end

function DebindFrameMixin:GetFilter(name)
	return _filters[name] == true;
end

--- 필터가 전부 기본값인가. 드롭다운의 리셋 버튼이 이걸 보고 스스로 뜨고 숨는다.
function DebindFrameMixin:AreFiltersDefault()
	for _, on in pairs(_filters) do
		if (not on) then
			return false;
		end
	end
	return true;
end

--- 전부 기본값으로. 리셋 버튼이 부른다.
function DebindFrameMixin:ResetFilters()
	if (self:AreFiltersDefault()) then
		return;
	end
	for name in pairs(_filters) do
		_filters[name] = true;
	end
	local visible = NarrowedVisibleActions();
	self:PruneSelectionToBinFilter(visible);
	self.LayerPanel:Refresh(false, visible);
	self:Update();
end

--- Whose keys the reader would be handing over: their own actions sitting on a key one of these
--- arrivals came in on.
---
--- **`arrivalID == nil` is what makes something an occupant.** A quarantined action holds a key
--- without occupying it (`BuildKeyMap` skips it), so a second arrival on the same key is not in
--- anyone's way and is not offered up here.
---
--- Answers the list and how many key groups it spans. The count is what the prompt says, because
--- what the reader loses on the overwrite answer is groups rather than actions: each of those comes
--- apart and nothing records which of its members went together (`ClearKeyForActions`).
local function OccupantsOfArrivals(arrivals)
	local keys, occupants, groups = {}, {}, 0;
	-- The keys both sides want, which is what the reader is answering about. Handed back so the
	-- answer can be applied to those keys and to no others.
	local contested = {};
	for i = 1, #arrivals do
		local key = arrivals[i].key;
		if (key ~= nil) then
			keys[key] = true;
		end
	end

	local seenGroup = {};
	for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
		for _, action in layer:Enumerate() do
			if (action.arrivalID == nil and action.key ~= nil and keys[action.key]) then
				occupants[#occupants + 1] = action;
				contested[action.key] = true;
				if (not seenGroup[action.key]) then
					seenGroup[action.key] = true;
					groups = groups + 1;
				end
			end
		end
	end
	return occupants, groups, contested;
end

--- Takes **every** badge left in the profile off. The second of the two presses the design note
--- calls the ordinary path.
---
--- **The ordinary end asks nothing.** A confirmation box on the ordinary end is what turns the badge
--- from a safeguard into homework, and how many are about to start working is on the button the menu
--- holding this item opened off (`IMPORT_PENDING`), which stands there for as long as the menu does.
---
--- **⚠ It asks when a key would be taken.** An arrival keeps the key it was sent on, so accepting
--- the lot puts those keys live -- and where the reader already uses one, something has to give.
--- Nothing used to: what arrived sat on a number the build skipped, so accepting could not reach a
--- key at all. That number is gone (`devdocs/building-export-import.md` 12절) and this question is
--- what stands in its place. **A free key still asks nothing**, which is the common case and the
--- reason the box is not on the ordinary end after all.
---
--- **It reaches what is not on screen** - `CollectArrivedActions` walks every layer. One entry
--- routinely splits across off-spec layers, so taking off only what is visible would leave the
--- rest quarantined somewhere no screen shows until the reader changes specialization.
function DebindFrameMixin:ApproveAllImported()
	local arrivals = DebindPrivate.CollectArrivedActions();
	if (#arrivals == 0) then
		return;
	end

	local occupants, groups, contested = OccupantsOfArrivals(arrivals);
	if (#occupants == 0) then
		ApproveArrivedActions(arrivals);
		return;
	end

	StaticPopup_Show("DEBIND_APPROVE_ALL_OCCUPIED", #arrivals, groups,
		{ arrivals = arrivals, occupants = occupants, contested = contested });
end

--- Throws back everything still waiting - the same set [Accept all] would take.
---
--- **It asks, and its twin does not.** Accepting is what importing is for, and the count in that
--- label is the whole of the warning it needs. This one removes N actions on one press, so it goes
--- through the prompt, which is also the only place the reader is told the way back
--- (`ShowRejectImportConfirmationPopup`).
function DebindFrameMixin:RejectAllImported()
	ShowRejectImportConfirmationPopup(DebindPrivate.CollectArrivedActions());
end

--- The menu the row above the columns opens, on either mouse button. **The two items are what the
--- two buttons there used to be**, and nothing else stands in it - what came in has exactly two
--- answers.
---
--- **It takes no target.** Both items collect the whole profile at the moment they are picked
--- (`ApproveAllImported` / `RejectAllImported`), so there is nothing to snapshot here and nothing
--- that can go stale while the menu is up. That is the opposite of the heading and bulk menus, which
--- read the rows the reader is looking at to decide whether their import items stand up at all.
---
--- `contextMenuAction` is left alone, the same as `ShowBulkDropdown` leaves it: it marks which row's
--- menu is open so that row can be highlighted, and this menu is not about a row.
function DebindFrameMixin:ShowPendingImportsDropdown(button)
	local menu = MenuUtil.CreateContextMenu(button, DebindUI.SetupPendingImportsDropdownMenu);
	self.contextMenu = menu;
	if (menu) then
		menu:SetClosedCallback(function()
			if (self.contextMenu ~= menu) then
				return;
			end
			self.contextMenu = nil;
			self:Update();
		end);
	end
	self:Update();
end


--- 블리자드 패널이 가운데나 전체를 차지하고 있으면 ESC는 그쪽 것이다.
---
--- 예전에는 물어볼 일이 없었다 - 우리 창이 UISpecialFrames에 있어서 area가 "center"/"full"인
--- 패널이 열리는 순간 이미 닫혔으니까. 이제는 거기서 빠졌으므로 공존하고, 여기서 안
--- 물러나면 마이크로 버튼으로 연 게임메뉴가 ESC로 안 닫힌다(우리 창이 키를 먼저 먹는다).
--- 게임메뉴는 `area="center"` 패널이다(UIPanelWindows.lua:4).
local function BlizzardOwnsEscape()
	-- **A dialog standing on top counts too, and it is not a UI panel** - `GetUIPanel` never sees a
	-- `StaticPopup`, so without this line the two above answer no while a question is on screen
	-- waiting to be answered. This window then eats that Escape, walks `HandleEscape` to the bottom
	-- and **closes itself**: the dialog stays up and the window behind it disappears, which is not
	-- what anybody pressed Escape for.
	--
	-- Stepping back is the whole fix. The game keeps its own handler for this
	-- (`RegisterGameMenuEscHandler` at `GameMenuEscPriority.Dialog` -> `StaticPopup_EscapePressed`),
	-- and that one reads each dialog's `hideOnEscape` - including other addons', which is the same
	-- reason this is asked about **any** dialog rather than about ours.
	return GetUIPanel("center") ~= nil or GetUIPanel("fullscreen") ~= nil
		or StaticPopup_IsAnyDialogShown();
end

--- What the window announces to the panels sitting in it.
---
--- **Blizzard's own registry, kept private to this frame.** `EventRegistry` is a global instance of
--- this very mixin, so nothing here is a machine of our own -- what was worth avoiding about the
--- global bus was the global, not the mixin (`devdocs/breaking-up-debindui.md`).
---
--- **A name not declared here raises where it is fired.** `GenerateCallbackEvents` turns each of
--- these into `DebindFrame.Event.<name>` and `SetUndefinedEventsAllowed` is off by default, so a
--- typo is an error at the call rather than a listener that never runs. That is the whole reason
--- this is worth more than a table of functions: the failure this replaces was silent.
---
--- **`TriggerEvent` does not promise an order.** Nothing may be registered here that needs to run
--- before or after another registrant.
--- **One name, because one thing listens.** The rest of C's list (`OnSelectionChanged`,
--- `OnFilterChanged`, and the four beside them) belongs to the overview's two columns and goes up
--- when those columns become files that register. Declaring them now would put six names on a bus
--- nothing rides, and a name nothing has ever fired is a name nothing has ever checked.
local FRAME_EVENTS = {
	--- The list of stored entries changed: one was made, taken in from a string, or deleted.
	---
	--- **Fired even when the storage tab did it itself**, so there is one path rather than a
	--- direct redraw for the near case and an event for the far one. The far one is the overview's
	--- key group menu, which makes an entry from a screen that is not the one that has to redraw.
	"OnStoreChanged",
};

function DebindFrameMixin:OnLoad()
	self.initialized = true;

	CallbackRegistryMixin.OnLoad(self);
	self:GenerateCallbackEvents(FRAME_EVENTS);

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
	---     [ADDON_ACTION_FORBIDDEN] AddOn 'Debind' tried to call 'SpellStopCasting()'
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

	-- The window's contents live in containers (`.zzz/main-frame-containers.md`). Two convenience
	-- references rather than an alias per widget; everything else goes through these.
	self.LayerPanel = self.OverviewPanel.LayerPanel;
	self.ResultPanel = self.OverviewPanel.ResultPanel;

	-- **The tab arrays split themselves now.** `PanelTabButtonTemplate` carries
	-- `parentArray="Tabs"` in its own definition (SharedUIPanelTemplates.xml), so anything
	-- inheriting it lands in **its parent's** array whatever the XML here says. The shared and
	-- character tabs are `LayerPanel`'s children and the window's own tab row is the window's, so
	-- the two sit in different arrays.
	--
	-- This used to be rewritten by hand as `self.Tabs = { self.Tab1, self.Tab2 }`. All of them
	-- were in one array, so `SetNumTabs` counted three and `AnchorTabs` dragged the odd one into
	-- the right-hand tab row. Splitting the parents made that line unnecessary.
	--
	-- What it costs instead: `PanelTemplates_*` takes `self.LayerPanel`, not the window - `.Tabs`
	-- and `.selectedTab` are over there now.
	for i, tab in ipairs(self.LayerPanel.Tabs) do
		tab:SetText(GetTabLabel(i));
		PanelTemplates_TabResize(tab, 0)
	end
	PanelTemplates_SetNumTabs(self.LayerPanel, #self.LayerPanel.Tabs);

	-- **여기서 한 번 고르지 않으면 탭이 안 칠해진다.** `PanelTabButtonTemplate`은 켜진 아트
	-- (LeftActive/Middle/Right)와 꺼진 아트(Left/Middle/Right)를 **둘 다 보이는 채로** 싣고
	-- 나온다 - 숨긴 것이 하나도 없다. 어느 쪽을 숨길지는 `PanelTemplates_UpdateTabs`가 정하는데,
	-- 그건 `frame.selectedTab`이 nil이면 통째로 돌아선다.
	--
	-- `SetTab`을 부르는 자리가 탭 클릭과 `GoToAction`뿐이라, 창을 열고 탭을 한 번도 안 누르면
	-- selectedTab이 nil인 채였다. 그래서 두 탭 다 아트 여섯 장이 겹쳐 깔린 금색 상자로 떴고,
	-- 켜진 탭이 어느 쪽인지도 화면에 없었다.
	PanelTemplates_SetTab(self.LayerPanel, _selectedTab);

	-- The window's own tab row. **A different array from the one above** (window vs `LayerPanel`) -
	-- the reasoning is in the XML. Labels and tooltips both come from `PANELS`, so all that is
	-- left here is standing them up.
	for i, tab in ipairs(self.Tabs) do
		tab:SetText(LLL[PANELS[i].title]);
		PanelTemplates_TabResize(tab, 0);
	end
	PanelTemplates_SetNumTabs(self, #self.Tabs);

	-- **Set once, never rewritten.** There is exactly one thing this panel ever says (see
	-- `ResolvePanel`), so it does not need the reason carried to it at the moment of failure.
	self.MissingPanel.Message:SetText(LLL["PANEL_ADDON_MISSING"]);

	-- **Overview names its width the same way the other panels do**, rather than the frame knowing
	-- one number. It is set here and not in the XML because the number is already a named constant
	-- with a paragraph of arithmetic behind it, and two copies of it is one too many.
	self.OverviewPanel.preferredWidth = FRAME_WIDTH;

	-- Start on Overview. `SelectPanel` turns back when the tab is already current, so this first
	-- one has to be forced through for `PanelTemplates_SetTab` to run and paint the tabs (the
	-- paragraph just above is why that matters). It is also what gives the frame its width.
	self.shownPanel = self.OverviewPanel;
	self:SelectPanel(OVERVIEW_PANEL, true);

	self.LayerPanel:InitializeScrollBox();
	self.LayerPanel:InitializeSideTabs();
	self:InitializeButtons();

	-- **The window hangs by its top left corner, and every path below goes through this.** Each
	-- tab names its own width (`SelectPanel`), and the frame is resized under whatever anchor it
	-- happens to be standing on. Anchored by its centre it keeps half of the width difference on
	-- each side, so changing tabs walks the window sideways.
	local function AnchorTopLeft(x, y)
		self:ClearAllPoints();
		self:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", x, y);
	end

	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", function()
		self:StartMoving();
	end);
	self:SetScript("OnDragStop", function()
		self:StopMovingOrSizing();
		self:SetUserPlaced(false);
		-- **`StartMoving` chooses the anchor, not us.** A window dropped near the middle of the
		-- screen comes back anchored by its centre, so saving the top left is not enough on its
		-- own: what was saved only described where the window was, and the anchor that keeps a
		-- tab change off the left edge lasted until the first drag. Reloading looked like a fix
		-- because the load path below is where that anchor was set.
		local x, y = self:GetLeft(), self:GetTop();
		AnchorTopLeft(x, y);
		DebindPrivate.db.global.ui.main = { x = x, y = y };
	end);

	DebindPrivate.db.global.ui = DebindPrivate.db.global.ui or {};
	local pos = DebindPrivate.db.global.ui.main;
	if (pos) then
		AnchorTopLeft(pos.x, pos.y);
	else
		-- Centred, written as the top left corner that centres it. `SetPoint("CENTER")` puts the
		-- window in the same place but leaves it hanging by the centre, so a window nobody has
		-- moved yet drifted on its first tab change. The width is already the one `SelectPanel`
		-- gave it a few lines up.
		AnchorTopLeft((UIParent:GetWidth() - self:GetWidth()) / 2,
			(UIParent:GetHeight() + self:GetHeight()) / 2);
	end
end

--------------------------------------------------------------------------------
-- 마이그레이션 안내창
--------------------------------------------------------------------------------

--- 3.0 이전에 저장된 설정을 아직 못 가져왔을 때 **로그인에서** 뜨는 창.
---
--- 메인 창과 별개인 이유는 XML에. 요약하면 업데이트한 사람은 애드온 창을 열 이유가 없고,
--- 그가 겪는 것은 "잘 되던 단축키가 안 먹는다"라서 창을 의심하지 않는다.
DebindMigrationDialogMixin = {};

function DebindMigrationDialogMixin:OnLoad()
	-- `BasicFrameTemplate`이라 초상화가 없다. 제목도 `SetTitle`이 아니라 `TitleText`다 -
	-- 그건 `TitledPanelMixin`이 붙는 초상화 계열 템플릿의 것이다.
	self.TitleText:SetText(LLL["MIGRATION_DIALOG_HEADER"]);
	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", function() self:StartMoving(); end);
	self:SetScript("OnDragStop", function() self:StopMovingOrSizing(); end);

	self.AcceptButton:SetText(LLL["MIGRATION_DIALOG_ENABLE"]);
	-- **권장이 하나뿐이라는 것을 색으로 말한다.** 버튼 셋이 모양이 같으면 셋 다 동등한
	-- 선택지로 읽히는데, 여기서는 아니다 - 나머지 둘은 되돌릴 수 없고 이건 잃는 게 없다.
	-- 본문에도 같은 색으로 "이게 맞는 답"이라고 적어뒀으므로 둘이 같이 읽힌다.
	self.AcceptButton:GetFontString():SetTextColor(GREEN_FONT_COLOR:GetRGB());
	self.DeclineCharButton:SetText(LLL["MIGRATION_DIALOG_DECLINE_CHARACTER"]);
	self.DeclineAccountButton:SetText(LLL["MIGRATION_DIALOG_DECLINE_ACCOUNT"]);

	self.AcceptButton:SetScript("OnClick", function()
		DebindPrivate.EnableLegacyAddonAndReload();
	end);
	self.DeclineCharButton:SetScript("OnClick", function()
		DebindPrivate.DeclineLegacyMigrationForCharacter();
		self:Hide();
	end);
	self.DeclineAccountButton:SetScript("OnClick", function()
		DebindPrivate.DeclineLegacyMigration();
		self:Hide();
	end);

	-- 툴팁은 **버튼 글자에 못 담는 것만** 말한다 - 되돌릴 수 없다는 사실, 옛 파일은 남는다는
	-- 사실, 어느 캐릭터까지 걸리는지. 글자를 풀어 쓰기만 하는 툴팁은 안 다느니만 못하다.
	local function attachTooltip(button, titleKey, bodyKey)
		button:SetScript("OnEnter", function()
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
			GameTooltip_SetTitle(GameTooltip, LLL[titleKey]);
			GameTooltip_AddNormalLine(GameTooltip, LLL[bodyKey]);
			GameTooltip:Show();
		end);
		button:SetScript("OnLeave", GameTooltip_Hide);
	end

	attachTooltip(self.AcceptButton, "MIGRATION_DIALOG_ENABLE", "MIGRATION_DIALOG_ENABLE_TOOLTIP");
	attachTooltip(self.DeclineCharButton, "MIGRATION_DIALOG_DECLINE_CHARACTER",
		"MIGRATION_DIALOG_DECLINE_CHARACTER_TOOLTIP");
	attachTooltip(self.DeclineAccountButton, "MIGRATION_DIALOG_DECLINE_ACCOUNT",
		"MIGRATION_DIALOG_DECLINE_ACCOUNT_TOOLTIP");
end

--- 두 상태를 가른다.
---
--- **계정 몫이 이미 넘어온 뒤라면 공유 바인딩은 지금 동작 중이다.** 그 사람은 대부분의 키가
--- 멀쩡한 것을 보면서 이 창을 읽으므로, "설정을 못 읽는다"고 뭉뚱그리면 눈앞의 사실과
--- 어긋난다 - 그러면 창이 무엇을 말하는지가 아니라 창을 믿을지가 문제가 된다.
--- 그때 실제로 없는 것은 이 캐릭터 전용 레이어와 `CustomTargets`뿐이다.
---
--- `legacyNeeded`가 아직 nil이면 우리도 아는 게 없으므로 일반 문구로 간다.
function DebindMigrationDialogMixin:UpdateText()
    local accountResolved = DebindPrivate.IsLegacyAccountResolved();
    local missing = DebindPrivate.legacyLoadFailure == "MISSING";

    if (missing) then
        -- 폴더가 아예 없다. **켜기 버튼이 할 수 있는 게 없다** - `EnableAddOn`은 없는 애드온에
        -- 아무 일도 안 하고, 리로드하면 같은 창으로 돌아온다. 그래서 숨기고 다시 받으라고 한다.
        self.Title:SetText(LLL["MIGRATION_DIALOG_TITLE_MISSING"]);
        self.Body:SetText(LLL["MIGRATION_DIALOG_BODY_MISSING"]);
    elseif (accountResolved) then
        self.Title:SetText(LLL["MIGRATION_DIALOG_TITLE_CHARACTER_ONLY"]);
        self.Body:SetText(LLL["MIGRATION_DIALOG_BODY_CHARACTER_ONLY"]);
    else
        self.Title:SetText(LLL["MIGRATION_DIALOG_TITLE"]);
        self.Body:SetText(LLL["MIGRATION_DIALOG_BODY"]);
    end

    self.AcceptButton:SetShown(not missing);

    -- **"이 캐릭터만"은 계정 질문이 끝난 뒤에만 답이 된다.** 아직 `nil`이면 그 답이 계정 몫을
    -- 미결로 둔 채 창을 열어주고, 그러면 사용자가 만든 공유 바인딩을 나중에 다른 캐릭터의
    -- 인수가 덮는다. 미결일 때 고를 수 있는 것은 "켠다"와 "전부 안 가져온다" 둘뿐이다.
    self.DeclineCharButton:SetShown(accountResolved);

    -- **버튼을 바닥에서부터 쌓는다.** XML의 앵커는 셋이 다 있을 때의 사슬이라, 하나를 숨기면
    -- 그 자리가 빈 채로 남는다(숨은 프레임도 위치는 그대로다). 보이는 것만 다시 건다.
    local BOTTOM_PAD, BUTTON_GAP = 16, 8;
    local y = BOTTOM_PAD;
    local stack = { self.DeclineAccountButton, self.DeclineCharButton, self.AcceptButton };
    for _, button in ipairs(stack) do
        if (button:IsShown()) then
            button:ClearAllPoints();
            button:SetPoint("BOTTOM", 0, y);
            y = y + button:GetHeight() + BUTTON_GAP;
        end
    end

    -- **높이를 글에 맞춘다.** 본문 셋의 길이가 다르고, 로케일마다 또 다르고, 폭이 같아도 줄
    -- 수가 달라진다. 고정 높이로 두면 긴 쪽이 버튼 위로 겹치거나 창 밖으로 나간다 - 스크롤은
    -- 없다(한 번 읽고 답하는 창이라 스크롤이 생기면 그게 더 나쁘다).
    --
    -- `GetStringHeight`는 텍스트를 넣은 **뒤에** 물어야 값이 나온다. TOP_PAD와 GAP은 XML에서
    -- Title이 TOP -38, Body가 Title 아래 -14인 것과 같은 값이다.
    local TOP_PAD, GAP = 38, 14;
    self:SetHeight(TOP_PAD + self.Title:GetStringHeight() + GAP + self.Body:GetStringHeight()
        + GAP + (y - BUTTON_GAP));
end

--- 미결일 때만 띄운다. 로그인과 `ToggleUI` 양쪽에서 부른다.
---
--- **닫기는 답이 아니다.** 세 버튼만 상태를 남기고, 그냥 닫으면 다음 로그인에 다시 온다 -
--- 지금 답하고 싶지 않은 사람에게 유일하게 영구가 아닌 선택지다.
function DebindPrivate.ShowMigrationDialogIfPending()
	if (not DebindPrivate.IsLegacyPending()) then
		return false;
	end
	-- 띄울 때마다 다시 고른다. 다른 캐릭터가 그 사이 계정 몫을 가져왔을 수 있고, 그러면
	-- 이 창이 할 말이 달라진다.
	DebindMigrationDialog:UpdateText();
	DebindMigrationDialog:Show();
	return true;
end


function DebindFrameMixin:OnShow()
	if (not self.initialized) then
		self:OnLoad();
	end

	self.LayerPanel:Refresh();
	-- **`Update`까지 와야 왼쪽 열이 그려진다.** `Refresh`는 오른쪽 목록만 다시 짓고, 왼쪽은
	-- 선택이 아니라 프로필 전체를 보므로 여기서 같이 깨워야 한다. 예전에는 선택이 없으면
	-- 왼쪽이 접혀 있어서 이 줄이 없어도 티가 안 났다.
	self:Update();
	self.LayerPanel:UpdateSideTabs();
	self:RegisterEvent("PLAYER_REGEN_DISABLED");
	self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
	self:RegisterEvent("CURSOR_CHANGED");

	DebindPrivate.RegisterCallback(self, "OnBindingsUpdated");

	local type, value = GetActionTypeAndValueFromCursorInfo();
	if (type) then
		_pickedupInfo = { type = type, value = value };
		self:OnPickup();
	end
end

function DebindFrameMixin:OnHide()
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE);

	HideDeleteConfirmationPopup();

	-- 주문 선택 창의 수명은 여기 묶여 있다. X 버튼도, ESC도, 전투 진입(OnEnterCombat이
	-- self:Hide()로 끝난다)도 전부 이 경로로 오므로 한 줄이 셋을 다 덮는다.
	-- 반대 방향은 없다 - 그 창을 닫아도 이 창은 남는다.
	DebindSpellPickerFrame:Hide();

	-- **The sharing window is not on this line.** It is opened from here but it is a window of its
	-- own: nothing it does needs this one to be up, and closing the thing you exported from should
	-- not take the string you were about to copy with it. It handles its own ESC through
	-- `UISpecialFrames` and closes on its own X.

	-- The icon selector is not a child of this window (see its frame comment in DebindUI.xml for
	-- why), so this line is the only thing that takes it down with us. Without it the main window
	-- vanishes and the popup stays on screen.
	--
	-- This line predates that, and back when it was a child it earned its place differently: a
	-- hidden parent only stopped the drawing while IsShown() stayed true. The popup's OnHide
	-- cleared onAccepted in that window, reopening brought the popup straight back (New mode has
	-- no OnShow guard), and confirming there produced a nameless, bodyless action with no editor.
	--
	-- 전투 진입은 `OnEnterCombat`이 따로 취소하고 있었지만, 게임 메뉴가 열려서 이 창이
	-- 숨는 길(`GameMenuFrame.Shown`)은 그 자리를 지나지 않는다. 여기서 한 번에 덮는다.
	DebindIconSelectorFrame:Close(true);

	-- 창이 닫히는 것도 "떠나는" 것이다. 기본 매크로 창의 OnHide와 같이, 편집 중이던
	-- 매크로 본문은 여기서 저장된다.
	-- The macro editor is not our child either, so this line is the only thing that closes it -
	-- and closing it is what saves.
	DebindMacroFrame:Close();
	DebindResultPanel:Close();

	if (self.iconDataProvider) ~= nil then
		self.iconDataProvider:Release();
		self.iconDataProvider = nil;
	end

	self:UnregisterEvent("PLAYER_REGEN_DISABLED");
	self:UnregisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
	self:UnregisterEvent("CURSOR_CHANGED");
	self:UnregisterEvent("GLOBAL_MOUSE_DOWN");

	DebindPrivate.UnregisterCallback(self, "OnBindingsUpdated");

	_pickedupInfo = nil;
	-- 글로우는 위 상태를 보고 켜지는데, 그걸 지웠다고 저절로 꺼지지는 않는다. 여기서
	-- 안 끄면 다음에 창을 열 때 목록이 빛나고 있다 - 창을 닫는 것도, 전투에 끌려들어가는
	-- 것도 커서에 뭘 든 채로 일어난다.
	self:UpdateDropHighlight();
	DebindUI.ClearMacrotextIconCache();
end

function DebindFrameMixin:OnEvent(event, arg1)
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
		self.LayerPanel:UpdateSideTabs();
	end
end

--- ESC 한 번에 한 칸씩 물러난다. 소비했으면 true.
---
--- 부르는 곳은 아래 OnKeyDown 하나뿐인데 따로 빼둔 건 **이 순서가 이 창의 계약**이기
--- 때문이다 - 전파 처리와 섞여 있으면 어느 줄이 순서고 어느 줄이 키 배관인지 안 보인다.
function DebindFrameMixin:HandleEscape()
	if (GetActionTypeAndValueFromCursorInfo()) then
		self:ClearMouse();
		return true;
	end

	-- 키를 듣는 중이면 그것부터 그만둔다.
	--
	-- 보통은 여기까지 안 온다 - 듣는 중에는 버튼이 마우스 위치와 무관하게 키를 먼저
	-- 받고 전파를 끊는다. 그래도 남겨두는 건 **물러나는 순서** 때문이다. 이 갈래가
	-- 없으면 어쩌다 여기로 온 ESC가 아래 선택 해제로 내려가서, 한 번 누른 것이
	-- 캡처를 끝내고 패널까지 접는다.
	--
	-- **되돌리는 쪽으로 나간다.** 한때 여기서 `CancelKeyCapture`를 불렀는데, 그 길은
	-- `SetBindingMode(false)`로 곧장 가는 **커밋**이다(그쪽 주석 참고). 지정 모드에서 ESC의
	-- 뜻은 `BindMode_OnKeyDown`이 정해놨고 그건 취소다 - 폴백이 본래 경로와 반대로 동작하면
	-- 그건 폴백이 아니다. 되돌리기는 되돌릴 수 없으므로 틀린 쪽이 더 비싸다.
	if (DebindFrame:IsCapturingKey()) then
		DebindFrame:CancelBindMode();
		return true;
	end

	-- 아이콘 선택기가 떠 있으면 그것부터 물러난다. 팝업이니 자기 ESC를 자기가 처리할
	-- 것 같지만 아니다 - IconSelectorPopupFrameTemplate은 키보드를 켜지도, ESC를
	-- 받지도, UISpecialFrames에 들지도 않는다. 그래서 여기서 안 세우면 팝업을 띄워둔
	-- 채로 선택이 풀리고, 한 번 더 누르면 팝업만 남기고 창이 닫힌다.
	if (DebindIconSelectorFrame:IsShown()) then
		DebindIconSelectorFrame:Close();
		return true;
	end

	-- 매크로 편집 창. It takes no keys of its own and is not in `UISpecialFrames` either, so without
	-- this rung ESC walked straight past it to `self:Hide()` at the bottom - one press meaning
	-- "close the editor" took the whole window down with it.
	--
	-- **Below the icon selector and above the spell picker**, which is the order the three open in:
	-- the picker's [New Custom Macro] opens the icon selector, and confirming there opens this
	-- editor. The picker stays up behind both on purpose (`AddNewAction`).
	--
	-- The body survives the press, since closing this window is what commits it. That is not what
	-- ESC means on the rungs around it, and it is not meant to be: this window holds nothing a press
	-- could be asked to discard, and [Cancel] inside it is the one thing that puts text back.
	--
	-- 편집칸에 포커스가 있으면 첫 ESC는 포커스만 푼다(`OnEscapePressed`). 여기까지는 그 다음
	-- 누름이 온다.
	if (DebindMacroFrame:IsShown()) then
		DebindMacroFrame:Close();
		return true;
	end

	-- 주문 선택 창도 여기서 닫는다. 그 창이 스스로 ESC를 처리하지 **못한다** - 그 창이
	-- 열려 있는 동안은 이 창도 반드시 열려 있고(수명이 묶여 있다), 이 사다리가 먼저 돈다.
	-- 저쪽을 UISpecialFrames에 넣어도 닿지 않는 자리라 계획서와 달리 사다리 한 칸으로 넣었다.
	if (DebindSpellPickerFrame:IsShown()) then
		DebindSpellPickerFrame:Hide();
		return true;
	end

	-- **The two sharing dialogs.** They are in `UISpecialFrames` as well (`InitDialog`), but that
	-- table is only read by `CloseSpecialWindows`, which the ESCAPE **binding** calls. This window
	-- gets ESCAPE first and neither of them enables the keyboard, so `BlizzardOwnsEscape` does not
	-- stand aside for them and the binding never runs. Take these rungs away and one press hides
	-- this window while the dialog stays up over nothing. The registration is still what closes
	-- them when this window is already gone, which the copy dialog is built to outlive
	-- (`DebindStoragePanelMixin:OnHide`).
	--
	-- **Two rungs and not one.** ESC is one step back. One rung would either close both, which is
	-- two windows for one press, or pick one anyway, and picking is what an ordered ladder already
	-- is.
	--
	-- **The order is how wide the gesture that opened it was**, which is also which of any two
	-- standing together is the newer. Paste comes off the tab's own button, and the copy dialog is a
	-- finished string the reader keeps: it is the one that survives leaving its tab, so it is the
	-- older half of every pair that can stand at once (a leftover copy dialog under a paste dialog,
	-- or under the spell picker two rungs above). Last is where ESC does not take away the string
	-- somebody was about to paste.
	--
	-- **There were three.** The bring dialog asked which layers to take, and the tick moved onto the
	-- action when the preview column arrived -- there is nothing left for it to ask
	-- (`devdocs/building-export-import.md` 12절).
	if (DebindPasteFrame:IsShown()) then
		DebindPasteFrame:Hide();
		return true;
	end

	if (DebindCopyFrame:IsShown()) then
		DebindCopyFrame:Hide();
		return true;
	end

	-- **선택 해제 칸은 없다.** 한때 여기서 ESC 한 번이 선택을 풀었는데, 그건 선택이 상세
	-- 패널을 펴고 접던 시절의 칸이다 - 물러날 화면이 실제로 있었다. 지금 선택이 하는 일은
	-- 행 강조와 왼쪽 열이 짚는 자리뿐이라, 그 칸은 **창을 닫으려는 ESC를 한 번 먹기만 한다.**
	self:Hide();
	return true;
end

--- ESC가 들어오는 유일한 자리. 블리자드 쪽에 아무것도 등록하지 않는 대가로 전파를 손수
--- 여닫는다(OnLoad 참고).
function DebindFrameMixin:OnKeyDown(input)
	-- 전투 중 `SetPropagateKeyboardInput`은 taint다. 전투에 들어가면 `OnEnterCombat`이 창을
	-- 숨기므로 보통은 여기까지 오지 않지만, **전투가 시작된 그 프레임에 눌린 키는
	-- PLAYER_REGEN_DISABLED보다 먼저 들어올 수 있다.** `BindMode_OnKeyDown`이 막는 것과
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

function DebindFrameMixin:OnEnterCombat()
	-- 캡처 중이면 접는다. 전투 중에는 SetPropagateKeyboardInput이 taint라 키를 받을 수 없다.
	-- 선택은 그대로 둔다 - 전투가 끝나고 창이 다시 뜨면 보던 액션이 그대로 있어야 한다.
	DebindFrame:CancelKeyCapture();

	if (DebindIconSelectorFrame:IsShown()) then
		DebindIconSelectorFrame:CancelButton_OnClick();
	end

	-- 매크로 본문은 아래 Hide()가 OnHide를 태우면서 저장된다.

	self:RegisterEvent("PLAYER_REGEN_ENABLED");
	self:Hide();
end

function DebindFrameMixin:OnLeaveCombat()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED");
	self:Show();
end

--- 목록은 키순으로 묶여 있으므로 키가 바뀌면 **다시 짜야** 한다. Update는 있는 줄을 그
--- 자리에서 고쳐 그릴 뿐이라, 우클릭 메뉴로 단축키를 푼 액션이 여전히 옛 키 헤더 밑에
--- 키 없이 앉아 있게 된다. 오버뷰 탭에서는 그 액션이 목록에서 통째로 빠져야 하므로 더 그렇다.
--- 스크롤 자리는 지킨다 - 방금 만진 줄이 눈앞에서 사라지면 안 된다.
function DebindFrameMixin:OnBindingsUpdated(_, skipped)
	self.LayerPanel:Refresh(true);
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
-- 그래서 이 목록은 **언제나 이름순**이다. 목록 어디에도 "위에 있는 게 먼저 나간다"가 없다.
-- 발동 순서를 말하는 자리는 왼쪽 열 하나뿐이고, 거기는 키로 묶여 있다.
local function CompareByName(lhs, rhs)
	if (lhs.sortName ~= rhs.sortName) then
		return lhs.sortName < rhs.sortName;
	end
	-- 이름이 같은 줄은 실재한다(같은 주문을 조건만 달리해 두 번 넣는 것이 정상이다).
	-- table.sort는 불안정하므로 여기서 받쳐주지 않으면 새로 그릴 때마다 자리가 바뀐다.
	return lhs.index < rhs.index;
end

--- 이 레이어의 액션을 이름순으로 놓는다. 검색어가 있으면 거른다.
---
--- **`index`는 거르기 전의 자리다.** `MoveAction`이 같은 레이어 안에서 복사할 때 넣을 자리로
--- 쓰는 값이라(`elementData.index + 1`) 화면에 몇 번째로 보이는지와는 상관이 없다.
---
--- **여기는 선택을 안 본다. 목록은 (레이어, 검색어)만의 함수다.**
---
--- 한때 검색어에 안 맞는 앵커를 흐리게 남겼다 - 왼쪽이 짚는 행은 오른쪽에 반드시 있어야
--- 한다고 봤기 때문이다. 그러면 **목록의 내용이 선택 상태에 묶인다.** 앵커는 목록이 지어진
--- **뒤에** 옮겨가는 경로가 있어서(`GoToAction`: `SetTab`→`Refresh`→`SetSelectedAction`)
--- 화면이 한 클릭씩 밀렸고, 앵커가 딴 데로 가도 옛 흐린 줄이 남았다.
---
--- 대신 검색어를 자동으로 비우는 것도 안 한다. 걸러진 행은 **그냥 안 보인다.** 사용자가 친
--- 검색어가 사용자 몰래 지워지는 것보다, 지금 거르고 있는 중이라 안 보이는 편이 설명이 쉽다 -
--- 검색창이 화면에 그대로 있으므로 왜 없는지가 이미 적혀 있다.
--- 이 레이어에서 오른쪽 목록에 설 것들.
---
--- **왼쪽 열에 서는 것 ∩ 이 레이어**, 그 이상은 없다. 오른쪽에 자기 필터를 따로 두면 한 창에
--- 좁히는 상태가 둘이 되고, 어느 쪽이 무엇을 감췄는지 화면이 대답하지 못한다.
---
--- 그래서 이쪽은 그룹을 모른다 - 왼쪽이 그룹째 판정한 결과가 액션 집합으로 넘어오고, 여기서는
--- 담겨 있나만 본다.
local function BuildSortedElements(layer, layerID, visible)
	local elements = {};
	for i, action in layer:Enumerate() do
		if (visible == nil or visible[action]) then
			elements[#elements + 1] = {
				action = action,
				layer = layerID,
				index = i,
				sortName = strlower(NameAndIconForAction(action) or ""),
			};
		end
	end

	sort(elements, CompareByName);
	return elements;
end

function DebindLayerPanelMixin:Refresh(retainScrollPosition, visible)
	HideDeleteConfirmationPopup();

	-- Built here for the two below it that filter by the same set, which is the whole of this
	-- update unless the caller was already holding one (`NarrowedVisibleActions`).
	visible = visible or NarrowedVisibleActions();

	local dataProvider = CreateDataProvider();
	local layerID = GetLayerID();
	local elements = BuildSortedElements(DebindPrivate.GetProfileLayer(layerID), layerID, visible);

	local selectedIsDrawn = false;
	for _, elementData in ipairs(elements) do
		if (elementData.action == _selectedAction) then
			selectedIsDrawn = true;
		end
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
	if (_selectedAction and not DebindPrivate.FindLayerID(_selectedAction)) then
		self:SetSelectedAction(nil);
	end

	-- **선택은 남아도 편집 창은 닫는다.** 검색어나 필터가 걸리면 고치던 행이 통에서 사라지는데,
	-- 위 규칙대로 선택은 그대로다. 그러면 화면 어디에도 없는 액션 위에 편집 창만 떠 있고,
	-- 무엇을 고치는 중인지 가리켜 줄 행이 없다.
	--
	-- 닫는 것이 곧 저장이다(`DebindMacroFrameMixin`). 이 길로 사라지는 본문은 없다.
	--
	-- The popup goes first, and only when it is standing on this same action: it is also the window
	-- [New Custom Macro] opens, and that one runs with no selection behind it at all.
	if (_selectedAction and not selectedIsDrawn) then
		if (DebindIconSelectorFrame.editAction == _selectedAction) then
			DebindIconSelectorFrame:Close(true);
		end
		DebindMacroFrame:Close();
	end

	-- **제목은 창의 이름이다. 탭 좌표가 아니다.**
	--
	-- 한때 "Debind [공유 - 일반]"처럼 지금 보는 탭을 낱말로 다시 말했다. 그 좌표는 이미
	-- 화면에 두 번 있다 - 통 아래의 탭과 오른쪽의 사이드탭이 각자 켜진 채로 서 있다.
	-- 세 번째로 적으면서 얻는 것은 없고, 탭을 누를 때마다 창 이름이 바뀌어서 **같은 창이
	-- 아닌 것처럼** 보이는 값은 치른다.
	-- The version hangs off the name for the same reason it is on the login line: so a bug report
	-- can carry it. Dimmed, because it is there to be found rather than read every time.
	DebindFrame:SetTitle(format("%s |cff9d9d9d%s|r", LLL["ADDON_NAME"], DebindPrivate.GetVersionLabel()));
	self:UpdateActionCounts(visible);
	DebindFrame:UpdateEmptyText();
end

--- 상세 패널이 보여줄 액션을 바꾼다. 언제나 성공한다.
---
--- 예전에는 패널이 저장 안 된 변경을 들고 거부할 수 있어서 false와 force가 있었다. 지금
--- 패널에는 미루는 저장이 없으므로(Close 참고) 거부할 일이 없다. 돌려주는 true는 부르는
--- 쪽의 옛 코드를 위해 남긴 것이다.
--- 집합이나 앵커를 손본 뒤 **반드시** 지나는 자리.
---
--- **다중이 되면 매크로 창을 닫는다.** 그 창은 본문 하나를 여는 편집기라 대상이 여럿이면
--- 열려 있을 자리가 없다. 본문은 `Close`가 저장한다. 앵커가 그대로면 `Refresh`는 창을
--- 안 건드리므로, CTRL-클릭으로 벌크를 시작하는 자리는 이 줄이 따로 챙겨야 한다.
---
--- 한 번 닫히면 다중인 동안 다시 안 열린다 - `Refresh`가 `IsShown()`에서 먼저 돌아선다.
local function CommitSelection()
	-- 왼쪽 열을 여기서 따로 다시 그리지 않는다. **맨 아래 `Update`가 이미 그 일을 한다**
	-- (`DebindResultPanel:Refresh`). 둘 다 부르면 선택이 한 번 달라질 때마다 키보드
	-- 전체를 두 번 짓는다 - 그 함수는 프로필의 모든 레이어를 훑어 키로 묶는 자리다.
	DebindResultPanel:Close();

	if (_selectionCount > 1) then
		DebindMacroFrame:Close();
	else
		-- If the macro editor is open on some other action, this is what closes it - Refresh
		-- does not carry the window over to a new target any more, it leaves. Same action, or
		-- window already closed, and nothing happens.
		DebindMacroFrame:Refresh();
	end

	DebindFrame:Update();
end

--- **선택을 이 액션 하나로 접고 앵커를 거기 둔다.** nil이면 아무것도 안 고른 상태다.
---
--- 벌크가 생기기 전부터 있던 입구라 부르는 데가 많다(탭 전환, 지정 모드, `GoToAction`,
--- 액션이 사라졌을 때). 전부 "이제 이것 하나다"라는 뜻이므로 집합도 여기서 같이 접는다 -
--- 저쪽들이 집합을 따로 챙기게 만들면 한 군데는 반드시 빠진다.
function DebindLayerPanelMixin:SetSelectedAction(action)
	-- **앵커가 같아도 집합이 여럿이면 접어야 한다.** 벌크로 셋을 고른 뒤 그중 앵커 행을 다시
	-- 좌클릭하는 것이 정확히 그 경우다. 앵커만 보고 돌아서면 나머지 둘이 고른 채로 남는다.
	--
	-- 집합에 앵커가 들어 있는지도 같이 본다 - CTRL-클릭으로 앵커 행을 집합에서 빼면 개수가
	-- 1인데 그 하나가 앵커가 아닌 상태가 된다.
	if (action) then
		if (_selectedAction == action and _selectionCount == 1 and _selection[action]) then
			-- **고를 것은 없어도 보여줄 것은 있다.** 이미 고른 행을 다시 누르는 것은 "그거
			-- 어디 갔지"라는 뜻이다 - 그 사이 왼쪽 열을 굴려놨거나 그룹을 접어놨으면 화면에
			-- 없고, 선택이 그대로라는 이유로 아무 일도 안 하면 누른 쪽에는 고장으로 보인다.
			--
			-- 목록을 다시 짓는 것은 접혀 있을 때 펼쳐야 하기 때문이다(`RefreshKeyboard`가
			-- 짓기 전에 편다). 이미 펴져 있으면 지은 결과가 같으므로 화면은 스크롤만 한다.
			_revealAction = action;
			DebindResultPanel:Refresh();
			return true;
		end
	elseif (_selectedAction == nil and _selectionCount == 0) then
		return true;
	end

	wipe(_selection);
	_selectionCount = 0;
	if (action) then
		_selection[action] = true;
		_selectionCount = 1;
	end
	_selectedAction = action;

	-- 오른쪽에서 고른 행을 왼쪽 열에서 찾아준다. 위 가드를 지나왔으므로 여기 오는 것은 선택이
	-- **바뀐** 경우뿐이고, 같은 행을 다시 고르면 화면은 가만히 있는다.
	_revealAction = action;

	CommitSelection();
	return true;
end

function DebindFrameMixin:GetSelectedAction()
	return _selectedAction;
end

--- 이 액션이 벌크 대상인가. 오른쪽 목록의 강조가 이걸 본다(앵커가 아니다).
function DebindFrameMixin:IsActionSelected(action)
	return _selection[action] == true;
end

function DebindFrameMixin:GetSelectionCount()
	return _selectionCount;
end

--- 벌크 대상을 **목록에 보이는 순서대로** 돌려준다.
---
--- 집합은 해시라 순서가 없는데, 이동·복사가 목적지 맨 뒤에 차례로 붙이므로(`MoveAction`)
--- 넘기는 순서가 그대로 결과가 된다. 해시 순서로 넘기면 방금 화면에서 고른 차례와 다르게
--- 쌓이고, 그건 매번 다르기까지 하다.
function DebindFrameMixin:GetSelectedActions()
	local actions = {};
	if (_selectionCount == 0 or not self.LayerPanel.dataProvider) then
		return actions;
	end

	for _, elementData in self.LayerPanel.dataProvider:EnumerateEntireRange() do
		if (_selection[elementData.action]) then
			actions[#actions + 1] = elementData.action;
		end
	end
	return actions;
end

--- Drops out of the bulk set whatever the bin no longer shows. Called only when what the bin is
--- narrowed by changes - the search text, or [Only what came in].
---
--- Bulk can only touch **what is on screen**. That is the same rule as the right-click contract
--- ("a menu opened on one row must not delete things that are not visible"), and it is also what
--- keeps the count from lying.
function DebindFrameMixin:PruneSelectionToBinFilter(visible)
	if (_selectionCount == 0) then
		return;
	end

	visible = visible or NarrowedVisibleActions();
	if (visible == nil) then
		return;
	end

	for action in pairs(_selection) do
		if (not visible[action]) then
			_selection[action] = nil;
			_selectionCount = _selectionCount - 1;
		end
	end
end

--- CTRL-좌클릭. 그 행 하나를 집합에 넣거나 뺀다.
---
--- **뺐을 때도 앵커는 그 행으로 간다.** 앵커는 "마지막으로 누른 행"이지 "고른 행"이 아니고,
--- 그래야 SHIFT가 재는 기준점이 방금 누른 자리에 있다.
function DebindLayerPanelMixin:ToggleActionSelected(action)
	if (not action) then
		return;
	end

	if (_selection[action]) then
		_selection[action] = nil;
		_selectionCount = _selectionCount - 1;
	else
		_selection[action] = true;
		_selectionCount = _selectionCount + 1;
	end
	_selectedAction = action;

	CommitSelection();
end

--- SHIFT-좌클릭. 앵커부터 이 행까지를 집합으로 삼는다.
---
--- **앵커는 안 옮긴다.** 그래야 범위를 다시 잴 수 있다 - SHIFT를 한 번 더 찍으면 같은
--- 기준점에서 새로 재므로 늘리는 것만이 아니라 줄이는 것도 된다(위 `_selectedAction` 주석).
---
--- `additive`(CTRL+SHIFT)면 앞서 고른 것을 그대로 두고 이 범위를 **더한다.** CTRL로 새 묶음의
--- 첫 행을 찍으면 앵커가 거기로 가므로, 이어서 CTRL+SHIFT로 그 묶음만 늘릴 수 있다 - 떨어져
--- 있는 덩어리 여럿을 한 집합에 담는 길이다. 없으면 행마다 CTRL을 눌러야 한다.
---
--- 앵커가 없거나 지금 목록에 없으면 그냥 하나만 고른다. 후자는 실재한다 - 앵커는 액션으로
--- 들고 있어서 탭이 바뀌어도 살아 있는데, 그 액션은 다른 레이어에 있으므로 여기서는 범위를
--- 잴 자리가 없다.
function DebindLayerPanelMixin:SelectRangeTo(action, additive)
	if (not action or not self.dataProvider) then
		return;
	end

	local _, anchorIndex = self:FindElementDataByActionInfo(_selectedAction);
	local _, targetIndex = self:FindElementDataByActionInfo(action);
	if (not anchorIndex or not targetIndex) then
		return self:SetSelectedAction(action);
	end

	if (anchorIndex > targetIndex) then
		anchorIndex, targetIndex = targetIndex, anchorIndex;
	end

	if (not additive) then
		wipe(_selection);
		_selectionCount = 0;
	end
	for i = anchorIndex, targetIndex do
		local elementData = self.dataProvider:Find(i);
		if (elementData and elementData.action and not _selection[elementData.action]) then
			_selection[elementData.action] = true;
			_selectionCount = _selectionCount + 1;
		end
	end

	CommitSelection();
end

function DebindLayerPanelMixin:FindElementDataByActionInfo(action)
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
---
--- **액션을 화면에 보이게 하는 자리는 여기 하나뿐이다.** ScrollBox의 기본 정렬은
--- AlignCenter라, 스크롤 함수를 직접 부르면 정렬을 안 넘긴 것만으로 이미 보이는 행까지
--- 화면 한가운데로 끌어온다. 보이는 행을 옮기는 것은 사용자가 보던 자리를 빼앗는 일이고,
--- 어느 행인지는 강조가 이미 말한다.
---
--- 찾은 elementData를 돌려준다 - 부르는 쪽이 그 행을 또 찾지 않아도 되게.
function DebindLayerPanelMixin:ScrollActionIntoView(action)
	local elementData, index = self:FindElementDataByActionInfo(action);
	if (not elementData) then
		return;
	end

	-- AlignNearest. 보이면 그대로 두고, 벗어난 쪽으로만 딱 그만큼 움직인다.
	self.ScrollBox:ScrollToNearest(index);
	return elementData;
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
function DebindFrameMixin:GoToAction(action, layerID)
	if (not TryCloseAnyDialog()) then
		return;
	end

	local tab, sideTab = GetLayerTabs(layerID);
	-- 사이드탭을 **먼저** 넣는다. SetTab이 사이드탭 갱신과 Refresh까지 하는데, 그 안의
	-- "안 보이는 사이드탭이면 1로" 가드가 새 좌표를 보고 판단해야 한다.
	_selectedSideTab = sideTab;
	self:SetTab(tab);

	-- **지정 모드 중에는 안 고른다.** 그 모드에서 선택은 비어 있어야 한다 - 대상은 커서 밑의
	-- 행이라, 강조가 남아 있으면 그것이 가리키는 것과 실제로 키가 걸릴 곳이 어긋난다
	-- (SetBindingMode가 켤 때 선택을 비우는 것과 같은 이유다).
	--
	-- 여기서 막는 이유는 이 함수가 **유일한 통로**이기 때문이다. 탭에 떨구든 지금 탭에
	-- 떨구든 전부 여기를 지나므로, 두 경우를 따로 적을 필요가 없다.
	--
	-- 옮기고 보여주는 것은 그대로 한다. 넣은 것이 어디로 갔는지는 모드와 상관없이 보여야 한다.
	if (not self:IsCapturingKey()) then
		self.LayerPanel:SetSelectedAction(action);
	end

	self.LayerPanel:ScrollActionIntoView(action);
end

--- `destLayerID` is the picker's right-click menu naming a tab. Without it the action is born in
--- the tab that is open, which is what every other way in here does.
function DebindFrameMixin:AddNewAction(type, value, name, icon, props, destLayerID)
	PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP);

	-- **Back to Overview first, if we are not there.** Everything below lands in the Overview
	-- panel - the list, the selection, the scroll - so from Import or Export the action would go
	-- in and nothing on screen would move. That is the same failure the `GoToAction` call further
	-- down exists to prevent, one rank up: there it is the wrong layer tab, here the wrong window
	-- tab, and in both cases picking a destination is saying "put it there".
	--
	-- It is reachable because the picker outlives the tab that opened it. `[+]` lives inside
	-- `OverviewPanel` and hides with it, so there is no way to *open* the picker from another tab -
	-- but one already up keeps working, and that is on purpose (it is the one dialog deliberately
	-- left out of the lock list, because its whole use is staying open while you move around).
	if (_selectedPanel ~= OVERVIEW_PANEL) then
		self:SelectPanel(OVERVIEW_PANEL);
	end

	local layerID = destLayerID or GetLayerID();
	local layer = DebindPrivate.GetProfileLayer(layerID);
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
	-- A new action goes through the same ordering rule as anything else. The ones that arrive here
	-- are born without a key and so get no number (`SetActionKey` hands one out when a key is
	-- given); if `props` carried a key, this is where it takes the back of that group.
	layer:PlaceInKeyGroup(action);

	-- 목록이 정렬돼 있으므로 새 액션이 맨 뒤에 붙는다는 보장이 없다. 다시 만들고 찾아간다.
	self.LayerPanel:Refresh(true);

	-- 곧바로 선택한다. 방금 생긴 액션은 키를 정해야 쓸모가 생기는데, 선택이 왼쪽 열을
	-- 그 액션으로 채운다. 커서에서 떨궈 만든 것과 **같은 대접**이어야 한다
	-- (OnReceiveDrag) - 선택 창에서 고른 것만 아무 데도 안 데려가면 같은 일을 하는 두 길이
	-- 다르게 끝난다.
	--
	-- **Naming another tab moves the window there**, the same way dropping on a tab button does
	-- (`OnReceiveDrag`, and its comment for why): picking a destination is saying "put it there",
	-- and the action would otherwise land where nothing on screen can show it. `GoToAction` is
	-- that trip - it opens the tab, then selects and scrolls like the line above.
	if (layerID ~= GetLayerID()) then
		self:GoToAction(action, layerID);
	else
		self.LayerPanel:SetSelectedAction(action);
	end

	local elementData = self.LayerPanel:ScrollActionIntoView(action);
	self:Update();

	return elementData;
end

function DebindFrameMixin:Update()
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
	self.LayerPanel:UpdateListStrip();
	self:UpdatePendingImports();
	DebindResultPanel:Refresh();
	DebindMacroFrame:Refresh();

	self.LayerPanel.ScrollBox:ForEachFrame(function(button)
		button:Update();
	end);

	self:UpdateEmptyText();

	self:UpdateDropHighlight();
end

--- Something outside the overview put actions in the profile or took them out.
---
--- **A panel says what happened, and the window decides who redraws.** The storage tab used to
--- name `DebindLayerPanel` and `DebindFrame` and call both, which is one panel knowing the layout
--- of another. What it knows now is that the profile moved.
---
--- **Not an event, and not yet.** Both columns that have to redraw are the window's own, so it
--- calls them; an `OnProfileChanged` declared here would be fired at nobody. It goes up when C
--- makes those columns files that register, and this function keeps its name and its callers
--- (`devdocs/breaking-up-debindui.md`).
---
--- **No rebuild.** Everything an import places is badged and `BuildKeyMap` skips a badged action,
--- so a rebuild here would spend the walk to arrive at the key map that is already up. Bindings
--- move when the reader accepts, not when the actions land.
function DebindFrameMixin:NotifyProfileChanged()
	self.LayerPanel:Refresh(true);
	self:Update();
end

--- An entry was made, taken in from a string, or deleted.
function DebindFrameMixin:NotifyStoreChanged()
	self:TriggerEvent(self.Event.OnStoreChanged);
end

--- 오른쪽 목록 위의 개수, 그리고 왼쪽 열 위의 좁히는 두 컨트롤.
---
--- 개수는 둘 이상일 때만 뜬다. 하나일 때는 행 강조가 이미 말했고, 늘 떠 있으면 "1 selected"가
--- 화면의 기본 상태가 되어 아무 말도 안 하게 된다.
---
--- **개수가 뜬다고 검색창을 내리지 않는다.** 둘이 오른쪽 목록 위 한 자리를 번갈아 쓰던 시절의
--- 규칙이었고, 그때는 검색창이 사라지는 것이 곧 "지금은 못 좁힌다"였다. 검색이 왼쪽으로 가면서
--- 자리가 갈렸고, 무엇보다 **걸러져 나간 선택은 이제 집합에서 빠진다**(`PruneSelectionToBinFilter`) -
--- 그 규칙이 막으려던 "안 보이는데 골라져 있는" 상태 자체가 안 생긴다.
function DebindLayerPanelMixin:UpdateListStrip()
	local multi = _selectionCount > 1;
	if (multi) then
		self.SelectionCount:SetFormattedText(LLL["BULK_SELECTED_COUNT"], _selectionCount);
	end
	self.SelectionCount:SetShown(multi);

	-- 좁히는 것이 죽는 자리는 둘이고, **판정은 여기 하나에 모은다.** `UpdateButtons`에도 같은
	-- 잠금이 있는데 이 함수가 그 뒤에 도므로, 저기서 같이 끄면 여기가 도로 켠다.
	--
	-- 1. **지정 모드.** 그동안 글자는 전부 단축키다. 포커스를 잡을 수 있게 두면 친 글자가
	--    검색창으로 새고, 모드는 켜진 채로 아무 반응도 안 하는 것처럼 보인다. 모드를 끄지는
	--    않는다 - 이 함수는 모드에서 나가는 문이 아니고(그건 오버레이의 두 버튼과 ESC다),
	--    여기서 끄면 검색창을 눌렀다는 이유로 걸어둔 키가 커밋된다.
	-- 2. **아이콘 선택기가 액션을 잡고 있을 때.** 창의 나머지가 전부 잠기는 자리라
	--    (`UpdateButtons`의 `enableButtons`) 좁히는 것만 살아 있으면 목록이 그 밑에서 바뀐다.
	--
	-- **드롭다운도 같이 잠근다.** 둘이 같은 일을 하므로 한쪽만 잠그면 잠긴 이유가 거짓이 된다.
	local capturing = DebindFrame:IsCapturingKey();
	local locked = capturing or IsEditingAction();
	DebindFrame.OverviewPanel.SearchBox:SetEnabled(not locked);
	if (locked) then
		DebindFrame.OverviewPanel.SearchBox:ClearFocus();
	end
	DebindFrame.OverviewPanel.FilterDropdown:SetEnabled(not locked);
end

--- The button for what came in. **It only stands while at least one badge is left.**
---
--- The count is over the **whole profile** (`CollectArrivedActions`) - not this tab, not this
--- specialization. What the menu's two items reach is that whole set, so the number that leads to
--- them has to be that set too. Put the visible count here instead and pressing through switches
--- more on, somewhere the reader was not looking.
---
--- **Zero takes it down now.** It used to stand at zero as well, because the narrowing to what came
--- in lived here and taking it away took the only switch that undid it. That narrowing is a tick in
--- the filter dropdown, which has its own reset button, so nothing is stranded by this leaving when
--- there is nothing waiting.
---
--- What locks it is the same as what locks the search box, for the same reasons
--- (`UpdateListStrip`): during bind mode every character on screen is a key, and while the icon
--- selector is holding an action that action can leave the list underneath it.
---
--- **It is an ordinary button and says what it is in words.** Two goes at also saying it in the
--- badge's blue were tried and both came back out on screen; the XML carries what each cost.
function DebindFrameMixin:UpdatePendingImports()
	local button = self.OverviewPanel.PendingImports;
	local count = #DebindPrivate.CollectArrivedActions();
	local shown = count > 0;

	button:SetShown(shown);
	if (not shown) then
		return;
	end

	button:SetFormattedText(LLL["IMPORT_PENDING"], count);
	button:SetWidth(max(120, button:GetFontString():GetStringWidth() + 30));
	button:SetEnabled(not self:IsCapturingKey() and not IsEditingAction());
end

--- 커서에 뭔가 들려 있는 동안 목록 인셋이 빛난다 - "여기가 받는다". 생김새와 자리는 XML에.
function DebindFrameMixin:UpdateDropHighlight()
	self.LayerPanel.ScrollBoxBackground.Highlight:SetShown(_pickedupInfo ~= nil);
end

--- 아이콘 선택기가 떠 있는 동안 잠기는 것들.
---
--- 주문 선택 창은 **여기 없다.** 그 창의 쓸모가 "열어둔 채 탭을 옮겨 다니며 골라 넣는
--- 것"이라, 잠그는 목록에 넣으면 스스로를 못 쓰게 만든다.
function DebindFrameMixin:UpdateButtons()
	local enableButtons = not IsEditingAction();

	for i = 1, #self.LayerPanel.Tabs do
		PanelTemplates_SetTabEnabled(self.LayerPanel, i, enableButtons);
	end

	-- `SideTabs`는 `InitializeSideTabs`가 채우고 그건 `OnLoad`에서만 돈다. 창이 한 번도
	-- 안 열린 세션에서는 nil인데, 그런 경로는 `Update`의 `initialized` 가드에서 막힌다.
	for _, tab in ipairs(self.LayerPanel.SideTabs) do
		tab:SetEnabled(enableButtons);
	end

	self.OverviewPanel.BindModePortrait:SetEnabled(enableButtons);
	self.OverviewPanel.AddPortrait:SetEnabled(enableButtons);
	self.OptionsPortrait:SetEnabled(enableButtons);
end

--- The panel this tab shows, or nil - in which case `MissingPanel` stands in its place.
---
--- **The panel always exists; what can be missing is what it reads.** Every one of the three is
--- built by this addon's own XML, so the old road - fetch it by global name from the load-on-demand
--- addon, reparent it, pin it - is gone along with the reason for it. What is left is that two of
--- them have nothing to draw without the addon that holds the drawer and answers `IsExportable`.
---
--- **It does not say why, because there is only one why: that addon did not come in.** A reader who
--- switched it off in the AddOns list is the one case, and `MissingPanel` says exactly that. Drawing
--- the panel anyway would put up a list that is empty for a reason it cannot state.
---
--- Loading is asked here rather than in the panel's `OnShow` so the failure has somewhere to be
--- said. A panel that shows and then discovers it has no data has already taken the screen.
function DebindFrameMixin:ResolvePanel(id)
	local entry = PANELS[id];

	if (entry.needsStore and not EnsureStore()) then
		return nil;
	end

	return self[entry.panelKey];
end

--- Picks what the window shows. This is the only job the frame has left - how many columns a
--- panel has, and what it draws, each panel settles inside itself.
---
--- **The tab lights up either way.** Failing to get a panel does not send the reader back to
--- Overview: landing somewhere they did not click reads as "this tab does not work", which is not
--- what happened. The tab stays where they put it and `MissingPanel` says what did.
function DebindFrameMixin:SelectPanel(id, force)
	if (_selectedPanel == id and not force) then
		return;
	end

	_selectedPanel = id;
	PanelTemplates_SetTab(self, id);

	local panel = self:ResolvePanel(id) or self.MissingPanel;

	-- **The width is the panel's to name.** Overview is two columns and the export list is one, so
	-- a single width would either crush one or leave the other half empty. A panel that says
	-- nothing keeps whatever is up, which is what `MissingPanel` wants - it is standing in for a
	-- panel whose width nobody can ask for.
	--
	-- Width only. The height is the same list-shaped rectangle in every tab, and the frame hangs
	-- by its **top left** (`AnchorTopLeft` in `OnLoad`), so growing sideways leaves the corner the
	-- user put it at where they put it.
	if (panel.preferredWidth) then
		self:SetWidth(panel.preferredWidth);
	end

	if (self.shownPanel ~= panel) then
		if (self.shownPanel) then
			self.shownPanel:Hide();
		end
		self.shownPanel = panel;
		panel:Show();
	end
end

function DebindFrameMixin:SetTab(id)
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);

	-- **고른 것을 여기서 놓는다.** 탭을 옮기면 그 액션은 새 목록에 없고, 그러면 상세 패널만
	-- 화면 어디에도 없는 액션을 붙들고 열려 있게 된다 - 왼쪽에는 짚어줄 행이 없으니 그 패널이
	-- 무엇을 고치는 중인지 말해줄 것이 아무것도 없고, 거기서 키를 바꾸면 안 보이는 레이어가
	-- 바뀐다. `Refresh`의 "액션이 없어졌을 때만 푼다"가 이 자리를 안 본다(그쪽 주석 참고).
	--
	-- 탭이 실제로 바뀔 때만이다. `GoToAction`은 같은 탭에도 이 함수를 부르고 곧바로 목표
	-- 액션을 고르는데, 거기서 놓았다 다시 잡으면 패널이 한 번 접혔다 펴진다.
	-- **검색어는 탭을 건너 산다.** 찾는 이름이 어느 탭에 있는지 모르는 채로 뒤지는 것이 흔한
	-- 일이라, 탭을 옮길 때마다 다시 치게 만들면 검색이 탭 하나짜리 도구가 된다. 새 탭이
	-- 걸러진 채로 열리는 것은 빈 목록 문구가 갈라준다(`NO_SEARCH_RESULTS`).
	if (_selectedTab ~= id) then
		self.LayerPanel:SetSelectedAction(nil);
	end

	_selectedTab = id;
	PanelTemplates_SetTab(self.LayerPanel, _selectedTab);
	self.LayerPanel:UpdateSideTabs();

	if (not self.LayerPanel.SideTabs[_selectedSideTab]:IsShown()) then
		_selectedSideTab = 1;
		self.LayerPanel:UpdateSideTabs();
	end

	-- `Refresh` rebuilds the list, `Update` re-reads it. Both are needed and neither can wait for
	-- the other's usual trigger: [+] is a function of the tab, and so are the selection strip and
	-- the multi-select tip. Leave `Update` out and the tip stays anchored under the list we just
	-- left - pointing at an empty one, or missing from one that just filled up.
	--
	-- (The spell picker deliberately stays open across a tab switch - its whole use is picking
	-- into one tab after another - which is why it is absent from `UpdateButtons`'s lock list.)
	self.LayerPanel:Refresh();
	self:Update();
end

--- elementData를 주면 버튼 대신 그것으로 연다. 순서 목록이 자기 행 대신 **왼쪽 목록이
--- 만든** elementData를 넘기기 위한 통로다 - 메뉴가 읽는 layer/index는 저쪽 소유의 값이라
--- 모양을 흉내내면 저쪽이 바뀔 때 조용히 어긋난다.
function DebindFrameMixin:ShowEditDropdown(button, elementData)
	elementData = elementData or button:GetElementData();
	local action = elementData.action;

	local menu = MenuUtil.CreateContextMenu(button, DebindUI.SetupEditDropdownMenu, elementData);
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

--- 고른 것이 여럿일 때 여는 메뉴. 대상은 이 행이 아니라 **집합 전체**다.
---
--- `ShowEditDropdown`과 갈라 둔 이유는 겨누는 것이 다르기 때문이다. 저쪽은 elementData
--- 하나를 들고 그 액션의 조건·중요도·키까지 만지는데, 그 값들은 여럿에 한꺼번에 걸 수 있는
--- 것이 아니다(중요도는 이 계정의 모든 캐릭터에 걸친다 - `PRIORITY_SHARED_WARNING`).
--- 여기는 이동·복사·삭제 셋뿐이라 액션 목록만 있으면 된다.
---
--- `contextMenuAction`은 안 세운다. 그건 "이 행의 메뉴가 떠 있다"는 표시로 행 강조에
--- 쓰이는데(`IsEditDropdownShown`), 여기서는 겨눈 행들이 이미 선택 강조를 받고 있다.
function DebindFrameMixin:ShowBulkDropdown(button)
	local menu = MenuUtil.CreateContextMenu(button, DebindUI.SetupBulkDropdownMenu, self:GetSelectedActions());
	self.contextMenu = menu;
	self.contextMenuAction = nil;
	if (menu) then
		menu:SetClosedCallback(function()
			if (self.contextMenu ~= menu) then
				return;
			end
			self.contextMenu = nil;
			self:Update();
		end);
	end
	self:Update();
end

function DebindFrameMixin:OnPickup()
	-- 우클릭으로 커서를 비우는 것만 듣는다. 예전에는 여기서 `ClearMouse(true)`로 진행 중인
	-- 행 드래그를 먼저 끊었는데, 이제 커서에 드는 길이 하나라 끊을 것이 없다.
	self:RegisterEvent("GLOBAL_MOUSE_DOWN");
	self:Update();
end

function DebindFrameMixin:ClearMouse()
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
function DebindFrameMixin:OnReceiveDrag(destLayerID)
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
	DebindMacroFrame:Close();
	DebindResultPanel:Close();

	local destLayer = DebindPrivate.GetProfileLayer(destLayerID);

	-- 항상 맨 뒤에 붙인다. 떨어진 위치는 의미가 없다.
	destLayer:Insert(action, nil);
	destLayer:PlaceInKeyGroup(action);

	self:ClearMouse();
	DebindPrivate.UpdateBindings();
	self.LayerPanel:Refresh(true);

	-- **떨군 곳으로 따라간다.** 탭 버튼에 떨구면 그 탭을 켜고, 방금 생긴 액션을 고르고,
	-- 화면 안으로 스크롤한다 - `GoToAction`이 그 셋을 이미 한 덩어리로 한다.
	--
	-- 한때 **같은 레이어에 떨궜을 때만** 골랐다("보이지도 않는 행을 선택할 수 없다"). 그
	-- 판단이 틀렸다 - 안 보이면 보이게 하면 된다. 다른 탭에 떨구는 것은 "저기에 넣겠다"는
	-- 분명한 의사표시인데, 그 결과가 화면 어디에도 안 나타나면 넣긴 넣었는지조차 알 수 없었다.
	--
	-- 목록이 정렬돼 있어서 새 액션이 어느 줄로 갈지는 넣어보기 전에는 모른다. 그래서
	-- 스크롤이 필요하고, 그것도 저 함수 안에 있다.
	self:GoToAction(action, destLayerID);
end

--- 아이콘 목록. **블리자드의 `IconDataProvider`를 그대로 쓰면 안 되는 이유가 여기 있다.**
---
--- 그쪽 `Init`은 파일 로컬 `BaseIconFilenames`가 비어 있으면 **부른 쪽이 채우고**, `Release`는
--- 마지막 사용자가 놓을 때 **부른 쪽이 nil로 지운다**(`IconDataProvider.lua`). 그 자리에 우리가
--- 쓰면 그 변수의 주인이 Debind가 된다.
---
--- 그 값을 편집모드가 읽는다. 진입 첫 줄의 `C_UnitAuras.SwitchAuraDataProvider()`가 오라
--- 제공자를 **가짜 샘플**로 바꾸고, 그 샘플이 아이콘을 `GetSampleAuraIcon`에서 뽑는데
--- (`EditModeAuraDataProvider.lua`) 그것이 `IconDataProviderMixin:GetNumIcons`를 지나며
--- `BaseIconFilenames`를 읽는다. 그 한 번의 읽기로 **편집모드 진입 실행 전체가 우리 오염을
--- 달고** 돌고, 같은 실행이 이어서 파티 프레임 체력바를 갱신하다 secret 값 비교에서 막힌다
--- (`PartyMemberHealthCheck`). 증상은 "이름/아이콘 창을 한 번 연 세션에서는 편집모드에 들어갈
--- 때마다 파티 체력바가 죽고 오류가 매 프레임 쏟아진다"였고, 리로드해야 풀렸다.
---
--- 그래서 기본 목록은 우리가 우리 테이블에 든다. **스펠북·특성 채우기와 필터 판정은 블리자드
--- 것을 그대로 물려받는다** - `extraIconsOnly`를 켜면 그쪽 `Init`이 공용 값을 안 건드리고
--- `extraIcons`만 채우기 때문이다. 우리가 새로 쓰는 것은 목록을 보는 접근자 셋뿐이다.
local DebindIconDataProviderMixin = CreateFromMixins(IconDataProviderMixin);

--- 블리자드의 `IconDataProvider_GetBaseIconTexture`와 같은 판정이다. 목록에는 파일 ID와 이름이
--- 섞여 들어오고, 숫자로 읽히면 그대로가 ID다.
local function BaseIconTexture(list, index)
	local texture = list[index];
	local fileDataID = tonumber(texture);
	if (fileDataID ~= nil) then
		return fileDataID;
	end
	return [[INTERFACE\ICONS\]] .. texture;
end

function DebindIconDataProviderMixin:Init(extraType)
	-- 두 번째 인자가 extraIconsOnly다. 이것이 공용 값을 안 건드리게 하는 스위치다.
	IconDataProviderMixin.Init(self, extraType, true);

	local spell, item = IconDataProviderIconType.Spell, IconDataProviderIconType.Item;
	self.baseIcons = { [spell] = {}, [item] = {} };

	-- 순서는 블리자드가 채우는 순서 그대로다. 목록 순서가 곧 화면의 아이콘 순서다.
	GetLooseMacroIcons(self.baseIcons[spell]);
	GetMacroIcons(self.baseIcons[spell]);
	GetLooseMacroItemIcons(self.baseIcons[item]);
	GetMacroItemIcons(self.baseIcons[item]);
end

--- 1번 칸은 물음표다. 그 뒤가 extraIcons, 그 뒤가 종류별 기본 목록이다.
function DebindIconDataProviderMixin:GetNumIcons()
	local numIcons = 1;
	if (self:ShouldShowExtraIcons()) then
		numIcons = numIcons + #self.extraIcons;
	end
	for _, iconType in pairs(self.requestedIconTypes) do
		numIcons = numIcons + #self.baseIcons[iconType];
	end
	return numIcons;
end

function DebindIconDataProviderMixin:GetIconByIndex(index)
	if (index == 1) then
		return [[INTERFACE\ICONS\INV_MISC_QUESTIONMARK]];
	end
	index = index - 1;

	local numExtraIcons = self:ShouldShowExtraIcons() and #self.extraIcons or 0;
	if (index <= numExtraIcons) then
		return self.extraIcons[index];
	end

	-- 종류별 목록은 각각 1부터라, 어느 목록에 떨어지는지를 빼가며 찾는다.
	local baseIndex = index - numExtraIcons;
	for _, iconType in pairs(self.requestedIconTypes) do
		local list = self.baseIcons[iconType];
		if (baseIndex <= #list) then
			return BaseIconTexture(list, baseIndex);
		end
		baseIndex = baseIndex - #list;
	end
	return nil;
end

--- 블리자드 쪽은 여기서 공용 카운터를 내리고 마지막이면 공용 목록을 지운다. 우리는 그 자리에
--- 쓴 적이 없으므로 우리 것만 놓는다.
---
--- **비우고 nil로는 두지 않는다.** 놓은 뒤에도 팝업 쪽에는 이 객체를 가리키던 참조가 남고
--- (`OnShow`가 다음에 열릴 때 새로 받아 간다), nil이면 그 참조로 개수를 묻는 순간 에러가 난다.
--- 블리자드 쪽은 `BaseIconFilenames`가 없으면 개수를 1로 답하고 넘어가므로, 그쪽과 같은
--- 자리에서 같은 답이 나오게 빈 목록을 남긴다.
function DebindIconDataProviderMixin:Release()
	self.baseIcons = { [IconDataProviderIconType.Spell] = {}, [IconDataProviderIconType.Item] = {} };
	self.extraIcons = {};
end

--- 창마다 따로 만들지 않는다. 이름/아이콘 선택기는 매크로 말고 다른 곳에서도 열리고, 목록은
--- 어느 쪽이든 같다. 창이 닫힐 때 `OnHide`가 놓는다.
function DebindFrameMixin:RefreshIconDataProvider()
	if (self.iconDataProvider == nil) then
		self.iconDataProvider = CreateAndInitFromMixin(DebindIconDataProviderMixin, IconDataProviderExtraType.Spellbook);
	end
	return self.iconDataProvider;
end

DebindIconSelectorFrameMixin = {};

function DebindIconSelectorFrameMixin:OnLoad()
end

--- 팝업을 여는 입구. 예전엔 호출자가 `mode`/`elementData`를 직접 꽂고 `Show()`를 불렀고,
--- 확인을 누르면 이 팝업이 매크로 편집기를 **직접** 열었다 - "나는 매크로에서 열렸다"가
--- 코드에 박혀 있었다. 이제 확인 뒤에 할 일은 연 쪽이 준다(`EditMacroText`의 `cancelFunc`과
--- 같은 모양). 콜백은 확인을 눌렀을 때만, 대상 elementData를 들고 불린다.
function DebindIconSelectorFrameMixin:OpenForNewMacro(onAccepted)
	self.mode = IconSelectorPopupFrameModes.New;
	self.editAction = nil;
	self.onAccepted = onAccepted;
	self:Show();
end

--- 이미 있는 액션의 이름·아이콘만 고친다. `onAccepted`는 없어도 된다 - 팝업 아래 화면이
--- 그대로 살아 있으면 확인 뒤에 갈 데가 없다.
function DebindIconSelectorFrameMixin:OpenForAction(action, onAccepted)
	self.mode = IconSelectorPopupFrameModes.Edit;
	self.editAction = action;
	self.onAccepted = onAccepted;
	self:Show();
end

function DebindIconSelectorFrameMixin:OnShow()
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

	self.iconDataProvider = DebindFrame:RefreshIconDataProvider();

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

	DebindFrame:Update();
end

function DebindIconSelectorFrameMixin:OnHide()
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
	DebindFrame:Update();
end

function DebindIconSelectorFrameMixin:Update()
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
function DebindIconSelectorFrameMixin:CancelButton_OnClick()
	IconSelectorPopupFrameTemplateMixin.CancelButton_OnClick(self);
end

function DebindIconSelectorFrameMixin:OkayButton_OnClick()
	local iconTexture = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture();
	local text = self.BorderBox.IconSelectorEditBox:GetText();
	text = string.gsub(text, "\"", "");

	local isNew = self.mode == IconSelectorPopupFrameModes.New;
	local elementData;
	if (isNew) then
		elementData = DebindFrame:AddNewAction(Constants.MACROTEXT, "", text, iconTexture);
	else
		self.editAction.name = text;
		self.editAction.icon = iconTexture;
	end

	-- 이름이 바뀌면 이름순 정렬에서 자리가 바뀐다. Update는 있는 줄을 그 자리에서 고쳐
	-- 그릴 뿐이라 방금 바꾼 이름이 옛 자리에 남는다.
	DebindLayerPanel:Refresh(true);
	DebindFrame:Update();

	-- 다음에 무엇이 열릴지는 이 팝업이 정하지 않는다. 연 쪽이 안다. 먼저 꺼내 두는 건
	-- 콜백이 이 창을 닫아도 OnHide가 같은 콜백을 두 번 부르지 않게 하려는 것이다.
	local onAccepted = self.onAccepted;
	self.onAccepted = nil;
	if (onAccepted and elementData) then
		onAccepted(elementData);
	end
	IconSelectorPopupFrameTemplateMixin.OkayButton_OnClick(self);
end

function DebindIconSelectorFrameMixin:HasUnsavedChanges()
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

function DebindIconSelectorFrameMixin:Close(force)
	if (self:IsShown()) then
		if (not force and self:HasUnsavedChanges()) then
			DebindPrivate.DisplayMessage(LLL["CONFIRM_CURRENT_CHANGE_FIRST"]);
			return false;
		end
		self:CancelButton_OnClick();
	end
	return true;
end

DebindResultPanelMixin = {};

--- 왼쪽 열. 보여주는 것은 하나다 - **지금 이 키보드가 어떻게 생겼나.**
---
--- 활성 레이어에서 키가 걸린 액션 전부를 키로 묶고, 그룹 안은 발동 순서로 놓는다. 통(오른쪽)이
--- 한 번에 한 레이어만 보여주므로 "이 키에 뭐가 다 걸렸나"에 답할 자리가 따로 필요하고,
--- 그 자리가 여기다. 넣으면 여기 나타나는 것이 레이어가 무엇을 하는지에 대한 설명이다.
---
--- **키 없는 액션은 안 담는다.** 이 열의 문장이 "지금 키보드"라서 아직 키가 아닌 것은
--- 그 문장 밖이고, 오른쪽 통이 이미 전부를 들고 있어서 잃는 것도 없다.
---
--- 한때 매크로 편집기가 두 번째 탭이었다. 되돌린 이유는 `DebindMacroFrame` 주석에 있다.
function DebindResultPanelMixin:OnLoad()
	-- The sentence for the empty column is not written here. There are two of them, so
	-- `RefreshKeyboard` picks one every time it draws - and that function has already run once by
	-- the time this returns, through the `Refresh` below.
	self:InitializeOrderScrollBox();

	-- 오버레이는 이 열의 **모든 것 위**에 서야 한다. XML에 절대 레벨을 박으면 ScrollBox가
	-- 만드는 행들과 어느 쪽이 위인지가 우연에 걸리므로(행 키 버튼이 그렇게 강조에 덮였다),
	-- 목록보다 위라는 사실을 여기서 관계로 적는다.
	local overlay = self.BindOverlay;
	overlay:SetFrameLevel(self.ContentArea.OrderArea.ScrollBox:GetFrameLevel() + 10);
	overlay.DoneButton:SetText(LLL["BIND_MODE_STOP"]);
	overlay.CancelButton:SetText(LLL["BIND_MODE_CANCEL"]);
	-- **Written once, because the mode listens for one thing: the row under the cursor.** A whole
	-- set is asked for its key in a dialog instead (`DebindUI.BeginKeyCapture`), so nothing arms
	-- this overlay with a second sentence to swap in.
	overlay.Instruction:SetText(LLL["BIND_MODE_OVERLAY"]);
	overlay.UnbindHint:SetText(LLL["BIND_MODE_UNBIND_HINT"]);

	self.initialized = true;
	self:Refresh();
end

function DebindResultPanelMixin:Refresh()
	if (not self.initialized) then
		return;
	end
	self:RefreshKeyboard();
end

--- 다른 것으로 넘어가기 전에 부르는 계약. 이 패널은 저장을 미루는 상태가 **없다** - 키도
--- 순서도 누르는 즉시 반영된다. 그래서 아무것도 막지 않고 언제나 true다.
---
--- 매크로 본문은 여기 없다. 그건 창(`DebindMacroFrame`)이 자기 몫으로 들고 있다 -
--- `TryCloseAnyDialog`가 둘 다 부른다.
---
--- 선택은 건드리지 않는다. 부르는 쪽이 이미 선택을 바꾸는 중이다.
---
--- **지정 모드도 안 끈다.** 이 함수는 `TryCloseAnyDialog`를 거쳐 탭 클릭에서도 불리는데,
--- 모드 중에 탭을 넘나드는 것은 허용해야 한다 - 트랜잭션은 탭에 걸쳐 살고, 되돌릴 목록은
--- 액션으로 잡으므로 탭 A에서 셋, 탭 B에서 둘을 걸어도 취소는 다섯을 전부 되돌린다.
--- 모드에서 나가는 길은 오버레이의 두 버튼과 ESC뿐이다.
function DebindResultPanelMixin:Close()
	return true;
end

DebindOrderLineMixin = {};

function DebindOrderLineMixin:Init()
	-- 아이콘은 프레임당 한 번이면 된다. 이 함수는 행이 풀에서 나와 다른 액션에 붙을 때마다
	-- 불리는데, 그때마다 텍스처 좌표를 다시 잡을 이유가 없다.
	if (not self.moveIconsSet) then
		SquareButton_SetIcon(self.MoveUpButton, "UP");
		SquareButton_SetIcon(self.MoveDownButton, "DOWN");
		-- The label never changes, so it is written once with the icons rather than on every
		-- redraw. The width does depend on it and is taken in `UpdateMoveButtons`.
		self.AcceptButton:SetText(LLL["ORDER_ACCEPT"]);
		self.moveIconsSet = true;
	end
	self:Update();
end

--- 이유 줄이 차지할 수 있는 **최대** 폭. 실제 폭은 글자 길이에 맞춰 행마다 정한다
--- (`SetReasonText`) - 이 값은 긴 사유가 이름을 다 밀어내지 못하게 막는 상한일 뿐이다.
local ORDER_REASON_WIDTH = 170;

--- 고른 행에만 이동 버튼을 세우고, 갈 수 있는 방향만 켠다.
---
--- 켜고 끄는 판단은 전부 `ComputeOrderSwap`이 한다. 그것은 위 네 축(중요도·호버·조건·레이어)이
--- 하나라도 갈리면 이웃 대신 **사유**를 돌려준다 - seq는 마지막 축이라, 위에서 이미 갈렸으면
--- 번호를 바꿔봐야 순서가 안 변하기 때문이다. 그 사유가 그대로 툴팁 문장이 된다.
---
--- 버튼은 없앴다 만들지 않고 **늘 두 개**다. 비활성이 곧 "지금은 안 된다"이고, 나타났다
--- 사라지면 연타할 때 과녁이 흔들린다.
function DebindOrderLineMixin:UpdateMoveButtons(elementData)
	local up, down = self.MoveUpButton, self.MoveDownButton;

	-- **혼자인 키에는 안 세운다.** 맞바꿀 상대가 없어서 양쪽 다 죽은 채로만 서 있게 되고,
	-- 그 상태는 설명할 것도 없다("맨 위이자 맨 아래다"는 배울 것이 없는 말이다). 대부분의
	-- 키가 여기 해당하므로, 안 세우는 것만으로 목록에서 버튼이 드물어진다.
	--
	-- **규칙 때문에 막힌 것은 다르다.** 그건 둘 이상이 같은 키를 두고 겨루는데 중요도나
	-- 조건이 순서를 정하고 있다는 뜻이라, 죽은 버튼과 그 툴팁이 이 애드온에서 순서 규칙을
	-- 가르치는 몇 안 되는 자리다. 그쪽은 그대로 세워 둔다.
	--
	-- **A row that came in gets the accept button instead.** What the arrows decide is which of the
	-- things on one key goes first, and a badged row does not go at all - up or down, nothing is
	-- decided. Pressing one does write `seq` though, so the gesture would edit the profile to settle
	-- nothing. The slot means "what you can do to this row right now", and for this row that is
	-- accepting it; the arrows come back the moment it is, which is when ordering becomes the job.
	local accept = self.AcceptButton;
	local arrived = elementData.row.action.arrivalID ~= nil;
	accept:SetShown(arrived);
	if (arrived) then
		accept:SetWidth(max(60, accept:GetFontString():GetStringWidth() + 24));
	end

	-- **Only the live rows count.** Neither a badged row nor an off-spec one can be an opponent
	-- (`ComputeOrderSwap`), so a key holding one live row and three of those is in the same
	-- position as a key holding one: put the arrows up and both of them are dead.
	local rows = elementData.rows;
	local live = 0;
	if (rows) then
		for i = 1, #rows do
			if (DebindPrivate.IsRowInOrder(rows[i])) then
				live = live + 1;
			end
		end
	end

	-- **An off-spec row gets no arrows and no accept button either.** What the arrows settle is the
	-- order on one key, and this row is not on that key in this specialization - the reader would be
	-- moving something they cannot see the effect of. The slot stays empty and the reason column
	-- says which specialization it belongs to.
	local offSpec = (elementData.row.specRank or 0) ~= 0;

	if (arrived or offSpec or not elementData.isCurrent or live < 2) then
		self.moveUpNeighbor, self.moveDownNeighbor = nil, nil;
		up:Hide();
		down:Hide();
		self.ReasonText:ClearAllPoints();
		-- A row with a button standing pulls the reason line left of it, for the reason spelled out
		-- in the arrows' branch below.
		if (arrived) then
			self.ReasonText:SetPoint("RIGHT", accept, "LEFT", -6, 0);
		else
			self.ReasonText:SetPoint("RIGHT", -6, 0);
		end
		return;
	end

	local upNeighbor, upReason = DebindPrivate.ComputeOrderSwap(rows, elementData.index, -1);
	local downNeighbor, downReason = DebindPrivate.ComputeOrderSwap(rows, elementData.index, 1);

	self.moveUpNeighbor, self.moveDownNeighbor = upNeighbor, downNeighbor;
	up.reasonKey = upReason and ("ORDER_BLOCKED_" .. upReason) or nil;
	down.reasonKey = downReason and ("ORDER_BLOCKED_" .. downReason) or nil;
	up.titleKey, up.descKey = "ORDER_MOVE_UP", "ORDER_MOVE_UP_DESC";
	down.titleKey, down.descKey = "ORDER_MOVE_DOWN", "ORDER_MOVE_DOWN_DESC";
	up:SetEnabled(upNeighbor ~= nil);
	down:SetEnabled(downNeighbor ~= nil);
	up:Show();
	down:Show();

	-- 이유 줄을 버튼 왼쪽으로 물린다. **오른쪽 변만 옮기면 끝이다** - 폭은 글자에서 나오므로
	-- (`SetReasonText`) 버튼 띠가 몇 픽셀인지 여기서 셀 일이 없다. 한때 그 폭을 손으로 적어
	-- 두고 빼다가 2px이 어긋났고, 그 2px에 걸린 이름이 **고른 행에서만 안 잘렸다.**
	--
	-- 버튼 자리를 다른 행에서도 비워두지는 않는다. 그러면 이름 칸의 한계가 행마다 같아져서
	-- 목록이 덜 출렁이지만, 대부분의 행에 **아무것도 안 서는 50px**을 깔게 된다 - 자리가
	-- 남는데 이름이 잘리는 것이 이 칸에서 제일 나쁜 일이다.
	self.ReasonText:ClearAllPoints();
	self.ReasonText:SetPoint("RIGHT", up, "LEFT", -6, 0);
end

--- 이웃과 **순서 번호를 맞바꾸는 것이 전부다.** 배열 자리는 순서에 아무 영향이 없다
--- (목록은 정렬해서 그린다) - 순서를 정하는 것은 액션이 들고 있는 seq다.
---
--- **A repair branch used to stand in front of this.** A missing number or two the same made the
--- swap a no-op, so an enabled button did nothing at all (`ComputeOrderSwap`, which decides whether
--- it is enabled, never looks at the numbers) -- and the fix was to renumber the group first, then
--- swap. Neither can happen now: every path that hands out a number goes through a renumber, so a
--- group's numbers are always 1..n, and a hand-edited file is swept by `CleanUpDB` at login.
---
--- Renumbering after the swap tidies the numbers rather than the order. The swap has already made
--- the drawn order what was asked for; the renumber reads that order back and closes it to 1..n.
---
--- The arrow buttons and the right-click menu **go through this one function.** Saving is three
--- things together (the `seq` swap, the renumber, `UpdateBindings`), and writing them along two
--- paths means one of them loses one someday. That loss stays invisible until the next login.
function DebindUI.ApplyOrderSwap(action, neighbor)
	if (not action or not neighbor) then
		return false;
	end

	action.seq, neighbor.seq = neighbor.seq, action.seq;
	-- 움직인 행을 따라간다. 한 칸씩 가는 동안은 대개 이미 보이고 있어서 화면이 서 있지만,
	-- 그룹의 끝에서 밀려나 화면 밖으로 나가는 순간에는 따라가야 한다.
	_revealAction = action;
	DebindPrivate.RenumberKeyGroupForAction(action);
	DebindPrivate.UpdateBindings();
	DebindLayerPanel:Refresh(true);
	DebindFrame:Update();
	PlaySound(SOUNDKIT.IG_ABILITY_ICON_DROP);
	return true;
end

function DebindOrderLineMixin:OnMoveClick(button)
	local neighborRow = (button == self.MoveUpButton) and self.moveUpNeighbor or self.moveDownNeighbor;
	local action = self:GetElementData().row.action;
	if (not DebindUI.ApplyOrderSwap(action, neighborRow and neighborRow.action)) then
		return;
	end

	-- **툴팁을 다시 그린다.** 커서가 버튼 위에 그대로 있으면 OnEnter가 다시 오지 않으므로,
	-- 방금 맨 끝으로 간 행에도 "한 칸 더 갈 수 있다"가 떠 있는 채로 남는다. 위 `Update`가
	-- `UpdateMoveButtons`를 지나면서 버튼의 상태와 사유(`reasonKey`)를 이미 새로 잡아뒀으니
	-- 여기서는 그 값으로 한 번 더 그리기만 하면 된다.
	if (GameTooltip:GetOwner() == button) then
		self:OnMoveEnter(button);
	end
end

--- Takes the badge off this one action.
---
--- **The same call the right-click menu makes**, so the two ways in cannot come apart - that one
--- rebuilds the bindings and the list, which is what has to happen the moment a key starts working.
--- The row redraws out from under the cursor and the button goes with it, since the arrows take the
--- slot back the instant the badge is gone.
---
--- No confirmation, for the reason the strip's button has none: accepting is what importing is for.
--- What it does have is a slot of its own away from the arrows' (the XML says why).
function DebindOrderLineMixin:OnAcceptClick()
	ApproveArrivedActions({ self:GetElementData().row.action });
	GameTooltip:Hide();
end

function DebindOrderLineMixin:OnAcceptEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, LLL["ORDER_ACCEPT"]);
	GameTooltip_AddNormalLine(GameTooltip, LLL["ORDER_ACCEPT_DESC"]);
	GameTooltip:Show();
end

--- 막힌 버튼은 **왜 막혔는지**를 말한다. 그 사유는 순서 규칙 자체라, 이 애드온에서 규칙을
--- 가르치는 몇 안 되는 자리다.
function DebindOrderLineMixin:OnMoveEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, LLL[button.titleKey]);
	GameTooltip_AddNormalLine(GameTooltip, LLL[button.descKey]);
	if (not button:IsEnabled() and button.reasonKey) then
		GameTooltip_AddErrorLine(GameTooltip, LLL[button.reasonKey]);
	end
	GameTooltip:Show();
end

--- 이 행의 이유 칸에 적을 글. 적을 것이 없으면 빈 문자열이다.
---
--- **문제가 순서를 이긴다.** 이 칸이 답하는 것은 "왜 이 자리인가"인데, 아예 안 나가는
--- 바인딩에게는 그게 물어볼 값어치가 없는 질문이다. 고칠 것이 있으면 그것부터 말하고
--- 순서 이야기는 접는다 - 둘 다 적으면 한 줄에 안 들어가고, 빨강이 회색 옆에서 힘을 잃는다.
---
--- 도달불가와 이슈를 함께 적지 않는 이유는 `GetBindingIssue`가 도달불가도 이슈로 치기
--- 때문이다(Misc.lua). 더 구체적인 쪽만 쓴다.
---
--- **The problem codes arrive here as one word, and that is deliberate.** They used to be spelled
--- out per code -- "No group selected", "Unknown state name" -- and in a list you scan that reads as
--- noise: this column's own subject is which row beat the one below it, so a guest sentence pitched
--- three levels finer makes one slot talk at two resolutions. The detail did not go away, it moved
--- to the one surface the reader opens on purpose. `BINDING_ERROR_*` under the condition it belongs
--- to is where it now lives, and only there.
---
--- Which leaves this column two words for a problem, matching the two grades exactly: the minor one
--- keeps its own sentence because "never runs" is the more specific thing to say, and everything
--- else is red and generic.
local function GetOrderReasonText(elementData)
	local row = elementData.row;
	-- **A badged row says nothing here, because the slot is the button's.** What this column
	-- normally holds is why this row beat the one below it, and for a row that does not fire that
	-- sentence is beside the point - it describes an ordering it takes no part in. The problem
	-- codes go quiet for the same span: accepting comes before fixing, since a problem already
	-- keeps an action out of the key map (`BuildKeyMap` takes only `not issue`), so taking the
	-- badge off something broken changes nothing about what any key does. Both come back the
	-- moment it is accepted, which is when either one starts to matter.
	if (row.action.arrivalID) then
		return "";
	-- **Which specialization it belongs to, in the slot the contest would have used.** The row sits
	-- where it would sit if that specialization were the live one, so without this line the reader
	-- has no way to tell it apart from what is running right now. It comes before the problem codes
	-- for the same reason those come before the ordering sentence: a more specific thing to say
	-- wins the one slot.
	elseif ((row.specRank or 0) ~= 0) then
		return DISABLED_FONT_COLOR:WrapTextInColorCode(LLL["ORDER_FLAG_OFFSPEC"]);
	elseif (row.unreachable) then
		return DISABLED_FONT_COLOR:WrapTextInColorCode(LLL["ORDER_FLAG_UNREACHABLE"]);
	elseif (row.issue) then
		return ERROR_COLOR:WrapTextInColorCode(LLL["ORDER_FLAG_ISSUE"]);
	end

	-- 아래 행을 이긴 이유. 없으면(그룹의 마지막 행, 또는 혼자인 키) 빈칸이다.
	local reason = elementData.reason;
	if (not reason) then
		return "";
	elseif (elementData.reasonB) then
		return format(LLL["ORDER_WHY_" .. reason], elementData.reasonA, elementData.reasonB);
	elseif (elementData.reasonA) then
		return format(LLL["ORDER_WHY_" .. reason], elementData.reasonA);
	end
	return LLL["ORDER_WHY_" .. reason];
end

--- 이유 줄은 **글자만큼만** 차지한다. 남는 폭은 이름이 가져간다 - 이름 칸의 오른쪽 변이
--- 이 줄의 왼쪽 변에 매달려 있어서(XML) 여기서 좁힌 만큼 저쪽이 넓어진다.
---
--- 폭이 붙박이(170)였을 때 `Never runs` 같은 짧은 사유가 100px 넘는 빈칸을 깔고 앉았고,
--- 그 옆에서 이름이 잘렸다. **자리가 남는데 잘리는 것**은 사용자가 손쓸 길이 없는 결함이다.
--- 이길 상대가 없어 아예 빈 행(대부분이 그렇다)은 이제 그 폭을 통째로 이름에 준다.
---
--- 상한(`ORDER_REASON_WIDTH`)은 남는다. 사유가 길면 이번엔 이름이 밀리는데, 이 목록에서
--- 먼저 읽혀야 하는 것은 무엇이 걸려 있는가라 이름 쪽을 지킨다.
---
--- 재기 전에 폭을 푸는 것은 블리자드가 쓰는 방식 그대로다(FriendsListTemplates). 폭이
--- 걸린 채로는 잘린 길이가 나오고, 그러면 한 번 좁아진 칸이 다시는 안 넓어진다 - 이
--- 프레임은 풀에서 나와 다음 행에 재활용되므로 지난 행의 폭을 물려받는다.
function DebindOrderLineMixin:SetReasonText(text)
	local reasonText = self.ReasonText;
	reasonText:SetText(text);
	reasonText:SetWidth(0);
	if (reasonText:GetWidth() > ORDER_REASON_WIDTH) then
		reasonText:SetWidth(ORDER_REASON_WIDTH);
	end
end

function DebindOrderLineMixin:Update()
	local elementData = self:GetElementData();
	local row = elementData.row;

	self:UpdateMoveButtons(elementData);

	-- 왼쪽 목록과 같은 색 규칙: 문제 있으면 빨강, 비활성이면 회색.
	local name, icon = ColoredNameAndIconForAction(row.action);
	self.Name:SetText(name);
	SetActionIcon(self.Icon, icon);

	self:SetReasonText(GetOrderReasonText(elementData));

	self.NewDot:SetShown(row.action.arrivalID ~= nil);

	-- 지금 보고 있는 액션은 오른쪽 목록의 선택과 같은 하이라이트로 띄운다.
	self.SelectedHighlight:SetShown(elementData.isCurrent);
end

--- 이 행의 툴팁 맨 아래 안내 줄. 좌클릭 줄만 이 목록의 것으로 갈아 끼운다 - 오른쪽 목록에서
--- 좌클릭은 고르는 것이지만 여기서는 **데려가는 것**이라 같은 말을 쓸 수 없다. 우클릭 줄은
--- 저쪽 것을 그대로 쓴다. 두 목록 다 그 액션의 메뉴가 열리고, 담긴 항목이 다르다는 것은
--- 열어보면 아는 일이지 안내가 미리 갈라 말할 것이 아니다.
local ORDER_LINE_GOTO_INSTRUCTIONS = {
	"ORDER_LINE_TOOLTIP_INSTRUCTION_GOTO",
	"LINE_TOOLTIP_INSTRUCTION_MESSAGE2",
};

function DebindOrderLineMixin:OnEnter()
	local row = self:GetElementData().row;
	GameTooltip:SetOwner(self, "ANCHOR_LEFT");
	AddActionToTooltip(GameTooltip, row.action, {
		offWorld = row.offWorld,
		suppressInactive = true,
		instructionKeys = ORDER_LINE_GOTO_INSTRUCTIONS,
		layerLabel = GetLayerLabel(row.layerID),
	});
	GameTooltip:Show();
end

function DebindOrderLineMixin:OnLeave()
	HideActionTooltip(GameTooltip);
end

--- 결과 목록의 행을 누르면 **그 액션이 사는 통으로 데려간다.**
---
--- 이 목록은 사영이다 - 행마다 다른 레이어에서 왔고, 여기서 편집을 열면 "어디 붙은
--- 액션인지 모르는 채로" 만지는 일이 된다. 대신 통을 그 레이어로 옮기고 행을 짚어주면,
--- 그 다음 손질은 전부 통 쪽의 규칙대로 일어난다.
---
--- **우클릭은 순서 메뉴다.** 편집 메뉴(`SetupEditDropdownMenu`)는 여기서 안 연다 - 그것은
--- 액션이 사는 곳의 것이고, 그 액션을 그리로 데려가는 것이 이 목록의 좌클릭이다. 순서만은
--- 예외로 두는데, **순서는 이 목록이 답하는 물음 자체**라서 답을 보는 자리와 고치는 자리가
--- 갈리면 한 칸 옮길 때마다 통을 다녀와야 한다.
---
--- 화살표 버튼은 고른 행에만 선다. 그 판단은 늘 켜져 있는 버튼이 목록을 어지럽히는 문제라
--- (`UpdateMoveButtons`) 사용자가 직접 연 메뉴에는 걸리지 않는다 - 여기서는 혼자인 키도
--- 두 항목을 죽은 채로 보여주고, 왜 안 되는지를 그 툴팁이 말한다.
function DebindOrderLineMixin:OnClick(button)
	-- 캡처 중에는 이 목록이 아직 옛 키의 것이다. 곧 갈아치워질 화면에서 떠나지 않고, 그
	-- 화면의 순서를 고치지도 않는다.
	if (DebindFrame:IsCapturingKey()) then
		return;
	end

	local row = self:GetElementData().row;

	if (button == "RightButton") then
		-- **액션만 넘긴다.** 메뉴는 뜬 채로 목록이 다시 지어질 수 있는 자리라, 지금 손에 든
		-- 그룹과 자리(`elementData.rows/index`)를 딸려 보내면 그것이 낡는다. 저쪽은 누를 때
		-- `ComputeOrderSwapForAction`으로 다시 묻는다.
		MenuUtil.CreateContextMenu(self, DebindUI.SetupOrderDropdownMenu, row.action);
		return;
	end

	DebindFrame:GoToAction(row.action, row.layerID);
end

local ORDER_LINE_INDENT = 10;

function DebindResultPanelMixin:InitializeOrderScrollBox()
	local orderArea = self.ContentArea.OrderArea;
	-- 행 사이는 띄우지 않는다(마지막 인자 0). 줄무늬가 경계를 그리므로 틈이 필요 없고,
	-- 틈이 있으면 무늬가 끊겨서 오히려 줄이 안 세어진다. 경매장 목록도 붙여 놓는다.
	local view = CreateScrollBoxListLinearView(4, 4, 2, 2, 3);
	-- 헤더와 행이 섞이므로 템플릿을 하나로 못 박지 못한다. 오른쪽 목록과 같은 방식이고,
	-- 키 헤더도 **같은 템플릿**이다 - 한 창의 두 목록이 키를 다른 그림으로 가르면 안 된다.
	view:SetElementFactory(function(factory, elementData)
		if (elementData.isHeader) then
			factory("DebindKeyHeaderTemplate", function(frame)
				frame:Init(elementData);
			end);
		else
			factory("DebindOrderLineTemplate", function(button)
				button:Init(elementData);
			end);
		end
	end);
	view:SetElementExtentCalculator(function(_, elementData)
		return elementData.isHeader and KEY_HEADER_HEIGHT or ORDER_LINE_HEIGHT;
	end);
	view:SetElementIndentCalculator(function(elementData)
		return elementData.isHeader and 0 or ORDER_LINE_INDENT;
	end);

	ScrollUtil.InitScrollBoxListWithScrollBar(orderArea.ScrollBox, orderArea.ScrollBar, view);
end

--- 프로필에 있는, 키가 걸린 액션 전부. 키로 묶고, 그룹 안은 발동 순서다.
---
--- 순서를 내는 것은 `CollectActionsForKey`로, 이 애드온에서 순서를 말하는 자리가 그 함수
--- 하나뿐이다 - 두 화면이 다른 답을 낼 길이 없다.
---
--- **오프스펙 액션도 그린다.** 한때 활성 레이어만 훑었고 근거는 "이 열의 문장이 '지금 이
--- 키보드'"였는데, 그 대가로 오프스펙에 걸린 것은 이 화면 어디에도 안 나왔다 - 오른쪽 탭을
--- 열어 하나씩 뒤지는 수밖에 없었다. 지금은 **자기가 활성이었다면 섰을 자리**에 서고
--- (`EnumerateAllProfileLayers`), 지금 안 돈다는 것은 자리가 아니라 사유 칸이 말한다.
---
--- 특성은 **지금 것**으로 고정이다. 오른쪽에서 다른 특성 탭을 열어도 여기는 안 따라간다 -
--- 무엇이 오프스펙인지가 화면마다 달라지면 이 열의 문장이 흔들린다.
---
--- 이 키 그룹이 필터와 검색을 통과하나. **판정 단위는 그룹이고 답은 통째다.**
---
--- 안을 솎을 수가 없다. 행마다 **바로 아래 행을 이긴 이유**가 붙어 있어서, 몇을 빼면 남은
--- 행이 화면에 없는 행을 이겼다고 말한다. 그래서 하나라도 통과하면 전부 남기고, 아니면 전부
--- 뺀다 - 살아남은 문장은 언제나 자기 주어를 갖는다.
---
--- **검색은 머리글이 말하는 것에도 걸린다.** 이 열에서 그룹을 부르는 이름이 곧 단축키라, 키를
--- 쳐서 거기 뭐가 걸렸는지 보는 것이 액션 이름으로 찾는 것만큼 자연스럽다.
local function KeyGroupPasses(rows, key)
	local any = false;
	for i = 1, #rows do
		if (ActionPassesFilters(rows[i].action, rows[i].specRank)) then
			any = true;
			break;
		end
	end
	if (not any or _searchText == nil) then
		return any;
	end

	if (NameMatchesSearch(DebindPrivate.GetKeyDisplayText(key))) then
		return true;
	end
	for i = 1, #rows do
		if (NameMatchesSearch(NameAndIconForAction(rows[i].action))) then
			return true;
		end
	end
	return false;
end

--- **필터는 키 그룹을 통째로 남기거나 뺀다**(`KeyGroupPasses`). 어느 키가 배지를 들고 있는지는
--- 아래 스캔이 정한다 - 나중에 행을 보고 되짚으면 머리글과 행이 어긋날 수 있는데, 이 스캔은
--- `CollectActionsForKey`가 볼 것과 정확히 같은 것을 본다(둘 다 살아 있는 레이어를 훑고 어느
--- 쪽도 빠뜨리지 않는다).
---
--- `elements`와 함께 **그려지는 액션의 집합**을 돌려준다. 오른쪽 목록과 탭 숫자가 그 집합으로
--- 거른다. **접힘은 집합에 안 든다** - 접기는 이 열의 보기 상태이지 필터가 아니라, 접힌 그룹의
--- 액션도 오른쪽에는 그대로 서 있어야 한다.
function BuildKeyboardElements()
	-- **한 키가 그룹 하나가 아니다.** 도착분은 보낸 사람의 실키를 그대로 들고 오므로 내 세트와
	-- 같은 키 위에 앉고, 그 둘은 머리글이 둘이다(`devdocs/building-export-import.md` 12절).
	-- 그래서 훑는 단위가 `(key, arrivalID)` 쌍이고, 아래 `groups`는 그 쌍의 목록이다.
	local seen, groups = {}, {};
	for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
		for _, action in layer:Enumerate() do
			local key = action.key;
			if (key) then
				local groupID = key .. "/" .. tostring(action.arrivalID);
				if (not seen[groupID]) then
					seen[groupID] = true;
					groups[#groups + 1] = { key = key, arrivalID = action.arrivalID };
				end
			end
		end
	end

	-- 키가 먼저고, 같은 키 안에서는 **내 것이 위**다. 도착분은 아직 안 눌리는 것이라, 눌리는
	-- 그룹을 위에 두는 편이 그 키를 눌렀을 때 무엇이 나가는지를 먼저 읽게 한다. 그다음은 번호
	-- 순이고, 번호는 도착한 차례라 오래된 것이 위에 선다.
	sort(groups, function(lhs, rhs)
		if (lhs.key ~= rhs.key) then
			return DebindPrivate.CompareKeys(lhs.key, rhs.key);
		end
		if (lhs.arrivalID == rhs.arrivalID) then
			return false;
		end
		if (lhs.arrivalID == nil) then
			return true;
		end
		if (rhs.arrivalID == nil) then
			return false;
		end
		return lhs.arrivalID < rhs.arrivalID;
	end);

	local elements, visible = {}, {};
	for _, group in ipairs(groups) do
		local key, arrivalID = group.key, group.arrivalID;
		local rows = DebindPrivate.CollectActionsForKey(key, nil, arrivalID);
		local collapsed = _collapsedKeys[CollapseKeyFor(key, arrivalID)] == true;
		local shown = KeyGroupPasses(rows, key);

		-- **이 키를 지금 눌러도 아무것도 안 나가는가.** 키는 걸려 있는데 멤버가 전부 다른
		-- 특성 것인 경우가 그렇고, 머리글은 그때 흐려진다.
		--
		-- 판정은 빌드에 들어갔는지 하나다(`ActiveActions`). "오프스펙인가"로 물으면 같은
		-- 답을 내는 다른 사유들 - 배지가 붙었다, 키가 번호다 - 을 따로 다시 세게 된다.
		-- 행이 자기 이름을 흐리게 할 때 보는 것도 같은 함수다.
		--
		-- **Is one of the ones that would run broken?** Only rows that got into the build are asked,
		-- which is what keeps this from reddening over things the reader cannot act on now: an
		-- off-spec or badged row is inactive for a reason of its own and already says so in its own
		-- slot. A problem does not keep an action out of `ActiveActions` (`BuildKeyMap` sets that
		-- outside the gate), so what is left is exactly "would run, except for this".
		--
		-- **One is enough**, unlike the grey above which needs all of them. Grey describes the group
		-- - nothing here runs - while red points at work waiting in it, and one broken row is work.
		-- A collapsed heading summarises only its first action, so a rule of "all of them" would
		-- leave a group with one bad row saying nothing at all while folded.
		local allInactive = true;
		local hasError = false;
		for i = 1, #rows do
			if (not DebindPrivate.IsInactiveAction(rows[i].action)) then
				allInactive = false;
				local issue = rows[i].issue;
				if (issue and not DebindPrivate.IsIssueMinor(issue)) then
					hasError = true;
					break;
				end
			end
		end

		if (shown) then
			-- 그룹이 남으면 **멤버 전부가** 집합에 든다. 통째로 남기는 것과 같은 이유다 -
			-- 오른쪽 목록이 여기서 매치된 하나만 받으면 두 열이 다른 그룹을 말하게 된다.
			for i = 1, #rows do
				visible[rows[i].action] = true;
			end
			elements[#elements + 1] = {
				isHeader = true,
				key = key,
				collapsed = collapsed,
				-- The heading summarises these (`UpdateSummary`), folded or not. **Emptying `rows`
				-- below rebinds the local name**, so the table carried here is left as it is.
				rows = rows,
				allInactive = allInactive,
				hasError = hasError,
				-- Which arrival this group is, or nil for the reader own. The heading reads it to
				-- know whether to tint, and the collapse state and the menu are filed under it.
				arrivalID = arrivalID,
			};
		end

		-- 각 행에 **바로 아래 행을 이긴 이유**를 붙인다. 마지막 행에는 안 붙는다 - 이길
		-- 상대가 없다. 넷 다 같았으면(nil) 남은 것은 순서 번호뿐이라 SEQ로 부른다.
		--
		-- **접혀 있으면 행을 안 만든다.** 만들어두고 숨기는 길도 있지만, 이 목록은 스크롤
		-- 길이를 elementData 개수로 재므로(`SetElementExtentCalculator`) 숨긴 행은 빈 자리로
		-- 남는다. 필터에 빠진 그룹도 같은 자리에서 걷힌다 - 머리글을 안 세웠으니 행도 없다.
		if (collapsed or not shown) then
			rows = {};
		end
		for i, row in ipairs(rows) do
			-- 이유마다 딸리는 값이 다르다. 중요도는 **어느 쪽이 높았는지**를 말해야 하고
			-- (이름만 쓰면 방향을 모른다), 레이어는 규칙 이름보다 **실제 두 레이어**를 대는
			-- 편이 읽힌다. 값은 여기서 뽑아둔다 - 그릴 때는 이웃 행이 손에 없다.
			local reason, argA, argB;
			-- **The next one that fires, not the next line.** A badged row is not in the order
			-- (`ComputeOrderSwap` skips it for the same reason), so measuring against one would
			-- describe a contest that does not happen. Rows that are themselves badged get no
			-- sentence at all - `GetOrderReasonText` returns "" for them, and the slot is the
			-- accept button's.
			--
			-- **An off-spec row is out of the running the same way.** It is not in this
			-- specialization's key map, so a sentence measured against one would describe a
			-- contest that does not happen - and its own slot says which specialization it
			-- belongs to instead.
			local next;
			for j = i + 1, #rows do
				if (DebindPrivate.IsRowInOrder(rows[j])) then
					next = rows[j];
					break;
				end
			end
			if (next) then
				reason = DebindPrivate.GetDecidingOrderAxis(row, next) or "SEQ";
				if (reason == "PRIORITY") then
					argA = LLL["PRIORITY" .. row.priority];
				elseif (reason == "LAYER") then
					argA, argB = GetLayerShortName(row.layerID), GetLayerShortName(next.layerID);
				end
			end
			elements[#elements + 1] = {
				row = row,
				isCurrent = row.action == _selectedAction,
				reason = reason,
				reasonA = argA,
				reasonB = argB,
				-- 이동 버튼이 `ComputeOrderSwap(rows, index, ±1)`을 물으려면 **그룹 전체와
				-- 자기 자리**가 있어야 한다. 그릴 때는 이웃 행이 손에 없으므로 여기서 실어둔다.
				rows = rows,
				index = i,
			};
		end
	end

	-- **Then everything with no key, last.** The column above is the keyboard, and these are not on
	-- it; putting them anywhere but the end would break the reading that a header owns a key.
	--
	-- **One pile, and it used to be several.** A set that arrived without a key was headed on its
	-- own here, because the grouping was the only surviving record of what the sender had built. An
	-- arrival keeps the key it was sent on now, so anything of it that reaches this pile came in on
	-- no key at all and was never a set (`devdocs/building-export-import.md` 12절).
	local rows = DebindPrivate.CollectKeylessActionRows();

	-- **The pile is narrowed row by row, and the key groups above are not.** A key group is kept
	-- whole because the reason text on each row names the one below it; nothing here carries a
	-- sentence about its neighbour, so there is nothing to break by thinning it.
	--
	-- 검색도 여기서는 행 단위다. 위에서는 키가 그룹을 부르는 이름이라 머리글에도 걸었지만, 이
	-- 덩어리의 머리글은 키가 아니라 상태를 말한다 - 「키 지정 안 됨」이 검색어에 걸리면 안
	-- 걸린 액션까지 전부 딸려 온다.
	do
		local kept = {};
		for _, row in ipairs(rows) do
			if (ActionPassesFilters(row.action, row.specRank)
				and NameMatchesSearch(NameAndIconForAction(row.action))) then
				kept[#kept + 1] = row;
				visible[row.action] = true;
			end
		end
		rows = kept;
	end

	-- **The pile is sorted by name, and the key groups above are not.** Firing order is what
	-- `CompareActionOrder` answers, and nothing in this pile fires - these are actions with no key
	-- at all, belonging to no set. What is left to sort them by is the one thing the reader is
	-- scanning for, which is what the action is.
	sort(rows, function(lhs, rhs)
		local lhsName = NameAndIconForAction(lhs.action) or "";
		local rhsName = NameAndIconForAction(rhs.action) or "";
		if (lhsName ~= rhsName) then
			return lhsName < rhsName;
		end
		-- Two of the same thing. Falling through keeps the list from rearranging itself between two
		-- draws - `table.sort` is not stable, so a pair that ties all the way down is free to swap.
		--
		-- **`layerID`, not `layerRank`.** The rank is a scope now and all four character-spec layers
		-- share it, so two rows in different specs tie on rank and can tie on `index` as well - both
		-- being the first action in their own layer.
		if (lhs.layerID ~= rhs.layerID) then
			return lhs.layerID < rhs.layerID;
		end
		return lhs.index < rhs.index;
	end);

	if (#rows > 0) then
		local collapsed = _collapsedKeys[CollapseKeyFor(nil)] == true;
		elements[#elements + 1] = {
			isHeader = true,
			key = nil,
			collapsed = collapsed,
			-- This pile gets the same summary every other heading gets. What differs is that its
			-- first name is first in name order rather than in firing order, and nothing here fires
			-- at all, so the difference has nothing to be about.
			rows = rows,
			-- **Not a scan like the one above, a definition.** Having no key at all is what puts an
			-- action in this pile, so every member of it is inactive by construction. Leaving the
			-- field off left this heading grey with a gold summary beside it -- the one split
			-- `UpdateSummary` says it is there to prevent.
			allInactive = true,
		};
		if (collapsed) then
			rows = {};
		end
		for _, row in ipairs(rows) do
			-- No `reason`, and no `rows`/`index`. Nothing here beat anything: with no key there is
			-- no contest to win and nowhere to move to, so the arrows stay down (`UpdateMoveButtons`
			-- finds fewer than two live rows) and the slot beside the name is the accept button's.
			elements[#elements + 1] = {
				row = row,
				isCurrent = row.action == _selectedAction,
			};
		end
	end

	return elements, visible;
end

--- 왼쪽 열이 그리는 액션 전부. 오른쪽 목록과 탭 숫자가 이걸로 거른다.
---
--- 목록을 통째로 다시 지어서 집합만 꺼낸다. 판정을 옮겨 적는 것보다 낫다 - 그룹 단위 규칙을
--- 두 벌 두면 한쪽만 고쳐지는 날이 오고, 그날 탭에 쓰인 숫자와 그 탭이 여는 목록이 갈린다.
function CollectVisibleActions()
	local _, visible = BuildKeyboardElements();
	return visible;
end

--- 한 행을 화면에 세운다. **머리글까지 같이 세운다** - 이 목록은 고정 머리글이 아니라 머리글이
--- 스크롤에 밀려 나가고, 그러면 무슨 키인지 알 수 없는 행만 남는다.
---
--- 네 갈래다:
---
--- 1. **키 없는 덩어리는 행만 본다.** 그 머리글은 키가 아니라 상태를 말하므로("키 지정 안 됨")
---    행 옆에 같이 있어야 할 이유가 없다.
--- 2. **둘 다 이미 보이면 움직이지 않는다.** 스크롤은 읽던 자리를 빼앗는 일이라, 화면이 이미
---    답을 보여주고 있으면 하지 않는 것이 답이다.
--- 3. 아니면 **둘이 들어오는 최소한만** 움직인다. 위로 벗어났으면 머리글을 맨 위에, 아래로
---    벗어났으면 행을 맨 아래에 세우면 그게 최소다 - 구간이 화면에 들어가므로 한쪽을 붙이면
---    다른 쪽은 따라 들어온다.
--- 4. 머리글부터 행까지가 **화면보다 길면** 둘을 같이 세울 방법이 없다. 그때는 행만 본다.
---
--- "보인다"는 완전히 보이는 것이다. 아래 끝에 반쯤 잘린 행은 안 보이는 것으로 센다 -
--- `AlignNearest`가 쓰는 기준과 같다.
local function RevealRow(scrollBox, headerIndex, rowIndex, keyless)
	if (keyless) then
		scrollBox:ScrollToElementDataIndex(rowIndex, ScrollBoxConstants.AlignNearest);
		return;
	end

	local visible = scrollBox:GetVisibleExtent();
	local headerTop = scrollBox:GetExtentUntil(headerIndex);
	local rowBottom = scrollBox:GetExtentUntil(rowIndex) + scrollBox:GetElementExtent(rowIndex);

	if ((rowBottom - headerTop) > visible) then
		scrollBox:ScrollToElementDataIndex(rowIndex, ScrollBoxConstants.AlignNearest);
		return;
	end

	local scrollOffset = scrollBox:GetDerivedScrollOffset();
	if (headerTop >= scrollOffset and rowBottom <= (scrollOffset + visible)) then
		return;
	end

	if (headerTop < scrollOffset) then
		scrollBox:ScrollToOffset(headerTop);
	else
		scrollBox:ScrollToOffset(rowBottom - visible);
	end
end


--- 왼쪽 열을 다시 그린다.
---
--- 선택은 목록을 **거르지 않는다.** 목록은 언제나 키보드 전부이고, 선택이 하는 일은 그 행을
--- 짚는 것 하나뿐이다(`isCurrent`).
---
--- **스크롤은 부탁받았을 때만 움직인다**(`_revealAction`). 그리는 일과 보여주는 일이 갈리는
--- 자리다 - 그 둘이 붙어 있으면 접기가 성립하지 않는다.
function DebindResultPanelMixin:RefreshKeyboard()
	local orderArea = self.ContentArea.OrderArea;

	-- 지어놓고 펼치면 방금 지은 목록을 버리고 다시 지어야 하므로, 펼치는 것이 먼저다.
	local revealAction = _revealAction;
	_revealAction = nil;
	if (revealAction) then
		_collapsedKeys[CollapseKeyFor(revealAction.key, revealAction.arrivalID)] = nil;
	end

	local elements = BuildKeyboardElements();

	-- **Two reasons to be empty, so two sentences.** Ordinarily empty means no key is bound yet; with
	-- something ticked off in the filters, a keyboard full of keys empties too, and saying "no key is
	-- bound yet" there is the screen lying.
	--
	-- 검색은 여기서 따로 말하지 않는다. 이 열이 비었는데 검색어를 친 사람은 자기가 무엇을 쳤는지
	-- 알고 있고, 지운 값이 무엇인지는 드롭다운을 열어야 보이는 것과 사정이 다르다.
	self.ContentArea.EmptyText:SetText(
		LLL[DebindFrame:AreFiltersDefault() and "OVERVIEW_EMPTY" or "OVERVIEW_EMPTY_FILTERED"]);

	-- 걸린 키가 하나도 없으면 구역을 통째로 내린다. 빈 상자만 남기지 않는다.
	--
	-- **숨기기 전에 데이터를 비운다.** 안 비우면 마지막으로 그린 행들이 프레임 풀에 그대로
	-- 잡혀 있고, 그 elementData가 방금 지워진 액션을 가리킨 채로 남는다 -
	-- `DebindOrderLineMixin:OnMoveClick`은 `self:GetElementData().row.action`을 확인 없이 읽는다.
	-- 다른 갈래는 전부 provider를 갈아끼우므로 이 자리만 예외였다.
	if (#elements == 0) then
		orderArea.ScrollBox:SetDataProvider(CreateDataProvider(), ScrollBoxConstants.DiscardScrollPosition);
		orderArea:Hide();
		self.ContentArea.EmptyText:Show();
		return;
	end

	self.ContentArea.EmptyText:Hide();
	orderArea:Show();

	-- 보여줄 행과 **그 행이 딸린 머리글**을 여기서 같이 집는다. 액션에서 그룹을 다시 계산하는
	-- 대신 지나온 머리글을 기억하는 쪽이, 묶는 규칙이 하나로 남는다.
	local dataProvider = CreateDataProvider();
	local headerIndex, revealIndex, revealHeaderIndex;
	for i, elementData in ipairs(elements) do
		if (elementData.isHeader) then
			headerIndex = i;
		elseif (revealAction and elementData.row.action == revealAction) then
			revealIndex, revealHeaderIndex = i, headerIndex;
		end
		dataProvider:Insert(elementData);
	end
	orderArea.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition);

	-- 없을 수 있다 - 지워진 액션을 부탁받았거나, [들어온 것만]이 그 그룹을 통째로 걷어냈거나.
	if (revealIndex) then
		RevealRow(orderArea.ScrollBox, revealHeaderIndex, revealIndex,
			elements[revealHeaderIndex].key == nil);
	end
end

--- 지금 단축키를 듣고 있는가.
---
--- **사용자가 버튼을 눌러서 들어온 상태만** 참이다. 예전에는 키가 없는 액션이면 무조건
--- 참이었는데, 그러면 사용자가 연 적 없는 모드가 열려서 다른 모든 동작이 "지금 캡처하면
--- 안 된다"를 따로 판단해야 했다. 지금은 버튼 하나의 상태라 그럴 일이 없다.
function DebindFrameMixin:IsCapturingKey()
	return self.bindingMode == true;
end


--- 과녁을 듣는 상태로 넣고 뺀다.
---
--- The keyboard and the gamepad are on only while it is listening. What listens is the one toggle in
--- the portrait row, and that widget does not come out of a pool - so the case the old shape had to
--- carry, "the row that was listening scrolled away", cannot arise here.
function DebindFrameMixin:SetBindingMode(active, button)
	-- **고른 액션이 없어도 켠다.** 예전에는 행의 키 버튼이 자기 액션을 먼저 고르고 들어와서
	-- 여기서 그걸 요구할 수 있었다. 지금은 모드가 먼저 켜지고 대상은 **그때그때 커서 밑의
	-- 행**이라, 켜는 시점에 고른 것이 없는 게 정상이다.
	active = active or false;
	if (self:IsCapturingKey() == active) then
		return;
	end
	self.bindingMode = active or nil;
	self:UpdateBindModeButton();
	DebindResultPanel.BindOverlay:SetShown(active);

	if (active) then
		-- 되돌릴 목록을 연다. 액션을 키로 잡으므로 **탭에 걸쳐 산다** - 탭 A에서 셋, 탭 B에서
		-- 둘을 걸어도 취소는 다섯을 전부 되돌린다.
		self.bindEdits = {};

		-- **선택을 비운다.** 선택은 "지금 이 액션 이야기 중"이라는 뜻인데 모드의 대상은 커서
		-- 밑의 행이라, 남겨두면 강조가 가리키는 것과 실제로 키가 걸릴 곳이 어긋난다.
		self.LayerPanel:SetSelectedAction(nil);
	else
		-- 여기로 오는 것은 전부 **커밋**이다(오버레이의 [종료], 창이 숨는 경우, 토글 다시 누르기).
		-- 되돌리는 쪽은 CancelBindMode가 목록을 먼저 챙긴 뒤에 이 함수를 부른다.
		self.bindEdits = nil;
	end

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
	-- 켜져 있다는 표시는 **포트레잇이 이미 가진 것**을 쓴다 - 테두리 채도와 그 위의 어두운 판
	-- (`SetSelectedState`). 여기 있던 것은 블리자드 단축키 버튼의 사각 텍스처를 버튼 전체에
	-- 덮는 방식이었고(CustomBindingButtonTemplate), 31x31 원형 위에서는 그 사각형이 그대로
	-- 비어져 나온다. 옆의 두 포트레잇이 메뉴를 연 동안 켜는 표시와도 이제 같은 것이다.
	button:SetSelectedState(active);
	button:EnableKeyboard(active);
	button:EnableMouseWheel(active);
	if (button.EnableGamePadButton) then
		button:EnableGamePadButton(active);
	end
	if (active) then
		-- 편집칸이 키보드 포커스를 들고 있으면 **양쪽이 다 받는다.** 포커스 잡힌 EditBox와
		-- 키보드를 켠 이 과녁에 같은 키가 각각 들어가서, 한 번 누른 것이 글자로도 들어가고
		-- 단축키도 바꾼다 - 한 번의 입력이 두 가지 일을 한다. 이 창의 검색창은 없앴지만
		-- 주문 선택 창과 매크로 편집기가 아직 EditBox를 들고 있다.
		--
		-- 마우스 위치는 상관이 없다. 키보드는 마우스가 패널 밖에 있어도 들어온다(잡히지 않는
		-- 건 클릭뿐이다). 그래서 "패널 위에서만 듣는다"로는 막을 수 없고, 듣기 시작할 때
		-- 포커스를 거두는 수밖에 없다.
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
		-- **좌클릭만이다.** 과녁이 행 버튼이던 시절에는 그 행이 좌우를 다 받았으므로 여기서
		-- 둘을 되돌리는 것이 맞았는데, 지금 과녁은 토글 하나다. 둘로 되돌리면 XML이 준 적
		-- 없는 우클릭 입구가 **첫 번째 모드를 끝낸 뒤부터** 생긴다 - 그 뒤로는 토글을
		-- 우클릭해도 모드가 켜진다.
		button:RegisterForClicks("LeftButtonUp");
		-- 여기서 SetPropagateKeyboardInput(true)로 되돌리면 안 된다. ESC로 빠져나오는 그
		-- 순간에 다시 켜지면서 **같은 ESC가 프레임까지 흘러가 창을 닫는다.** 키보드 자체를
		-- 끄므로 이 값은 어차피 다음에 들을 때까지 아무 일도 하지 않는다.
	end

	DebindResultPanel:Refresh();
	self:Update();
end

--- 토글의 말은 **지금 무엇을 하는 버튼인가**다. 켜져 있으면 "끝내기" - 켜진 상태에서
--- "키 지정"이라고 적혀 있으면 눌러야 시작되는 것처럼 읽힌다.
---
--- 그 말이 이제 툴팁 제목이다. 버튼에 글자가 있던 시절에는 제목이 늘 "키 지정"으로 고정이어도
--- 상태는 버튼 위에 적혀 있었는데, 포트레잇에는 적을 자리가 없다.
---
--- **켜져 있는 동안에는 설명을 뗀다.** `BIND_MODE_DESC`는 "이 모드를 켠다"고 말하는 문장이라
--- 이미 켜진 버튼 위에서는 거짓이고, 그때 필요한 말 - 어떻게 걸고 어떻게 끝내는지 - 는
--- 오버레이가 이미 화면에 띄워 두고 있다.
function DebindFrameMixin:UpdateBindModeButton()
	local button = self.OverviewPanel.BindModePortrait;
	if (self:IsCapturingKey()) then
		button.TooltipTitle = LLL["BIND_MODE_STOP"];
		button.TooltipText = nil;
	else
		button.TooltipTitle = LLL["BIND_MODE"];
		button.TooltipText = LLL["BIND_MODE_DESC"];
	end
end

--- Turns it on and off. The toggle in the portrait row is what calls this.
function DebindFrameMixin:ToggleBindMode()
	self:SetBindingMode(not self:IsCapturingKey(), self.OverviewPanel.BindModePortrait);
end

--- 커서 밑의 행. **들고 있지 않고 그때그때 찾는다.**
---
--- 행은 풀에서 돌아가므로 "지금 호버된 행"을 변수로 들고 있으면 스크롤 한 번에 그 포인터가
--- 남의 행을 가리킨다. 보이는 행은 많아야 열 몇이고 묻는 것은 키를 누를 때뿐이라, 그때
--- 훑는 편이 상태를 맞춰 두는 것보다 싸고 틀릴 데가 없다.
---
--- **`IsMouseOver`가 아니라 `IsMouseMotionFocus`다.** 앞의 것은 프레임 사각형만 보는 기하
--- 판정이라 ScrollBox가 잘라낸 행에도 참이 된다 - 목록 위쪽 바깥에서 ESC를 누르면 취소가
--- 아니라 **화면에 없는 행의 키를 지우는** 갈래로 들어갔다(아래 ESCAPE 처리).
---
--- 뒤의 것은 `OnEnter`/`OnLeave`가 걸리는 바로 그 조건이라, 판정이 강조 표시와 언제나 같다.
--- 행 템플릿에 마우스를 먹는 자식이 없어서(XML의 DebindLineTemplate) 자식에게 포커스를
--- 빼앗길 일도 없다.
local function GetHoveredLine()
	local hovered;
	DebindLayerPanel.ScrollBox:ForEachFrame(function(frame)
		if (not hovered and frame.GetElementData and frame:IsMouseMotionFocus()) then
			hovered = frame;
		end
	end);
	return hovered;
end

--- 키보드·마우스·휠·게임패드가 모두 지나는 길목.
---
--- **대상은 커서 밑의 행이다.** 클릭과 휠은 그 행이 직접 불러서 자기를 넘기고(누가
--- 받았는지 이미 알고 있다), 키보드는 프레임 하나로 들어오므로 여기서 찾는다.
---
--- **넣고 나서도 모드는 켜진 채다.** 그게 모드인 이유다 - 열 개를 걸 사람이 열 번 들어갔다
--- 나오지 않아도 된다. 나가는 길은 토글과 ESC 둘뿐이고, 둘 다 목록 밖의 동작이다.
function DebindFrameMixin:BindMode_OnInput(input, line)
	if (not self:IsCapturingKey()) then
		return;
	end
	if (IsMetaKey(input) or input == "UNKNOWN") then
		return;
	end

	line = line or GetHoveredLine();
	local elementData = line and line.GetElementData and line:GetElementData();
	local action = elementData and elementData.action;
	if (not action) then
		return;
	end

	local key = GetConvertedKeyOrButton(input);
	key = _CreateKeyChordStringUsingMetaKeyState(key);
	self:SetActionKey(action, key);
end

--- 모드가 켜진 동안 키보드는 **토글 버튼 하나로** 들어온다. 커서가 어디에 있든 그렇다.
function DebindFrameMixin:BindMode_OnKeyDown(button, key)
	if (not self:IsCapturingKey()) then
		button:SetPropagateKeyboardInput(true);
		return;
	end
	-- 전투 중 SetPropagateKeyboardInput은 taint다. 전투에 들어가면 창이 숨고 OnHide가
	-- 모드를 끄므로 보통은 여기까지 오지 않지만, 전투가 시작된 바로 그 프레임에 눌린 키는
	-- PLAYER_REGEN_DISABLED보다 먼저 들어올 수 있다. 그 한 프레임을 여기서 막는다.
	if (InCombatLockdown()) then
		return;
	end
	button:SetPropagateKeyboardInput(false);

	-- **ESC는 가리킨 것이 있으면 지우개, 없으면 취소다.** 둘 다 와우가 하는 그대로다:
	-- 빠른 키 지정 모드에서 과녁을 가리키는 중이면 ESC가 그 바인딩을 지우고
	-- (QuickKeybind.lua:201, 툴팁 문구는 클라이언트 전역 ESCAPE_TO_UNBIND), 가리키는 것이
	-- 없으면 `CancelBinding`으로 간다 - 그건 `LoadBindings(GetCurrentBindingSet())`으로
	-- **그 세션에 바꾼 것을 통째로 되돌리고** 닫는다(QuickKeybind.lua:178).
	--
	-- 지우개 쪽은 우리에게 필연이기도 하다. 좌·우·가운데·4·5·휠·DELETE까지 전부 걸 수 있는
	-- 키라, 모드 안에서 "이건 지우기"로 쓸 수 있는 입력이 ESC 말고는 남지 않는다.
	--
	-- 값이 큰 쪽이 빗나가기 쉬운 자리에 있다는 것은 안다 - 행을 겨냥하다 몇 픽셀 빗나가면
	-- 지우기가 아니라 전체 취소가 된다. 그래도 게임의 같은 모드와 같은 손버릇이 되는 편이
	-- 우리만의 규칙을 하나 더 만드는 것보다 낫다. 되돌린 것을 되살릴 길은 없다.
	--
	-- 두 갈래를 오버레이의 둘째 줄이 말한다(`BIND_MODE_UNBIND_HINT`).
	if (key == "ESCAPE") then
		local line = GetHoveredLine();
		local elementData = line and line:GetElementData();
		local action = elementData and elementData.action;
		if (action) then
			self:SetActionKey(action, nil);
		else
			self:CancelBindMode();
		end
		return;
	end
	self:BindMode_OnInput(key);
end

--- **모드에 들어온 뒤 바뀐 키를 전부 되돌리고 나간다.** 직전 하나가 아니다.
---
--- 목록을 먼저 챙기는 이유는 `SetBindingMode(false)`가 그걸 비우기 때문이다(거기로 가는 다른
--- 길은 전부 커밋이라 비우는 것이 맞다).
---
--- 되돌린 뒤 바인딩을 **한 번만** 다시 올린다. 액션마다 UpdateBindings를 부르면 스무 개를
--- 되돌릴 때 스무 번 올라간다.
function DebindFrameMixin:CancelBindMode()
	local edits = self.bindEdits;
	self:SetBindingMode(false);
	if (not edits) then
		return;
	end

	local changed;
	local restored;
	for action, original in pairs(edits) do
		-- The badge is restored with the other two. Giving a key inside the mode accepts what
		-- arrived (`SetActionKey`), and leaving it accepted after a cancel would be the one change
		-- of the session that the reader cannot take back - the badge is never handed out again.
		if (action.key ~= original.key or action.seq ~= original.seq or action.arrivalID ~= original.arrivalID) then
			action.key = original.key;
			action.seq = original.seq;
			action.arrivalID = original.arrivalID;
			changed = true;
			restored = restored or {};
			restored[#restored + 1] = action;
		end
	end

	-- **Renumber the group each one comes back to.** What is restored is the actions written down
	-- here, but an action passing through another group during the mode renumbered that group's
	-- **other** members on the way in and out, and none of them are written down. Coming back, the
	-- group has closed up in the meantime, so the old number handed back can already be somebody
	-- else's -- and two rows on one number are tied, which makes the order differ from one sort to
	-- the next.
	if (restored) then
		for i = 1, #restored do
			DebindPrivate.RenumberKeyGroupForAction(restored[i]);
		end
	end

	if (changed) then
		DebindPrivate.UpdateBindings();
		self.LayerPanel:Refresh(true);
		self:Update();
		DebindResultPanel:Refresh();
	end
end

--- 듣기를 그만둔다. 선택은 건드리지 않는다.
---
--- 예전에는 키 없는 액션에서 오버레이가 늘 걸려 있어서 "선택을 푸는 것"이 유일한 출구였고,
--- 그래서 선택을 지킬지 말지를 인자로 받았다. 듣는 상태가 사용자가 연 것이 되면서 그냥
--- 나오면 되므로 인자도 사라졌다.
function DebindFrameMixin:CancelKeyCapture()
	self:SetBindingMode(false);
end

--- 키를 저장하고 되비춘다. 목록이 키순으로 정렬돼 있으므로 왼쪽 자리도 바뀐다 - 그 자리가
--- 화면 밖이면 따라간다. 목록이 움직이는 이유가 사용자가 방금 누른 키 하나뿐이라, 어디로
--- 갔는지 보여주는 편이 놀래키는 것보다 낫다.
---
--- **Giving a key always lands at the back of that group**, whether the action has held the key
--- before or never had one. There is nothing to tell those apart -- the number is dropped when the
--- key goes (`ClearActionKey`) -- and detecting it would not help: days later the reader does not
--- know this action was once on this key, so a position they cannot account for reads the same
--- either way.
---
--- Once the last ordering step read the action's slot in the layer array. A freshly made action was
--- at the end of it and went last, while one that had been sitting near the front cut in above
--- everything -- the same gesture with two different results, which is what the number replaced.
---
--- **It takes a target.** It used to act on the selected action and needed no argument; in binding
--- mode the target is the row under the cursor, which can be a different one.
function DebindFrameMixin:SetActionKey(action, key)
	if (not action or action.key == key) then
		return false;
	end

	-- Binding mode's transaction. **Written once per action** -- change the same action three times
	-- inside the mode and what cancelling restores still has to be what it held on the way in.
	--
	-- All three fields the branch below writes are written down, not just the key. `seq` moves with
	-- it, and so does the badge; putting back only the key would leave the action holding a number
	-- from the session that was cancelled, or accepted by a session that was not.
	local edits = self.bindEdits;
	if (edits and edits[action] == nil) then
		edits[action] = { key = action.key, seq = action.seq, arrivalID = action.arrivalID };
	end

	-- **Both directions go through `Profile.lua`, and neither is written here.** Giving the key
	-- puts the action at the back of that group and renumbers it; taking it away drops the number
	-- and renumbers the group it left. Spelling either out at this call site would put the rule in
	-- two places, and this is not the only way in.
	--
	-- **Giving a key to something that arrived takes the badge off it.** Deciding the key is the
	-- reader saying yes; there is nothing further to approve about an action they just put on their
	-- own keyboard, and the set's own path has read it that way all along (`SetKeyForActions`).
	--
	-- **Only this direction.** [Unbind Key] settles nothing: it takes a key away rather than deciding
	-- one, so it is not the reader taking the action.
	local accepted;
	if (key ~= nil) then
		accepted = action.arrivalID ~= nil;
		action.key = key;
		action.arrivalID = nil;
		DebindPrivate.PlaceActionInKeyGroup(action);
	else
		DebindPrivate.ClearActionKey(action);
	end
	-- One set for the two below it, built after the two fields the filters read are settled
	-- (`NarrowedVisibleActions`).
	local visible = NarrowedVisibleActions();
	-- `imported` is one of the axes the filters read, so a row that just lost its badge can be one
	-- this list no longer draws - and the selection would go on counting it while nothing on screen
	-- is highlighted (`ApproveArrivedActions` carries the same call for the same reason).
	if (accepted) then
		self:PruneSelectionToBinFilter(visible);
	end
	DebindPrivate.UpdateBindings();
	self.LayerPanel:Refresh(true, visible);
	self.LayerPanel:ScrollActionIntoView(action);
	-- 키가 바뀌면 왼쪽 열에서 자리를 통째로 옮긴다 - 그 열은 키로 묶고 키로 정렬한다. 간 자리가
	-- 화면 밖이면 아무 일도 안 일어난 것처럼 보이므로 따라간다. 오른쪽 목록은 저 위에서 따로
	-- 굴린다(`ScrollActionIntoView`) - 두 열은 서로의 스크롤을 안 본다.
	--
	_revealAction = action;
	self:Update();
	return true;
end


--------------------------------------------------------------------------------
-- Giving a whole key group one key
--
-- Several actions on one key, told apart by conditions, is this addon's ordinary state, so moving
-- a key is a thing done to a **key group** rather than to an action. One at a time splits the group
-- the moment one of four is missed, and for a group that arrived without a key it also loses the
-- sender's ordering (`SetKeyForActions` in `Profile.lua`).
--
-- Three steps: pick the group from a menu -> press the key to give it -> answer if that key is
-- already carrying something.
--------------------------------------------------------------------------------

--- Once, after everything is written. Per action, moving one group would raise the bindings as many
--- times as it has members.
---
--- **The filters are left alone.** Giving a group a key is the reader accepting it
--- (`SetKeyForActions`), so the last badge can come off at this point; the tick that narrows to
--- [Pending] is still the reader's to clear, the same as everywhere else.
---
--- **And the set is followed to where it went.** A changed key moves its whole place in the left
--- column, which groups and sorts by key, and if the new place is off screen the operation looks
--- like it did nothing. Same thing `SetActionKey` does for a single action; here the target is the
--- set's **first row** - first in firing order, so it sits right under the heading, and seeing it
--- is seeing the set.
---
--- **A row and not the heading, even though a set is what moved.** Scrolling to the heading was
--- built and taken back out: nothing marks a heading, so the reader arrives and still has to work
--- out which of them it is. Asking for the row brings the heading along (`RevealRow` does that on
--- its own) and the selection highlight underneath answers "which one" with the one marker this
--- column has.
---
--- Selecting and scrolling are both needed. Selecting marks which row it is and asks the left
--- column to find it (`SetSelectedAction` sets `_revealAction`); the right list does not watch that
--- column, so it is rolled separately.
---
--- **`key` may be nil, and then there is no group to walk.** Unbinding clears the key outright
--- (`ClearKeyForActions`), so what is left is rows of their own in the pile at the bottom and each
--- is its own answer - `CollectActionsForKey` has nothing to say about a key that is not there.
local function RebuildAfterKeyGroupChange(actions, key)
	DebindPrivate.UpdateBindings();
	DebindLayerPanel:Refresh(true);

	local target;
	if (key == nil) then
		target = actions[1];
	else
		local moved = {};
		for _, action in ipairs(actions) do
			moved[action] = true;
		end
		for _, row in ipairs(DebindPrivate.CollectActionsForKey(key)) do
			if (moved[row.action]) then
				target = row.action;
				break;
			end
		end
	end

	if (target) then
		DebindLayerPanel:SetSelectedAction(target);
		DebindLayerPanel:ScrollActionIntoView(target);
	end

	DebindFrame:Update();
end

--- 차 있는 키에 답이 정해졌을 때 실제로 옮기는 자리. `unbindOccupants`의 두 값이 그 두 답이다
--- (`MoveKeyGroupToKey`).
local function ApplyKeyGroupMove(actions, key, occupants, unbindOccupants)
	DebindPrivate.MoveKeyGroupToKey(actions, key, occupants, unbindOccupants);
	RebuildAfterKeyGroupChange(actions, key);
end

--- Asked when the key that was pressed is already carrying something.
---
--- **The count is what the question is for.** This operation reaches past the screen -
--- `CollectKeyGroupActions` walks the eleven layers this character has, and with [Only what came in]
--- on, the reader's own group holding that key is hidden entirely - and the number standing there
--- before the press is how that is paid for. `ApproveAllImported` reaches past the screen the same
--- way and answers it the same way, with a count standing beside the press rather than in a box.
local function ShowKeyGroupConflictDialog(actions, key, occupants, label)
	StaticPopup_Show("DEBIND_KEY_GROUP_CONFLICT", nil, nil, {
		actions = actions,
		key = key,
		occupants = occupants,
		label = label,
	});
end

--- The answer, once a key has been taken from the reader. **Whatever asked for it is already gone**
--- by the time this runs - a question may come up here, and nothing should still be listening for
--- keys over it.
local function GiveKeyGroupTheKey(actions, key, label)
	-- The moving group is not its own occupant. Without subtracting it, someone giving a group the
	-- key it already has would be asked "F already has 3" about the very actions being moved, and
	-- picking overwrite would take their key from themselves.
	local moving = {};
	for _, action in ipairs(actions) do
		moving[action] = true;
	end

	local occupants = {};
	for _, action in ipairs(DebindPrivate.CollectKeyGroupActions(key)) do
		if (not moving[action]) then
			occupants[#occupants + 1] = action;
		end
	end

	-- **A free key asks nothing.** This is the common path - giving a group that came in a key the
	-- reader was not using.
	if (#occupants == 0) then
		ApplyKeyGroupMove(actions, key, nil, false);
		return;
	end

	ShowKeyGroupConflictDialog(actions, key, occupants, label);
end

local SharedKeyOf = DebindPrivate.SharedKeyOf;

--- How many of what was handed in would come apart: the size of every key group with two or more
--- members inside this list, added up.
---
--- **Counted inside the list, not in the profile.** Unbinding two of a group of four leaves the
--- other two together, and what the reader loses is that those two were with them. One member alone
--- in here loses nothing that was not already only its own.
---
--- The group is `(key, arrivalID)`, which is what keeps an arrival on the reader's key from being
--- counted as part of their set.
local function ScatteredByUnbinding(actions)
	local sizes, order = {}, {};
	for i = 1, #actions do
		local action = actions[i];
		if (action.key ~= nil) then
			local groupID = action.key .. "/" .. tostring(action.arrivalID);
			if (sizes[groupID] == nil) then
				order[#order + 1] = groupID;
			end
			sizes[groupID] = (sizes[groupID] or 0) + 1;
		end
	end

	local scattered = 0;
	for i = 1, #order do
		local size = sizes[order[i]];
		if (size >= 2) then
			scattered = scattered + size;
		end
	end
	return scattered;
end

--- What the question about an occupied key calls the thing that is moving (`KEY_GROUP_CONFLICT`).
---
--- Three shapes, and the sentence has to name the one the reader is looking at: one action is called
--- by its name, a set by the key it is on - the same words its heading uses (`KeyGroupLabel`) - and
--- a selection by how many were ticked, which is the only thing true of all of them and the same
--- words the bulk menu's own title uses.
local function CaptureLabel(actions)
	if (#actions == 1) then
		return (NameAndIconForAction(actions[1]));
	end

	local key, shared = SharedKeyOf(actions);
	if (shared) then
		-- **The heading's words.** A set is named by the key it is on, arrival or not, and this
		-- prompt calling it something else would put one set under two names inside a single press.
		return KeyGroupLabel(key);
	end
	return format(LLL["BULK_MENU_TITLE"], #actions);
end

--- **Asks for a key, and settles whatever comes back.** One action, a key group, a selection - the
--- window takes 1..n and so does everything below it, which is why the three menus that open it hand
--- in nothing but an array (`{ action }`, `CollectKeyGroupActions`, `GetSelectedActions`).
---
--- **It asks in a dialog** (`KeyCapture.lua`). The other shape - arming the bind mode with the set
--- and letting the overlay name it instead of pointing at a row - was built, stood beside this one
--- while the two were compared, and lost; the mode aims at the row under the cursor and nothing
--- else. What separates them is in `devdocs/legacy/asking-for-a-key.md`.
---
--- **The occupied-key question is asked by occupancy and not by size.** It used to be the set's
--- question alone, with a single action moving in beside whatever was there and saying nothing - a
--- split that came from the two paths being written months apart rather than from anything about
--- them. One rule now: if the key the reader picked is already carrying something that is not part
--- of what is moving, they are told what and asked what should happen to it.
function DebindUI.BeginKeyCapture(actions)
	if (actions == nil or #actions == 0) then
		return;
	end

	-- **Named before the window opens.** By the time the answer comes back the actions have moved,
	-- so a set asked about by the key it was on could no longer say which key that was.
	local label = CaptureLabel(actions);

	DebindKeyCaptureFrame:Open(actions, function(captured)
		-- **`nil` is [Unbind Key], not a cancel** -- cancelling never gets here.
		if (captured == nil) then
			DebindUI.UnbindActions(actions);
			return;
		end
		GiveKeyGroupTheKey(actions, captured, label);
	end);
end

--- Takes the key off, having asked if a set is about to come apart.
---
--- The rebuild is the function the give-key side uses. Four lines here once transcribed it and one
--- of them was missing - the left column was asked for nothing, so only `ScrollActionIntoView` (the
--- right list) rolled.
---
--- The key is read **after** the release, since that is where it is settled: scattered rows leave
--- `nil` behind, and the rebuild knows that case.
local function ReleaseAndRebuild(actions)
	DebindPrivate.ClearKeyForActions(actions);
	RebuildAfterKeyGroupChange(actions, actions[1].key);
end

--- [Unbind], from either place that offers it: the menu item, and the dialog's [Unbind Key] button
--- (`BeginKeyCapture`, where a nil capture comes back). **One function, because a menu offering the
--- button's other half must not be able to mean something else by it.**
---
--- **It asks when a set would come apart.** Taking the key off is what breaks a group up, and
--- nothing records that those actions were ever one thing (`ClearKeyForActions`) -- so a reader who
--- does not remember the membership has no way back. One action alone is not asked about: there is
--- no set there to lose, which is the same line the entry's action delete draws
--- (`devdocs/building-export-import.md` 12절).
---
--- Cancelling does nothing at all. It does not reopen the dialog the button was on either: that
--- dialog has already closed and asking for a key again is a fresh press.
function DebindUI.UnbindActions(actions)
	if (actions == nil or #actions == 0) then
		return;
	end

	local scattered = ScatteredByUnbinding(actions);
	if (scattered < 2) then
		ReleaseAndRebuild(actions);
		return;
	end

	StaticPopup_Show("DEBIND_UNBIND_SCATTERS", scattered, nil, { actions = actions });
end

--- Is any of what already holds the key **shared with other characters**.
---
--- The layer's own `isCharacterSpecific`, which is the same question the importance menu asks before
--- it warns (`PRIORITY_SHARED_WARNING`). Two of the eleven layers belong to the class and one to the
--- account, so "take the key from them" can reach every character the reader has - and the count in
--- the prompt above cannot show that on its own.
local function AnySharedOccupant(occupants)
	for _, action in ipairs(occupants) do
		local _, layer = DebindPrivate.FindLayerID(action);
		if (layer and not layer.isCharacterSpecific) then
			return true;
		end
	end
	return false;
end

--- Hangs a tooltip on one of a dialog's buttons, or takes it off again when `title` is nil.
---
--- **`StaticPopup` has no field for this**, so it is scripts put on and taken off around each
--- showing. Set rather than hooked: hooks stack, and this runs every time the dialog is shown.
local function SetPopupButtonTooltip(button, title, text)
	if (not button) then
		return;
	end

	if (title == nil) then
		button:SetScript("OnEnter", nil);
		button:SetScript("OnLeave", nil);
		return;
	end

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, title);
		GameTooltip_AddNormalLine(GameTooltip, text);
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", GameTooltip_Hide);
end

--- The two answers to an occupied key, plus stopping.
---
--- **`OnButton1..3`, not `OnAccept`/`OnCancel`.** Slot 2 is where the client expects cancel to sit,
--- so an `OnCancel` there would be reached by Escape as well (`StaticPopup_EscapePressed`) - and
--- slot 2 here is [overwrite]. With all three attached by number, Escape falls through to
--- `hideOnEscape` and closes without choosing any of them.
StaticPopupDialogs["DEBIND_KEY_GROUP_CONFLICT"] = {
	-- 문장만 여는 시점에 짓는다. 인자가 셋이라 `StaticPopup_Show`의 `text_arg1/2`로는 모자란다 -
	-- 클라이언트의 `GENERIC_CONFIRMATION`이 같은 이유로 같은 모양이다.
	text = "",
	button1 = LLL["KEY_GROUP_CONFLICT_KEEP"],
	button2 = LLL["KEY_GROUP_CONFLICT_UNBIND"],
	button3 = CANCEL,
	-- **Without this the second button is dead.** It is what makes `StaticPopup_OnClick` dispatch by
	-- number; without it the call falls to the backward-compatible branch, where 1 resolves
	-- `OnAccept or OnButton1`, 3 resolves `OnAlt`, and **everything else resolves `OnCancel`** --
	-- which this dialog does not have, so [overwrite] would close and do nothing at all. Blizzard's
	-- own three-button dialog (`GAME_SETTINGS_CONFIRM_DISCARD`) carries it for the same reason.
	selectCallbackByIndex = true,
	OnShow = function(dialog, data)
		-- **경고는 문장에 이어 붙여서 `SetFormattedText`에 함께 넘긴다.** 이 대화상자의 글은
		-- 저 함수 하나로만 세워봤고, 붙인 문자열에는 서식이 없으므로 인자는 그대로다.
		local text = LLL["KEY_GROUP_CONFLICT"];
		if (AnySharedOccupant(data.occupants)) then
			text = text .. "|n|n" .. LLL["KEY_GROUP_CONFLICT_SHARED"];
		end
		dialog:SetFormattedText(text, data.label, KeyGroupLabel(data.key), #data.occupants);

		-- 두 답이 무엇을 하는지는 낱말 두 개로는 안 나온다. **하나는 지정을 걷어내는 답이고**,
		-- 이 창은 이 애드온에서 되돌리기가 제일 비싼 자리다.
		SetPopupButtonTooltip(dialog:GetButton(1),
			LLL["KEY_GROUP_CONFLICT_KEEP"], LLL["KEY_GROUP_CONFLICT_KEEP_DESC"]);
		SetPopupButtonTooltip(dialog:GetButton(2),
			LLL["KEY_GROUP_CONFLICT_UNBIND"], LLL["KEY_GROUP_CONFLICT_UNBIND_DESC"]);
	end,
	-- **툴팁은 반드시 떼어낸다.** 대화상자 프레임은 풀에서 돌아가므로, 남겨두면 다음에 그
	-- 프레임을 쓰는 남의 팝업이 우리 툴팁을 달고 뜬다.
	OnHide = function(dialog)
		SetPopupButtonTooltip(dialog:GetButton(1), nil, nil);
		SetPopupButtonTooltip(dialog:GetButton(2), nil, nil);
	end,
	OnButton1 = function(_, data)
		ApplyKeyGroupMove(data.actions, data.key, data.occupants, false);
	end,
	OnButton2 = function(_, data)
		ApplyKeyGroupMove(data.actions, data.key, data.occupants, true);
	end,
	-- **An empty function, and it is not decoration: without it the button is dead.** Under
	-- `selectCallbackByIndex` the `dialog:Hide()` sits *inside* `if func then`
	-- (`StaticPopup_OnClick`), so a button with nothing attached neither answers nor closes. Only
	-- the backward-compatible branch below it defaults to hiding. `GAME_SETTINGS_CONFIRM_DISCARD`,
	-- the dialog this one borrowed `selectCallbackByIndex` from, carries the same empty third.
	OnButton3 = function() end,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
	wide = 1,
};

--- **The one thing here that cannot be walked back.** Nothing is deleted, so every action can be
--- given a key again one at a time -- but which of them belonged together is not written down
--- anywhere, and after this it is only in the reader's head.
StaticPopupDialogs["DEBIND_UNBIND_SCATTERS"] = {
	text = LLL["UNBIND_SCATTERS_CONFIRM"],
	button1 = LLL["UNBIND_SCATTERS_CONFIRM_YES"],
	button2 = CANCEL,
	OnAccept = function(_, data)
		ReleaseAndRebuild(data.actions);
	end,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
};

--- Asked once for the whole batch, when accepting everything would take keys the reader is using.
---
--- **Three answers and each names a winner**, which is what lets the reader read the set rather than
--- each label: mine, theirs, or both. The loser is the other one, and what happens to it is the
--- tooltip's.
---
--- **Four buttons, and the safest is first.** Button 1 is where Enter lands, and the answer that
--- touches nothing of the reader's is the one that belongs under a key they may be holding down.
---
--- **`KEY_GROUP_CONFLICT` shares `Merge` and nothing else.** That prompt asks after the reader picked
--- a key for a set, so "keep mine" there is "do not do what I just asked" -- which is Cancel -- and
--- the set moving in is not always an arrival. One word means one thing in both; the rest differ
--- because the questions do.
---
--- **Cancel accepts nothing.** Half a batch is not one of the answers: the reader is being asked
--- about the keys, and there is no half-answer to that.
StaticPopupDialogs["DEBIND_APPROVE_ALL_OCCUPIED"] = {
	text = LLL["APPROVE_ALL_OCCUPIED"],
	button1 = LLL["APPROVE_ALL_KEEP_EXISTING"],
	button2 = LLL["APPROVE_ALL_TAKE_INCOMING"],
	button3 = LLL["KEY_GROUP_CONFLICT_KEEP"],
	button4 = CANCEL,
	-- Without this every button but the first is dead, for the reason `DEBIND_KEY_GROUP_CONFLICT`
	-- spells out.
	selectCallbackByIndex = true,
	OnShow = function(dialog)
		SetPopupButtonTooltip(dialog:GetButton(1),
			LLL["APPROVE_ALL_KEEP_EXISTING"], LLL["APPROVE_ALL_KEEP_EXISTING_DESC"]);
		SetPopupButtonTooltip(dialog:GetButton(2),
			LLL["APPROVE_ALL_TAKE_INCOMING"], LLL["KEY_GROUP_CONFLICT_UNBIND_DESC"]);
		SetPopupButtonTooltip(dialog:GetButton(3),
			LLL["KEY_GROUP_CONFLICT_KEEP"], LLL["KEY_GROUP_CONFLICT_KEEP_DESC"]);
	end,
	OnHide = function(dialog)
		SetPopupButtonTooltip(dialog:GetButton(1), nil, nil);
		SetPopupButtonTooltip(dialog:GetButton(2), nil, nil);
		SetPopupButtonTooltip(dialog:GetButton(3), nil, nil);
	end,
	OnButton1 = function(_, data)
		ApproveArrivedActions(data.arrivals, data.occupants, data.contested, "mine");
	end,
	OnButton2 = function(_, data)
		ApproveArrivedActions(data.arrivals, data.occupants, data.contested, "theirs");
	end,
	OnButton3 = function(_, data)
		ApproveArrivedActions(data.arrivals, data.occupants, data.contested, "merge");
	end,
	-- Empty and not decoration, for the reason `DEBIND_KEY_GROUP_CONFLICT` spells out.
	OnButton4 = function() end,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
	wide = 1,
};


--------------------------------------------------------------------------------
-- 매크로 편집 창
--
-- **Closing the window is the commit.** Every path that hides this window writes the body:
-- [Close], the X, ESC, the main window going away, the selection moving to another action,
-- combat. Blizzard's macro window works the same way and its OnHide is where SaveMacro() runs
-- (Blizzard_MacroUI.lua).
--
-- **Which is why there is no [Save] and no [Okay].** A button that reads as the one that saves
-- says the opposite of what happens here: that nothing is written until it is pressed. The reader
-- has no way to find out otherwise except by losing something. The bottom row is [Close] and the
-- button that puts the body back.
--
-- 그래서 저장을 미루는 상태가 없다. HasUnsavedChanges / 저장-버림 팝업 / Close(force)
-- 계약은 이 창이 탭이던 시절에 이미 사라졌고, 창으로 돌아왔다고 되살리지 않는다.
--
-- **And nothing commits while the window is up**, which is what makes [Cancel] worth having:
-- `action.value` stays the body the window opened on, so that button always has the exact text to
-- go back to. The name/icon editor used to save on its way to the popup and it was the one thing
-- that broke this (EditNameIcon_OnClick).
--
-- **대상은 선택된 액션이다.** 창이 자기 대상을 따로 들고 있지 않으므로 왼쪽 목록의 강조가
-- 곧 "지금 무엇을 고치고 있나"이고, 다른 행을 고르면 이 창은 닫힌다(그러면서 저장된다).
--
-- 편집 대상(macroAction)은 **창이 열려 있는 동안만** 산다. OnHide가 저장하고 비운다.
--------------------------------------------------------------------------------

DebindMacroFrameMixin = {};

function DebindMacroFrameMixin:OnLoad()
	-- 편집칸은 보이는 만큼만 크고, 넘치는 본문은 스크롤로 간다(기본 매크로 창도 편집칸과
	-- 스크롤 영역이 같은 크기다). 창 크기를 XML에 박아두더라도 여기서 한 번 맞춰야
	-- ScrollFrame의 실제 크기를 따라간다.
	local editor = self.Editor;
	editor.ScrollFrame.EditBox:SetMaxLetters(MACRO_CHAR_LIMIT);
	editor.ScrollFrame:SetScript("OnSizeChanged", function(scrollFrame, width, height)
		scrollFrame.EditBox:SetSize(width, height);
	end);

end

--- Opens the window on this action.
---
--- The window only ever draws the selected action, so **it moves the selection onto its target.**
--- The ways in (the right-click menu, the conversion) can name a row the selection is nowhere near.
---
--- Called with an action that is not macrotext, it closes again at once (`Refresh`). The conversion
--- path changes the action first, so it does not go down that branch.
---
--- `cancelFunc` is how the conversion path gets its action back, and it is also what turns the
--- bottom-right button into [Revert] (`UpdateRevertButton`). It goes on **after** `Refresh`, which
--- clears it while loading the body: the one it clears belongs to whatever was being edited before.
function DebindMacroFrameMixin:Open(action, cancelFunc)
	if (not action) then
		return false;
	end
	DebindLayerPanel:SetSelectedAction(action);

	self:Show();
	self:Refresh();
	self.macroCancelFunc = cancelFunc;
	self:UpdateRevertButton();

	DebindFrame:Update();
	return true;
end

--- 창을 닫는다. 저장은 OnHide가 한다 - 닫는 길이 여럿이라(X 버튼, `TryCloseAnyDialog`,
--- 메인 창이 닫히면서 딸려 감) 한 군데로 모아야 한 번도 안 새어 나간다.
---
--- 언제나 true다. 이 창은 아무것도 막지 않는다.
function DebindMacroFrameMixin:Close()
	if (self:IsShown()) then
		self:Hide();
	end
	return true;
end

function DebindMacroFrameMixin:OnHide()
	self:Save();
	self:ClearEdit();
	DebindFrame:Update();
end

--- 본문을 편집칸에 올린다. **대상이 바뀔 때만** 부른다 - Refresh는 자주 도는데 거기서
--- 매번 넣으면 타이핑이 지워진다.
---
--- `macroOriginalText`는 여기서만 정해진다. [취소]가 돌아갈 자리이므로 편집이 사는 동안
--- (= 이 액션이 선택돼 있는 동안) 움직이지 않는다.
function DebindMacroFrameMixin:LoadText(action)
	self.macroAction = action;
	self.macroCancelFunc = nil;
	self.macroOriginalText = action.value or "";
	self.Editor.ScrollFrame.EditBox:SetText(self.macroOriginalText);
	-- `SetText` reaching `Text_OnTextChanged` would do this, but it does not have to fire when the
	-- box already holds that exact string - which is what reopening on the same action looks like.
	self:UpdateRevertButton();
end

--- 편집 상태만 비운다. 화면 갱신은 부르는 쪽이 한다.
function DebindMacroFrameMixin:ClearEdit()
	self.macroAction = nil;
	self.macroCancelFunc = nil;
	self.macroOriginalText = nil;
end

--- Writes the edit box into the action, and only when it differs. Same idea as the base macro
--- window's textChanged check.
---
--- **`OnHide` is the only caller**, which is what makes closing the window the one commit. Anything
--- else that wants the body written closes the window instead.
---
--- The guard compares against the field it is about to overwrite and not against
--- `macroOriginalText`. The two now hold the same value for as long as the window is up, so either
--- would answer the same; the one that decides whether the profile changes is the one worth asking.
function DebindMacroFrameMixin:Save()
	local action = self.macroAction;
	if (not action) then
		return;
	end

	local text = self.Editor.ScrollFrame.EditBox:GetText();
	if (text == (action.value or "")) then
		return;
	end

	action.value = text;
	DebindPrivate.UpdateBindings();
end

--- The bottom-right button, which carries two meanings on one frame.
---
--- Normally it is [Cancel] and it puts the edit box back to the body the window opened on, so it is
--- enabled only while those two differ. A greyed-out [Cancel] is this window saying that what is on
--- screen is what is in the profile.
---
--- Opened from the conversion it is [Revert] instead, and it is always enabled: what it undoes has
--- already happened, since the action became macrotext the moment the menu item was clicked.
---
--- **Only that one gets a tooltip.** [Cancel] does exactly what its label says and has no second
--- result to warn about. [Revert] takes the whole action with it.
function DebindMacroFrameMixin:UpdateRevertButton()
	local button = self.Editor.RevertButton;
	if (self.macroCancelFunc) then
		button:SetText(REVERT);
		button:Enable();
		return;
	end

	button:SetText(CANCEL);
	button:SetEnabled(self.Editor.ScrollFrame.EditBox:GetText() ~= (self.macroOriginalText or ""));
end

function DebindMacroFrameMixin:RevertButton_OnEnter(button)
	if (not self.macroCancelFunc) then
		return;
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
	GameTooltip_SetTitle(GameTooltip, REVERT);
	GameTooltip_AddNormalLine(GameTooltip, LLL["MACROFRAME_REVERT_DESC"]);
	GameTooltip:Show();
end

--- [Cancel], or [Revert] when the conversion opened this window.
---
--- **[Cancel] moves the edit box and nothing else.** Nothing has committed the body since the
--- window opened, so `action.value` is still what `macroOriginalText` holds and there is nothing to
--- put back in the profile. It used to write the action too, from the days when the window followed
--- the selection and saved on the way past; both of those are gone.
---
--- [Revert] puts back the **action** rather than the body: `cancelFunc` restores the type, name,
--- icon and unit it had before it became macrotext, and whatever was typed here goes with it. That
--- action is no longer macrotext, so `Refresh` closes the window.
---
--- **[Cancel] does not close, unlike [Close].** Two buttons that both leave would be tidier, but
--- they are not the same risk: [Close] keeps what you see and [Cancel] throws it away. Leaving the
--- window up puts the reverted body in front of you before anything is final, and if the revert was
--- not what you wanted, it is still there to edit. Costing one more click to leave is the cheaper
--- side of that trade.
function DebindMacroFrameMixin:Revert_OnClick()
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

		-- The row's name and icon changed with the type, so the list has to be built again and not
		-- just redrawn in place. `Refresh` is what closes the window now that it is not macrotext.
		self:Refresh();
		DebindLayerPanel:Refresh(true);
		DebindFrame:Update();
		return;
	end

	self.Editor.ScrollFrame.EditBox:SetText(self.macroOriginalText or "");
	self:UpdateRevertButton();
end

--- [Close]. Closing is the whole job: OnHide is where the text is written, and it stays the only
--- place that writes it. Calling Save here too would give the body two commit paths to keep in
--- step for no gain.
function DebindMacroFrameMixin:Close_OnClick()
	PlaySound(SOUNDKIT.GS_TITLE_OPTION_OK);
	self:Close();
end

--- Goes to the name/icon editor. **It does not save on the way**, which the base macro window does
--- (MacroEditButton_OnClick) and we deliberately do not: writing the body here would move the place
--- [Cancel] goes back to, and it would move it on a trip that never touched the body.
---
--- The popup opens **over** this window, which stays up. So the body is still there when you come
--- back, and the tempText juggling this used to need is gone.
function DebindMacroFrameMixin:EditNameIcon_OnClick()
	local action = self.macroAction;
	if (not action) then
		return;
	end

	-- 확인을 눌러도 갈 데가 없다. 이 창이 팝업 아래에 그대로 열려 있고, 새 이름·아이콘은
	-- 팝업이 닫히면서 도는 Update가 되비춘다.
	DebindIconSelectorFrame:OpenForAction(action);
end

function DebindMacroFrameMixin:Text_OnTextChanged(editBox)
	ScrollingEdit_OnTextChanged(editBox, editBox:GetParent());
	self.Editor.CharLimitText:SetFormattedText(
		LLL["MACROFRAME_CHAR_LIMIT"], editBox:GetNumLetters(), MACRO_CHAR_LIMIT);
	self:UpdateRevertButton();
end

--- 창을 되비춘다. 이름·아이콘은 매번, 본문은 창을 열 때 한 번.
--- 아이콘 선택기를 다녀오면 여기서 새 이름·아이콘이 반영된다.
---
--- 선택이 없어지면 닫는다. 대상이 없는 편집기는 보여줄 것도 저장할 것도 없다.
--- 대상이 **달라져도** 닫는다 - 그 이유는 아래 갈래에 적어뒀다.
function DebindMacroFrameMixin:Refresh()
	if (not self:IsShown()) then
		return;
	end

	local action = _selectedAction;
	if (not action) then
		self:Close();
		return;
	end

	-- **매크로텍스트가 아니면 닫는다.** 이 창은 본문 하나를 여는 편집기이고, 편집하던 중에
	-- 다른 액션이 선택됐다는 것은 여기서 할 일이 끝났다는 뜻이다.
	--
	-- 한때 이 자리에 "이 액션은 매크로가 아닙니다 / 전환하시겠습니까" 화면이 있었다. 창을
	-- 띄워둔 채 아무것도 편집할 수 없는 상태를 하나 만드는 값에 비해 얻는 것이 없었다 -
	-- 전환은 우클릭 메뉴에 이미 있고(`CreateConvertToMacroTextMenuItem`), 그 길로 들어오면
	-- 액션이 이미 매크로텍스트라 이 화면을 지나지 않는다.
	if (action.type ~= Constants.MACROTEXT) then
		self:Close();
		return;
	end

	-- **A different action means we are done here.** The window used to follow the selection,
	-- saving the old body on the way past - which read as nothing at all: the text you were
	-- typing went into the profile and the editor was suddenly showing someone else's macro,
	-- with no moment that looked like leaving. Closing makes the leaving visible, and it is the
	-- same answer this function already gives when the selection is empty or not a macro.
	--
	-- It also fixes what the revert point is worth. macroOriginalText is set by LoadText and is
	-- where [취소] goes back to; while the window followed the selection, stepping to another
	-- macro and back replaced it with the text you had just typed, so [취소] could no longer
	-- reach what you started from. With the window closing instead, that value is set once per
	-- opening and never moves.
	--
	-- nil is not "a different action" - it is nothing loaded yet, which is how Open arrives here
	-- one line after Show(). Treating it as different would make the window close itself the
	-- instant it opens.
	if (self.macroAction == nil) then
		self:LoadText(action);
	elseif (self.macroAction ~= action) then
		self:Close();
		return;
	end

	self.Editor.SelectedMacroName:SetText(action.name or "");
	self.Editor.SelectedMacroButton.Icon:SetTexture(action.icon);
end

function DebindUI.GetSelectedTab()
	return _selectedTab;
end

function DebindUI.GetSelectedSideTab()
	return _selectedSideTab;
end

DebindStateDriverUpdateThrottleSliderMixin = {};

function DebindStateDriverUpdateThrottleSliderMixin:OnLoad()
	self.Slider:SetAccessorFunction(function()
		return DebindPrivate.Options.stateDriverUpdateThrottle or 0.2;
	end);

	self.Slider:SetMutatorFunction(function(value)
		value = floor(value * 1000 + 1) / 1000;
		DebindPrivate.Options.stateDriverUpdateThrottle = value;
		DebindPrivate.ApplyOptions("stateDriverUpdateThrottle");
	end);

	self.Slider:RegisterPropertyChangeHandler("OnValueChanged", function(slider, value, isMouse)
		self.ValueText.Text:SetText(format("%.2f", value):gsub("%.?0+$", ""));
	end);

	self.Slider:UpdateVisibleState();
end

function DebindStateDriverUpdateThrottleSliderMixin:UpdateVisibleState()
	self.Slider:UpdateVisibleState();
end

-- temp
DebindUI.GetLayerID = GetLayerID;
DebindUI.MoveAction = MoveAction;
DebindUI.MoveActions = MoveActions;
DebindUI.ApproveArrivedActions = ApproveArrivedActions;
DebindUI.ShowDeleteConfirmationPopup = ShowDeleteConfirmationPopup;
DebindUI.ShowBulkDeleteConfirmationPopup = ShowBulkDeleteConfirmationPopup;
DebindUI.ShowRejectImportConfirmationPopup = ShowRejectImportConfirmationPopup;
DebindUI.ShowInputBox = ShowInputBox
