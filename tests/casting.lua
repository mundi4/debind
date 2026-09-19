-- Turning Hover Cast on, for the specs that need a hover twin without being about Hover Cast.
--
-- Off is what an action written with no `casting` has (`which-action-a-key-runs.md` §6), so
-- a spec that measures conditions or ordering reads one record per action and needs nothing here.
-- A spec that measures the pointed press needs the twin, and the twin is what this puts on.
--
-- **An action with a condition on the unit frame is left as it is.** Its twin is the same box as its
-- original, which the solver folds back into one record: what such a spec reads is one record either
-- way.

local M = {};

--- The action, answering a pointed press at the unit it points at. Edits the table and hands it
--- back, so it can wrap a constructor call.
function M.castOnHover(action)
    local casting = action.casting;
    if (casting == nil) then
        casting = {};
        action.casting = casting;
    end
    casting.hoverCast = "cast";
    return action;
end

--- Every action in the list, likewise.
function M.castOnHoverAll(actions)
    for i = 1, #actions do
        M.castOnHover(actions[i]);
    end
    return actions;
end

return M;
