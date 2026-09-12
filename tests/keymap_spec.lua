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

    --- The records the key came out with, or nil where it came out with none.
    local function Records(key)
        return DebindPrivate.KeyMap[key];
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

    -- **`UNUSED` is the one type that reaches the key in order to fire nothing.** It is how a reader
    -- takes a key away from the game without taking it away from Debind, so it has to come out of
    -- the build as a record like any other -- what it must not have is anything to run.
    test("an unused record stands on the key and keeps its type", function()
        Bind({ { type = Constants.UNUSED, key = "F1", seq = 1 } });

        local record = Records("F1") and Records("F1")[1];
        check(record, "the unused record did not reach the key");
        check(record.type == Constants.UNUSED, "it came out as " .. tostring(record.type));
    end);

    -- **A hover condition is two answers, and both ride the record.** Which reactions the frame's
    -- unit may have, and which kinds of frame count at all. Either one lost leaves a key that fires
    -- over frames the reader excluded, and nothing says so.
    test("a hover condition carries its reactions and its frame types", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "BUTTON3", seq = 1,
                conditions = {
                    units = { hover = { reaction = bor(Constants.REACTION_HELP,
                        Constants.REACTION_HARM) } },
                    frameTypes = Constants.FRAMETYPE_GROUP,
                } },
        });

        local record = Records("BUTTON3") and Records("BUTTON3")[1];
        check(record, "the hover record did not reach the key");
        check(record.hover == true, "the derived hover flag is " .. tostring(record.hover));

        local hover = record.conditions.units and record.conditions.units.hover;
        check(type(hover) == "table", "the hover condition came out as " .. tostring(hover));
        check(band(hover.reaction, Constants.REACTION_HELP) ~= 0, "the friendly bit is gone");
        check(band(hover.reaction, Constants.REACTION_HARM) ~= 0, "the hostile bit is gone");
        check(record.conditions.frameTypes == Constants.FRAMETYPE_GROUP,
            "frameTypes came out as " .. tostring(record.conditions.frameTypes));
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

    -- **The twin is not a hover record for ordering purposes.** It stands right before its own
    -- original and nowhere else: a hover record placed earlier stays ahead of it, and so does a
    -- plain record placed earlier. Only the original is sorted; the twin rides along.
    test("a hover twin stands right before its original and behind everything placed earlier", function()
        Bind({
            { type = Constants.SPELL, value = 1, key = "F1", seq = 1,
                conditions = { units = { hover = {} }, combat = true } },
            -- 이 액션은 스위치에서 빼 둔다. 재는 것은 쌍둥이 하나가 서는 자리이고, 여기도
            -- 쌍둥이를 받으면 줄이 둘 늘어나 자리 검사가 흐려진다.
            { type = Constants.SPELL, value = 2, key = "F1", seq = 2,
                ignoreHoverUnit = true, conditions = { combat = true } },
            { type = Constants.SPELL, value = 3, key = "F1", seq = 3 },
        }, nil, { hoverCast = true });

        check(Values("F1") == "1 2 3 3", "F1 came out as " .. Values("F1"));
        local records = Records("F1");
        check(records[3].hover == true and records[3].unit == "hover", "the third record is not the twin");
        check(records[4].hover == nil, "the fourth record is not the original");
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
