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
--- `known` does: the reader asking "only while I have it" is asking about those two ids, and
--- neither `[known:]` shape answers for them -- by id it is false whatever the state and by name
--- it is true whatever the state. `FindSpellBookSlotBySpellID` is the only thing that answers, and
--- the answer moves in combat where nothing can be rebuilt.
---
---   `cast`   the spell the button carries, whichever id is there
---   `known`  the ids a `known` on this action asks about, one binding each
local WARLOCK_DISPEL_GATE = {
    cast = 119898,
    known = { 119905, 132411 },
};

--- What the row draws and the tooltip names. 119905 and 132411 both carry Singe Magic's name and
--- icon, so one of the asked ids answers that too and no fourth id is kept.
local WARLOCK_DISPEL = WARLOCK_DISPEL_GATE.known[1];

--- Single-target damage reduction or absorb cast on somebody else.
local EXTERNAL_BY_SPEC = {
    [PRIEST_DISCIPLINE] = 33206, [PRIEST_HOLY] = 47788,
    [DRUID_RESTORATION] = 102342,
    [PALADIN_HOLY] = 6940, [PALADIN_PROTECTION] = 6940, [PALADIN_RETRIBUTION] = 6940,
    [EVOKER_PRESERVATION] = 357170,
    [MONK_MISTWEAVER] = 116849,
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
---   dispel, dispelGate   the friendly dispel and, for the warlock alone, what it is cast under
---                        and which ids a `known` on it asks about
---   external             the external
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
    out.external = spec and EXTERNAL_BY_SPEC[spec] or nil;
    out.raidbuff = RAID_BUFF_BY_CLASS[class];
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
--- none. **The second value is `{ cast, known }`** and it is there only for the warlock's dispel.
--- Everything that names or draws the action reads the first.
function SpecSpells.SpellForType(type)
    local kind = SpecSpells.KIND_BY_TYPE[type];
    if (not kind) then
        return nil;
    end
    local resolved = SpecSpells.Resolve(_resolved);
    return resolved[kind], kind == "dispel" and resolved.dispelGate or nil;
end
