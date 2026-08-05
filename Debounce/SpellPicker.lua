local _, DebouncePrivate = ...;

local Constants          = DebouncePrivate.Constants;
local LLL                = DebouncePrivate.L;
local DebounceUI         = DebouncePrivate.DebounceUI;
local ActionCatalog      = DebouncePrivate.ActionCatalog;

local INACTIVE_ALPHA     = 0.45;

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

--- 대상 레이어에 이미 들어 있는 주문. `[base spellID] = 개수`.
---
--- 추가를 막지는 않는다 - 같은 주문에 조건만 다른 줄을 두는 것이 정상 사용이다. 표시만 한다.
local _addedCounts = {};

local function RebuildAddedCounts()
	wipe(_addedCounts);

	local layerID = DebounceUI.GetSelectedLayerID();
	local layer = layerID and DebouncePrivate.GetProfileLayer(layerID);
	if (not layer) then
		return;
	end

	for _, action in layer:Enumerate() do
		if (action.type == Constants.SPELL and action.value) then
			-- 저장값이 언제나 base라는 보장은 없다. 커서에서 떨어진 주문은 오버라이드가
			-- 적용된 ID로 들어온다(`GetActionTypeAndValueFromCursorInfo`). 양쪽을 base로
			-- 접어놓고 비교한다.
			local baseID = C_SpellBook.FindBaseSpellByID(action.value) or action.value;
			_addedCounts[baseID] = (_addedCounts[baseID] or 0) + 1;
		end
	end
end

--------------------------------------------------------------------------------
-- 행
--------------------------------------------------------------------------------

DebounceSpellPickerRowMixin = {};

function DebounceSpellPickerRowMixin:Init(elementData)
	self.entry = elementData;

	self.Icon:SetTexture(elementData.icon);
	self.Name:SetText(elementData.name);

	-- 부제 자리는 하나다. 비활성 특성 이름이 있으면 그게 이긴다 - 랭크보다 "지금 못 쓴다"가
	-- 먼저 알아야 할 것이다.
	local subText = elementData.note or elementData.subName;
	self.SubName:SetText(subText or "");

	-- 오프스펙은 흐리게. 목록에 **넣는** 것은 이 애드온에 특성별 레이어가 있기 때문이고
	-- (지금 아닌 특성의 주문을 미리 걸어두는 게 정상 사용이다), 흐리게 하는 것은 지금
	-- 누른다고 나가지는 않기 때문이다.
	local inactive = elementData.isOffSpec or elementData.isPassive;
	self.Icon:SetDesaturated(elementData.isOffSpec or false);
	self:SetAlpha(inactive and INACTIVE_ALPHA or 1);

	self:Update();
end

function DebounceSpellPickerRowMixin:Update()
	local entry = self.entry;
	if (not entry) then
		return;
	end

	local count = _addedCounts[entry.value];
	self.AddedMark:SetShown(count ~= nil);
	self.AddedCount:SetText((count and count > 1) and tostring(count) or "");
end

function DebounceSpellPickerRowMixin:OnEnter()
	local entry = self.entry;
	if (not entry) then
		return;
	end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	-- 툴팁은 **지금 나가는 주문**을 보여야 한다. 들고 있는 값은 base라 오버라이드를 다시
	-- 씌운다 (행의 이름·아이콘이 이미 그쪽이다).
	GameTooltip:SetSpellByID(C_SpellBook.FindSpellOverrideByID(entry.value) or entry.value);

	if (entry.note) then
		GameTooltip_AddNormalLine(GameTooltip, entry.note);
	end
	if (_addedCounts[entry.value]) then
		GameTooltip_AddHighlightLine(GameTooltip, LLL["SPELL_PICKER_ALREADY_ADDED"]);
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
function DebounceSpellPickerRowMixin:OnClick()
	local entry = self.entry;
	if (not entry or InCombatLockdown()) then
		return;
	end

	DebounceFrame:AddNewAction(entry.type, entry.value);
end

--------------------------------------------------------------------------------
-- 창
--------------------------------------------------------------------------------

DebounceSpellPickerFrameMixin = {};

local function GetOptions()
	local db = DebouncePrivate.db.global;
	db.spellPicker = db.spellPicker or {};
	local options = db.spellPicker;
	if (options.showPassive == nil) then
		-- 패시브는 기본으로 뺀다 - 걸어봐야 안 나간다.
		options.showPassive = false;
	end
	if (options.showOffSpec == nil) then
		-- 오프스펙은 기본으로 넣는다. Clique와 반대인데, 그쪽엔 특성별 레이어가 없다.
		options.showOffSpec = true;
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

	self.filteredEntries = {};
end

function DebounceSpellPickerFrameMixin:InitializeTabs()
	-- 탭은 카탈로그의 카테고리와 **1:1이고 인덱스가 곧 탭 ID**다. 카테고리 목록은
	-- 재구축에도 안 흔들리므로(ActionCatalog 참고) 여기서 한 번 다는 것으로 끝난다.
	for _, category in ipairs(ActionCatalog.GetCategories()) do
		self.TabSystem:AddTab(category.name);
	end
	self.TabSystem:SetTabSelectedCallback(function(tabID)
		self:SetTab(tabID);
	end);

	self.selectedTab = 1;
	self.TabSystem:SetTabVisuallySelected(self.selectedTab);
end

function DebounceSpellPickerFrameMixin:InitializeScrollBox()
	-- 2컬럼. **페이징은 안 한다** - ScrollBox는 가상화되어 있어 수백 개여도 보이는 만큼만
	-- 프레임을 잡는다. 페이징을 넣으면 검색 결과까지 페이지로 넘겨야 하는 손해만 남는다.
	local view = CreateScrollBoxListGridView(2, 2, 2, 2, 2, 4, 2);
	view:SetElementInitializer("DebounceSpellPickerRowTemplate", function(button, elementData)
		button:Init(elementData);
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

function DebounceSpellPickerFrameMixin:InitializeFilterDropdown()
	self.FilterDropdown:SetupMenu(function(_, rootDescription)
		local options = GetOptions();

		rootDescription:CreateCheckbox(LLL["SPELL_PICKER_SHOW_PASSIVE"],
			function() return options.showPassive; end,
			function()
				options.showPassive = not options.showPassive;
				self:RefreshList();
			end);

		rootDescription:CreateCheckbox(LLL["SPELL_PICKER_SHOW_OFFSPEC"],
			function() return options.showOffSpec; end,
			function()
				options.showOffSpec = not options.showOffSpec;
				self:RefreshList();
			end);
	end);
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
	-- 초기화보다 **먼저** 세운다. 탭을 다는 쪽이 카탈로그를 한 번 짓기 때문에, 뒤에
	-- 세우면 첫 열림에서만 두 번 짓는다.
	ActionCatalog.Invalidate();

	if (not self.initialized) then
		self:OnLoad();
	end

	self:ApplyPosition();

	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN);

	self:RegisterEvent("SPELLS_CHANGED");
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	self:RegisterEvent("TRAIT_CONFIG_UPDATED");

	self:RefreshList();
end

function DebounceSpellPickerFrameMixin:OnHide()
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE);

	self:UnregisterEvent("SPELLS_CHANGED");
	self:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	self:UnregisterEvent("TRAIT_CONFIG_UPDATED");

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
	if (event == "SPELLS_CHANGED") then
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

--- 목록을 다시 짓는다. 카탈로그가 dirty면 여기서 갚는다.
function DebounceSpellPickerFrameMixin:RefreshList()
	local categories = ActionCatalog.GetCategories();

	-- 빈 카테고리는 탭을 숨긴다. 소환수 없는 직업에서 빈 탭이 하나 서 있으면 "여기 뭔가
	-- 있는데 안 나온다"로 읽힌다.
	for tabID, category in ipairs(categories) do
		self.TabSystem:SetTabShown(tabID, #category.entries > 0);
	end

	local category = categories[self.selectedTab];
	if (not category or #category.entries == 0) then
		self.selectedTab = 1;
		category = categories[1];
	end
	self.TabSystem:SetTabVisuallySelected(self.selectedTab);

	local options = GetOptions();
	ActionCatalog.Filter(category and category.entries or {}, {
		search = self.searchText,
		includePassive = options.showPassive,
		includeOffSpec = options.showOffSpec,
	}, self.filteredEntries);

	RebuildAddedCounts();

	local dataProvider = CreateDataProvider(self.filteredEntries);
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

--- 메인 창에서 열려 있는 레이어가 바뀌었다. "이미 있음" 표시만 다시 그린다.
---
--- 목록 자체는 그대로다 - 대상이 바뀐다고 고를 수 있는 주문이 바뀌지는 않는다.
function DebounceSpellPickerFrameMixin:OnTargetLayerChanged()
	if (not self:IsShown()) then
		return;
	end

	RebuildAddedCounts();
	self.ScrollBox:ForEachFrame(function(button)
		button:Update();
	end);
end

function DebounceSpellPickerFrameMixin:Toggle()
	if (self:IsShown()) then
		self:Hide();
	else
		self:Show();
	end
end
