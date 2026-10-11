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
local ApplyBindings = Dev.ApplyBindings
local MakeTestUnitFrame = Dev.MakeTestUnitFrame
local FreshNamedFrame = Dev.FreshNamedFrame
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local GetHoverUnit = Dev.GetHoverUnit
local FakeHeader = Dev.FakeHeader

-----------------------------------------------------------
-- Test Cases: standing on top of another addon's wrappers
--
-- `standing-on-top-of-foreign-wrappers.md`. The order of the chain and what each
-- script's gate does are headless (`tests/reassemble_spec.lua`); what needs the client is
-- everything the shim cannot be: that the sandbox accepts `RunFor` onto another header's handle at
-- all, that a key another engine binds from inside its own body still reaches the binding table,
-- and that two engines fighting for the top stop rather than filling the C stack.
--
-- **`OnLeave` is what these drive, and that is not a choice.** Everything `Reassemble` takes off a
-- frame goes straight back on, so the enter and click chains are Blizzard's to walk and a real
-- cursor crossing a real frame is the only thing that walks them (`RunWrappedEnter` says why). The
-- one body we run ourselves is the leave body the client can no longer reach, and that one is
-- reachable from here.
--
-- **The other addon is one fake header and nothing else.** Standing a real unit frame pack up
-- would make the run depend on which pack is installed, and every call it would make is one of
-- these four.
-----------------------------------------------------------

--- Runs our own body for one of the two hover scripts on this frame.
---
--- **The wrapped script itself cannot be fired from here, and that is settled rather than
--- suspected.** Every pre body in the chain reaches `CallRestrictedClosure`, which carries
--- `if (not issecure()) then error("Cannot call restricted closure from insecure code") end`
--- (`RestrictedExecution.lua`). `issecure()` is true only where the client called the handler from
--- C, which for these scripts means a real cursor crossing a real frame. `IsWrapEligible` is not
--- the gate -- it is `(not InCombatLockdown()) or frame:IsProtected()` and says nothing about who
--- called. **`securecall` cannot lift it and never could**: it keeps a callee's taint off the
--- caller, and clearing the caller's taint on the way in is the one thing it must not do, or the
--- whole idea of taint would be one call away from nothing. It is not an error trap either --
--- Blizzard writes `securecall(pcall, ...)` wherever it wants one.
---
--- **So this goes in through the door the rest of the kit already uses.** A snippet reached by
--- `SecureHandlerExecute` runs secure, because the client invokes the attribute handler itself, and
--- from inside it `RunFor` is as secure as the wrapper would have been.
---
--- **Enter runs our body alone, because that is all our wrapper holds.** Anything another addon
--- put on that script is a wrapper of its own further down the chain, and reaching it needs the
--- cursor.
local function RunWrappedEnter(frame)
    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_hover", frame)
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        local button = self:GetFrameRef("debindtest_hover")
        self:RunFor(button, self:GetAttribute("setup_onenter"))
    ]])
end

--- Leave runs what the wrapper carries, which is our body and then the one leave body the client
--- can no longer reach.
---
--- **The two return values are honoured** rather than the post being called unconditionally. The
--- client runs a post body only where the pre answered a second value, and one of the cases below
--- exists to catch us failing to answer with one.
---
--- **`message` is named for our post the way the client names it.** `Wrapped_OnLeave` compiles a
--- post with the signature `self,message`; `RunFor` compiles with `self,...`, so without the line
--- in front our own body would read `message` as a global and hand the foreign post a nil. This is
--- the same prologue `FrameRegistry.lua` puts in front of the foreign body for the same reason.
local function RunWrappedLeave(frame)
    SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_hover", frame)
    SecureHandlerExecute(DebindPrivate.BindingDriver, [[
        local button = self:GetFrameRef("debindtest_hover")
        local allow, message = self:RunFor(button, self:GetAttribute("setup_onleave_wrap"))
        if (allow ~= false and message ~= nil) then
            self:RunFor(button, "local message = ...\n" .. self:GetAttribute("setup_onleave_post"), message)
        end
    ]])
end

--- The other addon's header. Its pre bodies bind a key of its own and write a global into its own
--- managed environment, which is the pair of things a replay could get wrong: the key says the
--- body ran, and the environment says it ran in the right one.
local FAKE_ENTER = [[
    fake_hovered = self
    control:SetBindingClick(true, "SHIFT-F", self:GetName(), "fake")
]]

local FAKE_LEAVE = [[
    fake_hovered = nil
    control:ClearBinding("SHIFT-F")
]]

--- Reads `fake_hovered` out of the fake header's **own** environment. Asked there rather than of
--- anything of ours: a value in one of our tables would not say whose environment ran the body,
--- and that is the half `RunFor` on their handle is there to buy.
local function FakeHovered()
    local header = FakeHeader()
    header.__hovered = nil
    SecureHandlerExecute(header, [[
        self:CallMethod("ReportHovered", fake_hovered and fake_hovered:GetName() or nil)
    ]])
    return header.__hovered
end

--- A frame with a hover binding on it, so filling and emptying the slot is something to look at.
local function HoverBoundFrame()
    InsertAction({
        type = Constants.SPELL, value = 585, key = "BUTTON3",
        units = { unitframe = {} },
    })
    ApplyBindings()
    return CreateTestUnitFrame("player", "group")
end

-- **Both engines work on one frame**, and the leave half is the one that could not be had before:
-- the client runs one leave body, so whoever is outermost takes it, and it was them. Ours empties
-- the hover slot on the way out and theirs binds their own key, in that order.
RegisterTest("Foreign wrappers: their leave and our hover both work on one frame", {
    description = "남이 위에 감싸도 그쪽 leave와 우리 호버가 같이 동작한다",
    run = function()
        local NAME = "Both engines on one frame"

        if InCombatLockdown() then
            return Fail(NAME, "wrapping a protected frame is blocked in combat")
        end

        local frame, err = HoverBoundFrame()
        if not frame then return Fail(NAME, err) end

        local header = FakeHeader()
        SecureHandlerWrapScript(frame, "OnLeave", header, FAKE_ENTER)
        AddTeardown(function()
            SecureHandlerExecute(header, [[
                fake_hovered = nil
                self:ClearBinding("SHIFT-F")
            ]])
        end)

        RunWrappedEnter(frame)
        if GetHoverUnit() ~= "player" then
            return Fail(NAME, format("our own enter did not fill the slot (hover=%s)",
                tostring(GetHoverUnit())))
        end

        RunWrappedLeave(frame)

        local bound = GetBindingAction("SHIFT-F", true) or ""
        if bound ~= "CLICK " .. frame:GetName() .. ":fake" then
            return Fail(NAME, format("their body did not bind SHIFT-F (got %q)", bound))
        end
        if FakeHovered() ~= frame:GetName() then
            return Fail(NAME, format("their body ran somewhere else: fake_hovered=%s",
                tostring(FakeHovered())))
        end
        if GetHoverUnit() ~= nil then
            return Fail(NAME, format("the cursor left and the slot still holds %s",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "their leave body ran in their own environment and our slot emptied")
    end,
})

-- **A wrap is two things at once: a report, and the moment the name door first meets that frame.**
-- Where the door is what registers it, registering has already reassembled every script, and
-- reassembling the same one again finds our own header on top and takes nothing -- which on
-- `OnLeave` is the branch that leaves what is held standing, so the body this wrap brought has to
-- have been picked up by the registering pass itself.
--
-- **Only a client can answer this.** `Interp:replay` does not replay `SetAttribute`, so the three
-- `Reassemble` calls one registration makes all read the last pass's attributes there and the leave
-- capture never happens at all -- the headless layer cannot tell the fault from its own limit.
RegisterTest("Foreign wrappers: a frame the wrap itself registers keeps that body", {
    description = "이름으로 처음 등록되는 프레임의 leave 본문이 등록 과정에서 안 지워진다",
    run = function()
        local NAME = "First wrap registers"

        if InCombatLockdown() then
            return Fail(NAME, "wrapping a protected frame is blocked in combat")
        end

        -- A name the pack list answers, on a frame nothing has registered yet, so this wrap is
        -- also its first registration.
        local frame = FreshNamedFrame("ElvUF_DebindTestFirstWrap")
        if DebindPrivate.ccframes[frame] then
            return Fail(NAME, "it is already ours, so the door being measured is not the one taken")
        end
        frame:SetAttribute("unit", "player")

        SecureHandlerWrapScript(frame, "OnLeave", FakeHeader(), [[
            fake_hovered = self
        ]])
        -- **Cleared rather than left to another leave.** This body fills `fake_hovered` where
        -- `FAKE_LEAVE` empties it, so running it again would hand the next test a frame this one
        -- made -- which is what `Foreign unwrap` reads to answer its own question.
        AddTeardown(function()
            SecureHandlerExecute(FakeHeader(), [[ fake_hovered = nil ]])
        end)

        if type(DebindPrivate.ccframes[frame]) ~= "table" then
            return Fail(NAME, "the name door did not take it, so nothing here is being measured")
        end

        RunWrappedEnter(frame)
        RunWrappedLeave(frame)

        if FakeHovered() ~= frame:GetName() then
            return Fail(NAME, format("their leave body is gone: fake_hovered=%s",
                tostring(FakeHovered())))
        end

        return Pass(NAME, "the body the registering wrap brought still runs")
    end,
})

-- **A post body runs on what its own pre answered with.** Ours is the wrapper the client calls now,
-- so a message their leave body produced has to be carried out of our own pre, back in through the
-- client, and handed on in our post -- three places it could be dropped, none of which raises
-- anything.
RegisterTest("Foreign wrappers: their post body is handed their own message", {
    description = "우리가 대신 도는 leave의 post 본문이 자기 pre가 낸 message를 받는다",
    run = function()
        local NAME = "Foreign post body"

        if InCombatLockdown() then
            return Fail(NAME, "wrapping a protected frame is blocked in combat")
        end

        local frame, err = HoverBoundFrame()
        if not frame then return Fail(NAME, err) end

        local header = FakeHeader()
        SecureHandlerWrapScript(frame, "OnLeave", header, [[
            return nil, "carried"
        ]], [[
            fake_post = message
        ]])

        RunWrappedEnter(frame)
        RunWrappedLeave(frame)

        header.__post = nil
        SecureHandlerExecute(header, [[
            self:CallMethod("ReportPost", fake_post)
        ]])
        if header.__post ~= "carried" then
            return Fail(NAME, format("their post body saw %s", tostring(header.__post)))
        end

        return Pass(NAME, "their post body was handed its own message")
    end,
})

-- **An unwrap says nothing about who asked**, so it is passed on rather than read. When the top
-- comes off a frame of ours all we know is that the top was ours and that the wrapper the call
-- meant to take is still there; taking their outermost as well is what that call would have done
-- had we never been on this frame. Going back on top waits a tick, so an engine that unwraps in a
-- loop can reach an empty chain.
RegisterTest("Foreign wrappers: an unwrap nobody follows with a wrap stops their body", {
    description = "남이 unwrap하고 다시 안 감으면 그쪽 본문이 멈춘다",
    run = function()
        local NAME = "Foreign unwrap"

        if InCombatLockdown() then
            return Fail(NAME, "wrapping a protected frame is blocked in combat")
        end

        local frame, err = HoverBoundFrame()
        if not frame then return Fail(NAME, err) end

        local header = FakeHeader()
        SecureHandlerWrapScript(frame, "OnLeave", header, FAKE_ENTER)
        AddTeardown(function()
            SecureHandlerExecute(header, [[
                fake_hovered = nil
                self:ClearBinding("SHIFT-F")
            ]])
        end)

        -- Their body has to be reachable first, or "it stopped" is not a measurement.
        RunWrappedEnter(frame)
        RunWrappedLeave(frame)
        if FakeHovered() ~= frame:GetName() then
            return Fail(NAME, format("the premise is gone: their body never ran (fake_hovered=%s)",
                tostring(FakeHovered())))
        end
        SecureHandlerExecute(header, [[ fake_hovered = nil ]])

        SecureHandlerUnwrapScript(frame, "OnLeave")
        coroutine.yield(0)

        RunWrappedEnter(frame)
        RunWrappedLeave(frame)

        if FakeHovered() ~= nil then
            return Fail(NAME, format(
                "they took their wrapper back and their body still ran (fake_hovered=%s)",
                tostring(FakeHovered())))
        end
        if GetHoverUnit() ~= nil then
            return Fail(NAME, format("our own leave stopped working too (hover=%s)",
                tostring(GetHoverUnit())))
        end

        return Pass(NAME, "their body stopped and our own leave still runs")
    end,
})

-- **Two engines that both re-wrap on being wrapped over pile up on the call stack**, not over
-- time, so nothing that defers the judgement can help: measured without a guard it reached 198
-- frames and overflowed the C stack. The guard is read first and set synchronously, and the frame
-- is given up on the spot.
--
-- **The client is the only place this can be asked.** A stack overflow is not something the
-- headless harness would reproduce -- it would simply recurse in Lua and answer the same way.
RegisterTest("Foreign wrappers: a frame another engine keeps taking back is given up", {
    description = "되받아치는 엔진이 있으면 그 프레임에서 물러난다",
    run = function()
        local NAME = "Contested frame"

        if InCombatLockdown() then
            return Fail(NAME, "wrapping a protected frame is blocked in combat")
        end

        local frame, err = HoverBoundFrame()
        if not frame then return Fail(NAME, err) end

        local header = FakeHeader()
        local depth, watching = 0, true
        AddTeardown(function() watching = false end)

        -- **A hook cannot be taken off**, so it is switched off by teardown instead and answers
        -- for this one frame only. It behaves the way a competing engine does: it wraps again the
        -- moment somebody else's header goes on the frame.
        hooksecurefunc("SecureHandlerWrapScript", function(wrapped, script, wrappedBy)
            if not watching or wrapped ~= frame or script ~= "OnEnter" or wrappedBy == header then
                return
            end
            depth = depth + 1
            if depth > 20 then
                return
            end
            SecureHandlerWrapScript(frame, "OnEnter", header, FAKE_ENTER)
        end)

        SecureHandlerWrapScript(frame, "OnEnter", header, FAKE_ENTER)
        AddTeardown(function() RunWrappedLeave(frame) end)

        if depth > 3 then
            return Fail(NAME, format("the two of us traded the top %d times before stopping", depth))
        end
        if DebindPrivate.ccframes[frame] ~= false then
            return Fail(NAME, "we kept a frame another engine keeps taking back")
        end

        -- **And their wrapper is still on the frame**, which is the whole reason for standing down.
        -- Reading it back takes it off, so it goes straight back on.
        local header2, pre2, post2 = SecureHandlerUnwrapScript(frame, "OnEnter")
        if header2 then
            SecureHandlerWrapScript(frame, "OnEnter", header2, pre2, post2)
        end
        if header2 ~= header then
            return Fail(NAME, "we stood down and their wrapper is not the outermost")
        end

        return Pass(NAME, format("gave the frame up after %d passes", depth))
    end,
})

-- **Moving a Blizzard unit frame box does nothing at all until the next login.** Deregistering is
-- the frame owner's to ask for and Blizzard never asks, so ticking one cannot take the frame back;
-- and the gate reads the login snapshot rather than the stored table, so unticking one cannot
-- register on the spot either. Both halves are what `REQUIRES_RELOAD` on the box promises, and the
-- second half is the one that used to be false.
--
-- The harness cannot answer this: the option table and the fixed frame list are both the running
-- client's.
RegisterTest("Blizzard frames: moving a box changes nothing until the next login", {
    description = "블리자드 개체창 체크를 움직여도 리로드 전에는 아무 일도 없다",
    run = function()
        local NAME = "Blizzard frame toggle"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end
        if not PlayerFrame then
            return Fail(NAME, "there is no PlayerFrame on this board")
        end
        if type(DebindPrivate.ccframes[PlayerFrame]) ~= "table" then
            return Fail(NAME, format("the premise is gone: PlayerFrame is not registered (ccframes=%s)",
                tostring(DebindPrivate.ccframes[PlayerFrame])))
        end

        local stored = DebindPrivate.Options.frameBlacklist.blizzard
        local snapshot = DebindPrivate.optionsAtLogin.frameBlacklist.blizzard
        local previousStored = stored.player
        local previousSnapshot = snapshot.player
        AddTeardown(function()
            stored.player = previousStored
            snapshot.player = previousSnapshot
            if not InCombatLockdown() then
                DebindPrivate.UpdateBlizzardFrames()
            end
        end)

        stored.player = false
        DebindPrivate.UpdateBlizzardFrames()
        if type(DebindPrivate.ccframes[PlayerFrame]) ~= "table" then
            return Fail(NAME, "ticking the box took the frame back, which is not ours to do")
        end

        --- **The other direction, which is the one the snapshot fixed**, driven on a frame of ours
        --- rather than on `PlayerFrame`. What has to be seen is a frame going from unregistered to
        --- registered, and clearing the client's own frame's row to arrange that would re-wire a
        --- frame that is already wired.
        local ours = MakeTestUnitFrame("player")
        DebindPrivate.blizzardFrames[ours] = "player"
        AddTeardown(function()
            DebindPrivate.blizzardFrames[ours] = nil
        end)

        snapshot.player = false
        stored.player = nil
        DebindPrivate.UpdateBlizzardFrames()
        if DebindPrivate.ccframes[ours] ~= nil then
            return Fail(NAME, format("unticking the box registered a frame before a reload (%s)",
                tostring(DebindPrivate.ccframes[ours])))
        end

        -- And the login answer is what does register, so the same frame comes through on the flip.
        snapshot.player = nil
        DebindPrivate.UpdateBlizzardFrames()
        if type(DebindPrivate.ccframes[ours]) ~= "table" then
            return Fail(NAME, format("the login answer says ours and the frame got no row (%s)",
                tostring(DebindPrivate.ccframes[ours])))
        end

        return Pass(NAME, "neither direction reached a frame; the login answer is what did")
    end,
})
