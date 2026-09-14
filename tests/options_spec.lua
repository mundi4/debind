-- **What carries a stored account option across.** A setter only writes the profile and asks for a
-- rebuild, so `ApplyOptions` is the one hand that reaches a secure frame with the answer.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
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

    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
        characters = { ["Player-1-TESTGUID"] = { layers = {}, switches = {} } },
        migrated = {},
        switches = {},
    };
    DebindPrivate.InitDB();

    local function exclude(unit, on)
        local excluded = DebindPrivate.Options.excludePlayer or {};
        DebindPrivate.Options.excludePlayer = excluded;
        excluded[unit] = on or nil;
    end

    --- **A rebuild is the only hand that writes `showPlayer`**, and a value written to the profile
    --- with nothing carrying it is a setting that reads as set and does nothing.
    test("ApplyOptions writes showPlayer from the stored exclusions", function()
        local header = DebindPrivate.EnableUnitWatch("tank");
        check(header ~= nil, "no header to write on");

        exclude("tank", true);
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == false,
            "the exclusion never reached the header");

        exclude("tank", false);
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == true,
            "taking the exclusion back never reached the header");
    end);

    --- **And it stays off the header during a fight**: the header is a `SecureGroupHeaderTemplate`
    --- and the write would raise.
    test("ApplyOptions leaves the header alone during a fight", function()
        local header = DebindPrivate.EnableUnitWatch("healer");
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == true, "not the value this starts from");

        shim.world.inCombat = true;
        exclude("healer", true);
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == true,
            "the header was written during a fight");

        shim.world.inCombat = false;
        DebindPrivate.ApplyOptions();
        check(header:GetAttribute("showPlayer") == false,
            "the fight ended and the answer never crossed");
        exclude("healer", false);
    end);

    --- **The blacklist is read once at login, so a rebuild may not carry it anywhere.** It used to,
    --- and only in one direction: ticking a box could not take a wired frame back and so really did
    --- need the reload its tooltip promises, while unticking one reached `UpdateBlizzardFrames`
    --- from here and registered on the spot. `check:reload-options` asks the same thing of the
    --- source; this asks it of what runs.
    test("a rebuild does not carry the frame blacklist anywhere", function()
        local reached = false;
        local real = DebindPrivate.UpdateBlizzardFrames;
        DebindPrivate.UpdateBlizzardFrames = function() reached = true; end;

        DebindPrivate.Options.frameBlacklist.blizzard.party = false;
        DebindPrivate.ApplyOptions();
        DebindPrivate.Options.frameBlacklist.blizzard.party = nil;
        DebindPrivate.ApplyOptions();

        DebindPrivate.UpdateBlizzardFrames = real;
        check(not reached, "a rebuild still registers the Blizzard frames");
    end);

    return T;
end
