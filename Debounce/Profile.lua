local _, DebouncePrivate = ...;
local NUM_SPECS          = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));

local Constants          = DebouncePrivate.Constants;
local luatype            = type;
local dump               = DebouncePrivate.dump;
local LayerArray         = {};

local KEYS_TO_SAVE       = {
    type = true,
    value = true,
    key = true,
    name = true,
    icon = true,
    unit = true,
    hover = true,
    reactions = true,
    frameTypes = true,
    groups = true,
    known = true,
    combat = true,
    stealth = true,
    forms = true,
    bonusbars = true,
    specialbar = true,
    extrabar = true,
    pet = true,
    petbattle = true,
    priority = true,
    keepInBindingContext = true,
    ignoreHoverUnit = true,
    checkedUnits = true,
    ["$state1"] = true,
    ["$state2"] = true,
    ["$state3"] = true,
    ["$state4"] = true,
    ["$state5"] = true,
};

local LAYER_INFOS        = {
    [1] = { key = "GENERAL" },
    [2] = { key = Constants.PLAYER_CLASS, spec = 0 },
    [3] = { key = Constants.PLAYER_CLASS, spec = 1 },
    [4] = { key = Constants.PLAYER_CLASS, spec = 2 },
    [5] = { key = Constants.PLAYER_CLASS, spec = 3 },
    [6] = { key = Constants.PLAYER_CLASS, spec = 4 },
    [7] = { isCharacterSpecific = true, spec = 0 },
    [8] = { isCharacterSpecific = true, spec = 1 },
    [9] = { isCharacterSpecific = true, spec = 2 },
    [10] = { isCharacterSpecific = true, spec = 3 },
    [11] = { isCharacterSpecific = true, spec = 4 },
};


local ProfileLayerProto = {};

function ProfileLayerProto:Insert(action, insertIndex, keepId)
    if (insertIndex == nil) then
        insertIndex = #self.actions + 1;
    else
        if (luatype(insertIndex) == "table") then
            local before = insertIndex;
            insertIndex = nil;
            for i = 1, #self.actions do
                if (self.actions[i] == before) then
                    insertIndex = i;
                    break;
                end
            end
        elseif (insertIndex < 1) then
            insertIndex = 1;
        elseif (insertIndex > #self.actions + 1) then
            insertIndex = #self.actions + 1;
        end
    end

    tinsert(self.actions, insertIndex, action);
end

function ProfileLayerProto:Remove(action)
    local removed = false;
    for i = 1, #self.actions do
        if (self.actions[i] == action) then
            tremove(self.actions, i);
            removed = true;
            break;
        end
    end
    return removed;
end

function ProfileLayerProto:GetAction(index)
    return self.actions[index];
end

function ProfileLayerProto:GetNumActions()
    return #self.actions;
end

function ProfileLayerProto:Enumerate(indexBegin, indexEnd)
    return CreateTableEnumerator(self.actions, indexBegin, indexEnd);
end

local function MigrateLayer(layerTbl, dbver)
    if (layerTbl == nil) then
        return;
    end

    if (dbver == 1) then
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.checkUnitExists and (Constants.BASIC_UNITS[action.unit] or Constants.SPECIAL_UNITS[action.unit])) then
                if (action.checkedUnits == nil or action.checkedUnits["@"] == nil) then
                    action.checkedUnits = action.checkedUnits or {};
                    action.checkedUnits["@"] = true;
                    action.checkUnitExists = nil;
                end
            end

            if (action.checkedUnit == true and action.unit ~= nil and action.unit ~= "none" and action.unit ~= "player") then
                if (action.checkedUnits == nil or action.checkedUnits["@"] == nil) then
                    action.checkedUnits = action.checkedUnits or {};
                    action.checkedUnits[action.unit] = action.checkedUnitValue;
                    action.checkedUnit = nil;
                    action.checkedUnitValue = nil;
                end
            end

            if ((Constants.BASIC_UNITS[action.checkedUnit] or Constants.SPECIAL_UNITS[action.checkedUnit]) and action.checkedUnitValue ~= nil) then
                if (action.checkedUnits == nil or action.checkedUnits[action.checkedUnit] == nil) then
                    action.checkedUnits = action.checkedUnits or {};
                    action.checkedUnits[action.checkedUnit] = action.checkedUnitValue;
                    action.checkedUnit = nil;
                    action.checkedUnitValue = nil;
                end
            end

            if (action.checkedUnits) then
                if (action.checkedUnits["pet"] ~= nil) then
                    if (action.checkedUnits["pet"]) then
                        action.pet = true;
                    else
                        action.pet = false;
                    end
                    action.checkedUnits["pet"] = nil;
                end
    
                if (next(action.checkedUnits) == nil) then
                    action.checkedUnits = nil;
                end
            end
        end
        dbver = 2;
    end
end

local function MigrateDB(db, isCharacterSpecific)
    if (db.dbver == 1) then
        if (isCharacterSpecific) then
            for spec = 0, 5 do
                MigrateLayer(db[spec], db.dbver);
            end
        else
            MigrateLayer(db["GENERAL"], db.dbver);
            for classId = 1, 20 do
                local classInfo = C_CreatureInfo.GetClassInfo(classId);
                local class = classInfo and classInfo.classFile;
                local classTbl = class and db[class];
                if (classTbl) then
                    for spec = 0, 5 do
                        MigrateLayer(classTbl[spec], db.dbver);
                    end
                end
            end
        end

        db.dbver = 2;
    end
end

local function LoadLayer(layerID)
    local layerInfo = assert(LAYER_INFOS[layerID]);
    if (layerInfo.spec and layerInfo.spec > NUM_SPECS) then
        return nil;
    end

    local tbl;
    if (layerInfo.isCharacterSpecific) then
        tbl = DebouncePrivate.db.char
    else
        assert(layerInfo.key);
        tbl = DebouncePrivate.db.global[layerInfo.key];
        if (not tbl) then
            tbl = {};
            DebouncePrivate.db.global[layerInfo.key] = tbl;
        end
    end

    if (layerInfo.spec) then
        if (not tbl[layerInfo.spec]) then
            tbl[layerInfo.spec] = {};
        end
        tbl = tbl[layerInfo.spec];
    end

    local layer = setmetatable({ layerID = layerID, spec = layerInfo.spec, isCharacterSpecific = layerInfo.isCharacterSpecific, actions = tbl, }, { __index = ProfileLayerProto });
    return layer;
end

function DebouncePrivate.LoadProfile()
    wipe(LayerArray);
    for layerID = 1, #LAYER_INFOS do
        LayerArray[layerID] = LoadLayer(layerID);
    end

    dump("LayerArray", LayerArray);
    DebouncePrivate.callbacks:Fire("OnProfileLoaded");
end

function DebouncePrivate.InitDB()
    local function initDB(dbKey)
        local dbTbl = _G[dbKey];
        if (not dbTbl) then
            dbTbl = {
                dbver = Constants.DB_VERSION
            };
            _G[dbKey] = dbTbl;
        end
        dbTbl.dbver = dbTbl.dbver or 1;
        return dbTbl;
    end

    DebouncePrivate.db = {
        global = initDB("DebounceVars"),
        char = initDB("DebounceVarsPerChar"),
    };

    MigrateDB(DebouncePrivate.db.global);
    MigrateDB(DebouncePrivate.db.char, true);

    DebouncePrivate.db.global.options = DebouncePrivate.db.global.options or {};
    DebouncePrivate.db.global.options.blizzframes = DebouncePrivate.db.global.options.blizzframes or {};
    DebouncePrivate.Options = DebouncePrivate.db.global.options;

    DebouncePrivate.db.global.customStates = DebouncePrivate.db.global.customStates or {};
    DebouncePrivate.CustomStates = {};

    for i = 1, Constants.MAX_NUM_CUSTOM_STATES do
        local stateOptions = DebouncePrivate.db.global.customStates[i];
        if (not stateOptions) then
            stateOptions = {};
            DebouncePrivate.db.global.customStates[i] = stateOptions;
        end

        stateOptions.mode = stateOptions.mode or Constants.CUSTOM_STATE_MODES.MANUAL;
        if (stateOptions.mode == Constants.CUSTOM_STATE_MODES.MANUAL) then
            if (stateOptions.initialValue ~= nil) then
                stateOptions.value = stateOptions.initialValue;
            else
                stateOptions.value = stateOptions.savedValue and true or false;
            end
        else
            stateOptions.value = stateOptions.value or false;
        end

        DebouncePrivate.CustomStates[i] = stateOptions;
    end

    DebouncePrivate.LoadProfile();
    DebouncePrivate.CleanUpDB()
end

function DebouncePrivate.GetProfileLayer(layerID)
    return LayerArray[layerID];
end

function DebouncePrivate.CleanUpDB()
    for _, layer in pairs(LayerArray) do
        for _, action in layer:Enumerate() do
            for k in pairs(action) do
                if (KEYS_TO_SAVE[k] == nil) then
                    if (strsub(k, 1, 1) ~= "$") then
                        action[k] = nil;
                    end
                end
            end
            if (action.priority == Constants.DEFAULT_PRIORITY) then
                action.priority = nil;
            end
        end
    end
end

function DebouncePrivate.GetLayerID(spec, isCharacterSpecific)
    if (isCharacterSpecific) then
        if (not spec or spec == 0) then
            return 7
        else
            assert(spec > 0 and spec <= NUM_SPECS);
            return 7 + spec;
        end
    else
        if (not spec) then
            return 1;
        elseif (spec == 0) then
            return 2;
        else
            assert(spec > 0 and spec <= NUM_SPECS);
            return 2 + spec;
        end
    end
end

--- 어느 특성의 세계를 훑을지 고를 수 있다. spec을 주면 **그 특성일 때 활성인 레이어**를
--- 돌려준다 - 발동 순서는 순수 계산이라 지금 그 특성이 아니어도 답이 나온다. 생략하면
--- 현재 특성이다.
---
--- 실제 바인딩을 만드는 쪽(Debounce.lua의 BuildKeyMap)은 **반드시 생략해서** 부를 것.
--- 거기에 다른 특성을 넣으면 지금 쓰지도 않는 바인딩이 실제로 걸린다.
function DebouncePrivate.EnumerateProfileLayers(spec)
    if (spec == nil) then
        spec = C_SpecializationInfo.GetSpecialization();
    end
    local indexArray = {};

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(indexArray, DebouncePrivate.GetLayerID(spec, true));
    end

    tinsert(indexArray, DebouncePrivate.GetLayerID(0, true));

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(indexArray, DebouncePrivate.GetLayerID(spec, false));
    end

    tinsert(indexArray, DebouncePrivate.GetLayerID(0, false));
    tinsert(indexArray, DebouncePrivate.GetLayerID(nil, false));

    local function Enumerator(tbl, index)
        index = index + 1;
        if (index <= #tbl) then
            local layerIndex = tbl[index];
            local layer = DebouncePrivate.GetProfileLayer(layerIndex);
            return index, layer;
        end
    end

    return Enumerator, indexArray, 0;
end

-- 현재 호출자 없음. BuildKeyMap은 (layerRank, index)가 필요해서 EnumerateProfileLayers를
-- 직접 훑는다. 여기 ordinal은 그 두 값을 평탄화한 것과 같은 순서다.
function DebouncePrivate.EnumerateActionsInActiveLayers()
    local spec = C_SpecializationInfo.GetSpecialization();
    local layerIdArray = {};

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(layerIdArray, DebouncePrivate.GetLayerID(spec, true));
    end

    tinsert(layerIdArray, DebouncePrivate.GetLayerID(0, true));

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(layerIdArray, DebouncePrivate.GetLayerID(spec, false));
    end

    tinsert(layerIdArray, DebouncePrivate.GetLayerID(0, false));
    tinsert(layerIdArray, DebouncePrivate.GetLayerID(nil, false));

    local layerIndex = 1;
    local actionIndex = 0;
    local layer = DebouncePrivate.GetProfileLayer(layerIdArray[layerIndex]);
    local numActions = layer:GetNumActions();

    local function Enumerator(tbl, index)
        index = index + 1;
        while (actionIndex >= numActions) do
            layerIndex = layerIndex + 1;
            layer = DebouncePrivate.GetProfileLayer(tbl[layerIndex]);
            if (not layer) then
                return nil, nil;
            end
            numActions = layer:GetNumActions();
            actionIndex = 0;
        end
        actionIndex = actionIndex + 1;
        return index, layer:GetAction(actionIndex);
    end

    return Enumerator, layerIdArray, 0;
end

--- 주어진 키에 걸린 액션을 활성 레이어에서 직접 모아 실제 발동 순서로 정렬해 돌려준다.
---
--- GetKeyMap()을 쓰지 않는 이유: 그쪽은 이슈가 있는 액션과 도달불가 액션이 빠져 있는데,
--- 순서 UI에서는 **그것들이야말로** 보여줘야 할 대상이다.
---
--- spec을 주면 **그 특성이었을 때의** 순서를 돌려준다. 다른 특성 탭을 보고 있어도 답을
--- 낼 수 있는 이유는 순서를 정하는 다섯 가지(중요도/호버/조건/레이어/자리)가 전부 저장된
--- 값이라 지금 무엇을 하고 있든 바뀌지 않기 때문이다.
---
--- 돌려주는 레코드는 호출자 소유의 새 테이블이다. action 테이블에는 아무것도 쓰지 말 것이며,
--- GetBindingInfoForAction이 준 테이블도 쓰지 않는다(그쪽 필드는 BuildKeyMap이 소유한다).
function DebouncePrivate.CollectActionsForKey(key, spec)
    local rows = {};
    if (key == nil) then
        return rows;
    end

    -- 다른 특성의 세계를 물어본 것이면 **살아 있는 상태는 붙이지 않는다.** 순서는 순수
    -- 계산이라 참이지만, 도달 불가는 지금 이 특성으로 만들어진 키 맵에서 나온 값이라 그
    -- 세계에서는 참이 아니다. 조용히 틀린 표시를 다느니 없는 편이 낫다.
    --
    -- 빼는 것은 **도달 불가뿐이다.** 한때 `notCategory = "key"`로 갈래째 껐는데, 그 갈래에는
    -- 특성과 무관한 키 유효성 검사도 같이 있어서 (`IsKeyInvalidForAction`) 다른 특성 탭에서
    -- 보면 진짜 잘못된 키에도 ⚠가 안 떴다. 같은 데이터가 보는 특성에 따라 달라 보이면 안 된다.
    local simulated = spec ~= nil and spec ~= C_SpecializationInfo.GetSpecialization();

    for layerRank, layer in DebouncePrivate.EnumerateProfileLayers(spec) do
        for index, action in layer:Enumerate() do
            if (action.key == key) then
                rows[#rows + 1] = {
                    action        = action,
                    layer         = layer,
                    layerID       = layer.layerID,
                    layerRank     = layerRank,
                    index         = index,
                    priority      = action.priority or Constants.DEFAULT_PRIORITY,
                    -- hover는 원본 그대로 넘긴다. false와 nil이 다른 뜻이라 불리언으로 접으면
                    -- 정렬이 어긋난다 (Ordering.lua 주석 참고).
                    hover         = action.hover,
                    isConditional = DebouncePrivate.IsConditionalAction(action),
                    issue         = DebouncePrivate.GetBindingIssue(action, nil, simulated and "unreachable" or nil),
                    unreachable   = (not simulated) and DebouncePrivate.IsUnreachableAction(action) or nil,
                };
            end
        end
    end

    sort(rows, DebouncePrivate.CompareActionOrder);
    return rows;
end

-- TODO(§4): not implemented yet. No callers - do not call this until it is.
function DebouncePrivate.FindLayerID(action)

end
