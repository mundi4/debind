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
        -- **A value no build writes** (`UnitConditionIsUnreadable`), and its action is left out by
        -- `INVALID_ACTION`. `false` is for the readers that still draw it: the tooltip and the
        -- condition menu pick one of three radios and have no fourth.
        return false;
    end

    -- **The old name `off` is not read here.** `dbver <= 6` renames it in profiles and payloads
    -- alike -- a payload goes through `MigrateLayer` too (`Export.lua`'s
    -- `BringPayloadDataForward`) -- and nothing stored stays below that.
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

--- Whether a stored unit condition is a value no build writes: neither a table nor one of the four
--- old scalars. **Only hand-made data holds one**, a SavedVariables or a share string edited by
--- hand: every build since `dbver` 4 writes a table, and the import copies the inside of `units`
--- without looking. Read as [when there is none] it would cover a real [when there is none] binding
--- and the solver would delete that one, so its action is left out (`INVALID_ACTION`).
---
--- Asked per stored row on every issue check, so it allocates nothing.
function DebindPrivate.UnitConditionIsUnreadable(value)
    return value ~= nil and type(value) ~= "table" and UNIT_SCALAR_TO_STATE[value] == nil;
end

--- Does this stored unit row remember any axis? Asked when a row is turned off: one that remembers
--- nothing goes rather than staying as an empty table (`WriteUnitConditionMode`, `SetPlayerLife`,
--- `SanitizeAction`).
---
--- **Every field but the two mode ones is an axis**, read off `UNIT_CONDITION_FIELDS`. This used to
--- name the axes one by one, and the group axis was left off it when it was added: a row holding
--- only a group was deleted rather than remembered the moment it was turned off.
function DebindPrivate.UnitConditionRemembersAxis(cond)
    for name in pairs(Constants.UNIT_CONDITION_FIELDS) do
        if (name ~= "disabled" and name ~= "exists" and cond[name] ~= nil) then
            return true;
        end
    end
    return false;
end

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
        -- An old scalar the ladder has not reached. A value no build writes reads as the absent
        -- point, as `UnitConditionForBinding` reads it, and its action never reaches the solver
        -- (`INVALID_ACTION`).
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
--- rather than about the unit: which path a press takes (`KeyRecords.lua`'s `isClickCast` and
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
--- "no box chosen", and a binding that can fire becomes one that carries an issue forever.
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
--- **One rule for every reader**: the unit states below, the record `KeyRecords.lua` emits, the
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

--- Whether `role` and `frameTypes` say anything about this unit. **Only about the pointed frame's
--- unit**: the frame answers both, its type off the frame itself and its role off the group header
--- that handed it the unit (`Constants.lua`), and no unit token carries either.
---
--- The menu offers the two on `"@"` as well, and they count wherever `"@"` lands on `unitframe`:
--- the hover twin under Unit Frames, and every binding of an action aimed at Unit Frame.
local function FrameAxesOn(unit)
    return unit == "unitframe";
end
DebindPrivate.FrameAxesOn = FrameAxesOn;

--- No unit satisfies it: exists, and in none of the three reactions. Read-only.
local NO_UNIT = { reaction = 0 };

--- `out` refilled where the caller keeps one, a new table where it does not.
local function WriteUnitCondition(out, reaction, dead, role, frameTypes, group)
    if (out == nil) then
        return { reaction = reaction, dead = dead, role = role, frameTypes = frameTypes, group = group };
    end
    out.reaction, out.dead, out.role, out.frameTypes, out.group = reaction, dead, role, frameTypes, group;
    return out;
end

local function EmptyUnitCondition(out)
    if (out == nil) then
        return NO_UNIT;
    end
    return WriteUnitCondition(out, 0);
end

--- One more row about `unit`, met with what has been folded onto it so far.
---
--- **The only place two conditions on one unit become one.** The solver's columns, the record
--- the press checks and the row a macro text conversion writes back are all read off what this
--- answers, so a new axis is added here and nowhere else. A second copy anywhere is two answers
--- that drift apart one axis at a time.
---
--- `folded` is an earlier answer, nil for none yet. `row` is in binding shape
--- (`UnitConditionForBinding`; a stored scalar is put through it here), with `group` in boxes. The
--- answer is nil, `false` for [when there is none], or a table with `group` in cells
--- (`UnitGroupToCells`). `row` is never written to.
---
--- **`out` is the table the answer is written into, and it may be `folded` itself.** A caller that
--- folds on every `FillBinding` hands one in per unit so a refill allocates no condition tables
--- (`BuildUnitStates`). Without one, a row needing no change comes back as itself and anything else
--- is a new table.
---
--- **A meet nothing satisfies keeps a shape the masks already read as empty**: a zero on the axis
--- that emptied, or `NO_UNIT` where no axis can say it -- absent against present, life asked both
--- ways, and two picked role sets that do not meet.
---
--- **Two picked role sets that do not meet are a contradiction, though the press would still fire
--- over a frame where no role is measured** (2026-10-08, owner). Tank on one row and Healer on the
--- other was not meant as "only over frames that are not party or raid frames", and what was
--- meant cannot be told, so it is marked for the reader to fix rather than run as a guess. A single
--- row with no role picked is the other thing: that one says so on its own, and it keeps running
--- over those frames (`RoleLeavesNothing`).
local function FoldUnitCondition(unit, folded, row, out)
    if (row ~= nil and row ~= false and type(row) ~= "table") then
        row = UnitConditionForBinding(row);
    end
    if (row == nil) then
        return folded;
    end

    -- Spelled out rather than `and false or`: that idiom cannot return `false`.
    if (row == false) then
        if (folded == nil or folded == false) then
            return false;
        end
        return EmptyUnitCondition(out);
    end

    local reaction, dead = row.reaction, row.dead;
    local group = row.group and UnitGroupToCells(row.group);
    local role, frameTypes;
    if (FrameAxesOn(unit)) then
        role, frameTypes = row.role, row.frameTypes;
    end

    if (folded == nil) then
        if (out == nil and row.group == nil and role == row.role and frameTypes == row.frameTypes) then
            return row;
        end
        return WriteUnitCondition(out, reaction, dead, role, frameTypes, group);
    end
    if (folded == false) then
        return EmptyUnitCondition(out);
    end

    if (folded.reaction ~= nil) then
        reaction = reaction and band(reaction, folded.reaction) or folded.reaction;
    end

    if (folded.dead ~= nil) then
        if (dead ~= nil and dead ~= folded.dead) then
            return EmptyUnitCondition(out);
        end
        dead = folded.dead;
    end

    if (folded.role ~= nil) then
        if (role == nil) then
            role = folded.role;
        else
            local met = band(role, folded.role);
            if (met == 0 and role ~= 0 and folded.role ~= 0) then
                return EmptyUnitCondition(out);
            end
            role = met;
        end
    end

    if (folded.frameTypes ~= nil) then
        frameTypes = frameTypes and band(frameTypes, folded.frameTypes) or folded.frameTypes;
    end

    if (folded.group ~= nil) then
        group = group and band(group, folded.group) or folded.group;
    end

    return WriteUnitCondition(out, reaction, dead, role, frameTypes, group);
end
DebindPrivate.FoldUnitCondition = FoldUnitCondition;

local SOURCE_ROW = 1;
local SOURCE_AT = 2;
local SOURCE_SKIP = 8;
local SOURCE_TWIN = 16;
DebindPrivate.UNIT_SOURCE_ROW = SOURCE_ROW;
DebindPrivate.UNIT_SOURCE_AT = SOURCE_AT;

--- Fold everything that says something about a unit onto one condition per unit
--- (`binding.unitConditions`), and read the solver's columns off it.
---
--- **The record goes out with `unitConditions` as it is** (`KeyRecords.lua`), so what the solver
--- judged and what the press checks are one table.
---
--- The point of doing it here is that **the pointed frame's unit is just a unit, named
--- "unitframe"**. Kept apart, the `unitframe` condition and a unit condition on the same unit are
--- two columns describing one thing, and the solver cannot see that `unitframe=friendly` with
--- `@=hostile` never holds -- it keeps a binding that can never fire and warns about nothing.
---
--- **A mouse button adds nothing of its own.** Its records stand on the frame path as well as the
--- key path unless they rule the frame out (`KeyRecords.lua`'s `PrepareKeyBindings`), so a box
--- that spans the frame half is a record that really reaches it.
local function BuildUnitStates(binding)
    local sources = binding.unitSources;
    if (sources == nil) then
        sources = {};
        binding.unitSources = sources;
    else
        wipe(sources);
    end
    local folded = binding.unitConditions;
    if (folded == nil) then
        folded = {};
        binding.unitConditions = folded;
    else
        wipe(folded);
    end
    -- **One table per unit for the life of the binding**, which every refill writes into.
    local owned = binding.unitConditionTables;
    if (owned == nil) then
        owned = {};
        binding.unitConditionTables = owned;
    end

    local function add(unit, row, source)
        local out = owned[unit];
        if (out == nil) then
            out = {};
            owned[unit] = out;
        end
        folded[unit] = FoldUnitCondition(unit, folded[unit], row, out);
        sources[unit] = bor(sources[unit] or 0, source);
    end

    --- `"@"` and a resurrection branch's own row both land on the unit the binding aims at. A `unit`
    --- that is not a name has none, and its action is left out by `INVALID_ACTION`.
    local function addAimed(row)
        local unit = ResolvedUnitOf(binding);
        if (unit ~= nil) then
            add(unit, row, SOURCE_AT);
        end
    end

    local conditions = binding.conditions;
    local units = conditions and conditions.units;

    if (binding.skipsPointedUnit) then
        add(binding.skipsPointedUnit, false, SOURCE_SKIP);
    end
    if (units) then
        for key, value in pairs(units) do
            if (key == "@") then
                addAimed(value);
            else
                add(key, value, key == binding.twinOwnUnit and SOURCE_TWIN or SOURCE_ROW);
            end
        end
    end
    if (binding.branchUnit ~= nil) then
        addAimed(binding.branchUnit);
    end

    local states, groups;
    for unit, condition in pairs(folded) do
        states = states or {};
        states[unit] = UnitConditionToState(condition);
        -- **Its own column, per unit.** Unlike role it can be asked of any unit.
        if (type(condition) == "table" and condition.group ~= nil) then
            groups = groups or {};
            groups[unit] = condition.group;
        end
    end

    --- **Role and frame types are one column each, not one per unit**, since only the pointed
    --- frame's unit carries them (`FrameAxesOn`). `false` for [when there is none] carries neither:
    --- the menu remembers axes under a mode that does not use them, and the fold drops them there.
    local pointed = folded.unitframe;
    if (type(pointed) == "table") then
        binding.unitRole = pointed.role;
        binding.unitFrameTypes = pointed.frameTypes;
    else
        binding.unitRole = nil;
        binding.unitFrameTypes = nil;
    end

    binding.unitStates = states;
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

--- Whether a role mask of zero leaves this binding nowhere. **Not where the frame types reach past
--- party and raid frames**: the role is measured on those alone, and the binding still runs over the
--- rest (`RoleMeasuredUnder`). The zero is always a row that picked no role; two picked sets that do
--- not meet fold to no unit at all (`FoldUnitCondition`).
local function RoleLeavesNothing(binding)
    local _, onlyGroup = RoleMeasuredUnder(binding.unitFrameTypes);
    return onlyGroup;
end
DebindPrivate.RoleLeavesNothing = RoleLeavesNothing;
