-- `ClickCastFrames` when somebody else is holding the name. 와우 클라이언트 불필요.
--
-- **The rule is one question asked of the holder.** Its `__index` is what every addon already asks
-- of this table, so asking it back says what that addon decided about one frame -- without reading
-- its settings, its addon name, or the frame's name, none of which we could be right about for a
-- pack we have never seen. Truthy is theirs and we stand down; nil is a write it filed and dropped,
-- which leaves the frame with nobody answering its clicks, and that one is ours.
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
    --- `keep` decides what it does with one, which is the setting a pack would be reading.
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

    -- The two answers, off the same write.
    test("the holder keeps a frame and we stand down", function()
        Holder(true);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(DebindPrivate.ccframes[frame] == nil,
            "we took a frame the holder answers for: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    test("the holder drops a frame and we take it", function()
        Holder(false);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "a dropped frame never reached us: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **The original still runs, and first.** Whatever the holder does with a registration it goes
    -- on doing; only what it left behind is asked about.
    test("the holder's own __newindex still sees every write", function()
        local _, _, filed = Holder(false);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(filed[frame] == true, "the holder never saw the write: " .. tostring(filed[frame]));
    end);

    -- A deregistration is honoured wherever it comes from: the frame's owner is asking for it back.
    test("a nil write takes the frame back off us", function()
        Holder(false);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(DebindPrivate.ccframes[frame], "the premise is gone: the frame never registered");

        _G.ClickCastFrames[frame] = nil;
        check(DebindPrivate.ccframes[frame] == nil,
            "the row survived a nil write: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **A metatable is not a holder; a `__newindex` is.** A table that does not intercept its
    -- writes decides nothing about a registration, so there is no opinion to ask for and the write
    -- was landing in the table anyway. Hooking one meant our own write sat in the table before we
    -- read it back, `__index` never fired, and every frame came back reading as the holder's.
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
    -- and used to return with the old, dead table still recorded as the holder -- and every frame
    -- it was driving then read as dropped.
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

        _G.ClickCastFrames = NewTable();
        DebindPrivate.AttachClickCastFrames();

        local rebuilt = NewTable();
        _G.ClickCastFrames = rebuilt;
        DebindPrivate.AttachClickCastFrames();

        local frame = UnitFrame();
        rebuilt[frame] = true;
        check(DebindPrivate.ccframes[frame] == nil,
            "we took a frame the holder answers for: " .. tostring(DebindPrivate.ccframes[frame]));
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

    -- **A holder can let a frame go without a write coming through** -- its own setting moves, or
    -- its engine is switched off -- so the frames we stood down on are asked again.
    test("a re-ask picks up a frame the holder has since let go", function()
        local _, kept = Holder(true);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(DebindPrivate.ccframes[frame] == nil, "the premise is gone: we took it the first time");

        kept[frame] = nil;
        DebindPrivate.AskHolderAgain();
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "the re-ask left the frame with nobody: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- And the other direction: a frame we hold that the holder has since taken.
    test("a re-ask stands down on a frame the holder has since taken", function()
        local _, kept = Holder(false);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(DebindPrivate.ccframes[frame], "the premise is gone: the frame never registered");

        kept[frame] = true;
        DebindPrivate.AskHolderAgain();
        check(DebindPrivate.ccframes[frame] == nil,
            "we kept a frame the holder has taken: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **Wrapping and unwrapping a script is how any engine attaches and detaches**, so those two
    -- calls are what says a decision may have moved -- no addon name and no frame name read.
    test("the holder wrapping a script re-asks that frame on the next tick", function()
        local _, kept = Holder(true);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        check(DebindPrivate.ccframes[frame] == nil, "the premise is gone: we took it the first time");

        kept[frame] = nil;
        local header = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        _G.SecureHandlerUnwrapScript(frame, "OnEnter", header);
        check(DebindPrivate.ccframes[frame] == nil,
            "the re-ask ran inside the call rather than on the next tick");

        frames.drainTimers();
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "the tick after the unwrap never asked: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- **The fight can start inside that one frame.** The hook checked combat and the tick did not,
    -- so a re-ask landing under lockdown queued the registration and put out "cannot register a
    -- unit frame in combat" over something the reader never did. Standing down costs nothing:
    -- `PLAYER_REGEN_ENABLED` asks about that frame again.
    test("a re-ask that lands in combat stands down instead of queuing", function()
        local _, kept = Holder(true);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        kept[frame] = nil;

        local header = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        _G.SecureHandlerUnwrapScript(frame, "OnEnter", header);

        local queued = #DebindPrivate.FrameQueue;
        shim.world.inCombat = true;
        frames.drainTimers();
        shim.world.inCombat = false;
        check(#DebindPrivate.FrameQueue == queued,
            "the re-ask queued under lockdown: " .. (#DebindPrivate.FrameQueue - queued));
        check(DebindPrivate.ccframes[frame] == nil,
            "a row appeared under lockdown: " .. tostring(DebindPrivate.ccframes[frame]));

        -- And the fight ending is what catches up, so nothing is lost by standing down.
        DebindPrivate.AskHolderAgain();
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "the frame never came back: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    -- A frame nobody has ever mentioned to us is not worth a tick.
    test("a wrap on a frame we know nothing about queues nothing", function()
        Holder(true);
        local stranger = UnitFrame();
        local header = frames.newFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
        frames.drainTimers();

        _G.SecureHandlerWrapScript(stranger, "OnEnter", header, "-- theirs");
        frames.drainTimers();
        check(DebindPrivate.ccframes[stranger] == nil,
            "a frame nobody offered was taken: " .. tostring(DebindPrivate.ccframes[stranger]));
    end);

    -- **In combat the re-ask stands down entirely.** Registering and deregistering write through
    -- the API frame, which is protected, so a pass under lockdown would queue every frame it
    -- touched; `PLAYER_REGEN_ENABLED` is where it belongs and that is out of combat by definition.
    test("nothing is re-asked in combat", function()
        local _, kept = Holder(true);
        local frame = UnitFrame();
        _G.ClickCastFrames[frame] = true;
        kept[frame] = nil;

        shim.world.inCombat = true;
        DebindPrivate.AskHolderAgain();
        shim.world.inCombat = false;
        check(DebindPrivate.ccframes[frame] == nil,
            "a re-ask ran under lockdown: " .. tostring(DebindPrivate.ccframes[frame]));

        DebindPrivate.AskHolderAgain();
        check(type(DebindPrivate.ccframes[frame]) == "table",
            "and out of combat it never caught up: " .. tostring(DebindPrivate.ccframes[frame]));
    end);

    return T;
end
