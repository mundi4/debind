local _, DebouncePrivate = ...
local BindingDriver      = DebouncePrivate.BindingDriver;
local Constants          = DebouncePrivate.Constants;
local LLL                = DebouncePrivate.L;

DebouncePublic           = {};
DebouncePublic.header    = BindingDriver;
DebouncePublic.Units     = setmetatable({}, {
	__index = DebouncePrivate.Units,
	__newindex = function() end,
});

function DebouncePublic:SetCustomTarget(alias, value)
	if (InCombatLockdown()) then
		DebouncePrivate.DisplayMessage(LLL["ERROR_MESSAGE_CANNOT_SET_CUSTOM_TARGET_IN_COMBAT"], 1, 0, 0);
		return;
	end

	if (alias == 1 or alias == 2) then
		alias = "custom" .. alias;
	end

	if (alias == "custom1" or alias == "custom2") then
		DebouncePrivate.UnitWatch:SetAttribute(alias, value);
	end
end

function DebouncePublic:RegisterFrame(button, ...)
	DebouncePrivate.RegisterFrame(button, ...);
end

function DebouncePublic:UnregisterFrame(button)
	DebouncePrivate.UnregisterFrame(button);
end

function DebouncePublic:UpdateRegisteredClicks(button)
	DebouncePrivate.UpdateRegisteredClicks(button);
end

local VALID_EVENTNAMES = {
	UNIT_CHANGED = true,
	STATE_CHANGED = true,
};

function DebouncePublic.RegisterCallback(target, eventname, method, ...)
	if (not VALID_EVENTNAMES[eventname]) then
		return;
	end
	if (DebouncePublic == target) then
		error("RegisterCallback(): use your own 'self'", 2);
	end
	DebouncePrivate.RegisterCallback(target, eventname, method, ...);
end

function DebouncePublic.UnregisterCallback(target, eventname)
	if (not VALID_EVENTNAMES[eventname]) then
		return;
	end
	if (DebouncePublic == target) then
		error("UnregisterCallback(): use your own 'self'", 2);
	end
	DebouncePrivate.UnregisterCallback(target, eventname);
end

function DebouncePublic:ToggleUI()
	if (DebounceFrame:IsShown()) then
		DebounceFrame:Hide();
		return
	end
	if (InCombatLockdown()) then
		DebouncePrivate.DisplayMessage(LLL["CANNOT_OPEN_IN_COMBAT"], 1, 0, 0)
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
		DebouncePrivate.DisplayMessage(LLL["CANNOT_OPEN_WITH_GAME_MENU"], 1, 0, 0)
		return
	end
	DebounceFrame:Show();
end

if (not DebouncePrivate.CliqueDetected) then
	local prev = _G.DebouncePrivate;
	_G.DebouncePrivate = DebouncePrivate;
	C_AddOns.LoadAddOn("DebounceCliqueFake");
	_G.DebouncePrivate = prev;
end

SlashCmdList["DEBOUNCE"] = function(msg)
	msg = strlower(msg);
	if (msg == "overview") then
		DebounceOverviewFrame:Toggle();
		return;
	end

	local chunks = {};
	for s in msg:gmatch("%S+") do
		tinsert(chunks, s)
	end

	if (chunks[1] == "custom1" or chunks == "custom2") then
		DebouncePublic:SetCustomTarget(chunks[1], chunks[2]);
		return;
	end

	DebouncePublic:ToggleUI();
end

function Debounce_CompartmentFunc(name, mouseButton, btn)
	if (mouseButton == "RightButton") then
		DebounceOverviewFrame:Toggle();
	else
		DebouncePublic:ToggleUI();
	end
end

--- 구획 항목에 마우스를 올렸을 때. 좌·우클릭이 서로 다른 창을 여는데, 그걸 말해줄 자리가
--- 여기밖에 없다 - 메뉴 항목은 이름 한 줄이 전부라 우클릭은 우연히 눌러야만 발견된다.
--- 인자는 블리자드가 준다 (Blizzard_Minimap/AddonCompartment.lua의 funcOnEnter).
function Debounce_CompartmentOnEnter(name, btn)
	GameTooltip:SetOwner(btn, "ANCHOR_LEFT");
	GameTooltip_SetTitle(GameTooltip, C_AddOns.GetAddOnMetadata(name, "Title") or name);
	GameTooltip_AddInstructionLine(GameTooltip, LLL["COMPARTMENT_TOOLTIP_LEFT_CLICK"]);
	GameTooltip_AddInstructionLine(GameTooltip, LLL["COMPARTMENT_TOOLTIP_RIGHT_CLICK"]);
	GameTooltip:Show();
end

function Debounce_CompartmentOnLeave()
	GameTooltip:Hide();
end

SLASH_DEBOUNCE1 = "/debounce";
SLASH_DEBOUNCE2 = "/deb";

_G.DebouncePublic = setmetatable(DebouncePublic, { __newindex = function() end });

if (_G.Grid2) then
	local Grid2 = _G.Grid2;
	local UnitIsUnit = UnitIsUnit;
	local UnitGUID = UnitGUID;
	local roster_units = Grid2.roster_units;

	local aliases = { "custom1", "custom2", "hover", "tank", "healer", "maintank", "mainassist" };
	for i = 1, #aliases do
		local theAlias = aliases[i];
		local statusKey = "debounce_" .. theAlias;
		local Status = Grid2.statusPrototype:new(statusKey);

		local guiTarget, curTarget, oldTarget
		local function UpdateTarget()
			local unit = DebouncePublic.Units[theAlias];
			if (unit) then
				guiTarget = UnitGUID(unit);
			else
				guiTarget = nil;
			end
			oldTarget = curTarget;
			curTarget = guiTarget and roster_units[guiTarget];
		end

		function Status:OnEnable()
			DebouncePublic.RegisterCallback(self, "UNIT_CHANGED");
			self:RegisterMessage("Grid_UnitUpdated");
			UpdateTarget();
		end

		function Status:OnDisable()
			DebouncePublic.UnregisterCallback(self, "UNIT_CHANGED");
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
