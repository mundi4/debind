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
	-- 게임메뉴는 열릴 때 열린 창을 전부 닫고 나온다. 그 위에 얹히지 않는다.
	if (GameMenuFrame:IsShown()) then
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
	if (false and mouseButton == "RightButton") then
		DebounceOverviewFrame:Toggle();
	else
		DebouncePublic:ToggleUI();
	end
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
