-- `ClickCastFrames` when somebody else is holding the name. 와우 클라이언트 불필요.
--
-- **The rule is that there is no question.** Every unit frame is ours whoever else is standing on
-- it, so the holder is listened to rather than asked: its `__newindex` runs first and files the
-- write, and the frame reaches `RegisterFrame` after it. What that leaves to measure here is that
-- nothing behind a holder goes missing -- writes, the rows we already had, a table swapped under
-- the same metatable -- and that a locked table is left where it is.
--
-- **This spec is the only one that loads `Public.lua` and `DebindCliqueFake`** (`run.lua`,
-- `cliqueFake`). Everything below reaches the addon through the global the way a unit frame addon
-- does, because that global is the thing being measured.

return function(DebindPrivate)
    local frames = require("wow_frames");
    local shim = require("wow_shim");

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

    if (not DebindPrivate.AttachClickCastFrames) then
        T.failures[#T.failures + 1] = "setup: DebindCliqueFake did not load";
        return T;
    end

    local function UnitFrame(unit)
        local frame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
        frame:SetAttribute("unit", unit or "party1");
        return frame;
    end

    --- A holder in the shape the real ones have: its own store in an upvalue, an `__index` that
    --- answers for the frames it kept, and a `__newindex` that files every write.
    ---
    --- `keep` decides what it does with one, which is the setting a pack would be reading. Both
    --- answers reach us the same way now, and the cases below say so.
    local function Holder(keep)
        local filed, kept = {}, {};
        local proxy = setmetatable({}, {
            __index = function(_, frame) return kept[frame]; end,
            __newindex = function(_, frame, value)
                filed[frame] = value;
                if (keep and value) then
                    kept[frame] = true;
                end
            end,
        });
        _G.ClickCastFrames = proxy;
        DebindPrivate.AttachClickCastFrames();
        return proxy, kept, filed;
    end

    -- **The name is not taken back.** Taking it does not bring the frames already written into the
    -- other table with it, and it leaves that addon writing where nobody reads -- so the frames it
    -- is still holding would end up with both engines on them or neither.
    test("a table somebody else is holding is left where it is", function()
        local proxy = Holder(true);
        check(_G.ClickCastFrames == proxy,
            "the holder's table was replaced: " .. tostring(_G.ClickCastFrames));
    end);

    -- **The two answers a holder can give, off the same write, and both frames are ours.** Standing
    -- down was for one fault: whoever wrapped a frame last took its `OnLeave` and the other
    -- engine's hover died. We take the top and replay what was above us now, so both engines work
    -- on the frame and there is nothing left to stand down for.
    test("a frame the holder keeps is ours", function()
        Holder(true);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "a frame the holder kept never reached us: "
                .. tostring(DebindPrivate.ccframes[frame]));
    end);

    test("a frame the holder drops is ours", function()
        Holder(false);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "a dropped frame never reached us: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **And the holder still has it.** The name stays theirs and the write they filed is theirs;
    -- what changed is only that we no longer step off the frame because of it.
    test("taking a frame the holder kept leaves the holder holding it", function()
        local proxy, kept = Holder(true);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(_G.ClickCastFrames == proxy, "the holder's table was replaced");
        check(kept[frame] == true, "the holder lost the frame it kept");
    end);

    -- **The original still runs, and first.** Whatever the holder does with a registration it goes
    -- on doing; we only hear that one arrived.
    test("the holder's own __newindex still sees every write", function()
        local _, _, filed = Holder(false);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(filed[frame] == true, "the holder never saw the write: " .. tostring(filed[frame]));
    end);

    -- **A pack on the blacklist is left alone behind a holder as well.** The gate is
    -- `RegisterFrame`'s and every door reaches it, this one included. `ERFExtraFrame` is an
    -- `EllesmereUIRaidFrames` row.
    test("a frame whose pack is on the blacklist is refused behind a holder", function()
        Holder(false);
        DebindPrivate.packFrames = { EllesmereUIRaidFrames = false };
        local frame = frames.newFrame("Button", "ERFExtraFrame51", nil, "SecureUnitButtonTemplate");
        _G.ClickCastFrames[frame] = true;
        DebindPrivate.packFrames = {};
        check(DebindPrivate.ccframes[frame] == nil,
            "a pack the reader ticked was taken: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **A deregistration arriving through the holder means nothing.** Being ours is the blacklist's
    -- answer and not the frame owner's, so the write is the holder's to file and the row stays.
    test("a nil write behind a holder leaves the row standing", function()
        Holder(false);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        local row = DebindPrivate.ccframes[frame];
        check(type(row) == "table", "the premise is gone: the frame never registered");

        _G.ClickCastFrames[frame] = nil;
        check(DebindPrivate.ccframes[frame] == row,
            "a nil write took the row: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **The other three ways a deregistration arrives from outside**, all of them under our own
    -- name rather than behind a holder. The two remaining paths are the header door's
    -- `clickcast_unregister`, whose body is empty and locked by `check:snippet-golden`, and
    -- Clique's `export_unregister`, which `frames_spec` covers.
    test("a deregistration from outside leaves the row standing, whichever door it comes through", function()
        _G.ClickCastFrames = {};
        DebindPrivate.AttachClickCastFrames();

        local CASES = {
            { "the table's own nil write", function(frame) _G.ClickCastFrames[frame] = nil; end },
            { "DebindPublic:UnregisterFrame",
                function(frame) DebindPublic:UnregisterFrame(frame); end },
            { "Clique:UnregisterUnitFrame",
                function(frame) _G.Clique:UnregisterUnitFrame(frame); end },
        };
        for i = 1, #CASES do
            local frame = UnitFrame();
            _G.ClickCastFrames[frame] = true;
            local row = DebindPrivate.ccframes[frame];
            check(type(row) == "table", CASES[i][1] .. ": the frame never registered");

            CASES[i][2](frame);
            check(DebindPrivate.ccframes[frame] == row,
                CASES[i][1] .. " took the row: " .. tostring(DebindPrivate.ccframes[frame]));
        end
    end);

    -- **A metatable is not a holder; a `__newindex` is.** A table that does not intercept its
    -- writes decides nothing about a registration, and the write was landing in the table anyway.
    test("a table that does not intercept its writes is taken over, not hooked", function()
        local frame = UnitFrame();
        local plainish = setmetatable({}, { __index = function() end });
        _G.ClickCastFrames = plainish;
        DebindPrivate.AttachClickCastFrames();

        check(_G.ClickCastFrames ~= plainish, "the name was not taken");
        _G.ClickCastFrames[frame] = true;
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "a frame written after the takeover never registered: "
                .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **A holder can rebuild its store on the metatable it already has.** Its `__newindex` is
    -- wrapped once and stays wrapped, so the pass that meets the new table has nothing to install
    -- and used to return with the old, dead table still recorded as the holder.
    test("a holder that swaps its table under the same metatable is still the holder", function()
        --- **A store per table, reached from the table.** `Holder` above closes over one store for
        --- the life of its metatable, so a stale table would answer out of the same place and the
        --- fault would be invisible. Here the two tables answer out of two stores, which is what a
        --- rebuilt proxy really does.
        local stores = setmetatable({}, { __mode = "k" });
        local mt = {
            __index = function(t, frame) return stores[t][frame]; end,
            __newindex = function(t, frame, value)
                if (value) then
                    stores[t][frame] = true;
                end
            end,
        };
        local function NewTable()
            local t = setmetatable({}, mt);
            stores[t] = {};
            return t;
        end

        local first = NewTable();
        _G.ClickCastFrames = first;
        DebindPrivate.AttachClickCastFrames();

        local rebuilt = NewTable();
        _G.ClickCastFrames = rebuilt;
        DebindPrivate.AttachClickCastFrames();

        check(_G.ClickCastFrames == rebuilt, "the rebuilt table was replaced");
        local frame = UnitFrame();
        rebuilt[frame] = true;
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "a write into the rebuilt table was never heard: "
                .. tostring(DebindPrivate.ccframes[frame]));
        check(stores[first][frame] == nil, "the write landed in the dead table's store");
    end);

    -- **A table locked with `__metatable` is left entirely alone.** Its metamethods cannot be read,
    -- and replacing what cannot be read is the reclaim under another name.
    test("a locked table is neither hooked nor replaced", function()
        local locked = setmetatable({}, { __metatable = false, __index = function() end });
        _G.ClickCastFrames = locked;
        DebindPrivate.AttachClickCastFrames();
        check(_G.ClickCastFrames == locked,
            "a locked table was replaced: " .. tostring(_G.ClickCastFrames));
    end);

    -- **A plain table is nobody holding the name.** That is what Clique itself would have left, so
    -- the name is taken and what was in it is adopted.
    test("a plain table is taken over and what was in it is adopted", function()
        local frame = UnitFrame();
        _G.ClickCastFrames = { [frame] = true };
        DebindPrivate.AttachClickCastFrames();

        check(getmetatable(_G.ClickCastFrames) ~= nil, "the name was not taken");
        check(DebindPrivate.ccframes[frame], "what was already in the table was dropped");
    end);

    -- **The rows already in a proxy when we meet it.** One that files its writes in the table
    -- itself carries the registrations that arrived before we were listening, and nothing else
    -- would ever hand them over.
    test("rows already in a holder's table are taken when we hook it", function()
        local early = UnitFrame();
        local proxy = setmetatable({}, { __newindex = rawset });
        rawset(proxy, early, true);
        _G.ClickCastFrames = proxy;
        DebindPrivate.AttachClickCastFrames();

        check(type(DebindPrivate.ccframes[early]) == "table",
            "a row already in the proxy was never taken: "
                .. tostring(DebindPrivate.ccframes[early]));
    end);

    -- **A holder arriving later gets the rows we were already holding.** It builds its store by
    -- walking the table it found under the name (`pairs`), and our rows live beside the table
    -- rather than in it, so that walk yields nothing and those frames end up somewhere they would
    -- have been had we never been here. Writing them in as ordinary registrations is what a plain
    -- table would have handed over.
    test("a holder arriving later is handed the rows we already had", function()
        _G.ClickCastFrames = {};
        DebindPrivate.AttachClickCastFrames();

        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        local row = DebindPrivate.ccframes[frame];
        check(type(row) == "table", "the premise is gone: the frame never registered with us");

        local _, _, filed = Holder(false);
        check(filed[frame] == true,
            "the holder never heard about the frame we were already holding: "
                .. tostring(filed[frame]));
        check(DebindPrivate.ccframes[frame] == row,
            "handing the frame over registered it a second time: "
                .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **The bundle a holder wraps when it starts is all frames we know nothing about**, so none of
    -- them was a reason to look at the name, and a registration a third addon wrote into that proxy
    -- meanwhile was never heard -- its store is an upvalue, so no later pass can find it either.
    -- Checking the name on any foreign wrap is what shortens that window to one tick.
    test("a wrap on a frame we know nothing about still checks the name", function()
        _G.ClickCastFrames = {};
        DebindPrivate.AttachClickCastFrames();

        local kept = {};
        local proxy = setmetatable({}, {
            __index = function(_, frame) return kept[frame]; end,
            __newindex = function() end,
        });
        _G.ClickCastFrames = proxy;

        local stranger = UnitFrame();
        local header = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        _G.SecureHandlerWrapScript(stranger, "OnEnter", header, "-- theirs");
        frames.drainTimers();

        local third = UnitFrame();
        proxy[third] = true;
        check(type(DebindPrivate.ccframes[third]) == "table",
            "a registration written into the holder's proxy was never heard: "
                .. tostring(DebindPrivate.ccframes[third]));
    end);

    -- **A tick later, and not inside the wrap.** The hook runs while the holder is still putting
    -- itself up, so the table read there is the one it is mid-way through installing.
    test("the name check waits for the next tick", function()
        _G.ClickCastFrames = {};
        DebindPrivate.AttachClickCastFrames();

        local proxy = setmetatable({}, { __newindex = function() end });
        _G.ClickCastFrames = proxy;

        local stranger = UnitFrame();
        local header = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        _G.SecureHandlerWrapScript(stranger, "OnEnter", header, "-- theirs");

        local early = UnitFrame();
        proxy[early] = true;
        check(DebindPrivate.ccframes[early] == nil,
            "the name check ran inside the wrap: " .. tostring(DebindPrivate.ccframes[early]));

        frames.drainTimers();
        local late = UnitFrame();
        proxy[late] = true;
        check(type(DebindPrivate.ccframes[late]) == "table",
            "the tick after the wrap never looked: " .. tostring(DebindPrivate.ccframes[late]));
    end);

    -- **The fight can start inside that one tick.** Attaching registers whatever the proxy already
    -- holds, and each of those would go to the queue and put out "cannot register a unit frame in
    -- combat" over something the reader never did. Nothing is lost: `PLAYER_REGEN_ENABLED` attaches
    -- again.
    test("a name check that lands in combat stands down instead of queuing", function()
        _G.ClickCastFrames = {};
        DebindPrivate.AttachClickCastFrames();

        local early = UnitFrame();
        local proxy = setmetatable({}, { __newindex = rawset });
        rawset(proxy, early, true);
        _G.ClickCastFrames = proxy;

        local stranger = UnitFrame();
        local header = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        _G.SecureHandlerWrapScript(stranger, "OnEnter", header, "-- theirs");

        local queued = #DebindPrivate.FrameQueue;
        shim.world.inCombat = true;
        frames.drainTimers();
        shim.world.inCombat = false;
        check(#DebindPrivate.FrameQueue == queued,
            "the name check queued under lockdown: " .. (#DebindPrivate.FrameQueue - queued));
        check(DebindPrivate.ccframes[early] == nil,
            "a row appeared under lockdown: " .. tostring(DebindPrivate.ccframes[early]));

        -- And the fight ending is what catches up, so nothing is lost by standing down.
        DebindPrivate.AttachClickCastFrames();
        check(type(DebindPrivate.ccframes[early]) == "table",
            "the frame never came back: " .. tostring(DebindPrivate.ccframes[early]));
    end);

    return T;
end
