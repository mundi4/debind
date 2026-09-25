local _, DebindPrivate = ...;

--- `SpecSpells.lua`'s spells on retail, by specialization id and nothing else. Loaded on retail
--- only (`Debind.toc`); `SpecSpells_Camelot.lua` is the same shape for that client.
---
--- **A spell the whole class has is written under every specialization of it, the initial one
--- included**, since a character that has not picked one stands in that one. The initial ids are
--- the ones XPTR answered on 12.1.5 (`DebindDev`'s `Probe_InitialSpecs.lua`).
---
--- Ids that came from another addon's table and were not seen in the client yet are marked in
--- `adding-spec-resolved-actions.md`, not here.
local data = {};

local function Set(field, value, ...)
    for i = 1, select("#", ...) do
        local spec = select(i, ...);
        data[spec] = data[spec] or {};
        data[spec][field] = value;
    end
end

local WARRIOR   = { 71, 72, 73, 1446 };
local PALADIN   = { 65, 66, 70, 1451 };
local PRIEST    = { 256, 257, 258, 1452 };
local DEATHKNIGHT = { 250, 251, 252, 1455 };
local SHAMAN    = { 262, 263, 264, 1444 };
local MAGE      = { 62, 63, 64, 1449 };
local WARLOCK   = { 265, 266, 267, 1454 };
local MONK      = { 268, 269, 270, 1450 };
local DRUID     = { 102, 103, 104, 105, 1447 };
local EVOKER    = { 1467, 1468, 1473, 1465 };

--- Friendly dispels. Exactly one per specialization that has any; the warlock is the exception
--- and is below.
---
--- **The shadow priest's is a talent**, so `C_Spell.GetSpellInfo(213634)` answers nothing on a
--- character that has not taken it (2026-09-23, owner). It is still the right id: a spell this
--- specialization can obtain is what the table is for.
Set("dispel", 527, 256, 257);
Set("dispel", 213634, 258);
Set("dispel", 115450, 270);
Set("dispel", 218164, 268, 269);
Set("dispel", 4987, 65);
Set("dispel", 213644, 66, 70);
Set("dispel", 88423, 105);
Set("dispel", 2782, 102, 103, 104);
Set("dispel", 77130, 264);
Set("dispel", 51886, 262, 263);
Set("dispel", 360823, 1468);
Set("dispel", 365585, 1467, 1473);
Set("dispel", 475, unpack(MAGE));

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
---
--- The row is drawn off `known[1]`: both ids carry Singe Magic's name and icon.
local WARLOCK_DISPEL_GATE = { cast = 119898, known = { 119905, 132411 } };
Set("dispel", WARLOCK_DISPEL_GATE.known[1], unpack(WARLOCK));
Set("dispelGate", WARLOCK_DISPEL_GATE, unpack(WARLOCK));

Set("raidbuff", 21562, unpack(PRIEST));
Set("raidbuff", 1126, unpack(DRUID));
Set("raidbuff", 1459, unpack(MAGE));
Set("raidbuff", 6673, unpack(WARRIOR));
Set("raidbuff", 462854, unpack(SHAMAN));
Set("raidbuff", 364342, unpack(EVOKER));

--- Resurrection (`adding-spec-resolved-actions.md` §3-3). A single and a battle resurrection are
--- the class's; a mass one belongs to the healing specialization alone. The warlock's battle one is
--- Soulstone.
Set("rezSingle", 2006, unpack(PRIEST));
Set("rezSingle", 7328, unpack(PALADIN));
Set("rezSingle", 2008, unpack(SHAMAN));
Set("rezSingle", 50769, unpack(DRUID));
Set("rezSingle", 115178, unpack(MONK));
Set("rezSingle", 361227, unpack(EVOKER));

Set("rezMass", 212036, 256, 257);
Set("rezMass", 212056, 65);
Set("rezMass", 212048, 264);
Set("rezMass", 212040, 105);
Set("rezMass", 212051, 270);
Set("rezMass", 361178, 1468);

Set("rezBattle", 391054, unpack(PALADIN));
Set("rezBattle", 20484, unpack(DRUID));
Set("rezBattle", 61999, unpack(DEATHKNIGHT));
Set("rezBattle", 20707, unpack(WARLOCK));

DebindPrivate.SpecSpellData = data;
