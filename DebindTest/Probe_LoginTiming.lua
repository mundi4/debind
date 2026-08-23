-- Probe_LoginTiming.lua
-- 일회성 프로브: 로그인 틱과 전투 락다운의 관계를 재는 것.
-- 답이 나오면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 사용법:
--   보스전 도중에 튕겨서 재접속한 뒤 /deblogin
--   /deblogin        지난 기록 출력
--   /deblogin wipe   기록 지우고 다시 잰다 (다음 로그인부터)
--
-- 답하려는 것:
--   1. PLAYER_LOGIN 시점에 InCombatLockdown()이 켜져 있나
--   2. 안 켜져 있다면, 처음으로 켜진 채 도착하는 이벤트가 무엇이고 언제인가
--   3. 그것이 PLAYER_LOGIN과 같은 프레임인가 다음 프레임인가
--
-- 프레임 번호를 같이 찍는 이유는 그것이 3번을 답하는 유일한 값이기 때문이다. 타임스탬프는
-- 같은 프레임 안에서도 다르게 나올 수 있고, 다른 프레임인데 붙어 있을 수도 있다.

local DebindPrivate = _G.DebindPrivate
if (not DebindPrivate) then
    return
end

--- 로그인 순서를 이루는 이벤트들. RegisterAllEvents로 받는 것 중 이 목록에 있는 것만 적는다.
--- 나머지는 전투 로그처럼 초당 수십 번 오는 것들이라 적으면 기록이 그것만으로 찬다.
local INIT_EVENTS = {
    ADDON_LOADED = true,
    VARIABLES_LOADED = true,
    SPELLS_CHANGED = true,
    PLAYER_LOGIN = true,
    PLAYER_ENTERING_WORLD = true,
    PLAYER_ALIVE = true,
    UPDATE_BINDINGS = true,
    ACTIVE_PLAYER_SPECIALIZATION_CHANGED = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
    GROUP_ROSTER_UPDATE = true,
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
    ENCOUNTER_START = true,
    ZONE_CHANGED_NEW_AREA = true,
}

local T0 = GetTimePreciseSec()

--- 이 파일이 로드된 프레임을 0번으로 놓은 프레임 번호. `OnUpdate`는 프레임당 정확히 한 번
--- 불리므로, 두 이벤트의 번호가 같으면 같은 프레임에 도착한 것이다.
local frameIndex = 0

local log = {}
local firstLockdown = nil
local done = false

local probe = CreateFrame("Frame")

local function Record(kind, event, lockdown, arg1)
    log[#log + 1] = {
        kind = kind,
        event = event,
        lockdown = lockdown,
        frame = frameIndex,
        at = GetTimePreciseSec() - T0,
        arg1 = tostring(arg1),
    }
end

--- **기록을 멈추는 조건이 둘 다 필요하다.** 락다운을 봤어도 세계 진입을 아직 못 봤으면 순서가
--- 안 나오고, 세계 진입만 보고 멈추면 전투가 나중에 걸리는 평범한 로그인에서 1번 답이 없다.
local function StopIfAnswered()
    if (done) then
        return
    end
    if (not firstLockdown) then
        return
    end
    for i = 1, #log do
        if (log[i].event == "PLAYER_ENTERING_WORLD") then
            done = true
            probe:UnregisterAllEvents()
            probe:SetScript("OnUpdate", nil)
            return
        end
    end
end

--- **락다운은 이벤트 없이도 켜진다.** 서버가 재접속 뒤에 전투를 다시 걸 때 그것을 알리는
--- 이벤트가 우리에게 온다는 보장이 없고, 온다 해도 그 전에 이미 켜져 있을 수 있다. 그래서
--- 프레임마다 한 번 직접 묻는다. 이벤트 쪽에서 먼저 잡히면 그쪽이 기록되고 여기는 물러난다.
local function NoteLockdown(event, arg1)
    if (firstLockdown) then
        return
    end
    Record("LOCKDOWN", event, true, arg1)
    firstLockdown = log[#log]
end

probe:SetScript("OnUpdate", function()
    frameIndex = frameIndex + 1
    if (not firstLockdown and InCombatLockdown()) then
        NoteLockdown("(OnUpdate)")
        StopIfAnswered()
    end
end)

probe:SetScript("OnEvent", function(_, event, arg1)
    local lockdown = InCombatLockdown() and true or false

    if (not firstLockdown and lockdown) then
        NoteLockdown(event, arg1)
    elseif (INIT_EVENTS[event]) then
        Record("INIT", event, lockdown, arg1)
    end

    StopIfAnswered()
end)

probe:RegisterAllEvents()

--- SavedVariables에 옮기는 것은 로그아웃 때다. 재접속해서 읽는 것이 이 프로브의 용도라,
--- 이번 세션의 기록이 아니라 **지난 세션의 기록**이 답이다.
local saver = CreateFrame("Frame")
saver:RegisterEvent("PLAYER_LOGOUT")
saver:SetScript("OnEvent", function()
    DebindTestDB = DebindTestDB or {}
    DebindTestDB.loginTiming = log
end)

local function Dump(entries, label)
    if (not entries or #entries == 0) then
        print("|cffff9900[LoginTiming]|r " .. label .. ": 기록 없음")
        return
    end
    print(format("|cffff9900[LoginTiming]|r %s (%d줄)", label, #entries))
    print("|cff808080  frame     t(ms)  lockdown  event|r")
    for i = 1, #entries do
        local e = entries[i]
        local mark = (e.kind == "LOCKDOWN") and "|cffff4444<== 첫 락다운|r" or ""
        print(format("  %5d  %8.2f  %-8s  %s %s %s",
            e.frame or -1,
            (e.at or 0) * 1000,
            e.lockdown and "|cffff4444TRUE|r" or "false",
            e.event or "?",
            (e.arg1 ~= "nil") and ("|cff808080" .. e.arg1 .. "|r") or "",
            mark))
    end
end

SLASH_DEBLOGIN1 = "/deblogin"
SlashCmdList["DEBLOGIN"] = function(msg)
    msg = strlower(strtrim(msg or ""))

    if (msg == "wipe") then
        DebindTestDB = DebindTestDB or {}
        DebindTestDB.loginTiming = nil
        print("|cffff9900[LoginTiming]|r 지난 기록을 지웠다. 다음 로그인부터 다시 잰다.")
        return
    end

    Dump(DebindTestDB and DebindTestDB.loginTiming, "지난 세션")
    Dump(log, "이번 세션")
end
