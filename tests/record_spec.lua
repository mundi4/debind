-- Folding a binding's unit conditions, and the record that comes out of one.
--
-- **`"@"` is the reason this fold exists.** It names the action's own target, so a binding that
-- also carries an explicit condition on that same unit writes the same key twice -- and without a
-- fold, `pairs` order decides which of the two survives. A condition disappearing at random is
-- what that looks like from the outside.
--
-- The other half is `NEVER`: a fold that leaves nothing any state can satisfy. **Nothing should
-- reach it.** Every way it happens leaves a zero mask in `binding.unitStates`, `GetBindingIssue`
-- reports the zero, and `Debind.lua` keeps the binding out of `KeyMap` -- so it reaches neither
-- the solver nor the emitter. It is the backstop for those two intersections disagreeing, which is
-- two implementations of one rule, and it is the only thing that would notice.
--
-- Verified with a one-off script every time this was touched before, because the harness did not
-- read the file (`.zzz/refactor-candidates.md` 31).

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

    local HELP = Constants.REACTION_HELP;
    local HARM = Constants.REACTION_HARM;
    local OTHER = Constants.REACTION_OTHER;

    --- Folds one binding's unit conditions into a table of its own.
    local function fold(unit, units)
        return DebindPrivate.MergeKeyUnitConditions(
            { unit = unit, conditions = { units = units } }, {});
    end

    --- How many units the fold left.
    local function size(folded)
        local n = 0;
        for _ in pairs(folded) do n = n + 1; end
        return n;
    end

    ---------------------------------------------------------------------------
    -- "@" and the unit it names
    ---------------------------------------------------------------------------

    -- **The one this fold was written for.** Both conditions are about `target`, and both have to
    -- survive: dropping either is a restriction the reader set and cannot see gone.
    test("\"@\" merges with an explicit condition on the same unit", function()
        local folded = fold("target", {
            ["@"] = { reaction = HELP },
            target = { dead = false },
        });
        check(folded, "the fold refused a pair that can be satisfied");
        check(size(folded) == 1, "units left: " .. size(folded));
        check(folded.target.reaction == HELP, "the reaction was lost");
        check(folded.target.dead == false, "the life condition was lost");
    end);

    -- Narrower wins. Two reaction masks that overlap fold to the overlap, not to either one.
    test("two reaction masks fold to what they share", function()
        local folded = fold("target", {
            ["@"] = { reaction = HELP + OTHER },
            target = { reaction = HELP + HARM },
        });
        check(folded.target.reaction == HELP,
            "reaction: " .. tostring(folded.target.reaction));
    end);

    -- **A `"@"` on an action with no target is asked of `target`** (`Misc.lua`'s `ResolvedUnitOf`,
    -- `devdocs/implementing-focus-and-self-cast.md` §3-6). The record still carries no unit, so the
    -- game places the cast; only the condition lands on `target`, folding with one set there by name.
    test("\"@\" with no target lands on target and folds with it", function()
        for _, unit in ipairs({ false, "" }) do
            local folded = fold(unit or nil, {
                ["@"] = { reaction = HELP },
                target = { dead = false },
                focus = { reaction = HARM },
            });
            local label = "unit=" .. tostring(unit or nil) .. ": ";
            check(folded, label .. "the fold refused a pair that can be satisfied");
            check(size(folded) == 2, label .. "units left: " .. size(folded));
            check(folded.target.reaction == HELP, label .. "the resolved target's reaction was lost");
            check(folded.target.dead == false, label .. "the target's own condition was lost");
            check(folded.focus.reaction == HARM, label .. "the focus condition went with it");
        end
    end);

    -- A `unit` that is not a string at all is the one place left with nowhere to put `"@"`. The fold
    -- drops it quietly rather than inventing a unit; `BuildUnitStates` has already made the binding
    -- opaque.
    test("\"@\" on a unit that is not a string is dropped and nothing else is", function()
        local folded = fold(42, {
            ["@"] = { reaction = HELP },
            focus = { reaction = HARM },
        });
        check(folded, "the fold refused a binding whose only fault was a stray @");
        check(size(folded) == 1, "units left: " .. size(folded));
        check(folded.focus.reaction == HARM, "the focus condition went with it");
    end);

    -- Two units are two entries. Nothing folds across units.
    test("conditions on different units stay apart", function()
        local folded = fold("target", {
            ["@"] = { reaction = HELP },
            focus = { dead = true },
        });
        check(size(folded) == 2, "units left: " .. size(folded));
        check(folded.target.reaction == HELP, "the target condition is missing");
        check(folded.focus.dead == true, "the focus condition is missing");
    end);

    -- A binding with no unit conditions folds to nothing, which is **not** the same answer as a
    -- fold that failed. The caller emits the first and skips the second.
    test("no unit conditions is an empty fold, not a refusal", function()
        local folded = DebindPrivate.MergeKeyUnitConditions(
            { unit = "target", conditions = {} }, {});
        check(folded ~= nil, "an unconditional binding was refused");
        check(size(folded) == 0, "units left: " .. size(folded));
    end);

    ---------------------------------------------------------------------------
    -- Folds that leave nothing
    ---------------------------------------------------------------------------

    -- Reactions with nothing in common. There is no unit that is both only friendly and only
    -- hostile, so the binding can never fire.
    test("reactions that do not overlap leave nothing", function()
        check(fold("target", {
            ["@"] = { reaction = HELP },
            target = { reaction = HARM },
        }) == nil, "a contradiction folded to something");
    end);

    -- Alive and dead at once.
    test("life asked both ways leaves nothing", function()
        check(fold("target", {
            ["@"] = { dead = true },
            target = { dead = false },
        }) == nil, "a contradiction folded to something");
    end);

    -- **`false` is "this unit is absent", and the absent point sits on no axis.** So it cannot
    -- meet a condition that constrains one.
    test("absent and constrained leave nothing", function()
        check(fold("target", {
            ["@"] = false,
            target = { reaction = HELP },
        }) == nil, "absent folded with a reaction condition");
    end);

    -- **But two conditions that both say absent agree**, and that has to come back as `false`.
    -- Written out rather than with `and false or`, which cannot return `false` -- the idiom
    -- answered "never" for the one case it was there to let through, and the binding was dropped
    -- with no issue reported anywhere.
    test("both saying absent folds to absent", function()
        local folded = fold("target", { ["@"] = false, target = false });
        check(folded, "two units both said absent and the fold refused them");
        check(folded.target == false, "target: " .. tostring(folded.target));
    end);

    ---------------------------------------------------------------------------
    -- The record
    ---------------------------------------------------------------------------

    --- The value a record would emit under one name, and whether it names it at all.
    local function fieldOf(record, name)
        for i = 1, record.fieldCount do
            if (record.fieldNames[i] == name) then
                return record.fieldValues[i], true;
            end
        end
        return nil, false;
    end

    local function recordFor(binding, isClickCast, holdsKey, alwaysOurs, clickTime)
        binding.conditions = binding.conditions or {};
        return DebindPrivate.BuildKeyRecord(binding, isClickCast, holdsKey,
            alwaysOurs, clickTime,
            { fieldNames = {}, fieldValues = {}, fieldCount = 0, units = {}, switches = {} });
    end

    --- The spells the `known` tests below read, **stood up before the first record is built.**
    --- `Spells` builds its table once per specialization, so the first record to carry a
    --- `known` condition is what settles the table for the rest of the file.
    ---
    --- `levelLearned` is the level the book dates the spell at, against a character the shim puts
    --- at 80; `knownSpells` is what `[known:]` itself answers.
    for spellID, spell in pairs({
        [1000] = { levelLearned = 10, known = true },
        [1001] = { levelLearned = 10, known = false },
        [1002] = { levelLearned = 90, known = false },
    }) do
        shim.world.spellbook[spellID] = true;
        shim.world.spells[spellID] = { name = "Spell " .. spellID,
            levelLearned = spell.levelLearned };
        shim.world.knownSpells[spellID] = spell.known or nil;
    end

    -- A binding whose units fold to nothing gets **no record at all**, rather than one marked
    -- unreachable. Carrying it would cost three times over: the match loop walks and rejects it on
    -- every re-selection, its units get registered so the poll prices them every tick, and every
    -- ordinary condition pays whatever lookup the marker needs.
    test("a binding that can never fire yields no record", function()
        local record = recordFor({
            type = Constants.SPELL, value = 585, unit = "target",
            clickframe = true, clickbutton = "deb1",
            conditions = { units = { ["@"] = { reaction = HELP }, target = { reaction = HARM } } },
        }, false, true, false, true);
        check(record == nil, "a binding that can never fire got a record");
    end);

    -- **`clickframe` goes out only where the state loop will need it.** It is read when that loop
    -- hands the key to `SetBindingClick`, and a key whose wiring is fixed never enters the loop.
    test("clickframe is carried only for a key the state loop wires", function()
        local function frameField(alwaysOurs)
            local record = recordFor({
                type = Constants.SPELL, value = 585, unit = "target",
                clickframe = true, clickbutton = "deb1",
                clickframeName = "DebindClickButton_target",
            }, false, true, alwaysOurs, true);
            local value, named = fieldOf(record, "clickframe");
            return value, named;
        end

        local value, named = frameField(false);
        check(named and value == "DebindClickButton_target", "wired key: " .. tostring(value));

        local _, fixedNamed = frameField(true);
        check(not fixedNamed, "a key with fixed wiring carried a clickframe");
    end);

    -- **Press and hold rides the key branch only.** A click-cast record arrives through
    -- `delegate:Click(button)`, which carries no edge, so the wrapper's `if (down)` branch never
    -- runs and there is nowhere to read it -- and turning it on anyway makes the gate force
    -- `useOnKeyDown`, which sends the release of a spell nobody pressed.
    test("press and hold is carried on the key branch and not the click-cast one", function()
        local binding = {
            type = Constants.SPELL, value = 271466, unit = "hover", hover = true,
            clickframe = true, clickbutton = "deb1", pressAndHold = true,
        };

        local held = recordFor(binding, false, true, false, true);
        check(fieldOf(held, "pressAndHold") == true, "the key branch did not carry it");

        local clickCast = recordFor(binding, true, false, false, true);
        local _, named = fieldOf(clickCast, "pressAndHold");
        check(not named, "the click-cast branch carried press and hold");
    end);

    -- A `known` condition bakes **the whole macro conditional, brackets and all**, naming the
    -- action's own value. The click path hands that string straight to `SecureCmdOptionParse` and
    -- the poll uses the same string as a key in `States`; splitting it would either join it on
    -- every click or write the same fact down twice.
    test("a known condition bakes the conditional it will be parsed as", function()
        local record = recordFor({
            type = Constants.SPELL, value = 8936,
            clickframe = true, clickbutton = "deb1",
            conditions = { known = true },
        }, false, true, false, true);
        check(fieldOf(record, "known") == "[known:8936]",
            "known: " .. tostring(fieldOf(record, "known")));
    end);

    ---------------------------------------------------------------------------
    -- A `known` whose answer cannot move before the next rebuild
    ---------------------------------------------------------------------------

    -- The three branches of `devdocs/baking-the-known-condition.md` §5. The table says only that
    -- the answer is fixed; what it *is* gets measured here with the same string the snippet would
    -- have used, so the two cannot part.
    --
    -- **Fixed is the spellbook's answer and not the character's knowledge.** A spell the book
    -- dates at or below the character's level cannot be forgotten, so it is settled at the
    -- rebuild; one dated above it is still one level-up away from flipping and stays an axis.

    local function knownRecord(spellID)
        return recordFor({
            type = Constants.SPELL, value = spellID,
            clickframe = true, clickbutton = "deb1",
            conditions = { known = true },
        }, false, true, false, true);
    end

    test("a fixed known that holds carries no axis at all", function()
        local record = knownRecord(1000);
        check(record ~= nil, "the record was dropped");
        local value, named = fieldOf(record, "known");
        check(not named, "known was carried anyway: " .. tostring(value));
    end);

    test("a fixed known that does not hold drops the record", function()
        check(knownRecord(1001) == nil, "the record survived");
    end);

    test("a known the book dates above the character stays an axis", function()
        local record = knownRecord(1002);
        check(record ~= nil, "the record was dropped");
        check(fieldOf(record, "known") == "[known:Spell 1002]",
            "known: " .. tostring(fieldOf(record, "known")));
    end);

    -- A spell the book does not carry at all is the third case, and the test above at "a known
    -- condition bakes the conditional it will be parsed as" is it: 8936 is in no world here.

    -- The same three branches asked in a **name**, which is what the condition will store
    -- (`devdocs/making-known-a-spell-name.md` §3-2). The level that settles it comes off the
    -- walk's name index, and the answer is measured with the string that would be baked.
    -- **The condition's own value is the question.** A name is what it stores, and the action it
    -- sits on is not what it asks about any more: an action on the base spell can ask about the
    -- talent that replaces it (`devdocs/making-known-a-spell-name.md`).
    test("a known bakes the value it carries and not the action's spell", function()
        local record = recordFor({
            type = Constants.SPELL, value = 8936,
            clickframe = true, clickbutton = "deb1",
            conditions = { known = "Spell 1002" },
        }, false, true, false, true);
        check(fieldOf(record, "known") == "[known:Spell 1002]",
            "known: " .. tostring(fieldOf(record, "known")));
    end);

    test("the three branches answer the same when the known is asked by name", function()
        local Spells = DebindPrivate.Spells;
        check(Spells.SettleKnown("Spell 1000") == true,
            "holds: " .. tostring(Spells.SettleKnown("Spell 1000")));
        check(Spells.SettleKnown("Spell 1001") == false,
            "does not hold: " .. tostring(Spells.SettleKnown("Spell 1001")));
        check(Spells.SettleKnown("Spell 1002") == nil,
            "above the character's level, settled anyway: "
            .. tostring(Spells.SettleKnown("Spell 1002")));
    end);

    -- An axis set to "no restriction" is not carried. It would be a comparison that is always true
    -- on a path that runs at every press.
    test("an axis set to everything is not carried", function()
        local record = recordFor({
            type = Constants.SPELL, value = 585,
            clickframe = true, clickbutton = "deb1",
            conditions = { groups = Constants.GROUP_ALL, forms = Constants.FORM_ALL },
        }, false, true, false, true);
        local _, groups = fieldOf(record, "groups");
        local _, forms = fieldOf(record, "forms");
        check(not groups, "an unrestricted group condition was carried");
        check(not forms, "an unrestricted form condition was carried");
    end);

    return T;
end
