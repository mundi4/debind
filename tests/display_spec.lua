-- **What the reader is shown about an action.** No WoW client needed, which it used to be.
--
-- `ActionDisplay.lua` names an action and `ActionTooltip.lua` writes the block that hangs off it,
-- and both were out of reach here for one reason: they are `DebindUI.xml`'s files. Neither needs a
-- frame -- the first resolves a name, the second takes the tooltip as an argument and puts its
-- lines through the client's `GameTooltip_Add…` functions -- so `tests/run.lua` reads them now and
-- the words a reader sees are a value like any other.
--
-- **What is asked here is what the reader ends up looking at**, not which flag was set. The flags
-- have their own coverage (`issue_spec.lua`, `hovertwin_spec.lua`); what those cannot see is a
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
    -- The reader's own condition rows
    ---------------------------------------------------------------------------

    -- **Edited under `Group`, so it is drawn under `Group`.** The value lives in `units.player`,
    -- which would put it under the `Units` label with the units the reader picked by name -- and
    -- then the menu they change it in and the line they read it on are two different places.
    -- `hover` and `"@"` are skipped there for the same reason.
    --
    -- **Its label carries no subject**, so whichever rows it sits between say whose life it is.
    -- Among the reader's own conditions it reads as the reader's; among the units they named it
    -- reads as theirs. That is what fixes the order, in both places, to the same one.
    --- **라벨이 아니라 값의 모양으로 잰다.** `addLabelLine`이 라벨을 서식 문자열에 넣어
    --- 내보내므로 툴팁 텍스트에는 라벨 키가 안 남는다. 대신 `Units` 묶음은 값 앞에
    --- 유닛 이름을 붙이고 제 줄은 안 붙이므로, 그 접두사가 있느냐가 곧 어느 묶음이냐다.
    test("the reader's own life is drawn on its own line, not under Units", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { units = { player = { dead = false } } } },
        }, {});

        local row = DebindPrivate.CollectActionsForKey("F1")[1];
        check(row, "the action is not on the key");
        local text = Tooltip(row);
        check(text:find(LLL["LIFE_ALIVE"], 1, true),
            "the condition is not drawn at all: " .. text);
        check(not text:find(LLL["UNIT_PLAYER"] .. " - ", 1, true),
            "it came out under the Units label: " .. text);
    end);

    -- 순서까지 잰다. 위 테스트는 `Units` 묶음에서 빠졌다는 것만 말하는데, 이 줄의 뜻은
    -- **어느 줄들 사이에 있느냐**로 정해지므로 그것만으로는 모자란다.
    test("the reader's own life is drawn after the group line", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { groups = Constants.GROUP_PARTY,
                    units = { player = { dead = false } } } },
        }, {});

        local text = Tooltip(DebindPrivate.CollectActionsForKey("F1")[1]);
        local groupAt = text:find(LLL["GROUP_PARTY"], 1, true);
        local lifeAt = text:find(LLL["LIFE_ALIVE"], 1, true);
        check(groupAt and lifeAt, "one of the two lines is missing: " .. text);
        check(groupAt < lifeAt, "the life line came out above the group line: " .. text);
    end);

    -- 이름으로 고른 유닛은 그대로 `Units` 아래다. 위 갈래가 그 묶음까지 가져가면 안 된다.
    test("a unit the reader picked by name is still drawn under Units", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { units = { focus = { dead = false } } } },
        }, {});

        local row = DebindPrivate.CollectActionsForKey("F1")[1];
        local text = Tooltip(row);
        check(text:find(LLL["UNIT_FOCUS"] .. " - " .. LLL["LIFE_ALIVE"], 1, true),
            "the named unit lost its own block: " .. text);
    end);

    -- **The condition on the resolved target is drawn under `Units`**, where the menu that edits it
    -- lists it. The `Target` line says which unit was picked and nothing else.
    test("the resolved target's condition is drawn under Units, not on the Target line", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1, unit = "focus",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } },
        }, {});

        local row = DebindPrivate.CollectActionsForKey("F1")[1];
        check(row, "the action is not on the key");
        local text = Tooltip(row);
        local at = text:find(LLL["RESOLVED_TARGET"] .. " - ", 1, true);
        check(at and text:find(LLL["REACTION_HELP"], at, true),
            "the condition is not drawn under the resolved target: " .. text);
        check(not text:find(LLL["UNIT_FOCUS"] .. " - ", 1, true),
            "the Target line still carries a condition: " .. text);
    end);

    -- An action that takes no unit has the row too, so its condition is drawn the same way.
    test("a macro's resolved unit condition is drawn under Units", function()
        Bind({
            { type = Constants.MACROTEXT, value = "/say hi", key = "F1", seq = 1,
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } },
        }, {});

        local text = Tooltip(DebindPrivate.CollectActionsForKey("F1")[1]);
        local at = text:find(LLL["RESOLVED_TARGET"] .. " - ", 1, true);
        check(at and text:find(LLL["REACTION_HELP"], at, true),
            "the condition is not drawn: " .. text);
    end);

    -- `none` has the row as well: it is aimed like an action with no target (2026-09-15, owner).
    test("an Always Ask action's resolved unit condition is drawn under Units", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1, unit = "none",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } },
        }, {});

        local text = Tooltip(DebindPrivate.CollectActionsForKey("F1")[1]);
        local at = text:find(LLL["RESOLVED_TARGET"] .. " - ", 1, true);
        check(at and text:find(LLL["REACTION_HELP"], at, true),
            "the condition is not drawn: " .. text);
    end);

    --- The kind of line one piece of text came out on, so a spec can tell "the reason is written"
    --- from "the reason is written in the colour that says the key is dead".
    local function LineKind(row, text)
        local tooltip = shim.newTooltip();
        DebindPrivate.AddActionToTooltip(tooltip, row.action, {
            offWorld = row.offWorld,
            suppressInactive = true,
        });
        for i = 1, #tooltip.lines do
            if (tooltip.lines[i].text and tooltip.lines[i].text:find(text, 1, true)) then
                return tooltip.lines[i].kind, tooltip.lines[i].color;
            end
        end
    end

    --- **A contradiction belongs to the unit that carries it.** The reader's own life line asks the
    --- same `units` category as the units they picked by name, so an un-narrowed question puts one
    --- unit's contradiction on a line about somebody else -- and the reader goes and edits a
    --- condition that was never wrong.
    test("another unit's contradiction leaves the reader's own life line alone", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { units = { player = { dead = false }, focus = { reaction = 0 } } } },
        }, {});

        local row = DebindPrivate.CollectActionsForKey("F1")[1];
        check(row, "the action is not on the key");
        local kind, color = LineKind(row, LLL["BINDING_ERROR_CONDITIONS_NEVER"]);
        check(kind == "colored" and color == ERROR_COLOR,
            "the unit that carries the contradiction was not reported: " .. Tooltip(row));
        check(LineKind(row, LLL["LIFE_ALIVE"]) == "normal",
            "the reader's own life line was marked for another unit's contradiction");
    end);

    --- **`ignoreHoverUnit` is drawn on an action that has a target of its own.** The line used to
    --- be gated on the action having none, on the grounds that the box only kept a unit out of an
    --- empty slot; it also refuses the account-wide twin (`Misc.lua`'s `TwinUnitFor`), which is a
    --- thing it does exactly for an action that has a target. The reader saw no line on the one
    --- action where the box was the only thing stopping the cast from following the cursor.
    test("the ignore line is drawn on an action that has a target of its own", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1, unit = "focus",
                ignoreHoverUnit = true, conditions = { units = { unitframe = {} } } },
        }, {});

        local row = DebindPrivate.CollectActionsForKey("F1")[1];
        check(row, "the action is not on the key");
        check(Says(row, "LINE_TOOLTIP_IGNORE_HOVER_UNIT"),
            "the box is on and nothing says so: " .. Tooltip(row));
    end);

    --- **The tooltip walks the raw action's condition table**, so it meets the pre-rename key on a
    --- profile the ladder has not reached. Skipping it loses the condition off the screen; drawing
    --- it under its stored name raises instead, because `UNIT_INFO` has no row for it.
    test("a unit frame condition saved under the old name still draws its line", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { units = { hover = {} } } },
        }, {});

        local row = DebindPrivate.CollectActionsForKey("F1")[1];
        check(row, "the action is not on the key");
        check(Says(row, "UNIT_HOVER"),
            "the unit frame line is missing: " .. Tooltip(row));
    end);


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
    -- menu afterwards (§6-C of `devdocs/legacy/redesigning-custom-states.md`).
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

    --- **An icon is a file id or an atlas name, and the `A:` prefix is the only thing telling them
    --- apart.** Handing an atlas to `SetTexture` draws nothing and raises nothing, so a caller that
    --- misses the fork leaves one blank square on one screen and says so nowhere.
    ---
    --- Seven callers draw an action's icon and they all go through `SetActionIcon` now, which is
    --- what makes the convention worth pinning here: with one reader left, the way to break it is to
    --- change what the writers emit, and those two lines sit in the same file.
    local function drawnBy(icon)
        local drawn;
        local texture = {
            SetAtlas = function(_, atlas) drawn = { how = "atlas", value = atlas }; end,
            SetTexture = function(_, tex) drawn = { how = "texture", value = tex }; end,
        };
        DebindPrivate.DebindUI.SetActionIcon(texture, icon);
        return drawn;
    end

    test("an atlas icon is drawn as an atlas, a file id as a texture", function()
        local atlas = drawnBy("A:common-icon-undo");
        check(atlas.how == "atlas", "an A: icon went to SetTexture");
        check(atlas.value == "common-icon-undo", "the A: prefix was not taken off");

        local file = drawnBy(135953);
        check(file.how == "texture", "a file id went to SetAtlas");
        check(file.value == 135953, "the file id was altered on the way");

        -- A nil clears the texture rather than being skipped, which is what makes a row that lost
        -- its action go blank instead of keeping the last one's picture.
        check(drawnBy(nil).how == "texture", "a nil icon did not reach SetTexture");
    end);

    ---------------------------------------------------------------------------
    -- A `known` the rebuild has already settled
    ---------------------------------------------------------------------------

    -- **A binding the rebuild drops has to say why on the row.** A `known` whose answer is settled
    -- false for this rebuild takes the binding out of the key entirely
    -- (`devdocs/baking-the-known-condition.md` §6-1), and with nothing on the row a reader is
    -- looking at a binding that is simply not firing and no word about it.
    --
    -- It takes `noSpell`, the flag that already means "that spell is not there". **It stays with
    -- the live layer's rows in the filter**, which goes by the layer and not by whether a row fires.
    --
    -- The world is stood up before the first rebuild: `Spells` builds its table once.
    test("a known settled false marks the row, and one settled true does not", function()
        for spellID, learned in pairs({ [1000] = true, [1001] = false }) do
            shim.world.spellbook[spellID] = true;
            shim.world.spells[spellID] = { name = "Spell " .. spellID, levelLearned = 10 };
            shim.world.knownSpells[spellID] = learned or nil;
        end

        Bind({
            { type = Constants.SPELL, value = 1001, key = "F1", seq = 1,
                conditions = { known = true } },
            { type = Constants.SPELL, value = 1000, key = "F2", seq = 1,
                conditions = { known = true } },
        }, {});

        local dropped = DebindPrivate.CollectActionsForKey("F1")[1];
        check(dropped.noSpell == true,
            "the settled-false row was not marked: " .. tostring(dropped.noSpell));
        check(not DebindPrivate.IsRowOffSpec(dropped), "it was filed with the inactive layers");

        local held = DebindPrivate.CollectActionsForKey("F2")[1];
        check(held.noSpell == nil,
            "the settled-true row was marked: " .. tostring(held.noSpell));
    end);

    --- The two types with no icon file of their own. **If either stops emitting `A:`**, the fork
    --- above is still correct and the picture is still wrong, so what they emit is asked here.
    test("the two iconless types come back with an atlas", function()
        local _, command = DebindPrivate.DebindUI.NameAndIconForAction(
            { type = Constants.COMMAND, value = "TOGGLEGAMEMENU" });
        check(type(command) == "string" and command:sub(1, 2) == "A:",
            "a binding command's icon is not an atlas: " .. tostring(command));

        local _, unused = DebindPrivate.DebindUI.NameAndIconForAction({ type = Constants.UNUSED });
        check(type(unused) == "string" and unused:sub(1, 2) == "A:",
            "an unused action's icon is not an atlas: " .. tostring(unused));
    end);

    return T;
end
