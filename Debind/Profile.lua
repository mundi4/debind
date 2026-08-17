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
    -- **Which batch this action came in on**, and what quarantines it: while it is set the action
    -- is in the profile but reaches no key (`BuildKeyMap`), and removing it is the reader saying
    -- yes.
    --
    -- **Nothing else about the arrival is stored.** There used to be two more fields here -- the
    -- group inside the batch, and its place in that group -- because a string sent without keys had
    -- nothing else to hold a set together. It arrives with a key now, a synthetic one, so the group
    -- is a key group like any other and its order is `seq` (`devdocs/building-export-import.md`).
    imported = true,
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

--- 위 두 블록이 각각 spec 0..4를 덮으므로 저장이 자리를 갖는 특성 번호의 최댓값.
---
--- `NUM_SPECS`와 다르다 - 그쪽은 **이 직업**이 몇 개냐이고 이쪽은 **저장 구조**가 몇 번까지
--- 담느냐다. 임포트가 남의 직업 자리에 그대로 쓰므로(`StoredActionsAt`), 거기서 물어야 하는
--- 것은 내 직업 특성 수가 아니라 이 숫자다.
local MAX_SPEC           = 4;


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

--- The number an action holds for the length of one placement, and no longer.
---
--- What it does is make "which of these just arrived" a property of the number itself. A stored
--- number never exceeds the size of its group as long as renumbering runs, so this one always wins
--- and an arrival stands behind whatever its band already held. A set arriving together adds its
--- own ranking to it.
---
--- **Not a storage convention -- a local inside one operation.** The function that writes it
--- renumbers immediately after, so it reaches neither SavedVariables, nor the screen, nor anything
--- the comparator keeps. That is also why its size is not argued about: the only thing asked of it
--- is that it beat the numbers in one group.
local ARRIVAL_SEQ = 1000000;

--- Renumbers the actions on `key` in this layer 1..n, **in the order they are drawn**.
---
--- **One (layer, key) is one group**, because that is exactly the reach of the number -- the
--- comparator has already split on the five steps above it -- so sharing numbers with another key,
--- or with another layer, decides nothing.
---
--- **This is the invariant.** `seq` does not follow an action across a band, but if the number is
--- always "where this stands in its group right now" then the bands divide the range in order, and
--- a number carried in from another band can only land outside the destination's range. That is
--- what fixes the landing at the **end facing where it came from**, and what leaves an edit that
--- crosses no band moving nothing. The whole argument is in
--- `devdocs/legacy/renumbering-a-key-group.md`.
---
--- The record handed to the comparator is shorter than `MakeRow`'s. `layerRank` and `specRank` are
--- constant inside one layer and so can decide nothing, and the order without them is the full list
--- filtered down to this layer.
---
--- **Array position is the last tiebreak.** `sort` is not stable, so two equal numbers in a
--- hand-edited file come out differently on each pass -- and that answer is what gets stored, so one
--- wobble sticks.
function ProfileLayerProto:RenumberKeyGroup(key)
    if (key == nil) then
        return;
    end

    local records;
    for i = 1, #self.actions do
        local action = self.actions[i];
        if (action.key == key) then
            records = records or {};
            records[#records + 1] = {
                action        = action,
                index         = i,
                priority      = action.priority or Constants.DEFAULT_PRIORITY,
                hover         = DebindPrivate.GetBindingInfoForAction(action).hover,
                isConditional = DebindPrivate.IsConditionalAction(action),
                seq           = action.seq,
            };
        end
    end

    if (records == nil) then
        return;
    end

    sort(records, function(lhs, rhs)
        if (DebindPrivate.CompareActionOrder(lhs, rhs)) then
            return true;
        elseif (DebindPrivate.CompareActionOrder(rhs, lhs)) then
            return false;
        end
        return lhs.index < rhs.index;
    end);

    for i = 1, #records do
        local action = records[i].action;
        if (action.seq ~= i) then
            action.seq = i;
            action._dirty = true;
        end
    end
end

--- An action has **arrived** in this layer: whatever number it came with is dropped and it stands
--- at the back of its key group. Called for one that was just made, copied, or moved in.
---
--- **Placing and renumbering are one function.** There is then nowhere for the arrival number to
--- leak out of, and nobody has to remember a rule that says "and then renumber".
---
--- The number it came with goes first. From another layer it is that group's value and means
--- nothing here; from a copy in the same layer it is the original's, and the two would tie.
---
--- No key, no number. The number means "which of this key's actions goes first", so with no key
--- there is nothing for it to be a place in; it gets one when a key is given
--- (`PlaceActionInKeyGroup`).
function ProfileLayerProto:PlaceInKeyGroup(action)
    action.seq = nil;
    if (action.key ~= nil) then
        action.seq = ARRIVAL_SEQ;
        self:RenumberKeyGroup(action.key);
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
        -- 프로필), 두 군데 적으면 갈라지는 종류의 규칙이다.
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
        -- Per key, the numbers that group has already used. The net below reads it to find
        -- **duplicates**.
        local seenSeq = {};
        -- Per key, the next number to hand out. Opened at that group's highest plus one the first
        -- time it is needed -- almost no group ever trips the net, so counting the whole layer up
        -- front would be wasted on nearly all of them.
        local nextSeq = {};
        local function NextSeqFor(key)
            local seq = nextSeq[key];
            if (seq == nil) then
                seq = 1;
                for _, other in layer:Enumerate() do
                    if (other.key == key and other.seq and other.seq >= seq) then
                        seq = other.seq + 1;
                    end
                end
            end
            nextSeq[key] = seq + 1;
            return seq;
        end

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

            -- The ordering number's net. **It is for data the migration never reached** -- MigrateDB
            -- only walks the shapes it knows about, so a hand-edited SavedVariables or a corner left
            -- by an old client can go past it. In ordinary use nothing trips it: every path that
            -- hands out a number goes through a renumber (`RenumberKeyGroup`), which leaves neither
            -- a missing one nor two the same inside a group.
            --
            -- **It looks inside one (layer, key) and nowhere wider.** Renumbering starts each group
            -- at 1, so numbers repeating across one layer is now the normal state -- the comparator
            -- never puts two keys' actions next to each other.
            local key = action.key;
            if (key == nil) then
                -- **A keyless action has no number** (`ClearActionKey`). One here came from a
                -- profile written before that was true, and it is not a number for anything -- the
                -- key it was a place in is gone. Left alone it would sit in the file for good,
                -- since every path that gives the key back overwrites it anyway.
                action.seq = nil;
            else
                -- With no number the comparator reads the action as 0 (Ordering.lua) and puts it
                -- first -- the slot that fires before anything else on that key. With no way to
                -- know where it belongs, the back is the less startling end.
                if (action.seq == nil) then
                    action.seq = NextSeqFor(key);
                end

                -- **Duplicates are caught too.** When only missing numbers were, two of the same
                -- stayed -- and the comparator answers false both ways round (Ordering.lua), so the
                -- two are tied and `sort` places them arbitrarily. Which of two bindings on one key
                -- fires first could then change from one sort to the next.
                --
                -- The one met later takes a new number and goes to the back. Which of them was
                -- ahead was **never decided in the first place**, being a tie, so nothing is lost.
                local group = seenSeq[key];
                if (group == nil) then
                    group = {};
                    seenSeq[key] = group;
                end
                if (group[action.seq]) then
                    action.seq = NextSeqFor(key);
                end
                group[action.seq] = true;
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
--- (`DebindResultPanelMixin:OnLoad`) 그 창에 걸리면 창을 열기도 전에 터진다.
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

--- 열한 레이어 **전부**를, 스코프 순위와 특성 번호를 달아서.
---
--- `EnumerateProfileLayers`는 "지금 이 특성에서 도는 것"을 답한다. 오버뷰는 오프스펙 액션까지
--- 그리므로 그 물음으로는 모자란다 - 이쪽은 저장에 있는 것을 전부 낸다.
---
--- `(순회 번호, layer, scopeRank, specRank)`를 돌려준다.
---   scopeRank - 캐릭터/특성 1, 캐릭터/공용 2, 직업/특성 3, 직업/공용 4, 일반 5.
---               **특성 번호는 안 본다.** 오프스펙 액션은 자기 스코프에서 활성 액션과 같은
---               밴드에 들어가고, 그 안의 자리는 specRank가 정한다(`Ordering.lua`).
---   specRank  - 활성 특성과 특성 없는 레이어가 0, 나머지는 그 레이어의 특성 번호.
---
--- **비교자에게 건네는 layerRank가 이 scopeRank다.** `EnumerateProfileLayers`의 순회 번호와
--- 값은 다르지만 활성 레이어끼리의 차례는 같으므로, 실제로 발동하는 것들의 순서는 안 바뀐다.
function DebindPrivate.EnumerateAllProfileLayers(spec)
    if (spec == nil) then
        spec = C_SpecializationInfo.GetSpecialization() or 0;
    end

    local function Enumerator(_, index)
        while (index < #LAYER_INFOS) do
            index = index + 1;
            local layer = DebindPrivate.GetProfileLayer(index);
            if (layer) then
                local layerInfo = LAYER_INFOS[index];
                local layerSpec = layerInfo.spec or 0;
                local scopeRank;
                if (layerInfo.isCharacterSpecific) then
                    scopeRank = layerSpec > 0 and 1 or 2;
                elseif (layerInfo.key == "GENERAL") then
                    scopeRank = 5;
                else
                    scopeRank = layerSpec > 0 and 3 or 4;
                end
                return index, layer, scopeRank, layerSpec ~= spec and layerSpec or 0;
            end
        end
    end

    return Enumerator, nil, 0;
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

-- Defined below, between the two collectors that share it. Forward-declared so both can be read
-- top to bottom without the record's shape sitting in front of either of them.
local MakeRow;

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

    for _, layer, scopeRank, specRank in DebindPrivate.EnumerateAllProfileLayers(spec) do
        for index, action in layer:Enumerate() do
            if (action.key == key) then
                rows[#rows + 1] = MakeRow(action, layer, scopeRank, index, simulated, specRank);
            end
        end
    end

    sort(rows, DebindPrivate.CompareActionOrder);
    return rows;
end

--- The rows of every action with no key at all.
---
--- **One set, not several.** It used to take an arrival group as well: a string sent without keys
--- put its sets in here, and each of them had to stay whole because the grouping was the only
--- surviving record of what the sender had built. An arriving set carries a synthetic key now, so
--- it is a key group and is collected as one (`CollectActionsForKey`), and what is left here is the
--- standing pile of actions nobody has bound.
---
--- **A keyless action reaches nothing, so none of this is about firing order.** The comparator is
--- still what sorts them, since it is the only ordering this file has; the caller that draws the
--- pile sorts it by name over the top, because what the reader scans a pile of unbound actions for
--- is which action it is (`BuildKeyboardElements`).
function DebindPrivate.CollectKeylessActionRows(spec)
    local rows = {};
    local simulated = spec ~= nil and spec ~= C_SpecializationInfo.GetSpecialization();

    for _, layer, scopeRank, specRank in DebindPrivate.EnumerateAllProfileLayers(spec) do
        for index, action in layer:Enumerate() do
            if (action.key == nil) then
                rows[#rows + 1] = MakeRow(action, layer, scopeRank, index, simulated, specRank);
            end
        end
    end

    sort(rows, DebindPrivate.CompareActionOrder);
    return rows;
end

--- The record the two collectors above hand out, and the only place its shape is written.
---
--- **An off-spec row is the same case as a simulated one** for everything that reads the live key
--- map. `specRank ~= 0` says this action belongs to a specialization that is not the one in play,
--- so "unreachable" would be answered out of a key map it was never in.
function MakeRow(action, layer, layerRank, index, simulated, specRank)
    simulated = simulated or (specRank ~= nil and specRank ~= 0) or nil;
    return {
                    action        = action,
                    layerID       = layer.layerID,
                    layerRank     = layerRank,
                    -- 0이면 지금 도는 세계의 것이다. 그 밖은 다른 특성의 액션이고, 비교자가
                    -- seq를 보기 전에 이 값으로 갈라서 자기 레이어 안에서만 seq를 견주게 한다.
                    specRank      = specRank,
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
                    -- **Carried on the record rather than read off the action later.** Ordering
                    -- works on these rows and deliberately never reaches back through `.action`
                    -- (`hover` is the worked example just above), and `ComputeOrderSwap` has to
                    -- know which rows are out of the running: a badged action is not in the key
                    -- map, so it is not in the order either, and swapping numbers with it would
                    -- move a row on screen without changing what the key does.
                    imported      = action.imported,
                    issue         = DebindPrivate.GetBindingIssue(action, nil, simulated and "unreachable" or nil),
                    unreachable   = (not simulated) and DebindPrivate.IsUnreachableAction(action) or nil,
                    -- 이 행을 그리는 쪽도 같은 기준으로 물어야 한다. 툴팁이 이걸 보고
                    -- 도달 불가를 뺀다(DebindUI.lua의 ShowLineTooltip).
                    simulated     = simulated or nil,
    };
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

--- One action changed: renumber the key group in the layer that action lives in.
---
--- **It does not check whether the band changed.** Working that out would mean seeing the action
--- before and after, and not having to is the point of the design -- with the band unchanged the
--- renumber moves nothing (`RenumberKeyGroup`).
---
--- **It hands out no number.** Whether this is an arrival cannot be told from here; the call site
--- that gives the key is what knows, and that one goes to `PlaceActionInKeyGroup`.
function DebindPrivate.RenumberKeyGroupForAction(action)
    if (action == nil or action.key == nil) then
        return;
    end

    local _, layer = DebindPrivate.FindLayerID(action);
    if (layer) then
        layer:RenumberKeyGroup(action.key);
    end
end

--- One action has **been given a key**: it goes through `PlaceInKeyGroup` in the layer it lives in.
--- The wrapper is for call sites that do not have the layer in hand (`SetActionKey`).
---
--- **A key coming back is an arrival like any other.** There is no number left to resume from
--- (`ClearActionKey`), and there is nothing to tell "this was here before" from "this is new".
function DebindPrivate.PlaceActionInKeyGroup(action)
    if (action == nil or action.key == nil) then
        return;
    end

    local _, layer = DebindPrivate.FindLayerID(action);
    if (layer) then
        layer:PlaceInKeyGroup(action);
    end
end

--- 저장된 액션 목록 하나. `(scope, class, spec)` 주소가 가리키는 자리이며, 없으면 만든다.
---
--- **`LayerArray`를 안 거친다.** 그쪽은 *지금 캐릭터가 보는 뷰*라 열한 자리밖에 없다 - 드루이드
--- 세션에서 `classes.MAGE`는 그 배열에 아예 없다. 임포트는 남의 좌표에 그대로 써야 하므로
--- (`DebindStorage/Drawer.lua`의 `ImportAddress`) 저장 구조를 직접 짚는다.
---
--- 이미 로드된 레이어를 가리키면 **같은 테이블이 나온다.** `LoadLayer`가 저장 테이블을 그대로
--- `layer.actions`에 물려두기 때문에, 여기에 넣은 것은 그 레이어에 넣은 것과 같다.
local function StoredActionsAt(scope, class, spec)
    local db = DebindPrivate.db and DebindPrivate.db.global;
    if (not db) then
        return nil;
    end

    local specTbl;
    if (scope == "general") then
        local tbl = db.shared.GENERAL;
        if (not tbl) then
            tbl = {};
            db.shared.GENERAL = tbl;
        end
        return tbl;
    elseif (scope == "class") then
        if (luatype(class) ~= "string") then
            return nil;
        end
        specTbl = db.shared.classes[class];
        if (not specTbl) then
            specTbl = {};
            db.shared.classes[class] = specTbl;
        end
    elseif (scope == "character") then
        -- **이 캐릭터의 것은 `db.char`에서 받는다.** `characters[guid]`가 아직 비어 있을 수 있고
        -- (`InitDB`의 지연 생성), 그때 `db.char`는 아직 안 붙은 테이블이다. `characters`를 짚으면
        -- 나중에 `CleanUpDB`가 붙일 그 테이블이 아니라 딴 데다 쓰게 된다.
        specTbl = DebindPrivate.db.char.layers;
    else
        return nil;
    end

    spec = spec or 0;
    if (luatype(spec) ~= "number" or spec < 0 or spec > MAX_SPEC) then
        return nil;
    end

    local tbl = specTbl[spec];
    if (not tbl) then
        tbl = {};
        specTbl[spec] = tbl;
    end
    return tbl;
end

--- 저장된 액션 목록을 전부 훑는다. 로드된 레이어든 아니든.
---
--- **`LayerArray`로는 못 세는 것이 있다.** 그 배열은 지금 캐릭터의 뷰라 다른 직업의 레이어와
--- 다른 캐릭터의 레이어가 통째로 빠진다. 임포트가 그런 자리에 그대로 쓰므로(`StoredActionsAt`),
--- 프로필 전체에서 유일해야 하는 값을 그 배열로 구하면 **안 보이는 번호를 재사용한다.**
---
--- 같은 테이블은 한 번만 준다. 이 캐릭터의 엔트리는 `characters`와 `db.char` 양쪽에서 잡히는데,
--- 붙어 있을 때는 같은 테이블이다.
local function ForEachStoredActionList(fn)
    local db = DebindPrivate.db and DebindPrivate.db.global;
    if (not db) then
        return;
    end

    local seen = {};
    local function Visit(tbl)
        if (luatype(tbl) == "table" and not seen[tbl]) then
            seen[tbl] = true;
            fn(tbl);
        end
    end
    local function VisitSpecTable(specTbl)
        if (luatype(specTbl) == "table") then
            for _, tbl in pairs(specTbl) do
                Visit(tbl);
            end
        end
    end

    if (db.shared) then
        Visit(db.shared.GENERAL);
        if (db.shared.classes) then
            for _, classTbl in pairs(db.shared.classes) do
                VisitSpecTable(classTbl);
            end
        end
    end

    for _, charEntry in pairs(db.characters or {}) do
        VisitSpecTable(charEntry.layers);
    end

    -- 아직 `characters`에 안 붙은 이 캐릭터의 엔트리. `CleanUpDB`가 내용이 생긴 뒤에야 붙이므로,
    -- 캐릭터 레이어에 처음 뭔가를 넣은 직후가 정확히 위 훑기에서 빠지는 구간이다.
    if (DebindPrivate.db) then
        VisitSpecTable(DebindPrivate.db.char and DebindPrivate.db.char.layers);
    end
end

--- Puts imported actions where they belong.
---
--- **The profile is written from here and not from the sharing addon.** That one owns the wire
--- format and decides what each action becomes; where an action goes and what happens to the list
--- after is this file's, the same as every other way an action is placed.
---
--- Each entry is `{ scope, class, spec, action }` - the address the profile stores by, not a layer
--- ID. A layer ID is this character's view and a batch routinely lands outside it, so there is no
--- ID to hand for "another class's spec 2" at all (`DebindStorage/Drawer.lua`).
---
--- **Every action arriving here is expected to carry `imported`**, which keeps it out of the
--- binding build (`BuildKeyMap`). Nothing is asserted about that: this stays a placement function,
--- and a caller that placed something live would be answered by the bindings, not by a guard.
function DebindPrivate.PlaceImportedActions(placements)
    -- Where a stored list is worn as a `ProfileLayerProto`. Those methods look at nothing but
    -- `self.actions`, so one of these is reused for every address -- an unloaded layer has no layer
    -- object to put on, and writing the placement rule out a second time here would let it drift
    -- from `RenumberKeyGroup`.
    local scratch = setmetatable({}, { __index = ProfileLayerProto });

    -- The groups this touches: stored list -> key -> true. **One batch lands across several layers
    -- and several keys, so this is not "that group" but every group reached** -- miss one and it
    -- alone is left holding arrival numbers, which stays quiet until the next edit.
    local touched = {};

    for _, placement in ipairs(placements) do
        local actions = StoredActionsAt(placement.scope, placement.class, placement.spec);
        if (actions) then
            local action = placement.action;
            scratch.actions = actions;
            scratch:Insert(action);

            -- **Arrival number plus the number it came with.** Every one of these is new to its
            -- group, so renumbering alone cannot say which of them goes first. The arrival number
            -- dominates, so they land behind whatever the receiving group already held, and the low
            -- digits are the sender's own ranking (`seq` on the wire) -- which is what makes the
            -- order the sender designed survive the trip.
            --
            -- **The sender's number is only ever added to, never stored.** It is a place inside
            -- their layer and means nothing in this one; the renumber below is what turns the sum
            -- into a place here, and it runs before anything sees these.
            --
            -- No key, no number -- the rule `PlaceInKeyGroup` sets.
            action.seq = action.key ~= nil and (ARRIVAL_SEQ + (action.seq or 0)) or nil;
            if (action.key ~= nil) then
                local keys = touched[actions];
                if (keys == nil) then
                    keys = {};
                    touched[actions] = keys;
                end
                keys[action.key] = true;
            end
        end
    end

    -- After all of them are in, not one at a time: renumbering per placement walks the same group
    -- once per action, and it would take the arrival numbers away mid-batch -- leaving the ones
    -- still to come with nothing to be ranked against.
    for actions, keys in pairs(touched) do
        scratch.actions = actions;
        for key in pairs(keys) do
            scratch:RenumberKeyGroup(key);
        end
    end
end

--- Every action in the profile still wearing an import badge.
---
--- **Every loaded layer, not the live ones.** `EnumerateProfileLayers` answers "what is in play for
--- this spec", and a batch routinely lands outside that: an action is placed by the scope it was
--- sent with, so off-spec layers get their share. Counting the live ones would put a number on
--- screen smaller than what "accept all" has to clear, and leave the rest quarantined in a layer
--- with nothing on screen saying so.
---
--- **But it stops at `LayerArray` on purpose**, which `NextSyntheticKey` below does not. A layer
--- this session cannot see is one the reader cannot judge - another class's spells are all red to
--- them because they cannot learn any of it - so "accept all" must not reach it. It waits until
--- they log that class, which is what quarantine makes safe.
---
--- The order is `pairs`, so there is none worth relying on. Neither caller needs one - the strip
--- counts the list and accepting clears a field on each.
function DebindPrivate.CollectImportedActions()
    local actions = {};
    for _, layer in pairs(LayerArray) do
        for _, action in layer:Enumerate() do
            if (action.imported) then
                actions[#actions + 1] = action;
            end
        end
    end
    return actions;
end

--- Puts one key on a whole set of actions at once, in the order the set already has.
---
--- **This is the only way the ordering inside the set survives.** Giving the actions a key one at a
--- time issues `seq` in the order they happen to be touched, which is the profile array's -- so the
--- ranking the set arrived with (`devdocs/building-export-import.md`) is gone, silently, and the
--- reader has no way to tell.
---
--- Every action goes to the **back** of the key group it lands in, in that order. It is what
--- `PlaceInKeyGroup` does for anything arriving somewhere, and it is what merging onto an occupied
--- key should mean: the set that just moved in stands behind the one that was already there.
--- Numbers stay per (layer, key), which is the only scope they mean anything in
--- (`RenumberKeyGroup`), so a set spread over layers is ordered inside each of them and the
--- comparator's layer step keeps the layers apart.
---
--- **The badge comes off with it.** Deciding the key is the reader saying yes -- there is nothing
--- further to approve about a set they just placed on their own keyboard.
---
--- **No rebuild here.** `Profile.lua` places actions and does not decide when bindings go up
--- (`PlaceImportedActions` above is the same); the caller rebuilds once when it is done, which is
--- the point of doing the set in one call at all.
function DebindPrivate.SetKeyForActions(actions, key)
    if (key == nil or actions == nil or #actions == 0) then
        return false;
    end

    -- `sort` is not stable, so the collected order rides along as the tiebreak. Without it two
    -- actions that have nothing to rank them by (a set that arrived carrying no `seq` at all)
    -- would come out in a different order on each call.
    local ordered = {};
    for i = 1, #actions do
        ordered[i] = { action = actions[i], rank = actions[i].seq or 0, index = i };
    end
    sort(ordered, function(lhs, rhs)
        if (lhs.rank ~= rhs.rank) then
            return lhs.rank < rhs.rank;
        end
        return lhs.index < rhs.index;
    end);

    -- The groups this touches: layer -> key -> true. A set spans layers readily, and each of them
    -- hands out its own numbers; and the key being left is a group of its own.
    local touched = {};
    local function Touch(layer, groupKey)
        local keys = touched[layer];
        if (keys == nil) then
            keys = {};
            touched[layer] = keys;
        end
        keys[groupKey] = true;
    end

    for i, entry in ipairs(ordered) do
        local action = entry.action;
        local _, layer = DebindPrivate.FindLayerID(action);
        if (layer) then
            -- The group being left, when there was one. It closes up behind the departure the same
            -- way it does for a delete -- nothing walks out holding a number, so there is nothing
            -- to collide with and no reason for this to be the one change that skips it.
            if (action.key ~= nil and action.key ~= key) then
                Touch(layer, action.key);
            end
            Touch(layer, key);
        end

        action.key = key;
        action.imported = nil;
        action._dirty = true;
        if (layer) then
            -- **Arrival number plus this set's own ranking.** Renumbering alone cannot say which of
            -- these goes first -- they are all new to the group. The arrival number dominates
            -- whatever the group already holds, so the set lands behind it, and the low digits keep
            -- the order established above. Both are gone by the time this function returns, which
            -- is why it is only written where a renumber is going to reach it.
            action.seq = ARRIVAL_SEQ + i;
        end
    end

    -- After the whole set, not per action: the arrival numbers have to still be on every member
    -- while any of them is being ranked.
    for layer, keys in pairs(touched) do
        for groupKey in pairs(keys) do
            layer:RenumberKeyGroup(groupKey);
        end
    end

    return true;
end

--- Is anything here still waiting to be accepted.
---
--- **Two callers, and they ask it for opposite reasons**: one to decide whether to stand a section of
--- a menu up, the other to decide whether the menu opens at all. Both are asking about the same list
--- of actions, so the walk is here rather than in either of them.
function DebindPrivate.AnyImportedAction(actions)
    for i = 1, #(actions or {}) do
        local action = actions[i];
        if (action and action.imported) then
            return true;
        end
    end
    return false;
end

--- Are these actions all on one key? The key if so, plus a flag - **`nil` twice over means two
--- different things**, and the flag is what tells "they share no key" from "they share having none".
---
--- What it really asks is whether a list is a **set** or a **selection**. A key group is the actions
--- on one key and answers yes by construction; rows somebody ticked answer whatever their keys say.
--- Everything that takes 1..n actions and has to behave differently for the two reads it, so it is
--- here rather than in either caller - two copies of this drift, and the day they do, one window is
--- drawing what another one is not doing.
function DebindPrivate.SharedKeyOf(actions)
    if (actions == nil or #actions == 0) then
        return nil, false;
    end

    local key = actions[1].key;
    for i = 2, #actions do
        if (actions[i].key ~= key) then
            return nil, false;
        end
    end
    return key, true;
end

--- Moves one key group onto `key`, settling whatever already holds it on the way.
---
--- **Two answers to an occupied key, and `unbindOccupants` is which one.** They stay where they are
--- -- both sets on one key with conditions telling them apart, which is this addon's ordinary state
--- rather than a compromise -- or they lose their key and this set takes it.
---
--- A third answer, the two sets **swapping** keys, was dropped (`devdocs/building-export-import.md`):
--- a set arriving with no key of its own has nowhere to send the occupants, so on the path this was
--- built for it is the same operation as unbinding them.
---
--- The occupants are settled first because it reads in the order it happens -- the tenant leaves,
--- then the set moves in. **Nothing depends on it**: neither answer leaves the two sets sharing a
--- key while they are being numbered, and `seq` is only ever compared inside one key. `occupants`
--- having the moving set subtracted out of it already is the caller's, and it is what keeps that
--- true.
---
--- No rebuild, for the reason `SetKeyForActions` gives.
function DebindPrivate.MoveKeyGroupToKey(actions, key, occupants, unbindOccupants)
    if (unbindOccupants and occupants) then
        DebindPrivate.ClearKeyForActions(occupants);
    end
    return DebindPrivate.SetKeyForActions(actions, key);
end

--- Takes the key off one action, and the number with it.
---
--- **A keyless action has no `seq`, and this is where that becomes true.** The number says where the
--- action stands among the ones sharing its key; with no key there is nothing for it to be a place
--- in, so what is left is a number out of some group it is no longer part of.
---
--- It used to stay, so that unbinding and binding the same key again put the action back where the
--- reader had ordered it. **Nothing can tell that apart from an action joining the group for the
--- first time** -- the leftover number is the only evidence and it says "somewhere, once", not
--- "here". Read as a place it lands the action in the middle of whatever group the key next belongs
--- to, which is the exact defect renumbering exists to remove.
---
--- **And the detection is not what is missing.** Storing which key the number came from would
--- answer it, and it would still be wrong: days later the reader does not know this action was ever
--- on that key, so a position they cannot account for is the same unexplained landing whether or not
--- the code could justify it. Coming back is arriving (`PlaceInKeyGroup`).
---
--- The group it leaves is renumbered. Dropping a member cannot break the ordering on its own, but
--- there is no longer anything walking out with a number that would collide with the closed-up ones,
--- so the rule stays what it says it is: after any change, renumber that key group.
function DebindPrivate.ClearActionKey(action)
    if (action == nil or action.key == nil) then
        return false;
    end

    local key = action.key;
    action.key = nil;
    action.seq = nil;
    action._dirty = true;

    local _, layer = DebindPrivate.FindLayerID(action);
    if (layer) then
        layer:RenumberKeyGroup(key);
    end
    return true;
end

--- Takes the key off a key group without breaking the group up.
---
--- **A set of two or more keeps a key, and it is a synthetic one.** An action with `key == nil` is
--- nobody's group -- `CollectKeyGroupForAction` says so, and the left column files it in the unbound
--- pile as a row of its own -- so clearing a set of four leaves four loose actions and the thing the
--- reader was working with is gone. They cannot be put back together afterwards either: nothing
--- records that those four were once one set.
---
--- The synthetic key is exactly the state an arriving set sits in -- one group, no key yet, waiting
--- for the reader to decide -- and unbinding arrives at that same state from the other side.
---
--- **One action gets nothing.** There is no group to keep, and the unbound pile is where it belongs.
---
--- `SetKeyForActions` carries the order across, which is the reason the set is written in one call:
--- one at a time issues `seq` in whatever order the actions are touched. It also clears `imported`,
--- which changes nothing here - a set still carrying that badge is already on a synthetic key, and
--- there is nothing to unbind from one of those.
---
--- No rebuild, for the reason `SetKeyForActions` gives.
function DebindPrivate.UnbindKeyGroup(actions)
    if (actions == nil or #actions == 0) then
        return false;
    end
    if (#actions == 1) then
        return DebindPrivate.ClearActionKey(actions[1]);
    end
    return DebindPrivate.SetKeyForActions(actions, DebindPrivate.NextSyntheticKey());
end

--- Takes the key off a set. The other half of an overwrite: the set that was holding the key
--- steps off it, and the one that asked for it moves in.
---
--- **Nothing is deleted, and that is what makes the choice offerable.** A keyless action is out of
--- the binding build and drawn greyed in the pile at the bottom of the overview, so an overwrite is
--- a state the reader can look at and walk back, not a loss.
---
--- **A badge stays.** Losing a key is not the reader saying anything about where the action came
--- from, and an arriving action that had a key is still an arriving action without one.
function DebindPrivate.ClearKeyForActions(actions)
    if (actions == nil) then
        return false;
    end
    local changed = false;
    for i = 1, #actions do
        if (DebindPrivate.ClearActionKey(actions[i])) then
            changed = true;
        end
    end
    return changed;
end

--- The walk a key-group operation stands on, and its reach.
---
--- **Both sides of the operation have to come from the same place.** The set being moved and
--- whatever already holds the destination key are gathered by one walk with one reach, because a
--- reach that covers one and not the other is what makes a swap happen by halves and an overwrite
--- claim a key it left behind somewhere.
---
--- **The eleven layers this character has, which is more than what is in play.** Off-spec layers
--- are in, and they have to be: those actions are drawn in the overview now
--- (`devdocs/showing-off-spec-actions.md`), so a reader looking at a key sees them, and a set that
--- crosses specs is one set.
---
--- **Another class's layers are out.** A batch lands there readily (`ImportAddress`), so a group
--- really can have members this walk never sees -- and leaving them is the answer, not the gap:
---
---   * a key is a keyboard's, and that is a different keyboard. "This key is this set's now" is a
---     claim about the eleven layers in play here; carrying it into a class the reader has not
---     logged would rewrite bindings they never looked at, over a conflict they were never shown.
---     That is the harm the badge exists to prevent (`CollectImportedActions` stops here for the
---     same reason, and says so).
---   * the members left behind lose nothing. They keep the badge, the group and the order, so the
---     set is still a set the day that class is logged, and it is given a key against the
---     occupancy of *that* keyboard -- which is the only place the question can be answered.
local function CollectActionsWhere(match)
    local actions = {};
    for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
        for _, action in layer:Enumerate() do
            if (match(action)) then
                actions[#actions + 1] = action;
            end
        end
    end
    return actions;
end

--- Everything on one key. The overview's left column draws exactly this set under one heading.
---
--- **A set that arrived without a key is collected by this too**, since a synthetic key is a key
--- (`devdocs/building-export-import.md`). There used to be a second collector for those, asking by
--- the group number they carried instead, and one walk answering both is what stops the two from
--- ever disagreeing about what a set is.
---
--- nil collects nothing. Read literally it would match the profile's whole standing pile of unbound
--- actions, and hand that to something whose job is to put one key on all of them.
function DebindPrivate.CollectKeyGroupActions(key)
    if (key == nil) then
        return {};
    end
    return CollectActionsWhere(function(action) return action.key == key; end);
end

--- The highest synthetic key anywhere in the store. Only the seed below asks.
---
--- **The whole store, not `LayerArray`.** A batch lands in another class's layers as readily as in
--- this one's, and those are not in this session's view at all. Taking the highest from the view
--- would leave a number alive somewhere unseen and below the counter, and the collision surfaces the
--- day the reader logs that class: two waiting sets under one heading, and every key-wide action
--- sweeping both.
local function HighestSyntheticKey()
    local highest = 0;
    ForEachStoredActionList(function(actions)
        for i = 1, #actions do
            local key = actions[i].key;
            if (luatype(key) == "number" and key > highest) then
                highest = key;
            end
        end
    end);
    return highest;
end

--- The next synthetic key to hand out, unique across the whole profile.
---
--- **A synthetic key is what holds a set together while it has no key of its own.** A set arrives on
--- one when the sender left the keys out (`DebindStorage/Import.lua`), and a set the reader unbinds
--- lands on one for the same reason (`UnbindKeyGroup`): with `key == nil` there is no group left,
--- only that many loose actions. A number, because a real key is always a string, so the type alone
--- tells the two apart and there is no name a real key could collide with.
---
--- **Unique here, not in the string it came from.** A payload's own numbering starts at 1 in every
--- string, so two strings waiting at once would put two unrelated sets under one heading.
---
--- **Kept in the store and only ever counted up.** It used to be the highest in use plus one, worked
--- out on every call, and what paid for that walk was the number staying small - it was printed
--- ("Imported Binding #3"), so it had to restart at 1 once every waiting set had been given a real
--- key. Nothing prints it any more (`GetKeyDisplayText` names the set instead), so nothing cares how
--- large it gets, and a counter that never comes down needs no path anywhere to remember to lower
--- it. Should the numbers ever want tidying it is one pass over the store, run deliberately.
---
--- Seeded on first use rather than at login: an existing profile has numbers in it and no counter,
--- and this is the one place that has to know.
function DebindPrivate.NextSyntheticKey()
    local db = DebindPrivate.db.global;
    if (db.nextSyntheticKey == nil) then
        db.nextSyntheticKey = HighestSyntheticKey() + 1;
    end

    local key = db.nextSyntheticKey;
    db.nextSyntheticKey = key + 1;
    return key;
end
