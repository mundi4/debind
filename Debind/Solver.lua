local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

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
--
-- 네 값은 배타적이다 -- 런타임도 유닛 하나를 한 값으로 푼다
-- (`UpdateBindings.lua`의 unitStateExpression). 블리자드도 같은 자리를 if/elseif로 푼다
-- (`SecureTemplates.lua`의 `helpbutton`/`harmbutton` 치환). 우호와 적대가 동시에 참인
-- 상황이 확인되면 그때 이 축부터 다시 봐야 한다.
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
            elseif (action.key and DebindPrivate.GetMouseButtonAndPrefix(action.key)) then
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
local _keepCols = {};
local _covers = {};

-- 탐색 노드 수 상한. 넘으면 그 바인딩의 판정을 포기한다 -- 못 지우는 쪽이 안전한 실패다.
local MAX_NODES = 20000;

-- 마지막 CheckUnreachableBindings 호출의 통계.
-- 조용히 비싸지는 게 이 알고리즘의 유일한 실패 모드라서 밖에서 볼 수 있게 둔다.
local Stats = { nodes = 0, maxDepth = 0, gaveUp = false };
DebindPrivate.SolverStats = Stats;

-- 깊이별 작업 공간. 재귀가 깊어질 때만 늘어나고 재사용된다.
local _fragAt = {};      -- 만들고 있는 조각
local _prefixAt = {};    -- region ∩ O
local _liveAt = {};      -- 이 노드에서 아직 살아있는 커버들

local function scratch(pool, depth)
    local t = pool[depth];
    if (t == nil) then
        t = {};
        pool[depth] = t;
    end
    return t;
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
--- `region`이 커버들의 합집합에 완전히 덮이는가?
---
--- 잔여 집합을 만들어놓고 비었는지 보는 대신, 덮이지 않은 점을 **하나 찾으면 즉시 끝낸다.**
--- 대부분의 바인딩은 도달 가능하므로 흔한 경우가 곧 빨리 끝나는 경우가 된다.
--- 잔여를 전부 만들면 정반대였다 -- 도달 가능한 바인딩이 제일 비쌌음.
---
--- 각 노드에서:
---   1. region과 만나지 않는 커버를 버린다. 남는 게 없으면 반례를 찾은 것.
---   2. region을 통째로 덮는 커버가 있으면 이 가지는 끝.
---   3. 커버 O 하나를 골라 region \ O를 서로소 조각들로 쪼개고 각각 재귀한다.
---      조각들은 O와 만나지 않으므로 **O를 커버 목록에서 뺀 채로** 내려간다.
---
--- 쪼개지는 개수가 가장 적은 커버를 고른다 -- 가지치기가 가장 센 선택.
---
local _nodeBudget = 0;
local _gaveUp = false;

local function isCovered(region, covers, coverCount, depth)
    if (_nodeBudget <= 0) then
        _gaveUp = true;
        return false;   -- 포기 = "안 덮임" = 바인딩을 남긴다
    end
    _nodeBudget = _nodeBudget - 1;

    if (depth > Stats.maxDepth) then
        Stats.maxDepth = depth;
    end

    local live = scratch(_liveAt, depth);
    local liveCount = 0;
    local best, bestPieces;

    for i = 1, coverCount do
        local other = covers[i];
        local intersects = true;
        local pieces = 0;

        for col = 1, _numColumns do
            local value = region[col];
            if (band(value, other[col]) == 0) then
                -- 이 축에서 분리 -> 곱공간 전체에서 분리
                intersects = false;
                break;
            end
            if (band(value, bnot(other[col])) ~= 0) then
                pieces = pieces + 1;
            end
        end

        if (intersects) then
            if (pieces == 0) then
                return true;    -- region ⊆ other
            end
            liveCount = liveCount + 1;
            live[liveCount] = other;
            if (best == nil or pieces < bestPieces) then
                best = liveCount;
                bestPieces = pieces;
            end
        end
    end

    if (liveCount == 0) then
        return false;   -- 아무도 안 덮는 영역이 남음 = 반례
    end

    local other = live[best];
    live[best] = live[liveCount];
    liveCount = liveCount - 1;

    local prefix = scratch(_prefixAt, depth);
    for col = 1, _numColumns do
        prefix[col] = band(region[col], other[col]);
    end

    local frag = scratch(_fragAt, depth);

    for split = 1, _numColumns do
        local remaining = band(region[split], bnot(other[split]));
        if (remaining ~= 0) then
            -- 앞쪽을 교집합으로 눌러서 조각들을 서로소로 만든다
            for col = 1, split - 1 do
                frag[col] = prefix[col];
            end
            frag[split] = remaining;
            for col = split + 1, _numColumns do
                frag[col] = region[col];
            end

            if (not isCovered(frag, live, liveCount, depth + 1)) then
                return false;
            end
        end
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

function DebindPrivate.CheckUnreachableBindings(bindings)
    Stats.nodes = 0;
    Stats.maxDepth = 0;
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
            local coverCount = 0;
            for j = 1, i - 1 do
                local other = bindings[j];
                if (not _opaque[other]) then
                    coverCount = coverCount + 1;
                    _covers[coverCount] = _conditionsMap[other];
                end
            end

            if (coverCount > 0) then
                _nodeBudget = MAX_NODES;
                _gaveUp = false;

                unreachable = isCovered(_conditionsMap[binding], _covers, coverCount, 1);

                Stats.nodes = Stats.nodes + (MAX_NODES - _nodeBudget);
                if (_gaveUp) then
                    Stats.gaveUp = true;
                    unreachable = false;
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
end

function DebindPrivate.IsUnreachableAction(action)
    local binding = DebindPrivate.GetBindingInfoForAction(action);
    return UnreachableBindingCache[binding];
end

function DebindPrivate.ClearUnreachableBindingCache()
    wipe(UnreachableBindingCache);
end
