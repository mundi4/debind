local _, DebindPrivate = ...;

local Talents = {};
DebindPrivate.Talents = Talents;

--- Which talents are taken right now, by name.
---
--- **Names and not ids**, because a talent has an id per specialization and the reader who sees
--- one name on screen has no way to tell which build wrote which id
--- (`devdocs/legacy/adding-a-talent-condition.md` §3).
---
--- **A talent of the hero tree that is not running is not taken**, and that is the whole reason
--- this walk cannot take `entryIDsWithCommittedRanks` at face value. Ranks bought in a hero tree
--- stay bought after switching to the other one: measured on a balance druid, the live tree and
--- the dead one each answered eleven committed entries (2026-09-19,
--- `DebindDev/Probe_TalentCondition.lua`). `subTreeActive` is the only thing that says which of
--- them is running.
---
--- **Both hero trees are judged, not only the live one** (2026-09-19, owner). Treating the other
--- one's talents as "nothing said" made the condition nobody could otherwise write --
--- "while I am in that hero tree" -- impossible to express, since the talent that would say so is
--- exactly the one being skipped.
--- `subTreeByName` is every hero talent this specialization can reach, live tree and dead one
--- alike, filed under the tree it belongs to. **Not for the judgment** -- that reads `taken` --
--- but for spotting a condition that names both trees, which no state can satisfy.
local function NewIndex()
    return { taken = {}, subTreeByName = {} };
end

--- The name a tree entry grants, **taken off the spell and not off `overrideName`.** A condition
--- stores a spell id and the judgment names that id with `GetSpellName`; a display name the tree
--- carries of its own would put the two sides on different words.
local function EntryName(api, configID, entryID)
    local entry = api.GetEntryInfo(configID, entryID);
    -- No `definitionID` is a subtree selection entry, which names no spell.
    local definition = entry and entry.definitionID and api.GetDefinitionInfo(entry.definitionID);
    local spellID = definition and definition.spellID;
    return spellID and api.GetSpellName(spellID) or nil;
end

local function AddTraits(out, api)
    local configID = api.GetActiveConfigID();
    local configInfo = configID and api.GetConfigInfo(configID);
    local treeIDs = configInfo and configInfo.treeIDs;
    if (not treeIDs) then
        return;
    end
    for i = 1, #treeIDs do
        local nodes = api.GetTreeNodes(treeIDs[i]) or {};
        for j = 1, #nodes do
            local node = api.GetNodeInfo(configID, nodes[j]);
            if (node) then
                if (node.subTreeID ~= nil) then
                    local entryIDs = node.entryIDs;
                    for k = 1, (entryIDs and #entryIDs or 0) do
                        local name = EntryName(api, configID, entryIDs[k]);
                        if (name) then
                            out.subTreeByName[name] = node.subTreeID;
                        end
                    end
                end
                -- **A hero tree that is not running contributes nothing**, whatever it has
                -- committed.
                if (node.subTreeID == nil or node.subTreeActive) then
                    local committed = node.entryIDsWithCommittedRanks;
                    for k = 1, (committed and #committed or 0) do
                        local name = EntryName(api, configID, committed[k]);
                        if (name) then
                            out.taken[name] = true;
                        end
                    end
                end
            end
        end
    end
end

--- PvP talents. **The slot's own answer**, since `GetPvpTalentInfo(...).selected` is the talent's
--- and not the slot's. The slot count differs by expansion, so the walk stops where the client
--- does.
local function AddPvpTalents(out, api)
    local slot = 1;
    while (true) do
        local info = api.GetPvpTalentSlotInfo(slot);
        if (not info) then
            return;
        end
        local talent = info.selectedTalentID and api.GetPvpTalentInfo(info.selectedTalentID);
        local spellID = talent and talent.spellID;
        local name = spellID and api.GetSpellName(spellID);
        if (name) then
            out.taken[name] = true;
        end
        slot = slot + 1;
    end
end

--- One walk over this character's active configuration. `api` holds every client call it makes,
--- in one table so a spec can hand it a world of its own.
function Talents.Build(api)
    local out = NewIndex();
    AddTraits(out, api);
    AddPvpTalents(out, api);
    return out;
end

--- Does one specialization's entry hold, against the index `Build` made?
---
--- **An id the client cannot name fails `taken` and passes `notTaken`.** Nothing matches it.
---
--- **A non-number in either list is skipped.** The wire does not filter inside this table, the way
--- it does not filter inside `specs` and `units` (`DebindStorage/Export.lua`), and these lists are
--- walked rather than indexed.
local function EntryHolds(entry, index, GetSpellName)
    local taken = Talents.ListOf(entry, "taken");
    for i = 1, (taken and #taken or 0) do
        local spellID = taken[i];
        if (type(spellID) == "number") then
            local name = GetSpellName(spellID);
            if (not (name and index.taken[name])) then
                return false;
            end
        end
    end

    local notTaken = Talents.ListOf(entry, "notTaken");
    for i = 1, (notTaken and #notTaken or 0) do
        local spellID = notTaken[i];
        if (type(spellID) == "number") then
            local name = GetSpellName(spellID);
            if (name and index.taken[name]) then
                return false;
            end
        end
    end

    return true;
end

--- One of an entry's two lists, **or nil where what is stored is not a list at all.**
---
--- **The wire does not reach this deep.** `ConditionAllowed` types the condition itself and stops
--- (`DebindStorage/Import.lua`), the way it does for `specs` and `units`; those two are read by
--- indexing, so anything inside them is harmless, while these are walked. A hand-made string
--- carrying `talents = { [102] = { taken = 5 } }` otherwise raises on `#taken` inside the rebuild,
--- which has already wiped the key map -- the character comes out with no bindings at all.
function Talents.ListOf(entry, name)
    local list = type(entry) == "table" and entry[name];
    if (type(list) ~= "table") then
        return nil;
    end
    return list;
end

--- Does one entry's `taken` list name talents from two different hero trees?
---
--- **A character stands in one of them at a time**, so such a condition is false in every state
--- there is. It is reported rather than left to fail quietly, the way an empty specialization set
--- is (`BINDING_ISSUE_SPECS_NONE_SELECTED`): the reader picked two rows that each look reachable.
---
--- `notTaken` is not asked about. Two talents of two trees both being unpicked is an ordinary
--- state, not a contradiction.
function Talents.HeroTreesConflict(entry, index, GetSpellName)
    if (type(entry) ~= "table") then
        return false;
    end
    local taken = Talents.ListOf(entry, "taken");
    local seen;
    for i = 1, (taken and #taken or 0) do
        local spellID = taken[i];
        if (type(spellID) == "number") then
            local name = GetSpellName(spellID);
            local subTreeID = name and index.subTreeByName[name];
            if (subTreeID) then
                if (seen and seen ~= subTreeID) then
                    return true;
                end
                seen = subTreeID;
            end
        end
    end
    return false;
end

--- Whether a stored `talents` condition holds for the specialization being played.
---
--- **No key for this specialization is true**, because the condition said nothing about it (§2).
--- Which is what lets one action carry another class's talents without dying here.
function Talents.Holds(talents, specID, index, GetSpellName)
    if (talents == nil) then
        return true;
    end
    local entry = specID and talents[specID];
    if (type(entry) ~= "table") then
        return true;
    end
    return EntryHolds(entry, index, GetSpellName);
end

--- One row of a menu list: the id it stores and the name it shows.
---
--- **The id is the talent's own spell**, which is what §3 says the condition stores, and the name
--- is what the judgment matches on. The two come off the same entry so they cannot part.
local function AddRow(list, seen, api, configID, entryID)
    local entry = api.GetEntryInfo(configID, entryID);
    local definition = entry and entry.definitionID and api.GetDefinitionInfo(entry.definitionID);
    local spellID = definition and definition.spellID;
    local name = spellID and api.GetSpellName(spellID);
    -- **One row per name.** The condition matches on the name, so two ids sharing one would be two
    -- rows that do the same thing and disagree about which is ticked.
    if (name and not seen[name]) then
        seen[name] = true;
        list[#list + 1] = { id = spellID, name = name };
    end
end

local function SortRows(list)
    table.sort(list, function(a, b)
        return a.name < b.name;
    end);
    return list;
end

--- The lists the menu offers, for the specialization being played: the class tree, this
--- specialization's tree, one per hero tree, and the pvp talents.
---
--- **This specialization only** (`devdocs/legacy/adding-a-talent-condition.md` §5). Another one's nodes
--- are reachable through a view config, but its pvp talents are not reachable at all, and a branch
--- that opens four specializations beside one that opens one is worse than either.
---
--- **`isVisible` is what makes a node this specialization's.** The conditions a node carries name
--- specialization sets too, and those are not the same question: some of them grant a free rank on
--- a node every specialization sees (§6-1).
---
--- **Class and specialization are told apart by the currency the node costs.** The tree's currency
--- list has the class's first and the specialization's second, which is the split the talent frame
--- itself resets by (`Blizzard_ClassTalentsFrame.lua:821-827`).
---
--- **Built on demand and not kept**, the way `Spells.BuildBranches` is: only a menu asks, and a
--- second cache is a second thing to invalidate.
function Talents.BuildMenu(api)
    local out = {};
    local configID = api.GetActiveConfigID();
    local configInfo = configID and api.GetConfigInfo(configID);
    local treeIDs = configInfo and configInfo.treeIDs;
    local treeID = treeIDs and treeIDs[1];

    if (treeID) then
        local currencies = api.GetTreeCurrencyInfo(configID, treeID, false) or {};
        local classCurrency = currencies[1] and currencies[1].traitCurrencyID;

        local classRows, classSeen = {}, {};
        local specRows, specSeen = {}, {};
        local heroRows, heroSeen, heroOrder = {}, {}, {};

        local nodes = api.GetTreeNodes(treeID) or {};
        for i = 1, #nodes do
            local nodeID = nodes[i];
            local node = api.GetNodeInfo(configID, nodeID);
            if (node and node.isVisible) then
                local list, seen;
                if (node.subTreeID) then
                    list = heroRows[node.subTreeID];
                    if (not list) then
                        list, seen = {}, {};
                        heroRows[node.subTreeID] = list;
                        heroSeen[node.subTreeID] = seen;
                        heroOrder[#heroOrder + 1] = node.subTreeID;
                    else
                        seen = heroSeen[node.subTreeID];
                    end
                else
                    local cost = api.GetNodeCost(configID, nodeID);
                    local currency = cost and cost[1] and cost[1].ID;
                    if (currency == classCurrency) then
                        list, seen = classRows, classSeen;
                    else
                        list, seen = specRows, specSeen;
                    end
                end

                local entryIDs = node.entryIDs;
                for j = 1, (entryIDs and #entryIDs or 0) do
                    AddRow(list, seen, api, configID, entryIDs[j]);
                end
            end
        end

        out[#out + 1] = { key = "class", name = api.className, rows = SortRows(classRows) };
        out[#out + 1] = { key = "spec", name = api.specName, rows = SortRows(specRows) };

        -- **The client's own order, not the id's.** `GetHeroTalentSpecsForClassSpec` hands them
        -- over the way the talent window lays them out, and a reader who has both windows open is
        -- reading one list (2026-09-19, owner). Anything the call does not name keeps its place
        -- behind them, by id, so a tree that appears without being offered still has a row.
        local offered = api.GetHeroTalentSpecs and api.GetHeroTalentSpecs() or nil;
        local at = {};
        for i = 1, (offered and #offered or 0) do
            at[offered[i]] = i;
        end
        table.sort(heroOrder, function(a, b)
            local left, right = at[a], at[b];
            if (left ~= right) then
                return (left or math.huge) < (right or math.huge);
            end
            return a < b;
        end);

        for i = 1, #heroOrder do
            local subTreeID = heroOrder[i];
            local info = api.GetSubTreeInfo(configID, subTreeID);
            out[#out + 1] = {
                key = "hero",
                subTreeID = subTreeID,
                name = info and info.name,
                rows = SortRows(heroRows[subTreeID]),
            };
        end
    end

    -- **One list and not one per slot.** The three slots offer the same talents; which of them a
    -- talent sits in is the slot's answer, not a question the condition asks (§9).
    local pvpRows, pvpSeen = {}, {};
    local slot = api.GetPvpTalentSlotInfo(1);
    local available = slot and slot.availableTalentIDs;
    for i = 1, (available and #available or 0) do
        local talent = api.GetPvpTalentInfo(available[i]);
        local name = talent and talent.spellID and api.GetSpellName(talent.spellID);
        if (name and not pvpSeen[name]) then
            pvpSeen[name] = true;
            pvpRows[#pvpRows + 1] = { id = talent.spellID, name = name };
        end
    end
    out[#out + 1] = { key = "pvp", name = api.pvpName, rows = SortRows(pvpRows) };

    return out;
end


local function LiveAPI()
    return {
        GetActiveConfigID = C_ClassTalents.GetActiveConfigID,
        GetConfigInfo = C_Traits.GetConfigInfo,
        GetTreeNodes = C_Traits.GetTreeNodes,
        GetNodeInfo = C_Traits.GetNodeInfo,
        GetEntryInfo = C_Traits.GetEntryInfo,
        GetDefinitionInfo = C_Traits.GetDefinitionInfo,
        GetPvpTalentSlotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo,
        GetPvpTalentInfo = C_SpecializationInfo.GetPvpTalentInfo,
        GetSpellName = C_Spell.GetSpellName,
    };
end

--- What the last walk answered. **Dropped at every key map build** (`Debind.lua`) rather than kept
--- per specialization the way `Spells.lua`'s tables are: what that file holds is whether a spell
--- can be obtained, which is a property of the tree, and this one holds what is taken, which moves
--- the moment a talent is bought. The three changes that move it all raise a rebuild, so dropping
--- it there and dropping it on each of them are the same thing.
local index;

local function EnsureIndex()
    if (index == nil) then
        index = Talents.Build(LiveAPI());
    end
    return index;
end

function Talents.Wipe()
    index = nil;
end

--- `BuildMenu` against the client. **A fresh walk every call**, so it is for a menu and not for a
--- rebuild.
---
--- The three names come from the client rather than from our locale files: the class and the
--- specialization are the headings the talent frame itself puts over those two panels, and the
--- reader has one name for each already.
function Talents.GetMenu()
    local api = LiveAPI();
    api.GetTreeCurrencyInfo = C_Traits.GetTreeCurrencyInfo;
    api.GetNodeCost = C_Traits.GetNodeCost;
    api.GetSubTreeInfo = C_Traits.GetSubTreeInfo;
    --- **`MayReturnNothing`**, so it is wrapped rather than called into a list.
    api.GetHeroTalentSpecs = function()
        return (C_ClassTalents.GetHeroTalentSpecsForClassSpec());
    end;
    api.className = UnitClass("player");
    api.specName = select(2, C_SpecializationInfo.GetSpecializationInfo(
        C_SpecializationInfo.GetSpecialization() or 0));
    api.pvpName = PVP_TALENTS;
    return Talents.BuildMenu(api);
end

--- Does this action name talents from both hero trees at once, on the specialization being played?
---
--- **This specialization's entry only.** Which tree a talent belongs to is answered by the
--- configuration the character is standing in (`devdocs/legacy/adding-a-talent-condition.md`
--- §6-1), so a
--- contradiction stored under another specialization is out of reach until they are in it.
function DebindPrivate.TalentConditionContradicts(actionOrBinding)
    local conditions = actionOrBinding.conditions;
    local talents = conditions and conditions.talents;
    if (talents == nil) then
        return false;
    end
    local specID = DebindPrivate.SpecIDForIndex(C_SpecializationInfo.GetSpecialization());
    local entry = specID and talents[specID];
    if (entry == nil) then
        return false;
    end
    return Talents.HeroTreesConflict(entry, EnsureIndex(), C_Spell.GetSpellName);
end

--- The condition read off a binding, against this character as it stands.
function DebindPrivate.TalentConditionHolds(binding)
    local conditions = binding.conditions;
    local talents = conditions and conditions.talents;
    if (talents == nil) then
        return true;
    end
    local specID = DebindPrivate.SpecIDForIndex(C_SpecializationInfo.GetSpecialization());
    return Talents.Holds(talents, specID, EnsureIndex(), C_Spell.GetSpellName);
end
