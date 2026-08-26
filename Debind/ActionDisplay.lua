local _, DebindPrivate = ...;

--- **What an action is called and what it looks like**, and the words that go with it: the type
--- names, the unit names, and the colour a name wears when something is wrong with it.
---
--- **One resolver, because one action is drawn in several lists that must not disagree about what it
--- is called.** Most of them are not the overview window's: the export list, the import preview, the
--- key capture list, the spell picker's catalog. `ActionCatalog.lua` is further out still - it loads
--- before any window exists, which is why it takes the table below at call time and not at its own
--- load.
---
--- All of it lived inside `DebindUI.lua` as file locals, reachable only through what that file chose
--- to publish on its way past six thousand lines (`breaking-up-debindui.md`, "창보다 위로 올릴 것").
---
--- **`DebindPrivate.DebindUI` is created here** because this is the first file to put anything in it.
--- `DebindUI.lua` takes it as it finds it.
DebindPrivate.DebindUI = {};

local Constants              = DebindPrivate.Constants;
local LLL                    = DebindPrivate.L;
local DebindUI               = DebindPrivate.DebindUI;

local luatype                = type;
local GetBindingIssue        = DebindPrivate.GetBindingIssue;
local IsIssueMinor           = DebindPrivate.IsIssueMinor;
local GetSpellNameAndIconID  = DebindPrivate.GetSpellNameAndIconID;
local EquipSlotFacts         = DebindPrivate.EquipSlotFacts;
local InCombatLockdown       = InCombatLockdown;

local DISABLED_FONT_COLOR    = _G.DISABLED_FONT_COLOR;
local ERROR_COLOR            = _G.ERROR_COLOR;
--- 가져왔지만 아직 승인 안 된 액션의 이름. dot과 같은 파랑이라 둘이 한 표시로 읽힌다.
--- **뜻이 하나다** - 이 창은 이름 색으로 이미 셋을 말한다(회색·빨강·이 파랑). 넷째를 얹지 말 것.
---
--- 색이 나는 곳은 여기 하나다. 드롭다운 메뉴가 행과 같은 파랑을 그려야 하는데, 사본이 하나
--- 더 있으면 원본이 움직이는 날 그쪽이 안 따라온다.
local IMPORTED_FONT_COLOR    = BRIGHTBLUE_FONT_COLOR;

local QUESTION_MARK_ICON_NUM = 134400;
local TEMP_MACRO_NAME        = "zzDbncTmpMcr"

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
	local text = DebindPrivate.StripSwitchConditions(macrotext);

	local ret;
	if (not GetMacroInfo(TEMP_MACRO_NAME)) then
		local cnt1, cnt2 = GetNumMacros();
		-- 예전엔 `MAX_ACCOUNT_MACROS` 전역을 그대로 썼는데 **그런 전역은 없다.** 여기서
		-- 숫자와 nil을 비교하다 터지고 있었고, 오류를 삼키는 애드온을 쓰면 이 함수만
		-- 조용히 죽어서 매크로텍스트 아이콘이 영영 물음표로 남는다.
		local maxAccountMacros, maxCharacterMacros = DebindPrivate.GetMacroSlotLimits();
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

--- Throws the cache away. **Only the window knows when that is safe** - a list on screen is drawing
--- off these icons and would go back to question marks under the reader - so the moment is the one
--- call site's to pick (`DebindFrameMixin:OnHide`) and is not asked about here.
local function ClearMacrotextIconCache()
	wipe(_macrotextIconCache);
end

local BINDING_TYPE_NAMES   = {
	[Constants.SPELL] = LLL["TYPE_SPELL"],
	[Constants.ITEM] = LLL["TYPE_ITEM"],
	[Constants.EQUIPSLOT] = LLL["TYPE_EQUIPSLOT"],
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
	-- **Three types, one answer.** What sits in this table is what kind of action it is, and
	-- turning one on, off, or over are all setting a switch. It is also what puts the catalog's
	-- fifteen rows under one heading (`ActionCatalog.lua`). It is not printed beside the row: the
	-- SETSTATE branch below raises `skipTypeName`.
	[Constants.SETSTATE_ON] = LLL["TYPE_SETSTATE"],
	[Constants.SETSTATE_OFF] = LLL["TYPE_SETSTATE"],
	[Constants.SETSTATE_TOGGLE] = LLL["TYPE_SETSTATE"],
	[Constants.UNUSED] = LLL["TYPE_UNUSED"],
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
		tooltipWarning = DebindPrivate.CliqueDetected and ERROR_COLOR:WrapTextInColorCode(LLL["BINDING_ERROR_CANNOT_USE_HOVER_WITH_CLIQUE"]) or nil,
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
--- **`DebindUI`에 둔 것은 두 곳이 쓰기 때문이다.** [추가] 드롭다운(`DropDownMenus.lua`)과
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
		-- **Asked only when the value is a name.** A `MACRO` that holds anything else is one
		-- the import refused the value of (`RefusedByActionType`), so there is nothing here
		-- to ask about and `GetMacroInfo(nil)` raises. The row is drawn red either way:
		-- `GetMissingMacroName` already reports it.
		if (luatype(value) == "string") then
			macroName, actionIcon = GetMacroInfo(value);
		end
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
	elseif (type == Constants.EQUIPSLOT) then
		-- **Resolved every draw, never stored.** The whole point of binding a slot rather than an
		-- item is that swapping the trinket changes what the key fires -- so the icon has to
		-- follow it. A baked one would show yesterday's trinket forever.
		--
		-- The empty slot is not a fault. Nothing is worn there *today*; the binding is still the
		-- one the reader made, and the character frame's own placeholder is what that looks like
		-- everywhere else in this game.
		local slotName, slotTexture = EquipSlotFacts(value);
		actionName = slotName;
		actionIcon = GetInventoryItemTexture("player", value) or slotTexture;
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
	elseif (Constants.SETSTATE_MODES[type]) then
		-- The locale key assembles straight off the type (`TYPE_SETSTATE_ON`), and what goes into
		-- it is the switch's name, `$` and all. Those are the glyphs the Switches tab draws and the
		-- ones a macro body has to say (§6-B).
		--
		-- **A row with no switch picked yet fills the same sentence rather than replacing it.** One
		-- is added that way (§6-C of `devdocs/legacy/redesigning-custom-states.md`), and all three
		-- sentences have a `%s` that raises on nil. What goes in is the word, not the instruction:
		-- a name says what the action is, and telling the reader to go pick one is the job of the
		-- red the row is already wearing and of `BINDING_ERROR_SWITCH_NONE_SELECTED` beside it.
		actionName = format(LLL["TYPE_" .. strupper(type)],
			luatype(value) == "string" and value or LLL["TYPE_SETSTATE_ANY"]);
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
		actionName, actionIcon = DebindPrivate.GetFlyoutNameAndIcon(value, true);
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
--- Puts an icon from `NameAndIconForAction` on a texture.

---
--- The second return value is **not always a texture.** Binding commands and `UNUSED` hand back an
--- atlas name behind an `A:` prefix, and `SetTexture` on one of those draws nothing and raises
--- nothing - the icon is simply blank, which is only ever noticed by someone looking at that row.
---
--- **One function, and the whole convention lives in this file.** The only two places that put an
--- `A:` on an icon are a few lines above; this is the only place that takes one off. Seven callers
--- across five files draw an action's icon, and the branch was written out by hand in several of
--- them at one point -- the drag portrait was missing it, so dragging a command action carried a
--- blank square around while every list showed the picture correctly.
local function SetActionIcon(texture, icon)
	if (luatype(icon) == "string" and icon:sub(1, 2) == "A:") then
		texture:SetAtlas(icon:sub(3));
	else
		texture:SetTexture(icon);
	end
end
--- skipCategory는 **그 행이 스스로 보여주는** 이슈 계열이다. 이름은 다른 데서 안 보이는

--- 문제만 물들인다 - 단축키 칸이 이미 빨간데 이름까지 빨개지면 행 전체가 잘못된 것으로
--- 읽힌다. 도달불가는 이 행의 잘못이 아니라 다른 행 때문에 생기는 것이라 더 그렇다.
--- 단축키를 따로 안 보여주는 쪽(오버뷰, 툴팁 제목)은 안 넘기면 예전 그대로다.
local function ColoredNameAndIconForAction(action, skipCategory)
	local name, icon = NameAndIconForAction(action);
	if (action.arrivalID) then
		-- **회색 자리를 가져간다.** 가져온 액션은 빌드에 안 들어가므로 어차피 회색이 될
		-- 것인데, 그러면 "키가 없다"와 구별이 안 된다. 파랑이 그 자리에 서면 "안 나간다"와
		-- "왜"를 한 색이 같이 말한다. dot과 같은 파랑이라 둘이 한 표시로 읽힌다.
		name = IMPORTED_FONT_COLOR:WrapTextInColorCode(name);
	elseif (action.key == nil or DebindPrivate.IsInactiveAction(action)) then
		name = DISABLED_FONT_COLOR:WrapTextInColorCode(name);
	else
		local issue = GetBindingIssue(action, nil, skipCategory);
		if (issue) then
			-- **The grade picks the colour, not the code.** A minor one lands on the same grey the
			-- branch above uses, and that is the point rather than a collision: both say there is
			-- nothing here to go and fix. Red is for the rows that are waiting on the reader.
			if (IsIssueMinor(issue)) then
				name = DISABLED_FONT_COLOR:WrapTextInColorCode(name);
			else
				name = ERROR_COLOR:WrapTextInColorCode(name);
			end
		end
	end
	return name, icon;
end

DebindUI.QUESTION_MARK_ICON_NUM = QUESTION_MARK_ICON_NUM;
DebindUI.IMPORTED_FONT_COLOR = IMPORTED_FONT_COLOR;
DebindUI.BINDING_TYPE_NAMES = BINDING_TYPE_NAMES;
DebindUI.UNIT_INFO = UNIT_INFO;
DebindUI.SORTED_UNIT_LIST = SORTED_UNIT_LIST;
DebindUI.ClearMacrotextIconCache = ClearMacrotextIconCache;
DebindUI.NameAndIconForAction = NameAndIconForAction;
DebindUI.ColoredNameAndIconForAction = ColoredNameAndIconForAction;
DebindUI.SetActionIcon = SetActionIcon;
