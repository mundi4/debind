local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local CleanupActions = Dev.CleanupActions
local ApplyBindings = Dev.ApplyBindings
local EnableProbes = Dev.EnableProbes
local EvalClickCast = Dev.EvalClickCast
local WaitForEvalAnswer = Dev.WaitForEvalAnswer
local LastWinner = Dev.LastWinner
local ReadRoleMap = Dev.ReadRoleMap
local WaitForRoleMap = Dev.WaitForRoleMap
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local HoverEnter = Dev.HoverEnter
local HoverLeave = Dev.HoverLeave
local WaitForHoverSlot = Dev.WaitForHoverSlot

-- The client behaviour the role map's hook is built on: does `SetAttribute` with a value the
-- frame already holds still raise a **wrapped** `OnAttributeChanged`?
--
-- **Only the game can answer.** It is not documented anywhere, and the headless harness records
-- wrapped bodies rather than running them. It was measured in game on
-- 2026-08-28; this is what will notice the day the client stops doing it.
--
-- If it goes red, the role map stops updating on any layout where the roster did not change, and
-- nothing else says so -- `UnitWatch.lua`'s hook rides the header's last child, and that child is
-- written with the same `nil` on almost every pass.
RegisterTest("Unchanged attribute writes still raise a wrapped handler", {
    description = "SetAttribute with the value already there fires OnAttributeChanged, which the role map's hook needs",
    run = function()
        local NAME = "Unchanged write"

        if InCombatLockdown() then
            return Fail(NAME, "wrapping is blocked in combat")
        end

        local header = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")
        local target = CreateFrame("Frame", nil, nil, "SecureFrameTemplate")

        local fired = 0
        function target:DebindTestRoleProbe()
            fired = fired + 1
        end

        SecureHandlerWrapScript(target, "OnAttributeChanged", header, [[
            self:CallMethod("DebindTestRoleProbe")
        ]])
        AddTeardown(function()
            SecureHandlerUnwrapScript(target, "OnAttributeChanged")
        end)

        -- The first write is a real change, so it is not evidence. The two after it are not.
        target:SetAttribute("debindprobe", "raid1")
        local baseline = fired
        target:SetAttribute("debindprobe", "raid1")
        target:SetAttribute("debindprobe", "raid1")

        if fired <= baseline then
            return Fail(NAME, format("only the changing write fired (%d), so the role map would "
                .. "stop updating whenever the roster held still", fired))
        end

        -- Writing `nil` onto a field that is already absent is the case the tidy loop actually
        -- runs on every child past the ones it filled.
        local before = fired
        target:SetAttribute("debindprobenil", nil)
        target:SetAttribute("debindprobenil", nil)
        if fired <= before then
            return Fail(NAME, "writing nil onto an absent attribute raised nothing")
        end

        return Pass(NAME, format("%d fires for 5 writes", fired))
    end,
})

-- The role headers are the only thing that fills `UnitRoles`, and a header can only hold as many
-- people as it has child frames. Those frames cannot be made during combat, so the rebuild has to
-- have made them already.
--
-- **The hook has to be on the header's highest child.** `configureChildren` writes `unit` on every
-- child it has and the highest one is the last of those writes, so a hook anywhere below it reads
-- a half-placed arrangement. Growing the header moves it, and this is where that lands in a real
-- header rather than a recording.
RegisterTest("A role condition widens the role headers", {
    description = "Asking about a role gives tank/healer/damager a slot per raid member and leaves the hook on the last one",
    run = function()
        local NAME = "Role headers"

        if InCombatLockdown() then
            return Fail(NAME, "growing a header needs the secure handler API")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { role = Constants.ROLE_TANK,
                frameTypes = Constants.FRAMETYPE_ALL } },
        })
        ApplyBindings()

        local seen = {}
        for _, alias in ipairs({ "tank", "healer", "damager" }) do
            local header = DebindPrivate.UnitWatchHeaders[alias]
            if not header then
                return Fail(NAME, alias .. " has no header")
            end
            if not header:IsShown() then
                return Fail(NAME, alias .. " was not shown")
            end

            local count = 0
            while header:GetAttribute("child" .. (count + 1)) do
                count = count + 1
            end
            if count ~= Constants.MAX_ROLE_SLOTS then
                return Fail(NAME, format("%s has %d children, wanted %d",
                    alias, count, Constants.MAX_ROLE_SLOTS))
            end
            if header:GetAttribute("unitsPerColumn") ~= Constants.MAX_ROLE_SLOTS then
                return Fail(NAME, format("%s fills only %s of them",
                    alias, tostring(header:GetAttribute("unitsPerColumn"))))
            end
            seen[#seen + 1] = alias .. "=" .. count
        end

        -- **표가 서 있다는 것이 곧 셋이 다 섰다는 뜻이다.** 헤더 상태만 보면 표가 안 선 채로
        -- 셋이 켜져 있는 경우를 못 잡는데, 그러면 판정이 아예 안 서서 조건이 조용히 통과한다.
        ReadRoleMap()
        local roleMap = WaitForRoleMap()
        if not roleMap then
            return Fail(NAME, "the restricted environment never answered")
        end
        if not roleMap.present then
            return Fail(NAME, "the headers are up but the role map is not")
        end

        return Pass(NAME, table.concat(seen, ", ") .. format(", map=%d", roleMap.count))
    end,
})

-- **표는 셋을 켜기로 정한 리빌드가 세우고 내린다.** 헤더가 저마다 세우면 반쪽 맵이 유효해
-- 보이고, 그때 `unknown`은 "셋이 다 보고도 아무도 안 데려갔다"가 아니라 "덜 봤다"가 된다.
-- 탱커 헤더만 켜진 채로 답을 내면 딜러가 전부 `unknown`으로 떨어져서, [탱커]와 [알 수 없음]을
-- 고른 사용자에게 딜러까지 걸린다.
--
-- **끄는 쪽만 이 순서로 잡힌다.** 켜는 쪽은 위 테스트가 보고, 여기는 조건이 사라졌을 때 표가
-- 실제로 내려가는지 -- 그리고 다시 걸었을 때 되돌아오는지 -- 를 본다.
RegisterTest("Dropping the role condition takes the map down", {
    description = "The role map stands up with the condition and goes with it, so a half-built map never answers",
    run = function()
        local NAME = "Role map lifecycle"

        if InCombatLockdown() then
            return Fail(NAME, "showing and hiding a header needs the secure handler API")
        end

        local function mapPresent()
            ReadRoleMap()
            local roleMap = WaitForRoleMap()
            if not roleMap then
                return nil
            end
            return roleMap.present
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { role = Constants.ROLE_TANK,
                frameTypes = Constants.FRAMETYPE_ALL } },
        })
        ApplyBindings()
        if mapPresent() ~= true then
            return Fail(NAME, "the map never stood up")
        end

        CleanupActions()
        InsertAction({ type = Constants.SPELL, value = 585, key = "BUTTON3" })
        ApplyBindings()
        if mapPresent() ~= false then
            return Fail(NAME, "the map outlived the condition that asked for it")
        end
        for _, alias in ipairs({ "tank", "healer", "damager" }) do
            local header = DebindPrivate.UnitWatchHeaders[alias]
            if header and header:IsShown() then
                return Fail(NAME, alias .. " is still shown with nothing asking about roles")
            end
        end

        CleanupActions()
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { role = Constants.ROLE_HEALER,
                frameTypes = Constants.FRAMETYPE_ALL } },
        })
        ApplyBindings()
        if mapPresent() ~= true then
            return Fail(NAME, "the map did not come back when the condition did")
        end

        return Pass(NAME, "up, down, up")
    end,
})

-- The role axis at the press, without needing anybody else online.
--
-- **Two records that partition the axis.** One asks for `unknown`, the other for the three real
-- roles, so exactly one of them can match whatever the tester's group looks like -- and which one
-- wins is not something this test has to know. What it holds is that **one of them does**: a unit
-- with no row on the map has to read as `unknown` rather than as nothing, and if that fallback
-- goes, neither record matches and the key dies with nobody saying so.
RegisterTest("Role at the press: a unit off the map reads as unknown", {
    description = "One of two records partitioning the role axis wins the click, so the missing-row fallback is real",
    run = function()
        local NAME = "Role at the press"
        local REAL_ROLES = Constants.ROLE_TANK + Constants.ROLE_HEALER
            + Constants.ROLE_DAMAGER

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { role = Constants.ROLE_NONE,
                frameTypes = Constants.FRAMETYPE_ALL } },
        })
        InsertAction({
            type = Constants.SPELL, value = 8936, key = "BUTTON3",
            units = { unitframe = { role = REAL_ROLES, frameTypes = Constants.FRAMETYPE_ALL } },
        })
        ApplyBindings()

        local frame, ferr = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, ferr) end

        HoverEnter(frame)
        AddTeardown(function() HoverLeave(frame) end)
        WaitForHoverSlot(true)

        local ran, rerr = EvalClickCast(frame, 3, 0)
        if not ran then return Fail(NAME, rerr) end
        WaitForEvalAnswer()

        local winner = LastWinner()
        if winner == nil then
            return Fail(NAME, "neither record matched, so the role of a unit with no row on the "
                .. "map came back as neither unknown nor a real role")
        end

        return Pass(NAME, format("record %d took it", winner))
    end,
})
