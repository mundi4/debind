local _, Dev = ...

local DebindPrivate, Constants
Dev.OnDebindLoaded(function(private)
    DebindPrivate, Constants = private, private.Constants
end)

local RegisterTest = Dev.RegisterTest
local Pass = Dev.Pass
local Fail = Dev.Fail
local AddTeardown = Dev.AddTeardown
local UNIT_TOKEN_ABSENT = Dev.UNIT_TOKEN_ABSENT
local StandDownTestFrame = Dev.StandDownTestFrame
local MakeTestUnitFrame = Dev.MakeTestUnitFrame
local FreshNamedFrame = Dev.FreshNamedFrame

-----------------------------------------------------------
-- Another pack's unit frames
-----------------------------------------------------------

-- **Only a board with that pack installed can answer this**, which is the whole reason it is here.
-- `tests/frames_spec.lua` covers what the Clique door does with a frame handed to it; what no
-- harness can say is whether the pack still hands its frames over with its own hover casting off,
-- and still builds them by the time a run happens. Both are somebody else's file.
--
-- **The addon name comes out of `KNOWN_PACK_FRAMES`, asked for with one of the frame names the
-- case checks.** That table is what decides whether these frames are taken at all, so a row edited
-- away leaves the case skipping with a reason instead of asking for an addon nothing reads.
local EUI_UNITFRAMES_FRAME         = "EllesmereUIUnitFrames_Player";
local EUI_RAIDFRAMES_FRAME         = "ERFPartySelfButton";

local function EllesmereLoaded(frameName)
    return function()
        local addon = DebindPrivate.PackAddonForFrameName(frameName);
        if (not addon) then
            return false, frameName .. " is not on the known pack list";
        end
        if (not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon))) then
            return false, addon .. " is not loaded on this board";
        end
        --- **The frames below reach us through the three doors and nothing else**, and a listed
        --- pack's frames stand behind that pack's box at every one of them
        --- (`legacy/making-the-pack-box-own-its-addon.md`). Turned off, none of them is registered
        --- and the case would be measuring the reader's setting.
        if (not DebindPrivate.TakesPackFrames(addon)) then
            return false, addon .. " is turned off in this profile";
        end
        return true;
    end
end

--- One frame, checked the whole way through registration.
---
--- **The attribute is checked beside the row.** The row is what the insecure side kept and the
--- attribute is what the secure side reads back when the cursor arrives, and a registration that
--- wrote one without the other leaves a frame that answers one kind to the reader's conditions and
--- another to the window.
---
--- **The routing is checked because registration is not what puts it there.** `ApplyDebindRouting`
--- runs from `UpdateRegisteredClicks`, which is refused in combat and queued, so a frame can hold
--- a row and still send its clicks nowhere.
local function CheckWiredFrame(frame, name, expected)
    local row = DebindPrivate.ccframes[frame];
    if (row == false) then
        return format("%s was refused outright (unprotected, forbidden, anchored, or takes no click)", name);
    end
    if (type(row) ~= "table") then
        return format("%s is not registered (ccframes=%s)", name, tostring(row));
    end
    if (row.frameType ~= expected) then
        return format("%s registered as frameType %s, expected %s",
            name, tostring(row.frameType), tostring(expected));
    end
    if (frame:GetAttribute("debind_frametype") ~= expected) then
        return format("%s carries debind_frametype %s while its row says %s",
            name, tostring(frame:GetAttribute("debind_frametype")), tostring(expected));
    end
    if (frame:GetAttribute("*type-debind1") ~= "click") then
        return format("%s has no click routing (*type-debind1=%s)",
            name, tostring(frame:GetAttribute("*type-debind1")));
    end
    if (frame:GetAttribute("*clickbutton-debind1") ~= DebindPrivate.DefaultClickFrame) then
        return format("%s routes its click somewhere that is not ours", name);
    end
    return nil;
end

--- Walks a list of `{ globalName, expectedFrameType }` and reports what it found.
---
--- **A frame that is not there is not a failure**, and it is not a pass either. The pack builds
--- some of these only once the reader turns them on -- a boss frame when the encounter option is
--- set -- so a board without them is an ordinary board. What is reported instead is the count, and
--- finding **none at all** is the failure: that is what the door coming off looks like.
local function CheckNamedFrames(NAME, entries)
    local checked, missing, faults = {}, {}, {};
    for i = 1, #entries do
        local frameName, expected = entries[i][1], entries[i][2];
        local frame = _G[frameName];
        if (frame) then
            local fault = CheckWiredFrame(frame, frameName, expected);
            if (fault) then
                faults[#faults + 1] = fault;
            else
                checked[#checked + 1] = frameName;
            end
        else
            missing[#missing + 1] = frameName;
        end
    end

    if (#faults > 0) then
        return Fail(NAME, table.concat(faults, " | "));
    end
    if (#checked == 0) then
        return Fail(NAME, format("not one of these frames is registered, so no door reached them: %s",
            table.concat(missing, ", ")));
    end
    local detail = format("%d wired: %s", #checked, table.concat(checked, ", "));
    if (#missing > 0) then
        detail = detail .. format(" (%d not built on this board: %s)", #missing, table.concat(missing, ", "));
    end
    return Pass(NAME, detail);
end

-- **The real Clique is installed and we did not take anything of its.** This is the one thing no
-- headless spec can reach: the specs stand up a hand-made holder, and what this asks is whether the
-- real addon's own three globals are still the real addon's after we have loaded beside it.
--
-- **A board without Clique passes and says so.** There is nothing here that a board can be made to
-- have; installing it is outside the game.
--
-- The three are the three ways this could go wrong, and each of them is silent. Taking
-- `ClickCastFrames` leaves whoever is answering for Clique writing into a table nobody reads --
-- and that holder is not always Clique itself: with EllesmereUI's engine on, its proxy sits over
-- Clique's table and is what we stand behind. Taking `Clique` or
-- `ClickCastHeader` puts our stand-in over the real addon, and every unit frame addon that asks for
-- Clique gets us instead. That is the whole reason `DebindCliqueFake` may not load here, since
-- its XML would also raise on `ClickCastUnitTemplate`.
RegisterTest("Clique: the real addon keeps every name that is its own", {
    description = "Clique가 깔린 판에서 ClickCastFrames, Clique, ClickCastHeader 셋 다 저쪽 것으로 남아 있는지",
    run = function()
        local NAME = "Clique names"

        if not DebindPrivate.CliqueDetected then
            return Pass(NAME, "Clique가 안 깔린 판이라 잴 것이 없다")
        end

        if DebindPrivate.AttachClickCastFrames == nil then
            return Fail(NAME, "the click-cast table code did not load at all")
        end

        local ours = DebindPublic and DebindPublic.header
        if _G.ClickCastHeader == ours then
            return Fail(NAME, "ClickCastHeader is ours, so Clique's header protocol is cut off")
        end
        if type(_G.Clique) ~= "table" or _G.Clique.header == ours then
            return Fail(NAME, "the Clique global is ours, so addons asking for Clique reach us instead")
        end
        if type(_G.ClickCastFrames) ~= "table" then
            return Fail(NAME, format("ClickCastFrames is not a table (%s)", type(_G.ClickCastFrames)))
        end
        -- **신원으로 묻는다. 모양으로는 못 가른다.** 여기서 `__index`가 달린 메타테이블을 우리
        -- 것으로 읽던 자리인데, 그 전제는 "남의 프록시에는 `__index`가 없다" 하나에 걸려 있었다.
        -- EllesmereUI의 엔진은 자기 `registeredFrames`에서 답하는 `__index`를 달고, Clique가
        -- 깔린 판에서도 저장된 설정이 켜져 있으면 그 프록시가 Clique의 표 위에 앉는다
        -- (`how-unit-frames-reach-us.md`의 EllesmereUI 절). 그 판에서 이 검사는 남의
        -- 프록시를 보고 우리를 탓했다. 지금 묻는 것은 우리가 누구 뒤에 서 있느냐이고, 그 답은
        -- `ClickCastTable.lua` 안에서만 나온다.
        local holder = DebindPrivate.ClickCastTableHolder and DebindPrivate.ClickCastTableHolder()
        if holder == nil then
            return Fail(NAME, "ClickCastFrames is ours, so whoever is answering for Clique is writing into a table nobody reads")
        end
        -- 들고 있는 표가 바뀌었는데 우리가 옛 표 뒤에 남아 있으면, 듣고 있는 곳이 아무도 안
        -- 쓰는 표다. 이름 위의 것과 같은 표여야 한다.
        if holder ~= _G.ClickCastFrames then
            return Fail(NAME, "we are hooked onto a table that is no longer under the name")
        end

        return Pass(NAME, "나란히 서는 중이고, 이름은 우리 것이 아니며 우리는 그 표 뒤에 서 있다")
    end,
})

-- **Only a board with the real Clique can answer this**, and the stand-in cannot: what is measured
-- is that the frames Clique itself is holding carry our wiring as well, so the two engines are on
-- one frame rather than one of them having quietly won
-- (`taking-every-unit-frame-with-one-blacklist.md` §1-1).
--
-- **Both of Clique's lists, because they are two doors.** `Clique.ccframes` is what came in from
-- the insecure side and `Clique.hccframes` what its header protocol registered by name -- the
-- second is the one `export_register` fills, and nothing but a real Clique drives it.
--
-- **The kind is not asserted.** These are somebody else's frames and what each one is depends on
-- that board's layout; what a fault here looks like is a frame with no row or no routing at all.
RegisterTest("Clique: the frames Clique holds are wired by us too", {
    description = "진짜 Clique가 들고 있는 개체창에 우리 배선도 같이 걸려 있다",
    applies = function()
        if not DebindPrivate.CliqueDetected then
            return false, "Clique is not installed on this board"
        end
        return true
    end,
    run = function()
        local NAME = "Clique alongside"

        local clique = _G.Clique
        if type(clique) ~= "table" then
            return Fail(NAME, format("the Clique global is not a table (%s)", type(clique)))
        end

        local checked, faults = 0, {}
        local function CheckOne(frame, label)
            if type(frame) ~= "table" or not frame.GetAttribute then
                return
            end
            local row = DebindPrivate.ccframes[frame]
            if row == false then
                -- A frame the addon wrote off (unprotected, forbidden, anchor-tied, no clicks) is
                -- not a fault: those refusals are the same ones every door makes.
                return
            end
            if type(row) ~= "table" then
                faults[#faults + 1] = format("%s has no row of ours (ccframes=%s)",
                    label, tostring(row))
                return
            end
            if frame:GetAttribute("*type-debind1") ~= "click" then
                faults[#faults + 1] = format("%s has a row but no click routing (*type-debind1=%s)",
                    label, tostring(frame:GetAttribute("*type-debind1")))
                return
            end
            checked = checked + 1
        end

        if type(clique.ccframes) == "table" then
            for frame in pairs(clique.ccframes) do
                CheckOne(frame, tostring(frame.GetName and frame:GetName() or frame))
            end
        end
        if type(clique.hccframes) == "table" then
            for name, frame in pairs(clique.hccframes) do
                CheckOne(frame, tostring(name))
            end
        end

        if #faults > 0 then
            return Fail(NAME, table.concat(faults, " | "))
        end
        if checked == 0 then
            return Fail(NAME,
                "Clique is holding no frame we could look at, so nothing here was measured")
        end
        return Pass(NAME, format("%d of Clique's frames carry our row and our routing", checked))
    end,
})

-- **Needs the game, and needs no pack.** What a client alone can answer is whether a frame the
-- switch turned away really goes without the routing and the frametype attribute the secure side
-- reads at the press -- the row is only half of that. The kit adds its own row to
-- `KNOWN_PACK_FRAMES` and takes it back, so this runs on every board rather than on the one that
-- happens to have EllesmereUI installed.
RegisterTest("a pack that is turned off is not wired at all", {
    description = "꺼둔 팩의 개체창은 등록도 배선도 안 된다",
    run = function()
        local NAME = "pack switch";
        local PACK = "DebindPackSwitchTest";
        local FRAME_NAME = "DebindPackSwitchTestFrame";

        if (InCombatLockdown()) then
            return Fail(NAME, "registering a frame is blocked in combat");
        end

        local removeRow = DebindPrivate.AddKnownPackFrameRow("^debindpackswitchtestframe%d+$",
            PACK, "group");

        --- **The pack row comes off last**, after every frame it named has been stepped off: it is
        --- what `PackAddonForFrame` answers from, and the frames below keep their names for the rest
        --- of the session. One function rather than three, because teardowns run newest first and
        --- the frames make theirs after this one.
        local saved = DebindPrivate.optionsAtLogin.frameBlacklist.addons[PACK];
        local made = {};
        AddTeardown(function()
            for i = 1, #made do
                StandDownTestFrame(made[i]);
                made[i]:Hide();
            end
            DebindPrivate.optionsAtLogin.frameBlacklist.addons[PACK] = saved;
            removeRow();
        end);

        local function PackFrame()
            local frame = FreshNamedFrame(FRAME_NAME);
            frame:SetAttribute("unit", "player");
            frame:Show();
            made[#made + 1] = frame;
            return frame;
        end

        DebindPrivate.optionsAtLogin.frameBlacklist.addons[PACK] = false;
        local off = PackFrame();
        DebindPrivate.RegisterFrame(off, "group");

        if (DebindPrivate.ccframes[off] ~= nil) then
            return Fail(NAME, format("the switch is off and the frame still has a row (%s)",
                tostring(DebindPrivate.ccframes[off])));
        end
        if (off:GetAttribute("debind_frametype") ~= nil) then
            return Fail(NAME, format("the switch is off and the frame carries debind_frametype %s",
                tostring(off:GetAttribute("debind_frametype"))));
        end
        if (off:GetAttribute("*type-debind1") ~= nil) then
            return Fail(NAME, "the switch is off and the frame's clicks are still routed to us");
        end

        -- The other half: with the same row on, a frame with the same name gets everything.
        DebindPrivate.optionsAtLogin.frameBlacklist.addons[PACK] = nil;
        local on = PackFrame();
        DebindPrivate.RegisterFrame(on, "group");

        local fault = CheckWiredFrame(on, on:GetName(), Constants.FRAMETYPE_GROUP);
        if (fault) then
            return Fail(NAME, "the switch is on and " .. fault);
        end
        return Pass(NAME, "off: no row, no frametype, no routing; on: wired");
    end,
})

-- **The kind is read off these**, because each stands for one unit and carries it before anything
-- else touches it. So this pins the reading as much as the registration: a player frame that came
-- out a group frame would take the reader's party bindings.
--
-- **HoverCast is not a condition any more.** Whichever way the pack has it set, its frames reach us
-- -- through the Clique shape while it is off, and through the name door while it is on, with us
-- standing on top of whatever it wrapped either way.
RegisterTest("EllesmereUI: the single unit frames are wired, and read for what they are", {
    description = "EUI 개체창이 종류대로 등록되어 있다",
    applies = EllesmereLoaded(EUI_UNITFRAMES_FRAME),
    run = function()
        return CheckNamedFrames("EUI unit frames", {
            { "EllesmereUIUnitFrames_Player",       Constants.FRAMETYPE_PLAYER },
            { "EllesmereUIUnitFrames_Pet",          Constants.FRAMETYPE_PET },
            { "EllesmereUIUnitFrames_Target",       Constants.FRAMETYPE_TARGET },
            { "EllesmereUIUnitFrames_Focus",        Constants.FRAMETYPE_TARGET },
            { "EllesmereUIUnitFrames_TargetTarget", Constants.FRAMETYPE_TARGET },
            { "EllesmereUIUnitFrames_FocusTarget",  Constants.FRAMETYPE_TARGET },
            { "EllesmereUIUnitFrames_Boss1",        Constants.FRAMETYPE_BOSS },
            { "EllesmereUIUnitFrames_Boss2",        Constants.FRAMETYPE_BOSS },
            { "EllesmereUIUnitFrames_Boss3",        Constants.FRAMETYPE_BOSS },
            { "EllesmereUIUnitFrames_Boss4",        Constants.FRAMETYPE_BOSS },
            { "EllesmereUIUnitFrames_Boss5",        Constants.FRAMETYPE_BOSS },
        });
    end,
})

-- **The kind is declared for these**, so what this pins is the declaration reaching the frame. Two
-- of them would read as something else: the self slot holds `player` and the friendly-NPC frames
-- hold a boss token, and both are drawn in the party or raid block.
RegisterTest("EllesmereUI: the standalone party and raid frames are wired as group frames", {
    description = "EUI 파티 내 칸·아군 NPC 칸·복제본이 그룹 프레임으로 등록되어 있다",
    applies = EllesmereLoaded(EUI_RAIDFRAMES_FRAME),
    run = function()
        local entries = {
            { "ERFPartySelfButton", Constants.FRAMETYPE_GROUP },
        };
        for i = 1, 5 do
            entries[#entries + 1] = { "ERFFriendlyBoss" .. i, Constants.FRAMETYPE_GROUP };
        end
        -- The duplicates are capped in the pack's own file and that number is not ours to keep, so
        -- this walks until the names run out rather than up to a count written down here.
        local i = 1;
        while (_G["ERFExtraFrame" .. i]) do
            entries[#entries + 1] = { "ERFExtraFrame" .. i, Constants.FRAMETYPE_GROUP };
            i = i + 1;
        end
        return CheckNamedFrames("EUI standalone group frames", entries);
    end,
})

-- **The header children, which arrive through a different door entirely** -- the hook on
-- `SecureGroupHeader_Update`. They are here beside the standalone frames because the reader cannot
-- tell the two apart on screen: four slots of a party block come through the header and the fifth
-- does not, and that is exactly the shape of the fault that started all of this.
RegisterTest("EllesmereUI: the header's own children are wired as group frames", {
    description = "EUI 파티·공대 헤더 자식이 그룹 프레임으로 등록되어 있다",
    applies = EllesmereLoaded(EUI_RAIDFRAMES_FRAME),
    run = function()
        local NAME = "EUI header children";
        local HEADERS = { "ERFPartyHeader", "ERFFlatHeader",
            "ERFGroupHeader1", "ERFGroupHeader2", "ERFGroupHeader3", "ERFGroupHeader4",
            "ERFGroupHeader5", "ERFGroupHeader6", "ERFGroupHeader7", "ERFGroupHeader8" };

        local checked, faults, headersSeen = 0, {}, {};
        for h = 1, #HEADERS do
            local header = _G[HEADERS[h]];
            if (header and header.GetAttribute) then
                headersSeen[#headersSeen + 1] = HEADERS[h];
                local i = 1;
                while (true) do
                    local child = header:GetAttribute("child" .. i);
                    if (not child) then
                        break;
                    end
                    local fault = CheckWiredFrame(child, HEADERS[h] .. " child" .. i,
                        Constants.FRAMETYPE_GROUP);
                    if (fault) then
                        faults[#faults + 1] = fault;
                    else
                        checked = checked + 1;
                    end
                    i = i + 1;
                end
            end
        end

        if (#headersSeen == 0) then
            return Fail(NAME, "the pack's headers are not there under the names this test knows");
        end
        if (#faults > 0) then
            return Fail(NAME, table.concat(faults, " | "));
        end
        if (checked == 0) then
            return Fail(NAME, format("%d header(s) stood up and not one child is registered: %s",
                #headersSeen, table.concat(headersSeen, ", ")));
        end
        return Pass(NAME, format("%d children wired across %s", checked, table.concat(headersSeen, ", ")));
    end,
})

-- **The same rule against the pack that actually does this.** EUI puts its own proxy over the name
-- when its hover casting is on, and from then on it decides frame by frame. The name stays theirs
-- and the writes keep landing there; what a board answers that no harness can is whether the proxy
-- is one we can stand behind at all -- a table locked with `__metatable` would be left alone
-- entirely, and this case would then be measuring a frame nobody wired.
--
-- **The frame comes to us whichever way the pack decided.** That is the change: keeping a frame
-- used to be the pack saying it was not ours, and now it only says the pack is on it too.
RegisterTest("EllesmereUI: HoverCast on leaves the name with the pack", {
    description = "HoverCast를 켠 EUI가 ClickCastFrames를 쥐고 있고, 프레임은 우리에게도 온다",
    applies = function()
        local ok, why = EllesmereLoaded(EUI_UNITFRAMES_FRAME)();
        if (not ok) then
            return false, why;
        end
        if (type(_G._ERF_IsHoverCastEnabled) ~= "function") then
            return false, "the pack does not answer _ERF_IsHoverCastEnabled on this board";
        end
        if (not _G._ERF_IsHoverCastEnabled()) then
            return false, "HoverCast is off, so the pack hands its frames over and never takes the name";
        end
        return true;
    end,
    run = function()
        local NAME = "EUI holds ClickCastFrames"

        if InCombatLockdown() then
            return Fail(NAME, "registering a frame is blocked in combat")
        end

        local held = _G.ClickCastFrames
        if type(held) ~= "table" then
            return Fail(NAME, format("ClickCastFrames is not a table (%s)", type(held)))
        end
        if getmetatable(held) == nil then
            return Fail(NAME, "the name carries a plain table, so the pack is not holding it and this case is standing in the wrong place")
        end

        -- **Built without a registration**, so the write below is what registers it.
        local frame = MakeTestUnitFrame(UNIT_TOKEN_ABSENT)

        _G.ClickCastFrames[frame] = true
        local answered = held[frame]
        local row = DebindPrivate.ccframes[frame]
        AddTeardown(function()
            if not InCombatLockdown() then
                _G.ClickCastFrames[frame] = nil
            end
        end)

        if _G.ClickCastFrames ~= held then
            return Fail(NAME, "the pack's table was replaced, which loses every frame already written into it")
        end
        if type(row) ~= "table" then
            return Fail(NAME, format("the frame never reached us (ccframes=%s, the pack answered %s)",
                tostring(row), tostring(answered)))
        end

        return Pass(NAME, answered
            and "the pack kept the test frame, the name stayed theirs, and we took it as well"
            or "the pack dropped the test frame and we took it")
    end,
})

--- HealBot's button names, built the way `HealBot_Action_CreateNewButton` builds them so that a
--- board can be asked which of them exist. `hbTest_` is left out here for the same reason it is
--- left off `KNOWN_PACK_FRAMES`, and the case below asks about it separately.
local HEALBOT_PREFIXES = {
    "HealBot_", "hbPet_", "hbVehicle_", "hbPrivTar_", "hbUnitTar_", "hbEnemy_", "hbExtra_",
};

--- Every HealBot button standing on this board, as `CheckNamedFrames` entries.
---
--- **Walked by name rather than read out of HealBot's own tables**, because what is being measured
--- is whether our door reached the frames a reader can actually hover, and a name is what the
--- reader's screen and our row list have in common. The ids are HealBot's: real buttons run from 1
--- and stop below 500, which is where its test bars start (`HealBot_ButtonSeq`).
local function HealBotFrames()
    local entries = {};
    for i = 1, #HEALBOT_PREFIXES do
        local prefix = HEALBOT_PREFIXES[i];
        local emergency = (prefix == "HealBot_") and "HB_" or prefix;
        for id = 1, 499 do
            if (_G[prefix .. "HealUnit" .. id]) then
                entries[#entries + 1] = { prefix .. "HealUnit" .. id, Constants.FRAMETYPE_GROUP };
                entries[#entries + 1] = { emergency .. "EmergUnit" .. id, Constants.FRAMETYPE_GROUP };
            end
        end
    end
    return entries;
end

--- **Only a board with HealBot can answer this, and it is the one pack no other door reaches.**
--- HealBot writes nothing into `ClickCastFrames`, speaks no header protocol, hangs its buttons off
--- a plain frame and ships no oUF -- so what the headless spec proves is that the door works when
--- it is called, and what only the game says is whether `hooksecurefunc` on that addon's own
--- function takes at all, and whether the name it is asked for is still the name that addon uses.
---
--- **A board with no buttons built yet is not an answer.** HealBot makes them on a refresh its own
--- timers drive, so `applies` asks for one rather than letting the case pass on an empty walk.
RegisterTest("HealBot: its buttons come in through its own door", {
    description = "힐봇 버튼과 짝인 비상 버튼이 우리 배선을 달고 있다",
    applies = function()
        if (not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("HealBot"))) then
            return false, "HealBot is not loaded on this board";
        end
        if (not DebindPrivate.TakesPackFrames("HealBot")) then
            return false, "HealBot is turned off in this profile";
        end
        if (#HealBotFrames() == 0) then
            return false, "HealBot has not built a button yet on this board";
        end
        return true;
    end,
    run = function()
        local NAME = "HealBot door";

        --- **The bars the options panel shows while somebody arranges the display.** They are made
        --- by the same call and carry the same shape as a real button, so only the name keeps them
        --- out -- and a board with none of them up says nothing either way.
        for id = 500, 997 do
            local bar = _G["hbTest_HealUnit" .. id];
            if (bar and DebindPrivate.ccframes[bar] ~= nil) then
                return Fail(NAME, format("hbTest_HealUnit%d was taken for a unit frame (ccframes=%s)",
                    id, tostring(DebindPrivate.ccframes[bar])));
            end
        end

        return CheckNamedFrames(NAME, HealBotFrames());
    end,
})
