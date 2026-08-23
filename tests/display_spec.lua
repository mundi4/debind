-- **What the reader is shown about an action.** No WoW client needed, which it used to be.
--
-- `ActionDisplay.lua` names an action and `ActionTooltip.lua` writes the block that hangs off it,
-- and both were out of reach here for one reason: they are `DebindUI.xml`'s files. Neither needs a
-- frame -- the first resolves a name, the second takes the tooltip as an argument and puts its
-- lines through the client's `GameTooltip_Add…` functions -- so `tests/run.lua` reads them now and
-- the words a reader sees are a value like any other.
--
-- **What is asked here is what the reader ends up looking at**, not which flag was set. The flags
-- have their own coverage (`issue_spec.lua`, `suppression_spec.lua`); what those cannot see is a
-- reason that is computed correctly and then not written down, or written down on the wrong row.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local LLL = DebindPrivate.L;
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

    local ME = "Player-1-DISPLAY";

    local function Bind(actions, switches)
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = switches,
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    --- One row's tooltip, as text.
    ---
    --- `suppressInactive` is on because the order list is the caller that draws unreachable rows at
    --- all: with it off, an action the solver dropped reads as inactive and the key line is greyed
    --- instead of carrying the reason.
    local function Tooltip(row)
        local tooltip = shim.newTooltip();
        DebindPrivate.AddActionToTooltip(tooltip, row.action, {
            offWorld = row.offWorld,
            suppressInactive = true,
        });
        return tooltip:text();
    end

    local function Says(row, key)
        return Tooltip(row):find(LLL[key], 1, true) ~= nil;
    end

    ---------------------------------------------------------------------------
    -- Unreachable, and the row that covers it
    ---------------------------------------------------------------------------

    -- **Two records saying exactly the same thing.** The later one can never win, so the solver
    -- drops it, and it is the one with something to report.
    --
    -- **Three readings, and the middle one is the only one that looks like the point.** That the
    -- dropped row says so is the obvious half; that the row which covered it stays quiet is what
    -- separates "this row is unreachable" from "this key has something wrong with it", and a reader
    -- told the wrong one of those goes and edits the record that was working.
    --
    -- **The third is the order list's other-specialization view.** Unreachable is an answer out of
    -- a key map this record was never in, so the tooltip has to drop it there -- otherwise every
    -- row a reader looks at from another specialization is marked unreachable and none of them is.
    test("an unreachable row says so, the row covering it does not, and off-spec neither", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { combat = true } },
            { type = Constants.SPELL, value = 586, key = "F1", seq = 2,
                conditions = { combat = true } },
        }, {});

        local subject, cover;
        for _, row in ipairs(DebindPrivate.CollectActionsForKey("F1")) do
            if (row.unreachable) then subject = row; else cover = row; end
        end
        check(subject and cover, "the solver dropped nothing, so there is no pair to compare");
        check(cover.issue == nil, "the covering row picked up an issue: " .. tostring(cover.issue));

        check(not Says(cover, "BINDING_ERROR_UNREACHABLE"),
            "the working row's tooltip called itself unreachable");
        check(Says(subject, "BINDING_ERROR_UNREACHABLE"),
            "the dropped row's tooltip says nothing about why");

        -- Only the flag is set here: the real path recomputes `issue` from it, and the record's
        -- shape is what the tooltip reads.
        subject.offWorld = true;
        check(not Says(subject, "BINDING_ERROR_UNREACHABLE"),
            "a row read from another specialization was still called unreachable");
    end);

    -- **Suppression reaches one branch and must not reach the next.** `BUTTON1` with no hover
    -- condition is invalid wherever it is read from -- nothing about that comes out of a key map --
    -- so an off-spec view that swallowed it would leave a reader with a key that cannot work and a
    -- tooltip that says nothing is wrong.
    test("a key that is invalid anywhere is still called invalid off-spec", function()
        Bind({ { type = Constants.SPELL, value = 585, key = "BUTTON1", seq = 1 } }, {});

        local row = DebindPrivate.CollectActionsForKey("BUTTON1")[1];
        check(row, "no row stood on BUTTON1");
        check(row.issue == Constants.BINDING_ISSUE_NOT_SUPPORTED_MOUSE_BUTTON,
            "the row is not carrying the mouse-button issue: " .. tostring(row.issue));

        row.offWorld = true;
        check(Says(row, "BINDING_ERROR_NOT_SUPPORTED_MOUSE_BUTTON"),
            "being read from another specialization turned off the key validity check too");
    end);

    ---------------------------------------------------------------------------
    -- What the picker offers for a switch
    ---------------------------------------------------------------------------

    -- **One row, whatever the profile holds.** The special tab offered three per defined switch
    -- until 3c; it offers one that names no switch, and which switch is chosen in the action's own
    -- menu afterwards (§6-C of `devdocs/redesigning-custom-states.md`).
    --
    -- **The name is asked for, because a row that cannot be named is not drawn at all.**
    -- `NameAndIconForAction` formats the switch name into the label, and a target-less row has none
    -- -- so a resolver that raised or answered `"?"` would take the row out of the list and the
    -- count above would read zero rather than three.
    --
    -- **The second half is the key.** An action that names no switch must not bind: it is finished
    -- in the menu, and binding it half-made would fire a switch nobody chose. Without picking one
    -- afterwards, "it did not bind" also describes a row that never binds.
    test("the picker offers one switch row, unnamed, and it binds nothing until told which",
        function()
            Bind({}, { ["$picked"] = { mode = Constants.SWITCH_MODES.MANUAL } });

            local special;
            for _, category in ipairs(DebindPrivate.ActionCatalog.GetCategories()) do
                if (category.key == "special") then special = category; end
            end
            check(special, "the special category is not in the catalog");

            local rows, sample = 0, nil;
            for _, entry in ipairs(DebindPrivate.ActionCatalog.GetEntries(special)) do
                if (Constants.SETSTATE_MODES[entry.type]) then
                    rows = rows + 1;
                    sample = entry;
                end
            end
            check(rows == 1, "the picker draws " .. rows .. " switch rows, not one");
            check(sample.value == nil,
                "the row already names a switch: " .. tostring(sample.value));
            check(sample.name and sample.name ~= "?",
                "the row could not be named: " .. tostring(sample.name));

            local action = { type = sample.type, value = sample.value, key = "F1", seq = 1 };
            Bind({ action }, { ["$picked"] = { mode = Constants.SWITCH_MODES.MANUAL } });
            check(DebindPrivate.KeyMap["F1"] == nil,
                "an action that names no switch bound anyway");

            action.value = "$picked";
            check(DebindPrivate.UpdateBindings() == true, "the second rebuild declined");
            check(DebindPrivate.KeyMap["F1"],
                "picking a switch was not enough to make the action bind");
        end);

    return T;
end
