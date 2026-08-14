local _, DebindPrivate = ...;
local Constants          = DebindPrivate.Constants;

local DEFAULT_PRIORITY   = Constants.DEFAULT_PRIORITY;

-- 순서 규칙만 모아둔 파일. **WoW API를 부르지 말 것** - 헤드리스 테스트
-- (tests/ordering_spec.lua)가 이 파일을 그대로 로드한다.
-- 액션을 수집하는 쪽은 레이어를 훑어야 하므로 Profile.lua에 있다
-- (DebindPrivate.CollectActionsForKey).


--- 같은 키에 걸린 두 액션의 발동 순서를 비교한다.
---
--- 레코드 필드: priority, hover, isConditional, layerRank, seq
---   priority      - nil이면 Constants.DEFAULT_PRIORITY
---   hover         - **원본 값 그대로.** false와 nil이 다른 뜻이다(false = "hover 아님"을
---                   명시한 조건이라 조건이 걸린 것으로 친다). 불리언으로 접어 넘기지 말 것
---   isConditional - DebindPrivate.IsConditionalAction(action)
---   layerRank     - EnumerateProfileLayers의 순회 순번 (작을수록 구체적인 레이어)
---   seq           - action.seq. 그 레이어 안에서만 뜻이 있는 저장된 순서 번호
---
--- (layerRank, seq)는 예전 binding.ordinal(활성 레이어를 훑으며 매기던 통짜 일련번호)을
--- 두 자리로 편 것이다. 사전식 비교라 결과는 ordinal 비교와 동일하다.
---
--- 이 순서를 바꾸면 저장 데이터는 그대로인데 전 사용자의 발동 순서가 조용히 바뀌고,
--- 공유 레이어 때문에 순서를 보존하는 마이그레이션을 만들 수가 없다. 건드리지 말 것.
function DebindPrivate.CompareActionOrder(lhs, rhs)
    local lhsPriority = lhs.priority or DEFAULT_PRIORITY;
    local rhsPriority = rhs.priority or DEFAULT_PRIORITY;
    if (lhsPriority ~= rhsPriority) then
        return lhsPriority < rhsPriority;
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

    -- 마지막은 **저장된 순서 번호**다. 한때 여기서 레이어 배열의 자리(index)를 읽었는데,
    -- 목록이 키순 정렬로 바뀌면서 그 자리는 화면에도 안 나오고 만질 방법도 없는 값이 됐다.
    -- 뜻이 없는 값이 순서를 정하니 키를 새로 걸었을 때 어떤 액션은 기존 것들 위로, 어떤
    -- 액션은 아래로 들어갔다 - 같은 조작인데 결과가 그 액션이 우연히 배열 어디에 있었느냐로
    -- 갈렸다. 지금은 키를 걸 때 그 레이어의 맨 뒤 번호를 받는다(Profile.lua의 PlaceLast).
    --
    -- nil은 0으로 본다. 여기까지 왔다는 건 둘 다 키가 걸린 액션이라는 뜻이고, 그런 액션은
    -- 마이그레이션과 CleanUpDB가 번호를 보장한다. 그물이 찢어져도 정렬 안에서 nil을 비교해
    -- 터지는 것보다는 낫다.
    return (lhs.seq or 0) < (rhs.seq or 0);
end


--- 저장할 priority 값. 기본값이면 nil이다 - CleanUpDB가 어차피 지운다
--- (Profile.lua:286-287). UI가 저장하기 전에 반드시 이걸 거친다.
function DebindPrivate.PriorityToStored(priority)
    if (priority == nil or priority == DEFAULT_PRIORITY) then
        return nil;
    end
    return priority;
end

--- 두 액션의 순서를 **가른 단계**를 돌려준다. seq까지 내려왔으면(= 앞의 네 단계가 전부
--- 동률이면) nil이다. CompareActionOrder와 판정이 한 글자도 어긋나면 안 된다.
---
--- 순서 UI가 이걸 쓰는 이유: 비교자의 각 단계는 그 자체로 뜻이 있는 속성이고, 각각 자기
--- 뜻이 사는 자리에서 바뀐다(우선순위 메뉴 / 조건 편집 / 레이어 이동). 그 넷 중 아무것도
--- 안 갈렸을 때 남는 것이 seq이고, 정렬 버튼이 만지는 것도 그것뿐이다. 나머지에서 갈렸다면
--- 버튼은 손을 떼고 **어느 속성이 정하고 있는지**만 말해야 한다.
function DebindPrivate.GetDecidingOrderAxis(lhs, rhs)
    if ((lhs.priority or DEFAULT_PRIORITY) ~= (rhs.priority or DEFAULT_PRIORITY)) then
        return "PRIORITY";
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

    return nil;
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
---   "PRIORITY" | "HOVER" | "CONDITIONAL" | "LAYER" - 그 단계에서 갈려서 seq까지 안 내려옴
---
--- 대상 자리도 범위 안이어야 한다. 지금 부르는 쪽은 rows를 돌면서 찾은 값을 주므로 그럴
--- 일이 없지만, 이 함수는 "못 하면 이유를 돌려준다"고 약속해 놓고 대신 터지면 안 된다.
function DebindPrivate.ComputeOrderSwap(rows, targetIndex, direction)
    if (targetIndex == nil or targetIndex < 1 or targetIndex > #rows) then
        return nil, direction < 0 and "ALREADY_FIRST" or "ALREADY_LAST";
    end

    -- **A badged row is not an opponent.** `BuildKeyMap` leaves those actions out of the build, so
    -- they are not part of what this key does and therefore not part of its order. Swapping numbers
    -- with one moves a row on screen and changes nothing about the key - the reader presses a
    -- button, watches the list rearrange, and believes they settled something. That is the most
    -- expensive kind of wrong this list can be.
    --
    -- Skipping past the end is the same answer as starting there, so the two branches below catch
    -- it unchanged: nowhere to move to is nowhere to move to.
    local neighborIndex = targetIndex + direction;
    while (rows[neighborIndex] and rows[neighborIndex].imported) do
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
    function DebindPrivate.CompareKeys(lhs, rhs)
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
