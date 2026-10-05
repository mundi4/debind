local _, DebindPrivate = ...;

--[[
    **Whether the tail-key beat can come through `state-visibility`**, asked of this client once a
    login (`implementing-the-cuts-inside-the-beat-handler.md` Q1b).

    Blizzard's manager writes a driver's attribute only where the value differs, so the beat's
    `"a"` has to be put back to `0` by the handler, which enters it a second time on every tick. The
    `state-visibility` branch of `resolveDriver` is the one it does not compare: it shows the frame
    and writes `statehidden` on every tick, and a handler runs on a write of the same value
    (measured, `trimming-the-tail-key-beat.md` 7-1). One entry a tick instead of two, 8.65 µs to
    3.69 µs.

    **That rests on one line of Blizzard's code not being there.** A compare added to that branch
    would stop the beat without an error and leave every tail key where it stood. So a frame of
    our own carries both kinds of driver for a while and counts what its handler sees: a `"show"`
    one, and an `"a"` one put back to `0`, which is written on every tick by the design above and
    so counts the manager's ticks. The visibility one comes as often as the control one, or it
    does not come.

    **Ticks, not frames, and not time.** The manager runs on its own period (0.2 s, or whatever
    somebody set `updatetime` to), so counting against frames would answer "it does not come" on
    every ordinary client. And the first frame after a load takes the whole load as its elapsed
    time, so a window timed from before it closes on that frame having held nothing. The control
    driver's count is the window: no tick, no answer.

    `comes` is nil until there is an answer, which leaves the beat on `"a"`. That is the safe side.
]]

local BeatSignal = {};
DebindPrivate.BeatSignal = BeatSignal;

--- nil until the check answers. `true` where the manager writes `statehidden` on every tick.
BeatSignal.comes = nil;

--- The control ticks the window holds before it answers, past the one registering resolves on the
--- spot.
local TICKS = 3;

--- What the check frame's handler counts, as attributes the insecure side reads back. Each count
--- is written through the frame, which enters the handler again under its own name and does
--- nothing there.
---
--- **Both counts stop where the answer is read.** An answer inside a lockdown cannot take the
--- drivers off until the fight ends, and a capped control driver is left on `"a"`, which the manager
--- then never writes again: what is left is one entry a tick with no write. The two stop at the same
--- number, `cap`, which the frame carries so the body is one literal the snippet golden can hold.
local COUNTING_SNIPPET = [[
if (name == "statehidden") then
    local n = self:GetAttribute("seen-visibility") or 0
    if (n < self:GetAttribute("cap")) then
        self:SetAttribute("seen-visibility", n + 1)
    end
elseif (name == "state-control" and value ~= 0) then
    local n = self:GetAttribute("seen-control") or 0
    if (n < self:GetAttribute("cap")) then
        self:SetAttribute("seen-control", n + 1)
        self:SetAttribute("state-control", 0)
    end
end
]];

--- **One check**: a frame carrying both drivers, answering `onAnswer(comes)` once and taking its
--- drivers off. Answers the check, whose `frame` a spec drives. The caller makes sure it is not
--- under a lockdown, since registering a driver writes the manager's attributes.
---
--- A check whose answer came inside a lockdown keeps its drivers until `Release` is called again
--- out of one.
function BeatSignal.Check(onAnswer)
    local check = { releasePending = false };
    local frame = CreateFrame("Frame", nil, nil, "SecureHandlerAttributeTemplate");
    check.frame = frame;

    function check.Release()
        if (InCombatLockdown()) then
            check.releasePending = true;
            return;
        end
        check.releasePending = false;
        UnregisterAttributeDriver(frame, "state-visibility");
        UnregisterAttributeDriver(frame, "state-control");
    end

    frame:SetAttribute("cap", 1 + TICKS);
    frame:SetAttribute("_onattributechanged", COUNTING_SNIPPET);
    frame:SetScript("OnUpdate", function()
        local control = frame:GetAttribute("seen-control") or 0;
        if (control < 1 + TICKS) then
            return;
        end
        frame:SetScript("OnUpdate", nil);
        check.Release();
        onAnswer((frame:GetAttribute("seen-visibility") or 0) >= control);
    end);
    RegisterAttributeDriver(frame, "state-visibility", "show");
    RegisterAttributeDriver(frame, "state-control", "a");
    return check;
end

--- The session's check, once started.
local sessionCheck;

--- Starts the session's check, once. **Not under a lockdown**: it waits for
--- `PLAYER_REGEN_ENABLED` (`BeatSignal.OutOfCombat`).
function BeatSignal.Start()
    if (sessionCheck or InCombatLockdown()) then
        return;
    end
    sessionCheck = BeatSignal.Check(BeatSignal.Answered);
end

--- The session's answer. **A rebuild is asked for only where the `"a"` driver stands now**: that
--- rebuild is what moves it, and with no beat at all the next rebuild that wants one picks the
--- signal by itself. Rebuilding for nothing takes every binding off and puts it back.
function BeatSignal.Answered(comes)
    BeatSignal.comes = comes;
    if (comes and DebindPrivate.BeatOnAttribute()) then
        DebindPrivate.QueueUpdateBindings();
    end
end

--- What the session's check could not do under a lockdown: start, or take its drivers off.
function BeatSignal.OutOfCombat()
    if (not sessionCheck) then
        BeatSignal.Start();
    elseif (sessionCheck.releasePending) then
        sessionCheck.Release();
    end
end

--- The session's check, for a spec to drive. nil before it started.
function BeatSignal.SessionCheck()
    return sessionCheck;
end
