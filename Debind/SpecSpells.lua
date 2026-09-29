local _, DebindPrivate = ...;
local Constants = DebindPrivate.Constants;

--- The spells a class or a specialization decides for the reader, so an action can say "the
--- dispel" and a rebuild can put the spell in (`adding-spec-resolved-actions.md`).
---
--- **The spells themselves are the client's file, and this is the one reading of them.**
--- `SpecSpells_Mainline.lua` or `SpecSpells_Camelot.lua` is loaded (`Debind.toc`), and either sets
--- `DebindPrivate.SpecSpellData` to the same shape: specialization id to
--- `{ dispel, dispel2, raidbuff, rezSingle, rezMass, rezBattle }`. **Keyed by specialization id
--- alone**, with a class-wide spell written under each of the class's: a class-name fallback read
--- retail's spell on camelot, where the specialization ids are different and a class keeps its name.
---
--- **`dispel`, `dispel2` and `raidbuff` are lists of entries, one binding each**
--- (`splitting-the-camelot-dispel.md` §3):
---
---   `cast`   the spell the binding casts
---   `known`  the id its `known` asks about, where that is not `cast` itself. Absent, the binding
---            asks about `cast` by name, the shape every `known` goes out in
---
--- Tried in order, so a spell that does everything the one after it does is written first. One
--- shape for a specialization with one spell, for the warlock's two ids under one cast, and for a
--- camelot class with a lower and an upper spell.
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
function SpecSpells.Resolve(out)
    out = out or {};
    local entry = CurrentEntry();
    out.dispel = entry.dispel;
    out.dispel2 = entry.dispel2;
    out.raidbuff = entry.raidbuff;
    return out;
end

--- Which resolved list an action type stands for.
SpecSpells.KIND_BY_TYPE = {
    [Constants.DISPEL] = "dispel",
    [Constants.DISPEL2] = "dispel2",
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

--- The spell an entry is about: what its `known` asks, which is what the row is drawn with. The
--- warlock's is the book's id and not Command Demon, which it is cast under.
local function SpellOfEntry(entry)
    return entry.known or entry.cast;
end

--- The spell the row and the tooltip name, out of several entries: **the first one known at this
--- moment, or the last one where none is** (2026-09-29, owner). The last is the one the character
--- learns first, and the first known is the one a press casts.
---
--- **Measured with the question the entry's binding asks** (`KnownSpellOfEntry`), a name unless the
--- entry names an id. An id is answered by the spell book as well, and the book can hold a spell
--- the character has not learned, so asking by id could show a spell the press does not cast.
---
--- **Measured on every call, as `Resolve` reads on every call.** A rebuild asks it a few times per
--- binding it fills, and only a list of two or more gets measured at all. Keeping the answer
--- across calls would be one more value to invalidate.
local function ShownSpell(entries)
    local count = #entries;
    if (count > 1) then
        for i = 1, count - 1 do
            if (DebindPrivate.Spells.MeasureKnown(DebindPrivate.KnownSpellOfEntry(entries[i]))) then
                return SpellOfEntry(entries[i]);
            end
        end
    end
    return SpellOfEntry(entries[count]);
end

--- The spell a type resolves to right now, or nil where this specialization has none. **The
--- second value is the entry list** (see the header): `FillBinding` and `GetBindingsForAction` build
--- the bindings from it, and `Profile.lua`'s row asks every entry before saying the spell is not
--- there. Everything that names or draws the action reads the first.
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
    local entries = SpecSpells.Resolve(_resolved)[kind];
    if (not entries) then
        return nil;
    end
    return ShownSpell(entries), entries;
end
