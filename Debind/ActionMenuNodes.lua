local _, DebindPrivate      = ...;
local Constants             = DebindPrivate.Constants;
local LLL                   = DebindPrivate.L;
local DebindUI              = DebindPrivate.DebindUI;
local MenuKit               = DebindPrivate.MenuKit;

local dump                  = DebindPrivate.dump
local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;

--- **The condition groups.** One node per axis an action can be conditioned on. The order they
--- are drawn in is not here: the place that opens the menu holds it (`DropDownMenus.lua`'s
--- `SetupActionDropdownMenu`).
---
--- Reading and writing values is all `ActionMenuModel.lua`, and drawing a row is `MenuKit.lua`.
--- What is left in this file is which group asks what and shows what
--- (`putting-the-menus-on-a-kit.md`).
local ActionMenu                     = DebindPrivate.ActionMenu;
local ActionMenus                    = ActionMenu.ActionMenus;
local OnActionsChanged               = ActionMenu.OnActionsChanged;
local AllActions                     = ActionMenu.AllActions;
local AnyAction                      = ActionMenu.AnyAction;
local OnlyOneReason                  = ActionMenu.OnlyOneReason;
local CreateRadio                    = ActionMenu.CreateRadio;
local CreateCheckbox                 = ActionMenu.CreateCheckbox;
local TableFor                       = ActionMenu.TableFor;
local PruneConditions                = ActionMenu.PruneConditions;
local UnitConditionsOf               = ActionMenu.UnitConditionsOf;
local SpecConditionsOf               = ActionMenu.SpecConditionsOf;
local TalentConditionIs              = ActionMenu.TalentConditionIs;
local TalentConditionTouches         = ActionMenu.TalentConditionTouches;
local HasOtherSpecTalents            = ActionMenu.HasOtherSpecTalents;
local ClearOtherSpecTalents          = ActionMenu.ClearOtherSpecTalents;
local SetTalentCondition             = ActionMenu.SetTalentCondition;
local SpecConditionHasIndex          = ActionMenu.SpecConditionHasIndex;
local ToggleSpecConditionIndex       = ActionMenu.ToggleSpecConditionIndex;
local ClassSpecsAllPicked            = ActionMenu.ClassSpecsAllPicked;
local ToggleClassSpecs               = ActionMenu.ToggleClassSpecs;
local UnitConditionOnFor             = ActionMenu.UnitConditionOnFor;
local UnitConditionIsExists          = ActionMenu.UnitConditionIsExists;
local UnitConditionIsOn              = ActionMenu.UnitConditionIsOn;
local UnitConditionDeadIs            = ActionMenu.UnitConditionDeadIs;
local WriteUnitConditionMode         = ActionMenu.WriteUnitConditionMode;
local SetUnitConditionMode           = ActionMenu.SetUnitConditionMode;
local SetUnitConditionAxis           = ActionMenu.SetUnitConditionAxis;
local UnitConditionReactionChecked   = ActionMenu.UnitConditionReactionChecked;
local ToggleUnitConditionReaction    = ActionMenu.ToggleUnitConditionReaction;
local UnitConditionGroupChecked      = ActionMenu.UnitConditionGroupChecked;
local ToggleUnitConditionGroup       = ActionMenu.ToggleUnitConditionGroup;
local UnitConditionRoleChecked       = ActionMenu.UnitConditionRoleChecked;
local ToggleUnitConditionRole        = ActionMenu.ToggleUnitConditionRole;
local UnitConditionRemembersAxis     = ActionMenu.UnitConditionRemembersAxis;
local UnitConditionFrameTypeChecked  = ActionMenu.UnitConditionFrameTypeChecked;
local ToggleUnitConditionFrameType   = ActionMenu.ToggleUnitConditionFrameType;
local REACTION_ITEMS                 = ActionMenu.REACTION_ITEMS;
local LIFE_ITEMS                     = ActionMenu.LIFE_ITEMS;
local UNITGROUP_ITEMS                = ActionMenu.UNITGROUP_ITEMS;
local ROLE_ITEMS                     = ActionMenu.ROLE_ITEMS;
local FRAMETYPE_ITEMS                = ActionMenu.FRAMETYPE_ITEMS;
local SORTED_UNIT_LIST               = ActionMenu.SORTED_UNIT_LIST;
local range                          = ActionMenu.range;
local SetInstructionTooltip          = ActionMenu.SetInstructionTooltip;

local BONUSBAR_NAMES;


local UnitConditionIsOff             = ActionMenu.UnitConditionIsOff;
local UnitConditionIsAbsent          = ActionMenu.UnitConditionIsAbsent;

--- The first problem any selected action has with `unit`'s condition.
local function FirstUnitIssue(ctx, unit)
    for _, action in ipairs(ctx.actions) do
        local issue = DebindPrivate.GetBindingIssue(action, "units", nil, unit);
        if (issue) then
            return issue;
        end
    end
end

--- The axes one unit condition can carry. **This order is the order on screen.**
---
--- **`onlyPointedFrame` is the two that only a unit frame can answer.** A frame has a type and the
--- unit on a group frame has a role; neither can be read off a unit token, so the answer for a unit
--- that is not the one being pointed at is "yes" and the rows would say nothing
--- (`which-action-a-key-runs.md` §0). Only `"unitframe"` and the unit this action aims at
--- can be that unit.
local UNIT_CONDITION_AXES = {
    {
        axis = "reaction",
        title = "CONDITION_REACTIONS",
        append = function(description, ctx, unit, isEnabled)
            for _, item in ipairs(REACTION_ITEMS) do
                local reactionDescription = CreateCheckbox(description, ctx,item.text,
                    function()
                        return UnitConditionReactionChecked(ctx, unit, item.value);
                    end,
                    function()
                        return ToggleUnitConditionReaction(ctx, unit, item.value);
                    end
                );
                reactionDescription:SetEnabled(isEnabled);
            end
        end,
    },
    {
        axis = "dead",
        title = "CONDITION_LIFE",
        -- A two-valued axis gets radios. **What the UI can produce is exactly what storage can
        -- hold**, so the "neither box ticked" a checkbox pair would open up -- a condition no unit
        -- can satisfy -- never comes into existence. Reactions have three values and so need
        -- somewhere to pick a subset; that group stores its 0 and lets `GetBindingIssue` catch it.
        -- This is where the two axes part.
        append = function(description, ctx, unit, isEnabled)
            for _, item in ipairs(LIFE_ITEMS) do
                local lifeDescription = CreateRadio(description, ctx,item.text,
                    function()
                        return UnitConditionDeadIs(ctx, unit, item.value);
                    end,
                    function()
                        return SetUnitConditionAxis(ctx, unit, "dead", item.value);
                    end
                );
                lifeDescription:SetEnabled(isEnabled);
            end
        end,
    },
    {
        axis = "group",
        title = "CONDITION_UNIT_GROUP",
        append = function(description, ctx, unit, isEnabled)
            for _, item in ipairs(UNITGROUP_ITEMS) do
                local groupDescription = CreateCheckbox(description, ctx,item.text,
                    function()
                        return UnitConditionGroupChecked(ctx, unit, item.value);
                    end,
                    function()
                        return ToggleUnitConditionGroup(ctx, unit, item.value);
                    end
                );
                groupDescription:SetEnabled(isEnabled);
            end
        end,
    },
    {
        axis = "frameTypes",
        title = "CONDITION_FRAMETYPES",
        onlyPointedFrame = true,
        append = function(description, ctx, unit, isEnabled)
            for _, item in ipairs(FRAMETYPE_ITEMS) do
                local typeDescription = CreateCheckbox(description, ctx, item.text,
                    function()
                        return UnitConditionFrameTypeChecked(ctx, unit, item.value);
                    end,
                    function()
                        return ToggleUnitConditionFrameType(ctx, unit, item.value);
                    end
                );
                typeDescription:SetEnabled(isEnabled);
                SetInstructionTooltip(typeDescription, LLL["CONDITION_FRAMETYPES_DESC"]);

                --- **역할은 파티/공대 개체창 아래에 산다.** 맵의 키가 그룹 유닛 토큰이라 그
                --- 종류의 개체창만 답을 낼 수 있고(`Constants.lua`), 자리가 그것을 말한다.
                --- 그 줄을 안 켰으면 물을 것이 없으므로 하위 항목도 같이 잠근다.
                if (item.value == Constants.FRAMETYPE_GROUP) then
                    MenuKit.CreateTitle(typeDescription, LLL["CONDITION_ROLE"]);
                    for _, role in ipairs(ROLE_ITEMS) do
                        local roleDescription = CreateCheckbox(typeDescription, ctx, role.text,
                            function()
                                return UnitConditionRoleChecked(ctx, unit, role.value);
                            end,
                            function()
                                return ToggleUnitConditionRole(ctx, unit, role.value);
                            end
                        );
                        SetInstructionTooltip(roleDescription, LLL["CONDITION_ROLE_DESC"]);
                        roleDescription:SetEnabled(function()
                            return isEnabled()
                                and UnitConditionFrameTypeChecked(ctx, unit, Constants.FRAMETYPE_GROUP);
                        end);
                    end
                    ActionMenus:MarkNew("ROLE", typeDescription);
                end
            end
        end,
    },
};

local function CreateUnitConditionSubmenu(parentDescription, ctx, label, unit)
    -- Put together here because the sentence names two settings by their own labels
    -- (`RESOLVED_TARGET_DESC`).
    local instruction;
    if (unit == "@") then
        instruction = format(LLL["RESOLVED_TARGET_DESC"], LLL["TARGET_UNIT"], AUTO_SELF_CAST_KEY_TEXT,
            FOCUS_CAST_KEY_TEXT, LLL["CASTING_AS_USUAL"], LLL["POINTED_UNIT_CAST"]);
    end

    local optionsDescription = ActionMenus:BuildNode(parentDescription, {
        label = label,
        instruction = instruction,
        skipTitle = true,
        valueOf = function(action)
            local units = UnitConditionsOf(action);
            return units and units[unit];
        end,
        isActive = function()
            return UnitConditionIsOn(ctx, unit);
        end,
        issue = function()
            return FirstUnitIssue(ctx, unit);
        end,
    }, ctx);

    MenuKit.CreateTitle(optionsDescription, MenuUtil.GetElementText(optionsDescription));

    CreateRadio(optionsDescription, ctx,LLL["DISABLE"],
        function()
            return UnitConditionIsOff(ctx, unit);
        end,
        function()
            return SetUnitConditionMode(ctx, unit, "disabled");
        end
    );

    -- The three above are exclusive; the axis blocks below are alive only while `exists` is
    -- picked, which is what `axisIsEnabled` answers.
    CreateRadio(optionsDescription, ctx,LLL["CONDITION_UNIT_EXISTS"],
        function()
            return UnitConditionIsExists(ctx, unit);
        end,
        function()
            return SetUnitConditionMode(ctx, unit, "exists");
        end
    );

    local absentDescription = CreateRadio(optionsDescription, ctx,LLL["CONDITION_UNIT_DOES_NOT_EXIST"],
        function()
            return UnitConditionIsAbsent(ctx, unit);
        end,
        function()
            return SetUnitConditionMode(ctx, unit, "absent");
        end
    );

    -- `"@"`는 이 액션이 **겨누는** 대상이다. 없는 유닛은 겨눌 수 없으니 "없을 때"라는 말이
    -- 설 자리가 없다. 줄을 빼지 않고 잠그는 이유는, 다른 유닛과 같은 메뉴라는 것이 보여야
    -- 여기만 다른 문법이라고 읽지 않기 때문이다.
    if (unit == "@") then
        absentDescription:SetEnabled(false);
    end

    local function axisIsEnabled()
        return UnitConditionIsExists(ctx, unit);
    end

    --- Which axes a unit has is the unit's own answer (`ActionDisplay.lua`'s `UNIT_INFO`). An
    --- axis with only one possible answer is left out rather than greyed: a locked row says "not
    --- right now", a missing one says there is no such question here.
    ---
    --- `"@"` has no row there. It is whatever this action aims at, so nothing is taken off it.
    local unitInfo = DebindUI.UNIT_INFO[unit];
    local axes = unitInfo and unitInfo.conditionAxes;
    local pointedFrame = unit == "unitframe" or unit == "@";
    for _, block in ipairs(UNIT_CONDITION_AXES) do
        if ((axes == nil or axes[block.axis] ~= false)
                and (pointedFrame or not block.onlyPointedFrame)) then
            optionsDescription:CreateDivider();
            MenuKit.CreateTitle(optionsDescription, LLL[block.title]);
            block.append(optionsDescription, ctx, unit, axisIsEnabled);
        end
    end

    return optionsDescription;
end


--- Whether this menu has a row for `unit`, which is also whether it counts it.
--- `"player"` is edited by the life menu under `Group`. **Counting it here changes a condition this
--- menu does not show**: while it was missing from this test, [Disable All] switched the reader's
--- own life condition off, and nothing here could bring it back.
---
--- **Outside the node.** Inside it, the `isActive` closure would capture a name that is not there
--- yet and read nil at run time.
local function isListedUnit(unit)
    return unit ~= "player";
end

--- The units one action has a condition on that this menu lists.
local function ListedUnitsWithCondition(action)
    local units;
    if (UnitConditionsOf(action)) then
        for unit in pairs(UnitConditionsOf(action)) do
            if (isListedUnit(unit) and UnitConditionOnFor(action, unit)) then
                units = units or {};
                tinsert(units, unit);
            end
        end
    end
    return units;
end

local function BuildUnitConditionMenu(kit, ctx)
    local description = kit.description;

    CreateRadio(description, ctx,LLL["DISABLE_ALL"],
        function()
            return AllActions(ctx, function(action)
                return ListedUnitsWithCondition(action) == nil;
            end);
        end,
        function()
            -- **Turns off, does not erase.** The reactions and life picked stay where they are;
            -- there is no reason to make the reader pick them again when they turn it back on.
            --
            -- The names are gathered first because turning off deletes a unit that has nothing to
            -- remember, and when the last goes `units` itself becomes nil under the loop walking it.
            for _, action in ipairs(ctx.actions) do
                local units = ListedUnitsWithCondition(action);
                if (units) then
                    for i = 1, #units do
                        WriteUnitConditionMode(action, units[i], "disabled");
                    end
                end
            end
            return OnActionsChanged(ctx.actions);
        end
    );

    CreateUnitConditionSubmenu(description, ctx, "RESOLVED_TARGET", "@");

    for _, unit in ipairs(SORTED_UNIT_LIST) do
        -- **그리는 줄과 세는 유닛이 같은 목록이어야 한다.** `isListedUnit`이 그 목록이고,
        -- 갈리면 이 메뉴가 안 그리는 조건으로 파래지거나 빨개진다. `"none"`만 여기 더 있다 -
        -- 그건 유닛이 아니라 대상 없음이라 조건이 붙을 자리가 아예 없다.
        if (unit ~= "@" and isListedUnit(unit) and unit ~= "none") then
            CreateUnitConditionSubmenu(description, ctx, DebindUI.UNIT_INFO[unit].name, unit);
        end
    end
end

ActionMenus:Define("UNITS", {
    label = "CONDITION_UNITS",
    key = "units",
    -- 위 `isListedUnit`이 무엇을 세는지 정한다.
    isActive = function(ctx)
        return AnyAction(ctx, function(action)
            return ListedUnitsWithCondition(action) ~= nil;
        end);
    end,
    valueOf = function(action)
        local listed = {};
        for unit, cond in pairs(UnitConditionsOf(action) or {}) do
            if (isListedUnit(unit)) then
                listed[unit] = cond;
            end
        end
        return listed;
    end,
    build = BuildUnitConditionMenu,
});

--- 읽는 이 자신의 생사. **저장은 `units.player.dead`이고, 새 조건이 아니다.**
---
--- 그 축은 이미 끝까지 서 있다 - 솔버 컬럼, 방출, 상태 루프, 클릭 경로가 다른 유닛과
--- 똑같이 `player`를 잰다. 없던 것은 그 값을 만들 자리뿐이었다: `Units` 묶음이 `player`를
--- 목록에서 빼기 때문에(자기 자신에는 존재/부재 라디오가 걸 것이 없다) 손으로 고친
--- 프로필로만 들어왔다.
---
--- 최상위 조건 `conditions.dead`를 새로 두는 안은 안 잡았다. 같은 물음이 두 형태로
--- 저장되면 솔버가 다른 상자로 보고, 컬럼과 방출과 두 경로를 한 벌씩 더 쓰게 된다.
---
--- **`Units` 묶음에는 `player`를 넣지 않는다.** 넣으면 한 값을 두 메뉴가 편집한다.
--- 여기가 `Group`과 나란한 것도 그래서다. 둘 다 읽는 이 자신을 묻는다.
local function BuildSelfLifeConditionMenu(kit, ctx)
    local description = kit.description;

    --- **Not the other axes' setter.** That one is only called once the `exists` radio has stood a
    --- table up, and there is no such radio here, so the first press makes the table. Clearing is
    --- the same in reverse: this place has one axis, so emptying it leaves nothing, and an empty
    --- table left behind piles up a unit nothing was picked for (the same tidying
    --- `WriteUnitConditionMode` does when it turns one off).
    local function WritePlayerLife(action, value)
        local units = UnitConditionsOf(action);
        if (value == nil) then
            local cond = units and units.player;
            if (type(cond) == "table") then
                cond.dead = nil;
                -- A table holding only a mode marker is a unit nothing was picked for.
                -- `exists == false` cannot be made here, but a shared profile can bring one in, so
                -- it is kept.
                if (not UnitConditionRemembersAxis(cond) and cond.exists ~= false
                        and not cond.disabled) then
                    units.player = nil;
                    if (not next(units)) then
                        action.conditions.units = nil;
                        PruneConditions(action);
                    end
                end
            end
        else
            if (units == nil) then
                units = {};
                TableFor(action, "units", true).units = units;
            end
            local cond = units.player;
            if (type(cond) ~= "table") then
                cond = {};
                units.player = cond;
            end
            -- **The off marker goes too.** This menu has no row that sets `disabled`, but a shared
            -- profile or a hand edit can bring one in, and while it stands
            -- `UnitConditionForBinding` ignores the whole condition and the radio draws on -- a
            -- value with no row to bring it back.
            cond.disabled = nil;
            -- The reader always exists, so there is one mode. It is written anyway: a table with
            -- no mode is the old shape, and storage does not make new ones of those.
            if (cond.exists == nil) then
                cond.exists = true;
            end
            cond.dead = value;
        end
    end

    for _, item in ipairs(LIFE_ITEMS) do
        CreateRadio(description, ctx,item.text,
            function()
                return UnitConditionDeadIs(ctx, "player", item.value);
            end,
            function()
                for _, action in ipairs(ctx.actions) do
                    WritePlayerLife(action, item.value);
                end
                return OnActionsChanged(ctx.actions);
            end
        );
    end
end

ActionMenus:Define("SELFLIFE", {
    label = "CONDITION_LIFE",
    isActive = function(ctx)
        return AnyAction(ctx, function(action)
            local units = UnitConditionsOf(action);
            local cond = units and units.player;
            return type(cond) == "table" and not cond.disabled and cond.dead ~= nil;
        end);
    end,
    valueOf = function(action)
        local units = UnitConditionsOf(action);
        return units and units.player;
    end,
    build = BuildSelfLifeConditionMenu,
});

ActionMenus:Define("GROUP", {
    label = "CONDITION_GROUP",
    key = "groups",
    build = function(kit)
        kit:Disable("CONDITION_GROUP", "groups");
        kit:Checkboxes("groups", {
            { text = LLL["GROUP_NONE"],  value = Constants.GROUP_NONE },
            { text = LLL["GROUP_PARTY"], value = Constants.GROUP_PARTY },
            { text = LLL["GROUP_RAID"],  value = Constants.GROUP_RAID },
        });
    end,
});

--- The blue a `MenuKit` row wears while it is doing something, on a checkbox the family did not
--- build. `Registry:BuildNode` paints the rows it makes (`MenuKit.lua`); a checkbox is made
--- straight off the description, so the one thing it misses is put back here.
---
--- **The tick and the colour answer different questions.** A box says what this row holds and the
--- colour says whether anything under it is picked at all, which is what a reader scanning a closed
--- menu needs before they open anything (2026-09-22, owner).
local function PaintWhenActive(description, isActive)
    description:AddInitializer(function(button)
        local color = isActive() and BLUE_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
        button.fontString:SetTextColor(color:GetRGB());
    end);
    return description;
end

--- Does this class hold a specialization on any selected action, which is what paints its row.
---
--- **The colour follows what the condition picks.** A class nobody picked is not what the key is
--- for and stays unpainted; a class holding one specialization is this axis doing something, and
--- it is painted (2026-09-22, owner).
---
--- **A class half picked has no box of its own to say so.** The class row's own checkbox is
--- `ClassSpecsAllPicked` -- on when every specialization under it is, off otherwise -- so "off"
--- alone cannot tell "none picked" from "some picked". The row's colour is what carries that
--- difference, painted by hand below rather than by the family (`MenuKit.lua`), because a
--- checkbox row is not one the family builds.
local function ClassSpecConditionIsOn(ctx, classID)
    return AnyAction(ctx, function(action)
        return DebindPrivate.SpecSetHoldsAnyOfClass(SpecConditionsOf(action), classID);
    end);
end

--- **Names, one class at a time.** The condition is a mask per class, so a class is a key and its
--- specializations are the bits under it: **what the set holds is what the key is for**, and a class
--- with no key is one nobody picked (2026-09-22, owner).
---
--- **Every class is offered, not just this character's.** An action moves between tabs and can sit
--- in General, where it is a character of another class that will press the key.
---
--- The nameless initial specialization sits under each class rather than in a row of its own at
--- the bottom: it is one bit of that class's mask, so one row for all of them could only turn
--- every class's over at once.
---
--- **The class row is itself the whole-class checkbox, not a button that opens one.** Checking it
--- picks every specialization under it and unchecking clears them (`ClassSpecsAllPicked`,
--- `ToggleClassSpecs`); ticking every specialization by hand checks it back on the same way. That
--- makes a separate "All Specs" row under the submenu redundant -- the class row already answers
--- the question it would ask.
---
--- **No [Uncheck All] row either.** What it wrote is a set holding nothing, which is an error
--- rather than a destination (`BINDING_ISSUE_SPECS_NONE_SELECTED`), and the way out of the axis is
--- the `Disable` radio one row up. A button offering the error state as a shortcut is the one row
--- this menu has no use for.
ActionMenus:Define("SPEC", {
    label = "CONDITION_SPEC",
    key = "specs",
    build = function(kit)
        kit:Disable("CONDITION_SPEC", "specs");

        local catalog = DebindPrivate.ClassSpecCatalog();
        for i = 1, #catalog do
            local class = catalog[i];
            local specs = class.specs;
            local classID = class.id;
            if (#specs > 0) then
                local classDescription = CreateCheckbox(kit.description, kit.ctx,
                    Constants.CLASS_NAMES[class.classFile],
                    function()
                        return ClassSpecsAllPicked(kit.ctx, classID);
                    end,
                    function()
                        return ToggleClassSpecs(kit.ctx, classID);
                    end);
                PaintWhenActive(classDescription, function()
                    return ClassSpecConditionIsOn(kit.ctx, classID);
                end);

                for j = 1, #specs do
                    local index = specs[j].index;
                    local specDescription = CreateCheckbox(classDescription, kit.ctx,
                        specs[j].name or LLL["NO_SPECIALIZATION"],
                        function()
                            return SpecConditionHasIndex(kit.ctx, classID, index);
                        end,
                        function()
                            return ToggleSpecConditionIndex(kit.ctx, classID, index);
                        end);
                    PaintWhenActive(specDescription, function()
                        return SpecConditionHasIndex(kit.ctx, classID, index);
                    end);
                end
            end
        end

    end,
});

--- Which specializations one row writes to: **the one being played, and only that one.**
---
--- The class tree branch used to write every specialization of the class, on the grounds that a
--- class talent means the same thing in all of them. What that did was put a setting where the
--- reader cannot see it: this menu opens the specialization being played, so the other four keys
--- could not be read, changed or removed -- and one of them was the initial specialization, which
--- nobody can switch to (2026-09-19, owner).
local function TalentSpecIDs()
    return { DebindPrivate.SpecIDForIndex(C_SpecializationInfo.GetSpecialization()) };
end

--- One talent: taken, not taken, or neither.
---
--- **Three rows and not two.** A row that can only be turned on is a row the reader cannot take
--- back without clearing the whole condition, and clearing it would take every other talent with
--- it.
local function BuildTalentRow(parent, ctx, specIDs, row)
    local ids = { [row.id] = true };
    local description = ActionMenus:BuildNode(parent, {
        label = row.name,
        skipTitle = true,
        -- **The colour walks up from here.** This row, the tree it sits in and `Talents` itself all
        -- answer the same question, so a talent picked five levels down is visible from the top
        -- (`MenuKit.lua` paints an active node blue).
        isActive = function()
            return TalentConditionTouches(ctx, specIDs[1], ids);
        end,
    }, ctx);
    if (not description) then
        return;
    end

    local states = {
        { text = LLL["DISABLE"], value = nil },
        { text = LLL["CONDITION_TALENT_TAKEN"], value = "taken" },
        { text = LLL["CONDITION_TALENT_NOT_TAKEN"], value = "notTaken" },
    };
    for i = 1, #states do
        local state = states[i];
        CreateRadio(description, ctx, state.text,
            function()
                return TalentConditionIs(ctx, specIDs, row.id, state.value);
            end,
            function()
                return SetTalentCondition(ctx, specIDs, row.id, state.value);
            end);
    end
end

--- **Talents, this specialization's** (`adding-a-talent-condition.md` §5). The
--- class tree,
--- this specialization's tree, one branch per hero tree and the pvp talents, each named the way
--- the game names it.
---
--- **A selection of several actions is fine here**, unlike `known`: the rows come from the
--- character rather than from the action, so every action in the selection is offered the same
--- ones and a row that disagrees between them reads as unset, which is what ticking it fixes.
ActionMenus:Define("TALENT", {
    label = "CONDITION_TALENT",
    key = "talents",
    -- **Blue for what is reachable under this row.** The five tree branches are the specialization
    -- being played, and a key written on another one reaches the block at the bottom instead -- so
    -- both count, and the trail the colour promises ends on a row that exists either way.
    --
    -- The `Remove all` row itself is left alone (2026-09-19, owner): the colour is a trail to
    -- follow, and the end of it is where the reader acts rather than another step.
    isActive = function(ctx)
        local mine = DebindPrivate.SpecIDForIndex(C_SpecializationInfo.GetSpecialization());
        return AnyAction(ctx, function(action)
            local talents = action.conditions and action.conditions.talents;
            return mine ~= nil and talents ~= nil and talents[mine] ~= nil;
        end) or AnyAction(ctx, HasOtherSpecTalents);
    end,
    build = function(kit)
        local groups = DebindPrivate.Talents.GetMenu();
        for i = 1, #groups do
            local group = groups[i];
            if (#group.rows > 0) then
                local specIDs = TalentSpecIDs();
                -- One set per tree, so the tree's colour is one lookup per action rather than one
                -- per row.
                local groupIDs = {};
                for j = 1, #group.rows do
                    groupIDs[group.rows[j].id] = true;
                end
                -- **The hero trees say what they are.** The other four rows are named after
                -- something the reader already reads as a heading -- their class, their
                -- specialization, pvp -- and a hero tree's name is just a name.
                local label = group.name or "?";
                if (group.key == "hero") then
                    label = format(LLL["CONDITION_TALENT_HERO"], label);
                end
                local description = ActionMenus:BuildNode(kit.description, {
                    label = label,
                    skipTitle = true,
                    isActive = function(ctx)
                        return TalentConditionTouches(ctx, specIDs[1], groupIDs);
                    end,
                }, kit.ctx);
                if (description) then
                    for j = 1, #group.rows do
                        BuildTalentRow(description, kit.ctx, specIDs, group.rows[j]);
                    end
                end
            end
        end

        -- **The block stands whether or not there is anything in it.** Their talents are not
        -- listed here and cannot be, so a reader who has none has no way to tell that apart from
        -- the menu not saying; the empty line is the answer to the question this block exists to
        -- raise.
        kit.description:CreateDivider();
        kit.description:CreateTitle(LLL["CONDITION_TALENT_OTHER_SPECS"]);
        if (AnyAction(kit.ctx, HasOtherSpecTalents)) then
            local clear = kit.description:CreateButton(LLL["CONDITION_TALENT_CLEAR_OTHERS"],
                function()
                    return ClearOtherSpecTalents(kit.ctx);
                end);
            SetInstructionTooltip(clear, LLL["CONDITION_TALENT_CLEAR_OTHERS_DESC"]);
        else
            local none = kit.description:CreateButton(LLL["CONDITION_TALENT_NO_OTHERS"]);
            none:SetEnabled(false);
        end
    end,
});

--- The spells this action's `known` can ask about: the one it holds and everything that shares a
--- root with it, root first (`Spells.BuildBranches`). A talent that replaces a spell is what the
--- reader is picking between, so the chain is the list.
---
--- **Rows are names.** That is what the condition stores, because a spell has an id per
--- specialization and a talent combination can stand up one no walk ever sees
--- (`making-known-a-spell-name.md`).
---
--- The stored value leads, and it is there even when the walk does not know it: a name from
--- another specialization, or an id the client could not name. Without that row the reader sees a
--- condition the tooltip reports and no way to tell which one is on.
local function KnownRows(action)
    local rows, seen = {}, {};

    local function Add(value)
        if (value ~= nil and not seen[value]) then
            seen[value] = true;
            rows[#rows + 1] = value;
        end
    end

    Add(action.conditions and action.conditions.known);

    local root = DebindPrivate.ResolveBaseSpell(action.value);
    local family = root and DebindPrivate.Spells.GetBranches()[root];
    for i = 1, (family and #family or 0) do
        Add((GetSpellNameAndIconID(family[i])));
    end

    -- **The action's own spell, last and usually already there.** The walk only covers what this
    -- specialization can obtain, so an action holding another one's spell reaches no family at all
    -- and would open a menu with nothing to pick. The one thing always askable about an action is
    -- the spell it casts.
    Add((GetSpellNameAndIconID(action.value)));

    return rows;
end

local function AsksKnown(action)
    return action.type == Constants.SPELL or Constants.SPEC_RESOLVED_TYPES[action.type] == true;
end

--- **Spells only.** An item or a macro is not something you can fail to know. The three
--- spec-resolved types are spells too, and what the condition asks about is the spell this
--- specialization resolves to (`SpecSpells.lua`).
---
--- **One action at a time.** The rows come out of the action's own spell, so a selection has no one
--- list to offer.
ActionMenus:Define("KNOWN", {
    label = "CONDITION_KNOWN",
    key = "known",
    shown = function(ctx)
        return AnyAction(ctx, AsksKnown);
    end,
    blocked = OnlyOneReason,
    build = function(kit)
        local action = kit.ctx.actions[1];
        -- **A box and not a list**, because these three carry no spell to list. Which spell the
        -- key casts is decided at the rebuild, so `true` -- "whatever this action casts" -- is the
        -- only question that survives a specialization change here.
        if (Constants.SPEC_RESOLVED_TYPES[action.type]) then
            kit:ClearingCheckbox(LLL["CONDITION_KNOWN_YES"], "known", true);
            return;
        end

        kit:Disable("CONDITION_KNOWN", "known");

        -- **Walked once per open.** `GetBranches` walks the spellbook and every talent tree on
        -- each call, so the rows are taken here rather than asked for one at a time.
        -- **The rows are names and nothing else.** The title above them says what picking one
        -- does, the way the specialization list's rows are bare names too; a sentence on every
        -- row would repeat it four times and sit oddly beside `Disable`. The sentence is in the
        -- tooltip, where the condition is read rather than picked (`ActionTooltip.lua`).
        local rows = KnownRows(action);
        for i = 1, #rows do
            CreateRadio(kit.description, kit.ctx, rows[i], kit.handlers.equals, kit.handlers.set,
                { ctx = kit.ctx, key = "known", value = rows[i] });
        end
    end,
});

--- 사용 안 함/예/아니오 셋뿐인 갈래들. 축 이름과 키만 다르다.
for _, axis in ipairs({
    { name = "COMBAT",  label = "CONDITION_COMBAT",  key = "combat" },
    { name = "STEALTH", label = "CONDITION_STEALTH", key = "stealth" },
    { name = "MOUNTED",    label = "CONDITION_MOUNTED",    key = "mounted" },
    { name = "SKYRIDING",  label = "CONDITION_SKYRIDING",  key = "skyriding" },
    { name = "FLYABLE",    label = "CONDITION_FLYABLE",    key = "flyable" },
    { name = "ADVFLYABLE", label = "CONDITION_ADVFLYABLE", key = "advflyable" },
    { name = "FLYING",     label = "CONDITION_FLYING",     key = "flying" },
    { name = "INDOORS",    label = "CONDITION_INDOORS",    key = "indoors" },
    { name = "PETBATTLE",  label = "CONDITION_PETBATTLE",  key = "petbattle" },
}) do
    ActionMenus:Define(axis.name, {
        label = axis.label,
        key = axis.key,
        build = function(kit)
            kit:DisableYesNo(axis.label, axis.key);
        end,
    });
end

ActionMenus:Define("SHAPESHIFT", {
    label = "CONDITION_SHAPESHIFT",
    key = "forms",
    build = function(kit)
        kit:Disable("CONDITION_SHAPESHIFT", "forms");
        kit:Checkboxes("forms", range(0, 10, function(formId)
            local shapeshiftName;
            if (formId == 0) then
                shapeshiftName = LLL["NO_SHAPESHIFT"];
            else
                local _, _, _, spellID = GetShapeshiftFormInfo(formId);
                shapeshiftName = spellID and GetSpellNameAndIconID(spellID) or nil;
            end
            local label = format(LLL["CONDITION_FORM_N"], formId);
            if (shapeshiftName) then
                label = format("%s (%s)", label, shapeshiftName);
            end
            return { text = label, value = 2 ^ formId };
        end));
    end,
});

--- **The four that were not worth a row each.** `petbattle` was one of the top level's own rows
--- until `mounted` and `indoors` arrived and the list ran past what an eye reads down.
---
--- **`skyriding` is here rather than beside the bar offsets it reads**, and that is the whole
--- reason it is an axis of its own: nobody who wants "while flying" goes looking for it under
--- an action bar setting. Reusing `bonusbars` bit 5 would have cost no new field and would
--- have written the negative as `[bonusbar:0/1/2/3/4]` in the tooltip.
ActionMenus:Define("MISC", {
    label = "CONDITION_MISC",
    children = {
        "MOUNTED", "SKYRIDING", "FLYABLE", "ADVFLYABLE", "FLYING", "INDOORS", "PETBATTLE",
    },
    isActive = function(ctx)
        return AnyAction(ctx, function(action)
            local c = action.conditions;
            return c ~= nil and (c.mounted ~= nil or c.skyriding ~= nil
                or c.flyable ~= nil or c.advflyable ~= nil or c.flying ~= nil
                or c.indoors ~= nil or c.petbattle ~= nil);
        end);
    end,
});

--- **The first branch on the kit** (`putting-the-menus-on-a-kit.md`). The row that
--- opens this used to name `{ "bonusbars", "specialbar" }` beside itself so a red child would
--- redden it; the tree says who the children are, so the list is gone and a fourth one added
--- here brings its own colour up with it.
ActionMenus:Define("ACTIONBAR", {
    label = "CONDITION_ACTIONBARS",
    children = { "BONUSBAR", "SPECIALBAR", "EXTRABAR" },
    isActive = function(ctx)
        -- `action.bars`는 아무도 안 쓰는 필드였다. `KEYS_TO_SAVE`에 없어 늘 nil이라 이
        -- 절은 죽어 있었고, 나머지 셋이 같은 답을 낸다.
        return AnyAction(ctx, function(action)
            local c = action.conditions;
            return c ~= nil and (c.bonusbars ~= nil or c.specialbar ~= nil or c.extrabar ~= nil);
        end);
    end,
});

ActionMenus:Define("BONUSBAR", {
    label = "CONDITION_BONUSBAR",
    key = "bonusbars",
    build = function(kit)
        if (BONUSBAR_NAMES == nil) then
            BONUSBAR_NAMES = {
                [0] = LLL["DEFAULT"],
                [5] = GetFlyoutInfo(229)
            };
            if (Constants.PLAYER_CLASS == "DRUID") then
                BONUSBAR_NAMES[1] = GetSpellNameAndIconID(768);
                BONUSBAR_NAMES[3] = GetSpellNameAndIconID(5487);
                BONUSBAR_NAMES[4] = GetSpellNameAndIconID(24858);
            elseif (Constants.PLAYER_CLASS == "ROGUE") then
                BONUSBAR_NAMES[1] = GetSpellNameAndIconID(1784);
            end
        end

        kit:Disable("CONDITION_BONUSBAR", "bonusbars");
        kit:Checkboxes("bonusbars", range(0, Constants.MAX_BONUSBAR_OFFSET, function(offset)
            local name = BONUSBAR_NAMES[offset];
            local label = format("[bonusbar:%d]", offset);
            if (name) then
                label = format("%s (%s)", label, name);
            end
            return { text = label, value = 2 ^ offset };
        end));
    end,
});

ActionMenus:Define("SPECIALBAR", {
    label = "CONDITION_SPECIALBAR",
    key = "specialbar",
    build = function(kit)
        kit:DisableYesNo("CONDITION_SPECIALBAR", "specialbar");
    end,
});

--- **No check carries this name**, so the row never reddens and nothing rolls up from it. It is
--- a value the reader sets like the two above it, which is why it stands beside them.
ActionMenus:Define("EXTRABAR", {
    label = "CONDITION_EXTRABAR",
    key = "extrabar",
    build = function(kit)
        kit:DisableYesNo("CONDITION_EXTRABAR", "extrabar");
    end,
});

local function BuildSwitchConditionMenu(kit, ctx)
    local description = kit.description;

    -- **Only switches that exist** (2026-08-21, 소유자). A condition on a name nothing defines
    -- matches on neither `true` nor `false`, so the key it is on never fires. Offering a name to
    -- hang one on was offering a dead end.
    --
    -- **The dead end is marked, and that is not a reason to offer it.** `GetUndefinedSwitch`
    -- reads condition keys as well as bodies and targets, so such an action goes red and drops
    -- out of `KeyMap` (`Misc.lua`). The mark is there for the ways a name goes undefined *after*
    -- the condition was hung - a switch deleted, a string from someone else - and a list that
    -- lets the reader build one on purpose is a list that manufactures work for it.
    --
    -- **Making one is at the bottom of this list**, which is not the same thing: a name typed
    -- there gets a definition before the condition goes on, so nothing here ever hangs a
    -- condition on a name nothing defines.
    --
    -- **Plus whatever any selected action already names**, defined or not, because taking a
    -- condition off is done here and nowhere else. A switch deleted while an action still names it
    -- would otherwise leave that condition on the action with no way to reach it, which is worse
    -- than the dead end this list just stopped offering.
    local switchNames = DebindPrivate.GetSwitchNames();
    local listed = {};
    for _, name in ipairs(switchNames) do
        listed[name] = true;
    end
    for _, action in ipairs(ctx.actions) do
        for name in pairs(action.conditions or {}) do
            if (not listed[name] and Constants.IsSwitchName(name)
                    and not DebindPrivate.ResolveSwitchDefinition(name)) then
                listed[name] = true;
                switchNames[#switchNames + 1] = name;
            end
        end
    end
    sort(switchNames);

    -- 위 묶음이 빨개지는 것은 "이 액션에 끊긴 조건이 있다"이고, 여기가 빨개지는 것은
    -- **어느 것인지**다.
    local function UndefinedSwitchError(name)
        if (not DebindPrivate.ResolveSwitchDefinition(name)) then
            return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], name);
        end
    end

    for _, stateName in ipairs(switchNames) do
        -- isActive는 안 준다. 키로 조건 표를 읽는 기본 판정이 맞다.
        ActionMenus:BuildNode(description, {
            label = stateName,
            key = stateName,
            issue = function()
                return UndefinedSwitchError(stateName);
            end,
            build = function(stateKit)
                stateKit:DisableYesNo("CONDITION_CUSTOM_STATE", stateName);
            end,
        }, ctx);
    end

    -- **만드는 자리가 여기에도 있다** (§6-2). 조건을 걸려고 이 메뉴를 연 사람은 이미
    -- "이 액션이 언제 나갈지"를 생각하고 있고, 그 자리에서 스위치가 없다는 것을 안다.
    -- 창을 닫고 탭으로 건너가서 만들고 돌아와 다시 이 메뉴를 여는 왕복이 이 기능을 아무도
    -- 안 쓰는 이유로 지목된 하나다.
    --
    -- **만들고 나서 그 조건을 바로 켠다.** 만들기만 하면 방금 지나온 자리를 한 번 더
    -- 지나야 하고, 이름을 적은 사람이 원한 것은 정의가 아니라 이 액션에 걸린 조건이다.
    local actions = ctx.actions;
    local newDescription = description:CreateButton(LLL["SWITCH_CREATE"], function()
        DebindUI.ShowNewSwitchBox(function(name)
            for _, action in ipairs(actions) do
                action.conditions = action.conditions or {};
                action.conditions[name] = true;
            end
            OnActionsChanged(actions);
        end);
    end);
    SetInstructionTooltip(newDescription, LLL["SWITCH_CREATE_DESC"]);

    description:CreateDivider();
    MenuKit.CreateHelpButton(description, "switches", LLL["HELP_SWITCHES_TITLE"]);
end

ActionMenus:Define("SWITCHES", {
    label = "CONDITION_CUSTOM_STATES",

    -- 설명은 **명시적으로** 찍어 넘긴다. 안 넘기면 `CONDITION_CUSTOM_STATES_DESC`를
    -- 찾아가는데, 그건 `CUSTOM_STATES_DESC`와 글자 하나 다르지 않은 문단이었다. 같은
    -- 말을 로케일마다 두 번 번역하게 만드는 자리라 키를 없애고 이쪽으로 붙였다.
    -- 저쪽 키는 초상화의 스위치 단추 툴팁이었고, 3c가 그 단추를 걷은 뒤로는
    -- `Switches` 탭 자신의 툴팁이다(`DebindUI.lua`의 `PANELS`).
    instruction = LLL["CUSTOM_STATES_DESC"],

    -- **조건 표에 스위치 이름이 하나라도 있느냐.** 다섯 번호를 돌던 자리인데, 이 갈래가
    -- 켜져 보이느냐는 액션에 실제로 걸린 것을 따라가야 한다 - 다섯 밖의 이름이 걸린
    -- 액션이 "조건 없음"으로 보이면 그 조건을 지울 자리가 화면에서 사라진다.
    isActive = function(ctx)
        return AnyAction(ctx, function(action)
            for name in pairs(action.conditions or {}) do
                if (Constants.IsSwitchName(name)) then
                    return true;
                end
            end
            return false;
        end);
    end,

    valueOf = function(action)
        local named = {};
        for name, value in pairs(action.conditions or {}) do
            if (Constants.IsSwitchName(name)) then
                named[name] = value;
            end
        end
        return named;
    end,

    -- **자식에서 안 올라온다.** 스위치 줄은 이름이 있을 때만 생기는 노드라 트리에 자식이
    -- 없고, 그래서 이 갈래는 자기가 답한다. 하나로 물을 수 있는 물음이라 그래도 된다.
    --
    -- **본문 오타로는 안 빨개진다.** `GetUndefinedSwitch`는 매크로 본문과
    -- 켜기/끄기/전환의 대상까지 같이 답하므로, 그걸 쓰면 조건은 멀쩡한데 이 칸이
    -- 빨개져서 고칠 곳을 엉뚱한 데로 가리킨다. 조건만 보는 문이 따로 있다.
    issue = function(ctx)
        for _, action in ipairs(ctx.actions) do
            local name = DebindPrivate.GetUndefinedSwitchCondition(action);
            if (name) then
                return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], name);
            end
        end
    end,

    build = BuildSwitchConditionMenu,
});
