local _, DebindPrivate = ...;

--- Which spells' `[known:]` answer cannot move before the next rebuild
--- (`devdocs/baking-the-known-condition.md`). `spellID -> level`: the answer is fixed once the
--- character has reached that level, and `0` is a spell whose answer never depended on level.
---
--- **The table says only that the answer is fixed, never what it is.** What it is gets measured
--- with `SecureCmdOptionParse` at the bake, against the same string the snippet would have used,
--- so nothing here re-implements `[known:]`.
local KnownSpells = {};
DebindPrivate.KnownSpells = KnownSpells;

--- The higher level wins when two walks name the same spell, because a level the character has
--- not reached yet is the one thing that can still flip the answer inside a fight. Merging the
--- other way would bake a `false` that a level-up undoes with no rebuild behind it.
local function Record(out, spellID, level)
    if (not spellID) then
        return;
    end
    local existing = out[spellID];
    if (existing == nil or level > existing) then
        out[spellID] = level;
    end
end

--- Spells learned by levelling. Level does not go down, so one of these is unforgettable once it
--- is learned, and the level it is learned at is what says when that starts.
---
--- **The player bank only.** A summon changes the pet book in combat.
local function AddSpellBook(out, api)
    local bank = api.playerBank;
    for index = 1, (api.GetNumSpellBookSkillLines() or 0) do
        local line = api.GetSpellBookSkillLineInfo(index);
        if (line) then
            local first = line.itemIndexOffset + 1;
            for slot = first, first + line.numSpellBookItems - 1 do
                local info = api.GetSpellBookItemInfo(slot, bank);
                local level = info and api.GetSpellBookItemLevelLearned(slot, bank);
                if (level) then
                    -- Three keys because which one a binding carries is not fixed: the catalog
                    -- stores the base id (`ActionCatalog.lua:469`) and `binding.spell` arrives by
                    -- other routes.
                    Record(out, info.spellID, level);
                    Record(out, info.actionID, level);
                    Record(out, info.spellID and api.FindBaseSpellByID(info.spellID), level);
                end
            end
        end
    end
end

--- Spells a talent grants or replaces. Talents cannot be changed in combat and every change
--- raises a rebuild (`Events.lua:169`, `Events.lua:250`).
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
            -- **`entryIDs`, not `entryIDsWithCommittedRanks`.** A selection node offers two
            -- spells and the one nobody picked belongs here too: picking it is exactly what
            -- moves its `known`. Subtree nodes are in this same walk for the same reason.
            local entryIDs = node and node.entryIDs;
            for k = 1, (entryIDs and #entryIDs or 0) do
                local entry = api.GetEntryInfo(configID, entryIDs[k]);
                -- No `definitionID` is a subtree selection entry, which names no spell.
                local definition = entry and entry.definitionID
                    and api.GetDefinitionInfo(entry.definitionID);
                if (definition) then
                    Record(out, definition.spellID, 0);
                    -- The base spell this one replaces: taking the talent moves *its* answer.
                    Record(out, definition.overriddenSpellID, 0);
                end
            end
        end
    end
end

--- PvP talents. The slot count differs by expansion, so the walk stops where the client does.
local function AddPvpTalents(out, api)
    local slot = 1;
    while (true) do
        local info = api.GetPvpTalentSlotInfo(slot);
        if (not info) then
            return;
        end
        local available = info.availableTalentIDs;
        for i = 1, (available and #available or 0) do
            local talent = api.GetPvpTalentInfo(available[i]);
            if (talent) then
                Record(out, talent.spellID, 0);
            end
        end
        slot = slot + 1;
    end
end

--- Every client call this walk makes, in one table so a spec can hand it a world of its own.
function KnownSpells.Build(api)
    local out = {};
    AddSpellBook(out, api);
    AddTraits(out, api);
    AddPvpTalents(out, api);
    return out;
end

local function LiveAPI()
    return {
        playerBank = Enum.SpellBookSpellBank.Player,
        GetNumSpellBookSkillLines = C_SpellBook.GetNumSpellBookSkillLines,
        GetSpellBookSkillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo,
        GetSpellBookItemInfo = C_SpellBook.GetSpellBookItemInfo,
        GetSpellBookItemLevelLearned = C_SpellBook.GetSpellBookItemLevelLearned,
        FindBaseSpellByID = C_SpellBook.FindBaseSpellByID,
        GetActiveConfigID = C_ClassTalents.GetActiveConfigID,
        GetConfigInfo = C_Traits.GetConfigInfo,
        GetTreeNodes = C_Traits.GetTreeNodes,
        GetNodeInfo = C_Traits.GetNodeInfo,
        GetEntryInfo = C_Traits.GetEntryInfo,
        GetDefinitionInfo = C_Traits.GetDefinitionInfo,
        GetPvpTalentSlotInfo = C_SpecializationInfo.GetPvpTalentSlotInfo,
        GetPvpTalentInfo = C_SpecializationInfo.GetPvpTalentInfo,
    };
end

local cached, cachedSpec;

--- **Kept per specialization and not per level.** What the table holds is the level a spell is
--- learned at rather than whether it has been, so levelling cannot make it stale. Talent picks
--- cannot either: the question is whether a spell comes from the tree at all, which is a property
--- of the tree. `GetActiveConfigID` answers for the active specialization only, and reaching
--- another one means switching to it, which is a specialization this cache has not met yet.
function KnownSpells.GetTable()
    local spec = C_SpecializationInfo.GetSpecialization() or 0;
    if (cached == nil or cachedSpec ~= spec) then
        cached = KnownSpells.Build(LiveAPI());
        cachedSpec = spec;
    end
    return cached;
end

--- Whether this spell's `[known:]` answer holds for the rest of this rebuild. False also covers
--- "in the table but not learned yet", which a level-up flips with no rebuild behind it.
function KnownSpells.IsFixed(spellID)
    local level = spellID and KnownSpells.GetTable()[spellID];
    return level ~= nil and level <= (UnitLevel("player") or 0);
end
