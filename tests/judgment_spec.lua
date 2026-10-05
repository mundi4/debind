-- **A key's judgment item answers what the press would** (`handing-the-rest-of-a-key-to-the-game.md`
-- 2-2, 2-3, §7). For each case the world is put in every combination of what the item's columns
-- measure, and at each one the item's answer is held against the record the press actually picks
-- (the shipped `EVAL_SNIPPET`, through `EvalClickTimeKey`).
--
-- **And the loop against the item, at the same points.** After a beat the key has to be bound to
-- what the item answers there, which is the loop measuring every column the way the press does:
-- a column it reads differently is a key bound wrong at exactly the points that column decides.
--
-- The cases are shaped after the answer table's rows (§8) and between them reach every kind of
-- column `Judgment.lua` builds, since a column translated wrongly is wrong only where it is asked.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local Judgment = DebindPrivate.Judgment;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    -- `winningRecord` reaches the decision through a DEBUG-only attribute (`eval_spec.lua` says why).
    if (ctx and ctx.shipped) then
        return T;
    end

    --- **Every case under both beats** (`BeatSignal.lua`): the rebuild in the case registers the
    --- driver the answer picks and writes the handler's branch for it, and `Interp:beat` writes what
    --- the driver standing would.
    local function test(name, fn)
        for _, signal in ipairs({ "attribute", "visibility" }) do
            DebindPrivate.BeatSignal.comes = signal == "visibility" or nil;
            local ok, err = pcall(fn);
            if (ok) then
                T.passed = T.passed + 1;
            else
                T.failures[#T.failures + 1] = name .. " (" .. signal .. "): " .. tostring(err);
            end
        end
        DebindPrivate.BeatSignal.comes = nil;
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    local GUID = "Player-1-JUDGMENT";
    local interp;

    -- Registered before the first rebuild, for the reason `eval_spec.lua` gives.
    local groupFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(groupFrame, "group");
    groupFrame:SetAttribute("unit", "party1");
    local bossFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(bossFrame, "boss");
    bossFrame:SetAttribute("unit", "boss1");

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.value = t.value or (t.type == Constants.SPELL and 774 or nil);
        t.key = t.key or "F1";
        t.seq = seq;
        return t;
    end

    --- What the last `Bind` was handed, for a sweep to rebuild on.
    local lastBind;
    local function Bind(actions, switches)
        lastBind = { actions, switches };
        shim.world.spells[585] = { name = "Renew" };
        shim.world.spells[774] = { name = "Rejuvenation" };
        shim.world.bindings = {};
        _G.UnitGUID = function() return GUID; end
        local defined = { ["$s1"] = { mode = Constants.SWITCH_MODES.MANUAL } };
        for name, definition in pairs(switches or {}) do
            defined[name] = definition;
        end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = actions } } },
            characters = { [GUID] = { switches = {} } },
            migrated = {},
            switches = { account = { GENERAL = { [0] = defined } } },
        };
        DebindPrivate.InitDB();
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
    end

    ---------------------------------------------------------------------------
    -- Putting the world on a point
    ---------------------------------------------------------------------------

    local REACTION_OF = {
        [Constants.UNITSTATE_HELP_ALIVE] = { "help", false },
        [Constants.UNITSTATE_HELP_DEAD] = { "help", true },
        [Constants.UNITSTATE_HARM_ALIVE] = { "harm", false },
        [Constants.UNITSTATE_HARM_DEAD] = { "harm", true },
        [Constants.UNITSTATE_OTHER_ALIVE] = { "neutral", false },
        [Constants.UNITSTATE_OTHER_DEAD] = { "neutral", true },
    };

    local GROUP_OF = {
        [Constants.UNITGROUPCELL_NEITHER] = { false, false },
        [Constants.UNITGROUPCELL_PARTY] = { true, false },
        [Constants.UNITGROUPCELL_RAID] = { false, true },
        [Constants.UNITGROUPCELL_BOTH] = { true, true },
    };

    local PLAYER_GROUP = {
        [Constants.GROUP_NONE] = "none",
        [Constants.GROUP_PARTY] = "party",
        [Constants.GROUP_RAID] = "raid",
    };

    local ROLE_OF = {
        [Constants.ROLE_TANK] = "tank",
        [Constants.ROLE_HEALER] = "healer",
        [Constants.ROLE_DAMAGER] = "damager",
    };

    local function Index(bitValue)
        local i = 0;
        while (2 ^ i < bitValue) do
            i = i + 1;
        end
        return i;
    end

    --- The token each alias a case reads points at while its unit is there.
    local ALIAS_TOKEN = { custom1 = "party3", tank = "party4" };

    --- The unit `cells` puts under `unit`, or nil for none. False where the point asks for a group
    --- cell an absent unit cannot be in.
    local function UnitAt(cells, unit)
        local state = cells["unit " .. unit];
        local group = cells["unitgroup " .. unit] or Constants.UNITGROUPCELL_NEITHER;
        if (state == nil or state == Constants.UNITSTATE_NONE) then
            if (group == Constants.UNITGROUPCELL_NEITHER) then
                return nil;
            end
            return false;
        end
        local reaction = REACTION_OF[state];
        return {
            id = unit, reaction = reaction[1], dead = reaction[2],
            inParty = GROUP_OF[group][1], inRaid = GROUP_OF[group][2],
        };
    end

    --- Puts the world on the point `cells` (column key -> cell). False where no world is that point:
    --- two columns that read one thing, or a cell this world has no frame for.
    local function Apply(columns, cells)
        interp:resetState();
        interp:clearHoverSlot();
        interp.env.UnitRoles = false;
        shim.world.units = { player = { id = "me", reaction = "help" } };

        local state = interp.state;
        for _, column in ipairs(columns) do
            local cell, kind, arg = cells[column.key], column.kind, column.arg;
            if (kind == "groups") then
                state.group = PLAYER_GROUP[cell];
            elseif (kind == "forms") then
                state.form = Index(cell);
            elseif (kind == "bonusbars") then
                state.bonusbar = Index(cell);
            elseif (kind == "known") then
                local asked = arg:match("^%[known:(.+)%]$");
                state.known[tonumber(asked) or asked] = cell == Judgment.TRUE;
            elseif (kind == "switch") then
                -- **Through `SetSwitch`**, which is the only way a switch moves in the game and the
                -- wake the loop waits for. A beat does not read a switch set by hand again.
                local value;
                if (cell == Judgment.TRUE) then
                    value = true;
                elseif (cell == Judgment.FALSE) then
                    value = false;
                end
                interp.driverHandle:RunAttribute("SetSwitch", arg, value);
            elseif (kind == "unit") then
                if (arg ~= "unitframe") then
                    local unit = UnitAt(cells, arg);
                    -- The player is never absent, and both sides read it so (`UnitExpression`).
                    if (unit == false or (unit == nil and arg == "player")) then
                        return false;
                    end
                    -- An alias points at a token of its own, or at nothing where it is absent.
                    local token = ALIAS_TOKEN[arg];
                    if (token) then
                        shim.world.units[token] = unit;
                        interp.driverHandle:RunAttribute("SetUnit", arg, unit and token or nil);
                    else
                        shim.world.units[arg] = unit;
                    end
                end
            elseif (kind == "skyriding" or kind == "specialbar" or kind == "petbattle"
                    or kind == "unitgroup" or kind == "role" or kind == "frameType") then
                -- Below, together with what they share a reading with.
            else
                state[kind] = cell == Judgment.TRUE;
            end
        end

        -- `skyriding` is `GetBonusBarOffset() == 5`, and `bonusbars` reads the same call.
        local skyriding = cells.skyriding;
        if (skyriding ~= nil) then
            if (cells.bonusbars ~= nil) then
                if ((state.bonusbar == 5) ~= (skyriding == Judgment.TRUE)) then
                    return false;
                end
            else
                state.bonusbar = skyriding == Judgment.TRUE and 5 or 0;
            end
        end

        -- `specialbar` folds `petbattle` in (`EVAL_SNIPPET`).
        local petbattle = cells.petbattle == Judgment.TRUE;
        state.petbattle = petbattle;
        -- The loop is told, as the events tell it in the game (`SetPetBattle`).
        interp.driverHandle:RunAttribute("SetPetBattle", petbattle);
        if (cells.specialbar ~= nil) then
            local special = cells.specialbar == Judgment.TRUE;
            if (petbattle and not special) then
                return false;
            end
            state.vehiclebar = special and not petbattle;
        end

        local pointed = cells["unit unitframe"];
        local frameType = cells.frameType;
        local role = cells.role;
        if (pointed == nil or pointed == Constants.UNITSTATE_NONE) then
            if ((frameType ~= nil and frameType ~= Judgment.FRAMETYPE_NOFRAME)
                    or (role ~= nil and role ~= Judgment.ROLE_UNMEASURED)) then
                return false;
            end
            if ((cells["unitgroup unitframe"] or Constants.UNITGROUPCELL_NEITHER)
                    ~= Constants.UNITGROUPCELL_NEITHER) then
                return false;
            end
        else
            local frame, token = groupFrame, "party1";
            if (frameType == Constants.FRAMETYPE_BOSS) then
                frame, token = bossFrame, "boss1";
            elseif (frameType ~= nil and frameType ~= Constants.FRAMETYPE_GROUP) then
                return false;
            end
            if (role ~= nil and role ~= Judgment.ROLE_UNMEASURED) then
                if (frame ~= groupFrame) then
                    return false;
                end
                interp.env.UnitRoles = { party1 = ROLE_OF[role] };
            end
            shim.world.units[token] = UnitAt(cells, "unitframe");
            interp:hoverEnter(frame);
        end
        return true;
    end

    ---------------------------------------------------------------------------
    -- The two answers
    ---------------------------------------------------------------------------

    local TIER = {
        ["ALT-F1"] = Constants.CASTMOD_FOCUS,
        ["CTRL-F1"] = Constants.CASTMOD_SELF,
        ["ALT-CTRL-F1"] = Constants.CASTMOD_SELF,
    };

    local function OutcomeName(outcome, command)
        return command and (outcome .. " " .. command) or tostring(outcome);
    end

    --- What the press does with the key in the world as it stands.
    ---
    --- **Run under the button name the key's binding carries, not through the override table.** The
    --- loop lets a key go wherever the item says so, and a press on a key let go reaches nothing of
    --- ours, so asking the client where it lands would answer the loop rather than the press.
    local function Actual(key)
        local base = key:match("([^%-]+)$");
        local tier = TIER[key];
        local button = Constants.CLICKTIME_BUTTON_PREFIX .. base;
        if (tier) then
            button = string.format("%s#%d", button, tier);
        end
        local bindings = interp.env.ClickTimeKeys[button];
        check(bindings, key .. " has no records under " .. button);
        local _, index = interp.driverHandle:RunAttribute("EvalClickTimeKey", button);
        local record = index and bindings[index];
        check(record, key .. ": nothing won, though every tier ends in a block");
        if (record.tail == Constants.UNUSED) then
            return Judgment.RELEASE;
        elseif (record.tail == Constants.COMMAND) then
            return OutcomeName(Judgment.COMMAND, record.command);
        end
        if (tier) then
            local closing = tier == Constants.CASTMOD_SELF and bindings[bindings.focusFrom - 1]
                or bindings[bindings.noneFrom - 1];
            if (record == closing) then
                return Actual(base) == Judgment.OURS and Judgment.OURS or Judgment.RELEASE;
            end
        end
        return Judgment.OURS;
    end

    --- What the key is bound to now, in the item's words.
    local function Bound(key)
        local entry = interp.bindings[key];
        if (not entry) then
            return Judgment.RELEASE;
        elseif (entry.command) then
            return OutcomeName(Judgment.COMMAND, entry.command);
        end
        return Judgment.OURS;
    end

    --- What the key is bound to after a beat.
    local function Looped(key)
        interp:beat();
        return Bound(key);
    end

    local function PointFor(item, cells)
        local point = {};
        for i, column in ipairs(item.columns) do
            point[i] = cells[column.key];
        end
        return point;
    end

    --- What the item answers at the point.
    local function Expected(key, cells)
        local items = DebindPrivate.JudgmentItems;
        local item = items[key];
        local outcome, command = Judgment.Judge(item, PointFor(item, cells));
        if (outcome == Judgment.BASE) then
            local base = items[item.base];
            return Judgment.Judge(base, PointFor(base, cells)) == Judgment.OURS and Judgment.OURS
                or Judgment.RELEASE;
        end
        return OutcomeName(outcome, command);
    end

    local function Cells(all)
        local list, bitValue = {}, 1;
        while (bitValue <= all) do
            if (bit.band(all, bitValue) ~= 0) then
                list[#list + 1] = bitValue;
            end
            bitValue = bitValue * 2;
        end
        return list;
    end

    --- Every point of the columns `key`'s item and its base key's item measure, item against press.
    --- Answers the outcomes the press gave, so a case can say which it expected to see.
    local function Sweep(key)
        local items = DebindPrivate.JudgmentItems;
        local item = items[key];
        check(item, key .. " has no judgment item");
        local columns, seen = {}, {};
        local function take(list)
            for _, column in ipairs(list) do
                if (not seen[column.key]) then
                    seen[column.key] = true;
                    columns[#columns + 1] = column;
                end
            end
        end
        take(item.columns);
        if (item.base) then
            check(items[item.base], key .. "'s base key " .. tostring(item.base) .. " has no item");
            take(items[item.base].columns);
        end

        local outcomes, reached = {}, 0;
        local cells = {};
        local function Hold(how)
            local want, got, looped = Expected(key, cells), Actual(key), Looped(key);
            if (want ~= got or want ~= looped) then
                local parts = {};
                for _, column in ipairs(columns) do
                    parts[#parts + 1] = column.key .. "=" .. cells[column.key];
                end
                error(string.format("%s at {%s}%s: the item says %s, the press %s, the loop %s",
                    key, table.concat(parts, ", "), how, want, got, looped), 0);
            end
            return got;
        end
        --- **Then one column at a time to every other cell, and back** (Q2 of
        --- `implementing-the-cuts-inside-the-beat-handler.md`). Going from point to point moves
        --- several columns at once, and a column whose watch fragment is wrong is covered by another
        --- that moved with it. Every third point is rebuilt on first, so the fragments the pass
        --- writes are held as well as the first point's.
        local function Neighbours()
            if (reached % 3 == 0) then
                Bind(lastBind[1], lastBind[2]);
                Apply(columns, cells);
                Hold(" after a rebuild");
            end
            for _, column in ipairs(columns) do
                local here = cells[column.key];
                for _, cell in ipairs(Cells(column.all)) do
                    if (cell ~= here) then
                        cells[column.key] = cell;
                        if (Apply(columns, cells)) then
                            Hold(", moved to from " .. column.key .. "=" .. here);
                            cells[column.key] = here;
                            Apply(columns, cells);
                            Hold(", back from " .. column.key .. "=" .. cell);
                        end
                        cells[column.key] = here;
                    end
                end
            end
        end
        local function walk(i)
            if (i > #columns) then
                if (Apply(columns, cells)) then
                    reached = reached + 1;
                    outcomes[Hold("")] = true;
                    Neighbours();
                end
                return;
            end
            for _, cell in ipairs(Cells(columns[i].all)) do
                cells[columns[i].key] = cell;
                walk(i + 1);
            end
        end
        walk(1);
        check(reached > 0, key .. ": no point of its columns is a world");
        interp:clearHoverSlot();
        return outcomes;
    end

    --- Each outcome named has to turn up somewhere in the sweep, or the case measured less than it
    --- says: an outcome no point reaches is a hole in the sweep, not a pass.
    local function Saw(outcomes, ...)
        for i = 1, select("#", ...) do
            local name = select(i, ...);
            check(outcomes[name], "no point gave " .. name);
        end
    end

    ---------------------------------------------------------------------------
    -- Cases
    ---------------------------------------------------------------------------

    local MAP = "TOGGLEWORLDMAP";

    test("a key with no tail has no item, nor do its chords", function()
        Bind({ action({ conditions = { combat = true } }) });
        check(next(DebindPrivate.JudgmentItems) == nil, "an item was built");
    end);

    -- **A tier's item is built once however many chords land on it.** With self on CTRL and focus on
    -- ALT, CTRL-F1 and ALT-CTRL-F1 are both the self tier; building it for each is the same box
    -- subtraction twice, for a bundle the emission folds into one anyway.
    test("each tier's item is built once", function()
        local build, calls = Judgment.Build, 0;
        Judgment.Build = function(...)
            calls = calls + 1;
            return build(...);
        end
        local ok, err = pcall(Bind, {
            action({ conditions = { combat = true } }),
            action({ type = Constants.UNUSED }),
        });
        Judgment.Build = build;
        check(ok, tostring(err));
        check(DebindPrivate.JudgmentItems["ALT-CTRL-F1"], "ALT-CTRL-F1 has no item, bad premise");
        check(calls == 3, "built " .. calls .. " items for the bare key and two tiers");
    end);

    test("B1 B2 an unused under a conditional action", function()
        Bind({ action({ conditions = { combat = true } }), action({ type = Constants.UNUSED }) });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
    end);

    test("B3 a command under a conditional action", function()
        Bind({
            action({ conditions = { combat = true } }),
            action({ type = Constants.COMMAND, value = MAP }),
        });
        Saw(Sweep("F1"), Judgment.OURS, OutcomeName(Judgment.COMMAND, MAP));
    end);

    test("B4 B5 a conditional command over an unused", function()
        Bind({
            action({ conditions = { combat = true } }),
            action({ type = Constants.COMMAND, value = MAP, conditions = { mounted = true } }),
            action({ type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE, OutcomeName(Judgment.COMMAND, MAP));
    end);

    test("B6 every tail conditional leaves the key ours", function()
        Bind({
            action({ conditions = { combat = true } }),
            action({ type = Constants.COMMAND, value = MAP, conditions = { mounted = true } }),
            action({ type = Constants.UNUSED, conditions = { stealth = true } }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE, OutcomeName(Judgment.COMMAND, MAP));
    end);

    -- The chords' own items, each "its tier matches, or its base key is ours" (2-3).
    test("B9 to B15 an action on [@ exists] over an unused, with its chords", function()
        Bind({
            action({ conditions = { units = { ["@"] = {} } } }),
            action({ type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
        Saw(Sweep("ALT-F1"), Judgment.OURS, Judgment.RELEASE);
        Saw(Sweep("CTRL-F1"), Judgment.OURS);
        Saw(Sweep("ALT-CTRL-F1"), Judgment.OURS);
    end);

    -- The trap the base half of a chord's item is for: with the target there and no focus, the
    -- focus chord has no winner of its own, and released it would fall to the bare key and cast at
    -- the target.
    test("B10 a focus chord with no focus is held while the bare key is ours", function()
        Bind({
            action({ conditions = { units = { ["@"] = {} } } }),
            action({ type = Constants.UNUSED }),
        });
        local item = DebindPrivate.JudgmentItems["ALT-F1"];
        check(item and item.base == "F1", "ALT-F1 has no item made from F1");
        local columns, cells = {}, {};
        for _, list in ipairs({ item.columns, DebindPrivate.JudgmentItems.F1.columns }) do
            for _, column in ipairs(list) do
                if (not cells[column.key]) then
                    columns[#columns + 1] = column;
                    cells[column.key] = Cells(column.all)[1];
                end
            end
        end
        cells["unit target"] = Constants.UNITSTATE_HELP_ALIVE;
        cells["unit focus"] = Constants.UNITSTATE_NONE;
        cells["unit unitframe"] = Constants.UNITSTATE_NONE;
        cells["unit mouseover"] = Constants.UNITSTATE_NONE;
        check(Expected("ALT-F1", cells) == Judgment.OURS, "the item lets ALT-F1 go");
        check(Apply(columns, cells), "no world for the point");
        check(Actual("ALT-F1") == Judgment.OURS, "the press lets ALT-F1 go");
    end);

    test("M a switch-conditioned unused between a conditional action and a pointed one", function()
        Bind({
            action({ value = 585, conditions = { combat = true } }),
            action({ type = Constants.UNUSED, conditions = { ["$s1"] = true } }),
            action({ casting = { hoverCast = "cast" } }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
        -- The pointed action's focus twin stands on nothing, so the focus chord is never let go.
        Saw(Sweep("ALT-F1"), Judgment.OURS);
    end);

    -- **A tail follows Hover Cast like any action** (`taking-off-out-of-hover-cast.md` §2-1), so at
    -- the usual target it has no pointed twin and the frame's columns land on its original.
    test("a pointed frame's reaction, role and type on a tail", function()
        Bind({
            action({ type = Constants.COMMAND, value = MAP, conditions = { units = { unitframe = {
                reaction = Constants.REACTION_HELP, role = Constants.ROLE_TANK + Constants.ROLE_NONE,
                frameTypes = Constants.FRAMETYPE_GROUP + Constants.FRAMETYPE_BOSS,
            } } } }),
            action({ type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.RELEASE, OutcomeName(Judgment.COMMAND, MAP));
    end);

    -- **The action above the tail takes the pointed press it answers.** With the tail's pointed
    -- twins gathered ahead of every original, they took every press over a unit first and the
    -- action never won one; standing in its own place, the tail comes after it there too. The first
    -- case where the frame's role and type decide for an ordinary action.
    test("a pointed frame's reaction, role and type on the action above an unused", function()
        Bind({
            action({ conditions = { units = { unitframe = {
                reaction = Constants.REACTION_HELP, role = Constants.ROLE_TANK + Constants.ROLE_NONE,
                frameTypes = Constants.FRAMETYPE_GROUP + Constants.FRAMETYPE_BOSS,
            } } } }),
            action({ type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
    end);

    --- Runs `fn` with `kind` measured `by` (`Constants.MEASURED_BY`), put back after.
    local function MeasuredBy(kind, by, fn)
        local was = Constants.MEASURED_BY[kind];
        Constants.MEASURED_BY[kind] = by;
        local ok, err = pcall(fn);
        Constants.MEASURED_BY[kind] = was;
        if (not ok) then
            error(err, 0);
        end
    end

    -- **Each way a kind can be measured is swept**, so moving its row is a change that already has
    -- its test. Several records on the form, one beside another word.
    for _, by in ipairs({ "call", "parse" }) do
        test("forms and the player's group, the forms by " .. by, function()
            MeasuredBy("forms", by, function()
                Bind({
                    action({ conditions = { forms = 2 ^ 0 + 2 ^ 2, groups = Constants.GROUP_PARTY } }),
                    action({ type = Constants.UNUSED }),
                });
                Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
            end);
        end);
        test("several records on the form, the forms by " .. by, function()
            MeasuredBy("forms", by, function()
                Bind({
                    action({ conditions = { forms = 2 ^ 1, combat = true } }),
                    action({ type = Constants.COMMAND, value = MAP, conditions = { forms = 2 ^ 1 + 2 ^ 3 } }),
                    action({ value = 585, conditions = { forms = 2 ^ 0 } }),
                    action({ type = Constants.UNUSED }),
                });
                Saw(Sweep("F1"), Judgment.OURS, OutcomeName(Judgment.COMMAND, MAP), Judgment.RELEASE);
            end);
        end);
    end

    -- **The form is the call's, on both sides** (`Constants.MEASURED_BY`). With the word answering
    -- another form, a loop that still parsed would bind the key to what the press does not do.
    -- Once the two agree again, a quiet beat parses the watch and nothing else: its fragments are
    -- the word's, and one left holding would have every beat measure again.
    test("the press and the loop follow the call where the word says otherwise", function()
        Bind({
            action({ conditions = { forms = 2 ^ 1 } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        check(Actual("F1") == Judgment.RELEASE and Looped("F1") == Judgment.RELEASE,
            "the key was not let go in no form");
        interp.state.form, interp.state.diverge.form = 1, 2;
        local got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.OURS, "the press did not follow the call, it gave " .. got);
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        interp.state.diverge.form = nil;
        interp:beat();
        for n = 1, 2 do
            local before = {};
            for text, count in pairs(interp.parses) do
                before[text] = count;
            end
            interp:beat();
            local parsed = {};
            for text, count in pairs(interp.parses) do
                if (count ~= (before[text] or 0)) then
                    parsed[#parsed + 1] = string.format("%q x%d", text, count - (before[text] or 0));
                end
            end
            check(#parsed == 1 and parsed[1]:find(interp.env.JudgeWatch.text, 1, true) and parsed[1]:sub(-3) == " x1",
                string.format("quiet beat %d after the two agree parsed %s", n, table.concat(parsed, ", ")));
        end
        check(Bound("F1") == Judgment.OURS, "the loop let the key go with nothing moved");
        interp:resetState();
        shim.world.units = {};
    end);

    -- **A form past the last a condition names is no form** (`Constants.MAX_FORM`), to the press and
    -- the loop alike. Without that the loop's cell is a bit no mask holds, and the key falls to the
    -- rest, which here is not what no form answers: the solver puts the second record there.
    test("a form past the last one named is no form to both sides", function()
        Bind({
            action({ conditions = { forms = 2 ^ 0 } }),
            action({ type = Constants.COMMAND, value = MAP, conditions = { combat = false } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        interp.state.form = 2;
        local map = OutcomeName(Judgment.COMMAND, MAP);
        check(Actual("F1") == map and Looped("F1") == map, "the key was not handed to the command in form 2");
        interp.state.form = Constants.MAX_FORM + 1;
        local got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.OURS, "the press read form " .. interp.state.form .. " as a form, it gave " .. got);
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        interp:resetState();
        shim.world.units = {};
    end);

    -- **The press asks the form once, by the call**: a record's `expr` that kept its `form:` token
    -- would ask it twice, the second time at the price the call was chosen to save.
    test("the press does not parse the form", function()
        Bind({
            action({ conditions = { forms = 2 ^ 1, combat = true } }),
            action({ conditions = { forms = 2 ^ 1 + 2 ^ 2 } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        interp.state.form = 2;
        local before = {};
        for text, count in pairs(interp.parses) do
            before[text] = count;
        end
        local got = Actual("F1");
        check(got == Judgment.OURS, "the press gave " .. got);
        for text, count in pairs(interp.parses) do
            check(count == (before[text] or 0) or not text:find("form", 1, true),
                "the press parsed " .. text);
        end
        interp:resetState();
        shim.world.units = {};
    end);

    test("the bars, skyriding and pet battles", function()
        Bind({
            action({ conditions = { bonusbars = 2 ^ 1 + 2 ^ 5, skyriding = false } }),
            action({ type = Constants.COMMAND, value = MAP, conditions = { specialbar = true } }),
            action({ type = Constants.UNUSED, conditions = { petbattle = false } }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE, OutcomeName(Judgment.COMMAND, MAP));
    end);

    test("known and a unit's group", function()
        Bind({
            action({ value = 585, conditions = { known = true,
                units = { ["@"] = { group = Constants.UNITGROUP_PARTY } } } }),
            action({ type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
    end);

    ---------------------------------------------------------------------------
    -- The loop parses what the press parses (`implementing-the-trimmed-tail-key-beat.md` P3)
    ---------------------------------------------------------------------------

    -- **The beat parses what the press parses**, so a word the parse answers otherwise than its API
    -- moves both alike. A beat still measuring the API binds the key to what the press does not do.
    test("the beat follows the parse where the API says otherwise", function()
        Bind({
            action({ conditions = { combat = true, units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ type = Constants.UNUSED }),
        });
        for _, case in ipairs({
            { word = "combat", parse = true, world = { id = "friend", reaction = "help" } },
            { word = "help", parse = true, combat = true, world = { id = "enemy", reaction = "harm" } },
        }) do
            interp:resetState();
            interp:clearHoverSlot();
            shim.world.units = { player = { id = "me", reaction = "help" }, target = case.world };
            interp.state.combat = case.combat or false;
            check(Actual("F1") == Judgment.RELEASE and Looped("F1") == Judgment.RELEASE,
                case.word .. ": the key was not let go before the divergence");
            interp.state.diverge[case.word] = case.parse;
            local got, looped = Actual("F1"), Looped("F1");
            check(got == Judgment.OURS, case.word .. ": the press did not follow the parse");
            check(looped == got, case.word .. ": the press " .. got .. ", the loop " .. looped);
        end
        interp:resetState();
        shim.world.units = {};
    end);

    -- **A unit's cell is one classifying parse** (`ClassifyPieces`). A dead unit is the cell a
    -- classifier gets wrong by asking reaction alone.
    test("two units classified", function()
        Bind({
            action({ conditions = { units = {
                target = { reaction = Constants.REACTION_HELP + Constants.REACTION_HARM, dead = false },
                focus = { dead = true },
            } } }),
            action({ type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
    end);

    -- **An alias's token is put into its classifying text when it moves**, and where it points at
    -- nothing the loop decides it absent without a parse. `custom1` asks `exists` and `tank` does
    -- not, so one of each.
    test("aliases classified", function()
        Bind({
            action({ key = "F1", conditions = { units = { custom1 = { reaction = Constants.REACTION_HELP } } } }),
            action({ key = "F1", type = Constants.UNUSED }),
            action({ key = "F2", conditions = { units = {
                target = { reaction = Constants.REACTION_HARM },
                custom1 = { dead = false },
            } } }),
            action({ key = "F2", type = Constants.UNUSED }),
            action({ key = "F3", conditions = { units = { tank = { dead = false } } } }),
            action({ key = "F3", type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
        Saw(Sweep("F2"), Judgment.OURS, Judgment.RELEASE);
        Saw(Sweep("F3"), Judgment.OURS, Judgment.RELEASE);
    end);

    -- **A map-only alias is there when the map says so**, on both sides, until P3-2 puts `exists`
    -- into both at once. Pointing at a unit the client has no such unit for is the gap.
    test("a map-only alias pointing at no unit is there to both sides", function()
        Bind({
            action({ conditions = { units = { tank = { dead = false } } } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        interp.driverHandle:RunAttribute("SetUnit", "tank", "raid7");
        local got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.OURS, "the press read the alias absent");
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        interp.driverHandle:RunAttribute("SetUnit", "tank", nil);
        shim.world.units = {};
    end);

    -- **A frame laid out again under a cursor that never moved** sends neither enter nor leave
    -- (F3). The beat reads the frame again while pointing and composes the classifying text over.
    test("a frame laid out again under a still cursor", function()
        Bind({
            action({ conditions = { units = { unitframe = { reaction = Constants.REACTION_HELP } } } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        interp:clearHoverSlot();
        shim.world.units = { player = { id = "me", reaction = "help" },
            party1 = { id = "friend", reaction = "help" }, party2 = { id = "enemy", reaction = "harm" } };
        groupFrame:SetAttribute("unit", "party1");
        interp:hoverEnter(groupFrame);
        check(Looped("F1") == Judgment.OURS, "the friendly frame let the key go");
        groupFrame:SetAttribute("unit", "party2");
        local got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.RELEASE, "the press still read the friend");
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        groupFrame:SetAttribute("unit", "party1");
        interp:clearHoverSlot();
        shim.world.units = {};
    end);

    -- **A computed switch beside a state column**: the switch is worked out by the press's own
    -- composition and the column by `StateCellText`, and a word the parse answers otherwise than
    -- its API moves the press and the loop alike.
    test("a computed switch beside a parsed state column", function()
        Bind({
            action({ conditions = { ["$c"] = true, mounted = true } }),
            action({ type = Constants.UNUSED }),
        }, { ["$c"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" } });
        for _, case in ipairs({
            { combat = false, mounted = true, want = Judgment.RELEASE },
            { combat = true, mounted = true, want = Judgment.OURS },
            { combat = true, mounted = false, want = Judgment.RELEASE },
            { combat = true, mounted = false, diverge = true, want = Judgment.OURS },
        }) do
            interp:resetState();
            shim.world.units = { player = { id = "me", reaction = "help" } };
            interp.state.combat, interp.state.mounted = case.combat, case.mounted;
            if (case.diverge) then
                interp.state.diverge.mounted = true;
            end
            local got, looped = Actual("F1"), Looped("F1");
            check(got == case.want, "the press gave " .. got);
            check(looped == got, "the press " .. got .. ", the loop " .. looped);
        end
        interp:resetState();
        shim.world.units = {};
    end);

    -- **A computed switch aimed at the pointed frame, where no column reads the frame**: its text is
    -- composed with the frame's unit, so the loop has to read the frame for it all the same.
    test("a computed switch on the pointed frame", function()
        Bind({
            action({ conditions = { ["$h"] = true } }),
            action({ type = Constants.UNUSED }),
        }, { ["$h"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@unitframe,help]" } });
        interp:resetState();
        interp:clearHoverSlot();
        shim.world.units = { player = { id = "me", reaction = "help" },
            party1 = { id = "friend", reaction = "help" }, party2 = { id = "enemy", reaction = "harm" } };
        for _, case in ipairs({
            { unit = "party1", want = Judgment.OURS },
            { unit = "party2", want = Judgment.RELEASE },
            { unit = "party1", want = Judgment.OURS },
        }) do
            groupFrame:SetAttribute("unit", case.unit);
            interp:hoverEnter(groupFrame);
            local got, looped = Actual("F1"), Looped("F1");
            check(got == case.want, case.unit .. ": the press gave " .. got);
            check(looped == got, case.unit .. ": the press " .. got .. ", the loop " .. looped);
            interp:clearHoverSlot();
        end
        groupFrame:SetAttribute("unit", "party1");
        shim.world.units = {};
    end);

    --- Runs `fn` and answers how many texts the loop composed meanwhile: each composition ends in
    --- one `table.concat` (`COMPOSE_MACROTEXT_SNIPPET`).
    local function Compositions(fn)
        local tableLib = interp.env.table;
        local concat, n = tableLib.concat, 0;
        tableLib.concat = function(...)
            n = n + 1;
            return concat(...);
        end
        local ok, err = pcall(fn);
        tableLib.concat = concat;
        check(ok, tostring(err));
        return n;
    end

    -- **A computed switch's text is composed again only when a switch it reads flips**
    -- (`trimming-the-tail-key-beat.md` 8-6), in the beat that flips it, and once however many of
    -- them flip together.
    test("a computed switch reading two others", function()
        Bind({
            action({ conditions = { ["$c"] = true } }),
            action({ type = Constants.UNUSED }),
        }, {
            ["$a"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" },
            ["$b"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[mounted]" },
            ["$c"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$a,$b]" },
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        check(Looped("F1") == Judgment.RELEASE, "the key was not let go at peace on foot");
        check(Compositions(function()
            for _ = 1, 3 do
                interp:beat();
            end
        end) == 0, "a beat with no state changed composed a text");
        interp.state.combat, interp.state.mounted = true, true;
        local got, looped;
        check(Compositions(function()
            looped = Looped("F1");
        end) == 1, "two switches flipping in one beat did not compose their reader once");
        got = Actual("F1");
        check(got == Judgment.OURS, "the press gave " .. got);
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        interp.state.mounted = false;
        got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.RELEASE, "the press gave " .. got);
        check(looped == got, "on foot again: the press " .. got .. ", the loop " .. looped);
        interp:resetState();
        shim.world.units = {};
    end);

    -- **A switch set by hand or an alias moves a computed switch that reads it on its own wake**,
    -- with no beat between: that wake composes the text again and measures the switch.
    test("a computed switch reading a switch set by hand, and one reading an alias", function()
        Bind({
            action({ key = "F1", conditions = { ["$h"] = true } }),
            action({ key = "F1", type = Constants.UNUSED }),
            action({ key = "F2", conditions = { ["$u"] = true } }),
            action({ key = "F2", type = Constants.UNUSED }),
        }, {
            ["$h"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$s1,mounted]" },
            ["$u"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@custom1,help]" },
        });
        interp:resetState();
        interp.state.mounted = true;
        shim.world.units = { player = { id = "me", reaction = "help" },
            party3 = { id = "friend", reaction = "help" }, party4 = { id = "enemy", reaction = "harm" } };
        local driver = interp.driverHandle;
        driver:RunAttribute("SetSwitch", "$s1", false);
        driver:RunAttribute("SetUnit", "custom1", "party4");
        check(Looped("F1") == Judgment.RELEASE and Bound("F2") == Judgment.RELEASE,
            "the keys were not let go before anything moved");
        for _, case in ipairs({
            { key = "F1", move = function() driver:RunAttribute("SetSwitch", "$s1", true); end, want = Judgment.OURS },
            { key = "F1", move = function() driver:RunAttribute("SetSwitch", "$s1", false); end, want = Judgment.RELEASE },
            { key = "F2", move = function() driver:RunAttribute("SetUnit", "custom1", "party3"); end, want = Judgment.OURS },
            { key = "F2", move = function() driver:RunAttribute("SetUnit", "custom1", "party4"); end, want = Judgment.RELEASE },
        }) do
            case.move();
            local got, bound = Actual(case.key), Bound(case.key);
            check(got == case.want, case.key .. ": the press gave " .. got);
            check(bound == got, case.key .. ": the press " .. got .. ", the wake left " .. bound);
        end
        driver:RunAttribute("SetSwitch", "$s1", nil);
        driver:RunAttribute("SetUnit", "custom1", nil);
        interp:resetState();
        shim.world.units = {};
    end);

    -- **A computed switch with a column of its own moves that column wherever it is worked out**
    -- (`implementing-the-cuts-inside-the-beat-handler.md` Q1). `$t`'s wake works `$s` out first,
    -- since `$t` reads it, and `$s`'s column is not one that wake measures. The next beat then
    -- finds `$s` where the wake left it and has nothing to move.
    test("a computed switch worked out on another one's wake", function()
        Bind({
            action({ key = "F1", conditions = { ["$s"] = true } }),
            action({ key = "F1", type = Constants.UNUSED }),
            action({ key = "F2", conditions = { ["$t"] = true } }),
            action({ key = "F2", type = Constants.UNUSED }),
        }, {
            ["$s"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" },
            ["$t"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$s,$s1]" },
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        local driver = interp.driverHandle;
        driver:RunAttribute("SetSwitch", "$s1", false);
        check(Looped("F1") == Judgment.RELEASE, "the key was not let go at peace");
        interp.state.combat = true;
        driver:RunAttribute("SetSwitch", "$s1", true);
        local got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.OURS, "the press gave " .. got);
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        driver:RunAttribute("SetSwitch", "$s1", nil);
        interp:resetState();
        shim.world.units = {};
    end);

    --- The parses `fn` made, in all and of `expr`.
    local function Parses(fn, expr)
        local function count()
            local all = 0;
            for _, n in pairs(interp.parses) do
                all = all + n;
            end
            return all, interp:parseCount(expr or "");
        end
        local all, of = count();
        fn();
        local allAfter, ofAfter = count();
        return allAfter - all, ofAfter - of;
    end

    -- **A quiet beat parses the watch and nothing else** (Q2 of
    -- `implementing-the-cuts-inside-the-beat-handler.md`). A watch quietly off -- a text that never
    -- holds, or always does -- leaves every answer right and the gain gone, and the sweeps cannot
    -- see that. The profile here is all columns the watch carries, so the watch is all there is to
    -- parse; `specialbar` sits on its "on" cell, whose fragment is the one group of four turned-over
    -- tokens.
    test("a quiet beat parses the watch and nothing else", function()
        Bind({
            action({ conditions = { combat = true, forms = 2 ^ 2, groups = Constants.GROUP_PARTY } }),
            action({ type = Constants.COMMAND, value = MAP, conditions = { specialbar = true, mounted = false } }),
            action({ conditions = { known = "Some Spell" } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        interp.state.vehiclebar, interp.state.form, interp.state.group = true, 2, "party";
        interp:beat();
        interp:beat();
        local function Quiet(when)
            for n = 1, 2 do
                local text = interp.env.JudgeWatch.text;
                check(text, "the watch has no text");
                local all, watch = Parses(function() interp:beat(); end, text);
                check(all == 1 and watch == 1,
                    string.format("%s, quiet beat %d parsed %d texts, the watch %d times", when, n, all, watch));
            end
        end
        Quiet("after the rebuild");
        -- After a beat that moved one column, and one that moved two.
        interp.state.combat = true;
        interp:beat();
        Quiet("after combat moved");
        interp.state.combat, interp.state.form = false, 0;
        interp:beat();
        Quiet("after combat and the form moved");
        interp:resetState();
        shim.world.units = {};
    end);

    -- **Past `WATCH_ROUNDS` columns moved on one beat, every carried column is measured** (Q2b):
    -- one at a time, each costs a parse of the watch, and a fight starting moves several. Seen as
    -- the column that did not move being measured on that beat all the same.
    test("a beat where many columns move measures them all at once", function()
        Bind({
            action({ conditions = { combat = true, mounted = true, stealth = true, indoors = true, flying = true } }),
            action({ type = Constants.COMMAND, value = MAP, conditions = { extrabar = true } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        interp:beat();
        check(Bound("F1") == Judgment.RELEASE, "the key was not let go with nothing held");
        local state = interp.state;
        local _, extrabar = Parses(function()
            state.combat, state.mounted, state.stealth, state.indoors, state.flying = true, true, true, true, true;
            interp:beat();
        end, "[extrabar]");
        check(Bound("F1") == Judgment.OURS, "five columns moved on one beat and the key was not taken");
        check(extrabar == 1, "the column that did not move was measured " .. extrabar .. " times on that beat");
        local got = Actual("F1");
        check(got == Judgment.OURS, "the press gave " .. got);
        interp:resetState();
        shim.world.units = {};
    end);

    -- **A cell's fragment holds exactly where the text no longer answers that cell** (`FragmentsOf`).
    -- The list is made up to reach what no column's own list does yet: a clause of two tokens beside
    -- ones of one token on the same word, so a merge may not take the two-token group in, and
    -- fragments where the same word stands on both `no` sides, which may not merge either.
    --- The second list's clauses never hold two at once, so a cell's fragment is its own clause
    --- turned over and nothing more (Q2c). The third's clauses ask the `no` side, so a fragment holds
    --- two `no` groups of one word, which must stay two.
    local FRAGMENT_LISTS = {
        {
            { groups = { { "form:1", "combat" } }, cell = 2 },
            { groups = { { "form:2" } }, cell = 4 },
            { groups = { { "form:3" } }, cell = 8 },
            default = 1,
        },
        {
            { groups = { { "form:1" } }, cell = 2 },
            { groups = { { "form:2" } }, cell = 4 },
            { groups = { { "form:3" } }, cell = 8 },
            default = 1, exclusive = true,
        },
        {
            { groups = { { "noform:3" } }, cell = 2 },
            { groups = { { "noform:4" } }, cell = 4 },
            { groups = { { "form:1" } }, cell = 8 },
            { groups = { { "form:2" } }, cell = 16 },
            default = 1,
        },
    };
    test("a watch fragment holds exactly where its cell is left", function()
        for _, list in ipairs(FRAGMENT_LISTS) do
        local fragments = DebindPrivate.WatchFragmentsOf(list);
        check(fragments, "the list had no fragments");
        local clauses = {};
        for i, clause in ipairs(list) do
            clauses[i] = "[" .. table.concat(clause.groups[1], ",") .. "] " .. clause.cell;
        end
        local text = table.concat(clauses, "; ") .. "; " .. list.default;
        local parse = interp.env.SecureCmdOptionParse;
        local merged = false;
        for _, fragment in pairs(fragments) do
            merged = merged or fragment:find("/", 1, true) ~= nil;
        end
        check(merged, "no fragment merged a word's groups, so the case asks nothing of the merge");
        for form = 0, 4 do
            for _, combat in ipairs({ false, true }) do
                interp:resetState();
                interp.state.form, interp.state.combat = form, combat;
                local cell = tonumber(parse(text));
                for at, fragment in pairs(fragments) do
                    local holds = fragment ~= "" and parse(fragment) ~= nil;
                    check(holds == (cell ~= at), string.format(
                        "form %d, combat %s, in cell %d: %s %s", form, tostring(combat), at, fragment,
                        holds and "holds" or "does not hold"));
                end
            end
        end
        end
        interp:resetState();
    end);

    -- **A wake that moves a fragment joins the text again**, or every beat after it parses the old
    -- one. `SetPetBattle` moves `specialbar`'s fragment to `""` and back. A text left empty is not
    -- parsed at all: `SecureCmdOptionParse` answers an empty text as holding.
    test("after a wake moves the watch, a quiet beat parses only the new text", function()
        Bind({
            action({ type = Constants.COMMAND, value = MAP, conditions = { specialbar = true } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        local driver = interp.driverHandle;
        local ok, err = pcall(function()
            for _, battle in ipairs({ true, false, true }) do
                interp.state.petbattle = battle;
                driver:RunAttribute("SetPetBattle", battle);
                local text = interp.env.JudgeWatch.text;
                for n = 1, 2 do
                    local all, watch = Parses(function() interp:beat(); end, text or "");
                    if (battle) then
                        check(text == false, "in a battle the watch reads " .. tostring(text));
                        check(all == 0, string.format("battle, quiet beat %d parsed %d texts", n, all));
                    else
                        check(all == 1 and watch == 1, string.format(
                            "out of the battle, quiet beat %d parsed %d texts, the watch %d times", n, all, watch));
                    end
                end
            end
        end);
        driver:RunAttribute("SetPetBattle", false);
        interp:resetState();
        shim.world.units = {};
        check(ok, tostring(err));
    end);

    -- **What the loop worked a computed switch out to does not outlive the rebuild.** A switch made
    -- one set by hand is read through `States` from then on, and a value the loop left under its
    -- name would stand in front of it in every composition.
    test("a computed switch made one set by hand", function()
        local reader = { mode = Constants.SWITCH_MODES.EXPR, expr = "[$m]" };
        local actions = {
            action({ conditions = { ["$a"] = true } }),
            action({ type = Constants.UNUSED }),
        };
        Bind(actions, { ["$m"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat]" }, ["$a"] = reader });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        interp.state.combat = true;
        check(Looped("F1") == Judgment.OURS, "the key was not taken while $m was on");
        Bind(actions, { ["$m"] = { mode = Constants.SWITCH_MODES.MANUAL }, ["$a"] = reader });
        interp.driverHandle:RunAttribute("SetSwitch", "$m", false);
        local got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.RELEASE, "the press gave " .. got);
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        interp.driverHandle:RunAttribute("SetSwitch", "$m", nil);
        interp:resetState();
        shim.world.units = {};
    end);

    -- **A pet battle reaches the loop from its two events** (`trimming-the-tail-key-beat.md` 3-3).
    -- At the first of the two `PET_BATTLE_CLOSE` the client still answers in a battle, so a close is
    -- believed only where the parse already says it is over, and the loop holds the battle as long
    -- as the press does.
    test("a pet battle told by its events", function()
        Bind({
            action({ type = Constants.COMMAND, value = MAP, conditions = { petbattle = true } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" } };
        -- The insecure side's parse answers the battle from the world for this case, so a value
        -- asked at an event would read what the client says there.
        local parse = _G.SecureCmdOptionParse;
        _G.SecureCmdOptionParse = function(expr)
            if (expr == "[petbattle] 1") then
                return interp.state.petbattle and "1" or nil;
            end
            return parse(expr);
        end
        local function Run(fn)
            local mark = frames.mark();
            fn();
            interp:replay(frames.since(mark));
        end
        local function Fire(event)
            Run(function()
                check(frames.fireEvent(event) > 0, "nothing listens for " .. event);
            end);
        end
        local ok, err = pcall(function()
            -- A reload in a battle sends no event: the login asks once.
            interp.state.petbattle = true;
            Run(DebindPrivate.SeedPetBattle);
            check(Bound("F1") == OutcomeName(Judgment.COMMAND, MAP), "the login did not find the battle");
            interp.state.petbattle = false;
            Run(DebindPrivate.SeedPetBattle);
            -- A value written past the events (the kit does), which the seed has to put back.
            interp.driverHandle:RunAttribute("SetPetBattle", true);
            Run(DebindPrivate.SeedPetBattle);
            check(Bound("F1") == Judgment.RELEASE, "the seed left a battle pushed past it standing");
            Fire("PET_BATTLE_CLOSE");
            check(Bound("F1") == Judgment.RELEASE, "the key was not let go out of a battle");

            interp.state.petbattle = true;
            Fire("PET_BATTLE_OPENING_START");
            check(Bound("F1") == OutcomeName(Judgment.COMMAND, MAP), "the battle's start did not hand the key over");
            check(Looped("F1") == Bound("F1"), "a beat in the battle moved the key");

            Fire("PET_BATTLE_CLOSE");
            check(Actual("F1") == OutcomeName(Judgment.COMMAND, MAP), "the press read the first close as the end");
            check(Bound("F1") == Actual("F1"), "the first close took the battle off the loop and not the press");

            interp.state.petbattle = false;
            Fire("PET_BATTLE_CLOSE");
            check(Actual("F1") == Judgment.RELEASE and Looped("F1") == Judgment.RELEASE,
                "the second close left the battle on");

            -- Only a value that moved crosses.
            local mark = frames.mark();
            frames.fireEvent("PET_BATTLE_CLOSE");
            for _, entry in ipairs(frames.since(mark)) do
                check(entry.kind ~= "Execute", "a close that moved nothing crossed");
            end
        end);
        _G.SecureCmdOptionParse = parse;
        interp:resetState();
        shim.world.units = {};
        check(ok, tostring(err));
    end);

    -- **Nothing crosses under lockdown**, so a battle that ends in one is told once it ends.
    test("a pet battle told in a lockdown waits for its end", function()
        Bind({
            action({ type = Constants.COMMAND, value = MAP, conditions = { petbattle = true } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        interp.driverHandle:RunAttribute("SetPetBattle", false);
        shim.world.inCombat = true;
        local mark = frames.mark();
        frames.fireEvent("PET_BATTLE_OPENING_START");
        shim.world.inCombat = false;
        for _, entry in ipairs(frames.since(mark)) do
            check(entry.kind ~= "Execute", "the battle crossed in a lockdown");
        end
        DebindPrivate.FlushPetBattle();
        interp:replay(frames.since(mark));
        check(Bound("F1") == OutcomeName(Judgment.COMMAND, MAP), "the battle was never told");
        mark = frames.mark();
        frames.fireEvent("PET_BATTLE_CLOSE");
        interp:replay(frames.since(mark));
        interp:resetState();
    end);

    -- **The beat has no `[petbattle]` to parse**: the battle is pushed, and `specialbar` reads the
    -- pushed value beside the bars it parses.
    test("the beat parses no pet battle", function()
        local mark = frames.mark();
        Bind({
            action({ conditions = { petbattle = true } }),
            action({ type = Constants.COMMAND, value = MAP, conditions = { specialbar = true } }),
            action({ type = Constants.UNUSED }),
        });
        local seen = false;
        for _, entry in ipairs(frames.since(mark)) do
            if (entry.kind == "SetAttribute" and entry.name == "_onattributechanged" and type(entry.body) == "string") then
                seen = true;
                -- The beat's branch is the handler's first, under either signal, and Keys Given
                -- Back's comes after it.
                local beat = entry.body:match("^if %(name == \"[%w_]+\"%)(.-)if %(name == \"state%-giveback\"%)");
                check(beat, "no beat branch in the handler");
                check(not beat:find("petbattle", 1, true), "the beat parses the pet battle");
            end
        end
        check(seen, "no handler was written");
    end);

    ---------------------------------------------------------------------------
    -- Cell groups and the units' watch (Q3 of `implementing-the-cuts-inside-the-beat-handler.md`)
    ---------------------------------------------------------------------------

    -- **A move between cells no check tells apart moves no cell** (`ColumnGroups`). Only an enemy
    -- alive is asked, so a friend and a neutral are one group: going from one to the other stamps
    -- nothing. Then to an enemy, which does.
    test("a move inside a cell group judges nothing", function()
        Bind({
            action({ conditions = { units = { target = { reaction = Constants.REACTION_HARM, dead = false } } } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" }, target = { id = "t", reaction = "help" } };
        interp:beat();
        local generation = interp.env.JudgeGeneration;
        shim.world.units.target = { id = "t", reaction = "neutral" };
        interp:beat();
        check(interp.env.JudgeGeneration == generation, "a friend to a neutral raised the generation");
        check(Bound("F1") == Actual("F1"), "the press " .. Actual("F1") .. ", the loop " .. Bound("F1"));
        shim.world.units.target = { id = "t", reaction = "harm" };
        interp:beat();
        check(interp.env.JudgeGeneration ~= generation, "an enemy did not raise the generation");
        check(Bound("F1") == Judgment.OURS, "an enemy alive did not take the key");
        shim.world.units = {};
        interp:resetState();
    end);

    -- **A quiet beat parses the watch and nothing else, the units' cells carried in it.** A fixed
    -- unit there and one absent, an alias pointing at a unit.
    test("a quiet beat parses only the watch, units and all", function()
        Bind({
            action({ conditions = { combat = true, units = {
                target = { reaction = Constants.REACTION_HARM, dead = false },
                focus = { dead = true },
            } } }),
            action({ key = "F2", conditions = { units = { custom1 = { reaction = Constants.REACTION_HELP } } } }),
            action({ key = "F2", type = Constants.UNUSED }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = {
            player = { id = "me", reaction = "help" }, target = { id = "t", reaction = "harm" },
            party3 = { id = "p3", reaction = "help" },
        };
        interp.driverHandle:RunAttribute("SetUnit", "custom1", "party3");
        interp:beat();
        for n = 1, 2 do
            local text = interp.env.JudgeWatch.text;
            check(text and text:find("@target", 1, true) and text:find("@party3", 1, true),
                "the watch does not carry the units: " .. tostring(text));
            local all, watch = Parses(function() interp:beat(); end, text);
            check(all == 1 and watch == 1, string.format("quiet beat %d parsed %d texts, the watch %d times", n, all, watch));
        end
        interp.driverHandle:RunAttribute("SetUnit", "custom1", nil);
        shim.world.units = {};
        interp:resetState();
    end);

    -- **After a hit, only the places after it are asked again** (`BuildJudgeSnippet`): every place
    -- before it was false in the same parse. The target sits after the states, so its move ends in
    -- the one parse; a state's move is confirmed by a parse of the target's fragment alone.
    test("a hit is confirmed by the places after it only", function()
        Bind({
            action({ conditions = { combat = true, units = { target = { reaction = Constants.REACTION_HARM, dead = false } } } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = { player = { id = "me", reaction = "help" }, target = { id = "t", reaction = "help" } };
        interp:beat();
        local whole = interp.env.JudgeWatch.text;
        local function Parsed(fn)
            local before = {};
            for text, count in pairs(interp.parses) do
                before[text] = count;
            end
            fn();
            local out = {};
            for text, count in pairs(interp.parses) do
                for _ = 1, count - (before[text] or 0) do
                    out[#out + 1] = text;
                end
            end
            return out;
        end
        local parsed = Parsed(function()
            shim.world.units.target = { id = "t", reaction = "harm" };
            interp:beat();
        end);
        -- The watch, then the target's own cell.
        check(#parsed == 2 and (parsed[1] == whole or parsed[2] == whole),
            "the target's move parsed: " .. table.concat(parsed, " | "));
        whole = interp.env.JudgeWatch.text;
        parsed = Parsed(function()
            interp.state.combat = true;
            interp:beat();
        end);
        local wholes, suffix = 0, 0;
        for _, text in ipairs(parsed) do
            if (text == whole) then
                wholes = wholes + 1;
            elseif (text:sub(1, 8) == "[@target") then
                suffix = suffix + 1;
            end
        end
        check(wholes == 1 and suffix == 1, string.format(
            "combat's move parsed the whole watch %d times and the target's fragment alone %d", wholes, suffix));
        check(Bound("F1") == Actual("F1"), "the press " .. Actual("F1") .. ", the loop " .. Bound("F1"));
        shim.world.units = {};
        interp:resetState();
    end);

    -- **A wake that moves an alias's token writes its place again** though its cell stays: the
    -- fragment was the old token's, which no longer moves. Two enemies alive in turn, then the
    -- second dies with no wake.
    local function TokenMoves()
        Bind({
            action({ conditions = { units = { custom1 = { reaction = Constants.REACTION_HARM, dead = false } } } }),
            action({ type = Constants.UNUSED }),
        });
        interp:resetState();
        shim.world.units = {
            player = { id = "me", reaction = "help" },
            party3 = { id = "p3", reaction = "harm" }, party4 = { id = "p4", reaction = "harm" },
        };
        interp.driverHandle:RunAttribute("SetUnit", "custom1", "party3");
        interp:beat();
        check(Bound("F1") == Judgment.OURS, "an enemy alive did not take the key");
        interp.driverHandle:RunAttribute("SetUnit", "custom1", "party4");
        interp:beat();
        check(Bound("F1") == Judgment.OURS, "the second enemy alive did not hold the key");
        shim.world.units.party4 = { id = "p4", reaction = "harm", dead = true };
        local got, looped = Actual("F1"), Looped("F1");
        check(got == Judgment.RELEASE, "the press did not let the key go, it gave " .. got);
        check(looped == got, "the press " .. got .. ", the loop " .. looped);
        interp.driverHandle:RunAttribute("SetUnit", "custom1", nil);
        shim.world.units = {};
        interp:resetState();
    end
    test("a wake that moves a token writes its place again", TokenMoves);

    -- **The development build parses the units one at a time** (`BuildJudgeSnippet`'s `probesOn`), a
    -- branch no user runs and no other case reaches. Probes on with forms that answer as shipped, so
    -- the same cases have to come out the same.
    test("with probes on, the units are parsed one at a time and answer alike", function()
        local probes = {};
        for name, form in pairs(DebindPrivate.SNIPPET_PROBES_LIVE) do
            probes[name] = form;
        end
        local was = DebindPrivate.SnippetProbes;
        DebindPrivate.SnippetProbes = { expand = probes };
        local ok, err = pcall(function()
            Bind({
                action({ conditions = { combat = true, units = {
                    target = { reaction = Constants.REACTION_HELP + Constants.REACTION_HARM, dead = false },
                    focus = { dead = true },
                    custom1 = { reaction = Constants.REACTION_HELP },
                } } }),
                action({ type = Constants.UNUSED }),
            });
            local handler = interp.driver:GetAttribute("_onattributechanged");
            check(handler and handler:find("PROBE", 1, true) == nil and handler:find("fragment:sub(3)", 1, true),
                "the beat does not parse the units one at a time");
            Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
            TokenMoves();
        end);
        DebindPrivate.SnippetProbes = was;
        if (not ok) then
            error(err, 0);
        end
    end);

    return T;
end
