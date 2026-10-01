local _, DebindPrivate = ...;

--- The spells a character on World of Warcraft: Forever has not learned yet, for the spell list's
--- Unlearned group (`ActionCatalog.lua`). Loaded on that client only (`Debind.toc`): its spellbook
--- holds only what has been learned, where retail's lists the rest as `FutureSpell`.
---
--- **Three sources, merged, and nothing is ever taken out** (`listing-unlearned-spells-on-forever.md`):
--- the class lists generated off wowhead (`ClassSpells_Camelot.lua`), what the class trainers were
--- read selling, and the ids written below. None is complete on its own: the generated lists are
--- wowhead's, a trainer window lists only what its filters let through, and some spells never
--- appear at a trainer at all. The talent tree is a fourth, read where the group is built
--- (`ActionCatalog.lua`).

--- `[classFile] = { [spellID] = level required }`, for what the other two miss.
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

--- `spellID -> level required` for one class: every source, the lowest level where several name an
--- id.
function DebindPrivate.GetUnlearnedSpellCandidates(classFile)
    local merged = {};
    local sources = {
        data[classFile],
        (DebindPrivate.CamelotClassSpells or {})[classFile],
        (TrainerStore(false) or {})[classFile],
    };
    for i = 1, 3 do
        for spellID, level in pairs(sources[i] or {}) do
            if (merged[spellID] == nil or level < merged[spellID]) then
                merged[spellID] = level;
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
local function ReadTrainer()
    if (C_Trainer.GetTrainerType() ~= Enum.TrainerType.General or IsTradeskillTrainer()) then
        return;
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
        local _, serviceType, _, reqLevel, subText = GetTrainerServiceInfo(i);
        local tooltip = (serviceType == "available" or serviceType == "unavailable")
            and C_TooltipInfo.GetTrainerService(i);
        local spellID = tooltip and tooltip.id;
        -- Passive by the service's own subtext as well, since whether `IsSpellPassive` answers for a
        -- spell the character does not have is not known. The catalog asks it again.
        if (spellID and subText ~= SPELL_PASSIVE and not C_Spell.IsSpellPassive(spellID)) then
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
