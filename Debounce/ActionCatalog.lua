local _, DebouncePrivate = ...;

local Constants          = DebouncePrivate.Constants;
local LLL                = DebouncePrivate.L;

--- 선택 창이 **무엇을 고를 수 있는지**를 만든다. 프레임은 모른다 - 그리는 일은
--- `SpellPicker.lua`가 한다.
---
--- 셋으로 나뉘어 있다. 나눈 이유는 하나다 - 매크로·탈것을 나중에 붙일 때 **소스 하나만**
--- 등록하면 되게 하려는 것이다. 창도, 필터도, 행 템플릿도 그때 안 건드린다.
---
---   소스     주문서를 훑어 엔트리를 만든다. 카테고리(=탭)를 **정적으로** 선언한다
---   카탈로그 소스가 만든 것을 카테고리별로 모아 캐시한다. 이벤트가 오면 버린다
---   필터     순수 함수. 게임 API를 안 부르므로 헤드리스 테스트가 붙는다
---            (`tests/catalog_spec.lua`)
---
--- **엔트리 계약** - `DebounceFrameMixin:AddNewAction(type, value)`에 그대로 넘어간다:
---
---   type       Constants.SPELL 등. 액션의 종류
---   value      **저장값.** 주문이면 base spellID (아래 주의 참고)
---   name/icon  **표시값.** 오버라이드가 적용된 쪽이다
---   subName    부제(랭크·계열). 없으면 nil - 빈 문자열로 두지 않는다
---   note       행 오른쪽에 붙는 짧은 글. 지금은 비활성 특성 이름뿐이다
---   isPassive  패시브 주문. 기본 필터에서 빠진다
---   isOffSpec  지금 특성이 아닌 주문. 기본 필터에서는 **들어온다**
---   searchName / searchSubName  소문자로 미리 접어둔 검색용 사본
---
--- **주의: 저장은 base, 표시는 override.** `spellID` 필드는 이미 오버라이드가 적용된
--- 값이라 그걸 저장하면 특성을 바꿨을 때 죽은 ID가 남는다. `NameAndIconForAction`
--- (`DebounceUI.lua`)이 그릴 때 base -> override로 다시 푸는 것이 이 애드온의 규약이다.
local ActionCatalog = {};
DebouncePrivate.ActionCatalog = ActionCatalog;

--- 등록된 카테고리들. 순서가 곧 탭 순서다.
---
--- **이 목록은 재구축에도 안 흔들린다.** 엔트리가 0개가 돼도 카테고리는 남는다 - 탭 ID가
--- 카테고리 인덱스이므로, 소환수가 없어졌다고 목록에서 빼면 그 뒤 탭들의 ID가 밀린다.
--- 비어 있는 카테고리는 창이 탭을 숨기는 것으로 처리한다.
local _categories = {};
local _sourceKeys  = {};
local _built       = false;

--- 소스 하나를 등록한다. 매크로·탈것은 여기 하나 더 부르는 것으로 붙는다.
---
--- source = {
---     key        = "spellbook",              -- 중복 등록 방지용
---     categories = {
---         { key = "spell", name = "주문", Build = function(entries) ... end },
---     },
--- }
---
--- `Build(entries)`는 받은 테이블에 엔트리를 tinsert 한다. 비었으면 그냥 두면 된다.
function ActionCatalog.RegisterSource(source)
	if (_sourceKeys[source.key]) then
		return;
	end
	_sourceKeys[source.key] = true;

	for _, category in ipairs(source.categories) do
		category.source = source.key;
		category.entries = {};
		tinsert(_categories, category);
	end

	_built = false;
end

--- 다음 `GetCategories()`에서 다시 짓게 한다. 여기서 바로 짓지 않는 이유는, 이걸 부르는
--- 쪽(주문서 이벤트)이 창이 닫혀 있을 때도 오기 때문이다.
function ActionCatalog.Invalidate()
	_built = false;
end

function ActionCatalog.IsDirty()
	return not _built;
end

--- 카테고리 목록을 돌려준다. 필요하면 먼저 짓는다.
---
--- 엔트리 테이블은 **자리를 유지한 채 다시 채워진다**(wipe 후 재삽입). 창이 카테고리를
--- 붙들고 있어도 재구축 뒤에 딴 테이블을 보고 있지 않게 하려는 것이다.
function ActionCatalog.GetCategories()
	if (not _built) then
		for _, category in ipairs(_categories) do
			wipe(category.entries);
			category.Build(category.entries);
		end
		_built = true;
	end
	return _categories;
end

--- 순수 함수. 게임 API를 안 부른다.
---
--- `options.search`는 **부르는 쪽이 미리 소문자로 접어서** 넘긴다. 여기서 접으면 행이
--- 그려질 때마다가 아니라 필터가 돌 때마다 문자열을 만들게 된다.
---
--- 이름 매칭은 `find(..., true)` - 평문이다. 패턴으로 해석하면 사용자가 친 `(`, `-`,
--- `[` 가 오류나 빈 목록이 된다(Clique는 특수문자를 미리 지우는 것으로 때운다).
function ActionCatalog.Filter(entries, options, out)
	out = out or {};
	wipe(out);

	local search = options.search;
	local includePassive = options.includePassive;
	local includeOffSpec = options.includeOffSpec;

	for i = 1, #entries do
		local entry = entries[i];
		local matched = true;

		if (entry.isPassive and not includePassive) then
			matched = false;
		elseif (entry.isOffSpec and not includeOffSpec) then
			matched = false;
		elseif (search) then
			matched = strfind(entry.searchName, search, 1, true) ~= nil
				or (entry.searchSubName ~= nil and strfind(entry.searchSubName, search, 1, true) ~= nil);
		end

		if (matched) then
			out[#out + 1] = entry;
		end
	end

	return out;
end

--------------------------------------------------------------------------------
-- 소스: 주문서
--------------------------------------------------------------------------------

--- 같은 주문이 두 스킬라인에 나오는 일이 있어서(직업 + 특성) 저장값으로 한 번만 넣는다.
local function AddEntry(entries, seen, value, name, icon, subName, isPassive, isOffSpec, note)
	if (not value or not name or seen[value]) then
		return;
	end
	seen[value] = true;

	if (subName == "") then
		subName = nil;
	end

	tinsert(entries, {
		type = Constants.SPELL,
		value = value,
		name = name,
		icon = icon,
		subName = subName,
		note = note,
		isPassive = isPassive or nil,
		isOffSpec = isOffSpec or nil,
		searchName = strlower(name),
		searchSubName = subName and strlower(subName) or nil,
	});
end

--- 플라이아웃은 **펼친다.** 통째로 버리면 그 안의 주문들에 아예 손이 닿지 않는다
--- (야수 소환, 각인 등이 전부 그 안에 있다).
---
--- 슬롯의 `isKnown`이 거짓이면 건너뛴다 - 다만 오프스펙 플라이아웃은 통째로 안 배운
--- 상태라 그 검사를 통과할 수 없다. 그래서 오프스펙일 때만 예외로 둔다.
local function AddFlyoutEntries(entries, seen, flyoutID, isOffSpec, note)
	local _, _, numSlots = GetFlyoutInfo(flyoutID);
	if (not numSlots) then
		return;
	end

	for slot = 1, numSlots do
		local spellID, overrideSpellID, isKnown = GetFlyoutSlotInfo(flyoutID, slot);
		if (spellID and (isKnown or isOffSpec)) then
			local displayID = overrideSpellID or spellID;
			local spellInfo = C_Spell.GetSpellInfo(displayID);
			if (spellInfo) then
				AddEntry(entries, seen, spellID, spellInfo.name, spellInfo.iconID,
					C_Spell.GetSpellSubtext(displayID), false, isOffSpec, note);
			end
		end
	end
end

--- 주문서 항목 하나를 엔트리로 옮긴다.
---
--- 저장값이 갈리는 곳이다. API 문서(`SpellBookItemInfo.actionID`)가 이렇게 적고 있다 -
--- *"주문이면 base spellID, 플라이아웃이면 flyoutID, 소환수면 petActionID"*. 앞의 둘은
--- 그대로 쓸 수 있지만 **petActionID는 주문 ID가 아니다.** 그래서 소환수 쪽만
--- `spellID`(오버라이드가 적용된 값)에서 base로 되돌려 쓴다.
local function AddSpellBookItem(entries, seen, slotIndex, bank, isOffSpec, note)
	local info = C_SpellBook.GetSpellBookItemInfo(slotIndex, bank);
	if (not info) then
		return;
	end

	local itemType = info.itemType;

	if (itemType == Enum.SpellBookItemType.FutureSpell) then
		-- 아직 못 배운 주문. 걸어둬도 안 나가므로 목록에 없는 게 맞다.
		return;
	end

	if (itemType == Enum.SpellBookItemType.Flyout) then
		AddFlyoutEntries(entries, seen, info.actionID, isOffSpec, note);
		return;
	end

	local value;
	if (itemType == Enum.SpellBookItemType.PetAction) then
		local spellID = info.spellID or info.actionID;
		value = C_SpellBook.FindBaseSpellByID(spellID) or spellID;
	else
		value = info.actionID;
	end

	AddEntry(entries, seen, value, info.name, info.iconID, info.subName, info.isPassive, isOffSpec, note);
end

--- 정렬하지 않는다. 주문서 순서가 곧 일반 -> 직업 -> 현재 특성 -> 다른 특성이라
--- (`Enum.SpellBookSkillLineIndex`), 이름순으로 다시 세우면 그 묶음이 흩어지고 다른
--- 특성 주문이 목록 한가운데로 올라온다. 이름으로 찾는 길은 검색창이다.
local function BuildPlayerSpells(entries)
	local seen = {};
	local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0;

	for skillLineIndex = 1, numSkillLines do
		local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex);
		if (skillLineInfo and not skillLineInfo.shouldHide) then
			local isOffSpec = skillLineInfo.offSpecID ~= nil;
			-- 오프스펙 주문은 "왜 흐린가"를 행에서 바로 말해야 한다. 스킬라인 이름이 곧
			-- 특성 이름이다.
			local note = isOffSpec and format(LLL["INACTIVE_SPEC_LABEL"], skillLineInfo.name) or nil;

			local first = skillLineInfo.itemIndexOffset + 1;
			local last = skillLineInfo.itemIndexOffset + skillLineInfo.numSpellBookItems;
			for slotIndex = first, last do
				AddSpellBookItem(entries, seen, slotIndex, Enum.SpellBookSpellBank.Player, isOffSpec, note);
			end
		end
	end
end

--- 소환수 은행은 평평하다 - 스킬라인이 없고 슬롯 1..n이 전부다.
local function BuildPetSpells(entries)
	local numPetSpells = C_SpellBook.HasPetSpells();
	if (not numPetSpells) then
		return;
	end

	local seen = {};
	for slotIndex = 1, numPetSpells do
		AddSpellBookItem(entries, seen, slotIndex, Enum.SpellBookSpellBank.Pet, false, nil);
	end
end

ActionCatalog.RegisterSource({
	key = "spellbook",
	categories = {
		{ key = "spell", name = LLL["TYPE_SPELL"], Build = BuildPlayerSpells },
		{ key = "pet", name = LLL["PET"], Build = BuildPetSpells },
	},
});
