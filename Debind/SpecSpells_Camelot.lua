local _, DebindPrivate = ...;

--- `SpecSpells.lua`'s spells on World of Warcraft: Forever, the same shape as
--- `SpecSpells_Mainline.lua`. Loaded on that client only (`Debind.toc`). Every class has one
--- specialization there and nobody picks it, so each id below is a class.
---
--- **The ids are rank 1, read off the class trainers** (`DebindCamelotProbe`, 70009). A spell is
--- cast by name on a client with ranks (`Spells.lua`), so the highest rank the character has goes
--- out whatever rank is written here.
---
--- **No dispel for a class with two or more** (2026-09-25, owner): the action has one spell to
--- cast and cannot say which of a curse and a poison it meant. Each class it leaves out says which
--- two. A class missing below has none of the three.
local data = {};

local MAGE, DRUID, PRIEST, SHAMAN = 1482, 1484, 1487, 1489;

data[MAGE] = {
    dispel = 475,       -- Remove Lesser Curse, level 18
    raidbuff = 1459,    -- Arcane Intellect
};

-- No dispel: Remove Curse 2782 (level 24) and Abolish Poison 2893 (level 26).
data[DRUID] = {
    raidbuff = 1126,    -- Mark of the Wild
    rezSingle = 437138, -- Revive, level 12; not retail's 50769
    rezBattle = 20484,  -- Rebirth, level 20
};

-- **Power Word: Fortitude and not Prayer of Fortitude**, which retail's table names: the single
-- target one is what a priest has from level 1.
--
-- No dispel: Cure Disease 528 (level 14) and Dispel Magic 527 (level 18).
data[PRIEST] = {
    raidbuff = 1243,
    rezSingle = 2006,   -- Resurrection, level 10
};

-- No dispel: Cure Poison 526 (level 16) and Cure Disease 2870 (level 22).
data[SHAMAN] = {
    rezSingle = 2008,   -- Ancestral Spirit, level 12
};

-- The paladin (1486) has no entry. No dispel: Purify 1152 (level 8) and Cleanse 4987 (level 42).
-- No raid buff: the Blessings are several, and the action casts one.

DebindPrivate.SpecSpellData = data;
