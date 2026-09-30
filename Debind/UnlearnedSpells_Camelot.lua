local _, DebindPrivate = ...;

--- The spells a character on World of Warcraft: Forever has not learned yet, for the spell list's
--- Unlearned group (`ActionCatalog.lua`). Loaded on that client only (`Debind.toc`): its spellbook
--- holds only what has been learned, where retail's lists the rest as `FutureSpell`.
---
--- **Two sources, merged, and nothing is ever taken out**
--- (`listing-unlearned-spells-on-forever.md`). Neither is complete: a trainer window lists only what
--- its filters let through, and some spells never appear at a trainer at all.

--- `[classFile] = { [spellID] = level required }`, for the spells no class trainer lists: a quest
--- reward, or a spell only another race is taught. Merged with what trainers were seen selling.
local data = {
    DRUID = {
        [8946] = 14, -- Cure Poison, taught by a quest and not by a trainer
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

--- `spellID -> level required` for one class: both sources, the lower level where both name an id.
function DebindPrivate.GetUnlearnedSpellCandidates(classFile)
    local merged = {};
    local sources = { data[classFile], (TrainerStore(false) or {})[classFile] };
    for i = 1, 2 do
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
