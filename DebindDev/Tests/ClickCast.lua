local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local WaitUntil = Dev.WaitUntil
local AddTeardown = Dev.AddTeardown
local InsertAction = Dev.InsertAction
local ApplyBindings = Dev.ApplyBindings
local SetMockState = Dev.SetMockState
local EnableProbes = Dev.EnableProbes
local EvalClickCast = Dev.EvalClickCast
local LastEvalAnswer = Dev.LastEvalAnswer
local WaitForEvalAnswer = Dev.WaitForEvalAnswer
local LastWinner = Dev.LastWinner
local ReadKeyMembership = Dev.ReadKeyMembership
local WaitForMembership = Dev.WaitForMembership
local UNIT_TOKEN_ABSENT = Dev.UNIT_TOKEN_ABSENT
local MakeTestUnitFrame = Dev.MakeTestUnitFrame
local FreshNamedFrame = Dev.FreshNamedFrame
local CreateTestUnitFrame = Dev.CreateTestUnitFrame
local HoverEnter = Dev.HoverEnter
local HoverLeave = Dev.HoverLeave
local WaitForHoverSlot = Dev.WaitForHoverSlot
local FakeHeader = Dev.FakeHeader

--- The frames a click-cast test has to cover: one we made, and one of Blizzard's.
---
--- **Driving only our own frame would miss the thing that changed.** Blizzard's frames are the
--- ones whose `type1` the old routing took over, and they arrive through a different door --
--- `UpdateBlizzardFrames` rather than the Clique API -- so "it works on a frame the test built"
--- says nothing about them.
---
--- Blizzard's is skipped rather than failed when it is not registered: that is a user option
--- (`Options.frameBlacklist.blizzard`), not a fault.
local function ClickCastTargets()
    local targets = {}

    local frame, err = CreateTestUnitFrame("player", "group")
    if not frame then return nil, err end
    targets[#targets + 1] = { label = "our frame", frame = frame }

    if PlayerFrame and type(DebindPrivate.ccframes[PlayerFrame]) == "table" then
        -- Asked for where it already is. Moving or resizing one of Blizzard's frames to make it
        -- convenient would be the addon reaching into it, which is the thing being tested away.
        PlayerFrame.debindTestLeaveAlone = true
        targets[#targets + 1] = { label = "PlayerFrame", frame = PlayerFrame, blizzard = true }
    end

    return targets
end

-- Click-casting decides at the click now, in a wrapper on the frame rather than in attributes
-- stamped on it ahead of time. Clicking is the only way to reach that decision.
-- The claim the routing change was made for: a registered frame's own action slots are not
-- somewhere this addon writes. They used to be -- click-casting worked by overwriting `type1`
-- and remembering what had been there -- so this could not have been asserted before now.
--
-- No click needed; it only reads.
RegisterTest("Click-cast: the frame's own slots stay ours to not touch", {
    description = "Nothing of ours is written to type1/2/3 on a registered frame, Blizzard's own included",
    run = function()
        local NAME = "Click-cast non-invasion"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { frameTypes = Constants.FRAMETYPE_ALL } },
        })
        ApplyBindings()

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        local checked = {}
        for _, target in ipairs(targets) do
            local frame = target.frame

            -- Ours is a suffix nobody else uses, and it is what carries the click to us.
            if frame:GetAttribute("*type-debind1") ~= "click" then
                return Fail(NAME, format("%s: *type-debind1=%s, it should be click",
                    target.label, tostring(frame:GetAttribute("*type-debind1"))))
            end

            -- And nothing of ours in the slots that belong to the frame. "click" is the value the
            -- old routing wrote, but it is not ours alone: Clique's proxy build writes `click`
            -- into `*type1`/`*type2` on every Blizzard frame it holds and points the matching
            -- `clickbutton` at its proxy (`Clique/core/proxy_frames.lua`, measured 2026-09-08
            -- on this board). So what is asked is where the click goes, and only a slot aimed at
            -- our own frame is ours.
            for i = 1, 5 do
                for _, prefix in ipairs({ "*", "" }) do
                    if frame:GetAttribute(prefix .. "type" .. i) == "click"
                            and frame:GetAttribute(prefix .. "clickbutton" .. i)
                                == DebindPrivate.DefaultClickFrame then
                        return Fail(NAME, format(
                            "%s: click on %stype%d goes to our frame. the old routing still writes to that slot",
                            target.label, prefix, i))
                    end
                end
            end
            checked[#checked + 1] = target.label
        end

        return Pass(NAME, table.concat(checked, ", ") .. ", and the slots that are not ours are empty")
    end,
})

-- **A registered frame gets both edges, and the wrapper picks between them.**
--
-- The release is the edge a frame's own actions run on: `SECURE_ACTIONS.menu` acts on the release
-- and returns while `down` is true, so a frame missing it loses its unit menu outright, with no
-- error to say so. `target` does not gate on the edge, which is why targeting went on working and
-- hid that through several releases. Neither is tied to a button, since
-- `Enum.ClickBindingInteraction.Target` and `.OpenContextMenu` are both movable in Blizzard's
-- click binding window, which is why this asks for the whole release edge rather than one
-- button's.
--
-- **The press has to be there too, which is the reverse of what this case used to ask.** It was
-- written when `unitframeUseMouseDown` had just been removed, over a claim that registering an
-- edge another addon never asked for runs its `OnClick` twice per click. That claim is false:
-- `SecureActionButton_OnClick` computes
-- `clickAction = (down and useOnKeyDown) or (not down and not useOnKeyDown)`, so a frame acts on
-- exactly one edge however many are delivered. Delivery and action are separate, and the option
-- is back with three answers, one of them the press.
--
-- So a narrowing here is a silent death in either direction: without the press, choosing to cast
-- on mouse down does nothing at all; without the release, the default does. And narrowing to
-- per-button forms takes the middle and thumb buttons off the frame entirely, since a frame
-- delivers only what it is registered for.
--
-- The registration call is captured on a frame the test owns, because there is no API that asks a
-- frame which clicks it is registered for (`SimpleButtonAPIDocumentation.lua` has the setter and
-- no getter). Shadowing the method on our own frame leaves every other frame alone, and the real
-- one is still called.
RegisterTest("Click-cast: a registered frame carries both click edges", {
    description = "A registered frame carries both the press edge and the release edge",
    run = function()
        local NAME = "Click edges"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and RegisterForClicks are both blocked in combat")
        end

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        local captured
        local realRegisterForClicks = frame.RegisterForClicks
        frame.RegisterForClicks = function(self, ...)
            captured = { ... }
            return realRegisterForClicks(self, ...)
        end
        AddTeardown(function() frame.RegisterForClicks = nil end)

        DebindPrivate.UpdateRegisteredClicks(frame)

        if not captured then
            return Fail(NAME, "the registration itself never ran")
        end

        local function Registered(want)
            for _, got in ipairs(captured) do
                if got == want then return true end
            end
            return false
        end

        local seen = table.concat(captured, " ")

        if not Registered("AnyUp") then
            return Fail(NAME, format(
                "[%s] has no release edge. that edge is the only place the unit menu runs, so a button "
                .. "carrying the menu goes dead, and anyone casting on release gets no click at all", seen))
        end

        if not Registered("AnyDown") then
            return Fail(NAME, format(
                "[%s] has no press edge. anyone casting on press gets no click "
                .. "at all", seen))
        end

        return Pass(NAME, seen)
    end,
})

RegisterTest("Click-cast: the frame's wrapper picks a winner", {
    description = "A unit frame click reaches the wrapper and picks the record the condition matches, on our frame and on Blizzard's",
    run = function()
        local NAME = "Click-cast winner"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON3",
            units = { unitframe = { frameTypes = Constants.FRAMETYPE_ALL } },
        })
        ApplyBindings()

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        local seen = {}
        for _, target in ipairs(targets) do
            -- Hover is what the record is conditioned on, and the click-cast path reads it off the
            -- frame rather than the cache -- so it has to be under the cursor for real.
            HoverEnter(target.frame)
            AddTeardown(function() HoverLeave(target.frame) end)
            WaitForHoverSlot(true)

            local ran, rerr = EvalClickCast(target.frame, 3, 0)
            if not ran then return Fail(NAME, format("%s: %s", target.label, rerr)) end
            WaitForEvalAnswer()

            if LastWinner() == nil then
                return Fail(NAME, format("%s: it picked nothing, either nothing matched or "
                    .. "no key is registered for that button and modifier", target.label))
            end
            seen[#seen + 1] = format("%s=%d", target.label, LastWinner())

            HoverLeave(target.frame)
            WaitForHoverSlot(false)
        end

        return Pass(NAME, table.concat(seen, ", "))
    end,
})

-- A key whose records all carry a hover condition holds no key-binding record, so the key itself is
-- not bound and nothing is measured for it ahead of a click -- the click path measures at the press,
-- and click-casting does not even take the hover from the cache.
--
-- **What this holds is that measuring nothing did not narrow the judgement.** A press still has to
-- ask about `combat`, and the membership check beside it says the key really is click-cast only.
RegisterTest("Click-cast only: judged at the press with nothing measured for it", {
    description = "A click-cast only key is registered for frame clicks only and still judges its conditions",
    run = function()
        local NAME = "Click-cast only"
        local KEY = "BUTTON3"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        local ok, err = EnableProbes()
        if not ok then
            return Fail(NAME, "rebake failed: " .. tostring(err))
        end

        InsertAction({
            type = Constants.SPELL, value = 585, key = KEY,
            units = { unitframe = { frameTypes = Constants.FRAMETYPE_ALL } },
            combat = true,
        })
        ApplyBindings()

        ReadKeyMembership(KEY)
        local m = WaitForMembership()
        if not m then return Fail(NAME, "the restricted environment sent no answer") end

        -- The positive side is checked first. "Not a click-time key" is true of a key whose records
        -- never went out at all.
        if not m.clickCast then
            return Fail(NAME, "not in ClickCastKeys, and not because it was dropped: no record went out")
        end
        if m.clickTime then
            return Fail(NAME, "it is in ClickTimeKeys, so the key itself was bound with not one record holding it")
        end

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end
        local target = targets[1]

        -- The record carries hover as a condition and the click-cast path reads that off the frame
        -- rather than a cache, so the cursor really has to be on it.
        HoverEnter(target.frame)
        AddTeardown(function() HoverLeave(target.frame) end)
        WaitForHoverSlot(true)

        local function judge(inCombat)
            SetMockState("combat", inCombat)
            local ran, rerr = EvalClickCast(target.frame, 3, 0)
            if not ran then return false, rerr end
            WaitForEvalAnswer()
            return true, LastWinner()
        end

        local ran, hit = judge(true)
        if not ran then return Fail(NAME, tostring(hit)) end
        if hit == nil then
            return Fail(NAME, "set to combat and it still picked nothing, cutting the registration cut the judging with it")
        end

        local ran2, miss = judge(false)
        if not ran2 then return Fail(NAME, tostring(miss)) end
        if miss ~= nil then
            return Fail(NAME, format("out of combat and it picked %s, the combat condition is not being looked at",
                tostring(miss)))
        end

        return Pass(NAME, format("click-cast only: %s in combat, nothing out of it", tostring(hit)))
    end,
})

-- The point of judging on the frame instead of ahead of it: when nothing matches we return nil,
-- the button name is left alone, and the click carries on into whatever the frame itself does.
-- On the old path the frame's own `type` had been overwritten, so a click that matched nothing
-- did nothing at all -- silently, which is the shape of fault this addon keeps running into.
RegisterTest("Click-cast: a click that matches nothing falls through", {
    description = "Where nothing matches, the frame's own action goes out untouched: the dynamic fallback",
    run = function()
        local NAME = "Click-cast fallback"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame and wrapping are both blocked in combat")
        end

        -- **`LastWinner()` answers only with the probes on.** `PROBE.Winner` is removed outright on
        -- the release branch, so without them this test's "did it pick nothing" check reads nil every
        -- time and passes: it stays quiet even where a missing condition makes it pick the wrong
        -- record.
        local probesOk, probesErr = EnableProbes()
        if not probesOk then
            return Fail(NAME, "turning the probes on failed: " .. tostring(probesErr))
        end

        -- **The left button, because that is where falling through means something.** A unit
        -- frame's left click is targeting; what this checks is that declining hands the click
        -- back to it. (A hover binding may take BUTTON1 -- the button is only refused without
        -- one.)
        --
        -- Cannot match: the record wants combat and the state says otherwise. The binding still
        -- exists, so the frame is still routed and the wrapper still runs -- which is the point.
        -- A test with no binding at all would pass without the wrapper ever deciding anything.
        InsertAction({
            type = Constants.SPELL, value = 585, key = "BUTTON1",
            units = { unitframe = { frameTypes = Constants.FRAMETYPE_GROUP } },
            combat = true,
        })
        ApplyBindings()
        SetMockState("combat", false)

        local targets, terr = ClickCastTargets()
        if not targets then return Fail(NAME, terr) end

        -- **Our own frame only.** The Blizzard target could only assert "nothing was chosen", and
        -- a wrapper that was never installed gives that same answer.
        --
        -- **What is asserted is the decline, not the carrying-on.** Declining is answering nil,
        -- which leaves the button name alone so the click continues into the frame's own handler
        -- -- and only a real click can show that continuing. Answering nil is the half this addon
        -- decides; the rest is the game's.
        for _, target in ipairs(targets) do
            if not target.blizzard then
                HoverEnter(target.frame)
                AddTeardown(function() HoverLeave(target.frame) end)
                WaitForHoverSlot(true)

                local ran, rerr = EvalClickCast(target.frame, 1, 0)
                if not ran then return Fail(NAME, format("%s: %s", target.label, rerr)) end

                -- **The answer, not a winner.** Nothing is expected to be chosen here, and
                -- `WaitForWinner` would sit out its whole limit on every target proving it.
                WaitForEvalAnswer()

                if LastWinner() ~= nil then
                    return Fail(NAME, format(
                        "%s: nothing matched and it picked #%d. the combat check may not be in place",
                        target.label, LastWinner()))
                end

                if LastEvalAnswer() ~= nil then
                    return Fail(NAME, format(
                        "%s: it picked nothing and returned %q. that changes the button name, so the frame's "
                        .. "own action never goes out",
                        target.label, tostring(LastEvalAnswer())))
                end

                HoverLeave(target.frame)
                WaitForHoverSlot(false)
            end
        end

        return Pass(NAME, "no match -> picks nothing and changes no name (it falls through to the frame)")
    end,
})

-- **Only the game runs this one.** `clickcast_register` is a snippet body, and what it does now is
-- carry a name out of the restricted environment with `CallMethod`. The headless harness never
-- builds those tables, so nothing there can say whether the round trip happens at all -- it drives
-- `OnClickCastRegister` directly instead (`tests/frames_spec.lua`), which is the far side of the
-- trip and not the trip.
--
-- What is pinned: an addon reaching us through both doors ends on the header's answer whichever
-- order it uses them in. It did not. `ClickCastFrames` writes `unknown` because the Clique protocol
-- carries no kind, and the frame came out group or unknown depending on which call reached it
-- first. The header is the one that knows: its children hold whichever slot they are filling.
--
-- **And the hover wrappers, which moved.** The header door used to hang `clickcast_onenter` on the
-- child instead of wrapping its motion scripts. Now every door leaves the same wrappers, and
-- nothing but the game can say the wrap took.
RegisterTest("Header registration takes a frame back from the click-cast table", {
    description = "Header registration takes back a frame ClickCastFrames got to first",
    run = function()
        local NAME = "Header takeover"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        -- `true` is what unit frame addons actually put in `ClickCastFrames`, and it is not one of
        -- our category names -- so this is the door that yields `unknown`.
        local frame, err = CreateTestUnitFrame(UNIT_TOKEN_ABSENT, true)
        if not frame then return Fail(NAME, err) end
        local frameName = frame:GetName()

        local before = DebindPrivate.ccframes[frame]
        if before.frameType ~= Constants.FRAMETYPE_UNKNOWN then
            return Fail(NAME, format("the first registration should be unknown and it was %s", tostring(before.frameType)))
        end

        -- Exactly what a header does: hand the button over on the driver and run the body.
        SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_cc", frame)
        SecureHandlerExecute(DebindPrivate.BindingDriver, [[
            self:SetAttribute("clickcast_button", self:GetFrameRef("debindtest_cc"))
            self:RunAttribute("clickcast_register")
        ]])

        -- **The frame's own teardown is what takes the row**, and `clickcast_unregister` is not: a
        -- header taking a child back is a deregistration from outside and those do nothing now
        -- (`taking-every-unit-frame-with-one-blacklist.md` §1-5). Run here anyway,
        -- because the body still has to be reachable by name from a header that calls it.
        AddTeardown(function()
            SecureHandlerSetFrameRef(DebindPrivate.BindingDriver, "debindtest_cc", frame)
            SecureHandlerExecute(DebindPrivate.BindingDriver, [[
                self:SetAttribute("clickcast_button", self:GetFrameRef("debindtest_cc"))
                self:RunAttribute("clickcast_unregister")
            ]])
        end)

        -- **The registration is a tick behind the body**, which is the whole point of the signal:
        -- the callback lands while the header is still configuring the child, so it puts the work
        -- off rather than re-entering on a frame that is not finished.
        local arrived = WaitUntil(function()
            local row = DebindPrivate.ccframes[frame]
            return type(row) == "table" and row.hd
        end)
        if not arrived then
            return Fail(NAME, format("the header's signal never came back out (ccframes=%s)",
                tostring(DebindPrivate.ccframes[frame])))
        end

        -- Written out rather than handed to `CheckWiredFrame`, which is `Tests/Packs.lua`'s own and
        -- not in scope here.
        local after = DebindPrivate.ccframes[frame]
        if after.frameType ~= Constants.FRAMETYPE_GROUP then
            return Fail(NAME, format("unknown was not covered over. frameType=%s", tostring(after.frameType)))
        end
        if frame:GetAttribute("debind_frametype") ~= Constants.FRAMETYPE_GROUP then
            return Fail(NAME, format("the frame carries debind_frametype %s while its row says group",
                tostring(frame:GetAttribute("debind_frametype"))))
        end
        if frame:GetAttribute("*type-debind1") ~= "click" then
            return Fail(NAME, format("the header's child has no click routing (*type-debind1=%s)",
                tostring(frame:GetAttribute("*type-debind1"))))
        end
        if frame:GetAttribute("*clickbutton-debind1") ~= DebindPrivate.DefaultClickFrame then
            return Fail(NAME, "the header's child routes its click somewhere that is not ours")
        end
        -- What Clique exposes as `hccframes`: the header-registered frames by name.
        if DebindPrivate.hccframes[frameName] ~= frame then
            return Fail(NAME, "hccframes does not list the frame the header registered")
        end

        return Pass(NAME, "the header took an unknown row back as a wired group frame")
    end,
})

-- **Another addon holds the name `ClickCastFrames`, and we stand behind it.** The harness cannot
-- see this: that table is stood up by `DebindCliqueFake`, which is only read once `DebindPublic` is
-- there, and the runner loads neither.
--
-- Three questions, and they are the three the rule turns on. Is the holder's table left where it
-- is; does a write it keeps for itself still leave it holding that frame; and does every write
-- reach us, whichever way it answered. Both answers are ours, because standing on top of whatever
-- it wrapped means both engines work there.
RegisterTest("Click-cast table: the holder keeps the name and we stand on top of it", {
    description = "남의 ClickCastFrames를 되찾지 않고 그 뒤에 서서, 우리가 들고 있던 행을 건네주고 쓰기와 읽기를 다 듣는다",
    run = function()
        local NAME = "ClickCastFrames holder"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end
        if not DebindPrivate.AttachClickCastFrames then
            return Fail(NAME, "DebindCliqueFake did not come up, there is no name to stand behind on this board")
        end

        local ours = _G.ClickCastFrames
        if type(ours) ~= "table" then
            return Fail(NAME, format("ClickCastFrames is not a table (%s)", type(ours)))
        end
        -- **The name is stood back up as ours first, and that is the precondition rather than a
        -- convenience.** Our rows only fill while we are holding the name, so on a board where a
        -- pack is already holding it there is nothing for the hand-over below to hand over and the
        -- case would measure an empty table. Taking the pointer for the length of one test does not
        -- touch what that pack has in its own store.
        local handed, mine
        AddTeardown(function()
            if mine then
                _G.ClickCastFrames = mine
                if handed then
                    mine[handed] = nil
                end
            end
            _G.ClickCastFrames = ours
            DebindPrivate.AttachClickCastFrames()
        end)

        _G.ClickCastFrames = {}
        DebindPrivate.AttachClickCastFrames()
        mine = _G.ClickCastFrames
        if mine == ours then
            return Fail(NAME, "the name was not taken back, so there is nothing to hand a holder")
        end

        -- A frame registered while the name is ours, so the holder below arrives after it. Our rows
        -- sit beside the table rather than in it, so the `pairs` walk a holder builds its store from
        -- yields nothing -- and this is the frame that walk would have found had a plain table been
        -- sitting there.
        --
        -- **A unit the frame type can be read off, and not the absent token the other frames here
        -- use.** `RegisterFrame` leaves an already-registered frame on the row it has, but an
        -- `unknown` frameType deliberately does not close that question -- so on the absent token
        -- the hand-over below rebuilds the row for a reason that has nothing to do with what is
        -- being measured here.
        local err0
        handed, err0 = CreateTestUnitFrame("player", "player")
        if not handed then return Fail(NAME, err0) end
        mine[handed] = true
        local handedRow = DebindPrivate.ccframes[handed]
        if type(handedRow) ~= "table" then
            return Fail(NAME, format("the premise is gone: the frame never registered with us (ccframes=%s)",
                tostring(handedRow)))
        end

        -- A holder in the shape the real ones have: a store of its own in an upvalue, an `__index`
        -- that answers for the frames it decided to keep, and a `__newindex` that files every write.
        local kept, filed = {}, {}
        local theirs = setmetatable({}, {
            __index = function(_, frame) return kept[frame] end,
            __newindex = function(_, frame, value) filed[frame] = value end,
        })
        _G.ClickCastFrames = theirs

        DebindPrivate.AttachClickCastFrames()
        if _G.ClickCastFrames ~= theirs then
            return Fail(NAME, "the holder's table was replaced, which loses every frame already written into it")
        end
        if filed[handed] ~= true then
            return Fail(NAME, format("the holder never heard about the frame we were already holding (filed=%s)",
                tostring(filed[handed])))
        end
        if DebindPrivate.ccframes[handed] ~= handedRow then
            return Fail(NAME, "handing that frame over registered it a second time")
        end

        -- The frame the holder keeps. `kept` is what its `__index` answers out of, so writing it
        -- there first is that addon deciding before the write comes back to us. It stays theirs
        -- and it is ours as well. **Built without a registration**, so the write below is what
        -- registers it and the frame is not one we were already holding.
        local theirFrame = MakeTestUnitFrame(UNIT_TOKEN_ABSENT)
        kept[theirFrame] = true
        _G.ClickCastFrames[theirFrame] = true
        if type(DebindPrivate.ccframes[theirFrame]) ~= "table" then
            return Fail(NAME, format("a frame the holder kept never reached us (ccframes=%s)",
                tostring(DebindPrivate.ccframes[theirFrame])))
        end
        if kept[theirFrame] ~= true then
            return Fail(NAME, "the holder lost the frame it had kept")
        end

        -- And the frame it filed and dropped.
        local dropped = MakeTestUnitFrame(UNIT_TOKEN_ABSENT)
        _G.ClickCastFrames[dropped] = true
        local droppedRow = DebindPrivate.ccframes[dropped]
        if type(droppedRow) ~= "table" then
            return Fail(NAME, format("a frame the holder dropped never reached us (ccframes=%s)",
                tostring(droppedRow)))
        end

        -- **A deregistration arriving from outside means nothing**, here as everywhere: being ours
        -- is the blacklist's answer and not the frame owner's
        -- (`taking-every-unit-frame-with-one-blacklist.md` §1-5).
        _G.ClickCastFrames[dropped] = nil
        if DebindPrivate.ccframes[dropped] ~= droppedRow then
            return Fail(NAME, format("a nil write behind the holder took our row (ccframes=%s)",
                tostring(DebindPrivate.ccframes[dropped])))
        end

        -- **A holder puts its proxy up and then wraps its own frames, and we know nothing about any
        -- of them** -- so none of those wraps was a reason to look at the name, and a registration a
        -- third addon wrote into that proxy meanwhile was heard by nobody. A proxy keeps its store
        -- in an upvalue, so no later pass can find it either.
        local later = setmetatable({}, {
            __index = function() end,
            __newindex = function() end,
        })
        _G.ClickCastFrames = later
        local beforeWrap = getmetatable(later).__newindex

        local stranger = FreshNamedFrame("DebindTestHolderStranger")
        if DebindPrivate.ccframes[stranger] then
            return Fail(NAME, "the premise is gone: the stranger frame is one we already know about")
        end
        SecureHandlerWrapScript(stranger, "OnEnter", FakeHeader(), "-- theirs")
        AddTeardown(function() SecureHandlerUnwrapScript(stranger, "OnEnter") end)

        -- Waits for the tick the check is booked on, which is **not** what is asserted after it:
        -- the assertion is whether a write into that proxy then reaches us at all.
        local stood = WaitUntil(function() return getmetatable(later).__newindex ~= beforeWrap end, 2)
        if not stood then
            return Fail(NAME, "a foreign wrap never sent us back to look at the name")
        end

        local third = MakeTestUnitFrame(UNIT_TOKEN_ABSENT)
        later[third] = true
        if type(DebindPrivate.ccframes[third]) ~= "table" then
            return Fail(NAME, format("a registration written into the holder's proxy was never heard (ccframes=%s)",
                tostring(DebindPrivate.ccframes[third])))
        end

        return Pass(NAME, "the name was left alone, the frame we already had went over, the kept and dropped ones both came to us, a nil write took nothing back, and a later proxy was heard")
    end,
})

-- **Does the hook stand on a real secure frame.** What the harness sees is the rule: narrowed, we
-- put it back (`tests/frames_spec.lua`). What only the game answers is whether hanging
-- `hooksecurefunc` on the frame's own method takes at all, and whether the call that puts it back
-- is refused for taint.
RegisterTest("Click-cast: another addon narrowing the frame is put back", {
    description = "We put RegisterForClicks and EnableMouseWheel back where someone else narrowed them",
    run = function()
        local NAME = "Click input reasserted"

        if InCombatLockdown() then
            return Fail(NAME, "RegisterForClicks is blocked in combat")
        end

        local frame, err = CreateTestUnitFrame("player", "group")
        if not frame then return Fail(NAME, err) end

        -- There is no getter for what was last registered, so what is measured is the call our
        -- side makes to put it back.
        local seen
        local realRegisterForClicks = frame.RegisterForClicks
        frame.RegisterForClicks = function(self, ...)
            seen = table.concat({ ... }, " ")
            return realRegisterForClicks(self, ...)
        end
        AddTeardown(function() frame.RegisterForClicks = nil end)

        -- The call another click-casting engine makes to write its own edge on. A hook runs after
        -- the original returns, so this one line has to drag our own reassert along with it.
        frame:RegisterForClicks("AnyUp")
        if not seen then
            return Fail(NAME, "our hook never ran, the narrowed frame stays as it is")
        end
        if not (strfind(seen, "AnyUp", 1, true) and strfind(seen, "AnyDown", 1, true)) then
            return Fail(NAME, format("what was put back is [%s], one edge does not arrive", seen))
        end

        -- And the wheel. That addon turns it off in the **line after** the one that narrows the
        -- clicks, so hooking only the clicks leaves it off a moment after we put things back.
        seen = nil
        frame:EnableMouseWheel(false)
        if not seen then
            return Fail(NAME, "the call that turned the wheel off never called the restore")
        end

        return Pass(NAME, seen)
    end,
})
