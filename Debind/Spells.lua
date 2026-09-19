local _, DebindPrivate = ...;

local GetSpellSubtext = C_Spell.GetSpellSubtext;

local Spells = {};
DebindPrivate.Spells = Spells;

--- The topmost spell this one replaces, and how many steps away it is. **A loop and not one
--- call**, because one step is only known to reach one level and an id two levels down would keep
--- the level between. `seen` is what stops a pair that answers each other from spinning; the cap
--- is the same belt for a longer cycle.
local function Climb(spellID, FindBaseSpellByID)
    local seen = {};
    for depth = 0, 8 do
        if (seen[spellID]) then
            return spellID, depth;
        end
        seen[spellID] = true;
        local base = FindBaseSpellByID(spellID);
        if (not base or base == spellID) then
            return spellID, depth;
        end
        spellID = base;
    end
    return spellID, 8;
end

--- What one walk is filling in. Two indexes over the same set of ids -- every spell this
--- specialization can obtain -- so the walk runs once and answers both questions.
---
---   learnLevelBySpellID   `spellID -> level`, for `[known:]` (below)
---   learnLevelByName      the same thing keyed by name, for a `known` that stores one
---                         (`making-known-a-spell-name.md`)
---   obtainableIDsByName   `name -> { spellID, ... }`, for `ResolveBase` (below)
---   nameAsked             ids already put to `GetSpellName`. `AddSpellBook` files one id under
---                         three keys and the merge meets it again, so without this the same id
---                         stands in a list twice and costs a client call each time.
---   nameBySpellID         what that question answered, so the id filed a second time still has
---                         its name to merge a level under.
local function NewWalk()
    return {
        learnLevelBySpellID = {},
        learnLevelByName = {},
        obtainableIDsByName = {},
        nameAsked = {},
        nameBySpellID = {},
    };
end

--- Files `spellID` under its name and answers what that name is, asking the client once per id.
local function RecordName(out, api, spellID)
    if (out.nameAsked[spellID]) then
        return out.nameBySpellID[spellID];
    end
    out.nameAsked[spellID] = true;
    local name = api.GetSpellName(spellID);
    if (not name) then
        return nil;
    end
    out.nameBySpellID[spellID] = name;
    local ids = out.obtainableIDsByName[name];
    if (not ids) then
        ids = {};
        out.obtainableIDsByName[name] = ids;
    end
    ids[#ids + 1] = spellID;
    return name;
end

--- The higher level wins when two walks name the same spell, because a level the character has
--- not reached yet is the one thing that can still flip the answer inside a fight. Merging the
--- other way would bake a `false` that a level-up undoes with no rebuild behind it.
---
--- **The name's level is merged here and not where the name is asked.** One id is filed again and
--- again (two book rows can share a base) and `RecordName` asks the client only the first time, so
--- a merge written beside that question keeps whichever level arrived first.
local function Record(out, api, spellID, level)
    if (not spellID) then
        return;
    end
    local existing = out.learnLevelBySpellID[spellID];
    if (existing == nil or level > existing) then
        out.learnLevelBySpellID[spellID] = level;
    end
    local name = RecordName(out, api, spellID);
    if (name) then
        local byName = out.learnLevelByName[name];
        if (byName == nil or level > byName) then
            out.learnLevelByName[name] = level;
        end
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
                    Record(out, api, info.spellID, level);
                    if (info.itemType == Enum.SpellBookItemType.Spell) then
                        Record(out, api, info.actionID, level);
                    end
                    Record(out, api, info.spellID and api.FindBaseSpellByID(info.spellID), level);
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
                    Record(out, api, definition.spellID, 0);
                    -- The base spell this one replaces: taking the talent moves *its* answer.
                    Record(out, api, definition.overriddenSpellID, 0);
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
                Record(out, api, talent.spellID, 0);
            end
        end
        slot = slot + 1;
    end
end

--- One walk over every spell this specialization can obtain -- **learned or not**, since a talent
--- nobody picked is exactly what moves once somebody picks it -- returning the three indexes over
--- it.
---
--- First: which spells' `[known:]` answer cannot move before the next rebuild
--- (`baking-the-known-condition.md`). `spellID -> level`: the answer is fixed once the
--- character has reached that level, and `0` is a spell whose answer never depended on level.
---
--- **That table says only that the answer is fixed, never what it is.** What it is gets measured
--- with `SecureCmdOptionParse` at the bake, against the same string the snippet would have used,
--- so nothing here re-implements `[known:]`.
---
--- Second: `name -> { spellID, ... }`, what `ResolveBase` walks back through when the client can
--- no longer place a stored id.
---
--- Third: the first table keyed by name, for a `known` condition that stores one
--- (`making-known-a-spell-name.md`). A name several ids share holds the highest of their
--- levels, because any one of them still below it flips the answer with no rebuild behind it.
---
--- `api` holds every client call this walk makes, in one table so a spec can hand it a world of
--- its own.
function Spells.Build(api)
    local out = NewWalk();
    AddSpellBook(out, api);
    AddTraits(out, api);
    AddPvpTalents(out, api);
    return out.learnLevelBySpellID, out.obtainableIDsByName, out.learnLevelByName;
end

--- The same walk, turned the other way up: `뿌리 spellID -> { spellID, ... }`, every spell this
--- specialization can obtain grouped under the one it ultimately replaces. The root stands in its
--- own list.
---
--- **What it is for is the `known` row's choices.** A reader who stored one branch has to be
--- offered the whole family to pick a question from, and one stored id reaches all of it: up to
--- the root with `ResolveBase`, then out through this table.
---
--- **Ordered root first and then by depth**, because the family is a chain and the rows should
--- read as one. Equal depth falls back to the id, which is not meaningful in itself -- it is there
--- so two walks of the same world cannot hand the reader the rows in a different order.
---
--- **Built on demand and not kept.** Only a menu asks, a menu opening is not a hot path, and a
--- third cache would be a third thing to invalidate. Walking again also means a menu cannot
--- inherit a half-filled walk from login (`EnsureWalked` turns away an empty one, not a short
--- one).
function Spells.BuildBranches(api)
    local out = NewWalk();
    AddSpellBook(out, api);
    AddTraits(out, api);
    AddPvpTalents(out, api);

    local byRoot, depths = {}, {};
    for spellID in pairs(out.learnLevelBySpellID) do
        local root, depth = Climb(spellID, api.FindBaseSpellByID);
        local list = byRoot[root];
        if (not list) then
            list = {};
            byRoot[root] = list;
        end
        list[#list + 1] = spellID;
        depths[spellID] = depth;
    end

    for _, list in pairs(byRoot) do
        table.sort(list, function(a, b)
            if (depths[a] ~= depths[b]) then
                return depths[a] < depths[b];
            end
            return a < b;
        end);
    end
    return byRoot;
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
        GetSpellName = C_Spell.GetSpellName,
    };
end

--- What `Spells.Build` last answered, and the specialization it was standing in when it did.
--- **`walkedSpecIndex` is `GetSpecialization`'s index and not a specialization id**, which is what
--- `SpecSpells.lua` keys its tables by; the two are different numbers for the same thing.
local learnLevelBySpellID, obtainableIDsByName, learnLevelByName, walkedSpecIndex;

--- **Kept per specialization and not per level.** What the level table holds is the level a spell
--- is learned at rather than whether it has been, so levelling cannot make it stale. Talent picks
--- cannot either: the question is whether a spell comes from the tree at all, which is a property
--- of the tree. `GetActiveConfigID` answers for the active specialization only, and reaching
--- another one means switching to it, which is a specialization this cache has not met yet.
--- **An empty walk is not kept.** Every character has spells, so nothing in it means the client
--- had not answered yet rather than that there is nothing to hold, and keeping that would settle
--- the answer for the rest of the specialization. Walking again next rebuild costs one walk in a
--- case that should not happen.
local function EnsureWalked()
    local specIndex = C_SpecializationInfo.GetSpecialization() or 0;
    if (learnLevelBySpellID == nil or walkedSpecIndex ~= specIndex) then
        local levels, byName, levelsByName = Spells.Build(LiveAPI());
        if (next(levels) == nil) then
            return levels, byName, levelsByName;
        end
        learnLevelBySpellID = levels;
        obtainableIDsByName = byName;
        learnLevelByName = levelsByName;
        walkedSpecIndex = specIndex;
    end
    return learnLevelBySpellID, obtainableIDsByName, learnLevelByName;
end

--- `spellID -> the level it is learned at`, for every spell this specialization can obtain.
function Spells.GetLearnLevels()
    return (EnsureWalked());
end

--- `name -> { spellID, ... }`, for every spell this specialization can obtain. **One name holds
--- several ids**: a talent version and the spell it replaces share theirs, which is the whole
--- reason this index is worth keeping.
function Spells.GetObtainableIDsByName()
    local _, byName = EnsureWalked();
    return byName;
end

--- `BuildBranches` against the client. **A fresh walk every call**, so it is for a menu and not
--- for a rebuild. A stored id reaches its own family by way of `ResolveBaseSpell`, whose answer
--- is the key into this.
function Spells.GetBranches()
    return Spells.BuildBranches(LiveAPI());
end

--- Whether this spell's `[known:]` answer can still move before the next rebuild. A spell in the
--- table but below its level is **not** fixed: a level-up flips it with no rebuild behind it.
---
--- **A name asks the same question of the name index.** That is what a `known` condition stores
--- (`making-known-a-spell-name.md`), and the value handed here is the one that goes into
--- the conditional either way.
local function IsFixed(value)
    local level;
    if (type(value) == "string") then
        local _, _, levelsByName = EnsureWalked();
        level = levelsByName[value];
    elseif (value ~= nil) then
        level = Spells.GetLearnLevels()[value];
    end
    return level ~= nil and level <= (UnitLevel("player") or 0);
end

--- What `[known:<spell>]` answers for the rest of this rebuild: `true` if it holds, `false` if it
--- cannot, and **nil where the answer can still move**, which is the axis staying as it was.
---
--- **Measured with the string the snippet itself would have used**, so the two cannot part.
function Spells.SettleKnown(value)
    if (not IsFixed(value)) then
        return nil;
    end
    return SecureCmdOptionParse("[known:" .. value .. "]") and true or false;
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
--- levels down would keep the level between. `Climb` is at the top of this file.

--- **Measured in game, 2026-09-12, on 390414** (`Incarnation: Chosen of Elune` under
--- `Celestial Alignment` + `Orbital Strike`): with `Orbital Strike` taken,
--- `C_SpellBook.FindBaseSpellByID`, `C_Spell.GetBaseSpell` and the global `FindBaseSpellByID` all
--- answer 194223; with it untaken all three answer 390414 back, and `GetOverrideSpell` answers
--- 390414 in both. So the climb above resolves the id **only while the talent combination that
--- created it still stands**, and a stored id outlives that.
---
--- **The name is what is left.** 390414 carries the same name as 102560, which the talent walk
--- still puts in the index, and climbing from there reaches 194223.
---
--- **The climb answers the id back in two different situations and the client cannot tell them
--- apart**: a spell that simply is its own root, and one whose build is gone. The index is what
--- separates them. It holds every id this specialization can obtain, so an id **in** it that
--- answers itself is the root and is left alone; one that is **not** in it is the orphan, and
--- only that one goes looking under its name.
---
--- Without that split the detour fires on every ordinary spell, and any namesake in the index
--- takes the binding over.
---
--- Among several ids under one name, the first that climbs anywhere wins. **Which one that is
--- does not reach the cast**: they share a name and the name is what goes on the button
--- (`ComposeSpellCastName`). It does reach `[known:]` and the icon, and neither has a rule saying
--- which of them the reader meant -- see `resolving-a-stored-spell-id.md`.
---
--- **The client's answer and nothing else.** For an id that is already standing this is the whole
--- of the question, and it is what a caller holding a **fresh** id wants: one that just came out
--- of the spellbook or off the cursor cannot have lost its build, so there is nothing for the
--- detour below to repair.
---
--- **It is also the only safe call for an id the index does not cover.** `AddSpellBook` walks the
--- player bank alone, so a pet ability and a flyout slot are missing from the index for a reason
--- that has nothing to do with a lost talent -- and `ResolveBase` reads every absence as a lost
--- talent. A warlock's imp casts `Singe Magic` and so does the player under Grimoire of Sacrifice
--- (`SpecSpells.lua`); through `ResolveBase` the pet row comes back holding the player's id.
function Spells.ClimbBase(spellID, api)
    if (not spellID) then
        return spellID;
    end
    return (Climb(spellID, api.FindBaseSpellByID));
end

--- `api` the way `Spells.Build` takes it, plus the index that walk made.
function Spells.ResolveBase(spellID, api)
    if (not spellID) then
        return spellID;
    end
    local climbed = Climb(spellID, api.FindBaseSpellByID);
    if (climbed ~= spellID) then
        return climbed;
    end
    local name = api.GetSpellName(spellID);
    local ids = name and api.obtainableIDsByName[name];
    for i = 1, (ids and #ids or 0) do
        if (ids[i] == spellID) then
            return spellID;
        end
    end
    for i = 1, (ids and #ids or 0) do
        local candidate = ids[i];
        climbed = Climb(candidate, api.FindBaseSpellByID);
        if (climbed ~= candidate) then
            return climbed;
        end
    end
    return spellID;
end

local _resolveAPI = {
    FindBaseSpellByID = function(spellID) return C_SpellBook.FindBaseSpellByID(spellID); end,
    GetSpellName = function(spellID) return C_Spell.GetSpellName(spellID); end,
};

--- **For a stored id**: one read back out of SavedVariables, which may have been written under a
--- talent build that is gone. Walks the name index where the client has nothing left to say.
function DebindPrivate.ResolveBaseSpell(spellID)
    _resolveAPI.obtainableIDsByName = Spells.GetObtainableIDsByName();
    return Spells.ResolveBase(spellID, _resolveAPI);
end

--- **For an id that just came from the client**: a spellbook row, a flyout slot, the cursor. It is
--- standing by definition, so the climb is the whole answer and the name index is not consulted --
--- which is what keeps a pet ability from being re-rooted onto a player spell of the same name.
function DebindPrivate.ClimbBaseSpell(spellID)
    return Spells.ClimbBase(spellID, _resolveAPI);
end
