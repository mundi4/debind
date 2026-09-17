-- The self and focus twins and the BLOCKs, taken back out of a key's list.
--
-- Every action puts a self twin and a focus twin on its key, and those fill the key's first two
-- tiers (`devdocs/implementing-focus-and-self-cast.md` §3-4); every tier of a key that holds one
-- ends in a BLOCK (`devdocs/legacy/dropping-the-game-fallback.md` §3). Most specs ask about the order
-- among actions, or among what a press with no modifier held can reach. These helpers let them keep
-- asking exactly that, where writing every index out with the twins and blocks in would bury the
-- question under arithmetic.
--
-- **Two shapes come through here.** A binding carries its `type`; an emitted record carries none,
-- and a BLOCK record is the one with no `clickbutton`.
--
-- **Skipping is not quietly passing.** `index` answers with a string that equals no number, so a
-- spec expecting an ordinal fails on a twin or a block winning.

local M = {};

local function isTwin(Constants, record)
    local castModifier = record.castModifier;
    return castModifier == Constants.CASTMOD_SELF or castModifier == Constants.CASTMOD_FOCUS;
end
M.isTwin = isTwin;

local function isBlock(Constants, record)
    if (record.type ~= nil) then
        return record.type == Constants.BLOCK;
    end
    return record.clickbutton == nil;
end
M.isBlock = isBlock;

local function skipped(Constants, record)
    return isTwin(Constants, record) or isBlock(Constants, record);
end

--- The list without the self and focus twins and the blocks, as a new array. nil stays nil.
function M.without(Constants, records)
    if (not records) then
        return nil;
    end
    local out = {};
    for i = 1, #records do
        if (not skipped(Constants, records[i])) then
            out[#out + 1] = records[i];
        end
    end
    return out;
end

--- Where record `i` stands among the records that are neither twins nor blocks, or a string naming
--- what it is.
function M.index(Constants, records, i)
    if (not i) then
        return nil;
    end
    if (isTwin(Constants, records[i])) then
        return "twin at " .. i;
    end
    if (isBlock(Constants, records[i])) then
        return "block at " .. i;
    end
    local n = 0;
    for j = 1, i do
        if (not skipped(Constants, records[j])) then
            n = n + 1;
        end
    end
    return n;
end

return M;
