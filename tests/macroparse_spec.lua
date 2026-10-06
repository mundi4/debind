-- What the headless `SecureCmdOptionParse` answers (`restricted.lua`). Once a beat and a press
-- parse whole expressions (`implementing-the-trimmed-tail-key-beat.md` P0-1), every spec that reads
-- a key through `restricted.lua` stands on this answering the way the client does: clause values,
-- `@unit`, and the words where the client was measured answering otherwise than its API.

return function(DebindPrivate)
    local shim = require("wow_shim");
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

    local interp = restricted.new(DebindPrivate, shim.world);
    local env = interp.env;

    local function fresh()
        interp:resetState();
        for k in pairs(shim.world.units) do
            shim.world.units[k] = nil;
        end
    end

    local function parse(expr)
        return env.SecureCmdOptionParse(expr);
    end

    local function answers(expr, want)
        local got = parse(expr);
        check(got == want, format("%s answered %s, not %s", expr, tostring(got), tostring(want)));
    end

    test("the first matching clause answers with its own text", function()
        fresh();
        interp.state.mounted = true;
        answers("[combat] fight; [mounted] ride; walk", "ride");
        interp.state.combat = true;
        answers("[combat] fight; [mounted] ride; walk", "fight");
        interp.state.combat, interp.state.mounted = false, false;
        answers("[combat] fight; [mounted] ride; walk", "walk");
    end);

    test("no clause matching is nil, and a matched clause with no text is the empty string", function()
        fresh();
        answers("[combat] fight", nil);
        answers("[nocombat]", "");
        answers("[] always", "always");
    end);

    -- **A text ending in `; ` ends in an empty clause with no group, which matches and answers `""`**
    -- (2026-10-06, 57 watch-shaped texts on the client's insecure side, `cutting-the-beat-under-a-
    -- zero-period.md`). The beat's watch ends every fragment so and reads `""` as "no place held".
    -- The parser already answered so; this pins it to that measurement, and goes red against one
    -- that skips a blank clause.
    test("a trailing empty clause answers the empty string where nothing before it matched", function()
        fresh();
        answers("[combat] 1; ", "");
        answers("[nocombat] 1; ", "1");
        answers("[combat] 1; [mounted] 2; ", "");
        answers("; ", "");
    end);

    test("groups in one clause are OR'd, words in one group AND'd", function()
        fresh();
        interp.state.mounted = true;
        answers("[combat][mounted] x", "x");
        answers("[combat,mounted] x", nil);
    end);

    test("@unit names the unit for every unit word in its group, wherever it stands", function()
        fresh();
        shim.world.units.target = { id = 1, reaction = "harm" };
        shim.world.units.focus = { id = 2, reaction = "help" };
        answers("[help] t; f", "f");
        answers("[help,@focus] yes; no", "yes");
        answers("[@focus,harm] yes; no", "no");
        answers("[target=focus,help] yes; no", "yes");
    end);

    test("dead is true for a ghost too", function()
        fresh();
        shim.world.units.target = { id = 1, ghost = true };
        answers("[@target,dead] d; a", "d");
    end);

    test("the player is not in its own party to [party], and is in its own raid", function()
        fresh();
        shim.world.units.player = { id = 0, inParty = true, inRaid = true };
        interp.state.group = "raid";
        answers("[@player,party] p; n", "n");
        answers("[@player,raid] r; n", "r");
        check(env.UnitPlayerOrPetInParty("player") == true, "the API answer for the player moved");
    end);

    test("[group:party] holds in a raid", function()
        fresh();
        interp.state.group = "raid";
        answers("[group:party] p; n", "p");
        answers("[group:raid] r; n", "r");
        interp.state.group = "party";
        answers("[group:raid] r; n", "n");
    end);

    test("offset 0 is [nobonusbar:1/2/3/4/5], never [bonusbar:0] or bare [bonusbar]", function()
        fresh();
        answers("[nobonusbar:1/2/3/4/5] none; some", "none");
        answers("[bonusbar:0] zero; other", "other");
        answers("[bonusbar] any; none", "none");
        interp.state.bonusbar = 5;
        answers("[nobonusbar:1/2/3/4/5] none; some", "some");
        answers("[bonusbar:5] five; other", "five");
    end);

    test("a possession is [possessbar] and not [vehicleui]", function()
        fresh();
        interp.state.vehiclebar = true;
        answers("[vehicleui] v; [possessbar] p; n", "v");
        interp.state.possessbar = true;
        answers("[vehicleui] v; [possessbar] p; n", "p");
        check(env.HasVehicleActionBar() == true, "the vehicle bar is up for both");
    end);

    test("a diverged word parses one way while the API answers the other", function()
        fresh();
        interp.state.diverge.combat = true;
        answers("[combat] c; n", "c");
        check(env.PlayerInCombat() == false, "the API followed the divergence");
        interp:resetState();
        answers("[combat] c; n", "n");
    end);

    test("a word the interpreter does not know raises", function()
        fresh();
        local ok = pcall(parse, "[nosuchword] x");
        check(not ok, "an unknown word was read as an answer");
    end);

    return T;
end
