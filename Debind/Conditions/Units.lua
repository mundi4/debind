local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

local band      = bit.band;
local bor       = bit.bor;

local UNIT_SCALAR_TO_STATE = {
    [true]    = Constants.UNITSTATE_EXISTS,
    [false]   = Constants.UNITSTATE_NONE,
    ["help"]  = Constants.UNITSTATE_HELP,
    ["harm"]  = Constants.UNITSTATE_HARM,
};

local REACTION_TO_UNIT_STATE = {
    [Constants.REACTION_HELP]  = Constants.UNITSTATE_HELP,
    [Constants.REACTION_HARM]  = Constants.UNITSTATE_HARM,
    [Constants.REACTION_OTHER] = Constants.UNITSTATE_OTHER,
};

--- 저장된 유닛 조건 -> 바인딩이 읽는 모양. 조건이 꺼져 있으면 `nil`.
---
--- **저장과 바인딩은 다른 모양이고, 이 함수가 그 이음매다.**
---
--- 저장은 사용자가 편집하는 것이라 **끈 값을 기억한다.** 라디오를 [사용 안 함]이나
--- [없을 때]로 옮겼다고 골라둔 반응·생사를 지우면, 되돌렸을 때 처음부터 다시 골라야 한다.
--- **옵션을 끄는 것이지 지우는 것이 아니다.**
---
---     { exists = true, ... }       있을 때. 축이 붙으면 그만큼 좁아진다
---     { exists = false, ... }      없을 때. 축은 기억만 한다
---     { disabled = true, ... }     이 유닛에 조건 없음. 축은 기억만 한다
---
--- **표시가 하나도 없는 표는 옛 값이고, "있을 때"로 읽는다.** `dbver <= 6` 단계가 그것을
--- `exists = true`로 올리므로 저장에는 안 남는다. 아직 안 옮겨진 프로필과 페이로드가 그
--- 모양으로 오는데, 그것을 "조건 없음"으로 읽으면 걸어둔 조건이 조용히 사라져 바인딩이 제 것
--- 아닌 키까지 가져간다. 좁아지는 쪽이 안전하다.
---
--- 바인딩은 판정에 쓰는 것이라 기억을 안 들고 간다. 그래야 `IsConditionalBinding`도, 이슈
--- 검사도, 런타임 방출도 "꺼진 축"이라는 경우를 몰라도 된다.
---
--- 옛 스칼라도 여기서 받는다. 가져오기 도중이거나 손으로 고친 프로필, 테스트가 만든 액션이
--- 그 모양으로 온다 - **여기서 끝나야** 하류가 타입 검사를 안 한다.
local function UnitConditionForBinding(value)
    if (value == nil) then
        return nil;
    elseif (value == true) then
        return {};
    elseif (value == false) then
        return false;
    elseif (value == "help") then
        return { reaction = Constants.REACTION_HELP };
    elseif (value == "harm") then
        return { reaction = Constants.REACTION_HARM };
    elseif (type(value) ~= "table") then
        -- 모르는 스칼라. **떨어뜨리지 않는다** - 옛 버전이 쓴 값을 우리가 모를 수 있고, 조건이
        -- 조용히 사라지면 그 바인딩이 걸어둔 것보다 넓어져 남의 키를 가져간다.
        --
        -- **없을 때로 읽지만, 둘째 반환값이 그게 읽어낸 값이 아니라고 말한다.** 없음 점은 크기가
        -- 작을 뿐 "있을 때"의 부분집합이 아니라서, 좁게 틀리는 것이 아니라 **다른 자리로** 틀린다.
        -- 그대로 축에 올리면 이 바인딩이 진짜 [없을 때] 바인딩을 통째로 덮고 solver가 그것을
        -- 지운다. `GetBindingInfoForAction`이 둘째 값을 받아 바인딩을 두 역할에서 뺀다.
        --
        -- 첫째 값은 그대로 두는 것이 이 함수의 나머지 독자들 때문이다 - 툴팁과 조건 메뉴는
        -- 라디오 셋 중 하나를 골라야 하고, 넷째 자리가 없다.
        return false, true;
    end

    -- **옛 이름 `off`는 여기서 안 받는다.** 저장된 표를 읽는 자리가 둘인데
    -- (`IntersectStoredUnitConditions`) 한쪽만 옛 이름을 알면 같은 표를 두 가지로 읽는다.
    -- `dbver <= 6` 단계가 프로필과 페이로드 양쪽에서 이름을 올리고 - 페이로드도 `MigrateLayer`를
    -- 지난다(`Export.lua`의 `BringPayloadDataForward`) - 그 아래로 내려갈 저장은 없다.
    if (value.disabled) then
        return nil;
    elseif (value.exists == false) then
        return false;
    end
    return { reaction = value.reaction, dead = value.dead, role = value.role, group = value.group,
        frameTypes = value.frameTypes };
end

--- The old `hover` / `reactions` pair -> the unit condition they became.
---
--- The pointed frame's unit is a unit, so it is stored as one: `units["unitframe"]`
--- (`Migration.lua`'s `dbver <= 4` step). Kept in its own pair of fields it was one unit described
--- by two columns, meeting only in `BuildUnitStates` -- which meant two runtime paths measuring
--- the same thing about the same unit.
---
--- `existing` is whatever that key already holds, from the days both menus were live. This
--- **intersects** rather than overwrites: dropping either side would widen a binding past what
--- was set. Where the two do not overlap the answer is `reaction = 0` -- exists, and in none of
--- the three reactions, which no unit satisfies. That is not a new marker: `GetBindingIssue`
--- already reads a zero mask that way, and the pair was already an issue before it was folded.
--- **`existing`도 돌려주는 값도 바인딩 모양이다**(`UnitConditionForBinding`이 내는 것). 저장
--- 모양을 넣지 말 것 - 부르는 쪽이 먼저 통과시킨다. 접기는 "꺼진 축을 기억한다"는 편집 쪽
--- 사정과 아무 상관이 없고, 두 모양을 다 받게 만들면 어느 쪽인지 매번 물어야 한다.
local function UnitFrameConditionFromLegacy(hover, reactions, existing)
    if (hover == false) then
        -- "Not over a frame" against any condition that needs the unit there. Nothing is both.
        -- Spelled out rather than `and false or` -- that idiom cannot return `false`.
        if (existing == nil or existing == false) then
            return false;
        end
        return { reaction = 0 };
    end
    if (existing == false) then
        return { reaction = 0 };
    end

    local reaction = reactions;
    if (reaction == Constants.REACTION_ALL) then
        reaction = nil;
    end

    local folded = type(existing) == "table" and existing or {};
    if (reaction == nil) then
        reaction = folded.reaction;
    elseif (folded.reaction ~= nil) then
        reaction = band(reaction, folded.reaction);
    end
    folded.reaction = reaction;
    return folded;
end

DebindPrivate.UnitFrameConditionFromLegacy = UnitFrameConditionFromLegacy;
DebindPrivate.UnitConditionForBinding = UnitConditionForBinding;

--- The unit frame condition stored on this action. **The old spelling is read as well.**
---
--- `dbver <= 6` moves a stored `units.hover` to `units.unitframe`, but **a place that reads the raw
--- action also meets what the ladder has not reached**: a hand-edited profile, and the same cases
--- `FillBinding` takes a flat `checkedUnits` for. Looking at one name only drops that condition in
--- silence, and **a binding that lost a condition is wider and takes somebody else's key.**
---
--- The raw action is read here for `ActionUnitFrameIsOn` and in the same order by
--- `ActionTooltip.lua`, and only this function knows the old name. It makes no table, so a call
--- per row allocates nothing.
function DebindPrivate.StoredUnitFrameCondition(action)
    local units = action.conditions and action.conditions.units;
    if (units == nil) then
        return nil;
    end
    local value = units.unitframe;
    if (value == nil) then
        value = units.hover;
    end
    return value;
end

--- One stored unit condition -> a mask on the unit axis.
---
--- Storage keeps **one field per axis** (`{ reaction = ... }`), not one packed enum, so that a
--- new axis is a new field and old data stays valid: a field that is absent constrains nothing,
--- which is already the right answer. See `Migration.lua`'s `dbver <= 4` step.
---
--- An axis that is absent contributes its whole range, which is why an empty table means
--- "exists, nothing else asked". `false` is the one non-table value -- the absent point is not
--- on any axis, which is the whole reason this column is a product and not separate columns.
local function UnitConditionToState(value)
    if (value == false) then
        return Constants.UNITSTATE_NONE;
    end
    if (type(value) ~= "table") then
        -- 아직 안 옮겨진 값. `MigrateLayer`가 올려주지만, 가져오기 도중이거나 손으로 고친
        -- 프로필이면 여기로 온다.
        --
        -- **모르는 값이 여기까지 오면 이미 없음 점이다.** `UnitConditionForBinding`이 먼저
        -- 돌면서 `false`로 바꾸고, 못 읽었다는 사실은 그쪽 둘째 반환값이 따로 나른다.
        return UNIT_SCALAR_TO_STATE[value] or Constants.UNITSTATE_NONE;
    end

    local mask;
    local reactions = value.reaction;
    if (reactions == nil) then
        mask = Constants.UNITSTATE_EXISTS;
    else
        mask = 0;
        for reaction, state in pairs(REACTION_TO_UNIT_STATE) do
            if (band(reactions, reaction) ~= 0) then
                mask = mask + state;
            end
        end
    end

    -- Life **takes half of the product away**; it is not a column of its own. `nil` leaves both
    -- halves, which is what "constrains nothing" means -- and is already the right answer for old
    -- data that has no such field.
    if (value.dead ~= nil) then
        mask = band(mask, value.dead and Constants.UNITSTATE_DEAD or Constants.UNITSTATE_ALIVE);
    end

    return mask;
end

DebindPrivate.UnitConditionToState = UnitConditionToState;

--- This binding's condition on `unitframe`, in binding shape: nil, `false`, or a table.
---
--- **Read each time, not kept as a field.** The pointed frame's unit is an ordinary unit
--- (`which-action-a-key-runs.md` §0), so a second name for one entry of `units` would be
--- the split that fold removed. The readers left are the ones that ask something about the **key**
--- rather than about the unit: which path a press takes (`UpdateBindings.lua`'s `isClickCast` and
--- `holdsKey`), whether a mouse button can be bound at all (`IsKeyInvalidForAction`), and where the
--- frame's unit fills in for an empty target.
---
--- `false` and `nil` are **different answers** and both are load-bearing -- "only when not over a
--- frame" versus "does not care" -- so this cannot collapse to a boolean.
local function UnitFrameConditionOf(binding)
    local conditions = binding.conditions;
    return conditions and conditions.units and conditions.units.unitframe;
end

DebindPrivate.UnitFrameConditionOf = UnitFrameConditionOf;

--- 저장된 세 상자 -> 그것이 덮는 네 칸.
---
--- **`bor`인 것이 요지다.** `PARTY`와 `RAID`가 둘 다 `BOTH`를 덮으므로 더하면 그 칸을 두 번
--- 센다. 겹치는 것이 이 축의 성질이고, 겹침을 여기서 푸는 것이 컬럼을 분할로 만든다
--- (`Constants.lua`의 `UNITGROUPCELL_*`).
local function UnitGroupToCells(mask)
    if (mask == nil) then
        return Constants.UNITGROUPCELL_ALL;
    end
    local cells = 0;
    for flag, covered in pairs(Constants.UNITGROUP_TO_CELLS) do
        if (band(mask, flag) ~= 0) then
            cells = bor(cells, covered);
        end
    end
    return cells;
end

DebindPrivate.UnitGroupToCells = UnitGroupToCells;

--- The stored box mask naming exactly this cell set, or nil where none does.
---
--- **The three boxes are not closed under intersection.** [In my party] and [In my raid] meet on
--- "in a raid and in my subgroup" alone, and no box or combination of boxes names that one cell.
--- So a fold that has to be written back into a profile has to ask first whether its answer can be
--- written at all; `band` on the boxes themselves returns 0 there, which is not that answer but
--- "no box chosen", and a binding that can fire becomes one that carries an error forever.
local function CellsToUnitGroup(cells)
    for mask = 0, Constants.UNITGROUP_ALL do
        if (UnitGroupToCells(mask) == cells) then
            return mask;
        end
    end
end
DebindPrivate.CellsToUnitGroup = CellsToUnitGroup;

--- The unit a binding's `"@"` is asked of: the unit it aims at, and `target` where it aims at none.
--- nil only for a `unit` that is not a string at all.
---
--- **`target` is where the condition is checked and nothing more.** An original with no target keeps
--- `unit` empty and goes out for the game to place, Auto Self Cast included. Writing `target` into the
--- field would turn Auto Self Cast off the moment a condition was set, which is picking `target` under
--- Target (`implementing-focus-and-self-cast.md` §3-6). `""`, the hovered unit turned off, is
--- the game placing the cast too.
---
--- **One rule for every reader**: the unit states below, the record `UpdateBindings.lua` emits, the
--- issue check and the macro conversion. Two of them landing `"@"` on different units is a binding
--- judged on one unit and shown or fired on another.
local function ResolvedUnitOf(binding)
    local unit = binding.unit;
    if (unit == nil or unit == "") then
        return "target";
    end
    if (type(unit) ~= "string") then
        return nil;
    end
    return unit;
end
DebindPrivate.ResolvedUnitOf = ResolvedUnitOf;

local SOURCE_ROW = 1;
local SOURCE_AT = 2;
local SOURCE_KEY = 4;
local SOURCE_TWIN = 16;
DebindPrivate.UNIT_SOURCE_ROW = SOURCE_ROW;
DebindPrivate.UNIT_SOURCE_AT = SOURCE_AT;

--- Fold everything that says something about a unit onto one mask per unit.
---
--- `binding.unitStates` is the only thing the solver reads about units.
---
--- The point of doing it here is that **the pointed frame's unit is just a unit, named
--- "unitframe"**. Kept apart, the `unitframe` condition and a unit condition on the same unit are
--- two columns describing one thing, and the solver cannot see that `unitframe=friendly` with
--- `@=hostile` never holds -- it keeps a binding that can never fire and warns about nothing.
---
--- A mouse button reaches the not-pointing point and nothing else: the click fires wherever the
--- cursor already is, and over a unit frame the frame eats it, so only the frame path can act
--- there. The same absent condition on a keyboard key spans the whole axis.
local function BuildUnitStates(binding)
    local states;

    -- **A value this build cannot read makes the binding opaque before any axis is touched.**
    -- `GetBindingInfoForAction` sets the flag while turning the stored table into the binding one;
    -- what it means is the same thing `"@"` with nowhere to go means below, so it lands in the same
    -- field. Reading such a value as the absent point would cover the bindings that really are
    -- [when there is none] and delete them.
    local opaque = binding.unitConditionUnreadable or nil;

    local sources = binding.unitSources;
    if (sources == nil) then
        sources = {};
        binding.unitSources = sources;
    else
        wipe(sources);
    end

    local function narrow(unit, mask, source)
        states = states or {};
        local prev = states[unit];
        if (prev == nil) then
            states[unit] = mask;
        else
            states[unit] = band(prev, mask);
        end
        sources[unit] = bor(sources[unit] or 0, source);
    end

    --- **Its own column, and only the pointed frame's unit rides it.** The map behind it is keyed
    --- by group unit tokens, and a group frame is the only thing that hands us one
    --- (`Constants.lua`). Two sources can name that unit -- `units.unitframe` and a `"@"` that
    --- resolves to it -- so this narrows the same way `narrow` does.
    local role;
    local function narrowRole(mask)
        if (role == nil) then
            role = mask;
        else
            role = band(role, mask);
        end
    end

    --- 프레임의 종류. 역할과 같은 자리에 산다 - 개체창을 가리켰을 때만 답이 나오는 축이라
    --- 유닛마다 세울 값이 아니다.
    local frameTypes;
    local function narrowFrameTypes(mask)
        if (frameTypes == nil) then
            frameTypes = mask;
        else
            frameTypes = band(frameTypes, mask);
        end
    end

    --- 소속도 자기 컬럼이고, 역할과 달리 **유닛마다** 선다. 어느 유닛에나 물을 수 있는
    --- 축이라 unitframe 슬롯에 얹을 이유가 없다.
    local groups;
    local function narrowGroup(unit, mask)
        groups = groups or {};
        local prev = groups[unit];
        if (prev == nil) then
            groups[unit] = mask;
        else
            groups[unit] = band(prev, mask);
        end
    end

    -- The `unitframe` condition itself is not read here any more -- it lives in
    -- `units["unitframe"]` and the loop below folds it like any other unit. What is left is the
    -- one thing the **key** says: a mouse button reaches the not-pointing point and nothing else,
    -- because the click fires wherever the cursor already is and over a unit frame the frame eats it.
    --
    -- **Only when nothing was said about pointing.** An explicit `unitframe` condition on a mouse
    -- button key is the user overriding that reading, and it has always won here -- narrowing it
    -- to absent as well would leave an empty box and delete the binding for a reason nobody set.
    local conditions = binding.conditions;
    local units = conditions and conditions.units;

    if (binding.key and (units == nil or units.unitframe == nil)
            and DebindPrivate.GetMouseButtonAndPrefix(binding.key)) then
        narrow("unitframe", Constants.UNITSTATE_NONE, SOURCE_KEY);
    end
    if (units) then
        for key, value in pairs(units) do
            local unit = key;
            local source = SOURCE_ROW;
            if (key == binding.twinOwnUnit) then
                source = SOURCE_TWIN;
            elseif (key == "@") then
                source = SOURCE_AT;
                unit = ResolvedUnitOf(binding);
                if (unit == nil) then
                    -- Nowhere to put it. Dropping the condition instead would make the binding
                    -- look wider than it is, and a cover wider than it should be deletes
                    -- bindings that can still fire -- so it leaves both roles, not one.
                    opaque = true;
                    unit = nil;
                end
            end
            if (unit) then
                narrow(unit, UnitConditionToState(value), source);
                -- `value` is `false` for [when there is none], and role is remembered rather than
                -- applied there -- the menu's rule for every axis under a mode it does not use.
                if (unit == "unitframe" and type(value) == "table") then
                    if (value.role) then
                        narrowRole(value.role);
                    end
                    if (value.frameTypes) then
                        narrowFrameTypes(value.frameTypes);
                    end
                end
                if (type(value) == "table" and value.group) then
                    narrowGroup(unit, UnitGroupToCells(value.group));
                end
            end
        end
    end

    binding.unitStates = states;
    binding.unitStatesOpaque = opaque;
    binding.unitRole = role;
    binding.unitFrameTypes = frameTypes;
    binding.unitGroups = groups;
end

DebindPrivate.BuildUnitStates = BuildUnitStates;

--- Does a role get measured under these frame types, and is that all it is measured under? nil
--- frame types are every type. **A role is only measured on a party or raid frame**
--- (`SecureBindings.lua`'s click path and `setup_onenter`); on any other frame it has no say at all,
--- an empty one included.
local ROLE_FRAME_TYPES_OTHER = Constants.FRAMETYPE_ALL - Constants.FRAMETYPE_GROUP;
local function RoleMeasuredUnder(frameTypes)
    if (frameTypes == nil) then
        return true, false;
    end
    local measured = band(frameTypes, Constants.FRAMETYPE_GROUP) ~= 0;
    return measured, measured and band(frameTypes, ROLE_FRAME_TYPES_OTHER) == 0;
end
DebindPrivate.RoleMeasuredUnder = RoleMeasuredUnder;

--- Whether a role mask of zero leaves this binding nowhere. **Not where one row picked no role and
--- the frame types reach past party and raid frames**: the role is measured on those alone, and the
--- binding still runs over the rest (`RoleMeasuredUnder`). A zero two rows made between them is the
--- other thing, a contradiction, and `mergeUnitConditions` emits nothing for it
--- (`UpdateBindings.lua`), so that one leaves nothing whatever the frame types.
local function RoleLeavesNothing(binding)
    local units = binding.conditions and binding.conditions.units;
    local ownRow = false;
    if (units) then
        for key, value in pairs(units) do
            if ((key == "unitframe" or (key == "@" and ResolvedUnitOf(binding) == "unitframe"))
                    and type(value) == "table" and value.role == 0) then
                ownRow = true;
            end
        end
    end
    if (not ownRow) then
        return true;
    end
    local _, onlyGroup = RoleMeasuredUnder(binding.unitFrameTypes);
    return onlyGroup;
end
DebindPrivate.RoleLeavesNothing = RoleLeavesNothing;
