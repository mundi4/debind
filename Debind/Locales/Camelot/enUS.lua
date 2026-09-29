local _, addon = ...;
local L = addon.L;

-- **Loaded on camelot only, after every locale**, by the line in `Debind.toc` whose game type
-- conditions say so. What it sets replaces the value the locales gave, in every locale.

-- Every class has one specialization here and the player never picks it, so what the condition
-- picks is classes. Plural like the rows around it (`Talents`, `Units`): the row opens a list to
-- tick. The client has no plural of `CLASS` to borrow.
L["CONDITION_SPEC"] = "Classes"
L["CONDITION_SPECS"] = "Classes"

-- **Named after what they remove** (2026-09-27, owner): a reader with several healers thinks of a
-- curse-and-disease key and a magic-and-poison key, the same on every character
-- (`splitting-the-camelot-dispel.md`). A colon and not "Dispel Magic ...", which is a priest spell.
L["TYPE_DISPEL"] = "Dispel: Curse, Disease"
L["TYPE_DISPEL_DESC"] = "Casts your class's friendly dispel for a curse or a disease. Where your class has two, the higher-level one is cast once you know it."
L["TYPE_DISPEL2"] = "Dispel: Magic, Poison"
L["TYPE_DISPEL2_DESC"] = "Casts your class's friendly dispel for magic or a poison. Where your class has two, the higher-level one is cast once you know it."
