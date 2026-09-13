-- The self and focus twins, taken back out of a key's list.
--
-- Every action puts a self twin and a focus twin on its key, and those fill the key's first two
-- tiers (`devdocs/implementing-focus-and-self-cast.md` §3-4). Most specs ask about the order
-- among actions, or among what a press with no modifier held can reach. These helpers let them keep
-- asking exactly that, where writing every index out with the twins in would bury the question
-- under arithmetic.
--
-- **A twin winning is not quietly skipped.** `index` answers with a string that equals no number,
-- so a spec expecting an ordinal fails on it.

local M = {};

local function isTwin(Constants, record)
    local castModifier = record.castModifier;
    return castModifier == Constants.CASTMOD_SELF or castModifier == Constants.CASTMOD_FOCUS;
end
M.isTwin = isTwin;

--- The list without the self and focus twins, as a new array. nil stays nil.
function M.without(Constants, records)
    if (not records) then
        return nil;
    end
    local out = {};
    for i = 1, #records do
        if (not isTwin(Constants, records[i])) then
            out[#out + 1] = records[i];
        end
    end
    return out;
end

--- Where record `i` stands among the records that are not twins, or a string naming the twin.
function M.index(Constants, records, i)
    if (not i) then
        return nil;
    end
    if (isTwin(Constants, records[i])) then
        return "twin at " .. i;
    end
    local n = 0;
    for j = 1, i do
        if (not isTwin(Constants, records[j])) then
            n = n + 1;
        end
    end
    return n;
end

return M;
