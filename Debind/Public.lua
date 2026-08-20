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
	SWITCH_CHANGED = true,
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
	-- **Stood down, so there is no window to open.** What would come up is the empty profile
	-- `StandDown` handed out, and the user would start putting bindings into a place that saves
	-- nothing (`Profile.lua`). The refusal sits here rather than in the slash handler because the
	-- addon compartment button comes through here too, and it is the same shape as the three
	-- branches below: press something and have nothing happen, and that reads as broken.
	if (DebindPrivate.profileIsNewer) then
		DebindPrivate.ReportNewerProfile();
		return
	end
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
	-- **마이그레이션 질문이 남아 있으면 그것부터.** 창을 열어주면 그 안에서 바인딩을 만들 수
	-- 있고, 그러면 옛 설정을 가져오기 전에 새 설정이 생긴다 - 인수 쪽이 무엇을 덮을지 판정할
	-- 일이 없어지는 근거가 이 한 줄이다(`Legacy.lua`).
	--
	-- **조용히 돌아서지 않는다.** 위 두 분기와 같은 이유로, 안내창을 대신 띄운다. 로그인에
	-- 이미 한 번 떴다가 닫힌 것이라 사용자는 이게 무엇인지 안다.
	if (DebindPrivate.ShowMigrationDialogIfPending()) then
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

	-- `/deb reset` and `/deb reset confirm`, and **only while the addon has stood down** from a
	-- profile newer than itself (`Profile.lua`). Nothing here is a general "wipe my settings"
	-- command; the two steps exist because that is the one state with no other way out.
	if (DebindPrivate.HandleNewerProfileReset(chunks)) then
		return;
	end

	--@debug@
	-- Plants the development seed and reloads (`DevSeed.lua`). No `SLASH_` global of its own: this
	-- is the addon's command and the branch is one more word on it.
	if (DebindPrivate.HandleDevSeedCommand(chunks)) then
		return;
	end
	--@end-debug@

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

--- 구획 항목에 마우스를 올렸을 때. **좌·우클릭이 갈리던 시절의 흔적을 남기지 말 것** - 위
--- `Debind_CompartmentFunc` 주석대로 지금은 둘이 같은 일을 하고, 툴팁도 왼쪽 클릭 한 줄만 문다.
---
--- 그래도 툴팁이 필요한 이유는 따로 있다. 구획 항목은 이름 한 줄이 전부라 **눌러서 무엇이
--- 열리는지**를 말할 자리가 여기밖에 없고, 오버뷰가 창의 왼쪽 열로 들어간 뒤로는 그것을
--- 찾아가는 길도 여기서만 알려준다(COMPARTMENT_TOOLTIP_LEFT_CLICK).
---
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

	local aliases = { "custom1", "custom2", "hover", "tank", "healer", "maintank", "mainassist" };
	for i = 1, #aliases do
		local theAlias = aliases[i];
		-- **Stays `debounce_` after the rename.** Grid2 persists this key in its own saved
		-- variables to remember which statuses a user attached to which indicators. Renaming it
		-- would not migrate anything - it would just make those statuses vanish from layouts we
		-- have no way to reach or repair. Same reasoning as the `DebouncePublic` alias below.
		local statusKey = "debounce_" .. theAlias;
		local Status = Grid2.statusPrototype:new(statusKey);

		-- Grid2 keys its frames by unit token, so refreshing an indicator needs the *roster*
		-- token for our target - not whatever token Debind happens to hold, which may be
		-- "mouseover" or a custom unit that Grid2 never draws.
		--
		-- Resolving that through `UnitGUID` is not an option under Midnight. The GUID can come
		-- back as a secret value, and Grid2 refuses to file those in `roster_units` at all
		-- (`GridRoster.lua`), so the lookup would quietly miss and the status would simply never
		-- light up - no error, no clue. Walking the roster and comparing tokens costs one pass
		-- per target change and never touches a GUID.
		--
		-- `UnitIsUnit` can come back secret under Midnight for the same reason. An identity
		-- we cannot confirm counts as "not the same unit" - and `IsActive` below must hand
		-- Grid2 a plain boolean, because Grid2 boolean-tests the result and a secret there
		-- raises inside Grid2's own code.
		local function SameUnit(a, b)
			local same = UnitIsUnit(a, b);
			if (issecretvalue and issecretvalue(same)) then
				return false;
			end
			return same == true;
		end

		-- The roster also holds "target"/"focus" alongside the group tokens, and those point at
		-- the same player. Prefer the group token, or the indicator update lands on a frame
		-- Grid2 is not drawing.
		local function FindRosterUnit(unit)
			if (not unit) then
				return nil;
			end
			local fallback;
			for rosterUnit in Grid2:IterateRosterUnits() do
				if (SameUnit(rosterUnit, unit)) then
					if (Grid2:IsPlayerInRaid(rosterUnit) or Grid2:UnitIsPet(rosterUnit)) then
						return rosterUnit;
					end
					fallback = fallback or rosterUnit;
				end
			end
			return fallback;
		end

		local curUnit, curTarget, oldTarget
		local function UpdateTarget()
			curUnit = DebindPublic.Units[theAlias];
			oldTarget = curTarget;
			curTarget = FindRosterUnit(curUnit);
		end

		function Status:OnEnable()
			DebindPublic.RegisterCallback(self, "UNIT_CHANGED");
			self:RegisterMessage("Grid_UnitUpdated");
			UpdateTarget();
		end

		function Status:OnDisable()
			DebindPublic.UnregisterCallback(self, "UNIT_CHANGED");
			self:UnregisterMessage("Grid_UnitUpdated");
			curUnit, curTarget, oldTarget = nil, nil, nil;
		end

		function Status:UNIT_CHANGED(_, alias)
			if (alias == theAlias) then
				UpdateTarget()
				if oldTarget then self:UpdateIndicators(oldTarget) end
				if curTarget then self:UpdateIndicators(curTarget) end
			end
		end

		-- The roster reshuffled. Our target may have moved to a different token, or picked up a
		-- frame it did not have a moment ago, so re-resolve and repaint both ends - the old code
		-- recomputed the token but never asked for a redraw, leaving the mark on the old frame
		-- until the next target change.
		--
		-- Only bother when the update concerns us. This fires per unit, and the roster walk is
		-- not free.
		function Status:Grid_UnitUpdated(_, unit)
			if (not curUnit) then
				return;
			end
			if (unit == curTarget or SameUnit(unit, curUnit)) then
				local prev = curTarget;
				curTarget = FindRosterUnit(curUnit);
				if (prev ~= curTarget) then
					if prev then self:UpdateIndicators(prev) end
					if curTarget then self:UpdateIndicators(curTarget) end
				end
			end
		end

		function Status:IsActive(unit)
			return curTarget ~= nil and SameUnit(unit, curTarget)
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

	-- Two cosmetic fixes for Grid2's config list, both of which have to wait for Grid2Options.
	--
	-- The icon: without it our statuses wear the generic "Miscellaneous" category icon,
	-- indistinguishable from anything else that landed there. Same portrait the main window uses
	-- (`DebindFrameMixin:OnLoad`). `optionParams` is keyed by `dbx.type`, which for us is the
	-- status key. Passing no category leaves them under Miscellaneous - only the icon changes.
	--
	-- The label: Grid2 shows `L[statusName]` for a status it has no translation for, which means
	-- the raw key - a user reading the list sees `debounce_hover`. **This is the reason the key
	-- itself does not need renaming.** What was wrong was the word on screen, not the key in the
	-- database, and the two are separate here.
	--
	-- Writing into another addon's locale table is allowed where writing its SavedVariables is
	-- not: `Grid2Options.L` is AceLocale's in-memory table, it persists nothing, and a mistake
	-- costs one wrong label until the next reload. AceLocale puts no `__newindex` on what
	-- `GetLocale` hands back, and it already fills the table itself the same way - a missing key
	-- gets `rawset(self, key, key)` on first lookup. Our keys carry our own prefix, so nothing
	-- else can collide with them.
	--
	-- The names come from the same strings the rest of our UI uses for these units, so somebody
	-- who set up "Custom Target 1" in Debind finds that same wording here.
	local function DecorateStatusOptions()
		local Grid2Options = _G.Grid2Options;
		if (not Grid2Options) then
			return false;
		end
		for i = 1, #aliases do
			local theAlias = aliases[i];
			local statusKey = "debounce_" .. theAlias;
			Grid2Options:RegisterStatusOptions(statusKey, nil, nil, { titleIcon = 133015 });
			Grid2Options.L[statusKey] = format("%s: %s", LLL["ADDON_NAME"], LLL["UNIT_" .. strupper(theAlias)]);
		end
		return true;
	end

	-- Grid2Options is load-on-demand, so it usually does not exist yet - it arrives when the user
	-- first opens the config window. Register now if something already pulled it in, otherwise
	-- wait for it and then stop listening.
	if (not DecorateStatusOptions()) then
		local watcher = CreateFrame("Frame");
		watcher:RegisterEvent("ADDON_LOADED");
		watcher:SetScript("OnEvent", function(self, _, addonName)
			if (addonName == "Grid2Options") then
				DecorateStatusOptions();
				self:UnregisterEvent("ADDON_LOADED");
				self:SetScript("OnEvent", nil);
			end
		end);
	end
end
