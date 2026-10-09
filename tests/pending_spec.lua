-- Pending actions kept with the character that brought them in
-- (`keeping-pending-actions-per-character.md`).
--
-- On disk a pending action is not in the shared layers but in `pendingActions[guid]`. During a
-- session it is back in this character's layer arrays, so everything that reads layers reads it
-- there. The two halves are the merge at load and
-- the split at logout, and what goes wrong between them is silent: a share written out empty is
-- every pending action of that character gone, on a login that showed nothing.

return function(DebindPrivate)
    local frames = require("wow_frames");
    local C = DebindPrivate.Constants;

    DebindPrivate.callbacks = DebindPrivate.callbacks or { Fire = function() end };
    DebindPrivate.log = function() end;

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

    local GUID = _G.UnitGUID("player");
    local OTHER = "Player-1-SOMEONEELSE";
    local CLASS = C.PLAYER_CLASS;

    local function spell(value, key, arrivalID, seq)
        return { type = C.SPELL, value = value, key = key, seq = key and (seq or 1) or nil, arrivalID = arrivalID };
    end

    local function Login(vars)
        vars.dbver = C.DB_VERSION;
        vars.characters = vars.characters or {};
        vars.migrated = vars.migrated or {};
        vars.legacyNeeded = false;
        vars.layers = vars.layers or {};
        _G.DebindVars = vars;
        DebindPrivate.InitDB();
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");
    end

    local function Logout()
        check(frames.fireEvent("PLAYER_LOGOUT") > 0, "nothing is listening for PLAYER_LOGOUT");
    end

    local function LayerActions(spec, isCharacterSpecific)
        local layerID = isCharacterSpecific == nil and 1 or DebindPrivate.GetLayerID(spec, isCharacterSpecific);
        return DebindPrivate.GetProfileLayer(layerID).actions;
    end

    local function Values(list)
        local out = {};
        for i = 1, #(list or {}) do
            out[i] = tostring(list[i].value) .. (list[i].arrivalID and ("#" .. list[i].arrivalID) or "");
        end
        return table.concat(out, ",");
    end

    --- Every badged action anywhere in `layers`, as values.
    local function BadgesInLayers()
        local found = {};
        for _, classes in pairs(_G.DebindVars.layers or {}) do
            for _, specTbl in pairs(classes) do
                for spec = 0, 5 do
                    for _, action in ipairs(specTbl[spec] or {}) do
                        if (action.arrivalID) then
                            found[#found + 1] = tostring(action.value);
                        end
                    end
                end
            end
        end
        return table.concat(found, ",");
    end

    --- A profile with this character's share in three cells, and someone else's share beside it.
    local function TwoShares()
        return {
            layers = { account = { GENERAL = { [0] = { spell(1, "F1") } } } },
            pendingActions = {
                [GUID] = {
                    account = {
                        GENERAL = { [0] = { spell(11, "F2", 4), spell(12, "F2", 4, 2) } },
                        [CLASS] = { [2] = { spell(13, "F3", 4) } },
                    },
                    character = { [0] = { spell(14, nil, 5) } },
                },
                [OTHER] = { account = { GENERAL = { [0] = { spell(21, "F2", 6) } } } },
            },
        };
    end

    test("this character's pending actions are back in its layers for the session", function()
        Login(TwoShares());
        check(Values(LayerActions(0)) == "1,11#4,12#4", "general " .. Values(LayerActions(0)));
        check(Values(LayerActions(2, false)) == "13#4", "class spec 2 " .. Values(LayerActions(2, false)));
        check(Values(LayerActions(0, true)) == "14#5", "character " .. Values(LayerActions(0, true)));
    end);

    test("someone else's pending actions are nowhere in this session", function()
        Login(TwoShares());
        local seen = {};
        for _, action in ipairs(DebindPrivate.CollectArrivedActions()) do
            seen[#seen + 1] = tostring(action.value);
        end
        table.sort(seen);
        check(table.concat(seen, ",") == "11,12,13,14", "waiting in this session: " .. table.concat(seen, ","));
    end);

    -- **The load-time `CleanUpDB` must not split.** It runs before anything is merged, so a split
    -- there writes this character's share out empty.
    test("a logout rebuilds this character's share and leaves someone else's as it was", function()
        Login(TwoShares());
        -- An arrival placed this session, so the share has to be rebuilt rather than left alone.
        table.insert(LayerActions(2, false), spell(15, "F4", 7));
        Logout();
        local mine = _G.DebindVars.pendingActions and _G.DebindVars.pendingActions[GUID];
        check(mine, "this character's share is gone");
        check(Values(mine.account.GENERAL[0]) == "11#4,12#4", "general " .. Values(mine.account.GENERAL[0]));
        check(Values(mine.account[CLASS][2]) == "13#4,15#7", "class " .. Values(mine.account[CLASS] and mine.account[CLASS][2]));
        check(Values(mine.character[0]) == "14#5", "character " .. Values(mine.character and mine.character[0]));
        check(BadgesInLayers() == "", "badges left in the shared layers: " .. BadgesInLayers());
        check(Values(_G.DebindVars.layers.account.GENERAL[0]) == "1", "general layer " ..
            Values(_G.DebindVars.layers.account.GENERAL[0]));
        local theirs = _G.DebindVars.pendingActions[OTHER];
        check(theirs and Values(theirs.account.GENERAL[0]) == "21#6", "the other share changed");
    end);

    test("accepted stays in the layer and rejected is gone", function()
        Login(TwoShares());
        local general = LayerActions(0);
        -- Accept 11 and 12, reject 14 (the whole of arrival 5).
        general[2].arrivalID = nil;
        general[3].arrivalID = nil;
        local character = LayerActions(0, true);
        table.remove(character, 1);
        Logout();

        check(Values(_G.DebindVars.layers.account.GENERAL[0]) == "1,11,12",
            "general layer " .. Values(_G.DebindVars.layers.account.GENERAL[0]));
        local mine = _G.DebindVars.pendingActions[GUID];
        check(Values(mine.account[CLASS][2]) == "13#4", "class " .. Values(mine.account[CLASS][2]));
        check(mine.account.GENERAL == nil, "an emptied cell stayed")
        check(mine.character == nil, "an emptied cell stayed");
    end);

    test("a character with nothing pending leaves no share", function()
        local vars = TwoShares();
        vars.pendingActions[GUID] = { character = { [0] = { spell(14, nil, 5) } } };
        Login(vars);
        table.remove(LayerActions(0, true), 1);
        Logout();
        check(_G.DebindVars.pendingActions[GUID] == nil, "an empty share stayed");
    end);

    -- §3-2: badges written before this existed are in the shared layers, and the first logout of a
    -- character that loads the layer takes them.
    test("a badge already in a shared layer moves into this character's share", function()
        Login({ layers = { account = { GENERAL = { [0] = { spell(1, "F1"), spell(31, "F1", 1) } } } } });
        Logout();
        check(Values(_G.DebindVars.layers.account.GENERAL[0]) == "1",
            "general layer " .. Values(_G.DebindVars.layers.account.GENERAL[0]));
        local mine = _G.DebindVars.pendingActions and _G.DebindVars.pendingActions[GUID];
        check(mine and Values(mine.account.GENERAL[0]) == "31#1", "the old badge was not taken");
    end);

    test("a character layer holding only pending actions is not attached", function()
        Login({ layers = { [GUID] = { [CLASS] = { [0] = { spell(41, nil, 2) } } } } });
        Logout();
        check(_G.DebindVars.layers[GUID] == nil, "a character layer with nothing but pending stayed attached");
        local mine = _G.DebindVars.pendingActions and _G.DebindVars.pendingActions[GUID];
        check(mine and Values(mine.character[0]) == "41#2", "the pending action was not kept");
    end);

    -- A pending action names this profile's switches from the moment it lands
    -- (`importing-switches-apart-from-actions.md` 2-2), so what is done to a switch reaches it --
    -- someone else's pending included, which waits in their share until they log in.
    local function SwitchProfile()
        return {
            layers = { account = { GENERAL = { [0] = {
                { type = C.SPELL, value = 1, key = "F1", seq = 1, conditions = { ["$a"] = true } },
            } } } },
            switches = { account = { GENERAL = { [0] = {
                ["$a"] = { mode = C.SWITCH_MODES.MANUAL },
                ["$c"] = { mode = C.SWITCH_MODES.MANUAL },
            } } } },
            pendingActions = {
                [GUID] = { account = { GENERAL = { [0] = {
                    { type = C.SPELL, value = 2, key = "F2", seq = 1, arrivalID = 3, conditions = { ["$a"] = true } },
                } } } },
                [OTHER] = {
                    account = { GENERAL = { [0] = {
                        { type = C.SPELL, value = 3, key = "F3", seq = 1, arrivalID = 4, conditions = { ["$a"] = true } },
                    } } },
                    character = { [1] = {
                        { type = C.MACROTEXT, value = "/cast [$a] Fireball", arrivalID = 4 },
                    } },
                },
            },
        };
    end

    test("renaming a switch takes this character's pending actions with it", function()
        Login(SwitchProfile());
        check(DebindPrivate.Switches["$a"], "the switch is not there - the premise broke");
        check(DebindPrivate.RenameSwitch("$a", "$b"), "the rename was refused");
        local general = LayerActions(0);
        check(general[1].conditions["$b"] == true, "the reader's own action did not follow");
        check(general[2].conditions["$b"] == true and general[2].conditions["$a"] == nil,
            "the pending action stayed on the old name");
    end);

    test("renaming a switch reaches another character's pending actions", function()
        Login(SwitchProfile());
        check(DebindPrivate.RenameSwitch("$a", "$b"), "the rename was refused");
        local theirs = _G.DebindVars.pendingActions[OTHER];
        local action = theirs.account.GENERAL[0][1];
        check(action.conditions["$b"] == true and action.conditions["$a"] == nil,
            "their pending condition stayed on the old name");
        check(theirs.character[1][1].value == "/cast [$b] Fireball",
            "their pending macro body says " .. tostring(theirs.character[1][1].value));
    end);

    test("merging a switch takes every character's pending actions to the one kept", function()
        Login(SwitchProfile());
        check(DebindPrivate.MergeSwitch("$a", "$c"), "the merge was refused");
        local general = LayerActions(0);
        check(general[2].conditions["$c"] == true and general[2].conditions["$a"] == nil,
            "this character's pending action stayed on the merged name");
        local theirs = _G.DebindVars.pendingActions[OTHER];
        check(theirs.account.GENERAL[0][1].conditions["$c"] == true,
            "their pending condition stayed on the merged name");
        check(theirs.character[1][1].value == "/cast [$c] Fireball",
            "their pending macro body says " .. tostring(theirs.character[1][1].value));
    end);

    -- §2-5: pending is counted, and apart. It reaches no key yet, so it is not in the numbers that
    -- answer "what do my keys use"; it is in the ones that answer "can this go".
    test("counting a switch's users counts pending actions apart", function()
        Login(SwitchProfile());
        local account, character, live, pendingHere, pendingElsewhere = DebindPrivate.CountSwitchReferences("$a");
        check(account == 1 and character == 1 and live == 1,
            format("counted %d/%d/%d", account, character, live));
        check(pendingHere == 1, "this character's pending counted " .. tostring(pendingHere));
        check(pendingElsewhere == 2, "the other character's pending counted " .. tostring(pendingElsewhere));
    end);

    test("the usage list holds this character's pending actions in a group of their own", function()
        Login(SwitchProfile());
        local usage = DebindPrivate.CollectSwitchUsage()["$a"];
        check(usage and #usage.here == 1 and usage.general.actions == 1,
            format("usage lists %d, tallies %d", usage and #usage.here or -1,
                usage and usage.general.actions or -1));
        check(#usage.pending == 1 and usage.pending[1].action.value == 2,
            "pending listed " .. tostring(usage.pending and #usage.pending));
        check(usage.pendingElsewhere == 2, "elsewhere counted " .. tostring(usage.pendingElsewhere));
    end);

    -- §2-6: what adding says. Only a name this profile lacks is a name whose actions do nothing.
    test("the switches a set of actions names and this profile lacks, once each and sorted", function()
        Login(SwitchProfile());
        local missing = DebindPrivate.UndefinedSwitchNames({
            { type = C.SPELL, value = 1, conditions = { ["$a"] = true, ["$zz"] = true } },
            { type = C.MACROTEXT, value = "/cast [$yy] Fireball; [$zz] Frostbolt" },
            { type = C.SETSWITCH_TOGGLE, value = "$a" },
        });
        check(table.concat(missing, ",") == "$yy,$zz", "missing: " .. table.concat(missing, ","));
    end);

    test("a switch only pending actions name is in use", function()
        local vars = SwitchProfile();
        vars.layers.account.GENERAL[0][1].conditions = nil;
        Login(vars);
        check(DebindPrivate.CollectSwitchUsage()["$a"], "a switch pending actions wait on read as unused");
    end);

    return T;
end
