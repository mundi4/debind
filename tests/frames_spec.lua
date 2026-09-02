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

    -- **A name nobody listed goes nowhere.** Everything arriving at these doors is an addon's
    -- doing, so a frame that is not on the list has to leave without a row -- otherwise the
    -- reader's window fills with secure frames they can neither see nor hover.
    test("a frame the list does not name is left alone", function()
        local frame = ForeignFrame("SomeUIActionButton1", "player");
        SecureHandlerWrapScript(frame, "OnClick", ForeignHeader(), "-- theirs");
        check(DebindPrivate.ccframes[frame] == nil,
            "a frame nobody listed was taken: " .. tostring(DebindPrivate.ccframes[frame]));
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

    -- **And a frame we let go is let go.** The hook cannot be taken off a frame, so what stops it
    -- is the row being gone: putting the input back on a frame the addon is no longer watching
    -- would be holding on to somebody else's.
    test("a frame we stopped watching is left where the other addon put it", function()
        local frame = ForeignFrame(nil, "party1");
        DebindPrivate.RegisterFrame(frame, true);
        DebindPrivate.UnregisterFrame(frame);

        frame:RegisterForClicks("AnyDown");
        frame:EnableMouseWheel(false);

        check(ClicksOn(frame) == "AnyDown", "clicks: " .. ClicksOn(frame));
        check(frame.__mouseWheel == false, "the wheel was turned back on");
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
        local queued = #DebindPrivate.RegisterQueue;

        shim.world.inCombat = true;
        DebindPrivate.RegisterFrame(frame, "group");
        shim.world.inCombat = false;

        check(#DebindPrivate.RegisterQueue == queued + 1,
            "the frame was not queued: " .. #DebindPrivate.RegisterQueue);
        check(DebindPrivate.ccframes[frame] == nil,
            "a queued frame was answered: " .. tostring(DebindPrivate.ccframes[frame]));

        -- Out of combat the queue is paid, and the frame is registered for real.
        DebindPrivate.RegisterFrame(frame, "group");
        check(type(DebindPrivate.ccframes[frame]) == "table", "the frame never registered");
        for i = #DebindPrivate.RegisterQueue, 1, -1 do
            table.remove(DebindPrivate.RegisterQueue, i);
        end
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

    World();

    return T;
end
