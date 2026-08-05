local _, DebouncePrivate = ...;

local Constants          = DebouncePrivate.Constants;
local LLL                = DebouncePrivate.L;
local ActionCatalog      = DebouncePrivate.ActionCatalog;

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
--- 이 창이 **대상을 안 고른다**는 점이 설계의 중심이다. 추가되는 곳은 언제나 메인 창에서
--- 열려 있는 레이어이고, 대상을 바꾸는 것은 메인 창의 탭으로 한다 - 같은 선택기를 두 번
--- 만들지 않는다. 그래서 이 창은 모달이 아니고, `IsEditingAction()` 잠금에도 들어가지
--- 않는다(들어가면 메인 창 탭이 잠겨서 대상을 바꿀 수 없게 된다).

--- **"이미 들어 있음" 표시는 없다.** 한 번 넣었다가 뺐다.
---
--- 이 애드온에서는 같은 액션이 한 레이어에 여러 줄 있는 것이 정상이다 - 조건이 다르거나
--- 단축키가 다른 줄들이다. 그 자리에 체크 표시를 두면 "이미 있으니 그만"으로 읽혀서,
--- 정상 사용을 실수처럼 보이게 만든다. 개수를 붙여도 마찬가지다 - 세어서 알려줄 만한
--- 수가 아니다.

--------------------------------------------------------------------------------
-- 행
--------------------------------------------------------------------------------

DebounceSpellPickerRowMixin = {};

function DebounceSpellPickerRowMixin:Init(elementData)
	self.entry = elementData;

	self.Icon:SetTexture(elementData.icon);
	self.Name:SetText(elementData.name);

	-- 부제는 랭크·계열이다. "다른 특성"이라는 사실은 여기 안 쓴다 - 머리글이 말하고 있고,
	-- 행마다 반복하면 랭크가 들어갈 자리를 뺏는다.
	self.SubName:SetText(elementData.subName or "");

	-- 오프스펙은 흐리게. 목록에 **넣는** 것은 이 애드온에 특성별 레이어가 있기 때문이고
	-- (지금 아닌 특성의 주문을 미리 걸어두는 게 정상 사용이다), 흐리게 하는 것은 지금
	-- 누른다고 나가지는 않기 때문이다.
	local isOffSpec = elementData.isOffSpec or false;
	self.Icon:SetDesaturated(isOffSpec);
	self:SetAlpha(isOffSpec and INACTIVE_ALPHA or 1);
end

function DebounceSpellPickerRowMixin:OnEnter()
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
	elseif (entry.type == Constants.ITEM) then
		-- 장난감이 여기로 온다. 이름만 띄우면 비슷한 이름 둘을 구별할 수가 없다 -
		-- 필요한 건 "사용 효과" 줄과 재사용 대기시간이고, 그건 아이템 툴팁에 있다.
		GameTooltip:SetItemByID(entry.value);
	else
		GameTooltip_SetTitle(GameTooltip, entry.name);
		if (entry.tooltipText and entry.tooltipText ~= "") then
			GameTooltip_AddNormalLine(GameTooltip, entry.tooltipText);
		end
	end

	GameTooltip_AddInstructionLine(GameTooltip, LLL["SPELL_PICKER_CLICK_TO_ADD"]);

	GameTooltip:Show();
end

function DebounceSpellPickerRowMixin:OnLeave()
	GameTooltip:Hide();
end

--- 클릭 한 번에 즉시 추가하고 **창은 유지한다.** 계속 골라 넣을 수 있어야 한다.
---
--- 대상 레이어를 인자로 넘기지 않는 것에 주의. `AddNewAction`이 안에서 지금 열려 있는
--- 탭을 읽으므로, 여기서 대상을 다시 말하면 두 곳이 같은 것을 알게 된다.
---
--- **타입에 대한 분기가 여기 없다.** 엔트리가 들고 온 것을 그대로 넘긴다 - 주문이든
--- 탈것이든 매크로든, 나중에 붙을 무엇이든. 이름·아이콘 자리를 비워 두는 것도 뜻이 있다:
--- 저장해둬야 하는 타입은 카탈로그가 `props`에 담아 오고, 나머지는 그릴 때 다시 푼다
--- (`NameAndIconForAction`). 여기서 지금 보이는 값을 박으면 낡은 채로 남는다.
function DebounceSpellPickerRowMixin:OnClick()
	local entry = self.entry;
	if (not entry or InCombatLockdown()) then
		return;
	end

	DebounceFrame:AddNewAction(entry.type, entry.value, nil, nil, entry.props);
end

--------------------------------------------------------------------------------
-- 머리글
--------------------------------------------------------------------------------

DebounceSpellPickerHeaderMixin = {};

--- 머리글은 격자 때문에 행과 **같은 크기**의 칸을 쓴다(240×38). 글자는 그 칸의 **세로
--- 가운데**에 둔다 - 위나 아래로 붙이면 남는 자리가 한쪽에 몰려서 그쪽만 구멍처럼 보인다.
--- 위에 붙였다가 첫 머리글 아래가 비었고, 아래에 붙였다가 첫 머리글 위가 비었다.
--- 칸 크기를 못 줄이는 이상 없앨 수 있는 여백이 아니라, 양쪽으로 나누는 게 제일 낫다.
function DebounceSpellPickerHeaderMixin:Init(elementData)
	self.Label:SetText(elementData.name);
end

--------------------------------------------------------------------------------
-- 탭
--------------------------------------------------------------------------------

DebounceSpellPickerTabMixin = {};

function DebounceSpellPickerTabMixin:OnClick()
	PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
	self:GetParent():SetTab(self:GetID());
end

--------------------------------------------------------------------------------
-- 창
--------------------------------------------------------------------------------

DebounceSpellPickerFrameMixin = {};

--- 필터 값은 카탈로그가 선언한 것만 쓴다(`ActionCatalog.Filters`). 기본값도 거기 있다 -
--- 오프스펙을 기본으로 넣는 것은 이 애드온에 특성별 레이어가 있기 때문이다(Clique와 반대).
local function GetOptions()
	local db = DebouncePrivate.db.global;
	db.spellPicker = db.spellPicker or {};
	local options = db.spellPicker;

	for _, filter in pairs(ActionCatalog.Filters) do
		if (options[filter.option] == nil) then
			options[filter.option] = filter.default;
		end
	end

	return options;
end

function DebounceSpellPickerFrameMixin:OnLoad()
	self.initialized = true;

	self:SetTitle(LLL["SPELL_PICKER_TITLE"]);
	self:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09");

	self:RegisterForDrag("LeftButton");
	self:SetScript("OnDragStart", function()
		self:StartMoving();
	end);
	self:SetScript("OnDragStop", function()
		self:StopMovingOrSizing();
		self:SetUserPlaced(false);
		local x, y = self:GetCenter();
		DebouncePrivate.db.global.spellPickerUI = DebouncePrivate.db.global.spellPickerUI or {};
		DebouncePrivate.db.global.spellPickerUI.pos = { x = x, y = y };
	end);

	self:InitializeTabs();
	self:InitializeScrollBox();
	self:InitializeSearchBox();
	self:InitializeFilterDropdown();

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
function DebounceSpellPickerFrameMixin:InitializeTabs()
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

function DebounceSpellPickerFrameMixin:InitializeScrollBox()
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
			factory("DebounceSpellPickerHeaderTemplate", function(frame)
				frame:Init(elementData);
			end);
		elseif (elementData.isSpacer) then
			factory("DebounceSpellPickerSpacerTemplate");
		else
			factory("DebounceSpellPickerRowTemplate", function(button)
				button:Init(elementData);
			end);
		end
	end);

	ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);
end

function DebounceSpellPickerFrameMixin:InitializeSearchBox()
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
		DebounceDetailPanel:CancelKeyCapture();
	end);
	self.SearchBox:SetScript("OnEditFocusLost", SearchBoxTemplate_OnEditFocusLost);
end

--- 필터 버튼은 **지금 탭이 쓰는 것만** 보여준다. 카테고리가 `filters`에 적어둔 키를 읽는다.
---
--- 패시브 체크박스는 어디에도 없다. 패시브는 **누를 수 있는 물건이 아니라서** 카탈로그가
--- 아예 안 만든다(ActionCatalog). 켤 수 있게 두면 "켰는데 걸어도 안 나간다"가 된다.
function DebounceSpellPickerFrameMixin:InitializeFilterDropdown()
	self.FilterDropdown:SetupMenu(function(_, rootDescription)
		local options = GetOptions();

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
end

local NO_FILTERS = {};

function DebounceSpellPickerFrameMixin:GetSelectedCategoryFilters()
	local category = ActionCatalog.GetCategories()[self.selectedTab];
	return category and category.filters or NO_FILTERS;
end

function DebounceSpellPickerFrameMixin:OnShow()
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

	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN);

	self:RegisterEvent("SPELLS_CHANGED");
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	self:RegisterEvent("TRAIT_CONFIG_UPDATED");
	self:RegisterEvent("UPDATE_MACROS");
	self:RegisterEvent("NEW_MOUNT_ADDED");
	self:RegisterEvent("NEW_TOY_ADDED");
	-- 즐겨찾기는 머리글도 가르고 "즐겨찾기만" 필터도 가른다. 탈것 창을 옆에 열어둔 채
	-- 별을 누르는 건 흔한 일이라, 그때 목록이 안 따라가면 잘못 든 것처럼 보인다.
	self:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED");
	self:RegisterEvent("TOYS_UPDATED");
	-- 소환수 주문·명령은 **주문서 소환수 은행**에서 읽는다(`AddSpellBookItem`). 그쪽은
	-- `SPELLS_CHANGED`가 이미 덮으므로 따로 들을 것이 없다. 한때 `PET_BAR_UPDATE`를 걸어뒀는데
	-- 두 가지가 틀렸다: (1) 그때도 목록은 펫 바가 아니라 주문서에서 왔다 (2) 이 이벤트는 펫이
	-- 나와 있는 동안 자주 온다 - 재구축 한 번에 스크롤이 맨 위로 튀고(`DiscardScrollPosition`)
	-- `Invalidate()`가 모든 카테고리를 더럽혀서 다음 탈것 탭 클릭이 수천 번의 API 호출을 다시 한다.

	self:RefreshList();
end

function DebounceSpellPickerFrameMixin:OnHide()
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE);

	self:UnregisterEvent("SPELLS_CHANGED");
	self:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	self:UnregisterEvent("TRAIT_CONFIG_UPDATED");
	self:UnregisterEvent("UPDATE_MACROS");
	self:UnregisterEvent("NEW_MOUNT_ADDED");
	self:UnregisterEvent("NEW_TOY_ADDED");
	self:UnregisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED");
	self:UnregisterEvent("TOYS_UPDATED");

	-- 걸려 있던 재구축을 무효로 만든다. 타이머 자체는 못 끄므로 토큰으로 버린다.
	self.rebuildToken = (self.rebuildToken or 0) + 1;
	self.rebuildAt = nil;

	self.SearchBox:SetText("");
end

--- 첫 자리는 메인 창 오른쪽이다. 이 창은 메인 창과 **함께** 쓰는 물건이라 가운데에
--- 띄우면 십중팔구 메인 창을 덮는다. 한 번 끌어 옮기고 나면 저장된 자리가 이긴다.
function DebounceSpellPickerFrameMixin:ApplyPosition()
	local pos = DebouncePrivate.db.global.spellPickerUI and DebouncePrivate.db.global.spellPickerUI.pos;

	self:ClearAllPoints();
	if (pos) then
		self:SetPoint("CENTER", "UIParent", "BOTTOMLEFT", pos.x, pos.y);
	elseif (DebounceFrame:IsShown()) then
		self:SetPoint("TOPLEFT", DebounceFrame, "TOPRIGHT", 8, 0);
	else
		self:SetPoint("CENTER", "UIParent", 0, 0);
	end
end

function DebounceSpellPickerFrameMixin:OnEvent(event)
	if (event == "SPELLS_CHANGED" or event == "UPDATE_MACROS" or event == "NEW_MOUNT_ADDED" or event == "NEW_TOY_ADDED" or event == "MOUNT_JOURNAL_USABILITY_CHANGED" or event == "TOYS_UPDATED") then
		self:ScheduleRebuild(0.1);
	else
		-- 특성 변경은 주문서를 **비동기로** 갱신한다. 짧은 디바운스로는 아직 안 채워진
		-- 주문서를 읽어서 빈 목록을 본다.
		self:ScheduleRebuild(1);
	end
end

function DebounceSpellPickerFrameMixin:ScheduleRebuild(delay)
	ActionCatalog.Invalidate();

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

function DebounceSpellPickerFrameMixin:SetTab(tabID)
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
--- 머리글은 `group`이 있는 엔트리에만 붙는다. 나눌 것이 없는 카테고리(특수)는 group이
--- nil이라 머리글 없이 평평하게 나온다.
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
function DebounceSpellPickerFrameMixin:RefreshList()
	local categories = ActionCatalog.GetCategories();

	-- 없는 카테고리는 탭을 숨긴다. 소환수 없는 직업에서 빈 탭이 하나 서 있으면 "여기 뭔가
	-- 있는데 안 나온다"로 읽힌다.
	--
	-- 판정은 `IsAvailable()`이 한다. 여기서 목록 길이를 보면 **탭을 세우려고 탈것 수천 개를
	-- 훑게 된다** - 주문 탭만 보고 닫는 사람이 그 값을 치를 이유가 없다.
	--
	-- `PanelTemplates_SetTabShown` 대신 탭을 직접 숨긴다. 저 헬퍼는 12.1 트리에서 확인한
	-- 것이고 라이브(12.0)에 있다는 보장이 없다 - 여기서 얻는 것도 SetShown 한 줄뿐이다.
	-- 숨긴 탭의 자리는 **다시 이어 붙인다.** XML은 탭을 앞 탭의 오른쪽에 매다는 사슬이라
	-- (`PanelTemplates_AnchorTabs`도 같은 방식) 가운데 하나를 숨기면 그 자리가 빈 채로 남는다.
	-- 매크로도 장난감도 없는 새 캐릭터에서 "주문 [구멍] 탈것 [구멍] 특수"가 된다.
	-- 메인 창은 탭 둘이 언제나 보여서 이 문제를 만난 적이 없다.
	local prevTab;
	for tabID = 1, #self.Tabs do
		local tab = self.Tabs[tabID];
		local category = categories[tabID];
		local shown = category ~= nil and ActionCatalog.IsCategoryAvailable(category);
		tab:SetShown(shown);
		if (shown) then
			tab:ClearAllPoints();
			if (prevTab) then
				tab:SetPoint("LEFT", prevTab, "RIGHT", -15, 0);
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

	local options = GetOptions();
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

function DebounceSpellPickerFrameMixin:UpdateEmptyText()
	if (#self.filteredEntries > 0) then
		self.ScrollBox.EmptyText:Hide();
		return;
	end

	self.ScrollBox.EmptyText:SetText(self.searchText and LLL["SPELL_PICKER_NO_MATCH"] or LLL["SPELL_PICKER_EMPTY"]);
	self.ScrollBox.EmptyText:Show();
end

function DebounceSpellPickerFrameMixin:Toggle()
	if (self:IsShown()) then
		self:Hide();
	else
		self:Show();
	end
end
