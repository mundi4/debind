-- **The login's check of whether the beat can come through `state-visibility`** (`BeatSignal.lua`,
-- `implementing-the-cuts-inside-the-beat-handler.md` Q1b).
--
-- Blizzard's manager does not run headless, so a stand-in resolves the check frame's drivers the way
-- `resolveDriver` in `SecureStateDriver.lua` does and runs the frame's own handler through the
-- interpreter. Two stand-ins, because the answer is about which one the client is: one writes
-- `statehidden` on every tick as 12.1.0's source does, the other compares first as the line the
-- check guards against would. **Whether this client is the first is asked in the game** (`/debtest`,
-- "Beat: ...").

return function(DebindPrivate)
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");
    local BeatSignal = DebindPrivate.BeatSignal;

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

    local interp = restricted.new(DebindPrivate, shim.world);

    --- One pass of the manager over `frame`'s drivers, answering how many writes it made. `compares`
    --- is the client that writes `statehidden` only where it differs, which 12.1.0's source does
    --- not. `controlFirst` resolves the control driver ahead of the visibility one: the manager
    --- walks a frame's drivers with `pairs`, in no order anybody can lean on.
    local function Resolve(frame, compares, controlFirst)
        local handle = restricted.handleFor(interp, frame);
        local drivers = frames.attributeDrivers[frame] or {};
        local order = { "state-visibility", "state-control" };
        if (controlFirst) then
            order = { "state-control", "state-visibility" };
        end
        local writes = 0;
        for _, attribute in ipairs(order) do
            local values = drivers[attribute];
            if (attribute == "state-visibility" and values) then
                if (not compares or frame:GetAttribute("statehidden") ~= nil) then
                    handle:SetAttribute("statehidden", nil);
                    writes = writes + 1;
                end
            elseif (values and frame:GetAttribute(attribute) ~= values) then
                handle:SetAttribute(attribute, values);
                writes = writes + 1;
            end
        end
        return writes;
    end

    --- A check, its registration resolved on the spot as the manager does, then `count` frames with
    --- the manager ticking on every `period`-th of them (never, with no period). Answers what the
    --- check answered (nil for none) and the check.
    local function Run(opts)
        local answer;
        local probe = BeatSignal.Check(function(comes) answer = comes; end);
        local frame = probe.frame;
        Resolve(frame, opts.compares, opts.controlFirst);
        for f = 1, opts.count do
            if (opts.lockAt == f) then
                shim.world.inCombat = true;
            end
            if (opts.period and f % opts.period == 0) then
                Resolve(frame, opts.compares, opts.controlFirst);
            end
            local onUpdate = frame:GetScript("OnUpdate");
            if (onUpdate) then
                -- The first frame after a load takes the whole load as its elapsed time.
                onUpdate(frame, f == 1 and 10 or 1 / 144);
            end
        end
        return answer, probe;
    end

    local function DriversOn(frame)
        local n = 0;
        for _ in pairs(frames.attributeDrivers[frame] or {}) do
            n = n + 1;
        end
        return n;
    end

    test("a manager writing on every tick: it comes, and the drivers come off", function()
        local answer, probe = Run({ period = 1, count = 20 });
        check(answer == true, "answered " .. tostring(answer));
        check(DriversOn(probe.frame) == 0, "the check's drivers were left standing");
    end);

    test("a manager comparing first: it does not come", function()
        local answer, probe = Run({ period = 1, count = 20, compares = true });
        check(answer == false, "answered " .. tostring(answer));
        check(DriversOn(probe.frame) == 0, "the check's drivers were left standing");
    end);

    test("the answer does not hang on which driver the manager resolves first", function()
        for _, controlFirst in ipairs({ false, true }) do
            local what = controlFirst and "control first: " or "visibility first: ";
            check(Run({ period = 1, count = 20, controlFirst = controlFirst }) == true, what .. "it did not come");
            check(Run({ period = 1, count = 20, controlFirst = controlFirst, compares = true }) == false,
                what .. "a comparing manager came");
        end
    end);

    -- **The window is the manager's ticks, not frames.** 0.2 s at 144 fps is a tick every 29th
    -- frame, and `updatetime` is anybody's to set.
    test("a manager on a period of its own: it comes", function()
        for _, period in ipairs({ 7, 29, 144 }) do
            local answer = Run({ period = period, count = period * 5 });
            check(answer == true, "every " .. period .. " frames: answered " .. tostring(answer));
        end
    end);

    -- The load's own frame, with the load as its elapsed time, and no tick after it.
    test("no tick, no answer", function()
        local answer, probe = Run({ count = 300 });
        check(answer == nil, "answered " .. tostring(answer) .. " with no tick in the window");
        check(probe.frame:GetScript("OnUpdate") ~= nil, "the check stopped waiting");
        check(DriversOn(probe.frame) == 2, "the check took its drivers off with no answer");
    end);

    test("an answer inside a lockdown takes the drivers off after it", function()
        local answer, probe = Run({ period = 1, count = 20, lockAt = 2 });
        check(answer == true, "answered " .. tostring(answer));
        check(DriversOn(probe.frame) == 2, "the drivers came off inside the lockdown");
        shim.world.inCombat = false;
        check(probe.releasePending, "nothing remembered the drivers still standing");
        probe.Release();
        check(DriversOn(probe.frame) == 0, "the drivers stayed after the lockdown");
    end);

    -- **What the check costs for the rest of a fight it answered in**: the drivers cannot come off,
    -- so the manager goes on resolving them. Only `statehidden` may still be written, and nothing
    -- the handler counts may move.
    test("a check answered in a lockdown stops counting", function()
        local _, probe = Run({ period = 1, count = 20, lockAt = 2 });
        local frame = probe.frame;
        local seen = { frame:GetAttribute("seen-control"), frame:GetAttribute("seen-visibility") };
        for _ = 1, 10 do
            local writes = Resolve(frame);
            check(writes == 1, "a tick after the answer wrote " .. writes .. " times");
        end
        check(frame:GetAttribute("seen-control") == seen[1] and frame:GetAttribute("seen-visibility") == seen[2],
            "the counts went on after the answer");
        shim.world.inCombat = false;
        probe.Release();
    end);

    -- **Once a session**, and not inside a lockdown: a login into a fight starts it when the fight
    -- ends. Nothing has been rebuilt here, so no beat stands and the yes asks for no rebuild.
    test("the session's check starts once, out of combat", function()
        check(BeatSignal.SessionCheck() == nil, "a check had started before the case");
        shim.world.inCombat = true;
        BeatSignal.Start();
        check(BeatSignal.SessionCheck() == nil, "the check started inside a lockdown");
        shim.world.inCombat = false;
        BeatSignal.OutOfCombat();
        local session = BeatSignal.SessionCheck();
        check(session, "the check did not start when the lockdown ended");
        BeatSignal.Start();
        check(BeatSignal.SessionCheck() == session, "a second start made a second check");

        DebindPrivate.updateBindingsQueued = nil;
        local frame = session.frame;
        Resolve(frame);
        for _ = 1, 5 do
            Resolve(frame);
            local onUpdate = frame:GetScript("OnUpdate");
            if (onUpdate) then
                onUpdate(frame, 0.2);
            end
        end
        check(BeatSignal.comes == true, "the session's answer is " .. tostring(BeatSignal.comes));
        check(not DebindPrivate.updateBindingsQueued, "a rebuild was asked for with no beat standing");
        BeatSignal.comes = nil;
        frames.__clearTimers();
    end);

    --- A rebuild of a profile, as the login's would.
    local function Bind(actions)
        _G.DebindVars = {
            dbver = DebindPrivate.Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { ["Player-1-BEATSIGNAL"] = { switches = {} } },
            migrated = {},
        };
        _G.UnitGUID = function() return "Player-1-BEATSIGNAL"; end
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    -- **A yes asks for a rebuild only where the `"a"` driver stands**, since that rebuild is what
    -- moves the beat. Without a beat it would take every binding off and put it back for nothing.
    test("a yes asks for a rebuild only where the beat is on \"a\"", function()
        local Constants = DebindPrivate.Constants;
        local tail = {
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1, conditions = { combat = true } },
            { type = Constants.GIVEBACK, key = "F1", seq = 2 },
        };
        for _, case in ipairs({
            { what = "no tail", actions = {}, comes = nil, queued = false },
            { what = "a tail on \"a\"", actions = tail, comes = nil, queued = true },
            { what = "a tail already on state-visibility", actions = tail, comes = true, queued = false },
        }) do
            BeatSignal.comes = case.comes;
            Bind(case.actions);
            DebindPrivate.updateBindingsQueued = nil;
            BeatSignal.Answered(true);
            check((DebindPrivate.updateBindingsQueued and true or false) == case.queued,
                case.what .. ": a rebuild was " .. (case.queued and "not " or "") .. "asked for");
        end
        BeatSignal.comes = nil;
        DebindPrivate.updateBindingsQueued = nil;
        frames.__clearTimers();
    end);

    return T;
end
