local _, DebouncePrivate = ...;
local Constants          = DebouncePrivate.Constants;

local DEFAULT_PRIORITY   = Constants.DEFAULT_PRIORITY;

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
