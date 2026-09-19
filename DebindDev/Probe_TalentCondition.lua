-- Probe_TalentCondition.lua
-- What a talent condition's menu and its judgment can reach, measured per specialization and
-- written to `DebindDevDB`. `devdocs/adding-a-talent-condition.md` §6-1 is what this answers.
--
-- **Every number in it was first taken by hand in chat, one specialization deep, and two of the
-- readings were wrong.** `subTreeID` came back for the active specialization's two hero trees only,
-- which was read as "the other trees' nodes are not in the walk"; `Probe_SpecSweep.lua` had
-- already measured (2026-09-12) that `GetNodeInfo` answers for its config's specialization alone,
-- and that the view config reaches the others. A condition's `specSetID` was read as the
-- specialization gate, and the same file had already measured it to be `Granted`/`Increased` on
-- spells every specialization can see. So the readings are taken again here, through a config that
-- can see each specialization, and filed where they can be read side by side.
--
-- **The active specialization cannot be left to the view config.** `entryIDsWithCommittedRanks`
-- and the pvp slots are what "taken" means, and only the character's own config answers them. So
-- each sweep files itself under the specialization it was taken in and visiting all of them fills
-- the table; nothing is merged across sweeps.
--
-- **It is written for one pass.** Every node is stored rather than only the counts a question
-- happens to need today, because the reader gets one login and three specialization changes and a
-- number nobody thought to keep cannot be fetched afterwards. Each step is wrapped, so one call
-- that raises costs its own row instead of the sweep.
--
-- Usage:
--   it runs itself a few seconds after login and after a specialization change
--   /tc          what is stored, in one screenful
--   /tc now      sweep again without waiting
--   /tc wipe     drop this character's record
--
-- Answer found, delete the file and its TOC line.

--- The index the initial specialization sits at, for every class. Not a count
--- (`Debind/Constants.lua`, which this file cannot reach: DebindDev loads ahead of Debind).
local INITIAL_SPEC_INDEX = 5;

local function Bit(v)
    return v and 1 or nil;
end

--- A client call that may not be there, may raise, and may answer nothing. **Every call in this
--- file goes through it**: one raise would otherwise end the pass, and there is no second pass.
local function Ask(fn, ...)
    if (type(fn) ~= "function") then
        return nil, "missing";
    end
    local ok, a, b = pcall(fn, ...);
    if (not ok) then
        return nil, tostring(a);
    end
    return a, nil, b;
end

--- Every specialization of this character's class, the initial one included.
local function Specs()
    local classID = select(3, UnitClass("player"));
    local out = {};
    local count = Ask(C_SpecializationInfo.GetNumSpecializationsForClassID, classID) or 0;
    for index = 1, count do
        local id, _, name = Ask(C_SpecializationInfo.GetSpecializationInfo, index);
        if (id and id ~= 0) then
            out[#out + 1] = { i = index, id = id, name = name };
        end
    end
    local initialID, _, initialName = Ask(C_SpecializationInfo.GetSpecializationInfo,
        INITIAL_SPEC_INDEX);
    if (initialID and initialID ~= 0) then
        out[#out + 1] = { i = INITIAL_SPEC_INDEX, id = initialID, name = initialName };
    end
    return out;
end

local function ViewConfigID()
    return Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID;
end

--- The name an entry carries. `overrideName` is what the tree itself draws where it differs from
--- the spell's own name.
local function EntryName(definition)
    if (not definition) then
        return nil;
    end
    if (definition.overrideName) then
        return definition.overrideName;
    end
    if (definition.spellID) then
        return (Ask(C_Spell.GetSpellName, definition.spellID));
    end
    return nil;
end

--- Every entry of one node: what it grants, and whether this config calls it taken.
---
--- **`entryIDs` and `entryIDsWithCommittedRanks` are both recorded.** `Spells.lua` walks the first
--- on purpose, to reach the talent nobody picked; the second is the one a talent condition would
--- read and nothing in this repo has ever walked it.
local function Entries(configID, node, committedSet)
    local out = {};
    local entryIDs = node.entryIDs or {};
    for i = 1, #entryIDs do
        local entryID = entryIDs[i];
        local entry = Ask(C_Traits.GetEntryInfo, configID, entryID);
        -- No `definitionID` is a subtree selection entry, which names no spell.
        local definition = entry and entry.definitionID
            and Ask(C_Traits.GetDefinitionInfo, entry.definitionID);
        out[#out + 1] = {
            entry = entryID,
            id = definition and definition.spellID,
            name = EntryName(definition),
            repl = definition and definition.overriddenSpellID,
            sub = entry and entry.subTreeID,
            committed = Bit(committedSet[entryID]),
        };
    end
    return out;
end

--- Every condition on a node that names a set of specializations, **as data and not as an
--- attribution**: the type is stored beside the set because `Granted` and `Increased` carry one
--- too, and those are a free rank rather than a gate on who sees the node.
local function SpecConditions(configID, node)
    local conditionIDs = node.conditionIDs;
    local out;
    for i = 1, (conditionIDs and #conditionIDs or 0) do
        local cond = Ask(C_Traits.GetConditionInfo, configID, conditionIDs[i]);
        if (cond and cond.specSetID) then
            out = out or {};
            out[#out + 1] = {
                set = cond.specSetID,
                type = cond.type,
                gate = Bit(cond.isGate),
                granted = cond.ranksGranted,
                specs = Ask(C_SpecializationInfo.GetSpecIDs, cond.specSetID),
            };
        end
    end
    return out;
end

--- One specialization's whole tree under one config, node by node.
local function WalkTree(configID, treeID, own)
    local nodes = Ask(C_Traits.GetTreeNodes, treeID) or {};
    local out = {
        tree = treeID,
        config = configID,
        own = Bit(own),
        nodes = #nodes,
        visible = 0,
        noInfo = 0,
        committedCount = 0,
        bySubTree = {},
        byCurrency = {},
        rows = {},
    };

    for i = 1, #nodes do
        local nodeID = nodes[i];
        local node = Ask(C_Traits.GetNodeInfo, configID, nodeID);
        if (not node) then
            out.noInfo = out.noInfo + 1;
        else
            if (node.isVisible) then
                out.visible = out.visible + 1;
            end

            local committedSet = {};
            -- **Only where the config is the character's own.** Under the view config a committed
            -- rank is whatever loadout was last put there, which says nothing about the character.
            local committed = own and node.entryIDsWithCommittedRanks or {};
            for j = 1, #committed do
                committedSet[committed[j]] = true;
                out.committedCount = out.committedCount + 1;
            end

            local sub = node.subTreeID;
            if (sub) then
                local row = out.bySubTree[sub];
                if (not row) then
                    local info = Ask(C_Traits.GetSubTreeInfo, configID, sub);
                    row = {
                        name = info and info.name,
                        currency = info and info.traitCurrencyID,
                        active = Bit(info and info.isActive),
                        n = 0,
                        visible = 0,
                    };
                    out.bySubTree[sub] = row;
                end
                row.n = row.n + 1;
                if (node.isVisible) then
                    row.visible = row.visible + 1;
                end
            end

            local cost = Ask(C_Traits.GetNodeCost, configID, nodeID);
            local currency = cost and cost[1] and cost[1].ID;
            if (currency) then
                out.byCurrency[currency] = (out.byCurrency[currency] or 0) + 1;
            end

            out.rows[#out.rows + 1] = {
                node = nodeID,
                sub = sub,
                subActive = Bit(node.subTreeActive),
                vis = Bit(node.isVisible),
                avail = Bit(node.isAvailable),
                cur = currency,
                rank = node.ranksPurchased,
                type = node.type,
                cond = SpecConditions(configID, node),
                entries = Entries(configID, node, committedSet),
            };
        end
    end

    return out;
end

--- PvP talents. **The active specialization's alone**: no form of these calls takes a
--- specialization, which is the gap this probe is here to have on record rather than to close. The
--- slot count stops where the client does, since it differs by expansion.
local function Pvp()
    local out = {};
    local slot = 1;
    while (slot < 20) do
        local info = Ask(C_SpecializationInfo.GetPvpTalentSlotInfo, slot);
        if (not info) then
            return out;
        end
        local row = {
            slot = slot,
            enabled = Bit(info.enabled),
            level = info.level,
            selected = info.selectedTalentID,
            available = {},
        };
        local available = info.availableTalentIDs or {};
        for i = 1, #available do
            local talent = Ask(C_SpecializationInfo.GetPvpTalentInfo, available[i]);
            if (talent) then
                row.available[#row.available + 1] = {
                    talent = available[i],
                    id = talent.spellID,
                    name = talent.name,
                    taken = Bit(talent.selected),
                };
            end
        end
        out[#out + 1] = row;
        slot = slot + 1;
    end
    return out;
end

--- Did reading through the view config reach anything the active specialization's own config does
--- not? **This is the check the hand readings had no way to make.** A specialization whose subtree
--- rows are the active one's is a specialization that was not reached, whatever else the numbers
--- say.
local function CheckReach(bySpec, activeSpecID)
    local active = bySpec[activeSpecID];
    local activeSubs = active and active.bySubTree or {};
    local out = {};
    for specID, walk in pairs(bySpec) do
        local own = 0;
        for sub in pairs(walk.bySubTree or {}) do
            if (not activeSubs[sub]) then
                own = own + 1;
            end
        end
        out[specID] = { newSubTrees = own, visible = walk.visible, nodes = walk.nodes };
    end
    return out;
end

local function Sweep()
    local activeSpecIndex = Ask(C_SpecializationInfo.GetSpecialization) or 0;
    local activeSpecID = Ask(C_SpecializationInfo.GetSpecializationInfo, activeSpecIndex);
    local activeConfigID = Ask(C_ClassTalents.GetActiveConfigID);
    local viewConfigID = ViewConfigID();
    local level = UnitLevel("player") or 80;
    local specs = Specs();

    local record = {
        at = date("%Y-%m-%d %H:%M:%S"),
        build = select(1, GetBuildInfo()),
        interface = select(4, GetBuildInfo()),
        level = level,
        activeSpecIndex = activeSpecIndex,
        activeSpecID = activeSpecID,
        activeConfigID = activeConfigID,
        viewConfigID = viewConfigID,
        activeTreeIDs = (Ask(C_Traits.GetConfigInfo, activeConfigID) or {}).treeIDs,
        treeForSpec = {},
        heroForSpec = {},
        configForSpec = {},
        currencies = {},
        bySpec = {},
        errors = {},
        pvp = Pvp(),
    };

    --- **The active specialization is walked first, before any view loadout is initialized.** What
    --- the view config does to the client is documented only by the talent frame's own use of it,
    --- so the one reading that cannot be taken again is taken while nothing has touched it.
    local order = { activeSpecID };
    for i = 1, #specs do
        if (specs[i].id ~= activeSpecID) then
            order[#order + 1] = specs[i].id;
        end
    end

    for i = 1, #order do
        local specID = order[i];
        if (specID) then
            local treeID, treeErr = Ask(C_ClassTalents.GetTraitTreeForSpec, specID);
            record.treeForSpec[specID] = treeID;
            if (treeErr) then
                record.errors[#record.errors + 1] = specID .. " tree: " .. treeErr;
            end

            local configID, own = activeConfigID, true;
            if (specID ~= activeSpecID) then
                own = false;
                configID = viewConfigID;
                local _, initErr = Ask(C_ClassTalents.InitializeViewLoadout, specID, level);
                if (initErr) then
                    record.errors[#record.errors + 1] = specID .. " view: " .. initErr;
                    configID = nil;
                end
            end
            record.configForSpec[specID] = { config = configID, own = Bit(own) };

            if (configID) then
                local hero, heroErr = Ask(C_ClassTalents.GetHeroTalentSpecsForClassSpec,
                    configID, specID);
                record.heroForSpec[specID] = hero;
                if (heroErr) then
                    record.errors[#record.errors + 1] = specID .. " hero: " .. heroErr;
                end

                if (treeID) then
                    local info = Ask(C_Traits.GetTreeCurrencyInfo, configID, treeID, false) or {};
                    local list = {};
                    for j = 1, #info do
                        list[j] = info[j].traitCurrencyID;
                    end
                    record.currencies[specID] = list;

                    record.bySpec[specID] = WalkTree(configID, treeID, own);
                end
            end
        end
    end

    record.reach = CheckReach(record.bySpec, activeSpecID);
    return record, activeSpecID, specs;
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
    local all = DebindDevDB.talentCondition;
    if (not all) then
        all = {};
        DebindDevDB.talentCondition = all;
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
    -- The trait config arrives after `PLAYER_LOGIN`, and a sweep taken before it writes a record
    -- that looks complete and holds nothing.
    if (C_ClassTalents.GetActiveConfigID()) then
        -- **The write is wrapped too.** A raise here would leave the reader with a spent
        -- specialization change and no message saying so.
        local ok, record, err = pcall(Store);
        if (not ok) then
            print("|cffff4444Debind|r talentCondition raised: " .. tostring(record));
        elseif (record) then
            local walk = record.bySpec[record.activeSpecID];
            print(format(
                "|cff44ff44Debind|r talentCondition: spec %s, %d nodes, %d committed, %d errors",
                tostring(record.activeSpecID), walk and walk.nodes or 0,
                walk and walk.committedCount or 0, #record.errors));
        else
            print("|cffff4444Debind|r talentCondition: " .. tostring(err));
        end
        return;
    end
    pending = pending + 1;
    if (pending > 10) then
        print("|cffff4444Debind|r talentCondition: the client never answered");
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
-- **A specialization change and not login alone.** What "taken" is, and the pvp slots, answer for
-- the active specialization only.
probe:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");
probe:SetScript("OnEvent", Schedule);

local function Report()
    local entry = DebindDevDB and DebindDevDB.talentCondition
        and DebindDevDB.talentCondition[CharKey()];
    if (not entry) then
        print("talentCondition: nothing stored for this character");
        return;
    end
    print(format("talentCondition %s (%s)", CharKey(), tostring(entry.class)));

    local last;
    for _, record in pairs(entry.sweeps or {}) do
        if (not last or record.at > last.at) then
            last = record;
        end
    end

    for i = 1, #(entry.specs or {}) do
        local spec = entry.specs[i];
        local record = entry.sweeps and entry.sweeps[spec.id];
        local own = record and record.bySpec[spec.id];
        print(format("  %d %s  %s", spec.id, tostring(spec.name),
            record and format("swept %s, %d committed, %d errors", record.at,
                own and own.committedCount or 0, #record.errors)
                or "|cffff8800not swept|r"));
    end

    if (not last) then
        return;
    end
    print(format("  last %s: spec %s, view config %s", last.at, tostring(last.activeSpecID),
        tostring(last.viewConfigID)));
    for i = 1, #(entry.specs or {}) do
        local spec = entry.specs[i];
        local walk = last.bySpec[spec.id];
        local hero = last.heroForSpec[spec.id];
        if (walk) then
            local subs = {};
            for sub, row in pairs(walk.bySubTree) do
                subs[#subs + 1] = format("%d=%s(%d)", sub, tostring(row.name), row.n);
            end
            print(format("    %d tree=%s nodes=%d vis=%d hero=%s subs=%s",
                spec.id, tostring(walk.tree), walk.nodes, walk.visible,
                hero and table.concat(hero, ",") or "-",
                #subs > 0 and table.concat(subs, " ") or "-"));
        end
    end
    for i = 1, #(last.errors or {}) do
        print("    |cffff8800" .. last.errors[i] .. "|r");
    end
end

SLASH_DEBINDTC1 = "/tc";
SlashCmdList.DEBINDTC = function(msg)
    local arg = strtrim(strlower(msg or ""));
    if (arg == "wipe") then
        if (DebindDevDB and DebindDevDB.talentCondition) then
            DebindDevDB.talentCondition[CharKey()] = nil;
        end
        print("talentCondition: this character's record dropped");
    elseif (arg == "now") then
        pending = 0;
        Try();
    else
        Report();
    end
end;
