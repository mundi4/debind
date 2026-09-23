-- The 3.5.2 -> 4.0 run order upgrade, measured against **v3.5.2's own comparator**.
--
-- `legacy/taking-conditions-out-of-the-order.md` §6: the `dbver <= 6` renumber in `MigrateLayer`
-- bakes v3.5.2's order into `seq`, so the new comparator -- which has neither the unit frame step
-- nor the conditional one -- reproduces it. That claim holds for **every** arrangement or it holds
-- for none, and a handful of hand-written cases cannot say which. This file generates the
-- arrangements instead.
--
-- **The oracle is the real v3.5.2 source, frozen under `tests/v3.5.2/`.** Comparing against
-- `Profile.lua`'s own `OlderOrder` would be the migration marking its own paper: that function is
-- the thing under test, and a corpus checked against it goes green on any input. The three files
-- are `Constants.lua`, `Ordering.lua` and `Misc.lua` at the tag, byte for byte, loaded into a
-- private table of their own. `Misc.lua` is in because the old record's two derived fields
-- (`hover`, `isConditional`) come from `GetBindingInfoForAction`, and reading them out of storage
-- instead is what the migration already does.
--
-- **The corpus is in v3.5.2's storage shape, which is not today's.** The pointed frame's unit was
-- `conditions.units.hover` then and `units.unitframe` now, and the rename happens inside the same
-- `dbver <= 6` step, above the renumber. A generator written from the current schema would hand the
-- renumber a name no 3.5.2 profile carries and measure nothing.
--
-- What is deliberately **not** generated: ties in `seq` inside one key group. Both comparators end
-- at `seq` and both sort with an unstable `sort`, so a tie has no defined answer on either side.
-- Stored profiles do not carry one either -- `RenumberKeyGroup` hands out 1..n.

return function(DebindPrivate, _, ctx)
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

    local Constants = DebindPrivate.Constants;
    local MigrateLayer = DebindPrivate.MigrateLayer;

    ---------------------------------------------------------------------------
    -- The frozen oracle
    ---------------------------------------------------------------------------

    --- Loaded through the same `shim.loadAddon` the runner uses, so these files get the two
    --- arguments `local _, DebindPrivate = ...` wants and nothing else is special about them.
    --- They write only into the table handed in; every `_G` they touch is a read.
    ---
    --- **The path comes from `ctx`, never written out here.** `loadAddon` raises in the spec body
    --- rather than inside a `test()`, and the runner does not pcall the chunk, so a path that only
    --- resolves from the repo root takes the whole suite down with a traceback the moment anybody
    --- runs it from anywhere else.
    local shim = require("wow_shim");
    local OLD = shim.loadAddon(ctx.root .. "/v3.5.2", {
        "Constants.lua",
        "Ordering.lua",
        "Misc.lua",
    }, nil, { shipped = false, readFile = ctx.readFile });

    check(type(OLD.CompareActionOrder) == "function", "v3.5.2 비교자를 못 불러왔다");
    check(type(OLD.MakeOrderRecord) == "function", "v3.5.2 레코드를 못 불러왔다");

    ---------------------------------------------------------------------------
    -- The corpus
    ---------------------------------------------------------------------------

    --- Every condition shape that decides one of the two steps being removed, plus the two that
    --- look like conditions and are not. The name is what a failure prints.
    ---
    --- **`units.hover` and not `units.unitframe`.** That is the v3.5.2 spelling; see the header.
    local CONDITIONS = {
        { name = "none", make = function() return nil; end },
        { name = "combat", make = function() return { combat = true }; end },
        { name = "frame", make = function() return { units = { hover = { exists = true } } }; end },
        -- **[when not over a frame] is a unit frame condition too.** The old comparator put what
        -- was not nil ahead, not what was true.
        { name = "frame-off", make = function() return { units = { hover = { exists = false } } }; end },
        -- **Turned off is `off`, not `disabled`.** `disabled` is today's name and the `dbver <= 6`
        -- step is what renames it, above the renumber. Generated as `disabled`, v3.5.2 does not
        -- know the key at all and reads the table as a plain [when one is pointed at] -- so the
        -- corpus asks the oracle about a row no 3.5.2 profile ever held, and the disagreement that
        -- comes back is the generator's, not the migration's.
        { name = "frame-off-switch", make = function() return { units = { hover = { off = true } } }; end },
        -- A row with axes and no marker at all. That is the shape a profile older still carries,
        -- and the same step lifts it to `exists = true`; v3.5.2 read it as [when one is pointed at]
        -- too, so the two have to land in the same band.
        { name = "frame-bare", make = function()
            return { units = { hover = { reaction = Constants.REACTION_HELP } } };
        end },
        { name = "combat+frame", make = function()
            return { combat = true, units = { hover = { exists = true } } };
        end },
        -- A second axis under `units`, so "has any condition" cannot be answered by looking at one
        -- slot.
        { name = "target", make = function() return { units = { target = { exists = true } } }; end },
        { name = "known", make = function() return { known = true }; end },
    };

    local IMPORTANCE = { nil, 1, 2, 3, 5 };
    local KEYS = { "F1", "F2", "CTRL-F1" };

    --- A tiny deterministic generator. `math.random` is the interpreter's and seeding it would
    --- reach into whatever else a run does with it, so the corpus carries its own.
    ---
    --- **The high bits, never `state % n`.** An LCG's low bits have a period of their own -- with
    --- eight condition shapes the bottom three bits cycled and one shape never came out at all.
    --- The shape-coverage test below is what said so.
    local function Rng(seed)
        local state = seed;
        return function(n)
            state = (state * 1103515245 + 12345) % 2147483648;
            return (math.floor(state / 65536) % n) + 1;
        end
    end

    --- One layer in v3.5.2 storage shape. Each action gets a unique `value`, which is how a
    --- failure names it and how the two orders are compared without holding on to table identity
    --- across the migration.
    ---
    --- **`seq` is distinct inside each key group**, handed out by shuffling 1..n. That is what a
    --- stored profile looks like after `RenumberKeyGroup`, and it is what keeps both comparators
    --- total (see the header).
    local function GenerateLayer(rnd, count)
        local groups = {};
        local layer = {};
        for i = 1, count do
            local key = KEYS[rnd(#KEYS)];
            -- An arrival is its own numbering space, so it is part of the group name.
            local arrivalID = (rnd(4) == 1) and 7 or nil;
            local groupName = key .. "\0" .. tostring(arrivalID);
            local group = groups[groupName];
            if (group == nil) then
                group = {};
                groups[groupName] = group;
            end

            local shape = CONDITIONS[rnd(#CONDITIONS)];
            local action = {
                type = Constants.SPELL,
                value = 1000 + i,
                key = key,
                arrivalID = arrivalID,
                priority = IMPORTANCE[rnd(#IMPORTANCE)],
                conditions = shape.make(),
                shapeName = shape.name,
            };
            group[#group + 1] = action;
            layer[#layer + 1] = action;
        end

        -- Shuffle 1..n into each group's `seq`, after the groups are known.
        for _, group in pairs(groups) do
            local numbers = {};
            for j = 1, #group do numbers[j] = j; end
            for j = #numbers, 2, -1 do
                local k = rnd(j);
                numbers[j], numbers[k] = numbers[k], numbers[j];
            end
            for j = 1, #group do
                group[j].seq = numbers[j];
            end
        end

        return layer;
    end

    --- `(key, arrivalID)`, the grouping both the renumber and `RenumberKeyGroup` use.
    local function GroupsOf(layer)
        local names, groups = {}, {};
        for i = 1, #layer do
            local action = layer[i];
            local name = tostring(action.key) .. "\0" .. tostring(action.arrivalID);
            if (groups[name] == nil) then
                groups[name] = {};
                names[#names + 1] = name;
            end
            local group = groups[name];
            group[#group + 1] = { action = action, index = i };
        end
        return names, groups;
    end

    --- The order v3.5.2 drew, per group, as a list of `value`s.
    ---
    --- One layer, so `layerRank` and `specRank` are constants and cannot decide anything -- which
    --- is the premise the renumber rests on (§3-1 of the document).
    local function OldOrders(layer)
        local names, groups = GroupsOf(layer);
        local out = {};
        for _, name in ipairs(names) do
            local group = groups[name];
            local ranked = {};
            for j = 1, #group do
                ranked[j] = {
                    record = OLD.MakeOrderRecord(group[j].action, 1, 0),
                    value = group[j].action.value,
                    index = group[j].index,
                };
            end
            table.sort(ranked, function(lhs, rhs)
                if (OLD.CompareActionOrder(lhs.record, rhs.record)) then return true; end
                if (OLD.CompareActionOrder(rhs.record, lhs.record)) then return false; end
                return lhs.index < rhs.index;
            end);
            local values = {};
            for j = 1, #ranked do values[j] = ranked[j].value; end
            out[name] = values;
        end
        return names, out;
    end

    --- The order this build draws, per group, from the migrated layer.
    local function NewOrders(layer)
        local names, groups = GroupsOf(layer);
        local out = {};
        for _, name in ipairs(names) do
            local group = groups[name];
            local ranked = {};
            for j = 1, #group do
                ranked[j] = {
                    record = DebindPrivate.MakeOrderRecord(group[j].action, 1, 0),
                    value = group[j].action.value,
                    index = group[j].index,
                };
            end
            table.sort(ranked, function(lhs, rhs)
                if (DebindPrivate.CompareActionOrder(lhs.record, rhs.record)) then return true; end
                if (DebindPrivate.CompareActionOrder(rhs.record, lhs.record)) then return false; end
                return lhs.index < rhs.index;
            end);
            local values = {};
            for j = 1, #ranked do values[j] = ranked[j].value; end
            out[name] = values;
        end
        return names, out;
    end

    local function Join(values)
        local parts = {};
        for i = 1, #values do parts[i] = tostring(values[i]); end
        return table.concat(parts, ",");
    end

    --- What each action was, for a failure message. The shape name is put on the action by the
    --- generator and rides through the migration untouched.
    local function Describe(layer)
        local parts = {};
        for i = 1, #layer do
            local a = layer[i];
            parts[i] = string.format("%d[%s %s%s seq=%s pri=%s]", a.value, tostring(a.key),
                a.shapeName, a.arrivalID and " arrival" or "", tostring(a.seq),
                tostring(a.priority));
        end
        return table.concat(parts, " ");
    end

    ---------------------------------------------------------------------------

    local CORPUS_SEEDS = 400;

    --- **The whole of this file.** For every generated layer, what v3.5.2 drew and what this build
    --- draws after the migration are the same list, key group by key group.
    test("the corpus keeps v3.5.2's order through the upgrade", function()
        for seed = 1, CORPUS_SEEDS do
            local rnd = Rng(seed * 7919 + 13);
            local layer = GenerateLayer(rnd, 2 + (seed % 7));
            local before = Describe(layer);

            local names, old = OldOrders(layer);
            MigrateLayer(layer, 6);
            local _, new = NewOrders(layer);

            for _, name in ipairs(names) do
                check(Join(old[name]) == Join(new[name]), string.format(
                    "seed %d, 키 묶음 %q\n  옛 순서: %s\n  새 순서: %s\n  입력: %s",
                    seed, (name:gsub("%z", "/")), Join(old[name]), Join(new[name]), before));
            end
        end
    end);

    --- **A sweep that never disagrees with `seq` is measuring nothing.** If every generated group
    --- already stood in `seq` order under the old comparator, the renumber could be a no-op and the
    --- test above would still pass. This counts the groups where the old order and the stored one
    --- actually part.
    test("the corpus contains groups the renumber has to move", function()
        local moved = 0;
        for seed = 1, CORPUS_SEEDS do
            local rnd = Rng(seed * 7919 + 13);
            local layer = GenerateLayer(rnd, 2 + (seed % 7));
            local names, old = OldOrders(layer);
            local _, groups = GroupsOf(layer);
            for _, name in ipairs(names) do
                local group = groups[name];
                local bySeq = {};
                for j = 1, #group do bySeq[j] = group[j]; end
                table.sort(bySeq, function(lhs, rhs)
                    return (lhs.action.seq or 0) < (rhs.action.seq or 0);
                end);
                for j = 1, #bySeq do
                    if (bySeq[j].action.value ~= old[name][j]) then
                        moved = moved + 1;
                        break;
                    end
                end
            end
        end
        check(moved > 0, "옛 비교자가 저장 순서와 한 번도 안 갈렸다: 코퍼스가 아무것도 안 잰다");
        -- A floor rather than an exact number: the generator may be widened later, and a count
        -- pinned here would go red for a reason that is not a fault.
        check(moved >= 100, "갈리는 묶음이 너무 적다 (" .. moved .. "): 코퍼스가 좁아졌다");
    end);

    --- Every shape in `CONDITIONS` has to actually appear, or one of them is a row nothing reaches
    --- and the sweep is narrower than it reads.
    test("every condition shape appears in the corpus", function()
        local seen = {};
        for seed = 1, CORPUS_SEEDS do
            local rnd = Rng(seed * 7919 + 13);
            local layer = GenerateLayer(rnd, 2 + (seed % 7));
            for i = 1, #layer do
                seen[layer[i].shapeName] = (seen[layer[i].shapeName] or 0) + 1;
            end
        end
        for i = 1, #CONDITIONS do
            check(seen[CONDITIONS[i].name], "코퍼스에 없는 조건 모양: " .. CONDITIONS[i].name);
        end
    end);

    --- §6-1: running it again is a no-op. The second pass counts the same rows in the same order.
    test("the renumber is idempotent across the corpus", function()
        for seed = 1, CORPUS_SEEDS do
            local rnd = Rng(seed * 7919 + 13);
            local layer = GenerateLayer(rnd, 2 + (seed % 7));
            MigrateLayer(layer, 6);
            local first = {};
            for i = 1, #layer do first[i] = layer[i].seq; end
            MigrateLayer(layer, 6);
            for i = 1, #layer do
                check(layer[i].seq == first[i], string.format(
                    "seed %d: %d번 액션의 번호가 두 번째에 움직였다 (%s -> %s)",
                    seed, layer[i].value, tostring(first[i]), tostring(layer[i].seq)));
            end
        end
    end);

    --- Each key group is numbered 1..n on its own. A group numbered inside the layer's whole range
    --- reads the same in every case above -- the order is right and the numbers are not -- and
    --- `RenumberKeyGroup` would fold them on the next edit, so nothing else would ever say so.
    test("every key group is numbered 1..n", function()
        for seed = 1, CORPUS_SEEDS do
            local rnd = Rng(seed * 7919 + 13);
            local layer = GenerateLayer(rnd, 2 + (seed % 7));
            MigrateLayer(layer, 6);
            local names, groups = GroupsOf(layer);
            for _, name in ipairs(names) do
                local group = groups[name];
                local taken = {};
                for j = 1, #group do
                    local seq = group[j].action.seq;
                    check(seq ~= nil and seq >= 1 and seq <= #group, string.format(
                        "seed %d: 번호가 1..%d 밖이다 (%s)", seed, #group, tostring(seq)));
                    check(not taken[seq], string.format(
                        "seed %d: 번호 %s가 두 번 나왔다", seed, tostring(seq)));
                    taken[seq] = true;
                end
            end
        end
    end);

    return T;
end
