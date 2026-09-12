-- Probe_TalentNodes.lua
-- `/tn` dumps the current specialization's talent tree as node, entry and name, grouped by the
-- panel the game draws each node in.
--
-- **What it is for.** A talent condition would have the reader pick a talent rather than a spell
-- id, because the node does not move when a talent combination splits one spell into four ids
-- (`.zzz/session-2026-09-12-spell-ids.md`). Building that picker needs the ids the menu would be
-- written against, and this is where they come from.
--
-- **The panels.** Class and specialization share one tree and are told apart by which currency a
-- node costs; hero nodes carry `subTreeID` and only the chosen subtree is live
-- (`Blizzard_ClassTalentsFrame.lua:686-712`, `:820-828`). PvP talents are a set of slots rather
-- than a tree and are walked separately.
--
-- Output goes to the copy dialog, not the chat frame: a paste out of chat arrives truncated.

local Lines = {};

local function Emit(s)
    Lines[#Lines + 1] = s;
end

--- The name to show for one entry. `overrideName` is what the tree draws where it differs from the
--- spell's own name, which is why it comes first.
local function EntryName(definition)
    if (not definition) then
        return "?";
    end
    if (definition.overrideName) then
        return definition.overrideName;
    end
    if (definition.spellID) then
        return tostring(C_Spell.GetSpellName(definition.spellID));
    end
    return "?";
end

local function Sweep()
    wipe(Lines);

    local configID = C_ClassTalents.GetActiveConfigID();
    local configInfo = configID and C_Traits.GetConfigInfo(configID);
    local treeIDs = configInfo and configInfo.treeIDs;
    if (not treeIDs) then
        Emit("no talent config");
        return;
    end

    local _, class = UnitClass("player");
    local specIndex = GetSpecialization();
    local _, specName = GetSpecializationInfo(specIndex or 0);
    Emit(format("%s / %s / config=%d", tostring(class), tostring(specName), configID));

    for i = 1, #treeIDs do
        local treeID = treeIDs[i];
        local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {};
        for j = 1, #currencies do
            Emit(format("tree=%d currency[%d]=%s", treeID, j,
                tostring(currencies[j].traitCurrencyID)));
        end

        local nodes = C_Traits.GetTreeNodes(treeID) or {};
        for j = 1, #nodes do
            local nodeID = nodes[j];
            local node = C_Traits.GetNodeInfo(configID, nodeID);
            local entryIDs = node and node.entryIDs;
            if (entryIDs and #entryIDs > 0) then
                local panel = "?";
                if (node.subTreeID) then
                    local sub = C_Traits.GetSubTreeInfo(configID, node.subTreeID);
                    panel = format("hero:%d %s%s", node.subTreeID,
                        sub and tostring(sub.name) or "?",
                        node.subTreeActive and " *active" or "");
                else
                    local cost = C_Traits.GetNodeCost(configID, nodeID);
                    panel = cost and cost[1] and format("cur=%d", cost[1].ID) or "cur=?";
                end

                -- **Every entry, not only the bought one.** A selection node offers two and the one
                -- nobody picked is still something a condition could name.
                for k = 1, #entryIDs do
                    local entryID = entryIDs[k];
                    local entry = C_Traits.GetEntryInfo(configID, entryID);
                    local definition = entry and entry.definitionID
                        and C_Traits.GetDefinitionInfo(entry.definitionID);
                    local taken = node.activeEntry and node.activeEntry.entryID == entryID;
                    Emit(format("node=%d entry=%d spell=%s %s | %s%s",
                        nodeID, entryID,
                        definition and tostring(definition.spellID) or "nil",
                        EntryName(definition), panel,
                        taken and " *taken" or ""));
                end
            end
        end
    end

    -- PvP is a set of slots, so it has no nodes or entries. The talent id is what a condition would
    -- name there.
    local slot = 1;
    while (true) do
        local info = C_SpecializationInfo.GetPvpTalentSlotInfo(slot);
        if (not info) then
            break;
        end
        local available = info.availableTalentIDs or {};
        for i = 1, #available do
            local talent = C_SpecializationInfo.GetPvpTalentInfo(available[i]);
            if (talent) then
                Emit(format("pvp slot=%d talent=%d spell=%s %s%s",
                    slot, available[i], tostring(talent.spellID),
                    tostring(talent.name),
                    talent.selected and " *taken" or ""));
            end
        end
        slot = slot + 1;
    end
end

SLASH_DEBINDTN1 = "/tn";
SlashCmdList.DEBINDTN = function()
    Sweep();

    local text = table.concat(Lines, "\n");
    if (DebindCopyFrame) then
        DebindCopyFrame:ShowText(text);
    else
        print(text);
    end
end;
