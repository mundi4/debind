local _, DebindPrivate = ...;
local Constants          = DebindPrivate.Constants;

local DEFAULT_IMPORTANCE   = Constants.DEFAULT_IMPORTANCE;

-- 순서 규칙만 모아둔 파일. **WoW API를 부르지 말 것** - 헤드리스 테스트
-- (tests/ordering_spec.lua)가 이 파일을 그대로 로드한다.
-- 액션을 수집하는 쪽은 레이어를 훑어야 하므로 Profile.lua에 있다
-- (DebindPrivate.CollectActionsForKey).


--- Which of two actions on one key fires first.
---
--- **The record comes from `Misc.lua`'s `MakeOrderRecord` and nowhere else.** Three callers build
--- one (`BuildKeyMap`, `MakeRow`, `RenumberKeyGroup`) and none of them spells the fields out.
---
--- Record fields: priority, hover, isConditional, layerRank, specRank, seq
---   priority      - `Constants.DEFAULT_IMPORTANCE` when nil
---   hover         - **the raw value.** false and nil mean different things (false is a condition
---                   that says "not hovering" out loud, so it counts as one). Do not fold it to a
---                   boolean on the way in
---   isConditional - `DebindPrivate.IsConditionalBinding(binding)`
---   layerRank     - the scope's rank (smaller is narrower): character/spec -> character/shared ->
---                   class/spec -> class/shared -> general. **The specialization number is not read
---                   here** - an off-spec action goes in the same band as an active one
---   specRank      - 0 for the active specialization (and for layers that have none), the
---                   specialization number 1..4 for off-spec
---   seq           - `action.seq`. The stored ordering number, which means something only inside
---                   one layer
---
--- (layerRank, seq) is the old `binding.ordinal` -- one running number handed out while walking the
--- active layers -- spread over two. The comparison is lexicographic, so the result is the same as
--- comparing ordinals was.
---
--- **specRank comes before seq.** `seq` can only be trusted inside one layer, so comparing it
--- before the field is narrowed to one would set two different number spaces against each other.
--- `layerRank` narrows only as far as the scope, and this step is what finishes the job.
---
--- Changing this order leaves the stored data alone and **silently changes the firing order for
--- every existing user**, and the shared layers make an order-preserving migration impossible to
--- write. Do not touch it. specRank slipping in does not break that rule - everything that actually
--- fires is in an active layer, so that step is always a tie for them.
function DebindPrivate.CompareActionOrder(lhs, rhs)
    local lhsImportance = lhs.priority or DEFAULT_IMPORTANCE;
    local rhsImportance = rhs.priority or DEFAULT_IMPORTANCE;
    if (lhsImportance ~= rhsImportance) then
        return lhsImportance < rhsImportance;
    end

    if (lhs.hover ~= nil and rhs.hover == nil) then
        return true;
    elseif (lhs.hover == nil and rhs.hover ~= nil) then
        return false;
    end

    if (lhs.isConditional and not rhs.isConditional) then
        return true;
    elseif (not lhs.isConditional and rhs.isConditional) then
        return false;
    end

    if (lhs.layerRank ~= rhs.layerRank) then
        return lhs.layerRank < rhs.layerRank;
    end

    -- 오프스펙 액션은 자기 스코프의 활성 액션 **바로 뒤**에 선다. 0이 활성이라 언제나 앞이고,
    -- 오프끼리는 특성 번호 차례다.
    local lhsSpec = lhs.specRank or 0;
    local rhsSpec = rhs.specRank or 0;
    if (lhsSpec ~= rhsSpec) then
        return lhsSpec < rhsSpec;
    end

    -- Last is the **stored ordering number**. Once this read the action's slot in the layer array,
    -- and when the list moved to sorting by key that slot became a value nothing showed and nothing
    -- could touch. A meaningless value deciding the order meant that binding a new key put some
    -- actions above what was already there and some below -- the same gesture splitting on where
    -- the action happened to sit in the array. The number now says **where it stands inside its key
    -- group right now**, and it is rewritten 1..n whenever that group changes (Profile.lua's
    -- RenumberKeyGroup).
    --
    -- **Every action being compared here has a key**, so it has a number: no key, no number
    -- (`ClearActionKey`), and this comparator is only ever asked about actions sharing one. An
    -- arrival keeps the key it was sent on, so it is a key group like any other
    -- (`devdocs/building-export-import.md` 12절) -- there used to be a second field read in this
    -- slot for sets that had no key of their own, and it is gone with that case.
    --
    -- Absent reads as 0. If the net ever tears, that beats comparing nil inside a sort.
    return (lhs.seq or 0) < (rhs.seq or 0);
end


--- 저장할 priority 값. 기본값이면 nil이다 - CleanUpDB가 어차피 지운다
--- (Profile.lua:286-287). UI가 저장하기 전에 반드시 이걸 거친다.
function DebindPrivate.ImportanceToStored(priority)
    if (priority == nil or priority == DEFAULT_IMPORTANCE) then
        return nil;
    end
    return priority;
end

--- 두 액션의 순서를 **가른 단계**를 돌려준다. seq까지 내려왔으면(= 앞의 네 단계가 전부
--- 동률이면) nil이다. CompareActionOrder와 판정이 한 글자도 어긋나면 안 된다.
---
--- 순서 UI가 이걸 쓰는 이유: 비교자의 각 단계는 그 자체로 뜻이 있는 속성이고, 각각 자기
--- 뜻이 사는 자리에서 바뀐다(중요도 메뉴 / 조건 편집 / 레이어 이동). 그 넷 중 아무것도
--- 안 갈렸을 때 남는 것이 seq이고, 정렬 버튼이 만지는 것도 그것뿐이다. 나머지에서 갈렸다면
--- 버튼은 손을 떼고 **어느 속성이 정하고 있는지**만 말해야 한다.
function DebindPrivate.GetDecidingOrderAxis(lhs, rhs)
    if ((lhs.priority or DEFAULT_IMPORTANCE) ~= (rhs.priority or DEFAULT_IMPORTANCE)) then
        return "IMPORTANCE";
    end

    -- hover는 false와 nil이 다른 뜻이다. 비교자와 같은 기준으로 본다.
    if ((lhs.hover ~= nil) ~= (rhs.hover ~= nil)) then
        return "HOVER";
    end

    if ((lhs.isConditional and true or false) ~= (rhs.isConditional and true or false)) then
        return "CONDITIONAL";
    end

    if (lhs.layerRank ~= rhs.layerRank) then
        return "LAYER";
    end

    if ((lhs.specRank or 0) ~= (rhs.specRank or 0)) then
        return "SPEC";
    end

    return nil;
end

--- Is this row part of what the key does, and therefore part of its order?
---
--- **Two ways to be out, and everything that orders rows treats them the same.** A badged row is
--- not in the build until it is accepted (`BuildKeyMap` leaves it out), and an off-spec row is not
--- in this specialization's key map at all. Swapping numbers with either moves a row on screen and
--- settles nothing about the key, which is the most expensive kind of wrong this list can be.
---
--- **Written once because it is asked in four places**: the guard and the neighbour skip in
--- `ComputeOrderSwap`, the arrows' live count, and the search for the next row that actually fires
--- (both in `DebindUI.lua`). It was inline at each of them, and the guard had only half of it -
--- so a badged row refused the arrows and accepted the same move from its right-click menu.
function DebindPrivate.IsRowInOrder(row)
    return not row.arrivalID and (row.specRank or 0) == 0;
end

--- rows(발동 순서로 정렬된 상태)의 targetIndex번째와 **순서 번호를 맞바꿀 이웃 행**을
--- 돌려준다. direction은 -1(위로) / 1(아래로).
---
--- 순서를 가르는 게 seq뿐일 때만 가능하다. 그때는 layerRank가 같으므로 둘이 같은 레이어에
--- 있고, 번호를 맞바꾸면 정확히 한 칸만 움직인다. 밴드도 조건도 스코프도 건드리지 않는다.
---
--- **맞바꿔도 다른 액션은 안 흔들린다.** seq는 같은 키의 행끼리만 비교되는 값이라(비교자가
--- 그 전에 키로 갈라 놓은 목록이다), 두 번호 사이에 다른 키의 액션이 몇 개 끼어 있든 그쪽
--- 순서에는 영향이 없다. 이웃은 이 키의 행 중 바로 옆이므로 한 칸이 맞다.
---
--- 못 하면 nil과 이유를 돌려준다:
---   "ALREADY_FIRST" | "ALREADY_LAST" - 끝이라 움직일 데가 없음
---   "IMPORTED" | "SPEC" - 대상이 이 키의 순서에 없다(`IsRowInOrder`)
---   "IMPORTANCE" | "HOVER" | "CONDITIONAL" | "LAYER" | "SPEC" - 그 단계에서 갈려서 seq까지 안 내려옴
---
--- 대상 자리도 범위 안이어야 한다. 지금 부르는 쪽은 rows를 돌면서 찾은 값을 주므로 그럴
--- 일이 없지만, 이 함수는 "못 하면 이유를 돌려준다"고 약속해 놓고 대신 터지면 안 된다.
function DebindPrivate.ComputeOrderSwap(rows, targetIndex, direction)
    if (targetIndex == nil or targetIndex < 1 or targetIndex > #rows) then
        return nil, direction < 0 and "ALREADY_FIRST" or "ALREADY_LAST";
    end

    -- **Refused here rather than by the skip below.** The skip would catch it in the ordinary case,
    -- since the neighbour it lands on comes out live, but only while some live row is left to land
    -- on. On a key whose rows are all out of the order the loop runs off the end and the answer
    -- comes back "already last", said about the first of several. Asking up front is both true and
    -- shorter. Why these rows are out is on `IsRowInOrder`.
    local target = rows[targetIndex];
    if (not DebindPrivate.IsRowInOrder(target)) then
        return nil, target.arrivalID and "IMPORTED" or "SPEC";
    end

    -- Skipping past the end is the same answer as starting there, so the two branches below catch
    -- it unchanged: nowhere to move to is nowhere to move to.
    local neighborIndex = targetIndex + direction;
    while (rows[neighborIndex] and not DebindPrivate.IsRowInOrder(rows[neighborIndex])) do
        neighborIndex = neighborIndex + direction;
    end

    if (neighborIndex < 1) then
        return nil, "ALREADY_FIRST";
    elseif (neighborIndex > #rows) then
        return nil, "ALREADY_LAST";
    end

    local axis = DebindPrivate.GetDecidingOrderAxis(rows[targetIndex], rows[neighborIndex]);
    if (axis) then
        return nil, axis;
    end

    return rows[neighborIndex];
end

--- 같은 물음을, **그룹과 자리를 손에 들고 있지 않은 쪽**을 위해 감싼 것. 액션만 주면 그 키의
--- 그룹을 다시 세우고 그 안에서 자기 자리를 찾아서 묻는다.
---
--- 우클릭 메뉴가 이 길로 온다. 메뉴는 뜬 채로 목록이 다시 지어질 수 있는 자리라 - 열 때
--- 붙잡아 둔 그룹은 `UpdateBindings` 한 번이면 순서가 갈린다 - 누를 때 다시 물어야 한다.
--- 목록 행은 반대다: 그릴 때 이미 그룹과 자리가 손에 있고(`elementData.rows/index`) 그것이
--- 곧 화면에 그려진 순서라, 저쪽은 `ComputeOrderSwap`을 그대로 부른다.
---
--- 키가 없거나 그룹에서 못 찾으면 사유를 낸다. `ComputeOrderSwap`이 범위 밖 인덱스에 대해
--- 이미 그렇게 답하므로 여기서 따로 갈래를 만들지 않는다.
function DebindPrivate.ComputeOrderSwapForAction(action, direction)
    local rows = action.key and DebindPrivate.CollectActionsForKey(action.key) or {};

    local targetIndex;
    for i, row in ipairs(rows) do
        if (row.action == action) then
            targetIndex = i;
            break;
        end
    end

    return DebindPrivate.ComputeOrderSwap(rows, targetIndex, direction);
end

do
    local SORT_KEYS = {
        LALT = 1,
        RALT = 2,
        LCTRL = 3,
        RCTRL = 4,
        LSHIFT = 5,
        RSHIFT = 6,
        LMETA = 7,
        RMETA = 8,
        ALT = 9,
        CTRL = 10,
        SHIFT = 11,
        META = 12,

        BUTTON1 = 21,
        BUTTON2 = 22,
        BUTTON3 = 23,
        BUTTON4 = 24,
        BUTTON5 = 25,
        MOUSEWHEELUP = 26,
        MOUSEWHEELDOWN = 27,

        UP = 61,
        DOWN = 62,
        LEFT = 63,
        RIGHT = 64,
        PAGEUP = 65,
        PAGEDOWN = 66,
        BACKSPACE = 67,
        TAB = 68,
        SPACE = 69,
        ENTER = 70,
        ESCAPE = 71,
        INSERT = 72,
        DELETE = 73,
        HOME = 74,
        END = 75,
        PRINTSCREEN = 76,
        PAUSE = 77,
        CAPSLOCK = 78,
        SCROLLLOCK = 79,

        NUMPAD1 = 91,
        NUMPAD2 = 92,
        NUMPAD3 = 93,
        NUMPAD4 = 94,
        NUMPAD5 = 95,
        NUMPAD6 = 96,
        NUMPAD7 = 97,
        NUMPAD8 = 98,
        NUMPAD9 = 99,
        NUMPAD0 = 100,
        NUMPADDECIMAL = 101,
        NUMLOCK = 102,
        NUMPADDIVIDE = 103,
        NUMPADMULTIPLY = 104,
        NUMPADMINUS = 105,
        NUMPADPLUS = 106,

        F1 = 121,
        F2 = 122,
        F3 = 123,
        F4 = 124,
        F5 = 125,
        F6 = 126,
        F7 = 127,
        F8 = 128,
        F9 = 129,
        F10 = 130,
        F11 = 131,
        F12 = 132,
    };

    local _parsedKeys = {};

    -- strsplit("-", key)와 같은 의미로 쪼갠다: 빈 조각을 보존하고 마지막 조각이 실제 키다.
    -- ("SHIFT--"는 mods = {"SHIFT", ""}, lastKey = "" - `-`도 구분자로 먹으므로 뒤가
    -- 빈다. strsplit도 "SHIFT", "", ""로 같게 쪼갠다.) strsplit을 안 쓰는 건 이 파일이
    -- WoW 전역 없이 로드돼야 하기 때문이다.
    local function ParseKey(key)
        local parsed = _parsedKeys[key];
        if (parsed) then
            return parsed;
        end

        local mods = {};
        local pos = 1;
        while (true) do
            local first, last = strfind(key, "-", pos, true);
            if (not first) then
                break;
            end
            mods[#mods + 1] = strsub(key, pos, first - 1);
            pos = last + 1;
        end

        parsed = { key = key, lastKey = strsub(key, pos), mods = mods };
        _parsedKeys[key] = parsed;
        return parsed;
    end

    --- 두 키 문자열("SHIFT-F" 등)의 표시 순서를 비교한다.
    --- 실제 키 먼저(SORT_KEYS 순, 모르는 키는 사전순으로 뒤), 같으면 수식키가 적은 쪽,
    --- 그것도 같으면 수식키를 앞에서부터 비교.
    ---
    --- **A number is a key whose real one has not been decided yet** and it sorts after every real
    --- key, in the slot the unbound pile sits in (`devdocs/building-export-import.md`). It has no
    --- modifiers and no key name to rank, so nothing below this could say anything about it -- and
    --- comparing a number against a string there is what raises **inside `table.sort`**, which
    --- leaves the column half drawn.
    function DebindPrivate.CompareKeys(lhs, rhs)
        local lhsSynthetic = type(lhs) == "number";
        local rhsSynthetic = type(rhs) == "number";
        if (lhsSynthetic or rhsSynthetic) then
            if (lhsSynthetic and rhsSynthetic) then
                return lhs < rhs;
            end
            return rhsSynthetic;
        end

        lhs, rhs = ParseKey(lhs), ParseKey(rhs);

        if (lhs.lastKey ~= rhs.lastKey) then
            local l = SORT_KEYS[lhs.lastKey];
            local r = SORT_KEYS[rhs.lastKey];

            if (l and r) then
                return l < r;
            elseif (l) then
                return true;
            elseif (r) then
                return false;
            else
                return lhs.lastKey < rhs.lastKey;
            end
        end

        if (#lhs.mods ~= #rhs.mods) then
            return #lhs.mods < #rhs.mods;
        end

        -- 모르는 수식키도 lastKey와 같은 규칙으로 다룬다. 여기만 가드가 없으면 SORT_KEYS에
        -- 없는 조각이 하나라도 섞였을 때 nil과 숫자를 비교하다가 **table.sort 안에서**
        -- 터진다 - 목록이 반쯤 섞인 채로 그리기가 멈춘다. 양쪽 다 모르면 nil ~= nil이
        -- 거짓이라 그냥 지나가서, 서로 다른 키가 같은 것으로 판정돼 헤더가 겹쳐 나온다.
        -- 애드온이 만드는 키로는 닿지 않지만 SavedVariables는 손으로 고칠 수 있다.
        for i = 1, #lhs.mods do
            local lm, rm = lhs.mods[i], rhs.mods[i];
            if (lm ~= rm) then
                local a = SORT_KEYS[lm];
                local b = SORT_KEYS[rm];
                if (a and b) then
                    if (a ~= b) then
                        return a < b;
                    end
                elseif (a) then
                    return true;
                elseif (b) then
                    return false;
                else
                    return lm < rm;
                end
            end
        end
    end
end
