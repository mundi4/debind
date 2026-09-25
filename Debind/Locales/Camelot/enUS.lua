local _, addon = ...;
local L = addon.L;

-- **Loaded on camelot only, after every locale**, by the line in `Debind.toc` that carries
-- `[AllowLoadGameType camelot]`. What it sets replaces the value the locales gave, in every locale.

-- Every class has one specialization here and the player never picks it, so what the condition
-- picks is a class. The client's own word, already in every locale.
L["CONDITION_SPEC"] = CLASS
