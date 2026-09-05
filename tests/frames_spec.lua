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
             -- Both live in `DebindUI.lua`, which is not on the headless load list (`run.lua`).
            DebindPrivate.ShowUnitFrameNotice =
                DebindPrivate.ShowUnitFrameNotice or function() end;
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

    -- **The last word during a fight is the word that stands, and either order can be the last.**
    -- Both calls are queued, so what decides is the order they are paid in; two queues drained one
    -- after the other answered by which queue they were in instead, and "took it back, then offered
    -- it again" came out unregistered.
    test("an unregister then a register during one fight leaves the frame registered", function()
        local frame = UnitFrame();
        DebindPrivate.RegisterFrame(frame, "group");
        check(DebindPrivate.ccframes[frame], "the premise is gone: the frame never registered");

        throughCombat(function()
            DebindPrivate.UnregisterFrame(frame);
            DebindPrivate.RegisterFrame(frame, "group");
        end);

        check(type(DebindPrivate.ccframes[frame]) == "table",
            "the frame came out unregistered: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    test("a register then an unregister during one fight leaves the frame alone", function()
        local frame = UnitFrame();

        throughCombat(function()
            DebindPrivate.RegisterFrame(frame, "group");
            DebindPrivate.UnregisterFrame(frame);
        end);

        check(DebindPrivate.ccframes[frame] == nil,
            "the frame came out registered: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **A header's row is the header's, and a queued word does not overrule it.** The secure side
    -- writes an `hd` row when a group header registers a child through the protocol, and it takes
    -- those back itself. A registration queued before that row appeared used to let the drain
    -- rebuild the row as an ordinary one and then tear it down, leaving the header's own child
    -- unwired with nothing to say so.
    test("a header's row survives a register and unregister queued around it", function()
        local frame = UnitFrame();

        throughCombat(function()
            DebindPrivate.RegisterFrame(frame, "group");
            -- The header protocol arriving mid-fight, which is what `clickcast_register` leaves.
            DebindPrivate.ccframes[frame] =
                { hd = true, type = "group", frameType = Constants.FRAMETYPE_GROUP };
            DebindPrivate.UnregisterFrame(frame);
        end);

        local row = DebindPrivate.ccframes[frame];
        check(type(row) == "table" and row.hd,
            "the header's row was taken away: " .. tostring(row and row.hd or row));
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
        local key = failureKey("target", "hover", true);
        check(key == "CUSTOM_TARGET_UNSUPPORTED_UNIT_IN_COMBAT", "said: " .. tostring(key));
    end);

    -- The frame is the cause where the hover slot was empty, which is the mouseover fallback.
    test("the hover fallback in combat blames the frame", function()
        World({ mouseover = { id = "stranger" }, player = { id = "me" } });
        local key = failureKey("mouseover", "hover", true);
        check(key == "CUSTOM_TARGET_FRAME_NOT_OURS_IN_COMBAT", "said: " .. tostring(key));
    end);

    -- And out of combat the frame does not matter: what is left is a unit with no token.
    test("out of combat an unholdable unit is the cause", function()
        World({ target = { id = "stranger" }, player = { id = "me" } });
        local key = failureKey("target", "hover", false);
        check(key == "CUSTOM_TARGET_UNSUPPORTED_UNIT", "said: " .. tostring(key));
    end);

    World();

    return T;
end
