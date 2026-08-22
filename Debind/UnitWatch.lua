local _, DebindPrivate              = ...;
local Constants                       = DebindPrivate.Constants;
local CUSTOM_TARGET_VALID_UNIT_TOKENS = Constants.CUSTOM_TARGET_VALID_UNIT_TOKENS;
local LLL                             = DebindPrivate.L;
local BindingDriver                   = DebindPrivate.BindingDriver;
local UnitWatch                       = CreateFrame("Frame", nil, nil, "SecureFrameTemplate,SecureHandlerAttributeTemplate");
local dump                            = DebindPrivate.dump;
local issecretvalue                   = issecretvalue;

--- 12.1 answers some unit APIs with secrets for units outside our access (arena enemies,
--- mostly). A secret survives being stored, but a boolean test, a compare, a concat or a
--- format on one raises - so any insecure-side read that feeds those goes through here:
--- a secret becomes nil, and the caller treats it as "no answer", which is what it is.
--- (`issecretvalue` does not exist before 12.1; the guard short-circuits away there.)
local function PlainOrNil(value)
    if (issecretvalue and issecretvalue(value)) then
        return nil;
    end
    return value;
end

--- `UnitIsUnit` is marked ConditionalSecret: an identity we cannot confirm is treated as
--- "not the same unit" rather than an error.
local function SameUnit(a, b)
    return PlainOrNil(UnitIsUnit(a, b)) == true;
end

DebindPrivate.UnitWatch             = UnitWatch;
DebindPrivate.UnitWatchHeaders      = {};


SecureHandlerSetFrameRef(UnitWatch, "debind_driver", BindingDriver);
SecureHandlerExecute(UnitWatch, [=[
    unitwatch = self
    debind_driver = self:GetFrameRef("debind_driver")
    UnitwatchHeaders = newtable()
    ChildFrames = newtable()
    unitNames = newtable()
    unitMap = newtable()
    CUSTOM_TARGET_VALID_UNIT_TOKENS = newtable()
]=]);
do
    local tmp = {};
    for k, v in pairs(CUSTOM_TARGET_VALID_UNIT_TOKENS) do
        tmp[#tmp + 1] = format("CUSTOM_TARGET_VALID_UNIT_TOKENS[%q]=%q", k, v);
    end
    SecureHandlerExecute(UnitWatch, table.concat(tmp, "\n"));
end

---------------------------------------
-- UpdateGroupRoster
do
    local _prevUnitNameMap = {};
    function UnitWatch:UpdateGroupRoster()
        if (InCombatLockdown()) then
            return;
        end

        local unitNameMap = {};
        if (IsInRaid()) then
            for i = 1, MAX_RAID_MEMBERS do
                local unitToken = "raid" .. i;
                unitNameMap[unitToken] = DebindPrivate.GetUnitFullName(unitToken);
            end
        end
        if (IsInRaid() or IsInGroup()) then
            for i = 1, MAX_PARTY_MEMBERS do
                local unitToken = "party" .. i;
                unitNameMap[unitToken] = DebindPrivate.GetUnitFullName(unitToken);
            end
        end

        if (next(unitNameMap) == nil) then
            if (next(_prevUnitNameMap) ~= nil) then
                SecureHandlerExecute(UnitWatch, "wipe(unitNames)");
            end
        else
            local strArr = {};
            for k, v in pairs(unitNameMap) do
                if (_prevUnitNameMap[k] ~= v) then
                    strArr[#strArr + 1] = format("unitNames[%q]=%q", k, v);
                end
            end
            for k in pairs(_prevUnitNameMap) do
                if (unitNameMap[k] == nil) then
                    strArr[#strArr + 1] = format("unitNames[%q]=nil", k);
                end
            end
            if (#strArr > 0) then
                SecureHandlerExecute(UnitWatch, table.concat(strArr, "\n"));
            end
        end

        _prevUnitNameMap = unitNameMap;
        UnitWatch:SetAttribute("grouproster_uptodate", true);
        SecureHandlerExecute(UnitWatch, [[self:RunAttribute("OnGroupRosterChanged", true)]]);
    end
end

local CreateUnitWatchHeader;
do
    local CheckUnits = [=[
local alias, matchedUnit, tooMany = %q
local header = UnitwatchHeaders[alias]
if (not header:IsShown()) then
    return
end

for i = 1, %d do
    local child = ChildFrames[alias][i]
    local unit = child:GetAttribute("unit")
    if (unit) then
        if (matchedUnit) then
            matchedUnit = nil
            tooMany = true
            break
        else
            matchedUnit = unit
        end
    else
        break
    end
end

if (unitMap[alias] ~= matchedUnit) then
    unitMap[alias] = matchedUnit
    if (debind_driver:RunAttribute("SetUnit", alias, matchedUnit)) then
        debind_driver:RunAttribute("UpdateBindings")
    end
    if (tooMany) then
        unitwatch:CallMethod("OnSpecialUnitChanging", alias, false)
    else
        unitwatch:CallMethod("OnSpecialUnitChanging", alias, matchedUnit)
    end
end
self:Show()
]=];

    function CreateUnitWatchHeader(alias, numFrames, ...)
        local header = CreateFrame("Button", nil, nil, "SecureGroupHeaderTemplate");
        DebindPrivate.UnitWatchHeaders[alias] = header;
        header:Hide();

        header:SetAttribute("alias", alias);
        header:SetAttribute("showParty", true);
        header:SetAttribute("showRaid", true);
        if (strsub(alias, 1, 6) ~= "custom"
                and DebindPrivate.Options.excludePlayer
                and DebindPrivate.Options.excludePlayer[alias]) then
            header:SetAttribute("showPlayer", false);
        else
            header:SetAttribute("showPlayer", true);
        end
        header:SetAttribute("showSolo", true);
        header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8");
        header:SetAttribute("sortMethod", "NAME");
        header:SetAttribute("maxColumns", 1);
        header:SetAttribute("unitsPerColumn", numFrames);
        header:SetAttribute("template", "");
        header:SetAttribute("templateType", "Frame");

        for i = 1, select("#", ...), 2 do
            header:SetAttribute(select(i, ...), select(i + 1, ...));
        end

        for i = 1, numFrames do
            local childFrame = CreateFrame("Button", nil, header, "SecureFrameTemplate");
            header:SetAttribute("child" .. i, childFrame);
            SecureHandlerSetFrameRef(header, "child" .. i, childFrame);
        end

        SecureHandlerSetFrameRef(UnitWatch, "unitwatch_header", header);
        SecureHandlerExecute(UnitWatch, ([=[
            local alias, numFrames = %q, %d
            local header = self:GetFrameRef("unitwatch_header")
            UnitwatchHeaders[alias] = header
            ChildFrames[alias] = newtable()
            for i = 1, numFrames do
                ChildFrames[alias][i] = header:GetFrameRef("child"..i)
            end
        ]=]):format(alias, numFrames));

        local lastChildFrame = CreateFrame("Frame", nil, header, "SecureFrameTemplate");
        header:SetAttribute("child" .. (numFrames + 1), lastChildFrame);
        SecureHandlerWrapScript(lastChildFrame, "OnHide", UnitWatch, CheckUnits:format(alias, numFrames));

        return header;
    end
end

-- Tidies custom targets when the roster changed (uptodate=false) and when it is current
-- again (uptodate=true). Name-tracked ones (their header is shown) follow the person by
-- themselves, so only the volatile ones (a raw token) are touched here.
--
-- A volatile one is dropped rather than carried over because we never learned who it points
-- at. `unitNames` is filled by `UpdateGroupRoster`, which bails out in combat, so from the
-- first roster change of a fight onwards a raw `raid7` has no name behind it. At the next
-- roster change there is nothing to compare against and no way to tell whether `raid7` is
-- still the same person, and aiming at the wrong one is worse than aiming at nobody.
--
-- Called explicitly instead of being hung off the attribute changed event. SetAttribute with
-- an unchanged value does fire `_onattributechanged` (measured in game), but that is not
-- documented behaviour, and if invalidation silently stops running then `@custom1` points at
-- a stranger once the roster has shifted, so nothing here leans on it.
UnitWatch:SetAttribute("OnGroupRosterChanged", [==[
    local uptodate = ...
    for i = 1, 2 do
        local alias = "custom"..i
        local unit = unitMap[alias]
        if (CUSTOM_TARGET_VALID_UNIT_TOKENS[unit] == "group") then
            if (not UnitwatchHeaders[alias]:IsShown()) then
                if (uptodate) then
                    local unitName = unitNames[unit]
                    if (unitName) then
                        self:SetAttribute(alias, ":"..unitName)
                    end
                else
                    self:SetAttribute(alias, false)
                end
            end
        end
    end
]==]);

do
    local header = CreateFrame("Frame", nil, nil, "SecureGroupHeaderTemplate");
    header:SetAttribute("showParty", true);
    header:SetAttribute("showRaid", true);
    header:SetAttribute("showSolo", true);
    header:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8");
    header:SetAttribute("maxColumns", 1);
    header:SetAttribute("unitsPerColumn", 1);
    header:SetAttribute("template", "");
    header:SetAttribute("templateType", "Frame");

    local childFrame = CreateFrame("Button", nil, header, "SecureFrameTemplate");
    header:SetAttribute("child1", childFrame);
    SecureHandlerSetFrameRef(header, "child1", childFrame);

    local lastChildFrame = CreateFrame("Frame", nil, header, "SecureFrameTemplate");
    header:SetAttribute("child2", lastChildFrame);

    SecureHandlerWrapScript(lastChildFrame, "OnHide", UnitWatch, [==[
        unitwatch:SetAttribute("grouproster_uptodate", false)
        unitwatch:RunAttribute("OnGroupRosterChanged", false)
        unitwatch:CallMethod("UpdateGroupRoster")
		self:Show()
    ]==]);

    header:Show()
end

do
    local UNITWATCH_HEADER_PROPS = {
        tank = { 2, "roleFilter", "TANK", "showSolo", false },
        healer = { 2, "roleFilter", "HEALER", "showSolo", false },
        maintank = { 2, "roleFilter", "MAINTANK", "showSolo", false },
        mainassist = { 2, "roleFilter", "MAINASSIST", "showSolo", false },
        custom1 = { 1, "nameList", "" },
        custom2 = { 1, "nameList", "" },
    };

    function DebindPrivate.GetUnitWatchHeader(alias, allowCreate)
        local header = DebindPrivate.UnitWatchHeaders[alias];
        if (not header and allowCreate) then
            if (not UNITWATCH_HEADER_PROPS[alias]) then
                return;
            end
            header = CreateUnitWatchHeader(alias, unpack(UNITWATCH_HEADER_PROPS[alias]));
        end
        return header;
    end

    function DebindPrivate.EnableUnitWatch(unit, ...)
        local header = DebindPrivate.UnitWatchHeaders[unit];
        if (not header) then
            if (not UNITWATCH_HEADER_PROPS[unit]) then
                return;
            end
            header = CreateUnitWatchHeader(unit, unpack(UNITWATCH_HEADER_PROPS[unit]));
        end

        local n = select("#", ...);
        if (n > 0) then
            for i = 1, 2, 2 do
                header:SetAttribute(select(i, ...), select(i + 1, ...));
            end
        end

        header:Show();
        return header;
    end

    function DebindPrivate.DisableUnitWatch(unit, ...)
        local header = DebindPrivate.UnitWatchHeaders[unit];
        if (header and header:IsShown()) then
            header:Hide();
            SecureHandlerExecute(UnitWatch, format("unitMap[%q] = nil", unit));
            UnitWatch:OnSpecialUnitChanging(unit, nil);
        end
    end
end

CreateUnitWatchHeader("custom1", 1, "nameList", "");
CreateUnitWatchHeader("custom2", 1, "nameList", "");

-- false 실패
-- nil unset
-- value
local function DoResolveUnitToken(value)
    if (strsub(value, 1, 1) == ":") then
        return value;
    end

    local unitType = CUSTOM_TARGET_VALID_UNIT_TOKENS[value];
    if (unitType) then
        return value, unitType;
    end

    if (UnitExists(value)) then
        if (SameUnit(value, "player")) then
            return "player", "player";
        elseif (SameUnit(value, "pet")) then
            return "pet", "pet";
        end

        -- target focus targettarget focustarget mouseover etc etc
        local raidID = UnitInRaid(value);
        if (raidID) then
            return "raid" .. raidID, "group";
        elseif (UnitInParty(value)) then
            for i = 1, MAX_PARTY_MEMBERS do
                if (SameUnit("party" .. i, value)) then
                    return "party" .. i, "group";
                end
            end
        end

        for i = 1, Constants.MAX_BOSSES do
            if (SameUnit("boss" .. i, value)) then
                return "boss" .. i, "boss";
            end
        end

        for i = 1, MAX_ARENA_ENEMIES do
            if (SameUnit("arena" .. i, value)) then
                return "arena" .. i, "arena";
            end
        end

        return false;
    end

    return nil;
end

function UnitWatch:ResolveUnitToken(unitToken)
    if (InCombatLockdown()) then
        return;
    end
    local resolvedUnit = DoResolveUnitToken(unitToken);
    self:SetAttribute("resolvedUnit", resolvedUnit);
end

function UnitWatch:LoadCustomTargets()
    if (DebindPrivate.db.char.CustomTargets) then
        for i = 1, 2 do
            local alias = "custom" .. i;
            local savedValue = DebindPrivate.db.char.CustomTargets[alias];
            if (savedValue) then
                UnitWatch:SetAttribute(alias, savedValue);
            end
        end
    end
end

do
    local _lastSeen = {};
    local _changedAliases = {};
    local _sortedUnits = { "custom1", "custom2", "tank", "healer" };

    --- 12.1 arenas answer UnitClass (and friends) with secrets for enemy players, and
    --- neither the class-color table nor CreateColor can digest a secret - the lookup
    --- raised and took the rest of this update pass with it. The color is cosmetic, so
    --- anything unreadable falls back to gray. (GetClassColorObj can also return nil
    --- for a token it does not know; the same fallback covers that.)
    local function UnitDisplayColor(unit)
        local ok, color = pcall(function()
            if (UnitIsPlayer(unit)) then
                local _, classFilename = UnitClass(unit);
                return GetClassColorObj(classFilename);
            end
            return CreateColor(UnitSelectionColor(unit));
        end);
        return (ok and color) or GRAY_FONT_COLOR;
    end

    local function CustomTargetsChangedCallback()
        for _, alias in ipairs(_sortedUnits) do
            local info = _changedAliases[alias];
            if (info) then
                if (alias == "custom1" or alias == "custom2") then
                    local value = DebindPrivate.Units[alias];
                    local set = info.set;
                    local invalidating = info.invalidating;
                    local unitName, isVolatile, saveValue, guid;

                    if (value) then
                        local unitType = CUSTOM_TARGET_VALID_UNIT_TOKENS[value];
                        unitName = DebindPrivate.GetUnitFullName(value);
                        guid = PlainOrNil(UnitGUID(value));
                        if (unitType == "group") then
                            isVolatile = not DebindPrivate.UnitWatchHeaders[alias]:IsShown();
                            if (unitName) then
                                saveValue = ":" .. unitName;
                            end
                        else
                            saveValue = value;
                        end
                    elseif (DebindPrivate.UnitWatchHeaders[alias]:IsShown()) then
                        unitName = DebindPrivate.UnitWatchHeaders[alias]:GetAttribute("nameList");
                        if (unitName) then
                            saveValue = ":" .. unitName;
                        end
                    end

                    DebindPrivate.db.char.CustomTargets = DebindPrivate.db.char.CustomTargets or {};
                    DebindPrivate.db.char.CustomTargets[alias] = saveValue;

                    if (set or _lastSeen[alias] ~= guid) then
                        _lastSeen[alias] = guid;
                        if (value or unitName) then
                            local color;
                            if (value and UnitExists(value)) then
                                color = UnitDisplayColor(value);
                            else
                                color = GRAY_FONT_COLOR;
                            end
                            local colorCodedName = color:WrapTextInColorCode(unitName or value);
                            if (isVolatile) then
                                DebindPrivate.DisplayMessage(format(LLL["CUSTOM_TARGET_SET_VOLATILE"], LLL["UNIT_" .. strupper(alias)], colorCodedName));
                            else
                                DebindPrivate.DisplayMessage(format(LLL["SPECIAL_UNIT_SET_MESSAGE"], LLL["UNIT_" .. strupper(alias)], colorCodedName));
                            end
                        elseif (invalidating) then
                            DebindPrivate.DisplayMessage(format(LLL["CUSTOM_TARGET_INVALIDATED"], LLL["UNIT_" .. strupper(alias)]));
                        else
                            DebindPrivate.DisplayMessage(format(LLL["SPECIAL_UNIT_UNSET_MESSAGE"], LLL["UNIT_" .. strupper(alias)]));
                        end
                    end
                else
                    local value = DebindPrivate.Units[alias] or nil;
                    local invalidating = info.invalidating;
                    local unitName, guid;

                    if (value) then
                        unitName = DebindPrivate.GetUnitFullName(value);
                        guid = PlainOrNil(UnitGUID(value));
                    end

                    if (_lastSeen[alias] ~= guid) then
                        _lastSeen[alias] = guid;
                        if (value or unitName) then
                            local color;
                            if (value and UnitExists(value)) then
                                color = UnitDisplayColor(value);
                            else
                                color = GRAY_FONT_COLOR;
                            end
                            local colorCodedName = color:WrapTextInColorCode(unitName or value);
                            DebindPrivate.DisplayMessage(format(LLL["SPECIAL_UNIT_SET_MESSAGE"], LLL["UNIT_" .. strupper(alias)], colorCodedName));
                        elseif (invalidating) then
                            DebindPrivate.DisplayMessage(format(LLL["SPECIAL_UNIT_UNSET_MESSAGE_TOO_MANY"], LLL["UNIT_" .. strupper(alias)]));
                        else
                            DebindPrivate.DisplayMessage(format(LLL["SPECIAL_UNIT_UNSET_MESSAGE"], LLL["UNIT_" .. strupper(alias)]));
                        end
                    end
                end
            end
        end

        wipe(_changedAliases);
    end

    function UnitWatch:OnSpecialUnitChanging(alias, value, set)
        if (not next(_changedAliases)) then
            C_Timer.After(0, CustomTargetsChangedCallback);
        end
        _changedAliases[alias] = _changedAliases[alias] or {};
        _changedAliases[alias].value = value or nil;
        _changedAliases[alias].set = _changedAliases[alias].set or set;
        _changedAliases[alias].invalidating = value == false;
    end

    function UnitWatch:OnSetCustomTargetFailed(alias, value, originalValue)
        local resolvedUnit, unitType = DoResolveUnitToken(value);
        if (resolvedUnit == false) then
            DebindPrivate.DisplayMessage(format(LLL["CUSTOM_TARGET_UNSUPPORTED_UNIT"], LLL["UNIT_" .. strupper(alias)], DebindPrivate.GetUnitFullName(value) or value));
        else
            if (InCombatLockdown()) then
                local helpMessage;
                if ((originalValue == "hover" or originalValue == "mouseover") and unitType) then
                    helpMessage = rawget(LLL, "CUSTOM_TARGET_HELP_MESSAGE_" .. unitType:upper());
                end
                helpMessage = helpMessage or "";
                DebindPrivate.DisplayMessage(format(LLL["CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT"], LLL["UNIT_" .. strupper(alias)], value, helpMessage));
            else
                DebindPrivate.DisplayMessage(format(LLL["CUSTOM_TARGET_FAILED"], LLL["UNIT_" .. strupper(alias)], value));
            end
        end
    end
end

UnitWatch:SetAttribute("_onattributechanged", [==[
    if (name == "custom1" or name == "custom2") then
        local alias, unit, nameList = name, value or nil
		if (unit) then
			unit = strtrim(unit)
            if (unit == "" or unit == "none" or unit == ":") then
                unit = nil
			elseif (unit == "hover") then
                unit = debind_driver:RunAttribute("GetHoveredUnit")
            end
		end

		if (unit) then
			self:SetAttribute("resolvedUnit", unit)
			self:CallMethod("ResolveUnitToken", unit)
            unit = self:GetAttribute("resolvedUnit") or unit
		end

        if (unit ~= unitMap[alias]) then
            if (unit) then
                if (CUSTOM_TARGET_VALID_UNIT_TOKENS[unit]) then
                    if (CUSTOM_TARGET_VALID_UNIT_TOKENS[unit] == "group") then
                        if (UnitExists(unit)) then
                            if (self:GetAttribute("grouproster_uptodate")) then
                                nameList = unitNames[unit]
                            end
                        else
                            unit = nil
                        end
                    end
                elseif (strsub(unit, 1, 1) == ":") then
                    nameList = strsub(unit, 2)
                elseif (UnitExists(unit)) then
                    self:CallMethod("OnSetCustomTargetFailed", alias, unit, value)
                    return
                else
                    unit = nil
                end
            end

            local header = UnitwatchHeaders[alias]
            if (nameList) then
                header:SetAttribute("nameList", nameList)
                header:Show()
            else
                header:Hide()
                if (unitMap[alias] ~= unit) then
                    unitMap[alias] = unit
                    if (debind_driver:RunAttribute("SetUnit", alias, unit or nil)) then
                        debind_driver:RunAttribute("UpdateBindings")
                    end
                end
            end
        end

        if (value == false) then
            self:CallMethod("OnSpecialUnitChanging", alias, false)
        else
            self:CallMethod("OnSpecialUnitChanging", alias, unit, true)
        end
	end
]==]);

--- **이 PLAYER_LOGIN은 Events.lua의 것보다 뒤에 와야 한다.** `LoadCustomTargets`가 읽는
--- `db.char.CustomTargets`는 마이그레이션이 넣어주는 값이고(`Events.PLAYER_LOGIN` ->
--- `RunLegacyMigration`), 넘어온 사용자에게 그 값이 채워지는 것은 그 호출 뒤다. 먼저 오면
--- 빈 테이블을 읽고 조용히 아무것도 안 붙인다 - 마이그레이션한 캐릭터의 사용자 지정 대상이
--- 그 접속에서만 비어 보인다.
---
--- 지금 순서를 만드는 것은 **`Debind.xml`의 파일 차례**뿐이다(Events.lua가 UnitWatch.lua보다
--- 위). 같은 이벤트에 건 핸들러는 등록한 차례로 불리므로, 그 두 줄을 맞바꾸면 여기가 조용히
--- 깨진다. 옮길 일이 있으면 이 의존을 먼저 없앨 것.
UnitWatch:SetScript("OnEvent", function(_, event, arg1)
    if (event == "PLAYER_LOGIN") then
        UnitWatch:UpdateGroupRoster();
        UnitWatch:LoadCustomTargets();
        UnitWatch:RegisterEvent("PLAYER_REGEN_ENABLED");
        UnitWatch:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT");
        UnitWatch:RegisterEvent("ARENA_OPPONENT_UPDATE");
        UnitWatch:RegisterUnitEvent("UNIT_PET", "player");
    elseif (event == "PLAYER_REGEN_ENABLED") then
        if (not UnitWatch:GetAttribute("grouproster_uptodate")) then
            UnitWatch:UpdateGroupRoster();
        end
    elseif (event == "UNIT_PET") then
        if (arg1 == "player") then
            for i = 1, 2 do
                local alias = "custom" .. i;
                if (DebindPrivate.Units[alias] == "pet") then
                    UnitWatch:OnSpecialUnitChanging(alias, "pet");
                end
            end
        end
    elseif (event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT") then
        for i = 1, 2 do
            local alias = "custom" .. i;
            local value = DebindPrivate.Units[alias];
            if (value and CUSTOM_TARGET_VALID_UNIT_TOKENS[value] == "boss") then
                UnitWatch:OnSpecialUnitChanging(alias, value);
            end
        end
    elseif (event == "ARENA_OPPONENT_UPDATE") then
        local value = arg1;
        for i = 1, 2 do
            local alias = "custom" .. i;
            if (DebindPrivate.Units[alias] == value) then
                UnitWatch:OnSpecialUnitChanging(alias, value);
            end
        end
    end
end);
UnitWatch:RegisterEvent("PLAYER_LOGIN");

for i = 1, 2 do
    local button = CreateFrame("Button", "DebindCustom" .. i, nil, "SecureActionButtonTemplate");
    button:SetAttribute("alias", "custom" .. i);
    SecureHandlerWrapScript(button, "OnClick", UnitWatch, [==[
        local alias = self:GetAttribute("alias")
        local value = button
        if (not value or value == "LeftButton") then
            value = nil
        end
        unitwatch:SetAttribute(alias, value)
    ]==]);
end

local function AddCustomTargetMenus(owner, rootDescription, contextData)
    if (not DebindPrivate.Options.addCustomTargetMenusToUnitPopup) then
        return;
    end
    if (InCombatLockdown()) then
        return;
    end
    if (not contextData.unit) then
        return;
    end

    local unit = DoResolveUnitToken(contextData.unit);
    if (unit) then
        rootDescription:CreateDivider();
        rootDescription:CreateTitle(LLL["ADDON_NAME"]);
        for i = 1, 2 do
            local desc = rootDescription:CreateButton(LLL["TYPE_SETCUSTOM" .. i], function()
                if (not InCombatLockdown()) then
                    DebindPrivate.UnitWatch:SetAttribute("custom" .. i, unit);
                end
                return MenuResponse.Close;
            end);
            desc:SetEnabled(function()
                return not InCombatLockdown();
            end);

            desc:CreateButton(LLL["CUSTOM_TARGET_CLEAR"], function(...)
                if (not InCombatLockdown()) then
                    DebindPrivate.UnitWatch:SetAttribute("custom" .. i, nil);
                end
                return MenuResponse.Close;
            end);
        end
    end
end

Menu.ModifyMenu("MENU_UNIT_SELF", AddCustomTargetMenus);
Menu.ModifyMenu("MENU_UNIT_TARGET", AddCustomTargetMenus);
Menu.ModifyMenu("MENU_UNIT_FOCUS", AddCustomTargetMenus);
Menu.ModifyMenu("MENU_UNIT_PARTY", AddCustomTargetMenus);
Menu.ModifyMenu("MENU_UNIT_RAID", AddCustomTargetMenus);
Menu.ModifyMenu("MENU_UNIT_BOSS", AddCustomTargetMenus); -- not tested
Menu.ModifyMenu("MENU_UNIT_ARENA", AddCustomTargetMenus); -- not tested