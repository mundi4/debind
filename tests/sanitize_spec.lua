-- `SanitizeAction`: one action in, the shape the profile stores out (`sanitizing-actions-with-one-function.md`
-- §6). Each case is one row of that table: what goes in and what has to come out.
--
-- **The expected side is written out whole**, never derived from the field tables the function reads.
-- A case that asked the same table would agree with whatever the table says, and the table leaving
-- a field out is exactly the failure this has to catch.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local NAN = 0 / 0;

    local S = Constants.SPELL;
    local INVALID = Constants.INVALID;

    local T = { passed = 0, failures = {} };

    --- A readable picture of a value, keys sorted, so two runs print the same thing.
    local function show(value)
        if (type(value) ~= "table") then
            if (type(value) == "string") then
                return ("%q"):format(value);
            end
            return tostring(value);
        end
        local keys = {};
        for k in pairs(value) do
            keys[#keys + 1] = k;
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b); end);
        local parts = {};
        for _, k in ipairs(keys) do
            parts[#parts + 1] = ("%s=%s"):format(tostring(k), show(value[k]));
        end
        return "{" .. table.concat(parts, ", ") .. "}";
    end

    local function same(a, b)
        if (type(a) ~= "table" or type(b) ~= "table") then
            return a == b or (a ~= a and b ~= b);
        end
        for k, v in pairs(a) do
            if (not same(v, b[k])) then
                return false;
            end
        end
        for k in pairs(b) do
            if (a[k] == nil) then
                return false;
            end
        end
        return true;
    end

    --- `after` is the whole action expected back, or `false` for "the caller removes it".
    local function case(name, before, after)
        local ok, err = pcall(function()
            local kept = DebindPrivate.SanitizeAction(before);
            if (after == false) then
                if (kept ~= false) then
                    error("expected to be removed, kept as " .. show(before));
                end
                return;
            end
            if (kept == false) then
                error("removed, expected " .. show(after));
            end
            if (not same(before, after)) then
                error("got " .. show(before) .. ", expected " .. show(after));
            end
        end);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function spell(extra)
        local action = { type = S, value = 774, key = "F1", seq = 1 };
        for k, v in pairs(extra or {}) do
            action[k] = v;
        end
        return action;
    end
    local function withConditions(conditions)
        return spell({ conditions = conditions });
    end

    -- §6-2, the top of the action.

    case("a stored action comes out as it went in", spell(), spell());
    case("a name the profile does not save goes", spell({ somethingNew = true }), spell());
    case("a key that is not a string goes, and its seq with it",
        { type = S, value = 774, key = 7, seq = 1 }, { type = S, value = 774 });
    case("a NaN key goes", { type = S, value = 774, key = NAN, seq = 1 }, { type = S, value = 774 });
    case("Escape goes as a key", { type = S, value = 774, key = "ESCAPE", seq = 2 }, { type = S, value = 774 });
    case("a seq that is a table goes", spell({ seq = {} }), { type = S, value = 774, key = "F1" });
    case("a seq that is a string goes", spell({ seq = "1" }), { type = S, value = 774, key = "F1" });
    case("a NaN seq goes", spell({ seq = NAN }), { type = S, value = 774, key = "F1" });
    case("a keyless action keeps no seq", { type = S, value = 774, seq = 4 }, { type = S, value = 774 });
    case("a name that is not a string goes", spell({ name = {} }), spell());
    case("a NaN icon goes", spell({ icon = NAN }), spell());
    case("an icon path stays", spell({ icon = "Interface\\Icons\\X" }), spell({ icon = "Interface\\Icons\\X" }));
    case("a unit that is not a string goes", spell({ unit = 5 }), spell());
    case("a unit on an action that takes none goes",
        { type = Constants.MACRO, value = "M", unit = "target" }, { type = Constants.MACRO, value = "M" });
    case("a unit on a spell stays", spell({ unit = "focus" }), spell({ unit = "focus" }));
    case("a priority that is a table goes", spell({ priority = {} }), spell());
    case("a NaN priority goes", spell({ priority = NAN }), spell());
    case("the default priority is stored as none", spell({ priority = Constants.DEFAULT_IMPORTANCE }), spell());
    case("another priority stays", spell({ priority = 5 }), spell({ priority = 5 }));
    case("disabled that is not a boolean goes", spell({ disabled = "x" }), spell());
    case("disabled = false is stored as none", spell({ disabled = false }), spell());
    case("disabled = true stays", spell({ disabled = true }), spell({ disabled = true }));
    case("skipWhenUnusable stays on a spec-resolved type",
        { type = Constants.DISPEL, skipWhenUnusable = true }, { type = Constants.DISPEL, skipWhenUnusable = true });
    case("skipWhenUnusable = false is stored as none",
        { type = Constants.DISPEL, skipWhenUnusable = false }, { type = Constants.DISPEL });
    case("skipWhenUnusable goes from a spell", spell({ skipWhenUnusable = true }), spell());
    case("skipWhenUnusable that is not a boolean goes",
        { type = Constants.DISPEL, skipWhenUnusable = "x" }, { type = Constants.DISPEL });
    case("pinnedSpell stays on a spell", spell({ pinnedSpell = 8936 }), spell({ pinnedSpell = 8936 }));
    case("pinnedSpell goes from an item",
        { type = Constants.ITEM, value = 6948, pinnedSpell = 8936 }, { type = Constants.ITEM, value = 6948 });
    case("pinnedSpell that is a table goes", spell({ pinnedSpell = {} }), spell());
    case("resolvedSpellID stays beside a spell name",
        { type = S, value = "Rejuvenation", resolvedSpellID = 774 },
        { type = S, value = "Rejuvenation", resolvedSpellID = 774 });
    case("resolvedSpellID goes beside a spell id", spell({ resolvedSpellID = 774 }), spell());
    case("resolvedSpellID that is not a number goes",
        { type = S, value = "Rejuvenation", resolvedSpellID = "x" }, { type = S, value = "Rejuvenation" });
    case("a resurrection keeps noTargetMassRez = false",
        { type = Constants.RESURRECT, noTargetMassRez = false },
        { type = Constants.RESURRECT, noTargetMassRez = false });
    case("noTargetMassRez goes from a spell", spell({ noTargetMassRez = false }), spell());
    case("battleRezOutOfCombat that is not a boolean goes",
        { type = Constants.RESURRECT, battleRezOutOfCombat = "x" }, { type = Constants.RESURRECT });
    case("an arrival number stays", spell({ arrivalID = 3 }), spell({ arrivalID = 3 }));
    case("an arrival number that is not a number removes the action", spell({ arrivalID = "x" }), false);
    case("a NaN arrival number removes the action", spell({ arrivalID = NAN }), false);
    case("an action that is not a table is removed", 5, false);
    case("untranslated that is a table stays", spell({ untranslated = { spec1 = true } }),
        spell({ untranslated = { spec1 = true } }));
    case("untranslated that is not a table goes", spell({ untranslated = "x" }), spell());

    -- §6-2 and §6-6 item 2: a type or a value nothing can run on becomes `invalid`.

    case("a type that is a table makes it invalid, keeping a scalar value",
        { type = {}, value = 1, key = "F1", seq = 1 },
        { type = INVALID, formerly = { value = 1 }, key = "F1", seq = 1 });
    case("a type nobody knows makes it invalid, keeping both",
        { type = "직업변경", value = 1, key = "F1", seq = 1 },
        { type = INVALID, formerly = { type = "직업변경", value = 1 }, key = "F1", seq = 1 });
    case("a macro holding a number is invalid",
        { type = Constants.MACRO, value = 4 }, { type = INVALID, formerly = { type = Constants.MACRO, value = 4 } });
    case("a world marker with no value is invalid",
        { type = Constants.WORLDMARKER }, { type = INVALID, formerly = { type = Constants.WORLDMARKER } });
    case("a spell holding a table is invalid", spell({ value = {} }),
        { type = INVALID, formerly = { type = S }, key = "F1", seq = 1 });
    case("a spell holding NaN is invalid", spell({ value = NAN }),
        { type = INVALID, formerly = { type = S }, key = "F1", seq = 1 });
    case("an invalid action keeps its conditions and place",
        { type = Constants.MACRO, value = 4, key = "F1", seq = 2, priority = 5, conditions = { combat = true } },
        { type = INVALID, formerly = { type = Constants.MACRO, value = 4 }, key = "F1", seq = 2, priority = 5,
          conditions = { combat = true } });
    case("an invalid action keeps its target",
        { type = Constants.MACRO, value = 4, unit = "focus" },
        { type = INVALID, formerly = { type = Constants.MACRO, value = 4 }, unit = "focus" });
    case("a value on a type that holds none goes",
        { type = Constants.DISPEL, value = 5 }, { type = Constants.DISPEL });
    case("a command nobody knows on an action button stays",
        { type = Constants.ACTIONBUTTON, value = "NOPE" }, { type = Constants.ACTIONBUTTON, value = "NOPE" });
    case("a switch action with no switch picked stays",
        { type = Constants.SETSWITCH_ON }, { type = Constants.SETSWITCH_ON });
    case("formerly goes from a type that runs", spell({ formerly = { type = S } }), spell());
    case("formerly keeps only scalar type and value",
        { type = INVALID, formerly = { type = {}, value = 2, extra = 1 } }, { type = INVALID, formerly = { value = 2 } });
    case("formerly that is not a table goes", { type = INVALID, formerly = "x" }, { type = INVALID });
    case("an invalid action holds no value", { type = INVALID, value = 5 }, { type = INVALID });

    -- §6-3, `casting`.

    case("casting that is not a table goes", spell({ casting = "x" }), spell());
    case("normalCast = true is the default and goes, and the empty casting with it",
        spell({ casting = { normalCast = true } }), spell());
    case("normalCast = false stays", spell({ casting = { normalCast = false } }),
        spell({ casting = { normalCast = false } }));
    case("a casting value of the wrong type goes", spell({ casting = { hoverCast = 5, autoSelfCast = "x" } }), spell());
    case("a casting name nobody knows goes", spell({ casting = { notACastingValue = "skip" } }), spell());
    case("a casting spelling nobody knows stays when it is a string",
        spell({ casting = { hoverCast = "sometimes" } }), spell({ casting = { hoverCast = "sometimes" } }));

    -- §6-4, `conditions`.

    case("conditions that is not a table goes", withConditions("x"), spell());
    case("an empty conditions goes", withConditions({}), spell());
    case("a condition name nobody knows goes", withConditions({ somethingNew = true }), spell());
    case("a condition key that is not a string goes", withConditions({ [1] = true }), spell());
    case("a switch condition that is not a boolean goes", withConditions({ ["$burst"] = "x" }), spell());
    case("a switch condition stays", withConditions({ ["$burst"] = true }), withConditions({ ["$burst"] = true }));
    case("a yes/no condition that is not a boolean goes", withConditions({ combat = "x" }), spell());
    case("a mask that is not a number reads as nothing picked", withConditions({ groups = "x" }),
        withConditions({ groups = 0 }));
    case("a NaN mask reads as nothing picked", withConditions({ forms = NAN }), withConditions({ forms = 0 }));
    case("a fractional mask reads as nothing picked", withConditions({ bonusbars = 2.5 }),
        withConditions({ bonusbars = 0 }));
    case("a negative mask reads as nothing picked", withConditions({ bartakeover = -1 }),
        withConditions({ bartakeover = 0 }));
    case("a mask loses the bits past its range", withConditions({ groups = 8 + Constants.GROUP_PARTY }),
        withConditions({ groups = Constants.GROUP_PARTY }));
    case("a mask holding only bits past its range reads as nothing picked", withConditions({ groups = 8 }),
        withConditions({ groups = 0 }));
    case("every box ticked stays", withConditions({ forms = Constants.FORM_ALL }),
        withConditions({ forms = Constants.FORM_ALL }));
    case("known = false goes", withConditions({ known = false }), spell());
    case("known that is a table goes", withConditions({ known = {} }), spell());
    case("a NaN known goes", withConditions({ known = NAN }), spell());
    case("known goes from an item",
        { type = Constants.ITEM, value = 6948, conditions = { known = "Hearthstone" } },
        { type = Constants.ITEM, value = 6948 });
    case("known = true on a spec-resolved type becomes skipWhenUnusable",
        { type = Constants.DISPEL, conditions = { known = true } }, { type = Constants.DISPEL, skipWhenUnusable = true });
    case("a spell keeps a known spell name", withConditions({ known = "Flash Heal" }),
        withConditions({ known = "Flash Heal" }));

    case("specs that is not a table reads as nothing picked", withConditions({ specs = "x" }),
        withConditions({ specs = {} }));
    case("a specs class that is not a number goes", withConditions({ specs = { DRUID = 2, [11] = 2 } }),
        withConditions({ specs = { [11] = 2 } }));
    case("a specs value that is not a number leaves that class unpicked", withConditions({ specs = { [11] = "x" } }),
        withConditions({ specs = {} }));
    case("a specs value at 0 leaves that class unpicked, and the set stays",
        withConditions({ specs = { [11] = 0 } }), withConditions({ specs = {} }));
    case("a specs value loses the bits no client has", withConditions({ specs = { [11] = 32 + 1 } }),
        withConditions({ specs = { [11] = 1 } }));
    case("a specs bit this client's class lacks stays", withConditions({ specs = { [11] = 16 + 4 } }),
        withConditions({ specs = { [11] = 16 + 4 } }));

    case("talents that is not a table goes", withConditions({ talents = "x" }), spell());
    case("a talents entry that is not a table goes", withConditions({ talents = { [102] = true } }), spell());
    case("a talents key that is not a number goes",
        withConditions({ talents = { x = { taken = { 1 } }, [102] = { taken = { 2 } } } }),
        withConditions({ talents = { [102] = { taken = { 2 } } } }));
    case("a talent list keeps only its numbers",
        withConditions({ talents = { [102] = { taken = { 1, "x", NAN, 2 } } } }),
        withConditions({ talents = { [102] = { taken = { 1, 2 } } } }));
    case("a talent list name nobody knows goes", withConditions({ talents = { [102] = { maybe = { 1 } } } }), spell());
    case("an empty talent list goes beside a full one",
        withConditions({ talents = { [102] = { taken = {}, notTaken = { 5 } } } }),
        withConditions({ talents = { [102] = { notTaken = { 5 } } } }));
    case("a talent list that is not a table goes",
        withConditions({ talents = { [102] = { taken = 5, notTaken = { 5 } } } }),
        withConditions({ talents = { [102] = { notTaken = { 5 } } } }));

    -- §6-5, the rows of `units`.

    local function withUnits(units)
        return withConditions({ units = units });
    end
    case("units that is not a table goes", withUnits("x"), spell());
    case("a row for a unit no menu lists goes", withUnits({ arena1 = { exists = true } }), spell());
    case("a row for no target goes", withUnits({ none = { exists = true } }), spell());
    case("the row for the aimed unit stays", withUnits({ ["@"] = { exists = true } }),
        withUnits({ ["@"] = { exists = true } }));
    case("the player's row stays", withUnits({ player = { exists = true, dead = true } }),
        withUnits({ player = { exists = true, dead = true } }));
    case("a row that is not a table goes", withUnits({ target = "x" }), spell());
    case("the old scalar for there being one becomes its row", withUnits({ target = true }),
        withUnits({ target = { exists = true } }));
    case("the old scalar for there being none becomes its row", withUnits({ target = false }),
        withUnits({ target = { exists = false } }));
    case("the old friendly scalar becomes its row", withUnits({ target = "help" }),
        withUnits({ target = { exists = true, reaction = Constants.REACTION_HELP } }));
    case("the old hostile scalar becomes its row", withUnits({ target = "harm" }),
        withUnits({ target = { exists = true, reaction = Constants.REACTION_HARM } }));
    case("the pointed frame's old name moves to unitframe", withUnits({ hover = { exists = false } }),
        withUnits({ unitframe = { exists = false } }));
    case("both names at once keep the new one", withUnits({ hover = { exists = false }, unitframe = { exists = true } }),
        withUnits({ unitframe = { exists = true } }));
    case("a row name nobody knows inside goes", withUnits({ target = { exists = true, notAnAxis = 1 } }),
        withUnits({ target = { exists = true } }));
    case("a row's yes/no that is not a boolean goes", withUnits({ target = { exists = true, dead = "x" } }),
        withUnits({ target = { exists = true } }));
    case("a row with no mode reads as there being one", withUnits({ target = { reaction = Constants.REACTION_HELP } }),
        withUnits({ target = { exists = true, reaction = Constants.REACTION_HELP } }));
    case("a mode that is not a boolean leaves a row with no mode", withUnits({ target = { exists = "x" } }),
        withUnits({ target = { exists = true } }));
    case("disabled = false is stored as none", withUnits({ target = { disabled = false, exists = false } }),
        withUnits({ target = { exists = false } }));
    case("a turned-off row keeps its axes and drops exists",
        withUnits({ target = { disabled = true, exists = true, reaction = Constants.REACTION_HELP } }),
        withUnits({ target = { disabled = true, reaction = Constants.REACTION_HELP } }));
    case("a turned-off row with nothing to remember goes", withUnits({ target = { disabled = true } }), spell());
    case("a row mask that is not a number reads as nothing picked", withUnits({ target = { exists = true, reaction = "x" } }),
        withUnits({ target = { exists = true, reaction = 0 } }));
    case("a row mask loses the bits past its range",
        withUnits({ unitframe = { exists = true, role = 16 } }), withUnits({ unitframe = { exists = true, role = 0 } }));
    case("a row mask with every box ticked is stored as none",
        withUnits({ target = { exists = true, group = Constants.UNITGROUP_ALL } }),
        withUnits({ target = { exists = true } }));

    return T;
end
