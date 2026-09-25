local _, addon = ...;
local L = addon.L;

-- **Loaded on camelot only, after every locale**, by the line in `Debind.toc` whose game type
-- conditions say so. What it sets replaces the value the locales gave, in every locale.

-- Every class has one specialization here and the player never picks it, so what the condition
-- picks is classes. Plural like the rows around it (`Talents`, `Units`): the row opens a list to
-- tick. The client has no plural of `CLASS` to borrow.
L["CONDITION_SPEC"] = "Classes"
L["CONDITION_SPECS"] = "Classes"
