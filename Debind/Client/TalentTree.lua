local _, DebindPrivate = ...;
local Client = DebindPrivate.Client;

--- **Retail: class and specialization by the currency a node costs, then one section per hero
--- tree.** The tree's currency list has the class's first and the specialization's second, which
--- is the split the talent frame itself resets by (`Blizzard_ClassTalentsFrame.lua:821-827`).
---
--- **The hero trees in the client's own order, not the id's.** `GetHeroTalentSpecsForClassSpec`
--- hands them over the way the talent window lays them out, and a reader who has both windows open
--- is reading one list (2026-09-19, owner). Anything the call does not name keeps its place behind
--- them, by id, so a tree that appears without being offered still has a section.
local function SectionsByCurrency(api, configID, treeID, visible)
    local currencies = api.GetTreeCurrencyInfo(configID, treeID, false) or {};
    local classCurrency = currencies[1] and currencies[1].traitCurrencyID;

    local class = { key = "class", name = api.className, nodes = {} };
    local spec = { key = "spec", name = api.specName, nodes = {} };
    local heroes, heroOrder = {}, {};
    for i = 1, #visible do
        local nodeID, node = visible[i][1], visible[i][2];
        local section;
        if (node.subTreeID) then
            section = heroes[node.subTreeID];
            if (not section) then
                section = { key = "hero", subTreeID = node.subTreeID, nodes = {} };
                heroes[node.subTreeID] = section;
                heroOrder[#heroOrder + 1] = node.subTreeID;
            end
        else
            local cost = api.GetNodeCost(configID, nodeID);
            local currency = cost and cost[1] and cost[1].ID;
            section = currency == classCurrency and class or spec;
        end
        section.nodes[#section.nodes + 1] = node;
    end

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

    local out = { class, spec };
    for i = 1, #heroOrder do
        local section = heroes[heroOrder[i]];
        local info = api.GetSubTreeInfo(configID, section.subTreeID);
        section.name = info and info.name;
        out[#out + 1] = section;
    end
    return out;
end

--- **Camelot: one section per named group, in the talent frame's order.** Every node costs the one
--- currency there (3820 for a druid's 51 on 69977), so the split above would put all of them in the
--- class's section. The frame draws three trees out of `GetGroupDisplayInfoByTreeID` (Balance, Feral
--- Combat, Restoration); a node also sits in groups that call has nothing for, and those are not
--- trees. No hero trees.
local function SectionsByNamedGroup(named, visible)
    local groups = {};
    for i = 1, #named do
        groups[i] = named[i];
    end
    table.sort(groups, function(a, b) return a.orderIndex < b.orderIndex; end);

    local out, byGroup = {}, {};
    for i = 1, #groups do
        out[i] = { key = "tree", name = groups[i].displayName, nodes = {} };
        byGroup[groups[i].groupID] = out[i];
    end
    for i = 1, #visible do
        local node = visible[i][2];
        for _, groupID in ipairs(node.groupIDs or {}) do
            local section = byGroup[groupID];
            if (section) then
                section.nodes[#section.nodes + 1] = node;
            end
        end
    end
    return out;
end

--- The talent tree of the specialization being played, cut into the sections the reader knows it
--- by: `{ key =, name =, subTreeID =, nodes = { nodeInfo… } }`, in the talent frame's order.
---
--- **`api` carries the client's calls** (`Talents.GetMenu` fills it, the specs stand in for it).
--- The two clients cut the tree differently and this is the one place that knows how; the menu is
--- built from the sections the same way on both.
---
--- **`isVisible` is what makes a node this specialization's.** The conditions a node carries name
--- specialization sets too, and those are not the same question: some of them grant a free rank on
--- a node every specialization sees (`adding-a-talent-condition.md` §6-1).
function Client.TalentSections(api, configID, treeID)
    local visible = {};
    local nodeIDs = api.GetTreeNodes(treeID) or {};
    for i = 1, #nodeIDs do
        local node = api.GetNodeInfo(configID, nodeIDs[i]);
        if (node and node.isVisible) then
            visible[#visible + 1] = { nodeIDs[i], node };
        end
    end

    local named = api.GetGroupDisplayInfoByTreeID and api.GetGroupDisplayInfoByTreeID(treeID);
    if (named and #named > 0) then
        return SectionsByNamedGroup(named, visible);
    end
    return SectionsByCurrency(api, configID, treeID, visible);
end
