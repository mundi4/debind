local _, DebindPrivate = ...;

local DEBUG              = DebindPrivate.DEBUG;
local InCombatLockdown   = InCombatLockdown;
local format             = format;

--- 플라이아웃을 **커서 위치에, 전투 중에도** 연다.
---
--- ## 왜 블리자드의 `SpellFlyout`을 안 쓰나
---
--- 세 겹으로 막혀 있다. 하나씩 다 막는 길이 없어서 통째로 우리 것을 만든다.
---
--- 1. `SpellFlyout`은 `SecureFrameTemplate` 상속이라 protected다(`SpellFlyout.xml`).
---    여는 경로가 우리 클릭에서 시작하면 그 안의 `SetParent`/`Show`가 전투 중 막힌다.
--- 2. `SpellFlyoutMixin:Toggle`의 첫 인자는 `FlyoutButtonMixin`이어야 한다
---    (`GetPopupDirection`, `TogglePopup`을 부른다). 우리 클릭 프레임은 맨몸
---    `SecureActionButtonTemplate`이라 nil 메서드 호출로 죽는다. 즉 `*type- = "flyout"`
---    속성은 쓸 수 있는 물건이 아니다.
--- 3. 팝업 안의 버튼은 보안 액션 버튼이 아니라 평범한 CheckButton이고, OnClick에서
---    `CastSpellByID`를 직접 부른다(`SpellFlyout.lua`). 우리가 세팅한 값을 그 핸들러가
---    읽는 순간 전투 중 시전이 죽는다.
---
--- 블리자드 것은 건드리지 않는다는 이 애드온의 원칙과도 같은 방향이다.
---
--- ## 대신 쓰는 것
---
--- 제한 환경(`RestrictedFrames.lua`)이 전투 중에도 허용하는 것들만으로 짠다:
---
---   `SetPoint(p, "$cursor", x, y)`   커서 앵커. relpoint를 화면 BOTTOMLEFT로 바꾸고
---                                    오프셋에 커서 좌표를 더한다
---   `RegisterAutoHide(ttl)`          커서가 벗어나면 스스로 닫힌다(`SecureHoverDriver.lua`)
---   `GetMousePosition()`             프레임 안에서의 커서 위치(0~1). 위로 펼칠지 아래로
---                                    펼칠지를 이걸로 가른다
---   `Show`/`Hide`/`ClearAllPoints`   나머지
---
--- ## 구조
---
--- **플라이아웃 하나당 홀더 하나.** 홀더를 공유하지 않는 이유는 하나다 - 제한 환경에는
--- **텍스처를 만지는 방법이 없다**(`HANDLE`에 `SetTexture`도 `SetAtlas`도 없다). 홀더를 돌려
--- 쓰면 전투 중에 아이콘을 갈아끼울 수가 없어서, 어느 플라이아웃을 열어도 남의 그림이 뜬다.
---
--- 같은 벽이 **배경 방향**에도 있을 뻔했다. 위로 펼칠지 아래로 펼칠지는 커서 위치에 달렸으니
--- 전투 중에 정해지는데, 블리자드 플라이아웃 배경은 방향마다 조각의 자리와 회전이 다르다
--- (`FlyoutPopupMixin:UpdateBackground`). 우리 배경은 **양끝이 같은 마감**이라 방향을 안 탄다
--- (`CreateBackground` 참고) - 하나만 지어두고 스니펫은 배경을 아예 안 만진다.
---
--- 결과: 전투 중 스니펫이 하는 일은 **어디에 놓을 것인가** 하나뿐이다.
---
--- 여는 손잡이(`opener`)를 홀더와 따로 두는 것은 `SECURE_ACTIONS.click`이 `delegate:Click()`을
--- 부르기 때문이다. 숨어 있는 프레임을 Click하는 것이 되는지 아닌지에 기대지 않으려고,
--- 손잡이는 **언제나 보이는** 1x1 빈 버튼으로 둔다.
---
--- ## 동시에 두 개가 열리면
---
--- 막지 않는다. 홀더가 갈려 있어서 서로를 모르는데, 먼저 열린 쪽은 커서가 이미 밖에 있으므로
--- `RegisterAutoHide`의 TTL이 지나면 알아서 닫힌다. 이걸 막으려면 홀더들이 서로를 아는
--- 구조가 필요하고, 그 값어치가 TTL 한 번보다 크지 않다.

--- 치수는 전부 블리자드 플라이아웃에서 가져온다. **눈대중으로 정하면 안 되는 값들이다** -
--- 배경이 아틀라스 조각 셋이라 폭이 어긋나면 테두리가 어긋난 채로 그려진다.
---
---   `BUTTON_SIZE`  `SmallActionButtonTemplate`의 크기(`ActionButtonTemplate.xml`).
---                  주문책·액션바 플라이아웃이 쓰는 그 버튼이다
---   `CROSS_SIZE`   배경 조각의 폭. `FlyoutPopupMixin:UpdateBackground`가 셋 모두에
---                  `popupCrossAxisSize`를 주는데, 그 값은 **플라이아웃을 여는 버튼의
---                  것**이다. 우리가 흉내내는 것은 액션바에서 열리는 플라이아웃이므로
---                  `ActionButtonTemplate`의 47이다.
---                  `FlyoutButtonTemplate` 자신의 38을 쓰면 좌우 여백이 4.5px씩 좁아진다 -
---                  실제로 그렇게 시작했고, 액션바 것과 나란히 놓으니 우리 것만 끼어 보였다.
---                  38을 쓰는 플라이아웃은 게임에 없다(주문책은 42, 액션바는 47).
---   `SPACING`      `SPELLFLYOUT_DEFAULT_SPACING`
---   `END_PADDING`  `SPELLFLYOUT_INITIAL_SPACING`/`_FINAL_SPACING`. 양끝이 같은 값이라
---                  방향이 뒤집혀도 버튼을 다시 배치할 필요가 없다
local BUTTON_SIZE        = 30;
local CROSS_SIZE         = 47;
local SPACING            = 4;
local END_PADDING        = 9;
local AUTOHIDE_SECONDS   = 0.75;

--- 커서를 **가장 가까운 버튼 한가운데**에 얹는다. 두 가지를 한꺼번에 푼다.
---
--- 하나는 손맛이다 - 키를 누른 자리에 첫 칸이 와야 손을 안 옮기고 바로 고른다.
---
--- 다른 하나가 더 중요하다. 커서가 홀더 **밖**에서 시작하면 `SecureHoverDriver`가 카운트다운을
--- 시작하지 않는다 - 그 코드는 "들어왔다가 나갔을 때"만 TTL을 건다(`UpdateTrackedHovers`).
--- 한 번도 안 들어오면 `false` 상태로 머물러서 **영원히 안 닫힌다.**
local CURSOR_INSET       = END_PADDING + BUTTON_SIZE / 2;

--- 커서가 화면 아래쪽 절반에 있으면 위로 펼친다. 그래도 **버튼 순서는 안 뒤집는다** -
--- 위아래가 바뀔 때마다 목록이 거꾸로 서면 같은 자리에 있던 주문이 매번 딴 데 있게 된다.
--- 바뀌는 것은 홀더의 앵커와 배경 두 가지뿐이다.
local FLIP_THRESHOLD     = 0.5;

--- 커서 위치를 물어보려고 두는 화면 크기 프레임.
---
--- `HANDLE:GetMousePosition()`은 **프레임 안에서의** 위치를 내므로 물어볼 프레임이 필요한데,
--- 홀더에 물으면 열기 전에는 커서가 그 안에 없어서 nil이 나온다. UIParent에 물어도 되겠지만
--- 그건 블리자드 프레임이고, 제한 환경이 요구하는 것은 "명시적으로 protected"라는 성질뿐이라
--- 우리 것을 하나 두는 편이 의존이 적다.
local Screen             = CreateFrame("Frame", DEBUG and "DebindFlyoutScreen" or nil, UIParent, "SecureFrameTemplate");
Screen:SetAllPoints(UIParent);
Screen:SetFrameStrata("DIALOG");

--- flyoutID -> { opener =, holder =, buttons =, numSlots = }
local Flyouts            = {};

--- 전투 중에 주문서가 바뀌었다. 전투가 끝나면 다시 짓는다.
local _dirty             = false;

--- 손잡이의 스니펫. 전투 중에 도는 유일한 코드다.
---
--- 배치도 아이콘도 여기서 안 만진다 - 전투 밖에서 이미 굳혀뒀다. 그래서 이 스니펫은
--- 플라이아웃 내용이 무엇이든 똑같고, 홀더마다 다른 것은 프레임 참조 하나뿐이다.
local OPENER_ONCLICK     = format([[
	local holder = self:GetFrameRef("holder")
	if (not holder) then
		return
	end

	-- 같은 키를 다시 누르면 닫는다. 홀더가 플라이아웃마다 따로라 이 검사만으로 충분하다.
	if (holder:IsShown()) then
		holder:Hide()
		return
	end

	-- 커서가 화면 아래쪽이면 위로 펼친다. nil이면(커서를 못 잡으면) 아래로 - 화면 위쪽이
	-- 잘리는 것보다 아래쪽이 잘리는 편이 덜 나쁘다. 위가 잘리면 첫 칸부터 안 보인다.
	local screen = self:GetFrameRef("screen")
	local growUp = false
	if (screen) then
		local _, my = screen:GetMousePosition()
		growUp = (my ~= nil) and (my < %f)
	end

	-- 배경은 안 만진다. 양끝 마감이 같아서 어느 쪽으로 펼치든 같은 그림이다.
	holder:ClearAllPoints()
	if (growUp) then
		holder:SetPoint("BOTTOM", "$cursor", 0, -%d)
	else
		holder:SetPoint("TOP", "$cursor", 0, %d)
	end
	holder:Show()

	-- 자식 버튼을 따로 등록(`AddToAutoHide`)하지 않는다. 버튼이 전부 홀더 **안에** 있어서
	-- 홀더 사각형 하나가 이미 그것들을 덮는다. 등록 순서 제약(등록 직후에만 추가 가능)에
	-- 얽힐 이유가 없다.
	holder:RegisterAutoHide(%f)
]], FLIP_THRESHOLD, CURSOR_INSET, CURSOR_INSET, AUTOHIDE_SECONDS);

--------------------------------------------------------------------------------
-- 아트
--------------------------------------------------------------------------------

--- 그룹 전체를 감싸는 배경·테두리. **블리자드 플라이아웃과 같은 아틀라스다.**
---
--- 조각이 왜 여럿인가: 플라이아웃은 칸 수에 따라 길이가 변하므로 통짜 그림을 못 쓴다. 양끝
--- 마감 둘과 그 사이를 세로로 타일링하는 가운데 하나로 나뉘어 있다. 자리와 회전각은
--- `FlyoutPopupMixin:UpdateBackground`(`Blizzard_Flyout/Flyout.lua`)에서 그대로 옮겼다.
---
--- **다만 양끝을 같은 조각으로 마감한다.** 블리자드는 두 끝이 다른 조각이다 -
--- `…-FlyoutBottom`은 마감이 아니라 **액션 버튼에 붙는 이음매**고, 그 끝은 액션 버튼이
--- 덮어서 안 보인다. 우리 플라이아웃은 커서에 떠 있어서 덮을 것이 없다. 그대로 가져왔더니
--- 한쪽 끝만 잘려 보였다 - 아래는 둥근 마감인데 위는 끊긴 이음매였다.
---
--- 그래서 **둘 다 `…-FlyoutButton`**(먼 쪽 마감)을 쓰고 아래쪽만 180도 돌린다. 덤으로 배경이
--- 위아래 대칭이 되어 **방향을 안 탄다** - 위로 펼치든 아래로 펼치든 같은 그림이라 하나만
--- 지으면 되고, 전투 중 스니펫이 배경을 고를 일이 없다(머리주석 참고).
local END_CAP_ATLAS = "UI-HUD-ActionBar-IconFrame-FlyoutButton";

local function CreateBackground(holder)
	local bg = CreateFrame("Frame", nil, holder);
	bg:SetAllPoints();
	-- 홀더와 같은 층에 둔다. 버튼은 아래에서 더 위층으로 올리므로 아이콘이 배경에 안 묻힌다.
	bg:SetFrameLevel(holder:GetFrameLevel());

	-- 회전각 0이 블리자드의 "위로 펼침"에서 **위쪽** 마감이 서는 각이다. 아래쪽은 그것을
	-- 뒤집은 것이고, 그 각도 블리자드의 "아래로 펼침"에서 그대로 온다.
	local topCap = bg:CreateTexture(nil, "BACKGROUND");
	topCap:SetAtlas(END_CAP_ATLAS, true);
	topCap:SetPoint("TOP");
	SetClampedTextureRotation(topCap, 0);

	local bottomCap = bg:CreateTexture(nil, "BACKGROUND");
	bottomCap:SetAtlas(END_CAP_ATLAS, true);
	bottomCap:SetPoint("BOTTOM");
	SetClampedTextureRotation(bottomCap, 180);

	local middle = bg:CreateTexture(nil, "BACKGROUND");
	middle:SetAtlas("!UI-HUD-ActionBar-IconFrame-FlyoutMid", true);
	-- 아틀라스 이름 앞의 `!`가 "세로로 타일링되는 조각"이라는 표시다. XML의
	-- `vertTile="true"`에 해당하고, `SetAtlas` **다음에** 켜야 안 지워진다.
	middle:SetVertTile(true);
	middle:SetPoint("TOP", topCap, "BOTTOM");
	middle:SetPoint("BOTTOM", bottomCap, "TOP");

	-- 폭만 준다. 높이는 아틀라스 것을 그대로 쓴다(가운데 조각은 위아래 앵커가 정한다) -
	-- 블리자드도 가로 방향일 때만 높이를 건드린다.
	topCap:SetWidth(CROSS_SIZE);
	middle:SetWidth(CROSS_SIZE);
	bottomCap:SetWidth(CROSS_SIZE);

	return bg;
end

--------------------------------------------------------------------------------
-- 슬롯 버튼
--------------------------------------------------------------------------------

--- 게임이 그리는 툴팁을 그대로 쓴다. `SpellFlyoutPopupButtonMixin:SetTooltip`을 옮긴 것이고,
--- **`UberTooltips` cvar을 보는 것까지 같다** - 그 옵션을 끈 사람은 액션바에서도 이름 한 줄만
--- 보고 있으므로, 우리만 전체 툴팁을 띄우면 그 설정이 여기서만 안 먹는 것이 된다.
---
--- 한 가지만 다르다. 블리자드는 액션바에 붙은 플라이아웃일 때 화면 기본 자리에 띄우는데
--- (`isActionBar` 갈래), 우리 것은 **커서에 떠 있는** 물건이라 버튼 옆에 붙이는 쪽을 쓴다.
--- 화면 구석에 띄우면 눈이 커서와 구석 사이를 오간다.
---
--- `UpdateTooltip`은 게임이 부른다 - `GameTooltip`의 OnUpdate가 주인의 이 필드를 본다.
--- 재사용 대기 시간처럼 떠 있는 동안 바뀌는 줄이 갱신되려면 있어야 한다.
local function SlotButton_SetTooltip(self)
	if (not self.spellID) then
		return;
	end

	if (GetCVarBool("UberTooltips")) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4);
		if (GameTooltip:SetSpellByID(self.spellID)) then
			self.UpdateTooltip = SlotButton_SetTooltip;
		else
			self.UpdateTooltip = nil;
		end
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(C_Spell.GetSpellName(self.spellID),
			HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
		self.UpdateTooltip = nil;
	end
end

local function SlotButton_OnLeave(self)
	self.UpdateTooltip = nil;
	GameTooltip:Hide();
end

--- 슬롯 버튼 하나.
---
--- **블리자드 액션 버튼 템플릿을 안 쓴다.** `SmallActionButtonTemplate`은
--- `ActionButtonTemplate` -> `BaseActionButtonMixin`·`FlyoutButtonTemplate`을 끌고 오고,
--- 그것들은 **액션 슬롯이 있다는 전제**로 돈다. 이 애드온의 존재 이유가 슬롯을 안 쓰는
--- 것이므로 그 전제를 들이면 안 된다(`.zzz/TODO.md`의 상시 항목이 같은 이야기다).
---
--- 대신 **아트만 같은 것을 쓴다.** 아틀라스 이름과 크기는 `ActionButtonTemplate.xml`과
--- `SmallActionButtonMixin_OnLoad`에서 그대로 가져왔다 - 액션바의 칸과 같은 그림이 나온다.
local function CreateSlotButton(holder, index)
	local button = CreateFrame("Button", DEBUG and (holder:GetName() .. "Button" .. index) or nil,
		holder, "SecureActionButtonTemplate");
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE);
	button:SetFrameLevel(holder:GetFrameLevel() + 5);
	button:RegisterForClicks("AnyUp");
	button:SetAttribute("type", "spell");

	-- **이걸 안 걸면 `ActionButtonUseKeyDown` cvar를 켠 사람에게는 시전이 안 나간다.**
	-- `SecureActionButton_OnClick`의 판정이
	-- `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)`인데
	-- (`SecureTemplates.lua:814`), 위만 등록했으므로 `down`이 늘 false다. cvar가 켜져 있으면
	-- 두 항이 모두 거짓이 되어 아무것도 안 하고 돌아선다. 그런데 아래 감싼 **뒷본문의
	-- `owner:Hide()`는 그대로 돌아서 창은 닫힌다** - 눌린 것처럼 보이고 주문은 안 나간다.
	-- cvar를 끈 사람에게는 멀쩡히 도니 "가끔 안 된다"로 보인다.
	--
	-- 아래·위를 다 등록하는 길로 고치면 안 된다. cvar가 꺼진 쪽이 그때 깨진다 - 마우스
	-- 다운에서 시전 없이 뒷본문이 창을 닫아버리고, 마우스 업은 사라진 버튼에 못 닿는다.
	--
	-- 블리자드는 진짜 마우스 클릭에 `isSecureAction = true`를 넘겨 이 경로를 끈다
	-- (`ActionButton.lua:1363`, 그쪽 주석이 "마우스 클릭은 키 누름처럼 다루지 않는다"고 적어둔
	-- 그 자리다). 템플릿의 OnClick은 인자가 고정이라 우리가 그 값을 넘길 수 없으므로, 같은
	-- 결론에 속성으로 간다. 이 버튼은 마우스로만 눌리는 팝업 칸이라 cvar를 따를 이유도 없다.
	button:SetAttribute("useOnKeyDown", false);

	local slotBackground = button:CreateTexture(nil, "BACKGROUND");
	slotBackground:SetAtlas("UI-HUD-ActionBar-IconFrame-Background");
	slotBackground:SetAllPoints();

	button.icon = button:CreateTexture(nil, "BACKGROUND", nil, 1);
	button.icon:SetAllPoints();

	-- 테두리·눌림·마우스오버. 크기가 버튼보다 큰 것은 아트가 원래 칸 밖으로 조금 나오는
	-- 물건이기 때문이다(`SmallActionButtonMixin:UpdateButtonArt`가 35, 하이라이트가 31.6x30.9).
	local normal = button:CreateTexture(nil, "BORDER");
	normal:SetAtlas("UI-HUD-ActionBar-IconFrame");
	normal:SetSize(35, 35);
	normal:SetPoint("CENTER");
	button:SetNormalTexture(normal);

	local pushed = button:CreateTexture(nil, "BORDER");
	pushed:SetAtlas("UI-HUD-ActionBar-IconFrame-Down");
	pushed:SetSize(35, 35);
	pushed:SetPoint("CENTER");
	button:SetPushedTexture(pushed);

	local highlight = button:CreateTexture(nil, "HIGHLIGHT");
	highlight:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover");
	highlight:SetSize(31.6, 30.9);
	highlight:SetPoint("CENTER");
	button:SetHighlightTexture(highlight);

	button:SetScript("OnEnter", SlotButton_SetTooltip);
	button:SetScript("OnLeave", SlotButton_OnLeave);

	-- 고르고 나면 닫는다.
	--
	-- **앞 본문이 nil이 아닌 두 번째 값을 돌려줘야 뒷 본문이 돈다.** `Wrapped_Click`이
	-- `message ~= nil`일 때만 post를 부른다(`SecureHandlers.lua`). 첫 번째 값은 버튼을
	-- 바꿔치기하는 자리라 nil로 둔다 - `false`를 주면 클릭 자체가 취소된다.
	--
	-- 닫는 것은 **뒷 본문**이어야 한다. 앞에서 숨기면 시전이 나가기 전에 사라진다.
	SecureHandlerWrapScript(button, "OnClick", holder,
		[[ return nil, "close" ]],
		[[ owner:Hide() ]]);

	return button;
end

--------------------------------------------------------------------------------
-- 짓기
--------------------------------------------------------------------------------

--- The rows `RebuildFlyout` reads, refilled on every call.
local _slots = {};

--- Fills one holder from the spellbook as it stands now. **Out of combat only.**
---
--- Buttons are reused: a frame made on every tamed beast would pile up over a session. Slots that
--- went away hide theirs.
---
--- **What has not changed is not written again.** Every flyout this character knows has an entry
--- once an action button action reaches a slot (`GetBookFlyoutOpeners`), and every one is rebuilt
--- on each `SPELLS_CHANGED`, which fires often; nearly all of those change nothing.
---
--- **Answers true when whether it opens anything flipped**, since a key has to be bound again at
--- that edge; `RebuildAll` does that.
local function RebuildFlyout(entry, flyoutID)
	local slots = DebindPrivate.GetFlyoutCastableSlots(flyoutID, _slots);
	local holder, buttons = entry.holder, entry.buttons;
	local numSlots = #slots;
	local wasUsable = entry.numSlots > 0;

	for i = 1, numSlots do
		local slot = slots[i];
		local button = buttons[i];
		if (not button) then
			button = CreateSlotButton(holder, i);
			buttons[i] = button;
			if (i == 1) then
				button:SetPoint("TOP", holder, "TOP", 0, -END_PADDING);
			else
				button:SetPoint("TOP", buttons[i - 1], "BOTTOM", 0, -SPACING);
			end
		end

		-- Set by name. Some spells share a name under different ids, and set by id one of them
		-- does not go out in another specialization. The same rule as the `Constants.SPELL`
		-- branch in `ButtonAttributes.lua`, and `GetFlyoutCastableSlots` is the one place the value
		-- is made.
		if (button.cast ~= slot.cast) then
			button:SetAttribute("spell", slot.cast);
			button.cast = slot.cast;
		end
		button.spellID = slot.spellID;
		if (button.iconID ~= slot.icon) then
			button.icon:SetTexture(slot.icon);
			button.iconID = slot.icon;
		end
		button:Show();
	end

	for i = numSlots + 1, #buttons do
		local button = buttons[i];
		if (button.cast ~= nil) then
			button:Hide();
			button:SetAttribute("spell", nil);
			button.cast = nil;
			button.spellID = nil;
		end
	end

	if (numSlots > 0 and numSlots ~= entry.numSlots) then
		holder:SetSize(
			CROSS_SIZE,
			numSlots * BUTTON_SIZE + (numSlots - 1) * SPACING + END_PADDING * 2);
	end
	entry.numSlots = numSlots;

	-- 슬롯이 하나도 없으면 손잡이를 눌러도 빈 상자만 뜬다. 프레임 참조를 끊어서
	-- 스니펫이 첫 줄에서 되돌아가게 한다 - 목록에 있는데 눌러도 아무 일이 없는 것보다
	-- 아무것도 안 뜨는 편이 낫다.
	--
	-- 끊는 쪽은 속성을 직접 지운다. `SecureHandlerSetFrameRef`는 nil을 받으면
	-- `Invalid reference frame`으로 죽는다(`SecureHandlers.lua:715`).
	if (numSlots > 0 and not wasUsable) then
		SecureHandlerSetFrameRef(entry.opener, "holder", holder);
	elseif (numSlots == 0 and wasUsable) then
		entry.opener:SetAttribute("frameref-holder", nil);
	end

	-- 릴리스에서 `log`는 빈 함수지만 **인자는 그 전에 만들어진다.** 감싸지 않으면 실사용자도
	-- 플라이아웃을 훑을 때마다 버릴 문자열을 짓는다. 이 파일의 다른 로그와 `UpdateBindings`가
	-- 전부 이 모양이다.
	if (DEBUG) then
		DebindPrivate.log(format("[flyout] %d -> %d slots", flyoutID, numSlots));
	end

	return wasUsable ~= (numSlots > 0);
end

local function CreateFlyout(flyoutID)
	local name = DEBUG and ("DebindFlyout" .. flyoutID) or nil;

	local holder = CreateFrame("Frame", name, Screen, "SecureHandlerBaseTemplate");
	holder:SetFrameStrata("DIALOG");
	holder:SetSize(CROSS_SIZE, BUTTON_SIZE + END_PADDING * 2);
	holder:EnableMouse(true);
	holder:Hide();

	-- 배경 하나. 방향을 안 타므로 스니펫에 넘길 것이 없다.
	CreateBackground(holder);

	-- 손잡이. **보인 채로 둔다** - 숨은 프레임에 `Click()`이 먹는지에 기대지 않으려는 것이다.
	-- 크기가 1x1이고 텍스처가 없으므로 화면에는 아무것도 안 남고, 마우스를 끄므로 진짜 클릭을
	-- 가로채지도 않는다.
	local opener = CreateFrame("Button", name and (name .. "Opener") or nil, Screen,
		"SecureHandlerClickTemplate");
	opener:SetSize(1, 1);
	opener:SetPoint("BOTTOMLEFT");
	opener:EnableMouse(false);
	opener:RegisterForClicks("AnyUp", "AnyDown");
	opener:SetAttribute("_onclick", OPENER_ONCLICK);
	SecureHandlerSetFrameRef(opener, "screen", Screen);

	local entry = { opener = opener, holder = holder, buttons = {}, numSlots = 0 };
	Flyouts[flyoutID] = entry;
	RebuildFlyout(entry, flyoutID);
	return entry;
end

--- The handle frame that opens this flyout, which `SetBindingAttributes` puts on `*clickbutton-`.
--- Nil with no slot at all, and the caller then sends the action out opening nothing (`Inert`).
---
--- **전투 중에는 새로 만들지 않는다.** 부르는 쪽(`DebindPrivate.UpdateBindings`)이 전투
--- 중에는 첫 줄에서 통째로 되돌아가므로 이 갈래를 밟을 일은 없지만, 밟으면 프레임 생성이
--- 실패하는 게 아니라 **에러**가 나는 자리라 명시해둔다.
function DebindPrivate.GetFlyoutOpener(flyoutID)
	local entry = Flyouts[flyoutID];
	if (not entry) then
		if (InCombatLockdown()) then
			return nil;
		end
		entry = CreateFlyout(flyoutID);
	end

	return entry.numSlots > 0 and entry.opener or nil;
end

--- 주문서가 바뀌었다. 걸어둔 플라이아웃들을 다시 짓는다.
---
--- 전부 다시 짓는 이유는 어느 플라이아웃이 바뀌었는지 이벤트가 안 알려주기 때문이다.
--- 걸어둔 개수는 많아야 몇 개고, 하나 짓는 비용은 `GetFlyoutSlotInfo` 몇 번이다.
---
--- **칸이 0을 넘나들면 바인딩을 다시 건다.** 여기서 프레임을 고쳐놔도 키는 안 돌아온다 -
--- 키에 무엇을 걸지는 `SetBindingAttributes`가 정하고, 그건 `UpdateBindings`가 돌 때만
--- 다시 물어보기 때문이다. `Events.lua`가 듣는 것은 특성·바인딩·cvar 쪽이라 주문서 변화가
--- 거기 안 닿는다.
---
--- 그래서 야수를 길들이면 이런 일이 났다: 팝업은 되살아나는데 **키는 다음 특성 변경이나
--- `/reload`까지 죽어 있다.** 반대 방향(마지막 야수를 놓아준다)도 같다 - 걸려 있던 키가
--- 안 나가는 채로 남는다.
local function RebuildAll()
	if (InCombatLockdown()) then
		_dirty = true;
		return;
	end

	_dirty = false;

	local usabilityChanged = false;
	for flyoutID, entry in pairs(Flyouts) do
		-- `or` 순서를 뒤집으면 안 된다. 한 번 참이 나온 뒤로 나머지가 안 돌게 된다.
		usabilityChanged = RebuildFlyout(entry, flyoutID) or usabilityChanged;
	end

	if (usabilityChanged) then
		DebindPrivate.QueueUpdateBindings();
	end
end

local EventFrame = CreateFrame("Frame");
EventFrame:RegisterEvent("SPELLS_CHANGED");
EventFrame:RegisterEvent("SPELL_FLYOUT_UPDATE");
EventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED");
-- 야수 소환은 마구간이 바뀌면 칸이 늘고 준다. 빈 칸은 `GetFlyoutCastableSlots`가 걸러내므로
-- 이 이벤트를 안 받으면 길들인 야수가 목록에 안 나타난다.
EventFrame:RegisterEvent("PET_STABLE_UPDATE");
EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
EventFrame:SetScript("OnEvent", function(_, event)
	if (event == "PLAYER_REGEN_ENABLED") then
		if (_dirty) then
			RebuildAll();
		end
		return;
	end
	RebuildAll();
end);

local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;
local GetSpellCastName      = DebindPrivate.GetSpellCastName;

--- 야수 소환 플라이아웃의 **빈 칸**인가.
---
--- 야수 소환은 슬롯 수가 마구간 칸 수로 고정돼 있어서, 그 자리에 야수가 없어도 슬롯은
--- `isKnown`으로 남는다. 그래서 `isKnown` 검사만으로는 안 걸러지고, 아무것도 안 나가는
--- 칸이 목록과 팝업에 그대로 선다. 블리자드 플라이아웃도 같은 검사를 한다
--- (`SpellFlyout.lua`가 `GetCallPetSpellInfo`로 `visible`을 끈다).
---
--- **이 검사가 한 군데인 것이 요점이다.** 처음엔 시전 쪽(`GetFlyoutCastableSlots`)에만
--- 있었고, 선택 창은 안 걸러서 **팝업에는 안 뜨는 칸이 목록에는 뜨는** 상태가 됐다.
--- 지금은 `ActionCatalog.lua`의 `AddFlyoutEntries`도 이것을 부른다.
function DebindPrivate.IsEmptyCallPetSlot(spellID)
	local petIndex, petName = GetCallPetSpellInfo(spellID);
	return petIndex ~= nil and (not petName or petName == "");
end

local IsEmptyCallPetSlot = DebindPrivate.IsEmptyCallPetSlot;

--- 플라이아웃 **자기 아이콘**. flyoutID -> iconID.
---
--- 게임에는 플라이아웃 자기 아이콘이 있다 - 주문책이 "야수 소환" 칸에 그리는 그 그림이고,
--- 첫 슬롯의 것이 아니다. 문제는 그걸 내주는 API가 `C_SpellBook.GetSpellBookItemTexture`
--- 하나뿐이고 **flyoutID로는 못 묻는다**는 것이다 - 주문서 슬롯 번호가 있어야 한다
--- (`GetFlyoutInfo`가 내는 것은 이름·설명·슬롯 수·습득 여부뿐이다). 그래서 주문서를 한 번
--- 훑어 표를 만들어 둔다.
---
--- **찾은 값은 안 지운다.** 아이콘은 플라이아웃 정의에 박힌 것이라 특성이나 야수에 따라
--- 안 바뀐다. 다시 훑는 것은 **못 찾은 것** 때문이다 - 특성을 바꾸면 없던 플라이아웃이
--- 주문서에 생기고, 그 전까지는 물어볼 슬롯 자체가 없었다.
---
--- `shouldHide` 스킬라인도 훑는다. 카탈로그와 달리 여기서 찾는 것은 목록에 세울 줄이 아니라
--- 그림 한 장이고, 창에 안 보이는 줄에 있는 플라이아웃도 걸어둘 수는 있다.
local FlyoutIcons = {};
local flyoutIconsSwept = false;

local function ForEachBookFlyoutInBank(first, last, bank, fn, arg)
	for slotIndex = first, last do
		local info = C_SpellBook.GetSpellBookItemInfo(slotIndex, bank);
		if (info and info.itemType == Enum.SpellBookItemType.Flyout) then
			fn(arg, info.actionID, slotIndex, bank);
		end
	end
end

local function ForEachProfessionFlyout(professionIndex, fn, arg)
	if (professionIndex) then
		local _, _, _, _, numSpells, spellOffset = GetProfessionInfo(professionIndex);
		ForEachBookFlyoutInBank(spellOffset + 1, spellOffset + (numSpells or 0),
			Enum.SpellBookSpellBank.Player, fn, arg);
	end
end

--- `fn(arg, flyoutID, slotIndex, bank)` for every flyout in the spellbook, the pet's and the
--- professions' included. **The professions' slots sit past every skill line**, reached through
--- `GetProfessionInfo`'s offset (`ActionCatalog.lua`'s `AddProfessionSpells`), and a flyout there
--- can be put on a bar like any other.
local function ForEachBookFlyout(fn, arg)
	local playerBank = Enum.SpellBookSpellBank.Player;
	local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0;
	for skillLineIndex = 1, numSkillLines do
		local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex);
		if (skillLineInfo) then
			ForEachBookFlyoutInBank(skillLineInfo.itemIndexOffset + 1,
				skillLineInfo.itemIndexOffset + skillLineInfo.numSpellBookItems, playerBank, fn, arg);
		end
	end

	local numPetSpells = C_SpellBook.HasPetSpells();
	if (numPetSpells) then
		ForEachBookFlyoutInBank(1, numPetSpells, Enum.SpellBookSpellBank.Pet, fn, arg);
	end

	local prof1, prof2, archaeology, fishing, cooking = GetProfessions();
	ForEachProfessionFlyout(prof1, fn, arg);
	ForEachProfessionFlyout(prof2, fn, arg);
	ForEachProfessionFlyout(archaeology, fn, arg);
	ForEachProfessionFlyout(fishing, fn, arg);
	ForEachProfessionFlyout(cooking, fn, arg);
end

local function NoteFlyoutIcon(_, flyoutID, slotIndex, bank)
	local icon = C_SpellBook.GetSpellBookItemTexture(slotIndex, bank);
	if (icon) then
		FlyoutIcons[flyoutID] = icon;
	end
end

local function SweepFlyoutIcons()
	ForEachBookFlyout(NoteFlyoutIcon);
end

--- **Only a flyout this character knows**, the one `SpellFlyout:Toggle` would open: the others
--- would get frames that never open anything.
local function NoteBookFlyoutOpener(out, flyoutID)
	local _, _, _, isKnown = DebindPrivate.Client.FlyoutInfo(flyoutID);
	if (isKnown) then
		out[flyoutID] = DebindPrivate.GetFlyoutOpener(flyoutID);
	end
end

--- `flyoutID -> opener` for every flyout in the spellbook that opens anything, into `out`. **Out
--- of combat only**, since it makes the openers it has not made yet.
---
--- **The book is walked again on every call, not kept the way `FlyoutIcons` is.** A specialization
--- change rebuilds on the spot (`Events.ACTIVE_PLAYER_SPECIALIZATION_CHANGED`), and nothing orders
--- that ahead of or behind `SPELLS_CHANGED`: a list cleared by that event could still be the old
--- specialization's at that rebuild, leaving the new one's flyouts with no opener until the next. A
--- stale icon is a wrong picture; a stale list is a key that does nothing.
function DebindPrivate.GetBookFlyoutOpeners(out)
	wipe(out);
	ForEachBookFlyout(NoteBookFlyoutOpener, out);
	return out;
end

local function GetFlyoutIcon(flyoutID)
	local icon = FlyoutIcons[flyoutID];
	if (icon) then
		return icon;
	end

	-- 한 번 훑었으면 다시 안 훑는다. 없는 flyoutID를 그릴 때마다 주문서를 통째로 도는 일을
	-- 막는 것이고, 표를 다시 열어주는 것은 아래 `SPELLS_CHANGED`뿐이다.
	if (flyoutIconsSwept) then
		return nil;
	end

	SweepFlyoutIcons();
	flyoutIconsSwept = true;
	return FlyoutIcons[flyoutID];
end

local FlyoutIconEventFrame = CreateFrame("Frame");
FlyoutIconEventFrame:RegisterEvent("SPELLS_CHANGED");
FlyoutIconEventFrame:SetScript("OnEvent", function()
	flyoutIconsSwept = false;
end);

--- 플라이아웃의 이름과 아이콘.
---
--- 아이콘은 위의 표에서 온다 - 주문책이 그리는 **그 플라이아웃의 그림**이다. 표에 없을 때만
--- 첫 번째 쓸 수 있는 슬롯의 주문에서 빌려온다. 그 자리는 주문서에 아직 안 뜬 플라이아웃
--- (특성 변경 직후 등)을 위한 것이지 기본값이 아니다.
---
--- **아이콘은 저장하지 않는다.** 이 애드온의 규약대로(`ActionCatalog.lua` 머리주석) 저장은
--- flyoutID 하나뿐이고 그림은 그릴 때마다 여기서 다시 푼다.
---
--- `isOffSpec`은 **오프스펙 플라이아웃을 통째로 안 배운 상태**를 위한 예외다. 그때는 슬롯의
--- `isKnown`이 전부 거짓이라 그 검사만으로는 쓸 수 있는 슬롯을 하나도 못 고른다.
---
--- 네 번째 값 `hasUsableSlot`은 **열면 뭐라도 나오는가**이다. 야수가 하나도 없는 사냥꾼의
--- 야수 소환이 거짓이고, 부르는 쪽(`AddFlyoutEntry`)이 그 줄을 아예 안 올린다 - 열어도 빈
--- 상자만 뜨는 것을 목록에 세우지 않는 것이 요점이다. 한때 이 신호가 "아이콘이 안 나온다"였다.
--- 아이콘을 첫 슬롯에서 빌려오던 시절에는 같은 말이었지만, 지금은 플라이아웃 자기 아이콘이
--- 빈 칸에도 나오므로 갈라놔야 한다.
function DebindPrivate.GetFlyoutNameAndIcon(flyoutID, isOffSpec)
	local name, _, numSlots, isKnown = DebindPrivate.Client.FlyoutInfo(flyoutID);
	if (not name or not numSlots or numSlots == 0) then
		return nil, nil, nil, false;
	end

	local hasUsableSlot = false;
	local fallbackIcon;
	for slot = 1, numSlots do
		local spellID, overrideSpellID, isKnownSlot = GetFlyoutSlotInfo(flyoutID, slot);
		if (spellID and (isKnownSlot or isOffSpec) and not IsEmptyCallPetSlot(spellID)) then
			hasUsableSlot = true;
			local _, slotIcon = GetSpellNameAndIconID(overrideSpellID or spellID);
			if (slotIcon) then
				fallbackIcon = slotIcon;
				break;
			end
		end
	end

	return name, GetFlyoutIcon(flyoutID) or fallbackIcon, isKnown, hasUsableSlot;
end

--- The slots of a flyout that can actually fire, with the value to cast each by.
---
--- **Off-spec slots are refused here**, unlike the list that draws them. These go on a button, and
--- a spell the reader has not learned does nothing when pressed.
---
--- **Two icons and they are not the same question.** `icon` comes from the slot's own spell so a
--- slot always has one, `displayIcon` from whatever is overriding it right now, which is the picture
--- the spellbook draws. Casting still goes by the base spell's name.
---
--- **`out`'s rows are refilled in place**, so a caller passing one keeps no row across calls.
function DebindPrivate.GetFlyoutCastableSlots(flyoutID, out)
	out = out or {};
	local count = 0;

	local _, _, numSlots = DebindPrivate.Client.FlyoutInfo(flyoutID);
	for slot = 1, numSlots or 0 do
		local spellID, overrideSpellID, isKnown, spellName = GetFlyoutSlotInfo(flyoutID, slot);
		if (spellID and isKnown and not IsEmptyCallPetSlot(spellID)) then
			local castName = GetSpellCastName(spellID);
			local _, icon = GetSpellNameAndIconID(spellID);

			local _, displayIcon = GetSpellNameAndIconID(overrideSpellID or spellID);
			count = count + 1;
			local row = out[count] or {};
			out[count] = row;
			row.spellID = spellID;
			row.cast = castName or spellID;
			row.name = spellName or castName;
			row.icon = displayIcon or icon;
		end
	end

	for i = #out, count + 1, -1 do
		out[i] = nil;
	end
	return out;
end
