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
          reaction   `UpdateBindings.lua` emits both the state loop's line and the unitframe poll's;
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
-- The mask itself is built in `Misc.lua` (BuildUnitStates), which is also where the `unitframe`
-- condition is folded in -- the pointed frame's unit is a unit named "unitframe", so it belongs
-- on this axis rather than in a column of its own.

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
        -- Frame-dependent axes carry no condition off the `unitframe` path: with no frame
        -- pointed at there is no frame to have a type. Returning the full mask there is what
        -- keeps this column free -- every cover that reaches the not-pointing point reaches it
        -- for all seven frame types at once, so the point never splits across covers.
        --
        -- That is what `Misc.BuildUnitStates` hands over: the mask is folded only off
        -- `units["unitframe"]`, so a binding with no condition on that unit arrives with nil.
        name = "frameTypes",
        make = function(binding)
            return flagsToConditionFlags(binding.unitFrameTypes, 6);
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
    {
        name = "flying",
        make = function(binding)
            return boolToConditionFlags(binding.conditions.flying);
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
    -- **This column is what keeps a self or focus twin from deleting its original.** The twin has
    -- the original's conditions and stands ahead of it, so without the column its box would hold
    -- the original's whole (`devdocs/implementing-focus-and-self-cast.md` §3-5).
    {
        name = "castModifier",
        make = function(binding)
            return binding.castModifier or Constants.CASTMOD_ALL;
        end
    },
    -- **`specs` has no column here and must not be given one.** Nothing that fails it reaches this
    -- file: `BuildKeyMap` leaves those bindings out of the key map altogether, and the comment
    -- there is where that reasoning lives. What arrives is a set of bindings whose specialization
    -- condition is true everywhere in this space, and the full mask is how that is spelled.
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

--- **The one correlation across columns that is folded in, and the only place it can be.** The
--- cursor being on a frame is the client's `mouseover` standing on that frame's unit, so the
--- product's (on a frame, nothing moused over) point is one the game never produces. Left in, a
--- `mouseover` action never covers a `unitframe` action it always beats to the press -- the shape
--- a key with both casts on it has.
---
--- **Here rather than in the mask `Misc.lua` builds**, because narrowing it there would create
--- this column on a key where nobody named `mouseover`, and then a pair of bindings splitting the
--- `unitframe` axis between them would stop covering an unconditional one: the phantom point is
--- theirs to cover and neither reaches it. Done at column-build time, the space only grows the
--- axis when a binding really asks about it.
---
--- **Existence and nothing more, though it is the same unit.** Taking the `unitframe` mask
--- outright would say [the moused-over unit is friendly] where the user said it of the pointed
--- frame, and nobody here has measured the client on that.
---
--- **One direction.** Mousing over something in the world sets the token with no frame anywhere,
--- so a `unitframe` condition says nothing about `mouseover` being absent.
local function makeMouseoverFlags(binding)
    local states = binding.unitStates;
    local mask = (states and states.mouseover) or Constants.UNITSTATE_ALL;
    local unitframe = states and states.unitframe;
    if (unitframe and unitframe ~= 0 and band(unitframe, Constants.UNITSTATE_NONE) == 0) then
        mask = band(mask, Constants.UNITSTATE_EXISTS);
    end
    return mask;
end

--- **A column of its own rather than another factor in the unit product.** `Constants.lua` says
--- why over `UNITSTATE_NONE`: the product belongs to a key and widening the enumeration makes
--- every key pay for an axis it never asked about. It correlates with the `unitframe` column --
--- an absent unit is always of unknown role -- and a correlation across columns is the safe
--- direction (see "Across columns" above), so it is left alone.
local function makeRoleFlags(binding)
    return binding.unitRole or Constants.ROLE_ALL;
end

--- **Its own column per unit**, for the same reason the role one is its own: `Constants.lua` over
--- `UNITSTATE_NONE` says why a per-unit axis does not widen that product.
---
--- What arrives here is already the four-cell partition. The three boxes a user ticks overlap --
--- a raid member in their own subgroup is in both -- and `Misc.BuildUnitStates` is where that
--- overlap is resolved. **A mask of the stored three would not be a partition**, and the set
--- algebra below has no way to notice that.
local function makeUnitGroupFlags(binding, unit)
    local groups = binding.unitGroups;
    local mask = groups and groups[unit];
    if (mask == nil) then
        return Constants.UNITGROUPCELL_ALL;
    end
    return mask;
end

--- The spell a `known` condition asks about, which is **the condition's own value** and not the
--- action's (`Misc.lua`'s `KnownSpellAsked`). Two actions on one spell asking about two different
--- talents are two axes; folding them into one column keyed by the action would call the second a
--- repeat of the first.
---
--- nil only where `true` has nothing to fall back on: a spec-resolved type with no spell in this
--- specialization.
local function KnownSpellOf(binding)
    return DebindPrivate.KnownSpellAsked(binding);
end

local function makeKnownFlags(binding, spellValue)
    local known = binding.conditions.known;
    if (known ~= nil and KnownSpellOf(binding) == spellValue) then
        return known and KNOWN_YES or KNOWN_NO;
    end
    return KNOWN_ANY;
end

local UnreachableBindingCache = {};

local _colMake = {};
local _colArg = {};
local _numColumns = 0;

local _unitSeen = {};
local _unitGroupSeen = {};
local _knownSeen = {};
local _stateSeen = {};
local _roleSeen = false;
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
    wipe(_unitGroupSeen);
    wipe(_knownSeen);
    wipe(_stateSeen);
    _roleSeen = false;
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

        -- A spellbook-gated binding (`spellbook`, `SpecSpells.lua`) is decided at the press by a
        -- question no column here can hold, so it covers nothing. Left as a box it would be an
        -- unconditional one and delete the original standing behind it.
        if (binding.spellbook) then
            _opaque[binding] = true;
        end

        local states = binding.unitStates;
        if (states) then
            for unit in pairs(states) do
                if (not _unitSeen[unit]) then
                    _unitSeen[unit] = true;
                    _numColumns = _numColumns + 1;
                    _colMake[_numColumns] = unit == "mouseover" and makeMouseoverFlags
                            or makeUnitFlags;
                    _colArg[_numColumns] = unit;
                end
            end
        end

        local unitGroups = binding.unitGroups;
        if (unitGroups) then
            for unit in pairs(unitGroups) do
                if (not _unitGroupSeen[unit]) then
                    _unitGroupSeen[unit] = true;
                    _numColumns = _numColumns + 1;
                    _colMake[_numColumns] = makeUnitGroupFlags;
                    _colArg[_numColumns] = unit;
                end
            end
        end

        if (binding.unitRole and not _roleSeen) then
            _roleSeen = true;
            _numColumns = _numColumns + 1;
            _colMake[_numColumns] = makeRoleFlags;
            _colArg[_numColumns] = nil;
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
            local knownSpell = KnownSpellOf(binding);
            if (knownSpell ~= nil) then
                if (not _knownSeen[knownSpell]) then
                    _knownSeen[knownSpell] = true;
                    _numColumns = _numColumns + 1;
                    _colMake[_numColumns] = makeKnownFlags;
                    _colArg[_numColumns] = knownSpell;
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
--- Is `region` wholly covered by the union of the covers?
---
--- **It stops at the first uncovered point** instead of building the remainder and asking whether
--- it is empty. Most bindings are reachable, so the common case is the one that ends early; building
--- the whole remainder made it the other way round, and a reachable binding was the most expensive.
---
--- At each node:
---   1. Drop the covers that do not meet `region`. If none is left, a counterexample is found.
---   2. If one cover takes `region` whole, this branch is done.
---   3. Pick a cover O, split `region \ O` into disjoint pieces and recurse on each. The pieces do
---      not meet O, so they go down **with O taken off the cover list**.
---
--- The cover that splits into the fewest pieces is picked, which prunes hardest.
---
--- A degenerate box -- some column at 0, meaning the condition can never hold -- falls out of
--- both roles on the disjointness test, which is the right answer either way: as a region it
--- meets no cover and survives, as a cover it meets no region and deletes nothing. Strictly
--- such a binding *is* unreachable and could be dropped, but a silent deletion and a warning
--- are different products, and the warning is the issue check's.
---
--- **Such a box should not arrive here at all.** `BuildKeyMap` leaves off the key every binding
--- `FillBinding` marked `dead` and every action carrying an ERROR, `groups == 0` among them. The
--- behaviour above is a backstop, and it is one on purpose: assuming an upstream filter held is the
--- shape of coupling this file has been bitten by before.
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

--- True only when **every** binding the action puts on its key was dropped. An action whose hover
--- twin alone is covered still fires everywhere but over a frame, and calling that unreachable
--- would paint a working action red.
---
--- Read off the cached list rather than a fresh derivation: the cache was keyed by these tables in
--- the last `BuildKeyMap`, and this is asked several times per drawn row. An action with no list
--- yet gets one, which the cache cannot hold, so the answer is the same and the cost is paid once.
---
--- **Only the bindings that can stand are counted** (`binding.dead`). One that cannot never reaches
--- the key, so nothing covers it, and counted it would keep an action every press of which goes to
--- another from ever reading as unreachable.
---
--- **With none that stand the action is not unreachable.** That is an empty list, the action with
--- every Casting value turned off, or one whose every binding cannot stand; each has its own issue,
--- and "all of none were dropped" is vacuously true and put "another action gets there first" on a
--- key with nothing else on it.
function DebindPrivate.IsUnreachableAction(action)
    local list = DebindPrivate.PeekBindingsForAction(action)
        or DebindPrivate.GetBindingsForAction(action);
    local standing = false;
    for i = 1, #list do
        if (not list[i].dead) then
            if (not UnreachableBindingCache[list[i]]) then
                return false;
            end
            standing = true;
        end
    end
    return standing;
end

function DebindPrivate.ClearUnreachableBindingCache()
    wipe(UnreachableBindingCache);
end
