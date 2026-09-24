local _, DebindPrivate = ...;
local Constants                    = DebindPrivate.Constants;

local band                         = bit.band;
local bor                          = bit.bor;

local UnitConditionForBinding      = DebindPrivate.UnitConditionForBinding;
local UnitFrameConditionFromLegacy = DebindPrivate.UnitFrameConditionFromLegacy;
local UnitGroupToCells             = DebindPrivate.UnitGroupToCells;
local CellsToUnitGroup             = DebindPrivate.CellsToUnitGroup;
local BuildUnitStates              = DebindPrivate.BuildUnitStates;
local RoleLeavesNothing            = DebindPrivate.RoleLeavesNothing;

--- The unit a binding's cast goes out at: its `unit`, except on `none`, where `unit` is only what the
--- press aims at and the cast itself always asks (`ActionHasPickedUnit`).
function DebindPrivate.CastUnitOf(binding)
    if (binding.castsAtNone) then
        return "none";
    end
    return binding.unit;
end

--- Whether this binding cannot stand. **Given `visit`, every reason is handed to it** as the unit
--- the zero sits on and whether it is the solo rule, until `visit` returns true. The issue check
--- paints from those reasons, and a second copy of the rule there would drift from the one
--- `BuildKeyMap` leaves bindings out by.
---
--- **The solo reasons skip a zero**: that unit already has a reason of its own, and handing it
--- twice would paint the groups menu for a contradiction it has no part in.
---
--- **A verdict on the binding, not on one condition**, which is why it is not in `Units.lua`: the
--- solo rule holds the `groups` condition against the unit ones.
local function CannotStand(binding, visit)
    if (binding.unitStatesOpaque) then
        return false;
    end
    local function found(unit, solo)
        return visit == nil or visit(unit, solo) == true;
    end

    local states = binding.unitStates;
    if (states) then
        for unit, mask in pairs(states) do
            if (mask == 0 and found(unit, false)) then
                return true;
            end
        end
    end
    if (binding.unitGroups) then
        for unit, mask in pairs(binding.unitGroups) do
            if (mask == 0 and found(unit, false)) then
                return true;
            end
        end
    end
    -- Only a `unitframe` row, or a `"@"` landing there, narrows these two (`BuildUnitStates`).
    if ((binding.unitFrameTypes == 0 or (binding.unitRole == 0 and RoleLeavesNothing(binding)))
            and found("unitframe", false)) then
        return true;
    end

    -- **Solo only, against a unit that has to be there.** The role aliases and the role map are empty
    -- while the reader is alone (`showSolo = false`, `UnitWatch.lua`). `UNITSTATE_NONE` or
    -- `ROLE_NONE` still in the mask is [when there is none] or [unknown], which solo satisfies.
    local groups = binding.conditions and binding.conditions.groups;
    if (groups and band(groups, Constants.GROUP_ALL - Constants.GROUP_NONE) == 0) then
        local role = binding.unitRole;
        if (role and role ~= 0 and band(role, Constants.ROLE_NONE) == 0 and found("unitframe", true)) then
            return true;
        end
        if (states) then
            local absentWhenSolo = DebindPrivate.UNITS_ABSENT_WHEN_SOLO;
            for unit, mask in pairs(states) do
                if (absentWhenSolo[unit] and mask ~= 0 and band(mask, Constants.UNITSTATE_NONE) == 0
                        and found(unit, true)) then
                    return true;
                end
            end
        end
    end
    return false;
end
DebindPrivate.CannotStand = CannotStand;

do
    local _ActionToBindingCache = setmetatable({}, { __mode = "kv" });

    -- The stored shape of "that unit, whatever it is" is an empty table (`false` is [when there is
    -- none]); the emitter indexes it, so it cannot be `true`. Read-only downstream, hence one table.
    --
    -- **This is what keeps the twin from deleting the original.** Empty reads as
    -- `UNITSTATE_EXISTS` (`UnitConditionToState`), so the twin's box is the half of the axis where
    -- the unit is there and the original still covers the other half. A twin standing with no
    -- condition at all would cover the original, the solver would drop it, and the key would do
    -- nothing at the moment nothing is pointed at.
    local UNIT_IS_THERE = {};

    --- A resurrection branch's own condition on the aimed unit, met with the reader's on the same
    --- `"@"`. Answers the table to store, `false` for [when there is none], or nil where the two
    --- cannot both hold. A branch that asks for a corpse under a reader who asked for no target is
    --- one of those.
    ---
    --- **The group axis is met in cells**, as `IntersectStoredUnitConditions` does: the three values
    --- overlap, so a bit mask `band` is not the intersection in general.
    local function MeetResurrectUnit(existing, want)
        if (existing == nil) then
            if (want == false) then
                return false;
            end
            local out = {};
            for k, v in pairs(want) do
                out[k] = v;
            end
            return out;
        end
        if (existing == false or want == false) then
            if (existing == false and want == false) then
                return false;
            end
            return nil;
        end
        local out = {};
        for k, v in pairs(existing) do
            out[k] = v;
        end
        if (want.reaction ~= nil) then
            out.reaction = out.reaction and band(out.reaction, want.reaction) or want.reaction;
            if (out.reaction == 0) then
                return nil;
            end
        end
        if (want.dead ~= nil) then
            if (out.dead ~= nil and out.dead ~= want.dead) then
                return nil;
            end
            out.dead = want.dead;
        end
        if (want.group ~= nil) then
            if (out.group == nil) then
                out.group = want.group;
            else
                local cells = band(UnitGroupToCells(out.group), UnitGroupToCells(want.group));
                if (cells == 0) then
                    return nil;
                end
                out.group = CellsToUnitGroup(cells);
            end
        end
        return out;
    end

    --- No unit satisfies it: exists, and in none of the three reactions. The shape
    --- `IntersectStoredUnitConditions` uses for the same answer.
    local NO_UNIT = { reaction = 0 };

    --- Puts a resurrection branch's combat and target conditions on top of the reader's.
    ---
    --- **Where the two contradict, the branch still stands as one that cannot**, so the issue check
    --- sees it (`EvaluateIssues`). Left out of the list, every branch ruled out by the reader's own
    --- conditions left only the original holding the key and no mark on the row. A contradiction
    --- on the target writes a unit nothing satisfies, which the unit menus are painted for; one on
    --- combat has no such shape and answers `"combat"` for the caller to mark.
    local function ApplyResurrectBranch(conditions, branch)
        local units = conditions.units;
        local met = MeetResurrectUnit(units and units["@"], branch.unit);
        conditions.units = units or {};
        conditions.units["@"] = met == nil and NO_UNIT or met;
        if (branch.combat ~= nil) then
            if (conditions.combat ~= nil and conditions.combat ~= branch.combat) then
                return "combat";
            end
            conditions.combat = branch.combat;
        end
        return nil;
    end

    --- 액션을 바인딩으로.
    ---
    --- 이 함수에만 있는 사실 셋:
    ---
    --- **흐름이 한 방향이다.** 바인딩은 액션에서 다시 만들어지고 액션으로 되쓰이지 않는다.
    --- 그래서 아래 정규화가 사용자가 적은 것을 안 건드린다.
    ---
    --- **표를 재사용한다.** 캐시에서 꺼내 제자리에서 덮어쓰므로, 조건부로만 쓰는 필드는 이전
    --- 리빌드의 값이 남는다. `conditions`를 `wipe`하는 줄이 그것을 막는 자리다.
    ---
    --- **순서 필드는 여기 없다.** 어느 액션이 먼저 발동하느냐는 액션 하나로 답이 안 나오는
    --- 유일한 것이라, 그쪽은 `MakeOrderRecord`가 따로 든다.
    ---
    --- The original is called with the action's `unit` and nothing else. **A twin is called with
    --- `castModifier`, and that is what makes it one**: its `aimedUnit` is already the unit it goes
    --- out at, so nothing below strips or fills it (`GetBindingsForAction` works it out). A hover
    --- twin also brings `twinCondition`, which lands under `pointedUnit`.
    ---
    --- **`unit` has to arrive with the call**: the `unitframe` fill-in and `BuildUnitStates` at the end
    --- both read it, so changing `unit` on a filled binding leaves `"@"` standing on the old unit.
    ---
    --- **`dead` is asked of each binding, not of the action**
    --- (`rewriting-evaluate-issues.md` §2-2). `"@"` lands on the unit each binding
    --- aims at, so one action can have twins that stand beside an original that cannot, or the other
    --- way round. Nothing downstream drops such a binding, so `BuildKeyMap` leaves it out itself.
    ---
    --- **`unitSources` keeps what narrowed each unit's mask**, because a zero does not say which
    --- menu made it. `twinOwnUnit` is what tells the hover twin's own [the unit is there] apart from
    --- a row the reader wrote: both sit in `conditions.units` by the time `BuildUnitStates` reads it.
    local function FillBinding(binding, action, aimedUnit, twinCondition, castModifier, pointedUnit,
            knownSpell, branch)
        local twin = castModifier ~= nil;
        -- **The pre-rename spelling of the target, for the profiles the ladder has not reached.**
        -- `dbver <= 6` renames a stored `unit = "hover"` alongside the condition; the unit table
        -- below carries the same shim for the same reason. Left as it is, `binding.unit` holds a
        -- name nothing answers to any more: the click path does not recognise it
        -- (`UpdateBindings.lua`'s `isClickCast`) and the emitter finds it in neither
        -- `SPECIAL_UNITS` nor `BASIC_UNITS`, so the action goes out with no unit at all.
        if (aimedUnit == "hover") then
            aimedUnit = "unitframe";
        end
        binding.type, binding.value = action.type, action.value;
        binding.pinRank = action.pinRank;
        binding.resolvedSpellID = action.resolvedSpellID;
        -- **Only the binding changes.** The action keeps the type it was saved with, so its row
        -- still says what it was, and an older build reading the same SavedVariables still runs it.
        if (action.type == Constants.UNUSED or action.type == Constants.COMMAND) then
            binding.type = Constants.BLOCK;
        end
        -- **The three spec-resolved types put their spell here and leave `value` alone.** What the
        -- action stores is the kind; which spell that is today is this specialization's answer
        -- (`SpecSpells.lua`), and every reader of the binding that wants a spell id reads this
        -- field ahead of `value`.
        --
        -- `spellToCast` is what the button carries where it is not `spell`: the warlock's dispel
        -- goes out under a spell it is not named after (`SpecSpells.lua`). The row, the tooltip and
        -- the name stay on `spell`.
        local gate;
        if (Constants.SPEC_RESOLVED_TYPES[action.type]) then
            binding.spell, gate = DebindPrivate.SpecSpells.SpellForType(action.type);
        else
            binding.spell = nil;
        end
        binding.spellToCast = gate and gate.cast or nil;
        -- **Only the original answers a press with nothing held and nothing pointed at**, so this is
        -- the original's field: the twins each stand in a tier of their own and Normal Cast says
        -- nothing about those tiers. `BuildKeyMap` reads it to leave the original out of the last
        -- tier (`which-action-a-key-runs.md` §6). The bare left and right click have no
        -- original whatever the box says: it would hold the key and take the world click (§7).
        if (twin or (DebindPrivate.NormalCastEnabled(action)
                and not DebindPrivate.IsBareWorldClick(action.key))) then
            binding.normalCast = nil;
        else
            binding.normalCast = false;
        end

        binding.unit = aimedUnit;
        binding.key = action.key;

        -- **조건은 한 표를 통째로 옮긴다.** 예전에는 열두 줄이 손으로 적혀 있었고, 축이
        -- 하나 늘 때마다 이 줄을 잊으면 그 조건이 바인딩에 도착하지 않았다. 조용히 넓어지는
        -- 쪽이라 아무도 못 잡는다.
        --
        -- 표는 **재사용한다.** 아래 정규화가 제자리에서 nil을 쓰므로 액션 쪽 표를 그대로
        -- 가리키면 사용자가 건 조건을 지우게 된다.
        -- **The refill has to clear this too.** It is set from the conditions below and the table
        -- is reused, so a binding once marked opaque stayed opaque for the life of the action --
        -- the reader fixes the condition the menu could not read and the binding still covers
        -- nothing and is covered by nothing. Reachable only by luck before `_ActionToBindingsCache`
        -- held strong values; now the table never goes away.
        binding.unitConditionUnreadable = nil;

        local conditions = binding.conditions;
        if (conditions == nil) then
            conditions = {};
            binding.conditions = conditions;
        else
            wipe(conditions);
        end
        if (action.conditions) then
            for k, v in pairs(action.conditions) do
                -- **무시로 지정된 스위치는 안 담는다.** 값을 거짓으로 답하는 것이 아니라 조건
                -- 항 자체가 없던 것이 되므로, 이 표에 안 들어오는 것이 그대로 뜻이다. 솔버는
                -- 표에 있는 이름으로만 컬럼을 세우고(`Solver.lua`), `CollectRecordNeeds`도
                -- 여기서 나온 것만 거둔다.
                --
                -- 리빌드 때 펴도 되는 이유: `mode`는 사용자 편집이나 전문화 전환에서만 움직이고
                -- 둘 다 전투 중이 아니다. 누를 때 다시 잴 것이 없다.
                if (not (Constants.IsSwitchName(k) and DebindPrivate.IsSwitchIgnored(k))) then
                    conditions[k] = v;
                end
            end
        end

        -- 저장 모양 -> 바인딩 모양. 꺼진 조건은 여기서 빠지므로 하류는 기억을 안 만난다.
        -- 남는 것이 없으면 표 자체를 안 만든다 - `conditions.units`가 있느냐를 게이트로
        -- 쓰는 자리가 여럿이라(이슈 검사, `IsConditionalBinding`), 빈 표는 조건이 하나도
        -- 없는 액션을 조건부로 만든다.
        conditions.units = nil;
        -- **평면 `action.checkedUnits`도 받는다.** 나간 적 있는 프로필이 그 모양이고
        -- (`dbver <= 5`가 옮기기 전), 바로 아래 옛 `hover`/`reactions` 쌍이 같은 이유로
        -- 여기 있다. 한쪽만 받으면 마이그레이션이 아직 안 닿은 액션의 유닛 조건만 조용히
        -- 사라지는데, **조건이 사라진 바인딩은 넓어져서 남의 키를 가져간다.**
        --
        -- 나머지 축은 안 받는다. 그것들은 값이 스칼라라 중첩 여부가 뜻을 안 바꾸고,
        -- 액션 최상단을 한 번 더 훑는 값이 리빌드마다 붙는다.
        -- **옛 이름을 `rawget`으로 읽는다.** 마이그레이션 전 프로필의 최상단 이름은
        -- `checkedUnits`다(`dbver <= 5`가 옮기면서 `units`로 바꾼다). 최상단에서 조건
        -- 이름을 읽으면 DEBUG 함정이 터지는데(`Profile.lua`의 `ArmAction`), 여기는 그 옛
        -- 자리를 **일부러** 보는 유일한 자리다. 함정을 우회하는 것이 아니라, 함정이 잡으려는
        -- 실수가 아니라는 표시다.
        local storedUnits = (action.conditions and action.conditions.units)
            or rawget(action, "checkedUnits");
        if (storedUnits) then
            for unit, value in pairs(storedUnits) do
                -- **The pre-rename spelling is read here too.** A profile the ladder has not
                -- reached yet calls the pointed frame's unit `hover`, and the legacy lift just
                -- below writes `unitframe` -- so left alone, one unit arrives as two columns,
                -- which is the split the fold exists to remove. `dbver <= 6` renames what is
                -- stored; this is the same rule on the copy, for the profiles it has not met.
                if (unit == "hover") then
                    unit = "unitframe";
                end
                local condition, unreadable = UnitConditionForBinding(value);
                if (unreadable) then
                    -- 이 빌드가 못 읽는 값이 하나라도 있으면 바인딩을 판정에서 뺀다
                    -- (`BuildUnitStates`가 이 표시를 `unitStatesOpaque`로 바꾼다).
                    binding.unitConditionUnreadable = true;
                end
                if (condition ~= nil) then
                    conditions.units = conditions.units or {};
                    conditions.units[unit] = condition;
                end
            end
        end

        -- Same idea for the old hover pair. It is raised **onto the copy**, never onto the
        -- action: `Migration.lua` owns rewriting what is stored, and an action this
        -- reached first would otherwise be rewritten by whoever read it.
        if (action.hover ~= nil) then
            conditions.units = conditions.units or {};
            conditions.units.unitframe = UnitFrameConditionFromLegacy(
                action.hover, action.reactions, conditions.units.unitframe);
        end

        -- The frame type mask, likewise raised onto the copy. It was a condition of its own until
        -- the pointed frame's unit became an ordinary unit (`dbver <= 6`); a profile the ladder has
        -- not reached carries it at the action's top level or right under `conditions`, and both
        -- have to be cleared off the binding or the name sits there as a condition nothing reads --
        -- which is enough to make an unconditional action rank as a conditional one
        -- (`IsConditionalBinding`).
        --
        -- **Only onto a condition that is a table.** Nothing else can hold an axis: the absent
        -- point is not a frame, and with no `unitframe` condition at all there is no frame to have
        -- a type. The mask is dropped there rather than inventing a condition nobody set.
        local legacyFrameTypes = action.frameTypes or conditions.frameTypes;
        conditions.frameTypes = nil;
        if (legacyFrameTypes ~= nil and legacyFrameTypes ~= Constants.FRAMETYPE_ALL) then
            local row = conditions.units and conditions.units.unitframe;
            if (type(row) == "table" and row.frameTypes == nil) then
                row.frameTypes = legacyFrameTypes;
            end
        end

        -- **Under the unit the twin aims at, not under a fixed name.** That is what narrows the
        -- twin's box to [the unit is there] on that unit's own axis (`BuildUnitStates`), which is
        -- what lets the original take the rest.
        --
        -- **The merge already happened.** `TwinUnitFor` hands over the reader's own condition where
        -- that unit carries one and `UNIT_IS_THERE` where it does not, so what is written here is
        -- the meeting point either way.
        binding.twinOwnUnit = nil;
        if (twinCondition ~= nil) then
            conditions.units = conditions.units or {};
            conditions.units[pointedUnit] = twinCondition;
            if (twinCondition == UNIT_IS_THERE) then
                binding.twinOwnUnit = pointedUnit;
            end
        end

        -- 커스텀 상태를 따로 도는 루프가 여기 있었다. 위 벌크 복사가 조건 표를 통째로
        -- 옮기므로 슬롯 다섯을 이름으로 세어줄 필요가 없고, 재설계가 임의 이름을 풀어도
        -- 이 자리가 안 바뀐다.

        -- **A type with no spell carries no `known` at all**, whatever the value is. The question
        -- does stand on its own now that the value names a spell
        -- (`making-known-a-spell-name.md`), but no menu offers it on those types, so a
        -- value there is one the reader could not have made and cannot take off. `CleanUpDB` takes
        -- it out of storage for the same reason; this is the same rule on the binding.
        --
        -- **`false` has no state that satisfies it.** It would say "cast it only while it is
        -- unlearned" of the action's own spell, and it is checked against `false` rather than
        -- truthiness because nothing here writes one but a shared profile can carry one, and left
        -- in place it bakes the same conditional a `true` would.
        if (conditions.known == false or (conditions.known ~= nil
                and binding.type ~= Constants.SPELL
                and not Constants.SPEC_RESOLVED_TYPES[binding.type])) then
            conditions.known = nil;
        end

        -- **A spec-resolved spell is cast only under a `known`, ticked or not** (2026-09-23,
        -- owner). A binding that casts asks about one spell, `knownSpell`: an id of the warlock's
        -- (`SpecSpells.lua`), or `true` for the spell this specialization resolves to. Unticked,
        -- the binding the reader sees is `holdsOnly`: it keeps the key and casts nothing, and the
        -- ones that cast stand ahead of it (`GetBindingsForAction`). A class that has not learned
        -- its dispel then looks like one that has none (§4 of `adding-spec-resolved-actions.md`)
        -- instead of sending a cast for the game to refuse, and the warlock's Command Demon, which
        -- casts whatever the demon that is out has, never goes out as a Spell Lock.
        --
        -- **Ticked, the binding the reader sees asks about the first id itself**, rather than that
        -- being the derivation's business, because this function is what every caller of
        -- `GetBindingInfoForAction` gets and it has to answer the same thing every time it runs.
        -- A `known` naming a spell is a different question and is left as it is.
        --
        -- **`skipWhenUnusable` is the ticked box under the reader's own name for it** (2026-09-23,
        -- owner): "hand the key on when there is nothing to cast", whatever the reason is. Ticking
        -- `known` as well changes nothing. With no spell at all it reaches `KnownConditionCanHold`
        -- the same way, and the action leaves the build.
        if (conditions.known == nil and action.skipWhenUnusable
                and Constants.SPEC_RESOLVED_TYPES[binding.type]) then
            conditions.known = true;
        end
        --
        -- **A resurrection's branch is a binding like the dispel's ids**, with its own spell and the
        -- conditions that pick it on top of the reader's (`ApplyResurrectBranch`). Its original has
        -- no one spell to cast, so ticked it is `omitted` rather than asking about one.
        binding.holdsOnly = nil;
        binding.omitted = nil;
        binding.combatContradicts = nil;
        if (branch ~= nil) then
            conditions.known = branch.spell;
            binding.spellToCast = branch.spell;
            binding.combatContradicts = ApplyResurrectBranch(conditions, branch) == "combat" or nil;
        elseif (binding.spell ~= nil) then
            if (knownSpell ~= nil) then
                conditions.known = knownSpell;
            elseif (conditions.known == true) then
                if (binding.type == Constants.RESURRECT) then
                    binding.omitted = true;
                else
                    conditions.known = gate and gate.known[1] or true;
                end
            elseif (conditions.known == nil) then
                binding.holdsOnly = true;
            end
        end


        -- `"@"` and an explicit condition on the same unit used to be folded into one key here, by
        -- hand, for the scalar shape. **Both consumers intersect them themselves now**:
        -- `BuildUnitStates` with `band` for the solver, and `mergeUnitConditions` per axis on the way
        -- to the snippet. Folding again would be a third copy of one rule, and the one that drifts is
        -- the one nothing checks.
        --
        -- **No target drops `"@"`, `none` included** (2026-09-15, owner). `none` is aimed like an
        -- action with no target and only its cast asks, so each binding of it has a unit to ask.

        if (conditions.groups and band(conditions.groups, Constants.GROUP_ALL) == Constants.GROUP_ALL) then
            conditions.groups = Constants.GROUP_ALL;
        end

        -- **`specs` is not folded, unlike the masks around it.** Those fold an all-on mask to the
        -- one value that says "every box ticked", so a condition constraining nothing has one
        -- shape rather than two. A set of specialization ids has no such value: the ids of one
        -- class are not an accident to normalize away, they are the class condition itself.

        if (conditions.forms and band(conditions.forms, Constants.FORM_ALL) == Constants.FORM_ALL) then
            conditions.forms = Constants.FORM_ALL;
        end

        if (conditions.bonusbars and band(conditions.bonusbars, Constants.BONUSBAR_ALL) == Constants.BONUSBAR_ALL) then
            conditions.bonusbars = Constants.BONUSBAR_ALL;
        end

        -- 대상을 못 갖는 타입이면 지운다. 목록은 `Constants.TYPES_WITH_UNIT` 하나뿐이다 -
        -- 대상 메뉴를 여는 쪽(`DropDownMenus.lua`)도 같은 값을 본다. 예전에는 여기와
        -- 저기에 같은 목록이 손으로 하나씩 적혀 있었고, 한쪽에만 타입을 넣는 바람에
        -- **화면에는 대상이 보이는데 나가는 매크로에는 없는** 상태가 나왔다.
        --
        -- **Not on a twin.** A twin of an action that takes no unit still carries `player` or
        -- `focus`, which is what the client's `UnitExists` guard reads: the press stops where there
        -- is no focus, as it does on an action bar.
        --
        -- **`none` keeps no unit here and goes out as `none` all the same** (`CastUnitOf`). Left in
        -- `unit`, it would be where `"@"` is asked and where the `unitframe` condition fills in, and neither
        -- has a unit to stand on there.
        binding.castsAtNone = (action.unit == "none" and DebindPrivate.ActionTakesUnit(binding)) or nil;
        -- **쌍둥이도 같은 액션이라 같은 값을 든다.** 어느 누름으로 나가든 클라이언트의 자동
        -- 동작을 어떻게 둘지는 액션이 정한 하나다.
        binding.automatics = DebindPrivate.CastAutomaticsKeyOf(action);
        if (twin) then
            binding.unit = aimedUnit;
        elseif (not Constants.TYPES_WITH_UNIT[binding.type]) then
            binding.unit = nil;
        elseif (not DebindPrivate.ActionTakesUnit(binding)) then
            -- The type alone does not settle a pet command or an action button, and the target menu
            -- asks the same question. Cleared here too, or a unit left in an old profile goes out.
            binding.unit = nil;
        elseif (binding.castsAtNone) then
            binding.unit = nil;
        end

        -- **Every original stands on [none held]**, whatever its type or target: every action has
        -- the self and focus twins, so a held modifier is answered among those and never by an
        -- original placed ahead of them (`implementing-focus-and-self-cast.md` §3-4).
        binding.castModifier = castModifier or Constants.CASTMOD_NONE;
        binding.hoverTwin = pointedUnit ~= nil or nil;

        -- **An action that takes no unit keeps `"@"`** (2026-09-15, owner). It asks the unit the
        -- press aims at, and whether the action does anything with that unit cannot be known: every
        -- action has the self and focus twins, and a macro body can aim wherever it likes.

        if (conditions.petbattle and conditions.specialbar) then
            conditions.specialbar = nil;
        end

        -- **A unit frame condition fills no target in.** With no unit picked the original lets the
        -- game place the cast, condition or no condition (`which-action-a-key-runs.md` §5);
        -- the pointed unit is reached through the hover twin, which is what the condition's own
        -- action is carried over as (§8). The fill-in that used to sit here put `unitframe` in
        -- `unit`, which made an ordinary press over nothing cast at a unit that was not there.

        BuildUnitStates(binding);
        binding.dead = (CannotStand(binding) or binding.combatContradicts) or nil;

        return binding;
    end

    function DebindPrivate.GetBindingInfoForAction(action)
        local binding = _ActionToBindingCache[action];

        if (not binding) then
            binding = {};
            _ActionToBindingCache[action] = binding;
        end

        return FillBinding(binding, action, action.unit, nil);
    end

    --- Does a switch a person toggles print a line? Absent means on, so a profile written before
    --- the option reads as on.
    function DebindPrivate.SwitchMessagesEnabled()
        local options = DebindPrivate.Options;
        return not (options and options.switchMessages == false);
    end

    --- The three places Debind hands a key it holds back to the game, and the two values that
    --- narrow what goes over (`giving-keys-back.md` §7).
    ---
    --- **Two of the three are on with the value absent and one is off**, so which way a reader is
    --- asked differs per row. What decides it is whether the situation happens in a fight: a pet
    --- battle and the house editor do not, so a key handed over there costs the reader nothing,
    --- while a replaced bar is usually mid-fight and a key that does something else there is the
    --- loss itself.
    function DebindPrivate.GiveBackOnReplacedBar()
        local options = DebindPrivate.Options;
        return (options and options.giveBackOnReplacedBar) and true or false;
    end

    --- Narrows the row above to the buttons whose slot holds something.
    function DebindPrivate.GiveBackWhenActionExists()
        local options = DebindPrivate.Options;
        return (options and options.giveBackWhenActionExists) and true or false;
    end

    function DebindPrivate.GiveBackInPetBattle()
        local options = DebindPrivate.Options;
        return not (options and options.giveBackInPetBattle == false);
    end

    --- The house editor and whatever else opens a binding context. **This one was running before it
    --- was an option**, which is why absent reads as on: the keys a context claims were never ours
    --- to hold (`BindingContexts.lua`).
    function DebindPrivate.GiveBackInBindingContext()
        local options = DebindPrivate.Options;
        return not (options and options.giveBackInBindingContext == false);
    end


    --- One value of `action.casting`. **The stored table is not trusted to hold a name we know**: a
    --- payload carries whatever it was written with, so an unknown value has to read as the default,
    --- which is what an action with no `casting` at all has.
    local function CastingValue(action, name)
        local casting = action and action.casting;
        return casting and casting[name];
    end

    --- Whether that press's twin goes out at the unit the press names, or the way the original does.
    --- "Cast as usual" is the second: the twin keeps its turn in that tier and lets the game place
    --- the cast, Auto Self Cast included (`which-action-a-key-runs.md` §6).
    local function CastsAsUsual(action, name)
        return CastingValue(action, name) == "usual";
    end

    --- The settings tab's Hover Cast mode, which an action follows unless it names one of its own.
    --- Absent reads as Unit Frames, because that is where the condition it replaces stood
    --- (`which-action-a-key-runs.md` §8).
    function DebindPrivate.AccountHoverCastMode()
        local options = DebindPrivate.Options;
        if (options and options.hoverCastMode == "mouseover") then
            return "mouseover";
        end
        return "unitframe";
    end

    --- The unit this action counts as pointed at. **`hover` is a name storage uses and this is where
    --- it stops**: everything below reads `unitframe` or `mouseover`
    --- (`which-action-a-key-runs.md` §0).
    ---
    --- **A skipped action has a mode too**: it names the unit whose presence takes the action off the
    --- press (`HoverCastSkipped`).
    ---
    --- **Asked of no action it answers the account's mode**, which is what the settings tab shows.
    ---
    --- **The bare left and right click answer Unit Frames whatever the action or the tab says**
    --- (`which-action-a-key-runs.md` §7). The key is never held there, so a Mouseover twin
    --- would have to take the world click to stand at all.
    function DebindPrivate.HoverCastMode(action)
        if (action and DebindPrivate.IsBareWorldClick(action.key)) then
            return "unitframe";
        end
        local mode = CastingValue(action, "hoverCastMode");
        if (mode == "unitframe" or mode == "mouseover") then
            return mode;
        end
        return DebindPrivate.AccountHoverCastMode();
    end

    --- Whether Debind answers the Self Cast Key and the Focus Cast Key for this action. **Absent
    --- means on** on both levels, which is how every key behaved before either value existed. Off is
    --- no twin and no question at the press, never the game's own handling
    --- (`implementing-focus-and-self-cast.md` §3-12).
    ---
    --- **The account's box and the action's value are one answer.** With the box off the tier is not
    --- built at all, so the action's value has nothing to say there
    --- (`which-action-a-key-runs.md` §6); asked of no action, this is the box alone, which
    --- is what the emitter wires the press up from.
    function DebindPrivate.SelfCastEnabled(action)
        local options = DebindPrivate.Options;
        if (options and options.selfCast == false) then
            return false;
        end
        return CastingValue(action, "selfCastKey") ~= "skip";
    end

    function DebindPrivate.FocusCastEnabled(action)
        local options = DebindPrivate.Options;
        if (options and options.focusCast == false) then
            return false;
        end
        return CastingValue(action, "focusCastKey") ~= "skip";
    end

    --- What Hover Cast answers for this action: the pointed unit (`"cast"`), where the press would
    --- have gone anyway (`"usual"`), or nil for off, which is the default and means no twin at all.
    ---
    --- **Off leaves the original where it was**, in the last tier, so the action still answers a
    --- pointed press when nothing ahead of it does. Keeping it out of the pointed press is a
    --- condition the reader writes on that unit, not a value here
    --- (`which-action-a-key-runs.md` §6).
    ---
    --- **The bare left and right click answer `"cast"` whatever is stored** (§7). The only press
    --- those keys can serve is a click on a unit frame, so off would leave the action with nothing.
    function DebindPrivate.HoverCastChoiceOf(action)
        if (action and DebindPrivate.IsBareWorldClick(action.key)) then
            return "cast";
        end
        local value = CastingValue(action, "hoverCast");
        if (value == "cast" or value == "usual") then
            return value;
        end
        return nil;
    end

    --- Which of the three a press holds: the action goes to that press's unit (`"cast"`), where the
    --- press would have gone anyway (`"usual"`), or it is out of that press (`"skip"`). The same three
    --- on all three rows (`which-action-a-key-runs.md` §6).
    function DebindPrivate.CastKeyChoiceOf(action, row)
        local value = CastingValue(action, row);
        if (value == "usual" or value == "skip") then
            return value;
        end
        return "cast";
    end

    --- Whether the action stands on a press with nothing held and nothing pointed at. Off is the
    --- original not being made, so the press falls through to the next action on the key -- which is
    --- what the old [when a frame is pointed at] condition did, without swallowing the press
    --- (`which-action-a-key-runs.md` §6).
    function DebindPrivate.NormalCastEnabled(action)
        local casting = action and action.casting;
        return not (casting and casting.normalCast == false);
    end

    --- 누르는 동안 클라이언트의 자동 동작을 액션이 정하는 네 줄. **이름이 CVar 이름 그대로이고,
    --- 순서가 화면에 서는 순서다** (`setting-the-clients-cast-automatics-per-action.md` §1).
    DebindPrivate.CAST_AUTOMATIC_ROWS = {
        "autoSelfCast",
        "autoUnshift",
        "autoDismount",
        "autoDismountFlying",
    };

    --- 네 줄의 값을 한 글자씩 적은 열쇠, 또는 넷 다 기본이면 `nil`. 켬이 `1`, 끔이 `0`,
    --- 게임 설정 그대로가 `-`다.
    ---
    --- **버튼을 가르는 것이 이 열쇠다.** 값은 액션마다 빌드 때 확정되므로 감싼 본문도 그때
    --- 정해지고, `(종류, 값)`으로만 잡힌 버튼은 값이 다른 액션 둘에게 같은 본문을 준다
    --- (`setting-the-clients-cast-automatics-per-action.md` §4).
    ---
    --- **`nil`은 "감쌀 것이 없다"는 뜻이고 그 액션은 버튼을 감싸지 않는다.** 클라이언트가 하던
    --- 그대로 나가는 것이 넷 다 기본일 때의 동작이다.
    function DebindPrivate.CastAutomaticsKeyOf(action)
        local rows = DebindPrivate.CAST_AUTOMATIC_ROWS;
        local key, any = "", false;
        for i = 1, #rows do
            local value = DebindPrivate.CastAutomaticOf(action, rows[i]);
            if (value == nil) then
                key = key .. "-";
            else
                key = key .. (value and "1" or "0");
                any = true;
            end
        end
        return any and key or nil;
    end

    --- 열쇠에서 그 줄의 값을 읽는다. `CastAutomaticOf`의 열쇠 쪽 짝이고, 액션이 안 닿는
    --- 자리에서 쓴다. 이름으로 자리를 찾으므로 줄의 순서가 바뀌어도 따라간다.
    function DebindPrivate.CastAutomaticInKey(key, row)
        if (key == nil) then
            return nil;
        end
        local rows = DebindPrivate.CAST_AUTOMATIC_ROWS;
        for i = 1, #rows do
            if (rows[i] == row) then
                local mark = strsub(key, i, i);
                if (mark == "1") then
                    return true;
                elseif (mark == "0") then
                    return false;
                end
                return nil;
            end
        end
        return nil;
    end

    --- 한 줄의 화면 이름. **메뉴와 툴팁이 같은 말을 써야 해서 한 자리에 둔다** -- 툴팁은 메뉴의
    --- 줄을 열어 보라고 그리는 것이라, 두 곳의 이름이 갈리면 그리는 뜻이 없어진다.
    ---
    --- 클라이언트가 가진 둘은 그대로 쓰고, 설정 패널이 안 내는 둘만 우리가 적었다.
    ---
    --- **불려야 답한다.** 로케일은 이 파일보다 늦게 설 수 있다.
    local CAST_AUTOMATIC_LABELS;
    function DebindPrivate.CastAutomaticLabel(row)
        if (not CAST_AUTOMATIC_LABELS) then
            local locale = DebindPrivate.L;
            CAST_AUTOMATIC_LABELS = {
                autoSelfCast = AUTO_SELF_CAST_TEXT,
                autoUnshift = locale["AUTO_CANCEL_FORM"],
                autoDismount = locale["AUTO_DISMOUNT_TEXT"],
                autoDismountFlying = AUTO_DISMOUNT_FLYING_TEXT,
            };
        end
        return CAST_AUTOMATIC_LABELS[row];
    end

    --- 네 줄이 이 액션에서 아무 일도 못 하는 이유, 또는 `nil`. **켰는데 조용히 아무 일도 안 나는
    --- 자리를 막는 것이 전부다.**
    ---
    --- 값이 닿는 액션 종류. **감싸는 두 길이 닿는 곳이 곧 이 목록이다**: 매크로 안에서
    --- `/click`으로 부를 수 있는 것들(주문·아이템·장비칸·주문으로 나가는 탈것)과, 본문이 우리
    --- 문자열이라 앞뒤에 줄을 붙일 수 있는 것들(직접 쓴 매크로, 펫 명령, 매크로로 나가는 탈것).
    --- 전문화가 주문을 정하는 셋은 주문으로 다시 쓰이므로 여기 든다
    --- (`UpdateBindings.lua`의 `castsAtUnit`과 `AutomaticsWrap`).
    local CAST_AUTOMATIC_TYPES = {
        [Constants.SPELL] = true,
        [Constants.ITEM] = true,
        [Constants.USESLOT] = true,
        [Constants.MOUNT] = true,
        [Constants.MACROTEXT] = true,
        [Constants.PETACTION] = true,
    };
    for actionType in pairs(Constants.SPEC_RESOLVED_TYPES) do
        CAST_AUTOMATIC_TYPES[actionType] = true;
    end

    --- 네 줄이 이 액션에서 아무 일도 못 하는 이유, 또는 `nil`. **켰는데 조용히 아무 일도 안 나는
    --- 자리를 막는 것**이 전부다.
    ---
    --- 게임 매크로는 본문이 게임의 것이라 앞뒤에 붙일 문자열이 없고, 나머지는 시전이라는 것을
    --- 아예 안 해서 클라이언트가 그 주위에 할 일도 없다
    --- (`setting-the-clients-cast-automatics-per-action.md` §5).
    function DebindPrivate.CastAutomaticsBlockedReason(action)
        if (action == nil) then
            return nil;
        end
        if (action.type == Constants.MACRO) then
            return "gamemacro";
        end
        if (not CAST_AUTOMATIC_TYPES[action.type]) then
            return "nocast";
        end
        return nil;
    end

    --- 그 줄 하나의 값: 켬(`true`), 끔(`false`), 게임 설정 그대로(`nil`).
    ---
    --- **셋째 값에는 이름이 없다.** 값이 없는 것이 그것이고, 그래서 불리언이 아닌 것은 전부
    --- 셋째로 읽힌다 -- 공유 문자열은 우리가 모르는 값을 실어 올 수 있고, 모르는 값이
    --- 기본으로 읽혀야 한다는 것은 `casting` 전체의 규칙이다(`CastingValue`).
    function DebindPrivate.CastAutomaticOf(action, row)
        local value = CastingValue(action, row);
        if (value == true or value == false) then
            return value;
        end
        return nil;
    end

    local _ActionToBindingsCache = setmetatable({}, { __mode = "k" });
    local _ActionToTwinCache = setmetatable({}, { __mode = "kv" });
    local _ActionToFocusCache = setmetatable({}, { __mode = "kv" });
    local _ActionToSelfCache = setmetatable({}, { __mode = "kv" });

    --- The bindings that cast ahead of a spec-resolved one, as an array per action, one cache per
    --- tier (`GetBindingsForAction`). **Weak keys only**: nothing else holds the array.
    local _ActionToKnownCache = setmetatable({}, { __mode = "k" });
    local _ActionToKnownTwinCache = setmetatable({}, { __mode = "k" });
    local _ActionToKnownFocusCache = setmetatable({}, { __mode = "k" });
    local _ActionToKnownSelfCache = setmetatable({}, { __mode = "k" });

    local ASK_OWN_SPELL = { true };
    local NO_KNOWN = {};

    local HELP_DEAD = { dead = true, reaction = Constants.REACTION_HELP };

    --- A resurrection's branches, in the order a press tries them (`adding-spec-resolved-actions.md`
    --- §6). Each asks `known` about its own spell, so one not known gives way to the next and "the
    --- single one where there is no mass one" is written by order alone.
    ---
    --- **Only 1 goes out in combat**, since it is the only one the game casts there; the rest would
    --- send a cast for the game to refuse. **4 asks for no target** rather than standing as a last
    --- catch-all: a catch-all would send a mass resurrection at a living friend as well, and a
    --- [Friendly] the reader puts on the target would leave it standing, which nobody could guess
    --- from the screen (2026-09-23, owner).
    ---
    ---   1  battle     [combat, target dead, target friendly]
    ---   2  mass       [out of combat, target dead, target in my group]
    ---   3  single     [out of combat, target dead, target friendly]
    ---   3b battle     the same, with `battleRezOutOfCombat` on. Behind 3, so it stands in only
    ---                 while no single one is known: none in the class, or not learned yet
    ---                 (2026-09-23, owner)
    ---   4  mass       [out of combat, no target], unless `noTargetMassRez` is false
    ---
    --- **No Soulstone for the living** (2026-09-23, owner). It would have to fall back to you the way
    --- Auto Self Cast does, which cannot be told in combat, and left to the game it would take every
    --- press the Spell to Cast condition should hand on. A plain Soulstone action at the end of the
    --- key does it.
    local function ResurrectBranches(action)
        local spells = DebindPrivate.SpecSpells.ResurrectSpells();
        local out = {};
        if (spells.battle) then
            out[#out + 1] = { spell = spells.battle, combat = true, unit = HELP_DEAD };
        end
        if (spells.mass) then
            out[#out + 1] = { spell = spells.mass, combat = false, unit = { dead = true,
                group = bor(Constants.UNITGROUP_PARTY, Constants.UNITGROUP_RAID) } };
        end
        if (spells.single) then
            out[#out + 1] = { spell = spells.single, combat = false, unit = HELP_DEAD };
        end
        if (spells.battle and action.battleRezOutOfCombat) then
            out[#out + 1] = { spell = spells.battle, combat = false, unit = HELP_DEAD };
        end
        if (spells.mass and action.noTargetMassRez ~= false) then
            out[#out + 1] = { spell = spells.mass, combat = false, unit = false };
        end
        return out;
    end

    --- The hover twin, as three answers: the pointed unit its condition stands under, that
    --- condition, and the unit it goes out at. nil where the action gets none.
    ---
    --- **One rule, and the special cases are gone** (`which-action-a-key-runs.md` §4). The
    --- twin inherits every condition the reader wrote, adds [the pointed unit is there] on the unit
    --- the action's mode names, and goes out at that unit. A condition the reader wrote is never
    --- widened, and a unit the reader picked is never moved.
    ---
    --- **Only an action with Hover Cast turned on gets one**, because the twin is what gives an
    --- action a place in the tier a pointed press is decided in (§3). An action left without one
    --- waits in the last tier, and a Hover Cast action behind it takes every press made over a unit,
    --- however high the reader put the first. That is what turning it on buys: with every action in
    --- the pointed tier the value would change where the press goes and never which action answers
    --- it, so the one the reader turned on could sit under a plain action for good.
    ---
    --- **A condition the reader put on that unit is narrowed into, never replaced** (2026-09-12,
    --- owner). The twin says [the unit is there] and the reader may have said [it is hostile]; the
    --- two meet at [it is hostile], which is the reader's own table, since `UNIT_IS_THERE` constrains
    --- nothing. Replacing was measured on 2026-09-12: an action aimed at `target` that runs [when the
    --- mouseover unit is hostile] came out with a twin wider than its original on that axis, the
    --- solver deleted the original, and the key fired at whatever the cursor was over.
    ---
    --- **[when there is none] is the one that has no meeting point.** The twin only stands while that
    --- unit is there, so it could never match, and no twin is made.
    local function TwinUnitFor(action, original)
        local choice = DebindPrivate.HoverCastChoiceOf(action);
        if (choice == nil) then
            return nil;
        end
        local unit = DebindPrivate.HoverCastMode(action);

        local units = original.conditions and original.conditions.units;

        local existing = units and units[unit];
        if (existing == false) then
            return nil;
        end

        local aim = unit;
        if (DebindPrivate.ActionHasPickedUnit(action) or choice == "usual") then
            aim = original.unit;
        end

        return unit, existing or UNIT_IS_THERE, aim;
    end

    --- Every binding one action puts on its key, in place: `[1]` is the original
    --- (`GetBindingInfoForAction`'s table) and what follows is derived. `BuildKeyMap` sorts the
    --- originals and lays the key out in tiers after the sort, so only a hover twin has a placement
    --- of its own (`implementing-focus-and-self-cast.md` §3-4).
    function DebindPrivate.GetBindingsForAction(action)
        local list = _ActionToBindingsCache[action];
        if (not list) then
            list = {};
            _ActionToBindingsCache[action] = list;
        end

        local original = DebindPrivate.GetBindingInfoForAction(action);
        list[1] = original;
        local n = 1;

        -- **A spec-resolved action casts only through bindings that ask `known`, one per spell it
        -- asks about, and it has to be bindings rather than one binding with a cleverer field**
        -- (2026-09-23; the same ground was walked and lost once before). The warlock's dispel is
        -- the case that needs more than one, and the reasoning is `SpecSpells.lua`'s:
        --
        --   1. The book holds it as one id while the imp is out and as another while it is
        --      swallowed. `[known:]` tells the two apart in neither direction -- false by id
        --      whatever the state, true by name whatever the state -- so a conditional cannot
        --      carry the question at all.
        --   2. `FindSpellBookSlotBySpellID` can, and its answer moves **in combat**, where nothing
        --      can be rebuilt. So it is asked at the press.
        --   3. "Either of these two ids" is not one condition. Said on one binding it needs a field
        --      of its own and a check of its own in the press path, and **the solver has no column
        --      for that check** -- which makes the binding opaque, and an opaque binding is left
        --      out of coverage in both directions. It then sits on a key behind an unconditional
        --      action, wearing no mark, winning no press ever. That was built on 2026-09-23 and
        --      the screen is where it showed.
        --
        -- Two bindings say the same thing with what already exists: each asks about its own id on
        -- the ordinary `known` axis, so the solver sees two real boxes, coverage and the
        -- unreachable mark work, and the press path gains no new idea.
        --
        -- **Ticked, the original asks about the first spell and the rest are derived. Unticked,
        -- every one is derived** and the original holds the key behind them (`FillBinding`).
        -- Read off the original, which is where `FillBinding` settled what the box, a stored
        -- `false` and `skipWhenUnusable` add up to. A gated one that took the first id is ticked;
        -- a `known` naming some other spell is neither.
        local asks, firstDerived, branches = NO_KNOWN, 1, nil;
        if (action.type == Constants.RESURRECT) then
            branches = ResurrectBranches(action);
            asks = branches;
        elseif (original.spell ~= nil) then
            local _, gate = DebindPrivate.SpecSpells.SpellForType(action.type);
            if (original.holdsOnly) then
                asks = gate and gate.known or ASK_OWN_SPELL;
            elseif (gate and original.conditions.known == gate.known[1]) then
                asks, firstDerived = gate.known, 2;
            end
        end

        local function fill(cache, aimedUnit, twinCondition, castModifier, pointedUnit)
            local binding = cache[action];
            if (not binding) then
                binding = {};
                cache[action] = binding;
            end
            FillBinding(binding, action, aimedUnit, twinCondition, castModifier, pointedUnit);
            n = n + 1;
            list[n] = binding;
        end

        --- The casting bindings of one tier, after its original or twin so they land ahead of it.
        ---
        --- `aimsPointed` is a tier aimed at a unit that has to be there, where a resurrection's
        --- no-target branch cannot stand.
        local function fillKnown(cache, aimedUnit, twinCondition, castModifier, pointedUnit,
                aimsPointed)
            if (firstDerived > #asks) then
                return;
            end
            local bindings = cache[action];
            if (not bindings) then
                bindings = {};
                cache[action] = bindings;
            end
            -- Back to front, for the reason the whole list is: the first branch has to land first.
            for i = #asks, firstDerived, -1 do
                local branch = branches and asks[i];
                if (not branch or not aimsPointed or branch.unit ~= false) then
                    local binding = bindings[i];
                    if (not binding) then
                        binding = {};
                        bindings[i] = binding;
                    end
                    FillBinding(binding, action, aimedUnit, twinCondition, castModifier,
                        pointedUnit, not branch and asks[i] or nil, branch or nil);
                    n = n + 1;
                    list[n] = binding;
                end
            end
        end

        local pointedUnit, pointedCondition, pointedAim = TwinUnitFor(action, original);
        local focusTwin, selfTwin = false, false;
        if (DebindPrivate.KeyTakesCastKeyTwins(action)) then
            focusTwin, selfTwin = DebindPrivate.FocusCastEnabled(action), DebindPrivate.SelfCastEnabled(action);
        end
        -- **Four values off is an action with no bindings at all** (`which-action-a-key-runs.md`
        -- §6). It is not blocked: the row says why it does not run (`GetCastingOffReason`), and the
        -- key carries on with whatever else is on it. Answered before anything is filled, so the caches
        -- keep the tables they had. **The original's mark, not the stored box**: Skip can take the
        -- original away as well (`FillBinding`).
        if (original.normalCast == false and not pointedUnit
                and not focusTwin and not selfTwin) then
            for i = 1, #list do
                list[i] = nil;
            end
            return list;
        end

        -- **The list is filled back to front.** `BuildKeyMap` walks a list from its last entry
        -- down, so each casting binding is written after the one it stands beside and lands in
        -- the same tier, ahead of it.
        fillKnown(_ActionToKnownCache, action.unit);
        if (pointedUnit) then
            fill(_ActionToTwinCache, pointedAim, pointedCondition, Constants.CASTMOD_NONE, pointedUnit);
            -- Aimed at the pointed unit, which the twin needs to be there, the no-target branch can
            -- never stand. Cast as usual aims at the target instead, and there it can.
            fillKnown(_ActionToKnownTwinCache, pointedAim, pointedCondition, Constants.CASTMOD_NONE,
                pointedUnit, pointedAim == pointedUnit);
        end

        -- **Twins on every action, a picked unit and one that takes no unit included**: the original
        -- stands on [none held], so a held modifier has nothing else to land on. A picked unit keeps
        -- its twins aimed at itself (`ActionHasPickedUnit`), which is what keeps its place in the held
        -- tier.
        --
        -- "Cast as usual" keeps the twin and aims it where the original aims, so the action holds its
        -- turn in that tier without using the key's unit. Skip this action is the other value and it
        -- is answered above, where the twin is not made at all.
        local focusAim, selfAim = "focus", "player";
        if (DebindPrivate.ActionHasPickedUnit(action)) then
            focusAim, selfAim = original.unit, original.unit;
        end
        if (CastsAsUsual(action, "focusCastKey")) then
            focusAim = original.unit;
        end
        if (CastsAsUsual(action, "selfCastKey")) then
            selfAim = original.unit;
        end
        if (focusTwin) then
            fill(_ActionToFocusCache, focusAim, nil, Constants.CASTMOD_FOCUS);
            fillKnown(_ActionToKnownFocusCache, focusAim, nil, Constants.CASTMOD_FOCUS);
        end
        -- **Nobody resurrects themselves**, so a resurrection has no self tier aimed at you. Aimed at a
        -- picked unit or cast as usual, it is an ordinary tier and every branch stands in it. Decided
        -- here and not before the four-values check above, which is about the reader's switches.
        if (branches and selfAim == "player") then
            selfTwin = false;
        end
        if (selfTwin) then
            fill(_ActionToSelfCache, selfAim, nil, Constants.CASTMOD_SELF);
            fillKnown(_ActionToKnownSelfCache, selfAim, nil, Constants.CASTMOD_SELF);
        end

        for i = n + 1, #list do
            list[i] = nil;
        end

        return list;
    end

    --- The list as the last `GetBindingsForAction` left it, without refilling. For readers that
    --- only need the tables as keys (`Solver.lua`'s unreachable cache, filled by the last
    --- `BuildKeyMap` from these same tables): refilling would cost a full normalization per call
    --- and change nothing they read. nil for an action never derived, which is one no key map holds.
    function DebindPrivate.PeekBindingsForAction(action)
        return _ActionToBindingsCache[action];
    end
end

local GetBindingInfoForAction = DebindPrivate.GetBindingInfoForAction


-- GetMouseButtonAndPrefix는 Solver.lua가 쓰는데 그쪽이 먼저 로드되므로 Constants.lua에 있음

function DebindPrivate.IsConditionalAction(action)
    local binding = GetBindingInfoForAction(action);
    return DebindPrivate.IsConditionalBinding(binding);
end

local function HasSwitchCondition(action)
    if (action.conditions) then
        for k in pairs(action.conditions) do
            if (Constants.IsSwitchName(k)) then
                return true;
            end
        end
    end
    return false;
end

--- The record `CompareActionOrder` reads, and **the only place its shape is written.**
---
--- Three callers build one: `Debind.lua`'s `BuildKeyMap`, and `Profile.lua`'s `MakeRow` and
--- `RenumberKeyGroup`. Each used to spell the fields out for itself, and the three lists had
--- drifted apart -- they are never sorted against each other, so nothing was wrong today and
--- nothing would have said so on the day one of them lost a field.
---
--- **Where an action stands is the one thing not derived from the action.** `priority` and
--- `isConditional` are; `layerRank`, `specRank` and `seq` are its place in the profile. Those
--- last three used to be written onto the binding from outside, which left the binding a pure
--- function of its action by convention rather than in fact.
---
--- `dest` lets a caller hand its own table in. `BuildKeyMap` keeps one per binding and rebuilds
--- in place, because it runs over every bound action on every rebuild and used to allocate
--- nothing at all.
---
--- **One record per action, twins included.** Every tier stands in the originals' order, which is
--- the order the window draws (`which-action-a-key-runs.md` §2), so a twin is never ordered
--- against anything on its own terms.
---
--- **An ignored Switch still counts as a condition here** (2026-09-23, owner), although the binding
--- leaves it out (`FillBinding`). The reader still sees a condition on the action, and Ignored says
--- the action works whether the Switch is on or off, not that the condition is gone. A
--- Class/Specialization condition is the same: always true on this character, and still a
--- condition. Ignoring is also decided per character and specialization (`ResolveSwitchAnswer`), so
--- reading it here would order one shared layer differently on each character, and
--- `RenumberKeyGroup` would write one character's order into the number the others read.
---
--- **Normal Cast set to Skip is not counted**, although no plain press reaches such an action
--- (2026-09-23, owner). It is a cast option and not a condition, and counting it would be one more
--- exception for the reader to learn. What it costs is in `orderupgrade_spec`'s main test.
function DebindPrivate.MakeOrderRecord(action, layerRank, specRank, dest)
    local binding = GetBindingInfoForAction(action);
    dest = dest or {};
    dest.priority = action.priority or Constants.DEFAULT_IMPORTANCE;
    dest.isConditional = DebindPrivate.IsConditionalBinding(binding) or HasSwitchCondition(action);
    dest.layerRank = layerRank;
    dest.specRank = specRank;
    dest.seq = action.seq;
    return dest;
end

--- Does this binding carry any condition at all? The conditions step of the run order reads it
--- (`MakeOrderRecord`), and so does the conditional mark (`MARK_TOOLTIP_CONDITIONAL`).
---
--- Twelve branches stood here, a `nil` check per axis. Each new axis whose branch was forgotten
--- filed a binding carrying it as unconditional, **the run order moved in silence**, and nothing on
--- screen showed it.
---
--- **The binding's table can be empty.** It always exists, because every rebuild refills it in
--- place (`GetBindingInfoForAction`). Storage is the opposite and keeps no empty table
--- (`CleanUpDB`).
---
--- **Everything in the table is a condition.** A name this addon does not write has no way here:
--- `CleanUpDB` takes it out of storage, and an import carrying one is refused whole (`Import.lua`'s
--- `IsUsableAction`). A hand-edited SavedVariables is not defended against.
function DebindPrivate.IsConditionalBinding(binding)
    local conditions = binding.conditions;
    return conditions ~= nil and next(conditions) ~= nil;
end

--- The bare left and right click. **Never held**: the only press Debind answers on them is a click on
--- a unit frame, whatever the action's Cast Options say (`which-action-a-key-runs.md` §7).
function DebindPrivate.IsBareWorldClick(key)
    return key == "BUTTON1" or key == "BUTTON2";
end

--- Whether this action runs over a unit frame and nowhere else, **read off the action**: the issue
--- check asks it per row while the list is drawn, and going through `GetBindingInfoForAction` would
--- rebuild the binding each time.
---
--- **Public because two places ask it and must agree**: whether the key is held (`BuildKeyMap`'s
--- `KeysToHold`) and whether a mouse button carries cast key twins (`KeyTakesCastKeyTwins`).
---
--- A profile the migration has not reached (`action.hover`) answers what `UnitFrameConditionFromLegacy`
--- would, and a stored condition wins over it.
function DebindPrivate.ActionUnitFrameIsOn(action)
    -- **The bare left and right click run over a frame or not at all** (§7). With Hover Cast skipped
    -- nothing is left, and that is still nothing off a frame.
    if (DebindPrivate.IsBareWorldClick(action.key)) then
        return true;
    end

    -- **With no condition saying so.** Normal Cast off and Hover Cast on Unit Frames is that shape,
    -- and the old unit frame condition actions are carried over as it with no condition written
    -- (§8).
    --
    -- **Not with Normal Cast on.** The original then takes the presses off the frame and holds the
    -- key (`PrepareKeyBindings`' `holdsKey`).
    local casting = action.casting;
    if (casting and casting.normalCast == false
            and DebindPrivate.HoverCastChoiceOf(action) ~= nil
            and DebindPrivate.HoverCastMode(action) == "unitframe") then
        return true;
    end

    local condition = DebindPrivate.StoredUnitFrameCondition(action);
    if (condition == nil) then
        return action.hover == true;
    end
    -- **Folded, not read raw.** The stored table keeps a condition that is turned off, and
    -- `{ exists = false }` or `{ disabled = true }` is a table all the same.
    local folded = UnitConditionForBinding(condition);
    return folded ~= nil and folded ~= false;
end

--- Whether this action's key carries Self Cast Key and Focus Cast Key twins. **Not a mouse button
--- that runs over a frame** (2026-09-16, owner; §7): a frame click never reads the cast modifiers
--- and the action holds no key, so no press reaches them, and made anyway they held the key.
function DebindPrivate.KeyTakesCastKeyTwins(action)
    return not (DebindPrivate.GetMouseButtonAndPrefix(action.key)
        and DebindPrivate.ActionUnitFrameIsOn(action));
end
