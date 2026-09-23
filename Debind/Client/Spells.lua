local _, DebindPrivate = ...;
local Client = DebindPrivate.Client;

--- **Whether spells come in ranks, each rank its own id under one name.** Camelot's do, and there a
--- spell's subtext is its rank ("Rank 1", measured on 69977). `IsSpellBookItemLowRank` exists only
--- on a client with ranks. Taken once at load because `ComposeSpellCastName` may not ask the client
--- anything (it spells the value `DescribeBinding` does).
Client.SPELLS_HAVE_RANKS = C_SpellBook.IsSpellBookItemLowRank ~= nil;

--- Whether a book item is a lower rank the client's own book would hide. That book hides them
--- unless `ShowAllSpellRanks` is on (`Blizzard_SpellBookFrame.lua`), and a list of spells to bind
--- follows it: the cast name carries no rank, so a lower rank's row casts the highest anyway.
function Client.IsHiddenLowRank(slotIndex, bank)
    if (not Client.SPELLS_HAVE_RANKS or GetCVarBool("ShowAllSpellRanks")) then
        return false;
    end
    return C_SpellBook.IsSpellBookItemLowRank(slotIndex, bank);
end

--- The spellbook's class line, as `GetSpellBookSkillLineInfo` answers a line.
---
--- **Camelot's book has no class line among its lines**: one line per talent tree, so its second
--- line is a tree (Restoration for a druid, 69977). Its own book borrows the class line from
--- `GetClassSkillLineInfo`, which only that client has (`Camelot/SpellBook/Blizzard_SpellBookFrame.lua`).
function Client.ClassSkillLine()
    if (C_SpellBook.GetClassSkillLineInfo) then
        return C_SpellBook.GetClassSkillLineInfo();
    end
    return C_SpellBook.GetSpellBookSkillLineInfo(Enum.SpellBookSkillLineIndex.Class);
end
