-- **A custom target pinned on a group member, found again by its header.** No WoW client needed.
--
-- A pin on a party or raid member is kept by name: `UnitWatch` hands a `SecureGroupHeaderTemplate`
-- header a `nameList`, and the header fills a child with whoever answers to it. What decides
-- whether anyone does is **the name the header compares**, and that is the client's code, not
-- ours -- so the header's layout runs here as `restricted.lua` transcribes it, and each case asks
-- which unit `@custom1` ends up on.
--
-- Run on both clients. Camelot's `UnitName` answers a surname where retail answers a realm, and
-- the shim joins that surname with a separator of its own, so there the "-" name a party compares
-- and the shown name are two spellings and a list holding only one of them finds nobody somewhere.

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
    --- **Spelled unlike every name the unit gives, on purpose.** Camelot's roster does not spell a
    --- name the way a party's `UnitName` join does (measured on 70338: "Jathelbur Drillmaven"), and
    --- what has to hold is that the list carries whatever the roster answers, read rather than
    --- assumed. `shownRaid` below is the spelling camelot actually has.
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
    --- be a first name alone, and on camelot a first name is not one person. The press still sets
    --- them, by the token: a secret is not a name that is about to load, so turning it down with
    --- "try again" would never come right, least of all in the fight where secrets turn up.
    test("a member whose second name is secret is pinned by token, not by the first", function()
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
            check(custom1() == "party1", "@custom1 is " .. tostring(custom1()));
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

    --- **"Unknown" is the client saying it has no name yet**, and it says it for everyone it has
    --- not loaded. Kept as a name, the pin would gather every one of them when it is carried; kept
    --- as a bare token, the roster watcher's next layout drops it -- and the name arriving is what
    --- sets that layout off. So the press is turned down, and the pin before it stays.
    test("a member the client has no name for yet is turned down, and the pin before stays", function()
        unpin();
        party();
        shim.world.units.party1 = setmetatable({ inParty = true, name = UNKNOWNOBJECT, second = false },
            { __index = THEM });
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "player");
        check(custom1() == "player", "premise: the pin on the player never took");
        frames.drainTimers();

        local said = {};
        local display = DebindPrivate.DisplayMessage;
        DebindPrivate.DisplayMessage = function(text) said[#said + 1] = text; end;
        local ok, err = pcall(function()
            interp:setCustomTarget("custom1", "party1");
            frames.drainTimers();
        end);
        DebindPrivate.DisplayMessage = display;
        assert(ok, err);

        check(custom1() == "player", "the press moved @custom1 to " .. tostring(custom1()));
        check(#said == 1 and said[1]:find("CUSTOM_TARGET_NAME_NOT_LOADED", 1, true),
            "expected the not-loaded line, got: " .. table.concat(said, " | "));
    end);

    --- **The roster can know a name `UnitName` does not yet**, and in a raid the roster's is the one
    --- the header compares. The pin takes it, and gains the "-" name once that loads.
    test("in a raid, a member named only by the roster is pinned by it", function()
        unpin();
        raid();
        shim.world.units.raid2 = setmetatable({ raidIndex = 2, inRaid = true, name = UNKNOWNOBJECT,
            second = false, rosterName = THEM_ROSTER }, { __index = THEM });
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "raid2");
        --- By the name, not the bare token, which would also land on raid2 here.
        check(header:IsShown() and header:GetAttribute("nameList") == THEM_ROSTER and custom1() == "raid2",
            ("@custom1 is %s; the header %s %q"):format(tostring(custom1()),
                header:IsShown() and "held" or "is hidden and last held",
                tostring(header:GetAttribute("nameList"))));

        raid();
        interp:rosterChanged();
        party();
        interp:rosterChanged();
        check(custom1() == "party1",
            ("once the name loaded and the raid became a party, @custom1 is %s; the header held %q")
                :format(tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    --- The header trims each name it is handed (`SecureGroupHeaders.lua`, `fillTable`), so a list
    --- typed with a space finds its person, and carrying it has to read the name the same way.
    test("a hand-typed list with spaces is carried to a raid", function()
        unpin();
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", ": Jathelbur-Drillmaven");
        check(custom1() == "party1", "premise: the header did not find them in the party");

        raid();
        interp:rosterChanged();
        check(custom1() == "raid2",
            ("in the raid @custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    --- The roster can say "Unknown" for a member whose `UnitName` is already loaded, and that
    --- spelling in the list would find every member the roster has not loaded yet.
    test("a roster that answers Unknown adds nothing to the pin", function()
        unpin();
        raid();
        shim.world.units.raid2.rosterName = UNKNOWNOBJECT;
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "raid2");
        interp:rosterChanged();
        local list = tostring(header:GetAttribute("nameList"));
        check(not (("," .. list .. ",")):find("," .. UNKNOWNOBJECT .. ",", 1, true),
            "the pin holds " .. list);
    end);

    --- **Camelot only.** On retail the shown name is the "-" join, so these two would pass against a
    --- list that never held the shown spelling at all.
    if (DebindPrivate.GAME_TYPE == "camelot") then

    --- **A raid spelled the way the client shows a name**, as camelot's is (measured on 70338:
    --- `GetRaidRosterInfo` answered "Jathelbur Drillmaven", the same as `GetUnitFullName`, for every
    --- member). The group converts in a fight, so no roster update comes to carry anything: the
    --- list from the party has to find them as it is.
    local function shownRaid()
        raid();
        shim.world.units.raid1.rosterName = DebindPrivate.JoinUnitName(ME.name, ME.second);
        shim.world.units.raid2.rosterName = DebindPrivate.JoinUnitName(THEM.name, THEM.second);
    end

    test("a pin from a party is found when the group becomes a raid in a fight", function()
        unpin();
        party();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", "party1");
        check(custom1() == "party1", "premise: the pin never took in the party");

        shownRaid();
        shim.world.inCombat = true;
        local ok, err = pcall(function() interp:rosterChanged(); end);
        shim.world.inCombat = false;
        assert(ok, err);
        check(custom1() == "raid2",
            ("in the fight @custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    --- **What a released build saved on camelot.** It built the list with `FULL_PLAYER_NAME`, which
    --- is "%s %s" there with a space for the surname separator (measured on 70338), so the saved
    --- pin holds the shown spelling alone -- `JoinUnitName`'s, which is what this saves. A raid's
    --- header compares that spelling and a party's does not.
    test("a pin saved as the shown name is found in a party after a login", function()
        unpin();
        party();
        interp:rosterChanged();
        DebindPrivate.SaveCustomTarget("custom1", ":" .. DebindPrivate.JoinUnitName(THEM.name, THEM.second));

        local unitWatch = DebindPrivate.UnitWatch;
        local mark = frames.mark();
        unitWatch:GetScript("OnEvent")(unitWatch, "PLAYER_LOGIN");
        interp:replay(frames.since(mark));
        check(custom1() == "party1",
            ("after the login @custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));
    end);

    end

    --- **Any name in the list says who it is**, the roster's included, as far as a header can tell
    --- (`CarryNamePins`). A list holding only the roster's spelling still has to be found again once
    --- the raid becomes a party.
    test("a list holding only the roster's spelling follows its person back to a party", function()
        unpin();
        raid();
        interp:rosterChanged();
        interp:setCustomTarget("custom1", ":" .. THEM_ROSTER);
        check(custom1() == "raid2", "premise: the roster's spelling found nobody in the raid");
        interp:rosterChanged();

        party();
        interp:rosterChanged();
        check(custom1() == "party1",
            ("back in the party @custom1 is %s; the header held %q"):format(
                tostring(custom1()), tostring(header:GetAttribute("nameList"))));
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
