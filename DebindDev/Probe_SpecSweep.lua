-- Probe_SpecSweep.lua
-- One-shot probe: every spell **every specialization of this character's class** can obtain, and
-- for each one the base/override relation and the three disposition questions. Written to
-- `DebindDevDB`, not to the screen, because the answer is a few thousand rows and has to be read
-- outside the game.
--
-- **What it is for.** `adding-hover-and-mouseover-cast.md` needs to know which spells
-- `C_ClickBindings.CanSpellBeClickBound`, `IsSpellHelpful` and `IsSpellHarmful` disagree about, and
-- `resolving-a-stored-spell-id.md` needs the override families across specializations rather than
-- the one the character happens to be standing in. `Probe_SpellDisposition.lua` answers both for
-- the **active** specialization only, and a spellbook row this one cannot see is exactly where the
-- surprises are.
--
-- **How each part reaches a specialization other than the active one:**
--   spellbook   the book already holds every specialization's skill lines. `offSpecID` on
--               `GetSpellBookSkillLineInfo` names the non-active one a line belongs to, which is
--               what the book page draws greyed (`Blizzard_SpellBookCategory.lua:211`).
--   talents     `C_ClassTalents.InitializeViewLoadout(specID, level)` then
--               `Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID` as the config, which is how the
--               talent frame draws an imported loadout for a specialization nobody is standing in
--               (`Blizzard_ClassTalentImportExport.lua:254-257`). The **active** specialization is
--               walked through its own config instead, since that is the only one whose `taken`
--               means anything.
--
--               **Measured 2026-09-12, and this is why the view config is here at all:** walking
--               the class tree once under the active config reached 118 nodes on a Discipline
--               priest and every spec-currency node in them was Discipline's. `Void Eruption`,
--               `Dark Ascension`, `Apotheosis` and `Divine Hymn` were absent from the talent rows
--               altogether. One tree does hold every specialization's nodes
--               (`Blizzard_ClassTalentImportExport.lua:30`), but `GetNodeInfo` under a config
--               answers for that config's specialization alone.
--
--               **A condition's `specSetID` is not the specialization gate it looks like.** Read
--               that way the same sweep put `Psychic Scream` under Shadow and `Holy Nova` under
--               Holy while both were visible to Discipline: those conditions are
--               `Granted`/`Increased` (a free rank for one specialization), not visibility. So
--               `isVisible` under each specialization's own config is what attributes a node, and
--               the conditions are stored as data with their `type` beside them rather than
--               being read as an answer.
--   relations   `C_Spell.GetBaseSpell` and `C_Spell.GetOverrideSpell` both take a specialization
--               as their second argument, so the relation is asked per specialization without
--               standing in one.
--
-- **Two things cannot be reached from one specialization, and that is why this also runs on a
-- specialization change rather than at login alone:**
--   the trio    `CanSpellBeClickBound`, `IsSpellHelpful`, `IsSpellHarmful` and `IsSpellPassive`
--               take no specialization argument. Whatever they answer is the active
--               specialization's answer.
--   pvp         `GetPvpTalentSlotInfo` answers for the active specialization only. There is no
--               per-specialization form of it.
-- So each sweep is filed under the specialization it was taken in (`sweeps[specID]`), and visiting
-- all of them fills the table in. Nothing is merged across sweeps: a stored row says which
-- specialization measured it.
--
-- Usage:
--   it runs itself a few seconds after login and after a specialization change
--   /ss          what is stored, in one screenful
--   /ss now      sweep again without waiting
--   /ss wipe     drop this character's record
--
-- Answer found, delete the file and its TOC line.

local CHAIN_CAP = 8;

--- The index the initial specialization sits at, for every class. Not a count: a class with two
--- specializations has 1, 2 and 5 and nothing at 3 or 4 (`Debind/Constants.lua`, which this file
--- cannot reach -- DebindDev loads ahead of Debind).
local INITIAL_SPEC_INDEX = 5;

local PLAYER_BANK = Enum.SpellBookSpellBank.Player;

--- **Ids no walk here reaches, written by hand.** `Void Volley` (1242173) replaces `Voidform`
--- (228260) on a shadow priest (258) under some state, and it is in no spellbook row and no talent
--- definition, so nothing in this file would ever name it (owner, 2026-09-12). It is what
--- `Probe_KnownFlip.lua` was written around: a spell that replaces another mid-fight is the case the
--- baked `known` axis assumes cannot happen.
---
--- A seeded id is measured like any other -- the trio, the relations per specialization -- and
--- carries `seed` in `src` so a reader can tell it was not found.
local SEEDS = { 1242173 };

local function Bit(v)
    return v and 1 or nil;
end

--- Every specialization of this character's class, the initial one included.
local function Specs()
    local classID = select(3, UnitClass("player"));
    local out = {};
    local count = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0;
    for index = 1, count do
        local id, name = C_SpecializationInfo.GetSpecializationInfo(index);
        if (id and id ~= 0) then
            out[#out + 1] = { i = index, id = id, name = name };
        end
    end
    local initialID, initialName = C_SpecializationInfo.GetSpecializationInfo(INITIAL_SPEC_INDEX);
    if (initialID and initialID ~= 0) then
        out[#out + 1] = { i = INITIAL_SPEC_INDEX, id = initialID, name = initialName };
    end
    return out;
end

--- One row in `spells`: what does not vary by specialization, plus the trio, which varies by
--- specialization but cannot be asked about one. `fbase` is `FindBaseSpellByID`, which has no
--- specialization argument either -- `GetBaseSpell` is the one that does, and it is in `rel`.
local function SpellFacts(id)
    local canBind = C_ClickBindings and C_ClickBindings.CanSpellBeClickBound(id);
    local fbase = C_SpellBook.FindBaseSpellByID(id);
    return {
        n = C_Spell.GetSpellName(id),
        p = Bit(C_Spell.IsSpellPassive(id)),
        b = Bit(canBind),
        h = Bit(C_Spell.IsSpellHelpful(id)),
        x = Bit(C_Spell.IsSpellHarmful(id)),
        fbase = (fbase and fbase ~= id) and fbase or nil,
    };
end

--- Every override `id` can reach **in `specID`**, in the client's own order. `onlyKnown=false` asks
--- for the ones no form or buff has brought up yet; the walk takes the last answer out of the
--- running to get the next, which is what `ignoreOverrideSpellID` is for. `seen` stops a pair that
--- answers each other.
local function OverrideChain(id, specID, discovered)
    local chain, seen, ignore = nil, {}, 0;
    for _ = 1, CHAIN_CAP do
        local got = C_Spell.GetOverrideSpell(id, specID, false, ignore);
        if (not got or got == id or seen[got]) then
            break;
        end
        seen[got] = true;
        chain = chain or {};
        chain[#chain + 1] = got;
        discovered[got] = true;
        ignore = got;
    end
    return chain;
end

--- The per-specialization half: base and overrides for the ids in `queue`, asked with the
--- specialization as the second argument. **Empty rows are dropped**, since most spells are their
--- own base and override nothing, and keeping them would treble the file for no answer.
---
--- `discovered` collects the ids the chains named, a set this round does not cover. It is a table of
--- its own and not the found set the queue came out of, because adding keys to a table while
--- `pairs` walks it is what Lua leaves undefined.
local function Relations(specID, queue, discovered, out)
    for i = 1, #queue do
        local id = queue[i];
        local base = C_Spell.GetBaseSpell(id, specID);
        local known = C_Spell.GetOverrideSpell(id, specID, true, 0);
        local chain = OverrideChain(id, specID, discovered);
        if ((base and base ~= id) or (known and known ~= id) or chain) then
            out[id] = {
                base = (base and base ~= id) and base or nil,
                ovrk = (known and known ~= id) and known or nil,
                ovr = chain,
            };
        end
    end
end

--- The spellbook, every skill line. `specID` is the line's own specialization and `off` says it is
--- one this character is not standing in; both are nil on a line no specialization owns (general,
--- racials, professions).
---
--- **`actionID` is the base id and `spellID` is the override-applied one** -- the book draws the
--- second and a binding may hold either, so both are recorded. On a flyout row `actionID` is the
--- flyout id instead, and the slots inside carry the spells.
local function Book(rows, found)
    for index = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(index);
        if (line) then
            local first = line.itemIndexOffset + 1;
            for slot = first, first + line.numSpellBookItems - 1 do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER_BANK);
                if (info) then
                    local row = {
                        line = line.name,
                        spec = line.specID,
                        off = Bit(line.offSpecID ~= nil),
                        hidden = Bit(line.shouldHide),
                        type = info.itemType,
                        action = info.actionID,
                        id = info.spellID,
                        lvl = C_SpellBook.GetSpellBookItemLevelLearned(slot, PLAYER_BANK),
                    };
                    -- **`FutureSpell` counts as a spell here.** It is a row the book draws greyed
                    -- because the character has not reached its level, and its `actionID` is a real
                    -- spell id -- which is what an off-spec row is too, though that one comes back
                    -- as `Spell` with the greying carried by `offSpecID` instead
                    -- (`Blizzard_SpellBookItem.lua:220`).
                    if (info.itemType == Enum.SpellBookItemType.Spell
                        or info.itemType == Enum.SpellBookItemType.FutureSpell) then
                        found[info.actionID] = found[info.actionID] or "book";
                        if (info.spellID) then
                            found[info.spellID] = found[info.spellID] or "book";
                        end
                    elseif (info.itemType == Enum.SpellBookItemType.Flyout) then
                        local _, _, numSlots = GetFlyoutInfo(info.actionID);
                        local slots = {};
                        for i = 1, (numSlots or 0) do
                            local spellID, overrideID, isKnown = GetFlyoutSlotInfo(info.actionID, i);
                            if (spellID) then
                                slots[#slots + 1] = {
                                    id = spellID,
                                    ovr = (overrideID ~= spellID) and overrideID or nil,
                                    known = Bit(isKnown),
                                };
                                found[spellID] = found[spellID] or "flyout";
                                if (overrideID) then
                                    found[overrideID] = found[overrideID] or "flyout";
                                end
                            end
                        end
                        row.slots = slots;
                    end
                    rows[#rows + 1] = row;
                end
            end
        end
    end
end

--- Every condition on a node, as data. **Not an attribution**: a condition carrying a `specSetID`
--- may be `Granted` or `Increased`, which is a free rank for those specializations rather than a
--- gate on who sees the node (`Psychic Scream` and `Holy Nova` are both, measured 2026-09-12). The
--- `type` is stored beside the set so a reader can tell the two apart, and which specializations a
--- node belongs to is taken from `isVisible` under that specialization's own config.
local function Conditions(configID, node)
    local conditionIDs = node.conditionIDs;
    local out;
    for i = 1, (conditionIDs and #conditionIDs or 0) do
        local cond = C_Traits.GetConditionInfo(configID, conditionIDs[i]);
        if (cond and cond.specSetID) then
            out = out or {};
            out[#out + 1] = {
                set = cond.specSetID,
                specs = C_SpecializationInfo.GetSpecIDs(cond.specSetID),
                type = cond.type,
                gate = Bit(cond.isGate),
                granted = cond.ranksGranted,
            };
        end
    end
    return out;
end

--- One tree under one config: every entry of every node. **`entryIDs` and not
--- `entryIDsWithCommittedRanks`**, because the talent nobody picked is half of what this probe is
--- for, and both hero trees rather than the chosen one for the same reason.
---
--- Entry facts that do not vary by specialization go in `entries` and are written once. What the
--- config answers about the node -- visible, taken, the hero tree being live -- goes in `rows`,
--- keyed by entry, because that is what differs between one specialization's config and another's.
local function WalkTree(configID, treeID, entries, rows, found, stats)
    local nodes = C_Traits.GetTreeNodes(treeID) or {};
    stats.nodes = stats.nodes + #nodes;
    for j = 1, #nodes do
        local nodeID = nodes[j];
        local node = C_Traits.GetNodeInfo(configID, nodeID);
        local entryIDs = node and node.entryIDs;
        if (not node) then
            stats.noInfo = stats.noInfo + 1;
        elseif (not entryIDs or #entryIDs == 0) then
            stats.noEntries = stats.noEntries + 1;
        else
            local cost = C_Traits.GetNodeCost(configID, nodeID);
            for k = 1, #entryIDs do
                local entryID = entryIDs[k];
                local entry = C_Traits.GetEntryInfo(configID, entryID);
                -- No `definitionID` is a subtree selection entry, which names no spell.
                local definition = entry and entry.definitionID
                    and C_Traits.GetDefinitionInfo(entry.definitionID);
                local id = definition and definition.spellID;
                if (id) then
                    found[id] = found[id] or "talent";
                    if (definition.overriddenSpellID) then
                        found[definition.overriddenSpellID] =
                            found[definition.overriddenSpellID] or "replaced";
                    end
                    if (not entries[entryID]) then
                        entries[entryID] = {
                            tree = treeID,
                            node = nodeID,
                            id = id,
                            repl = definition.overriddenSpellID,
                            name = definition.overrideName,
                            sub = node.subTreeID,
                            cur = cost and cost[1] and cost[1].ID or nil,
                            cond = Conditions(configID, node),
                        };
                    end
                    rows[entryID] = {
                        vis = Bit(node.isVisible),
                        subActive = Bit(node.subTreeActive),
                        taken = Bit(node.activeEntry and node.activeEntry.entryID == entryID),
                    };
                    stats.rows = stats.rows + 1;
                end
            end
        end
    end
end

--- The trait tree once per specialization. The active one is walked through its own config, which is
--- the only place `taken` means anything; the rest go through the view config, which is what the
--- talent frame itself puts an imported loadout in
--- (`Blizzard_ClassTalentImportExport.lua:254-257`).
---
--- **`InitializeViewLoadout` has to come before the walk and there is nothing to undo after it.**
--- It fills a config of the client's own (`VIEW_TRAIT_CONFIG_ID`), and the talent frame picks its
--- config up fresh every time it refreshes (`Blizzard_ClassTalentsFrame.lua:861-871`), so nothing
--- the reader sees is left standing on it.
local function Talents(specs, entries, bySpec, found, stats)
    local activeConfigID = C_ClassTalents.GetActiveConfigID();
    local activeSpecIndex = C_SpecializationInfo.GetSpecialization() or 0;
    local activeSpecID = C_SpecializationInfo.GetSpecializationInfo(activeSpecIndex);
    local viewConfigID = Constants and Constants.TraitConsts
        and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID;
    local level = UnitLevel("player") or 80;

    for i = 1, #specs do
        local specID = specs[i].id;
        local treeID = C_ClassTalents.GetTraitTreeForSpec(specID);
        local configID = activeConfigID;
        if (specID ~= activeSpecID) then
            if (not viewConfigID) then
                treeID = nil;
            else
                C_ClassTalents.InitializeViewLoadout(specID, level);
                configID = viewConfigID;
            end
        end

        local rows, stat = {}, { nodes = 0, noInfo = 0, noEntries = 0, rows = 0 };
        if (treeID and configID) then
            WalkTree(configID, treeID, entries, rows, found, stat);
        end
        stat.tree = treeID;
        stat.config = configID;
        bySpec[specID] = rows;
        stats[specID] = stat;
    end

    return activeConfigID;
end

--- PvP talents. **The active specialization's alone**, and the slot count stops where the client
--- does because it differs by expansion.
local function Pvp(rows, found)
    local slot = 1;
    while (true) do
        local info = C_SpecializationInfo.GetPvpTalentSlotInfo(slot);
        if (not info) then
            return;
        end
        local available = info.availableTalentIDs or {};
        for i = 1, #available do
            local talent = C_SpecializationInfo.GetPvpTalentInfo(available[i]);
            if (talent and talent.spellID) then
                found[talent.spellID] = found[talent.spellID] or "pvp";
                rows[#rows + 1] = {
                    slot = slot,
                    talent = available[i],
                    id = talent.spellID,
                    taken = Bit(talent.selected),
                };
            end
        end
        slot = slot + 1;
    end
end

--- Does the specialization argument on `GetBaseSpell` / `GetOverrideSpell` mean a specialization
--- id? The docs say "which Class Specialization to consider" and `0` is the current one, which
--- leaves a specialization **index** as the other reading, and the two are different numbers for
--- the same thing. For the active specialization the id form has to answer what `0` answers; a
--- count here that is not zero says the argument is not what this file assumes and the whole `rel`
--- table is then measuring the wrong thing.
local function CheckSpecArg(ids, activeSpecID)
    local disagree = 0;
    for id in pairs(ids) do
        if (C_Spell.GetBaseSpell(id, activeSpecID) ~= C_Spell.GetBaseSpell(id, 0)
            or C_Spell.GetOverrideSpell(id, activeSpecID, false, 0)
                ~= C_Spell.GetOverrideSpell(id, 0, false, 0)) then
            disagree = disagree + 1;
        end
    end
    return disagree;
end

--- Did the view config actually reach a tree the active config cannot? **This is the check the
--- first version of this file did not have**, and the walk it was missing looked exactly like a
--- complete one: 118 nodes, no error, and both other specializations' spec trees absent.
---
--- `visible` is how many of a specialization's entries its own config calls visible, and `own` how
--- many of those the active specialization does not see. A specialization whose `own` is zero was
--- not reached, whatever else the numbers say.
local function CheckReach(specs, bySpec, activeSpecID)
    local out = {};
    local active = bySpec[activeSpecID] or {};
    for i = 1, #specs do
        local specID = specs[i].id;
        local visible, own = 0, 0;
        for entryID, row in pairs(bySpec[specID] or {}) do
            if (row.vis == 1) then
                visible = visible + 1;
                local mine = active[entryID];
                if (specID ~= activeSpecID and (not mine or mine.vis ~= 1)) then
                    own = own + 1;
                end
            end
        end
        out[specID] = { visible = visible, own = own };
    end
    return out;
end

local function Sweep()
    local activeSpecIndex = C_SpecializationInfo.GetSpecialization() or 0;
    local activeSpecID = C_SpecializationInfo.GetSpecializationInfo(activeSpecIndex);

    local specs = Specs();
    local found = {};
    local book, pvp = {}, {};
    local entries, bySpec, treeStats = {}, {}, {};
    Book(book, found);
    local configID = Talents(specs, entries, bySpec, found, treeStats);
    Pvp(pvp, found);

    -- **After the walks, so a seed the client does name keeps the source that named it.** A seed
    -- still reading `seed` in `src` is one nothing else reached, which is the claim `SEEDS` is
    -- making and worth being able to check.
    for i = 1, #SEEDS do
        found[SEEDS[i]] = found[SEEDS[i]] or "seed";
    end

    -- **The relation walk names ids nothing else did** -- an override no talent and no book row
    -- mentions -- and each of those has relations of its own, so the walk runs again over what the
    -- last round turned up. The cap stops a chain that never closes; `CHAIN_CAP` inside one chain is
    -- the other half of the same belt.
    local rel = {};
    for i = 1, #specs do
        rel[specs[i].id] = {};
    end

    local queue = {};
    for id in pairs(found) do
        queue[#queue + 1] = id;
    end

    for _ = 1, CHAIN_CAP do
        if (#queue == 0) then
            break;
        end
        local discovered = {};
        for i = 1, #specs do
            Relations(specs[i].id, queue, discovered, rel[specs[i].id]);
        end
        queue = {};
        for id in pairs(discovered) do
            if (not found[id]) then
                found[id] = "ovr";
                queue[#queue + 1] = id;
            end
        end
    end

    local spells, count = {}, 0;
    for id in pairs(found) do
        spells[id] = SpellFacts(id);
        count = count + 1;
    end

    return {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(1, GetBuildInfo()),
        interface = select(4, GetBuildInfo()),
        level = UnitLevel("player"),
        activeSpecIndex = activeSpecIndex,
        configID = configID,
        src = found,
        spells = spells,
        book = book,
        entries = entries,
        bySpec = bySpec,
        pvp = pvp,
        rel = rel,
        checks = {
            spells = count,
            specArgDisagree = CheckSpecArg(found, activeSpecID),
            reach = CheckReach(specs, bySpec, activeSpecID),
            trees = treeStats,
            clickBindings = Bit(C_ClickBindings ~= nil),
        },
    }, activeSpecID, specs;
end

local function CharKey()
    local name = UnitName("player");
    local realm = GetRealmName();
    return (name or "?") .. "-" .. (realm or "?");
end

local function Store()
    local record, activeSpecID, specs = Sweep();
    if (not activeSpecID or activeSpecID == 0) then
        return nil, "no active specialization";
    end

    DebindDevDB = DebindDevDB or {};
    local all = DebindDevDB.specSweep;
    if (not all) then
        all = {};
        DebindDevDB.specSweep = all;
    end

    local key = CharKey();
    local entry = all[key];
    if (not entry) then
        entry = {};
        all[key] = entry;
    end
    local className, classTag, classID = UnitClass("player");
    entry.className = className;
    entry.class = classTag;
    entry.classID = classID;
    entry.specs = specs;
    entry.sweeps = entry.sweeps or {};
    entry.sweeps[activeSpecID] = record;

    return record;
end

local pending = 0;

local function Try()
    -- The trait config and the spellbook both arrive after `PLAYER_LOGIN`, and a sweep taken
    -- before them writes a record that looks complete and holds nothing.
    if (C_ClassTalents.GetActiveConfigID()
        and (C_SpellBook.GetNumSpellBookSkillLines() or 0) > 0) then
        local record, err = Store();
        if (record) then
            local entries = 0;
            for _ in pairs(record.entries) do
                entries = entries + 1;
            end
            print(format("|cff44ff44Debind|r specSweep: %d spells, %d talent entries, %d book rows",
                record.checks.spells, entries, #record.book));
        else
            print("|cffff4444Debind|r specSweep: " .. tostring(err));
        end
        return;
    end
    pending = pending + 1;
    if (pending > 10) then
        print("|cffff4444Debind|r specSweep: the client never answered");
        return;
    end
    C_Timer.After(2, Try);
end

local function Schedule()
    pending = 0;
    C_Timer.After(3, Try);
end

local probe = CreateFrame("Frame");
probe:RegisterEvent("PLAYER_LOGIN");
-- **A specialization change and not login alone.** The trio and the pvp slots answer for the
-- active specialization only, so they are filled in by visiting each one.
probe:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
probe:SetScript("OnEvent", Schedule);

local function Report()
    local entry = DebindDevDB and DebindDevDB.specSweep and DebindDevDB.specSweep[CharKey()];
    if (not entry) then
        print("specSweep: nothing stored for this character");
        return;
    end
    print(format("specSweep %s (%s)", CharKey(), tostring(entry.class)));
    for i = 1, #(entry.specs or {}) do
        local spec = entry.specs[i];
        local record = entry.sweeps and entry.sweeps[spec.id];
        print(format("  %d %s  %s", spec.id, tostring(spec.name),
            record and format("swept %s: %d spells, specArg=%d",
                record.at, record.checks.spells, record.checks.specArgDisagree)
                or "|cffff8800not swept|r"));
    end

    -- **Which specializations the last sweep's talent walk actually reached.** `own` is the count of
    -- entries a specialization sees that the swept one does not, and a zero there is a tree that was
    -- not read -- the failure the first version of this file shipped with.
    local last;
    for _, record in pairs(entry.sweeps or {}) do
        if (not last or record.at > last.at) then
            last = record;
        end
    end
    for i = 1, #(entry.specs or {}) do
        local spec = entry.specs[i];
        local reach = last and last.checks.reach and last.checks.reach[spec.id];
        local stat = last and last.checks.trees and last.checks.trees[spec.id];
        if (reach and stat) then
            print(format("    tree %s for %d: %d nodes, %d visible entries, %d not the swept one's",
                tostring(stat.tree), spec.id, stat.nodes, reach.visible, reach.own));
        end
    end
end

SLASH_DEBINDSS1 = "/ss";
SlashCmdList.DEBINDSS = function(msg)
    local arg = strtrim(strlower(msg or ""));
    if (arg == "wipe") then
        if (DebindDevDB and DebindDevDB.specSweep) then
            DebindDevDB.specSweep[CharKey()] = nil;
        end
        print("specSweep: this character's record dropped");
    elseif (arg == "now") then
        pending = 0;
        Try();
    else
        Report();
    end
end;
