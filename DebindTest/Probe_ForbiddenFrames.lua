-- Probe_ForbiddenFrames.lua
-- 일회성 프로브: forbidden 프레임 조사(.zzz/forbidden-frames.md)의 게임 확인 배터리.
-- 결론이 나면 파일째로 지우고 TOC에서 한 줄 빼면 된다.
--
-- 사용법:
--   /debforbid         배터리 실행 (전투 밖). 결과는 채팅 + DebindTestDB에 저장
--   /debforbid arena   아레나 프레임을 직접 생성·갱신해서 제보의 크래시 경로를 재현
--                      (아레나 프레임이 taint되므로 확인 후 /reload 권장)
--   /debforbid last    지난 실행 결과 다시 출력
--
-- 답하려는 것:
--   1. 12.1 TargetFrame의 <AuraContainer>와 그 오라 버튼이 명시적 forbidden인가
--   2. 비공개 오라 예약 프레임이 forbidden인가, 마우스 모션을 받는가
--   3. 3.1.4의 SetPropagate walk가 실제 등록 대상 프레임들에서 살아남는가
--   4. forbidden 프레임에서 어떤 getter가 아직 답하는가 (이후 진단 수단 결정)
--
-- The whole battery is read-only except two things that mirror what Debind already does:
-- the 3.1.4-walk replica runs only on frames Debind has actually registered (so the same
-- SetPropagateMouseMotion calls already happened at registration), and the private-aura
-- probe parents Blizzard's reserved frames under a frame this file owns.

local DebindPrivate = _G.DebindPrivate
if (not DebindPrivate) then
    return
end

local out = {}

local function Emit(fmt, ...)
    local line = format(fmt, ...)
    tinsert(out, line)
    print("|cffff9900[Forbid]|r " .. line)
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

--- pcall a zero-arg method and collapse the outcome to one printable token, because on a
--- forbidden frame any of these may throw, and in Midnight any of them may answer a secret.
local function Try(obj, method)
    local okIndex, fn = pcall(function() return obj[method] end)
    if (not okIndex) then
        return "idxERR"
    end
    if (not fn) then
        return "-"
    end
    local ok, v = pcall(fn, obj)
    if (not ok) then
        return "ERR"
    end
    if (IsSecret(v)) then
        return "secret"
    end
    return tostring(v)
end

-- Values from Enum.ForbiddenAspect; kept literal so the probe still runs if the enum moves.
local ASPECTS = {
    { 1, "SetToDefaults" },
    { 2, "ScriptBindings" },
    { 4, "UntrustedScript" },
    { 8, "UntrustedLayout" },
    { 16, "EventReg" },
    { 32, "AlwaysPropagateInput" },
    { 64, "ScriptedInput" },
    { 128, "QueryFocus" },
    { 256, "ChangeAnimTarget" },
    { 512, "RemoveSecretAspects" },
}

local function AspectString(frame)
    local okIndex, fn = pcall(function() return frame.HasAnyForbiddenAspects end)
    if (not okIndex or not fn) then
        return "?"
    end
    local names = {}
    for _, a in ipairs(ASPECTS) do
        local ok, v = pcall(fn, frame, a[1])
        if (ok and v == true) then
            tinsert(names, a[2])
        elseif (ok and IsSecret(v)) then
            tinsert(names, a[2] .. "?secret")
        end
    end
    return #names > 0 and table.concat(names, ",") or "none"
end

--- A printable name for a child we may not be allowed to ask. GetName can throw on a
--- forbidden frame; the parent is walkable, so fall back to the parentKey that holds it.
local function ChildLabel(parent, child, index)
    local ok, name = pcall(function() return child:GetName() end)
    if (ok and type(name) == "string" and name ~= "") then
        return name
    end
    local okScan, key = pcall(function()
        for k, v in pairs(parent) do
            if (v == child and type(k) == "string") then
                return k
            end
        end
    end)
    if (okScan and key) then
        return "." .. key
    end
    return "#" .. index
end

-----------------------------------------------------------
-- Read-only census: find every forbidden descendant, touch nothing
-----------------------------------------------------------

local function NewStats()
    return { visited = 0, forbidden = 0, hidden = 0, hits = {}, errors = {} }
end

local function Census(frame, path, stats, depth)
    depth = depth or 0
    local kids
    local okC = pcall(function() kids = { frame:GetChildren() } end)
    if (not okC) then
        tinsert(stats.errors, path .. ": GetChildren ERR")
        return
    end

    -- 12.1's Forbidden Partition may hide children from insecure GetChildren entirely.
    -- GetNumChildren disagreeing with what GetChildren handed back is the direct proof.
    local okN, num = pcall(function() return frame:GetNumChildren() end)
    if (okN and not IsSecret(num) and type(num) == "number" and num ~= #kids) then
        stats.hidden = stats.hidden + (num - #kids)
        tinsert(stats.errors, format("%s: GetNumChildren=%d, GetChildren=%d (숨은 자식 %d)",
            path, num, #kids, num - #kids))
    end

    for i = 1, #kids do
        local child = kids[i]
        if (IsSecret(child)) then
            -- GetChildren handed back a secret instead of a frame: the class of failure
            -- the 3.1.4 IsForbidden guard cannot catch.
            tinsert(stats.errors, path .. "#" .. i .. ": SECRET child")
        else
            local label = path .. "/" .. ChildLabel(frame, child, i)
            local okF, forb = pcall(function() return child:IsForbidden() end)
            if (not okF) then
                tinsert(stats.errors, label .. ": IsForbidden ERR")
            elseif (forb == true) then
                stats.forbidden = stats.forbidden + 1
                -- depth/siblings printed to match against the 3.1.3 stack (재귀 4겹, n=10)
                tinsert(stats.hits, format("%s [d=%d n=%d] type=%s shown=%s mouse=%s motion=%s aspects=%s",
                    label, depth + 1, #kids, Try(child, "GetObjectType"), Try(child, "IsShown"),
                    Try(child, "IsMouseEnabled"), Try(child, "IsMouseMotionEnabled"),
                    AspectString(child)))
            else
                stats.visited = stats.visited + 1
                Census(child, label, stats, depth + 1)
            end
        end
    end
end

-----------------------------------------------------------
-- The 3.1.4 walk, verbatim (FrameRegistry.lua SetPropagate) — run under pcall to learn
-- whether the guard actually survives the frames it meets today.
-----------------------------------------------------------

local function SetPropagate314(...)
    local n = select("#", ...)
    for i = 1, n do
        local frame = select(i, ...)
        if (frame and not (frame.IsForbidden and frame:IsForbidden())) then
            if (frame.SetPropagateMouseMotion) then
                frame:SetPropagateMouseMotion(true)
            end
            if (frame.GetChildren) then
                SetPropagate314(frame:GetChildren())
            end
        end
    end
end

--- The same traversal, but every frame is handled under its own pcall, so the frame that
--- passes the 3.1.4 IsForbidden guard and still blows up gets *identified* (with the new
--- 12.1 visibility APIs sampled) instead of killing the walk. Found live in an arena:
--- Grid2 buttons carried children that answered IsForbidden()=false yet threw the
--- forbidden-object error from SetPropagateMouseMotion.
local function DiagWalk(parent, path, report, depth)
    local kids = {}
    if (not pcall(function() kids = { parent:GetChildren() } end)) then
        tinsert(report, path .. ": GetChildren ERR")
        return
    end
    for i = 1, #kids do
        local child = kids[i]
        if (IsSecret(child)) then
            tinsert(report, format("%s#%d: SECRET child", path, i))
        else
            local label = path .. "/" .. ChildLabel(parent, child, i)
            local guardOk, guardVal = pcall(function()
                return child.IsForbidden and child:IsForbidden()
            end)
            if (not guardOk) then
                tinsert(report, label .. ": IsForbidden 자체가 던짐")
            elseif (guardVal ~= true) then
                local okS, errS = pcall(function()
                    if (child.SetPropagateMouseMotion) then
                        child:SetPropagateMouseMotion(true)
                    end
                end)
                if (not okS) then
                    tinsert(report, format(
                        "%s [d=%d n=%d] 가드 통과 후 폭발 | access=%s ctx=%s type=%s shown=%s motion=%s aspects=%s | %s",
                        label, depth + 1, #kids,
                        Try(child, "HasAccessConstraints"), Try(child, "CanBeAccessedInContext"),
                        Try(child, "GetObjectType"), Try(child, "IsShown"),
                        Try(child, "IsMouseMotionEnabled"), AspectString(child), tostring(errS)))
                else
                    DiagWalk(child, label, report, depth + 1)
                end
            end
        end
    end
end

-----------------------------------------------------------
-- Private-aura container probe: stand up our own anchor so Blizzard reserves its
-- forbidden frames under a frame we own. No arena, no raid needed.
-----------------------------------------------------------

local paHolder
local paAnchorID

-- Everything PrivateAuraAnchorContainerMixin:ReadContainerSettings reads. Numbers where
-- their code does arithmetic, false where it branches; anything missing errors inside
-- their secure environment, not ours.
local function ApplyContainerAttributes(holder)
    local orgType = (Enum.RaidAuraOrganizationType and Enum.RaidAuraOrganizationType.Legacy) or 0
    local dispelOff = (Enum.RaidDispelDisplayType and Enum.RaidDispelDisplayType.Disabled) or 0
    holder:SetAttribute("max-buffs", 2)
    holder:SetAttribute("max-debuffs", 2)
    holder:SetAttribute("max-dispel-debuffs", 1)
    holder:SetAttribute("aura-organization-type", orgType)
    holder:SetAttribute("always-hide-duration", true)
    holder:SetAttribute("set-aura-size-to-icon-size", true)
    holder:SetAttribute("display-larger-role-specific-debuffs", false)
    holder:SetAttribute("dispel-indicator-overlay-type", 0)
    holder:SetAttribute("dispel-indicator-overlay-animation", false)
    holder:SetAttribute("show-big-defensive", false)
    holder:SetAttribute("big-defensive-size", 20)
    holder:SetAttribute("power-bar-used-height", 0)
    holder:SetAttribute("display-only-dispellable-debuffs", false)
    holder:SetAttribute("ignore-buffs", false)
    holder:SetAttribute("ignore-debuffs", false)
    holder:SetAttribute("ignore-dispel-debuffs", false)
    holder:SetAttribute("dispel-indicator-option", dispelOff)
    holder:SetAttribute("debuff-size", 20)
    holder:SetAttribute("buff-size", 20)
    holder:SetAttribute("debuff-border-scale", 1)
    holder:SetAttribute("buff-border-scale", 1)
end

local function RunPrivateAuraProbe(onDone)
    if (not (C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor)) then
        Emit("PA-probe: C_UnitAuras.AddPrivateAuraAnchor 없음")
        onDone()
        return
    end

    if (not paHolder) then
        paHolder = CreateFrame("Frame", "DebindForbidProbeFrame", UIParent)
        paHolder:SetSize(64, 64)
        paHolder:SetPoint("CENTER")
        paHolder:Hide()
    end
    ApplyContainerAttributes(paHolder)

    -- The args schema drifted between versions: 12.0.7 requires
    -- showCountdownFrame/showCountdownNumbers, 12.1 renamed them to
    -- showCooldownFrame/showCooldownEdge (+showDispelIcon). Unknown extra keys are
    -- ignored by the marshaler, so each variant carries everything it might need.
    local iconInfo = {
        iconAnchor = {
            point = "CENTER",
            relativeTo = paHolder,
            relativePoint = "CENTER",
            offsetX = 0,
            offsetY = 0,
        },
        iconWidth = 20,
        iconHeight = 20,
        borderScale = 1,
    }
    local variants = {
        {
            name = "12.1",
            args = {
                unitToken = "player", auraIndex = 1, parent = paHolder,
                showCooldownFrame = false, showCooldownEdge = false,
                showCountdownNumbers = false, showDispelIcon = false,
                isContainer = true, iconInfo = iconInfo,
            },
        },
        {
            name = "12.0",
            args = {
                unitToken = "player", auraIndex = 1, parent = paHolder,
                showCountdownFrame = false, showCountdownNumbers = false,
                isContainer = true, iconInfo = iconInfo,
                iconWidth = 20, iconHeight = 20, borderScale = 1,
            },
        },
    }

    local anchorID, lastErr
    for _, variant in ipairs(variants) do
        local ok, result = pcall(C_UnitAuras.AddPrivateAuraAnchor, variant.args)
        if (ok and result) then
            anchorID = result
            Emit("PA-probe: 앵커 등록됨 (스키마 %s)", variant.name)
            break
        end
        lastErr = tostring(result)
    end
    if (not anchorID) then
        Emit("PA-probe: AddPrivateAuraAnchor 실패: %s", lastErr or "?")
        onDone()
        return
    end
    paAnchorID = anchorID

    -- The watcher reserves frames synchronously but lays out on a deferred Clean
    -- (C_Timer.After(0) on their side), so give it a beat before reading.
    C_Timer.After(0.8, function()
        local stats = NewStats()
        Census(paHolder, "PAProbe", stats)
        local okN, num = pcall(function() return paHolder:GetNumChildren() end)
        Emit("PA-probe: 자식(비forbidden 경유 포함) visited=%d forbidden=%d numchildren=%s",
            stats.visited, stats.forbidden, okN and tostring(num) or "ERR")
        for _, line in ipairs(stats.hits) do
            Emit("  %s", line)
        end
        for _, line in ipairs(stats.errors) do
            Emit("  err: %s", line)
        end

        -- The one thing the previous session could not manufacture: the 3.1.4 guard
        -- meeting real forbidden frames. Our own frame, so the setter is fair game.
        local okW, errW = pcall(SetPropagate314, paHolder:GetChildren())
        Emit("PA-probe walk(3.1.4): %s", okW and "ok" or ("ERR " .. tostring(errW)))

        pcall(C_UnitAuras.RemovePrivateAuraAnchor, paAnchorID)
        paAnchorID = nil
        onDone()
    end)
end

-----------------------------------------------------------
-- The battery
-----------------------------------------------------------

local function ResolveTargetAuras()
    local content = TargetFrame and TargetFrame.TargetFrameContent
    local main = content and content.TargetFrameContentMain
    return main and main.Auras
end

local function Finish()
    DebindTestDB = DebindTestDB or {}
    DebindTestDB.forbiddenProbe = { at = date("%Y-%m-%d %H:%M:%S"), lines = out }
    Emit("끝. /debforbid last 로 다시 볼 수 있다")
end

local function Run()
    if (InCombatLockdown()) then
        print("|cffff9900[Forbid]|r 전투 중에는 실행하지 않는다")
        return
    end
    out = {}

    -- 1. Environment
    local version, build = GetBuildInfo()
    Emit("build=%s (%s)", tostring(version), tostring(build))
    if (GetBuildOption) then
        local ok, v = pcall(GetBuildOption, "RestrictedAuraAPI")
        Emit("GetBuildOption(RestrictedAuraAPI)=%s", ok and tostring(v) or ("ERR " .. tostring(v)))
    else
        Emit("GetBuildOption 없음")
    end

    -- 2. The 12.1 target-frame aura container, asked directly
    local auras = ResolveTargetAuras()
    if (auras) then
        Emit("TargetFrame...Auras: forbidden=%s aspects=%s type=%s motion=%s",
            Try(auras, "IsForbidden"), AspectString(auras),
            Try(auras, "GetObjectType"), Try(auras, "IsMouseMotionEnabled"))
    else
        Emit("TargetFrame...Auras: 경로 없음 (12.1 이전이거나 구조 변경)")
    end

    -- 3. Read-only census over everything Debind tracks (arena에서 실행하면 아레나
    --    프레임도 여기 포함된다). 대상을 잡고 오라가 보이는 상태로 한 번 더 돌리면
    --    오라 버튼까지 세어진다.
    local censusTotal = 0
    for frame, category in pairs(DebindPrivate.blizzardFrames or {}) do
        if (category) then
            censusTotal = censusTotal + 1
            local name = frame.GetName and frame:GetName() or tostring(frame)
            local stats = NewStats()
            Census(frame, name, stats)
            if (stats.forbidden > 0 or #stats.errors > 0) then
                Emit("census %s: visited=%d forbidden=%d", name, stats.visited, stats.forbidden)
                for _, line in ipairs(stats.hits) do
                    Emit("  %s", line)
                end
                for _, line in ipairs(stats.errors) do
                    Emit("  err: %s", line)
                end
            end
        end
    end
    Emit("census: %d개 프레임을 훑음 (forbidden 없는 프레임은 조용히 통과)", censusTotal)

    -- 4. The diagnostic walk over frames Debind actually registered — same setter calls
    --    registration already made, but per-frame pcall, so a frame that passes the
    --    3.1.4 guard and still throws gets identified instead of aborting the walk.
    local diag = {}
    local walked = 0
    for frame, entry in pairs(DebindPrivate.ccframes or {}) do
        if (entry) then
            walked = walked + 1
            local name = frame.GetName and frame:GetName() or tostring(frame)
            DiagWalk(frame, name, diag, 0)
        end
    end
    Emit("walk(진단): 등록 프레임 %d개, 가드 뚫린 지점 %d개", walked, #diag)
    local DIAG_CAP = 12
    for i = 1, math.min(#diag, DIAG_CAP) do
        Emit("  %s", diag[i])
    end
    if (#diag > DIAG_CAP) then
        Emit("  ...외 %d건 (전체는 DebindTestDB에 저장됨)", #diag - DIAG_CAP)
        for i = DIAG_CAP + 1, #diag do
            tinsert(out, "  " .. diag[i])
        end
    end

    -- 5. Private-aura reserved frames, on a frame of our own
    RunPrivateAuraProbe(Finish)
end

--- Reproduces the reported arena crash path without an arena: create/refresh
--- CompactArenaFrame ourselves. RefreshMembers calls SetUnit (private-aura container
--- reserves its forbidden children) *before* SetUpFrame (our hook -> registration walk),
--- which is the ordering that killed 3.1.3. Under pcall, so a hole in the 3.1.4 guard
--- prints instead of erroring.
---
--- Taints the arena frames it touches - fine on a test character, /reload afterwards.
local function RunArenaProbe()
    if (InCombatLockdown()) then
        print("|cffff9900[Forbid]|r 전투 중에는 실행하지 않는다")
        return
    end
    out = {}

    if (not CompactArenaFrame and not CompactArenaFrame_Generate) then
        Emit("arena: CompactArenaFrame도 Generate도 없음")
        Finish()
        return
    end
    if (not CompactArenaFrame) then
        local ok, err = pcall(CompactArenaFrame_Generate)
        if (not ok) then
            Emit("arena: Generate ERR %s", tostring(err))
            Finish()
            return
        end
        Emit("arena: CompactArenaFrame 생성됨")
    else
        Emit("arena: CompactArenaFrame 이미 있음")
    end

    -- The crash path itself. SetUnit("arena1"..) attaches forbidden children even for
    -- units that do not exist, then SetUpFrame fires Debind's hook and the walk.
    local okR, errR = pcall(function() CompactArenaFrame:RefreshMembers() end)
    if (okR) then
        Emit("arena: RefreshMembers ok - 훅+walk까지 안 터짐 (3.1.4 가드 실전 생존)")
    else
        Emit("arena: RefreshMembers ERR %s", tostring(errR))
    end

    local frames = {}
    for _, f in ipairs(CompactArenaFrame.memberUnitFrames or {}) do tinsert(frames, f) end
    for _, f in ipairs(CompactArenaFrame.petUnitFrames or {}) do tinsert(frames, f) end

    for _, f in ipairs(frames) do
        local name = (f.GetName and f:GetName()) or tostring(f)
        local stats = NewStats()
        Census(f, name, stats)
        -- ccframes tells whether Debind's hook actually registered it; the queue length
        -- tells whether registration got deferred instead (the reload-in-combat theory).
        local reg = DebindPrivate.ccframes and DebindPrivate.ccframes[f]
        Emit("arena census %s: visited=%d forbidden=%d hidden=%d 등록=%s",
            name, stats.visited, stats.forbidden, stats.hidden,
            reg and "ccframes" or tostring(reg))
        for _, line in ipairs(stats.hits) do
            Emit("  %s", line)
        end
        for _, line in ipairs(stats.errors) do
            Emit("  err: %s", line)
        end
    end
    Emit("arena: RegisterQueue=%d RegisterClickQueue=%d",
        #(DebindPrivate.RegisterQueue or {}), #(DebindPrivate.RegisterClickQueue or {}))
    Emit("주의: 아레나 프레임이 taint됐다 - 확인 끝나면 /reload")
    Finish()
end

local function PrintLast()
    local saved = DebindTestDB and DebindTestDB.forbiddenProbe
    if (not saved) then
        print("|cffff9900[Forbid]|r 저장된 결과 없음")
        return
    end
    print("|cffff9900[Forbid]|r === " .. saved.at .. " ===")
    for _, line in ipairs(saved.lines) do
        print("|cffff9900[Forbid]|r " .. line)
    end
end

SLASH_DEBFORBID1 = "/debforbid"
SlashCmdList["DEBFORBID"] = function(msg)
    msg = strtrim(msg or "")
    if (msg == "last") then
        PrintLast()
    elseif (msg == "arena") then
        RunArenaProbe()
    else
        Run()
    end
end
