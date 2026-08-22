local _, DebindPrivate = ...;
local NUM_SPECS          = C_SpecializationInfo.GetNumSpecializationsForClassID(select(3, UnitClass("player")));

local Constants          = DebindPrivate.Constants;
local L                  = DebindPrivate.L;
local ERROR_COLOR        = _G.ERROR_COLOR;
local luatype            = type;
-- One caller: the `dbver` 5 step that opens the old SETSTATE bitpack.
local band               = bit.band;
local strlower           = strlower;
local dump               = DebindPrivate.dump;
local LayerArray         = {};

local KEYS_TO_SAVE       = {
    type = true,
    value = true,
    key = true,
    name = true,
    icon = true,
    unit = true,
    -- **조건은 전부 이 안에 있다.** 어느 이름이 조건인지는 `Constants.IsConditionField`가
    -- 답하고, 그 표의 머리주석이 밖에 남은 것들이 왜 조건이 아닌지를 하나씩 적어둔다.
    -- `hover`/`reactions`도 한때 여기 있었다. 지금은 `conditions.units["hover"]`다.
    conditions = true,
    priority = true,
    seq = true,
    -- **The key this action came in on**, and what quarantines it: while it is set the action is in
    -- the profile but reaches no key (`BuildKeyMap`), and removing it is the reader saying yes.
    -- `true` where it arrived on no key at all, and a string is the sender's key, which is what the
    -- heading calls a set that is still waiting (`GetKeyDisplayText`). It used to be the batch's id,
    -- from when a string with no keys in it needed something to hold a set together.
    --
    -- **Nothing else about the arrival is stored.** There used to be two more fields here -- the
    -- group inside the batch, and its place in that group -- because a string sent without keys had
    -- nothing else to hold a set together. It arrives with a key now, a synthetic one, so the group
    -- is a key group like any other and its order is `seq` (`devdocs/building-export-import.md`).
    imported = true,
    keepInBindingContext = true,
    ignoreHoverUnit = true,
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


--- 액션 최상단에서 조건 이름을 읽으면 **그 자리에서 터진다.** DEBUG 전용.
---
--- 조건이 `action.conditions`로 내려간 뒤, 옛 자리를 읽는 코드는 에러가 아니라 `nil`을
--- 받는다. `nil`은 "조건 없음"과 생김새가 같아서 **바인딩이 넓어지고**, 넓어진 바인딩은
--- 남의 키를 가져간다. 화면에도 로그에도 아무것도 안 나온다.
---
--- **이름으로 훑어서는 다 못 찾는다.** `action.combat`은 grep에 걸리지만 `action[field]`나
--- `action[key]`처럼 변수로 도는 자리는 안 걸리고, 조건이 열여덟 개라 그렇게 도는 코드가
--- 오히려 흔하다. 실제로 그렇게 놓친 자리가 셋 나왔다(메뉴 묶음 강조, 툴팁의 불리언 조건,
--- 그리고 인게임 키트). 읽는 순간 터뜨리는 쪽이 전수 검사가 된다.
---
--- **`__index`는 없는 키에만 걸린다**, 즉 잡고 싶은 경우에만 걸린다. 조건이 제자리에
--- 있으면 `conditions` 안에서 읽히므로 이 함수는 안 불린다.
---
--- 저장에는 안 따라간다. 메타테이블은 SavedVariables로 직렬화되지 않는다.
local ArmAction;
if (Constants.DEBUG) then
    local trap = {
        __index = function(_, k)
            if (Constants.IsConditionField(k)) then
                error("action." .. tostring(k) .. "를 최상단에서 읽었다." ..
                    " 조건은 action.conditions 안이다" ..
                    " (devdocs/action-and-binding-shapes.md)", 2);
            end
            return nil;
        end,
    };
    ArmAction = function(action)
        if (luatype(action) == "table" and getmetatable(action) == nil) then
            setmetatable(action, trap);
        end
        return action;
    end
else
    ArmAction = function(action) return action; end
end

local ProfileLayerProto = {};

function ProfileLayerProto:Insert(action, insertIndex, keepId)
    ArmAction(action);
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
--- The record is `MakeOrderRecord`'s, with no scope on it. `layerRank` and `specRank` are constant
--- inside one layer and so can decide nothing, and the order without them is the full list filtered
--- down to this layer.
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
            local record = DebindPrivate.MakeOrderRecord(action, nil, nil);
            record.action = action;
            record.index = i;
            records[#records + 1] = record;
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
        records[i].action.seq = i;
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

--- Raises one layer's array of actions from `dbver` to `Constants.DB_VERSION`.
---
--- **Every step opens with `dbver <= N`, never `== N`.** With `==`, a profile two versions behind
--- walks the first step and leaves. And each step has to be safe to run again on data it has
--- already finished.
---
--- **What comes through here is not only the profile.** A received payload's action array rides
--- the same ladder (`BringPayloadForward` in `Export.lua`). That is what keeps one transformation
--- from being written twice (`devdocs/legacy/unifying-action-migration.md` §3-4), and the price
--- of it is that **the input is no longer trusted**: a pasted string's fields arrive as any type at
--- all, and
--- an error raised in here takes down a commit with half the batch already in the profile.
---
--- So **the steps a payload can reach** ask about types, and the rest stand as they were written
--- when only the profile came through. A payload's `dbver` cannot go below 5
--- (`OLDEST_PAYLOAD_DBVER` in `Export.lua`), which is what keeps it out of them.
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

    if (dbver <= 5) then
        -- **아직 안 나간 단계다. 다음 저장 형식 변경도 7을 새로 열지 말고 여기 얹는다.**
        -- 나간 적 없는 번호를 둘로 쪼개면 세상에 없는 중간 상태를 위한 단계가 생기고, 그
        -- 단계는 아무 데이터도 안 만나면서 영원히 남는다. 6이 한 번 나가고 나면 그때부터
        -- 7이다.
        --
        -- 조건을 액션 최상단에서 `conditions` 안으로 내리고, 옮기는 김에 이름도 간다.
        --
        -- **왜 옮기나.** 저장 필드 서른 개 중 열여덟이 조건이었고, 그 사이에 `unit`이 섞여
        -- 앉아 있었다. `unit`은 겨누는 대상이고 `checkedUnits`는 언제 발동하느냐라, 이름만
        -- 보면 한 식구인데 성격이 정반대다. 높이가 갈리면 구조가 그것을 말한다.
        --
        -- **그래서 `checkedUnits`는 `units`가 된다.** `conditions.` 접두어가 이미 "이건
        -- 조건이다"를 말하므로 `checked`가 같은 말을 한 번 더 한다. 이름은 옮기는 길에
        -- 얹혀서 온다 - 따로 단계를 세우면 아무 데이터도 안 만나는 단계가 하나 는다.
        --
        -- **무엇이 조건인지는 `Constants.IsConditionField` 하나가 답한다.** 여기 목록을 또
        -- 적으면 그 표와 갈라지는 날이 온다. `$state1`~`5`도 그 함수가 같이 받는다.
        --
        -- 다시 돌아도 안전하다. 최상단에 조건 이름이 안 남아 있으면 아무것도 안 한다.
        --
        -- **이름을 먼저 다 모으고, 그다음에 옮긴다.** 한 바퀴로 쓰면 첫 조건을 만났을 때
        -- `action.conditions`라는 **없던 키**가 순회 중에 생기는데, Lua 5.1은 그 경우의
        -- `next` 동작을 정의하지 않는다(있는 필드를 지우는 것은 되고, 없던 필드에 대입하는
        -- 것은 안 된다). 그러면 뒤의 조건이 건너뛰어지고, 최상단에 남은 그것을 바로 뒤의
        -- `CleanUpDB`가 지운다. **사용자가 건 조건이 로그인 한 번에 사라지고 `dbver`는
        -- 이미 찍혀 있어서 다시 돌 기회도 없다.**
        local names = {};
        for i = 1, #layerTbl do
            local action = layerTbl[i];

            local count = 0;
            for k in pairs(action) do
                if (Constants.IsConditionField(k) or k == "checkedUnits") then
                    count = count + 1;
                    names[count] = k;
                end
            end

            if (count > 0) then
                local conditions = luatype(action.conditions) == "table"
                    and action.conditions or {};
                for j = 1, count do
                    local k = names[j];
                    conditions[k == "checkedUnits" and "units" or k] = action[k];
                    action[k] = nil;
                    names[j] = nil;
                end
                action.conditions = conditions;
            end
        end

        -- SETSTATE's `mode | index` bitpack, opened out into three types and a name.
        --
        -- **The step holds the old name and the old numbers itself.** Neither the type `"setstate"`
        -- nor the `SETCUSTOM_MODE_*` flags is a language this build speaks any more, and left in
        -- `Constants.lua` a dead name sits next to the live ones forever. A step is frozen once it
        -- is written, so there is nothing here for it to drift from (`0-DECISION-LOG.md`,
        -- 2026-08-21; `MigrateSwitches` below holds its own old numbers for the same reason).
        --
        -- **A mode this does not recognise is left alone.** A bitpack that is none of the three
        -- does not say what the action was meant to do, and picking a type for it would turn an
        -- "on" into an "off". Left under the old type it reaches nothing and does nothing, which is
        -- where an unknown type ends up anyway.
        --
        -- Safe to run again: an action already split has a type that is not `"setstate"`.
        -- **The payload side stands on that.** The v1 adapter opens its subtable straight into the
        -- new types, and this block walks past what it produced (`Export.lua`).
        local SETSTATE_BY_FLAG = {
            [0x100] = Constants.SETSTATE_ON,
            [0x200] = Constants.SETSTATE_OFF,
            [0x400] = Constants.SETSTATE_TOGGLE,
        };
        for i = 1, #layerTbl do
            local action = layerTbl[i];
            if (action.type == "setstate" and luatype(action.value) == "number") then
                local newType = SETSTATE_BY_FLAG[band(action.value, 0x100 + 0x200 + 0x400)];
                local name = Constants.SWITCH_NAMES[band(action.value, 0xf)];
                if (newType and name) then
                    action.type = newType;
                    action.value = name;
                end
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

--- Every action stored anywhere in this account file, handed to `fn`.
---
--- **Wider than `LayerArray`, and it has to be.** That array is the eleven layers this character
--- on this specialization reads. A switch is account-wide, so anything that counts or rewrites
--- references to one has to reach the druid's layers while the priest is logged in. Otherwise a
--- rename fixes what is on screen and quietly breaks what is not.
---
--- **`charEntry` is this character's entry and it is handed in, because it may not be in
--- `db.characters` yet.** An entry is attached once there is something in it (`CleanUpDB`), so
--- everything a character puts in its own layers this session lives in a table the account walk
--- cannot see. That is not an edge: it is the layer the reader is looking at while they rename.
---
--- Takes the account table rather than reading `DebindPrivate.db`, because the migration walks
--- this on a profile that is not attached yet.
local function ForEachStoredAction(db, fn, charEntry)
    local function walkLayer(layerTbl)
        if (layerTbl == nil) then
            return;
        end
        for i = 1, #layerTbl do
            fn(layerTbl[i]);
        end
    end

    local function walkSpecTable(specTbl)
        if (specTbl == nil) then
            return;
        end
        for spec = 0, 5 do
            walkLayer(specTbl[spec]);
        end
    end

    if (db.shared) then
        walkLayer(db.shared.GENERAL);
        if (db.shared.classes) then
            for _, classTbl in pairs(db.shared.classes) do
                walkSpecTable(classTbl);
            end
        end
    end
    local attached = false;
    if (db.characters) then
        for _, entry in pairs(db.characters) do
            if (entry == charEntry) then
                attached = true;
            end
            walkSpecTable(entry.layers);
        end
    end
    if (charEntry and not attached) then
        walkSpecTable(charEntry.layers);
    end
end
DebindPrivate.ForEachStoredAction = ForEachStoredAction;

--- Every switch name this profile still names, gathered from all five layers of every character
--- and every class.
---
--- **Conditions and `SETSTATE` targets, and nothing else.** Those two are the places a switch is
--- named by picking it out of a menu, so a name cannot get in by being mistyped. A macro body's
--- `[$burst]` is typed by hand and is deliberately left out (`devdocs/redesigning-custom-states.md`
--- §9-3): read as a use, one typo would keep a definition alive and take away the red mark that is
--- how the user finds out about the typo at all.
---
--- **No `charEntry`, unlike the callers further down.** This runs inside the migration, where the
--- entry for the character logging in has just been made and holds nothing but what the ladder
--- itself writes there.
local function CollectReferencedSwitches(db, found)
    ForEachStoredAction(db, function(action)
        local conditions = action.conditions;
        if (conditions) then
            for name in pairs(conditions) do
                if (Constants.IsSwitchName(name)) then
                    found[name] = true;
                end
            end
        end
        if (Constants.SETSTATE_MODES[action.type] and luatype(action.value) == "string") then
            found[action.value] = true;
        end
    end);
end

--- Has anything been set on this definition, or is it the empty one a load used to plant?
---
--- **`value` is not a setting.** `BindDerivedTables` writes it on every load from `resetValue` and
--- the character's stored value, so it is on every definition including the ones nobody ever
--- touched. Everything else on a definition got there because somebody chose it.
---
--- **Pressing a switch leaves nothing here**, and that is the one thing this cannot answer on its
--- own. The remembered value sits on the character now, so a switch somebody has used and never
--- configured looks exactly like one nobody made. `CollectStoredSwitchValues` is what the caller
--- asks instead.
local function SwitchIsUntouched(definition)
    for key, value in pairs(definition) do
        if (key == "mode") then
            if (value ~= Constants.SWITCH_MODES.MANUAL) then
                return false;
            end
        elseif (key ~= "value") then
            return false;
        end
    end
    return true;
end

--- Every switch name some character remembers a value for.
---
--- **Having a value is evidence the switch was used**, and after the `dbver` 6 move it is the only
--- evidence left for one nobody configured (`SwitchIsUntouched`). Reading it back out of the
--- characters rather than remembering what the move just wrote is what keeps that step safe to run
--- twice: the answer is derived from the shape the step produces, not from the one it consumed.
local function CollectStoredSwitchValues(db, charEntry, out)
    for _, entry in pairs(db.characters) do
        for name in pairs(entry.switches or {}) do
            out[name] = true;
        end
    end
    if (charEntry) then
        for name in pairs(charEntry.switches or {}) do
            out[name] = true;
        end
    end
end

--- The remembered value leaves the account table and lands on the characters.
---
--- **`db.characters` is inside the account file and all of it is in memory on every login**, so
--- the design's "each character migrates on its own first login" does not hold here -- the ladder
--- runs once per account. What that one pass can reach is every entry that already exists plus the
--- character logging in, and between them they cover everyone who could notice: an alt with no
--- entry has no character-specific anything, which is the case the entry is lazily withheld for.
---
--- **Copied to all of them rather than to one.** Handing the value only to the character present
--- would silently flip the switch off on every other one at their next login, and which key does
--- what hangs off that. They diverge from here on, which is the point of the move.
---
--- **A value already on a character wins.** Nothing on the ordinary path has one -- `dbver` 5 data
--- has nowhere to keep it -- but `Legacy.lua` runs this at PLAYER_LOGIN on an account that has been
--- writing values since it was installed, and the account share it carries is older than any of
--- them. Whichever value arrives, the one the user set on that character is the newer answer.
local function MoveSavedValues(db, switches, charEntry)
    local function Give(entry, name, value)
        entry.switches = entry.switches or {};
        if (entry.switches[name] == nil) then
            entry.switches[name] = value;
        end
    end

    for index, definition in pairs(switches) do
        if (luatype(definition) == "table" and definition.savedValue ~= nil) then
            local name = Constants.SWITCH_NAMES[index];
            if (name) then
                for _, entry in pairs(db.characters) do
                    Give(entry, name, definition.savedValue);
                end
                if (charEntry) then
                    Give(charEntry, name, definition.savedValue);
                end
            end
            definition.savedValue = nil;
        end
    end
end

--- The switch definitions, which sit at the top of the global table rather than inside a layer.
---
--- **A second ladder, because `MigrateLayer` cannot reach these.** That one walks a layer's array of
--- actions; a definition is not an action and lives nowhere near one. Both ladders are stepped in
--- the same `MigrateDB` pass, so nothing is ever half raised, and `check:dbver` asks each about its
--- own order because two ladders carrying the same step number is not a fault.
---
--- **`Legacy.lua`'s `ImportAccount` is the other caller**, and it is the one that had to be found:
--- the pre-rename share is laid on top of a table `MigrateDB` has already stamped.
---
--- **It is handed the whole account table, not just the definitions**, because the step below has
--- to know which switches the layers still name. On the `ImportAccount` path this character's own
--- pre-rename layers have not arrived yet (`ImportCharacter` runs after), so a definition used
--- only there is judged on whether anything was ever set on it. That is enough for a switch the
--- user actually used: pressing one leaves a remembered value, and both of the other modes write a
--- field of their own.
---
--- **`charEntry` is this character's entry, and it is handed in because it may not be in
--- `db.characters` yet** -- `InitDB` withholds an entry until there is something in it. Without it
--- the remembered value would reach every alt that has an entry and miss the person logging in.
local function MigrateSwitches(db, dbver, charEntry)
    if (dbver <= 5) then
        -- **아직 안 나간 단계다** - `MigrateLayer`의 같은 단계 주석을 볼 것.
        --
        -- 정의의 저장 모양 셋을 한 번에 옮긴다. 표 이름 `customStates` -> `switches`,
        -- `mode`의 숫자 -> 문자열, `initialValue` -> `resetValue`.
        --
        -- **단계가 옛 숫자를 직접 든다.** `Constants.SWITCH_MODES`는 이 판이 더 이상 모르는
        -- 언어라, 거기에 옛 값을 남겨두면 죽은 이름이 산 것 옆에 영원히 앉는다. 단계는 한 번
        -- 쓰면 얼어붙어서 갈릴 것이 없다 (`Export.lua`의 `NestPayloadConditions`가 같은
        -- 이유로 `checkedUnits`라는 글자를 직접 든다).
        --
        -- 다시 돌아도 안전하다. 옮길 이름이 안 남아 있으면 아무것도 안 한다 - `mode`는 이미
        -- 문자열이면 건드리지 않고, `initialValue`는 옮기면서 지운다.
        if (db.customStates ~= nil) then
            -- **옛 이름이 있으면 그것이 정의다.** 개명 전 SavedVariables는 `MigrateDB`가
            -- 지나간 **뒤에** `customStates`를 통째로 얹으므로(`Legacy.lua`의
            -- `ImportAccount`), 그 길에서는 새 이름이 이미 있는 채로 여기 들어온다. 그때
            -- 지켜야 하는 것은 방금 들어온 쪽이다.
            db.switches = db.customStates;
            db.customStates = nil;
        end

        local switches = db.switches;
        if (switches) then
            for _, definition in pairs(switches) do
                if (luatype(definition) == "table") then
                    if (luatype(definition.mode) == "number") then
                        if (definition.mode == 3) then
                            definition.mode = Constants.SWITCH_MODES.EXPR;
                        else
                            definition.mode = Constants.SWITCH_MODES.MANUAL;
                        end
                    end

                    if (definition.initialValue ~= nil) then
                        if (definition.resetValue == nil) then
                            definition.resetValue = definition.initialValue;
                        end
                        definition.initialValue = nil;
                    end
                end
            end

            -- **다섯을 미리 만들어두던 것을 여기서 되돌린다.** 매 로드마다 빈 정의 다섯 개를
            -- 심던 자리가 `BindDerivedTables`였고, 그래서 이 기능을 한 번도 안 쓴 프로필에도
            -- 아무도 만든 적 없는 스위치 다섯이 앉아 있다. 만드는 것은 이제 사용자가 이름을
            -- 적는 것뿐이라(`CreateSwitch`), 그때 심긴 것은 여기서 한 번 걷어낸다.
            --
            -- **한 번이지 매 로드 수리가 아니다.** 참조를 훑어 정의를 되살리거나 지우는 것이
            -- 로그인마다 돈다면, 사용자가 지운 스위치가 참조 때문에 돌아오거나 아직 아무 데도
            -- 안 건 새 스위치가 사라진다 (`devdocs/redesigning-custom-states.md` §9-3).
            --
            -- 지우는 것은 **손댄 적도 없고, 참조도 없고, 어느 캐릭터도 값을 기억하지 않는**
            -- 것뿐이다. 셋 중 하나라도 있으면 남는다: 설정을 해뒀는데 아직 아무 액션에도 안 건
            -- 스위치가 조용히 사라지면 안 되고, 조건이 거는 이름의 정의가 사라지면 그 조건은
            -- 영영 거짓인 채로 남는다.
            --
            -- **값을 옮기는 것이 먼저다.** 옮기고 나면 눌러보기만 한 스위치의 정의에는 모드
            -- 하나만 남아 손 안 댄 것과 모양이 같아진다. 눌러본 증거를 계정이 아니라 캐릭터
            -- 쪽에서 읽는 것이 그것을 받는 자리이고(`CollectStoredSwitchValues`), 옛 판정을
            -- 그대로 뒀으면 실제로 쓰던 스위치가 값을 옮긴 바로 그 단계에 지워졌다.
            MoveSavedValues(db, switches, charEntry);

            local keep = {};
            CollectReferencedSwitches(db, keep);
            CollectStoredSwitchValues(db, charEntry, keep);

            for index, definition in pairs(switches) do
                local name = Constants.SWITCH_NAMES[index];
                if (luatype(definition) == "table" and name and not keep[name]
                        and SwitchIsUntouched(definition)) then
                    switches[index] = nil;
                end
            end

            -- **The table stops being filed by number and starts being filed by name.** Everything
            -- downstream of storage already named a switch by string: a condition key, a macro
            -- body, an on/off/toggle target, `DebindPrivate.Switches`. The number was the one
            -- place left where a switch had a second identity. Renaming is what could not be built
            -- on top of that: the name would have had to be a field beside the number, and then
            -- two things would say which switch this is (§6-B of
            -- `devdocs/redesigning-custom-states.md`).
            --
            -- **Only number keys move.** A table that has already been through here is keyed by
            -- name, and the pre-rename share `Legacy.lua` lays on top arrives numbered and comes
            -- back through this step, so running twice has to be a no-op on what it produced.
            --
            -- A number outside the five is dropped rather than carried. Nothing could ever address
            -- it: `BindDerivedTables` read names off `SWITCH_NAMES` and skipped anything it had no
            -- name for, so such a row has never been a switch anybody could see or set.
            --
            -- Collected before anything moves, because **adding a key to a table `pairs` is walking
            -- is undefined.** Clearing one is allowed and putting one back is not, and the two
            -- would have been in the same loop.
            local numbered = {};
            for index, definition in pairs(switches) do
                if (luatype(index) == "number") then
                    numbered[index] = definition;
                end
            end
            for index, definition in pairs(numbered) do
                switches[index] = nil;
                local name = Constants.SWITCH_NAMES[index];
                if (name and switches[name] == nil) then
                    switches[name] = definition;
                end
            end
        end
    end
end

-- Used by `Legacy.lua` to raise imported data to the current version before attaching it.
DebindPrivate.MigrateLayer     = MigrateLayer;
DebindPrivate.MigrateSpecTable = MigrateSpecTable;
DebindPrivate.MigrateShared    = MigrateShared;
DebindPrivate.MigrateSwitches  = MigrateSwitches;

--- **When the version goes up, everything is raised in one pass.** Every entry in `characters` is
--- in memory on every login, so a single login by any character brings all twenty alts forward on
--- the spot. Nothing can fall behind, which is why there is no per-entry version - `dbver` is the
--- only one.
---
--- The paths that join late (pre-rename SavedVariables, someone else's export file) **arrive
--- carrying their own version and are raised to the current one before being attached**
--- (`Legacy.lua`). Once attached, everything is on the same version.
local function MigrateDB(db, charEntry)
    local dbver = db.dbver;
    if (dbver >= Constants.DB_VERSION) then
        return;
    end

    MigrateShared(db.shared, dbver);
    for _, entry in pairs(db.characters) do
        MigrateSpecTable(entry.layers, dbver);
    end
    MigrateSwitches(db, dbver, charEntry);

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
---
--- **Everything a character can hold has to be listed here**, and the one that is missing is
--- silent: `CleanUpDB` detaches the whole entry on the way out, so a character whose only content
--- this does not recognise loses it at logout rather than at the write, with nothing said either
--- time (`devdocs/redesigning-custom-states.md` ⚑4). `switches` is the remembered switch values.
local function HasCharContent(entry)
    if (entry.CustomTargets and next(entry.CustomTargets) ~= nil) then
        return true;
    end
    if (entry.switches and next(entry.switches) ~= nil) then
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

--- What a switch is before anybody sets anything on it.
---
--- **Read as well as copied**, and that is the point of it being one table. A switch nobody has
--- made yet is still drawn in the menu, with a row ticked -- manual, off, remembers -- and those
--- ticks have to be the ones the user gets if they press the row next to them. Two copies of this
--- would let the drawing and the making drift apart, which reads as a click that changed something
--- nobody touched.
local SWITCH_DEFAULTS = { mode = Constants.SWITCH_MODES.MANUAL, value = false };
DebindPrivate.SWITCH_DEFAULTS = SWITCH_DEFAULTS;

--- The definition behind a switch name, or nil when nothing defines that name.
---
--- **The only door to a definition.** Every caller used to reach into the stored table itself, and
--- half of them had to know that a definition is filed by index while a condition names it by
--- string. Going through here is what lets that stop being true in one place: §4-6 of
--- `devdocs/redesigning-custom-states.md` puts the answer behind a layer cascade, and this function
--- is the whole of what changes.
---
--- **nil is an ordinary answer, not a mistake.** Names are free -- the parser takes any
--- `[a-zA-Z0-9_]+`, a shared string can carry one this install has never seen, and definitions are
--- only made for switches somebody set up. Every caller has to have an answer for a name nothing
--- defines, and everywhere the answer is the same: **it is false, and it stays false.** A macro
--- body's `[$typo]` bakes to `known:0`, a condition compares against a value nothing ever writes,
--- and the action carries `BINDING_ISSUE_UNDEFINED_STATE` so the user is told which name it was.
---
--- What it must not do is error. It did until now, on `nil <= 5` for any name it did not know
--- (⚑7), which was unreachable only because every caller passed a gate first.
function DebindPrivate.ResolveSwitchDefinition(name)
    return DebindPrivate.Switches[name];
end

--- The absolute key a layer's override is filed under, or nil where a layer has none.
---
--- ⚠ **`LAYER_INFOS` 7..11 mean "whoever is logged in".** Overrides hang off the definition and
--- definitions are account-wide, so filing one under the layer's own number would have the next
--- character to log in read this one's setting, and write over it. The key has to say *which*
--- character, the way `characters[guid]` already does
--- (`devdocs/redesigning-custom-states.md` §4-7-3).
---
--- **Layer 1 has no key, and that is not a gap.** `GENERAL` is the root answer; it lives on the
--- definition itself and cannot be missing, which is what the whole cascade stands on (§4-6).
---
--- **The specialization half is still the index and not the specialization's own id.** `DRUID:2`
--- has to be read knowing the class, and the key carries the class, so it is readable. §4-7-3 has
--- the swap to ids written up along with why it needs no version bump, so it stays available.
function DebindPrivate.GetSwitchLayerKey(layerID)
    local layerInfo = LAYER_INFOS[layerID];
    if (not layerInfo or layerInfo.key == "GENERAL") then
        return nil;
    end
    if (layerInfo.isCharacterSpecific) then
        local guid = DebindPrivate.playerGUID;
        if (not guid) then
            return nil;
        end
        return guid .. ":" .. layerInfo.spec;
    end
    return layerInfo.key .. ":" .. layerInfo.spec;
end

--- Every layer this character can file an override at, in the order the window's own tabs stand
--- in. **`GENERAL` is not among them**: that is the root, and the root is the definition.
---
--- **Read in, not resolved in.** Narrowest first is the order an override is *looked up* through
--- (`ActiveOverrideLayers` below), and nothing here is looked up: the reader picks a situation off
--- a list. Every other list of layers in the window starts at shared and puts general above the
--- specializations, since that is how the tabs stand and move, copy and the export window all
--- walk them. This one ran the other way and read as a mistake next to them.
---
--- **Every specialization, not the one being played.** This is what the Switches tab draws its rows
--- and its override menu from, and setting a switch up for a specialization you are not currently
--- in is the ordinary case - the same reason the window's own side tabs reach all of them.
---
--- The table is shared and must not be written to. It cannot change during a session: what is in it
--- is the class's specialization count, which is fixed for the character who is logged in.
local OVERRIDABLE_LAYERS;
function DebindPrivate.GetOverridableLayerIDs()
    if (not OVERRIDABLE_LAYERS) then
        OVERRIDABLE_LAYERS = {};
        local function Add(spec, isCharacterSpecific)
            OVERRIDABLE_LAYERS[#OVERRIDABLE_LAYERS + 1] =
                DebindPrivate.GetLayerID(spec, isCharacterSpecific);
        end
        Add(0, false);
        for spec = 1, NUM_SPECS do
            Add(spec, false);
        end
        Add(0, true);
        for spec = 1, NUM_SPECS do
            Add(spec, true);
        end
    end
    return OVERRIDABLE_LAYERS;
end

--- The layers an override is looked up through, narrowest first. `GENERAL` is not among them: the
--- root definition is that row.
---
--- **The order is `EnumerateProfileLayers`'s**, deliberately the same walk minus its last entry.
--- §4-6 chose a cascade for switches by pointing at the order bindings already resolve in, and two
--- orders that have to agree are better kept as one.
local _overrideLayers = {};
local function ActiveOverrideLayers(spec)
    wipe(_overrideLayers);
    if (spec == nil) then
        spec = C_SpecializationInfo.GetSpecialization() or 0;
    end
    -- The same guard `EnumerateProfileLayers` uses: a character that has not picked a
    -- specialization is handed an out-of-range index rather than nil, and those two layers do not
    -- exist for it.
    local hasSpec = spec > 0 and spec <= NUM_SPECS;
    if (hasSpec) then
        _overrideLayers[#_overrideLayers + 1] = DebindPrivate.GetLayerID(spec, true);
    end
    _overrideLayers[#_overrideLayers + 1] = DebindPrivate.GetLayerID(0, true);
    if (hasSpec) then
        _overrideLayers[#_overrideLayers + 1] = DebindPrivate.GetLayerID(spec, false);
    end
    _overrideLayers[#_overrideLayers + 1] = DebindPrivate.GetLayerID(0, false);
    return _overrideLayers;
end

--- How this switch behaves **here**: on this character, in this specialization. Four values, and
--- the last one says where the answer came from - the winning layer's key, or nil where the root
--- gave it.
---
--- **Not a table.** A merged one would be written through: half of what reaches a definition sets a
--- field on it, and a copy would take those writes and drop them with nothing said. Editing a
--- switch is editing one row, and which row is something the caller has to say out loud
--- (`SetSwitchAnswer`).
---
--- **A row is one answer and not a patch**, so the first one found answers all three fields. §4-6
--- gives a layer four things it can say and `nil` is one of them - "come back the way this
--- character left it" is `resetValue == nil` - so a field-by-field merge could not express it: a
--- missing field would mean both "this layer says nothing" and "reset to nothing".
---
--- **`displayMessage` is not one of the four**, so it is not here. It stays on the definition with
--- the one menu that sets it (`SwitchesUI.lua`); an override row carrying it would be a stored
--- field nothing writes and nothing reads.
function DebindPrivate.ResolveSwitchAnswer(name)
    local definition = DebindPrivate.Switches[name];
    if (not definition) then
        return nil;
    end

    local overrides = definition.overrides;
    if (overrides) then
        local layerIDs = ActiveOverrideLayers();
        for i = 1, #layerIDs do
            local key = DebindPrivate.GetSwitchLayerKey(layerIDs[i]);
            local row = key and overrides[key];
            if (row) then
                return row.mode or SWITCH_DEFAULTS.mode, row.resetValue, row.expr, key;
            end
        end
    end

    return definition.mode or SWITCH_DEFAULTS.mode, definition.resetValue, definition.expr, nil;
end

--- The answer one layer gives, or nil where that layer says nothing. `layerKey` nil is the root,
--- which always answers.
function DebindPrivate.GetSwitchAnswerAt(name, layerKey)
    local definition = DebindPrivate.Switches[name];
    if (not definition) then
        return nil;
    end

    local row = definition;
    if (layerKey ~= nil) then
        row = definition.overrides and definition.overrides[layerKey];
        if (not row) then
            return nil;
        end
    end
    return row.mode or SWITCH_DEFAULTS.mode, row.resetValue, row.expr;
end

--- Writes one of the four answers at one layer. `layerKey` nil writes the root.
---
--- **Both fields, every time**, because the four are one axis: arriving from the expression answer
--- and setting only `resetValue` leaves a row that computes itself *and* claims to come up on.
---
--- **`expr` is left alone**, which is the other half of the same rule. It is not one of the four,
--- it is the words behind one of them, and a reader who tries the other three and comes back has
--- not asked to lose what they typed.
function DebindPrivate.SetSwitchAnswer(name, layerKey, mode, resetValue)
    local definition = DebindPrivate.Switches[name];
    if (not definition) then
        return false;
    end

    local row = definition;
    if (layerKey ~= nil) then
        definition.overrides = definition.overrides or {};
        row = definition.overrides[layerKey];
        if (not row) then
            row = {};
            definition.overrides[layerKey] = row;
        end
    end

    row.mode = mode;
    row.resetValue = resetValue;
    return true;
end

--- The expression behind one row's expression answer, written on its own for the reason above:
--- picking the answer and saying what it computes are two gestures, and the box that asks the
--- second one can be reopened without going back through the first.
function DebindPrivate.SetSwitchExpression(name, layerKey, expr)
    local definition = DebindPrivate.Switches[name];
    if (not definition) then
        return false;
    end

    local row = definition;
    if (layerKey ~= nil) then
        row = definition.overrides and definition.overrides[layerKey];
        if (not row) then
            return false;
        end
    end

    row.expr = expr;
    return true;
end

--- Takes one layer's override away. **The root has none to take**: it is the row §4-6 requires to
--- always be there, and without it the references pointing at this switch have nowhere to land.
function DebindPrivate.ClearSwitchOverride(name, layerKey)
    local definition = DebindPrivate.Switches[name];
    if (layerKey == nil or not definition or not definition.overrides) then
        return false;
    end
    if (not definition.overrides[layerKey]) then
        return false;
    end

    definition.overrides[layerKey] = nil;
    if (next(definition.overrides) == nil) then
        definition.overrides = nil;
    end
    return true;
end

--- How many layers override this switch, **counting the ones this character cannot see**.
---
--- That is the whole reason it is a number and not a list. The definition is account-wide while the
--- Switches tab draws the layers one character reaches, so deleting from a priest takes a druid's
--- overrides with it, and the delete question is the only place that asymmetry is ever on screen
--- (§6-B).
function DebindPrivate.CountSwitchOverrides(name)
    local definition = DebindPrivate.Switches[name];
    local count = 0;
    for _ in pairs(definition and definition.overrides or {}) do
        count = count + 1;
    end
    return count;
end

--- Every switch back to what its answer says it comes up as, wherever that answer has moved since
--- the last time this ran.
---
--- **`resetValue` is not a login-time value** (§4-8). An override saying "always on in this
--- specialization" is a lie the moment changing into that specialization leaves the switch off. The
--- answer in effect moves when the specialization moves, when the character does, and when the
--- reader edits a row - one event as far as this is concerned, *the answer is not the one that was
--- last applied*.
---
--- **Not on every rebuild.** A rebuild runs whenever a binding is edited, so applying every time
--- would put a forced switch back on seconds after the reader pressed it off. What is compared is
--- the answer itself, so nothing moves while it stands still.
---
--- **The expression is not part of the comparison.** Three fields decide a reset - where the answer
--- came from, whether it is computed, and what it resets to - and rewording an expression changes
--- none of them. The expression loop recomputes the value on the next pass anyway.
local _appliedAnswers = {};

function DebindPrivate.ApplySwitchResets()
    local savedValues = DebindPrivate.db.char.switches;

    for name, definition in pairs(DebindPrivate.Switches) do
        local mode, resetValue, _, layerKey = DebindPrivate.ResolveSwitchAnswer(name);
        -- One string rather than three values kept side by side: what is being asked is "the same
        -- answer from the same row", and three compared one at a time is three chances to forget
        -- one.
        local applied = tostring(layerKey) .. "|" .. mode .. "|" .. tostring(resetValue);
        if (_appliedAnswers[name] ~= applied) then
            _appliedAnswers[name] = applied;
            if (mode == Constants.SWITCH_MODES.MANUAL) then
                -- **`resetValue == nil` is an answer, not a missing value** - come back to what
                -- this character was left on. That link is invisible in either field's name.
                if (resetValue ~= nil) then
                    definition.value = resetValue;
                else
                    definition.value = savedValues[name] and true or false;
                end
            else
                definition.value = definition.value or false;
            end
        end
    end

    -- Names whose definition has gone. Left in, a switch made again under the same name would come
    -- up holding an answer nobody gave it.
    for name in pairs(_appliedAnswers) do
        if (not DebindPrivate.Switches[name]) then
            _appliedAnswers[name] = nil;
        end
    end
end

--- Forgets what was last applied, so the next `ApplySwitchResets` applies every switch again.
---
--- One caller: `BindDerivedTables`, which runs at load and again after the pre-rename import swaps
--- the tables out (`Legacy.lua`). Both are a new world, and a memo carried across it would answer
--- for switches that are no longer the same switches.
local function ForgetAppliedAnswers()
    wipe(_appliedAnswers);
end

--- Carries what was last applied over to a new name.
---
--- **The memo is keyed by name, so a rename that leaves it behind is a press.** The new name has
--- nothing recorded, the first rebuild after the rename therefore applies its answer from scratch,
--- and a switch whose answer is "comes up off" goes off in front of a reader who only asked to
--- rename it. `RenameSwitch` is careful not to touch the value itself for exactly this reason; the
--- rebuild that follows it is where the value would actually move.
local function MoveAppliedAnswer(oldName, newName)
    _appliedAnswers[newName] = _appliedAnswers[oldName];
    _appliedAnswers[oldName] = nil;
end

--- Makes a switch under this name. Answers `true`, or `false` and a locale key saying why it
--- refused. It is the same contract `RenameSwitch` has, and for the same reason: both are a reader
--- typing a name into a box, and the sentence they get back has to be about the name they typed.
---
--- **Creating is a user's doing, and this is the only place it happens.** Nothing is planted at
--- load (`BindDerivedTables`), so a row on disk means somebody made it. The alternative, making
--- one wherever a reference to the name turns up, is what §9-3 of
--- `devdocs/redesigning-custom-states.md` rules out: a switch the user deleted would come back on
--- the next login and the red references to it would go quiet, which is the deletion being undone
--- by the thing that was supposed to report it.
---
--- **There is no count.** `GetOrCreateSwitchDefinition` stood here and refused every name outside
--- the built-in five, which was the whole of what kept a profile to five switches; stage 3c took
--- it out along with the menu that handed those five names out (§6-C). What is left is the name
--- rule, which is not a limit but a shape: a name `ParseMacroText` cannot read is one the reader
--- could never type where the Switches tab tells them to (`IsValidSwitchName`).
--- **The name goes to lower case here, and `RenameSwitch` is the only other door.** A switch name
--- is read inside `[...]` beside the client's own macro options, and those do not care about case
--- -- `[Combat]` fires. Somebody who made `$ZZZ` and later types `[$zzz]` is typing the same name
--- as far as they are concerned, so two switches that differ only in case are two the reader cannot
--- tell apart in the list and cannot aim at reliably in a macro.
---
--- **Only the doors fold, not `ParseMacroText`.** Folding the reader too would mean the stored
--- names had to be folded as well, and a body that still says `[$ZZZ]` against a switch named that
--- way keeps working exactly as it does now. What a body cannot do is quietly find a different
--- switch: an unfolded name that nothing defines is marked (`GetUndefinedSwitch`).
function DebindPrivate.CreateSwitch(name)
    if (not Constants.IsValidSwitchName(name)) then
        return false, "SWITCH_NAME_ERROR_INVALID";
    end
    name = strlower(name);
    if (DebindPrivate.Switches[name]) then
        return false, "SWITCH_NAME_ERROR_TAKEN";
    end

    DebindPrivate.Switches[name] = CopyTable(SWITCH_DEFAULTS);
    DebindPrivate.OnSwitchesChanged();
    return true;
end

--- Every switch that exists, by name, in the order a list draws them.
---
--- Sorted rather than walked with `pairs`, which would order the Switches tab and the picker's
--- special category differently on every client and differently again after a reload.
function DebindPrivate.GetSwitchNames(out)
    out = out or {};
    for name in pairs(DebindPrivate.Switches) do
        out[#out + 1] = name;
    end
    sort(out);
    return out;
end

--- Does this action name that switch, in any of the three places one can be named?
---
--- A condition key, an on/off/toggle target, and a macro body. The body is asked through the
--- parser, which is the same door `GetUndefinedSwitch` uses, so what is counted here is exactly
--- what goes red there.
local function ActionNamesSwitch(action, name)
    local conditions = action.conditions;
    if (conditions and conditions[name] ~= nil) then
        return true;
    end
    if (Constants.SETSTATE_MODES[action.type] and action.value == name) then
        return true;
    end
    if (action.type == Constants.MACROTEXT and luatype(action.value) == "string") then
        local _, args = DebindPrivate.ParseMacroText(action.value);
        for i = 1, (args and #args or 0) do
            local arg = args[i];
            if (arg.type == Constants.MACROTEXT_ARG_SWITCH and arg.name == name) then
                return true;
            end
        end
    end
    return false;
end

--- How many actions name this switch, at three distances: **the whole account, this character, and
--- what is live right now.** Widest first, and each one contains the next.
---
--- **One number could not answer the question the reader is asking.** A definition belongs to the
--- account while the screen in front of them belongs to a character, so "used by 5" leaves them
--- unable to tell a switch three of their characters depend on from one nothing has used since
--- they made it. Deleting is where that matters most and the delete question carries the widest of
--- the three, but the row's tooltip is where a reader goes to find out what a switch is *for*.
---
--- The three walks:
---
---   * the account is every action stored anywhere (`ForEachStoredAction`)
---   * this character is its eleven layers, inactive specializations included -- what it could
---     reach by switching specialization, not what it reaches now
---   * live is the layers this specialization actually reads, which is the set `BuildKeyMap` binds
---     from. A number that drops when you change specialization is the honest one for "does this
---     switch do anything for me at the moment"
---
--- **Actions, not references**: an action naming the same switch in its condition and again in its
--- macro body is one row that goes wrong, and what is being reported is how much of the profile
--- this reaches.
function DebindPrivate.CountSwitchReferences(name)
    local account, character, live = 0, 0, 0;

    ForEachStoredAction(DebindPrivate.db.global, function(action)
        if (ActionNamesSwitch(action, name)) then
            account = account + 1;
        end
    end, DebindPrivate.db.char);

    -- **The layer walks, not a second pass over the same tables.** The eleven layers are the
    -- addon's own answer to "what does this character read", and going through them is what keeps
    -- these two numbers agreeing with the list the reader is looking at.
    for _, layer in DebindPrivate.EnumerateAllProfileLayers() do
        for _, action in layer:Enumerate() do
            if (ActionNamesSwitch(action, name)) then
                character = character + 1;
            end
        end
    end

    for _, layer in DebindPrivate.EnumerateProfileLayers() do
        for _, action in layer:Enumerate() do
            if (ActionNamesSwitch(action, name)) then
                live = live + 1;
            end
        end
    end

    return account, character, live;
end

--- Renames a switch, **and rewrites every reference to it**. Answers `true`, or `false` and a
--- locale key saying why it refused.
---
--- **The rename is the four rewrites.** The definition moving is the easy part; a name is written
--- down in four other kinds of place, and one missed leaves a condition that never matches or a
--- macro clause that quietly stopped being a clause (`devdocs/redesigning-custom-states.md` §3):
---
---   * a condition key, `action.conditions["$burst"]`
---   * an on/off/toggle action's target, `action.value`
---   * a macro body's `[$burst]` and `no$burst`
---   * **another switch's expression**, which is the one that gets forgotten. An expression is a
---     macro body too, and one switch computed from another is a shape this addon supports. There
---     is one per row that answers with an expression now, not one per switch
---
--- And a fifth that is not a reference but is keyed by the name all the same: the value each
--- character remembers. Left behind, a switch that remembers would come up off after a rename with
--- nothing anywhere saying the value had been dropped.
---
--- **Every character and every class, not the layers on screen** (`ForEachStoredAction`).
---
--- The live table is re-keyed rather than rebuilt, because `BindDerivedTables` recomputes `value`
--- from `resetValue`, and rebuilding here would reset a switch the user has on right now as a
--- side effect of renaming it.
function DebindPrivate.RenameSwitch(oldName, newName)
    local definition = DebindPrivate.Switches[oldName];
    if (not definition) then
        return false, "SWITCH_RENAME_ERROR_GONE";
    end
    -- **Shape first, then case, then whether it moved.** Asked in the other order, changing only
    -- the case of a name reads as a move to a free name and the five rewrites below all run for
    -- nothing. `CreateSwitch` says why the case is folded at all.
    if (not Constants.IsValidSwitchName(newName)) then
        return false, "SWITCH_NAME_ERROR_INVALID";
    end
    newName = strlower(newName);
    if (newName == oldName) then
        return true;
    end
    if (DebindPrivate.Switches[newName]) then
        return false, "SWITCH_NAME_ERROR_TAKEN";
    end

    local db = DebindPrivate.db.global;

    ForEachStoredAction(db, function(action)
        local conditions = action.conditions;
        if (conditions and conditions[oldName] ~= nil) then
            conditions[newName] = conditions[oldName];
            conditions[oldName] = nil;
        end
        if (Constants.SETSTATE_MODES[action.type] and action.value == oldName) then
            action.value = newName;
        end
        if (action.type == Constants.MACROTEXT and luatype(action.value) == "string") then
            action.value = DebindPrivate.RenameSwitchInMacroText(action.value, oldName, newName);
        end
    end, DebindPrivate.db.char);

    -- **Every row, not only the root's.** A layer override carries an expression of its own, and
    -- one left behind is the quietest failure this function has: the switch computed from the old
    -- name bakes to `known:0` **on that one tab**, so it works everywhere the reader is likely to
    -- look and is false in the one place they set it up for.
    local function RenameInRow(row)
        if (luatype(row.expr) == "string") then
            row.expr = DebindPrivate.RenameSwitchInMacroText(row.expr, oldName, newName);
        end
    end
    for _, other in pairs(DebindPrivate.Switches) do
        RenameInRow(other);
        for _, row in pairs(other.overrides or {}) do
            RenameInRow(row);
        end
    end

    for _, entry in pairs(db.characters) do
        if (entry.switches and entry.switches[oldName] ~= nil) then
            entry.switches[newName] = entry.switches[oldName];
            entry.switches[oldName] = nil;
        end
    end
    local charSwitches = DebindPrivate.db.char.switches;
    if (charSwitches[oldName] ~= nil) then
        charSwitches[newName] = charSwitches[oldName];
        charSwitches[oldName] = nil;
    end

    DebindPrivate.Switches[newName] = definition;
    DebindPrivate.Switches[oldName] = nil;
    MoveAppliedAnswer(oldName, newName);

    DebindPrivate.OnSwitchesChanged();
    return true;
end

--- Deletes a switch. **References to it are left where they are.**
---
--- That is the decision and not an omission: an action naming a switch nothing defines goes red
--- (`GetUndefinedSwitch`), and the red is how the user finds the places they have to go and fix.
--- Rewriting them here would delete parts of actions the user never asked to lose, and doing it
--- silently would be worse than the red (§9-3 of `devdocs/redesigning-custom-states.md` turns the
--- same argument the other way round: a reference must not resurrect a definition either).
---
--- **The remembered values go**, because they are this switch's and nothing else's. Leaving them
--- would hand its value to the next switch that happens to take the name.
function DebindPrivate.DeleteSwitch(name)
    if (not DebindPrivate.Switches[name]) then
        return false;
    end

    DebindPrivate.Switches[name] = nil;
    for _, entry in pairs(DebindPrivate.db.global.characters) do
        if (entry.switches) then
            entry.switches[name] = nil;
        end
    end
    DebindPrivate.db.char.switches[name] = nil;

    DebindPrivate.OnSwitchesChanged();
    return true;
end

--- Fills in defaults for `options` / `switches` and **hands those tables to `DebindPrivate`**.
---
--- It is a separate function because what gets handed over is a **reference**. The pre-rename
--- import (`Legacy.lua`) replaces these tables wholesale during PLAYER_LOGIN, so without running
--- this again afterwards `DebindPrivate.Options` and `.Switches` would keep pointing at the
--- empty tables from before the import. For `switches` it is not only the reference: `value`
--- has to be recomputed from the answer in effect and `savedValue`, so copying the contents across
--- would not be enough - that calculation has to run again.
---
--- **`DebindPrivate.Switches` is `db.switches`.** Both are keyed by name, so there is nothing left
--- to join: a condition, a macro body and an on/off/toggle target all name a switch by string, and
--- the stored table now answers under the same key (`ResolveSwitchDefinition`). It used to be a
--- second table built here, because storage filed a definition by index and the index was a second
--- identity a switch could not be renamed while it had.
---
--- **The remembered value comes off this character, not off the definition.** The definition is
--- account-wide and a name raises an expectation of scope that a number never did, so "remember"
--- used to mean "remember what the character who logged out last left" (§5 of
--- `devdocs/redesigning-custom-states.md`). Keyed by name because that is what everything asking
--- for a switch says, and because the five numbers stopped being the whole list.
---
--- **Nothing is created.** A row is a switch somebody made; five empty ones were being planted on
--- every load, which put a row under a name the user never touched and would have filled §6-B's
--- list with blanks for people who have never used the feature
--- (`devdocs/redesigning-custom-states.md` §9-3). A definition is made by a reader naming one
--- (`CreateSwitch`), and `MigrateSwitches` cleared out the untouched ones once.
function DebindPrivate.BindDerivedTables()
    local db = DebindPrivate.db.global;

    db.options = db.options or {};
    db.options.blizzframes = db.options.blizzframes or {};
    DebindPrivate.Options = db.options;

    db.switches = db.switches or {};
    DebindPrivate.Switches = db.switches;

    -- **The value is not computed here any more.** Which answer a switch is giving depends on the
    -- character and the specialization now (§4-6), so the same calculation has to run again every
    -- time either of those moves - and a load is only the first of those times.
    ForgetAppliedAnswers();
    DebindPrivate.ApplySwitchResets();
end

--- A person changed a switch, **and what the character remembers of it moves with it**.
---
--- Those two are one write and were two. A value written without the memory beside it survives
--- until the next load and then quietly goes back. The restricted side's report comes through here
--- (`SwitchesChangedCallback`); the Switches tab's toggle is the second caller, and it is what
--- turned a rule into a function. Written out twice, the tab's toggle would have looked like it
--- worked and lost the switch on the next reload.
---
--- **The memory is never cleared** (§4-9). It used to be wiped whenever the switch had a reset
--- value, on the grounds that a forced switch has nothing to remember. With overrides that reading
--- turns into "leaving the specialization that forced it throws away what it was before", and the
--- value the reader gets back is whatever the force happened to be. So `savedValue` follows the
--- last real value and the answer in effect decides only whether to apply its own
--- (`ApplySwitchResets`) - one branch fewer, and no observable difference where nothing overrides.
---
--- **A value the definition already holds is a reset coming back, not news.** Applying a reset
--- writes the field here and hands it to the restricted side, which reports it straight back
--- (`OnSwitchChanged`); taking that report as a memory is exactly the throwing-away above, from the
--- other direction. Everything a person does arrives as a change, so equality is what tells the two
--- apart.
---
--- **What the caller still owns is the rebuild.** Nothing in this file asks for one; the value only
--- reaches a key through `UpdateBindings`, and both callers have their own moment for it.
--- **Bumped only where a value really moved**, which the early return above already decides.
--- The Switches tab watches this instead of an event: a switch flipping stopped being one on
--- 2026-08-22 (`Public.lua`), and a counter is what is left to notice it by. Reading it is one
--- comparison, so the tab can ask every frame and redraw only when the answer moves.
DebindPrivate.switchValueSerial = 0;

function DebindPrivate.SetSwitchValue(name, value)
    local definition = DebindPrivate.Switches[name];
    if (not definition or definition.value == value) then
        return;
    end

    definition.value = value;
    DebindPrivate.db.char.switches[name] = value;
    DebindPrivate.switchValueSerial = DebindPrivate.switchValueSerial + 1;
end

--- The set of switches changed: one was made, renamed or deleted.
---
--- **Only the set.** A switch's value flipping stopped being an event on 2026-08-22 and the
--- Switches tab polls for it now (`SwitchesUI.lua`); this is for the list itself changing, which is
--- rare enough to stay pushed. Two things read that list: the picker's catalog, which
--- offers one on/off/toggle action per switch, and the Switches tab.
---
--- The bus is `Debind.lua`'s and the headless runner does not load that file (`tests/run.lua`), so
--- it is asked for rather than assumed. Everything that calls this is reachable from a spec.
function DebindPrivate.OnSwitchesChanged()
    -- **The catalog is not rebuilt here any more.** It listed three rows per switch, so making or
    -- deleting one moved what the picker offered; 3c collapsed that to one row that names no
    -- switch (`BuildSpecialActions`), and the index now holds nothing this set can change.
    if (DebindPrivate.callbacks) then
        DebindPrivate.callbacks:Fire("OnSwitchesChanged");
    end
end

--- The stored profile was written by a build newer than this one. **Stand down without touching
--- one thing in it.**
---
--- There is nothing to handle. `dbver` having gone up means the format changed, and the only code
--- that knows what changed and how is the newer code; what an older build can do is not interpret
--- but step aside. Leave it alone and the file survives: WoW writes the global back out at logout
--- exactly as it came in, so as long as nobody edits that table it goes out untouched.
---
--- **The empty profile handed out here is a detached table, not `_G.DebindVars`.** That is the
--- whole mechanism. The rest of the addon goes on reading `DebindPrivate.db` and `LayerArray` as
--- always, but what those end at is the table built here rather than the one that gets saved, so
--- a write nobody expected still cannot reach disk.
---
--- `guarding-against-a-downgrade.md`.
local function StandDown()
    DebindPrivate.playerGUID = UnitGUID("player");
    DebindPrivate.db = {
        global = { shared = { classes = {} }, characters = {}, migrated = {} },
        char = { layers = {}, switches = {} },
    };
    DebindPrivate.BindDerivedTables();
    DebindPrivate.LoadProfile();
end

function DebindPrivate.InitDB()
    local db = _G.DebindVars;
    if (not db) then
        db = {};
        _G.DebindVars = db;
    end

    --@debug@
    -- The other answer to the same condition, and it stands in the same place: a development build
    -- swaps a seed in and carries on where a release stands down. It also answers the empty client
    -- and the `/deb seed` command, which is why the call is not inside the branch below.
    --
    -- **What the seed lands on is decided here and nowhere else.** `/deb seed <dbver>` can plant
    -- any version `DevSeed.lua` has a builder for, so the table coming back is read the same way a
    -- profile off disk is: an older one falls through to `MigrateDB` and migrates, a newer one
    -- trips the branch below and this build stands down. Planting one of each is how both of those
    -- paths are reached on purpose.
    -- `devdocs/legacy/setting-up-a-dev-profile.md`.
    --
    -- Asked for rather than called outright, because the headless harness loads a hand written list
    -- of files and `DevSeed.lua` is not on it (`tests/run.lua`). It must not be either, or every
    -- spec starting from an empty profile would be handed the seed instead. In the game the halves
    -- are never apart: the TOC line and this block are removed by the same packager pass.
    if (DebindPrivate.ApplyDevSeed) then
        db = DebindPrivate.ApplyDevSeed(db);
    end
    --@end-debug@

    -- **"already current" and "came from the future" are different answers.** `MigrateDB` ties them
    -- to one `return`, which is right for it, since either way there is no migration to run. That
    -- is not the same as being safe to walk past. Everything below here edits the stored table: the
    -- `CleanUpDB` at the tail strips every action field missing from this build's `KEYS_TO_SAVE`
    -- and detaches a character entry whose content it does not recognise, and `db.dbver` stays high
    -- afterwards so nothing will ever migrate it back.
    DebindPrivate.profileIsNewer = (db.dbver ~= nil and db.dbver > Constants.DB_VERSION);
    if (DebindPrivate.profileIsNewer) then
        StandDown();
        return;
    end

    db.dbver = db.dbver or Constants.DB_VERSION;

    db.shared = db.shared or {};
    db.shared.classes = db.shared.classes or {};
    db.characters = db.characters or {};
    -- Which characters have already had the pre-rename SavedVariables pulled across. `Legacy.lua`.
    db.migrated = db.migrated or {};

    -- **Lazy creation.** If there is no entry we hand out a **detached** table rather than putting
    -- one in `characters`. Attaching it is `CleanUpDB`'s job, once there is something in it. An alt
    -- that never used a character-specific binding therefore never gets an entry in the account
    -- file - one of the two things bounding how far deleted characters can pile up (the other is
    -- removing empty entries, in the same place).
    --
    -- **Made before the migration rather than after**, because a step can have something to write
    -- here: `MigrateSwitches` hands this character the remembered switch values that used to sit on
    -- the account table, and a detached entry is the one place it could not otherwise reach.
    local guid = UnitGUID("player");
    local charEntry = db.characters[guid] or {};
    charEntry.layers = charEntry.layers or {};
    charEntry.switches = charEntry.switches or {};

    MigrateDB(db, charEntry);

    DebindPrivate.playerGUID = guid;
    DebindPrivate.db = {
        global = db,
        char = charEntry,
    };

    DebindPrivate.BindDerivedTables();
    DebindPrivate.LoadProfile();
    DebindPrivate.CleanUpDB()
end

--- Says out loud that the addon stood down. Once at login (`Events.lua`), and again every time
--- somebody tries to open the window (`Public.lua`).
---
--- **Chat, not a dialog.** A line at login can scroll past, but the first thing anyone does when an
--- addon looks broken is type its slash command, and that command still answers with no events
--- registered at all. The way back opens again whenever they ask, so no one line is the last
--- chance. There is nothing here to answer either: no choice, no deadline, and the thing to do is
--- outside the game.
---
--- **One line.** It was three, one per thing the design listed as needing to be said, which
--- mistook a list of what to say for a count of how many times to say it. Three entries in the
--- frame carrying loot and quest text is three prefixes and three timestamps for one piece of
--- news, and the sentence order inside one entry does the same work for free.
function DebindPrivate.ReportNewerProfile()
    DebindPrivate.DisplayMessage(L["NEWER_PROFILE_MESSAGE"], ERROR_COLOR:GetRGBA());
end

--- `/deb reset`, in two steps. Returns whether this call handled the command.
---
--- **It is typed, not pressed, so there is no such thing as a slip.** One mistaken click presses a
--- popup button; this has to be meant twice. The token to type is printed directly above the line
--- it is typed on, so there is nothing to count and nothing to remember, and it does not depend on
--- the login message still being on screen.
---
--- **No token with a repeated letter in it** (`reallllllly` and its kind). The default client
--- cannot copy text out of the chat frame, so the user reads it off the screen and types it again,
--- and miscounting the letters makes nothing happen at all, which reads as one more thing broken.
--- What a door has to count is the mistaken attempt, not the deliberate one.
---
--- **The token is not translated.** Typing Hangul into a Korean client would be strange, and every
--- command this addon has is already English (`/debind`, `/deb`, `/debounce`).
---
--- **This is the one path allowed to change the stored table while stood down.** What it deletes is
--- the newer profile, and it is parked nowhere, so saying it cannot be undone is simply true. Not
--- parking it is what the user chose by typing this.
---
--- Replacing `_G.DebindVars` at runtime is safe *here*, where it is not safe in general: nothing is
--- holding that table. `DebindPrivate.db` and `LayerArray` are looking at the detached table
--- `StandDown` built, and `PLAYER_LOGOUT` was never even registered (`Events.lua`).
function DebindPrivate.HandleNewerProfileReset(chunks)
    if (not DebindPrivate.profileIsNewer or chunks[1] ~= "reset") then
        return false;
    end

    if (chunks[2] == "confirm") then
        -- **`legacyNeeded = false` is not decoration, it is the difference between a reset and a
        -- fresh install.** An empty table is exactly what a first-ever login starts from, so
        -- without this the next login finds `legacyNeeded` unset, reads the pre-rename
        -- `DebounceVars` still on disk and imports the whole thing (`Legacy.lua`). Somebody who has
        -- just been told this cannot be undone would come back to a screen full of bindings and no
        -- way to tell where they came from.
        --
        -- Same value and same meaning as answering "I don't need them" in the window's overlay
        -- (`DeclineLegacyMigration`), and account wide for the same reason: the shared layers are.
        _G.DebindVars = { legacyNeeded = false };
        ReloadUI();
        return true;
    end

    DebindPrivate.DisplayMessage(L["NEWER_PROFILE_RESET_PROMPT"], ERROR_COLOR:GetRGBA());
    return true;
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
                    action[k] = nil;
                end
            end

            -- 디스크에서 올라온 액션은 `Insert`를 안 지나므로 여기서 건다. 마이그레이션
            -- 뒤이기도 해서, 조건이 아직 최상단에 있는 동안에는 안 걸린다.
            ArmAction(action);

            -- **면제가 한 겹 내려왔다.** `$`로 시작하는 키를 남겨두는 규칙은 커스텀 상태
            -- 조건을 위한 것인데(2024-09-08 `d3118cf`, 2.0.4부터), 조건이 `conditions`
            -- 안으로 들어가면서 액션 최상단에는 그런 키가 더 이상 없다. 위에서 면제를
            -- 그대로 두면 `$`로 시작하기만 하면 무엇이든 최상단에 눌러앉는다.
            --
            -- 여기서 묻는 것은 `IsConditionField`이므로 재설계가 임의 이름을 풀어도
            -- (`devdocs/redesigning-custom-states.md`) 이 줄은 안 바뀐다.
            local conditions = action.conditions;
            if (conditions) then
                for k in pairs(conditions) do
                    if (not Constants.IsConditionField(k)) then
                        conditions[k] = nil;
                    end
                end
                -- **빈 표는 안 남긴다.** 있느냐를 게이트로 쓰는 자리가 여럿이라
                -- (`IsConditionalBinding`이 `next` 하나로 답한다), 빈 표는 조건이 하나도
                -- 없는 액션을 조건부로 만든다.
                if (next(conditions) == nil) then
                    action.conditions = nil;
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

--- The record the two collectors above hand out. Its ordering half is `Misc.lua`'s
--- `MakeOrderRecord`, shared with `BuildKeyMap` and `RenumberKeyGroup`; what is written here is
--- the half only a drawn row needs.
---
--- **`offWorld` is answered here because this is the only place that knows both halves.** A row is
--- outside the live world if the caller asked for another specialization's order at all, or if
--- this action belongs to a specialization other than the one that was asked about. Everything
--- that reads the live key map has to treat those two the same, since "unreachable" would be
--- answered out of a key map the action was never in.
---
--- **The two halves are not the same value**, which is why neither can stand in for the other. Ask
--- for specialization 3's order while playing 1, and a layer belonging to 3 comes back with
--- `specRank == 0` -- it matches what was asked about -- while the whole view is still outside the
--- live world. `simulated` is the caller's half, `specRank` is the row's, and only the two
--- together answer the question the tooltip asks.
function MakeRow(action, layer, layerRank, index, simulated, specRank)
    local offWorld = simulated or (specRank ~= nil and specRank ~= 0) or nil;

    -- 순서를 정하는 여섯 필드는 `Misc.lua`의 `MakeOrderRecord`가 채운다. 그 위에 얹는 것이
    -- 아래 넷이고, 그리는 쪽과 편집 메뉴가 그것을 읽는다.
    local row = DebindPrivate.MakeOrderRecord(action, layerRank, specRank);

    row.action = action;
    row.layerID = layer.layerID;
    -- 레이어 배열에서의 자리. 순서에는 안 쓰인다(비교자는 seq를 본다). 편집 메뉴가 이 값으로
    -- 프로필을 만진다 - 같은 레이어로 복사할 때 끼워 넣을 자리가 이 번호다(DebindUI.lua의
    -- MoveAction). 그리는 쪽이 손으로 세면 같은 뜻의 번호가 두 군데서 따로 만들어진다.
    row.index = index;
    -- **Carried on the record rather than read off the action later.** Ordering works on these
    -- rows and deliberately never reaches back through `.action`, and `ComputeOrderSwap` has to
    -- know which rows are out of the running: a badged action is not in the key map, so it is not
    -- in the order either, and swapping numbers with it would move a row on screen without
    -- changing what the key does.
    row.imported = action.imported;
    row.issue = DebindPrivate.GetBindingIssue(action, nil, offWorld and "unreachable" or nil);
    row.unreachable = (not offWorld) and DebindPrivate.IsUnreachableAction(action) or nil;
    -- Carried so that whoever draws this row asks on the same terms the two above were answered
    -- on. The row's tooltip passes it straight through (`ActionTooltip.lua`),
    -- which is what keeps the row and its tooltip from disagreeing.
    row.offWorld = offWorld;

    return row;
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
--- (`DebindStorage/Import.lua`의 `ImportAddress`) 저장 구조를 직접 짚는다.
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
--- ID to hand for "another class's spec 2" at all (`DebindStorage/Import.lua`).
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
--- The key these **arrived** on, when they all arrived on the same one. `nil` where any of them
--- came in on a different key, came in on none, or was never an arrival at all.
---
--- Separate from the key they are on now, which for anything still badged is a synthetic number
--- (`KeyMapper`). Three screens name a waiting set by this and they have to name it the same, so
--- the walk is here rather than repeated at each of them.
function DebindPrivate.ArrivalKeyOf(actions)
    if (actions == nil) then
        return nil;
    end

    local from;
    for i = 1, #actions do
        local imported = actions[i].imported;
        if (type(imported) == "string") then
            if (from ~= nil and from ~= imported) then
                return nil;
            end
            from = imported;
        end
    end
    return from;
end

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
