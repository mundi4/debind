-- The canonical-shape net itself (`canonical.lua`): **does it reach every stored list?** A net that
-- walks too little stays green over exactly what it was put there to find, and nothing else says so.
--
-- Each case plants one wrong value in a place a writer can reach and asks the net's findings
-- directly. No rebuild runs here, so the net installed around this spec never sees the planted
-- values, and each case takes them out again before the next one stands a profile up.

return function(DebindPrivate, DebindStorage, ctx)
    local Constants = DebindPrivate.Constants;
    local GUID = _G.UnitGUID("player");

    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function Login()
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = {
                { type = Constants.SPELL, value = 1, key = "F1", seq = 1 },
            } } } },
            characters = {}, migrated = {},
        };
        DebindPrivate.InitDB();
    end

    --- The net's findings, with `undo` run however the asking ends.
    local function Findings(undo)
        local ok, findings = pcall(ctx.CanonicalFindings, DebindPrivate, DebindStorage);
        undo();
        assert(ok, findings);
        return table.concat(findings, " | ");
    end

    local function expect(findings, text, where)
        if (not findings:find(text, 1, true) or not findings:find(where, 1, true)) then
            error(("expected %q at %q, the net said: %s"):format(text, where, findings == "" and "nothing" or findings), 2);
        end
    end

    test("a profile as it loads holds nothing to report", function()
        Login();
        local findings = Findings(function() end);
        assert(findings == "", findings);
    end);

    test("another class's cell is reached", function()
        Login();
        local layers = _G.DebindVars.layers;
        layers.account.PRIEST = { [2] = { { type = Constants.SPELL, value = 2, key = "P" } } };
        expect(Findings(function() layers.account.PRIEST = nil; end),
            "no seq on a keyed action", "layers/account/PRIEST/2");
    end);

    test("another character's cell is reached", function()
        Login();
        local layers = _G.DebindVars.layers;
        layers["Player-1-OTHER"] = { PRIEST = { [0] = { { type = Constants.SPELL, value = 2, junk = 1 } } } };
        expect(Findings(function() layers["Player-1-OTHER"] = nil; end),
            "field junk is not saved", "layers/Player-1-OTHER/PRIEST/0");
    end);

    test("this character's cell is reached before it is attached", function()
        Login();
        local charLayers = DebindPrivate.db.charLayers;
        charLayers.WARRIOR = { [1] = { { type = Constants.SPELL, value = 2, junk = 1 } } };
        expect(Findings(function() charLayers.WARRIOR = nil; end),
            "field junk is not saved", "layers/" .. GUID .. "/WARRIOR/1");
    end);

    test("a pending share is reached", function()
        Login();
        local global = DebindPrivate.db.global;
        global.pendingActions = { ["Player-1-OTHER"] = {
            account = { GENERAL = { [0] = { { type = Constants.SPELL, value = 2, arrivalID = 3, junk = 1 } } } },
            character = { [1] = { { type = Constants.SPELL, value = 3, arrivalID = 3, junk = 1 } } },
        } };
        local findings = Findings(function() global.pendingActions = nil; end);
        expect(findings, "field junk is not saved", "pendingActions/Player-1-OTHER/account/GENERAL/0");
        expect(findings, "field junk is not saved", "pendingActions/Player-1-OTHER/character/1");
    end);

    test("what stands where a table belongs is reported", function()
        Login();
        local layers = _G.DebindVars.layers;
        layers.account.PRIEST = { [1] = "x", [2] = { [1] = 5 } };
        local findings = Findings(function() layers.account.PRIEST = nil; end);
        expect(findings, "is a string, not a list", "layers/account/PRIEST/1");
        expect(findings, "[1] is a number, not an action", "layers/account/PRIEST/2");
    end);

    test("an action under a name or past a hole is reported", function()
        Login();
        local list = DebindPrivate.GetProfileLayer(1).actions;
        list.extra = { type = Constants.SPELL, value = 2 };
        list[3] = { type = Constants.SPELL, value = 3 };
        local findings = Findings(function()
            list.extra = nil;
            list[3] = nil;
        end);
        expect(findings, "under \"extra\", not at a position", "layer 1");
        expect(findings, "a hole: 2 elements up to [3]", "layer 1");
    end);

    test("a list marked as planted is passed over whole", function()
        Login();
        local layers = _G.DebindVars.layers;
        layers.account.PRIEST = { [2] = ctx.HandMade({ "x", { type = Constants.SPELL, value = 2, junk = 1 } }) };
        local findings = Findings(function() layers.account.PRIEST = nil; end);
        assert(findings == "", findings);
    end);

    return T;
end
