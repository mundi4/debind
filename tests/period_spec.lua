-- **What a rebuild does to the state driver manager's period**, applied rather than planned
-- (`zeroing-the-beat-period-where-it-is-needed.md` §4). `plan_spec.lua` asks which period a plan
-- wants; this file runs the rebuilds, because what is asked here is what one leaves for the next:
-- a period written and put back, and a 0 held for the rest of the session.
--
-- **A 0 written stays for the whole spec**, as it does for a session, so the cases that write one
-- come after the ones that must not see it, and each says so.
--
-- What is **not** here: the manager running on the period, and the wrap's body in the restricted
-- environment. No manager runs here, and a write to the shell raises no handler; the hook is called
-- the way Blizzard's handler would leave it called.

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

    local GUID = "Player-1-PERIOD";
    local manager = _G.SecureStateDriverManager;
    local Period = DebindPrivate.StateDriverPeriod;

    local seq = 0;
    local function spell(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.value = t.value or 585;
        t.seq = seq;
        return t;
    end

    --- A tail key whose beat measures combat.
    local function Beating()
        return {
            spell({ key = "F1", conditions = { combat = true } }),
            spell({ key = "F1", type = Constants.GIVEBACK, value = nil }),
        };
    end

    --- A key with no tail, so no beat.
    local function Still()
        return { spell({ key = "F1" }) };
    end

    --- Rebuilds on a profile holding `actions`, with the period option at `period`.
    local function Rebuild(actions, period)
        _G.UnitGUID = function() return GUID; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = { stateDriverPeriod = period },
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = { account = { GENERAL = { [0] = {} } } },
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    --- The period the manager's handler would be running on: the last value written that it did not
    --- ignore. Read off the recording, since `GetAttribute` answers a value the wrap kept out too.
    local function UpdatetimeWrites(mark)
        local list = {};
        for _, e in ipairs(frames.since(mark)) do
            if (e.kind == "SetAttribute" and e.target == "SecureStateDriverManager"
                    and e.name == "updatetime") then
                list[#list + 1] = e.body;
            end
        end
        return list;
    end

    local function Wraps(mark)
        local n = 0;
        for _, e in ipairs(frames.since(mark)) do
            if (e.kind == "WrapScript" and e.target == "SecureStateDriverManager") then
                n = n + 1;
            end
        end
        return n;
    end

    ---------------------------------------------------------------------------
    -- A period other than 0. None of these may write a 0.
    ---------------------------------------------------------------------------

    -- **What was there goes back**, and a nil that was there goes back as 0.2: the manager takes no
    -- nil, so writing one would leave our period in force.
    test("a period is written with a beat and put back without one", function()
        local mark = frames.mark();
        Rebuild(Beating(), 0.1);
        check(manager:GetAttribute("updatetime") == 0.1,
            "with a beat: " .. tostring(manager:GetAttribute("updatetime")));
        Rebuild(Beating(), 0.15);
        check(manager:GetAttribute("updatetime") == 0.15,
            "moved to 0.15: " .. tostring(manager:GetAttribute("updatetime")));
        Rebuild(Still(), 0.15);
        check(manager:GetAttribute("updatetime") == Constants.STATE_DRIVER_UPDATETIME_DEFAULT,
            "the beat gone: " .. tostring(manager:GetAttribute("updatetime")));

        manager.__attributes.updatetime = 0.12;
        Rebuild(Beating(), 0.1);
        Rebuild(Beating(), nil);
        check(manager:GetAttribute("updatetime") == 0.12,
            "back to the default: " .. tostring(manager:GetAttribute("updatetime")));
        local writes = UpdatetimeWrites(mark);
        check(#writes == 5, "writes: " .. table.concat(writes, ", "));
        check(not Period.HeldAtZero(), "a non-zero period held zero");
    end);

    -- **A period somebody wrote over ours is theirs.** Nothing listens for it: putting ours back is
    -- skipped, and a new period of ours puts theirs back when it comes off.
    test("a period written over ours is left in place", function()
        Rebuild(Beating(), 0.1);
        manager:SetAttribute("updatetime", 0.05);
        Rebuild(Still(), 0.1);
        check(manager:GetAttribute("updatetime") == 0.05,
            "theirs was replaced by " .. tostring(manager:GetAttribute("updatetime")));

        -- Another value of theirs than the 0.05 above, which is what ours went on over this time.
        Rebuild(Beating(), 0.1);
        manager:SetAttribute("updatetime", 0.07);
        Rebuild(Beating(), 0.15);
        check(manager:GetAttribute("updatetime") == 0.15,
            "a new period was not written: " .. tostring(manager:GetAttribute("updatetime")));
        Rebuild(Still(), 0.15);
        check(manager:GetAttribute("updatetime") == 0.07,
            "theirs did not come back: " .. tostring(manager:GetAttribute("updatetime")));
    end);

    -- **0 is written only where the beat runs**, so a reader who chose 0 with no tail key has used
    -- nothing, and is not asked to reload for moving off it.
    test("0 with no beat writes nothing and asks for no reload", function()
        local mark = frames.mark();
        Rebuild(Still(), 0);
        check(#UpdatetimeWrites(mark) == 0, "0 was written with no beat");
        check(not Period.HeldAtZero(), "0 is held with no beat");
        DebindPrivate.Options.stateDriverPeriod = 0.1;
        check(not DebindPrivate.IsReloadRequired(), "a reload is asked for moving off a 0 never written");
        DebindPrivate.Options.stateDriverPeriod = 0.15;
        check(not DebindPrivate.IsReloadRequired(), "a reload is asked for 0.1 to 0.15");
    end);

    ---------------------------------------------------------------------------
    -- 0, held. Everything from here on runs with 0 written.
    ---------------------------------------------------------------------------

    -- **Once written, 0 stays for the session** (owner, 2026-10-11): nothing puts the manager back
    -- from it, so a reader moving off it is told to reload, and moving back to it needs none.
    test("0 is held for the session once written", function()
        local mark = frames.mark();
        Rebuild(Beating(), 0);
        check(manager:GetAttribute("updatetime") == 0, "0 was not written");
        check(not DebindPrivate.IsReloadRequired(), "0.2 to 0 asked for a reload");

        Rebuild(Still(), 0);
        check(manager:GetAttribute("updatetime") == 0,
            "the beat gone, the period is " .. tostring(manager:GetAttribute("updatetime")));
        Rebuild(Beating(), 0.1);
        check(manager:GetAttribute("updatetime") == 0,
            "0.1 chosen, the period is " .. tostring(manager:GetAttribute("updatetime")));
        local writes = UpdatetimeWrites(mark);
        check(#writes == 1, "writes: " .. table.concat(writes, ", "));

        check(DebindPrivate.IsReloadRequired(), "moving off a 0 written asked for no reload");
        DebindPrivate.Options.stateDriverPeriod = 0;
        check(not DebindPrivate.IsReloadRequired(), "moving back to 0 still asks for a reload");
    end);

    -- **Somebody else's non-zero period is taken back to 0 and kept out with a wrap**, at once out
    -- of a lockdown. In one, only a snippet holding the manager can write it, and our writes wait for
    -- the fight to end.
    test("a foreign period under a held 0 goes back to 0, after the fight if one is on", function()
        check(Period.HeldAtZero(), "0 is not held -- bad premise");
        local hook = manager:GetScript("OnAttributeChanged");
        check(hook, "nothing is hooked on the manager");

        -- `PLAYER_REGEN_ENABLED` is registered inside the login.
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");
        frames.drainTimers();

        shim.world.inCombat = true;
        local mark = frames.mark();
        manager.__attributes.updatetime = 0.2;
        hook(manager, "updatetime", 0.2);
        local inFight, wrapsInFight = UpdatetimeWrites(mark), Wraps(mark);
        shim.world.inCombat = false;
        check(#inFight == 0 and wrapsInFight == 0,
            "written in the fight: " .. table.concat(inFight, ", ") .. ", wraps " .. wrapsInFight);

        frames.fireEvent("PLAYER_REGEN_ENABLED");
        check(manager:GetAttribute("updatetime") == 0,
            "after the fight: " .. tostring(manager:GetAttribute("updatetime")));
        check(Wraps(mark) == 1, "wrapped " .. Wraps(mark) .. " times after the fight");

        mark = frames.mark();
        manager.__attributes.updatetime = 0.1;
        hook(manager, "updatetime", 0.1);
        check(manager:GetAttribute("updatetime") == 0,
            "out of a fight: " .. tostring(manager:GetAttribute("updatetime")));
        check(Wraps(mark) == 0, "wrapped a second time");

        mark = frames.mark();
        hook(manager, "updatetime", 0);
        hook(manager, "setstate", "state-x a");
        check(#UpdatetimeWrites(mark) == 0, "a write of 0 or of another attribute was answered");
    end);

    return T;
end
