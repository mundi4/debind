local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

--- The spells a class or a specialization decides for the reader, so an action can say "the
--- dispel" and a rebuild can put the spell in (`devdocs/adding-spec-resolved-actions.md`).
---
--- Keyed by specialization id where the spell differs across a class, by class file otherwise.
--- Ids that came from another addon's table and were not seen in the client yet are marked in
--- that document, not here.
local SpecSpells = {};
DebindPrivate.SpecSpells = SpecSpells;

local PRIEST_DISCIPLINE, PRIEST_HOLY, PRIEST_SHADOW = 256, 257, 258;
local MONK_BREWMASTER, MONK_WINDWALKER, MONK_MISTWEAVER = 268, 269, 270;
local PALADIN_HOLY, PALADIN_PROTECTION, PALADIN_RETRIBUTION = 65, 66, 70;
local DRUID_BALANCE, DRUID_FERAL, DRUID_GUARDIAN, DRUID_RESTORATION = 102, 103, 104, 105;
local SHAMAN_ELEMENTAL, SHAMAN_ENHANCEMENT, SHAMAN_RESTORATION = 262, 263, 264;
local EVOKER_DEVASTATION, EVOKER_PRESERVATION, EVOKER_AUGMENTATION = 1467, 1468, 1473;

--- Friendly dispels. Exactly one per specialization that has any; the warlock is the exception
--- and is below.
local DISPEL_BY_SPEC = {
    [PRIEST_DISCIPLINE] = 527, [PRIEST_HOLY] = 527, [PRIEST_SHADOW] = 213634,
    [MONK_MISTWEAVER] = 115450, [MONK_BREWMASTER] = 218164, [MONK_WINDWALKER] = 218164,
    [PALADIN_HOLY] = 4987, [PALADIN_PROTECTION] = 213644, [PALADIN_RETRIBUTION] = 213644,
    [DRUID_RESTORATION] = 88423,
    [DRUID_BALANCE] = 2782, [DRUID_FERAL] = 2782, [DRUID_GUARDIAN] = 2782,
    [SHAMAN_RESTORATION] = 77130, [SHAMAN_ELEMENTAL] = 51886, [SHAMAN_ENHANCEMENT] = 51886,
    [EVOKER_PRESERVATION] = 360823, [EVOKER_DEVASTATION] = 365585, [EVOKER_AUGMENTATION] = 365585,
};

local DISPEL_BY_CLASS = {
    MAGE = 475,
};

--- The warlock's dispel is the imp's, cast through the player's own Command Demon (119905) while
--- the imp is out, and the player's own Singe Magic (132411) under Grimoire of Sacrifice. Neither
--- is visible to `[known:]`; the restricted environment's `FindSpellBookSlotBySpellID` is what
--- tells the two apart at the press (`adding-spec-resolved-actions.md` §3-1).
local WARLOCK_DISPEL = 132411;
local WARLOCK_DISPEL_PET = 119905;

--- Single-target damage reduction or absorb cast on somebody else.
local EXTERNAL_BY_SPEC = {
    [PRIEST_DISCIPLINE] = 33206, [PRIEST_HOLY] = 47788,
    [DRUID_RESTORATION] = 102342,
    [PALADIN_HOLY] = 6940, [PALADIN_PROTECTION] = 6940, [PALADIN_RETRIBUTION] = 6940,
    [EVOKER_PRESERVATION] = 357170,
    [MONK_MISTWEAVER] = 116849,
};

local REZ_BY_CLASS = {
    PRIEST = 2006, PALADIN = 7328, SHAMAN = 2008, DRUID = 50769, MONK = 115178, EVOKER = 361227,
};

local MASS_REZ_BY_SPEC = {
    [PRIEST_DISCIPLINE] = 212036, [PRIEST_HOLY] = 212036,
    [PALADIN_HOLY] = 212056,
    [SHAMAN_RESTORATION] = 212048,
    [DRUID_RESTORATION] = 212040,
    [MONK_MISTWEAVER] = 212051,
    [EVOKER_PRESERVATION] = 361178,
};

local BATTLE_REZ_BY_CLASS = {
    PALADIN = 391054, DRUID = 20484, DEATHKNIGHT = 61999, WARLOCK = 20707,
};

local RAID_BUFF_BY_CLASS = {
    PRIEST = 21562, DRUID = 1126, MAGE = 1459, WARRIOR = 6673, SHAMAN = 462854, EVOKER = 364342,
};

local function CurrentSpecID()
    local index = C_SpecializationInfo.GetSpecialization();
    if (not index) then
        return nil;
    end
    return (C_SpecializationInfo.GetSpecializationInfo(index));
end

--- Everything the current class and specialization resolve to. **A fresh read every call**: a
--- rebuild is the only caller that matters and it runs after every specialization change, so a
--- cache would only be one more thing to invalidate.
---
---   dispel, dispelPet   the friendly dispel; `dispelPet` only for the warlock, the id the press
---                       asks the spellbook about and casts when it answers
---   external            the external
---   raidbuff            the raid buff
---   rez, massrez        single-target and mass resurrection
---   battlerez           the combat resurrection
function SpecSpells.Resolve(out)
    out = out or {};
    local class = Constants.PLAYER_CLASS;
    local spec = CurrentSpecID();

    if (class == "WARLOCK") then
        out.dispel = WARLOCK_DISPEL;
        out.dispelPet = WARLOCK_DISPEL_PET;
    else
        out.dispel = (spec and DISPEL_BY_SPEC[spec]) or DISPEL_BY_CLASS[class];
        out.dispelPet = nil;
    end
    out.external = spec and EXTERNAL_BY_SPEC[spec] or nil;
    out.raidbuff = RAID_BUFF_BY_CLASS[class];
    out.rez = REZ_BY_CLASS[class];
    out.massrez = spec and MASS_REZ_BY_SPEC[spec] or nil;
    out.battlerez = BATTLE_REZ_BY_CLASS[class];
    return out;
end

--- Which resolved spell an action type stands for. The three types that carry no value.
SpecSpells.KIND_BY_TYPE = {
    [Constants.DISPEL] = "dispel",
    [Constants.EXTERNAL] = "external",
    [Constants.RAIDBUFF] = "raidbuff",
};

local _resolved = {};

--- The spell one of the three types resolves to right now, or nil where this specialization has
--- none. The second value is the warlock's probe id, for the dispel only.
function SpecSpells.SpellForType(type)
    local kind = SpecSpells.KIND_BY_TYPE[type];
    if (not kind) then
        return nil;
    end
    local resolved = SpecSpells.Resolve(_resolved);
    return resolved[kind], kind == "dispel" and resolved.dispelPet or nil;
end
