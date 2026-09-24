local _, DebindPrivate = ...;
local Constants             = DebindPrivate.Constants;

local GetSpellNameAndIconID = DebindPrivate.GetSpellNameAndIconID;

--- What this binding's `known` condition asks about: the spell it names, or the action's own spell
--- where it says `true` (`making-known-a-spell-name.md`). nil where there is no condition,
--- and where `true` has no spell to fall back on.
---
--- **One answer for the three places that ask.** The conditional baked into the record, the
--- solver's column key and the overview's "no spell" mark all have to name the same thing, and
--- they used to spell the derivation out one at a time.
--- A boolean is the shape that asks about the action, and `false` is one of those: it never
--- reaches storage (`GetBindingInfoForAction` strips it) but the solver models both answers on one
--- axis, and both are about the same spell.
---
--- **The action's spell is named too** (2026-09-12, owner). What goes out is then one shape
--- whatever the condition stored, and two actions asking about the same spell share a state key
--- even when one of them is a `Dispel` and the other holds the spell itself. The id is what is
--- left when the client cannot name it, which is where `[known:]` answers false anyway.
function DebindPrivate.KnownSpellAsked(binding)
    local asked = binding.conditions and binding.conditions.known;
    if (asked == nil) then
        return nil;
    end
    if (type(asked) == "boolean") then
        local spell = binding.spell or binding.value;
        return spell and (GetSpellNameAndIconID(spell) or spell);
    end
    return asked;
end

--- Does this binding's `known` condition have a spell to ask about? **The second condition the
--- insecure side settles by itself**, for the same reason as `SpecConditionHolds`: a spec-resolved
--- type asks about the spell this specialization resolves to (`binding.spell`), a specialization
--- that has none leaves the condition false for every press in this build, and a specialization
--- change rebuilds everything.
---
--- **Only `true` can answer no**, because only `true` asks about the action
--- (`making-known-a-spell-name.md`). A condition carrying a spell of its own asks the same
--- question whatever this specialization resolves to, and a specialization that cannot answer it
--- is answering false rather than having nothing to answer.
---
--- Only those three types can answer no. Every other type asks about a value the action stores,
--- which is there or the action would not have been built.
function DebindPrivate.KnownConditionCanHold(binding)
    local conditions = binding.conditions;
    if (conditions == nil or conditions.known ~= true) then
        return true;
    end
    if (not Constants.SPEC_RESOLVED_TYPES[binding.type]) then
        return true;
    end
    return binding.spell ~= nil;
end
