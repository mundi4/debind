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

    local function Bind(actions, switches)
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

    --- What the key is bound to after a beat, in the item's words.
    local function Looped(key)
        interp:beat();
        local entry = interp.bindings[key];
        if (not entry) then
            return Judgment.RELEASE;
        elseif (entry.command) then
            return OutcomeName(Judgment.COMMAND, entry.command);
        end
        return Judgment.OURS;
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
        local function walk(i)
            if (i > #columns) then
                if (Apply(columns, cells)) then
                    reached = reached + 1;
                    local want, got, looped = Expected(key, cells), Actual(key), Looped(key);
                    if (want ~= got or want ~= looped) then
                        local parts = {};
                        for _, column in ipairs(columns) do
                            parts[#parts + 1] = column.key .. "=" .. cells[column.key];
                        end
                        error(string.format("%s at {%s}: the item says %s, the press %s, the loop %s",
                            key, table.concat(parts, ", "), want, got, looped), 0);
                    end
                    outcomes[got] = true;
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

    test("forms and the player's group", function()
        Bind({
            action({ conditions = { forms = 2 ^ 0 + 2 ^ 2, groups = Constants.GROUP_PARTY } }),
            action({ type = Constants.UNUSED }),
        });
        Saw(Sweep("F1"), Judgment.OURS, Judgment.RELEASE);
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

    -- **No body of the loop measures a state through the API**: it parses its state columns as the
    -- press parses them. `Constants.STATE_EVAL_EXPRESSIONS` is the list of the API forms it may not
    -- take back up.
    test("the loop's bodies measure no state through the API", function()
        local mark = frames.mark();
        Bind({
            action({ conditions = { combat = true, stealth = true, mounted = true,
                indoors = true, flyable = true, advflyable = true, flying = true, skyriding = false,
                specialbar = false, extrabar = false, petbattle = false, forms = 2 ^ 1,
                bonusbars = 2 ^ 2, groups = Constants.GROUP_PARTY } }),
            action({ type = Constants.UNUSED }),
        });
        local bodies = 0;
        for _, entry in ipairs(frames.since(mark)) do
            local name = entry.name;
            if (entry.kind == "SetAttribute" and type(entry.body) == "string" and type(name) == "string"
                    and (name == "JudgePass" or name == "_onattributechanged" or name:sub(1, 6) == "judge-")) then
                bodies = bodies + 1;
                for state, form in pairs(Constants.STATE_EVAL_EXPRESSIONS) do
                    check(not entry.body:find(form, 1, true), name .. " measures " .. state .. " by " .. form);
                end
            end
        end
        check(bodies > 0, "no body of the loop was written");
    end);

    return T;
end
