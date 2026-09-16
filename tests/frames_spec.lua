-- Registering a unit frame for click-casting, and resolving a custom target.
--
-- **Registration refuses quietly, and remembers the refusal.** A frame that is not protected, is
-- forbidden, has its anchors tied, or cannot be told what to do with a click, is written off and
-- never asked again -- with nothing said anywhere. Left unchecked, a test drives a frame the addon
-- is not watching, reads an empty slot, and reports a bug that is not there; that is a rule in
-- `devdocs/testing-a-change.md` because it happened.
--
-- Neither of these needed a client. What kept them out of the harness was that `FrameRegistry.lua`
-- and `UnitWatch.lua` build frames when they load, and the line has moved: a frame shell is what
-- the harness gives them now (`devdocs/legacy/going-headless-outside-the-ui.md`).

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");

    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    --- A unit frame the way another addon would hand one over: protected, not forbidden, and
    --- able to take clicks. `flaws` turns one of those off.
    local function UnitFrame(flaws)
        local frame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
        flaws = flaws or {};
        if (flaws.unprotected) then
            frame.IsProtected = function() return false; end
        end
        if (flaws.forbidden) then
            frame.IsForbidden = function() return true; end
        end
        if (flaws.anchored) then
            frame.IsAnchoringRestricted = function() return true; end
        end
        -- **Shadowed with `false` rather than removed.** The shell's methods live on a metatable,
        -- so assigning nil here would let the inherited one show through again. What the addon
        -- asks is `not button.RegisterForClicks`, and a falsy field answers that the same way a
        -- frame that never had the method does.
        if (flaws.noClicks) then
            frame.RegisterForClicks = false;
        end
        return frame;
    end

    ---------------------------------------------------------------------------
    -- What registration does
    ---------------------------------------------------------------------------

    -- The frame type is stamped **on the frame**, because the secure side reads it back there when
    -- the cursor arrives -- a record with a `frameTypes` condition has nothing else to compare
    -- against.
    test("a registered frame carries the type its records will be matched on", function()
        local frame = UnitFrame();
        DebindPrivate.RegisterFrame(frame, "group");

        local info = DebindPrivate.ccframes[frame];
        check(type(info) == "table", "the frame was refused: " .. tostring(info));
        check(info.frameType == Constants.FRAMETYPE_GROUP,
            "frameType: " .. tostring(info.frameType));
        check(frame:GetAttribute("debind_frametype") == Constants.FRAMETYPE_GROUP,
            "the attribute does not match what was recorded");
    end);

    -- **A type nobody listed is `unknown`, not nothing.** Falling through to nil would leave the
    -- comparison on the secure side with no value at all, and a hover record with a frame type
    -- condition would then match a frame the reader never described.
    test("an unlisted frame type registers as unknown", function()
        local frame = UnitFrame();
        DebindPrivate.RegisterFrame(frame, "somebodyelsesframe");
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_UNKNOWN,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    -- Enter and leave are what fill the hover slot, so a registration that skipped them would
    -- leave a frame that is watched and never reports anything.
    test("registering wraps the frame's enter and leave", function()
        local frame = UnitFrame();
        local mark = frames.mark();
        DebindPrivate.RegisterFrame(frame, "target");
        local entries = frames.since(mark);

        local wrapped = {};
        for i = 1, #entries do
            if (entries[i].kind == "WrapScript") then
                wrapped[entries[i].name] = true;
            end
        end
        check(wrapped.OnEnter, "OnEnter was not wrapped");
        check(wrapped.OnLeave, "OnLeave was not wrapped");
    end);

    ---------------------------------------------------------------------------
    -- Working the type out when nobody supplies one
    ---------------------------------------------------------------------------

    --- A frame the way another addon hands one over through `ClickCastFrames`: the Clique
    --- protocol carries no category, so the second argument is whatever that addon put in the
    --- table and never one of our names.
    local function ForeignFrame(name, unit)
        local frame = frames.newFrame("Button", name, nil, "SecureUnitButtonTemplate");
        if (unit) then
            frame:SetAttribute("unit", unit);
        end
        return frame;
    end

    -- Every frame any other unit frame addon hands over arrived as `unknown`, because the only
    -- thing feeding the category table was our own Blizzard registration.
    test("a frame nobody described is read off its own unit", function()
        local CASES = {
            { "target", Constants.FRAMETYPE_TARGET },
            { "focus", Constants.FRAMETYPE_TARGET },
            { "targettarget", Constants.FRAMETYPE_TARGET },
            { "pet", Constants.FRAMETYPE_PET },
            { "party2", Constants.FRAMETYPE_GROUP },
            { "raid17", Constants.FRAMETYPE_GROUP },
            { "boss3", Constants.FRAMETYPE_BOSS },
            { "arena1", Constants.FRAMETYPE_ARENA },
            { "player", Constants.FRAMETYPE_PLAYER },
        };
        for i = 1, #CASES do
            local frame = ForeignFrame(nil, CASES[i][1]);
            DebindPrivate.RegisterFrame(frame, true);
            check(DebindPrivate.ccframes[frame].frameType == CASES[i][2],
                CASES[i][1] .. ": " .. tostring(DebindPrivate.ccframes[frame].frameType));
        end
    end);

    -- **The one token that lies.** A party frame set has five slots and only four party units, so
    -- the slot holding you carries `player` -- Blizzard's compact container does it, and so does a
    -- unit frame addon that draws its own party block, sometimes with the token written on the
    -- frame for good. Reading the unit alone calls that frame the player frame, which is the one
    -- place the name gets asked.
    test("a party frame holding the player is still a party frame", function()
        local frame = ForeignFrame("SomeUIPartySelfButton", "player");
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_GROUP,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    -- The player frame of the same addon, so the case above is not passing by refusing `player`
    -- outright.
    test("a frame named for the player is the player frame", function()
        local frame = ForeignFrame("SomeUIUnitFrames_Player", "player");
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_PLAYER,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    -- **And the name is asked nowhere else**, because an addon puts its own prefix in every name
    -- it makes. This pack is named for a group frame, so every frame it draws carries the word,
    -- and its target frame would answer group to anything that read the name before the unit.
    test("an addon named for a group frame does not make all its frames group frames", function()
        local frame = ForeignFrame("PartyPixelUI_TargetFrame", "target");
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_TARGET,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    --- A child of a `SecureGroupHeaderTemplate` header, handed over the way a unit frame addon
    --- does it: from the addon's own styling pass, with the header holding no unit for that slot.
    local function HeaderChild(name, unit, onEvent)
        local header = frames.newFrame("Frame", "SomeUIPartyHeader", nil, "SecureGroupHeaderTemplate");
        header:SetScript("OnEvent", onEvent or SecureGroupHeader_OnEvent);
        local frame = frames.newFrame("Button", name, header, "SecureUnitButtonTemplate");
        if (unit) then
            frame:SetAttribute("unit", unit);
        end
        return frame;
    end

    -- **The header takes the unit away and gives it back**, so an empty slot says nothing about
    -- the frame. A header that is showing nobody has just written nil over every slot it owns,
    -- and that is the state the addon's styling pass hands the child over in.
    test("a header child with no unit is a group frame", function()
        local frame = HeaderChild("SomeUIPartyHeaderUnitButton1", nil);
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_GROUP,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    -- A pet header's children are group frames too, which is what the header door already calls
    -- every child that arrives through it.
    test("a pet header child is a group frame", function()
        local frame = HeaderChild(nil, nil, SecureGroupPetHeader_OnEvent);
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_GROUP,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    -- **Being parented to something is not being a header child.** A pack anchors its frames to
    -- its own container, and that container answers none of Blizzard's scripts.
    test("a frame parented to an ordinary frame is read off its own unit", function()
        local container = frames.newFrame("Frame", "SomeUIPartyContainer");
        local frame = frames.newFrame("Button", "SomeUIPartyTarget", container, "SecureUnitButtonTemplate");
        frame:SetAttribute("unit", "target");
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_TARGET,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    --- **A pack whose frames say what they are in the name, whatever unit they are holding.**
    --- VuhDo's panels are group frames; a panel can be filled with pets or with the targets of the
    --- people in it, and every button in one is still a slot in a group display.
    local function VuhDoButton(name, unit)
        local frame = frames.newFrame("Button", name, nil, "VuhDoButtonSecureTemplate");
        frame:SetAttribute("unit", unit);
        return frame;
    end

    test("every button of a VuhDo panel is a group frame", function()
        local CASES = {
            { "Vd1H1", "player" },
            { "Vd10H51", "raid7" },
            { "Vd4H2", "partypet1" },
            { "Vd4H3", "raidpet12" },
            { "Vd1H1Tg", "raid3target" },
            { "Vd1H1Tot", "raid3targettarget" },
        };
        for i = 1, #CASES do
            local frame = VuhDoButton(CASES[i][1], CASES[i][2]);
            DebindPrivate.RegisterFrame(frame, true);
            check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_GROUP,
                CASES[i][1] .. " (" .. CASES[i][2] .. "): "
                .. tostring(DebindPrivate.ccframes[frame].frameType));
        end
    end);

    -- **`unknown` closes nothing.** A frame library can write the unit attribute *after* the
    -- styling pass that registers the frame, so the first call has nothing to read, and the addon
    -- on top of it registers the finished frame a second time. Standing down on the type matching
    -- spent that second call.
    test("a frame that could not be read is asked again", function()
        local frame = ForeignFrame(nil, nil);
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_UNKNOWN,
            "the first pass should have had nothing to go on");

        frame:SetAttribute("unit", "target");
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_TARGET,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);
    ---------------------------------------------------------------------------
    -- Fetching what another addon's table swallowed
    ---------------------------------------------------------------------------

    --- The addon list the collector walks, shaped the way the game's is: **fixed before the first
    --- pass.** `X-oUF` is read out of the `.toc`, which the client has parsed for every addon by
    --- the time anything runs, so the collector walks the list once and works off the names it
    --- found. A library declared here after that first pass would be one the game could not have
    --- produced, and the collector would rightly never see it.
    local oufAddons = {};

    local function DeclareOUFLibrary(objects)
        local name = "SomeUIoUF" .. (#oufAddons + 1);
        oufAddons[#oufAddons + 1] = name;
        _G[name] = { objects = objects };
        return name;
    end

    --- One pass, with those addons standing where `GetAddOnMetadata` can find them.
    local function CollectOUFFrames()
        local realNum = _G.C_AddOns.GetNumAddOns;
        local realMeta = _G.C_AddOns.GetAddOnMetadata;
        _G.C_AddOns.GetNumAddOns = function() return #oufAddons; end
        _G.C_AddOns.GetAddOnMetadata = function(i, field)
            if (field == "X-oUF") then
                return oufAddons[i];
            end
        end

        local ok, err = pcall(DebindPrivate.CollectOUFFrames);

        _G.C_AddOns.GetNumAddOns = realNum;
        _G.C_AddOns.GetAddOnMetadata = realMeta;
        if (not ok) then
            error(err, 0);
        end
    end

    -- **These frames were addressed to us and went somewhere else.** A frame library writes every
    -- frame it builds into `ClickCastFrames`, and a unit frame addon running click casting of its
    -- own can put its own table over that global first, so the writes land there and we never hear
    -- of them. Getting the global back afterwards does not get the frames back, and the other
    -- table cannot be read out of. So the library is asked instead, through the `X-oUF` global it
    -- publishes itself under.
    --
    -- **One test, because the collector remembers across passes and so does a session.** The list
    -- it reads keeps growing -- a header gets more children as the roster does, a frame spawned
    -- later lands on the end -- so what has to be shown is a sequence: the frames standing at the
    -- first pass, then the ones appended after it, then that a pass with nothing new offers
    -- nothing. Split into three, each would be starting from the other two's marks.
    test("a library's frames are fetched, and the ones appended after them", function()
        local first = { ForeignFrame(nil, "party1"), ForeignFrame(nil, "party2") };
        -- A second library, to show the mark is kept per library rather than as one number. An
        -- addon is free to carry its own copy of oUF under its own global.
        local second = { ForeignFrame(nil, "target") };
        DeclareOUFLibrary(first);
        DeclareOUFLibrary(second);

        CollectOUFFrames();
        for i = 1, 2 do
            local seen = DebindPrivate.ccframes[first[i]];
            check(seen and seen.frameType == Constants.FRAMETYPE_GROUP,
                "first library, object " .. i .. ": " .. tostring(seen and seen.frameType));
        end
        check(DebindPrivate.ccframes[second[1]], "the second library was never asked");

        -- Nothing new: the mark is what makes a pass on every loading screen cost nothing.
        local offered = 0;
        local realRegister = DebindPrivate.RegisterFrame;
        DebindPrivate.RegisterFrame = function(...)
            offered = offered + 1;
            return realRegister(...);
        end
        CollectOUFFrames();
        DebindPrivate.RegisterFrame = realRegister;
        check(offered == 0, "a pass over nothing new offered " .. offered .. " frames again");

        -- And the tail each library grew since.
        first[3] = ForeignFrame(nil, "party3");
        second[2] = ForeignFrame(nil, "focus");
        CollectOUFFrames();
        check(DebindPrivate.ccframes[first[3]],
            "the frame appended to the first library was never offered");
        check(DebindPrivate.ccframes[second[2]],
            "the frame appended to the second library was never offered");

        -- **And a frame another door has already answered for is left standing.** Header children
        -- land in this list too -- `initObject` appends before the branch that separates a spawned
        -- frame from a header's child -- and the header is the door that knows what they are: it
        -- hands a child whichever unit it is filling and takes it back, so the token says which
        -- slot and not which frame. A party block's self slot carries `player`, so a pass that
        -- re-read this one would hand it back as the player frame on the next loading screen, and
        -- the next roster change would hand it to the header again.
        local child = ForeignFrame("SomeUIHeaderUnitButton1", "player");
        local header = frames.newFrame("Frame", nil, nil, "SecureGroupHeaderTemplate");
        header:SetAttribute("child1", child);
        SecureGroupHeader_Update(header);
        check(DebindPrivate.ccframes[child]
            and DebindPrivate.ccframes[child].frameType == Constants.FRAMETYPE_GROUP,
            "the header did not answer for its own child");

        first[4] = child;
        CollectOUFFrames();
        check(DebindPrivate.ccframes[child].frameType == Constants.FRAMETYPE_GROUP,
            "the library pass read the header's child back as "
                .. tostring(DebindPrivate.ccframes[child].frameType));

        -- **And a spare child has no unit to be read off at all**, which is the same fault without
        -- needing a name to go wrong. A group that shrinks leaves its extra children hidden with
        -- the unit taken back off them (`configureChildren`), so re-reading one answers `unknown`
        -- and the frame stops matching the group records the reader bound.
        local spare = ForeignFrame("SomeUIHeaderUnitButton9", "raid9");
        header:SetAttribute("child2", spare);
        SecureGroupHeader_Update(header);
        check(DebindPrivate.ccframes[spare].frameType == Constants.FRAMETYPE_GROUP,
            "the header did not answer for the spare child");

        spare:SetAttribute("unit", nil);
        first[5] = spare;
        CollectOUFFrames();
        check(DebindPrivate.ccframes[spare].frameType == Constants.FRAMETYPE_GROUP,
            "the emptied child came back as "
                .. tostring(DebindPrivate.ccframes[spare].frameType));
    end);

    ---------------------------------------------------------------------------
    -- The frames a pack keeps to itself, taken by name
    ---------------------------------------------------------------------------

    --- The secure header another addon runs its own click casting through.
    local function ForeignHeader()
        return frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
    end

    -- **These arrive through no protocol at all.** A pack running its own click casting registers
    -- its frames nowhere, and these are not a group header's children either: a party block's self
    -- slot, the boss frames and the duplicates of chosen raid members are all standalone, because
    -- their units are fixed or picked rather than rostered. So the moment a pack wires one up is
    -- what is listened for, and the name decides whether to take it.
    --
    -- **The kind comes from the list and not from the frame.** A duplicate is wired up two lines
    -- after it is made and gets its unit later, so the pass that could read one has nothing to
    -- read -- and the pack wraps each frame once, so there is no second pass.
    test("a pack's own frames are taken by name as it wires them up", function()
        local CASES = {
            { "ERFPartySelfButton", "player", Constants.FRAMETYPE_GROUP },
            -- **Carries a boss unit and is not a boss frame.** The friendly NPC an encounter puts
            -- on a boss token is drawn in the raid block to be healed, so reading the unit would
            -- answer with the enemy's bar off to the side. The list overrules it.
            { "ERFFriendlyBoss3", "boss3", Constants.FRAMETYPE_GROUP },
            { "ERFExtraFrame7", nil, Constants.FRAMETYPE_GROUP },
            -- **Read, not declared.** A frame standing for one unit and no other carries it
            -- before anything else touches it, and it cannot move, so a row saying the kind
            -- would only be a second place to keep the same answer.
            { "EllesmereUIUnitFrames_Player", "player", Constants.FRAMETYPE_PLAYER },
            { "EllesmereUIUnitFrames_Boss2", "boss2", Constants.FRAMETYPE_BOSS },
            { "EllesmereUIUnitFrames_TargetTarget", "targettarget", Constants.FRAMETYPE_TARGET },
            -- Two more rows, one of each kind: one declared and one left to the reading.
            { "Vd1H1Tg", "raid3target", Constants.FRAMETYPE_GROUP },
            { "Grid2LayoutHeader1UnitButton3", "raid5", Constants.FRAMETYPE_GROUP },
            { "ElvUF_Focus", "focus", Constants.FRAMETYPE_TARGET },
        };
        for i = 1, #CASES do
            local frame = ForeignFrame(CASES[i][1], CASES[i][2]);
            SecureHandlerWrapScript(frame, "OnEnter", ForeignHeader(), "-- theirs");
            local info = DebindPrivate.ccframes[frame];
            check(type(info) == "table",
                CASES[i][1] .. " never arrived: " .. tostring(info));
            check(info.frameType == CASES[i][3],
                CASES[i][1] .. " frameType: " .. tostring(info.frameType));
        end
    end);

    -- **A row's kind is the frame's kind whichever door it came through.** These same frames also
    -- arrive through the Clique shape, which carries no kind, and reading one there answered with
    -- the unit -- so a frame came out group or boss depending on which call reached it first.
    test("a named frame's kind does not depend on the door", function()
        local frame = ForeignFrame("ERFFriendlyBoss1", "boss1");
        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame].frameType == Constants.FRAMETYPE_GROUP,
            "frameType: " .. tostring(DebindPrivate.ccframes[frame].frameType));
    end);

    --- Runs `fn` with the pack list standing at `packs`, and puts back whatever was there.
    local function withPacks(packs, fn)
        local saved = DebindPrivate.optionsAtLogin.frameBlacklist;
        DebindPrivate.optionsAtLogin.frameBlacklist = { blizzard = {}, addons = packs };
        local ok, err = pcall(fn);
        DebindPrivate.optionsAtLogin.frameBlacklist = saved;
        if (not ok) then
            error(err, 0);
        end
    end

    -- **A pack turned off is turned off at every door**, because the switch is asked where all of
    -- them meet. Half an answer is worse than either: a frame with no row still carrying our
    -- wrapper runs a body that then declines, on every hover.
    test("a pack that is turned off arrives through no door", function()
        local clique = ForeignFrame("ERFFriendlyBoss4", "boss4");
        local named = ForeignFrame("ERFExtraFrame9", nil);
        local other = ForeignFrame("EllesmereUIUnitFrames_Target", "target");

        withPacks({ EllesmereUIRaidFrames = false }, function()
            DebindPrivate.RegisterFrame(clique, true);
            SecureHandlerWrapScript(named, "OnEnter", ForeignHeader(), "-- theirs");
            SecureHandlerWrapScript(other, "OnEnter", ForeignHeader(), "-- theirs");
        end);

        check(DebindPrivate.ccframes[clique] == nil,
            "the Clique door registered a pack that is off: "
            .. tostring(DebindPrivate.ccframes[clique]));
        check(DebindPrivate.ccframes[named] == nil,
            "the name door registered a pack that is off: "
            .. tostring(DebindPrivate.ccframes[named]));
        -- **The switch is one pack's**, and the rows carry the addon so that it can be.
        check(type(DebindPrivate.ccframes[other]) == "table",
            "turning one pack off took another one with it");
    end);

    -- **A pack box reaches its own pack and nothing else.** A name no row covers is nobody's to
    -- leave alone, so the only thing that can turn one away is being on the blacklist by name.
    test("a pack box reaches only the pack it names", function()
        local unlisted = ForeignFrame("SomeUIUnitFrame1", "target");

        withPacks({ EllesmereUIRaidFrames = false, EllesmereUIUnitFrames = false, VuhDo = false },
            function()
                DebindPrivate.RegisterFrame(unlisted, true);
            end);

        check(type(DebindPrivate.ccframes[unlisted]) == "table",
            "a pack box turned away a frame that is not that pack's: "
            .. tostring(DebindPrivate.ccframes[unlisted]));
    end);

    --- Runs `fn` with the `Any Other Addon` box standing at `taken`, and puts back what was there.
    local function withOtherAddons(taken, fn)
        local blacklist = DebindPrivate.optionsAtLogin.frameBlacklist;
        local other;
        if (not taken) then
            other = false;
        end
        DebindPrivate.optionsAtLogin.frameBlacklist =
            { blizzard = {}, addons = {}, other = other };
        local ok, err = pcall(fn);
        DebindPrivate.optionsAtLogin.frameBlacklist = blacklist;
        if (not ok) then
            error(err, 0);
        end
    end

    --- **`Any Other Addon` takes every name no row covers**, which is the last way out for somebody
    --- whose frames are broken by an addon we have never seen. Without it the only answer is to wait
    --- for that name to reach `KNOWN_PACK_FRAMES`, which is our way out and not theirs.
    ---
    --- **The addon that hands its frames over goes with the rest**, and that is the decision rather
    --- than an oversight: "handed over" is the Clique API's vocabulary and no tooltip can draw the
    --- line, so the last resort is blunt on purpose. The Clique door is what this drives for that
    --- reason.
    --- **One door is enough to drive because there is one gate.** `RegisterFrame` is where every
    --- door meets and where the question is asked, which the pack box's own tests already pin; the
    --- name door cannot even be used here, since a name no row covers never reaches it.
    test("Any Other Addon turns away every name no row covers", function()
        local offered = ForeignFrame("SomeUIUnitFrame42", "target");

        withOtherAddons(false, function()
            DebindPrivate.RegisterFrame(offered, true);
        end);

        check(DebindPrivate.ccframes[offered] == nil,
            "an addon that handed its frame over was taken anyway: "
            .. tostring(DebindPrivate.ccframes[offered]));

        --- 반대쪽 절반. 상자를 안 켰을 때 같은 프레임이 우리 것이어야, 위가 "언제나 거절"이 아닌
        --- 것이 된다.
        local taken = ForeignFrame("SomeUIUnitFrame43", "target");
        withOtherAddons(true, function()
            DebindPrivate.RegisterFrame(taken, true);
        end);
        check(type(DebindPrivate.ccframes[taken]) == "table",
            "the box is off and an unknown addon's frame was still turned away: "
            .. tostring(DebindPrivate.ccframes[taken]));
    end);

    --- **이름 문이 이름을 모를 때 프레임 자신에게 묻는다.**
    ---
    --- `Any Other Addon`이 켜져 있으면 모르는 애드온의 개체창도 우리 것인데, 그 프레임에 닿는
    --- 길이 이름 문뿐이고 그 문은 `KNOWN_PACK_FRAMES`에 든 이름만 통과시킨다. 그래서 약속과
    --- 실제가 갈렸다: 모르는 애드온이라 상자가 덮는다면서, 모르는 이름이라 안 받았다.
    ---
    --- **`SecureUnitButtonTemplate`이 `OnClick`에 거는 것은 전역 함수 자신이고**
    --- (`SecureTemplates.xml`의 `<OnClick function="SecureUnitButton_OnClick"/>`), 시전 버튼
    --- 템플릿은 인라인 본문이라 프레임마다 다른 클로저가 걸린다. 그래서 이 비교는 시전 버튼을
    --- 구조적으로 못 통과시킨다.
    test("이름을 모르는 애드온의 개체창은 프레임 자신이 답한다", function()
        local unitButton = ForeignFrame("SomeUIWeHaveNeverSeen1", "party1");
        SecureHandlerWrapScript(unitButton, "OnEnter", unitButton, "-- theirs");

        check(type(DebindPrivate.ccframes[unitButton]) == "table",
            "이름 없는 개체창이 이름 문에서 그냥 돌아갔다: "
            .. tostring(DebindPrivate.ccframes[unitButton]));

        --- 반대쪽. 같은 문으로 도착하지만 개체창이 아닌 것은 안 받아야 한다. 없으면 위 케이스가
        --- "무엇이든 받는다"에도 초록으로 나온다.
        local castButton = frames.newFrame("Button", "SomeUICastButton1", nil,
            "SecureActionButtonTemplate");
        SecureHandlerWrapScript(castButton, "OnEnter", castButton, "-- theirs");

        check(DebindPrivate.ccframes[castButton] == nil,
            "시전 버튼이 개체창으로 잡혔다: " .. tostring(DebindPrivate.ccframes[castButton]));
    end);

    --- 반대쪽. 없이는 위 케이스가 "언제나 거절"에도 초록으로 나온다.
    test("a known pack and Blizzard's own are not what Any Other Addon covers", function()
        local pack = ForeignFrame("ERFExtraFrame41", nil);
        local blizzard = ForeignFrame("SomeBlizzardLikeFrame41", "target");

        withOtherAddons(false, function()
            --- **Blizzard's are exempt by being in `blizzardFrames`**, which is the only list that
            --- says a frame came through that door. Their own seven boxes are what takes them out.
            DebindPrivate.blizzardFrames[blizzard] = "target";
            DebindPrivate.RegisterFrame(pack, true);
            DebindPrivate.RegisterFrame(blizzard, "target");
            DebindPrivate.blizzardFrames[blizzard] = nil;
        end);

        check(type(DebindPrivate.ccframes[pack]) == "table",
            "a known pack went out with the unknown ones: " .. tostring(DebindPrivate.ccframes[pack]));
        check(type(DebindPrivate.ccframes[blizzard]) == "table",
            "one of the client's own frames went out with the unknown ones: "
            .. tostring(DebindPrivate.ccframes[blizzard]));
    end);

    -- **Every door takes what nobody named, which is the whole decision.** The frames a pack keeps
    -- to itself used to sit behind an option, and the option is gone
    -- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md` §1-3): a listed name and a
    -- name no row covers arrive the same way at each of the three.
    test("every door takes a listed name and a name no row covers alike", function()
        local named = ForeignFrame("ERFExtraFrame41", nil);
        local child = ForeignFrame("ERFExtraFrame42", "raid3");
        local strayChild = ForeignFrame("SomeUIHeaderUnitButton42", "raid4");
        local spawned = ForeignFrame("EllesmereUIUnitFrames_Focus2", "focus");
        local straySpawned = ForeignFrame("SomeUIUnitFrame43", "focus");

        SecureHandlerWrapScript(named, "OnEnter", ForeignHeader(), "-- theirs");

        local header = frames.newFrame("Frame", nil, nil, "SecureGroupHeaderTemplate");
        header:SetAttribute("child1", child);
        header:SetAttribute("child2", strayChild);
        SecureGroupHeader_Update(header);

        -- Appended to a library the collector already knows: its list of libraries is fixed
        -- on the first pass (`DeclareOUFLibrary`), and the passes above have run.
        local library = _G[oufAddons[1]];
        check(library, "setup: no library was declared before the first pass");
        library.objects[#library.objects + 1] = spawned;
        library.objects[#library.objects + 1] = straySpawned;
        CollectOUFFrames();

        check(type(DebindPrivate.ccframes[spawned]) == "table",
            "the library door refused a listed name: " .. tostring(DebindPrivate.ccframes[spawned]));
        check(type(DebindPrivate.ccframes[child]) == "table",
            "the header door refused a listed name: " .. tostring(DebindPrivate.ccframes[child]));
        check(type(DebindPrivate.ccframes[named]) == "table",
            "the name door refused a listed name: " .. tostring(DebindPrivate.ccframes[named]));
        check(type(DebindPrivate.ccframes[strayChild]) == "table",
            "the header door refused a frame no row names: "
            .. tostring(DebindPrivate.ccframes[strayChild]));
        check(type(DebindPrivate.ccframes[straySpawned]) == "table",
            "the library door refused a frame no row names: "
            .. tostring(DebindPrivate.ccframes[straySpawned]));
    end);

    -- **Several doors, because none of them is compulsory.** Nothing in the game makes a unit frame
    -- call any one of these, so listening on one would be betting on a habit.
    test("the other doors take the same frames", function()
        local DOORS = {
            { "SecureUnitButton_OnLoad", SecureUnitButton_OnLoad },
            { "RegisterUnitWatch", RegisterUnitWatch },
            { "UnitFrame_Initialize", UnitFrame_Initialize },
            { "RegisterStateDriver", RegisterStateDriver },
            { "RegisterAttributeDriver", RegisterAttributeDriver },
        };
        for i = 1, #DOORS do
            local frame = ForeignFrame("ERFExtraFrame" .. i, nil);
            DOORS[i][2](frame);
            check(DebindPrivate.ccframes[frame], DOORS[i][1] .. " did not take the frame");
        end

        -- The odd one out: the frame being handed over is the third argument, not the first.
        local referenced = ForeignFrame("ERFFriendlyBoss2", "boss2");
        SecureHandlerSetFrameRef(ForeignHeader(), "theirs", referenced);
        check(DebindPrivate.ccframes[referenced],
            "SecureHandlerSetFrameRef did not take the frame");
    end);

    --- HealBot's door needs that addon standing there, since what it hooks is its own function.
    --- Stands the two globals up and installs the hook once: a second `AttachPackHooks` would wrap
    --- the wrapper and run the door twice for every button.
    local healbotEmerg = {};
    local healbotAttached = false;
    local function withHealBot()
        if (healbotAttached) then
            return;
        end
        healbotAttached = true;
        _G.HealBot_Emerg_Button = healbotEmerg;
        _G.HealBot_Action_RegisterUnitEvents = function() end;
        DebindPrivate.AttachPackHooks();
    end

    --- One of HealBot's buttons the way HealBot makes them: a heal button and an emergency twin
    --- sharing an id, reachable from each other only through `HealBot_Emerg_Button`.
    local function HealBotPair(prefix, id, unit)
        local heal = ForeignFrame(prefix .. "HealUnit" .. id, unit);
        local twin = prefix == "HealBot_" and "HB_" or prefix;
        local emerg = ForeignFrame(twin .. "EmergUnit" .. id, unit);
        heal.id = id;
        healbotEmerg[id] = emerg;
        return heal, emerg;
    end

    -- **The one door aimed at a single addon, and the only way in for it.** HealBot offers nothing,
    -- speaks no protocol, hangs its buttons off a plain frame and ships no oUF, so without this
    -- hook nothing of theirs is reached at all rather than reached late.
    --
    -- **The test bar is driven through the same call on purpose.** HealBot never announces one --
    -- they are given a plain field instead of a unit -- so nothing about the frame tells them
    -- apart, and the name list is the only thing that does. Handing one to the door is what asks
    -- that list the question.
    test("the HealBot door takes the pair and leaves the test bars", function()
        withHealBot();
        local heal, emerg = HealBotPair("HealBot_", 3, "target");
        local bar = HealBotPair("hbTest_", 501, "target");

        HealBot_Action_RegisterUnitEvents(heal);
        HealBot_Action_RegisterUnitEvents(bar);

        check(type(DebindPrivate.ccframes[heal]) == "table",
            "the heal button was refused: " .. tostring(DebindPrivate.ccframes[heal]));
        check(type(DebindPrivate.ccframes[emerg]) == "table",
            "the emergency twin was left behind: " .. tostring(DebindPrivate.ccframes[emerg]));
        -- Pinned by the row rather than read: a panel slot holds `target` this second and a raid
        -- token the next, and it is a group display either way.
        check(DebindPrivate.ccframes[heal].frameType == Constants.FRAMETYPE_GROUP,
            "frameType: " .. tostring(DebindPrivate.ccframes[heal].frameType));
        check(DebindPrivate.ccframes[bar] == nil,
            "a test bar was taken for a unit frame: " .. tostring(DebindPrivate.ccframes[bar]));
    end);

    -- The box is asked where every door meets, so HealBot's frames pass the same gate the rest do.
    test("the HealBot box shuts the HealBot door", function()
        withHealBot();
        local heal, emerg = HealBotPair("HealBot_", 4, "target");

        withPacks({ HealBot = false }, function()
            HealBot_Action_RegisterUnitEvents(heal);
        end);

        check(DebindPrivate.ccframes[heal] == nil,
            "the HealBot door registered a pack that is off: "
            .. tostring(DebindPrivate.ccframes[heal]));
        check(DebindPrivate.ccframes[emerg] == nil,
            "the emergency twin came in while the box was off: "
            .. tostring(DebindPrivate.ccframes[emerg]));
    end);

    -- **A name nobody listed is asked what it is.** Everything arriving at these doors is an
    -- addon's doing, and most of it is not a unit frame at all -- an action bar wraps the same
    -- scripts. What separates the two is the template the frame was built from, and a cast button
    -- has to leave without a row, otherwise the reader's window fills with secure frames they can
    -- neither see nor hover.
    test("a frame the list does not name and is no unit button is left alone", function()
        local frame = frames.newFrame("Button", "SomeUIActionButton1", nil,
            "SecureActionButtonTemplate");
        frame:SetAttribute("unit", "player");
        SecureHandlerWrapScript(frame, "OnClick", ForeignHeader(), "-- theirs");
        check(DebindPrivate.ccframes[frame] == nil,
            "a cast button was taken: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **Our own wrapping is not somebody else's frame arriving.** `RegisterFrame` wraps enter and
    -- leave on the very frames this list matches, before the row it is about to write is there.
    test("our own wrapping does not come back through the door", function()
        local frame = ForeignFrame("ERFPartySelfButton", "player");
        local seen = 0;
        local realRegister = DebindPrivate.RegisterFrame;
        DebindPrivate.RegisterFrame = function(...)
            seen = seen + 1;
            return realRegister(...);
        end
        SecureHandlerWrapScript(frame, "OnEnter", ForeignHeader(), "-- theirs");
        DebindPrivate.RegisterFrame = realRegister;
        check(seen == 1, "registration re-entered " .. seen .. " times");
    end);

    ---------------------------------------------------------------------------
    -- Taking a group header's children off the header
    ---------------------------------------------------------------------------

    --- A header the way `configureChildren` leaves one: each unit button in a `child<i>` attribute,
    --- counted from 1 and ending where the attribute does.
    local function HeaderWithChildren(n)
        local header = frames.newFrame("Frame", nil, nil, "SecureGroupHeaderTemplate");
        local children = {};
        for i = 1, n do
            children[i] = ForeignFrame(nil, "raid" .. i);
            header:SetAttribute("child" .. i, children[i]);
        end
        return header, children;
    end

    -- **A header's children reach us off the header or not at all.** The header protocol connects
    -- once, when the header is built, by reading a global we have to be standing in at that moment;
    -- a header built before that, or one whose addon does not speak the protocol, is never joined.
    -- The table is no better, since whoever holds its name gets the writes.
    test("a header hands over its children when it is loaded", function()
        local header, children = HeaderWithChildren(3);
        SecureGroupHeader_OnLoad(header);

        for i = 1, 3 do
            local seen = DebindPrivate.ccframes[children[i]];
            check(seen and seen.frameType == Constants.FRAMETYPE_GROUP,
                "child " .. i .. ": " .. tostring(seen and seen.frameType));
        end
    end);

    -- **A group grows and the header makes more.** `configureChildren` runs inside
    -- `SecureGroupHeader_Update`, so the hook on it is both the certain catch and the re-walk.
    test("children made after the load are taken on the next update", function()
        local header, children = HeaderWithChildren(1);
        SecureGroupHeader_OnLoad(header);
        check(DebindPrivate.ccframes[children[1]], "the first child was not taken");

        children[2] = ForeignFrame(nil, "raid2");
        header:SetAttribute("child2", children[2]);
        SecureGroupHeader_Update(header);

        check(DebindPrivate.ccframes[children[2]], "the child added afterwards was never offered");
    end);

    -- The pet headers are the same door and the same answer: what someone reading "pet frame"
    -- pictures is their own pet's frame, not a grid of other people's pets.
    test("a pet header's children are group frames too", function()
        local header, children = HeaderWithChildren(2);
        SecureGroupPetHeader_Update(header);

        for i = 1, 2 do
            local seen = DebindPrivate.ccframes[children[i]];
            check(seen and seen.frameType == Constants.FRAMETYPE_GROUP,
                "child " .. i .. ": " .. tostring(seen and seen.frameType));
        end
    end);

    -- The walk stops where the attributes do, rather than at some count of its own.
    test("the walk stops at the first missing child", function()
        local header, children = HeaderWithChildren(2);
        local beyond = ForeignFrame(nil, "raid9");
        header:SetAttribute("child4", beyond);
        SecureGroupHeader_Update(header);

        check(DebindPrivate.ccframes[children[2]], "the last contiguous child was not taken");
        check(DebindPrivate.ccframes[beyond] == nil, "a child past the gap was taken");
    end);


    ---------------------------------------------------------------------------
    -- Holding on to the click input
    ---------------------------------------------------------------------------

    --- What the frame will deliver, as one string to look for words in.
    local function ClicksOn(frame)
        return frame.__clicks and table.concat(frame.__clicks, " ") or "";
    end

    -- **A registered frame has to keep delivering both edges and the wheel**, because that is what
    -- the click wrapper reads and what a wheel binding arrives on. Nothing guarantees it: the
    -- registration is the frame's own state, so the last addon to write it writes it for everyone.
    test("a registered frame is set up to deliver both edges and the wheel", function()
        local frame = ForeignFrame(nil, "party1");
        DebindPrivate.RegisterFrame(frame, true);

        local clicks = ClicksOn(frame);
        check(strfind(clicks, "AnyUp", 1, true) and strfind(clicks, "AnyDown", 1, true),
            "clicks: " .. clicks);
        check(frame.__mouseWheel == true, "the wheel was not turned on");
    end);

    -- **Another click-casting addon narrows it, and does so more than once.** It writes its own
    -- edge onto every frame it takes, and again on every re-registration rather than only when its
    -- setting moves; turning itself off narrows the frame too, with the wheel going off in the
    -- line after the edges. Every one of those leaves a binding on this frame silently dead, so
    -- the frame is listened to and put back.
    test("a frame narrowed by another addon is put back", function()
        local frame = ForeignFrame(nil, "party1");
        DebindPrivate.RegisterFrame(frame, true);

        frame:RegisterForClicks("AnyDown");
        frame:EnableMouseWheel(false);

        local clicks = ClicksOn(frame);
        check(strfind(clicks, "AnyUp", 1, true) and strfind(clicks, "AnyDown", 1, true),
            "clicks: " .. clicks);
        check(frame.__mouseWheel == true, "the wheel was left off");
    end);

    --- Makes the frame lose its row the one way that is left: a fight, which is another engine
    --- wrapping over us **inside our own wrap** (`ContestedNow`). The hook stays on the global for
    --- the rest of the session, which is why it answers for one frame only.
    local function StandDown(frame)
        local theirs = ForeignHeader();
        local fighting = false;
        hooksecurefunc("SecureHandlerWrapScript", function(wrapped, script, header)
            if (wrapped == frame and script == "OnEnter" and fighting
                    and header == DebindPrivate.BindingDriver) then
                fighting = false;
                SecureHandlerWrapScript(frame, "OnEnter", theirs, "-- theirs, on top again");
            end
        end);
        fighting = true;
        SecureHandlerWrapScript(frame, "OnEnter", theirs, "-- theirs");
        fighting = false;
    end

    --- **물러난 것이 굳는가.** 행을 지우기만 하면 다음 헤더 갱신이나 `ClickCastFrames` 쓰기가
    --- `RegisterFrame`을 다시 부르고, 그쪽은 만난 적 없는 프레임으로 보고 다시 등록한다. 그러면
    --- 같은 싸움이 다시 붙고 `DeinitFrame`이 매번 돈다. 거절 표시가 그것을 막는 유일한 값이다.
    test("standing down survives a later registration", function()
        local frame = ForeignFrame(nil, "party3");
        DebindPrivate.RegisterFrame(frame, true);
        StandDown(frame);

        DebindPrivate.RegisterFrame(frame, true);
        check(DebindPrivate.ccframes[frame] == false,
            "물러난 프레임이 다시 등록됐다: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **And a frame we stepped off is stepped off.** The hook cannot be taken off a frame, so what
    -- stops it is the row being gone: putting the input back on a frame the addon is no longer
    -- watching would be holding on to somebody else's.
    test("a frame we stopped watching is left where the other addon put it", function()
        local frame = ForeignFrame(nil, "party1");
        DebindPrivate.RegisterFrame(frame, true);
        StandDown(frame);
        check(DebindPrivate.ccframes[frame] == false, "setup: the fight did not stand us down");

        frame:RegisterForClicks("AnyDown");
        frame:EnableMouseWheel(false);

        check(ClicksOn(frame) == "AnyDown", "clicks: " .. ClicksOn(frame));
        check(frame.__mouseWheel == false, "the wheel was turned back on");
    end);

    ---------------------------------------------------------------------------
    -- Refusals
    ---------------------------------------------------------------------------

    -- **All four refusals are remembered as `false`**, and that is not the same as "not
    -- registered": it is what stops the addon asking again every time the frame is offered.
    test("every reason to refuse is recorded as a refusal", function()
        local REASONS = { "unprotected", "forbidden", "anchored", "noClicks" };
        for i = 1, #REASONS do
            local frame = UnitFrame({ [REASONS[i]] = true });
            DebindPrivate.RegisterFrame(frame, "group");
            check(DebindPrivate.ccframes[frame] == false,
                REASONS[i] .. ": " .. tostring(DebindPrivate.ccframes[frame]));
        end
    end);

    -- And a refused frame stays refused. Offering it again -- which every unit frame addon does on
    -- its own schedule -- must not walk the checks a second time and must not register it.
    test("a refused frame is not reconsidered", function()
        local frame = UnitFrame({ unprotected = true });
        DebindPrivate.RegisterFrame(frame, "group");

        -- The fault is now gone. The addon still does not take it, because the answer is stored.
        frame.IsProtected = function() return true; end
        local mark = frames.mark();
        DebindPrivate.RegisterFrame(frame, "group");
        local entries = frames.since(mark);

        check(DebindPrivate.ccframes[frame] == false, "a refused frame was registered later");
        check(#entries == 0, "a refused frame reached the secure side");
    end);

    -- Registering the same frame under the same type again is a no-op. The registration crosses to
    -- the secure side, so repeating it for nothing is paid for on every frame every addon offers.
    test("re-offering a frame under the same type does nothing", function()
        local frame = UnitFrame();
        DebindPrivate.RegisterFrame(frame, "group");

        local mark = frames.mark();
        DebindPrivate.RegisterFrame(frame, "group");
        local entries = frames.since(mark);
        check(#entries == 0, "the second registration reached the secure side");
    end);

    -- **In combat it is queued, not refused.** Attributes cannot be set on a protected frame
    -- during a lockdown, and writing the frame off would mean losing it until a reload.
    test("a frame offered in combat is queued rather than written off", function()
        local frame = UnitFrame();
        local queued = #DebindPrivate.FrameQueue;

        shim.world.inCombat = true;
        DebindPrivate.RegisterFrame(frame, "group");
        shim.world.inCombat = false;

        check(#DebindPrivate.FrameQueue == queued + 1,
            "the frame was not queued: " .. #DebindPrivate.FrameQueue);
        check(DebindPrivate.ccframes[frame] == nil,
            "a queued frame was answered: " .. tostring(DebindPrivate.ccframes[frame]));

        -- Out of combat the queue is paid, and the frame is registered for real.
        DebindPrivate.RegisterFrame(frame, "group");
        check(type(DebindPrivate.ccframes[frame]) == "table", "the frame never registered");
        for i = #DebindPrivate.FrameQueue, 1, -1 do
            table.remove(DebindPrivate.FrameQueue, i);
        end
    end);

    --- Puts the client in combat, runs `calls` against it, and lets the fight end the way the game
    --- does -- `PLAYER_REGEN_ENABLED` is where the queue is paid.
    ---
    --- **The login is fired first because nothing listens for the fight ending before it.**
    --- `PLAYER_REGEN_ENABLED` is registered in the login handler, so a pass that only sends the
    --- second one drains nothing and every case below it goes green having measured nothing. The
    --- queue being empty afterwards is what says the drain really ran.
    local function throughCombat(calls)
        for i = #DebindPrivate.FrameQueue, 1, -1 do
            table.remove(DebindPrivate.FrameQueue, i);
        end
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
         -- The login handler reads the profile, and the migration it runs indexes `db` outright.
        _G.DebindVars = _G.DebindVars or {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { ["Player-1-TESTGUID"] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");

        shim.world.inCombat = true;
        calls();
        shim.world.inCombat = false;
        check(frames.fireEvent("PLAYER_REGEN_ENABLED") > 0,
            "nothing is listening for PLAYER_REGEN_ENABLED");
        check(#DebindPrivate.FrameQueue == 0,
            "the queue was not paid: " .. #DebindPrivate.FrameQueue);
    end

    -- **The queue holds registrations and nothing else**, so the drain is what the fight held back
    -- and there is no second word for it to weigh against.
    test("registrations offered during one fight are all paid at the end of it", function()
        local first = UnitFrame();
        local second = UnitFrame();

        throughCombat(function()
            DebindPrivate.RegisterFrame(first, "group");
            DebindPrivate.RegisterFrame(second, "group");
        end);

        check(type(DebindPrivate.ccframes[first]) == "table",
            "the first came out unregistered: " .. tostring(DebindPrivate.ccframes[first]));
        check(type(DebindPrivate.ccframes[second]) == "table",
            "the second came out unregistered: " .. tostring(DebindPrivate.ccframes[second]));
    end);

    --- A header's child the way the header door offers one: a named frame the driver is handed
    --- the name of. **The tick is not optional** -- the callback is made from inside the header's
    --- `initialConfigFunction`, so it puts the registration off by one frame rather than
    --- re-entering the restricted environment on a child that is still being configured.
    local function HeaderDoorFrame(name)
        local frame = frames.newFrame("Button", name, nil, "SecureUnitButtonTemplate");
        _G[name] = frame;
        return frame;
    end

    local function HeaderRegister(name)
        DebindPrivate.BindingDriver:OnClickCastRegister(name);
        frames.drainTimers();
    end

    -- **No number of wraps is a fight.** Clique unwraps and rewraps both hover scripts on every
    -- frame it holds on every loading screen, four hook calls per frame each time, and a budget
    -- counted per session stood us down from every Blizzard frame on the third loading screen;
    -- counted per tick it would have gone the same way the day Clique did it twice in one tick.
    -- Counting cannot tell an addon re-laying its own wrapper from one fighting us, so nothing is
    -- counted (code review, 2026-09-08).
    test("an addon re-laying its wrapper any number of times never stands us down", function()
        local patient = ForeignFrame(nil, "party1");
        DebindPrivate.RegisterFrame(patient, true);
        check(DebindPrivate.ccframes[patient], "setup: the frame was refused");
        local theirs = ForeignHeader();
        for _ = 1, 12 do
            SecureHandlerUnwrapScript(patient, "OnEnter");
            SecureHandlerWrapScript(patient, "OnEnter", theirs, "-- theirs");
        end
        check(type(DebindPrivate.ccframes[patient]) == "table",
            "twelve re-wraps in one tick stood us down: "
            .. tostring(DebindPrivate.ccframes[patient]));
    end);

    -- **What a fight is: wrapping over us because we wrapped.** That is synchronous by
    -- construction, since the hooks fire inside `SecureHandlerWrapScript`, so it lands while our
    -- own reassembly of that frame is still on the stack, and that is the one thing that stands
    -- us down. The engine that keeps the frame is theirs.
    test("an addon that re-wraps inside our own wrap is a fight and we step off", function()
        local fought = ForeignFrame(nil, "party2");
        DebindPrivate.RegisterFrame(fought, true);
        check(DebindPrivate.ccframes[fought], "setup: the frame was refused");
        local theirs = ForeignHeader();

        local rounds = 0;
        hooksecurefunc("SecureHandlerWrapScript", function(frame, script, header)
            if (frame == fought and script == "OnEnter" and header == DebindPrivate.BindingDriver
                    and rounds < 3) then
                rounds = rounds + 1;
                SecureHandlerWrapScript(fought, "OnEnter", theirs, "-- theirs, on top again");
            end
        end);

        SecureHandlerWrapScript(fought, "OnEnter", theirs, "-- theirs");

        check(DebindPrivate.ccframes[fought] == false,
            "an addon wrapping over us inside our own wrap did not stand us down: "
            .. tostring(DebindPrivate.ccframes[fought]));
        check(rounds < 3, "the fight went " .. rounds .. " rounds before we stepped off");
    end);

    -- **A header's row says which door wrote it, and that is what `hccframes` is keyed off.** The
    -- kind is the header's own word, since a child carries whichever slot it is filling.
    test("the header door leaves a row marked as the header's", function()
        local frame = HeaderDoorFrame("DebindSpecHeaderOwned");

        HeaderRegister("DebindSpecHeaderOwned");
        local row = DebindPrivate.ccframes[frame];
        check(type(row) == "table" and row.hd, "the header door left no hd row: " .. tostring(row));
        check(row.frameType == Constants.FRAMETYPE_GROUP,
            "the header's own answer was lost: " .. tostring(row.frameType));
        check(DebindPrivate.hccframes.DebindSpecHeaderOwned == frame,
            "the header's list forgot its own child");
        _G.DebindSpecHeaderOwned = nil;
    end);

    -- **The header door is a door like the others now, so the combat queue holds it too.** It used
    -- to register from inside the restricted environment, which a fight does not block, and the
    -- half that a fight *did* block was queued separately. One queue is what makes the last word
    -- the answer.
    test("a header registration during a fight waits for the queue", function()
        local frame = HeaderDoorFrame("DebindSpecHeaderQueued");

        throughCombat(function()
            HeaderRegister("DebindSpecHeaderQueued");
            check(DebindPrivate.ccframes[frame] == nil,
                "the header door registered during a fight: "
                .. tostring(DebindPrivate.ccframes[frame]));
        end);

        local row = DebindPrivate.ccframes[frame];
        check(type(row) == "table", "the drain did not register it: " .. tostring(row));
        -- **The mark is on the frame and not in the queue entry**, which is the whole reason it is
        -- a mark: the entry carries the arguments the call had, not who made it.
        check(row.hd, "the drain registered it as an ordinary row");
        -- The list Clique exposes is written where the row is, so the queue carries it too. It
        -- used to be written beside the registration, which read an empty row during the fight.
        check(DebindPrivate.hccframes.DebindSpecHeaderQueued == frame,
            "the queued registration never reached hccframes");
        _G.DebindSpecHeaderQueued = nil;
    end);

    -- **The header's claim has to reach a row another door already wrote.** `RegisterFrame` stands
    -- down when the row it finds already says what it was about to say, and standing down there
    -- used to mean the claim never landed, so the frame was missing from `hccframes`.
    test("a frame another door registered still becomes the header's", function()
        local frame = HeaderDoorFrame("DebindSpecHeaderSecond");
        frame:SetAttribute("unit", "party2");

        DebindPrivate.RegisterFrame(frame, true);
        local first = DebindPrivate.ccframes[frame];
        check(type(first) == "table" and first.frameType == Constants.FRAMETYPE_GROUP,
            "the other door did not register it as a group frame first");
        check(not first.hd, "it was the header's before the header said so");

        HeaderRegister("DebindSpecHeaderSecond");
        check(DebindPrivate.ccframes[frame].hd,
            "the header's claim never reached the row that was already there");
        check(DebindPrivate.hccframes.DebindSpecHeaderSecond == frame,
            "the claim did not reach hccframes either");
        _G.DebindSpecHeaderSecond = nil;
    end);

    -- **The pack switch reaches the header door too, and this is the change that made it.** That
    -- door used to register from inside the restricted environment and write our row from
    -- `CallMethod`, so it never passed the gate: a pack the reader had turned off went on
    -- registering through its group headers, and what the box did depended on which layout that
    -- reader had picked.
    test("a pack that is turned off is refused at the header door", function()
        local off = HeaderDoorFrame("ERFExtraFrame7");
        local other = HeaderDoorFrame("EllesmereUIUnitFrames_Focus");

        withPacks({ EllesmereUIRaidFrames = false }, function()
            HeaderRegister("ERFExtraFrame7");
            HeaderRegister("EllesmereUIUnitFrames_Focus");
        end);

        check(DebindPrivate.ccframes[off] == nil,
            "the header door registered a pack that is off: "
            .. tostring(DebindPrivate.ccframes[off]));
        check(DebindPrivate.hccframes.ERFExtraFrame7 == nil,
            "a pack that is off was still listed in hccframes");
        -- **The switch is one pack's**, and it must not take another pack's frames with it.
        check(type(DebindPrivate.ccframes[other]) == "table",
            "turning one pack off took another one with it: "
            .. tostring(DebindPrivate.ccframes[other]));

        _G.ERFExtraFrame7 = nil;
        _G.EllesmereUIUnitFrames_Focus = nil;
    end);
    ---------------------------------------------------------------------------
    -- Resolving a custom target
    ---------------------------------------------------------------------------

    --- Runs the resolver and reads back what it decided. It answers by writing an attribute, so
    --- the frame is the only reader there is -- which suits this: the three answers are what the
    --- secure side sees, not what an internal function returned.
    local function resolve(token)
        DebindPrivate.UnitWatch:SetAttribute("resolvedUnit", "unset");
        DebindPrivate.UnitWatch:ResolveUnitToken(token);
        return DebindPrivate.UnitWatch:GetAttribute("resolvedUnit");
    end

    local function World(units)
        shim.world.units = units or {};
    end

    -- A token the game already understands passes through untouched. There is nothing to look up:
    -- `raid7` is `raid7` whoever is standing in it.
    test("a fixed unit token resolves to itself", function()
        World();
        check(resolve("raid7") == "raid7", "raid7: " .. tostring(resolve("raid7")));
        check(resolve("player") == "player", "player: " .. tostring(resolve("player")));
    end);

    -- A name, which is what the reader typed. It has to be turned into a token the secure side can
    -- use, and **which token depends on where that unit is standing right now**.
    test("a unit that exists resolves to the token it is standing in", function()
        World({
            target = { id = "healer-guid" },
            raid7 = { id = "healer-guid" },
            party2 = { id = "healer-guid" },
        });
        shim.world.units.target.raidIndex = 7;
        check(resolve("target") == "raid7", "in a raid: " .. tostring(resolve("target")));

        World({
            target = { id = "healer-guid", inParty = true },
            party2 = { id = "healer-guid" },
        });
        check(resolve("target") == "party2", "in a party: " .. tostring(resolve("target")));
    end);

    -- **Yourself and your pet come back as themselves**, ahead of any group token, because those
    -- two are the ones that stay true when the group changes shape.
    test("the player and the pet resolve to their own tokens", function()
        World({
            target = { id = "me", raidIndex = 3 },
            player = { id = "me" },
            raid3 = { id = "me" },
        });
        check(resolve("target") == "player", "player: " .. tostring(resolve("target")));

        World({ target = { id = "mypet" }, pet = { id = "mypet" }, player = { id = "me" } });
        check(resolve("target") == "pet", "pet: " .. tostring(resolve("target")));
    end);

    -- **Three answers, and the two negatives are different.** A unit that exists but sits in no
    -- token we can name is `false` -- the reader asked for something real and we cannot carry it.
    -- A unit that does not exist is unset: there is nothing to say yet, and the answer may change
    -- when they come into range.
    test("out of reach is false and absent is unset", function()
        World({ target = { id = "stranger" }, player = { id = "me" } });
        check(resolve("target") == false, "out of reach: " .. tostring(resolve("target")));

        World({ player = { id = "me" } });
        check(resolve("target") == nil, "absent: " .. tostring(resolve("target")));
    end);

    -- Combat is a fourth outcome and it is silence: the attribute is not written at all, because
    -- writing one on a protected frame during a lockdown is what raises.
    test("nothing is resolved in combat", function()
        World({ target = { id = "me" }, player = { id = "me" } });
        shim.world.inCombat = true;
        local answer = resolve("target");
        shim.world.inCombat = false;
        check(answer == "unset", "combat wrote an answer: " .. tostring(answer));
    end);


    ---------------------------------------------------------------------------
    -- Standing beside Clique
    ---------------------------------------------------------------------------

    --- Clique installed, which is the one flag left: there is no answer to it any more, so what
    --- this covers is that nothing behind it shuts.
    local function withClique(fn)
        local savedDetected = DebindPrivate.CliqueDetected;
        DebindPrivate.CliqueDetected = true;
        local ok, err = pcall(fn);
        DebindPrivate.CliqueDetected = savedDetected;
        if (not ok) then
            error(err, 0);
        end
    end

    --- Clique's global in the shape the door reads: a header to hook, and the two lists.
    local function CliqueStandIn(alreadyRegistered)
        local header = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        local saved = _G.Clique;
        _G.Clique = { header = header, hccframes = alreadyRegistered or {}, ccframes = {} };
        return header, function() _G.Clique = saved; end
    end

    -- **Clique being there closes no door.** The switch that used to shut them is gone
    -- (`devdocs/legacy/taking-every-unit-frame-with-one-blacklist.md` §1-1): a pack that wires its
    -- own frames up hands them to whoever holds `ClickCastFrames`, and both engines end up on the
    -- frame.
    test("the name door is open while Clique is installed", function()
        local frame = ForeignFrame("ERFFriendlyBoss3", "boss3");

        withClique(function()
            SecureHandlerWrapScript(frame, "OnEnter", ForeignHeader(), "-- theirs");
        end);

        check(type(DebindPrivate.ccframes[frame]) == "table",
            "Clique being installed shut the name door: "
            .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **The header configures its children inside the call that registers them**, and our own
    -- header door waits a tick for exactly that reason (`BindingDriver:OnClickCastRegister`). The
    -- door on Clique's header used to register on the spot (code review, 2026-09-08).
    test("a frame Clique's header door registers is taken a tick later", function()
        local child = HeaderDoorFrame("DebindSpecCliqueHeaderLater");
        child:SetAttribute("unit", "raid4");
        local header, restore = CliqueStandIn();

        withClique(function()
            DebindPrivate.AttachCliqueHeader();
            header:GetScript("OnAttributeChanged")(header, "export_register", child);
            check(DebindPrivate.ccframes[child] == nil,
                "the frame was registered inside the header's own call");
            frames.drainTimers();
        end);
        restore();

        local row = DebindPrivate.ccframes[child];
        check(type(row) == "table" and row.hd,
            "the frame never arrived as the header's: " .. tostring(row and row.hd));
        _G.DebindSpecCliqueHeaderLater = nil;
    end);

    -- **`export_unregister` is one of the deregistrations that arrive from outside, and it means
    -- nothing.** Clique's header taking a child back is that addon's bookkeeping; being ours is the
    -- blacklist's answer (§1-5).
    test("Clique's header taking a child back leaves the row standing", function()
        local child = HeaderDoorFrame("DebindSpecCliqueHeaderKept");
        child:SetAttribute("unit", "raid5");
        local header, restore = CliqueStandIn();

        local row;
        withClique(function()
            DebindPrivate.AttachCliqueHeader();
            local handler = header:GetScript("OnAttributeChanged");
            handler(header, "export_register", child);
            frames.drainTimers();
            row = DebindPrivate.ccframes[child];
            check(type(row) == "table", "setup: the frame never registered");

            handler(header, "export_unregister", child);
            frames.drainTimers();
        end);
        restore();

        check(DebindPrivate.ccframes[child] == row,
            "Clique's own withdrawal took our row: " .. tostring(DebindPrivate.ccframes[child]));
        check(DebindPrivate.hccframes.DebindSpecCliqueHeaderKept == child,
            "the header's list forgot a frame that is still registered");
        _G.DebindSpecCliqueHeaderKept = nil;
    end);

    -- **What an addon wrote into Clique's table before we were listening.** Clique files those in
    -- its own `ccframes` and never puts them in the table, so the walk that adopts a plain table
    -- finds nothing; the header's `hccframes` was already swept at attach time and this is its
    -- twin (code review, 2026-09-08).
    test("frames already in Clique's ccframes are taken when we attach", function()
        local early = ForeignFrame("DebindSpecCliqueEarly", "party3");
        local _, restore = CliqueStandIn();
        _G.Clique.ccframes[early] = true;

        withClique(function()
            DebindPrivate.AttachCliqueHeader();
            frames.drainTimers();
        end);
        restore();

        check(type(DebindPrivate.ccframes[early]) == "table",
            "a frame Clique already held never reached us: "
            .. tostring(DebindPrivate.ccframes[early]));
    end);

    -- **A frame written into Clique's own proxy is ours as well.** Both engines end up on it, and
    -- the reassembly is what makes that safe; there is no answer of Clique's to read and none is
    -- asked for.
    test("a frame Clique keeps is ours too", function()
        local frame = ForeignFrame("DebindSpecCliqueKept", "party4");
        local kept = {};
        local previous = _G.ClickCastFrames;
        _G.ClickCastFrames = setmetatable({}, {
            __index = function(_, f) return kept[f]; end,
            __newindex = function(_, f, value) kept[f] = value or nil; end,
        });

        withClique(function()
            DebindPrivate.AttachClickCastFrames();
            _G.ClickCastFrames[frame] = true;
        end);
        _G.ClickCastFrames = previous;
        DebindPrivate.AttachClickCastFrames();

        check(type(DebindPrivate.ccframes[frame]) == "table",
            "a frame Clique kept was left to Clique: " .. tostring(DebindPrivate.ccframes[frame]));
        check(kept[frame] == true, "the holder lost the frame it kept");
    end);

    -- **`States.unitframe` is what a `frameTypes` record matches on, and registering is what fills
    -- it.** Clique being installed used to leave those records going false with nothing said on
    -- screen; the row carries the kind now whoever else is on the frame.
    test("a frame taken beside Clique carries its frame type", function()
        local frame = ForeignFrame("ERFExtraFrame3", "raid7");

        withClique(function()
            SecureHandlerWrapScript(frame, "OnEnter", ForeignHeader(), "-- theirs");
        end);

        local row = DebindPrivate.ccframes[frame];
        check(type(row) == "table" and row.frameType == Constants.FRAMETYPE_GROUP,
            "the row carries no frame type: " .. tostring(row and row.frameType));
    end);

    -- **Blizzard's own unit frames are ours whoever else is installed.** Blizzard hands them to
    -- nobody; Clique picks them up itself and so do we, and the two meeting inside
    -- `ClickCastFrames` is Clique's implementation rather than a door the frame came in by
    -- (`devdocs/legacy/coexisting-with-clique.md` §5).
    test("Blizzard's own unit frames are registered while Clique is installed", function()
        local frame = ForeignFrame(nil, "player");

        withClique(function()
            DebindPrivate.blizzardFrames[frame] = "player";
            DebindPrivate.UpdateBlizzardFrames();
            DebindPrivate.blizzardFrames[frame] = nil;
        end);

        check(type(DebindPrivate.ccframes[frame]) == "table",
            "Clique being installed took Blizzard's own frame with it: "
            .. tostring(DebindPrivate.ccframes[frame]));
    end);

    --- Clique's own header, in the shape `AttachCliqueHeader` reaches for: a frame that takes a
    --- script hook, and the by-name list of what the header door registered before we were
    --- listening (`Clique/core/core.lua`).

    -- **The header protocol is a road no insecure hook stands on**, so what is read is the place
    -- Clique gets off it: its `clickcast_register` body writes the child into `export_register` and
    -- its own `OnAttributeChanged` picks it up. Hooking that script reads the same value.
    test("a frame Clique's header door registers reaches us", function()
        local child = HeaderDoorFrame("DebindSpecCliqueHeaderChild");
        child:SetAttribute("unit", "raid3");
        local header, restore = CliqueStandIn();

        withClique(function()
            DebindPrivate.AttachCliqueHeader();
            local handler = header:GetScript("OnAttributeChanged");
            check(handler, "the header was never hooked");
            handler(header, "export_register", child);
            frames.drainTimers();
        end);
        restore();

        check(type(DebindPrivate.ccframes[child]) == "table",
            "the header door's frame never reached us: "
            .. tostring(DebindPrivate.ccframes[child]));

        _G.DebindSpecCliqueHeaderChild = nil;
    end);

    -- **What registered before the hook was on is in `hccframes` and nowhere else.** Clique wires
    -- its header up as it loads and we only ask once the profile has been read, so a group that was
    -- already laid out arrived entirely in that window.
    test("frames Clique's header took before we hooked it are adopted", function()
        local early = HeaderDoorFrame("DebindSpecCliqueEarlyChild");
        early:SetAttribute("unit", "raid4");
        local _, restore = CliqueStandIn({ DebindSpecCliqueEarlyChild = early });

        withClique(function()
            DebindPrivate.AttachCliqueHeader();
            frames.drainTimers();
        end);
        restore();

        check(type(DebindPrivate.ccframes[early]) == "table",
            "a frame Clique had already taken was never adopted: "
            .. tostring(DebindPrivate.ccframes[early]));

        _G.DebindSpecCliqueEarlyChild = nil;
    end);
    ---------------------------------------------------------------------------
    -- Which failure the reader is told about
    ---------------------------------------------------------------------------

    --- Runs the failure path and answers **which line went out**, by locale key. Three causes wear
    --- one failure and the reader can act on a different thing in each, so naming the wrong one
    --- sends them after a fault that is not theirs.
    local function failureKey(value, originalValue, inCombat)
        local L = DebindPrivate.L;
        local said;
        local realDisplay = DebindPrivate.DisplayMessage;
        DebindPrivate.DisplayMessage = function(message) said = message; end
        shim.world.inCombat = inCombat and true or false;
        DebindPrivate.UnitWatch:OnSetCustomTargetFailed("custom1", value, originalValue);
        shim.world.inCombat = false;
        DebindPrivate.DisplayMessage = realDisplay;

        for _, key in ipairs({ "CUSTOM_TARGET_FRAME_NOT_OURS_IN_COMBAT",
                "CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT", "CUSTOM_TARGET_UNSUPPORTED_UNIT" }) do
            if (said == L[key]) then
                return key;
            end
        end
        return said;
    end

    -- **In combat the lookup is not what failed.** `DoResolveUnitToken` answers under lockdown --
    -- a target frame over a raid member resolves to `raid7` -- and what cannot happen is handing
    -- that answer back, because `resolvedUnit` is an attribute on a protected frame. Reading the
    -- resolve first called that a unit that could not be held, which is a cause the reader can do
    -- nothing about and is not true either.
    test("a unit that resolves fine is a combat failure, not an unsupported one", function()
        World({
            target = { id = "healer-guid", raidIndex = 7 },
            raid7 = { id = "healer-guid" },
            player = { id = "me" },
        });
        local key = failureKey("target", "unitframe", true);
        check(key == "CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT", "said: " .. tostring(key));
    end);

    -- The frame is the cause where the hover slot was empty, which is the mouseover fallback.
    test("the hover fallback in combat blames the frame", function()
        World({ mouseover = { id = "stranger" }, player = { id = "me" } });
        local key = failureKey("mouseover", "unitframe", true);
        check(key == "CUSTOM_TARGET_FRAME_NOT_OURS_IN_COMBAT", "said: " .. tostring(key));
    end);

    -- And out of combat the frame does not matter: what is left is a unit with no token.
    test("out of combat an unholdable unit is the cause", function()
        World({ target = { id = "stranger" }, player = { id = "me" } });
        local key = failureKey("target", "unitframe", false);
        check(key == "CUSTOM_TARGET_UNSUPPORTED_UNIT", "said: " .. tostring(key));
    end);

    World();

    return T;
end
