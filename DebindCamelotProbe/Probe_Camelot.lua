-- Probe_Camelot.lua
-- Everything about the camelot (Forever) client that `shipping-on-the-camelot-client.md` and
-- `preparing-the-code-for-camelot.md` could not settle from the interface source.
--
-- **It runs by itself and has no command.** Only the camelot client loads it: the TOC names that
-- client's interface number alone, since `WOW_PROJECT_ID` answers 1 there just as on retail. Two
-- kinds of value, two cadences:
--
--   the client       the same for every character: each section measured once per build at login,
--                    kept under `DebindCamelotProbeDB.builds[<build>][<section>]`
--   the character    what playing changes (level, talents, spec group, spellbook, professions,
--                    forms): measured at login and again a moment after any event that can change
--                    it, kept under
--                    `DebindCamelotProbeDB.characters[<build> <name-realm>][<level>][<section>]`
--
-- plus a running log of the events a dual spec swap or a new profession raises, under `.events`.
--
-- **Nothing in here touches `DebindPrivate`.** On a client whose interface number Debind's TOC does
-- not list, Debind does not load and this addon still does, so the probe has to stand alone.
--
-- **A conditional is asked twice, positive and negative.** `SecureCmdOptionParse("[combat] y")`
-- answering nothing means either "not in combat" or "this client has no such conditional", and
-- those two are the whole question. Exactly one of `[x]` and `[nox]` holds on a client that knows
-- `x`, so both coming back empty is the client saying it does not. Unit clauses (`[@focus]`) carry
-- no negative form and are read off the **second** return instead, which is the unit the clause
-- resolved to.
--
-- **The restricted environment is asked by running one expression per snippet.** A missing function
-- raises inside the body rather than answering nil, so each call gets its own `SecureHandlerExecute`
-- and the failure names it. **On 1.60.1.69913 and 69977 every one of them raises**, because those
-- builds never hand the restricted environment its compiler (`shipping-on-the-camelot-client.md`
-- §3). The raise lands in the error frame, which is why this is part of the once-per-build record:
-- one error per build rather than one per login. A line answering a value instead is the news that
-- the client was fixed.
--
-- **Blizzard templates are not in here.** `npm run check:templates` answers that one without the
-- game: `WOW_UI_BRANCH=forever` judged all 58 of our inherited templates against this client's
-- branch on 2026-09-22 and found every one of them.

local Lines = {};

local function Emit(fmt, ...)
    Lines[#Lines + 1] = select("#", ...) > 0 and format(fmt, ...) or fmt;
end

local function Yes(v)
    return v and "yes" or "no";
end

--- The atlases our UI asks the client for. We ship no art of our own, so a name this client does
--- not have is a control that draws nothing.
local ATLASES = {
    "!UI-HUD-ActionBar-IconFrame-FlyoutMid",
    "ClickCastList-ButtonBackground",
    "ClickCastList-ButtonHighlight",
    "Options_HorizontalDivider",
    "Transmog-nav-slot-selected",
    "UI-HUD-ActionBar-IconFrame",
    "UI-HUD-ActionBar-IconFrame-Background",
    "UI-HUD-ActionBar-IconFrame-Down",
    "UI-HUD-ActionBar-IconFrame-Mouseover",
    "auctionhouse-ui-row-select",
    "bags-roundhighlight",
    "plunderstorm-new-dot-lg",
    "transmog-icon-warning-small",
    "UI-HUD-ActionBar-IconFrame-FlyoutButton",
    "editmode-new-layout-plus",
    "questlog-questtypeicon-quest",
    "icons_16x16_important",
    "checkmark-minimal",
    "common-icon-minus",
    "NPE_Icon",
    "Professions-Icon-Quality-Tier1-Inv",
};

--- Conditionals with a negative form, so the pair test applies. The first group is what the binding
--- builder and the give-back driver actually write; the rest are the axes the reader sets and the
--- custom conditional box lets through.
local CONDITIONALS = {
    "petbattle", "vehicleui", "possessbar", "overridebar", "shapeshift", "bonusbar:1", "extrabar",
    "combat", "stealth", "mounted", "flying", "indoors", "outdoors", "swimming", "resting",
    "group:party", "group:raid", "pet", "channeling", "dead", "exists", "help", "harm",
    "mod:shift", "actionbar:1", "form:1", "stance:1", "spec:1", "talent:1/1", "equipped:Shields",
    "canexitvehicle", "cursor", "flyable", "advflyable", "known:1459",
};

--- Unit clauses, read off the resolved unit rather than a truth value.
local UNIT_CLAUSES = {
    "@player", "@target", "@focus", "@mouseover", "@pet", "@party1", "@raid1", "@arena1", "@boss1",
    "@vehicle", "@none",
};

--- One expression per restricted-environment function our snippet bodies call, with arguments the
--- body would actually pass. `SetBindingClick` and `ClearBinding` are left out on purpose: calling
--- them would move the reader's keys, and they sit in the same byte-identical file as the rest.
local RESTRICTED = {
    "IsIndoors()", "IsOutdoors()", "IsFlyableArea()", "IsAdvancedFlyableArea()", "IsFlying()",
    "IsMounted()", "IsStealthed()", "PlayerInCombat()", "PlayerIsChanneling()",
    "GetShapeshiftForm()", "GetBonusBarOffset()", "GetBonusBarIndex()", "GetActionBarPage()",
    "GetOverrideBarIndex()", "GetTempShapeshiftBarIndex()", "GetVehicleBarIndex()",
    "HasVehicleActionBar()", "HasOverrideActionBar()", "HasTempShapeshiftActionBar()",
    "HasExtraActionBar()", "HasBonusActionBar()", "PetHasActionBar()", "HasAction(1)",
    "GetActionInfo(1)", "UnitExists('player')", "UnitIsDead('player')", "UnitIsGhost('player')",
    "UnitPlayerOrPetInParty('player')", "UnitPlayerOrPetInRaid('player')",
    "PlayerCanAssist('player')", "PlayerCanAttack('target')", "IsShiftKeyDown()",
    "IsControlKeyDown()", "IsAltKeyDown()", "IsModifiedClick('SELFCAST')",
    "SecureCmdOptionParse('[petbattle]')", "FindSpellBookSlotBySpellID(1459)",
};

--- The insecure calls whose absence would break a whole screen rather than one value. Not the whole
--- list of what we call: the generated API documentation of this client's own build already carries
--- every namespace we use, and these are the ones a wrong reading of it would show up in first.
local APIS = {
    "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetNumSpecializationsForClassID",
    "C_ClassTalents.GetActiveConfigID", "C_ClassTalents.GetHeroTalentSpecsForClassSpec",
    "C_Traits.GetTreeNodes", "C_Traits.GetNodeInfo", "C_Traits.GetSubTreeInfo",
    "C_SpellBook.GetSpellBookItemInfo", "C_SpellBook.HasPetSpells", "C_Spell.GetSpellInfo",
    "C_Spell.GetOverrideSpell", "C_Spell.IsPressHoldReleaseSpell", "C_Item.GetItemInfo",
    "C_MountJournal.GetMountIDs", "C_ToyBox.GetToyInfo", "C_Container.GetContainerNumSlots",
    "C_KeyBindings.GetBindingContextForAction", "C_AssistedCombat.GetActionSpell",
    "C_UnitAuras.SwitchAuraDataProvider", "C_ClickBindings.GetProfileInfo",
    "C_PaperDollInfo.GetInventorySlotInfoForInvSlot", "C_CreatureInfo.GetClassInfo",
    "C_Texture.GetAtlasInfo", "issecretvalue", "GetNumClasses", "GetClassInfo",
    "GetSpecializationInfoForClassID", "SecureCmdOptionParse", "SetBindingClick",
    "RegisterAttributeDriver", "SecureHandlerExecute", "SecureHandlerWrapScript",
};

--- What `SpecSpells.lua` would want for the nine classes this client has, as the retail ids it
--- holds today. The question each row asks is whether that spell exists here at all; the number a
--- camelot key needs is whatever the answer names.
local SPEC_RESOLVED = {
    PRIEST = { { "dispel", 527 }, { "dispel/shadow", 213634 }, { "raidbuff", 21562 } },
    PALADIN = { { "dispel/holy", 4987 }, { "dispel/other", 213644 } },
    DRUID = { { "dispel/resto", 88423 }, { "dispel/other", 2782 }, { "raidbuff", 1126 } },
    SHAMAN = { { "dispel/resto", 77130 }, { "dispel/other", 51886 }, { "raidbuff", 462854 } },
    MAGE = { { "dispel", 475 }, { "raidbuff", 1459 } },
    WARLOCK = { { "dispel", 132411 }, { "dispel/pet", 119905 } },
    WARRIOR = { { "raidbuff", 6673 } },
    HUNTER = {},
    ROGUE = {},
};

local probeFrame;

local function RestrictedAnswer(expr)
    if (not probeFrame) then
        probeFrame = CreateFrame("Frame", nil, nil, "SecureHandlerBaseTemplate");
    end
    probeFrame:SetAttribute("debprobe", nil);
    local body = format("self:SetAttribute('debprobe', tostring(%s));", expr);
    local ok, err = pcall(SecureHandlerExecute, probeFrame, body);
    if (not ok) then
        return nil, tostring(err);
    end
    return probeFrame:GetAttribute("debprobe") or "nil";
end

local function Conditional(cond)
    local okYes, yes = pcall(SecureCmdOptionParse, "[" .. cond .. "] y");
    local okNo, no = pcall(SecureCmdOptionParse, "[no" .. cond .. "] y");
    if (not okYes or not okNo) then
        return "raised";
    end
    if (yes == "y") then
        return "true";
    elseif (no == "y") then
        return "false";
    end
    return "UNKNOWN";
end

local function UnitClause(clause)
    local ok, action, unit = pcall(SecureCmdOptionParse, "[" .. clause .. "] y");
    if (not ok) then
        return "raised";
    end
    if (action ~= "y") then
        return "UNKNOWN";
    end
    return unit or "(no unit)";
end

local function Client()
    local version, build, date, tocversion = GetBuildInfo();
    Emit("== client");
    Emit("  GetBuildInfo  %s  build %s  %s  toc %s",
        tostring(version), tostring(build), tostring(date), tostring(tocversion));
    if (C_GameRules and C_GameRules.GetActiveGameMode) then
        Emit("  game mode     %s", tostring(C_GameRules.GetActiveGameMode()));
    end
    Emit("  WOW_PROJECT_ID %s", tostring(WOW_PROJECT_ID));
    Emit("  locale        %s", GetLocale());
end

local function Classes()
    Emit("== classes and specializations");
    -- **`GetNumClasses` is a count and not the last index.** On 1.60.1 it answers 9 while indices 6
    -- and 10 are empty and Druid sits at 11, so every index is walked for its answer. `Misc.lua`'s
    -- `ClassSpecCatalog` stops at `GetNumClasses()` and loses Druid on this client.
    local last = 0;
    for index = 1, 30 do
        if (select(3, GetClassInfo(index))) then
            last = index;
        end
    end
    for index = 1, last do
        local className, classFile, classID = GetClassInfo(index);
        if (classID) then
            local count = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0;
            local specs = {};
            for i = 1, count do
                local id, name = GetSpecializationInfoForClassID(classID, i);
                specs[#specs + 1] = format("%s=%s", tostring(id), tostring(name));
            end
            -- Index 5 is where retail keeps the initial specialization, which is a state a
            -- character can actually stand in (`Misc.lua`'s `EnumerateClassSpecs`).
            local initialID, initialName = GetSpecializationInfoForClassID(classID, 5);
            if (initialID) then
                specs[#specs + 1] = format("initial(5) %s=%s",
                    tostring(initialID), tostring(initialName));
            end
            Emit("  idx %2d  id %2d  %-13s count %d  %s", index, classID,
                classFile or className or "?", count, table.concat(specs, "  "));
        else
            Emit("  idx %2d  (empty)", index);
        end
    end
    Emit("  GetNumClasses %s, highest index answering %d", tostring(GetNumClasses()), last);
    -- Blizzard's own class loops on this client walk this list instead of `1..GetNumClasses()`
    -- (`Blizzard_ClassMenu.lua`).
    local allClassIDs = C_SpecializationInfo.GetAllClassIDs and C_SpecializationInfo.GetAllClassIDs();
    Emit("  GetAllClassIDs %s", allClassIDs and table.concat(allClassIDs, ",") or "nil");
end

--- One specialization per class, but two spec groups (dual spec), each with its own talent config
--- (`Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua`). Debind keys layers and talents on the
--- spec, so whether the config it reads follows the active group is the question.
local function SpecGroups()
    Emit("== spec groups");
    local index = C_SpecializationInfo.GetSpecialization();
    Emit("  specialization index %s  id %s", tostring(index),
        index and tostring((C_SpecializationInfo.GetSpecializationInfo(index))) or "nil");
    Emit("  GetNumSpecGroups %s  active %s", tostring(GetNumSpecGroups and GetNumSpecGroups()),
        tostring(C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup()));
    for group = 1, 2 do
        local configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup
            and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group);
        Emit("  group %d config %s", group, tostring(configID));
    end
    Emit("  C_ClassTalents.GetActiveConfigID %s", tostring(C_ClassTalents.GetActiveConfigID()));
end

local function Conditionals()
    Emit("== conditionals (UNKNOWN means this client has no such conditional)");
    for i = 1, #CONDITIONALS do
        Emit("  %-18s %s", CONDITIONALS[i], Conditional(CONDITIONALS[i]));
    end
    Emit("== unit clauses");
    for i = 1, #UNIT_CLAUSES do
        Emit("  %-18s %s", UNIT_CLAUSES[i], UnitClause(UNIT_CLAUSES[i]));
    end
end

-- **`pcall` does not catch this one.** The raise happens inside the secure call, so the call
-- returns normally and only the error frame shows it; what comes back is an attribute nobody wrote.
-- So the gate reads the answer rather than the failure: one body is tried, and nothing written
-- means no body compiles on this client (3절), so the other 37 are not asked.
local function Restricted()
    Emit("== restricted environment");
    local value, err = RestrictedAnswer("1");
    if (value == nil or value == "nil") then
        Emit("  no snippet compiles on this client, so the rest was not asked");
        Emit("  %s", tostring(err or "the body wrote nothing back"));
        return;
    end
    for i = 1, #RESTRICTED do
        local answer, raised = RestrictedAnswer(RESTRICTED[i]);
        Emit("  %-40s %s", RESTRICTED[i], answer or ("RAISED " .. tostring(raised)));
    end
end

local function Atlases()
    Emit("== atlases");
    for i = 1, #ATLASES do
        Emit("  %-42s %s", ATLASES[i], C_Texture.GetAtlasInfo(ATLASES[i]) and "ok" or "MISSING");
    end
end

local function Talents()
    Emit("== talent tree");
    local configID = C_ClassTalents.GetActiveConfigID();
    Emit("  active config %s", tostring(configID));
    if (not configID) then
        return;
    end
    local info = C_Traits.GetConfigInfo(configID);
    local treeID = info and info.treeIDs and info.treeIDs[1];
    Emit("  tree          %s", tostring(treeID));
    if (not treeID) then
        return;
    end
    local nodes = C_Traits.GetTreeNodes(treeID) or {};
    Emit("  nodes         %d", #nodes);
    local subTrees, visible = 0, 0;
    for i = 1, #nodes do
        local node = C_Traits.GetNodeInfo(configID, nodes[i]);
        if (node) then
            if (node.isVisible) then
                visible = visible + 1;
            end
            if (node.subTreeID) then
                subTrees = subTrees + 1;
            end
        end
    end
    Emit("  visible %d, carrying a subTreeID %d", visible, subTrees);
    -- `Talents.lua`'s `BuildMenu` splits the tree into class and spec by the first tree currency.
    -- This client's talent frame splits it by trait group instead, and each group carries a skill
    -- line, so how many currencies there are and how the nodes fall into groups decides which of
    -- the two splits a menu can be built from here.
    local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false) or {};
    for i = 1, #currencies do
        local c = currencies[i];
        Emit("  currency %d   id %s  max %s  spent %s", i, tostring(c.traitCurrencyID),
            tostring(c.maxQuantity), tostring(c.spent));
    end
    local byGroup, noGroup, byCostCurrency = {}, 0, {};
    for i = 1, #nodes do
        local node = C_Traits.GetNodeInfo(configID, nodes[i]);
        if (node) then
            local groups = node.groupIDs or {};
            if (#groups == 0) then
                noGroup = noGroup + 1;
            end
            for g = 1, #groups do
                byGroup[groups[g]] = (byGroup[groups[g]] or 0) + 1;
            end
            local cost = C_Traits.GetNodeCost(configID, nodes[i]);
            local currencyID = cost and cost[1] and cost[1].ID;
            byCostCurrency[tostring(currencyID)] = (byCostCurrency[tostring(currencyID)] or 0) + 1;
        end
    end
    for currencyID, count in pairs(byCostCurrency) do
        Emit("  nodes costing currency %s: %d", currencyID, count);
    end
    Emit("  nodes in no group %d", noGroup);
    local displays = C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupDisplayInfoByTreeID(treeID);
    if (not displays) then
        Emit("  GetGroupDisplayInfoByTreeID nil");
    else
        for i = 1, #displays do
            local d = displays[i];
            Emit("  group %s  order %s  skill line %s  %s  nodes %d", tostring(d.groupID),
                tostring(d.orderIndex), tostring(d.skillLineID), tostring(d.displayName),
                byGroup[d.groupID] or 0);
        end
    end
    for groupID, count in pairs(byGroup) do
        local listed = false;
        for i = 1, #(displays or {}) do
            listed = listed or displays[i].groupID == groupID;
        end
        if (not listed) then
            Emit("  group %s (no display info)  nodes %d", tostring(groupID), count);
        end
    end
    local specID = C_SpecializationInfo.GetSpecialization();
    specID = specID and (C_SpecializationInfo.GetSpecializationInfo(specID));
    local heroSpecs = specID and C_ClassTalents.GetHeroTalentSpecsForClassSpec(configID, specID);
    Emit("  hero specs    %s", heroSpecs and #heroSpecs or "nil");
    local slots = C_SpecializationInfo.GetPvpTalentSlotInfo and C_SpecializationInfo.GetPvpTalentSlotInfo(1);
    Emit("  pvp slot 1    %s", slots and "present" or "nil");
end

--- `LayerDisplay.lua` takes skill line 2 as the class line (`GetSpellTabNameAndIcon(2)`). This
--- client's spellbook is classic-style, one skill line per talent tree, and borrows the class line
--- from `GetClassSkillLineInfo`. Spell ranks: each rank is its own book item, and the subtext our
--- cast name appends may be the rank.
local function SkillLines()
    Emit("== spellbook skill lines");
    local bank = Enum.SpellBookSpellBank.Player;
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line);
        if (info) then
            local lowRanks = 0;
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                if (C_SpellBook.IsSpellBookItemLowRank and C_SpellBook.IsSpellBookItemLowRank(slot, bank)) then
                    lowRanks = lowRanks + 1;
                end
            end
            Emit("  line %d  %-20s items %3d  low ranks %d  spec %s  offspec %s  hide %s", line,
                tostring(info.name), info.numSpellBookItems, lowRanks, tostring(info.specID),
                tostring(info.offSpecID), Yes(info.shouldHide));
            local first = C_SpellBook.GetSpellBookItemInfo(info.itemIndexOffset + 1, bank);
            if (first and first.spellID) then
                Emit("          first %s %d  subtext %s", tostring(first.name), first.spellID,
                    tostring(C_Spell.GetSpellSubtext(first.spellID)));
            end
        end
    end
    local classLine = C_SpellBook.GetClassSkillLineInfo and C_SpellBook.GetClassSkillLineInfo();
    Emit("  GetClassSkillLineInfo %s", classLine and tostring(classLine.name) or "nil");
end

--- This client's `GetProfessions` answers seven slots (two primary, five secondary) where retail
--- answers fewer (`Camelot/Blizzard_ProfessionsFrame.lua`), and a profession's spells sit at
--- `spellOffset` in the player's book. Whether they also show up as a skill line above decides
--- whether the spell list already offers them.
local function Professions()
    Emit("== professions");
    local slots = { GetProfessions() };
    Emit("  GetProfessions %d returns", select("#", GetProfessions()));
    local bank = Enum.SpellBookSpellBank.Player;
    for slot = 1, select("#", GetProfessions()) do
        local index = slots[slot];
        if (index) then
            local name, _, rank, maxRank, numSpells, spellOffset, skillLine = GetProfessionInfo(index);
            Emit("  slot %d  index %s  %s  %s/%s  skill line %s  spells %s at offset %s", slot,
                tostring(index), tostring(name), tostring(rank), tostring(maxRank), tostring(skillLine),
                tostring(numSpells), tostring(spellOffset));
            for i = 1, numSpells or 0 do
                local item = C_SpellBook.GetSpellBookItemInfo(spellOffset + i, bank);
                Emit("          %s %s", tostring(item and item.name), tostring(item and item.spellID));
            end
        end
    end
end

--- `Misc.lua`'s `CANCEL_FORM_LINE` writes druid forms as retail form indices, and the bonus bar
--- labels read skyriding off flyout 229 and `GetBonusBarOffset() == 5`.
local function FormsAndBars()
    Emit("== forms and bars");
    for i = 1, GetNumShapeshiftForms() do
        local _, active, _, spellID = GetShapeshiftFormInfo(i);
        Emit("  form %d  %s %s%s", i, tostring(spellID), tostring(spellID and C_Spell.GetSpellName(spellID)),
            active and "  (active)" or "");
    end
    Emit("  GetBonusBarOffset %s  GetShapeshiftForm %s", tostring(GetBonusBarOffset()),
        tostring(GetShapeshiftForm()));
    -- **This client raises for a flyout it does not have** rather than answering nil (69977), and
    -- the raise used to end the section before the lines below.
    local okFlyout, flyoutName = pcall(GetFlyoutInfo, 229);
    Emit("  GetFlyoutInfo(229) %s", okFlyout and tostring(flyoutName) or "RAISED");
    Emit("  CompactArenaFrame %s", Yes(_G.CompactArenaFrame));
end

local function SpecResolved()
    local _, classFile = UnitClass("player");
    Emit("== spell ids SpecSpells would want (this character's class: %s)", tostring(classFile));
    for class, rows in pairs(SPEC_RESOLVED) do
        for i = 1, #rows do
            local kind, id = rows[i][1], rows[i][2];
            local name = C_Spell.GetSpellName(id);
            Emit("  %-9s %-16s %-7d %s", class, kind, id, name or "MISSING");
        end
    end
end

local function Apis()
    Emit("== insecure calls");
    for i = 1, #APIS do
        local name = APIS[i];
        local namespace, fn = name:match("^(C_%a+)%.(%a+)$");
        local value;
        if (namespace) then
            value = _G[namespace] and _G[namespace][fn];
        else
            value = _G[name];
        end
        Emit("  %-52s %s", name, Yes(value ~= nil));
    end
end

--- **Records are kept per section, under the section's name, and a later change to this file only
--- ever adds.** A client section is measured once per build: a record already holding it is never
--- measured again, so a section added later is measured on the next login on its own and nothing
--- recorded before it is redone. The same goes for changing what a section measures: give it a new
--- name here rather than editing the old one, and the old records keep meaning what they meant.
local CLIENT_SECTIONS = {
    "client", Client, "classes", Classes, "conditionals", Conditionals,
    "restricted", Restricted, "atlases", Atlases, "specspells", SpecResolved, "apis", Apis,
};

local CHARACTER_SECTIONS = {
    "spec groups", SpecGroups, "talents", Talents, "skill lines", SkillLines,
    "professions", Professions, "forms", FormsAndBars,
};

--- One section's text, stamped with when it was taken. A section that raises records the raise
--- rather than taking anything else down with it.
local function Measure(name, fn)
    Lines = {};
    Emit("%s, %s", name, date("%Y-%m-%d %H:%M"));
    local ok, err = pcall(fn);
    if (not ok) then
        Emit("  !! raised: %s", tostring(err));
    end
    return table.concat(Lines, "\n");
end

local function BuildKey()
    local version, build = GetBuildInfo();
    return version .. "." .. build;
end

local function Store()
    DebindCamelotProbeDB = DebindCamelotProbeDB or {};
    local store = DebindCamelotProbeDB;
    store.builds = store.builds or {};
    store.characters = store.characters or {};
    store.events = store.events or {};
    return store;
end

local function MeasureClient()
    local store, key = Store(), BuildKey();
    local record = store.builds[key] or {};
    store.builds[key] = record;
    local added = {};
    for i = 1, #CLIENT_SECTIONS, 2 do
        local name = CLIENT_SECTIONS[i];
        if (record[name] == nil) then
            record[name] = Measure(name, CLIENT_SECTIONS[i + 1]);
            added[#added + 1] = name;
        end
    end
    if (#added > 0) then
        print(format("camelot probe: %s measured on %s", table.concat(added, ", "), key));
    end
end

--- Unlike the client, the character is measured again every time: what it records is how the
--- character stands now. One record per level keeps what an earlier level looked like.
local function MeasureCharacter()
    local name, realm = UnitFullName("player");
    local key = format("%s %s-%s", BuildKey(), tostring(name), tostring(realm or GetRealmName()));
    local characters = Store().characters;
    local record = characters[key] or {};
    characters[key] = record;
    local level = UnitLevel("player");
    local atLevel = record[level] or {};
    record[level] = atLevel;
    for i = 1, #CHARACTER_SECTIONS, 2 do
        atLevel[CHARACTER_SECTIONS[i]] = Measure(CHARACTER_SECTIONS[i], CHARACTER_SECTIONS[i + 1]);
    end
end

--- What playing can change about the character. Each of these schedules one measurement a moment
--- later, so a burst (a level up raises several) is measured once, after it settles.
local CHARACTER_EVENTS = {
    "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORMS", "TRAIT_CONFIG_UPDATED",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "SKILL_LINES_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE",
};

--- Which events a dual spec swap or a new profession raises, with the group and the active config at
--- each. Debind
--- rebuilds on `ACTIVE_PLAYER_SPECIALIZATION_CHANGED` and on `TRAIT_CONFIG_UPDATED` for the active
--- config only.
local LOGGED_EVENTS = {
    "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
    "PLAYER_TALENT_UPDATE",
    -- Learning a profession: which spell and skill line arrive, for a condition on the profession.
    "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
};
local LOG_LIMIT = 200;

local function LogEvent(event, ...)
    local log = Store().events;
    local group = C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup();
    local line = format("%s %s %s  args %s  group %s  config %s", BuildKey(), date("%m-%d %H:%M:%S"),
        event, strjoin(",", tostringall(...)), tostring(group), tostring(C_ClassTalents.GetActiveConfigID()));
    log[#log + 1] = line;
    while (#log > LOG_LIMIT) do
        table.remove(log, 1);
    end
end

local pending = false;
local function ScheduleCharacter()
    if (pending) then
        return;
    end
    pending = true;
    C_Timer.After(2, function()
        pending = false;
        MeasureCharacter();
    end);
end

local frame = CreateFrame("Frame");
frame:RegisterEvent("PLAYER_LOGIN");
local logged, measured = {}, {};
for i = 1, #LOGGED_EVENTS do
    logged[LOGGED_EVENTS[i]] = true;
end
for i = 1, #CHARACTER_EVENTS do
    measured[CHARACTER_EVENTS[i]] = true;
end
for event in pairs(logged) do
    pcall(frame.RegisterEvent, frame, event);
end
for event in pairs(measured) do
    pcall(frame.RegisterEvent, frame, event);
end
local loggedIn = false;
frame:SetScript("OnEvent", function(_, event, ...)
    if (event == "PLAYER_LOGIN") then
        loggedIn = true;
        MeasureClient();
        ScheduleCharacter();
        return;
    end
    -- Events before login would be written into a table the saved one is about to replace.
    if (not loggedIn) then
        return;
    end
    if (logged[event]) then
        LogEvent(event, ...);
    end
    if (measured[event]) then
        ScheduleCharacter();
    end
end);
