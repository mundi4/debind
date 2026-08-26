-- Probe_NamePlates.lua
-- 일회성 프로브: 이름표에 호버와 클릭을 물릴 수 있는가.
-- 답이 나오면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 사용법:
--   /debnp          지금 떠 있는 이름표 표 + 세션 집계를 출력
--   /debnp wrap     지금 떠 있는 이름표에 실제로 래퍼를 건다 (전투 밖)
--   /debnp unwrap   그 래퍼를 떼어낸다. 비보안 훅은 안 떨어지니 확인이 끝나면 /reload
--   /debnp last     지난 출력 다시 보기
--
-- 답하려는 것:
--   1. 베이스 프레임이 무슨 위젯이고 OnEnter/OnLeave/OnClick 스크립트 타입을 갖는가.
--      OnClick이 있으면 베이스에 바로 감싸면 되고, 없으면 우리 버튼을 덮어야 한다.
--   2. IsProtected / IsForbidden / IsAnchoringRestricted 가 실제로 뭐라고 답하는가.
--      야외 / 던전 / 레이드 각각, 적과 아군 각각 찍어야 한다.
--   3. SecureHandlerWrapScript 가 통과하는가, 통과한 래퍼가 실제로 도는가.
--      거는 것과 도는 것은 다른 질문이라 둘 다 찍는다.
--   4. 베이스가 전투 중에 생기는 일이 실전에서 얼마나 잦은가. 그때 생긴 베이스는
--      전투가 끝날 때까지 손을 못 대므로, 이 빈도가 기능이 쓸 만한지를 가른다.
--
-- 4번만 파일이 로드된 순간부터 늘 돌고, 나머지는 슬래시 명령으로만 움직인다.

local LOG_CAP = 60
local PLATE_CAP = 20

local out = {}

local function Emit(fmt, ...)
    local line = format(fmt, ...)
    tinsert(out, line)
    print("|cff66ccff[NP]|r " .. line)
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

--- pcall a zero-arg method and collapse the outcome to one printable token. Same shape as
--- Probe_ForbiddenFrames: a nameplate may answer a secret, and a forbidden one throws on
--- every method, so nothing here may be called bare.
local function Try(obj, method, ...)
    local okIndex, fn = pcall(function() return obj[method] end)
    if (not okIndex) then
        return "idxERR"
    end
    if (not fn) then
        return "-"
    end
    local ok, v = pcall(fn, obj, ...)
    if (not ok) then
        return "ERR"
    end
    if (IsSecret(v)) then
        return "secret"
    end
    return tostring(v)
end

--- `IsProtected` answers two values and only the second one settles whether SecureHandlers
--- will take the frame as a header, so the pair is printed as `protected/explicit`.
local function TryProtected(frame)
    local okIndex, fn = pcall(function() return frame.IsProtected end)
    if (not okIndex or not fn) then
        return "-"
    end
    local ok, a, b = pcall(fn, frame)
    if (not ok) then
        return "ERR"
    end
    if (IsSecret(a) or IsSecret(b)) then
        return "secret"
    end
    return tostring(a) .. "/" .. tostring(b)
end

--- Which of the four script types the widget actually has. This is the whole of question 1:
--- `HasScript("OnClick")` false means the base is not a button and a wrapper cannot route a
--- click through it.
local SCRIPTS = { "OnEnter", "OnLeave", "OnClick", "OnMouseDown" }

local function ScriptString(frame)
    local okIndex, fn = pcall(function() return frame.HasScript end)
    if (not okIndex or not fn) then
        return "?"
    end
    local names = {}
    for _, script in ipairs(SCRIPTS) do
        local ok, v = pcall(fn, frame, script)
        if (ok and v == true) then
            tinsert(names, script:sub(3))
        end
    end
    return #names > 0 and table.concat(names, "+") or "none"
end

-----------------------------------------------------------
-- Session census: runs from load, because the pool only ever grows and a count started at
-- /debnp time has already missed every base the session made before it.
-----------------------------------------------------------

local census = {
    created = 0,
    createdInCombat = 0,
    forbiddenCreated = 0,
    forbiddenInCombat = 0,
    unitFrames = 0,
    unitFrameSwaps = 0,
    log = {},
}

local function InstanceType()
    local ok, _, kind = pcall(IsInInstance)
    return ok and tostring(kind) or "?"
end

local function NoteCreation(kind)
    local combat = InCombatLockdown() and true or false
    local where = InstanceType()

    if (kind == "forbidden") then
        census.forbiddenCreated = census.forbiddenCreated + 1
        if (combat) then
            census.forbiddenInCombat = census.forbiddenInCombat + 1
        end
    else
        census.created = census.created + 1
        if (combat) then
            census.createdInCombat = census.createdInCombat + 1
        end
    end

    if (#census.log < LOG_CAP) then
        tinsert(census.log, format("%s #%d t=%.1f %s %s",
            kind, (kind == "forbidden") and census.forbiddenCreated or census.created,
            GetTime(), where, combat and "|cffff4444전투중|r" or "밖"))
    end

    -- The one case worth interrupting for: a base born mid-fight is one we cannot touch
    -- until the fight ends, so it gets said out loud when it happens.
    if (combat and kind ~= "forbidden") then
        print(format("|cff66ccff[NP]|r 전투 중 베이스 생성 #%d (%s)", census.created, where))
    end
end

--- `plate.UnitFrame` is pooled separately from the base: the driver acquires one on unit
--- added and releases it on unit removed (`NamePlateBaseMixin:AcquireUnitFrame`). So a
--- wrapper put on the UnitFrame would follow the pool and not the plate. This counts how
--- often a plate comes back holding a different UnitFrame, which is what settles whether
--- the UnitFrame is a place we could hold on to at all.
local unitFrameOfPlate = setmetatable({}, { __mode = "k" })
local unitFramesSeen = setmetatable({}, { __mode = "k" })

local function NoteUnitFrame(token)
    if (type(token) ~= "string") then
        return
    end
    local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, token)
    if (not okP or not plate) then
        return
    end
    local uf = rawget(plate, "UnitFrame")
    if (not uf) then
        return
    end
    if (not unitFramesSeen[uf]) then
        unitFramesSeen[uf] = true
        census.unitFrames = census.unitFrames + 1
    end
    local prev = unitFrameOfPlate[plate]
    if (prev and prev ~= uf) then
        census.unitFrameSwaps = census.unitFrameSwaps + 1
    end
    unitFrameOfPlate[plate] = uf
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("NAME_PLATE_CREATED")
watcher:RegisterEvent("FORBIDDEN_NAME_PLATE_CREATED")
watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
watcher:SetScript("OnEvent", function(_, event, ...)
    if (event == "NAME_PLATE_CREATED") then
        NoteCreation("plate")
    elseif (event == "FORBIDDEN_NAME_PLATE_CREATED") then
        NoteCreation("forbidden")
    elseif (event == "NAME_PLATE_UNIT_ADDED") then
        NoteUnitFrame(...)
    end
end)

-----------------------------------------------------------
-- The plate table
-----------------------------------------------------------

--- Tokens whose unit exists but whose plate `GetNamePlateForUnit` will not hand over. That
--- gap is the forbidden detector: `includeForbidden` defaults to false, so a forbidden plate
--- reads as nil. Nothing here calls a method on a forbidden frame.
local function ScanTokens()
    local exists, visible, hidden = 0, 0, 0
    for i = 1, 40 do
        local token = "nameplate" .. i
        local okE, e = pcall(UnitExists, token)
        if (okE and e == true) then
            exists = exists + 1
            local okP, plate = pcall(C_NamePlate.GetNamePlateForUnit, token)
            if (okP and plate) then
                visible = visible + 1
            else
                hidden = hidden + 1
            end
        end
    end
    return exists, visible, hidden
end

local function PlateLabel(plate)
    local ok, name = pcall(function() return plate:GetName() end)
    if (ok and type(name) == "string" and name ~= "") then
        return name
    end
    return tostring(plate)
end

local function DumpPlates()
    local plates
    local ok = pcall(function() plates = C_NamePlate.GetNamePlates() end)
    if (not ok or not plates) then
        Emit("GetNamePlates 실패")
        return
    end

    Emit("지금 떠 있는 이름표 %d개 (표시는 최대 %d개)", #plates, PLATE_CAP)
    for i = 1, math.min(#plates, PLATE_CAP) do
        local plate = plates[i]
        Emit("  %s type=%s prot=%s forb=%s anchorRes=%s",
            PlateLabel(plate), Try(plate, "GetObjectType"), TryProtected(plate),
            Try(plate, "IsForbidden"), Try(plate, "IsAnchoringRestricted"))
        local okIdx, regForClicks = pcall(function() return plate.RegisterForClicks end)
        Emit("    scripts=%s regForClicks=%s mouse=%s motion=%s click=%s",
            ScriptString(plate), (okIdx and regForClicks) and "yes" or "no",
            Try(plate, "IsMouseEnabled"), Try(plate, "IsMouseMotionEnabled"),
            Try(plate, "IsMouseClickEnabled"))
        Emit("    unit=%s template=%s hitTest=%s",
            Try(plate, "GetUnit"), tostring(rawget(plate, "unitFrameTemplate")),
            Try(plate, "CanChangeHitTestPoints"))

        -- The UnitFrame is the button half of the pair, so it is the candidate if the base
        -- turns out not to take clicks. It comes out of a frame pool and carries no name,
        -- so it is labelled by the field and never asked for one.
        local uf = rawget(plate, "UnitFrame")
        if (uf) then
            Emit("    .UnitFrame type=%s prot=%s forb=%s anchorRes=%s",
                Try(uf, "GetObjectType"), TryProtected(uf),
                Try(uf, "IsForbidden"), Try(uf, "IsAnchoringRestricted"))
            Emit("      scripts=%s mouse=%s motion=%s click=%s disableMouse=%s",
                ScriptString(uf), Try(uf, "IsMouseEnabled"), Try(uf, "IsMouseMotionEnabled"),
                Try(uf, "IsMouseClickEnabled"), tostring(rawget(uf, "disableMouse")))
        else
            Emit("    .UnitFrame 없음 (유닛이 안 붙은 베이스)")
        end
    end
end

-----------------------------------------------------------
-- The wrap test. Only the secure wrapper, and nothing insecure alongside it: a wrapper
-- arriving already proves the frame receives the event, and `SecureHandlerUnwrapScript`
-- takes it back off, so `wrap` and `unwrap` can be repeated without a /reload between them.
-- A `HookScript` here would have answered the same question and could never be removed.
-----------------------------------------------------------

local header
local wrapped = setmetatable({}, { __mode = "k" })
--- Arrivals per key, not a seen flag. **One print and silence afterwards cannot tell "it
--- fires every time" from "it fired once and stopped"**, and that difference is the answer
--- for a wrapper. Every arrival prints, with its running count.
local fired = {}

local function NoteFire(key, label)
    local n = (fired[key] or 0) + 1
    fired[key] = n
    print(format("|cff66ccff[NP]|r %s (%d회째)", label, n))
end

--- What `/debnp wrap` actually put on, in the order it went on, so `/debnp unwrap` can take
--- it back off. The base frames are pooled and live until the client restarts, so a wrapper
--- left behind outlives the question it was asked for.
local installed = {}

local control

--- A button on screen that takes the mouse, so `wrap` always has one frame whose wrapper is
--- obliged to fire. Nothing about it is borrowed: it is created here, sized here and has its
--- mouse turned on here.
local function EnsureControl()
    if (control) then
        return control
    end
    control = CreateFrame("Button", "DebindNamePlateProbeControl", UIParent)
    control:SetSize(160, 28)
    control:SetPoint("CENTER", 0, 200)
    control:EnableMouse(true)
    control:RegisterForClicks("AnyUp", "AnyDown")
    control:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
    control:GetNormalTexture():SetVertexColor(0.2, 0.4, 0.8, 0.8)
    local text = control:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText("NP 대조군")
    return control
end

local function EnsureHeader()
    if (header) then
        return header
    end
    header = CreateFrame("Frame", "DebindNamePlateProbeHeader", UIParent, "SecureHandlerBaseTemplate")
    header:SetScript("OnAttributeChanged", function(_, name, value)
        if (name == "np_hit" and value) then
            NoteFire("보안 " .. tostring(value), "|cff44ff44보안 래퍼 도착|r " .. tostring(value))
        end
    end)
    return header
end

--- **The body depends on nothing in the environment.** A wrapped body runs through
--- `SecureHandler_Other_Execute(header, self, "self", preBody)`, so `self` is the wrapped
--- frame and that is the only name bound. Reaching the header through a global set by
--- `SecureHandlerExecute` is what failed: the body died on its first line, and a body that
--- dies makes `Wrapped_Click` return before the real handler, which is why clicking a
--- nameplate stopped targeting. The frame ref is put on the wrapped frame itself, so the
--- body only ever touches `self`.
---
--- The counter is there so the value differs every time: `SetAttribute` with the value it
--- already holds does not fire `OnAttributeChanged`, and every hit after the first would be
--- swallowed.
--- Set by `/debnp wrap empty`. A body that does nothing cannot fail, so if the wrapped
--- frames still swallow clicks with this on, the body is not what is wrong and the wrapping
--- itself is.
local emptyBody = false

local function SecureBody(what)
    if (emptyBody) then
        return "-- empty"
    end
    return format([[
        np_n = (np_n or 0) + 1
        self:GetFrameRef("np_probe"):SetAttribute("np_hit", "%s #" .. np_n)
    ]], what)
end

--- **A failure here cannot be caught, so it has to be avoided instead.** The whole
--- SecureHandlers API works by setting attributes on an internal frame, and the validation
--- and its `error()` run inside that frame's `OnAttributeChanged`
--- (`SecureHandlers.lua:430`). A script handler's error does not travel back up the call
--- stack, so a `pcall` around the call catches nothing and the message lands in the error
--- window. Blizzard reads unwrap results back through a temp table for the same reason.
---
--- The one failure this probe can see coming is a script type the widget does not have,
--- which `SecureHandlerWrapScript` rejects at `SecureHandlers.lua:501`. `HasScript` answers
--- that here, and a frame that says no is never handed over. Anything that still errors is
--- a cause we did not predict, which is a result and not noise.
local function WrapSecure(frame, script, tag)
    if (wrapped[frame] and wrapped[frame][script]) then
        return "이미"
    end
    local okHas, has = pcall(function() return frame:HasScript(script) end)
    if (not okHas) then
        return "HasScript ERR"
    end
    if (has ~= true) then
        return "없는 타입"
    end
    SecureHandlerSetFrameRef(frame, "np_probe", EnsureHeader())
    SecureHandlerWrapScript(frame, script, EnsureHeader(), SecureBody(tag .. " " .. script))
    wrapped[frame] = wrapped[frame] or {}
    wrapped[frame][script] = true
    tinsert(installed, { frame = frame, script = script })
    return "걸었음"
end

local function RunWrap()
    if (InCombatLockdown()) then
        print("|cff66ccff[NP]|r 전투 중에는 실행하지 않는다")
        return
    end

    local plates
    local ok = pcall(function() plates = C_NamePlate.GetNamePlates() end)
    if (not ok or not plates or #plates == 0) then
        Emit("걸 이름표가 없다. 이름표가 떠 있는 곳에서 다시")
        return
    end

    out = {}
    wipe(fired)
    -- The control, and a frame this file owns rather than one borrowed from elsewhere: a
    -- plain button with the mouse turned on, which has to fire. It is the only thing that
    -- tells "nameplates do not take a wrapper" apart from "this probe's wrapping is wrong",
    -- and without it a silent run means nothing at all.
    Emit("대조군 버튼 enter=%s leave=%s click=%s",
        WrapSecure(EnsureControl(), "OnEnter", "control"),
        WrapSecure(EnsureControl(), "OnLeave", "control"),
        WrapSecure(EnsureControl(), "OnClick", "control"))

    Emit("래퍼 시도: %d개", #plates)

    for i = 1, math.min(#plates, PLATE_CAP) do
        local plate = plates[i]
        -- The base first, because the hit testing lives there (`SetHitTestPoints`,
        -- `GetNamePlateHitTestInsets`) and the UnitFrame is `disableMouse=true`. Blizzard
        -- puts nothing but `OnSizeChanged` on the base, so whether it fires a Lua mouse
        -- script at all is exactly what has never been measured. `WrapSecure` asks
        -- `HasScript` first, so OnClick drops out on its own if the widget has no such type.
        Emit("  %s base enter=%s leave=%s click=%s", PlateLabel(plate),
            WrapSecure(plate, "OnEnter", "base"),
            WrapSecure(plate, "OnLeave", "base"),
            WrapSecure(plate, "OnClick", "base"))
    end

    Emit("이제 이름표에 커서를 올리고 클릭해봐라. 도착할 때마다 찍힌다")
    Emit("래퍼 %d개를 걸었다. 끝나면 /debnp unwrap", #installed)
end

--- Takes back off what `wrap` put on. `SecureHandlerUnwrapScript` removes the **topmost**
--- wrapper, so this is only safe because nothing else wraps a nameplate in a dev session;
--- if something did, the last one on would come off instead of ours. Reverse order for the
--- same reason.
local function RunUnwrap()
    if (InCombatLockdown()) then
        print("|cff66ccff[NP]|r 전투 중에는 실행하지 않는다")
        return
    end

    out = {}
    local count = #installed
    for i = count, 1, -1 do
        local entry = installed[i]
        SecureHandlerUnwrapScript(entry.frame, entry.script)
        if (wrapped[entry.frame]) then
            wrapped[entry.frame][entry.script] = nil
        end
        installed[i] = nil
    end
    Emit("래퍼 %d개 제거", count)
end

-----------------------------------------------------------
-- Report
-----------------------------------------------------------

local function Save()
    DebindDevDB = DebindDevDB or {}
    DebindDevDB.namePlateProbe = { at = date("%Y-%m-%d %H:%M:%S"), lines = out }
end

local function Report()
    out = {}

    local version, build = GetBuildInfo()
    Emit("build=%s (%s) 지금=%s", tostring(version), tostring(build), InstanceType())

    local exists, visible, hidden = ScanTokens()
    Emit("토큰 스캔: 유닛 있는 토큰=%d, 프레임 나오는 것=%d, nil(=forbidden)=%d",
        exists, visible, hidden)

    Emit("세션 집계: 베이스 생성=%d (전투 중 %d), forbidden 생성=%d (전투 중 %d)",
        census.created, census.createdInCombat, census.forbiddenCreated, census.forbiddenInCombat)
    Emit("UnitFrame: 서로 다른 것 %d개, 같은 베이스가 다른 것을 받은 횟수 %d",
        census.unitFrames, census.unitFrameSwaps)

    -- Only present after `wrap`. A key sitting at 1 is the interesting one: it took, it ran,
    -- and then it stopped.
    local anyFire = false
    for key, n in pairs(fired) do
        if (not anyFire) then
            Emit("도착 횟수:")
            anyFire = true
        end
        Emit("  %s = %d", key, n)
    end
    if (#installed > 0 and not anyFire) then
        Emit("도착 횟수: 걸린 래퍼 %d개, 아직 하나도 안 왔다", #installed)
    end

    DumpPlates()

    if (#census.log > 0) then
        Emit("생성 기록 (최대 %d줄):", LOG_CAP)
        for _, line in ipairs(census.log) do
            Emit("  %s", line)
        end
    end

    Save()
    Emit("끝. /debnp last 로 다시 볼 수 있다")
end

local function PrintLast()
    local saved = DebindDevDB and DebindDevDB.namePlateProbe
    if (not saved) then
        print("|cff66ccff[NP]|r 저장된 결과 없음")
        return
    end
    print("|cff66ccff[NP]|r === " .. saved.at .. " ===")
    for _, line in ipairs(saved.lines) do
        print("|cff66ccff[NP]|r " .. line)
    end
end

SLASH_DEBNP1 = "/debnp"
SlashCmdList["DEBNP"] = function(msg)
    msg = strtrim(msg or "")
    if (msg == "last") then
        PrintLast()
    elseif (msg == "wrap") then
        emptyBody = false
        RunWrap()
        Save()
    elseif (msg == "wrap empty") then
        emptyBody = true
        RunWrap()
        Save()
    elseif (msg == "unwrap") then
        RunUnwrap()
        Save()
    else
        Report()
    end
end
