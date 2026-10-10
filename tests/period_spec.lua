-- **What a rebuild does to the state driver manager's period**, applied rather than planned
-- (`zeroing-the-beat-period-where-it-is-needed.md` §4). `plan_spec.lua` asks which period a plan
-- wants; this file runs the rebuilds, because what is asked here is what one leaves for the next:
-- a period written and taken off, and a 0 of ours with the events it takes off and puts back.
--
-- **Every case leaves the manager off 0**, so the next starts from a period nothing of ours holds.
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
    local DEFAULT = Constants.STATE_DRIVER_UPDATETIME_DEFAULT;
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

    --- A tail key whose beat measures combat, which the manager announces itself.
    local function Beating()
        return {
            spell({ key = "F1", conditions = { combat = true } }),
            spell({ key = "F1", type = Constants.GIVEBACK, value = nil }),
        };
    end

    --- A tail key whose beat measures the mount, for which we register an event of our own.
    local function Mounted()
        return {
            spell({ key = "F1", conditions = { mounted = true } }),
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

    --- Every `updatetime` written on the manager since `mark`, in order.
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

    --- Where in the recording since `mark` the first entry `match` accepts sits, nil for none.
    local function IndexOf(mark, match)
        for i, e in ipairs(frames.since(mark)) do
            if (match(e)) then
                return i;
            end
        end
    end

    --- The manager's `updatetime` as it stands.
    local function Current()
        return manager:GetAttribute("updatetime");
    end

    ---------------------------------------------------------------------------
    -- A period other than 0
    ---------------------------------------------------------------------------

    -- **Ours comes off to 0.2**, whatever was there before it went on (owner, 2026-10-11): nobody
    -- was found writing the attribute, so what was there is 0.2 in practice.
    test("a period is written with a beat and taken off to 0.2 without one", function()
        local mark = frames.mark();
        Rebuild(Beating(), 0.1);
        check(Current() == 0.1, "with a beat: " .. tostring(Current()));
        Rebuild(Beating(), 0.15);
        check(Current() == 0.15, "moved to 0.15: " .. tostring(Current()));
        Rebuild(Still(), 0.15);
        check(Current() == DEFAULT, "the beat gone: " .. tostring(Current()));

        manager.__attributes.updatetime = 0.12;
        Rebuild(Beating(), 0.1);
        Rebuild(Beating(), nil);
        check(Current() == DEFAULT, "back to the default: " .. tostring(Current()));
        local writes = UpdatetimeWrites(mark);
        check(#writes == 5, "writes: " .. table.concat(writes, ", "));
    end);

    -- **A period somebody wrote over ours is theirs.** Nothing listens for it: taking ours off is
    -- skipped, and a new period of ours goes over it.
    test("a period written over ours is left in place", function()
        Rebuild(Beating(), 0.1);
        manager:SetAttribute("updatetime", 0.05);
        Rebuild(Still(), 0.1);
        check(Current() == 0.05, "theirs was replaced by " .. tostring(Current()));

        Rebuild(Beating(), 0.1);
        manager:SetAttribute("updatetime", 0.07);
        Rebuild(Beating(), 0.15);
        check(Current() == 0.15, "a new period was not written: " .. tostring(Current()));
        Rebuild(Still(), 0.15);
        check(Current() == DEFAULT, "ours came off to " .. tostring(Current()));
    end);

    -- **0 is written only where the beat runs.**
    test("0 with no beat writes nothing", function()
        local mark = frames.mark();
        Rebuild(Still(), 0);
        check(#UpdatetimeWrites(mark) == 0, "0 was written with no beat");
        check(not Period.ZeroedByUs(), "0 counts as ours with no beat");
    end);

    ---------------------------------------------------------------------------
    -- A 0 of ours, and what comes off with it
    ---------------------------------------------------------------------------

    -- **0 takes every event off the manager and puts them back when it comes off** (§5-2, owner
    -- 2026-10-11): Blizzard's twelve as Blizzard registered them, and what addons asked for since
    -- load -- ours, one from before 0 with its unit, one that landed while 0 stood -- as they asked.
    -- One registered and taken off again while 0 stood stays off.
    --
    -- **Our own taking-off does not count as anybody's unregistering**, or the restore would find
    -- the record of what to put back empty.
    test("0 comes off with the beat and puts back what it took", function()
        Rebuild(Mounted(), 0.1);
        manager:RegisterEvent("PLAYER_STARTED_MOVING");
        manager:RegisterUnitEvent("UNIT_AURA", "player");
        check(manager:IsEventRegistered("PLAYER_STARTED_MOVING"), "an event registered before 0 was taken off");
        check(manager:IsEventRegistered("PLAYER_MOUNT_DISPLAY_CHANGED"),
            "on 0.1 the mounted column registered nothing -- bad premise");

        local mark = frames.mark();
        Rebuild(Mounted(), 0);
        check(Current() == 0, "0 was not written");
        check(Period.ZeroedByUs(), "0 of ours is not counted as ours");
        check(IndexOf(mark, function(e) return e.kind == "Execute" and e.body == "ZeroedByUs = true"; end),
            "the restricted side was not told 0 is ours");
        for _, event in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_STARTED_MOVING", "UNIT_AURA" }) do
            check(not manager:IsEventRegistered(event), event .. " is still registered at 0");
        end

        manager:RegisterEvent("PLAYER_STOPPED_MOVING");
        check(not manager:IsEventRegistered("PLAYER_STOPPED_MOVING"), "an event registered at 0 stayed");
        manager:RegisterUnitEvent("UNIT_HEALTH", "player");
        check(not manager:IsEventRegistered("UNIT_HEALTH"), "a unit event registered at 0 stayed");
        manager:UnregisterEvent("UNIT_HEALTH");

        mark = frames.mark();
        Rebuild(Mounted(), 0);
        for _, e in ipairs(frames.since(mark)) do
            check(not ((e.kind == "RegisterEvent" or e.kind == "RegisterUnitEvent")
                    and e.target == "SecureStateDriverManager"),
                "a rebuild on 0 registered " .. tostring(e.name));
        end

        mark = frames.mark();
        Rebuild(Mounted(), nil);
        check(not Period.ZeroedByUs(), "0 still counts as ours");
        check(Current() == DEFAULT, "0 came off to " .. tostring(Current()));
        local cleared = IndexOf(mark, function(e) return e.kind == "Execute" and e.body == "ZeroedByUs = false"; end);
        local restored = IndexOf(mark, function(e)
            return e.kind == "SetAttribute" and e.target == "SecureStateDriverManager" and e.name == "updatetime";
        end);
        check(cleared and restored and cleared < restored,
            "the restricted flag did not come off before the period: " .. tostring(cleared) .. " / " .. tostring(restored));
        for _, event in ipairs(Period.BLIZZARD_EVENTS) do
            check(manager:IsEventRegistered(event), "Blizzard's " .. event .. " was not put back");
        end
        for _, event in ipairs({ "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" }) do
            check(manager:IsEventRegistered(event), event .. " was not put back");
        end
        check(manager.__events.UNIT_AURA == "player",
            "UNIT_AURA came back as " .. tostring(manager.__events.UNIT_AURA));
        check(not manager:IsEventRegistered("UNIT_HEALTH"), "an event taken off at 0 by its owner came back");

        -- Ours is still known to be ours once it is back.
        Rebuild(Still(), nil);
        check(not manager:IsEventRegistered("PLAYER_MOUNT_DISPLAY_CHANGED"),
            "our event outlived the column that wanted it");
        check(manager:IsEventRegistered("PLAYER_STARTED_MOVING"), "somebody else's event went with ours");
    end);

    -- **An event of ours stays ours across a 0.** The rebuild that leaves 0 for a profile that no
    -- longer reads the mount has to take the mount's event off again once it is back, which it can
    -- only do while it still knows the event was ours.
    test("an event of ours no longer wanted when 0 comes off stays off", function()
        Rebuild(Mounted(), 0.1);
        Rebuild(Mounted(), 0);
        Rebuild(Still(), nil);
        check(not Period.ZeroedByUs(), "0 still counts as ours");
        check(not manager:IsEventRegistered("PLAYER_MOUNT_DISPLAY_CHANGED"),
            "the mount's event came back with nothing reading it");
    end);

    -- **Somebody else's event stays theirs across a 0**, where a column of ours wants the same one.
    -- It was registered when we came to want it, so it is not ours to take off when the column goes.
    test("an event another addon registered first stays theirs across a 0", function()
        Rebuild(Still(), nil);
        manager:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED");
        Rebuild(Mounted(), 0.1);
        Rebuild(Mounted(), 0);
        Rebuild(Mounted(), nil);
        check(manager:IsEventRegistered("PLAYER_MOUNT_DISPLAY_CHANGED"), "theirs did not come back -- bad premise");
        Rebuild(Still(), nil);
        check(manager:IsEventRegistered("PLAYER_MOUNT_DISPLAY_CHANGED"),
            "theirs was taken off with the column that also wanted it");
        manager:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED");
    end);

    -- **Off 0 to a period the reader chose**, that period goes on and comes off as any other.
    test("0 coming off for a non-zero period writes that period", function()
        Rebuild(Beating(), 0);
        Rebuild(Beating(), 0.1);
        check(not Period.ZeroedByUs(), "0 still counts as ours");
        check(Current() == 0.1, "off 0 to 0.1 left " .. tostring(Current()));
        check(manager:IsEventRegistered("UNIT_PET"), "Blizzard's events were not put back");
        Rebuild(Still(), 0.1);
        check(Current() == DEFAULT, "0.1 came off to " .. tostring(Current()));
    end);

    -- **Somebody else's non-zero period is taken back to 0 and kept out with a wrap** while a 0 of
    -- ours stands, at once out of a lockdown. In one, only a snippet holding the manager can write
    -- it, and our writes wait for the fight to end. Once our 0 is off, theirs stays.
    test("a foreign period under a 0 of ours goes back to 0, after the fight if one is on", function()
        Rebuild(Beating(), 0);
        local hook = manager:GetScript("OnAttributeChanged");
        check(hook, "nothing is hooked on the manager");

        -- `PLAYER_REGEN_ENABLED` is registered inside the login.
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");
        frames.drainTimers();
        check(Period.ZeroedByUs(), "the login took our 0 off -- bad premise");

        shim.world.inCombat = true;
        local mark = frames.mark();
        manager.__attributes.updatetime = 0.2;
        hook(manager, "updatetime", 0.2);
        local inFight, wrapsInFight = UpdatetimeWrites(mark), Wraps(mark);
        shim.world.inCombat = false;
        check(#inFight == 0 and wrapsInFight == 0,
            "written in the fight: " .. table.concat(inFight, ", ") .. ", wraps " .. wrapsInFight);

        frames.fireEvent("PLAYER_REGEN_ENABLED");
        check(Current() == 0, "after the fight: " .. tostring(Current()));
        check(Wraps(mark) == 1, "wrapped " .. Wraps(mark) .. " times after the fight");

        mark = frames.mark();
        manager.__attributes.updatetime = 0.1;
        hook(manager, "updatetime", 0.1);
        check(Current() == 0, "out of a fight: " .. tostring(Current()));
        check(Wraps(mark) == 0, "wrapped a second time");

        mark = frames.mark();
        hook(manager, "updatetime", 0);
        hook(manager, "setstate", "state-x a");
        check(#UpdatetimeWrites(mark) == 0, "a write of 0 or of another attribute was answered");

        Rebuild(Still(), 0);
        mark = frames.mark();
        manager.__attributes.updatetime = 0.1;
        hook(manager, "updatetime", 0.1);
        check(#UpdatetimeWrites(mark) == 0, "a foreign period was answered with our 0 off");
    end);

    return T;
end
