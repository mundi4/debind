-- **The specialization index condition, from the profile to the key.**
--
-- It is the one condition nothing downstream can see. Every other one rides the record into the
-- restricted environment, so `record_spec` and `eval_spec` can ask what the snippet decided; this
-- one is answered on the insecure side and the binding it turns down is simply not in the key map
-- (`Debind.lua`'s `BuildKeyMap`). So the only place it is visible at all is the list a key comes
-- out with, which is what every case here reads.
--
-- **Which is also why the change of specialization is a case.** The condition is measured once per
-- rebuild and never again, so a rebuild that does not happen is a key left answering for the
-- specialization the reader has left.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local bor = bit.bor;

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

    local ME = "Player-1-SPECCOND";

    local function Flag(index)
        return Constants.SpecIndexFlag(index);
    end

    --- Which specialization the world is in. The shim answers 1, and every case here says so
    --- itself rather than leaning on that.
    local function SetSpec(spec)
        _G.C_SpecializationInfo.GetSpecialization = function() return spec; end
    end

    local function Bind(actions, spec)
        _G.UnitGUID = function() return ME; end
        SetSpec(spec or 1);
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    --- The first action `Bind` put in General, as it is stored.
    local function FirstStoredAction()
        local layer = DebindPrivate.GetProfileLayer(DebindPrivate.GetLayerID(nil, false));
        check(layer, "there is no General layer");
        for _, action in layer:Enumerate() do
            return action;
        end
    end

    --- The values on the key, in order, or `<none>` where the key came out with no records.
    local function Values(key)
        local records = DebindPrivate.KeyMap[key];
        if (not records) then return "<none>"; end
        local out = {};
        for i = 1, #records do out[i] = tostring(records[i].value); end
        return table.concat(out, " ");
    end

    ---------------------------------------------------------------------------
    -- The set, against the index the character is on
    ---------------------------------------------------------------------------

    test("an index in the set reaches the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = bor(Flag(1), Flag(3)) } },
        }, 1);

        check(Values("F1") == "585", "the key came out with " .. Values("F1"));
    end);

    test("an index outside the set keeps the action off the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = bor(Flag(2), Flag(3)) } },
        }, 1);

        check(Values("F1") == "<none>", "the key came out with " .. Values("F1"));
    end);

    -- **Off the key is also greyed in the window.** `ActiveActions` is what `IsInactiveAction`
    -- reads, and an action that reaches nothing has to read as one, the same treatment a
    -- keyless action already gets. Left set, the row would draw as live while the key ignores it.
    test("an action the specialization rules out is drawn as inactive", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = Flag(2) } },
        }, 1);

        local stored = FirstStoredAction();
        check(stored, "the action is not in the layer");
        check(DebindPrivate.IsInactiveAction(stored), "it is still counted as active");
    end);

    -- **The fifth index is the initial specialization**, which every class has and none names. It
    -- is out of range for the two specialization layers (`EnumerateProfileLayers` drops those),
    -- so a condition that could not answer for it would leave those characters with an axis the
    -- rest of the addon still offers them.
    test("the fifth index answers like any other", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = Flag(5) } },
            { type = Constants.SPELL, value = 774, key = "F2", seq = 1,
                conditions = { specs = Flag(1) } },
        }, 5);

        check(Values("F1") == "585", "the fifth index did not reach the key: " .. Values("F1"));
        check(Values("F2") == "<none>", "F2 came out with " .. Values("F2"));
    end);

    test("an action with no specialization condition is untouched by the index", function()
        Bind({ { type = Constants.SPELL, value = 585, key = "F1", seq = 1 } }, 3);

        check(Values("F1") == "585", "the key came out with " .. Values("F1"));
    end);

    -- **An empty set is a set nothing satisfies**, and it is reported rather than left silent:
    -- the three mask conditions beside this one all raise on a zero, and a reader who unticked
    -- the last box otherwise has a key that stopped working and nothing saying why.
    test("an empty set is reported and reaches no key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = 0 } },
        }, 1);

        local stored = FirstStoredAction();
        check(DebindPrivate.GetBindingIssue(stored, "specs")
            == Constants.BINDING_ISSUE_SPECS_NONE_SELECTED, "the empty set was not reported");
        check(Values("F1") == "<none>", "the key came out with " .. Values("F1"));

        -- **And it stays active, unlike the test above.** The two look alike on the key and are
        -- opposite in the window. Another specialization's action is inactive because there is
        -- nothing to fix -- it works when that specialization comes round -- while this one is
        -- work waiting, and the row is where the reader goes to do it.
        --
        -- What reads this is the key heading (`DebindUI.lua`), which asks only active rows
        -- whether any of them is broken. Filtered out here, the heading draws plain over a dead
        -- key while the row under it shows the error, and the two say different things.
        check(not DebindPrivate.IsInactiveAction(stored),
            "the empty set was filtered out as if it belonged to another specialization");
    end);

    -- **A specialization that is not known yet takes the conditioned action out, not in.**
    -- `CanBuildBindings` refuses to build at all in that window, so what this pins is the answer
    -- for a caller that builds the key map on its own: the safe direction is the key that fires
    -- nothing rather than the key that fires the wrong thing until the window shuts.
    test("an unknown index keeps a conditioned action off the key and leaves the rest alone", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = Constants.SPEC_ALL } },
            { type = Constants.SPELL, value = 774, key = "F2", seq = 1 },
        }, 1);

        SetSpec(nil);
        DebindPrivate.BuildKeyMap();

        check(Values("F1") == "<none>", "F1 came out with " .. Values("F1"));
        check(Values("F2") == "774", "F2 came out with " .. Values("F2"));
    end);

    ---------------------------------------------------------------------------
    -- Changing specialization
    ---------------------------------------------------------------------------

    -- **The condition is only ever as fresh as the last rebuild.** Nothing measures it again
    -- between two of them, so the event that follows the change is the whole of what keeps the key
    -- honest. The two actions sit on one key so that the change is a key changing hands rather
    -- than a key going quiet, which is the case that would still pass with the second action
    -- dropped for some other reason.
    test("a specialization change rebuilds and the key changes hands", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = Flag(1) } },
            { type = Constants.SPELL, value = 774, key = "F1", seq = 2,
                conditions = { specs = Flag(2) } },
        }, 1);

        -- Both live in `DebindUI.lua`, which is not on the headless load list (`run.lua`), and
        -- the login's last lines call them.
        DebindPrivate.ShowMigrationDialogIfPending =
            DebindPrivate.ShowMigrationDialogIfPending or function() end;
        check(frames.fireEvent("PLAYER_LOGIN") > 0, "nothing is listening for PLAYER_LOGIN");

        check(Values("F1") == "585", "before the change the key held " .. Values("F1"));

        SetSpec(2);
        check(frames.fireEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED") > 0,
            "nobody is listening for the specialization change");

        check(Values("F1") == "774", "after the change the key held " .. Values("F1"));
    end);

    ---------------------------------------------------------------------------
    -- Where the condition goes with the action
    ---------------------------------------------------------------------------

    -- **Converting to macro text does not put the condition in the body.** A body has nowhere to
    -- write it that this addon would read back, so the condition stays where every other one
    -- stays, on the action, and the converted action is filtered by the same line. Dropped in
    -- the conversion, the key would start firing in every specialization and the row would go on
    -- drawing the condition it no longer has.
    test("converting to macro text keeps the condition and the filter still holds", function()
        shim.world.spells[585] = { name = "Consecration", iconID = 135926 };
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = Flag(2) } },
        }, 1);

        local stored = FirstStoredAction();
        check(DebindPrivate.ConvertToMacroText(stored), "the conversion declined");
        check(stored.type == Constants.MACROTEXT, "it is still a " .. tostring(stored.type));
        check(stored.conditions.specs == Flag(2),
            "the condition came out as " .. tostring(stored.conditions and stored.conditions.specs));

        DebindPrivate.BuildKeyMap();
        check(Values("F1") == "<none>", "the converted action reached the key: " .. Values("F1"));
    end);

    ---------------------------------------------------------------------------
    -- What the overview's list makes of it
    ---------------------------------------------------------------------------

    -- **Marked like an off-spec layer row, and moved not at all.** The two halves are one case
    -- because the second is what a fold into `specRank` would have cost: that field is a step of
    -- the comparator, and this action is in a layer that is live, so pushing it behind the active
    -- rows would make the list say it stands somewhere it does not.
    --
    -- **Both rows carry a condition** so that the step above `specRank` cannot be what orders
    -- them. With one of them unconditional, `isConditional` settles it first and the row would
    -- come out in front whether or not anything below that step ran.
    test("a row the condition leaves out is off-spec and keeps its place", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = Flag(2) } },
            { type = Constants.SPELL, value = 774, key = "F1", seq = 2,
                conditions = { combat = true } },
        }, 1);

        local rows = DebindPrivate.CollectActionsForKey("F1");
        check(#rows == 2, "row count " .. #rows);
        check(rows[1].action.value == 585,
            "the excluded row moved, and it is in a live layer: " .. tostring(rows[1].action.value));
        check((rows[1].specRank or 0) == 0, "it was given a specRank, which the comparator reads");
        check(DebindPrivate.IsRowOffSpec(rows[1]), "it is not marked off-spec");
        -- **Marked and still in the order**, which is the pair of answers this row needs. The flag
        -- is about the words on it; `seq` is still what settles it against the row below, so it is
        -- that row's arrow neighbour (the swap case below).
        check(DebindPrivate.IsRowInOrder(rows[1]), "it was taken out of the key's order as well");
        check(not DebindPrivate.IsRowOffSpec(rows[2]), "the row beside it was marked too");
    end);

    test("a row whose set holds this index is an ordinary row", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = bor(Flag(1), Flag(2)) } },
        }, 1);

        local rows = DebindPrivate.CollectActionsForKey("F1");
        check(not DebindPrivate.IsRowOffSpec(rows[1]), "a set holding this index was marked");
        check(DebindPrivate.IsRowInOrder(rows[1]), "it was taken out of the order");
    end);

    -- **The window can ask for another specialization's order**, and the answer has to be about
    -- that one. Asked with the index the character happens to be on, this would mark the rows of
    -- the very specialization whose tab the reader opened, and leave the ones that do run there
    -- looking like the live ones.
    test("another specialization's order marks what that world leaves out", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = Flag(1) } },
            { type = Constants.SPELL, value = 774, key = "F1", seq = 2,
                conditions = { specs = Flag(2) } },
        }, 1);

        local here = DebindPrivate.CollectActionsForKey("F1");
        check(not DebindPrivate.IsRowOffSpec(here[1]), "the row for this index was marked");
        check(DebindPrivate.IsRowOffSpec(here[2]), "the row for the other index was not marked");

        local there = DebindPrivate.CollectActionsForKey("F1", 2);
        check(DebindPrivate.IsRowOffSpec(there[1]),
            "asked about index 2, the row for index 1 was not marked");
        check(not DebindPrivate.IsRowOffSpec(there[2]),
            "asked about index 2, the row for index 2 was marked");
    end);

    -- **The arrows still promise one place, and this row is one place.** `seq` is a single number
    -- space shared by every specialization on the key, and this row stands in it: the row above it
    -- and the row below it are ordered against it by `seq` alone. So it is the neighbour an arrow
    -- swaps with. Skipping over it would move the pressed row two places on screen and settle the
    -- pair either side of it, which is a gesture that says one thing and does another.
    test("an arrow swaps with the row beside it, one this specialization leaves out included",
        function()
            Bind({
                { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                    conditions = { combat = true } },
                { type = Constants.SPELL, value = 774, key = "F1", seq = 2,
                    conditions = { specs = Flag(2) } },
                { type = Constants.SPELL, value = 116, key = "F1", seq = 3,
                    conditions = { stealth = true } },
            }, 1);

            local rows = DebindPrivate.CollectActionsForKey("F1");
            check(#rows == 3, "row count " .. #rows);
            check(rows[2].action.value == 774, "the excluded row is not in the middle");

            local neighbor, reason = DebindPrivate.ComputeOrderSwap(rows, 3, -1);
            check(neighbor == rows[2], "the arrow reached past it to "
                .. tostring(neighbor and neighbor.action.value) .. " (" .. tostring(reason) .. ")");
        end);

    -- **An empty set is nobody's specialization.** No index satisfies it, so calling the row
    -- "inactive specialization" sends the reader off to change specialization, which can never
    -- help. It is a mistake, the row already has a word for it, and that word has to be the one
    -- that survives: the flag would take the slot the problem code prints in, and the filter would
    -- file the row under a specialization that is not this one and hide it with the rest.
    test("an empty set is a mistake rather than another specialization", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { specs = 0 } },
        }, 1);

        local rows = DebindPrivate.CollectActionsForKey("F1");
        check(not DebindPrivate.IsRowOffSpec(rows[1]), "the empty set was filed as another spec");
        check(rows[1].issue == Constants.BINDING_ISSUE_SPECS_NONE_SELECTED,
            "the row's problem is " .. tostring(rows[1].issue));
    end);

    return T;
end
