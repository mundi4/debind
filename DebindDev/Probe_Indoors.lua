-- Probe_Indoors.lua
-- 일회성 프로브: `IsIndoors()`와 `IsOutdoors()`가 서로의 여집합인가.
-- 답이 나오면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 사용법:
--   /debio          세션 집계 출력 (지금 값, 표본 수, 어긋난 자리 목록)
--   /debio reset    집계를 지운다. 저장된 것까지
--
-- 왜 묻는가:
--   `indoors` 조건 축은 `IsIndoors()` **하나만** 잰다. 둘이 여집합이면 거짓 쪽 라벨을
--   클라이언트의 "실외"(`HOUSING_CATALOG_FILTERS_OUTDOORS`)로 바꿀 수 있고,
--   `SWITCH_GATE_STATES`에 `outdoors`도 넣을 수 있다. 여집합이 아니면 지금 라벨인
--   "실내가 아닐 때"가 맞고 게이트에도 못 넣는다.
--
--   추출본으로는 답이 안 나온다. 블리자드 UI 코드는 두 함수를 한 번도 안 부르고, API
--   문서도 양쪽 다 `bool`이라고만 하지 둘의 관계를 말하지 않는다.
--
-- 무엇이 답인가:
--   **어긋남 = 둘이 같은 값**이다. 여집합이면 언제나 하나는 참 하나는 거짓이어야 하므로,
--   둘 다 참이거나 둘 다 거짓인 순간이 한 번이라도 잡히면 여집합이 아니다.
--
--   한 번도 안 잡히는 것도 답이다. 다만 그 답의 무게는 표본 수가 정하므로 프레임 수와
--   돌아본 자리 수를 같이 센다. "아무것도 안 찍혔다"는 그 자체로는 아무 말도 아니다.
--
-- 매 프레임 도는 것은 이 파일의 `OnUpdate` 하나고, C 호출 둘과 비교 하나가 전부다.
-- 어긋난 자리는 자리마다 한 번만 찍는다 - 문간을 왔다갔다하면 같은 줄이 수백 번 나온다.

local TAG = "|cffffcc66[IO]|r "
local PLACE_CAP = 40

local census = {
    frames = 0,
    mismatches = 0,
    places = {},
    placeCount = 0,
    -- 본 조합 넷 각각의 프레임 수. 어긋남이 안 나왔을 때 **무엇을 본 표본인지**를 말해준다:
    -- 실내에 한 번도 안 들어가 본 세션이면 참/거짓 한 쪽만 수십만 번 본 것이라 값이 없다.
    pairs = {},
}

--- `true/false` 두 값을 표의 키로 쓸 한 글자짜리 조합 이름으로.
local function PairKey(indoors, outdoors)
    return (indoors and "I" or "i") .. (outdoors and "O" or "o")
end

--- 지금 서 있는 자리를, 다시 찾아올 수 있을 만큼만.
---
--- **좌표는 없을 수 있다.** 인스턴스 안에서는 `GetPlayerMapPosition`이 nil을 내고, 맵이
--- 아직 안 잡힌 순간도 있다. 그래서 좌표가 있으면 붙이고 없으면 이름만 쓴다.
local function Where()
    local zone = GetZoneText() or "?"
    local sub = GetSubZoneText()
    local _, kind = pcall(IsInInstance)
    local name = (sub and sub ~= "") and (zone .. " / " .. sub) or zone

    local mapID = C_Map.GetBestMapForUnit("player")
    if (mapID) then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if (ok and pos) then
            local x, y = pos:GetXY()
            if (x and y) then
                return format("%s (%s) %.1f,%.1f", name, tostring(kind), x * 100, y * 100)
            end
        end
    end
    return format("%s (%s)", name, tostring(kind))
end

local function Save()
    DebindDevDB = DebindDevDB or {}
    DebindDevDB.indoorsProbe = {
        at = date("%Y-%m-%d %H:%M:%S"),
        frames = census.frames,
        mismatches = census.mismatches,
        places = census.places,
        pairs = census.pairs,
    }
end

--- **자리마다 한 번만 찍는다.** 문간에 서서 한 발씩 움직이면 같은 어긋남이 프레임마다
--- 다시 잡히고, 채팅창이 한 줄로 덮인다. 세는 것은 전부 세고 말하는 것만 줄인다.
local function NoteMismatch(indoors, outdoors)
    census.mismatches = census.mismatches + 1

    local key = PairKey(indoors, outdoors) .. " " .. Where()
    if (census.places[key]) then
        census.places[key] = census.places[key] + 1
        return
    end
    if (census.placeCount >= PLACE_CAP) then
        return
    end

    census.places[key] = 1
    census.placeCount = census.placeCount + 1

    print(format("%s|cffff4444여집합 아님|r indoors=%s outdoors=%s @ %s",
        TAG, tostring(indoors), tostring(outdoors), Where()))
    Save()
end

--- 직전 프레임의 조합. 바뀐 프레임에서만 어긋남을 따진다.
---
--- **이 메모가 없으면 어긋난 자리에 서 있는 동안 매 프레임 `Where()`가 돈다.** 그쪽이
--- 이 파일에서 유일하게 싼 값이 아닌 호출이다.
local last

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
    local indoors = IsIndoors() and true or false
    local outdoors = IsOutdoors() and true or false

    census.frames = census.frames + 1

    local key = PairKey(indoors, outdoors)
    census.pairs[key] = (census.pairs[key] or 0) + 1

    if (key ~= last) then
        last = key
        if (indoors == outdoors) then
            NoteMismatch(indoors, outdoors)
        end
    end
end)

local function Report()
    local indoors = IsIndoors() and true or false
    local outdoors = IsOutdoors() and true or false

    print(format("%s지금: indoors=%s outdoors=%s", TAG, tostring(indoors), tostring(outdoors)))
    print(format("%s%s", TAG, Where()))
    print(format("%s표본 %d프레임, 어긋남 %d회", TAG, census.frames, census.mismatches))

    -- **넷 다 적는다.** 안 본 조합이 0으로 남는 것이 이 표의 값이다: `Io`와 `iO`만 있고
    -- `II`/`ii`가 0이면 "여집합이더라"가 아니라 "여집합인 자리만 돌아다녔다"이다.
    print(format("%s조합별 프레임: 실내만 Io=%d, 실외만 iO=%d, |cffff4444둘 다 참 II=%d, 둘 다 거짓 ii=%d|r",
        TAG, census.pairs["Io"] or 0, census.pairs["iO"] or 0,
        census.pairs["II"] or 0, census.pairs["ii"] or 0))

    if (census.placeCount == 0) then
        print(TAG .. "어긋난 자리 없음. 위의 II/ii가 둘 다 0이면 아직 반례를 못 본 것이다")
    else
        print(format("%s어긋난 자리 %d곳 (최대 %d곳까지 기억):", TAG, census.placeCount, PLACE_CAP))
        for place, count in pairs(census.places) do
            print(format("%s  %s x%d", TAG, place, count))
        end
    end

    Save()
end

SLASH_DEBIO1 = "/debio"
SlashCmdList["DEBIO"] = function(msg)
    if (strtrim(msg or "") == "reset") then
        census.frames = 0
        census.mismatches = 0
        census.places = {}
        census.placeCount = 0
        census.pairs = {}
        last = nil
        if (DebindDevDB) then
            DebindDevDB.indoorsProbe = nil
        end
        print(TAG .. "집계를 지웠다")
        return
    end
    Report()
end
