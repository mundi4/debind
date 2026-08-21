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
-- the harness gives them now (`devdocs/going-headless-outside-the-ui.md`).

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
