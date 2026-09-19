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
---
--- **The menu aims at `ctx.actions`, and a single row is a selection of one**
--- (`editing-many-actions-at-once.md`). Every read below answers for the whole selection and
--- every write lands on each action in it, then rebuilds once.
local ActionMenu = {};
DebindPrivate.ActionMenu = ActionMenu;

local ARRAY_MARKER          = {};
-- 선택 창의 명령 탭도 같은 목록을 건다. 사본을 하나 더 두면 갈라진다 (`ActionDisplay.lua`).
local SORTED_UNIT_LIST      = DebindUI.SORTED_UNIT_LIST;
local USE_CHECKED_VALUE     = MenuKit.TOGGLE;

-- The `unitframe` condition and the unit conditions draw their reaction boxes from this one list. Two
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

--- 소속 확인란. unitframe 조건과 유닛 조건이 이 하나를 나눠 쓴다.
local UNITGROUP_ITEMS       = {
    { text = LLL["UNITGROUP_NONE"],  value = Constants.UNITGROUP_NONE },
    { text = LLL["UNITGROUP_PARTY"], value = Constants.UNITGROUP_PARTY },
    { text = LLL["UNITGROUP_RAID"],  value = Constants.UNITGROUP_RAID },
};

local FRAMETYPE_ITEMS       = {
    { text = LLL["FRAMETYPE_PLAYER"],  value = Constants.FRAMETYPE_PLAYER },
    { text = LLL["FRAMETYPE_PET"],     value = Constants.FRAMETYPE_PET },
    { text = LLL["FRAMETYPE_GROUP"],   value = Constants.FRAMETYPE_GROUP },
    { text = LLL["FRAMETYPE_TARGET"],  value = Constants.FRAMETYPE_TARGET },
    { text = LLL["FRAMETYPE_BOSS"],    value = Constants.FRAMETYPE_BOSS },
    { text = LLL["FRAMETYPE_ARENA"],   value = Constants.FRAMETYPE_ARENA },
    { text = LLL["FRAMETYPE_UNKNOWN"], value = Constants.FRAMETYPE_UNKNOWN },
};

--- 역할 확인란. **[역할 없음]도 고를 수 있는 값이다** - 역할이 지정 안 된 유닛에 대한 답이지
--- 못 알아냈다는 뜻이 아니다. 세 헤더가 다 서 있으면 애드온은 언제나 답을 내므로, 그 답만
--- 골라 나가는 바인딩을 걸 수 있어야 한다.
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

--- Does `holds` answer true for every action the menu aims at.
local function AllActions(ctx, holds)
    local actions = ctx.actions;
    if (#actions == 0) then
        return false;
    end
    for i = 1, #actions do
        if (not holds(actions[i])) then
            return false;
        end
    end
    return true;
end

local function AnyAction(ctx, holds)
    local actions = ctx.actions;
    for i = 1, #actions do
        if (holds(actions[i])) then
            return true;
        end
    end
    return false;
end

--- `"all"`, `"some"` or `"none"`: how many of the selected actions can take an item at all.
---
--- **Some is its own answer because it is the one that has to be refused out loud.** Changing only
--- the ones that can take it is five of seven moved with nobody told which, the same reason moving
--- a selection with an arrival in it is refused.
local function HowManyAccept(ctx, accepts)
    local actions = ctx.actions;
    local taken = 0;
    for i = 1, #actions do
        if (accepts(actions[i])) then
            taken = taken + 1;
        end
    end
    if (taken == 0) then
        return "none";
    elseif (taken == #actions) then
        return "all";
    end
    return "some";
end

--- The reason an item that belongs to one action at a time is locked, or nil when one is picked.
local function OnlyOneReason(ctx)
    if (#ctx.actions ~= 1) then
        return LLL["MENU_BLOCKED_ONLY_ONE"];
    end
end

--- Runs `fn` with the selection narrowed to one action, and puts the selection back even when it
--- raises. Every reading in these menus takes the selection off `ctx` when it is called, so this is
--- how one of them is asked about a single action without a second copy of it.
local function WithOneAction(ctx, action, fn, ...)
    local actions = ctx.actions;
    ctx.actions = { action };
    local ok, result = pcall(fn, ...);
    ctx.actions = actions;
    if (not ok) then
        error(result, 0);
    end
    return result;
end

--- How many selected actions a choice row holds, or nil where they all agree.
---
--- **The row's own reading is asked once per action**, so the number beside a row and the tick on it
--- cannot come from two rules.
local function MixedCount(ctx, isSelected, data)
    local actions = ctx.actions;
    if (#actions < 2) then
        return nil;
    end
    local held = 0;
    for i = 1, #actions do
        if (WithOneAction(ctx, actions[i], isSelected, data)) then
            held = held + 1;
        end
    end
    if (held == 0 or held == #actions) then
        return nil;
    end
    return held;
end

local function DecorateChoice(description, ctx, isSelected, data)
    MenuKit.AppendCount(description, function()
        return MixedCount(ctx, isSelected, data);
    end);
    return description;
end

--- A radio or a box drawn for the action menu, carrying the count where the selection is split.
--- The rows the kit's appenders draw get the same through `decorateChoice`.
local function CreateRadio(description, ctx, text, isSelected, setSelected, data)
    return DecorateChoice(description:CreateRadio(text, isSelected, setSelected, data), ctx, isSelected, data);
end

local function CreateCheckbox(description, ctx, text, isSelected, setSelected, data)
    return DecorateChoice(description:CreateCheckbox(text, isSelected, setSelected, data), ctx, isSelected, data);
end

local NodeMixedCount;

--- The menu has changed values on these actions.
---
--- **It does not look at which value.** Conditions and importance are steps in the ordering, so
--- changing one changes what an action is up against -- and rather than work out
--- which step moved, each action's key group is renumbered. If nothing moved the renumber moves
--- nothing (`Profile.lua`'s `RenumberKeyGroup`). Working it out would mean seeing each action
--- before and after, and putting that pair of snapshots across the dozen call sites in this menu
--- means missing one someday.
---
--- **One rebuild for the whole selection.** Two actions sharing a group renumber it twice, which
--- moves nothing the second time.
local function OnActionsChanged(actions)
    for i = 1, #actions do
        DebindPrivate.RenumberKeyGroupForAction(actions[i]);
    end
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

--- Every Casting value is a scalar one level down (`action.casting.hoverCast`) and the kit addresses
--- a value by one key, so the key spells the whole address: `casting.<name>`
--- (`action-and-binding-shapes.md` §1).
---
--- Returns the table the value lives in and its name, or nil for a key that is not one of these.
--- **Reading makes nothing**: an action with no `casting` answers off the empty table, the way
--- `TableFor` refuses to make a condition table for a reader.
local EMPTY_CASTING = {};
local function CastingHolder(action, key, create)
    if (strsub(key, 1, 8) ~= "casting.") then
        return nil;
    end
    local name = strsub(key, 9);
    local casting = action.casting;
    if (casting == nil) then
        if (not create) then
            return EMPTY_CASTING, name;
        end
        casting = {};
        action.casting = casting;
    end
    return casting, name;
end

--- 빈 표는 안 남긴다. `CleanUpDB`와 같은 규칙이고, 여기서도 하는 것은 저장과 내보내기와
--- 같은지 묻기(`IDENTITY_FIELDS`)가 로그아웃을 안 기다리기 때문이다.
local function PruneCasting(action)
    local casting = action.casting;
    if (casting ~= nil and next(casting) == nil) then
        action.casting = nil;
    end
end

--- 이 액션의 유닛 조건 표. 없으면 nil이고, 만들지 않는다.
local function UnitConditionsOf(action)
    return action.conditions and action.conditions.units;
end

--- This action's set of specialization ids. nil where there is none, and none is made.
local function SpecConditionsOf(action)
    return action.conditions and action.conditions.specs;
end

--- The set, made where it is not there yet.
local function SpecConditionsFor(action)
    local conditions = TableFor(action, "specs", true);
    local specs = conditions.specs;
    if (specs == nil) then
        specs = {};
        conditions.specs = specs;
    end
    return specs;
end

--- Is this one specialization in every selected action's set.
local function SpecConditionHasID(ctx, specID)
    return AllActions(ctx, function(action)
        local specs = SpecConditionsOf(action);
        return specs ~= nil and specs[specID] ~= nil;
    end);
end

--- **The empty set is written and kept**, the way the all-off masks beside it are. Picking no
--- specialization is not the same as putting no condition on the action: it is an error the
--- reader is meant to see (`BINDING_ISSUE_SPECS_NONE_SELECTED`), and the row that says so is the
--- row this leaves behind. [Disable] at the top of the menu is what clears the key.
---
--- **The set is read off each action at click time.** It does not exist until the first box is
--- ticked, so a reference taken while the menu was built is stale the moment one is.
---
--- **Off only when every action has it**, which is also why turning off never meets an action
--- with no set: a selection where one lacks it is drawn off and turns it on.
local function ToggleSpecConditionID(ctx, specID)
    local turnOn = not SpecConditionHasID(ctx, specID);
    for _, action in ipairs(ctx.actions) do
        SpecConditionsFor(action)[specID] = turnOn or nil;
    end
    return OnActionsChanged(ctx.actions);
end

--- Is every specialization of this class in every selected action's set. **The same question the
--- tooltip line asks** before it writes the class name in place of the specializations
--- (`Misc.lua`'s `DescribeSpecCondition`), so the box and the line cannot disagree about what a
--- whole class is.
local function ClassSpecsAllPicked(ctx, classID)
    return AllActions(ctx, function(action)
        return DebindPrivate.SpecSetHoldsClass(SpecConditionsOf(action), classID);
    end);
end

--- **Half on goes to all on.** A checkbox is ticked or it is not, so a class with some of its
--- specialization picked has no third state to draw, and "pressing it turns it on" is the only
--- answer a reader can predict from what is on screen. A selection where one action holds the
--- class and another does not is half on the same way.
local function ToggleClassSpecs(ctx, classID)
    local turnOn = not ClassSpecsAllPicked(ctx, classID);
    for _, action in ipairs(ctx.actions) do
        DebindPrivate.SetClassInSpecSet(SpecConditionsFor(action), classID, turnOn);
    end
    return OnActionsChanged(ctx.actions);
end

--- 조건을 하나 지운 뒤. **빈 표는 안 남긴다** - 있느냐를 게이트로 쓰는 자리가 여럿이라
--- (`IsConditionalBinding`, `CleanUpDB`) 조건이 없는 액션이 조건부가 된다.
local function PruneConditions(action)
    if (action.conditions and next(action.conditions) == nil) then
        action.conditions = nil;
    end
end

--- This action's talent condition. nil where there is none, and none is made.
local function TalentConditionOf(action)
    return action.conditions and action.conditions.talents;
end

--- One specialization's entry, made where it is not there yet.
local function TalentEntryFor(action, specID)
    local conditions = TableFor(action, "talents", true);
    local talents = conditions.talents;
    if (talents == nil) then
        talents = {};
        conditions.talents = talents;
    end
    -- **Replaced rather than written into where it is not a table.** A shared string can leave
    -- anything under a specialization id, and writing a row into it would raise; what the reader
    -- just clicked is what the entry should hold.
    local entry = talents[specID];
    if (type(entry) ~= "table") then
        entry = {};
        talents[specID] = entry;
    end
    return entry;
end

--- **Anything may be under these two names.** The wire types the condition and stops there
--- (`DebindStorage/Import.lua`), so a hand-made string reaches this with a number where a list
--- belongs, and `#` on one raises.
local function ListHolds(list, spellID)
    if (type(list) ~= "table") then
        return nil;
    end
    for i = 1, #list do
        if (list[i] == spellID) then
            return i;
        end
    end
    return nil;
end

--- What this action says about one talent in one specialization: `"taken"`, `"notTaken"` or nil.
local function TalentStateOf(action, specID, spellID)
    local talents = TalentConditionOf(action);
    local entry = talents and talents[specID];
    local Talents = DebindPrivate.Talents;
    if (ListHolds(Talents.ListOf(entry, "taken"), spellID)) then
        return "taken";
    end
    if (ListHolds(Talents.ListOf(entry, "notTaken"), spellID)) then
        return "notTaken";
    end
    return nil;
end

--- **Read off the first specialization and written to all of them.** The class tree hands this the
--- whole class, because a class talent means the same thing in every specialization and a tick
--- that landed on one would read as untouched from the other three
--- (`adding-a-talent-condition.md` §2). Reading is the specialization being played,
--- which
--- is the one the reader is looking at; a set that arrived out of step realigns on the next click.
local function TalentConditionIs(ctx, specIDs, spellID, state)
    return AllActions(ctx, function(action)
        return TalentStateOf(action, specIDs[1], spellID) == state;
    end);
end

local function ListTouches(list, ids)
    if (type(list) ~= "table") then
        return false;
    end
    for i = 1, #list do
        if (ids[list[i]]) then
            return true;
        end
    end
    return false;
end

--- Does any selected action say anything about any of these talents?
---
--- **Any, not every.** This is what colours a row that only opens a submenu, and the question a
--- colour answers there is "is there something of mine down here" (`MenuKit.lua`). A row lit only
--- where the whole selection agrees would leave the reader hunting through branches that look
--- untouched.
local function TalentConditionTouches(ctx, specID, ids)
    return AnyAction(ctx, function(action)
        local talents = TalentConditionOf(action);
        local entry = talents and talents[specID];
        local Talents = DebindPrivate.Talents;
        return ListTouches(Talents.ListOf(entry, "taken"), ids)
            or ListTouches(Talents.ListOf(entry, "notTaken"), ids);
    end);
end

--- **The empty entry is swept here rather than left for the logout.** A specialization key with
--- both lists empty says nothing, and an action carrying one reads as conditional
--- (`IsConditionalBinding`, `CleanUpDB`).
local function PruneTalents(action)
    local talents = TalentConditionOf(action);
    if (talents == nil) then
        return;
    end
    -- **An entry that is not a pair of lists goes with the empty ones.** Nothing here can make
    -- one, and one that arrived in a shared string says nothing this menu can draw or undo.
    local Talents = DebindPrivate.Talents;
    for specID, entry in pairs(talents) do
        local taken = Talents.ListOf(entry, "taken");
        local notTaken = Talents.ListOf(entry, "notTaken");
        if ((taken == nil or #taken == 0) and (notTaken == nil or #notTaken == 0)) then
            talents[specID] = nil;
        end
    end
    if (next(talents) == nil) then
        action.conditions.talents = nil;
    end
end

--- Puts one talent on one of the two lists, or on neither. **Off both is how a row is cleared**,
--- which is the third choice every row carries.
local function WriteList(entry, name, spellID, wanted)
    local list = DebindPrivate.Talents.ListOf(entry, name);
    local at = ListHolds(list, spellID);
    if (wanted and not at) then
        list = list or {};
        entry[name] = list;
        list[#list + 1] = spellID;
    elseif (at and not wanted) then
        table.remove(list, at);
    end
end

local function SetTalentCondition(ctx, specIDs, spellID, state)
    for _, action in ipairs(ctx.actions) do
        for i = 1, #specIDs do
            local entry = TalentEntryFor(action, specIDs[i]);
            WriteList(entry, "taken", spellID, state == "taken");
            WriteList(entry, "notTaken", spellID, state == "notTaken");
        end
        PruneTalents(action);
        PruneConditions(action);
    end
    return OnActionsChanged(ctx.actions);
end

--- Does this action carry a talent condition on a specialization other than the one being played?
---
--- **The menu cannot show those.** It opens the specialization being played, so a key written in
--- another one -- by that specialization's own menu, or by a shared string -- is on the action with
--- no row of its own.
local function HasOtherSpecTalents(action)
    local mine = DebindPrivate.SpecIDForIndex(C_SpecializationInfo.GetSpecialization());
    local talents = TalentConditionOf(action);
    for specID in pairs(talents or {}) do
        if (specID ~= mine) then
            return true;
        end
    end
    return false;
end

--- Drops every specialization's entry but the one being played.
local function ClearOtherSpecTalents(ctx)
    local mine = DebindPrivate.SpecIDForIndex(C_SpecializationInfo.GetSpecialization());
    for _, action in ipairs(ctx.actions) do
        local talents = TalentConditionOf(action);
        if (talents) then
            for specID in pairs(talents) do
                if (specID ~= mine) then
                    talents[specID] = nil;
                end
            end
            PruneTalents(action);
            PruneConditions(action);
        end
    end
    return OnActionsChanged(ctx.actions);
end







--- **The one place this file turns a menu value into stored state.** Every handler the kit
--- makes goes in and out through these (`MenuKit.MakeHandlers`), so what a write costs after the
--- values moved is written once, in `Commit`.
---
--- `targetObj` used to let a bit checkbox name some other table to work on. Nothing ever passed
--- one, so nothing ever ran that branch, and it is not carried over.
local ActionValues = {
    Targets = function(ctx)
        return ctx.actions;
    end,

    Get = function(action, key)
        local holder, field = CastingHolder(action, key);
        if (holder) then
            return holder[field];
        end
        local tbl = TableFor(action, key);
        return tbl and tbl[key];
    end,

    Set = function(action, key, value)
        local holder, field = CastingHolder(action, key, value ~= nil);
        if (holder) then
            holder[field] = value;
            PruneCasting(action);
            return;
        end
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
    end,

    -- The checkbox branch comes through here as well. No checkbox in this menu is a step in the
    -- ordering today, so the renumber moves nothing -- but the day one that is arrives here, that
    -- group alone would quietly keep the old symptom.
    Commit = function(ctx)
        return OnActionsChanged(ctx.actions);
    end,
};

local ActionHandlers = MenuKit.MakeHandlers(ActionValues);

local actionValueEquals = ActionHandlers.equals;
local setActionValue = ActionHandlers.set;

local CastKeyChoiceOf = DebindPrivate.CastKeyChoiceOf;

local function CastKeyChoiceIs(ctx, row, choice)
    return AllActions(ctx, function(action)
        return CastKeyChoiceOf(action, row) == choice;
    end);
end

local function SetCastKeyChoice(ctx, row, choice)
    local value;
    if (choice ~= "cast") then
        value = choice;
    end
    for _, action in ipairs(ctx.actions) do
        ActionValues.Set(action, "casting." .. row, value);
    end
    return OnActionsChanged(ctx.actions);
end

local HoverCastChoiceOf = DebindPrivate.HoverCastChoiceOf;

--- Hover Cast's own three, where the absent value is off rather than the pointed unit
--- (`Misc.lua`'s `HoverCastChoiceOf`). nil is the choice here, not the lack of one.
local function HoverCastChoiceIs(ctx, choice)
    return AllActions(ctx, function(action)
        return HoverCastChoiceOf(action) == choice;
    end);
end

local function SetHoverCastChoice(ctx, choice)
    for _, action in ipairs(ctx.actions) do
        ActionValues.Set(action, "casting.hoverCast", choice);
    end
    return OnActionsChanged(ctx.actions);
end

--- Hover Cast's other question, which units count as pointed at. An action with it turned off keeps
--- this: turning it back on should find the mode the reader picked.
local function SetHoverCastMode(ctx, mode)
    for _, action in ipairs(ctx.actions) do
        ActionValues.Set(action, "casting.hoverCastMode", mode);
    end
    return OnActionsChanged(ctx.actions);
end

--- **On is the absent value**, so the box cannot be one of the kit's: those store what they are
--- ticked with (`MenuKit.TOGGLE`), and here that would write the default into every action the
--- reader ticks.
local function NormalCastIsOn(ctx)
    return AllActions(ctx, DebindPrivate.NormalCastEnabled);
end

local function ToggleNormalCast(ctx)
    local value;
    if (NormalCastIsOn(ctx)) then
        value = false;
    end
    for _, action in ipairs(ctx.actions) do
        ActionValues.Set(action, "casting.normalCast", value);
    end
    return OnActionsChanged(ctx.actions);
end

--- The action menu's family (`MenuKit.NewRegistry`). Every condition group is a node on it;
--- what is left off is the rest of the edit menu, which stage 3 takes
--- (`putting-the-menus-on-a-kit.md`).
local ActionMenus = MenuKit.NewRegistry({
    accessor = ActionValues,

    decorateChoice = DecorateChoice,

    mixedCount = function(node, ctx)
        return NodeMixedCount(node, ctx);
    end,

    --- **What wears a new-feature dot. Emptying this list at a release takes them all off.**
    newFeatures = { "ROLE" },

    -- **Not every group's key is an issue category.** Half the keys this menu writes have no check
    -- by that name (`combat`, `known`, `stealth`, `extrabar`, custom states, importance). Asking
    -- anyway would answer nil all the same, but asking for a category that does not exist trips
    -- DEBUG. The first action in the selection with a problem is the one the row speaks for.
    issueForKey = function(ctx, key)
        if (Constants.BINDING_ISSUE_CATEGORIES[key]) then
            for _, action in ipairs(ctx.actions) do
                local issue = DebindPrivate.GetBindingIssue(action, key);
                if (issue) then
                    return issue;
                end
            end
        end
    end,

    -- **Through `TableFor`.** Conditions live in `action.conditions`, so reading the top level
    -- always gives nil and no group with a condition would turn blue. A key that is not a condition
    -- (`priority`) is read off the action. **Blue when any selected action has it**: the colour says
    -- there is something in here to look at.
    isActiveForKey = function(ctx, key)
        return AnyAction(ctx, function(action)
            local tbl = TableFor(action, key);
            return tbl ~= nil and tbl[key] ~= nil;
        end);
    end,

    --- 이슈 코드를 문장과 색으로. **등급이 색을 고른다** (`Misc.lua`의 `GetIssueColor`).
    --- Clique가 개체창을 가져간 것처럼 **그 묶음에서 고칠 것이 없는** 문제까지 빨갛게
    --- 칠하면, 열어 본 사람이 고칠 것을 찾다가 못 찾는다.
    resolveIssue = function(issue)
        return DebindPrivate.IssueSentence(issue), DebindPrivate.GetIssueColor(issue);
    end,
});

--- What one action holds under a node, as text only an equal value produces: its own `valueOf`, or
--- the value under its `key`, then each child's.
local function NodeValueText(node, action)
    local parts = {};
    local value;
    if (node.valueOf) then
        value = node.valueOf(action);
    elseif (node.key) then
        value = ActionValues.Get(action, node.key);
    end
    parts[1] = DebindPrivate.CanonicalValue(value) or "";
    for _, child in ipairs(node.children or {}) do
        parts[#parts + 1] = NodeValueText(ActionMenus:Get(child), action);
    end
    return table.concat(parts, "|");
end

--- How many selected actions have something set under a group row, or nil where they all hold the
--- same.
---
--- **Where every action has it set and they hold different things, the count is all of them.** The
--- number says how many have anything here; that they disagree is what its being there says.
function NodeMixedCount(node, ctx)
    local actions = ctx.actions;
    if (#actions < 2) then
        return nil;
    end
    local active, first, differs = 0, nil, false;
    for i = 1, #actions do
        local isActive = WithOneAction(ctx, actions[i], ActionMenus.IsActive, ActionMenus, node, ctx);
        if (isActive) then
            active = active + 1;
        end
        local text = (isActive and "1" or "0") .. NodeValueText(node, actions[i]);
        if (i == 1) then
            first = text;
        elseif (text ~= first) then
            differs = true;
        end
    end
    if (not differs or active == 0) then
        return nil;
    end
    return active;
end

--- Read and write one unit condition, one field per axis (`Profile.lua`'s `dbver <= 4` step).
---
--- Three radios at the top of the submenu line up with the three shapes storage has: no key
--- (unconstrained), a table (exists, plus whatever axes it names), `false` (absent). Every
--- axis is one field inside that table, so a new axis adds a block to the menu and leaves
--- these accessors alone.
---
--- **Every one of these reads the table off the action when it is called** rather than capturing
--- it. `units` is nil until the first condition is set, so a reference grabbed while the menu was
--- being built goes stale the moment the user turns one on.
local function UnitConditionAxisOf(action, unit, axis)
    local units = UnitConditionsOf(action);
    local value = units and units[unit];
    if (type(value) ~= "table") then
        return nil;
    end
    return value[axis];
end

--- Which of the three radios above is on for one action, `nil` where no condition was ever made.
---
--- **The reading is `UnitConditionForBinding`'s and not a second one.** This used to spell the
--- same fork out again -- scalars first, then `off`, then `exists == false` -- with a comment
--- saying the two had to agree. The day they parted, the screen would have said [when there is
--- one] while the binding meant [when there is not], and only somebody pressing the key would have
--- found out. `ActionTooltip.lua` reads unit conditions the same way, for the same reason.
---
--- **`off` is the one thing that function cannot answer.** It conflates a turned-off condition
--- with an absent one, answering `nil` for both, which is right for a binding and wrong for a
--- menu: this screen has to keep showing the axes a reader turned off but did not throw away.
--- So it is asked here, ahead of the shared reading.
local function UnitConditionModeOf(action, unit)
    local units = UnitConditionsOf(action);
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

--- 조건이 실제로 걸려 있는가. 꺼진 채로 축만 기억하는 것은 조건이 아니다 - 묶음을 파랗게
--- 칠하는 자리들이 이걸 물어야 **끈 조건 때문에 "걸려 있음"으로 보이지** 않는다.
local function UnitConditionOnFor(action, unit)
    local mode = UnitConditionModeOf(action, unit);
    return mode == "exists" or mode == "absent";
end

--- Is the [when there is one] radio on for every selected action. The axis blocks under it are
--- locked on this, so they open only where every action has a table to write into.
local function UnitConditionIsExists(ctx, unit)
    return AllActions(ctx, function(action)
        return UnitConditionModeOf(action, unit) == "exists";
    end);
end

--- Is the [Disable] radio on for every selected action: no condition made, or one turned off.
local function UnitConditionIsOff(ctx, unit)
    return AllActions(ctx, function(action)
        local mode = UnitConditionModeOf(action, unit);
        return mode == nil or mode == "disabled";
    end);
end

--- Is the [when there is none] radio on for every selected action. **Only a condition saying so**:
--- an action with no condition on the unit is [Disable]'s, and reading it here too drew two ticks.
local function UnitConditionIsAbsent(ctx, unit)
    return AllActions(ctx, function(action)
        return UnitConditionModeOf(action, unit) == "absent";
    end);
end

--- Is the condition on for any selected action. What paints a row blue.
local function UnitConditionIsOn(ctx, unit)
    return AnyAction(ctx, function(action)
        return UnitConditionOnFor(action, unit);
    end);
end

--- Is the life radio holding `value` on every selected action.
local function UnitConditionDeadIs(ctx, unit, value)
    return AllActions(ctx, function(action)
        return UnitConditionAxisOf(action, unit, "dead") == value;
    end);
end

--- 이 유닛 조건이 기억하고 있는 축이 하나라도 있는가.
---
--- **축이 하나 늘 때마다 여기 항이 하나 는다.** 빠뜨리면 그 축만 걸어둔 유닛이 [사용 안
--- 함]으로 옮기는 순간 기억되는 대신 지워진다. 소속을 넣을 때 실제로 그렇게 빠졌다. 두
--- 자리가 같은 물음을 하므로 값이 하나여야 한다(`SetUnitConditionMode`, `SetPlayerLife`).
local function UnitConditionRemembersAxis(cond)
    return cond.reaction ~= nil or cond.dead ~= nil or cond.role ~= nil or cond.group ~= nil
        or cond.frameTypes ~= nil;
end

--- What the three radios at the top write into one action. **It moves the mode and leaves the axes
--- alone**: a reader who switches to [Disable] and back has to find the reaction and the life they
--- picked still there. Ignoring them while the condition is off is `Misc.UnitConditionForBinding`'s
--- job.
---
--- **Each of the three modes carries a value of its own.** While an empty table meant [when there
--- is one], an action carrying a single unit condition signed the same as an action carrying no
--- condition at all, and the duplicate check paired the two. The `dbver <= 6` step raises the old
--- values.
---
--- A key with nothing left to remember is deleted rather than left as an empty table, or a unit
--- nothing was ever picked for piles up in the profile.
local function WriteUnitConditionMode(action, unit, mode)
    local units = UnitConditionsOf(action);
    local cond = units and units[unit];
    if (type(cond) ~= "table") then
        cond = {};
    end
    -- **Not `and false or`.** That idiom cannot return `false`: when the test is true,
    -- `true and false` is `false`, which is again the left of the `or`, so the right side comes
    -- out. Written that way, [when there is none] stored nothing and matched [when there is one].
    cond.disabled = (mode == "disabled") or nil;
    if (mode == "absent") then
        cond.exists = false;
    elseif (mode == "disabled") then
        cond.exists = nil;
    else
        cond.exists = true;
    end

    if (mode == "disabled" and not UnitConditionRemembersAxis(cond)) then
        -- Nothing left to remember. An empty table would pile up units nothing was picked for.
        if (units) then
            units[unit] = nil;
            if (not next(units)) then
                action.conditions.units = nil;
                PruneConditions(action);
            end
        end
    else
        if (units == nil) then
            units = {};
            TableFor(action, "units", true).units = units;
        end
        units[unit] = cond;
    end
end

local function SetUnitConditionMode(ctx, unit, mode)
    for _, action in ipairs(ctx.actions) do
        WriteUnitConditionMode(action, unit, mode);
    end
    return OnActionsChanged(ctx.actions);
end

--- Write one axis on every selected action. Every caller is gated on the `exists` radio being on
--- for all of them, so the tables are already there; one that is not is skipped rather than made.
local function SetUnitConditionAxis(ctx, unit, axis, value)
    for _, action in ipairs(ctx.actions) do
        local cond = UnitConditionsOf(action) and UnitConditionsOf(action)[unit];
        if (type(cond) == "table") then
            cond[axis] = value;
        end
    end
    return OnActionsChanged(ctx.actions);
end

--- The reaction, group, role and frame type boxes share one rule. Storage is a mask, but **all-on
--- is never written** -- that says the same thing as constraining nothing, and one condition stored
--- two ways is two different boxes to the solver.
---
--- 0 **is** written. Choosing nothing is not something to normalize away; it is an issue, and
--- `GetBindingIssue` reads the stored row and reports it where the user set it.
local function UnitConditionMaskChecked(ctx, unit, axis, value)
    return AllActions(ctx, function(action)
        local mask = UnitConditionAxisOf(action, unit, axis);
        return mask == nil or bit.band(mask, value) == value;
    end);
end

--- **One outcome for the selection, and each action keeps its other bits.** On when some action
--- lacks the bit, off when every one has it.
local function ToggleUnitConditionMask(ctx, unit, axis, value, allMask)
    local turnOn = not UnitConditionMaskChecked(ctx, unit, axis, value);
    for _, action in ipairs(ctx.actions) do
        local cond = UnitConditionsOf(action) and UnitConditionsOf(action)[unit];
        if (type(cond) == "table") then
            local mask = cond[axis] or allMask;
            if (turnOn) then
                mask = bit.bor(mask, value);
            else
                mask = mask - bit.band(mask, value);
            end
            if (mask == allMask) then
                mask = nil;
            end
            cond[axis] = mask;
        end
    end
    return OnActionsChanged(ctx.actions);
end

local function UnitConditionReactionChecked(ctx, unit, value)
    return UnitConditionMaskChecked(ctx, unit, "reaction", value);
end

local function ToggleUnitConditionReaction(ctx, unit, value)
    return ToggleUnitConditionMask(ctx, unit, "reaction", value, Constants.REACTION_ALL);
end

--- 소속 확인란. **셋이 서로 겹친다** - 공대에서 같은 소그룹인 사람은 [파티]와 [공대]에
--- 다 든다. 그래서 [파티]만 켜도 파티가 공대가 된 뒤에 옆자리 사람에게 계속 걸린다.
--- 반응·역할과 같은 규칙: 전부 켠 값은 안 쓰고, 0은 쓴다.
local function UnitConditionGroupChecked(ctx, unit, value)
    return UnitConditionMaskChecked(ctx, unit, "group", value);
end

local function ToggleUnitConditionGroup(ctx, unit, value)
    return ToggleUnitConditionMask(ctx, unit, "group", value, Constants.UNITGROUP_ALL);
end

--- 프레임 종류 확인란. 반응·소속과 같은 규칙이고, 사는 곳도 같다 - 가리킨 개체창의 유닛에
--- 걸린 조건 하나의 축이다.
local function UnitConditionFrameTypeChecked(ctx, unit, value)
    return UnitConditionMaskChecked(ctx, unit, "frameTypes", value);
end

local function ToggleUnitConditionFrameType(ctx, unit, value)
    return ToggleUnitConditionMask(ctx, unit, "frameTypes", value, Constants.FRAMETYPE_ALL);
end

--- The role boxes. Same rule as the reaction ones above: all-on is never written, and 0 is.
local function UnitConditionRoleChecked(ctx, unit, value)
    return UnitConditionMaskChecked(ctx, unit, "role", value);
end

local function ToggleUnitConditionRole(ctx, unit, value)
    return ToggleUnitConditionMask(ctx, unit, "role", value, Constants.ROLE_ALL);
end

--- What the two drawing files and the entry points reach in here. Everything else above is this
--- file's own.
ActionMenu.REACTION_ITEMS            = REACTION_ITEMS;
ActionMenu.LIFE_ITEMS                = LIFE_ITEMS;
ActionMenu.UNITGROUP_ITEMS           = UNITGROUP_ITEMS;
ActionMenu.ROLE_ITEMS                = ROLE_ITEMS;
ActionMenu.FRAMETYPE_ITEMS           = FRAMETYPE_ITEMS;
ActionMenu.SORTED_UNIT_LIST          = SORTED_UNIT_LIST;
ActionMenu.USE_CHECKED_VALUE         = USE_CHECKED_VALUE;
ActionMenu.range                     = range;
ActionMenu.GetTabList                = GetTabList;
ActionMenu.SetInstructionTooltip     = SetInstructionTooltip;
ActionMenu.SetErrorTooltip           = SetErrorTooltip;

ActionMenu.AllActions                = AllActions;
ActionMenu.AnyAction                 = AnyAction;
ActionMenu.HowManyAccept             = HowManyAccept;
ActionMenu.OnlyOneReason             = OnlyOneReason;
ActionMenu.MixedCount                = MixedCount;
ActionMenu.NodeMixedCount            = NodeMixedCount;
ActionMenu.CreateRadio               = CreateRadio;
ActionMenu.CreateCheckbox            = CreateCheckbox;

ActionMenu.ActionMenus               = ActionMenus;
ActionMenu.OnActionsChanged          = OnActionsChanged;
ActionMenu.TableFor                  = TableFor;
ActionMenu.PruneConditions           = PruneConditions;
ActionMenu.UnitConditionsOf          = UnitConditionsOf;
ActionMenu.SpecConditionsOf          = SpecConditionsOf;
ActionMenu.SpecConditionHasID        = SpecConditionHasID;
ActionMenu.ToggleSpecConditionID     = ToggleSpecConditionID;
ActionMenu.TalentConditionIs         = TalentConditionIs;
ActionMenu.TalentConditionTouches    = TalentConditionTouches;
ActionMenu.HasOtherSpecTalents       = HasOtherSpecTalents;
ActionMenu.ClearOtherSpecTalents     = ClearOtherSpecTalents;
ActionMenu.SetTalentCondition        = SetTalentCondition;
ActionMenu.ClassSpecsAllPicked       = ClassSpecsAllPicked;
ActionMenu.ToggleClassSpecs          = ToggleClassSpecs;
ActionMenu.actionHandlers            = ActionHandlers;
ActionMenu.actionValueEquals         = actionValueEquals;
ActionMenu.setActionValue            = setActionValue;

ActionMenu.CastKeyChoiceOf           = CastKeyChoiceOf;
ActionMenu.CastKeyChoiceIs           = CastKeyChoiceIs;
ActionMenu.SetCastKeyChoice          = SetCastKeyChoice;
ActionMenu.HoverCastChoiceIs         = HoverCastChoiceIs;
ActionMenu.SetHoverCastChoice        = SetHoverCastChoice;
ActionMenu.SetHoverCastMode          = SetHoverCastMode;
ActionMenu.NormalCastIsOn            = NormalCastIsOn;
ActionMenu.ToggleNormalCast          = ToggleNormalCast;

ActionMenu.UnitConditionAxisOf       = UnitConditionAxisOf;
ActionMenu.UnitConditionModeOf       = UnitConditionModeOf;
ActionMenu.UnitConditionOnFor        = UnitConditionOnFor;
ActionMenu.UnitConditionIsExists     = UnitConditionIsExists;
ActionMenu.UnitConditionIsOff        = UnitConditionIsOff;
ActionMenu.UnitConditionIsAbsent     = UnitConditionIsAbsent;
ActionMenu.UnitConditionIsOn         = UnitConditionIsOn;
ActionMenu.UnitConditionDeadIs       = UnitConditionDeadIs;
ActionMenu.WriteUnitConditionMode    = WriteUnitConditionMode;
ActionMenu.SetUnitConditionMode      = SetUnitConditionMode;
ActionMenu.SetUnitConditionAxis      = SetUnitConditionAxis;
ActionMenu.UnitConditionReactionChecked = UnitConditionReactionChecked;
ActionMenu.ToggleUnitConditionReaction  = ToggleUnitConditionReaction;
ActionMenu.UnitConditionGroupChecked = UnitConditionGroupChecked;
ActionMenu.ToggleUnitConditionGroup  = ToggleUnitConditionGroup;
ActionMenu.UnitConditionRoleChecked  = UnitConditionRoleChecked;
ActionMenu.ToggleUnitConditionRole   = ToggleUnitConditionRole;
ActionMenu.UnitConditionRemembersAxis = UnitConditionRemembersAxis;
ActionMenu.UnitConditionFrameTypeChecked = UnitConditionFrameTypeChecked;
ActionMenu.ToggleUnitConditionFrameType  = ToggleUnitConditionFrameType;
