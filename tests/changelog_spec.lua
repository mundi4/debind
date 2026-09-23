-- **Which profile the changelog window opens for**, and it is decided once, in `InitDB`
-- (`showing-the-changelog-on-login.md`). The window itself is `DebindMessageFrame.lua`'s and out
-- of reach here; what is in reach is the number it compares, and getting that wrong is silent
-- either way -- a reader who never sees the page, or a fresh install handed a list of changes it
-- has never met.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;

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

    --- The account file as a profile that has been on disk holds it, minus the field under test.
    local function StoredProfile()
        return {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { ["Player-1-TESTGUID"] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
    end

    --- **The specs share one process and one `_G.DebindVars`.** Whatever was standing before this
    --- file ran goes back up at the end, through `InitDB`, so the tables the rest of the run reads
    --- are the ones it left.
    local before = _G.DebindVars;

    test("a profile made on this login starts at the current number", function()
        _G.DebindVars = nil;
        DebindPrivate.InitDB();
        check(_G.DebindVars.changelogSeen == Constants.CHANGELOG_VERSION,
            "a fresh install would be shown the changelog: " .. tostring(_G.DebindVars.changelogSeen));
    end);

    test("a profile already on disk starts behind", function()
        _G.DebindVars = StoredProfile();
        DebindPrivate.InitDB();
        check(_G.DebindVars.changelogSeen == 0,
            "an existing reader would never be shown the changelog: "
            .. tostring(_G.DebindVars.changelogSeen));
    end);

    --- **Loading does not move a number that is already there.** Raising it here would read as
    --- the page having been shown, and the login that was meant to show it never would.
    test("a number already stored is left where it is", function()
        local db = StoredProfile();
        db.changelogSeen = 0;
        _G.DebindVars = db;
        DebindPrivate.InitDB();
        check(_G.DebindVars.changelogSeen == 0,
            "the stored number moved to " .. tostring(_G.DebindVars.changelogSeen));
    end);

    _G.DebindVars = before;
    if (before) then
        DebindPrivate.InitDB();
    end

    return T;
end
