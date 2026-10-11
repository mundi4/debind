-- **A custom target pinned on a group member, found again by its header.** No WoW client needed.
--
-- A pin on a party or raid member is kept by name: `UnitWatch` hands a `SecureGroupHeaderTemplate`
-- header a `nameList`, and the header fills a child with whoever answers to it. What decides
-- whether anyone does is **the name the header compares**, and that is the client's code, not
-- ours -- so the header's layout runs here as `restricted.lua` transcribes it, and each case asks
-- which unit `@custom1` ends up on.
--
-- Run on both clients. Camelot's `UnitName` answers a surname where retail answers a realm, and
-- the shim joins that surname with a separator of its own, so a list built from the displayed name
-- rather than the compared one shows there.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

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

    local GUID = "Player-1-CUSTOMSPEC";
    _G.DebindVars = {
        dbver = Constants.DB_VERSION,
        layers = {
            account = { GENERAL = { [0] = {
                { type = Constants.SPELL, value = 585, key = "F1", unit = "custom1", seq = 1 },
            } } },
            [GUID] = { [Constants.PLAYER_CLASS] = {} },
        },
        characters = { [GUID] = { switches = {} } },
        migrated = {},
        switches = { account = { GENERAL = { [0] = {} } } },
    };
    DebindPrivate.InitDB();
    shim.world.spells[585] = { name = "Renew" };
    check(DebindPrivate.UpdateBindings() == true, "the rebuild was refused");
    local interp = restricted.new(DebindPrivate, shim.world);

    --- Two people, each with a second name the header has to join: the reader, and one other.
    local ME = { id = "me", name = "Galstan", second = "Yulebraid", reaction = "help", isPlayer = true };
    local THEM = { id = "them", name = "Jathelbur", second = "Drillmaven", reaction = "help", isPlayer = true };
    --- **Spelled unlike the "-" name on purpose.** Nothing says a raid roster spells a name the
    --- way a party's `UnitName` join does, and a list that only works when the two agree would
    --- pass here only by luck.
    local ME_ROSTER, THEM_ROSTER = "Galstan of the roster", "Jathelbur of the roster";

    local function party()
        shim.world.group = "party";
        shim.world.units = {
            player = ME,
            party1 = setmetatable({ inParty = true }, { __index = THEM }),
        };
    end

    --- **They share a subgroup**, so the client also answers THEM as `party1` -- a second token for
    --- one raid member, and the one a list built from the token's own name gets wrong.
    local function raid()
        shim.world.group = "raid";
        shim.world.units = {
            player = setmetatable({ raidIndex = 1 }, { __index = ME }),
            raid1 = setmetatable({ raidIndex = 1, inRaid = true, rosterName = ME_ROSTER }, { __index = ME }),
            raid2 = setmetatable({ raidIndex = 2, inRaid = true, rosterName = THEM_ROSTER },
                { __index = THEM }),
            party1 = setmetatable({ raidIndex = 2, inRaid = true, inParty = true }, { __index = THEM }),
        };
    end

    local function solo()
        shim.world.group = nil;
        shim.world.units = { player = ME };
    end

    --- Puts custom1 back to nothing, saved value included, so a case starts from no pin.
    local function unpin()
        interp:setCustomTarget("custom1", "none");
        frames.drainTimers();
    end

    local header = DebindPrivate.UnitWatchHeaders.custom1;
    local function custom1()
        return interp.env.UnitAliasMap.custom1;
    end

    test("a party member pinned by token is found by the header", function()
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "party1");
        frames.drainTimers();

        check(header:IsShown(), "the pin did not go to the header");
        check(custom1() == "party1",
            ("@custom1 is %s; the header held %q and found nobody"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    --- **The pin is the person, not the slot**, and converting the group renames every slot.
    --- In a raid the header compares the roster's name, so the list it was given in the party has
    --- to be carried to the one this roster writes for the same person.
    test("the pin follows its person from party to raid and back", function()
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "party1");
        check(custom1() == "party1", "premise: the pin never took in the party");

        raid();
        interp:rosterChanged();
        check(custom1() == "raid2",
            ("in the raid @custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));

        party();
        interp:rosterChanged();
        check(custom1() == "party1",
            ("back in the party @custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));

        --- What a login reads back, so it has to be a list the header can still find them by.
        frames.drainTimers();
        local saved = DebindPrivate.GetSavedCustomTarget("custom1");
        interp:setCustomTarget("custom1", "none");
        check(custom1() == nil, "premise: the clear did not take");
        interp:setCustomTarget("custom1", saved);
        check(custom1() == "party1",
            ("the saved %q finds %s after a login"):format(tostring(saved), tostring(custom1())));
    end);

    --- **A raid member has more than one token.** One in the reader's subgroup is `party1` as well
    --- as `raid2`, and the raid header looks it up by the roster's name whichever token named it.
    test("in a raid, a subgroup member pinned by its party token is found", function()
        unpin();
        raid();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "party1");
        check(custom1() == "raid2",
            ("@custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    --- **A login reads the saved list before the roster can carry it.** Pinned in a party, and the
    --- group became a raid while the reader was away: the saved list is the party's.
    test("a pin saved in a party is found after logging in to a raid", function()
        unpin();
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "party1");
        frames.drainTimers();
        local saved = DebindPrivate.GetSavedCustomTarget("custom1");
        unpin();
        DebindPrivate.SaveCustomTarget("custom1", saved);

        raid();
        local unitWatch = DebindPrivate.UnitWatch;
        local mark = frames.mark();
        unitWatch:GetScript("OnEvent")(unitWatch, "PLAYER_LOGIN");
        interp:replay(frames.since(mark));
        check(custom1() == "raid2",
            ("saved %q, and after the login @custom1 is %s; the header held %q"):format(
                tostring(saved), tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    --- **A name the client will not show is no name at all.** Kept with half of it, the pin would
    --- be a first name alone, and on camelot a first name is not one person.
    test("a member whose second name is secret is not pinned by the first", function()
        unpin();
        local SECRET = {};
        local prior = _G.issecretvalue;
        _G.issecretvalue = function(value) return value == SECRET; end;
        local ok, err = pcall(function()
            party();
            shim.world.units.party1 = setmetatable({ inParty = true, second = SECRET }, { __index = THEM });
            interp:rosterChanged();
            interp:setCustomTarget("custom1", "party1");
            frames.drainTimers();
            check(not header:IsShown(),
                ("the header holds %q"):format(tostring(header:GetAttribute("nameList"))));
            local saved = DebindPrivate.GetSavedCustomTarget("custom1");
            check(saved == nil, "saved " .. tostring(saved));
        end);
        _G.issecretvalue = prior;
        assert(ok, err);
    end);

    --- **A list is whatever `/deb custom1` was handed**, and one with no first name still has to
    --- leave the announcing timer working: a raise there stops every later change being saved.
    test("a list with an empty first entry leaves later pins saved", function()
        unpin();
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", ":,Somebody");
        local ok, err = pcall(frames.drainTimers);
        check(ok, "announcing it raised: " .. tostring(err));

        interp:setCustomTarget("custom1", "player");
        frames.drainTimers();
        local saved = DebindPrivate.GetSavedCustomTarget("custom1");
        check(saved == "player", "the pin after it was saved as " .. tostring(saved));
    end);

    --- **Carrying adds names and takes none away.** A roster that cannot answer a member's name
    --- yet (a login into a raid) must not cost the list the one name the raid header reads, and a
    --- fight that follows gets no roster update to win it back.
    test("a roster that cannot name the member yet leaves the pin's raid name in place", function()
        unpin();
        raid();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "raid2");
        check(custom1() == "raid2", "premise: the pin never took in the raid");

        shim.world.units.raid2 = setmetatable({ raidIndex = 2, inRaid = true }, { __index = THEM });
        interp:rosterChanged();

        raid();
        shim.world.inCombat = true;
        local ok, err = pcall(function() interp:rosterChanged(); end);
        shim.world.inCombat = false;
        assert(ok, err);
        check(custom1() == "raid2",
            ("in the fight @custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    --- A list handed over by hand can name more than one person, and carrying it to a raid keeps
    --- the ones the roster says nothing about.
    test("carrying a list keeps the names nobody in the roster answers to", function()
        unpin();
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", ":Jathelbur-Drillmaven,Somebody");
        check(custom1() == "party1", "premise: the pin never took in the party");

        raid();
        interp:rosterChanged();
        local list = tostring(header:GetAttribute("nameList"));
        check(custom1() == "raid2", ("in the raid @custom1 is %s; the header held %q"):format(
            tostring(custom1()), list));
        check((("," .. list .. ",")):find(",Somebody,", 1, true), "Somebody was dropped: " .. list);
    end);

    --- **The person is named the way the client names them**, present or not.
    test("a pinned member who left is named as the client shows them", function()
        unpin();
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "party1");
        frames.drainTimers();

        --- The harness loads no locale, so the line would be its key alone and name nobody.
        local said = {};
        local display = DebindPrivate.DisplayMessage;
        DebindPrivate.DisplayMessage = function(text) said[#said + 1] = text; end;
        DebindPrivate.L.SPECIAL_UNIT_SET_MESSAGE = "%s - %s";
        local ok, err = pcall(function()
            solo();
            interp:rosterChanged();
            frames.drainTimers();
        end);
        DebindPrivate.DisplayMessage = display;
        DebindPrivate.L.SPECIAL_UNIT_SET_MESSAGE = nil;
        assert(ok, err);

        local shown = DebindPrivate.JoinUnitName(THEM.name, THEM.second);
        check(#said == 1 and said[1]:find(shown, 1, true),
            ("expected one line naming %q, got: %s"):format(shown, table.concat(said, " | ")));
    end);

    return T;
end
