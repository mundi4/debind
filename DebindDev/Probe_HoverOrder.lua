-- Probe_HoverOrder.lua
-- One-shot probe. Questions:
--   1. Within one frame, does SecureStateDriverManager's OnUpdate (where the beat runs) come
--      before or after a unit frame's OnEnter / OnLeave?
--   2. Crossing onto the next frame, do the leave and the enter land in the same frame, and with
--      a gap between the frames, for how many frames is nothing entered?
--   3. Does UPDATE_MOUSEOVER_UNIT arrive before the manager's OnUpdate in the enter's frame, and
--      does the manager then resolve its drivers in that same frame, whatever `updatetime` is?
--   4. A leave with no enter in its frame: does the manager resolve in that frame?
--   5. Crossing from one cell to the next, both on the same unit: does UPDATE_MOUSEOVER_UNIT fire
--      at all? Entering a cell from outside the grid is the control: the unit appears there.
-- Delete the file and its TOC line once answered.
--
--   /debhover [gap]   start (gap in pixels between the grid's cells, default 0) / stop.
--                     Stopping prints the totals.
--
-- Tokens: E enter, L leave, M UPDATE_MOUSEOVER_UNIT, T the manager resolved a driver of ours,
-- U the manager's OnUpdate finished.
--
-- GetTime() is the frame's start time and holds within a frame (Probe_FrameBoundary.lua), so
-- tokens sharing a GetTime() share a frame, and the order they arrive in is the order within it.
-- U is a post-hook, so a T the manager resolves in its OnUpdate arrives just before that frame's U.
-- T is BeatSignal.lua's control driver: a constant "a" the handler puts back to 0, so the manager
-- writes it, and T fires, on every resolve it does.

local VERSION = "v5"
local CELL_W, CELL_H = 90, 45
local on = false
local hooked = {}
local cells, isCell = {}, {}
local container
local frameTime, tokens = nil, {}
local frameNo = 0
local pending -- the leave not yet followed by an enter: { frame, from, outside }
local pendingM -- frameNo of an M whose frame had no T
local pendingCross -- frameNo of a cell-to-cell crossing whose frame had no M
local stats

local function Reset()
    stats = {
        before = { E = 0, L = 0, M = 0 }, after = { E = 0, L = 0, M = 0 }, noUpdate = { E = 0, L = 0, M = 0 },
        orders = {},
        same = { grid = 0, other = 0 },
        apart = { grid = {}, other = {} },
        outside = 0,
        -- frames from an M to the first T: "0" is the same frame
        mToT = {},
        enterNoM = 0,
        leaveOnlyT = 0, leaveOnlyNoT = 0,
        ticks = 0,
        -- cell to cell in one frame (L and E both on cells): M in that frame, in the next two, or none
        cross = { same = 0, later = 0, none = 0 },
        -- a cell entered with no leave in the frame and the cursor coming from outside the grid
        fromOutside = { M = 0, noM = 0 },
    }
    frameTime, tokens, frameNo, pending, pendingM, pendingCross = nil, {}, 0, nil, nil, nil
end

local function Where(name)
    return isCell[name] and "grid" or "other"
end

local function Bump(t, k)
    t[k] = (t[k] or 0) + 1
end

local function Flush()
    frameNo = frameNo + 1
    local updateAt
    local has = {}
    for i, t in ipairs(tokens) do
        has[t[1]] = true
        if (t[1] == "U" and not updateAt) then
            updateAt = i
        end
    end
    if (has.T) then
        stats.ticks = stats.ticks + 1
        if (pendingM) then
            local d = frameNo - pendingM
            Bump(stats.mToT, d >= 5 and "5+" or tostring(d))
            pendingM = nil
        end
    end
    if (has.M) then
        if (has.T) then
            Bump(stats.mToT, "0")
        elseif (not pendingM) then
            pendingM = frameNo
        end
    end
    if (has.E and not has.M) then
        stats.enterNoM = stats.enterNoM + 1
    end

    local leftCell, enteredCell = false, false
    for _, t in ipairs(tokens) do
        if (t[1] == "L" and isCell[t[2]]) then
            leftCell = true
        elseif (t[1] == "E" and isCell[t[2]]) then
            enteredCell = true
        end
    end
    if (pendingCross) then
        if (has.M) then
            stats.cross.later = stats.cross.later + 1
            pendingCross = nil
        elseif (frameNo - pendingCross > 2) then
            stats.cross.none = stats.cross.none + 1
            pendingCross = nil
        end
    end
    if (leftCell and enteredCell) then
        if (pendingCross) then
            stats.cross.none = stats.cross.none + 1
        end
        if (has.M) then
            stats.cross.same = stats.cross.same + 1
            pendingCross = nil
        else
            pendingCross = frameNo
        end
    elseif (enteredCell and not has.L and (not pending or pending.outside)) then
        Bump(stats.fromOutside, has.M and "M" or "noM")
    end
    if (has.L and not has.E) then
        if (has.T) then
            stats.leaveOnlyT = stats.leaveOnlyT + 1
        else
            stats.leaveOnlyNoT = stats.leaveOnlyNoT + 1
        end
    end

    local text, any, leftHere = {}, false, false
    for i, t in ipairs(tokens) do
        text[#text + 1] = t[2] and (t[1] .. ":" .. t[2]) or t[1]
        local k = t[1]
        if (k == "E" or k == "L" or k == "M") then
            any = true
            if (not updateAt) then
                Bump(stats.noUpdate, k)
            elseif (i < updateAt) then
                Bump(stats.before, k)
            else
                Bump(stats.after, k)
            end
        end
        if (k == "L") then
            leftHere = true
            pending = { frame = frameNo, from = t[2], outside = false }
        elseif (k == "E" and pending) then
            local where = Where(pending.from)
            if (leftHere) then
                stats.same[where] = stats.same[where] + 1
            elseif (where == "grid" and pending.outside) then
                stats.outside = stats.outside + 1
            else
                local gap = frameNo - pending.frame
                Bump(stats.apart[where], gap >= 5 and "5+" or tostring(gap))
            end
            pending = nil
        end
    end
    if (any) then
        local order = table.concat(text, " ")
        local shape = order:gsub(":%S+", "")
        Bump(stats.orders, shape)
        print(format("|cffff9900[HoverOrder]|r frame %d  %s", frameNo, order))
    end
    wipe(tokens)
end

local function Token(kind, name)
    if (not on) then
        return
    end
    local now = GetTime()
    if (frameTime ~= now) then
        if (frameTime) then
            Flush()
        end
        frameTime = now
    end
    tokens[#tokens + 1] = { kind, name }
end

local function NameOf(frame)
    return frame:GetName() or tostring(frame):sub(-6)
end

local function OnEnter(frame)
    Token("E", NameOf(frame))
end

local function OnLeave(frame)
    Token("L", NameOf(frame))
end

-- Every protected button carrying a unit: Blizzard's, Grid2's, VuhDo's, whatever is loaded.
-- HookScript cannot be undone; the hooks go quiet when the probe is off and leave on /reload.
local function HookUnitFrames()
    local count = 0
    local f = EnumerateFrames()
    while (f) do
        if (not hooked[f] and not isCell[f:GetName() or ""]) then
            local ok, isUnitButton = pcall(function()
                return not f:IsForbidden() and f:IsObjectType("Button") and f:IsProtected()
                    and f:GetAttribute("unit") ~= nil
            end)
            if (ok and isUnitButton) then
                f:HookScript("OnEnter", OnEnter)
                f:HookScript("OnLeave", OnLeave)
                hooked[f] = true
                count = count + 1
            end
        end
        f = EnumerateFrames(f)
    end
    return count
end

-- A 2x2 grid of unit buttons on `player`, `gap` pixels apart, so the client gives them a mouseover
-- (question 3) the way it does a raid frame. The container covers the cells and the gaps, so a
-- leave followed by frames outside it is a trip out, not a gap crossed.
local function ShowGrid(gap)
    if (not container) then
        container = CreateFrame("Frame", "DebindProbeHoverGrid", UIParent)
        container:SetPoint("CENTER")
        for i = 1, 4 do
            local b = CreateFrame("Button", "DebindProbeHoverCell" .. i, container, "SecureUnitButtonTemplate")
            b:SetAttribute("unit", "player")
            b:SetSize(CELL_W, CELL_H)
            local tex = b:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints()
            tex:SetColorTexture(i % 2 == 1 and 0.2 or 0.35, 0.3, (i <= 2) and 0.5 or 0.3, 0.9)
            local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("CENTER")
            label:SetText("cell " .. i)
            b:EnableMouse(true)
            b:HookScript("OnEnter", OnEnter)
            b:HookScript("OnLeave", OnLeave)
            cells[i] = b
            isCell[b:GetName()] = true
        end
    end
    container:SetSize(CELL_W * 2 + gap, CELL_H * 2 + gap)
    for i, b in ipairs(cells) do
        b:ClearAllPoints()
        local x = (i % 2 == 1) and 0 or (CELL_W + gap)
        local y = (i <= 2) and 0 or -(CELL_H + gap)
        b:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
    end
    container:Show()
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function()
    Token("M")
end)

local tickFrame = CreateFrame("Frame")
tickFrame:SetScript("OnAttributeChanged", function(self, name, value)
    if (name == "state-tick" and value ~= 0) then
        Token("T")
        self:SetAttribute("state-tick", 0)
    end
end)

local function Buckets(t, keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = format("%s:%d", k, t[k] or 0)
    end
    return table.concat(parts, "  ")
end

local managerHooked = false
local managerEventOurs = false
local gapNow = 2

SLASH_DEBHOVER1 = "/debhover"
SlashCmdList["DEBHOVER"] = function(msg)
    if (not on) then
        if (InCombatLockdown()) then
            print("|cffff9900[HoverOrder]|r 전투 중에는 시작하지 않는다.")
            return
        end
        if (not managerHooked) then
            SecureStateDriverManager:HookScript("OnUpdate", function()
                Token("U")
                if (on and pending and container and not container:IsMouseOver()) then
                    pending.outside = true
                end
            end)
            managerHooked = true
        end
        -- Debind puts this event on the manager only where a column reads `mouseover`.
        if (not SecureStateDriverManager:IsEventRegistered("UPDATE_MOUSEOVER_UNIT")) then
            SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
            managerEventOurs = true
        end
        gapNow = tonumber(msg) or 0
        Reset()
        local count = HookUnitFrames()
        ShowGrid(gapNow)
        eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        on = true
        RegisterAttributeDriver(tickFrame, "state-tick", "a")
        print(format("|cffff9900[HoverOrder]|r %s 켰다. 칸 사이 틈 %dpx, 개체창 %d개에 걸었다. 끄려면 /debhover",
            VERSION, gapNow, count))
    else
        if (frameTime) then
            Flush()
        end
        if (pendingCross) then
            stats.cross.none = stats.cross.none + 1
            pendingCross = nil
        end
        on = false
        UnregisterAttributeDriver(tickFrame, "state-tick")
        eventFrame:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
        if (managerEventOurs and not InCombatLockdown()) then
            SecureStateDriverManager:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
            managerEventOurs = false
        end
        container:Hide()
        local s = stats
        print(format("|cffff9900[HoverOrder]|r %s 껐다. 칸 사이 틈 %dpx, 매니저가 드라이버를 푼 프레임 %d / 전체 %d",
            VERSION, gapNow, s.ticks, frameNo))
        for _, k in ipairs({ "E", "L", "M" }) do
            print(format("  %s: 매니저 앞 %d / 뒤 %d / 매니저 없는 프레임 %d", k, s.before[k], s.after[k], s.noUpdate[k]))
        end
        print(format("  M 뒤 매니저가 푼 프레임까지 (0 = 같은 프레임)  %s", Buckets(s.mToT, { "0", "1", "2", "3", "4", "5+" })))
        print(format("  칸에서 옆 칸으로 (같은 유닛): M 같은 프레임 %d / 두 프레임 안에 늦게 %d / 안 옴 %d",
            s.cross.same, s.cross.later, s.cross.none))
        print(format("  격자 밖에서 칸으로 (대조군): M 옴 %d / 안 옴 %d", s.fromOutside.M or 0, s.fromOutside.noM or 0))
        print(format("  M 없이 온 enter %d", s.enterNoM))
        print(format("  enter 없는 leave 프레임: 그 프레임에 매니저가 품 %d / 안 품 %d", s.leaveOnlyT, s.leaveOnlyNoT))
        print(format("  칸에서 칸: 같은 프레임 %d / 칸 밖에 나갔다 옴 %d", s.same.grid, s.outside))
        print(format("  칸에서 칸: 다른 프레임, 사이 프레임 수별  %s", Buckets(s.apart.grid, { "1", "2", "3", "4", "5+" })))
        print(format("  진짜 개체창: 같은 프레임 %d / 다른 프레임  %s", s.same.other, Buckets(s.apart.other, { "1", "2", "3", "4", "5+" })))
        for shape, n in pairs(s.orders) do
            print(format("  순서 %-20s %d", shape, n))
        end
    end
end
