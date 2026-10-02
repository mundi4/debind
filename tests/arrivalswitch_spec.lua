-- The switches an arrival brings, kept at commit and settled at acceptance
-- (`resolving-switches-on-accept.md`). The window itself is the in-game kit's; what it is asked
-- and what its answers write is decided here.

return function(DebindPrivate, DebindStorage)
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

    local C = DebindPrivate.Constants;
    local CLASS = C.PLAYER_CLASS;
    local MANUAL, EXPR = C.SWITCH_MODES.MANUAL, C.SWITCH_MODES.EXPR;

    --- A profile with `$a` defined as the reader has it: manual, on at reset, and an override on
    --- class spec 2.
    local function Profile()
        _G.DebindVars = {
            dbver = C.DB_VERSION, characters = {}, migrated = {}, legacyNeeded = false,
            layers = { account = { GENERAL = { [0] = {} } } },
            switches = {
                account = {
                    GENERAL = { [0] = { ["$a"] = { mode = MANUAL, resetValue = true } } },
                    [CLASS] = { [2] = { ["$a"] = { mode = MANUAL, resetValue = false } } },
                },
            },
        };
        DebindPrivate.InitDB();
    end

    local function Spell(key, conditions)
        return { type = C.SPELL, value = 774, key = key, seq = 1, conditions = conditions };
    end

    --- A payload: actions in general, switch rows wherever `switches` puts them.
    local function Payload(actions, switches, extraLayers)
        local layers = { account = { GENERAL = { [0] = actions } } };
        for owner, classes in pairs(extraLayers or {}) do
            layers[owner] = classes;
        end
        return {
            v = DebindStorage.PAYLOAD_VERSION, dbver = C.DB_VERSION,
            layers = layers, switches = switches,
        };
    end

    local function Commit(payload, options)
        _G.DebindStorageVars = nil;
        local entry = assert(DebindStorage.StorePayload(payload));
        local placed, _, actions = DebindStorage.CommitEntry(entry, options or {});
        check(placed, "nothing was placed: " .. tostring(_));
        return actions;
    end

    local function Row(mode, resetValue, expr)
        return { mode = mode, resetValue = resetValue, expr = expr };
    end

    ---------------------------------------------------------------------------
    -- Keeping
    ---------------------------------------------------------------------------

    test("an arrival keeps the rows of the switches its actions name, at this character's addresses", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$b"] = true }) }, {
            account = {
                GENERAL = { [0] = { ["$b"] = Row(EXPR, nil, "[$c]"), ["$c"] = Row(MANUAL, true),
                    ["$unused"] = Row(MANUAL) } },
                [CLASS] = { [1] = { ["$b"] = Row(MANUAL, false) } },
                MAGE = { [1] = { ["$b"] = Row(MANUAL, true) } },
            },
            ["Player-9-SENDER"] = { [CLASS] = { [0] = { ["$b"] = Row(MANUAL, true) } } },
        }, { ["Player-9-SENDER"] = { [CLASS] = { [0] = { Spell("F2") } } } }),
            { parts = { general = true, class = false, character = "Player-9-SENDER" } });
        local record = DebindPrivate.GetArrivalRecord(actions[1].arrivalID);
        check(record and record.switches, "no record was kept");
        local b = record.switches["$b"];
        check(b and b.general and b.general.expr == "[$c]", "the general row of $b is missing");
        check(b.class and b.class[1] and b.class[1].resetValue == false,
            "the class row was dropped because the class box was not ticked");
        check(b.character and b.character[0], "the picked character's row is missing");
        check(record.switches["$c"], "a switch named only by another's expression was not followed");
        check(record.switches["$unused"] == nil, "a switch nothing names was kept");
        check(not (b.class and b.class.MAGE), "another class's row was kept");
    end);

    test("no character picked keeps no character rows", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$b"] = true }) }, {
            account = { GENERAL = { [0] = { ["$b"] = Row(MANUAL) } } },
            ["Player-9-SENDER"] = { [CLASS] = { [0] = { ["$b"] = Row(MANUAL, true) } } },
        }), { parts = { general = true } });
        local b = DebindPrivate.GetArrivalRecord(actions[1].arrivalID).switches["$b"];
        check(b.character == nil, "a character row came in with no character picked");
    end);

    ---------------------------------------------------------------------------
    -- Classifying
    ---------------------------------------------------------------------------

    local function Steps(actions)
        local answers = DebindPrivate.NewArrivalAnswers();
        local steps, byArrival = DebindPrivate.ArrivalSwitchSteps(actions);
        local items = {};
        for _, step in ipairs(steps) do
            local got = DebindPrivate.ClassifyArrivalSwitches(byArrival, step, answers);
            items[#items + 1] = got;
        end
        return answers, steps, items, byArrival;
    end

    test("a name the profile lacks is made without asking; a matching one is left alone", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$new"] = true, ["$a"] = true }) }, {
            account = {
                GENERAL = { [0] = { ["$new"] = Row(MANUAL, true), ["$a"] = Row(MANUAL, true) } },
                [CLASS] = { [2] = { ["$a"] = Row(MANUAL, false) } },
            },
        }));
        local answers, steps, items = Steps(actions);
        check(#steps == 1 and #items[1] == 0, "something was asked: " .. #(items[1] or {}));
        check(answers.creates["$new"], "the missing switch is not going to be made");
        check(answers.creates["$a"] == nil, "a switch the reader has was going to be made again");
    end);

    test("only rows that would overwrite or fill a layer are asked", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$a"] = true }) }, {
            account = {
                GENERAL = { [0] = { ["$a"] = Row(MANUAL, true) } },
                [CLASS] = { [2] = { ["$a"] = Row(MANUAL, true) }, [3] = { ["$a"] = Row(MANUAL, false) } },
            },
        }));
        local _, _, items = Steps(actions);
        local item = items[1][1];
        check(item and item.name == "$a", "nothing was asked about $a");
        check(#item.rows == 2, "rows asked: " .. #item.rows);
        local spec2 = DebindPrivate.GetLayerID(2, false);
        local spec3 = DebindPrivate.GetLayerID(3, false);
        check(item.rows[1].layerID == spec2 and item.rows[1].mine, "spec 2 is not an overwrite");
        check(item.rows[2].layerID == spec3 and item.rows[2].mine == nil, "spec 3 is not a fill");
    end);

    test("an expression left behind under another answer is not a difference", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$a"] = true }) }, {
            account = {
                GENERAL = { [0] = { ["$a"] = Row(MANUAL, true, "[combat]") } },
                [CLASS] = { [2] = { ["$a"] = Row(MANUAL, false) } },
            },
        }));
        local _, _, items = Steps(actions);
        check(#items[1] == 0, "a stale expression was asked about");
    end);

    test("two arrivals holding one name differently are asked one after another", function()
        Profile();
        local first = Commit(Payload({ Spell("F1", { ["$x"] = true }) },
            { account = { GENERAL = { [0] = { ["$x"] = Row(MANUAL, true) } } } }));
        local second = Commit(Payload({ Spell("F2", { ["$x"] = true }) },
            { account = { GENERAL = { [0] = { ["$x"] = Row(MANUAL, false) } } } }));
        local both = { first[1], second[1] };
        local answers, steps, items = Steps(both);
        check(#steps == 2, "steps " .. #steps);
        check(answers.creates["$x"] and answers.creates["$x"].cells[1].resetValue == true,
            "the first arrival's $x is not the one made");
        check(#items[2] == 1 and items[2][1].rows[1].mine.resetValue == true,
            "the second window did not compare with the first one's answer");
    end);

    ---------------------------------------------------------------------------
    -- Writing
    ---------------------------------------------------------------------------

    test("nothing is written until the badge comes off, and then all of it", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$a"] = true, ["$new"] = true }) }, {
            account = {
                GENERAL = { [0] = { ["$a"] = Row(MANUAL, false), ["$new"] = Row(MANUAL, true) } },
            },
        }));
        local answers, steps, items = Steps(actions);
        local item = items[1][1];
        DebindPrivate.AnswerArrivalSwitches(answers, items[1], { [item] = { checked = { [1] = true } } });
        check(DebindPrivate.Switches["$new"] == nil, "a switch was made before acceptance");
        check(DebindPrivate.Switches["$a"].resetValue == true, "a row was written before acceptance");

        DebindPrivate.TakeBadgesOff(actions, answers);
        check(actions[1].arrivalID == nil, "the badge stayed");
        check(DebindPrivate.Switches["$new"] and DebindPrivate.Switches["$new"].resetValue == true,
            "the missing switch was not made");
        check(DebindPrivate.Switches["$a"].resetValue == false, "the ticked row was not written");
        local record = DebindPrivate.GetArrivalRecord(steps[1][1]);
        check(record.resolved and record.resolved["$a"], "the answer was not marked");
    end);

    test("an answered switch is not asked again from the same arrival", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$a"] = true }), Spell("F2", { ["$a"] = true }) },
            { account = { GENERAL = { [0] = { ["$a"] = Row(MANUAL, false) } } } }));
        local answers, _, items = Steps({ actions[1] });
        DebindPrivate.AnswerArrivalSwitches(answers, items[1], {});
        DebindPrivate.TakeBadgesOff({ actions[1] }, answers);
        local _, steps = Steps({ actions[2] });
        check(#steps == 0, "kept mine and was asked again");
    end);

    test("a rename brings the switch in whole under the new name and the arrival follows", function()
        Profile();
        local actions = Commit(Payload({
            Spell("F1", { ["$a"] = true }),
            Spell("F2", { ["$a"] = false }),
            Spell("F3", { ["$c"] = true }),
        }, { account = { GENERAL = { [0] = {
            ["$a"] = Row(MANUAL, false), ["$c"] = Row(EXPR, nil, "[$a]"),
        } } } }));
        local answers, _, items = Steps({ actions[1] });
        local renamed, why = DebindPrivate.CheckArrivalRename("$Mine_A", answers);
        check(renamed == "$mine_a", "rename refused: " .. tostring(why));
        check(DebindPrivate.CheckArrivalRename("$a", answers) == nil, "a taken name was accepted");
        DebindPrivate.AnswerArrivalSwitches(answers, items[1], { [items[1][1]] = { rename = renamed } });
        DebindPrivate.TakeBadgesOff({ actions[1] }, answers);

        check(DebindPrivate.Switches["$a"].resetValue == true, "the reader's $a was touched");
        check(DebindPrivate.Switches["$mine_a"] and DebindPrivate.Switches["$mine_a"].resetValue == false,
            "the renamed switch was not made from the kept rows");
        check(actions[1].conditions["$mine_a"] == true, "the accepted action kept the old name");
        check(actions[2].conditions["$mine_a"] == false, "a pending action of the arrival kept the old name");
        local record = DebindPrivate.GetArrivalRecord(actions[2].arrivalID);
        check(record.switches["$mine_a"] and record.switches["$a"] == nil, "the kept rows kept the old name");
        check(record.switches["$c"].general.expr == "[$mine_a]", "another kept row's expression kept the old name");
    end);

    test("what TakeBadgesOff wrote is put back by its undo", function()
        Profile();
        local actions = Commit(Payload({ Spell("F1", { ["$a"] = true, ["$new"] = true }) }, {
            account = { GENERAL = { [0] = { ["$a"] = Row(MANUAL, false), ["$new"] = Row(MANUAL) } } },
        }));
        local arrivalID = actions[1].arrivalID;
        local answers, _, items = Steps(actions);
        DebindPrivate.AnswerArrivalSwitches(answers, items[1], { [items[1][1]] = { checked = { [1] = true } } });
        local undo = {};
        DebindPrivate.TakeBadgesOff(actions, answers, undo);
        check(DebindPrivate.Switches["$new"], "premise: nothing was made");
        DebindPrivate.RunArrivalUndo(undo);
        check(DebindPrivate.Switches["$new"] == nil, "the made switch stayed");
        check(DebindPrivate.Switches["$a"].resetValue == true, "the overwritten row stayed");
        local record = DebindPrivate.GetArrivalRecord(arrivalID);
        check(not (record.resolved and record.resolved["$a"]), "the answered mark stayed");
    end);

    return T;
end
