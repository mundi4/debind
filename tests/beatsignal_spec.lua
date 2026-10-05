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

    --- One pass of the manager over `frame`'s drivers. `compares` is the client that writes
    --- `statehidden` only where it differs, which 12.1.0's source does not.
    local function Resolve(frame, compares)
        local handle = restricted.handleFor(interp, frame);
        for attribute, values in pairs(frames.attributeDrivers[frame] or {}) do
            if (attribute == "state-visibility") then
                if (not compares or frame:GetAttribute("statehidden") ~= nil) then
                    handle:SetAttribute("statehidden", nil);
                end
            elseif (frame:GetAttribute(attribute) ~= values) then
                handle:SetAttribute(attribute, values);
            end
        end
    end

    --- A check, its registration resolved on the spot as the manager does, then `count` frames with
    --- the manager ticking on every `period`-th of them (never, with no period). Answers what the
    --- check answered (nil for none) and the check.
    local function Run(opts)
        local answer;
        local probe = BeatSignal.Check(function(comes) answer = comes; end);
        local frame = probe.frame;
        Resolve(frame, opts.compares);
        for f = 1, opts.count do
            if (opts.lockAt == f) then
                shim.world.inCombat = true;
            end
            if (opts.period and f % opts.period == 0) then
                Resolve(frame, opts.compares);
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

    -- **Once a session**, and not inside a lockdown: a login into a fight starts it when the fight
    -- ends. An answer that it comes is what asks for the rebuild that moves the beat.
    test("the session's check starts out of combat and asks for a rebuild", function()
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
        check(DebindPrivate.updateBindingsQueued, "it comes, and no rebuild was asked for");
        BeatSignal.comes = nil;
        frames.__clearTimers();
    end);

    return T;
end
