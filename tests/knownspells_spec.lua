-- `Spells.Build` - which spells' `[known:]` answer cannot move before the next rebuild.
-- No client needed: the walk takes every call it makes in one table, and this spec hands it a
-- world of its own.
--
-- **What this cannot see** is whether the real client puts what we expect in those fields. The
-- fake API answers here, so what is verified is our traversal and nothing about Blizzard's data
-- (`devdocs/baking-the-known-condition.md` §7).

return function(DebindPrivate)
    local Spells = DebindPrivate.Spells;

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
                return {
                    spellID = entry.spellID,
                    actionID = entry.actionID,
                    itemType = entry.itemType or Enum.SpellBookItemType.Spell,
                };
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
            GetSpellName = function(spellID) return (world.spellNames or {})[spellID]; end,
        };
    end

    ---------------------------------------------------------------------------
    -- The spellbook walk
    ---------------------------------------------------------------------------

    test("spellbook: 배우는 레벨이 값으로 들어간다", function()
        local out = Spells.Build(API({
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
        local out = Spells.Build(API(world));
        check(out[200] == 70, "unlearned spell missing: " .. tostring(out[200]));
        check(out[100] == 12, "learned spell missing: " .. tostring(out[100]));
    end)

    test("spellbook: 펫 뱅크는 안 돈다", function()
        local out = Spells.Build(API({
            book = { { items = {
                { spellID = 100, level = 12 },
                { spellID = 300, level = 10, bank = PET_BANK },
            } } },
        }));
        check(out[300] == nil, "pet spell got in");
        check(out[100] == 12, "player spell missing");
    end)

    test("spellbook: 레벨이 없는 항목은 안 들어간다", function()
        local out = Spells.Build(API({
            book = { { items = { { spellID = 100 } } } },
        }));
        check(out[100] == nil, "levelless spell got in");
    end)

    test("spellbook: actionID와 base id도 같이 들어간다", function()
        local out = Spells.Build(API({
            book = { { items = { { spellID = 100, actionID = 101, level = 12 } } } },
            baseSpells = { [100] = 99 },
        }));
        check(out[100] == 12, "spellID missing");
        check(out[101] == 12, "actionID missing");
        check(out[99] == 12, "base id missing");
    end)

    -- `actionID` is a flyout id on a flyout row, and `GetSpellBookItemLevelLearned` answers 0
    -- there rather than nil. Filed, it would be fixed for good under a number that is not a spell.
    test("spellbook: 플라이아웃 줄의 actionID는 안 들어간다", function()
        local out = Spells.Build(API({
            book = { { items = { {
                actionID = 101,
                level = 0,
                itemType = Enum.SpellBookItemType.Flyout,
            } } } },
        }));
        check(out[101] == nil, "flyout id got in");
    end)

    test("spellbook: 스킬라인이 여럿이면 슬롯 범위가 안 겹친다", function()
        local out = Spells.Build(API({
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
        local out = Spells.Build(API(selectionWorld()));
        check(out[500] == 0, "picked entry missing: " .. tostring(out[500]));
        check(out[501] == 0, "unpicked entry missing: " .. tostring(out[501]));
    end)

    test("talent: overriddenSpellID도 들어간다", function()
        local world = selectionWorld();
        world.definitions[30] = { spellID = 500, overriddenSpellID = 400 };
        local out = Spells.Build(API(world));
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
        local out = Spells.Build(API(world));
        check(out[600] == 0, "inactive subtree spell missing: " .. tostring(out[600]));
    end)

    test("talent: definitionID가 nil인 엔트리에서 안 죽는다", function()
        local world = selectionWorld();
        world.nodes[10].entryIDs = { 20, 21, 23 };
        world.entries[23] = { subTreeID = 3 };
        local out = Spells.Build(API(world));
        check(out[500] == 0 and out[501] == 0, "walk stopped early");
    end)

    test("talent: 활성 설정이 없으면 그냥 비어 있다", function()
        local out = Spells.Build(API({}));
        check(next(out) == nil, "something got in");
    end)

    ---------------------------------------------------------------------------
    -- The PvP talent walk
    ---------------------------------------------------------------------------

    test("pvp: 슬롯을 nil에서 끊고 고를 수 있는 것을 전부 넣는다", function()
        local out = Spells.Build(API({
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
        local out = Spells.Build(API(world));
        check(out[500] == 70, "got " .. tostring(out[500]));
    end)

    ---------------------------------------------------------------------------
    -- The name index
    ---------------------------------------------------------------------------

    local function names(world)
        local _, byName = Spells.Build(API(world));
        return byName;
    end

    --- The whole reason the index exists: a stored id the client can no longer place is found
    --- again through the name it shares with one that is still standing.
    test("이름: 한 이름에 걸린 id가 전부 선다", function()
        local byName = names({
            book = { { items = {
                { spellID = 100, level = 12 },
                { spellID = 200, level = 12 },
            } } },
            spellNames = { [100] = "광포", [200] = "광포" },
        });
        local ids = byName["광포"];
        check(ids and #ids == 2, "got " .. tostring(ids and #ids));
        check((ids[1] == 100 and ids[2] == 200) or (ids[1] == 200 and ids[2] == 100),
            "wrong ids: " .. tostring(ids[1]) .. "/" .. tostring(ids[2]));
    end)

    test("이름: 세 갈래 전부에서 모은다", function()
        local world = selectionWorld();
        world.book = { { items = { { spellID = 100, level = 12 } } } };
        world.pvpSlots = { { availableTalentIDs = { 40 } } };
        world.pvpTalents = { [40] = { spellID = 700 } };
        world.spellNames = { [100] = "책", [500] = "특성", [700] = "투기장" };
        local byName = names(world);
        check(byName["책"] and byName["책"][1] == 100, "book missing");
        check(byName["특성"] and byName["특성"][1] == 500, "talent missing");
        check(byName["투기장"] and byName["투기장"][1] == 700, "pvp missing");
    end)

    --- The one the walk hands out most: `AddSpellBook` files the same id under three keys and the
    --- merge walk meets it again. A list that grew a duplicate would make a caller try the same
    --- dead id twice and call that two answers.
    test("이름: 같은 id를 여러 번 만나도 한 번만 선다", function()
        local byName = names({
            book = { { items = { { spellID = 100, actionID = 100, level = 12 } } } },
            baseSpells = { [100] = 100 },
            spellNames = { [100] = "광포" },
        });
        check(#byName["광포"] == 1, "got " .. tostring(#byName["광포"]));
    end)

    test("이름: 이름 없는 id는 안 들어간다", function()
        local byName = names({
            book = { { items = { { spellID = 100, level = 12 } } } },
        });
        check(next(byName) == nil, "something got in");
    end)

    ---------------------------------------------------------------------------
    -- Learn levels by name
    ---------------------------------------------------------------------------

    --- The same question the id table answers, asked in the name a `known` condition stores
    --- (`devdocs/making-known-a-spell-name.md` §3-2).

    local function nameLevels(world)
        return (select(3, Spells.Build(API(world))));
    end

    test("이름 레벨: 이름이 배우는 레벨을 단다", function()
        local levels = nameLevels({
            book = { { items = { { spellID = 100, level = 12 } } } },
            spellNames = { [100] = "광포" },
        });
        check(levels["광포"] == 12, "got " .. tostring(levels["광포"]));
    end)

    --- A name a talent version and the book version share holds the **higher** level, for the
    --- reason the id table merges that way: the lower one would call the answer fixed while a
    --- level-up can still flip it.
    test("이름 레벨: 한 이름을 나눠 쓰면 높은 레벨이 남는다", function()
        local levels = nameLevels({
            book = { { items = {
                { spellID = 100, level = 12 },
                { spellID = 200, level = 70 },
            } } },
            spellNames = { [100] = "광포", [200] = "광포" },
        });
        check(levels["광포"] == 70, "got " .. tostring(levels["광포"]));
    end)

    --- **The merge has to sit where the level is, not where the name is asked.** One id is filed
    --- again and again -- two book rows can share a base -- and the walk asks its name only the
    --- first time. A name level written beside that question keeps whatever level came first.
    test("이름 레벨: 이름을 이미 물어본 id도 레벨 병합에 든다", function()
        local levels = nameLevels({
            book = { { items = {
                { spellID = 100, level = 12 },
                { spellID = 200, level = 70 },
            } } },
            baseSpells = { [100] = 99, [200] = 99 },
            spellNames = { [99] = "뿌리" },
        });
        check(levels["뿌리"] == 70, "got " .. tostring(levels["뿌리"]));
    end)

    ---------------------------------------------------------------------------
    -- The branch index
    ---------------------------------------------------------------------------

    local function branches(world)
        return Spells.BuildBranches(API(world));
    end

    local function ids(list)
        local out = {};
        for i = 1, #(list or {}) do
            out[i] = tostring(list[i]);
        end
        return table.concat(out, ",");
    end

    --- What the `known` list is built from: one stored id reaches the whole family, **root first**,
    --- so the rows read as the chain they are rather than as a flat set.
    test("갈래: 뿌리 밑에 뿌리부터 순서대로 선다", function()
        local byRoot = branches({
            book = { { items = {
                { spellID = 194223, level = 0 },
                { spellID = 102560, level = 0 },
            } } },
            baseSpells = { [102560] = 194223 },
        });
        check(ids(byRoot[194223]) == "194223,102560", "got " .. ids(byRoot[194223]));
    end)

    --- Two steps down sits below one step down, which is what makes the list a chain. 390414 is
    --- the real shape of this: it reaches 194223 through 102560.
    test("갈래: 두 칸 아래가 한 칸 아래보다 뒤에 선다", function()
        local byRoot = branches({
            book = { { items = {
                { spellID = 390414, level = 0 },
                { spellID = 194223, level = 0 },
                { spellID = 102560, level = 0 },
            } } },
            baseSpells = { [390414] = 102560, [102560] = 194223 },
        });
        check(ids(byRoot[194223]) == "194223,102560,390414", "got " .. ids(byRoot[194223]));
    end)

    --- Same depth, so nothing about the chain decides between them. The id does, because a list
    --- that reshuffles between two walks would move the rows under the reader's cursor.
    test("갈래: 깊이가 같으면 id 순으로 선다", function()
        local byRoot = branches({
            book = { { items = {
                { spellID = 383410, level = 0 },
                { spellID = 194223, level = 0 },
                { spellID = 102560, level = 0 },
            } } },
            baseSpells = { [383410] = 194223, [102560] = 194223 },
        });
        check(ids(byRoot[194223]) == "194223,102560,383410", "got " .. ids(byRoot[194223]));
    end)

    test("갈래: 아무것도 안 덮은 주문은 혼자 자기 뿌리 밑에 선다", function()
        local byRoot = branches({
            book = { { items = { { spellID = 100, level = 12 } } } },
        });
        check(ids(byRoot[100]) == "100", "got " .. ids(byRoot[100]));
    end)

    test("갈래: 같은 id를 여러 번 만나도 한 번만 선다", function()
        local byRoot = branches({
            book = { { items = { { spellID = 100, actionID = 100, level = 12 } } } },
            baseSpells = { [100] = 100 },
        });
        check(ids(byRoot[100]) == "100", "got " .. ids(byRoot[100]));
    end)

    ---------------------------------------------------------------------------
    -- Resolving a stored id to its base
    ---------------------------------------------------------------------------

    --- `api` the same way `Build` takes it: every call in one table, plus the index `Build` made.
    local function RESOLVER(world)
        return {
            FindBaseSpellByID = function(spellID) return (world.baseSpells or {})[spellID]; end,
            GetSpellName = function(spellID) return (world.spellNames or {})[spellID]; end,
            obtainableIDsByName = world.byName or {},
        };
    end

    test("resolve: 클라이언트가 답하면 뿌리까지 올라간다", function()
        local got = Spells.ResolveBase(390414, RESOLVER({
            baseSpells = { [390414] = 102560, [102560] = 194223 },
        }));
        check(got == 194223, "got " .. tostring(got));
    end)

    --- 390414 with the talent combination gone: every client route answers the id back, and the
    --- name is the only thing left that still points anywhere.
    ---
    --- **390414 is not in the index in this world, and that is the real shape.** The walk files
    --- spellbook ids, talent definitions and PvP talents; an id that only exists while three
    --- talents stand together is none of those once one of them goes.
    test("resolve: 클라이언트가 막히면 이름으로 갈아타 올라간다", function()
        local got = Spells.ResolveBase(390414, RESOLVER({
            baseSpells = { [102560] = 194223 },
            spellNames = { [390414] = "화신: 엘룬의 정수", [102560] = "화신: 엘룬의 정수" },
            byName = { ["화신: 엘룬의 정수"] = { 102560 } },
        }));
        check(got == 194223, "got " .. tostring(got));
    end)

    --- The name is a detour and not an override: an id the client places is not re-decided by a
    --- namesake that roots somewhere else.
    test("resolve: 클라이언트가 답한 뿌리를 동명이주문이 못 뒤집는다", function()
        local got = Spells.ResolveBase(106951, RESOLVER({
            baseSpells = { [106951] = 999, [50334] = 888 },
            spellNames = { [106951] = "광포", [50334] = "광포" },
            byName = { ["광포"] = { 50334, 106951 } },
        }));
        check(got == 999, "got " .. tostring(got));
    end)

    --- **The client answers the id back in two different situations** and this is the one the
    --- detour must not fire in: a spell that simply is its own root. The walk holds it, so the
    --- index saying its own name carries it is what tells the two apart -- without that, every
    --- ordinary spell with a namesake in the index is re-rooted onto the namesake.
    test("resolve: 자기가 뿌리인 주문은 동명이주문으로 안 새어나간다", function()
        local got = Spells.ResolveBase(106951, RESOLVER({
            baseSpells = { [50334] = 888 },
            spellNames = { [106951] = "광포", [50334] = "광포" },
            byName = { ["광포"] = { 50334, 106951 } },
        }));
        check(got == 106951, "got " .. tostring(got));
    end)

    test("resolve: 이름으로도 못 풀면 저장값 그대로 둔다", function()
        local got = Spells.ResolveBase(390414, RESOLVER({
            spellNames = { [390414] = "화신: 엘룬의 정수" },
            byName = { ["화신: 엘룬의 정수"] = { 390414 } },
        }));
        check(got == 390414, "got " .. tostring(got));
    end)

    test("resolve: 서로를 가리키는 짝에서 안 돈다", function()
        local got = Spells.ResolveBase(100, RESOLVER({
            baseSpells = { [100] = 200, [200] = 100 },
        }));
        check(got == 100 or got == 200, "got " .. tostring(got));
    end)

    test("resolve: nil은 nil로 나간다", function()
        check(Spells.ResolveBase(nil, RESOLVER({})) == nil, "nil did not survive");
    end)

    ---------------------------------------------------------------------------
    -- Climbing without the detour
    ---------------------------------------------------------------------------

    --- **The index covers the player bank only**, so an id from outside it -- a pet ability, a
    --- flyout slot -- is absent for a reason that has nothing to do with a lost talent build.
    --- `ResolveBase` cannot tell those two absences apart, so the caller says which question it is
    --- asking: `ClimbBase` never reaches for a name.
    test("climb: 색인 밖 id를 동명이주문으로 안 바꾼다", function()
        local got = Spells.ClimbBase(132411, RESOLVER({
            baseSpells = { [119905] = 555 },
            spellNames = { [132411] = "Singe Magic", [119905] = "Singe Magic" },
            byName = { ["Singe Magic"] = { 119905 } },
        }));
        check(got == 132411, "got " .. tostring(got));
    end)

    --- The same world through `ResolveBase`, which is what the pet row used to reach: it takes the
    --- namesake. This is the pair that says the two functions are not interchangeable.
    test("climb: 같은 세계에서 ResolveBase는 갈아탄다", function()
        local got = Spells.ResolveBase(132411, RESOLVER({
            baseSpells = { [119905] = 555 },
            spellNames = { [132411] = "Singe Magic", [119905] = "Singe Magic" },
            byName = { ["Singe Magic"] = { 119905 } },
        }));
        check(got == 555, "got " .. tostring(got));
    end)

    test("climb: 덮은 것이 있으면 뿌리까지 올린다", function()
        local got = Spells.ClimbBase(390414, RESOLVER({
            baseSpells = { [390414] = 102560, [102560] = 194223 },
        }));
        check(got == 194223, "got " .. tostring(got));
    end)

    test("climb: nil은 nil로 나간다", function()
        check(Spells.ClimbBase(nil, RESOLVER({})) == nil, "nil did not survive");
    end)

    return T;
end
