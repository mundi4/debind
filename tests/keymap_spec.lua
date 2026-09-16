-- **What `BuildKeyMap` hands out for one key.** No WoW client needed.
--
-- The specs beside this one stop a step short of it on purpose: `normalize_spec` reads the binding
-- `GetBindingInfoForAction` makes from one action, `ordering_spec` reads the comparator, `solver_spec`
-- reads the boxes. This reads the list a key actually ends up with -- the same walk, run whole.
--
-- **Two walks cross this profile and they must not disagree.** `CollectActionsForKey` is the list
-- the window draws and `BuildKeyMap` is the list the key fires from, and a reader shown one order
-- while the key runs another has no way to find out. So the cases here read `KeyMap` and the cases
-- in `renumber_spec` read both.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local castmod = require("castmod");
    local band, bor = bit.band, bit.bor;

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

    local ME = "Player-1-KEYMAP";

    local function Bind(actions, switches, options)
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches or {},
            options = options,
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    --- The records the key came out with, or nil where it came out with none. The self and focus
    --- twins are left out; the one case that is about them reads `KeyMap` itself.
    local function Records(key)
        return castmod.without(Constants, DebindPrivate.KeyMap[key]);
    end

    local function Values(key)
        local records = Records(key);
        if (not records) then return "<none>"; end
        local out = {};
        for i = 1, #records do out[i] = tostring(records[i].value); end
        return table.concat(out, " ");
    end

    ---------------------------------------------------------------------------
    -- What a record carries out
    ---------------------------------------------------------------------------

    -- **A saved `UNUSED` or `COMMAND` stands on the key as a BLOCK**, and the action keeps the type
    -- it was saved with (`devdocs/dropping-the-game-fallback.md` §3). Nothing after it on the key
    -- can fire, so it has to reach the key rather than be left out.
    test("an unused or command action stands on the key as a block", function()
        local unused = { type = Constants.UNUSED, key = "F1", seq = 1 };
        local command = { type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "F2", seq = 2 };
        Bind({ unused, command });

        for key, stored in pairs({ F1 = unused, F2 = command }) do
            local list = DebindPrivate.KeyMap[key];
            local original;
            for i = 1, #(list or {}) do
                if (not castmod.isTwin(Constants, list[i])) then
                    original = list[i];
                end
            end
            check(original, key .. ": the action did not reach the key");
            check(original.type == Constants.BLOCK, key .. ": it came out as " .. tostring(original.type));
            check(stored.type ~= Constants.BLOCK, key .. ": the stored action was rewritten");
        end
    end);

    -- **A hover condition is two answers, and both ride the record.** Which reactions the frame's
    -- unit may have, and which kinds of frame count at all. Either one lost leaves a key that fires
    -- over frames the reader excluded, and nothing says so.
    test("a hover condition carries its reactions and its frame types", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "BUTTON3", seq = 1,
                conditions = {
                    units = { unitframe = {
                        reaction = bor(Constants.REACTION_HELP, Constants.REACTION_HARM),
                        frameTypes = Constants.FRAMETYPE_GROUP,
                    } },
                } },
        });

        local record = Records("BUTTON3") and Records("BUTTON3")[1];
        check(record, "the hover record did not reach the key");

        local unitframe = record.conditions.units and record.conditions.units.unitframe;
        check(type(unitframe) == "table", "the unitframe condition came out as " .. tostring(unitframe));
        check(band(unitframe.reaction, Constants.REACTION_HELP) ~= 0, "the friendly bit is gone");
        check(band(unitframe.reaction, Constants.REACTION_HARM) ~= 0, "the hostile bit is gone");
        check(record.unitFrameTypes == Constants.FRAMETYPE_GROUP,
            "frameTypes came out as " .. tostring(record.unitFrameTypes));
    end);

    -- **Five axes at once, which is what a real profile looks like.** One condition on one key only
    -- answers "does it look at conditions at all"; a record dropping *one* of several is the shape
    -- that gets through, and it widens the binding rather than narrowing it.
    test("every condition on one record reaches the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "HOME", seq = 1,
                conditions = {
                    combat = true,
                    groups = Constants.GROUP_RAID,
                    stealth = false,
                    mounted = true,
                    ["$state2"] = true,
                } },
        }, { ["$state2"] = { mode = Constants.SWITCH_MODES.MANUAL } });

        local record = Records("HOME") and Records("HOME")[1];
        check(record, "the record did not reach the key");
        local c = record.conditions;
        check(c.combat == true, "combat: " .. tostring(c.combat));
        check(c.groups == Constants.GROUP_RAID, "groups: " .. tostring(c.groups));
        -- `false` is "when there is not", which is a point on the axis and not an absence.
        check(c.stealth == false, "stealth: " .. tostring(c.stealth));
        check(c.mounted == true, "mounted: " .. tostring(c.mounted));
        check(c["$state2"] == true, "$state2: " .. tostring(c["$state2"]));
    end);

    -- **A record is a pure derivation of one action**, and the numbers that order it are not: where
    -- an action stands is a fact about the profile around it, so `Misc.MakeOrderRecord` holds those
    -- beside the record rather than on it.
    --
    -- **Going back is silent.** `BuildKeyMap` used to write these fields on and nobody wiped them,
    -- so they survived to the next rebuild and the second writer agreed with the first. The order
    -- stays right; what stops being true is "a record tells you its action", and no screen says so.
    test("a record carries no ordering fields", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", priority = 5, seq = 1 },
            { type = Constants.SPELL, value = 116, key = "F1", priority = 1, seq = 2,
                conditions = { combat = true } },
        });

        local records = Records("F1");
        check(records and #records == 2, "expected two records, got " .. Values("F1"));
        for i = 1, #records do
            for _, field in ipairs({ "layerRank", "specRank", "seq", "isConditional", "priority" }) do
                check(records[i][field] == nil,
                    "record " .. i .. " carries " .. field .. "=" .. tostring(records[i][field]));
            end
        end
    end);

    ---------------------------------------------------------------------------
    -- Which record goes first
    ---------------------------------------------------------------------------

    -- **A conditional record goes ahead of an unconditional one on the same key**, whatever order
    -- they were written in. The other way round the unconditional one matches everything and the
    -- conditional one below it can never be reached -- the reader's narrower answer would be the
    -- one that never runs.
    test("a conditional record comes before an unconditional one", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "DELETE", seq = 1 },
            { type = Constants.SPELL, value = 116, key = "DELETE", seq = 2,
                conditions = { combat = true } },
        });
        check(Values("DELETE") == "116 585", "the order came out " .. Values("DELETE"));
    end);

    -- **A condition on the resolved target makes the action conditional, target or not.** An
    -- action with no target and nothing but that condition used to read as unconditional, so it sat
    -- behind an unconditional one placed earlier, and that one's self twin covered its own: held or
    -- not, the key never reached it (`devdocs/implementing-focus-and-self-cast.md` §3-6).
    test("a resolved target condition with no target picked sorts as conditional", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "DELETE", seq = 1 },
            { type = Constants.SPELL, value = 116, key = "DELETE", seq = 2,
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } },
        });
        check(Values("DELETE") == "116 585", "the order came out " .. Values("DELETE"));
    end);

    -- **What arrives keeps the sender's key and the sender's order.** The badge is the only thing
    -- holding it out of the build, so the key it names is a real one -- and once the badge comes off
    -- the order the set was sent in is the order it fires in.
    --
    -- **The stored array is deliberately out of step with it.** If the two agreed, this would be
    -- measuring the array's order rather than the order that arrived.
    test("an accepted arrival fires in the order it was sent in", function()
        local third = { type = Constants.SPELL, value = 3, key = "F4", arrivalID = 1, seq = 3,
            conditions = { combat = true } };
        local first = { type = Constants.SPELL, value = 1, key = "F4", arrivalID = 1, seq = 1,
            conditions = { stealth = true } };
        local second = { type = Constants.SPELL, value = 2, key = "F4", arrivalID = 1, seq = 2,
            conditions = { mounted = true } };
        Bind({ third, first, second });

        check(Records("F4") == nil, "a badged set stood on the key it arrived on");

        local group = DebindPrivate.CollectKeyGroupActions("F4", 1);
        check(#group == 3, "the set did not come back together: " .. #group);

        DebindPrivate.SetKeyForActions(group, "F4");
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        check(Values("F4") == "1 2 3", "the sender's order was not kept: " .. Values("F4"));
    end);

    ---------------------------------------------------------------------------
    -- What never reaches the key
    ---------------------------------------------------------------------------

    -- **An imported string plants no switch definitions**, so an on/off/toggle action arriving from
    -- somebody else can name a switch this profile has never had. Nothing about the row says so;
    -- what says so is the action going red and dropping out of the build.
    --
    -- **The passing half first.** Without it a missing key reads as "switch actions do not bind at
    -- all" rather than as the marker doing its job.
    test("a setstate action naming an undefined switch reaches no key", function()
        Bind({
            { type = Constants.SETSTATE_TOGGLE, value = "$defined", key = "F1", seq = 1 },
            { type = Constants.SETSTATE_TOGGLE, value = "$nodefinition", key = "F2", seq = 2 },
        }, { ["$defined"] = { mode = Constants.SWITCH_MODES.MANUAL } });

        check(Records("F1"), "an action naming a defined switch was kept out too -- bad premise");
        check(Records("F2") == nil, "an action naming nothing that exists bound anyway");

        check(DebindPrivate.GetBindingIssue({ type = Constants.SETSTATE_TOGGLE,
            value = "$nodefinition", key = "F2" }) == Constants.BINDING_ISSUE_UNDEFINED_STATE,
            "the row is drawn as though nothing were wrong with it");
    end);

    ---------------------------------------------------------------------------
    -- One action, two records (`devdocs/splitting-an-action-into-bindings.md`)
    ---------------------------------------------------------------------------

    -- **The key is laid out in tiers**: every self twin, every focus twin, every hover twin, every
    -- original (`devdocs/implementing-focus-and-self-cast.md` §3-4). Side by side, an original placed
    -- first took a pointed press before the hover twin of the action behind it had a turn. Among the
    -- originals the hover condition still sorts first; action 1 has no hover twin to show it, since
    -- its [not pointing] leaves the twin nothing to match.
    test("the key is laid out in tiers", function()
        Bind({
            { type = Constants.SPELL, value = 1, key = "F1", seq = 1,
                conditions = { units = { unitframe = false }, stealth = true } },
            { type = Constants.SPELL, value = 2, key = "F1", seq = 2, conditions = { combat = true } },
        }, nil, { hoverCast = true });

        local records = DebindPrivate.KeyMap["F1"];
        local shape = {};
        for i = 1, #records do
            local record = records[i];
            local tier = (record.castModifier == Constants.CASTMOD_SELF and "self")
                or (record.castModifier == Constants.CASTMOD_FOCUS and "focus")
                or (record.hoverTwin and "hover")
                or "original";
            shape[i] = tier .. ":" .. tostring(record.value);
        end
        shape = table.concat(shape, " ");
        check(shape == "self:1 self:2 focus:1 focus:2 hover:2 original:1 original:2",
            "F1 came out as " .. shape);
    end);

    -- **A mouse button gets no hover twin that only competes for order** (§3-4, 2026-09-13, owner).
    -- A mouse-button original with no hover condition never fires over a frame, so a twin going out
    -- the way it does would only be a frame click record, and a frame click arrives on its exact
    -- combination with nothing to order against. Left out, the click on the frame falls through to
    -- the frame's own action. The Hover Cast twin aimed at the frame's unit stays a frame record.
    test("on a mouse button a twin that goes out as its original is not made", function()
        Bind({
            { type = Constants.MACROTEXT, value = "/say hi", key = "BUTTON4", seq = 1 },
            { type = Constants.SPELL, value = 585, key = "SHIFT-BUTTON4", seq = 2 },
        }, nil, { hoverCast = true });

        local macro = DebindPrivate.KeyMap["BUTTON4"];
        check(macro and #macro > 0, "the macro did not reach its key");
        for i = 1, #macro do
            check(not macro[i].hoverTwin, "the macro has a hover twin at " .. i);
            check(not macro[i].isClickCast, "the macro has a frame click record at " .. i);
        end

        local spell = DebindPrivate.KeyMap["SHIFT-BUTTON4"];
        local frameRecord;
        for i = 1, #(spell or {}) do
            if (spell[i].hoverTwin and spell[i].isClickCast) then
                frameRecord = spell[i];
            end
        end
        check(frameRecord and frameRecord.unit == "unitframe",
            "the spell's Hover Cast twin is not a frame record aimed at the frame's unit");
    end);

    -- On a mouse button the two split the way a hover record and a plain one always have: the twin
    -- is a click on the frame, the original holds the key.
    test("on a mouse button the twin is the click-cast and the original holds the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "BUTTON3", seq = 1 },
        }, nil, { hoverCast = true });

        local records = Records("BUTTON3");
        check(records and #records == 2, "BUTTON3 came out with " .. tostring(records and #records));
        check(records[1].isClickCast == true and records[1].holdsKey == false,
            "the twin is not the click-cast");
        check(records[2].isClickCast == false and records[2].holdsKey == true,
            "the original does not hold the key");
    end);


    return T;
end
