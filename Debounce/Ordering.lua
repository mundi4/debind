local _, DebouncePrivate = ...;
local Constants          = DebouncePrivate.Constants;

local DEFAULT_PRIORITY   = Constants.DEFAULT_PRIORITY;
local MIN_PRIORITY       = Constants.MIN_PRIORITY;
local MAX_PRIORITY       = Constants.MAX_PRIORITY;

-- 순서 규칙만 모아둔 파일. **WoW API를 부르지 말 것** - 헤드리스 테스트
-- (tests/ordering_spec.lua)가 이 파일을 그대로 로드한다.
-- 액션을 수집하는 쪽은 레이어를 훑어야 하므로 Profile.lua에 있다
-- (DebouncePrivate.CollectActionsForKey).


--- 같은 키에 걸린 두 액션의 발동 순서를 비교한다.
---
--- 레코드 필드: priority, hover, isConditional, layerRank, index
---   priority      - nil이면 Constants.DEFAULT_PRIORITY
---   hover         - **원본 값 그대로.** false와 nil이 다른 뜻이다(false = "hover 아님"을
---                   명시한 조건이라 조건이 걸린 것으로 친다). 불리언으로 접어 넘기지 말 것
---   isConditional - DebouncePrivate.IsConditionalAction(action)
---   layerRank     - EnumerateProfileLayers의 순회 순번 (작을수록 구체적인 레이어)
---   index         - 그 레이어 배열 안의 위치
---
--- (layerRank, index)는 예전 binding.ordinal(활성 레이어를 훑으며 매기던 통짜 일련번호)을
--- 두 자리로 편 것이다. 사전식 비교라 결과는 ordinal 비교와 동일하다.
---
--- 이 순서를 바꾸면 저장 데이터는 그대로인데 전 사용자의 발동 순서가 조용히 바뀌고,
--- 공유 레이어 때문에 순서를 보존하는 마이그레이션을 만들 수가 없다. 건드리지 말 것.
function DebouncePrivate.CompareActionOrder(lhs, rhs)
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

    return lhs.index < rhs.index;
end


--- 저장할 priority 값. 기본값이면 nil이다 - CleanUpDB가 어차피 지운다
--- (Profile.lua:286-287). UI가 저장하기 전에 반드시 이걸 거친다.
function DebouncePrivate.PriorityToStored(priority)
    if (priority == nil or priority == DEFAULT_PRIORITY) then
        return nil;
    end
    return priority;
end

do
    -- 비교자에 넘길 임시 레코드. 한 번에 하나만 쓰므로 하나로 돌려쓴다.
    local _probe = {};

    local function WithPriority(rec, priority)
        _probe.priority = priority;
        _probe.hover = rec.hover;
        _probe.isConditional = rec.isConditional;
        _probe.layerRank = rec.layerRank;
        _probe.index = rec.index;
        return _probe;
    end

    --- rows(정렬된 상태)의 targetIndex번째를 **바로 위 행보다 먼저** 오게 하는 데 필요한
    --- priority를 찾는다. 성공하면 priority를, 못 하면 nil과 이유를 돌려준다.
    ---
    --- 두 단계뿐이다. 같은 밴드로 올려서 이기면 그걸로 끝이고(구체성·레이어·index가 우리
    --- 편인 경우), 아니면 한 밴드 위로 간다 - priority는 비교의 첫 단계라 그건 항상 이긴다.
    --- 이미 최상단 밴드인데 같은 밴드에서 못 이기면 방법이 없다. 그때는 스코프나 조건을
    --- 고쳐야 하고, 그건 우선순위가 할 수 있는 일이 아니다.
    ---
    --- 이유: "ALREADY_FIRST" | "TOP_BAND"
    function DebouncePrivate.ComputeRaisePriority(rows, targetIndex)
        if (targetIndex == nil or targetIndex <= 1) then
            return nil, "ALREADY_FIRST";
        end

        local target = rows[targetIndex];
        local above = rows[targetIndex - 1];
        local abovePriority = above.priority or DEFAULT_PRIORITY;

        if (DebouncePrivate.CompareActionOrder(WithPriority(target, abovePriority), above)) then
            return abovePriority;
        end

        local candidate = abovePriority - 1;
        if (candidate < MIN_PRIORITY) then
            return nil, "TOP_BAND";
        end
        return candidate;
    end

    --- 위와 대칭. targetIndex번째를 **바로 아래 행보다 뒤로** 보낸다.
    --- 이유: "ALREADY_LAST" | "BOTTOM_BAND"
    function DebouncePrivate.ComputeLowerPriority(rows, targetIndex)
        if (targetIndex == nil or targetIndex >= #rows) then
            return nil, "ALREADY_LAST";
        end

        local target = rows[targetIndex];
        local below = rows[targetIndex + 1];
        local belowPriority = below.priority or DEFAULT_PRIORITY;

        if (DebouncePrivate.CompareActionOrder(below, WithPriority(target, belowPriority))) then
            return belowPriority;
        end

        local candidate = belowPriority + 1;
        if (candidate > MAX_PRIORITY) then
            return nil, "BOTTOM_BAND";
        end
        return candidate;
    end
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
    -- ("SHIFT--"는 mods = {"SHIFT", ""}, lastKey = "-") strsplit을 안 쓰는 건 이 파일이
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
    function DebouncePrivate.CompareKeys(lhs, rhs)
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

        for i = 1, #lhs.mods do
            local a = SORT_KEYS[lhs.mods[i]];
            local b = SORT_KEYS[rhs.mods[i]];
            if (a ~= b) then
                return a < b;
            end
        end
    end
end
