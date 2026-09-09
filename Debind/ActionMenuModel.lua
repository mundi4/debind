local _, DebindPrivate      = ...;
local Constants             = DebindPrivate.Constants;
local LLL                   = DebindPrivate.L;
local DebindUI              = DebindPrivate.DebindUI;
local MenuKit               = DebindPrivate.MenuKit;

local dump                  = DebindPrivate.dump

--- What the action menus are made of, minus the drawing.
---
--- **One table on `DebindPrivate` rather than one entry per name.** Forty entries on the addon's
--- private table would be the same forty upvalues the split just took out, one scope wider.
local ActionMenu = {};
DebindPrivate.ActionMenu = ActionMenu;

local ARRAY_MARKER          = {};
-- 선택 창의 명령 탭도 같은 목록을 건다. 사본을 하나 더 두면 갈라진다 (`ActionDisplay.lua`).
local SORTED_UNIT_LIST      = DebindUI.SORTED_UNIT_LIST;
local USE_CHECKED_VALUE     = MenuKit.TOGGLE;

-- The hover condition and the unit conditions draw their reaction boxes from this one list. Two
-- copies drift the day a reaction is added.
local REACTION_ITEMS        = {
    { text = LLL["REACTION_HELP"],  value = Constants.REACTION_HELP },
    { text = LLL["REACTION_HARM"],  value = Constants.REACTION_HARM },
    { text = LLL["REACTION_OTHER"], value = Constants.REACTION_OTHER },
};

--- The life radios. **`value` is what gets stored, verbatim** -- the first row clears the `dead`
--- field, so it carries no `value` at all (a table cannot hold a `nil` one).
---
--- It says `Disable`, the same word every other three-way radio here opens with. The row is not a
--- third value to pick from; it is this axis constraining nothing, which is what every other
--- first row means too.
local LIFE_ITEMS            = {
    { text = LLL["DISABLE"] },
    { text = LLL["LIFE_ALIVE"], value = false },
    { text = LLL["LIFE_DEAD"],  value = true },
};

--- 소속 확인란. hover 조건과 유닛 조건이 이 하나를 나눠 쓴다.
local UNITGROUP_ITEMS       = {
    { text = LLL["UNITGROUP_NONE"],  value = Constants.UNITGROUP_NONE },
    { text = LLL["UNITGROUP_PARTY"], value = Constants.UNITGROUP_PARTY },
    { text = LLL["UNITGROUP_RAID"],  value = Constants.UNITGROUP_RAID },
};

--- 역할 확인란. **[역할 없음]도 고를 수 있는 값이다** - 역할이 지정 안 된 유닛에 대한 답이지
--- 못 알아냈다는 뜻이 아니다. 세 헤더가 다 서 있으면 애드온은 언제나 답을 내므로, 그 답만
--- 골라 나가는 바인딩을 걸 수 있어야 한다.
--- 프레임 종류 확인란의 기본값, 곧 **아무것도 안 정했을 때 켜져 있는 것**. 확인란과 그것을
--- 읽는 쪽이 같은 값을 봐야 해서 이름을 붙였다 - 한쪽만 `FRAMETYPE_ALL`로 읽으면 비트가 하나
--- 늘어나는 날 두 답이 갈린다.
local FRAMETYPE_DEFAULT     = Constants.FRAMETYPE_PLAYER
                            + Constants.FRAMETYPE_PET
                            + Constants.FRAMETYPE_GROUP
                            + Constants.FRAMETYPE_TARGET
                            + Constants.FRAMETYPE_BOSS
                            + Constants.FRAMETYPE_ARENA
                            + Constants.FRAMETYPE_UNKNOWN;

local ROLE_ITEMS            = {
    { text = LLL["ROLE_TANK"],    value = Constants.ROLE_TANK },
    { text = LLL["ROLE_HEALER"],  value = Constants.ROLE_HEALER },
    { text = LLL["ROLE_DAMAGER"], value = Constants.ROLE_DAMAGER },
    { text = LLL["ROLE_NONE"],    value = Constants.ROLE_NONE },
};


local TAB_LIST;


local function range(startIndex, endIndex, func)
    local arr = {};
    for i = startIndex, endIndex do
        local t, eof = func(i);
        if (t ~= nil) then
            tinsert(arr, func(i));
        end
        if (eof) then
            break;
        end
    end
    arr[ARRAY_MARKER] = true;
    return arr;
end

--- The name `SwitchesUI.lua` already reaches this by. The body moved to `MenuKit.lua` with the
--- rest of the parts a menu is made of; this keeps the door where its callers knock.
DebindUI.SetInstructionTooltip = MenuKit.SetInstructionTooltip;
local SetInstructionTooltip = MenuKit.SetInstructionTooltip;

local SetErrorTooltip = MenuKit.SetErrorTooltip;

--- The destination list every "where does this go" menu reads. Move, copy, and the picker's
--- "add to" all take the same one - two copies drift the day a tab is added.
---
--- 목록은 **레이어**의 목록이지 탭 좌표의 목록이 아니다.
---
--- 같은 레이어를 두 좌표가 가리키는 일이 실재한다: 캐릭터 전용 탭에서 (탭2, 사이드탭1)과
--- (탭2, 사이드탭2)가 **둘 다 레이어 7**이다. 그래서 layerID로 접는다 - 안 접으면 같은
--- 곳으로 가는 항목이 이름만 다르게 둘 나오고, "이동"으로 그 둘째를 고르면
--- `MoveAction`의 `assert(copying, "cannot move to same layer")`에 걸린다.
--- 남는 이름은 사이드탭1 쪽인데, 화면에서 레이어 7이 실제로 서 있는 자리가 거기다
--- (`UpdateSideTabs`가 탭2에서 사이드탭2를 숨긴다).
local function GetTabList()
    if (TAB_LIST == nil) then
        TAB_LIST = {};
        local seenLayers = {};
        for tabID = 1, #DebindLayerPanel.Tabs do
            local tabLabel = DebindUI.GetTabLabel(tabID);
            if (tabLabel) then
                for sideTabID = 1, #DebindLayerPanel.SideTabs do
                    local sideTabLabel = DebindUI.GetSideTabLabel(sideTabID);
                    if (sideTabLabel) then
                        local layerID = DebindUI.GetLayerID(tabID, sideTabID);
                        if (not seenLayers[layerID]) then
                            seenLayers[layerID] = true;
                            tinsert(TAB_LIST, {
                                layerID = layerID,
                                label = format("%s - %s", tabLabel, sideTabLabel),
                            });
                        end
                    end
                end
            end
        end
    end
    return TAB_LIST;
end

--- The edit menu has changed one of the action's values.
---
--- **It does not look at which value.** Conditions, importance and hover are steps in the
--- ordering, so changing one changes what this action is up against -- and rather than work out
--- which step moved, the key group is always renumbered. If nothing moved the renumber moves
--- nothing (`Profile.lua`'s `RenumberKeyGroup`). Working it out would mean seeing the action
--- before and after, and putting that pair of snapshots across the dozen call sites in this menu
--- means missing one someday.
local function OnActionValueChanged(action)
    DebindPrivate.RenumberKeyGroupForAction(action);
    DebindPrivate.UpdateBindings();
    return MenuResponse.Refresh;
end

--- 이 키가 사는 표. 조건은 `action.conditions` 안이고 나머지는 액션 자신이다.
--- 어느 이름이 조건인지는 `Constants.IsConditionField`가 답한다.
---
--- **참조를 붙들어 두지 않고 부를 때마다 푼다.** 조건 표는 첫 조건이 걸릴 때 생기고
--- 마지막 조건이 풀릴 때 없어진다. 메뉴를 세울 때 잡아두면 그 사이에 표가 갈려서
--- 사라진 표에 쓰게 된다 - `units`가 같은 함정을 갖고 있고 그 자리에 적혀 있다.
---
--- `create`가 거짓이면 없는 표를 만들지 않는다. 읽기만 하는 쪽이 조건 하나 없는 액션에
--- 표를 만들어 두면, 조건이 하나도 없는데 조건부로 분류된다(`IsConditionalBinding`).
local function TableFor(action, key, create)
    if (not Constants.IsConditionField(key)) then
        return action;
    end
    local conditions = action.conditions;
    if (conditions == nil and create) then
        conditions = {};
        action.conditions = conditions;
    end
    return conditions;
end

--- 이 액션의 유닛 조건 표. 없으면 nil이고, 만들지 않는다.
local function UnitConditionsOf(action)
    return action.conditions and action.conditions.units;
end

--- This action's set of specialization ids. nil where there is none, and none is made.
local function SpecConditionsOf(action)
    return action.conditions and action.conditions.specs;
end

--- Is this one specialization in the set.
local function SpecConditionHasID(ctx, specID)
    local specs = SpecConditionsOf(ctx.action);
    return specs ~= nil and specs[specID] ~= nil;
end

--- **The empty set is written and kept**, the way the all-off masks beside it are. Picking no
--- specialization is not the same as putting no condition on the action: it is an error the
--- reader is meant to see (`BINDING_ISSUE_SPECS_NONE_SELECTED`), and the row that says so is the
--- row this leaves behind. [Disable] at the top of the menu is what clears the key.
---
--- **The set is read off the action at click time.** It does not exist until the first box is
--- ticked, so a reference taken while the menu was built is stale the moment one is.
local function ToggleSpecConditionID(ctx, specID)
    local conditions = TableFor(ctx.action, "specs", true);
    local specs = conditions.specs;
    if (specs == nil) then
        specs = {};
        conditions.specs = specs;
    end
    if (specs[specID] == nil) then
        specs[specID] = true;
    else
        specs[specID] = nil;
    end
    return OnActionValueChanged(ctx.action);
end

--- Is every specialization of this class in the set. **The same question the tooltip line asks**
--- before it writes the class name in place of the specializations
--- (`Misc.lua`'s `DescribeSpecCondition`), so the box and the line cannot disagree about what a
--- whole class is.
local function ClassSpecsAllPicked(ctx, classID)
    return DebindPrivate.SpecSetHoldsClass(SpecConditionsOf(ctx.action), classID);
end

--- **Half on goes to all on.** A checkbox is ticked or it is not, so a class with some of its
--- specialization picked has no third state to draw, and "pressing it turns it on" is the only
--- answer a reader can predict from what is on screen.
local function ToggleClassSpecs(ctx, classID)
    local turnOn = not ClassSpecsAllPicked(ctx, classID);
    local conditions = TableFor(ctx.action, "specs", true);
    local specs = conditions.specs;
    if (specs == nil) then
        specs = {};
        conditions.specs = specs;
    end
    DebindPrivate.SetClassInSpecSet(specs, classID, turnOn);
    return OnActionValueChanged(ctx.action);
end

--- 조건을 하나 지운 뒤. **빈 표는 안 남긴다** - 있느냐를 게이트로 쓰는 자리가 여럿이라
--- (`IsConditionalBinding`, `CleanUpDB`) 조건이 없는 액션이 조건부가 된다.
local function PruneConditions(action)
    if (action.conditions and next(action.conditions) == nil) then
        action.conditions = nil;
    end
end

--- **The one place this file turns a menu value into stored state.** Every handler the kit
--- makes goes in and out through these two (`MenuKit.MakeHandlers`), so what a write costs
--- after the value moved is written once.
---
--- `targetObj` used to let a bit checkbox name some other table to work on. Nothing ever passed
--- one, so nothing ever ran that branch, and it is not carried over.
local ActionValues = {
    Get = function(ctx, key)
        local tbl = TableFor(ctx.action, key);
        return tbl and tbl[key];
    end,

    Set = function(ctx, key, value)
        local action = ctx.action;
        if (value == nil) then
            -- `nil`을 고를 때 표를 만들었다가 곧바로 거두는 일이 없어야 해서, 표는 실제로
            -- 쓸 때만 만든다.
            local tbl = TableFor(action, key);
            if (tbl) then
                tbl[key] = nil;
                PruneConditions(action);
            end
        else
            TableFor(action, key, true)[key] = value;
        end
        -- The checkbox branch comes through here as well. Neither field that does so today
        -- (`ignoreHoverUnit`, `keepInBindingContext`) is a step in the ordering, so the
        -- renumber moves nothing -- but the day one that is arrives here, that group alone
        -- would quietly keep the old symptom.
        return OnActionValueChanged(action);
    end,
};

local ActionHandlers = MenuKit.MakeHandlers(ActionValues);

local actionValueEquals = ActionHandlers.equals;
local setActionValue = ActionHandlers.set;

--- The action menu's family (`MenuKit.NewRegistry`). Every condition group is a node on it;
--- what is left off is the rest of the edit menu, which stage 3 takes
--- (`devdocs/legacy/putting-the-menus-on-a-kit.md`).
local ActionMenus = MenuKit.NewRegistry({
    accessor = ActionValues,

    --- **What wears a new-feature dot. Emptying this list at a release takes them all off.**
    newFeatures = { "SMART_CAST", "ROLE" },

    -- **묶음 키가 곧 이슈 갈래인 것은 아니다.** 이 메뉴가 쓰는 키 중 절반은 그 이름의
    -- 검사가 없다(`combat`, `known`, `stealth`, `extrabar`, 커스텀 상태, 중요도).
    -- 그냥 물으면 언제나 nil이라 답은 같지만, 없는 갈래를 묻는 것 자체가 DEBUG에서 걸린다.
    issueForKey = function(ctx, key)
        if (Constants.BINDING_ISSUE_CATEGORIES[key]) then
            return DebindPrivate.GetBindingIssue(ctx.action, key);
        end
    end,

    -- **`TableFor`를 거친다.** 조건은 `action.conditions` 안이라 최상단을 보면 언제나
    -- nil이고, 그러면 조건이 걸린 묶음이 하나도 안 파래진다. 조건이 아닌 키(`priority`)는
    -- 그대로 액션에서 읽힌다.
    isActiveForKey = function(ctx, key)
        local tbl = TableFor(ctx.action, key);
        return tbl ~= nil and tbl[key] ~= nil;
    end,

    --- 이슈 코드를 문장과 색으로. **등급이 색을 고른다** (`Misc.lua`의 `GetIssueColor`).
    --- Clique가 개체창을 가져간 것처럼 **그 묶음에서 고칠 것이 없는** 문제까지 빨갛게
    --- 칠하면, 열어 본 사람이 고칠 것을 찾다가 못 찾는다.
    resolveIssue = function(issue)
        return rawget(LLL, issue) or rawget(LLL, "BINDING_ERROR_" .. issue) or issue,
            DebindPrivate.GetIssueColor(issue);
    end,
});

--- Read and write one unit condition, one field per axis (`Profile.lua`'s `dbver <= 4` step).
---
--- Three radios at the top of the submenu line up with the three shapes storage has: no key
--- (unconstrained), a table (exists, plus whatever axes it names), `false` (absent). Every
--- axis is one field inside that table, so a new axis adds a block to the menu and leaves
--- these accessors alone.
---
--- The axis widgets all read the table off `ctx.action` at click time rather than capturing it.
--- `units` is nil until the first condition is set, so a reference grabbed while the
--- menu was being built goes stale the moment the user turns one on.
local function GetUnitConditionReaction(ctx, unit)
    local value = UnitConditionsOf(ctx.action) and UnitConditionsOf(ctx.action)[unit];
    if (type(value) ~= "table") then
        return nil;
    end
    return value.reaction;
end

--- Which of the three radios above is on, `nil` where no condition was ever made.
---
--- **The reading is `UnitConditionForBinding`'s and not a second one.** This used to spell the
--- same fork out again -- scalars first, then `off`, then `exists == false` -- with a comment
--- saying the two had to agree, which nothing could check: that function is reached by the
--- headless specs and this file is not (`tests/run.lua`). The day they parted, the screen would
--- have said [when there is one] while the binding meant [when there is not], and only somebody
--- pressing the key would have found out. `ActionTooltip.lua` reads unit conditions the same
--- way, for the same reason.
---
--- **`off` is the one thing that function cannot answer.** It conflates a turned-off condition
--- with an absent one, answering `nil` for both, which is right for a binding and wrong for a
--- menu: this screen has to keep showing the axes a reader turned off but did not throw away.
--- So it is asked here, ahead of the shared reading.
local function UnitConditionMode(ctx, unit)
    local units = UnitConditionsOf(ctx.action);
    local value = units and units[unit];
    if (value == nil) then
        return nil;
    end
    if (type(value) == "table" and value.disabled) then
        return "disabled";
    end
    if (DebindPrivate.UnitConditionForBinding(value) == false) then
        return "absent";
    end
    return "exists";
end

local function UnitConditionIsExists(ctx, unit)
    return UnitConditionMode(ctx, unit) == "exists";
end

--- 조건이 실제로 걸려 있는가. 꺼진 채로 축만 기억하는 것은 조건이 아니다 - 묶음을 파랗게
--- 칠하는 자리들이 이걸 물어야 **끈 조건 때문에 "걸려 있음"으로 보이지** 않는다.
local function UnitConditionIsOn(ctx, unit)
    local mode = UnitConditionMode(ctx, unit);
    return mode == "exists" or mode == "absent";
end

local function GetUnitConditionDead(ctx, unit)
    local value = UnitConditionsOf(ctx.action) and UnitConditionsOf(ctx.action)[unit];
    if (type(value) ~= "table") then
        return nil;
    end
    return value.dead;
end

local function GetUnitConditionGroup(ctx, unit)
    local value = UnitConditionsOf(ctx.action) and UnitConditionsOf(ctx.action)[unit];
    if (type(value) ~= "table") then
        return nil;
    end
    return value.group;
end

local function GetUnitConditionRole(ctx, unit)
    local value = UnitConditionsOf(ctx.action) and UnitConditionsOf(ctx.action)[unit];
    if (type(value) ~= "table") then
        return nil;
    end
    return value.role;
end

--- 이 유닛 조건이 기억하고 있는 축이 하나라도 있는가.
---
--- **축이 하나 늘 때마다 여기 항이 하나 는다.** 빠뜨리면 그 축만 걸어둔 유닛이 [사용 안
--- 함]으로 옮기는 순간 기억되는 대신 지워진다. 소속을 넣을 때 실제로 그렇게 빠졌다. 두
--- 자리가 같은 물음을 하므로 값이 하나여야 한다(`SetUnitConditionMode`, `SetPlayerLife`).
local function UnitConditionRemembersAxis(cond)
    return cond.reaction ~= nil or cond.dead ~= nil or cond.role ~= nil or cond.group ~= nil;
end

--- What the three radios at the top write. **It moves the mode and leaves the axes alone**: a
--- reader who switches to [Disable] and back has to find the reaction and the life they picked
--- still there. Ignoring them while the condition is off is `Misc.UnitConditionForBinding`'s job.
---
--- **Each of the three modes carries a value of its own.** While an empty table meant [when there
--- is one], an action carrying a single unit condition signed the same as an action carrying no
--- condition at all, and the duplicate check paired the two. The `dbver <= 6` step raises the old
--- values.
---
--- A key with nothing left to remember is deleted rather than left as an empty table, or a unit
--- nothing was ever picked for piles up in the profile.
local function SetUnitConditionMode(ctx, unit, mode)
    local units = UnitConditionsOf(ctx.action);
    local cond = units and units[unit];
    if (type(cond) ~= "table") then
        cond = {};
    end
    -- **`and false or`로 쓰지 말 것.** 그 관용구는 `false`를 못 돌려준다 - 참일 때
    -- `true and false`가 `false`가 되고 그게 다시 `or`의 왼쪽이라 오른쪽이 나온다.
    -- 그렇게 쓴 동안 [없을 때]가 아무것도 안 적어서 [있을 때]와 같은 값이 됐다.
    cond.disabled = (mode == "disabled") or nil;
    if (mode == "absent") then
        cond.exists = false;
    elseif (mode == "disabled") then
        cond.exists = nil;
    else
        cond.exists = true;
    end

    if (mode == "disabled" and not UnitConditionRemembersAxis(cond)) then
        -- 기억할 축이 하나도 없다. 빈 표를 남기면 아무것도 안 고른 유닛이 프로필에 쌓인다.
        if (units) then
            units[unit] = nil;
            if (not next(units)) then
                ctx.action.conditions.units = nil;
                PruneConditions(ctx.action);
            end
        end
    else
        if (units == nil) then
            units = {};
            TableFor(ctx.action, "units", true).units = units;
        end
        units[unit] = cond;
    end

    OnActionValueChanged(ctx.action);
    return MenuResponse.Refresh;
end

--- Write one axis. Every caller is gated on the `exists` radio, so the table is already there.
local function SetUnitConditionAxis(ctx, unit, axis, value)
    local cond = UnitConditionsOf(ctx.action) and UnitConditionsOf(ctx.action)[unit];
    if (type(cond) ~= "table") then
        return;
    end
    cond[axis] = value;
    OnActionValueChanged(ctx.action);
    return MenuResponse.Refresh;
end

--- The reaction boxes. Storage is a mask, but **all-on is never written** -- that says the
--- same thing as constraining nothing, and one condition stored two ways is two different
--- boxes to the solver (`Misc.lua` normalizes `reactions`/`frameTypes` for the same reason).
---
--- 0 **is** written. Choosing nothing is not something to normalize away; it is an issue, and
--- `GetBindingIssue`'s zero-mask branch reports it where the user set it.
local function UnitConditionReactionChecked(ctx, unit, value)
    local reaction = GetUnitConditionReaction(ctx, unit);
    if (reaction == nil) then
        return true;
    end
    return bit.band(reaction, value) == value;
end

local function ToggleUnitConditionReaction(ctx, unit, value)
    local mask = bit.bxor(GetUnitConditionReaction(ctx, unit) or Constants.REACTION_ALL, value);
    if (mask == Constants.REACTION_ALL) then
        mask = nil;
    end
    return SetUnitConditionAxis(ctx, unit, "reaction", mask);
end

--- 소속 확인란. **셋이 서로 겹친다** - 공대에서 같은 소그룹인 사람은 [파티]와 [공대]에
--- 다 든다. 그래서 [파티]만 켜도 파티가 공대가 된 뒤에 옆자리 사람에게 계속 걸린다.
--- 반응·역할과 같은 규칙: 전부 켠 값은 안 쓰고, 0은 쓴다.
local function UnitConditionGroupChecked(ctx, unit, value)
    local group = GetUnitConditionGroup(ctx, unit);
    if (group == nil) then
        return true;
    end
    return bit.band(group, value) == value;
end

local function ToggleUnitConditionGroup(ctx, unit, value)
    local mask = bit.bxor(GetUnitConditionGroup(ctx, unit) or Constants.UNITGROUP_ALL, value);
    if (mask == Constants.UNITGROUP_ALL) then
        mask = nil;
    end
    return SetUnitConditionAxis(ctx, unit, "group", mask);
end

--- 프레임 종류 확인란 하나가 켜져 있는가. **`AppendCheckboxes`의 `_hasBit`과 같은 답을
--- 내야 한다** - 그쪽은 값이 없으면 기본 마스크로 읽으므로, 여기만 0으로 읽으면 아무것도
--- 안 정한 액션에서 전부 꺼진 것으로 보인다.
local function HoverFrameTypeChecked(ctx, value)
    local conditions = ctx.action and ctx.action.conditions;
    local current = (conditions and conditions.frameTypes) or FRAMETYPE_DEFAULT;
    return bit.band(current, value) == value;
end

--- The role boxes. Same rule as the reaction ones above: all-on is never written, and 0 is.
local function UnitConditionRoleChecked(ctx, unit, value)
    local role = GetUnitConditionRole(ctx, unit);
    if (role == nil) then
        return true;
    end
    return bit.band(role, value) == value;
end

local function ToggleUnitConditionRole(ctx, unit, value)
    local mask = bit.bxor(GetUnitConditionRole(ctx, unit) or Constants.ROLE_ALL, value);
    if (mask == Constants.ROLE_ALL) then
        mask = nil;
    end
    return SetUnitConditionAxis(ctx, unit, "role", mask);
end
--- 왜 "개체창 위에서는 그 개체를 우선"을 지금 못 켜는가. 켤 수 있으면 nil.
---
--- **잠그는 이유와 파생이 거절하는 이유는 같은 목록이어야 한다** (`Misc.lua`의
--- `GetBindingsForAction`). 공유 프로필은 이 메뉴를 안 지나므로, 갈리면 잠긴 상자가
--- 동작하거나 켠 상자가 아무 일도 안 한다.
---
--- **하나씩 문장을 돌려주는 것은 잠긴 상자가 이유를 말해야 하기 때문이다** (2026-09-06,
--- 소유자). 회색으로 굳어 있기만 하면 읽는 사람은 자기가 무엇을 되돌려야 켜지는지 모른다.
---
--- **hover 조건은 [안 올렸을 때]도 잠근다.** 그 액션은 개체창 위에서 아예 발동하지 않으므로
--- 개체창의 개체로 나갈 가능성이 0이다. 켜져 있으면 켤 수 있는 것처럼 보이는데 그 상자가
--- 할 수 있는 일이 없다.
local function PreferHoverUnitLockReason(ctx)
    if (UnitConditionIsOn(ctx, "hover")) then
        return LLL["PREFER_HOVER_UNIT_LOCKED_HOVER"];
    elseif (ctx.action.unit == "hover") then
        return LLL["PREFER_HOVER_UNIT_LOCKED_TARGET_HOVER"];
    elseif (ctx.action.unit == "none") then
        return LLL["PREFER_HOVER_UNIT_LOCKED_TARGET_NONE"];
    end
end

local function hoverConditionIsOn(ctx)
    return UnitConditionIsExists(ctx, "hover");
end

--- What the two drawing files and the entry points reach in here. Everything else above is this
--- file's own.
ActionMenu.REACTION_ITEMS            = REACTION_ITEMS;
ActionMenu.LIFE_ITEMS                = LIFE_ITEMS;
ActionMenu.UNITGROUP_ITEMS           = UNITGROUP_ITEMS;
ActionMenu.ROLE_ITEMS                = ROLE_ITEMS;
ActionMenu.FRAMETYPE_DEFAULT         = FRAMETYPE_DEFAULT;
ActionMenu.SORTED_UNIT_LIST          = SORTED_UNIT_LIST;
ActionMenu.USE_CHECKED_VALUE         = USE_CHECKED_VALUE;
ActionMenu.range                     = range;
ActionMenu.GetTabList                = GetTabList;
ActionMenu.SetInstructionTooltip     = SetInstructionTooltip;
ActionMenu.SetErrorTooltip           = SetErrorTooltip;

ActionMenu.ActionMenus               = ActionMenus;
ActionMenu.OnActionValueChanged      = OnActionValueChanged;
ActionMenu.TableFor                  = TableFor;
ActionMenu.PruneConditions           = PruneConditions;
ActionMenu.UnitConditionsOf          = UnitConditionsOf;
ActionMenu.SpecConditionsOf          = SpecConditionsOf;
ActionMenu.SpecConditionHasID        = SpecConditionHasID;
ActionMenu.ToggleSpecConditionID     = ToggleSpecConditionID;
ActionMenu.ClassSpecsAllPicked       = ClassSpecsAllPicked;
ActionMenu.ToggleClassSpecs          = ToggleClassSpecs;
ActionMenu.actionValueEquals         = actionValueEquals;
ActionMenu.setActionValue            = setActionValue;

ActionMenu.UnitConditionMode         = UnitConditionMode;
ActionMenu.UnitConditionIsExists     = UnitConditionIsExists;
ActionMenu.UnitConditionIsOn         = UnitConditionIsOn;
ActionMenu.GetUnitConditionDead      = GetUnitConditionDead;
ActionMenu.SetUnitConditionMode      = SetUnitConditionMode;
ActionMenu.SetUnitConditionAxis      = SetUnitConditionAxis;
ActionMenu.UnitConditionReactionChecked = UnitConditionReactionChecked;
ActionMenu.ToggleUnitConditionReaction  = ToggleUnitConditionReaction;
ActionMenu.UnitConditionGroupChecked = UnitConditionGroupChecked;
ActionMenu.ToggleUnitConditionGroup  = ToggleUnitConditionGroup;
ActionMenu.UnitConditionRoleChecked  = UnitConditionRoleChecked;
ActionMenu.ToggleUnitConditionRole   = ToggleUnitConditionRole;
ActionMenu.UnitConditionRemembersAxis = UnitConditionRemembersAxis;
ActionMenu.HoverFrameTypeChecked     = HoverFrameTypeChecked;
ActionMenu.PreferHoverUnitLockReason = PreferHoverUnitLockReason;
ActionMenu.hoverConditionIsOn        = hoverConditionIsOn;
