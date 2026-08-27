local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

local IsSwitchName = Constants.IsSwitchName;

local band, bnot = bit.band, bit.bnot;
local tremove, wipe = tremove, wipe;
local pairs = pairs;

--[[
    도달불가 바인딩 검출.

    2024년에 노트 펴고 끙끙대며 도출한 알고리즘을 계승했다. 2024-02-04 첫 커밋의
    `CheckUnreachableBindings`(당시 `Debounce.lua`)가 그 원형이다.

    같은 키에 걸린 바인딩들을 순서대로 훑으면서, 어떤 바인딩이 위쪽
    바인딩들에 완전히 덮이면(= 절대 발동할 수 없으면) 제거한다.

    모델: 각 바인딩의 조건은 조건 공간의 '상자' 하나. 상자는 컬럼(축)의 배열이고
    컬럼 값은 그 축에서 허용되는 값들의 비트마스크다.

    핵심 불변식: **한 컬럼은 정확히 한 축이어야 한다.**
    band/bnot 기반 집합 연산은 컬럼 안의 비트들이 서로 배타적일 때만 성립한다.
    독립적인 축(커스텀 상태 각각, 유닛 각각, known 주문 각각)을 한 워드에 접으면
    "어느 한 축에서 분리 -> 전체 분리"가 "모든 축에서 분리"로 바뀌어 무너진다.
    그래서 유닛/known/커스텀 상태 컬럼은 키마다 동적으로 생성한다.

    Stated exactly, because two halves of that invariant keep getting mistaken for one
    another:

      - **Inside a column**, the bits must partition the runtime state space. Exclusive, so
        that `band(a, b) == 0` really means disjoint; and exhaustive, so that `bnot` really
        means complement and the split really covers all of `region \ O`. A runtime state
        lights exactly one bit of every column.

        Several axes are exclusive only because **an ordered chain makes them so**, and no
        chain lives here. Group membership overlaps in reality -- a raid member is also in a
        party -- and comes out single-valued because the chain asks about raid first. Reaction
        is the same shape (assist, then attack, then other; Blizzard asks the other way round,
        and that file says so). Reorder one of those and this column stops being a partition
        without anything here noticing.

        Each chain is written twice, once for the poll and once for the click, and the two have
        to stay in the same order as each other as well as in this one:

          group      `Constants.STATE_EVAL_EXPRESSIONS` and `SecureBindings.lua`'s
                     `EVAL_SNIPPET`. `check:state-eval` holds those two together, and that is
                     the only check anywhere near either invariant
          reaction   `UpdateBindings.lua` emits both the state loop's line and the hover poll's;
                     `SecureBindings.lua` carries the click path and `setup_onenter`

      - **Across columns**, independence is not required. Correlated columns -- target and
        targettarget, combat and form -- leave points in the product space that cannot
        happen, and a point that cannot happen simply goes uncovered and keeps a binding.
        That is the safe direction. Do not "fix" a correlation.

    Merging two axes into one column is sound as a **product** (one bit per combination,
    still a partition) and fatal as a **union** (bits laid side by side), which is the
    collapse above. A product costs bits multiplicatively and buys nothing that separate
    columns do not already give -- except the one thing separate columns cannot express: a
    set that is not a rectangle. "The unit is absent, or present and alive" is that set,
    which is why a unit's existence and its other properties share one column.

    A box is used as **both** region and cover, so its mask has to be exact in both
    directions. Too narrow and the binding is deleted as a region; too wide and it deletes
    others as a cover. There is no safe direction to round toward -- which is why a
    condition that cannot be placed on an axis makes the binding `_opaque`, out of both
    roles, rather than being ignored.
]]

-- 커스텀 상태 축: on / off
local STATE_ON, STATE_OFF = 1, 2;
local STATE_ANY = STATE_ON + STATE_OFF;

-- known 축: 앎 / 모름
local KNOWN_YES, KNOWN_NO = 1, 2;
local KNOWN_ANY = KNOWN_YES + KNOWN_NO;

-- 유닛 축은 `Constants.UNITSTATE_*`. 값들이 배타적이라는 것이 이 컬럼의 전제고, 런타임도
-- 유닛 하나를 한 값으로 푼다 (`UpdateBindings.lua`의 unitStateExpression). 블리자드도 같은
-- 자리를 if/elseif로 푼다 (`SecureTemplates.lua`의 `helpbutton`/`harmbutton` 치환).
--
-- The mask itself is built in `Misc.lua` (BuildUnitStates), which is also where the hover
-- condition is folded in -- the hovered frame's unit is a unit named "hover", so it belongs on
-- this axis rather than in a column of its own.

-- `max` is the exhaustive half of the column invariant: it has to name every value the game
-- can produce on this axis. One index past it and "no condition" stops standing for the whole
-- space, boxes come out narrower than the conditions they represent, and bindings that can
-- still fire get deleted.
--
-- **Padding it is not the safe move.** A value the game cannot produce is a point no cover
-- ever reaches, so it sits there uncovered: put one binding per form on a key plus one with no
-- form condition, and the last one stops being deleted because it alone spans the phantoms.
-- The number has to be right, not generous.
--
-- Right today, with the margins written down so this does not get re-derived:
--   forms 10      -- `GetNumShapeshiftForms()`. Druid has the most and is nowhere near it;
--                    Blizzard's own edit-mode placeholder is 10 (`StanceBar.lua:32`).
--   bonusbars 5   -- `GetBonusBarOffset()`, a fixed set. Shapeshift and stance bars plus
--                    skyriding at 5, which `DropDownMenus.lua` names from flyout 229.
--                    Not the vehicle/possess/override bars -- those are `specialbar`.
--   groups 2      -- none/party/raid. Cannot grow.
--   frameTypes 6  -- ours, not the game's (`FrameRegistry.lua`). Grows only if we grow it,
--                    and `FRAMETYPE_ALL` is checked against the spec's point space.
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
        -- Hover-dependent axes carry no condition off the hover path: with nothing hovered
        -- there is no frame to have a type. Returning the full mask there is what keeps this
        -- column free -- every cover that reaches the not-hovering point reaches it for all
        -- seven frame types at once, so the point never splits across covers.
        --
        -- `Misc.lua` already nils the field for non-hover bindings; reading `hover` here is
        -- what stops that from being a cross-file assumption.
        name = "frameTypes",
        make = function(binding)
            if (not binding.hover) then
                return flagsToConditionFlags(nil, 6);
            end
            return flagsToConditionFlags(binding.conditions.frameTypes, 6);
        end
    },
    {
        name = "groups",
        make = function(binding)
            return flagsToConditionFlags(binding.conditions.groups, 2);
        end
    },
    {
        name = "bonusbars",
        make = function(binding)
            return flagsToConditionFlags(binding.conditions.bonusbars, 5);
        end
    },
    {
        name = "forms",
        make = function(binding)
            return flagsToConditionFlags(binding.conditions.forms, 10);
        end
    },
    {
        name = "specialbar",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.specialbar);
        end
    },
    {
        name = "extrabar",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.extrabar);
        end
    },
    {
        name = "combat",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.combat);
        end
    },
    {
        name = "stealth",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.stealth);
        end
    },
    {
        name = "pet",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.pet);
        end
    },
    {
        name = "petbattle",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.petbattle);
        end
    },
    {
        name = "mounted",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.mounted);
        end
    },
    {
        name = "indoors",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.indoors);
        end
    },
    {
        name = "flyable",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.flyable);
        end
    },
    {
        name = "advflyable",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.advflyable);
        end
    },
    -- **Correlated with `bonusbars`, and left that way on purpose.** Both read
    -- `GetBonusBarOffset()`, so the product space holds points the game cannot reach -- skyriding
    -- true beside an offset that is not 5. That is the direction the header calls safe: an
    -- unreachable point goes uncovered and keeps a binding rather than deleting one. Do not merge
    -- the two into a column.
    {
        name = "skyriding",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.skyriding);
        end
    },
};

-- **컬럼의 인자가 이름이다.** 다섯 번호를 도는 루프였고 컬럼마다 번호를 들고 있었다. 스위치
-- 이름이 자유로워지면 번호로 가리킬 수 없는 이름이 조건에 앉는데, 그런 이름에 컬럼을 안
-- 만들면 그 조건이 솔버에게 안 보인다 - 상자가 조건 공간 전체가 되어 같은 키의 아래
-- 바인딩들을 전부 덮고, 사용자가 건 것들이 지워진다.
local function makeSwitchFlags(binding, name)
    local value = binding.conditions[name];
    if (value == nil) then
        return STATE_ANY;
    end
    return value and STATE_ON or STATE_OFF;
end

local function makeUnitFlags(binding, unit)
    local states = binding.unitStates;
    local mask = states and states[unit];
    if (mask == nil) then
        return Constants.UNITSTATE_ALL;
    end
    return mask;
end

local function makeKnownFlags(binding, spellValue)
    local known = binding.conditions.known;
    if (known ~= nil and binding.type == Constants.SPELL and binding.value == spellValue) then
        return known and KNOWN_YES or KNOWN_NO;
    end
    return KNOWN_ANY;
end

local UnreachableBindingCache = {};

local _colMake = {};
local _colArg = {};
local _numColumns = 0;

local _unitSeen = {};
local _knownSeen = {};
local _stateSeen = {};
local _opaque = {};
local _conditionsMap = {};
local _keepCols = {};
local _covers = {};

-- 탐색 비용 상한. 넘으면 그 바인딩의 판정을 포기한다 -- 못 지우는 쪽이 안전한 실패다.
--
-- **단위는 노드가 아니라 `노드 x 커버 수 x 컬럼 수`다.** 노드 하나가 살아있는 커버를 전부,
-- 그 안에서 컬럼을 전부 훑기 때문이다. 노드로 재면 컬럼이 넓거나 커버가 많은 키에서 같은
-- 예산이 훨씬 오래 걸리고, 그러면 이 상한이 막으라고 있는 바로 그것을 못 막는다.
--
-- 상한이 둘인 이유: 바인딩당 예산만 두면 **호출 전체가 안 묶인다.** 프레임을 멈추는 단위는
-- 한 바인딩의 판정이 아니라 `CheckUnreachableBindings` 한 번이고, 그건 그 키의 바인딩 수만큼
-- 곱해진다. 호출 예산이 그 곱을 자른다.
--
-- 값은 벤치에서 잡았다(`tests/bench.lua`, Lua 5.4 로컬):
--   바인딩 하나가 쓰는 최악    3,104   (40개 / 밀도 0.4)
--   호출 하나가 쓰는 최악     30,078   (같은 칸)
--   대략 4,600 비용 = 1ms
-- 한 자릿수 여유를 두되, 넘으면 잃는 것이 "덜 지운다"뿐이라 넉넉하게 잡을 이유도 없다.
-- CI는 5.1이라 같은 비용이 더 걸린다 -- 비례하므로 상한은 그대로 두고 시간만 다르게 읽는다.
local MAX_WORK      = 30000;
local MAX_CALL_WORK = 150000;

-- 마지막 CheckUnreachableBindings 호출의 통계.
-- 조용히 비싸지는 게 이 알고리즘의 유일한 실패 모드라서 밖에서 볼 수 있게 둔다.
--
-- `nodes` counts search nodes; `work` counts what they cost. A node walks every live cover
-- across every column, so on a wide layout the two diverge by two orders of magnitude -- 342
-- nodes taking 21ms was what made that obvious. The budget is spent in `work`. `nodes` stays
-- because "deep" and "wide" are different diagnoses and the fix differs.
local Stats = { nodes = 0, work = 0, maxWork = 0, maxDepth = 0, gaveUp = false };
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
    wipe(_stateSeen);
    wipe(_opaque);

    for i = 1, #FIXED_COLUMNS do
        _numColumns = _numColumns + 1;
        _colMake[_numColumns] = FIXED_COLUMNS[i].make;
        _colArg[_numColumns] = nil;
    end

    for i = 1, #bindings do
        local binding = bindings[i];

        -- `"@"`가 어느 축에 걸리는지 못 정한 바인딩. 조건을 통째로 무시하면 실제보다 넓어
        -- 보여서 남을 잘못 덮는다.
        if (binding.unitStatesOpaque) then
            _opaque[binding] = true;
        end

        local states = binding.unitStates;
        if (states) then
            for unit in pairs(states) do
                if (not _unitSeen[unit]) then
                    _unitSeen[unit] = true;
                    _numColumns = _numColumns + 1;
                    _colMake[_numColumns] = makeUnitFlags;
                    _colArg[_numColumns] = unit;
                end
            end
        end

        local conditions = binding.conditions;

        for name in pairs(conditions) do
            if (not _stateSeen[name] and IsSwitchName(name)) then
                _stateSeen[name] = true;
                _numColumns = _numColumns + 1;
                _colMake[_numColumns] = makeSwitchFlags;
                _colArg[_numColumns] = name;
            end
        end

        if (conditions.known ~= nil) then
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

local function buildConditionSet(binding, dest)
    for i = 1, _numColumns do
        dest[i] = _colMake[i](binding, _colArg[i]);
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
--- A degenerate box -- some column at 0, meaning the condition can never hold -- falls out of
--- both roles on the disjointness test, which is the right answer either way: as a region it
--- meets no cover and survives, as a cover it meets no region and deletes nothing. Strictly
--- such a binding *is* unreachable and could be dropped, but a silent deletion and a warning
--- are different products, and the warning is `GetBindingIssue`'s.
---
--- That filter runs before this one (`Debind.lua` builds KeyMap from issue-free actions only),
--- so a degenerate box should not arrive here at all. The behaviour above is a backstop, and
--- it is one on purpose: assuming an upstream filter held is the shape of coupling this file
--- has been bitten by before.
---
local _workBudget = 0;
local _nodeCount = 0;
local _gaveUp = false;

local function isCovered(region, covers, coverCount, depth)
    if (_workBudget <= 0) then
        _gaveUp = true;
        return false;   -- 포기 = "안 덮임" = 바인딩을 남긴다
    end
    -- 이 노드가 치를 값. 살아있는 커버를 전부, 그 안에서 컬럼을 전부 훑으므로 곱이다.
    -- 노드 수만 세면 커버가 늘거나 컬럼이 넓어지는 것을 예산이 못 본다 -- 실제로 342노드가
    -- 21ms인 것을 노드 수로는 설명할 수 없었다.
    _workBudget = _workBudget - coverCount * _numColumns;
    _nodeCount = _nodeCount + 1;

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
    Stats.work = 0;
    Stats.maxWork = 0;
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

    local callBudget = MAX_CALL_WORK;

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

            if (coverCount > 0 and callBudget > 0) then
                -- 남은 호출 예산보다 크게 주지 않는다. 그래야 바인딩 하나가 아니라 이 호출이
                -- 묶인다 -- 프레임을 멈추는 단위가 호출이다.
                local granted = MAX_WORK;
                if (granted > callBudget) then
                    granted = callBudget;
                end
                _workBudget = granted;
                _nodeCount = 0;
                _gaveUp = false;

                unreachable = isCovered(_conditionsMap[binding], _covers, coverCount, 1);

                local spent = granted - _workBudget;
                callBudget = callBudget - spent;
                Stats.nodes = Stats.nodes + _nodeCount;
                Stats.work = Stats.work + spent;
                if (spent > Stats.maxWork) then Stats.maxWork = spent; end
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

--- A record with no conditions at all: every column comes out full, so its box is the whole
--- space. Appending it to a sorted key and asking whether it is reachable asks exactly "do the
--- records before it cover everything?".
---
--- **The empty conditions table is not decoration.** This record goes through `buildLayout` and
--- `buildConditionSet` beside the real ones, and both reach straight into `binding.conditions`.
--- A real binding always has that table (`Misc.lua` rebuilds it in place), so nothing guards the
--- read; leaving it off here is the one record that would be missing it.
local _sentinel = { conditions = {} };
local _sentinelArray = {};

--- Is this key ours no matter what the state does?
---
--- The answer is yes when nothing that would hand the key back is reachable. Two kinds do that:
--- a reachable `UNUSED` (we release the key) or a reachable `COMMAND` (we bind it with
--- `SetBinding`, not a click). And the sentinel stands for the case nobody wrote down -- the
--- state where no record matches at all, which also hands the key back.
---
--- **This subsumes the syntactic test it replaces.** `IsKeyAlwaysClickBound` walked for an
--- unconditional non-click record and gave up at the first `UNUSED`/`COMMAND`; if such a record
--- exists at position k, the sentinel is covered by it, every `UNUSED`/`COMMAND` after k is
--- covered too, and any before k is not -- the same three answers. What is new is the key whose
--- author covered an axis instead: `[전투] A / [비전투] B` is always ours and no unconditional
--- record appears in it.
---
--- **It only ever errs one way.** Opaque records (conditions with no axis) and running out of
--- work budget both count as "not covered", so the answer can be a false no and never a false
--- yes. A false yes would leave a key bound that should have been released.
function DebindPrivate.IsKeyAlwaysOurs(bindings)
    local count = #bindings;
    if (count == 0) then
        return false;
    end

    -- **키를 잡는 레코드만 본다.**
    --
    -- `click-time-phase3.md` §3은 축 인코딩이 이 일을 대신하므로 거를 필요가 없다고 적었는데,
    -- **틀렸다.** hover 컬럼이 클릭 전용 레코드를 `NONE` 밖으로 밀어내는 것은 그 레코드가
    -- `hover`를 들고 있을 때뿐이고, `isClickCast`은 `SETCUSTOM`이나 `unit == "hover"`로도 선다.
    -- 그런 레코드는 hover 컬럼이 센티넬과 같은 상자라 **센티넬을 덮어버린다** - 키를 잡는
    -- 레코드가 하나도 없는 키가 "언제나 우리 것"으로 나온다.
    --
    -- 묻는 것이 키의 배선이므로 키를 안 잡는 레코드는 덮개로도 세지 않고 돌려주는 쪽으로도
    -- 안 센다. 그냥 없는 것이다.
    local arr = _sentinelArray;
    local n = 0;
    for i = 1, count do
        local binding = bindings[i];
        if (binding.holdsKey) then
            n = n + 1;
            arr[n] = binding;
        end
    end

    if (n == 0) then
        return false;
    end

    count = n;
    arr[count + 1] = _sentinel;
    for i = count + 2, #arr do
        arr[i] = nil;
    end

    buildLayout(arr);
    for i = 1, count + 1 do
        _conditionsMap[arr[i]] = buildConditionSet(arr[i], {});
    end

    -- The sentinel is in the array for this too, and that is what makes pruning safe here. A
    -- column every real record shares would otherwise be dropped as constant, and dropping it
    -- would hide the hole the sentinel exists to find - every record having `combat=true` says
    -- nothing about `combat=false`. With the sentinel present that column is not constant.
    pruneConstantColumns(arr);

    local answer = true;
    local callBudget = MAX_CALL_WORK;

    for i = 1, count + 1 do
        local binding = arr[i];
        local handsBack = binding == _sentinel
            or binding.type == Constants.UNUSED
            or binding.type == Constants.COMMAND;

        if (handsBack) then
            if (i == 1 or _opaque[binding]) then
                answer = false;
                break;
            end

            local coverCount = 0;
            for j = 1, i - 1 do
                local other = arr[j];
                if (not _opaque[other]) then
                    coverCount = coverCount + 1;
                    _covers[coverCount] = _conditionsMap[other];
                end
            end

            if (coverCount == 0 or callBudget <= 0) then
                answer = false;
                break;
            end

            local granted = MAX_WORK;
            if (granted > callBudget) then
                granted = callBudget;
            end
            _workBudget = granted;
            _nodeCount = 0;
            _gaveUp = false;

            local covered = isCovered(_conditionsMap[binding], _covers, coverCount, 1);
            callBudget = callBudget - (granted - _workBudget);

            if (_gaveUp or not covered) then
                answer = false;
                break;
            end
        end
    end

    wipe(_conditionsMap);
    return answer;
end

function DebindPrivate.IsUnreachableAction(action)
    local binding = DebindPrivate.GetBindingInfoForAction(action);
    return UnreachableBindingCache[binding];
end

function DebindPrivate.ClearUnreachableBindingCache()
    wipe(UnreachableBindingCache);
end
