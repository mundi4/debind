local _, DebindPrivate = ...;

local GetSpellSubtext = C_Spell.GetSpellSubtext;

local Spells = {};
DebindPrivate.Spells = Spells;

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
                    --
                    -- **`actionID` is a spell id only on a row that is a spell.** On a flyout it
                    -- is the flyout id and on a pet action the pet action id, and neither is
                    -- caught by the guard above: `GetSpellBookItemLevelLearned` answers 0 for a
                    -- row that is not a spell, and 0 is true in Lua. One of those filed as
                    -- "level 0" is fixed for good, so a binding on a spell whose id it collides
                    -- with has its `[known:]` answer nailed down for the rest of the rebuild.
                    Record(out, info.spellID, level);
                    if (info.itemType == Enum.SpellBookItemType.Spell) then
                        Record(out, info.actionID, level);
                    end
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

--- Which spells' `[known:]` answer cannot move before the next rebuild
--- (`devdocs/baking-the-known-condition.md`). `spellID -> level`: the answer is fixed once the
--- character has reached that level, and `0` is a spell whose answer never depended on level.
---
--- **The table says only that the answer is fixed, never what it is.** What it is gets measured
--- with `SecureCmdOptionParse` at the bake, against the same string the snippet would have used,
--- so nothing here re-implements `[known:]`.
---
--- `api` holds every client call this walk makes, in one table so a spec can hand it a world of
--- its own.
function Spells.Build(api)
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
--- **An empty table is not kept.** Every character has spells, so nothing in it means the client
--- had not answered yet rather than that there is nothing to hold, and keeping that would settle
--- the answer for the rest of the specialization. Walking again next rebuild costs one walk in a
--- case that should not happen.
function Spells.GetTable()
    local spec = C_SpecializationInfo.GetSpecialization() or 0;
    if (cached == nil or cachedSpec ~= spec) then
        local built = Spells.Build(LiveAPI());
        if (next(built) == nil) then
            return built;
        end
        cached = built;
        cachedSpec = spec;
    end
    return cached;
end

--- Whether this spell's `[known:]` answer can still move before the next rebuild. A spell in the
--- table but below its level is **not** fixed: a level-up flips it with no rebuild behind it.
local function IsFixed(spellID)
    local level = spellID and Spells.GetTable()[spellID];
    return level ~= nil and level <= (UnitLevel("player") or 0);
end

--- What `[known:<spell>]` answers for the rest of this rebuild: `true` if it holds, `false` if it
--- cannot, and **nil where the answer can still move**, which is the axis staying as it was.
---
--- **Measured with the string the snippet itself would have used**, so the two cannot part.
function Spells.SettleKnown(spellID)
    if (not IsFixed(spellID)) then
        return nil;
    end
    return SecureCmdOptionParse("[known:" .. spellID .. "]") and true or false;
end

--- The value a spell goes on a secure button under. **A name and not an id**, because spells share
--- names across ids (a specialization's own version of a shapeshift), and an id bound here does not
--- fire for the other one. The subtext is what tells two same-named spells apart, so it comes along
--- in the client's own parenthesised form.
---
--- **Pure, and separate from `GetSpellCastName` for one reason**: `DescribeBinding` has to spell the
--- same value and may not ask the client anything (`UpdateBindings.lua`'s `CollectBindingFacts`
--- holds every call in that path). It arrives here with the two halves already in hand.
---
--- Nil name in, nil out. The callers fall back to the id, which at least fires for the reader who
--- is on the specialization that has it.
function DebindPrivate.ComposeSpellCastName(name, subtext)
    if (not name) then
        return nil;
    end
    if (subtext and subtext ~= "") then
        return name .. "(" .. subtext .. ")";
    end
    return name;
end

local ComposeSpellCastName = DebindPrivate.ComposeSpellCastName;

--- The same value, asked of the client. **The id is taken as given**: each caller resolves its own,
--- and they do not resolve it alike. A stored action holds whatever id the reader picked and needs
--- `FindBaseSpellByID` first; a flyout slot is handed its base id and its override as two separate
--- returns, so resolving again there would be asking a question already answered.
function DebindPrivate.GetSpellCastName(spellID)
    -- Reached through `DebindPrivate` rather than an upvalue: `Misc.lua` defines it and loads
    -- after this file (`Debind.xml`).
    local name = DebindPrivate.GetSpellNameAndIconID(spellID);
    return ComposeSpellCastName(name, name and GetSpellSubtext(spellID));
end

--- The id a spell should be **stored** under: the topmost base, resolved at the moment the reader
--- adds it.
---
--- **The answer is only available while the build that produced the id stands.** Both resolvers
--- read the talent tree rather than the spell data, so an id a talent combination created answers
--- its base while those talents are taken and answers itself once they are not. 390414 is that:
--- it comes back as 194223 only while `Celestial Alignment`, `Orbital Strike` and
--- `Incarnation: Chosen of Elune` are all taken, and after a respec nothing in the client can say
--- what it was. **So it has to be resolved on the way in, not on the way out.**
---
--- **A loop and not one call**, because one step is only known to reach one level and an id two
--- levels down would keep the level between. `seen` is what stops a pair that answers each other
--- from spinning; the cap is the same belt for a longer cycle.
function DebindPrivate.ResolveBaseSpell(spellID)
    local seen = {};
    for _ = 1, 8 do
        if (not spellID or seen[spellID]) then
            return spellID;
        end
        seen[spellID] = true;
        local base = C_SpellBook.FindBaseSpellByID(spellID);
        if (not base or base == spellID) then
            return spellID;
        end
        spellID = base;
    end
    return spellID;
end
