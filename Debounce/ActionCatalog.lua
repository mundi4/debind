local _, DebouncePrivate = ...;

local Constants          = DebouncePrivate.Constants;
local LLL                = DebouncePrivate.L;

--- 선택 창이 **무엇을 고를 수 있는지**를 만든다. 프레임은 모른다 - 그리는 일은
--- `SpellPicker.lua`가 한다.
---
--- 셋으로 나뉘어 있다. 나눈 이유는 하나다 - 소스를 하나 더 붙이는 것으로 탭이 하나 느는
--- 구조를 만드는 것. 창도, 필터도, 행 템플릿도 그때 안 건드린다.
---
---   소스     주문서·탈것 목록 따위를 훑어 엔트리를 만든다. 카테고리(=탭)를 **정적으로** 선언한다
---   카탈로그 카테고리별로 캐시한다. **필요한 카테고리만 짓는다** - 탈것 목록은 수천 번의
---            API 호출이라, 주문 탭만 보고 닫는 사람이 그 값을 치르면 안 된다
---   필터     순수 함수. 게임 API를 안 부르므로 헤드리스 테스트가 붙는다
---            (`tests/catalog_spec.lua`)
---
--- **엔트리 계약** - `DebounceFrameMixin:AddNewAction(type, value)`에 그대로 넘어간다:
---
---   type       Constants.SPELL / Constants.MOUNT / Constants.MACRO … **무엇이든 된다**
---   value      **저장값.** 주문이면 base spellID, 탈것이면 mountID, 매크로면 이름
---              (아래 주의 참고)
---   props      `AddNewAction`의 다섯째 인자로 그대로 간다. 저장할 것이 type/value 말고 더
---              있는 타입을 위한 자리다 - 유닛(`{ unit = "focus" }`), 또는 이름·아이콘을
---              **저장해둬야** 하는 타입(`{ name =, icon = }`). 주문·탈것·매크로는 그릴 때
---              다시 푸므로 여기 아무것도 안 넣는다. 넣으면 낡은 값이 박힌다
---   name/icon  **목록에 그릴 값.** 저장되지 않는다(위 props 참고)
---   subName    부제(랭크·계열). 없으면 nil - 빈 문자열로 두지 않는다
---   spellID    툴팁용. 탈것처럼 value가 주문 ID가 아닌 타입이 쓴다
---   tooltipText  툴팁 본문. 게임이 툴팁을 안 주는 타입(매크로)이 쓴다
---   group      머리글. **같은 값이 이어지는 동안 한 덩어리다.** nil이면 머리글을 안 단다
---   isOffSpec  지금 특성이 아닌 주문. 기본 필터에서는 **들어온다**
---   isFavorite 즐겨찾기 여부. **이 개념이 없는 엔트리는 nil로 둔다** - "즐겨찾기만"
---              필터가 nil을 안 건드리므로, 탈것 탭의 설정이 주문 탭을 비우지 않는다
---   searchName / searchSubName  소문자로 미리 접어둔 검색용 사본
---
--- **주의: 저장은 base, 표시는 override.** `spellID` 필드는 이미 오버라이드가 적용된
--- 값이라 그걸 저장하면 특성을 바꿨을 때 죽은 ID가 남는다. `NameAndIconForAction`
--- (`DebounceUI.lua`)이 그릴 때 base -> override로 다시 푸는 것이 이 애드온의 규약이다.
local ActionCatalog = {};
DebouncePrivate.ActionCatalog = ActionCatalog;

--- 필터 하나의 정의. 카테고리가 `filters`에 키를 적으면 그 탭에서만 체크박스가 뜬다.
--- 인 것과 아닌 것을 카테고리가 스스로 말하므로, 탈것 탭에만 있는 옵션이 주문 탭 드롭다운에
--- 죽은 채로 서 있는 일이 없다.
ActionCatalog.Filters = {
	offSpec = { label = "SPELL_PICKER_SHOW_OFFSPEC", option = "showOffSpec", default = true },
	favorites = { label = "SPELL_PICKER_ONLY_FAVORITES", option = "favoritesOnly", default = false },
};

--- 등록된 카테고리들. 순서가 곧 탭 순서다.
---
--- **이 목록은 재구축에도 안 흔들린다.** 엔트리가 0개가 돼도 카테고리는 남는다 - 탭 ID가
--- 카테고리 인덱스이므로, 소환수가 없어졌다고 목록에서 빼면 그 뒤 탭들의 ID가 밀린다.
--- 탭을 세울지 말지는 `IsAvailable()`이 답한다. **그 판정은 목록을 짓지 않고 나와야 한다.**
local _categories = {};
local _sourceKeys = {};
local _dirty      = true;

--- 소스 하나를 등록한다.
---
--- source = {
---     key        = "spellbook",
---     categories = {
---         {
---             key = "spell", name = "주문",
---             filters = { "offSpec" },              -- 없으면 필터 버튼이 숨는다
---             IsAvailable = function() ... end,     -- 없으면 언제나 있다. **싸야 한다**
---             Build = function(entries) ... end,
---         },
---     },
--- }
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

	_dirty = true;
end

--- 다음 `GetEntries()`에서 다시 짓게 한다. 여기서 바로 짓지 않는 이유는 둘이다 - 이걸
--- 부르는 쪽(주문서 이벤트)이 창이 닫혀 있을 때도 오고, 보고 있지도 않은 카테고리를
--- 지을 이유가 없다.
function ActionCatalog.Invalidate()
	_dirty = true;
end

--- 카테고리 목록. **짓지 않는다.**
function ActionCatalog.GetCategories()
	return _categories;
end

--- 탭을 세울지. **목록을 짓지 않고** 답해야 한다 - 탭 하나 세우려고 탈것 수천 개를 훑으면
--- 게으른 구축이 무의미해진다.
function ActionCatalog.IsCategoryAvailable(category)
	if (category.IsAvailable == nil) then
		return true;
	end
	return category.IsAvailable() and true or false;
end

--- 이 카테고리의 엔트리. 필요하면 여기서 짓는다.
---
--- 엔트리 테이블은 **자리를 유지한 채 다시 채워진다**(wipe 후 재삽입). 창이 카테고리를
--- 붙들고 있어도 재구축 뒤에 딴 테이블을 보고 있지 않게 하려는 것이다.
function ActionCatalog.GetEntries(category)
	if (_dirty) then
		for _, other in ipairs(_categories) do
			other.built = false;
		end
		_dirty = false;
	end

	if (not category.built) then
		wipe(category.entries);
		category.Build(category.entries);
		category.built = true;
	end

	return category.entries;
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
	local includeOffSpec = options.includeOffSpec;
	local favoritesOnly = options.favoritesOnly;

	for i = 1, #entries do
		local entry = entries[i];
		local matched = true;

		if (entry.isOffSpec and not includeOffSpec) then
			matched = false;
		elseif (favoritesOnly and entry.isFavorite == false) then
			-- `== false`다. 즐겨찾기라는 개념이 없는 엔트리는 nil이라 안 걸린다 - 탈것 탭에서
			-- 켜둔 옵션이 주문 탭을 비우면 안 된다.
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
-- 엔트리 만들기
--------------------------------------------------------------------------------

--- 같은 것이 두 번 나오는 일이 있어서(주문 하나가 직업·특성 두 스킬라인에 걸린다) 한 번만 넣는다.
--- `entry`를 그대로 목록에 넣으므로 부르는 쪽이 테이블을 재사용하면 안 된다.
---
--- **이름을 안 주면 애드온의 공용 해석기에서 가져온다.** `NameAndIconForAction`은 어떤
--- 액션이든 이름과 아이콘을 낸다 - 명령(`BINDING_NAME_*`), 사용 안 함, 커스텀 타겟처럼
--- **이름이 코드 안에 있는 타입**까지. 소스가 그 규칙을 베끼면 두 곳이 갈라진다.
--- 세 번째 반환값을 쓰는 이유는 그게 타입 이름을 안 붙인 쪽이기 때문이다("Wrath"이지
--- "주문: Wrath"가 아니다) - 여기서는 탭이 이미 타입을 말하고 있다.
local function AddEntry(entries, seen, entry)
	if (not entry.name) then
		local _, icon, bareName = DebouncePrivate.DebounceUI.NameAndIconForAction(entry);
		-- **`"?"`는 이름이 아니라 "못 풀었다"는 표시다**(`NameAndIconForAction`의
		-- `actionName or "?"`). 그 함수는 **그리는** 쪽이라 물음표가 맞는 답이다 - 이미 걸어둔
		-- 액션은 이름을 모르더라도 한 줄을 차지해야 하니까. 고르는 쪽은 반대다: 이름을
		-- 못 푼 것을 목록에 올리면 `?`라고 적힌 줄을 눌러 진짜 액션을 만들게 된다.
		--
		-- 세 번째 반환값이 nil인 적이 없어서 아래 `not entry.name` 검사만으로는 안 걸린다.
		if (bareName and bareName ~= "?") then
			entry.name = bareName;
			entry.icon = entry.icon or icon;
		end
	end

	if (not entry.name) then
		return;
	end

	-- 키에 타입을 같이 넣는다. 한 카테고리에 여러 타입이 섞이면 값이 겹치고(커스텀 타겟 1과
	-- 상태 지정 1), 값이 아예 없는 타입도 있다(사용 안 함) - `tostring`이 둘 다 받는다.
	local key = entry.type .. ":" .. tostring(entry.value);
	if (seen[key]) then
		return;
	end
	seen[key] = true;

	if (entry.subName == "") then
		entry.subName = nil;
	end

	entry.searchName = strlower(entry.name);
	entry.searchSubName = entry.subName and strlower(entry.subName) or nil;

	tinsert(entries, entry);
end

--- 주문 ID 하나를 엔트리로. 이름·아이콘이 안 나오면(아직 안 배웠거나 없는 ID) 아무것도 안 한다.
local function AddSpellEntry(entries, seen, spellID, group)
	if (not spellID) then
		return;
	end

	local spellInfo = C_Spell.GetSpellInfo(spellID);
	if (not spellInfo) then
		return;
	end

	AddEntry(entries, seen, {
		type = Constants.SPELL,
		value = spellID,
		name = spellInfo.name,
		icon = spellInfo.iconID,
		subName = C_Spell.GetSpellSubtext(spellID),
		group = group,
	});
end

--------------------------------------------------------------------------------
-- 소스: 주문서
--------------------------------------------------------------------------------

--- 플라이아웃은 **펼친다.** 통째로 버리면 그 안의 주문들에 아예 손이 닿지 않는다
--- (야수 소환, 각인 등이 전부 그 안에 있다).
---
--- 슬롯의 `isKnown`이 거짓이면 건너뛴다 - 다만 오프스펙 플라이아웃은 통째로 안 배운
--- 상태라 그 검사를 통과할 수 없다. 그래서 오프스펙일 때만 예외로 둔다.
local function AddFlyoutEntries(entries, seen, flyoutID, isOffSpec, group)
	local _, _, numSlots = GetFlyoutInfo(flyoutID);
	if (not numSlots) then
		return;
	end

	for slot = 1, numSlots do
		local spellID, overrideSpellID, isKnown = GetFlyoutSlotInfo(flyoutID, slot);
		if (spellID and (isKnown or isOffSpec)) then
			local displayID = overrideSpellID or spellID;
			local spellInfo = C_Spell.GetSpellInfo(displayID);
			-- 패시브 검사가 여기에도 있어야 한다. `AddSpellBookItem`의 검사는 이 함수를
			-- 부르기 **전에** 지나가고, 거기서 보는 `isPassive`는 플라이아웃 자신의 것이라
			-- 언제나 false다 - 안쪽 주문은 그 검사를 통과한 적이 없다.
			if (spellInfo and not C_Spell.IsSpellPassive(displayID)) then
				AddEntry(entries, seen, {
					type = Constants.SPELL,
					value = spellID,
					name = spellInfo.name,
					icon = spellInfo.iconID,
					subName = C_Spell.GetSpellSubtext(displayID),
					group = group,
					isOffSpec = isOffSpec or nil,
				});
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
local function AddSpellBookItem(entries, seen, slotIndex, bank, isOffSpec, group)
	local info = C_SpellBook.GetSpellBookItemInfo(slotIndex, bank);
	if (not info) then
		return;
	end

	local itemType = info.itemType;

	if (itemType == Enum.SpellBookItemType.FutureSpell) then
		-- 아직 못 배운 주문. 걸어둬도 안 나가므로 목록에 없는 게 맞다.
		return;
	end

	-- 패시브는 **시전할 수 있는 물건이 아니다.** 단축키에 걸 대상이 아니므로 필터로
	-- 켤 수 있게 두지도 않았다 - 켜지는 옵션은 "켜면 쓸 수 있다"는 뜻이 된다.
	--
	-- `info.isPassive`만으로는 부족하다. API 문서가 그 필드에 **"주문이 아니면 언제나
	-- false"**라고 못 박아 뒀는데, 소환수 항목은 `Spell`이 아니라 `PetAction`이라 그 말에
	-- 걸린다 - 소환수 패시브가 전부 통과했다. `C_SpellBook.IsSpellBookItemPassive`도 같은
	-- 단서가 붙어 있어 소용없다. 주문 ID로 직접 묻는 것만 남는다(블리자드도 마이크로 메뉴에서
	-- 이렇게 한다, `MainMenuBarMicroButtons.lua`).
	if (info.isPassive or (info.spellID and C_Spell.IsSpellPassive(info.spellID))) then
		return;
	end

	if (itemType == Enum.SpellBookItemType.Flyout) then
		AddFlyoutEntries(entries, seen, info.actionID, isOffSpec, group);
		return;
	end

	local value;
	if (itemType == Enum.SpellBookItemType.PetAction) then
		-- 소환수 항목은 여기서 둘로 갈린다.
		--
		-- **주문이면 `spellID`로 간다.** `actionID`는 주문 ID가 아니라 비트로 채워진
		-- petActionID이므로(실측 `0x06000003`) 그걸 주문으로 저장하면 목록엔 이름이 뜨는데
		-- 눌러도 아무 일이 없다 - 조용히 죽는 바인딩이라 제일 나쁜 종류다.
		--
		-- **명령이면(`spellID`가 없다) 그 petActionID가 유일한 식별자다.** 실행은 주문이
		-- 아니라 보안 슬래시 명령으로 나간다(`Constants.PETACTION`). 아는 값만 받는다.
		if (not info.spellID) then
			local command = DebouncePrivate.GetPetActionCommandByActionID(info.actionID);
			-- **표에 있는 것만으로는 모자란다.** 표는 우리가 적은 것이고, 실행은 게임이 그
			-- 슬래시 명령을 실제로 올려놨을 때만 된다(`SLASH_<키>1` 전역). 명령이 게임
			-- 버전마다 갈리므로, 여기서 본문을 만들어보고 안 나오면 목록에도 안 올린다 -
			-- 목록에 있는데 눌러도 아무 일이 없는 것이 제일 나쁘다.
			if (command and DebouncePrivate.GetPetActionMacroText(command)) then
				AddEntry(entries, seen, {
					type = Constants.PETACTION,
					value = command,
					name = info.name,
					icon = info.iconID,
					group = LLL["PET"],
					-- 이름·아이콘은 저장해둔다. 펫이 없으면 주문서가 통째로 비어서 그릴 때
					-- 다시 풀 수가 없는데, 프로필 목록은 펫이 없을 때도 그려져야 한다.
					props = { name = info.name, icon = info.iconID },
				});
			end
			return;
		end
		value = C_SpellBook.FindBaseSpellByID(info.spellID) or info.spellID;
	else
		value = info.actionID;
	end

	AddEntry(entries, seen, {
		type = Constants.SPELL,
		value = value,
		name = info.name,
		icon = info.iconID,
		subName = info.subName,
		group = group,
		isOffSpec = isOffSpec or nil,
	});
end

--- 소환수 은행은 평평하다 - 스킬라인이 없고 슬롯 1..n이 전부다.
local function AddPetSpells(entries, seen)
	local numPetSpells = C_SpellBook.HasPetSpells();
	if (not numPetSpells) then
		return;
	end

	for slotIndex = 1, numPetSpells do
		AddSpellBookItem(entries, seen, slotIndex, Enum.SpellBookSpellBank.Pet, false, LLL["PET"]);
	end
end

--- 정렬하지 않는다. 주문서 순서가 곧 일반 -> 직업 -> 현재 특성 -> 다른 특성이라
--- (`Enum.SpellBookSkillLineIndex`), 이름순으로 다시 세우면 그 묶음이 흩어진다.
--- 그 묶음이 곧 머리글이다.
---
--- **소환수 주문도 여기 들어온다** - 맨 뒤에 "소환수" 머리글로 붙는다. 탭을 따로 두면
--- 소환수를 가진 절반의 직업만 쓰는 탭이 하나 서 있게 되고, 어차피 같은 주문서다.
local function BuildPlayerSpells(entries)
	local seen = {};
	local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0;

	for skillLineIndex = 1, numSkillLines do
		local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex);
		if (skillLineInfo and not skillLineInfo.shouldHide) then
			local isOffSpec = skillLineInfo.offSpecID ~= nil;
			-- 오프스펙이라는 사실은 **머리글이 말한다.** 행마다 반복하면 부제 자리를 통째로
			-- 뺏는데, 거기엔 랭크가 들어가야 한다.
			local group = isOffSpec and format(LLL["INACTIVE_SPEC_LABEL"], skillLineInfo.name)
				or skillLineInfo.name;

			local first = skillLineInfo.itemIndexOffset + 1;
			local last = skillLineInfo.itemIndexOffset + skillLineInfo.numSpellBookItems;
			for slotIndex = first, last do
				AddSpellBookItem(entries, seen, slotIndex, Enum.SpellBookSpellBank.Player, isOffSpec, group);
			end
		end
	end

	AddPetSpells(entries, seen);
end

ActionCatalog.RegisterSource({
	key = "spellbook",
	categories = {
		{
			key = "spell",
			name = LLL["TYPE_SPELL"],
			filters = { "offSpec" },
			Build = BuildPlayerSpells,
		},
	},
});

--------------------------------------------------------------------------------
-- 소스: 매크로
--------------------------------------------------------------------------------

--- 저장값은 **이름**이다. 인덱스가 아니다 - 매크로 하나를 지우면 그 뒤 인덱스가 전부
--- 밀리므로, 인덱스를 저장하면 남의 매크로를 가리키게 된다. 이 애드온은 이미 커서에서
--- 떨어진 매크로도 이름으로 받는다(`GetActionTypeAndValueFromCursorInfo`).
local function BuildMacros(entries)
	local seen = {};
	local numAccount, numCharacter = GetNumMacros();

	local function Add(index, group)
		local name, icon, body = GetMacroInfo(index);
		if (not name) then
			return;
		end
		AddEntry(entries, seen, {
			type = Constants.MACRO,
			value = name,
			name = name,
			icon = icon,
			group = group,
			-- 게임이 매크로 툴팁을 안 만들어 준다. 본문을 그대로 보여주는 것이 여기서
			-- 가장 쓸모 있다 - 이름만으로는 어느 매크로인지 모르는 일이 흔하다.
			tooltipText = body,
		});
	end

	for index = 1, (numAccount or 0) do
		Add(index, LLL["SPELL_PICKER_GROUP_ACCOUNT_MACROS"]);
	end

	-- 캐릭터 매크로는 개수와 상관없이 **계정 구간 다음 인덱스부터** 시작한다.
	local accountSlots = DebouncePrivate.GetMacroSlotLimits();
	for index = accountSlots + 1, accountSlots + (numCharacter or 0) do
		Add(index, LLL["SPELL_PICKER_GROUP_CHARACTER_MACROS"]);
	end
end

ActionCatalog.RegisterSource({
	key = "macro",
	categories = {
		{
			key = "macro",
			name = LLL["TYPE_MACRO"],
			IsAvailable = function()
				local numAccount, numCharacter = GetNumMacros();
				return ((numAccount or 0) + (numCharacter or 0)) > 0;
			end,
			Build = BuildMacros,
		},
	},
});

--------------------------------------------------------------------------------
-- 소스: 특수
--------------------------------------------------------------------------------

--- 주문서에 없지만 걸고 싶은 것들. 전부 **한 자리에 하나씩** 있는 물건이라 열거가 아니라
--- 목록을 손으로 적는다.
---
--- 상수로 박힌 것은 전투 애완동물 둘뿐이고, 그건 블리자드도 그렇게 한다
--- (`Blizzard_PetCollection.xml`의 KeyValue spellID). 나머지는 API가 값을 준다 -
--- 비행 방식은 캐릭터마다 다르고, 단일 버튼 도우미는 직업마다 다르기 때문이다.
local REVIVE_BATTLE_PETS_SPELL_ID = 125439;
local SUMMON_RANDOM_FAVORITE_PET_SPELL_ID = 243819;

--- 무작위 즐겨찾는 탈것. 저장값은 mountID `0`이고, 그게 `SummonByID(0)`이다.
--- 이름·아이콘은 주문 150544에서 온다 - 애드온의 다른 곳도 그렇게 푼다
--- (`NameAndIconForAction`, `Misc.lua`).
local RANDOM_FAVORITE_MOUNT_SPELL_ID = 150544;

local function BuildSpecials(entries)
	local seen = {};

	local mountInfo = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT_SPELL_ID);
	if (mountInfo) then
		AddEntry(entries, seen, {
			type = Constants.MOUNT,
			value = 0,
			name = mountInfo.name,
			icon = mountInfo.iconID,
			spellID = RANDOM_FAVORITE_MOUNT_SPELL_ID,
		});
	end

	-- 비행 방식 전환. 안 열었으면 주문 자체가 없다.
	if (C_MountJournal.IsDragonridingUnlocked and C_MountJournal.IsDragonridingUnlocked()) then
		AddSpellEntry(entries, seen, C_MountJournal.GetDynamicFlightModeSpellID());
	end

	-- 단일 버튼 도우미. 직업·특성마다 다른 주문이라 물어봐야 안다.
	if (C_AssistedCombat and C_AssistedCombat.GetActionSpell) then
		AddSpellEntry(entries, seen, C_AssistedCombat.GetActionSpell());
	end

	AddSpellEntry(entries, seen, REVIVE_BATTLE_PETS_SPELL_ID);
	AddSpellEntry(entries, seen, SUMMON_RANDOM_FAVORITE_PET_SPELL_ID);
end

--------------------------------------------------------------------------------
-- 소스: 탈것
--------------------------------------------------------------------------------

--- **수집한 것 전부** 넣는다. 수백 개여도 상관없다 - ScrollBox가 가상화되어 있어 보이는
--- 만큼만 프레임을 잡고, 찾는 일은 검색창이 한다. 즐겨찾기는 걸러내는 조건이 아니라
--- 위로 올리는 머리글이고, "즐겨찾기만"은 필터에 따로 있다.
---
--- 정렬은 여기서 한다. 주문서와 달리 `GetMountIDs`가 주는 순서에는 뜻이 없다.
local function BuildMounts(entries)
	local mountIDs = C_MountJournal.GetMountIDs();
	if (not mountIDs) then
		return;
	end

	local collected = {};
	for i = 1, #mountIDs do
		local mountID = mountIDs[i];
		local name, spellID, icon, _, _, _, isFavorite, _, _, shouldHideOnChar, isCollected =
			C_MountJournal.GetMountInfoByID(mountID);
		if (name and isCollected and not shouldHideOnChar) then
			collected[#collected + 1] = {
				type = Constants.MOUNT,
				value = mountID,
				name = name,
				icon = icon,
				-- 저장값은 mountID지만 툴팁은 주문으로 뜬다.
				spellID = spellID,
				isFavorite = isFavorite and true or false,
			};
		end
	end

	sort(collected, function(a, b)
		if (a.isFavorite ~= b.isFavorite) then
			return a.isFavorite;
		end
		return a.name < b.name;
	end);

	local seen = {};
	for i = 1, #collected do
		local entry = collected[i];
		entry.group = entry.isFavorite and LLL["SPELL_PICKER_GROUP_FAVORITES"]
			or LLL["SPELL_PICKER_GROUP_OTHERS"];
		AddEntry(entries, seen, entry);
	end
end

ActionCatalog.RegisterSource({
	key = "mount",
	categories = {
		{
			key = "mount",
			name = LLL["SPELL_PICKER_TAB_MOUNT"],
			filters = { "favorites" },
			IsAvailable = function() return (C_MountJournal.GetNumMounts() or 0) > 0; end,
			Build = BuildMounts,
		},
	},
});

--------------------------------------------------------------------------------
-- 소스: 장난감
--------------------------------------------------------------------------------

--- 장난감은 아이템이다 - 저장값은 itemID고 타입은 `Constants.ITEM`이다.
---
--- **블리자드의 장난감 상자 필터를 그대로 읽는다.** `GetToyFromIndex`가 색인하는 목록이
--- 그쪽 필터를 이미 거친 것이라, 사용자가 장난감 상자에서 확장팩이나 "수집한 것만"을
--- 걸어놨으면 여기 목록도 같이 줄어든다. 그걸 우회하려면 필터를 껐다 켜야 하는데,
--- **그건 블리자드 상태를 건드리는 것**이라 안 한다(이 애드온이 서 있는 자리가 그 반대다).
--- 대신 목록이 왜 짧은지는 검증 목록에 적어뒀다.
local function BuildToys(entries)
	local collected = {};

	for index = 1, (C_ToyBox.GetNumFilteredToys() or 0) do
		local itemID = C_ToyBox.GetToyFromIndex(index);
		if (itemID and itemID > 0 and PlayerHasToy(itemID)) then
			local _, name, icon = C_ToyBox.GetToyInfo(itemID);
			if (name) then
				collected[#collected + 1] = {
					type = Constants.ITEM,
					value = itemID,
					name = name,
					icon = icon,
					isFavorite = C_ToyBox.GetIsFavorite(itemID) and true or false,
				};
			end
		end
	end

	sort(collected, function(a, b)
		if (a.isFavorite ~= b.isFavorite) then
			return a.isFavorite;
		end
		return a.name < b.name;
	end);

	local seen = {};
	for i = 1, #collected do
		local entry = collected[i];
		entry.group = entry.isFavorite and LLL["SPELL_PICKER_GROUP_FAVORITES"]
			or LLL["SPELL_PICKER_GROUP_OTHERS"];
		AddEntry(entries, seen, entry);
	end
end

ActionCatalog.RegisterSource({
	key = "toy",
	categories = {
		{
			key = "toy",
			name = LLL["SPELL_PICKER_TAB_TOY"],
			filters = { "favorites" },
			-- **탭을 숨기지 않는다.** 쓸 수 있는 개수 API가 전부 블리자드 장난감 상자
			-- 필터를 탄 값이라(`GetNumLearnedDisplayedToys`는 그쪽 "수집/표시" 진행도
			-- 카운터다) 사용자가 거기서 "미수집만" 같은 필터를 걸어두면 0이 나온다.
			-- 그걸로 탭을 숨기면 자기 장난감에 닿을 길이 아예 없어진다 - 우리 창에는 남의
			-- 필터를 푸는 수단이 없고, 있어도 블리자드 상태는 안 건드린다.
			--
			-- 목록이 그 필터를 타는 것은 남는 비용이다(빈 목록이면 안내문이 뜬다).
			-- 탭이 사라지는 것과 달리 되돌릴 길이 사용자에게 보인다.
			IsAvailable = function() return true; end,
			Build = BuildToys,
		},
	},
});

--- 특수는 **맨 끝이다.** 등록 순서가 곧 탭 순서인데, 이건 어디에도 안 맞는 것들을 모은
--- 자루라 앞에 서면 안 된다. (그래서 `BuildSpecials`가 정의된 자리와 등록하는 자리가 다르다.)
ActionCatalog.RegisterSource({
	key = "special",
	categories = {
		{
			key = "special",
			name = LLL["SPELL_PICKER_TAB_SPECIAL"],
			Build = BuildSpecials,
		},
	},
});
