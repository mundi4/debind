-- Renumbering a key group's ordering numbers. `devdocs/legacy/renumbering-a-key-group.md` is the spec.
--
-- **What this measures is where an action stands after it crosses a band.** The five steps above
-- `seq` in `CompareActionOrder` (importance, hover, conditions, layer, specialization) are what that
-- document calls a band. Turning a condition on sends the action into another band, and while the
-- number it carries is a history unrelated to that band it landed **at the front, in the middle or
-- at the back** -- one gesture with three outcomes, and nothing on screen saying which.
--
-- Renumbering is what puts the premise under it. Once the number is "where this stands in its group
-- right now", the bands divide the range in order, so a number carried in can only be outside the
-- destination's range and the landing is fixed at the **end facing where it came from**.

return function(DebindPrivate)
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
            error(msg or "assertion failed", 2);
        end
    end

    local Constants = DebindPrivate.Constants;
    local CLASS = Constants.PLAYER_CLASS;
    local GUID = "Player-1-TESTGUID";

    -- The same premise keygroup_spec runs on: a druid (four specs), specialization 1 active.
    check(CLASS == "DRUID", "druid assumed, got " .. tostring(CLASS));

    local function ResetProfile(layout)
        layout = layout or {};
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = layout.general or {}, classes = { [CLASS] = layout.class or {} } },
            characters = { [GUID] = { layers = layout.char or {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    --- An action with a condition on it. `combat` touches only the band's `conditions` step -- hover
    --- is an independent step above it, and mixing the two blurs what split the band.
    local function Cond(value, key, seq)
        return { type = Constants.SPELL, value = value, key = key, seq = seq, combat = true };
    end

    local function Plain(value, key, seq)
        return { type = Constants.SPELL, value = value, key = key, seq = seq };
    end

    --- The firing order on one line, so a failure shows the order rather than describing it.
    local function Order(key)
        local out = {};
        for i, row in ipairs(DebindPrivate.CollectActionsForKey(key)) do
            out[i] = tostring(row.action.value);
        end
        return table.concat(out, " ");
    end

    --- The group's numbers in order. Anything but `1 2 3 ...` means the renumber did not run, or ran
    --- over something other than the drawn order.
    local function Seqs(key)
        local out = {};
        for i, row in ipairs(DebindPrivate.CollectActionsForKey(key)) do
            out[i] = tostring(row.action.seq);
        end
        return table.concat(out, " ");
    end

    local function Find(key, value)
        for _, row in ipairs(DebindPrivate.CollectActionsForKey(key)) do
            if (row.action.value == value) then
                return row.action;
            end
        end
    end

    --- Turning one condition on or off in the game. **Writing the value and renumbering that key
    --- group is the whole of it**, and those two are what `DropDownMenus.lua`'s
    --- `onActionValueChanged` does.
    local function Edit(action, field, value)
        action[field] = value;
        DebindPrivate.RenumberKeyGroupForAction(action);
    end

    --- One key holding two bands, with the numbers **deliberately planted out of step**.
    ---
    --- The conditional band holds 10, 20 and 30 while the unconditional one holds 2, 25 and 99. Turn
    --- a condition on for one of the unconditional three and its number falls in front of the 10-30
    --- range, inside it, or behind it -- values picked so all three outcomes are reachable. Had the
    --- numbers lined up with the drawn order, this file would measure nothing.
    ---
    --- **The stored array's order is out of step with the drawn order too.** Renumbering in array
    --- order would turn that mismatch into the firing order, and what has to be numbered is what is
    --- drawn.
    local function TwoBands()
        ResetProfile({
            general = {
                Plain(23, "F", 99),
                Cond(11, "F", 10),
                Plain(22, "F", 25),
                Cond(13, "F", 30),
                Plain(21, "F", 2),
                Cond(12, "F", 20),
            },
        });
        check(Order("F") == "11 12 13 21 22 23", "planted order: " .. Order("F"));
    end

    --- Sends **one edit through** ahead of the numbers that are out of step.
    ---
    --- The invariant stands by induction: if the numbers lined up with the drawn order before an
    --- edit, they line up after it. Numbers out of step from an older profile are outside that
    --- induction, and the first edit reaching the group is what brings them inside it. Every toggle
    --- below is the edit **after** that one.
    ---
    --- This priming edit crosses no band itself (one more condition on an action that already has
    --- one), so nothing moves and only the numbers are tidied -- which the first test below stands
    --- up on its own.
    local function Settle()
        Edit(Find("F", 12), "stealth", true);
    end

    ---------------------------------------------------------------------------
    -- An edit inside one band moves nothing
    ---------------------------------------------------------------------------

    -- Refining conditions is most of what editing is, and losing the place every time is not on.
    -- `isConditional` is derived, so one more condition on an action that already has one leaves the
    -- band where it was.
    test("an edit that crosses no band moves nothing", function()
        TwoBands();

        Edit(Find("F", 12), "stealth", true);

        check(Order("F") == "11 12 13 21 22 23", "order moved: " .. Order("F"));
    end);

    -- What the renumber numbers is **the drawn order**. Numbering in array order would pass the test
    -- above -- nothing moves on the first pass either way -- and split the order from the next edit
    -- onwards.
    test("renumbering hands out 1..n in the drawn order", function()
        TwoBands();

        Edit(Find("F", 12), "stealth", true);

        check(Seqs("F") == "1 2 3 4 5 6", "numbers: " .. Seqs("F"));
    end);

    ---------------------------------------------------------------------------
    -- Crossing a band lands at the end facing where it came from
    ---------------------------------------------------------------------------

    --- Whether the action whose condition was turned on stands at the **back** of the conditional
    --- band. That band is the earlier one, so a number arriving from behind it is larger than
    --- everything in its range, which is the back.
    local function ExpectBackOfConditionalBand(value, expected)
        TwoBands();
        Settle();

        Edit(Find("F", value), "combat", true);

        check(Order("F") == expected, "order: " .. Order("F"));
    end

    -- **All three land in the same place.** Without renumbering these three were exactly the front,
    -- the middle and the back: 21 holds 2 and so came before the whole conditional band (10-30), 22
    -- holds 25 and landed between 20 and 30, 23 holds 99 and landed behind. One gesture with three
    -- outcomes, and nothing on screen said which.
    test("turning a condition on lands at the back of the conditional band -- the one that went first", function()
        ExpectBackOfConditionalBand(21, "11 12 13 21 22 23");
    end);

    test("turning a condition on lands at the back of the conditional band -- the one that went middle", function()
        ExpectBackOfConditionalBand(22, "11 12 13 22 21 23");
    end);

    test("turning a condition on lands at the back of the conditional band -- the one that went last", function()
        ExpectBackOfConditionalBand(23, "11 12 13 23 21 22");
    end);

    -- The other direction. The unconditional band is the later one, so a number arriving from in
    -- front is smaller than everything in its range and lands at the **front**. Leaving is "the near
    -- front" and returning is "the near back", so toggling off and on does not put the action back
    -- where it was -- an unavoidable cost of renumbering at all, which the document argues out
    -- under "복구 불가는 구조적이다".
    test("turning a condition off lands at the front of the unconditional band", function()
        TwoBands();
        Settle();

        Edit(Find("F", 11), "combat", nil);

        check(Order("F") == "12 13 11 21 22 23", "order: " .. Order("F"));
    end);

    ---------------------------------------------------------------------------
    -- Leaving a group and coming back
    ---------------------------------------------------------------------------

    -- **The number goes with the key.** It means "which of this key's actions goes first", so with
    -- no key there is no place for it to be, and leaving it there leaves not a place but **a number
    -- from somewhere**. The remaining group closes to 1..n -- nothing walks out holding a number, so
    -- there is nothing to collide with.
    test("taking the key away drops the number and closes the group", function()
        ResetProfile({
            general = { Plain(11, "F", 1), Plain(12, "F", 2), Plain(13, "F", 3) },
        });

        local leaving = Find("F", 12);
        DebindPrivate.ClearActionKey(leaving);

        check(leaving.seq == nil, "number kept: " .. tostring(leaving.seq));
        check(Seqs("F") == "1 2", "remaining group: " .. Seqs("F"));
    end);

    -- **Giving the key back is an arrival.** Letting it resume its place would leave the window
    -- answering two round trips differently -- toggling a condition off and on does not come back
    -- (structurally, as long as renumbering runs) while unbinding and rebinding would. And a reader
    -- rebinding days later does not know the action was ever on this key.
    test("rebinding the same key lands at the back", function()
        ResetProfile({
            general = { Plain(11, "F", 1), Plain(12, "F", 2), Plain(13, "F", 3) },
        });

        local action = Find("F", 12);
        DebindPrivate.ClearActionKey(action);

        action.key = "F";
        DebindPrivate.PlaceActionInKeyGroup(action);

        check(Order("F") == "11 13 12", "order: " .. Order("F"));
        check(Seqs("F") == "1 2 3", "numbers: " .. Seqs("F"));
    end);

    -- **Binding a different key gives the same answer.** The number carried used to point into the
    -- middle of the destination group, so walking into a group of eight holding a 5 landed fifth --
    -- the symptom this document exists to remove, surviving on this one path.
    test("binding a different key lands at the back of that band", function()
        ResetProfile({
            general = {
                Plain(11, "F", 1), Plain(12, "F", 2), Plain(13, "F", 3),
                Plain(21, "G", 1), Plain(22, "G", 2), Plain(23, "G", 3), Plain(24, "G", 4),
            },
        });

        local wanderer = Find("F", 13);
        DebindPrivate.ClearActionKey(wanderer);
        wanderer.key = "G";
        DebindPrivate.PlaceActionInKeyGroup(wanderer);

        check(Order("G") == "21 22 23 24 13", "order: " .. Order("G"));
    end);

    -- An action being given a key for the first time goes through the same place. A newly bound key
    -- always starting behind what was already there is why `seq` exists (`SetActionKey`).
    test("a first key lands at the back of that band", function()
        ResetProfile({
            general = { Cond(11, "F", 1), Cond(12, "F", 2), Plain(21, "F", 3) },
        });

        local fresh = { type = Constants.SPELL, value = 14, combat = true };
        DebindPrivate.GetProfileLayer(1):Insert(fresh);
        fresh.key = "F";
        DebindPrivate.PlaceActionInKeyGroup(fresh);

        -- The back of the conditional band, which is in front of the unconditional 21.
        check(Order("F") == "11 12 14 21", "order: " .. Order("F"));
    end);

    ---------------------------------------------------------------------------
    -- The arrows, deleting, and moving between layers
    ---------------------------------------------------------------------------

    --- What `ApplyOrderSwap` does with the redraw taken out. That function lives in `DebindUI.lua`
    --- and cannot be called from here; these two lines are all of it that can. The real button is
    --- pressed by `/debtest`.
    local function Swap(a, b)
        a.seq, b.seq = b.seq, a.seq;
        DebindPrivate.RenumberKeyGroupForAction(a);
    end

    test("the arrows move exactly one step and a round trip comes back", function()
        ResetProfile({
            general = { Plain(11, "F", 1), Plain(12, "F", 2), Plain(13, "F", 3) },
        });

        Swap(Find("F", 12), Find("F", 11));
        check(Order("F") == "12 11 13", "one step up: " .. Order("F"));

        Swap(Find("F", 12), Find("F", 11));
        check(Order("F") == "11 12 13", "and back down: " .. Order("F"));
        check(Seqs("F") == "1 2 3", "numbers: " .. Seqs("F"));
    end);

    -- A deleted action has no number to walk out with, which is why deleting closes the group up.
    test("deleting closes the group to 1..n", function()
        ResetProfile({
            general = { Plain(11, "F", 1), Plain(12, "F", 2), Plain(13, "F", 3) },
        });

        local layer = DebindPrivate.GetProfileLayer(1);
        layer:Remove(Find("F", 12));
        layer:RenumberKeyGroup("F");

        check(Order("F") == "11 13", "order: " .. Order("F"));
        check(Seqs("F") == "1 2", "numbers: " .. Seqs("F"));
    end);

    -- The path moving and copying between layers goes through. The number carried belongs to the
    -- other group, so it is dropped and the action stands at the back of its band in the group it
    -- landed in.
    test("arriving in another layer lands at the back of that band", function()
        ResetProfile({
            general = { Cond(11, "F", 1) },
            class = { [0] = { Cond(51, "F", 1), Cond(52, "F", 2), Plain(61, "F", 3) } },
        });

        -- Move 11 out of the general layer into class/shared. It arrives holding that layer's 1.
        local moving = Find("F", 11);
        DebindPrivate.GetProfileLayer(1):Remove(moving);
        local destLayer = DebindPrivate.GetProfileLayer(2);
        destLayer:Insert(moving);
        destLayer:PlaceInKeyGroup(moving);

        -- Keeping the 1 it came with would have put it in front of 51.
        check(Order("F") == "51 52 11 61", "order: " .. Order("F"));
        check(Seqs("F") == "1 2 3 4", "numbers: " .. Seqs("F"));
    end);

    -- **Arriving with no key means arriving with no number.** A number is a place among the actions
    -- sharing a key, so one held while there is no key is a place in some group this action is not
    -- in. Everything that reads `seq` now reads it unguarded (`MakeRow`, `SetKeyForActions`), and
    -- this line is what makes that safe.
    test("arriving with no key drops the number carried", function()
        ResetProfile({ general = {} });

        -- A keyless action that came from another layer holding a 5.
        local arriving = { type = Constants.SPELL, value = 71, seq = 5 };
        local layer = DebindPrivate.GetProfileLayer(1);
        layer:Insert(arriving);
        layer:PlaceInKeyGroup(arriving);

        check(arriving.seq == nil, "number kept: " .. tostring(arriving.seq));
    end);

    ---------------------------------------------------------------------------
    -- How far a renumber reaches
    ---------------------------------------------------------------------------

    -- The number is read inside one (layer, key) and nowhere wider, so the renumber stops there too.
    -- Walking the layer's other keys would drag the places a reader set on those keys along with an
    -- edit that had nothing to do with them.
    test("another key in the same layer is left alone", function()
        ResetProfile({
            general = {
                Cond(11, "F", 10),
                Plain(21, "F", 2),
                Plain(31, "G", 7),
                Plain(32, "G", 9),
            },
        });

        Edit(Find("F", 21), "combat", true);

        check(Seqs("G") == "7 9", "G's numbers changed: " .. Seqs("G"));
    end);

    -- **The answer must not hang on `sort`'s internals.** With several ties `table.sort` scatters the
    -- equals wholesale -- invisible on the three-element groups above, visible at around eight. The
    -- renumber's answer is stored immediately, so one scatter sticks and the next pass scatters
    -- differently.
    --
    -- Only a hand-edited file gets this far. **The numbers are planted after loading** -- `InitDB`
    -- ends in `CleanUpDB` and its net splits duplicates inside a group first.
    test("several ties are ordered by array position", function()
        ResetProfile({
            general = {
                Plain(1, "F", 1), Plain(2, "F", 2), Plain(3, "F", 3), Plain(4, "F", 4),
                Plain(5, "F", 5), Plain(6, "F", 6), Plain(7, "F", 7), Plain(8, "F", 8),
            },
        });

        local layer = DebindPrivate.GetProfileLayer(1);
        for i = 1, 8 do
            layer:GetAction(i).seq = (i % 2 == 1) and 2 or 1;
        end

        layer:RenumberKeyGroup("F");

        -- The ones holding 1 first in array order, then the ones holding 2 in array order.
        check(Order("F") == "2 4 6 8 1 3 5 7", "order: " .. Order("F"));
    end);

    -- Every layer counts from 1 again. `seq` means something inside one layer only (the comparator
    -- splits on layerRank first), so numbers repeating across layers never meet.
    --
    -- **A band is wider than a layer.** The `conditions` step sits above the `layer` step, so the
    -- conditional band crosses layers (51 and 11 come together, then 61 and 21). Filtering that
    -- order down to one layer still leaves the relative order it had in the whole list, which is why
    -- a renumber running inside one layer still numbers by the drawn order.
    test("a key spanning layers counts from 1 in each", function()
        ResetProfile({
            general = { Cond(11, "F", 40), Plain(21, "F", 50) },
            class = { [0] = { Cond(51, "F", 60), Plain(61, "F", 70) } },
        });

        Edit(Find("F", 11), "stealth", true);
        Edit(Find("F", 51), "stealth", true);

        -- The conditional band (51, 11) comes first, and inside it class/shared outranks general.
        check(Order("F") == "51 11 61 21", "order: " .. Order("F"));
        check(Seqs("F") == "1 1 2 2", "numbers: " .. Seqs("F"));
    end);

    return T;
end
