local _, DebindPrivate = ...;
local Client = DebindPrivate.Client;

--- **Whether spells come in ranks, each rank its own id under one name.** Camelot's do, and there a
--- spell's subtext is its rank ("Rank 1", measured on 69977). `IsSpellBookItemLowRank` exists only
--- on a client with ranks. Taken once at load because `ComposeSpellCastName` may not ask the client
--- anything (it spells the value `DescribeBinding` does).
Client.SPELLS_HAVE_RANKS = C_SpellBook.IsSpellBookItemLowRank ~= nil;

--- Whether a book item is a lower rank of a spell the book holds a higher rank of.
function Client.IsLowRank(slotIndex, bank)
    return Client.SPELLS_HAVE_RANKS and C_SpellBook.IsSpellBookItemLowRank(slotIndex, bank) or false;
end

--- Whether a book item is a lower rank the client's own book would hide. That book hides them
--- unless `ShowAllSpellRanks` is on (`Blizzard_SpellBookFrame.lua`), and a list of spells to bind
--- follows it: an unpinned cast name carries no rank, so a lower rank's row would cast the highest.
function Client.IsHiddenLowRank(slotIndex, bank)
    return not GetCVarBool("ShowAllSpellRanks") and Client.IsLowRank(slotIndex, bank);
end

--- The ranks of a spell the character has, as `{ id =, subtext = }` in book order: every player
--- book item under the spell's name. Empty where spells have no ranks.
function Client.SpellRanks(spellID)
    local out = {};
    local name = Client.SPELLS_HAVE_RANKS and C_Spell.GetSpellName(spellID);
    if (not name) then
        return out;
    end
    local bank = Enum.SpellBookSpellBank.Player;
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line);
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, bank);
            local id = item and item.spellID;
            if (id and C_Spell.GetSpellName(id) == name) then
                out[#out + 1] = { id = id, subtext = C_Spell.GetSpellSubtext(id) };
            end
        end
    end
    return out;
end

--- `GetFlyoutInfo`, answering nothing for a flyout the client does not have.
---
--- **Camelot 69977 raised for one instead** ("No flyout found for ID"), where retail answers
--- nothing; 70009 answers nothing too. A flyout id can come from somewhere other than this
--- client's own book: the skyriding one the bonus bar labels name, and any flyout action in a string brought over from retail.
function Client.FlyoutInfo(flyoutID)
    local ok, name, description, numSlots, isKnown = pcall(GetFlyoutInfo, flyoutID);
    if (not ok) then
        return nil;
    end
    return name, description, numSlots, isKnown;
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
