local _, DebindPrivate = ...;

local Constants          = DebindPrivate.Constants;
local LLL                = DebindPrivate.L;
local ActionCatalog      = DebindPrivate.ActionCatalog;
local DebindUI           = DebindPrivate.DebindUI;

--- 다른 특성 주문을 죽이는 정도. 아이콘 채도까지 같이 빠지므로 알파는 **글자를 읽을 수
--- 있는 선**에서 멈춘다 - 이건 "지금은 안 나간다"는 말이지 "볼 것 없다"는 말이 아니다.
--- (0.45로 뒀다가 너무 흐려서 올렸다.)
local INACTIVE_ALPHA     = 0.75;

--- 주문 선택 창.
---
--- **끌어놓기를 없애려고 만든 창이다.** 요즘 주문서(`PlayerSpellsFrame`)는 화면을 거의
--- 채우기 때문에, 거기서 주문을 끌어오려면 우리 창을 구석까지 밀어놔야 했다. 여기서는
--- 목록을 우리가 갖고 있고 클릭 한 번이 곧 추가다.
---
--- **왼쪽 클릭은 대상을 안 고른다.** 추가되는 곳은 메인 창에서 열려 있는 레이어이고, 대상을
--- 바꾸는 것은 메인 창의 탭으로 한다 - 같은 선택기를 두 번 만들지 않는다. 그래서 이 창은
--- 모달이 아니고, `IsEditingAction()` 잠금에도 들어가지 않는다(들어가면 메인 창 탭이 잠겨서
--- 대상을 바꿀 수 없게 된다).
---
--- Right click names a tab instead (`SetupSpellPickerDropdownMenu`). It is the same destination
--- list the move and copy menus show, not a second selector: the list lives in one place and this
--- window only hands it the entry. Left click stays the fast path, so a tab you are filling costs
--- a click each and only the odd one out costs a menu.

--- **"이미 들어 있음" 표시는 없다.** 한 번 넣었다가 뺐다.
---
--- 이 애드온에서는 같은 액션이 한 레이어에 여러 줄 있는 것이 정상이다 - 조건이 다르거나
--- 단축키가 다른 줄들이다. 그 자리에 체크 표시를 두면 "이미 있으니 그만"으로 읽혀서,
--- 정상 사용을 실수처럼 보이게 만든다. 개수를 붙여도 마찬가지다 - 세어서 알려줄 만한
--- 수가 아니다.

--------------------------------------------------------------------------------
-- 행
--------------------------------------------------------------------------------

DebindSpellPickerRowMixin = {};

function DebindSpellPickerRowMixin:Init(elementData)
	self.entry = elementData;

	DebindUI.SetActionIcon(self.Icon, elementData.icon);

	self.Name:SetText(elementData.name);

	-- 부제는 랭크·계열이다. "다른 특성"이라는 사실은 여기 안 쓴다 - 머리글이 말하고 있고,
	-- 행마다 반복하면 랭크가 들어갈 자리를 뺏는다.
	-- One exception, decided in the catalog rather than here: a spell you have not learned yet has
	-- no rank to show, so its level requirement takes the line instead (`AddSpellBookItem`).
	self.SubName:SetText(elementData.subName or "");

	-- 오프스펙은 흐리게. 목록에 **넣는** 것은 이 애드온에 특성별 레이어가 있기 때문이고
	-- (지금 아닌 특성의 주문을 미리 걸어두는 게 정상 사용이다), 흐리게 하는 것은 지금
	-- 누른다고 나가지는 않기 때문이다.
	--
	-- Not-yet-learned spells get the same grey. Both mean "listed, not castable now", and two
	-- shades would ask the reader to tell them apart when something else already does: the header
	-- for another spec, the subtitle's level requirement for a spell that has not arrived yet.
	local isInactive = elementData.isOffSpec or elementData.isUnlearned or false;
	self.Icon:SetDesaturated(isInactive);
	self:SetAlpha(isInactive and INACTIVE_ALPHA or 1);
end

function DebindSpellPickerRowMixin:OnEnter()
	local entry = self.entry;
	if (not entry) then
		return;
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");

	-- 툴팁을 주문에서 뽑을 수 있으면 그렇게 한다. 타입마다 갈리지 않는다:
	--   주문   value가 곧 주문이다. 다만 **지금 나가는 것**을 보여야 하므로 base에
	--          오버라이드를 다시 씌운다(행의 이름·아이콘이 이미 그쪽이다)
	--   탈것   value는 mountID라 주문이 아니다. 카탈로그가 `spellID`를 같이 준다
	--   그 밖  게임이 툴팁을 안 만들어 주는 것들(매크로). 이름과 본문을 우리가 쓴다
	local tooltipSpellID = entry.spellID;
	if (not tooltipSpellID and entry.type == Constants.SPELL) then
		tooltipSpellID = C_SpellBook.FindSpellOverrideByID(entry.value) or entry.value;
	end

	if (tooltipSpellID) then
		GameTooltip:SetSpellByID(tooltipSpellID);
	elseif (entry.spellBookSlot) then
		-- 플라이아웃. **주문이 아니라 주문서 항목이라** 주문 ID로는 툴팁이 안 나온다
		-- (`GetFlyoutInfo`가 주는 것은 이름과 설명 문자열뿐이다). 게임이 주문책에서
		-- 띄우는 바로 그 툴팁을 그대로 쓴다 - 블리자드도 같은 한 줄이다
		-- (`Blizzard_SpellBookItem.lua`의 `tooltip:SetSpellBookItem(slotIndex, spellBank)`).
		--
		-- 슬롯 번호는 **엔트리에만** 있고 저장되지 않는다. 주문서가 바뀌면 번호가 밀리는데,
		-- 카탈로그는 그때 통째로 다시 지어지므로(`ActionCatalog.Invalidate`) 엔트리가 든
		-- 번호는 언제나 지금 것이다. 액션에 저장되는 값은 여전히 flyoutID 하나다.
		GameTooltip:SetSpellBookItem(entry.spellBookSlot, entry.spellBookBank);
	elseif (entry.type == Constants.ITEM) then
		-- 장난감이 여기로 온다. 이름만 띄우면 비슷한 이름 둘을 구별할 수가 없다 -
		-- 필요한 건 "사용 효과" 줄과 재사용 대기시간이고, 그건 아이템 툴팁에 있다.
		GameTooltip:SetItemByID(entry.value);
	else
		-- 제목이 행의 글자와 다를 수 있다. 대상 지정 행이 그렇다 - 행에는 대상만 적고
		-- (머리글이 타입을 말한다) 툴팁은 머리글에서 떨어져 뜨므로 제목에 타입을 다시 붙인다.
		GameTooltip_SetTitle(GameTooltip, entry.tooltipTitle or entry.name);
		if (entry.tooltipText and entry.tooltipText ~= "") then
			GameTooltip_AddNormalLine(GameTooltip, entry.tooltipText);
		end
	end

	-- 안내 줄은 **툴팁 내용이 아니라 우리가 덧붙인 것**이다. 빈 줄이 그 경계를 만든다 -
	-- 안 두면 주문 툴팁의 마지막 줄(재사용 대기시간 따위)에 붙어서 그것도 주문 설명인 것처럼
	-- 읽힌다. 애드온의 다른 툴팁들도 같은 자리에 빈 줄을 둔다.
	GameTooltip_AddBlankLineToTooltip(GameTooltip);
	-- **The line names the tab, it does not just say "the current one".** Two windows stand side
	-- by side here and only one of them has tabs, so "current" is a word this window cannot answer;
	-- the name can be read where the cursor already is. `GetLayerLabel` is the same name the side
	-- tab tooltips and the order list use - a tab called two things is two tabs to the reader.
	GameTooltip_AddInstructionLine(GameTooltip,
		format(LLL["SPELL_PICKER_LEFT_CLICK_TO_ADD"], DebindUI.GetLayerLabel(DebindUI.GetLayerID())));
	-- The right-click menu leaves no mark on the row, so this line is the only place it is
	-- announced. It sits under the left-click line because that is still the ordinary way in.
	GameTooltip_AddInstructionLine(GameTooltip, LLL["SPELL_PICKER_RIGHT_CLICK_TO_ADD"]);

	GameTooltip:Show();
end

function DebindSpellPickerRowMixin:OnLeave()
	GameTooltip:Hide();
end

--- 클릭 한 번에 즉시 추가하고 **창은 유지한다.** 계속 골라 넣을 수 있어야 한다.
---
--- 왼쪽 클릭은 대상 레이어를 인자로 넘기지 않는 것에 주의. `AddNewAction`이 안에서 지금
--- 열려 있는 탭을 읽으므로, 여기서 대상을 다시 말하면 두 곳이 같은 것을 알게 된다. 오른쪽
--- 클릭은 그 인자를 채우는 유일한 자리다 - 메뉴가 고른 탭이 거기로 간다.
---
--- **타입에 대한 분기가 여기 없다.** 엔트리가 들고 온 것을 그대로 넘긴다 - 주문이든
--- 탈것이든 매크로든, 나중에 붙을 무엇이든. 이름·아이콘 자리를 비워 두는 것도 뜻이 있다:
--- 저장해둬야 하는 타입은 카탈로그가 `props`에 담아 오고, 나머지는 그릴 때 다시 푼다
--- (`NameAndIconForAction`). 여기서 지금 보이는 값을 박으면 낡은 채로 남는다.
function DebindSpellPickerRowMixin:OnClick(button)
	local entry = self.entry;
	if (not entry or InCombatLockdown()) then
		return;
	end

	if (button == "RightButton") then
		-- The row owns the menu but does not anchor it - a context menu opens at the cursor
		-- either way (`MenuManagerMixin:OpenContextMenu`); the owner is what closes it when the
		-- frame hides. The entry is read now and kept, so a rebuild that hands this frame a
		-- different spell cannot change what the menu adds.
		MenuUtil.CreateContextMenu(self, DebindUI.SetupSpellPickerDropdownMenu, entry);
		return;
	end

	DebindFrame:AddNewAction(entry.type, entry.value, nil, nil, entry.props);
end

--------------------------------------------------------------------------------
-- 머리글
--------------------------------------------------------------------------------

DebindSpellPickerHeaderMixin = {};

--- 머리글은 격자 때문에 행과 **같은 크기**의 칸을 쓴다(240×38). 글자는 그 칸의 **세로
--- 가운데**에 둔다 - 위나 아래로 붙이면 남는 자리가 한쪽에 몰려서 그쪽만 구멍처럼 보인다.
--- 위에 붙였다가 첫 머리글 아래가 비었고, 아래에 붙였다가 첫 머리글 위가 비었다.
--- 칸 크기를 못 줄이는 이상 없앨 수 있는 여백이 아니라, 양쪽으로 나누는 게 제일 낫다.
function DebindSpellPickerHeaderMixin:Init(elementData)
	self.Label:SetText(elementData.name);
end

--------------------------------------------------------------------------------
-- 탭
--------------------------------------------------------------------------------

DebindSpellPickerTabMixin = {};

function DebindSpellPickerTabMixin:OnClick()
	PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
	self:GetParent():SetTab(self:GetID());
end

--------------------------------------------------------------------------------
-- 창
--------------------------------------------------------------------------------

DebindSpellPickerFrameMixin = {};

--- 필터 값은 카탈로그가 선언한 것만 쓴다(`ActionCatalog.Filters`). 기본값도 거기 있다 -
--- 오프스펙을 기본으로 넣는 것은 이 애드온에 특성별 레이어가 있기 때문이다(Clique와 반대).
---
--- **값은 탭마다 따로 산다.** 필터 버튼이 지금 탭의 것만 보여주므로 값도 그래야 한다 -
--- 안 그러면 탈것 탭에서 켠 "즐겨찾기만"이 장난감 탭까지 걸러버리는데, 그건 **다른 탭에서
--- 켠 적 없는 필터가 목록을 비우는** 것이라 원인을 찾을 데가 없다. 개수가 수백인 두 탭이라
--- 같은 값을 쓰고 싶은 상황도 아니다. X 버튼이 지금 탭만 되돌리는 것도 같은 이유다.
local function GetOptions(categoryKey)
	local db = DebindPrivate.db.global;
	db.spellPicker = db.spellPicker or {};

	-- 예전에는 값이 탭 구분 없이 평평하게 저장됐다. 남아 있으면 통째로 버린다 - 필터 몇 개의
	-- 기본값으로 돌아가는 것뿐이라 옮겨줄 값어치가 없고, 섞여 있으면 아래 인덱싱이 불리언을
	-- 테이블처럼 읽는다.
	for _, value in pairs(db.spellPicker) do
		if (type(value) ~= "table") then
			wipe(db.spellPicker);
			break;
		end
	end

	local options = db.spellPicker[categoryKey];
	if (not options) then
		options = {};
		db.spellPicker[categoryKey] = options;
	end

	for _, filter in pairs(ActionCatalog.Filters) do
		if (options[filter.option] == nil) then
			options[filter.option] = filter.default;
		end
	end

	return options;
end

function DebindSpellPickerFrameMixin:OnLoad()
	self.initialized = true;

	self:SetTitle(LLL["SPELL_PICKER_TITLE"]);

	-- **Not the spellbook icon, and not one per tab.** The spellbook spoke for this window when it
	-- held nothing but spells, and macros, mounts, toys, commands and specials stand beside them
	-- now. Following the tab would mean six pictures to choose, and a portrait that changes reads as
	-- a different window when a tab is a move inside one.
	self:SetPortraitToAsset(Constants.ADDON_ICON);

	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", function()
		self:StartMoving();
	end);
	self:SetScript("OnDragStop", function()
		self:StopMovingOrSizing();
		self:SetUserPlaced(false);
		local x, y = self:GetCenter();
		DebindPrivate.db.global.ui = DebindPrivate.db.global.ui or {};
		DebindPrivate.db.global.ui.spellPicker = { x = x, y = y };
	end);

	self:InitializeTabs();
	self:InitializeScrollBox();
	self:InitializeSearchBox();
	self:InitializeFilterDropdown();
	self:InitializeNewMacroButton();

	-- 프레임마다 새 테이블을 만들지 않으려고 둘 다 재사용한다.
	--   filteredEntries  필터를 통과한 엔트리 (비었는지는 이쪽을 본다)
	--   displayList      거기에 머리글·빈 칸을 끼운 것. ScrollBox가 받는 건 이쪽이다
	self.filteredEntries = {};
	self.displayList = {};
end

--- 탭은 카탈로그의 카테고리와 **1:1이고 인덱스가 곧 탭 ID**다. 카테고리 목록은 재구축에도
--- 안 흔들리므로(ActionCatalog 참고) 여기서 한 번 다는 것으로 끝난다.
---
--- XML에 있는 탭보다 카테고리가 많으면 남는 카테고리는 탭 없이 남는다. 소스를 붙이는 날
--- XML에 한 줄을 더하는 것이 그 대가다 - 메인 창도 같은 방식이다.
function DebindSpellPickerFrameMixin:InitializeTabs()
	local categories = ActionCatalog.GetCategories();
	for i, tab in ipairs(self.Tabs) do
		local category = categories[i];
		tab:SetText(category and category.name or "");
		PanelTemplates_TabResize(tab, 0);
	end

	PanelTemplates_SetNumTabs(self, #self.Tabs);
	self.selectedTab = 1;
	PanelTemplates_SetTab(self, self.selectedTab);
end

function DebindSpellPickerFrameMixin:InitializeScrollBox()
	-- 2컬럼. **페이징은 안 한다** - ScrollBox는 가상화되어 있어 수백 개여도 보이는 만큼만
	-- 프레임을 잡는다. 페이징을 넣으면 검색 결과까지 페이지로 넘겨야 하는 손해만 남는다.
	--
	-- 위 여백은 0이다. 목록 맨 위에 오는 것은 대개 머리글인데, 머리글 칸이 행과 같은 크기라
	-- (격자가 셀 크기를 하나로 쓴다) 그 안에 이미 여백이 들어 있다. 여기서 더 주면 겹친다.
	local view = CreateScrollBoxListGridView(2, 0, 2, 2, 2, 4, 2);

	-- 머리글·빈 칸·행이 섞이므로 템플릿을 하나로 못 박지 못한다. 셋 다 **같은 크기**여야
	-- 한다 - 격자가 첫 프레임에서 셀 크기를 한 번 가져다 전부에 쓴다.
	view:SetElementFactory(function(factory, elementData)
		if (elementData.isHeader) then
			factory("DebindSpellPickerHeaderTemplate", function(frame)
				frame:Init(elementData);
			end);
		elseif (elementData.isSpacer) then
			factory("DebindSpellPickerSpacerTemplate");
		else
			factory("DebindSpellPickerRowTemplate", function(button)
				button:Init(elementData);
			end);
		end
	end);

	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

function DebindSpellPickerFrameMixin:InitializeSearchBox()
	self.SearchBox:SetScript("OnTextChanged", function(editBox)
		InputBoxInstructions_OnTextChanged(editBox);

		local text = strtrim(editBox:GetText()):lower();
		if (text == "") then
			text = nil;
		end
		if (self.searchText ~= text) then
			self.searchText = text;
			-- OnHide가 검색어를 비우는 것도 여기로 온다. 그때 목록을 다시 짜면 닫으면서
			-- 카탈로그를 짓는다.
			if (self:IsShown()) then
				self:RefreshList();
			end
		end
	end);
	self.SearchBox:SetScript("OnEditFocusGained", function(editBox)
		SearchBoxTemplate_OnEditFocusGained(editBox);
		-- 메인 창이 단축키를 듣는 중이면 여기 친 글자가 단축키로도 들어간다. 검색창의
		-- 포커스가 그걸 끝낸다 (메인 창 검색창과 같은 처리).
		DebindFrame:CancelKeyCapture();
	end);
	self.SearchBox:SetScript("OnEditFocusLost", SearchBoxTemplate_OnEditFocusLost);
end

--- 필터 버튼은 **지금 탭이 쓰는 것만** 보여준다. 카테고리가 `filters`에 적어둔 키를 읽는다.
---
--- 패시브 체크박스는 어디에도 없다. 패시브는 **누를 수 있는 물건이 아니라서** 카탈로그가
--- 아예 안 만든다(ActionCatalog). 켤 수 있게 두면 "켰는데 걸어도 안 나간다"가 된다.
function DebindSpellPickerFrameMixin:InitializeFilterDropdown()
	self.FilterDropdown:SetupMenu(function(_, rootDescription)
		local options = GetOptions(self:GetSelectedCategoryKey());

		for _, key in ipairs(self:GetSelectedCategoryFilters()) do
			local filter = ActionCatalog.Filters[key];
			local optionKey = filter.option;
			rootDescription:CreateCheckbox(LLL[filter.label],
				function() return options[optionKey]; end,
				function()
					options[optionKey] = not options[optionKey];
					self:RefreshList();
				end);
		end
	end);

	-- 기본값이 아니면 필터 버튼 오른쪽 위에 X가 뜬다. **템플릿이 이미 다 갖고 있다** -
	-- `ResetButton`도, 메뉴가 닫힐 때·창이 열릴 때 다시 판정하는 것도
	-- (`WowDropdownFilterBehaviorMixin`). 우리가 줄 것은 "지금 기본값인가"와
	-- "기본값으로 되돌려라" 둘뿐이다. 탈것 창·애완동물 창의 그 X와 같은 물건이다.
	--
	-- **지금 탭의 필터만 본다.** 이 버튼이 그때 보여주는 것이 그것뿐이라, 탈것 탭에서 누른
	-- X가 주문 탭의 "다른 특성"까지 되돌리면 보이지 않는 곳을 건드리는 것이 된다.
	self.FilterDropdown:SetIsDefaultCallback(function()
		local options = GetOptions(self:GetSelectedCategoryKey());
		for _, key in ipairs(self:GetSelectedCategoryFilters()) do
			local filter = ActionCatalog.Filters[key];
			if (options[filter.option] ~= filter.default) then
				return false;
			end
		end
		return true;
	end);

	self.FilterDropdown:SetDefaultCallback(function()
		local options = GetOptions(self:GetSelectedCategoryKey());
		for _, key in ipairs(self:GetSelectedCategoryFilters()) do
			local filter = ActionCatalog.Filters[key];
			options[filter.option] = filter.default;
		end
		self:RefreshList();
	end);
end

--- 매크로 텍스트만은 **고르는 것이 아니라 만드는 것**이라 목록에 자리가 없다. 주문서에도
--- 없고 커서로 끌어올 수도 없어서(`GetActionTypeAndValueFromCursorInfo`가 받는 것은
--- 주문·매크로·아이템·탈것 넷뿐이다) 이 버튼이 유일한 길이다.
---
--- 흐름은 [추가] 드롭다운이 하던 것과 **똑같다** - 이름·아이콘을 먼저 받고, 만들어진
--- 액션의 본문 편집기로 이어 간다. 그 이어붙임을 아는 것은 부르는 쪽이다(아이콘 선택기는
--- "무엇을 열지"를 모른다).
function DebindSpellPickerFrameMixin:InitializeNewMacroButton()
	local button = self.NewMacroButton;

	button:SetText(LLL["SPELL_PICKER_NEW_MACROTEXT"]);

	-- 폭을 글자에 맞춘다. XML의 120은 번역이 짧은 경우의 하한이고, 길어지면 여기서 늘어난다 -
	-- 잘린 라벨은 이 줄에서 유일하게 만드는 물건을 못 알아보게 만든다.
	local fontString = button:GetFontString();
	if (fontString) then
		button:SetWidth(max(120, fontString:GetStringWidth() + 30));
	end

	button:SetScript("OnClick", function()
		if (InCombatLockdown()) then
			return;
		end
		DebindIconSelectorFrame:OpenForNewMacro(function(elementData)
			DebindMacroFrame:Open(elementData.action);
		end);
	end);

	button:SetScript("OnEnter", function()
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
		GameTooltip_SetTitle(GameTooltip, LLL["SPELL_PICKER_NEW_MACROTEXT"]);
		GameTooltip_AddNormalLine(GameTooltip, LLL["TYPE_MACROTEXT_DESC"]);
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", GameTooltip_Hide);
end

local NO_FILTERS = {};

function DebindSpellPickerFrameMixin:GetSelectedCategoryFilters()
	local category = ActionCatalog.GetCategories()[self.selectedTab];
	return category and category.filters or NO_FILTERS;
end

--- 필터 값을 담아둘 칸의 이름. 카테고리가 아직 없는 순간(초기화 중)에도 뭔가는 돌려줘야
--- `GetOptions`가 nil로 인덱싱하지 않는다.
function DebindSpellPickerFrameMixin:GetSelectedCategoryKey()
	local category = ActionCatalog.GetCategories()[self.selectedTab];
	return category and category.key or "?";
end

function DebindSpellPickerFrameMixin:OnShow()
	-- **This window opens under those two**, at MEDIUM against their HIGH and DIALOG, so leaving
	-- them up means the thing that just opened is the thing you cannot see. Closing the editor is
	-- what commits its body, which is the same answer every other way out of it gives.
	--
	-- The icon selector goes first and by force: it belongs to the editor underneath it, so a
	-- refusal here would leave a popup standing over a window that is on its way out. It should not
	-- be reachable in the first place - the portraits are locked while it is up - and that is
	-- exactly why this line is not worth making conditional.
	--
	-- 여기서 안 닫히는 것: 이 창이 스스로 연 것들이다. [새 사용자 지정 매크로]는 이미 열려
	-- 있는 이 창에서 아이콘 선택기와 편집 창을 띄우므로 OnShow를 다시 지나지 않는다.
	DebindIconSelectorFrame:Close(true);
	DebindMacroFrame:Close();

	-- 이벤트는 **보이는 동안만** 듣는다. 그러면 닫혀 있는 동안의 변경을 못 듣게 되는데,
	-- 그건 열 때 무조건 다시 짓는 것으로 갚는다.
	--
	-- 계획서는 "닫혀 있으면 플래그만 세우고 OnShow에서 갱신"이라고 적었지만, 그 플래그를
	-- 세워줄 사람이 없다 - 안 듣는데 무엇이 세우겠는가. 상시 청취를 하나 더 두는 것보다
	-- 여는 순간 한 번 훑는 게 싸다. 주문서 한 바퀴는 몇백 번의 API 호출이고 창을 여는
	-- 동작 안에서 끝난다. 디바운스가 값을 하는 자리는 여기가 아니라 **열려 있는 동안**
	-- 이벤트가 쏟아질 때다.
	--
	-- "한 바퀴"는 **보고 있는 탭 하나**다. 탈것 수천 개는 탈것 탭을 눌러야 훑는다.
	ActionCatalog.Invalidate();

	if (not self.initialized) then
		self:OnLoad();
	end

	self:ApplyPosition();

	-- 이 창을 연 버튼에 눌린 표시를 남긴다. 창이 메인 창을 덮지 않고 옆에 서므로 둘이 같이
	-- 보이는데, 그때 [+]가 평범하게 서 있으면 이 창이 저 버튼에서 나온 것인지 알 수 없다.
	-- 오버뷰 창이 자기 버튼에 하는 것과 같다.
	DebindFrame.OverviewPanel.AddPortrait:SetSelectedState(true);

	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN);

	self:RegisterEvent("SPELLS_CHANGED");
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	self:RegisterEvent("TRAIT_CONFIG_UPDATED");
	self:RegisterEvent("UPDATE_MACROS");
	self:RegisterEvent("NEW_MOUNT_ADDED");
	self:RegisterEvent("NEW_TOY_ADDED");
	-- 즐겨찾기는 머리글도 가르고 "즐겨찾기만" 필터도 가른다. 탈것 창을 옆에 열어둔 채
	-- 별을 누르는 건 흔한 일이라, 그때 목록이 안 따라가면 잘못 든 것처럼 보인다.
	--
	-- **탈것 쪽은 `MOUNT_JOURNAL_SEARCH_UPDATED`다.** 한때 `MOUNT_JOURNAL_USABILITY_CHANGED`를
	-- 걸어뒀는데 그건 별과 아무 상관이 없다 - 블리자드 탈것 창에서 그 이벤트는
	-- `COMPANION_*`·`PLAYER_REGEN_ENABLED`와 같은 분기에 묶여 있고(`Blizzard_MountCollection.lua`),
	-- 별을 눌러 목록을 다시 세우는 것은 `SEARCH_UPDATED` 쪽이다. 우리는 사용 가능 여부로
	-- 거르지도 않으므로 예전 이벤트는 듣고도 할 일이 없었다.
	--
	-- 이 이벤트는 저쪽 창의 검색어가 바뀔 때도 온다. 우리 목록은 그 검색과 무관하지만
	-- 재구축이 한 번 더 도는 것뿐이고, 디바운스가 연타를 접는다.
	self:RegisterEvent("MOUNT_JOURNAL_SEARCH_UPDATED");
	self:RegisterEvent("TOYS_UPDATED");
	-- 소환수 주문·명령은 **주문서 소환수 은행**에서 읽는다(`AddSpellBookItem`). 그쪽은
	-- `SPELLS_CHANGED`가 이미 덮으므로 따로 들을 것이 없다. 한때 `PET_BAR_UPDATE`를 걸어뒀는데
	-- 두 가지가 틀렸다: (1) 그때도 목록은 펫 바가 아니라 주문서에서 왔다 (2) 이 이벤트는 펫이
	-- 나와 있는 동안 자주 온다 - 재구축 한 번에 스크롤이 맨 위로 튀고(`DiscardScrollPosition`)
	-- `Invalidate()`가 모든 카테고리를 더럽혀서 다음 탈것 탭 클릭이 수천 번의 API 호출을 다시 한다.

	self:RefreshList();
end

function DebindSpellPickerFrameMixin:OnHide()
	DebindFrame.OverviewPanel.AddPortrait:SetSelectedState(false);

	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE);

	self:UnregisterEvent("SPELLS_CHANGED");
	self:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	self:UnregisterEvent("TRAIT_CONFIG_UPDATED");
	self:UnregisterEvent("UPDATE_MACROS");
	self:UnregisterEvent("NEW_MOUNT_ADDED");
	self:UnregisterEvent("NEW_TOY_ADDED");
	self:UnregisterEvent("MOUNT_JOURNAL_SEARCH_UPDATED");
	self:UnregisterEvent("TOYS_UPDATED");

	-- 걸려 있던 재구축을 무효로 만든다. 타이머 자체는 못 끄므로 토큰으로 버린다.
	self.rebuildToken = (self.rebuildToken or 0) + 1;
	self.rebuildAt = nil;

	self.SearchBox:SetText("");
end

--- 첫 자리는 메인 창 오른쪽이다. 이 창은 메인 창과 **함께** 쓰는 물건이라 가운데에
--- 띄우면 십중팔구 메인 창을 덮는다. 한 번 끌어 옮기고 나면 저장된 자리가 이긴다.
function DebindSpellPickerFrameMixin:ApplyPosition()
	local pos = DebindPrivate.db.global.ui and DebindPrivate.db.global.ui.spellPicker;

	self:ClearAllPoints();
	if (pos) then
		self:SetPoint("CENTER", "UIParent", "BOTTOMLEFT", pos.x, pos.y);
	elseif (DebindFrame:IsShown()) then
		self:SetPoint("TOPLEFT", DebindFrame, "TOPRIGHT", 8, 0);
	else
		self:SetPoint("CENTER", "UIParent", 0, 0);
	end
end

--- 어느 이벤트가 어느 소스를 낡게 만드는가. **여기 없는 이벤트는 전부를 낡게 만든다** -
--- 모르는 이벤트에 아무것도 안 짓는 것보다 남는 것을 짓는 편이 안전한 쪽이다.
---
--- **`command`와 `special`은 어디에도 안 나온다.** 둘 다 손으로 적은 고정 열거라 게임에서
--- 오는 어떤 소식으로도 안 바뀐다. 창을 열 때의 무인자 `Invalidate()`가 그 둘을 덮는다.
local EVENT_SOURCES = {
	SPELLS_CHANGED             = "spellbook",
	ACTIVE_TALENT_GROUP_CHANGED = "spellbook",
	TRAIT_CONFIG_UPDATED       = "spellbook",
	UPDATE_MACROS              = "macro",
	NEW_MOUNT_ADDED            = "mount",
	MOUNT_JOURNAL_SEARCH_UPDATED = "mount",
	NEW_TOY_ADDED              = "toy",
	TOYS_UPDATED               = "toy",
};

function DebindSpellPickerFrameMixin:OnEvent(event)
	if (event == "SPELLS_CHANGED" or event == "UPDATE_MACROS" or event == "NEW_MOUNT_ADDED" or event == "NEW_TOY_ADDED" or event == "MOUNT_JOURNAL_SEARCH_UPDATED" or event == "TOYS_UPDATED") then
		self:ScheduleRebuild(0.1, EVENT_SOURCES[event]);
	else
		-- 특성 변경은 주문서를 **비동기로** 갱신한다. 짧은 디바운스로는 아직 안 채워진
		-- 주문서를 읽어서 빈 목록을 본다.
		self:ScheduleRebuild(1, EVENT_SOURCES[event]);
	end
end

function DebindSpellPickerFrameMixin:ScheduleRebuild(delay, source)
	ActionCatalog.Invalidate(source);

	if (not self:IsShown()) then
		-- 닫혀 있으면 dirty만 남긴다. 다음 OnShow가 갚는다. (이벤트는 보이는 동안만 듣게
		-- 돼 있으므로 여기 오는 일은 없어야 하지만, 타이머가 도는 사이에 창이 닫히는 길이
		-- 있어서 남겨둔다.)
		return;
	end

	-- 이미 더 늦은 재구축이 걸려 있으면 그걸 지킨다. 특성을 바꾸면 두 이벤트가 같이
	-- 오는데(TRAIT_CONFIG_UPDATED + SPELLS_CHANGED), 짧은 쪽에 맞추면 빈 목록을 본다.
	local at = GetTime() + delay;
	if (self.rebuildAt and self.rebuildAt >= at) then
		return;
	end

	self.rebuildAt = at;
	self.rebuildToken = (self.rebuildToken or 0) + 1;
	local token = self.rebuildToken;

	C_Timer.After(delay, function()
		if (self.rebuildToken ~= token or not self:IsShown()) then
			return;
		end
		self.rebuildAt = nil;
		self:RefreshList();
	end);
end

function DebindSpellPickerFrameMixin:SetTab(tabID)
	if (self.selectedTab == tabID) then
		return;
	end
	self.selectedTab = tabID;
	self:RefreshList();
end

--- 걸러진 엔트리에 머리글을 끼워 화면에 놓을 목록을 만든다.
---
--- **머리글은 언제나 줄 첫 칸이다.** 격자에는 "한 줄 차지"가 없어서(`AnchorUtil.GridLayout`은
--- stride를 고정으로 두고 셀 크기를 하나로 쓴다) 자리를 실제로 먹는 빈 칸으로 민다:
--- 줄 가운데면 앞을 채우고, 머리글 뒤에도 채운다. 그러면 다음 주문이 다시 1번 칸에서 시작한다.
---
--- 머리글은 `group`이 있는 엔트리에만 붙는다. group이 nil인 엔트리들은 머리글 없이 한
--- 덩어리로 나오는데, **그건 카테고리 전체가 group을 안 쓸 때만 쓸 수 있는 길이다.**
--- 머리글이 있는 카테고리에 group 없는 엔트리를 하나 섞으면 격자에는 그룹 경계를 그리는
--- 것이 머리글뿐이라 **앞 그룹에 이어 붙은 것으로 읽힌다** - 한 번 그렇게 새서(특수 탭의
--- "사용 안 함") 그쪽에 머리글을 줬다. 섞을 거면 전부 주는 쪽이 맞다.
---
--- **같은 머리글끼리 먼저 모은다.** 예전엔 "값이 바뀌는 자리"마다 머리글을 넣었는데, 그건
--- 소스가 그룹별로 뭉쳐서 준다고 전제한 것이었다. 소환수 주문서가 명령과 주문을 번갈아 주는
--- 바람에 같은 머리글이 여섯 번 뜬 적이 있다. 소스에 정렬 의무를 지우는 대신 여기서 모은다.
---
--- 그룹의 순서는 **처음 나온 순서**이고 그룹 안의 순서는 원본 그대로다. 그래서 이미 뭉쳐서
--- 오는 소스(주문서의 일반 -> 직업 -> 특성)는 결과가 예전과 똑같다.
local function BuildDisplayList(entries, out, stride)
	wipe(out);

	local order, buckets = {}, {};
	for i = 1, #entries do
		local entry = entries[i];
		local key = entry.group or "";
		local bucket = buckets[key];
		if (not bucket) then
			bucket = {};
			buckets[key] = bucket;
			order[#order + 1] = key;
		end
		bucket[#bucket + 1] = entry;
	end

	for _, key in ipairs(order) do
		if (key ~= "") then
			-- **머리글은 언제나 줄 첫 칸이다.** 격자에는 "한 줄 차지"가 없어서
			-- (`AnchorUtil.GridLayout`은 stride를 고정으로 두고 셀 크기를 하나로 쓴다)
			-- 자리를 실제로 먹는 빈 칸으로 민다: 줄 가운데면 앞을 채우고, 머리글 뒤에도
			-- 채운다. 그러면 다음 주문이 다시 1번 칸에서 시작한다.
			while (#out % stride ~= 0) do
				out[#out + 1] = { isSpacer = true };
			end
			out[#out + 1] = { isHeader = true, name = key };
			for _ = 2, stride do
				out[#out + 1] = { isSpacer = true };
			end
		end

		local bucket = buckets[key];
		for i = 1, #bucket do
			out[#out + 1] = bucket[i];
		end
	end

	return out;
end

--- 목록을 다시 짓는다. 카탈로그가 dirty면 **보고 있는 카테고리만** 여기서 갚는다.
function DebindSpellPickerFrameMixin:RefreshList()
	local categories = ActionCatalog.GetCategories();

	-- 없는 카테고리는 탭을 숨긴다. 소환수 없는 직업에서 빈 탭이 하나 서 있으면 "여기 뭔가
	-- 있는데 안 나온다"로 읽힌다.
	--
	-- 판정은 `IsAvailable()`이 한다. 여기서 목록 길이를 보면 **탭을 세우려고 탈것 수천 개를
	-- 훑게 된다** - 주문 탭만 보고 닫는 사람이 그 값을 치를 이유가 없다.
	--
	-- `PanelTemplates_SetTabShown` 대신 탭을 직접 숨긴다. 저 헬퍼는 12.1 트리에서 확인한
	-- 것이고 라이브(12.0)에 있다는 보장이 없다 - 여기서 얻는 것도 SetShown 한 줄뿐이다.
	-- 숨긴 탭의 자리는 **다시 이어 붙인다.** 탭은 앞 탭의 오른쪽에 매다는 사슬이라 가운데
	-- 하나를 숨기면 그 자리가 빈 채로 남는다. 매크로도 장난감도 없는 새 캐릭터에서
	-- "주문 [구멍] 탈것 [구멍] 특수"가 된다.
	-- 메인 창은 탭 둘이 언제나 보여서 이 문제를 만난 적이 없다.
	--
	-- **간격은 `PanelTemplates_AnchorTabs`와 같은 값을 쓴다(TOPLEFT→TOPRIGHT, +3).**
	-- XML에 적힌 오프셋을 베끼면 안 된다 - `PanelTemplates_SetNumTabs`가 내부에서
	-- `AnchorTabs`를 부르면서 2번 탭부터 앵커를 통째로 덮어쓰기 때문에, XML의 값은
	-- `SetNumTabs`를 부르는 창에서는 한 번도 화면에 닿지 않는 죽은 값이다(블리자드
	-- 창들에 남은 -15/-16도 전부 그렇다). 여기서만 그걸 베껴 와서 캡이 포개져 있었다.
	-- 메인 창은 `SetNumTabs`가 마지막이라 +3으로 서 있고, 이제 두 창이 같은 자리다.
	local prevTab;
	for tabID = 1, #self.Tabs do
		local tab = self.Tabs[tabID];
		local category = categories[tabID];
		local shown = category ~= nil and ActionCatalog.IsCategoryAvailable(category);
		tab:SetShown(shown);
		if (shown) then
			tab:ClearAllPoints();
			if (prevTab) then
				tab:SetPoint("TOPLEFT", prevTab, "TOPRIGHT", 3, 0);
			else
				tab:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 12, 1);
			end
			prevTab = tab;
		end
	end

	local category = categories[self.selectedTab];
	if (not category or not ActionCatalog.IsCategoryAvailable(category)) then
		self.selectedTab = 1;
		category = categories[1];
	end
	PanelTemplates_SetTab(self, self.selectedTab);

	-- 쓸 필터가 없는 탭에서는 버튼을 숨기고 **검색창이 그 자리까지 간다.** 두면 눌러도 빈
	-- 메뉴가 뜨는데(빈 메뉴는 "필터가 없다"가 아니라 "고장났다"로 읽힌다), 숨기기만 하면
	-- 검색창이 필터에 매달려 있어서 오른쪽에 110px짜리 구멍이 남는다 - 숨은 프레임도 자리는
	-- 그대로다. 매크로·명령·특수 탭이 그 경우다.
	local hasFilters = #self:GetSelectedCategoryFilters() > 0;
	self.FilterDropdown:SetShown(hasFilters);

	self.SearchBox:ClearAllPoints();
	if (hasFilters) then
		self.SearchBox:SetPoint("RIGHT", self.FilterDropdown, "LEFT", -6, 0);
	else
		self.SearchBox:SetPoint("BOTTOMRIGHT", self.ScrollBoxBackground, "TOPRIGHT", -2, 4);
	end

	-- X 표시를 다시 판정한다. 템플릿은 **메뉴가 응답할 때와 창이 열릴 때**만 스스로 판정하는데
	-- (`WowDropdownFilterBehaviorMixin`), 탭을 옮기면 보는 필터 자체가 바뀐다 - 탈것 탭에서
	-- 켜둔 "즐겨찾기만" 때문에 뜬 X가 주문 탭으로 가서도 남아 있으면 안 된다.
	self.FilterDropdown:ValidateResetState();

	local options = GetOptions(category and category.key or "?");
	ActionCatalog.Filter(category and ActionCatalog.GetEntries(category) or {}, {
		search = self.searchText,
		includeOffSpec = options.showOffSpec,
		favoritesOnly = options.favoritesOnly,
	}, self.filteredEntries);

	BuildDisplayList(self.filteredEntries, self.displayList, 2);

	local dataProvider = CreateDataProvider(self.displayList);
	self.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.DiscardScrollPosition);

	self:UpdateEmptyText();
end

function DebindSpellPickerFrameMixin:UpdateEmptyText()
	if (#self.filteredEntries > 0) then
		self.ScrollBox.EmptyText:Hide();
		return;
	end

	self.ScrollBox.EmptyText:SetText(self.searchText and LLL["SPELL_PICKER_NO_MATCH"] or LLL["SPELL_PICKER_EMPTY"]);
	self.ScrollBox.EmptyText:Show();
end

function DebindSpellPickerFrameMixin:Toggle()
	if (self:IsShown()) then
		self:Hide();
	else
		self:Show();
	end
end
