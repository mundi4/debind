local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

--- The spells a class or a specialization decides for the reader, so an action can say "the
--- dispel" and a rebuild can put the spell in (`adding-spec-resolved-actions.md`).
---
--- **The spells themselves are the client's file, and this is the one reading of them.**
--- `SpecSpells_Mainline.lua` or `SpecSpells_Camelot.lua` is loaded (`Debind.toc`), and either sets
--- `DebindPrivate.SpecSpellData` to the same shape: specialization id to
--- `{ dispel, dispelGate, raidbuff, rezSingle, rezMass, rezBattle }`. **Keyed by specialization id
--- alone**, with a class-wide spell written under each of the class's: a class-name fallback read
--- retail's spell on camelot, where the specialization ids are different and a class keeps its name.
local SpecSpells = {};
DebindPrivate.SpecSpells = SpecSpells;

local NONE = {};

local function CurrentEntry()
    local index = C_SpecializationInfo.GetSpecialization();
    local spec = index and (C_SpecializationInfo.GetSpecializationInfo(index));
    local data = DebindPrivate.SpecSpellData;
    return spec and data and data[spec] or NONE;
end

--- Everything the current specialization resolves to. **A fresh read every call**: a rebuild is
--- the only caller that matters and it runs after every specialization change, so a cache would
--- only be one more thing to invalidate.
---
---   dispel, dispelGate   the friendly dispel and, for the warlock alone, what it is cast under
---                        and which ids a `known` on it asks about
---   raidbuff             the raid buff
function SpecSpells.Resolve(out)
    out = out or {};
    local entry = CurrentEntry();
    out.dispel = entry.dispel;
    out.dispelGate = entry.dispelGate;
    out.raidbuff = entry.raidbuff;
    return out;
end

--- Which resolved spell an action type stands for.
SpecSpells.KIND_BY_TYPE = {
    [Constants.DISPEL] = "dispel",
    [Constants.RAIDBUFF] = "raidbuff",
};

--- The resurrections this specialization has, into `out` or a fresh table:
---
---   single     one friend, out of combat
---   mass       everyone in the group, out of combat
---   battle     one friend, in combat
---
--- **`out` is how a rebuild asks without allocating**: `SpellForType` runs for every binding it
--- fills, as `Resolve` does with `_resolved`.
function SpecSpells.ResurrectSpells(out)
    local entry = CurrentEntry();
    out = out or {};
    out.single = entry.rezSingle;
    out.mass = entry.rezMass;
    out.battle = entry.rezBattle;
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
