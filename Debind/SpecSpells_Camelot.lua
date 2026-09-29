local _, DebindPrivate = ...;

--- `SpecSpells.lua`'s spells on World of Warcraft: Forever, the same shape as
--- `SpecSpells_Mainline.lua`. Loaded on that client only (`Debind.toc`). Every class has one
--- specialization there and nobody picks it, so each id below is a class.
---
--- **The ids are rank 1, read off the class trainers** (`DebindCamelotProbe`, 70009). A spell is
--- cast by name on a client with ranks (`Spells.lua`), so the highest rank the character has goes
--- out whatever rank is written here.
---
--- **Dispels come in two kinds here, and a class can have one of each** (2026-09-27, owner).
--- `dispel` removes a curse or a disease and `dispel2` magic or a poison, which is the split that
--- leaves no class with two kinds inside one type. A reader with several healers presses one key
--- for the same debuff on every character (`splitting-the-camelot-dispel.md`).
---
--- **Where a type has two spells, the upper one is written first** and a press casts it once it is
--- known. It removes everything the lower one does for the same mana, and the Abolish spells go on
--- removing for a while after. Cure Poison 8946 is taught by a quest, not a trainer.
---
--- A class missing below has none of these.
local data = {};

local MAGE, DRUID, PRIEST, SHAMAN, PALADIN = 1482, 1484, 1487, 1489, 1486;

data[MAGE] = {
    dispel = { { cast = 475 } },     -- Remove Lesser Curse, level 18
    raidbuff = { { cast = 1459 } },  -- Arcane Intellect
};

data[DRUID] = {
    dispel = { { cast = 2782 } },    -- Remove Curse, level 24
    -- Abolish Poison (26), then Cure Poison (14)
    dispel2 = { { cast = 2893 }, { cast = 8946 } },
    raidbuff = { { cast = 1126 } },  -- Mark of the Wild
    rezSingle = 437138, -- Revive, level 12; not retail's 50769
    rezBattle = 20484,  -- Rebirth, level 20
};

-- **Power Word: Fortitude and not Prayer of Fortitude**, which retail's table names: the single
-- target one is what a priest has from level 1.
data[PRIEST] = {
    -- Abolish Disease (32), then Cure Disease (14)
    dispel = { { cast = 552 }, { cast = 528 } },
    dispel2 = { { cast = 527 } },    -- Dispel Magic, level 18
    raidbuff = { { cast = 1243 } },
    rezSingle = 2006,   -- Resurrection, level 10
};

data[SHAMAN] = {
    dispel = { { cast = 2870 } },    -- Cure Disease, level 22
    dispel2 = { { cast = 526 } },    -- Cure Poison, level 16
    rezSingle = 2008,   -- Ancestral Spirit, level 12
};

-- **One list for both types**: Cleanse removes a disease, a poison and magic, and Purify a disease
-- and a poison, so each is right under either. Cleanse (42), then Purify (8).
--
-- No raid buff: the Blessings are several, and the action casts one.
local PALADIN_DISPEL = { { cast = 4987 }, { cast = 1152 } };
data[PALADIN] = {
    dispel = PALADIN_DISPEL,
    dispel2 = PALADIN_DISPEL,
};

DebindPrivate.SpecSpellData = data;
