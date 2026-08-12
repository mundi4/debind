local _, DebindPrivate = ...;
local NUM_SPECS          = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));

local Constants          = DebindPrivate.Constants;
local luatype            = type;
local dump               = DebindPrivate.dump;
local LayerArray         = {};

local KEYS_TO_SAVE       = {
    type = true,
    value = true,
    key = true,
    name = true,
    icon = true,
    unit = true,
    -- `hover` and `reactions` used to live here. They are `checkedUnits["hover"]` now -- the
    -- hovered frame's unit is a unit, and keeping it in its own pair of fields meant one unit
    -- described by two columns that only met in `Misc.BuildUnitStates`. `frameTypes` and
    -- `ignoreHoverUnit` stay: those describe the **frame**, not the unit on it.
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
--- (DebindUI.lua의 SetActionKey).
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

    if (dbver <= 4) then
        -- 유닛 조건을 **축별 마스크**로. 스칼라 네 값(`true`/`false`/`"help"`/`"harm"`)으로는
        -- "우호 또는 기타"도 "우호이면서 살아있음"도 못 쓴다 - 값 하나에 존재와 반응이
        -- 뭉쳐 있어서 축을 하나 더 얹을 자리가 없다.
        --
        -- **뭉친 열거 대신 축마다 필드를 둔다.** 생사·소속이 올 때 열거였다면 같은 숫자의
        -- 뜻이 바뀌어 마이그레이션을 또 해야 하는데, 필드면 하나 늘 뿐이고 **옛 데이터에
        -- 그 필드가 없다는 것 자체가 "이 축은 제약 안 함"이라 이미 맞는 답**이다.
        --
        --   없음        { exists = false }   축을 기억할 자리가 있어야 해서 표가 된다
        --   존재        {}                   제약하는 축이 없음
        --   우호/적대   { reaction = ... }
        --
        -- `false`가 표가 되는 이유는 **끈 값을 기억하기 위해서다.** 라디오를 [없을 때]로
        -- 옮겼다고 골라둔 반응·생사를 지우면 되돌렸을 때 처음부터 다시 골라야 한다. 끄는 것과
        -- 지우는 것은 다르다 - `frameTypes`가 hover를 껐다 켜도 남아 있는 것과 같다.
        -- 무시하는 것은 `Misc.UnitConditionForBinding`이 한다.
        --
        -- 다시 돌아도 안전하다 - 이미 테이블이면 건드리지 않는다.
        for i = 1, #layerTbl do
            local checkedUnits = layerTbl[i].checkedUnits;
            if (checkedUnits) then
                for unit, value in pairs(checkedUnits) do
                    if (value == true) then
                        checkedUnits[unit] = {};
                    elseif (value == false) then
                        checkedUnits[unit] = { exists = false };
                    elseif (value == "help") then
                        checkedUnits[unit] = { reaction = Constants.REACTION_HELP };
                    elseif (value == "harm") then
                        checkedUnits[unit] = { reaction = Constants.REACTION_HARM };
                    end
                end
            end
        end

        -- 그리고 hover 조건을 그 유닛들 옆으로 옮긴다. 접는 규칙은 `Misc.lua`에 있다 -
        -- 바인딩을 만들 때도 같은 규칙으로 들어올려야 해서(마이그레이션이 아직 안 닿은
        -- 프로필), 두 벌로 적으면 갈라지는 종류의 규칙이다.
        --
        -- `frameTypes`/`ignoreHoverUnit`은 안 옮긴다: 그건 유닛이 아니라 **프레임**을 말한다.
        --
        -- 다시 돌아도 안전하다 - `hover`가 없으면 아무것도 안 한다.
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.hover ~= nil) then
                action.checkedUnits = action.checkedUnits or {};
                -- 접기는 바인딩 모양 위에서 돈다. 넣기 전에 한 번 통과시키고, 나온 것을 다시
                -- 저장 모양으로 돌린다 - `false`(없을 때)만 표가 되면 되고, 나머지는 그대로다.
                local folded = DebindPrivate.HoverConditionFromLegacy(
                    action.hover, action.reactions,
                    DebindPrivate.UnitConditionForBinding(action.checkedUnits.hover));
                if (folded == false) then
                    folded = { exists = false };
                end
                action.checkedUnits.hover = folded;
                action.hover = nil;
                action.reactions = nil;
            end
        end
    end
end

--- Raises one whole per-spec table (`{[0]=…, [1]=…}`). Class entries and character entries have
--- the same shape, so both go through here.
local function MigrateSpecTable(specTbl, dbver)
    if (specTbl == nil) then
        return;
    end
    for spec = 0, 5 do
        MigrateLayer(specTbl[spec], dbver);
    end
end

--- Everything on the shared side (layers 1-6).
---
--- This used to build class names with `C_CreatureInfo.GetClassInfo` and look each one up, because
--- `dbver` and `options` sat right next to the class names and `pairs` would have walked them too.
--- `shared.classes` holds nothing but classes, so it can just be iterated.
local function MigrateShared(shared, dbver)
    if (shared == nil) then
        return;
    end
    MigrateLayer(shared.GENERAL, dbver);
    if (shared.classes) then
        for _, classTbl in pairs(shared.classes) do
            MigrateSpecTable(classTbl, dbver);
        end
    end
end

-- Used by `Legacy.lua` to raise imported data to the current version before attaching it.
DebindPrivate.MigrateLayer     = MigrateLayer;
DebindPrivate.MigrateSpecTable = MigrateSpecTable;
DebindPrivate.MigrateShared    = MigrateShared;

--- **When the version goes up, everything is raised in one pass.** Every entry in `characters` is
--- in memory on every login, so a single login by any character brings all twenty alts forward on
--- the spot. Nothing can fall behind, which is why there is no per-entry version - `dbver` is the
--- only one.
---
--- The paths that join late (pre-rename SavedVariables, someone else's export file) **arrive
--- carrying their own version and are raised to the current one before being attached**
--- (`Legacy.lua`). Once attached, everything is on the same version.
local function MigrateDB(db)
    local dbver = db.dbver;
    if (dbver >= Constants.DB_VERSION) then
        return;
    end

    MigrateShared(db.shared, dbver);
    for _, charEntry in pairs(db.characters) do
        MigrateSpecTable(charEntry.layers, dbver);
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
        tbl = DebindPrivate.db.char.layers;
    elseif (layerInfo.key == "GENERAL") then
        tbl = DebindPrivate.db.global.shared.GENERAL;
        if (not tbl) then
            tbl = {};
            DebindPrivate.db.global.shared.GENERAL = tbl;
        end
    else
        assert(layerInfo.key);
        local classes = DebindPrivate.db.global.shared.classes;
        tbl = classes[layerInfo.key];
        if (not tbl) then
            tbl = {};
            classes[layerInfo.key] = tbl;
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

function DebindPrivate.LoadProfile()
    wipe(LayerArray);
    for layerID = 1, #LAYER_INFOS do
        LayerArray[layerID] = LoadLayer(layerID);
    end

    dump("LayerArray", LayerArray);
    DebindPrivate.callbacks:Fire("OnProfileLoaded");
end

--- Does this character entry hold any **content**? The identity fields (`name`, `class`,
--- `lastSeen`, …) do not count - we write those ourselves on every login, so treating them as
--- content would give every single alt an entry.
local function HasCharContent(entry)
    if (entry.CustomTargets and next(entry.CustomTargets) ~= nil) then
        return true;
    end
    local layers = entry.layers;
    if (layers) then
        for spec = 0, 5 do
            local layerTbl = layers[spec];
            if (layerTbl and #layerTbl > 0) then
                return true;
            end
        end
    end
    return false;
end

--- Fills in defaults for `options` / `customStates` and **hands those tables to `DebindPrivate`**.
---
--- It is a separate function because what gets handed over is a **reference**. The pre-rename
--- import (`Legacy.lua`) replaces these tables wholesale during PLAYER_LOGIN, so without running
--- this again afterwards `DebindPrivate.Options` and `.CustomStates` would keep pointing at the
--- empty tables from before the import. For `customStates` it is not only the reference: `value`
--- has to be recomputed from `initialValue`/`savedValue`, so copying the contents across would not
--- be enough - this calculation has to run again.
function DebindPrivate.BindDerivedTables()
    local db = DebindPrivate.db.global;

    db.options = db.options or {};
    db.options.blizzframes = db.options.blizzframes or {};
    DebindPrivate.Options = db.options;

    db.customStates = db.customStates or {};
    DebindPrivate.CustomStates = {};

    for i = 1, Constants.MAX_NUM_CUSTOM_STATES do
        local stateOptions = db.customStates[i];
        if (not stateOptions) then
            stateOptions = {};
            db.customStates[i] = stateOptions;
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

        DebindPrivate.CustomStates[i] = stateOptions;
    end
end

function DebindPrivate.InitDB()
    local db = _G.DebindVars;
    if (not db) then
        db = {};
        _G.DebindVars = db;
    end
    db.dbver = db.dbver or Constants.DB_VERSION;

    db.shared = db.shared or {};
    db.shared.classes = db.shared.classes or {};
    db.characters = db.characters or {};
    -- Which characters have already had the pre-rename SavedVariables pulled across. `Legacy.lua`.
    db.migrated = db.migrated or {};

    MigrateDB(db);

    -- **Lazy creation.** If there is no entry we hand out a **detached** table rather than putting
    -- one in `characters`. Attaching it is `CleanUpDB`'s job, once there is something in it. An alt
    -- that never used a character-specific binding therefore never gets an entry in the account
    -- file - one of the two things bounding how far deleted characters can pile up (the other is
    -- removing empty entries, in the same place).
    local guid = UnitGUID("player");
    local charEntry = db.characters[guid] or {};
    charEntry.layers = charEntry.layers or {};

    DebindPrivate.playerGUID = guid;
    DebindPrivate.db = {
        global = db,
        char = charEntry,
    };

    DebindPrivate.BindDerivedTables();
    DebindPrivate.LoadProfile();
    DebindPrivate.CleanUpDB()
end

function DebindPrivate.GetProfileLayer(layerID)
    return LayerArray[layerID];
end

function DebindPrivate.CleanUpDB()
    for _, layer in pairs(LayerArray) do
        -- 이 레이어에서 이미 쓰인 순서 번호. 아래 그물이 **겹치는 번호**를 찾는 데 쓴다.
        local seenSeq = {};

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

            -- **겹치는 번호도 건진다.** 없는 번호만 건지던 시절에는 같은 번호 둘이 그대로
            -- 남았는데, 그러면 비교자가 양쪽 다 false를 내서(Ordering.lua) 두 액션이 동률이
            -- 되고 `sort`가 임의로 놓는다 - 같은 키에 걸린 두 지정의 발동 순서가 정렬할
            -- 때마다 달라질 수 있다는 뜻이다. 더 나쁜 것은 **사용자가 그것을 못 고친다**는
            -- 점이다: 순서 이동은 두 번호를 맞바꾸는 것이라 같은 값끼리는 바꿔도 그대로다
            -- (DebindUI.lua의 `ApplyOrderSwap`이 누를 때마다 그 그룹을 고쳐주지만, 그건
            -- 눌러본 그룹만이다).
            --
            -- 번호를 들고 있으면 키가 없어도 본다. 키를 떼도 번호를 남기는 것은 뗐다 다시
            -- 걸었을 때 자리를 지키려는 것인데(PlaceLast 주석), 그 번호가 남의 것과 겹쳐
            -- 있으면 지킬 자리가 애초에 없다.
            --
            -- 나중에 만난 쪽이 새 번호를 받아 맨 뒤로 간다. 둘 중 어느 쪽이 앞이었는지는
            -- 동률이라 **원래도 정해진 바가 없었으므로**, 여기서 잃는 것이 없다.
            local seq = action.seq;
            if (seq ~= nil) then
                if (seenSeq[seq]) then
                    seq = layer:GetNextSeq();
                    action.seq = seq;
                end
                seenSeq[seq] = true;
            end
        end
    end

    -- **Attach or detach this character's entry.** `InitDB` does not create one up front (lazy
    -- creation), so this is where anything actually enters `characters`. The decision is remade on
    -- every logout, which is how the entry disappears for someone who just deleted their last
    -- character-specific binding.
    --
    -- **Empty entries are removed without asking**, because there is nothing to lose. That does not
    -- contradict "never delete an entry that has content automatically" - these two together are
    -- what stops the account file from growing without bound.
    local db = DebindPrivate.db.global;
    local guid = DebindPrivate.playerGUID;
    if (db and guid) then
        if (HasCharContent(DebindPrivate.db.char)) then
            db.characters[guid] = DebindPrivate.db.char;
        else
            db.characters[guid] = nil;
        end
    end
end

function DebindPrivate.GetLayerID(spec, isCharacterSpecific)
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
--- 실제 바인딩을 만드는 쪽(Debind.lua의 BuildKeyMap)은 **반드시 생략해서** 부를 것.
--- 거기에 다른 특성을 넣으면 지금 쓰지도 않는 바인딩이 실제로 걸린다.
--- **특성이 없는 것은 정상이고, 그 답은 nil이 아니다.** `GetSpecialization()`은 아직 특성을
--- 못 고른 캐릭터에게 **범위 밖 인덱스**를 준다(4특성 직업이면 5). 아래 `spec <= NUM_SPECS`가
--- 그걸 거르는 자리다 - 특성 레이어 둘이 빠지고 나머지는 그대로 나오는 것이 맞는 세계다.
---
--- `or 0`은 nil 쪽 보험이다. API 문서는 이 함수를 non-nilable로 적어두었지만 `Events.lua`가
--- 로그인 직후 nil을 보고 재시도하고 있으므로(ACTIVE_PLAYER_SPECIALIZATION_CHANGED) 실제로
--- nil이 오는 창이 있다고 보는 편이 맞다. 여기는 **XML을 읽는 길**에서도 불리므로
--- (`DebindOverviewPanelMixin:OnLoad`) 그 창에 걸리면 창을 열기도 전에 터진다.
function DebindPrivate.EnumerateProfileLayers(spec)
    if (spec == nil) then
        spec = C_SpecializationInfo.GetSpecialization() or 0;
    end
    local indexArray = {};

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(indexArray, DebindPrivate.GetLayerID(spec, true));
    end

    tinsert(indexArray, DebindPrivate.GetLayerID(0, true));

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(indexArray, DebindPrivate.GetLayerID(spec, false));
    end

    tinsert(indexArray, DebindPrivate.GetLayerID(0, false));
    tinsert(indexArray, DebindPrivate.GetLayerID(nil, false));

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
            local layer = DebindPrivate.GetProfileLayer(tbl[index]);
            if (layer) then
                return index, layer;
            end
        end
    end

    return Enumerator, indexArray, 0;
end

-- 현재 호출자 없음. BuildKeyMap은 (layerRank, index)가 필요해서 EnumerateProfileLayers를
-- 직접 훑는다. 여기 ordinal은 그 두 값을 평탄화한 것과 같은 순서다.
function DebindPrivate.EnumerateActionsInActiveLayers()
    local spec = C_SpecializationInfo.GetSpecialization();
    local layerIdArray = {};

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(layerIdArray, DebindPrivate.GetLayerID(spec, true));
    end

    tinsert(layerIdArray, DebindPrivate.GetLayerID(0, true));

    if (spec > 0 and spec <= NUM_SPECS) then
        tinsert(layerIdArray, DebindPrivate.GetLayerID(spec, false));
    end

    tinsert(layerIdArray, DebindPrivate.GetLayerID(0, false));
    tinsert(layerIdArray, DebindPrivate.GetLayerID(nil, false));

    local layerIndex = 1;
    local actionIndex = 0;
    local layer = DebindPrivate.GetProfileLayer(layerIdArray[layerIndex]);
    local numActions = layer:GetNumActions();

    local function Enumerator(tbl, index)
        index = index + 1;
        while (actionIndex >= numActions) do
            layerIndex = layerIndex + 1;
            layer = DebindPrivate.GetProfileLayer(tbl[layerIndex]);
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
function DebindPrivate.CollectActionsForKey(key, spec)
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

    for layerRank, layer in DebindPrivate.EnumerateProfileLayers(spec) do
        for index, action in layer:Enumerate() do
            if (action.key == key) then
                rows[#rows + 1] = {
                    action        = action,
                    layerID       = layer.layerID,
                    layerRank     = layerRank,
                    -- 레이어 배열에서의 자리. 순서에는 안 쓰인다(비교자는 seq를 본다).
                    -- 편집 메뉴가 이 값으로 프로필을 만진다 - 같은 레이어로 복사할 때 끼워
                    -- 넣을 자리가 이 번호다(DebindUI.lua의 MoveAction). 그리는 쪽이 손으로
                    -- 세면 같은 뜻의 번호가 두 군데서 따로 만들어진다.
                    index         = index,
                    seq           = action.seq,
                    priority      = action.priority or Constants.DEFAULT_PRIORITY,
                    -- hover는 파생값이라 **바인딩에서** 읽는다(`Misc.DeriveHoverFields`).
                    -- 액션에는 이제 그 필드가 없고, nil로 읽으면 `CompareActionOrder`의
                    -- HOVER 층이 통째로 죽어서 **목록이 실제 발동 순서와 다르게 그려진다.**
                    --
                    -- 불리언으로 접지 않는 이유는 그대로다: false와 nil이 다른 뜻이다
                    -- (Ordering.lua 주석 참고).
                    hover         = DebindPrivate.GetBindingInfoForAction(action).hover,
                    isConditional = DebindPrivate.IsConditionalAction(action),
                    issue         = DebindPrivate.GetBindingIssue(action, nil, simulated and "unreachable" or nil),
                    unreachable   = (not simulated) and DebindPrivate.IsUnreachableAction(action) or nil,
                    -- 이 행을 그리는 쪽도 같은 기준으로 물어야 한다. 툴팁이 이걸 보고
                    -- 도달 불가를 뺀다(DebindUI.lua의 ShowLineTooltip).
                    simulated     = simulated or nil,
                };
            end
        end
    end

    sort(rows, DebindPrivate.CompareActionOrder);
    return rows;
end

--- 액션이 사는 레이어를 찾는다. (layerID, layer)를 돌려주고, 없으면 nil.
---
--- 순서 번호를 주려면 **그 액션이 실제로 사는 레이어**를 알아야 한다. 화면에서 보고 있는
--- 탭으로 대신하면 안 된다 - 지금은 선택이 언제나 현재 탭의 한 줄이지만, 그건 목록을 다시
--- 그릴 때마다 확인해서 유지되는 성질이지 이 함수가 기댈 불변식이 아니다.
function DebindPrivate.FindLayerID(action)
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
