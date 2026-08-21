-- What a binding needs stamped on the click frame before it can fire, and **why one is refused**.
--
-- `SetBindingAttributes` used to answer both at once by writing the attributes and returning the
-- button name, so a refusal was a missing return value and one DEBUG log line
-- (`devdocs/legacy/going-headless-outside-the-ui.md` §3-3). Getting a refusal wrong is not a binding that
-- goes missing -- the secure side counts an emitted record as a binding that took, so `keyBound`
-- goes up and **every lower priority action on that key is blocked with it**. A hunter with no pet
-- and a Call Pet binding is the case that put the drop there.
--
-- **These specs build no frames.** `DescribeBinding` asks the client nothing and touches nothing;
-- everything it needs arrives in `facts`, which is what a spec hands in as plain values rather
-- than by imitating an API (§4).

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local frames = require("wow_frames");

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

    --- Describes one binding against facts written out here, into a table of its own so two
    --- descriptors can be held side by side.
    local function describe(type, value, unit, facts)
        return DebindPrivate.DescribeBinding(type, value, unit, facts or {}, nil);
    end

    --- The value a descriptor would put on one attribute, and whether it names it at all. The two
    --- are different answers: `*macro-` named with a nil value **clears** it, and not naming it
    --- leaves whatever was there.
    local function attribute(descriptor, name)
        for i = 1, descriptor.count do
            if (descriptor.attrNames[i] == name) then
                return descriptor.attrValues[i], true;
            end
        end
        return nil, false;
    end

    ---------------------------------------------------------------------------
    -- Refusals
    ---------------------------------------------------------------------------

    -- A pet command the client has no slash command for. There is nothing to bind and no way to
    -- find out at the press, so the binding must not reach a record at all.
    test("a pet command with no slash command behind it is refused", function()
        local descriptor, reason = describe(Constants.PETACTION, "PETNOSUCHCOMMAND", "target",
            { petMacrotext = nil });
        check(descriptor == nil, "it described a pet command that cannot fire");
        check(reason == "unknown-pet-action", "reason: " .. tostring(reason));
    end);

    -- The same type with the macro text resolved: it stops being a pet command and becomes macro
    -- text, **carrying its target in the body**, which is why the unit is dropped.
    test("a pet command that resolves becomes macro text with no unit", function()
        local descriptor = describe(Constants.PETACTION, "PETATTACK", "target",
            { petMacrotext = "/petattack [@target]" });
        check(descriptor, "a resolvable pet command was refused");
        check(descriptor.type == Constants.MACROTEXT, "type: " .. tostring(descriptor.type));
        check(descriptor.unit == nil, "the unit survived: " .. tostring(descriptor.unit));
        check(attribute(descriptor, "*macrotext-") == "/petattack [@target]",
            "body: " .. tostring(attribute(descriptor, "*macrotext-")));
    end);

    -- **The flyout with no opener is the one the drop was written for.** A flyout whose slots are
    -- all empty -- a hunter who let the last pet go -- has a handle that opens nothing, and a key
    -- bound to it does nothing when pressed while still counting as bound.
    test("a flyout with no opener is refused", function()
        local descriptor, reason = describe(Constants.FLYOUT, 900, nil, { flyoutOpener = nil });
        check(descriptor == nil, "it described a flyout that opens nothing");
        check(reason == "no-flyout-opener", "reason: " .. tostring(reason));
    end);

    -- An on/off/toggle action whose switch has not been chosen yet. The name is the only thing
    -- left to be wrong once the type has decided the mode, and handing `SetAttribute` a nil name
    -- raises nothing -- it clears the attribute and the key dies quietly on the restricted side.
    test("a switch action with no switch named is refused", function()
        local descriptor, reason = describe(Constants.SETSTATE_TOGGLE, 3, nil, {});
        check(descriptor == nil, "it described a switch action with a number for a name");
        check(reason == "switch-not-chosen", "reason: " .. tostring(reason));
    end);

    -- A type this build does not know. It cannot come from the window, but it can come from a
    -- profile written by a newer build.
    test("an unknown type is refused", function()
        local descriptor, reason = describe("teleport", 1, nil, {});
        check(descriptor == nil, "it described an unknown type");
        check(reason == "unhandled-type", "reason: " .. tostring(reason));
    end);

    -- **Not every nil is a refusal.** Unused clears the key and a command binds itself, so neither
    -- needs a button -- and the caller must not drop them the way it drops the four above.
    test("unused and command are answered apart from the refusals", function()
        local _, unusedReason = describe(Constants.UNUSED, nil, nil, {});
        local _, commandReason = describe(Constants.COMMAND, "TOGGLEWORLDMAP", nil, {});
        check(unusedReason == "self-bound", "unused: " .. tostring(unusedReason));
        check(commandReason == "self-bound", "command: " .. tostring(commandReason));
    end);

    ---------------------------------------------------------------------------
    -- What gets described
    ---------------------------------------------------------------------------

    -- A spell goes out **by name**, because two specializations can hold spells with one name and
    -- different ids, and binding the id fires nothing in the other one. A subtext is what tells
    -- those two apart, so it is appended in brackets when there is one.
    test("a spell that resolves goes out by name, with its subtext", function()
        local plain = describe(Constants.SPELL, 585, nil, { spellID = 585, spellName = "Renew" });
        check(attribute(plain, "*spell-") == "Renew", "plain: " .. tostring(attribute(plain, "*spell-")));

        local ranked = describe(Constants.SPELL, 8936, nil,
            { spellID = 8936, spellName = "Regrowth", spellSubtext = "Restoration" });
        check(attribute(ranked, "*spell-") == "Regrowth(Restoration)",
            "ranked: " .. tostring(attribute(ranked, "*spell-")));

        -- An empty subtext is not a subtext. Appending `()` would name a spell that does not
        -- exist and the key would fire nothing.
        local empty = describe(Constants.SPELL, 585, nil,
            { spellID = 585, spellName = "Renew", spellSubtext = "" });
        check(attribute(empty, "*spell-") == "Renew", "empty: " .. tostring(attribute(empty, "*spell-")));
    end);

    -- And where the name does not resolve, the id goes out instead. **The id it carries is the
    -- base spell**, which is what an override points back at.
    test("a spell whose name does not resolve goes out by id", function()
        local descriptor = describe(Constants.SPELL, 155777, nil, { spellID = 774 });
        check(attribute(descriptor, "*spell-") == 774,
            "id: " .. tostring(attribute(descriptor, "*spell-")));
    end);

    -- Press and hold bakes two extra attributes. **The fact that it was baked is what the wrapper
    -- reads**, so a descriptor that says press and hold and a stamp that did not write these two
    -- would be a spell that starts on the press and never lets go.
    test("press and hold bakes the release attributes", function()
        local held = describe(Constants.SPELL, 271466, nil,
            { spellID = 271466, spellName = "Will of the Necropolis", pressAndHold = true });
        check(attribute(held, "*typerelease-") == "spell", "no typerelease");
        check(attribute(held, "*pressAndHoldAction-") == true, "no pressAndHoldAction");
        check(held.pressAndHold == true, "the descriptor does not say press and hold");

        local ordinary = describe(Constants.SPELL, 585, nil, { spellID = 585, spellName = "Renew" });
        local _, named = attribute(ordinary, "*typerelease-");
        check(named == false, "an ordinary spell named typerelease");
        check(ordinary.pressAndHold == false, "an ordinary spell says press and hold");
    end);

    -- **A macro and macro text share one attribute pair and have to clear the other half.** Both
    -- go out as `type="macro"`, and a button that kept the previous binding's `*macrotext-` would
    -- run that body instead of the macro named beside it.
    test("macro and macro text each clear the other's attribute", function()
        local macro = describe(Constants.MACRO, "Trinkets", nil, {});
        check(attribute(macro, "*macro-") == "Trinkets", "the macro name is missing");
        local value, named = attribute(macro, "*macrotext-");
        check(named == true and value == nil, "a macro did not clear *macrotext-");

        local text = describe(Constants.MACROTEXT, "/cast Renew", nil, {});
        check(attribute(text, "*macrotext-") == "/cast Renew", "the body is missing");
        local macroValue, macroNamed = attribute(text, "*macro-");
        check(macroNamed == true and macroValue == nil, "macro text did not clear *macro-");
    end);

    -- A mount takes the spell fork when the journal names a spell **whether or not that spell's
    -- name resolves**, and the generated macro text only where it names none.
    test("a mount forks on the journal's spell id, not on the name", function()
        local named = describe(Constants.MOUNT, 6, nil,
            { mountSpellID = 458, mountSpellName = "Brown Horse" });
        check(attribute(named, "*type-") == "spell", "type: " .. tostring(attribute(named, "*type-")));
        check(attribute(named, "*spell-") == "Brown Horse", "name is missing");

        local spellless = describe(Constants.MOUNT, 7, nil,
            { mountMacrotext = "/script C_MountJournal.SummonByID(7)" });
        check(attribute(spellless, "*type-") == "macro",
            "type: " .. tostring(attribute(spellless, "*type-")));
        check(attribute(spellless, "*macrotext-") == "/script C_MountJournal.SummonByID(7)",
            "body is missing");
    end);

    ---------------------------------------------------------------------------
    -- The cache key
    ---------------------------------------------------------------------------

    -- **An item is looked up under its id and filed under its id.** The value used to be rewritten
    -- to `"item:<id>"` for the attribute before the key was read back, so the lookup and the filing
    -- disagreed: every rebuild missed, allocated a fresh button, and left the last one behind --
    -- for the whole session, since the cache is never cleared.
    test("an item is filed under the id it is looked up by", function()
        local descriptor = describe(Constants.ITEM, 6948, nil, {});
        check(descriptor.cacheKey == 6948, "cacheKey: " .. tostring(descriptor.cacheKey));
        check(attribute(descriptor, "*item-") == "item:6948",
            "attribute: " .. tostring(attribute(descriptor, "*item-")));
    end);

    -- The same thing seen from where it actually hurt: two rebuilds of one item binding used to
    -- hand out two buttons, and the one from the first rebuild stayed on the click frame for the
    -- session. Measured through the whole path, because the fault was the lookup and the filing
    -- disagreeing and either half alone looks right.
    test("describing and stamping an item twice reuses one button", function()
        local first = describe(Constants.ITEM, 5512, nil, {});
        local _, firstButton = DebindPrivate.StampBinding(first);
        local second = describe(Constants.ITEM, 5512, nil, {});
        local _, secondButton = DebindPrivate.StampBinding(second);
        check(firstButton == secondButton,
            "two buttons for one item: " .. tostring(firstButton) .. " / " .. tostring(secondButton));

        -- A spell is the control: it always cached, so this half must have been green before and
        -- after. Without it, "they match" would also be true of a cache that answers one button
        -- for everything.
        local spell = describe(Constants.SPELL, 5512, nil, { spellID = 5512, spellName = "Fear" });
        local _, spellButton = DebindPrivate.StampBinding(spell);
        check(spellButton ~= firstButton,
            "a spell and an item share a button: " .. tostring(spellButton));
    end);

    ---------------------------------------------------------------------------
    -- Describing touches nothing
    ---------------------------------------------------------------------------

    -- **The claim the rest of this file rests on.** Every type is described in one pass and the
    -- recorder must catch nothing at all -- no frame built, no attribute written, nothing handed
    -- to the secure side.
    test("describing every type reaches neither a frame nor the secure side", function()
        local cases = {
            { Constants.SPELL, 585, "target", { spellID = 585, spellName = "Renew" } },
            { Constants.ITEM, 6948, "player", {} },
            { Constants.MACRO, "Trinkets", nil, {} },
            { Constants.MACROTEXT, "/cast Renew", nil, {} },
            { Constants.MOUNT, 6, nil, { mountSpellID = 458, mountSpellName = "Brown Horse" } },
            { Constants.MOUNT, 7, nil, { mountMacrotext = "/script x" } },
            { Constants.TARGET, nil, "focus", {} },
            { Constants.FOCUS, nil, "target", {} },
            { Constants.TOGGLEMENU, nil, "player", {} },
            { Constants.SETCUSTOM, 1, nil, {} },
            { Constants.SETSTATE_ON, "$burst", nil, {} },
            { Constants.FLYOUT, 66, nil, { flyoutOpener = "opener" } },
            { Constants.WORLDMARKER, 3, nil, {} },
            { Constants.PETACTION, "PETATTACK", "target", { petMacrotext = "/petattack" } },
            { Constants.UNUSED, nil, nil, {} },
            { Constants.COMMAND, "TOGGLEWORLDMAP", nil, {} },
        };

        local mark = frames.mark();
        local described = 0;
        for i = 1, #cases do
            local case = cases[i];
            local descriptor = describe(case[1], case[2], case[3], case[4]);
            if (descriptor) then
                described = described + 1;
            end
        end
        local entries = frames.since(mark);

        check(described == #cases - 2,
            "described " .. described .. " of " .. (#cases - 2) .. " bindable types");
        check(#entries == 0, "describing reached the game: "
            .. (entries[1] and (entries[1].kind .. " " .. tostring(entries[1].target)) or ""));
    end);

    return T;
end
