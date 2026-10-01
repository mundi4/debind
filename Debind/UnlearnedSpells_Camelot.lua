local _, DebindPrivate = ...;

--- The spells a character on World of Warcraft: Forever has not learned yet, for the spell list's
--- rows of them (`ActionCatalog.lua`). Loaded on that client only (`Debind.toc`): its spellbook
--- holds only what has been learned, where retail's lists the rest as `FutureSpell`.
---
--- **Every source merged, and nothing is ever taken out** (`listing-unlearned-spells-on-forever.md`):
--- the class lists and the professions' spells generated from the camelot probe's record
--- (`ClassSpells_Camelot.lua`), what the class trainers were read selling, and the ids written below.
--- None is complete on its own: the class lists start from wowhead's, the professions are the ones
--- the probe has met, a trainer window lists only what its filters let through, and some spells
--- never appear at a trainer at all. The talent tree is one more, read where the group is built
--- (`ActionCatalog.lua`).

--- `[classFile] = { [spellID] = level required }`, for what the other two miss.
---
--- **A string in a level's place names where the spell comes from instead** (2026-10-01, owner),
--- in every source here and in the talent tree's (`"talent"`). See `CompareUnlearnedValue`.
--- `"pet"` and `"profession"` also say which group of the spell list the spell joins.
local data = {
    DRUID = {
        [8946] = 14, -- Cure Poison, taught by a quest (`SpecSpells_Camelot.lua`)
    },
};

local function TrainerStore(create)
    local global = DebindPrivate.db and DebindPrivate.db.global;
    if (not global) then
        return nil;
    end
    if (create and not global.trainerSpells) then
        global.trainerSpells = {};
    end
    return global.trainerSpells;
end

--- Which of two values one spell is listed with wins: below 0 for `a`, above 0 for `b`, 0 for
--- neither. A value is a level (number) or where the spell comes from (string).
---
--- **Where it comes from beats a level.** The case it was written for: a trainer sells a talent
--- spell's higher ranks with a level, and none of them can be learned before the talent is taken
--- (2026-10-01, owner). Two levels, the lower: the rank the character reaches first.
function DebindPrivate.CompareUnlearnedValue(a, b)
    local aSource, bSource = type(a) == "string", type(b) == "string";
    if (aSource ~= bSource) then
        return aSource and -1 or 1;
    end
    if (aSource or a == b) then
        return 0;
    end
    return a < b and -1 or 1;
end

local CompareUnlearnedValue = DebindPrivate.CompareUnlearnedValue;

--- The generated table's first ranks for one class and every class's (`ClassSpells_Camelot.lua`), as
--- `spellID -> value`. A higher rank's entry is its first rank's id, and the first rank's row is the
--- one that stands for it.
---
--- **Walked once, the first time the spell list is built, and kept**: the table is fixed at load and
--- a character's class does not change within a session, so nothing can make it stale.
local generated, generatedFor;
local function GeneratedCandidates(classFile)
    if (generatedFor ~= classFile) then
        generated, generatedFor = {}, classFile;
        for spellID, entry in pairs(DebindPrivate.CamelotSpells or {}) do
            if (type(entry) == "table" and (entry.classes == nil or entry.classes[classFile])) then
                generated[spellID] = entry[1];
            end
        end
    end
    return generated;
end

--- `spellID -> value` for one class, from every source, the winning value where several name an id.
function DebindPrivate.GetUnlearnedSpellCandidates(classFile)
    local merged = {};
    local sources = {
        data[classFile],
        GeneratedCandidates(classFile),
        (TrainerStore(false) or {})[classFile],
    };
    for i = 1, 3 do
        for spellID, value in pairs(sources[i] or {}) do
            if (merged[spellID] == nil or CompareUnlearnedValue(value, merged[spellID]) < 0) then
                merged[spellID] = value;
            end
        end
    end
    return merged;
end

--- **What the window shows now, and the filters are left as the reader set them**
--- (2026-09-30, owner). The probe turned all three on for its read; that is Blizzard's state.
---
--- **`used` is skipped**, and not because the book has it: a learned service reports level 0
--- (probe, 70009), which would win the merge over the rank the reader has yet to buy.
---
--- The spell id comes off the service's tooltip; `GetTrainerServiceInfo` does not give one.
--- Whether the generated table names this spell, or the first rank it stands under, a pet's.
local function IsPetSpell(spellID)
    local spells = DebindPrivate.CamelotSpells or {};
    local entry = spells[spellID];
    if (type(entry) == "number") then
        entry = spells[entry];
    end
    return type(entry) == "table" and entry[1] == "pet";
end

local function ReadTrainer()
    if (C_Trainer.GetTrainerType() ~= Enum.TrainerType.General or IsTradeskillTrainer()) then
        return;
    end
    -- **A pet trainer answers as a class trainer here** (probe, 70124: type 0), so it is told by
    -- what it teaches. Read as one, its spells stood in the class group; the pet's come from the
    -- generated table instead.
    for i = 1, GetNumTrainerServices() do
        local tooltip = C_TooltipInfo.GetTrainerService(i);
        if (tooltip and tooltip.id and IsPetSpell(tooltip.id)) then
            return;
        end
    end
    local _, classFile = UnitClass("player");
    local store = TrainerStore(true);
    if (not store) then
        return;
    end
    local class = store[classFile] or {};
    store[classFile] = class;

    local added = false;
    for i = 1, GetNumTrainerServices() do
        local _, serviceType, _, reqLevel = GetTrainerServiceInfo(i);
        local tooltip = (serviceType == "available" or serviceType == "unavailable")
            and C_TooltipInfo.GetTrainerService(i);
        local spellID = tooltip and tooltip.id;
        -- **`IsSpellPassive` answers for a spell the character does not have** (measured in game,
        -- 2026-10-01): the weapon and armour skills a trainer sells come back passive although their
        -- service has no "Passive" subtext, as Parry's does.
        if (spellID and not C_Spell.IsSpellPassive(spellID)) then
            local level = reqLevel or 0;
            if (class[spellID] == nil or level < class[spellID]) then
                class[spellID] = level;
                added = true;
            end
        end
    end

    if (added) then
        DebindPrivate.ActionCatalog.Invalidate("spellbook");
    end
end

--- **From login and not from file scope**, so an addon standing down over a newer profile listens
--- to nothing here either (`Events.PLAYER_LOGIN`).
---
--- `TRAINER_UPDATE` is what arrives when the reader changes a filter, and the list has already
--- changed by then: Blizzard's own window redraws from it in its handler for that event
--- (`Blizzard_TrainerUI.lua`, `ClassTrainerFrame_OnEvent`).
function DebindPrivate.StartReadingTrainers()
    local frame = CreateFrame("Frame");
    frame:RegisterEvent("TRAINER_SHOW");
    frame:RegisterEvent("TRAINER_UPDATE");    frame:SetScript("OnEvent", ReadTrainer);
end
