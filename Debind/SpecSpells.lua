local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

--- The spells a class or a specialization decides for the reader, so an action can say "the
--- dispel" and a rebuild can put the spell in (`adding-spec-resolved-actions.md`).
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
    -- **The shadow priest's is a talent**, so `C_Spell.GetSpellInfo(213634)` answers nothing on a
    -- character that has not taken it (2026-09-23, owner). It is still the right id: a spell this
    -- specialization can obtain is what the table is for, and §4 already covers the press that
    -- finds nothing there.
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

--- **The warlock's dispel is three spells wearing one name** (`adding-spec-resolved-actions.md`
--- §3-1, measured 2026-09-23 by the owner).
---
--- The spell is the imp's, and the imp is either out or swallowed by Grimoire of Sacrifice. The
--- book holds 119905 in the first case and 132411 in the second, and **Command Demon casts it in
--- both**, so what goes out never depends on which one is there.
---
--- **Whether one of the two is there does**, because with neither Command Demon casts whatever the
--- demon that is out has: a Spell Lock where the reader asked for a dispel. Neither `[known:]`
--- shape answers for them -- by id it is false whatever the state and by name it is true whatever
--- the state. `FindSpellBookSlotBySpellID` is the only thing that answers, and the answer moves in
--- combat where nothing can be rebuilt.
---
---   `cast`   the spell the button carries, whichever id is there
---   `known`  the ids asked before it casts, one binding each (`GetBindingsForAction`)
local WARLOCK_DISPEL_GATE = {
    cast = 119898,
    known = { 119905, 132411 },
};

--- What the row draws and the tooltip names. 119905 and 132411 both carry Singe Magic's name and
--- icon, so one of the asked ids answers that too and no fourth id is kept.
local WARLOCK_DISPEL = WARLOCK_DISPEL_GATE.known[1];

local RAID_BUFF_BY_CLASS = {
    PRIEST = 21562, DRUID = 1126, MAGE = 1459, WARRIOR = 6673, SHAMAN = 462854, EVOKER = 364342,
};

--- Resurrection (`adding-spec-resolved-actions.md` §3-3). A single and a battle resurrection are
--- the class's; a mass one belongs to the healing specialization alone.
local REZ_SINGLE_BY_CLASS = {
    PRIEST = 2006, PALADIN = 7328, SHAMAN = 2008, DRUID = 50769, MONK = 115178, EVOKER = 361227,
};

local REZ_MASS_BY_SPEC = {
    [PRIEST_DISCIPLINE] = 212036, [PRIEST_HOLY] = 212036,
    [PALADIN_HOLY] = 212056,
    [SHAMAN_RESTORATION] = 212048,
    [DRUID_RESTORATION] = 212040,
    [MONK_MISTWEAVER] = 212051,
    [EVOKER_PRESERVATION] = 361178,
};

--- The warlock's is Soulstone, which also goes on a living friend ahead of time.
local REZ_BATTLE_BY_CLASS = {
    PALADIN = 391054, DRUID = 20484, DEATHKNIGHT = 61999, WARLOCK = 20707,
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
---   dispel, dispelGate   the friendly dispel and, for the warlock alone, what it is cast under
---                        and which ids a `known` on it asks about
---   raidbuff             the raid buff
function SpecSpells.Resolve(out)
    out = out or {};
    local class = Constants.PLAYER_CLASS;
    local spec = CurrentSpecID();

    if (class == "WARLOCK") then
        out.dispel = WARLOCK_DISPEL;
        out.dispelGate = WARLOCK_DISPEL_GATE;
    else
        out.dispel = (spec and DISPEL_BY_SPEC[spec]) or DISPEL_BY_CLASS[class];
        out.dispelGate = nil;
    end
    out.raidbuff = RAID_BUFF_BY_CLASS[class];
    return out;
end

--- Which resolved spell an action type stands for.
SpecSpells.KIND_BY_TYPE = {
    [Constants.DISPEL] = "dispel",
    [Constants.RAIDBUFF] = "raidbuff",
};

--- The resurrections this class and specialization have, into `out` or a fresh table:
---
---   single     one friend, out of combat
---   mass       everyone in the group, out of combat
---   battle     one friend, in combat
---   soulstone  true where `battle` also goes on a living friend
---
--- **`out` is how a rebuild asks without allocating**: `SpellForType` runs for every binding it
--- fills, as `Resolve` does with `_resolved`.
function SpecSpells.ResurrectSpells(out)
    local class = Constants.PLAYER_CLASS;
    local spec = CurrentSpecID();
    out = out or {};
    out.single = REZ_SINGLE_BY_CLASS[class];
    out.mass = spec and REZ_MASS_BY_SPEC[spec] or nil;
    out.battle = REZ_BATTLE_BY_CLASS[class];
    out.soulstone = class == "WARLOCK" or nil;
    return out;
end

local _resolved = {};
local _rezSpells = {};

--- The spell a type resolves to right now, or nil where this specialization has none. **The
--- second value is `{ cast, known }`** and it is there only for the warlock's dispel. Everything
--- that names or draws the action reads the first.
---
--- A resurrection answers with the spell the row is drawn with (§6-5 of the design): the single
--- one, or the battle or the mass one where there is none. Which one a press casts is the
--- derivation's (`GetBindingsForAction`).
function SpecSpells.SpellForType(type)
    if (type == Constants.RESURRECT) then
        local spells = SpecSpells.ResurrectSpells(_rezSpells);
        return spells.single or spells.battle or spells.mass, nil;
    end
    local kind = SpecSpells.KIND_BY_TYPE[type];
    if (not kind) then
        return nil;
    end
    local resolved = SpecSpells.Resolve(_resolved);
    return resolved[kind], kind == "dispel" and resolved.dispelGate or nil;
end
