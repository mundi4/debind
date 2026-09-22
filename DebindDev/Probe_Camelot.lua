-- Probe_Camelot.lua
-- One-shot probe: everything about the camelot (Forever) client that `shipping-on-the-camelot-client.md`
-- could not settle from the interface source. Run it once on that client and §11 of that document
-- has its answers.
--
-- **Nothing in here touches `DebindPrivate`.** On a client whose interface number Debind's TOC does
-- not list, Debind does not load and this addon still does, so the probe has to stand alone. The
-- copy dialog is Debind's and is used only when it happens to be there.
--
-- **The flavor line comes first because every other line is read against it.** A result filed
-- without the build it was taken on is a measurement nobody can place. The interface number is also
-- the one value the TOCs need before anything else can be tried.
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
-- and the failure names it. The file the whitelist lives in is byte-identical between the two
-- clients (`shipping-on-the-camelot-client.md` §3), so a red line here means that comparison was
-- read wrong.
--
-- **Blizzard templates are not in here.** `npm run check:templates` answers that one without the
-- game: `WOW_UI_BRANCH=forever` judged all 58 of our inherited templates against this client's
-- branch on 2026-09-22 and found every one of them.
--
-- Usage:
--   /camelot        measure and show
--   /camelot wipe   drop the stored record
-- The record also lands in `DebindDevDB.camelot`, because a paste out of chat arrives truncated.

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
    PRIEST = { { "dispel", 527 }, { "dispel/shadow", 213634 }, { "external/disc", 33206 },
        { "external/holy", 47788 }, { "raidbuff", 21562 } },
    PALADIN = { { "dispel/holy", 4987 }, { "dispel/other", 213644 }, { "external", 6940 } },
    DRUID = { { "dispel/resto", 88423 }, { "dispel/other", 2782 }, { "external", 102342 },
        { "raidbuff", 1126 } },
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
    for index = 1, GetNumClasses() do
        local className, classFile, classID = GetClassInfo(index);
        local count = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0;
        local specs = {};
        for i = 1, count do
            local id, name = GetSpecializationInfoForClassID(classID, i);
            specs[#specs + 1] = format("%s=%s", tostring(id), tostring(name));
        end
        -- Index 5 is where retail keeps the initial specialization, which is a state a character
        -- can actually stand in (`Misc.lua`'s `EnumerateClassSpecs`).
        local initialID, initialName = GetSpecializationInfoForClassID(classID, 5);
        if (initialID) then
            specs[#specs + 1] = format("initial(5) %s=%s", tostring(initialID), tostring(initialName));
        end
        Emit("  %2d %-13s count %d  %s", classID, classFile or className or "?", count,
            table.concat(specs, "  "));
    end
    local index = C_SpecializationInfo.GetSpecialization();
    Emit("  mine          index %s  id %s", tostring(index),
        index and tostring((C_SpecializationInfo.GetSpecializationInfo(index))) or "nil");
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

local function Restricted()
    Emit("== restricted environment");
    for i = 1, #RESTRICTED do
        local value, err = RestrictedAnswer(RESTRICTED[i]);
        Emit("  %-40s %s", RESTRICTED[i], value or ("RAISED " .. tostring(err)));
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
    local specID = C_SpecializationInfo.GetSpecialization();
    specID = specID and (C_SpecializationInfo.GetSpecializationInfo(specID));
    local heroSpecs = specID and C_ClassTalents.GetHeroTalentSpecsForClassSpec(configID, specID);
    Emit("  hero specs    %s", heroSpecs and #heroSpecs or "nil");
    local slots = C_SpecializationInfo.GetPvpTalentSlotInfo and C_SpecializationInfo.GetPvpTalentSlotInfo(1);
    Emit("  pvp slot 1    %s", slots and "present" or "nil");
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

local function Measure()
    Lines = {};
    Emit("Debind camelot probe, %s", date("%Y-%m-%d %H:%M"));
    Client();
    Classes();
    Conditionals();
    Restricted();
    Atlases();
    Talents();
    SpecResolved();
    Apis();
    return table.concat(Lines, "\n");
end

SLASH_DEBINDCAMELOT1 = "/camelot";
SlashCmdList.DEBINDCAMELOT = function(arg)
    DebindDevDB = DebindDevDB or {};
    if (arg == "wipe") then
        DebindDevDB.camelot = nil;
        print("camelot probe: record dropped");
        return;
    end

    local text = Measure();
    DebindDevDB.camelot = text;
    if (DebindCopyFrame) then
        DebindCopyFrame:ShowText(text);
    else
        print(text);
    end
    print(format("camelot probe: %d lines, also in DebindDevDB.camelot", #Lines));
end;
