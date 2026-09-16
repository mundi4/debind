-- The Casting values, for the specs that are **not** about them.
--
-- Every action stands on four presses (`devdocs/which-action-a-key-runs.md` §6), and one written
-- with no `casting` at all follows the account's Hover Cast mode -- so it puts a hover twin on its
-- key beside its original. A spec measuring something else would be reading two records per action
-- and asking its question through arithmetic.
--
-- **Skip this action is the shape an existing profile arrives in**, not a shape invented here: the
-- `dbver` 7 step moves every action that had no unit frame condition to it (§8), so an action a
-- spec writes by hand looks like one that came through the ladder.

local M = {};

--- The action, with its Hover Cast off. Edits the table and hands it back, so it can wrap a
--- constructor call.
function M.skipHover(action)
    local casting = action.casting;
    if (casting == nil) then
        casting = {};
        action.casting = casting;
    end
    casting.hoverCast = { mode = "skip" };
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
