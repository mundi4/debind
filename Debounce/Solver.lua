local _, DebouncePrivate = ...;
local Constants = DebouncePrivate.Constants;

local MAX_NUM_CUSTOM_STATES = Constants.MAX_NUM_CUSTOM_STATES;

local band, bnot = bit.band, bit.bnot;
local tremove, wipe = tremove, wipe;
local pairs, type = pairs, type;

--[[
    도달불가 바인딩 검출.

    같은 키에 걸린 바인딩들을 우선순위 순으로 훑으면서, 어떤 바인딩이 위쪽
    바인딩들에 완전히 덮이면(= 절대 발동할 수 없으면) 제거한다.

    모델: 각 바인딩의 조건은 조건 공간의 '상자' 하나. 상자는 컬럼(축)의 배열이고
    컬럼 값은 그 축에서 허용되는 값들의 비트마스크다.

    핵심 불변식: **한 컬럼은 정확히 한 축이어야 한다.**
    band/bnot 기반 집합 연산은 컬럼 안의 비트들이 서로 배타적일 때만 성립한다.
    독립적인 축(커스텀 상태 5개, 유닛 각각, known 주문 각각)을 한 워드에 접으면
    "어느 한 축에서 분리 -> 전체 분리"가 "모든 축에서 분리"로 바뀌어 무너진다.
    그래서 유닛/known 컬럼은 키마다 동적으로 생성한다.
]]

-- 커스텀 상태 축: on / off
local STATE_ON, STATE_OFF = 1, 2;
local STATE_ANY = STATE_ON + STATE_OFF;

-- known 축: 앎 / 모름
local KNOWN_YES, KNOWN_NO = 1, 2;
local KNOWN_ANY = KNOWN_YES + KNOWN_NO;

-- 유닛 축: 존재하지만 우호/적대 아님 / 우호 / 적대 / 존재하지 않음
local UNIT_OTHER, UNIT_HELP, UNIT_HARM, UNIT_NONE = 1, 2, 4, 8;
local UNIT_EXISTS = UNIT_OTHER + UNIT_HELP + UNIT_HARM;
local UNIT_ANY = UNIT_EXISTS + UNIT_NONE;

local function flagsToConditionFlags(value, max)
    if (value) then
        return value;
    else
        return (2 ^ (max + 1)) - 1;
    end
end

local function boolToConditionFlags(value)
    if (value == nil) then
        return 3;
    end
    return value and 1 or 2;
end

--- 축이 하나뿐인 컬럼들. 순서는 상관없음.
local FIXED_COLUMNS = {
    {
        name = "hover",
        make = function(action)
            if (action.hover) then
                return band(action.reactions or Constants.REACTION_ALL, Constants.REACTION_ALL);
            elseif (action.hover == false) then
                return Constants.REACTION_NONE;
            elseif (action.key and DebouncePrivate.GetMouseButtonAndPrefix(action.key)) then
                return Constants.REACTION_NONE;
            else
                return Constants.REACTION_ALL + Constants.REACTION_NONE;
            end
        end
    },
    {
        name = "frameTypes",
        make = function(action)
            return flagsToConditionFlags(action.frameTypes, 6);
        end
    },
    {
        name = "groups",
        make = function(action)
            return flagsToConditionFlags(action.groups, 2);
        end
    },
    {
        name = "bonusbars",
        make = function(action)
            return flagsToConditionFlags(action.bonusbars, 5);
        end
    },
    {
        name = "forms",
        make = function(action)
            return flagsToConditionFlags(action.forms, 10);
        end
    },
    {
        name = "specialbar",
        make = function(action)
            return boolToConditionFlags(action.specialbar);
        end
    },
    {
        name = "extrabar",
        make = function(action)
            return boolToConditionFlags(action.extrabar);
        end
    },
    {
        name = "combat",
        make = function(action)
            return boolToConditionFlags(action.combat);
        end
    },
    {
        name = "stealth",
        make = function(action)
            return boolToConditionFlags(action.stealth);
        end
    },
    {
        name = "pet",
        make = function(action)
            return boolToConditionFlags(action.pet);
        end
    },
    {
        name = "petbattle",
        make = function(action)
            return boolToConditionFlags(action.petbattle);
        end
    },
};

local function makeCustomStateFlags(action, index)
    local value = action["$state" .. index];
    if (value == nil) then
        return STATE_ANY;
    end
    return value and STATE_ON or STATE_OFF;
end

local function unitConditionToFlags(value)
    if (value == true) then
        return UNIT_EXISTS;
    elseif (value == "help") then
        return UNIT_HELP;
    elseif (value == "harm") then
        return UNIT_HARM;
    else
        return UNIT_NONE;
    end
end

local function makeUnitFlags(action, unit)
    local checkedUnits = action.checkedUnits;
    if (not checkedUnits) then
        return UNIT_ANY;
    end

    local flags = UNIT_ANY;

    local value = checkedUnits[unit];
    if (value ~= nil) then
        flags = band(flags, unitConditionToFlags(value));
    end

    -- "@"는 이 액션 자신의 대상 유닛을 가리킴. 같은 축에 걸리므로 교집합.
    if (action.unit == unit) then
        local atValue = checkedUnits["@"];
        if (atValue ~= nil) then
            flags = band(flags, unitConditionToFlags(atValue));
        end
    end

    return flags;
end

local function makeKnownFlags(action, spellValue)
    if (action.known ~= nil and action.type == Constants.SPELL and action.value == spellValue) then
        return action.known and KNOWN_YES or KNOWN_NO;
    end
    return KNOWN_ANY;
end

local UnreachableBindingCache = {};

local _colMake = {};
local _colArg = {};
local _numColumns = 0;

local _unitSeen = {};
local _knownSeen = {};
local _opaque = {};
local _conditionsMap = {};
local _tempFlags = {};
local _prefixFlags = {};
local _keepCols = {};

-- 잔여 상자 개수 상한. 서로소 분해라 현실적인 조건 집합에서는 격자 칸 수로
-- 묶이지만, 축 하나에 서로 다른 마스크가 잔뜩 붙는 경우까지 막지는 못한다.
-- 넘으면 판정을 포기한다 -- 못 지우는 쪽이 안전한 실패다.
local MAX_BOXES = 2048;

-- 상자가 한 번 크게 불어난 뒤 버퍼가 계속 물고 있지 않도록 되돌릴 지점.
local KEEP_ROWS = 64;

-- 마지막 CheckUnreachableBindings 호출의 통계.
-- maxBoxes가 조용히 커지는 게 이 알고리즘의 유일한 실패 모드라서 밖에서 볼 수 있게 둔다.
local Stats = { maxBoxes = 0, gaveUp = false };
DebouncePrivate.SolverStats = Stats;

-- removeConditions는 읽기 버퍼와 쓰기 버퍼를 번갈아 쓴다.
-- 한 상자가 여러 조각으로 쪼개질 수 있어서 제자리 압축이 불가능하기 때문.
local _listA = { n = 0 };
local _listB = { n = 0 };
local _currentList = _listA;

local function setConditions(tbl, pos, conditions)
    local row = tbl[pos];
    if (row == nil) then
        row = {};
        tbl[pos] = row;
    end
    for col = 1, _numColumns do
        row[col] = conditions[col];
    end
    row[_numColumns + 1] = nil;
    return row;
end

--- A \ O의 splitCol번째 조각:
---   (A_1 ∩ O_1, ..., A_{d-1} ∩ O_{d-1}, A_d \ O_d, A_{d+1}, ..., A_n)
--- 앞쪽을 교집합으로 눌러두면 조각들이 서로소가 된다.
local function setFragment(tbl, pos, conditions, splitCol)
    local row = tbl[pos];
    if (row == nil) then
        row = {};
        tbl[pos] = row;
    end
    for col = 1, splitCol - 1 do
        row[col] = _prefixFlags[col];
    end
    row[splitCol] = _tempFlags[splitCol];
    for col = splitCol + 1, _numColumns do
        row[col] = conditions[col];
    end
    row[_numColumns + 1] = nil;
    return row;
end

---
--- 이 키에 걸린 바인딩들이 실제로 쓰는 축만으로 컬럼 배치를 만든다.
--- 조건이 걸리지 않은 축은 컬럼이 없고, 있으면 "조건 없음 = 전체 비트"가 된다.
---
local function buildLayout(bindings)
    _numColumns = 0;
    wipe(_unitSeen);
    wipe(_knownSeen);
    wipe(_opaque);

    for i = 1, #FIXED_COLUMNS do
        _numColumns = _numColumns + 1;
        _colMake[_numColumns] = FIXED_COLUMNS[i].make;
        _colArg[_numColumns] = nil;
    end

    for i = 1, MAX_NUM_CUSTOM_STATES do
        _numColumns = _numColumns + 1;
        _colMake[_numColumns] = makeCustomStateFlags;
        _colArg[_numColumns] = i;
    end

    for i = 1, #bindings do
        local binding = bindings[i];

        local checkedUnits = binding.checkedUnits;
        if (checkedUnits) then
            for key in pairs(checkedUnits) do
                local unit = key;
                if (key == "@") then
                    unit = binding.unit;
                    if (type(unit) ~= "string" or unit == "") then
                        -- "@"를 어느 축에 걸어야 할지 모름. 조건을 통째로 무시하면
                        -- 이 바인딩이 실제보다 넓어 보여서 남을 잘못 덮는다.
                        _opaque[binding] = true;
                        unit = nil;
                    end
                end

                if (unit and not _unitSeen[unit]) then
                    _unitSeen[unit] = true;
                    _numColumns = _numColumns + 1;
                    _colMake[_numColumns] = makeUnitFlags;
                    _colArg[_numColumns] = unit;
                end
            end
        end

        if (binding.known ~= nil) then
            if (binding.type == Constants.SPELL and binding.value ~= nil) then
                if (not _knownSeen[binding.value]) then
                    _knownSeen[binding.value] = true;
                    _numColumns = _numColumns + 1;
                    _colMake[_numColumns] = makeKnownFlags;
                    _colArg[_numColumns] = binding.value;
                end
            else
                _opaque[binding] = true;
            end
        end
    end

    _colMake[_numColumns + 1] = nil;
    _colArg[_numColumns + 1] = nil;
end

local function buildConditionSet(action, dest)
    for i = 1, _numColumns do
        dest[i] = _colMake[i](action, _colArg[i]);
    end
    dest[_numColumns + 1] = nil;
    return dest;
end

---
--- 현재 남아있는 상자들에서 `other` 상자를 뺀다.
---
--- 조각을 앞쪽 교집합으로 눌러서 만들면(setFragment) 조각들이 **서로소**가 되고,
--- 잔여 집합은 축들이 만드는 격자의 칸 수를 넘지 못한다.
--- 겹치는 합집합으로 만들면 같은 영역이 중복 표현되면서 상한이 사라진다 --
--- 바인딩 18개짜리 키에서 상자가 2,000개 가까이 불어나는 걸 확인함.
---
--- 상한을 넘으면 false를 돌려주고 호출자가 판정을 포기한다.
---
local function removeConditions(other)
    local src = _currentList;
    if (src.n == 0) then
        return true;
    end

    local dest = (src == _listA) and _listB or _listA;
    local destN = 0;

    for row = 1, src.n do
        local conditions = src[row];
        local overlaps = true;
        local isSubset = true;

        for col = 1, _numColumns do
            local common = band(conditions[col], other[col]);
            if (common == 0) then
                -- 이 축에서 두 상자가 만나지 않음 -> 곱공간 전체에서 분리. 뺄 것 없음.
                overlaps = false;
                break;
            end

            _prefixFlags[col] = common;

            local remaining = band(conditions[col], bnot(other[col]));
            _tempFlags[col] = remaining;
            if (remaining ~= 0) then
                isSubset = false;
            end
        end

        if (not overlaps) then
            destN = destN + 1;
            if (destN > MAX_BOXES) then
                return false;
            end
            setConditions(dest, destN, conditions);
        elseif (not isSubset) then
            for col = 1, _numColumns do
                if (_tempFlags[col] ~= 0) then
                    destN = destN + 1;
                    if (destN > MAX_BOXES) then
                        return false;
                    end
                    setFragment(dest, destN, conditions, col);
                end
            end
        end
        -- isSubset이면 A가 O에 통째로 덮임 -> 남는 조각 없음
    end

    dest.n = destN;
    _currentList = dest;
    if (destN > Stats.maxBoxes) then
        Stats.maxBoxes = destN;
    end
    return true;
end

---
--- 모든 바인딩이 같은 값을 갖는 컬럼은 버린다.
---
--- 그런 컬럼에서는 A \ O = v \ v = 0이라 조각을 만들 일이 없고,
--- v ~= 0이므로 분리 판정에 걸릴 일도 없다. 즉 아무 일도 안 하면서
--- 안쪽 루프만 늘린다. 실제 프로필에서는 컬럼 25개 중 20개 가까이가 여기 해당.
---
--- (v == 0인 컬럼은 남긴다 -- 퇴화 상자를 없애버리면 판정이 바뀐다)
---
local function pruneConstantColumns(bindings)
    local count = #bindings;
    local kept = 0;

    for col = 1, _numColumns do
        local value = _conditionsMap[bindings[1]][col];
        local constant = (value ~= 0);
        if (constant) then
            for i = 2, count do
                if (_conditionsMap[bindings[i]][col] ~= value) then
                    constant = false;
                    break;
                end
            end
        end
        if (not constant) then
            kept = kept + 1;
            _keepCols[kept] = col;
        end
    end

    if (kept == _numColumns) then
        return;
    end

    -- _keepCols[k] >= k 이므로 제자리 압축이 안전하다.
    for i = 1, count do
        local conditions = _conditionsMap[bindings[i]];
        for k = 1, kept do
            conditions[k] = conditions[_keepCols[k]];
        end
        conditions[kept + 1] = nil;
    end

    _numColumns = kept;
end

--- 한 번 크게 불어난 버퍼를 계속 물고 있지 않게 한다.
--- (BuildKeyMap은 키마다 이걸 부르므로 테이블을 새로 만들지 않는다)
local function trimList(list)
    local i = KEEP_ROWS + 1;
    while (list[i] ~= nil) do
        list[i] = nil;
        i = i + 1;
    end
end

function DebouncePrivate.CheckUnreachableBindings(bindings)
    Stats.maxBoxes = 0;
    Stats.gaveUp = false;

    if (#bindings < 2) then
        return;
    end

    buildLayout(bindings);

    for i = 1, #bindings do
        local binding = bindings[i];
        _conditionsMap[binding] = buildConditionSet(binding, {});
    end

    pruneConstantColumns(bindings);

    local i = 1;
    while (i <= #bindings) do
        local binding = bindings[i];
        local unreachable = false;

        if (i > 1 and not _opaque[binding]) then
            _currentList = _listA;
            setConditions(_listA, 1, _conditionsMap[binding]);
            _listA.n = 1;

            for j = 1, i - 1 do
                local other = bindings[j];
                if (not _opaque[other]) then
                    if (not removeConditions(_conditionsMap[other])) then
                        -- 상자가 상한을 넘음. 판정 포기 -- 안 지우는 쪽이 안전하다.
                        Stats.gaveUp = true;
                        unreachable = false;
                        break;
                    end
                    if (_currentList.n == 0) then
                        unreachable = true;
                        break;
                    end
                end
            end
        end

        if (unreachable) then
            UnreachableBindingCache[binding] = true;
            tremove(bindings, i);
        else
            i = i + 1;
        end
    end

    wipe(_conditionsMap);
    trimList(_listA);
    trimList(_listB);
end

function DebouncePrivate.IsUnreachableAction(action)
    local binding = DebouncePrivate.GetBindingInfoForAction(action);
    return UnreachableBindingCache[binding];
end

function DebouncePrivate.ClearUnreachableBindingCache()
    wipe(UnreachableBindingCache);
end
