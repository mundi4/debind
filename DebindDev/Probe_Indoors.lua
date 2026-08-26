-- Probe_Indoors.lua
-- 일회성 프로브: `IsIndoors()`와 `IsOutdoors()`가 여집합인가. 둘이 같은 값이면 반례다.
-- 답이 나오면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 한두 프레임 스치는 것과 그 자리에 서 있는 내내 그런 것은 결론이 반대라서, 프레임마다가
-- 아니라 구간이 끝날 때 몇 프레임이었는지를 찍는다.

local frames, value = 0

CreateFrame("Frame"):SetScript("OnUpdate", function()
    local indoors = IsIndoors() and true or false
    if (indoors == (IsOutdoors() and true or false)) then
        if (frames == 0) then
            value = indoors
        end
        frames = frames + 1
    elseif (frames > 0) then
        print(format("[IO] 둘 다 %s로 %d프레임", tostring(value), frames))
        frames = 0
    end
end)
