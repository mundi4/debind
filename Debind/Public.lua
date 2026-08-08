local _, DebindPrivate = ...
local BindingDriver      = DebindPrivate.BindingDriver;
local Constants          = DebindPrivate.Constants;
local LLL                = DebindPrivate.L;

DebindPublic           = {};
DebindPublic.header    = BindingDriver;
DebindPublic.Units     = setmetatable({}, {
	__index = DebindPrivate.Units,
	__newindex = function() end,
});

function DebindPublic:SetCustomTarget(alias, value)
	if (InCombatLockdown()) then
		DebindPrivate.DisplayMessage(LLL["ERROR_MESSAGE_CANNOT_SET_CUSTOM_TARGET_IN_COMBAT"], 1, 0, 0);
		return;
	end

	if (alias == 1 or alias == 2) then
		alias = "custom" .. alias;
	end

	if (alias == "custom1" or alias == "custom2") then
		DebindPrivate.UnitWatch:SetAttribute(alias, value);
	end
end

function DebindPublic:RegisterFrame(button, ...)
	DebindPrivate.RegisterFrame(button, ...);
end

function DebindPublic:UnregisterFrame(button)
	DebindPrivate.UnregisterFrame(button);
end

function DebindPublic:UpdateRegisteredClicks(button)
	DebindPrivate.UpdateRegisteredClicks(button);
end

local VALID_EVENTNAMES = {
	UNIT_CHANGED = true,
	STATE_CHANGED = true,
};

function DebindPublic.RegisterCallback(target, eventname, method, ...)
	if (not VALID_EVENTNAMES[eventname]) then
		return;
	end
	if (DebindPublic == target) then
		error("RegisterCallback(): use your own 'self'", 2);
	end
	DebindPrivate.RegisterCallback(target, eventname, method, ...);
end

function DebindPublic.UnregisterCallback(target, eventname)
	if (not VALID_EVENTNAMES[eventname]) then
		return;
	end
	if (DebindPublic == target) then
		error("UnregisterCallback(): use your own 'self'", 2);
	end
	DebindPrivate.UnregisterCallback(target, eventname);
end

function DebindPublic:ToggleUI()
	if (DebindFrame:IsShown()) then
		DebindFrame:Hide();
		return
	end
	if (InCombatLockdown()) then
		DebindPrivate.DisplayMessage(LLL["CANNOT_OPEN_IN_COMBAT"], 1, 0, 0)
		return
	end
	-- 게임 메뉴 위에는 얹히지 않는다.
	--
	-- (예전 주석은 "게임메뉴가 열릴 때 열린 창을 전부 닫는다"고 했는데 반대다.
	-- ToggleGameMenu는 ESC 핸들러를 먼저 돌리고 **아무도 ESC를 가져가지 않았을 때만**
	-- 메뉴를 띄운다 - 우리 창이 떠 있으면 그 ESC가 우리 창을 닫고 메뉴는 안 뜬다.
	-- 그래서 이 분기가 실제로 걸리는 건 컴파트먼트 버튼 같은 다른 입구뿐이다.)
	--
	-- 조용히 돌아서지 않는다. 위의 전투 분기와 같다 - 버튼을 눌렀는데 아무 일도 안
	-- 일어나면 그건 고장으로 읽힌다.
	if (GameMenuFrame:IsShown()) then
		DebindPrivate.DisplayMessage(LLL["CANNOT_OPEN_WITH_GAME_MENU"], 1, 0, 0)
		return
	end
	DebindFrame:Show();
end

if (not DebindPrivate.CliqueDetected) then
	local prev = _G.DebindPrivate;
	_G.DebindPrivate = DebindPrivate;
	C_AddOns.LoadAddOn("DebindCliqueFake");
	_G.DebindPrivate = prev;
end

--- 창을 연다. **이미 열려 있으면 닫지 않는다** - 오버뷰를 보려고 부른 것이라 토글로
--- 받으면 원하는 것의 반대가 나온다.
---
--- 옮길 탭은 이제 없다. 창의 왼쪽 열이 늘 그 오버뷰라 여는 것으로 끝난다.
local function ShowOverview()
	if (not DebindFrame:IsShown()) then
		DebindPublic:ToggleUI();
	end
end

SlashCmdList["DEBIND"] = function(msg)
	msg = strlower(msg);
	-- 오버뷰가 별도 창이던 시절의 명령어. 창도 탭도 없어졌지만 손가락이 기억하는 것을
	-- 뺏지 않는다 - 창을 열면 그 오버뷰가 왼쪽 열에 있다.
	if (msg == "overview") then
		ShowOverview();
		return;
	end

	local chunks = {};
	for s in msg:gmatch("%S+") do
		tinsert(chunks, s)
	end

	if (chunks[1] == "custom1" or chunks[1] == "custom2") then
		DebindPublic:SetCustomTarget(chunks[1], chunks[2]);
		return;
	end

	DebindPublic:ToggleUI();
end

--- **좌·우클릭이 같은 일을 한다.** 오른쪽은 원래 바인딩 오버뷰를 여는 자리였는데, 그 오버뷰가
--- 창의 왼쪽 열이 되면서 갈 데가 없어졌다.
---
--- 한때 여기서 우클릭만 `ShowOverview`(열려 있으면 아무것도 안 함)로 갈랐다. 그러면 창이 열린
--- 상태에서 우클릭이 **아무 반응도 없는 클릭**이 된다 - `ToggleUI`가 거절하는 두 자리에서
--- 굳이 메시지를 찍는 이유가 "눌렀는데 아무 일도 안 일어나면 고장으로 읽힌다"인데, 그 규칙을
--- 정작 이 버튼이 어겼다. 구분이 사라졌으면 구분하는 척을 그만두는 게 맞다.
---
--- `ShowOverview`는 남는다. `/deb overview`는 **보여달라고 친 것**이라 닫으면 안 된다.
function Debind_CompartmentFunc(name, mouseButton, btn)
	DebindPublic:ToggleUI();
end

--- 구획 항목에 마우스를 올렸을 때. 좌·우클릭이 서로 다른 데로 가는데, 그걸 말해줄 자리가
--- 여기밖에 없다 - 메뉴 항목은 이름 한 줄이 전부라 우클릭은 우연히 눌러야만 발견된다.
--- 인자는 블리자드가 준다 (Blizzard_Minimap/AddonCompartment.lua의 funcOnEnter).
function Debind_CompartmentOnEnter(name, btn)
	GameTooltip:SetOwner(btn, "ANCHOR_LEFT");
	GameTooltip_SetTitle(GameTooltip, C_AddOns.GetAddOnMetadata(name, "Title") or name);
	GameTooltip_AddInstructionLine(GameTooltip, LLL["COMPARTMENT_TOOLTIP_LEFT_CLICK"]);
	GameTooltip:Show();
end

function Debind_CompartmentOnLeave()
	GameTooltip:Hide();
end

SLASH_DEBIND1 = "/debind";
SLASH_DEBIND2 = "/deb";
--- The old name. Fingers remember it; taking it away buys nothing.
SLASH_DEBIND3 = "/debounce";

_G.DebindPublic = setmetatable(DebindPublic, { __newindex = function() end });

--- Compatibility alias for the pre-rename name.
---
--- This is the only global other addons and user macros were ever told to call, so renaming it
--- without an alias would silently break code we cannot see or fix. Same table, not a copy - a
--- caller reaching either name gets the same object and the same `__newindex` guard.
---
--- Keep it. There is no version at which dropping it becomes safe, and it costs one line.
_G.DebouncePublic = _G.DebindPublic;

if (_G.Grid2) then
	local Grid2 = _G.Grid2;
	local UnitIsUnit = UnitIsUnit;
	local UnitGUID = UnitGUID;
	local roster_units = Grid2.roster_units;

	local aliases = { "custom1", "custom2", "hover", "tank", "healer", "maintank", "mainassist" };
	for i = 1, #aliases do
		local theAlias = aliases[i];
		-- **Stays `debounce_` after the rename.** Grid2 persists this key in its own saved
		-- variables to remember which statuses a user attached to which indicators. Renaming it
		-- would not migrate anything - it would just make those statuses vanish from layouts we
		-- have no way to reach or repair. Same reasoning as the `DebouncePublic` alias below.
		local statusKey = "debounce_" .. theAlias;
		local Status = Grid2.statusPrototype:new(statusKey);

		local guiTarget, curTarget, oldTarget
		local function UpdateTarget()
			local unit = DebindPublic.Units[theAlias];
			if (unit) then
				guiTarget = UnitGUID(unit);
			else
				guiTarget = nil;
			end
			oldTarget = curTarget;
			curTarget = guiTarget and roster_units[guiTarget];
		end

		function Status:OnEnable()
			DebindPublic.RegisterCallback(self, "UNIT_CHANGED");
			self:RegisterMessage("Grid_UnitUpdated");
			UpdateTarget();
		end

		function Status:OnDisable()
			DebindPublic.UnregisterCallback(self, "UNIT_CHANGED");
			self:UnregisterMessage("Grid_UnitUpdated");
			guiTarget, curTarget, oldTarget = nil, nil, nil;
		end

		function Status:UNIT_CHANGED(_, alias)
			if (alias == theAlias) then
				UpdateTarget()
				if oldTarget then self:UpdateIndicators(oldTarget) end
				if curTarget then self:UpdateIndicators(curTarget) end
			end
		end

		function Status:Grid_UnitUpdated(_, unit)
			if guiTarget then
				curTarget = roster_units[guiTarget];
			end
		end

		function Status:IsActive(unit)
			return curTarget and UnitIsUnit(unit, curTarget)
		end

		function Status:GetText()
			return theAlias;
		end

		Status.GetColor = Grid2.statusLibrary.GetColor

		local function Create(baseKey, dbx)
			Grid2:RegisterStatus(Status, { "color", "text" }, baseKey, dbx)
			return Status;
		end

		Grid2.setupFunc[statusKey] = Create
		Grid2:DbSetStatusDefaultValue(statusKey, { type = statusKey, color1 = { r = .8, g = .8, b = .8, a = .75 } })
	end
end
