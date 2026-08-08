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
    seq = true,
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

--- 이 레이어에서 다음에 줄 순서 번호.
---
--- 번호는 레이어 안에서만 뜻이 있다. 비교자가 layerRank로 먼저 가르므로 다른 레이어의
--- 액션과는 절대 겹쳐 볼 일이 없다(Ordering.lua).
---
--- 번호에 구멍이 나는 것은 괜찮다 - 크기 비교만 하지 세는 데 쓰지 않는다.
function ProfileLayerProto:GetNextSeq()
    local maxSeq = 0;
    for i = 1, #self.actions do
        local seq = self.actions[i].seq;
        if (seq and seq > maxSeq) then
            maxSeq = seq;
        end
    end
    return maxSeq + 1;
end

--- 액션을 이 레이어의 **순서 맨 뒤**에 세운다. 새로 만들었거나 다른 레이어에서 온
--- 액션에 부른다.
---
--- 키가 없으면 번호를 주지 않는다. 번호의 뜻이 "이 키를 눌렀을 때 몇 번째로 나가는가"라
--- 키가 없는 동안에는 가리킬 것이 없고, 나중에 키를 걸 때 그 시점의 맨 뒤 번호를 받는다
--- (DebounceUI.lua의 SetActionKey).
function ProfileLayerProto:PlaceLast(action)
    -- 먼저 지운다. 다른 레이어에서 온 액션이 그 레이어의 번호를 들고 있으면
    -- GetNextSeq가 자기 자신을 세어 쓸데없이 큰 번호가 나온다.
    action.seq = nil;
    if (action.key ~= nil) then
        action.seq = self:GetNextSeq();
    end
end

--- 레이어 배열 하나를 dbver에서 Constants.DB_VERSION까지 올린다.
---
--- 단계마다 `dbver <= N`으로 여는 것에 주의. `== N`이면 두 판 밀린 프로필이 첫 단계만
--- 밟고 나온다. 각 단계는 자기가 이미 끝난 데이터 위에서 다시 돌아도 안전해야 한다.
local function MigrateLayer(layerTbl, dbver)
    if (layerTbl == nil) then
        return;
    end

    if (dbver <= 1) then
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
    end

    if (dbver <= 2) then
        -- 발동 순서의 마지막 단계를 **배열 자리에서 저장값으로** 옮긴다.
        --
        -- 예전에는 비교자가 레이어 배열의 자리(index)를 읽었다. 그 자리는 목록이 배열
        -- 순서를 그대로 그리고 드래그로 그 자리를 바꾸던 시절에는 사용자가 보고 만지는
        -- 값이었지만, 목록이 키순 정렬로 바뀌면서 **화면에도 안 나오고 만질 방법도 없는**
        -- 값이 됐다. 뜻이 없는 값이 순서를 정하니 키를 새로 걸었을 때 어떤 액션은 위로
        -- 어떤 액션은 아래로 들어갔다 - 규칙이 아니라 그 액션이 우연히 배열 어디에
        -- 있었느냐였다.
        --
        -- 배열 순서 그대로 번호를 매기므로 **기존 사용자의 발동 순서는 한 칸도 안 바뀐다.**
        -- 번호는 레이어 안에서만 뜻이 있어서(비교자가 layerRank로 먼저 가른다) 레이어마다
        -- 1부터 다시 센다.
        --
        -- 받는 것은 키가 걸린 액션뿐이다. 키 없는 액션의 자리는 애초에 아무것도 안 정했고,
        -- 나중에 키를 걸 때 그 시점의 맨 뒤 번호를 받는다.
        local seq = 0;
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.key ~= nil) then
                seq = seq + 1;
                action.seq = seq;
            else
                action.seq = nil;
            end
        end
    end
end

local function MigrateDB(db, isCharacterSpecific)
    local dbver = db.dbver;
    if (dbver >= Constants.DB_VERSION) then
        return;
    end

    if (isCharacterSpecific) then
        for spec = 0, 5 do
            MigrateLayer(db[spec], dbver);
        end
    else
        MigrateLayer(db["GENERAL"], dbver);
        for classId = 1, 20 do
            local classInfo = C_CreatureInfo.GetClassInfo(classId);
            local class = classInfo and classInfo.classFile;
            local classTbl = class and db[class];
            if (classTbl) then
                for spec = 0, 5 do
                    MigrateLayer(classTbl[spec], dbver);
                end
            end
        end
    end

    db.dbver = Constants.DB_VERSION;
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

            -- 키가 있는데 순서 번호가 없는 액션에 번호를 준다. **마이그레이션이 도달하지
            -- 못한 데이터를 위한 그물이다** - MigrateDB는 자기가 아는 모양의 표만 훑으므로
            -- 손으로 고친 SavedVariables나 옛 클라이언트가 남긴 자리는 지나칠 수 있다.
            -- 번호가 없으면 비교자가 그 액션을 맨 앞으로 보고(Ordering.lua) 순서가 조용히
            -- 뒤집힌다.
            --
            -- 맨 뒤로 보낸다. 어디에 둘지 알 길이 없을 때 덜 놀라는 쪽이다.
            if (action.key ~= nil and action.seq == nil) then
                action.seq = layer:GetNextSeq();
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
--- **특성이 없는 것은 정상이고, 그 답은 nil이 아니다.** `GetSpecialization()`은 아직 특성을
--- 못 고른 캐릭터에게 **범위 밖 인덱스**를 준다(4특성 직업이면 5). 아래 `spec <= NUM_SPECS`가
--- 그걸 거르는 자리다 - 특성 레이어 둘이 빠지고 나머지는 그대로 나오는 것이 맞는 세계다.
---
--- `or 0`은 nil 쪽 보험이다. API 문서는 이 함수를 non-nilable로 적어두었지만 `Events.lua`가
--- 로그인 직후 nil을 보고 재시도하고 있으므로(ACTIVE_PLAYER_SPECIALIZATION_CHANGED) 실제로
--- nil이 오는 창이 있다고 보는 편이 맞다. 여기는 **XML을 읽는 길**에서도 불리므로
--- (`DebounceOverviewPanelMixin:OnLoad`) 그 창에 걸리면 창을 열기도 전에 터진다.
function DebouncePrivate.EnumerateProfileLayers(spec)
    if (spec == nil) then
        spec = C_SpecializationInfo.GetSpecialization() or 0;
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

    --- **없는 레이어는 건너뛴다.** `LoadProfile`이 열한 개를 한꺼번에 만들므로 평소에는
    --- 하나도 안 빠지지만, 그 전에 물어보는 길이 있다 - UI 프레임의 `OnLoad`는 XML을
    --- 읽을 때 도는데 그건 `InitDB`보다 앞이다. 그때 `GetProfileLayer`는 그냥 테이블
    --- 조회라 nil을 주고, 부르는 쪽은 전부 `layer:Enumerate()`부터 한다.
    ---
    --- 세는 자리를 여기 하나로 둔다. 부르는 쪽마다 nil을 걸러내게 하면 새로 부르는 곳이
    --- 생길 때마다 같은 줄을 다시 써야 하고, 빠뜨려도 그 화면을 열기 전까지 조용하다.
    local function Enumerator(tbl, index)
        while (index < #tbl) do
            index = index + 1;
            local layer = DebouncePrivate.GetProfileLayer(tbl[index]);
            if (layer) then
                return index, layer;
            end
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
                    layerID       = layer.layerID,
                    layerRank     = layerRank,
                    -- 레이어 배열에서의 자리. 순서에는 안 쓰인다(비교자는 seq를 본다).
                    -- 편집 메뉴가 이 값으로 프로필을 만진다 - 같은 레이어로 복사할 때 끼워
                    -- 넣을 자리가 이 번호다(DebounceUI.lua의 MoveAction). 그리는 쪽이 손으로
                    -- 세면 같은 뜻의 번호가 두 군데서 따로 만들어진다.
                    index         = index,
                    seq           = action.seq,
                    priority      = action.priority or Constants.DEFAULT_PRIORITY,
                    -- hover는 원본 그대로 넘긴다. false와 nil이 다른 뜻이라 불리언으로 접으면
                    -- 정렬이 어긋난다 (Ordering.lua 주석 참고).
                    hover         = action.hover,
                    isConditional = DebouncePrivate.IsConditionalAction(action),
                    issue         = DebouncePrivate.GetBindingIssue(action, nil, simulated and "unreachable" or nil),
                    unreachable   = (not simulated) and DebouncePrivate.IsUnreachableAction(action) or nil,
                    -- 이 행을 그리는 쪽도 같은 기준으로 물어야 한다. 툴팁이 이걸 보고
                    -- 도달 불가를 뺀다(DebounceUI.lua의 ShowLineTooltip).
                    simulated     = simulated or nil,
                };
            end
        end
    end

    sort(rows, DebouncePrivate.CompareActionOrder);
    return rows;
end

--- 액션이 사는 레이어를 찾는다. (layerID, layer)를 돌려주고, 없으면 nil.
---
--- 순서 번호를 주려면 **그 액션이 실제로 사는 레이어**를 알아야 한다. 화면에서 보고 있는
--- 탭으로 대신하면 안 된다 - 지금은 선택이 언제나 현재 탭의 한 줄이지만, 그건 목록을 다시
--- 그릴 때마다 확인해서 유지되는 성질이지 이 함수가 기댈 불변식이 아니다.
function DebouncePrivate.FindLayerID(action)
    if (action == nil) then
        return nil;
    end

    for layerID, layer in pairs(LayerArray) do
        for _, candidate in layer:Enumerate() do
            if (candidate == action) then
                return layerID, layer;
            end
        end
    end
end
