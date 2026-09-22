-- The action menu's reads and writes over a selection (`editing-many-actions-at-once.md`).
--
-- **One menu aims at `ctx.actions`, and a single row is a selection of one.** What is measured here is
-- that a press lands the same on every action picked: a radio holds for all or for none, a box goes
-- to one outcome decided from what is drawn, and a bit or a set moves only the item pressed while
-- each action keeps the rest of its own.
--
-- Which row the press came from is the in-game kit's. Here the setters are called the way the rows
-- call them.

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
    local ActionMenu = DebindPrivate.ActionMenu;
    local CLASS = Constants.PLAYER_CLASS;
    local GUID = "Player-1-TESTGUID";

    --- Actions in the General layer, in the stored shape: conditions live in `conditions`.
    local function ResetProfile(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [CLASS] = {} } },
            characters = { [GUID] = { layers = {} } },
            migrated = {},
        };
        DebindPrivate.InitDB();
        return actions;
    end

    local function Spell(value, fields)
        local action = { type = Constants.SPELL, value = value, key = "F" };
        for k, v in pairs(fields or {}) do
            if (Constants.IsConditionField(k)) then
                action.conditions = action.conditions or {};
                action.conditions[k] = v;
            else
                action[k] = v;
            end
        end
        return action;
    end

    local function Ctx(actions)
        return { actions = actions };
    end

    --- How many times the bindings were rebuilt while `fn` ran.
    local function CountRebuilds(fn)
        local original = DebindPrivate.UpdateBindings;
        local count = 0;
        DebindPrivate.UpdateBindings = function(...)
            count = count + 1;
            return original(...);
        end
        local ok, err = pcall(fn);
        DebindPrivate.UpdateBindings = original;
        if (not ok) then
            error(err, 0);
        end
        return count;
    end

    local function Cond(action, key)
        return action.conditions and action.conditions[key];
    end

    ---------------------------------------------------------------------------
    -- Radios and boxes
    ---------------------------------------------------------------------------

    test("a radio written over a mixed selection lands on every action, and rebuilds once", function()
        local actions = ResetProfile({
            Spell(1, { combat = true }), Spell(2, { combat = false }), Spell(3),
        });
        local data = { ctx = Ctx(actions), key = "combat", value = true };

        check(not ActionMenu.actionValueEquals(data), "a mixed selection lights the radio");
        local rebuilds = CountRebuilds(function()
            ActionMenu.setActionValue(data);
        end);
        for i, action in ipairs(actions) do
            check(Cond(action, "combat") == true, "action " .. i .. ": " .. tostring(Cond(action, "combat")));
        end
        check(ActionMenu.actionValueEquals(data), "every action holding it leaves the radio dark");
        check(rebuilds == 1, "rebuilds: " .. rebuilds);
    end);

    test("clearing a condition over a selection prunes each action's table", function()
        local actions = ResetProfile({ Spell(1, { combat = true }), Spell(2, { combat = false }) });

        ActionMenu.setActionValue({ ctx = Ctx(actions), key = "combat", value = nil });
        for i, action in ipairs(actions) do
            check(action.conditions == nil, "action " .. i .. " kept an empty conditions table");
        end
    end);

    test("a box over a mixed selection turns all on, then all off", function()
        local actions = ResetProfile({ Spell(1, { disabled = true }), Spell(2) });
        local data = { ctx = Ctx(actions), key = "disabled", value = ActionMenu.USE_CHECKED_VALUE };

        check(not ActionMenu.actionValueEquals(data), "a mixed selection draws the box on");
        ActionMenu.setActionValue(data);
        check(actions[1].disabled == true and actions[2].disabled == true,
            "first press: " .. tostring(actions[1].disabled) .. " " .. tostring(actions[2].disabled));
        ActionMenu.setActionValue(data);
        check(actions[1].disabled == false and actions[2].disabled == false,
            "second press: " .. tostring(actions[1].disabled) .. " " .. tostring(actions[2].disabled));
    end);

    test("a selection of one flips the box the way a single row always has", function()
        local actions = ResetProfile({ Spell(1, { disabled = true }) });
        local data = { ctx = Ctx(actions), key = "disabled", value = ActionMenu.USE_CHECKED_VALUE };

        check(ActionMenu.actionValueEquals(data), "the one action's box is on");
        ActionMenu.setActionValue(data);
        check(actions[1].disabled == false, "pressed: " .. tostring(actions[1].disabled));
    end);

    test("a bit box moves that bit on every action and leaves the other bits", function()
        local actions = ResetProfile({ Spell(1, { forms = 1 + 4 }), Spell(2, { forms = 2 }), Spell(3) });
        local data = { ctx = Ctx(actions), key = "forms", value = 4 };

        ActionMenu.actionHandlers.toggleBit(data);
        check(Cond(actions[1], "forms") == 5, "first: " .. tostring(Cond(actions[1], "forms")));
        check(Cond(actions[2], "forms") == 6, "second: " .. tostring(Cond(actions[2], "forms")));
        check(Cond(actions[3], "forms") == 4, "third: " .. tostring(Cond(actions[3], "forms")));
    end);

    ---------------------------------------------------------------------------
    -- Sets that are written by hand
    ---------------------------------------------------------------------------

    --- A class with at least two specializations, read from the catalog the menu reads.
    local function AClass()
        for _, class in ipairs(DebindPrivate.ClassSpecCatalog()) do
            if (#class.specs >= 2) then
                return class;
            end
        end
        error("no class with two specializations in the catalog");
    end

    -- **Off is what a mixed selection draws**, so one press takes every action to the same place.
    -- The action that already had the box on keeps whatever else it had picked.
    test("a specialization box goes to one outcome and keeps each action's other picks", function()
        local class = AClass();
        local picked, other = class.specs[1].index, class.specs[2].index;
        local pickedFlag = Constants.SpecIndexFlag(picked);
        local otherFlag = Constants.SpecIndexFlag(other);
        local actions = ResetProfile({
            Spell(1, { specs = { [class.id] = pickedFlag + otherFlag } }),
            -- A class shut out, so the box under it is off and the press turns it on.
            Spell(2, { specs = { [class.id] = 0 } }),
        });
        local ctx = Ctx(actions);

        check(not ActionMenu.SpecConditionHasIndex(ctx, class.id, picked),
            "a mixed selection draws the box on");
        ActionMenu.ToggleSpecConditionIndex(ctx, class.id, picked);
        check(ActionMenu.SpecConditionHasIndex(ctx, class.id, picked), "not every action took it");
        check(DebindPrivate.SpecSetHoldsIndex(Cond(actions[1], "specs"), class.id, other),
            "first lost its other pick");

        ActionMenu.ToggleSpecConditionIndex(ctx, class.id, picked);
        check(not ActionMenu.SpecConditionHasIndex(ctx, class.id, picked), "the pressed one stayed on");
        check(DebindPrivate.SpecSetHoldsIndex(Cond(actions[1], "specs"), class.id, other),
            "first, off: the other one went with it");
    end);

    test("a class box over a mixed selection puts the class whole on every action, then takes it off", function()
        local class = AClass();
        local actions = ResetProfile({
            Spell(1, { specs = { [class.id] = Constants.SpecIndexFlag(class.specs[1].index) } }),
            Spell(2),
        });
        local ctx = Ctx(actions);

        check(not ActionMenu.ClassSpecsAllPicked(ctx, class.id), "a class half picked draws the box on");
        ActionMenu.ToggleClassSpecs(ctx, class.id);
        for i, action in ipairs(actions) do
            check(DebindPrivate.SpecSetHoldsClass(Cond(action, "specs"), class.id), "on, action " .. i);
        end

        -- **Off takes the key out and leaves the table standing.** The class loses its mask rather
        -- than keeping a zero, and the condition itself stays for the issue to speak for.
        ActionMenu.ToggleClassSpecs(ctx, class.id);
        for i, action in ipairs(actions) do
            local specs = Cond(action, "specs");
            check(specs ~= nil, "off, action " .. i .. ": the condition went");
            check(specs[class.id] == nil,
                "off, action " .. i .. ": the mask stayed " .. tostring(specs[class.id]));
        end
    end);

    -- **One meaning, one shape.** A class whose every box the reader ticked by hand has to read as
    -- one ticked in a single press, or the class box draws off over a class that holds everything.
    test("a class ticked box by box reads as the whole class", function()
        local class = AClass();
        local actions = ResetProfile({ Spell(1) });
        local ctx = Ctx(actions);

        for i = 1, #class.specs do
            ActionMenu.ToggleSpecConditionIndex(ctx, class.id, class.specs[i].index);
        end

        local specs = Cond(actions[1], "specs");
        check(specs ~= nil, "the whole condition went");
        check(specs[class.id] == DebindPrivate.ClassSpecMask(class.id),
            "the mask came out " .. tostring(specs[class.id]));
        check(ActionMenu.ClassSpecsAllPicked(ctx, class.id), "the class box stayed off");
    end);

    -- **A condition left holding nothing stays and is reported.** Unticking the last box is not
    -- the same answer as never having set the axis: this key fires nowhere, and the row is where
    -- the reader is told so. Dropping the table would make the two indistinguishable, and every
    -- other mask axis on this menu keeps its zero for the same reason.
    test("a condition left holding nothing stays, and says so", function()
        local class = AClass();
        local actions = ResetProfile({
            Spell(1, { specs = { [class.id] = DebindPrivate.ClassSpecMask(class.id) } }),
        });
        local ctx = Ctx(actions);

        ActionMenu.ToggleClassSpecs(ctx, class.id);

        local specs = Cond(actions[1], "specs");
        check(specs ~= nil, "the condition went away");
        check(DebindPrivate.SpecSetIsEmpty(specs), "it left something behind");
        check(DebindPrivate.GetBindingIssue(actions[1], "specs")
            == Constants.BINDING_ISSUE_SPECS_NONE_SELECTED,
            "the empty set was not reported");
    end);

    -- **A value that is not a mask under a class id does not raise on the next click.** A shared
    -- string is typed as far as `specs` being a table and no further (`Export.lua`'s
    -- `CONDITION_TYPES`), so anything can sit under a class id. Writing here is arithmetic and the
    -- normalization walks all thirteen classes, which means one imported action like this would
    -- otherwise raise on **any** box in this menu rather than on its own class's.
    --- **The junk sits on a class other than the one being clicked**, which is the whole point. The
    --- pressed class is read through a guard on its way to being written, so it cleans itself up;
    --- what the walk reaches is every other class, and any one of them holding such a value takes
    --- the click down with it.
    test("a click on a condition holding a value that is not a mask does not raise", function()
        local class = AClass();
        local other;
        for _, candidate in ipairs(DebindPrivate.ClassSpecCatalog()) do
            if (candidate.id ~= class.id and #candidate.specs > 0) then
                other = candidate.id;
                break;
            end
        end
        check(other, "the catalog has one class");

        local actions = ResetProfile({ Spell(1, { specs = { [other] = true } }) });
        local ctx = Ctx(actions);

        local ok, err = pcall(ActionMenu.ToggleSpecConditionIndex, ctx, class.id,
            class.specs[1].index);
        check(ok, "it raised: " .. tostring(err));

        check(DebindPrivate.SpecSetHoldsIndex(Cond(actions[1], "specs"), class.id,
            class.specs[1].index), "the box that was pressed did not come on");

        -- **And the pressed class holding it**, which is the other of the two readers: the mask is
        -- taken off the action to be written back, and that read is arithmetic too.
        local own = ResetProfile({ Spell(1, { specs = { [class.id] = true } }) });
        local ownCtx = Ctx(own);

        local ownOk, ownErr = pcall(ActionMenu.ToggleSpecConditionIndex, ownCtx, class.id,
            class.specs[1].index);
        check(ownOk, "the pressed class raised: " .. tostring(ownErr));

        check(DebindPrivate.SpecSetHoldsIndex(Cond(own[1], "specs"), class.id,
            class.specs[1].index), "the box that was pressed did not come on");
        check(not DebindPrivate.SpecSetHoldsIndex(Cond(own[1], "specs"), class.id,
            class.specs[2].index), "a value nobody can read came out holding more than was pressed");
    end);


    ---------------------------------------------------------------------------
    -- Unit conditions
    ---------------------------------------------------------------------------

    test("a unit condition mode lands on every action and each keeps what it remembered", function()
        local actions = ResetProfile({
            Spell(1, { units = { target = { disabled = true, reaction = Constants.REACTION_HELP } } }),
            Spell(2),
        });
        local ctx = Ctx(actions);

        ActionMenu.SetUnitConditionMode(ctx, "target", "exists");
        local first, second = Cond(actions[1], "units").target, Cond(actions[2], "units").target;
        check(first.exists == true and first.disabled == nil, "first did not come on");
        check(first.reaction == Constants.REACTION_HELP, "first forgot its reaction");
        check(second.exists == true, "second did not come on");

        ActionMenu.SetUnitConditionMode(ctx, "target", "disabled");
        check(Cond(actions[1], "units").target.disabled == true, "first did not turn off");
        check(actions[2].conditions == nil, "second remembered nothing and still holds a table");
    end);

    test("a reaction box goes to one outcome, and all-on folds away per action", function()
        local HELP, HARM = Constants.REACTION_HELP, Constants.REACTION_HARM;
        local actions = ResetProfile({
            Spell(1, { units = { target = { exists = true } } }),
            Spell(2, { units = { target = { exists = true, reaction = HELP } } }),
        });
        local ctx = Ctx(actions);

        check(not ActionMenu.UnitConditionReactionChecked(ctx, "target", HARM),
            "only one of them takes hostile, and the box is on");
        ActionMenu.ToggleUnitConditionReaction(ctx, "target", HARM);
        check(Cond(actions[1], "units").target.reaction == nil, "first was all-on and should stay unwritten");
        check(Cond(actions[2], "units").target.reaction == HELP + HARM,
            "second: " .. tostring(Cond(actions[2], "units").target.reaction));

        ActionMenu.ToggleUnitConditionReaction(ctx, "target", HARM);
        check(Cond(actions[1], "units").target.reaction == Constants.REACTION_ALL - HARM,
            "first, off: " .. tostring(Cond(actions[1], "units").target.reaction));
        check(Cond(actions[2], "units").target.reaction == HELP,
            "second, off: " .. tostring(Cond(actions[2], "units").target.reaction));
    end);

    ---------------------------------------------------------------------------
    -- Ordering after a write
    ---------------------------------------------------------------------------

    test("every key group a write touched is numbered 1..n again", function()
        local actions = ResetProfile({
            Spell(1, { seq = 10 }), Spell(2, { seq = 20 }), Spell(3, { seq = 30 }),
        });

        ActionMenu.setActionValue({ ctx = Ctx({ actions[3], actions[1] }), key = "combat", value = true });

        local seqs = {};
        for i, row in ipairs(DebindPrivate.CollectActionsForKey("F")) do
            seqs[i] = tostring(row.action.seq);
        end
        check(table.concat(seqs, " ") == "1 2 3", "numbers: " .. table.concat(seqs, " "));
    end);

    ---------------------------------------------------------------------------
    -- How many hold it, where the selection is split
    ---------------------------------------------------------------------------

    --- **The count asks the row's own reading once per action**, so the number beside a row and the
    --- tick on it cannot come from two different rules.
    test("a choice counts the actions holding it, and only when they differ", function()
        local actions = ResetProfile({
            Spell(1, { combat = true }), Spell(2, { combat = false }), Spell(3, { combat = true }),
        });
        local ctx = Ctx(actions);
        local data = { ctx = ctx, key = "combat", value = true };

        check(ActionMenu.MixedCount(ctx, ActionMenu.actionValueEquals, data) == 2,
            "count: " .. tostring(ActionMenu.MixedCount(ctx, ActionMenu.actionValueEquals, data)));
        check(ctx.actions == actions, "the selection was not put back");
        check(ActionMenu.MixedCount(ctx, ActionMenu.actionValueEquals,
            { ctx = ctx, key = "combat", value = "never" }) == nil, "nobody holds it, and a count stood");

        local same = Ctx({ actions[1], actions[3] });
        check(ActionMenu.MixedCount(same, ActionMenu.actionValueEquals,
            { ctx = same, key = "combat", value = true }) == nil, "everyone holds it, and a count stood");
    end);

    test("a group counts the actions with something set, when what they hold differs", function()
        local actions = ResetProfile({
            Spell(1, { combat = true }), Spell(2, { combat = false }), Spell(3),
        });
        local node = { key = "combat" };

        check(ActionMenu.NodeMixedCount(node, Ctx({ actions[1], actions[2] })) == 2,
            "both set, differently: " .. tostring(ActionMenu.NodeMixedCount(node, Ctx({ actions[1], actions[2] }))));
        check(ActionMenu.NodeMixedCount(node, Ctx({ actions[1], actions[3] })) == 1,
            "one set, one not: " .. tostring(ActionMenu.NodeMixedCount(node, Ctx({ actions[1], actions[3] }))));
        check(ActionMenu.NodeMixedCount(node, Ctx({ actions[1], actions[1] })) == nil, "the same, and a count stood");
        check(ActionMenu.NodeMixedCount(node, Ctx({ actions[1] })) == nil, "one action, and a count stood");
    end);

    test("a group with no key of its own compares what it says it holds, and what its children hold", function()
        local actions = ResetProfile({
            Spell(1, { units = { unitframe = { exists = true } } }), Spell(2, { units = { unitframe = { exists = false } } }),
            Spell(3, { stealth = true }), Spell(4, { stealth = true }),
        });
        local hover = {
            isActive = function(ctx)
                return ActionMenu.UnitConditionIsOn(ctx, "unitframe");
            end,
            valueOf = function(action)
                local units = action.conditions and action.conditions.units;
                return units and units.unitframe;
            end,
        };
        check(ActionMenu.NodeMixedCount(hover, Ctx({ actions[1], actions[2] })) == 2, "two hovers that differ");

        ActionMenu.ActionMenus:Define("SPEC_STEALTH_CHILD", { label = "x", key = "stealth" });
        local parent = {
            children = { "SPEC_STEALTH_CHILD" },
            isActive = function(ctx)
                return ActionMenu.AnyAction(ctx, function(action)
                    return action.conditions ~= nil and action.conditions.stealth ~= nil;
                end);
            end,
        };
        check(ActionMenu.NodeMixedCount(parent, Ctx({ actions[3], actions[4] })) == nil, "same child value");
        check(ActionMenu.NodeMixedCount(parent, Ctx({ actions[3], actions[1] })) == 1, "a child set on one only");
    end);

    ---------------------------------------------------------------------------
    -- What a selection may not reach
    ---------------------------------------------------------------------------

    test("an item for one action at a time is open for one and locked with a reason for more", function()
        local actions = ResetProfile({ Spell(1), Spell(2) });
        check(ActionMenu.OnlyOneReason(Ctx({ actions[1] })) == nil, "one action is locked out");
        local reason = ActionMenu.OnlyOneReason(Ctx(actions));
        check(type(reason) == "string" and reason ~= "", "two actions get no reason: " .. tostring(reason));
    end);

    test("an item every action has to take answers all, some or none", function()
        local actions = ResetProfile({
            Spell(1), Spell(2), { type = Constants.MACROTEXT, value = "/say x", key = "F" },
        });
        local takes = DebindPrivate.ActionTakesUnit;
        check(ActionMenu.HowManyAccept(Ctx({ actions[1], actions[2] }), takes) == "all", "two spells");
        check(ActionMenu.HowManyAccept(Ctx(actions), takes) == "some", "two spells and a macro");
        check(ActionMenu.HowManyAccept(Ctx({ actions[3] }), takes) == "none", "a macro alone");
    end);

    return T;
end
