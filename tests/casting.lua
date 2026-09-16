-- The Casting values, for the specs that are **not** about them.
--
-- Every action stands on four presses (`devdocs/which-action-a-key-runs.md` §6), and one written
-- with no `casting` at all follows the account's Hover Cast mode -- so it puts a hover twin on its
-- key beside its original. A spec measuring something else would be reading two records per action
-- and asking its question through arithmetic.
--
-- **Skip this action takes the twin away and stands the original on [no unit frame].** No stored
-- shape gives an action with neither since Skip means the same on all three rows, so what a spec
-- reads carries that one unit row.
--
-- **An action with a condition on the unit frame is left as it is.** Skip would leave its original
-- nowhere to stand (`FillBinding`), and its twin is the same box as its original, which the solver
-- folds back into one record: what such a spec reads is one record either way.

local M = {};

--- The action, out of the pointed press. Edits the table and hands it back, so it can wrap a
--- constructor call.
function M.skipHover(action)
    local units = action.conditions and action.conditions.units;
    if (units and type(units.unitframe) == "table") then
        return action;
    end
    local casting = action.casting;
    if (casting == nil) then
        casting = {};
        action.casting = casting;
    end
    casting.hoverCast = { aim = "skip" };
    return action;
end

--- Every action in the list, likewise.
function M.skipHoverAll(actions)
    for i = 1, #actions do
        M.skipHover(actions[i]);
    end
    return actions;
end

return M;
