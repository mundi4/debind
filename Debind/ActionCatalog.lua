local _, DebindPrivate = ...;

local Constants          = DebindPrivate.Constants;
local LLL                = DebindPrivate.L;

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
--- **엔트리 계약** - `DebindFrameMixin:AddNewAction(type, value)`에 그대로 넘어간다:
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
---   tooltipText  툴팁 본문. 게임이 툴팁을 안 주는 타입이 쓴다 - 매크로는 본문을,
---                애드온 고유 액션은 **무엇을 하는 것인지**를(`TYPE_*_DESC`). 뒤쪽은
---                선택이 아니다: 이름이 설명을 못 하는 타입들이라 툴팁이 유일한 설명이다
---   tooltipTitle 툴팁 제목이 행의 이름과 **달라야 할 때만**. 대상 지정 행이 그렇다 -
---                행은 대상만 적고 타입은 머리글이 말하는데, 툴팁은 머리글에서 떨어져 뜬다
---   group      머리글. **같은 값이 이어지는 동안 한 덩어리다.** nil이면 머리글을 안 단다
---   isOffSpec  지금 특성이 아닌 주문. 기본 필터에서는 **들어온다**
---   isUnlearned Not learned yet (`FutureSpell`). Dimmed like isOffSpec, but no filter hides it -
---              "다른 특성" would be a lie about a spell of the spec you are standing in
---   isFavorite 즐겨찾기 여부. **이 개념이 없는 엔트리는 nil로 둔다** - "즐겨찾기만"
---              필터가 nil을 안 건드리므로, 탈것 탭의 설정이 주문 탭을 비우지 않는다
---   searchName / searchSubName  소문자로 미리 접어둔 검색용 사본
---
--- **주의: 저장은 base, 표시는 override.** `spellID` 필드는 이미 오버라이드가 적용된
--- 값이라 그걸 저장하면 특성을 바꿨을 때 죽은 ID가 남는다. `NameAndIconForAction`
--- (`DebindUI.lua`)이 그릴 때 base -> override로 다시 푸는 것이 이 애드온의 규약이다.
local ActionCatalog = {};
DebindPrivate.ActionCatalog = ActionCatalog;

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
---             key = "spell", name = "주문",          -- 탭에 그대로 걸리는 글자. **복수**다
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
	-- **이름이나 아이콘 중 하나만 없어도 물어본다.** 대상 지정 세 타입은 이름을 우리가
	-- 주지만(유닛 이름) 아이콘은 해석기 것을 쓴다 - 여기서 아이콘 ID를 또 적으면 상세
	-- 패널과 목록이 다른 그림을 그리게 된다.
	if (not entry.name or not entry.icon) then
		local _, icon, bareName = DebindPrivate.DebindUI.NameAndIconForAction(entry);
		-- **`"?"`는 이름이 아니라 "못 풀었다"는 표시다**(`NameAndIconForAction`의
		-- `actionName or "?"`). 그 함수는 **그리는** 쪽이라 물음표가 맞는 답이다 - 이미 걸어둔
		-- 액션은 이름을 모르더라도 한 줄을 차지해야 하니까. 고르는 쪽은 반대다: 이름을
		-- 못 푼 것을 목록에 올리면 `?`라고 적힌 줄을 눌러 진짜 액션을 만들게 된다.
		--
		-- 세 번째 반환값이 nil인 적이 없어서 아래 `not entry.name` 검사만으로는 안 걸린다.
		--
		-- **이름을 준 엔트리의 이름은 안 덮는다.** 대상 지정 세 타입이 그 경우다 - 해석기가
		-- 내는 이름은 타입 이름 하나뿐(유닛이 안 들어간다)이라 덮으면 유닛 열세 줄이 전부
		-- 같은 글자가 된다. 아이콘은 반대로 언제나 해석기 것으로 채운다.
		if (not entry.name and bareName and bareName ~= "?") then
			entry.name = bareName;
		end
		entry.icon = entry.icon or icon;
	end

	if (not entry.name) then
		return;
	end

	-- 키에 타입을 같이 넣는다. 한 카테고리에 여러 타입이 섞이면 값이 겹치고(커스텀 타겟 1과
	-- 상태 지정 1), 값이 아예 없는 타입도 있다(사용 안 함) - `tostring`이 둘 다 받는다.
	local key = entry.type .. ":" .. tostring(entry.value);

	-- **대상도 키의 일부다.** 대상 지정·주시 대상·메뉴 열기는 값이 없고 대상만으로 갈린다
	-- (`props.unit`). 안 넣으면 유닛 열세 개가 전부 `target:nil` 하나로 접혀서 목록에
	-- 첫 번째 하나만 남는다.
	if (entry.props and entry.props.unit) then
		key = key .. ":" .. entry.props.unit;
	end

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

--- 플라이아웃 **자체**를 한 줄로. 펼친 주문들 바로 앞에 선다.
---
--- 안쪽 주문들과 **같이 올린다, 대신이 아니다.** 야수 소환 3번만 딱 걸고 싶은 사람과
--- 야수 소환 묶음 전체를 한 키에 두고 싶은 사람은 다른 사람이고, 둘 다 있어야 한다.
--- 키가 `type:value`라 `flyout:229`와 `spell:229`는 서로를 안 가린다(`AddEntry` 참고).
---
--- **이름은 게임 것을 그대로 쓴다.** `AddEntry`의 해석기 경유 갈래로 보내면
--- `NameAndIconForAction`이 같은 값을 다시 푸는 일이 되고, 여기서는 이미 손에 있다.
---
--- 툴팁은 우리가 안 쓴다. `spellBookSlot`/`spellBookBank`를 얹어 두면 선택 창이
--- `GameTooltip:SetSpellBookItem`으로 **게임이 주문책에서 띄우는 그 툴팁**을 그대로 띄운다
--- (`SpellPicker.lua`). 그 두 값은 엔트리에만 있고 액션에는 안 들어간다 - 주문서가 바뀌면
--- 슬롯 번호가 밀리지만, 그때 카탈로그가 통째로 다시 지어진다.
local function AddFlyoutEntry(entries, seen, flyoutID, isOffSpec, group, slotIndex, bank)
	local name, icon, isKnown, hasUsableSlot = DebindPrivate.GetFlyoutNameAndIcon(flyoutID, isOffSpec);
	if (not name) then
		return;
	end

	-- 안 배운 플라이아웃은 안 올린다. 오프스펙은 통째로 안 배운 상태가 정상이라 예외다 -
	-- `AddFlyoutEntries`가 슬롯의 `isKnown`에 두는 예외와 같은 이유다.
	if (not isKnown and not isOffSpec) then
		return;
	end

	-- **열어도 빈 칸만 뜨는 것은 안 올린다.** 슬롯이 전부 안 배운 상태(길들인 야수가 없는
	-- 야수 소환 등)라는 뜻이다. 아이콘 유무로는 못 가린다 - 플라이아웃 자기 아이콘은 칸이
	-- 비어 있어도 나온다(`Misc.lua`의 `GetFlyoutNameAndIcon`).
	if (not hasUsableSlot) then
		return;
	end

	AddEntry(entries, seen, {
		type = Constants.FLYOUT,
		value = flyoutID,
		name = name,
		icon = icon,
		group = group,
		isOffSpec = isOffSpec or nil,
		-- 선택 창이 게임 툴팁을 띄우는 데 쓴다. 저장되는 값이 아니다.
		spellBookSlot = slotIndex,
		spellBookBank = bank,
	});
end

--- 플라이아웃은 **펼친다.** 통째로 버리면 그 안의 주문들에 아예 손이 닿지 않는다
--- (야수 소환, 각인 등이 전부 그 안에 있다).
---
--- 슬롯의 `isKnown`이 거짓이면 건너뛴다 - 다만 오프스펙 플라이아웃은 통째로 안 배운
--- 상태라 그 검사를 통과할 수 없다. 그래서 오프스펙일 때만 예외로 둔다.
---
--- **`isKnown`만으로는 야수 소환의 빈 칸이 안 걸러진다.** 마구간 칸 수만큼 슬롯이 있고
--- 비어 있어도 배운 것으로 나오기 때문이다. 검사는 `Misc.lua`의 `IsEmptyCallPetSlot` 하나이고
--- 시전 쪽(`GetFlyoutCastableSlots`)도 같은 것을 부른다 - 갈리면 **팝업에는 안 뜨는 칸이
--- 목록에는 뜨는** 상태가 된다(실제로 그랬다).
local function AddFlyoutEntries(entries, seen, flyoutID, isOffSpec, group)
	local _, _, numSlots = GetFlyoutInfo(flyoutID);
	if (not numSlots) then
		return;
	end

	for slot = 1, numSlots do
		local spellID, overrideSpellID, isKnown = GetFlyoutSlotInfo(flyoutID, slot);
		if (spellID and (isKnown or isOffSpec) and not DebindPrivate.IsEmptyCallPetSlot(spellID)) then
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

	-- Not-yet-learned spells stay in. They are the same kind of thing as an off-spec spell - in the
	-- spellbook, not castable right now - and this addon is built around setting a key once and
	-- leaving it. Binding at level 20 the spell that arrives at level 40 costs nothing and starts
	-- working the moment it is learned. Blizzard's spellbook draws both through one flag
	-- (`isUnlearned = isOffSpec or FutureSpell`, `Blizzard_SpellBookItem.lua`).
	--
	-- The passive check below still applies: `isPassive` is meaningful here, a FutureSpell is a
	-- spell. A passive you have not learned is no more bindable than one you have.
	local isUnlearned = itemType == Enum.SpellBookItemType.FutureSpell;

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
		-- 묶음을 먼저, 그 안의 주문들을 뒤에. 둘 다 올린다 - 순서가 이래야 목록에서
		-- "야수 소환" 다음에 야수 다섯 마리가 오고, 앞의 한 줄이 뒤의 묶음을 설명한다.
		AddFlyoutEntry(entries, seen, info.actionID, isOffSpec, group, slotIndex, bank);
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
			local command = DebindPrivate.GetPetActionCommandByActionID(info.actionID);
			-- **표에 있는 것만으로는 모자란다.** 표는 우리가 적은 것이고, 실행은 게임이 그
			-- 슬래시 명령을 실제로 올려놨을 때만 된다(`SLASH_<키>1` 전역). 명령이 게임
			-- 버전마다 갈리므로, 여기서 본문을 만들어보고 안 나오면 목록에도 안 올린다 -
			-- 목록에 있는데 눌러도 아무 일이 없는 것이 제일 나쁘다.
			if (command and DebindPrivate.GetPetActionMacroText(command)) then
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

	-- Grey alone cannot say **why** a row is grey. An off-spec row has its header to explain it; a
	-- future spell sits inside the class group with nothing to set it apart. The level requirement
	-- is the one answer that is always true, so it takes the subtitle line (the rank that would
	-- otherwise sit there is empty on an unlearned spell anyway).
	--
	-- The spellbook's other two cases get no text rather than a guess: "learn it from a trainer"
	-- is dead in retail, and the newly-boosted lock string is a sentence that will not fit 195px.
	-- Off-spec is excluded here for the same reason Blizzard leaves it blank - the header said it.
	local subName = info.subName;
	if (isUnlearned and not isOffSpec) then
		local levelLearned = C_SpellBook.GetSpellBookItemLevelLearned(slotIndex, bank);
		if (levelLearned and levelLearned > UnitLevel("player")) then
			subName = format(SPELLBOOK_AVAILABLE_AT, levelLearned);
		end
	end

	AddEntry(entries, seen, {
		type = Constants.SPELL,
		value = value,
		name = info.name,
		icon = info.iconID,
		subName = subName,
		group = group,
		isOffSpec = isOffSpec or nil,
		isUnlearned = isUnlearned or nil,
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

--- 주문서에 없지만 걸고 싶은 주문·탈것들. 전부 **한 자리에 하나씩** 있는 물건이라 열거가
--- 아니라 목록을 손으로 적는다.
---
--- **주문 탭의 맨 끝 그룹이고 이름이 "그 밖"이다.** 한때 자기 탭("특수")이었는데, 내용이
--- 전부 "주문서에서 한 칸 비껴 있는 주문"이라 주문 탭에 붙는 것이 맞다. 이름을 "특수"로
--- 안 가져온 것은 그 이름이 **특수 탭의 것**이기 때문이다 - 그쪽은 애드온 고유 액션이라는
--- 뜻이 있는 이름이고, 여기는 정말로 나머지를 담는 자루다. 자루 쪽이 "그 밖"을 쓴다.
---
--- **중복은 `seen`이 알아서 막는다.** 여기 있는 것 중 몇은 캐릭터에 따라 주문서에도 있다
--- (전투 애완동물 되살리기 등). 주문서를 먼저 훑으므로 그때는 일반/직업 그룹에 남고
--- 여기서는 안 붙는다 - 같은 주문이 두 그룹에 뜨는 일이 없다.
---
--- 비행 방식 전환(`GetDynamicFlightModeSpellID`)이 여기 없는 것이 그 규칙의 예다.
--- 주문서 **일반**에 이미 들어 있어서 여기 적으면 하는 일이 없다.
---
--- 상수로 박힌 것은 전투 애완동물 둘뿐이고, 그건 블리자드도 그렇게 한다
--- (`Blizzard_PetCollection.xml`의 KeyValue spellID). 나머지는 API가 값을 준다 -
--- 단일 버튼 도우미가 직업마다 다르기 때문이다.
local REVIVE_BATTLE_PETS_SPELL_ID = 125439;
local SUMMON_RANDOM_FAVORITE_PET_SPELL_ID = 243819;

--- 무작위 즐겨찾는 탈것. 저장값은 mountID `0`이고, 그게 `SummonByID(0)`이다.
--- 이름·아이콘은 주문 150544에서 온다 - 애드온의 다른 곳도 그렇게 푼다
--- (`NameAndIconForAction`, `Misc.lua`).
local RANDOM_FAVORITE_MOUNT_SPELL_ID = 150544;

--- **이 그룹만 이름순으로 세운다.** 주문서에서 온 그룹들은 정렬하면 안 된다 - 거기서는
--- 순서가 곧 스킬라인이고 그게 머리글이 되기 때문이다(바로 아래 `BuildPlayerSpells` 참고).
--- 여기는 반대다. 손으로 적은 목록이라 **적어둔 순서에 뜻이 없고**, 뜻 없는 순서를 그대로
--- 내보내면 읽는 쪽은 있지도 않은 규칙을 찾게 된다.
---
--- 임시 목록에 모았다가 옮기는 것은 그래서다. `seen`은 그대로 넘기므로 주문서와의 중복
--- 제거는 모으는 단계에서 이미 끝나 있다.
local function AddExtraSpellEntries(entries, seen)
	local group = LLL["SPELL_PICKER_GROUP_OTHERS"];
	local collected = {};

	local mountInfo = C_Spell.GetSpellInfo(RANDOM_FAVORITE_MOUNT_SPELL_ID);
	if (mountInfo) then
		AddEntry(collected, seen, {
			type = Constants.MOUNT,
			value = 0,
			name = mountInfo.name,
			icon = mountInfo.iconID,
			spellID = RANDOM_FAVORITE_MOUNT_SPELL_ID,
			group = group,
		});
	end

	-- 단일 버튼 도우미. 직업·특성마다 다른 주문이라 물어봐야 안다.
	if (C_AssistedCombat and C_AssistedCombat.GetActionSpell) then
		AddSpellEntry(collected, seen, C_AssistedCombat.GetActionSpell(), group);
	end

	AddSpellEntry(collected, seen, REVIVE_BATTLE_PETS_SPELL_ID, group);
	AddSpellEntry(collected, seen, SUMMON_RANDOM_FAVORITE_PET_SPELL_ID, group);

	sort(collected, function(a, b) return a.name < b.name; end);

	for i = 1, #collected do
		tinsert(entries, collected[i]);
	end
end

--- 그룹 **안**은 정렬하지 않는다. 스킬라인 안의 순서는 주문서가 정한 것이고, 이름순으로
--- 다시 세우면 그 묶음이 흩어진다. 그 묶음이 곧 머리글이다.
---
--- 그룹 **사이**의 순서만 하나 바꾼다 - **일반을 뒤로 보낸다.**
--- `Enum.SpellBookSkillLineIndex`는 `General=1, Class=2, MainSpec=3, OffSpecStart=4`라
--- 인덱스를 그대로 따르면 일반이 맨 앞에 선다. 그런데 여기서 찾는 것은 대개 직업 주문이고
--- 일반은 탈것·화롯불 같은 것들이다. 요즘 주문서 창도 직업을 앞에 두고 일반을 뒤에 둔다.
--- 결과: 직업 -> 현재 특성 -> 다른 특성 -> 일반 -> 소환수 -> 그 밖.
---
--- **소환수 주문도 여기 들어온다** - "소환수" 머리글로 붙는다. 탭을 따로 두면
--- 소환수를 가진 절반의 직업만 쓰는 탭이 하나 서 있게 되고, 어차피 같은 주문서다.
local function BuildPlayerSpells(entries)
	local seen = {};
	local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0;

	-- 상수로 부른다. 이 자리에서 `1`은 "첫 번째"가 아니라 **일반**이라는 뜻이고, 숫자로
	-- 적으면 그 뜻이 사라진다(`.zzz/refactor-candidates.md` 14번이 같은 이야기다).
	local generalIndex = Enum.SpellBookSkillLineIndex and Enum.SpellBookSkillLineIndex.General or 1;

	local function AddSkillLine(skillLineIndex)
		local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex);
		if (not skillLineInfo or skillLineInfo.shouldHide) then
			return;
		end

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

	for skillLineIndex = 1, numSkillLines do
		if (skillLineIndex ~= generalIndex) then
			AddSkillLine(skillLineIndex);
		end
	end

	-- 일반은 여기서. 스킬라인이 하나도 없는 경우(생성 직후 등)에는 그냥 아무것도 안 붙는다.
	if (generalIndex <= numSkillLines) then
		AddSkillLine(generalIndex);
	end

	AddPetSpells(entries, seen);

	-- 주문서 밖의 것들이 맨 끝에 "그 밖" 그룹으로 붙는다. `seen`을 그대로 넘기는 것이
	-- 핵심이다 - 주문서에 이미 있는 것은 여기서 안 붙는다.
	AddExtraSpellEntries(entries, seen);
end

ActionCatalog.RegisterSource({
	key = "spellbook",
	categories = {
		{
			key = "spell",
			-- 탭 이름은 `TYPE_SPELL`을 재사용하지 않는다. 저건 상세 패널이 "이 액션은
			-- Spell이다"라고 말할 때 쓰는 **타입 이름**이라 단수여야 하고, 탭은 모아둔
			-- 것을 가리키는 자리라 복수여야 한다. 한때 같은 키를 썼더니 탭 줄이
			-- "Spell / Macro / Mounts / Toys"로 섞였다.
			name = LLL["SPELL_PICKER_TAB_SPELL"],
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
--- **계정과 캐릭터가 각자 `seen`을 쓴다.** 저장값이 이름이라 같은 이름의 매크로 둘이
--- 하나로 접혔다 - 계정 "치유"와 캐릭터 "치유"가 있으면 계정 것만 목록에 서고 캐릭터 것은
--- **어디서도 닿을 수 없었다**([추가] 드롭다운이 없어지면서 다른 길도 사라졌다).
--- 주문서의 중복(한 주문이 두 스킬라인에 걸리는 것)은 같은 물건이지만 이 둘은 다른 물건이다.
---
--- 한 은행 안에서는 이름이 겹치지 않으므로 은행마다 따로 세면 그것으로 충분하다.
---
--- **이름이 겹칠 때 어느 쪽이 실행되는지는 여기서 못 정한다.** 저장값이 이름인 것은 이
--- 애드온의 계약이고(인덱스를 저장하면 매크로 하나만 지워도 남의 것을 가리킨다), 커서에서
--- 떨궈 넣는 길도 똑같이 이름으로 받는다. 목록에 안 보이는 것과 실행이 헷갈리는 것은 다른
--- 문제라, 여기서는 **보이게 하는 것까지** 한다.
local function BuildMacros(entries)
	local numAccount, numCharacter = GetNumMacros();

	local seen = {};

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
	seen = {};
	local accountSlots = DebindPrivate.GetMacroSlotLimits();
	for index = accountSlots + 1, accountSlots + (numCharacter or 0) do
		Add(index, LLL["SPELL_PICKER_GROUP_CHARACTER_MACROS"]);
	end
end

ActionCatalog.RegisterSource({
	key = "macro",
	categories = {
		{
			key = "macro",
			name = LLL["SPELL_PICKER_TAB_MACRO"],
			IsAvailable = function()
				local numAccount, numCharacter = GetNumMacros();
				return ((numAccount or 0) + (numCharacter or 0)) > 0;
			end,
			Build = BuildMacros,
		},
	},
});

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

--------------------------------------------------------------------------------
-- 소스: 명령
--------------------------------------------------------------------------------

--- **"누르면 무슨 일이 일어나는" 것들.** 두 곳에서 온다:
---
---   우리 것   대상 지정 · 주시 대상 지정 · 메뉴 열기 · 공격대 표적. 대상이나 표적을
---             인자로 받는 명령이고, 타입은 각각 따로다
---   게임 것   게임 자신의 단축키 목록(점프, 가방 열기, 액션바 1번 …). 타입은
---             `Constants.COMMAND`이고 저장값은 명령 문자열이다("JUMP", "TOGGLEBACKPACK")
---
--- **탭 이름을 "바인딩 명령"이 아니라 "명령"으로 지은 것이 이 합침을 가능하게 했다.**
--- 앞의 이름은 `Constants.COMMAND` 하나를 가리키는 타입 이름이라 우리 것이 끼면 거짓말이
--- 되지만, "명령"은 동사 하나를 가리키는 말이라 둘 다 받는다.
---
--- **우리 것이 먼저 온다.** 게임 명령은 250줄쯤이라 뒤에 두지 않으면 우리 것 스무 줄이
--- 그 안에 묻힌다. 이 탭에서 목록을 끝까지 훑는 사람은 없고 검색으로 찾는 자리다.
---
--- 특수 탭으로 안 간 이유: 저 탭은 **이 애드온에만 있는 개념**(지정 대상, 사용자 상태)을
--- 담는 자리다. 대상 지정과 공격대 표적은 게임에도 같은 성격의 단축키가 있어서
--- (`BINDING_HEADER_TARGETING`, `BINDING_HEADER_RAID_TARGET`) 이쪽 이웃이 맞다.
---
--- 이 목록은 한때 [추가] 드롭다운에도 있었다. 거기는 머리글 아홉 겹의 하위 메뉴라
--- **이름을 이미 알고 있어야** 닿았다 - 액션바 하나를 찾으려고 메뉴를 다섯 번 펼치는
--- 자리였다. 이 탭이 그걸 대신하면서 그쪽은 통째로 없어졌고, 지금 이 열거는 **여기 하나뿐**이다.
---
--- **이름·아이콘을 여기서 안 만든다.** `AddEntry`가 공용 해석기(`NameAndIconForAction`)에
--- 물어본다 - 명령의 이름 규칙(`BINDING_NAME_*`)과 아이콘이 이미 거기 있고, 목록과 걸어둔
--- 액션이 다른 이름으로 보이면 안 된다.

--- 머리글 순서. 게임이 주는 순서(`GetNumBindings`)는 액션바가 앞을 통째로 차지해서
--- 이동·인터페이스처럼 제일 자주 쓰는 것이 한참 뒤로 밀린다. 자주 쓰는 것부터 세운다.
--- 여기 없는 머리글은 뒤에 게임 순서대로 붙고, 비는 머리글은 그냥 안 나온다.
---
--- **전역 이름으로 적는다.** 값(현지화된 글자)을 테이블에 바로 넣으면 하나가 nil인 날
--- 배열이 거기서 잘린다 - `ipairs`가 멈춘다.
local PREFERRED_BINDING_HEADERS = {
	"BINDING_HEADER_MOVEMENT",
	"BINDING_HEADER_INTERFACE",
	"BINDING_HEADER_CHAT",
	"BINDING_HEADER_TARGETING",
	"BINDING_HEADER_RAID_TARGET",
	"BINDING_HEADER_VEHICLE",
	"BINDING_HEADER_CAMERA",
	"BINDING_HEADER_MISC",
};

--- 대상을 인자로 받는 우리 타입들. 머리글 하나에 유닛들이 붙는다.
local UNIT_ACTION_TYPES = {
	Constants.TARGET,
	Constants.FOCUS,
	Constants.TOGGLEMENU,
};

--- 우리 명령들. 게임 목록보다 **먼저** 버킷에 들어간다.
---
--- 대상 지정 셋만 이름을 우리가 준다. `NameAndIconForAction`이 내는 이름은 타입 이름
--- 하나뿐이라(유닛이 안 들어간다) 유닛 열세 줄이 전부 같은 글자가 된다 - 머리글이 타입을
--- 말하고 행이 대상을 말하는 것으로 갈랐다. 아이콘은 그 함수 것을 그대로 쓴다.
local function AddOwnCommands(Bucket)
	local DebindUI = DebindPrivate.DebindUI;
	local typeNames = DebindUI.BINDING_TYPE_NAMES;

	-- 대상 지정 / 주시 대상 지정 / 메뉴 열기.
	-- `UNIT_INFO[unit][type] == false`인 조합은 그 타입이 그 유닛을 못 받는다는 뜻이다
	-- (가리킨 프레임에 메뉴 열기 등) - 드롭다운과 같은 판정을 쓴다.
	for _, actionType in ipairs(UNIT_ACTION_TYPES) do
		local typeName = typeNames[actionType];
		local bucket = Bucket(typeName);
		local desc = LLL["TYPE_" .. strupper(actionType) .. "_DESC"];
		for _, unit in ipairs(DebindUI.SORTED_UNIT_LIST) do
			local unitInfo = DebindUI.UNIT_INFO[unit];
			if (unitInfo and unitInfo[actionType] ~= false) then
				bucket[#bucket + 1] = {
					type = actionType,
					name = unitInfo.name,
					-- 툴팁 제목만은 타입을 다시 붙인다. 행에는 대상만 적혀 있고
					-- (머리글이 타입을 말한다) 툴팁은 머리글에서 떨어져 뜨므로,
					-- 제목이 "주시 대상"이면 무엇을 하는 줄인지가 사라진다.
					tooltipTitle = format(LLL["BINDING_TITLE"], typeName, unitInfo.name),
					tooltipText = desc,
					props = { unit = unit },
				};
			end
		end
	end

	-- 공격대 표적. 게임의 `BINDING_HEADER_RAID_TARGET`과는 다른 물건이라 머리글을 따로 둔다 -
	-- 저쪽은 대상에 아이콘을 찍는 것이고 이건 바닥에 놓는 표식이다.
	local markerBucket = Bucket(typeNames[Constants.WORLDMARKER]);
	for i = 1, NUM_WORLD_RAID_MARKERS do
		markerBucket[#markerBucket + 1] = {
			type = Constants.WORLDMARKER,
			value = WORLD_RAID_MARKER_ORDER[i],
			tooltipText = LLL["TYPE_WORLDMARKER_DESC"],
		};
	end
end

local function BuildBindingCommands(entries)
	local seen = {};

	local order, buckets = {}, {};
	local function Bucket(group)
		local bucket = buckets[group];
		if (not bucket) then
			bucket = {};
			buckets[group] = bucket;
			order[#order + 1] = group;
		end
		return bucket;
	end

	AddOwnCommands(Bucket);

	for _, key in ipairs(PREFERRED_BINDING_HEADERS) do
		local group = _G[key];
		if (group) then
			Bucket(group);
		end
	end

	for bindingIndex = 1, GetNumBindings() do
		local action, cat = GetBinding(bindingIndex);

		-- `HEADER_*`는 명령이 아니라 목록 안의 구분선이다. 걸어봐야 아무 일도 안 난다.
		--
		-- `ADDONS`도 뺀다. 드롭다운과 같은 선택이다 - 저기 서 있는 것은 **다른 애드온이**
		-- 자기 창에서 쓰려고 올려둔 명령이라, 우리가 조건을 붙여 눌러주는 것이 그 애드온이
		-- 기대하는 동작이라는 보장이 없다. 그리고 우리 것도 저기 있다.
		if (action and strsub(action, 1, 6) ~= "HEADER" and cat ~= "ADDONS") then
			-- **이름이 없는 명령은 안 올린다.** `NameAndIconForAction`은 이름을 못 찾으면
			-- 명령 문자열을 그대로 돌려주므로(`"MOVEFORWARD"`) 가드가 안 걸린다 - 그 함수는
			-- 이미 걸어둔 액션을 **그리는** 쪽이라 그게 맞는 답이지만, 고르는 쪽에서는
			-- 대문자 덩어리가 적힌 줄을 만들 뿐이다.
			if (_G["BINDING_NAME_" .. action]) then
				local group = (cat and (_G[cat] or cat)) or BINDING_HEADER_OTHER;
				local bucket = Bucket(group);
				bucket[#bucket + 1] = {
					type = Constants.COMMAND,
					value = action,
				};
			end
		end
	end

	for _, group in ipairs(order) do
		local bucket = buckets[group];
		for i = 1, #bucket do
			local entry = bucket[i];
			entry.group = group;
			AddEntry(entries, seen, entry);
		end
	end
end

ActionCatalog.RegisterSource({
	key = "command",
	categories = {
		{
			key = "command",
			name = LLL["SPELL_PICKER_TAB_COMMAND"],
			-- 탭을 숨길 일이 없다. 게임의 단축키 목록은 캐릭터와 무관하게 언제나 있다.
			Build = BuildBindingCommands,
		},
	},
});

--------------------------------------------------------------------------------
-- 소스: 특수
--------------------------------------------------------------------------------

--- **이 애드온에만 있는 개념들.** 게임에 대응하는 물건이 없어서 여기 말고 갈 데가 없다 -
--- 지정 대상, 사용자 상태, 사용 안 함. 손으로 적은 열거이고 개수가 고정이다.
---
--- **"기타"가 아니다.** 이름이 정체성을 정하는 자리라 한 번 짚어둔다. 여기 안 들어가는
--- 것 둘이 그 경계를 보여준다:
---
---   주문서 밖의 주문   무작위 즐겨찾는 탈것 따위. **주문**이라 주문 탭의 "그 밖" 그룹으로
---                      간다(`AddExtraSpellEntries`). 자루가 필요하면 그쪽이 자루다
---   대상 지정 · 표적   게임에도 같은 성격의 단축키가 있어서(`BINDING_HEADER_TARGETING`,
---                      `BINDING_HEADER_RAID_TARGET`) 명령 탭으로 간다(`AddOwnCommands`)
---
--- 남는 셋은 전부 "레이어와 조건이 있는 애드온"이라야 뜻이 통하는 것들이다. 그래서 이
--- 탭은 항목이 네 줄뿐이어도 자기 자리를 갖는다. 여기 처음 온 사람이 **이 애드온이
--- 무엇을 더 할 수 있는지**를 보는 자리이기도 하다.
---
--- 스무 줄이었다. 열다섯이 스위치 셋 × 다섯이었고, 개수 제한이 풀리면서 그 자리가 한 줄이
--- 됐다(§6-C). **줄어든 것이 아니라 목록에서 빠진 것이다.** 개념은 그대로 한 줄로 서 있고,
--- 어느 스위치냐는 액션 편집 메뉴가 답한다.
---
--- 이름·아이콘은 전부 `NameAndIconForAction`이 낸다 - 여기 있는 타입이 그 함수가
--- `skipTypeName`으로 처리하는 것들이라 이름이 이미 완성돼 있다.
---
--- **툴팁 본문은 반드시 붙인다.** 다른 탭은 이름만 봐도 무엇인지 알지만(주문·탈것·장난감),
--- 여기 있는 것들은 이 애드온이 만든 개념이라 이름이 설명을 못 한다 - "지정 대상 1"을
--- 처음 보는 사람에게 그 글자는 아무 말도 안 한다. 설명은 타입별로 이미 있는 것을 쓴다
--- (`TYPE_*_DESC`) - 드롭다운이 쓰던 바로 그 문장이라 두 곳이 갈라지지 않는다.
local function BuildSpecialActions(entries)
	local seen = {};
	local typeNames = DebindPrivate.DebindUI.BINDING_TYPE_NAMES;

	-- 지정 대상 1·2.
	local setCustomGroup = typeNames[Constants.SETCUSTOM];
	for i = 1, 2 do
		AddEntry(entries, seen, {
			type = Constants.SETCUSTOM,
			value = i,
			group = setCustomGroup,
			tooltipText = LLL["TYPE_SETCUSTOM_DESC"],
		});
	end

	-- Setting a switch. **One row, and it names no switch** (§6-C of
	-- `devdocs/redesigning-custom-states.md`).
	--
	-- It was three rows per switch, one each for on, off and toggle, which came to fifteen of this
	-- tab's twenty while a profile could hold five. Lifting that count turned the number into
	-- "however many the reader has made", and this tab is a hand-written list whose whole job is
	-- showing somebody new **what the addon can do**; a screen of `$burst on / $burst off /
	-- $burst toggle` says that once and then repeats itself.
	--
	-- **What the row adds is an action with no target**, which starts red
	-- (`BINDING_ISSUE_SWITCH_NONE_SELECTED`) and does not bind until the reader picks a switch in
	-- its own menu (`CreateSetSwitchMenuItem`). That menu has to exist regardless: deleting a
	-- switch leaves actions pointing at a name nothing defines, and repointing one is where they
	-- get fixed. Once it exists the picker has nothing left to ask.
	--
	-- **Toggle, because it is the only one of the three that finishes on one key.** On and off are
	-- halves and take two keys to get anywhere, so a reader who presses the row they just made and
	-- sees something happen got the useful default.
	AddEntry(entries, seen, {
		type = Constants.SETSTATE_TOGGLE,
		group = typeNames[Constants.SETSTATE_TOGGLE],
		tooltipText = LLL["TYPE_SETSTATE_DESC"],
	});

	-- 사용 안 함. **혼자여도 머리글을 준다.**
	--
	-- 처음엔 안 줬다 - 머리글이 자기 이름을 두 번 말하게 되니까. 그런데 격자에는 그룹
	-- 경계를 그리는 것이 머리글뿐이라, 머리글이 없으면 앞 그룹(사용자 상태) 줄에 이어
	-- 붙어서 **그 그룹의 일부로 읽힌다.** 이름을 두 번 말하는 것보다 남의 그룹에 들어가
	-- 있는 것이 나쁘다.
	local unusedGroup = typeNames[Constants.UNUSED];
	AddEntry(entries, seen, {
		type = Constants.UNUSED,
		group = unusedGroup,
		tooltipText = LLL["TYPE_UNUSED_DESC"],
	});
end

--- 특수는 **맨 끝이다.** 등록 순서가 곧 탭 순서인데, 앞의 탭들이 "이미 가진 것"이라
--- 그쪽을 먼저 보게 하는 것이 맞다.
ActionCatalog.RegisterSource({
	key = "special",
	categories = {
		{
			key = "special",
			name = LLL["SPELL_PICKER_TAB_SPECIAL"],
			-- 캐릭터와 무관하게 언제나 있다. 우리가 만드는 것들이라 없어질 일이 없다.
			Build = BuildSpecialActions,
		},
	},
});
