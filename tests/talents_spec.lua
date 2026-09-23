-- **The talent condition, from the walk to the key.**
--
-- Two halves. `Talents.Build` and `Talents.Holds` take every client call in one table, so the
-- first half hands them a world of its own and never touches the shim. The second half goes
-- through a real rebuild, because the condition is answered on the insecure side and the binding
-- it turns down is simply not in the key map (`Debind.lua`'s `BuildKeyMap`) -- the same place the
-- specialization condition is answered, and the same reason `specid_spec.lua` reads the key.
--
-- **What this cannot see** is whether the real client fills those fields the way the fake one
-- does. The shapes come from a measurement kept in `DebindDevDB.talentCondition`
-- (`adding-a-talent-condition.md` §6-1), and nothing headless can check them
-- again.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local Talents = DebindPrivate.Talents;
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

    ---------------------------------------------------------------------------
    -- A world of its own
    ---------------------------------------------------------------------------

    --- `world.nodes` is a list of `{ sub =, subActive =, entries = { {id=, name=, taken=}, ... } }`
    --- and `world.pvp` a list of slots, each `{ selected = { id =, name = } }`. Ids and names are
    --- written side by side so a case can say "two ids, one name" without a second table.
    local function API(world)
        local entries, definitions, names = {}, {}, {};
        local nodes, order = {}, {};

        local nextEntry, nextDefinition = 1, 1;
        for i = 1, #(world.nodes or {}) do
            local node = world.nodes[i];
            local all, committed = {}, {};
            for j = 1, #(node.entries or {}) do
                local entry = node.entries[j];
                local entryID, definitionID = nextEntry, nextDefinition;
                nextEntry, nextDefinition = nextEntry + 1, nextDefinition + 1;
                entries[entryID] = { definitionID = definitionID };
                definitions[definitionID] = { spellID = entry.id };
                names[entry.id] = entry.name;
                all[#all + 1] = entryID;
                if (entry.taken) then
                    committed[#committed + 1] = entryID;
                end
            end
            nodes[i] = {
                subTreeID = node.sub,
                subTreeActive = node.subActive,
                entryIDs = all,
                entryIDsWithCommittedRanks = committed,
            };
            order[i] = i;
        end

        local slots = {};
        for i = 1, #(world.pvp or {}) do
            local slot = world.pvp[i];
            slots[i] = { selectedTalentID = slot.selected and slot.selected.id or nil };
            if (slot.selected) then
                names[slot.selected.id] = slot.selected.name;
            end
        end

        return {
            GetActiveConfigID = function() return world.config or 7; end,
            GetConfigInfo = function(configID)
                if (configID ~= (world.config or 7)) then return nil; end
                return { treeIDs = { 1 } };
            end,
            GetTreeNodes = function(treeID) return treeID == 1 and order or nil; end,
            GetNodeInfo = function(_, nodeID) return nodes[nodeID]; end,
            GetEntryInfo = function(_, entryID) return entries[entryID]; end,
            GetDefinitionInfo = function(definitionID) return definitions[definitionID]; end,
            GetPvpTalentSlotInfo = function(slot) return slots[slot]; end,
            GetPvpTalentInfo = function(talentID) return { spellID = talentID }; end,
            GetSpellName = function(spellID) return names[spellID]; end,
        }, function(spellID) return names[spellID]; end;
    end

    --- One index and the name resolver that goes with it.
    local function Index(world)
        local api, GetSpellName = API(world);
        return Talents.Build(api), GetSpellName;
    end

    local SPEC = 102;

    local function Holds(world, entry)
        local index, GetSpellName = Index(world);
        return Talents.Holds({ [SPEC] = entry }, SPEC, index, GetSpellName);
    end

    --- A class-tree node: no hero tree, so whatever it says is live.
    local function Class(entries)
        return { entries = entries };
    end

    test("a talent that is taken satisfies taken", function()
        check(Holds({ nodes = { Class({ { id = 10, name = "Ravage", taken = true } }) } },
            { taken = { 10 } }) == true);
    end);

    test("a talent that is not taken fails taken", function()
        check(Holds({ nodes = { Class({ { id = 10, name = "Ravage" } }) } },
            { taken = { 10 } }) == false);
    end);

    test("every id on the list has to be taken", function()
        local world = { nodes = { Class({
            { id = 10, name = "Ravage", taken = true },
            { id = 11, name = "Thorns" },
        }) } };
        check(Holds(world, { taken = { 10, 11 } }) == false);
        check(Holds(world, { taken = { 10 } }) == true);
    end);

    test("notTaken fails on a talent that is taken", function()
        local world = { nodes = { Class({ { id = 10, name = "Ravage", taken = true } }) } };
        check(Holds(world, { notTaken = { 10 } }) == false);
    end);

    test("notTaken holds on a talent that is not taken", function()
        local world = { nodes = { Class({ { id = 10, name = "Ravage" } }) } };
        check(Holds(world, { notTaken = { 10 } }) == true);
    end);

    -- **The whole reason the index is keyed by name** (§3): a talent has an id per specialization
    -- and the reader sees one name.
    test("a different id under the same name matches", function()
        local world = { nodes = { Class({ { id = 10, name = "Ravage", taken = true } }) } };
        -- 99 is that talent's other-specialization id, which this world names the same.
        world.nodes[1].entries[2] = { id = 99, name = "Ravage" };
        check(Holds(world, { taken = { 99 } }) == true);
    end);

    test("an id the client cannot name fails taken and passes notTaken", function()
        local world = { nodes = { Class({ { id = 10, name = "Ravage", taken = true } }) } };
        check(Holds(world, { taken = { 4242 } }) == false);
        check(Holds(world, { notTaken = { 4242 } }) == true);
    end);

    -- **The wire types the condition and stops there.** `ConditionAllowed` checks that `talents`
    -- is a table, the way it does for `specs` and `units`; those two are read by indexing and this
    -- one is walked, so a hand-made string reaches the rebuild with a number where a list belongs.
    -- `#` on one raises, and the rebuild has already wiped the key map by then.
    test("an entry that is not a pair of lists is survivable", function()
        local world = { nodes = { Class({ { id = 10, name = "Ravage", taken = true } }) } };
        local index, GetSpellName = Index(world);

        local function Answer(talents)
            local ok, held = pcall(Talents.Holds, talents, SPEC, index, GetSpellName);
            check(ok, "it raised: " .. tostring(held));
            return held;
        end

        check(Answer({ [SPEC] = { taken = 5 } }) == true);
        check(Answer({ [SPEC] = { taken = "x", notTaken = 7 } }) == true);
        check(Answer({ [SPEC] = 5 }) == true);
        check(Answer({ [SPEC] = { taken = { 10 }, notTaken = "x" } }) == true);
    end);

    test("a list holding something that is not a number is skipped", function()
        local world = { nodes = { Class({ { id = 10, name = "Ravage", taken = true } }) } };
        check(Holds(world, { taken = { "x", 10 } }) == true);
        check(Holds(world, { notTaken = { "x" } }) == true);
    end);

    ---------------------------------------------------------------------------
    -- The hero tree that is not in play
    ---------------------------------------------------------------------------

    --- Ranks stay bought in the tree the character left, so the dead tree answers committed too.
    --- That is measured, not invented (§6-2).
    local function TwoHeroTrees()
        return { nodes = {
            Class({ { id = 10, name = "Ravage", taken = true } }),
            { sub = 24, subActive = true, entries = {
                { id = 20, name = "Lunar Calling", taken = true },
            } },
            { sub = 23, entries = {
                { id = 30, name = "Dream Surge", taken = true },
            } },
        } };
    end

    test("a talent of the live hero tree is taken", function()
        check(Holds(TwoHeroTrees(), { taken = { 20 } }) == true);
    end);

    test("a committed talent of the dead hero tree is not read as taken", function()
        check(Holds(TwoHeroTrees(), { notTaken = { 30 } }) == true);
    end);

    -- **A talent of the tree that is not running is not taken.** Which is what makes "while I am
    -- in that hero tree" writable at all: the talent that says so is one of its own
    -- (2026-09-19, owner).
    test("a talent of the dead hero tree fails taken", function()
        check(Holds(TwoHeroTrees(), { taken = { 30 } }) == false);
        check(Holds(TwoHeroTrees(), { taken = { 10, 30 } }) == false);
    end);

    test("switching hero tree flips both of them", function()
        local live24 = TwoHeroTrees();
        check(Holds(live24, { taken = { 20 } }) == true);
        check(Holds(live24, { taken = { 30 } }) == false);

        local live23 = TwoHeroTrees();
        live23.nodes[2].subActive = nil;
        live23.nodes[3].subActive = true;
        check(Holds(live23, { taken = { 20 } }) == false);
        check(Holds(live23, { taken = { 30 } }) == true);
    end);

    -- The two are exclusive, so a product over both can never be true. That is the cost of the
    -- rule above and it is the intended one: the reader who wants a key in both builds writes two
    -- actions, which is what §2 says about union.
    test("a condition naming both hero trees is never true", function()
        check(Holds(TwoHeroTrees(), { taken = { 20, 30 } }) == false);
    end);

    -- **And it is reported rather than left to fail quietly.** Both rows look reachable in the
    -- menu, so a key that simply never fires says nothing about why.
    test("naming both hero trees is a contradiction", function()
        local index, GetSpellName = Index(TwoHeroTrees());
        check(Talents.HeroTreesConflict({ taken = { 20, 30 } }, index, GetSpellName) == true);
        check(Talents.HeroTreesConflict({ taken = { 20 } }, index, GetSpellName) == false);
        check(Talents.HeroTreesConflict({ taken = { 20, 10 } }, index, GetSpellName) == false);
    end);

    -- Both unpicked is an ordinary state: one tree runs and neither of those two is bought.
    test("naming both hero trees on notTaken is not a contradiction", function()
        local index, GetSpellName = Index(TwoHeroTrees());
        check(Talents.HeroTreesConflict({ notTaken = { 20, 30 } }, index, GetSpellName) == false);
    end);

    test("the contradiction check survives an entry that is not a pair of lists", function()
        local index, GetSpellName = Index(TwoHeroTrees());
        local ok, conflict = pcall(Talents.HeroTreesConflict, { taken = 5 }, index, GetSpellName);
        check(ok, "it raised: " .. tostring(conflict));
        check(conflict == false);
    end);

    ---------------------------------------------------------------------------
    -- PvP
    ---------------------------------------------------------------------------

    test("the talent a pvp slot holds is taken", function()
        local world = { nodes = {}, pvp = { { selected = { id = 50, name = "Thorns" } } } };
        check(Holds(world, { taken = { 50 } }) == true);
        check(Holds(world, { notTaken = { 50 } }) == false);
    end);

    test("an empty pvp slot takes nothing", function()
        local world = { nodes = { Class({ { id = 50, name = "Thorns" } }) }, pvp = { {} } };
        check(Holds(world, { taken = { 50 } }) == false);
    end);

    ---------------------------------------------------------------------------
    -- The specialization key
    ---------------------------------------------------------------------------

    test("no key for this specialization is true", function()
        local index, GetSpellName = Index({ nodes = {} });
        check(Talents.Holds({ [999] = { taken = { 10 } } }, SPEC, index, GetSpellName) == true);
    end);

    test("no condition at all is true", function()
        local index, GetSpellName = Index({ nodes = {} });
        check(Talents.Holds(nil, SPEC, index, GetSpellName) == true);
    end);

    test("an empty entry is true", function()
        local index, GetSpellName = Index({ nodes = {} });
        check(Talents.Holds({ [SPEC] = {} }, SPEC, index, GetSpellName) == true);
    end);

    ---------------------------------------------------------------------------
    -- Through a rebuild, onto the key
    ---------------------------------------------------------------------------

    local ME = "Player-1-TALENTCOND";

    --- The shim's world, holding one class-tree talent and one taken.
    local function SetWorld()
        shim.world.spells[700] = { name = "Ravage", iconID = 1 };
        shim.world.spells[701] = { name = "Thorns", iconID = 1 };
        shim.world.spells[585] = { name = "Smite", iconID = 1 };
        shim.world.traits = {
            configID = 7,
            treeIDs = { 1 },
            trees = { [1] = { 1, 2 } },
            nodes = {
                -- `isVisible` is what makes a node this specialization's, so the menu walk needs
                -- it even where the judgment does not (`Talents.BuildMenu`).
                [1] = { entryIDs = { 11 }, entryIDsWithCommittedRanks = { 11 }, isVisible = true },
                [2] = { entryIDs = { 12 }, entryIDsWithCommittedRanks = {}, isVisible = true },
            },
            entries = { [11] = { definitionID = 21 }, [12] = { definitionID = 22 } },
            definitions = { [21] = { spellID = 700 }, [22] = { spellID = 701 } },
            -- The class panel's currency first, the specialization's second.
            currencies = { { traitCurrencyID = 1 }, { traitCurrencyID = 2 } },
            costs = { [1] = { { ID = 1 } }, [2] = { { ID = 2 } } },
        };
    end

    local function Bind(actions)
        _G.UnitGUID = function() return ME; end
        SetWorld();
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    local function Values(key)
        local records = require("castmod").without(Constants, DebindPrivate.KeyMap[key]);
        if (not records) then return "<none>"; end
        local out = {};
        for i = 1, #records do out[i] = tostring(records[i].value); end
        return table.concat(out, " ");
    end

    --- The specialization this character is standing in, as the condition addresses it.
    local function MySpec()
        return DebindPrivate.SpecIDForIndex(_G.C_SpecializationInfo.GetSpecialization());
    end

    test("a satisfied talent condition reaches the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = { [MySpec()] = { taken = { 700 } } } } },
        });
        check(Values("F1") == "585", "the key came out with " .. Values("F1"));
    end);

    test("an unsatisfied talent condition keeps the action off the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = { [MySpec()] = { taken = { 701 } } } } },
        });
        check(Values("F1") == "<none>", "the key came out with " .. Values("F1"));
    end);

    -- **The key is held all the same.** Every filter under that line in `BuildKeyMap` is the
    -- rebuild settling an answer early, and an answer settled early must not hand the key back to
    -- the game.
    test("the key stays ours even where the condition is false", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = { [MySpec()] = { taken = { 701 } } } } },
        });
        check(DebindPrivate.KeysToHold["F1"] == true, "the key was handed back");
    end);

    -- The action below it takes the key, which is the whole point of answering this early.
    test("the action below takes the key", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = { [MySpec()] = { taken = { 701 } } } } },
            { type = Constants.SPELL, value = 700, key = "F1", seq = 2 },
        });
        check(Values("F1") == "700", "the key came out with " .. Values("F1"));
    end);

    --- The first action `Bind` put in General, as it is stored.
    local function FirstStoredAction()
        local layer = DebindPrivate.GetProfileLayer(DebindPrivate.GetLayerID(nil, false));
        check(layer, "there is no General layer");
        for _, action in layer:Enumerate() do
            return action;
        end
    end

    -- **An empty list is not a condition.** Left in the profile it is a specialization key saying
    -- nothing, which reads as a talent condition on every screen that gates on the table being
    -- there (`IsConditionalBinding`), and it moves the firing order.
    test("a specialization entry with nothing in it is swept", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = { [MySpec()] = { taken = {}, notTaken = {} } } } },
        });
        local stored = FirstStoredAction();
        check(stored, "the action is not in the layer");
        check(stored.conditions == nil,
            "the action is still conditional: " .. tostring(stored.conditions));
    end);

    test("a talents table with no specialization in it is swept", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = {} } },
        });
        local stored = FirstStoredAction();
        check(stored.conditions == nil,
            "the action is still conditional: " .. tostring(stored.conditions));
    end);

    test("an empty entry beside a real one leaves the real one", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = {
                    [MySpec()] = { taken = { 700 } },
                    [999] = { taken = {} },
                } } },
        });
        local stored = FirstStoredAction();
        local talents = stored.conditions and stored.conditions.talents;
        check(talents ~= nil, "the whole condition went");
        check(talents[MySpec()] ~= nil, "the live entry went");
        check(talents[999] == nil, "the empty entry stayed");
    end);

    --- The world `Bind` sets up, plus a second hero tree with one talent in each, so an action can
    --- name both. 23 is the live one.
    local function SetHeroWorld()
        shim.world.spells[800] = { name = "Lunar Calling", iconID = 1 };
        shim.world.spells[801] = { name = "Dream Surge", iconID = 1 };
        local traits = shim.world.traits;
        traits.trees[1] = { 1, 2, 3, 4 };
        traits.nodes[3] = { entryIDs = { 13 }, entryIDsWithCommittedRanks = { 13 },
            isVisible = true, subTreeID = 23, subTreeActive = true };
        traits.nodes[4] = { entryIDs = { 14 }, entryIDsWithCommittedRanks = { 14 },
            isVisible = true, subTreeID = 24 };
        traits.entries[13] = { definitionID = 23 };
        traits.entries[14] = { definitionID = 24 };
        traits.definitions[23] = { spellID = 800 };
        traits.definitions[24] = { spellID = 801 };
        traits.costs[3] = { { ID = 3 } };
        traits.costs[4] = { { ID = 4 } };
    end

    -- **The key is not left to die quietly.** The action is reported, the gate keeps it out of the
    -- key map, and what fills the key then is the block every emptied key gets.
    test("an action naming both hero trees is reported and off the key", function()
        _G.UnitGUID = function() return ME; end
        SetWorld();
        SetHeroWorld();
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {
                { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                    conditions = { talents = { [MySpec()] = { taken = { 800, 801 } } } } },
            }, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");

        local stored = FirstStoredAction();
        check(DebindPrivate.GetBindingIssue(stored, "talents")
            == Constants.BINDING_ISSUE_CONDITIONS_NEVER,
            "it was not reported: " .. tostring(DebindPrivate.GetBindingIssue(stored, "talents")));
        check(Values("F1") == "<none>", "the key came out with " .. Values("F1"));
    end);

    test("one hero tree alone is not reported", function()
        _G.UnitGUID = function() return ME; end
        SetWorld();
        SetHeroWorld();
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {
                { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                    conditions = { talents = { [MySpec()] = { taken = { 800 } } } } },
            }, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");

        local stored = FirstStoredAction();
        check(DebindPrivate.GetBindingIssue(stored, "talents") == nil,
            "it was reported anyway: "
                .. tostring(DebindPrivate.GetBindingIssue(stored, "talents")));
        check(Values("F1") == "585", "the key came out with " .. Values("F1"));
    end);

    test("an action with no talent condition is untouched", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1 },
        });
        check(Values("F1") == "585", "the key came out with " .. Values("F1"));
    end);

    -- The condition is measured once per key map build, so a walk kept from the last one would
    -- answer for talents the reader has since changed.
    test("changing a talent changes the answer on the next rebuild", function()
        Bind({
            { type = Constants.SPELL, value = 585, key = "F1", seq = 1,
                conditions = { talents = { [MySpec()] = { taken = { 701 } } } } },
        });
        check(Values("F1") == "<none>", "the key came out with " .. Values("F1"));

        shim.world.traits.nodes[2].entryIDsWithCommittedRanks = { 12 };
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        check(Values("F1") == "585", "the key came out with " .. Values("F1"));
    end);

    ---------------------------------------------------------------------------
    -- The lists the menu offers
    ---------------------------------------------------------------------------

    --- A world the menu walk reads: `nodes` is a list of
    --- `{ currency =, sub =, vis =, groups = { groupID… }, entries = { {id=,name=}, ... } }`.
    local function MenuAPI(world)
        local entries, definitions, names = {}, {}, {};
        local nodes, order, costs = {}, {}, {};
        local nextEntry = 1;
        for i = 1, #world.nodes do
            local node = world.nodes[i];
            local ids = {};
            for j = 1, #node.entries do
                local entry = node.entries[j];
                entries[nextEntry] = { definitionID = nextEntry };
                definitions[nextEntry] = { spellID = entry.id };
                names[entry.id] = entry.name;
                ids[#ids + 1] = nextEntry;
                nextEntry = nextEntry + 1;
            end
            nodes[i] = {
                subTreeID = node.sub,
                isVisible = node.vis ~= false,
                entryIDs = ids,
                groupIDs = node.groups or {},
            };
            costs[i] = { { ID = node.currency or 1 } };
            order[i] = i;
        end

        return {
            className = "Druid",
            specName = "Balance",
            pvpName = "PvP Talents",
            GetActiveConfigID = function() return 7; end,
            GetConfigInfo = function() return { treeIDs = { 1 } }; end,
            GetTreeCurrencyInfo = function()
                return world.currencies or { { traitCurrencyID = 1 }, { traitCurrencyID = 2 } };
            end,
            --- Camelot's call only: `world.groups` is its answer, a list of
            --- `{ groupID =, displayName =, orderIndex = }`.
            GetGroupDisplayInfoByTreeID = world.groups and function() return world.groups; end,
            GetTreeNodes = function() return order; end,
            GetNodeInfo = function(_, nodeID) return nodes[nodeID]; end,
            GetNodeCost = function(_, nodeID) return costs[nodeID]; end,
            GetEntryInfo = function(_, entryID) return entries[entryID]; end,
            GetDefinitionInfo = function(definitionID) return definitions[definitionID]; end,
            GetSubTreeInfo = function(_, subTreeID)
                return { name = "Tree" .. subTreeID };
            end,
            GetHeroTalentSpecs = function() return world.heroSpecs; end,
            GetPvpTalentSlotInfo = function(slot)
                if (slot ~= 1) then return nil; end
                return { availableTalentIDs = world.pvp };
            end,
            GetPvpTalentInfo = function(talentID) return { spellID = talentID }; end,
            GetSpellName = function(spellID) return names[spellID] or world.pvpNames[spellID]; end,
        };
    end

    local function Menu(world)
        world.pvpNames = world.pvpNames or {};
        local groups = Talents.BuildMenu(MenuAPI(world));
        local byKey = {};
        for i = 1, #groups do
            local key = groups[i].key;
            if (key == "hero") then
                key = "hero" .. groups[i].subTreeID;
            end
            byKey[key] = groups[i];
        end
        return groups, byKey;
    end

    local function Names(group)
        local out = {};
        for i = 1, #(group and group.rows or {}) do
            out[i] = group.rows[i].name;
        end
        return table.concat(out, ",");
    end

    test("the currency splits the class tree from the specialization tree", function()
        local _, byKey = Menu({ nodes = {
            { currency = 1, entries = { { id = 1, name = "Thick Hide" } } },
            { currency = 2, entries = { { id = 2, name = "Starfire" } } },
        } });
        check(Names(byKey.class) == "Thick Hide", "class: " .. Names(byKey.class));
        check(Names(byKey.spec) == "Starfire", "spec: " .. Names(byKey.spec));
    end);

    -- **Camelot's tree is one currency and three named groups**, the classic talent trees (a druid
    -- on 69977: 3820 for all 51 nodes; Balance, Feral Combat, Restoration). A node also sits in
    -- groups with no display info, which are not trees. Split by currency, every node is the
    -- class's and the specialization's list is empty.
    test("where the tree comes in named groups, each group is a list", function()
        local groups = Talents.BuildMenu(MenuAPI({
            currencies = { { traitCurrencyID = 3820 } },
            groups = {
                { groupID = 11340, displayName = "Restoration", orderIndex = 2 },
                { groupID = 11328, displayName = "Balance", orderIndex = 0 },
                { groupID = 11347, displayName = "Feral Combat", orderIndex = 1 },
            },
            nodes = {
                { currency = 3820, groups = { 11328, 12704 }, entries = { { id = 1, name = "Moonfury" } } },
                { currency = 3820, groups = { 12705, 11347 }, entries = { { id = 2, name = "Ferocity" } } },
                { currency = 3820, groups = { 11340 }, entries = { { id = 3, name = "Furor" } } },
                { currency = 3820, groups = { 11328 }, entries = { { id = 4, name = "Starlight Wrath" } } },
            },
        }));
        local seen = {};
        for i = 1, #groups do
            if (groups[i].key ~= "pvp") then
                seen[#seen + 1] = tostring(groups[i].name) .. "=" .. Names(groups[i]);
            end
        end
        local got = table.concat(seen, " ");
        check(got == "Balance=Moonfury,Starlight Wrath Feral Combat=Ferocity Restoration=Furor",
            "lists: " .. got);
    end);

    -- A node another specialization owns is in the same tree and has to stay out of these lists
    -- (§6-1).
    test("a node this specialization cannot see is left out", function()
        local _, byKey = Menu({ nodes = {
            { currency = 2, entries = { { id = 1, name = "Starfire" } } },
            { currency = 2, vis = false, entries = { { id = 2, name = "Rip" } } },
        } });
        check(Names(byKey.spec) == "Starfire", "spec: " .. Names(byKey.spec));
    end);

    -- **The talent window's order, not the id's.** A reader with both windows open is reading one
    -- list, and the ids do not run in the order the two trees are drawn.
    test("the hero trees come out in the client's order", function()
        local groups = Talents.BuildMenu(MenuAPI({
            nodes = {
                { currency = 2, sub = 23, entries = { { id = 1, name = "Dream Surge" } } },
                { currency = 2, sub = 24, entries = { { id = 2, name = "Lunar Calling" } } },
            },
            heroSpecs = { 24, 23 },
        }));
        local order = {};
        for i = 1, #groups do
            if (groups[i].key == "hero") then
                order[#order + 1] = groups[i].subTreeID;
            end
        end
        check(order[1] == 24 and order[2] == 23,
            "drawn as " .. tostring(order[1]) .. ", " .. tostring(order[2]));
    end);

    test("each hero tree is its own list, named by the client", function()
        local _, byKey = Menu({ nodes = {
            { currency = 2, sub = 24, entries = { { id = 1, name = "Lunar Calling" } } },
            { currency = 2, sub = 23, entries = { { id = 2, name = "Dream Surge" } } },
        } });
        check(Names(byKey.hero24) == "Lunar Calling", "24: " .. Names(byKey.hero24));
        check(Names(byKey.hero23) == "Dream Surge", "23: " .. Names(byKey.hero23));
        check(byKey.hero23.name == "Tree23", "the tree is named " .. tostring(byKey.hero23.name));
    end);

    -- **Both of them, live or not.** The reader writes the condition for the build they are going
    -- to play, which is not always the one they are standing in (§6-2).
    test("the hero tree that is not in play is offered too", function()
        local _, byKey = Menu({ nodes = {
            { currency = 2, sub = 23, entries = { { id = 2, name = "Dream Surge" } } },
        } });
        check(byKey.hero23 ~= nil, "the dead tree has no list");
    end);

    test("one name is one row", function()
        local _, byKey = Menu({ nodes = {
            { currency = 1, entries = { { id = 1, name = "Ravage" } } },
            { currency = 1, entries = { { id = 2, name = "Ravage" } } },
        } });
        check(Names(byKey.class) == "Ravage", "class: " .. Names(byKey.class));
    end);

    test("the pvp list comes off one slot", function()
        local world = { nodes = {}, pvp = { 90, 91 }, pvpNames = { [90] = "Thorns", [91] = "Overrun" } };
        local _, byKey = Menu(world);
        check(Names(byKey.pvp) == "Overrun,Thorns", "pvp: " .. Names(byKey.pvp));
    end);

    ---------------------------------------------------------------------------
    -- Writing one row
    ---------------------------------------------------------------------------

    local ActionMenu = DebindPrivate.ActionMenu;

    local function Ctx(...)
        return { actions = { ... } };
    end

    test("a row writes taken, then not taken, then clears", function()
        local action = { type = Constants.SPELL, value = 585 };
        local ctx = Ctx(action);
        local specs = { 102 };

        ActionMenu.SetTalentCondition(ctx, specs, 700, "taken");
        check(ActionMenu.TalentConditionIs(ctx, specs, 700, "taken"), "not taken after writing it");
        check(action.conditions.talents[102].taken[1] == 700, "the id is not on the list");

        ActionMenu.SetTalentCondition(ctx, specs, 700, "notTaken");
        check(ActionMenu.TalentConditionIs(ctx, specs, 700, "notTaken"), "the second write missed");
        check(#action.conditions.talents[102].taken == 0, "it is on both lists");

        ActionMenu.SetTalentCondition(ctx, specs, 700, nil);
        check(action.conditions == nil,
            "clearing the last row left " .. tostring(action.conditions));
    end);

    -- **The class tree is every specialization's** (§2). A tick that landed on one alone would read
    -- as untouched from the other three, and the condition would quietly say nothing there.
    test("a class-tree row writes every specialization it is handed", function()
        local action = { type = Constants.SPELL, value = 585 };
        local ctx = Ctx(action);
        local specs = { 102, 103, 104, 105 };

        ActionMenu.SetTalentCondition(ctx, specs, 700, "taken");
        for i = 1, #specs do
            check(action.conditions.talents[specs[i]].taken[1] == 700,
                "specialization " .. specs[i] .. " was not written");
        end

        ActionMenu.SetTalentCondition(ctx, specs, 700, nil);
        check(action.conditions == nil, "clearing left " .. tostring(action.conditions));
    end);

    -- **What paints the rows above a picked talent.** The tree it sits in and the condition itself
    -- ask this same question, so a talent picked at the bottom is visible from the top.
    test("a tree with a picked talent under it reads as touched", function()
        local action = { type = Constants.SPELL, value = 585 };
        local ctx = Ctx(action);
        local specs = { 102 };
        local tree = { [700] = true, [701] = true };

        check(not ActionMenu.TalentConditionTouches(ctx, 102, tree), "touched before anything was set");

        ActionMenu.SetTalentCondition(ctx, specs, 701, "notTaken");
        check(ActionMenu.TalentConditionTouches(ctx, 102, tree),
            "the tree holding it does not read as touched");
        check(not ActionMenu.TalentConditionTouches(ctx, 102, { [900] = true }),
            "a tree holding none of it reads as touched");
        check(not ActionMenu.TalentConditionTouches(ctx, 103, tree),
            "another specialization's key reads as touched");
    end);

    -- **Any and not every**: the colour answers "is there something of mine down here", so one
    -- action out of three is enough to light the way to it.
    test("one action out of a selection is enough to touch it", function()
        local one = { type = Constants.SPELL, value = 585 };
        local two = { type = Constants.SPELL, value = 586 };
        ActionMenu.SetTalentCondition(Ctx(one), { 102 }, 700, "taken");
        check(ActionMenu.TalentConditionTouches(Ctx(one, two), 102, { [700] = true }),
            "the branch is dark while one of them holds it");
    end);

    test("a row reads as unset while the selected actions disagree", function()
        local one = { type = Constants.SPELL, value = 585 };
        local two = { type = Constants.SPELL, value = 586 };
        local specs = { 102 };

        ActionMenu.SetTalentCondition(Ctx(one), specs, 700, "taken");

        local both = Ctx(one, two);
        check(not ActionMenu.TalentConditionIs(both, specs, 700, "taken"),
            "it reads as taken while only one of them says so");

        ActionMenu.SetTalentCondition(both, specs, 700, "taken");
        check(ActionMenu.TalentConditionIs(both, specs, 700, "taken"),
            "the click did not bring them together");
    end);

    ---------------------------------------------------------------------------
    -- Where the highlight leads
    ---------------------------------------------------------------------------

    --- A description that keeps what it was told to draw, the way `actionmenutree_spec` builds one.
    local function Element(kind, text)
        local element = { kind = kind, text = text, children = {} };
        local function Add(child)
            element.children[#element.children + 1] = child;
            return child;
        end
        function element:AddInitializer() end
        function element:SetEnabled() end
        function element:SetTooltip() end
        function element:SetTag() end
        function element:HasElements() return #self.children > 0; end
        function element:AddQueuedDescription(child) table.insert(self.children, 1, child); end
        function element:CreateTitle(label) return Add(Element("title", label)); end
        function element:CreateButton(label) return Add(Element("button", label)); end
        function element:CreateRadio(label, sel, set, data)
            local child = Add(Element("radio", label));
            child.isSelected, child.setSelected, child.data = sel, set, data;
            return child;
        end
        function element:CreateCheckbox(label) return Add(Element("checkbox", label)); end
        function element:CreateDivider() return Add(Element("divider")); end
        return element;
    end

    --- The path to the first row whose label is `text`, or nil.
    local function PathTo(root, text)
        local function Walk(element, path)
            for _, child in ipairs(element.children or {}) do
                local here = path .. "/" .. tostring(child.text);
                if (child.text == text) then
                    return here;
                end
                local found = Walk(child, here);
                if (found) then
                    return found;
                end
            end
        end
        return Walk(root, "");
    end

    --- **The panel is stood up and put back.** The move and copy rows read its tabs while the menu
    --- is built, and nothing here is about those rows (`actionmenutree_spec.lua` does the same).
    local function ActionMenuTree(action)
        SetWorld();
        local panel = rawget(_G, "DebindLayerPanel");
        _G.DebindLayerPanel = { Tabs = {}, SideTabs = {} };
        local root = Element("root");
        local ok, err = pcall(DebindPrivate.DebindUI.SetupActionDropdownMenu,
            nil, root, { actions = { action } });
        _G.DebindLayerPanel = panel;
        if (not ok) then
            error(err, 0);
        end
        return root;
    end

    -- **The rows answer for the specialization being played and no other.** The same talent can
    -- sit in another specialization's entry, and its row here has to read as untouched.
    test("a talent set on another specialization leaves this one's row unset", function()
        local mine = MySpec();
        local other = mine == 102 and 103 or 102;
        local action = {
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [other] = { taken = { 700 } } } },
        };
        local ctx = { actions = { action } };
        check(not DebindPrivate.ActionMenu.TalentConditionIs(ctx, { mine }, 700, "taken"),
            "the row reads as taken off another specialization's entry");
        check(not DebindPrivate.ActionMenu.TalentConditionTouches(ctx, mine, { [700] = true }),
            "the branch lights off another specialization's entry");
    end);

    -- **The one thing the menu can do about them.** Without it a condition written elsewhere, or
    -- one that arrived in a shared string, cannot be taken off without switching specialization,
    -- and the initial specialization cannot be switched to at all.
    test("a row to clear the other specializations stands when there are any", function()
        local mine = MySpec();
        local other = mine == 102 and 103 or 102;
        local root = ActionMenuTree({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [other] = { taken = { 700 } } } },
        });
        check(PathTo(root, "CONDITION_TALENT_CLEAR_OTHERS"), "there is no way to clear them");
    end);

    -- **Silence is not an answer.** The reader opened this block to find out whether anything is
    -- set elsewhere, and a block that only appears when there is something leaves them unable to
    -- tell "nothing" from "not said".
    test("with none, the block says so instead of offering to clear", function()
        local root = ActionMenuTree({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [MySpec()] = { taken = { 700 } } } },
        });
        check(PathTo(root, "CONDITION_TALENT_NO_OTHERS"), "it says nothing at all");
        check(not PathTo(root, "CONDITION_TALENT_CLEAR_OTHERS"),
            "it offers to clear specializations that carry nothing");
    end);

    test("clearing leaves this specialization's alone", function()
        local mine = MySpec();
        local other = mine == 102 and 103 or 102;
        local action = {
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = {
                [mine] = { taken = { 700 } },
                [other] = { taken = { 701 } },
            } },
        };
        DebindPrivate.ActionMenu.ClearOtherSpecTalents({ actions = { action } });
        local talents = action.conditions and action.conditions.talents;
        check(talents and talents[mine], "it cleared the one being played");
        check(talents and talents[other] == nil, "the other one is still there");
    end);

    -- **Another class's specialization is in this too.** A shared string carries the sender's own
    -- ids, so an imported action can hold a class this character will never play, and no
    -- specialization change can ever reach it.
    test("another class's entry counts and clears", function()
        local action = {
            type = Constants.SPELL, value = 585, key = "F1",
            -- 62 is a mage specialization; this character is a druid.
            conditions = { talents = { [62] = { taken = { 700 } } } },
        };
        local ctx = { actions = { action } };
        check(DebindPrivate.ActionMenu.HasOtherSpecTalents(action),
            "another class's entry does not count");
        DebindPrivate.ActionMenu.ClearOtherSpecTalents(ctx);
        check(action.conditions == nil,
            "it stayed: " .. tostring(action.conditions));
    end);

    test("clearing the last one leaves no empty condition behind", function()
        local mine = MySpec();
        local other = mine == 102 and 103 or 102;
        local action = {
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [other] = { taken = { 701 } } } },
        };
        DebindPrivate.ActionMenu.ClearOtherSpecTalents({ actions = { action } });
        check(action.conditions == nil,
            "the action is still conditional: " .. tostring(action.conditions));
    end);

    -- **One click writes one specialization.** The class tree branch used to write every
    -- specialization of the class, which put a setting where this menu cannot show it.
    test("a class-tree row writes only the specialization being played", function()
        SetWorld();
        local root = Element("root");
        local panel = rawget(_G, "DebindLayerPanel");
        _G.DebindLayerPanel = { Tabs = {}, SideTabs = {} };
        local action = { type = Constants.SPELL, value = 585, key = "F1" };
        local ctx = { actions = { action } };
        local ok, err = pcall(DebindPrivate.DebindUI.SetupActionDropdownMenu, nil, root, ctx);
        _G.DebindLayerPanel = panel;
        if (not ok) then
            error(err, 0);
        end

        local found;
        local function Walk(element)
            for _, child in ipairs(element.children or {}) do
                if (child.kind == "radio" and child.text == "CONDITION_TALENT_TAKEN") then
                    found = found or child;
                end
                Walk(child);
            end
        end
        Walk(root);
        check(found, "no talent row was drawn");
        found.setSelected(found.data);

        local talents = action.conditions and action.conditions.talents;
        check(talents, "the click wrote nothing");
        local count = 0;
        for _ in pairs(talents) do
            count = count + 1;
        end
        check(count == 1, "it wrote " .. count .. " specializations");
        check(talents[MySpec()], "it wrote a specialization other than the one being played");
    end);

    ---------------------------------------------------------------------------
    -- What the tooltip says
    ---------------------------------------------------------------------------

    --- The tooltip's lines for one action, as one string.
    local function Tooltip(action)
        SetWorld();
        local tooltip = shim.newTooltip();
        DebindPrivate.AddActionToTooltip(tooltip, action, { suppressInactive = true });
        local texts = {};
        for i = 1, #tooltip.lines do
            texts[i] = tooltip.lines[i].text or "";
        end
        return table.concat(texts, "\n");
    end

    -- **The line is read by the key it was written with.** No locale file is loaded here, so every
    -- lookup falls through to the key itself (`Locales/enUS.lua`'s metatable) and the names the
    -- sentence would carry never make it into the text. What this can hold is that each list puts
    -- out its own line, which is the half that picks the wrong one when it is wrong.
    test("the tooltip draws a line for each list", function()
        local text = Tooltip({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [MySpec()] = { taken = { 700 }, notTaken = { 701 } } } },
        });
        check(text:find("CONDITION_TALENT_VALUE_TAKEN", 1, true),
            "no line for the taken list:\n" .. text);
        check(text:find("CONDITION_TALENT_VALUE_NOT_TAKEN", 1, true),
            "no line for the untaken list:\n" .. text);
    end);

    test("a list with nothing in it draws no line", function()
        local text = Tooltip({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [MySpec()] = { taken = { 700 } } } },
        });
        check(not text:find("CONDITION_TALENT_VALUE_NOT_TAKEN", 1, true),
            "the empty list drew a line:\n" .. text);
    end);

    -- An id no talent of this client carries is one nothing matches, so the sentence would name a
    -- number to a reader who cannot do anything with it.
    test("an id the client cannot name draws no line", function()
        local text = Tooltip({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [MySpec()] = { taken = { 4242 } } } },
        });
        check(not text:find("CONDITION_TALENT_VALUE_TAKEN", 1, true),
            "the unnameable id drew a line:\n" .. text);
    end);

    -- **Otherwise it is a condition with nowhere on screen.** The menu opens this specialization
    -- alone, so a key written elsewhere has no other line to appear on.
    -- **A key on another specialization judges nothing here**, so the tooltip says nothing about
    -- it. Naming it put a specialization under a talent's line and read as that talent being taken
    -- over there.
    -- **Three cases, told apart.** What is set on another class or specialization does not run
    -- here and has no row in the menu, so the lines have to say which of the three the reader is
    -- looking at.
    test("only this specialization: the talents, and nothing about others", function()
        local text = Tooltip({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [MySpec()] = { taken = { 700 } } } },
        });
        check(text:find("CONDITION_TALENT_VALUE_TAKEN", 1, true), "no talent line:\n" .. text);
        check(not text:find("LINE_TOOLTIP_TALENT_ALSO_OTHERS", 1, true),
            "it claims another one carries talents:\n" .. text);
        check(not text:find("LINE_TOOLTIP_TALENT_ONLY_OTHERS", 1, true),
            "it says nothing applies here:\n" .. text);
    end);

    test("both: the talents, and a line saying others carry their own", function()
        local mine = MySpec();
        local other = mine == 102 and 103 or 102;
        local text = Tooltip({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = {
                [mine] = { taken = { 700 } },
                [other] = { taken = { 701 } },
            } },
        });
        check(text:find("CONDITION_TALENT_VALUE_TAKEN", 1, true), "no talent line:\n" .. text);
        check(text:find("LINE_TOOLTIP_TALENT_ALSO_OTHERS", 1, true),
            "nothing says another one carries talents:\n" .. text);
    end);

    test("others only: a line saying none of it applies here", function()
        local mine = MySpec();
        local other = mine == 102 and 103 or 102;
        local text = Tooltip({
            type = Constants.SPELL, value = 585, key = "F1",
            conditions = { talents = { [other] = { taken = { 700 } } } },
        });
        check(text:find("LINE_TOOLTIP_TALENT_ONLY_OTHERS", 1, true),
            "the action reads as carrying nothing:\n" .. text);
        check(not text:find("CONDITION_TALENT_VALUE_TAKEN", 1, true),
            "it named a talent it cannot answer for:\n" .. text);
    end);

    return T;
end
