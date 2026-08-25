-- **The value a spell goes on a secure button under, and the three places that had to agree on it.**
--
-- A spell is bound by name rather than by id, because two specializations can hold spells that share
-- a name under different ids and an id bound here does not fire for the other one. The subtext is
-- what tells those two apart, so it is appended in the client's parenthesised form.
--
-- The rule was written out by hand in three places: `GetFlyoutCastableSlots`, `ConvertToMacroText`
-- and `DescribeBinding`. **Divergence there is silent.** A site that drops the subtext casts the
-- wrong one of two same-named spells, or nothing at all, while the list on screen still shows the
-- right name -- so nothing about looking at the window would find it. That is what this spec is for:
-- not the rule in the abstract, but the three answers being the same string.
--
-- `DescribeBinding` reaches the rule through `ComposeSpellCastName`, the pure half, because that
-- function may not ask the client anything (`UpdateBindings.lua`'s `CollectBindingFacts` holds every
-- call in that path). The other two go through `GetSpellCastName`, which asks.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");

    local T = { passed = 0, failures = {} };

    local function test(name, fn)
        local ok, err = pcall(fn);
        if (ok) then
            T.passed = T.passed + 1;
        else
            T.failures[#T.failures + 1] = name .. ": " .. tostring(err);
        end
    end

    local function check(cond, msg)
        if (not cond) then
            error(msg or "check failed", 2);
        end
    end

    local Compose = DebindPrivate.ComposeSpellCastName;
    local CastName = DebindPrivate.GetSpellCastName;

    --- Two spells sharing a name across specializations, which is the case the subtext exists for.
    --- 8936 is the one with a subtext; 774 has none and is the ordinary shape beside it.
    ---
    --- **17116 is an override pointing back at 774.** Only `ConvertToMacroText` resolves that, and
    --- it is here so the flyout's answer and the macro's answer can be compared on a slot whose id
    --- is already a base id.
    local function installWorld()
        shim.world.spells[8936] = { name = "Regrowth", iconID = 136085, subtext = "Restoration" };
        shim.world.spells[774] = { name = "Rejuvenation", iconID = 136081 };
        shim.world.spells[17116] = { name = "Nature's Swiftness" };
        shim.world.baseSpells[17116] = 774;
        shim.world.flyouts[66] = { name = "Growth", slots = { 8936, 774 } };
    end

    test("the rule - a subtext is appended, an empty one is not", function()
        check(Compose("Regrowth", "Restoration") == "Regrowth(Restoration)",
            "a subtext did not go into brackets");
        check(Compose("Renew", nil) == "Renew", "a nil subtext changed the name");
        check(Compose("Renew", "") == "Renew", "an empty subtext changed the name");
    end);

    --- **Nil in, nil out, and the callers are what makes that matter.** All three fall back to the
    --- id when the name does not resolve, and they can only do that if the composer refuses to hand
    --- back something like `"(Restoration)"` for a spell it could not name.
    test("the rule - no name means no answer", function()
        check(Compose(nil, nil) == nil, "a nil name did not come back nil");
        check(Compose(nil, "Restoration") == nil, "a subtext alone built a name");
    end);

    test("asking the client gives the same answer as composing by hand", function()
        installWorld();
        check(CastName(8936) == "Regrowth(Restoration)", "the client-facing half lost the subtext");
        check(CastName(774) == "Rejuvenation", "a spell with no subtext gained one");
        check(CastName(5176) == nil, "a spell the world does not name answered with something");
    end);

    --- The first of the two sites that ask the client. A flyout slot is handed its base id, so it
    --- does not resolve one, and the cast value must still carry the subtext.
    test("a flyout slot casts by the same string", function()
        installWorld();
        local slots = DebindPrivate.GetFlyoutCastableSlots(66);
        check(#slots == 2, "expected two castable slots, got " .. #slots);

        local bySpell = {};
        for i = 1, #slots do
            bySpell[slots[i].spellID] = slots[i];
        end

        check(bySpell[8936], "the subtexted spell is not among the castable slots");
        check(bySpell[8936].cast == CastName(8936),
            "the flyout slot casts " .. tostring(bySpell[8936].cast)
                .. " where the shared answer is " .. tostring(CastName(8936)));
        check(bySpell[774].cast == CastName(774), "the plain slot disagrees with the shared answer");
    end);

    --- The second. This one **does** resolve the id first, which is why the override's assertion is
    --- against `CastName(774)` and not `CastName(17116)`: what a reader stored is an override, and
    --- the macro has to name the base spell or it fires nothing on the other specialization.
    ---
    --- **The conversion rewrites the action in place** and answers `true`, so each case needs one of
    --- its own and the body is read back out of `value`.
    local function convert(spellID)
        local action = { type = Constants.SPELL, value = spellID };
        check(DebindPrivate.ConvertToMacroText(action), "the conversion refused spell " .. spellID);
        return action.value;
    end

    --- **The whole body, not a substring of it.** `find` alone let a body reading
    --- `nil Regrowth(Restoration)` pass: `SLASH_CAST1` was missing from the shim, `%s` in Lua 5.4
    --- prints a nil rather than refusing it, and the name the check looked for was still in there.
    --- CI runs lua5.1, which does refuse it, so the same run was green here and red there.
    test("a macro body names the spell by the same string", function()
        installWorld();

        check(convert(8936) == "/cast Regrowth(Restoration)",
            "the macro body is not what it should be: " .. convert(8936));

        check(convert(17116) == "/cast " .. CastName(774),
            "the macro body did not resolve the override to its base name: " .. convert(17116));
    end);

    --- The third, reached the way `DescribeBinding` reaches it: with the two halves already in hand
    --- and no client to ask. **Held against the site that does ask**, because agreeing with itself
    --- is not what this spec is about.
    test("what gets stamped on the button is the same string", function()
        installWorld();

        local facts = { spellID = 8936, spellName = "Regrowth", spellSubtext = "Restoration" };
        local descriptor = DebindPrivate.DescribeBinding(Constants.SPELL, 8936, nil, facts, nil);

        local stamped;
        for i = 1, descriptor.count do
            if (descriptor.attrNames[i] == "*spell-") then
                stamped = descriptor.attrValues[i];
            end
        end

        check(stamped == CastName(8936),
            "the button is stamped " .. tostring(stamped)
                .. " where the shared answer is " .. tostring(CastName(8936)));
    end);

    --- The fallback, on the site where getting it wrong is worst. An id on the attribute at least
    --- fires for the reader who is on the specialization that has the spell; an empty string or a
    --- `nil` binds the key to nothing and takes every lower action on it down with it.
    test("a name that does not resolve falls back to the id", function()
        installWorld();

        local descriptor = DebindPrivate.DescribeBinding(
            Constants.SPELL, 5176, nil, { spellID = 5176 }, nil);

        local stamped;
        for i = 1, descriptor.count do
            if (descriptor.attrNames[i] == "*spell-") then
                stamped = descriptor.attrValues[i];
            end
        end

        check(stamped == 5176, "expected the id on the attribute, got " .. tostring(stamped));
    end);

    return T;
end
