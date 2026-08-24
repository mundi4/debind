-- Probe_FrameBoundary.lua
-- 일회성 프로브: 이벤트가 어느 프레임에 도착하는지.
-- 답이 나오면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 사용법:
--   /debframe        켜고 끄기. 켠 채로 대상을 바꾸면 줄이 찍힌다
--
-- `GetTime()`은 프레임 시작 시각이라 한 프레임 안에서는 값이 같다. 그래서 이벤트 줄의
-- `GetTime()`이 바로 앞 OnUpdate와 같으면 그 이벤트는 그 OnUpdate와 같은 프레임이고,
-- 다르면 그 사이에서 프레임이 넘어간 것이다. `GetTimePreciseSec()`은 부를 때마다 달라서
-- 이걸 못 가른다.

local on = false
local seq = 0
local lastGetTime = nil

local probe = CreateFrame("Frame")

local function Line(kind, extra)
    seq = seq + 1
    local now = GetTime()
    local mark = (lastGetTime == now) and "|cff808080same|r" or "|cffffcc00NEW FRAME|r"
    lastGetTime = now
    print(format("|cffff9900[FrameBoundary]|r %3d  %-8s  GetTime=%.3f  %s  %s",
        seq, kind, now, mark, extra or ""))
end

probe:SetScript("OnUpdate", function(_, elapsed)
    Line("OnUpdate", format("elapsed=%.4f", elapsed))
end)

probe:SetScript("OnEvent", function(_, event)
    Line("EVENT", event)
end)

SLASH_DEBFRAME1 = "/debframe"
SlashCmdList["DEBFRAME"] = function()
    on = not on
    if (on) then
        seq = 0
        lastGetTime = nil
        probe:RegisterEvent("PLAYER_TARGET_CHANGED")
        probe:Show()
        print("|cffff9900[FrameBoundary]|r 켰다. 대상을 바꿔라. 끄려면 /debframe")
    else
        probe:UnregisterAllEvents()
        probe:Hide()
        print("|cffff9900[FrameBoundary]|r 껐다.")
    end
end

probe:Hide()
