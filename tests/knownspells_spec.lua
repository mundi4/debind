-- `KnownSpells.Build` - which spells' `[known:]` answer cannot move before the next rebuild.
-- No client needed: the walk takes every call it makes in one table, and this spec hands it a
-- world of its own.
--
-- **What this cannot see** is whether the real client puts what we expect in those fields. The
-- fake API answers here, so what is verified is our traversal and nothing about Blizzard's data
-- (`devdocs/baking-the-known-condition.md` §7).

return function(DebindPrivate)
    local KnownSpells = DebindPrivate.KnownSpells;

    local T = { passed = 0, failures = {} };

    local function fail(name, msg)
        T.failures[#T.failures + 1] = name .. ": " .. msg;
    end

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            fail(name, tostring(err));
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "assertion failed", 2);
        end
    end

    local PLAYER_BANK, PET_BANK = 0, 1;

    --- A world, and the API table that reads it. Everything is optional; a walk whose part of the
    --- world is empty has to come out empty rather than dying.
    ---
    --- `world.book` is a list of skill lines, each `{ items = { {...} } }`, and an item is what
    --- `GetSpellBookItemInfo` answers plus a `level` and an optional `bank`.
    local function API(world)
        local lines = world.book or {};
        -- Slot numbers the way the client hands them out: one run across every line, each line
        -- carrying the offset its own slots start at.
        local slots = {};
        local offset = 0;
        for i = 1, #lines do
            lines[i].itemIndexOffset = offset;
            lines[i].numSpellBookItems = #lines[i].items;
            for j = 1, #lines[i].items do
                slots[offset + j] = lines[i].items[j];
            end
            offset = offset + #lines[i].items;
        end

        local function item(slot, bank)
            local entry = slots[slot];
            if (entry and (entry.bank or PLAYER_BANK) == bank) then
                return entry;
            end
        end

        return {
            playerBank = PLAYER_BANK,
            GetNumSpellBookSkillLines = function() return #lines; end,
            GetSpellBookSkillLineInfo = function(index) return lines[index]; end,
            GetSpellBookItemInfo = function(slot, bank)
                local entry = item(slot, bank);
                if (not entry) then return nil; end
                return { spellID = entry.spellID, actionID = entry.actionID };
            end,
            GetSpellBookItemLevelLearned = function(slot, bank)
                local entry = item(slot, bank);
                return entry and entry.level;
            end,
            FindBaseSpellByID = function(spellID) return (world.baseSpells or {})[spellID]; end,
            GetActiveConfigID = function() return world.configID; end,
            GetConfigInfo = function(configID)
                if (configID ~= world.configID) then return nil; end
                return { treeIDs = world.treeIDs };
            end,
            GetTreeNodes = function(treeID) return (world.trees or {})[treeID]; end,
            GetNodeInfo = function(_, nodeID) return (world.nodes or {})[nodeID]; end,
            GetEntryInfo = function(_, entryID) return (world.entries or {})[entryID]; end,
            GetDefinitionInfo = function(definitionID)
                return (world.definitions or {})[definitionID];
            end,
            GetPvpTalentSlotInfo = function(slot) return (world.pvpSlots or {})[slot]; end,
            GetPvpTalentInfo = function(talentID) return (world.pvpTalents or {})[talentID]; end,
        };
    end

    ---------------------------------------------------------------------------
    -- The spellbook walk
    ---------------------------------------------------------------------------

    test("spellbook: 배우는 레벨이 값으로 들어간다", function()
        local out = KnownSpells.Build(API({
            book = { { items = { { spellID = 100, level = 12 } } } },
        }));
        check(out[100] == 12, "got " .. tostring(out[100]));
    end)

    --- The whole point of holding the level rather than a boolean: an unlearned spell is in the
    --- table, and the same book read at two different character levels is the same table.
    test("spellbook: 아직 못 배운 주문도 배우는 레벨을 달고 들어간다", function()
        local world = {
            book = { { items = {
                { spellID = 100, level = 12 },
                { spellID = 200, level = 70 },
            } } },
        };
        local out = KnownSpells.Build(API(world));
        check(out[200] == 70, "unlearned spell missing: " .. tostring(out[200]));
        check(out[100] == 12, "learned spell missing: " .. tostring(out[100]));
    end)

    test("spellbook: 펫 뱅크는 안 돈다", function()
        local out = KnownSpells.Build(API({
            book = { { items = {
                { spellID = 100, level = 12 },
                { spellID = 300, level = 10, bank = PET_BANK },
            } } },
        }));
        check(out[300] == nil, "pet spell got in");
        check(out[100] == 12, "player spell missing");
    end)

    test("spellbook: 레벨이 없는 항목은 안 들어간다", function()
        local out = KnownSpells.Build(API({
            book = { { items = { { spellID = 100 } } } },
        }));
        check(out[100] == nil, "levelless spell got in");
    end)

    test("spellbook: actionID와 base id도 같이 들어간다", function()
        local out = KnownSpells.Build(API({
            book = { { items = { { spellID = 100, actionID = 101, level = 12 } } } },
            baseSpells = { [100] = 99 },
        }));
        check(out[100] == 12, "spellID missing");
        check(out[101] == 12, "actionID missing");
        check(out[99] == 12, "base id missing");
    end)

    test("spellbook: 스킬라인이 여럿이면 슬롯 범위가 안 겹친다", function()
        local out = KnownSpells.Build(API({
            book = {
                { items = { { spellID = 100, level = 12 } } },
                { items = { { spellID = 200, level = 30 }, { spellID = 201, level = 40 } } },
            },
        }));
        check(out[100] == 12 and out[200] == 30 and out[201] == 40,
            "missed a line: " .. tostring(out[100]) .. "/" .. tostring(out[200])
            .. "/" .. tostring(out[201]));
    end)

    ---------------------------------------------------------------------------
    -- The talent walk
    ---------------------------------------------------------------------------

    --- One selection node offering two spells, one of them picked. The unpicked one is the miss
    --- this walk exists to avoid: an implementation reading `entryIDsWithCommittedRanks` passes
    --- everything above and fails here.
    local function selectionWorld()
        return {
            configID = 7,
            treeIDs = { 1 },
            trees = { [1] = { 10 } },
            nodes = {
                [10] = {
                    entryIDs = { 20, 21 },
                    entryIDsWithCommittedRanks = { 20 },
                    activeEntry = { entryID = 20 },
                },
            },
            entries = { [20] = { definitionID = 30 }, [21] = { definitionID = 31 } },
            definitions = { [30] = { spellID = 500 }, [31] = { spellID = 501 } },
        };
    end

    test("talent: 안 고른 쪽 주문도 표에 들어간다", function()
        local out = KnownSpells.Build(API(selectionWorld()));
        check(out[500] == 0, "picked entry missing: " .. tostring(out[500]));
        check(out[501] == 0, "unpicked entry missing: " .. tostring(out[501]));
    end)

    test("talent: overriddenSpellID도 들어간다", function()
        local world = selectionWorld();
        world.definitions[30] = { spellID = 500, overriddenSpellID = 400 };
        local out = KnownSpells.Build(API(world));
        check(out[400] == 0, "overridden spell missing: " .. tostring(out[400]));
    end)

    --- A subtree node is in the same tree walk, so nothing here asks whether the subtree is the
    --- one in force.
    test("talent: 안 고른 서브트리의 주문도 들어간다", function()
        local world = selectionWorld();
        world.trees[1] = { 10, 11 };
        world.nodes[11] = { subTreeID = 3, subTreeActive = false, entryIDs = { 22 } };
        world.entries[22] = { definitionID = 32 };
        world.definitions[32] = { spellID = 600 };
        local out = KnownSpells.Build(API(world));
        check(out[600] == 0, "inactive subtree spell missing: " .. tostring(out[600]));
    end)

    test("talent: definitionID가 nil인 엔트리에서 안 죽는다", function()
        local world = selectionWorld();
        world.nodes[10].entryIDs = { 20, 21, 23 };
        world.entries[23] = { subTreeID = 3 };
        local out = KnownSpells.Build(API(world));
        check(out[500] == 0 and out[501] == 0, "walk stopped early");
    end)

    test("talent: 활성 설정이 없으면 그냥 비어 있다", function()
        local out = KnownSpells.Build(API({}));
        check(next(out) == nil, "something got in");
    end)

    ---------------------------------------------------------------------------
    -- The PvP talent walk
    ---------------------------------------------------------------------------

    test("pvp: 슬롯을 nil에서 끊고 고를 수 있는 것을 전부 넣는다", function()
        local out = KnownSpells.Build(API({
            pvpSlots = {
                { selectedTalentID = 40, availableTalentIDs = { 40, 41 } },
                { selectedTalentID = 42, availableTalentIDs = { 42 } },
            },
            pvpTalents = {
                [40] = { spellID = 700 }, [41] = { spellID = 701 }, [42] = { spellID = 702 },
            },
        }));
        check(out[700] == 0 and out[701] == 0 and out[702] == 0,
            "missed one: " .. tostring(out[700]) .. "/" .. tostring(out[701])
            .. "/" .. tostring(out[702]));
    end)

    ---------------------------------------------------------------------------
    -- Merging
    ---------------------------------------------------------------------------

    --- A talent that also sits in the book above the character's level keeps the level. Taking
    --- the talent's `0` instead would call the answer fixed while a level-up can still flip it.
    test("merge: 두 갈래가 겹치면 높은 레벨이 남는다", function()
        local world = selectionWorld();
        world.book = { { items = { { spellID = 500, level = 70 } } } };
        local out = KnownSpells.Build(API(world));
        check(out[500] == 70, "got " .. tostring(out[500]));
    end)

    return T;
end
