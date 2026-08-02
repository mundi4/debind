local _, DebouncePrivate    = ...;
local Constants             = DebouncePrivate.Constants;
local LLL                   = DebouncePrivate.L;

local band                  = bit.band;
local GetBindingIssue       = DebouncePrivate.GetBindingIssue;
local GetSpellNameAndIconID = DebouncePrivate.GetSpellNameAndIconID;

--------------------------------------------------------------------------------
-- 조건 서술자
--
-- 같은 조건 집합을 세 곳이 그린다: 행 툴팁, 우클릭 드롭다운, 상세 패널의 조건 탭.
-- 세 번째가 생기는 시점에 표시 규칙을 한 군데로 모았다. 여기가 아니면 "설정돼 있는가"와
-- "지금 값이 무엇인가"가 곧 세 벌이 되고, 그때부터는 조용히 어긋난다.
--
-- 서술자 하나가 아는 것:
--   key            액션의 필드명. 저장 포맷 그대로다 - 새 필드를 만들지 않는다
--   label          사람이 읽는 이름
--   IsSet          설정돼 있는가. 툴팁의 표시 규칙과 같아야 한다
--   GetLines       지금 값을 줄 단위로. 툴팁이 그대로 쓰고, 조건 탭은 요약에 쓴다
--   GetSummary     한 줄 요약(선택). 없으면 GetLines를 이어붙인다
--   Clear          nil로 되돌린다
--   IsAvailable    이 액션에 이 조건을 붙일 수 있는가(선택)
--   BuildMenu      편집 메뉴. DropDownMenus.lua가 자기 빌더를 끼워 넣는다
--
-- GetLines가 채우는 줄: { text = "...", error = nil | true | false, isDescriptorError = bool }
--   error == nil 이면 서술자 자신의 이슈를 따른다. 줄마다 이슈가 다른 경우(hover의
--   반응/프레임타입)에만 줄이 직접 답한다.
--   isDescriptorError는 "이 줄의 글자가 곧 그 이유"라는 표시다. 아래에 이유를 또 적지 않는다.
--------------------------------------------------------------------------------

--- 유닛 표시 순서. 툴팁·드롭다운·조건 탭이 같은 순서를 써야 같은 것으로 보인다.
local SORTED_UNIT_LIST      = {
    "player",
    "pet",
    "target",
    "focus",
    "mouseover",
    "tank",
    "healer",
    "maintank",
    "mainassist",
    "custom1",
    "custom2",
    "hover",
    "none",
};

local UNIT_FRAME_REACTIONS  = {
    "HELP",
    "HARM",
    "OTHER",
};

local UNIT_FRAME_TYPES      = {
    "PLAYER",
    "PET",
    "GROUP",
    "TARGET",
    "BOSS",
    "ARENA",
    "UNKNOWN",
};

DebouncePrivate.SORTED_UNIT_LIST = SORTED_UNIT_LIST;

-- UNIT_INFO는 UI 쪽 자산이고 이 파일보다 나중에 로드된다. 부를 때 꺼내온다.
local function GetUnitName(unit)
    local unitInfo = DebouncePrivate.DebounceUI.UNIT_INFO[unit];
    return unitInfo and unitInfo.name or unit;
end

--- [bonusbar:N] (변신 이름). 드롭다운과 툴팁이 같은 문자열을 써야 하므로 여기 있다.
local GetActionBarTypeLabel;
do
    local _bonusbarLabels;
    function GetActionBarTypeLabel(index)
        if (_bonusbarLabels == nil) then
            _bonusbarLabels = {
                [0] = LLL["DEFAULT"],
                [5] = GetFlyoutInfo(229),
            };
            if (Constants.PLAYER_CLASS == "DRUID") then
                _bonusbarLabels[1] = GetSpellNameAndIconID(768);
                _bonusbarLabels[3] = GetSpellNameAndIconID(5487);
                _bonusbarLabels[4] = GetSpellNameAndIconID(24858);
            elseif (Constants.PLAYER_CLASS == "ROGUE") then
                _bonusbarLabels[1] = GetSpellNameAndIconID(1784);
            end
            for i = 0, Constants.MAX_BONUS_ACTIONBAR_OFFSET do
                local text = _bonusbarLabels[i];
                _bonusbarLabels[i] = format("[bonusbar:%d]", i);
                if (text) then
                    _bonusbarLabels[i] = format("%s (%s)", _bonusbarLabels[i], text);
                end
            end
        end
        return _bonusbarLabels[index];
    end
end

local function GetShapeshiftFormLabel(formId)
    local shapeshiftName;
    if (formId == 0) then
        shapeshiftName = LLL["NO_SHAPESHIFT"];
    else
        local _, _, _, spellID = GetShapeshiftFormInfo(formId);
        shapeshiftName = spellID and GetSpellNameAndIconID(spellID) or nil;
    end
    if (shapeshiftName) then
        return format("[form:%d] (%s)", formId, shapeshiftName);
    end
    return format("[form:%d]", formId);
end

DebouncePrivate.GetActionBarTypeLabel = GetActionBarTypeLabel;
DebouncePrivate.GetShapeshiftFormLabel = GetShapeshiftFormLabel;

--------------------------------------------------------------------------------

local ConditionDescriptors = {};
local _byKey = {};

local function AddDescriptor(descriptor)
    tinsert(ConditionDescriptors, descriptor);
    _byKey[descriptor.key] = descriptor;
    return descriptor;
end

--- 켜짐/꺼짐/미설정 3-state. 조건 대부분이 이 모양이다.
local function AddTriStateDescriptor(key, labelKey, prefix)
    return AddDescriptor({
        key = key,
        label = LLL[labelKey],
        IsSet = function(_, action)
            return action[key] ~= nil;
        end,
        GetLines = function(_, action, out)
            out[#out + 1] = { text = action[key] == true and LLL[prefix .. "_YES"] or LLL[prefix .. "_NO"] };
        end,
        Clear = function(_, action)
            action[key] = nil;
        end,
    });
end

--- 비트마스크. 0이면 "아무것도 선택 안 됨"이 곧 오류다.
local function AddBitmaskDescriptor(key, labelKey, emptyErrorKey, firstBit, lastBit, GetBitLabel)
    return AddDescriptor({
        key = key,
        label = LLL[labelKey],
        IsSet = function(_, action)
            return action[key] ~= nil;
        end,
        GetLines = function(_, action, out)
            local value = action[key];
            if (value == 0) then
                out[#out + 1] = { text = LLL[emptyErrorKey], error = true, isDescriptorError = true };
                return;
            end
            for i = firstBit, lastBit do
                if (band(value, 2 ^ i) ~= 0) then
                    local text = GetBitLabel(i);
                    if (text) then
                        out[#out + 1] = { text = text };
                    end
                end
            end
        end,
        Clear = function(_, action)
            action[key] = nil;
        end,
    });
end

--
-- 순서는 툴팁이 그리던 순서 그대로다. 조건 탭도 이 순서로 나열한다.
--

AddDescriptor({
    key = "hover",
    label = LLL["CONDITION_HOVER"],
    IsSet = function(_, action)
        return action.hover ~= nil;
    end,
    GetSummary = function(_, action)
        return action.hover and LLL["CONDITION_HOVER_YES"] or LLL["CONDITION_HOVER_NO"];
    end,
    GetLines = function(_, action, out)
        if (not action.hover) then
            out[#out + 1] = { text = LLL["CONDITION_HOVER_NO"] };
            return;
        end

        local reactions = action.reactions or Constants.REACTION_ALL;
        local s;
        if (reactions == Constants.REACTION_ALL) then
            s = LLL["ALL"];
        elseif (reactions == 0) then
            s = LLL["NOT_SELECTED"];
        else
            s = "";
            for i = 1, #UNIT_FRAME_REACTIONS do
                local flag = Constants["REACTION_" .. UNIT_FRAME_REACTIONS[i]];
                if (band(reactions, flag) == flag) then
                    if (s ~= "") then
                        s = s .. ", ";
                    end
                    s = s .. LLL["REACTION_" .. UNIT_FRAME_REACTIONS[i]];
                end
            end
        end
        out[#out + 1] = {
            text = format("|cnWHITE_FONT_COLOR:%s:|r %s", LLL["CONDITION_REACTIONS"], s),
            error = GetBindingIssue(action, "reactions") and true or false,
            wrap = true,
        };

        local frameTypes = action.frameTypes or Constants.FRAMETYPE_ALL;
        if (frameTypes == Constants.FRAMETYPE_ALL) then
            s = LLL["ALL"];
        elseif (frameTypes == 0) then
            s = LLL["NOT_SELECTED"];
        else
            s = "";
            for i = 1, #UNIT_FRAME_TYPES do
                local flag = Constants["FRAMETYPE_" .. UNIT_FRAME_TYPES[i]];
                if (band(frameTypes, flag) == flag) then
                    if (s ~= "") then
                        s = s .. ", ";
                    end
                    s = s .. LLL["FRAMETYPE_" .. UNIT_FRAME_TYPES[i]];
                end
            end
        end
        out[#out + 1] = {
            text = format("|cnWHITE_FONT_COLOR:%s:|r %s", LLL["CONDITION_FRAMETYPES"], s),
            error = GetBindingIssue(action, "frameTypes") and true or false,
            wrap = true,
        };

        if (action.ignoreHoverUnit) then
            out[#out + 1] = { text = LLL["IGNORE_HOVER_UNIT"], error = false };
        end
    end,
    -- reactions/frameTypes/ignoreHoverUnit은 남긴다. 다시 켰을 때 하던 설정이 살아있는 게
    -- 맞고, 이 필드들은 hover가 없으면 아무 데서도 읽히지 않는다.
    Clear = function(_, action)
        action.hover = nil;
    end,
});

AddDescriptor({
    key = "checkedUnits",
    label = LLL["CONDITION_UNITS"],
    -- "@"(지정한 대상)는 대상이 있을 때만 뜻이 있다. 툴팁이 쓰던 규칙 그대로다.
    IsSet = function(_, action)
        if (not action.checkedUnits) then
            return false;
        end
        for checkedUnit in pairs(action.checkedUnits) do
            if (checkedUnit ~= "@" or (action.unit and action.unit ~= "none")) then
                return true;
            end
        end
        return false;
    end,
    GetLines = function(_, action, out)
        local checkedUnits = action.checkedUnits;
        if (not checkedUnits) then
            return;
        end

        local function addUnit(checkedUnit, unitStr)
            local value = checkedUnits[checkedUnit];
            local valueStr;
            if (value == true) then
                valueStr = LLL["CONDITION_UNIT_EXISTS"];
            elseif (value == "help") then
                valueStr = LLL["CONDITION_UNIT_HELP"];
            elseif (value == "harm") then
                valueStr = LLL["CONDITION_UNIT_HARM"];
            else
                valueStr = LLL["CONDITION_UNIT_DOES_NOT_EXIST"];
            end
            out[#out + 1] = { text = unitStr .. " - " .. valueStr };
        end

        if (checkedUnits["@"] ~= nil and action.unit and action.unit ~= "none") then
            addUnit("@", format(LLL["SELECTED_TARGET_UNIT"], GetUnitName(action.unit)));
        end
        for _, unit in ipairs(SORTED_UNIT_LIST) do
            if (checkedUnits[unit] ~= nil) then
                addUnit(unit, GetUnitName(unit));
            end
        end
    end,
    Clear = function(_, action)
        action.checkedUnits = nil;
    end,
});

local GROUP_LABEL_KEYS = { [0] = "GROUP_NONE", "GROUP_PARTY", "GROUP_RAID" };
AddBitmaskDescriptor("groups", "CONDITION_GROUP", "BINDING_ERROR_GROUPS_NONE_SELECTED", 0, 2, function(index)
    return LLL[GROUP_LABEL_KEYS[index]];
end);

AddTriStateDescriptor("combat", "CONDITION_COMBAT", "CONDITION_COMBAT");

AddTriStateDescriptor("stealth", "CONDITION_STEALTH", "CONDITION_STEALTH");

AddDescriptor({
    key = "known",
    label = LLL["CONDITION_KNOWN"],
    -- 주문에만 뜻이 있다. 메뉴도 true/nil만 만든다.
    IsAvailable = function(_, action)
        return action.type == Constants.SPELL;
    end,
    IsSet = function(_, action)
        return action.known and true or false;
    end,
    GetLines = function(_, action, out)
        out[#out + 1] = { text = LLL["CONDITION_KNOWN_YES"] };
    end,
    Clear = function(_, action)
        action.known = nil;
    end,
});

AddBitmaskDescriptor("forms", "CONDITION_SHAPESHIFT", "BINDING_ERROR_FORMS_NONE_SELECTED", 0, 10, GetShapeshiftFormLabel);

AddBitmaskDescriptor("bonusbars", "CONDITION_BONUSBAR", "BINDING_ERROR_BONUSBARS_NONE_SELECTED", 0,
    Constants.MAX_BONUS_ACTIONBAR_OFFSET, GetActionBarTypeLabel);

AddTriStateDescriptor("specialbar", "CONDITION_SPECIALBAR", "CONDITION_SPECIALBAR");

AddTriStateDescriptor("extrabar", "CONDITION_EXTRABAR", "CONDITION_EXTRABAR");

AddTriStateDescriptor("pet", "CONDITION_PET", "CONDITION_PET");

AddTriStateDescriptor("petbattle", "CONDITION_PETBATTLE", "CONDITION_PETBATTLE");

for stateIndex = 1, Constants.MAX_NUM_CUSTOM_STATES do
    local descriptor = AddTriStateDescriptor("$state" .. stateIndex, "CONDITION_CUSTOM_STATE", "CONDITION_CUSTOM_STATE");
    descriptor.label = format(LLL["CUSTOM_STATE_NUM"], stateIndex);
    descriptor.stateIndex = stateIndex;
end

--------------------------------------------------------------------------------

DebouncePrivate.ConditionDescriptors = ConditionDescriptors;

function DebouncePrivate.GetConditionDescriptor(key)
    return _byKey[key];
end

--- 편집 메뉴를 끼워 넣는다. 메뉴 빌더는 드롭다운 쪽에 있고(액션 업밸류에 기대고 있다)
--- 서술자는 그걸 부르기만 한다.
function DebouncePrivate.SetConditionMenuBuilder(key, builder)
    local descriptor = _byKey[key];
    if (descriptor) then
        descriptor.BuildMenu = builder;
    end
end

--- 한 줄 요약. 조건 탭의 행이 쓴다.
function DebouncePrivate.GetConditionSummary(descriptor, action)
    if (descriptor.GetSummary) then
        return descriptor:GetSummary(action);
    end

    local lines = {};
    descriptor:GetLines(action, lines);

    local texts = {};
    for i = 1, #lines do
        texts[i] = lines[i].text;
    end
    return table.concat(texts, ", ");
end
