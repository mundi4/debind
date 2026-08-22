local _, DebindPrivate = ...;

--- **What a layer is called, and the picture that stands for it.**
---
--- Five layers, and every one of them is named to the reader out of the words the client already
--- has: the character's name, the class, the specialization. Nothing here invents a word
--- (`writing-user-facing-text.md`), which is also why the labels are assembled from the tab labels
--- rather than written out again - the reader picked the layer with those.
---
--- **The tab coordinates go in and out of here, and nothing further.** Which tab is open is the
--- overview window's business and stays there (`GetLayerID`); a `layerID` is enough for everything
--- below, so the sharing panels and the switches tab can ask without a window being open at all
--- (`breaking-up-debindui.md`, "창보다 위로 올릴 것").
local LLL                    = DebindPrivate.L;
local Constants              = DebindPrivate.Constants;
local DebindUI               = DebindPrivate.DebindUI;
local GetSpellTabNameAndIcon = DebindPrivate.GetSpellTabNameAndIcon;

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

--- 레이어의 **짧은 이름.** "X over Y"에 들어가는 값이라 한두 낱말이어야 한다 -
--- `GetLayerLabel`은 "공유 / 일반" 꼴이라 문장에 못 넣는다.
---
--- 공유/일반을 Account라 부른다. "Shared"는 무엇과 공유하는지를 안 말하는데 여기서 답은
--- 계정이고, 짧기까지 하다.
local function GetLayerShortName(layerID)
	local tab, sideTab = GetLayerTabs(layerID);
	if (tab == 2) then
		return LLL[sideTab == 1 and "LAYER_SHORT_CHARACTER" or "LAYER_SHORT_CHARACTER_SPEC"];
	end
	if (sideTab == 1) then
		return LLL["LAYER_SHORT_ACCOUNT"];
	end
	return LLL[sideTab == 2 and "LAYER_SHORT_CLASS" or "LAYER_SHORT_SPEC"];
end

--- A payload's address as a `layerID`. `scope` is the `"general"` / `"class"` / `"character"` a
--- payload is keyed by (`ForEachPayloadLayer`).
---
--- **The numbers describe anybody's layers.** Which class they belong to is not in them, which is
--- why it is the second argument to the label rather than something the id has to carry -- and why
--- an address out of somebody else's string maps straight onto one.
---
--- Nil for a spec past the end. A hand-made string can name spec 9 and there is no eleventh layer
--- for it to be; the caller draws it or drops it, and this does not decide that.
local function GetLayerIDForAddress(scope, spec)
	spec = spec or 0;
	if (spec < 0 or spec > 4 or spec ~= floor(spec)) then
		return nil;
	end
	if (scope == "general") then
		return 1;
	elseif (scope == "class") then
		return spec == 0 and 2 or spec + 2;
	elseif (scope == "character") then
		return 7 + spec;
	end
	return nil;
end

--- `GetSideTabaLabel` for a **named** class: spec 0 is the class itself, above that its
--- specializations.
---
--- The side tab version reads `UnitClass("player")` and `GetSpecializationInfo`, which is right for
--- that row -- it is this character's layers -- and wrong for anything else. Nil for a spec number
--- past the end of a real class, which only a hand-made string carries: one naming a class this
--- client does not have never reaches a screen (`PayloadIsImpossible`).
local function GetSideLabelForClass(class, spec)
	if (spec == 0) then
		return LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class;
	end
	local classID = Constants.CLASS_IDS[class];
	if (not classID) then
		return nil;
	end
	local _, specName = C_SpecializationInfo.GetSpecializationInfoForClassID(classID, spec);
	return specName;
end

--- **The tab labels, reused verbatim.** They are already the class, specialization and character
--- names the reader picked the layer with, so a label built from them teaches nothing new.
---
--- **`class` says whose layer it is, and nil means this character's.** A `layerID` is a coordinate
--- that never mentions a class -- it says general, class, class-by-spec, character, character-by-
--- spec -- so the same eleven numbers describe anybody's layers and what was missing was only the
--- one value. Every call site that means "mine" passes nothing and reads as it did.
---
--- The one thing a foreign layer cannot have is a **name**: a string carries no character name on
--- purpose (`devdocs/building-export-import.md` 3절), so the character scope falls back to the bare
--- word. Naming it would print *this* reader's character over somebody else's layer, which is the
--- fault that made the bring dialog write a second set of labels of its own (`IMPORT_BRING_LINE_*`).
local function GetLayerLabel(layerID, class)
	local tab, sideTab = GetLayerTabs(layerID);
	local scope;

	if (tab ~= 2) then
		scope = LLL["SHARED_BINDINGS"];
	elseif (class) then
		scope = LLL["LAYER_SHORT_CHARACTER"];
	else
		scope = UnitName("player");
	end

	if (not class) then
		return format(LLL["ORDER_LAYER_LABEL"], scope, GetSideTabaLabel(sideTab));
	end

	-- Side tab 1 is "general" under either tab, and 2 is the class itself; 3 and up are that
	-- class's specializations, counted the way the side tab row counts them.
	local side;
	if (sideTab == 1) then
		side = LLL["GENERAL"];
	else
		side = GetSideLabelForClass(class, sideTab == 2 and 0 or sideTab - 2);
	end

	return format(LLL["ORDER_LAYER_LABEL"], scope, side or LLL["GENERAL"]);
end

--- Is this layer outside the world the live key map was built for?
---
--- Only a specialization layer can answer yes, and only while a different one is in play. **The
--- bin list can be sitting on one**: its side tabs reach every specialization's layer, not only
--- the current one, so what it draws there is not what the solver was answering about.
---
--- Nothing visibly depends on this yet. `IsUnreachableAction` is a lookup in a cache the solver
--- fills, and an off-specialization action was never in it, so the answer comes back empty either
--- way. That is an accident of how the verdict is stored rather than a decision, and the day it
--- becomes a computation this is what keeps the tooltip from starting to lie.
---
--- **Asked of the layer, not rebuilt from the tab coordinates.** The layer carries the number it
--- was loaded for (`Profile.lua`'s `LoadLayer`); a side tab is a drawing position that happens to
--- encode the same thing.
local function IsLayerOffWorld(layerID)
	local layer = layerID and DebindPrivate.GetProfileLayer(layerID);
	local spec = layer and layer.spec;
	return spec ~= nil and spec > 0 and spec ~= C_SpecializationInfo.GetSpecialization();
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

DebindUI.GetLayerTabs = GetLayerTabs;
DebindUI.GetTabLabel = GetTabLabel;
DebindUI.GetSideTabaLabel = GetSideTabaLabel;
DebindUI.GetLayerShortName = GetLayerShortName;
DebindUI.GetLayerLabel = GetLayerLabel;
DebindUI.GetLayerIDForAddress = GetLayerIDForAddress;
DebindUI.IsLayerOffWorld = IsLayerOffWorld;
DebindUI.GetSideTabIcon = GetSideTabIcon;
