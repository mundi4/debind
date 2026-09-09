local _, DebindPrivate      = ...;
local Constants             = DebindPrivate.Constants;
local LLL                   = DebindPrivate.L;
local DebindUI              = DebindPrivate.DebindUI;
local MenuKit               = DebindPrivate.MenuKit;

local dump                  = DebindPrivate.dump
local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;

--- **The condition groups.** One node per axis an action can be conditioned on. The order they
--- are drawn in is not here: the place that opens the menu holds it (`DropDownMenus.lua`'s
--- `SetupEditDropdownMenu`).
---
--- Reading and writing values is all `ActionMenuModel.lua`, and drawing a row is `MenuKit.lua`.
--- What is left in this file is which group asks what and shows what
--- (`devdocs/legacy/putting-the-menus-on-a-kit.md`).
local ActionMenu                     = DebindPrivate.ActionMenu;
local ActionMenus                    = ActionMenu.ActionMenus;
local OnActionValueChanged           = ActionMenu.OnActionValueChanged;
local TableFor                       = ActionMenu.TableFor;
local PruneConditions                = ActionMenu.PruneConditions;
local UnitConditionsOf               = ActionMenu.UnitConditionsOf;
local SpecConditionsOf               = ActionMenu.SpecConditionsOf;
local SpecConditionHasID             = ActionMenu.SpecConditionHasID;
local ToggleSpecConditionID          = ActionMenu.ToggleSpecConditionID;
local ClassSpecsAllPicked            = ActionMenu.ClassSpecsAllPicked;
local ToggleClassSpecs               = ActionMenu.ToggleClassSpecs;
local UnitConditionMode              = ActionMenu.UnitConditionMode;
local UnitConditionIsExists          = ActionMenu.UnitConditionIsExists;
local UnitConditionIsOn              = ActionMenu.UnitConditionIsOn;
local GetUnitConditionDead           = ActionMenu.GetUnitConditionDead;
local SetUnitConditionMode           = ActionMenu.SetUnitConditionMode;
local SetUnitConditionAxis           = ActionMenu.SetUnitConditionAxis;
local UnitConditionReactionChecked   = ActionMenu.UnitConditionReactionChecked;
local ToggleUnitConditionReaction    = ActionMenu.ToggleUnitConditionReaction;
local UnitConditionGroupChecked      = ActionMenu.UnitConditionGroupChecked;
local ToggleUnitConditionGroup       = ActionMenu.ToggleUnitConditionGroup;
local UnitConditionRoleChecked       = ActionMenu.UnitConditionRoleChecked;
local ToggleUnitConditionRole        = ActionMenu.ToggleUnitConditionRole;
local UnitConditionRemembersAxis     = ActionMenu.UnitConditionRemembersAxis;
local HoverFrameTypeChecked          = ActionMenu.HoverFrameTypeChecked;
local hoverConditionIsOn             = ActionMenu.hoverConditionIsOn;
local REACTION_ITEMS                 = ActionMenu.REACTION_ITEMS;
local LIFE_ITEMS                     = ActionMenu.LIFE_ITEMS;
local UNITGROUP_ITEMS                = ActionMenu.UNITGROUP_ITEMS;
local ROLE_ITEMS                     = ActionMenu.ROLE_ITEMS;
local FRAMETYPE_DEFAULT              = ActionMenu.FRAMETYPE_DEFAULT;
local SORTED_UNIT_LIST               = ActionMenu.SORTED_UNIT_LIST;
local range                          = ActionMenu.range;
local SetInstructionTooltip          = ActionMenu.SetInstructionTooltip;

local BONUSBAR_NAMES;


--- The three axes one unit condition can carry. **This order is the order on screen.**
local UNIT_CONDITION_AXES = {
    {
        axis = "reaction",
        title = "CONDITION_REACTIONS",
        append = function(description, ctx, unit, isEnabled)
            for _, item in ipairs(REACTION_ITEMS) do
                local reactionDescription = description:CreateCheckbox(item.text,
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
                local lifeDescription = description:CreateRadio(item.text,
                    function()
                        return GetUnitConditionDead(ctx, unit) == item.value;
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
                local groupDescription = description:CreateCheckbox(item.text,
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
};

local function CreateUnitConditionSubmenu(parentDescription, ctx, label, unit)
    local optionsDescription = ActionMenus:BuildNode(parentDescription, {
        label = label,
        skipTitle = true,
        isActive = function()
            return UnitConditionIsOn(ctx, unit);
        end,
        issue = function()
            return DebindPrivate.GetBindingIssue(ctx.action, "units", nil, unit);
        end,
    }, ctx);

    local titleDescription = MenuKit.CreateTitle(optionsDescription, MenuUtil.GetElementText(optionsDescription));
    if (unit == "@") then
        -- 여는 줄은 `Only if...`로 두고, **어느 유닛에 거는 조건인지는 안쪽 제목이 말한다.**
        -- 바깥 줄까지 대상 이름으로 바꾸면 바로 위 라디오 목록이 방금 고른 그 이름을 한 번
        -- 더 되뇌게 된다.
        --
        -- `player`가 빠지는 이유는 다른 것과 같다: 자기 자신은 늘 있으므로 걸 조건이 없다.
        optionsDescription:SetEnabled(function()
            return ctx.action.unit and ctx.action.unit ~= "none" and ctx.action.unit ~= "player"
                and true or false;
        end);

        titleDescription:AddInitializer(function(button, elementDescription, menu)
            if (ctx.action.unit and ctx.action.unit ~= "none") then
                button.fontString:SetText(format(LLL["SELECTED_TARGET_UNIT"], DebindUI.UNIT_INFO[ctx.action.unit].name));
            else
                button.fontString:SetText(LLL["SELECTED_TARGET_UNIT_EMPTY"]);
            end
        end);
    end

    optionsDescription:CreateRadio(LLL["DISABLE"],
        function()
            local mode = UnitConditionMode(ctx, unit);
            return mode == nil or mode == "disabled";
        end,
        function()
            return SetUnitConditionMode(ctx, unit, "disabled");
        end
    );

    -- The three above are exclusive; the axis blocks below are alive only while `exists` is
    -- picked. Same arrangement the hover menu gets from `hoverConditionIsOn`.
    optionsDescription:CreateRadio(LLL["CONDITION_UNIT_EXISTS"],
        function()
            return UnitConditionIsExists(ctx, unit);
        end,
        function()
            return SetUnitConditionMode(ctx, unit, "exists");
        end
    );

    local absentDescription = optionsDescription:CreateRadio(LLL["CONDITION_UNIT_DOES_NOT_EXIST"],
        function()
            return UnitConditionMode(ctx, unit) == "absent";
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
    for _, block in ipairs(UNIT_CONDITION_AXES) do
        if (axes == nil or axes[block.axis] ~= false) then
            optionsDescription:CreateDivider();
            MenuKit.CreateTitle(optionsDescription, LLL[block.title]);
            block.append(optionsDescription, ctx, unit, axisIsEnabled);
        end
    end

    return optionsDescription;
end


--- 이 메뉴가 만지는 것은 `units["hover"]`다 - **호버한 프레임의 유닛도 유닛이다**
--- (`Profile.lua`의 `dbver <= 4`). 옛 `hover`/`reactions` 두 필드는 없어졌고, 그 이름들은
--- 이제 파생값이라(`Misc.DeriveHoverFields`) 이슈 category로는 그대로 쓴다.
---
--- `frameTypes`와 `ignoreHoverUnit`은 여전히 액션 루트에 있다. 그건 유닛이 아니라
--- **프레임**을 말하는 값이라 접을 축이 아니었다.
local function BuildHoverMenu(kit, ctx)
    local description = kit.description;

    --- 축 위젯들이 잠기는 조건. 설명자에 함수로 넘어가므로 인자를 못 받고, ctx는 여기서
    --- 묶는다.
    local function hoverIsOn()
        return hoverConditionIsOn(ctx);
    end

    -- 유닛 서브메뉴의 라디오 셋과 같은 세 상태다. 글자만 이 자리의 말로 쓴다 -
    -- 여기서는 "존재"가 곧 "마우스를 올리고 있음"이다.
    description:CreateRadio(rawget(LLL, "CONDITION_HOVER_DISABLE") or LLL["DISABLE"],
        function()
            local mode = UnitConditionMode(ctx, "hover");
            return mode == nil or mode == "disabled";
        end,
        function()
            return SetUnitConditionMode(ctx, "hover", "disabled");
        end
    );

    description:CreateRadio(LLL["CONDITION_HOVER_YES"],
        function()
            return UnitConditionIsExists(ctx, "hover");
        end,
        function()
            return SetUnitConditionMode(ctx, "hover", "exists");
        end
    );

    description:CreateRadio(LLL["CONDITION_HOVER_NO"],
        function()
            return UnitConditionMode(ctx, "hover") == "absent";
        end,
        function()
            return SetUnitConditionMode(ctx, "hover", "absent");
        end
    );


    description:CreateDivider();
    MenuKit.CreateTitle(description, LLL["CONDITION_REACTIONS"]);

    for _, item in ipairs(REACTION_ITEMS) do
        local reactionDescription = description:CreateCheckbox(item.text,
            function()
                return UnitConditionReactionChecked(ctx, "hover", item.value);
            end,
            function()
                return ToggleUnitConditionReaction(ctx, "hover", item.value);
            end
        );
        reactionDescription:SetEnabled(hoverIsOn);
    end

    description:CreateDivider();
    MenuKit.CreateTitle(description, LLL["CONDITION_LIFE"]);

    for _, item in ipairs(LIFE_ITEMS) do
        local lifeDescription = description:CreateRadio(item.text,
            function()
                return GetUnitConditionDead(ctx, "hover") == item.value;
            end,
            function()
                return SetUnitConditionAxis(ctx, "hover", "dead", item.value);
            end
        );
        lifeDescription:SetEnabled(hoverIsOn);
    end

    description:CreateDivider();
    MenuKit.CreateTitle(description, LLL["CONDITION_UNIT_GROUP"]);

    for _, item in ipairs(UNITGROUP_ITEMS) do
        local groupDescription = description:CreateCheckbox(item.text,
            function()
                return UnitConditionGroupChecked(ctx, "hover", item.value);
            end,
            function()
                return ToggleUnitConditionGroup(ctx, "hover", item.value);
            end
        );
        groupDescription:SetEnabled(hoverIsOn);
    end

    description:CreateDivider();
    MenuKit.CreateTitle(description, LLL["CONDITION_FRAMETYPES"]);

    kit:Checkboxes("frameTypes", {
            { text = LLL["FRAMETYPE_PLAYER"],  value = Constants["FRAMETYPE_PLAYER"] },
            { text = LLL["FRAMETYPE_PET"],     value = Constants["FRAMETYPE_PET"] },
            { text = LLL["FRAMETYPE_GROUP"],   value = Constants["FRAMETYPE_GROUP"] },
            { text = LLL["FRAMETYPE_TARGET"],  value = Constants["FRAMETYPE_TARGET"] },
            { text = LLL["FRAMETYPE_BOSS"],    value = Constants["FRAMETYPE_BOSS"] },
            { text = LLL["FRAMETYPE_ARENA"],   value = Constants["FRAMETYPE_ARENA"] },
            { text = LLL["FRAMETYPE_UNKNOWN"], value = Constants["FRAMETYPE_UNKNOWN"] },
        }, function(elementDescription, item)
            elementDescription:SetEnabled(hoverIsOn);

            --- **역할은 파티/공대 개체창 아래에 산다.** 맵의 키가 그룹 유닛 토큰이라 그
            --- 종류의 개체창만 답을 낼 수 있고(`Constants.lua`), 자리가 그것을 말한다.
            --- 그 줄을 안 켰으면 물을 것이 없으므로 하위 항목도 같이 잠근다.
            if (item.value == Constants.FRAMETYPE_GROUP) then
                MenuKit.CreateTitle(elementDescription, LLL["CONDITION_ROLE"]);
                for _, role in ipairs(ROLE_ITEMS) do
                    local roleDescription = elementDescription:CreateCheckbox(role.text,
                        function()
                            return UnitConditionRoleChecked(ctx, "hover", role.value);
                        end,
                        function()
                            return ToggleUnitConditionRole(ctx, "hover", role.value);
                        end
                    );
                    SetInstructionTooltip(roleDescription, LLL["CONDITION_ROLE_DESC"]);
                    roleDescription:SetEnabled(function()
                        return hoverConditionIsOn(ctx) and HoverFrameTypeChecked(ctx, Constants.FRAMETYPE_GROUP);
                    end);
                end
                ActionMenus:MarkNew("ROLE", elementDescription);
            end
        end,
        FRAMETYPE_DEFAULT
    );

    description:CreateDivider();
    local ignoreHoverUnit = description:CreateCheckbox(LLL["IGNORE_HOVER_UNIT"],
        kit.handlers.equals, kit.handlers.set,
        { ctx = ctx, key = "ignoreHoverUnit", value = MenuKit.TOGGLE });
    SetInstructionTooltip(ignoreHoverUnit, LLL["IGNORE_HOVER_UNIT_DESC"]);
    ignoreHoverUnit:SetEnabled(hoverIsOn);
end

ActionMenus:Define("HOVER", {
    label = "CONDITION_HOVER",
    key = "hover",
    isActive = function(ctx)
        return UnitConditionIsOn(ctx, "hover");
    end,
    build = BuildHoverMenu,
});

--- 이 메뉴가 답할 수 있는 유닛인가. `"@"`는 대상 메뉴가, `"hover"`는 hover 메뉴가,
--- `"player"`는 `Group` 아래 생사 메뉴가 편집한다 - 여기서 건드리면 **안 보여주는 조건이
--- 여기서 바뀐다.** 실제로 `"player"`가 빠져 있는 동안 [전부 사용 안 함]이 읽는 이의 생사
--- 조건을 꺼버렸고, 그 메뉴에는 그것을 되살릴 줄이 없었다.
---
--- **노드 밖에 있다.** 안에 두면 `isActive` 클로저가 만들어지는 시점에 아직 없는 이름을
--- 잡아서 런타임에 nil이 된다.
local function isListedUnit(unit)
    return unit ~= "@" and unit ~= "hover" and unit ~= "player";
end

local function BuildUnitConditionMenu(kit, ctx)
    local description = kit.description;

    local function listedUnitsWithCondition()
        local units;
        if (UnitConditionsOf(ctx.action)) then
            for unit in pairs(UnitConditionsOf(ctx.action)) do
                if (isListedUnit(unit) and UnitConditionIsOn(ctx, unit)) then
                    units = units or {};
                    tinsert(units, unit);
                end
            end
        end
        return units;
    end

    description:CreateRadio(LLL["DISABLE_ALL"],
        function()
            return listedUnitsWithCondition() == nil;
        end,
        function()
            -- **끄기만 한다.** 골라둔 반응·생사는 그 자리에 남는다 - 되돌렸을 때 처음부터
            -- 다시 고르게 만들 이유가 없다.
            --
            -- 이름을 먼저 모으는 이유: 끄는 쪽이 기억할 축이 없는 항목을 지우고, 마지막
            -- 하나가 지워지면 `units` 자체가 nil이 된다. 그 표를 돌면서 하면
            -- 순회하던 표가 사라진다.
            local units = listedUnitsWithCondition();
            if (units) then
                for i = 1, #units do
                    SetUnitConditionMode(ctx, units[i], "disabled");
                end
            end
            OnActionValueChanged(ctx.action);
            return MenuResponse.Refresh;
        end
    );

    -- if (ctx.action.type == Constants.SPELL or ctx.action.type == Constants.ITEM or ctx.action.type == Constants.TARGET or ctx.action.type == Constants.FOCUS or ctx.action.type == Constants.TOGGLEMENU) then
    --     CreateUnitConditionSubmenu(description, "SELECTED_TARGET_UNIT_EMPTY", "@");
    -- end

    for _, unit in ipairs(SORTED_UNIT_LIST) do
        -- `"hover"` is out. `Hovering Over Unit Frame` edits the very same key now, and it is
        -- the one that stays because `frameTypes` and `ignoreHoverUnit` only fit there --
        -- those describe the frame, not the unit on it. Two rows onto one key would be two
        -- ways to say one thing again, which is what the fold just removed.
        -- **그리는 줄과 세는 유닛이 같은 목록이어야 한다.** `isListedUnit`이 그 목록이고,
        -- 갈리면 이 메뉴가 안 그리는 조건으로 파래지거나 빨개진다. `"none"`만 여기 더 있다 -
        -- 그건 유닛이 아니라 대상 없음이라 조건이 붙을 자리가 아예 없다.
        if (isListedUnit(unit) and unit ~= "none") then
            CreateUnitConditionSubmenu(description, ctx, DebindUI.UNIT_INFO[unit].name, unit);
        end
    end
end

ActionMenus:Define("UNITS", {
    label = "CONDITION_UNITS",
    key = "units",
    -- 위 `isListedUnit`이 무엇을 세는지 정한다.
    isActive = function(ctx)
        local units = UnitConditionsOf(ctx.action);
        if (units) then
            for unit in pairs(units) do
                if (isListedUnit(unit) and UnitConditionIsOn(ctx, unit)) then
                    return true;
                end
            end
        end
        return false;
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

    --- 다른 축의 setter를 못 쓴다. 그쪽은 `exists` 라디오가 표를 세워둔 뒤에만 불리는데
    --- 여기는 그 라디오가 없어서 첫 클릭이 표를 만든다. 지울 때도 같다 - 축 하나짜리
    --- 자리라 그 값을 비우면 남는 것이 없고, 빈 표를 남기면 아무것도 안 고른 유닛이
    --- 프로필에 쌓인다(`SetUnitConditionMode`가 끄는 자리에서 하는 것과 같은 정리다).
    local function SetPlayerLife(value)
        local units = UnitConditionsOf(ctx.action);
        if (value == nil) then
            local cond = units and units.player;
            if (type(cond) == "table") then
                cond.dead = nil;
                -- 모드 표시 하나만 남은 표는 아무것도 안 고른 유닛이다. `exists == false`는
                -- 이 메뉴가 못 만들지만 공유 프로필이 들고 올 수 있어서 남긴다.
                if (not UnitConditionRemembersAxis(cond) and cond.exists ~= false
                        and not cond.disabled) then
                    units.player = nil;
                    if (not next(units)) then
                        ctx.action.conditions.units = nil;
                        PruneConditions(ctx.action);
                    end
                end
            end
        else
            if (units == nil) then
                units = {};
                TableFor(ctx.action, "units", true).units = units;
            end
            local cond = units.player;
            if (type(cond) ~= "table") then
                cond = {};
                units.player = cond;
            end
            -- **끈 표시도 같이 지운다.** 이 메뉴에는 `disabled`를 세우는 줄이 없지만 공유
            -- 프로필과 손으로 고친 것이 들고 올 수 있고, 남아 있으면
            -- `UnitConditionForBinding`이 조건을 통째로 무시하는 동안 라디오는 켜진 채로
            -- 그려진다 - 되살릴 줄이 없는 값이 된다.
            cond.disabled = nil;
            -- 읽는 이는 언제나 있으므로 모드는 하나뿐이다. 그래도 적는다: 모드 없는 표는
            -- 옛 값이고, 저장에 새로 만들지 않는다.
            if (cond.exists == nil) then
                cond.exists = true;
            end
            cond.dead = value;
        end

        OnActionValueChanged(ctx.action);
        return MenuResponse.Refresh;
    end

    for _, item in ipairs(LIFE_ITEMS) do
        description:CreateRadio(item.text,
            function()
                return GetUnitConditionDead(ctx, "player") == item.value;
            end,
            function()
                return SetPlayerLife(item.value);
            end
        );
    end
end

ActionMenus:Define("SELFLIFE", {
    label = "CONDITION_LIFE",
    isActive = function(ctx)
        local units = UnitConditionsOf(ctx.action);
        local cond = units and units.player;
        return type(cond) == "table" and not cond.disabled and cond.dead ~= nil;
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

--- Does anything under this class's row carry a tick. **That is the whole of the partial state.**
--- A menu checkbox is on or off with nothing in between, so a class whose specializations are
--- half picked cannot be drawn as a third kind of box; what says so is the row's own colour,
--- which every node in this family already gets from `isActive` (`MenuKit.lua`).
local function ClassSpecConditionIsOn(ctx, specs)
    local conditions = SpecConditionsOf(ctx.action);
    if (conditions == nil) then
        return false;
    end
    for i = 1, #specs do
        if (conditions[specs[i].id] ~= nil) then
            return true;
        end
    end
    return false;
end

--- **Names, one class at a time.** The condition stores specialization ids, so a row means the
--- same specialization wherever the action sits and a class is exactly its own ids: ticking every
--- box under one class is what "while I am a warrior" is
--- (`devdocs/moving-the-spec-condition-to-spec-ids.md`).
---
--- **Every class is offered, not just this character's.** An action moves between tabs and can sit
--- in General, where it is a character of another class that will press the key.
---
--- The nameless initial specialization sits under each class rather than in a row of its own at
--- the bottom: its id differs by class, so one row for all of them could only tick every class's
--- at once.
ActionMenus:Define("SPEC", {
    label = "CONDITION_SPEC",
    key = "specs",
    build = function(kit)
        kit:Disable("CONDITION_SPEC", "specs");
        local catalog = DebindPrivate.ClassSpecCatalog();
        for i = 1, #catalog do
            local class = catalog[i];
            local specs = class.specs;
            if (#specs > 0) then
                local classDescription = ActionMenus:BuildNode(kit.description, {
                    label = Constants.CLASS_NAMES[class.classFile],
                    skipTitle = true,
                    isActive = function(ctx)
                        return ClassSpecConditionIsOn(ctx, specs);
                    end,
                }, kit.ctx);

                -- **The whole class, from inside the submenu rather than from its row.** The
                -- class row is the button that opens this, so an action on it would turn every
                -- box under it over on the click that was meant to open it. The client puts the
                -- same thing in the same place, one row above the specializations and in these
                -- words (`ALL_SPECS`, `Blizzard_ClassMenu`).
                local classID = class.id;
                classDescription:CreateCheckbox(ALL_SPECS,
                    function()
                        return ClassSpecsAllPicked(kit.ctx, classID);
                    end,
                    function()
                        return ToggleClassSpecs(kit.ctx, classID);
                    end);

                for j = 1, #specs do
                    local specID = specs[j].id;
                    classDescription:CreateCheckbox(specs[j].name or LLL["NO_SPECIALIZATION"],
                        function()
                            return SpecConditionHasID(kit.ctx, specID);
                        end,
                        function()
                            return ToggleSpecConditionID(kit.ctx, specID);
                        end);
                end
            end
        end
    end,
});

--- **Spells only.** An item or a macro is not something you can fail to know. The three
--- spec-resolved types are spells too, and what the condition asks about is the spell this
--- specialization resolves to (`SpecSpells.lua`).
ActionMenus:Define("KNOWN", {
    label = "CONDITION_KNOWN",
    key = "known",
    shown = function(ctx)
        return ctx.action.type == Constants.SPELL
            or Constants.SPEC_RESOLVED_TYPES[ctx.action.type] == true;
    end,
    build = function(kit)
        kit:ClearingCheckbox(LLL["CONDITION_KNOWN_YES"], "known", true);
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
        local c = ctx.action.conditions;
        return c ~= nil and (c.mounted ~= nil or c.skyriding ~= nil
            or c.flyable ~= nil or c.advflyable ~= nil or c.flying ~= nil
            or c.indoors ~= nil or c.petbattle ~= nil);
    end,
});

--- **The first branch on the kit** (`devdocs/legacy/putting-the-menus-on-a-kit.md`). The row that
--- opens this used to name `{ "bonusbars", "specialbar" }` beside itself so a red child would
--- redden it; the tree says who the children are, so the list is gone and a fourth one added
--- here brings its own colour up with it.
ActionMenus:Define("ACTIONBAR", {
    label = "CONDITION_ACTIONBARS",
    children = { "BONUSBAR", "SPECIALBAR", "EXTRABAR" },
    isActive = function(ctx)
        -- `action.bars`는 아무도 안 쓰는 필드였다. `KEYS_TO_SAVE`에 없어 늘 nil이라 이
        -- 절은 죽어 있었고, 나머지 셋이 같은 답을 낸다.
        local c = ctx.action.conditions;
        return c ~= nil and (c.bonusbars ~= nil or c.specialbar ~= nil or c.extrabar ~= nil);
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
    local action = ctx.action;

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
    -- **Plus whatever this action already names**, defined or not, because taking a condition
    -- off is done here and nowhere else. A switch deleted while an action still names it would
    -- otherwise leave that condition on the action with no way to reach it, which is worse than
    -- the dead end this list just stopped offering.
    local switchNames = DebindPrivate.GetSwitchNames();
    local conditions = action and action.conditions;
    if (conditions) then
        for name in pairs(conditions) do
            if (Constants.IsSwitchName(name) and not DebindPrivate.ResolveSwitchDefinition(name)) then
                switchNames[#switchNames + 1] = name;
            end
        end
        sort(switchNames);
    end

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
    if (action) then
        local newDescription = description:CreateButton(LLL["SWITCH_CREATE"], function()
            DebindUI.ShowNewSwitchBox(function(name)
                action.conditions = action.conditions or {};
                action.conditions[name] = true;
                OnActionValueChanged(action);
            end);
        end);
        SetInstructionTooltip(newDescription, LLL["SWITCH_CREATE_DESC"]);
    end
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
        local conditions = ctx.action.conditions;
        if (conditions) then
            for name in pairs(conditions) do
                if (Constants.IsSwitchName(name)) then
                    return true;
                end
            end
        end
        return false;
    end,

    -- **자식에서 안 올라온다.** 스위치 줄은 이름이 있을 때만 생기는 노드라 트리에 자식이
    -- 없고, 그래서 이 갈래는 자기가 답한다. 하나로 물을 수 있는 물음이라 그래도 된다.
    --
    -- **본문 오타로는 안 빨개진다.** `GetUndefinedSwitch`는 매크로 본문과
    -- 켜기/끄기/전환의 대상까지 같이 답하므로, 그걸 쓰면 조건은 멀쩡한데 이 칸이
    -- 빨개져서 고칠 곳을 엉뚱한 데로 가리킨다. 조건만 보는 문이 따로 있다.
    issue = function(ctx)
        local name = ctx.action and DebindPrivate.GetUndefinedSwitchCondition(ctx.action);
        if (name) then
            return format(LLL["BINDING_ERROR_UNDEFINED_STATE"], name);
        end
    end,

    build = BuildSwitchConditionMenu,
});

--- The target menu's [Only if...] opens this same submenu (`ActionMenuItems.lua`).
ActionMenu.CreateUnitConditionSubmenu = CreateUnitConditionSubmenu;
