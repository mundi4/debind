-- The Resurrect type (`adding-spec-resolved-actions.md` §6): one action, and a binding per branch
-- spell derived from it, each asking `known` about its own spell and carrying the conditions that
-- pick it. Which branch a press reaches is asked by what fires, never by a record index: a
-- binding that holds the key covers everything behind it and the solver drops those.
--
-- The shim's character is a druid, which has all three branches in Restoration. The other
-- classes are stood up by handing `SpecSpells.ResurrectSpells` their answer, since
-- `Constants.PLAYER_CLASS` is read once at load.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local shipped = ctx and ctx.shipped;
    local frames = require("wow_frames");
    local restricted = require("restricted");

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

    -- Every case here presses a key, which goes through the DEBUG eval hook.
    if (shipped) then
        return T;
    end

    local GUID = "Player-1-TESTGUID";
    local interp;
    local seq = 0;

    -- Registered before the first rebuild, the way `eval_spec` does it: the interpreter is stood up
    -- on what was recorded before it existed.
    local unitFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(unitFrame, "group");
    unitFrame:SetAttribute("unit", "party1");

    local function action(t)
        seq = seq + 1;
        t.seq = seq;
        return t;
    end

    local function Bind(actions)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [GUID] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();

        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");

        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
        return interp;
    end

    --- The spell the winning record casts, `false` for one that holds the key and casts nothing,
    --- nil for no record at all.
    local function fired(key)
        local index, _, record = interp:evalKey(key);
        if (not index) then
            return nil;
        end
        return record.spell or false;
    end

    local REVIVE, REVITALIZE, REBIRTH = 50769, 212040, 20484;
    local REGROWTH = 8936;

    --- Restoration, with every branch in the book so `known` answers yes through it.
    local function druidWorld()
        shim.world.specIndex = 4;
        shim.world.spells[REVIVE] = { name = "Revive" };
        shim.world.spells[REVITALIZE] = { name = "Revitalize" };
        shim.world.spells[REBIRTH] = { name = "Rebirth" };
        shim.world.spells[REGROWTH] = { name = "Regrowth" };
        shim.world.spellbook[REVIVE] = true;
        shim.world.spellbook[REVITALIZE] = true;
        shim.world.spellbook[REBIRTH] = true;
    end

    local function reset()
        shim.world.units = {};
        shim.world.specIndex = nil;
        shim.world.spellbook[REVIVE] = nil;
        shim.world.spellbook[REVITALIZE] = nil;
        shim.world.spellbook[REBIRTH] = nil;
        if (interp) then
            interp:resetState();
        end
    end

    --- Another class's answer, for the length of `fn`.
    local function withSpells(spells, fn)
        local SpecSpells = DebindPrivate.SpecSpells;
        local saved = SpecSpells.ResurrectSpells;
        SpecSpells.ResurrectSpells = function()
            return spells;
        end
        local ok, err = pcall(fn);
        SpecSpells.ResurrectSpells = saved;
        if (not ok) then
            error(err, 0);
        end
    end

    local DEAD_FRIEND = { id = "friend", reaction = "help", dead = true };
    local DEAD_MATE = { id = "mate", reaction = "help", dead = true, inParty = true };
    local LIVE_FRIEND = { id = "friend", reaction = "help" };

    local function inCombat(on)
        interp.state.combat = on;
    end

    test("each branch fires where its conditions put it", function()
        druidWorld();
        Bind({ action({ type = Constants.RESURRECT, key = "F1" }) });

        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == "Revive", "a dead friend out of combat: " .. tostring(fired("F1")));

        shim.world.units = { target = DEAD_MATE };
        check(fired("F1") == "Revitalize", "a dead party member: " .. tostring(fired("F1")));

        inCombat(true);
        check(fired("F1") == "Rebirth", "a dead party member in combat: " .. tostring(fired("F1")));
        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == "Rebirth", "a dead friend in combat: " .. tostring(fired("F1")));
        inCombat(false);

        shim.world.units = {};
        check(fired("F1") == "Revitalize", "no target: " .. tostring(fired("F1")));
        reset();
    end);

    -- The key is held where nothing applies, which is §4 of the design.
    test("a living target holds the key and casts nothing", function()
        druidWorld();
        Bind({
            action({ type = Constants.RESURRECT, key = "F1" }),
            action({ type = Constants.SPELL, key = "F1", value = REGROWTH }),
        });
        shim.world.units = { target = LIVE_FRIEND };
        check(fired("F1") == false, "a living friend: " .. tostring(fired("F1")));

        -- A resurrection cannot be cast in combat but Rebirth, so a dead friend in combat with no
        -- battle resurrection known is held too.
        shim.world.spellbook[REBIRTH] = nil;
        shim.world.units = { target = DEAD_FRIEND };
        inCombat(true);
        check(fired("F1") == false, "in combat with no Rebirth: " .. tostring(fired("F1")));
        reset();
    end);

    test("skipping hands the key on where nothing applies", function()
        druidWorld();
        Bind({
            action({ type = Constants.RESURRECT, key = "F1", skipWhenUnusable = true }),
            action({ type = Constants.SPELL, key = "F1", value = REGROWTH }),
        });
        shim.world.units = { target = LIVE_FRIEND };
        check(fired("F1") == "Regrowth", "a living friend: " .. tostring(fired("F1")));
        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == "Revive", "a dead friend: " .. tostring(fired("F1")));
        reset();
    end);

    -- A branch not known is passed over for the next one, which is how "Revive if there is no
    -- Revitalize" is written without a `noknown`.
    test("a branch not known gives way to the next", function()
        druidWorld();
        shim.world.spellbook[REVITALIZE] = nil;
        Bind({ action({ type = Constants.RESURRECT, key = "F1" }) });
        shim.world.units = { target = DEAD_MATE };
        check(fired("F1") == "Revive", "a dead party member: " .. tostring(fired("F1")));
        shim.world.units = {};
        check(fired("F1") == false, "no target: " .. tostring(fired("F1")));
        reset();
    end);

    test("turning the no-target mass resurrection off holds the key", function()
        druidWorld();
        Bind({ action({ type = Constants.RESURRECT, key = "F1", noTargetMassRez = false }) });
        shim.world.units = {};
        check(fired("F1") == false, "no target: " .. tostring(fired("F1")));
        shim.world.units = { target = DEAD_MATE };
        check(fired("F1") == "Revitalize", "a dead party member: " .. tostring(fired("F1")));
        reset();
    end);

    -- **A condition the reader puts on the target narrows every branch.** [Friendly] needs a
    -- target, so the no-target branch cannot match, and a press with none is not this action's.
    test("a friendly condition takes the no-target branch away", function()
        druidWorld();
        Bind({
            action({ type = Constants.RESURRECT, key = "F1",
                conditions = { units = { ["@"] = { exists = true, reaction = Constants.REACTION_HELP } } } }),
            action({ type = Constants.SPELL, key = "F1", value = REGROWTH }),
        });
        shim.world.units = {};
        check(fired("F1") == "Regrowth", "no target: " .. tostring(fired("F1")));
        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == "Revive", "a dead friend: " .. tostring(fired("F1")));
        reset();
    end);

    local RAISE_ALLY, SOULSTONE = 61999, 20707;

    test("a class with no resurrection uses its battle resurrection out of combat only when allowed",
        function()
            shim.world.spells[RAISE_ALLY] = { name = "Raise Ally" };
            shim.world.spellbook[RAISE_ALLY] = true;
            withSpells({ battle = RAISE_ALLY }, function()
                Bind({ action({ type = Constants.RESURRECT, key = "F1" }) });
                shim.world.units = { target = DEAD_FRIEND };
                check(fired("F1") == false, "off, out of combat: " .. tostring(fired("F1")));
                inCombat(true);
                check(fired("F1") == "Raise Ally", "off, in combat: " .. tostring(fired("F1")));
                inCombat(false);

                Bind({ action({ type = Constants.RESURRECT, key = "F1", battleRezOutOfCombat = true }) });
                shim.world.units = { target = DEAD_FRIEND };
                check(fired("F1") == "Raise Ally", "on, out of combat: " .. tostring(fired("F1")));
            end);
            shim.world.spellbook[RAISE_ALLY] = nil;
            reset();
        end);

    -- **"No other resurrection" is what you have, not what the class has** (2026-09-23, owner). A
    -- class with Revive keeps using it out of combat whatever the switch says, and falls back to
    -- its battle resurrection only while Revive is not known, the way a low level character is.
    test("the out-of-combat battle resurrection stands in only for a single one not known", function()
        druidWorld();
        shim.world.specIndex = 1;
        Bind({ action({ type = Constants.RESURRECT, key = "F1", battleRezOutOfCombat = true }) });
        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == "Revive", "Revive known: " .. tostring(fired("F1")));

        shim.world.spellbook[REVIVE] = nil;
        check(fired("F1") == "Rebirth", "Revive not known: " .. tostring(fired("F1")));

        Bind({ action({ type = Constants.RESURRECT, key = "F1" }) });
        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == false, "switch off, Revive not known: " .. tostring(fired("F1")));
        reset();
    end);

    -- **Soulstone is a resurrection here and nothing else** (2026-09-23, owner). On a living friend
    -- the key is held and nothing goes out; a plain Soulstone action does that job.
    test("a warlock's resurrection puts no Soulstone on a living friend", function()
        shim.world.spells[SOULSTONE] = { name = "Soulstone" };
        shim.world.spellbook[SOULSTONE] = true;
        withSpells({ battle = SOULSTONE }, function()
            Bind({ action({ type = Constants.RESURRECT, key = "F1" }) });
            shim.world.units = { target = LIVE_FRIEND };
            check(fired("F1") == false, "a living friend: " .. tostring(fired("F1")));
            shim.world.units = { target = DEAD_FRIEND };
            inCombat(true);
            check(fired("F1") == "Soulstone", "a dead friend in combat: " .. tostring(fired("F1")));
        end);
        shim.world.spellbook[SOULSTONE] = nil;
        reset();
    end);

    -- **No self tier aimed at you.** Nobody resurrects themselves, so a held self cast key reaches
    -- nothing of this action and the tier's own block takes the press.
    test("a held self cast key resurrects nobody", function()
        druidWorld();
        Bind({ action({ type = Constants.RESURRECT, key = "F1" }) });
        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == "Revive", "no key held: " .. tostring(fired("F1")));
        interp.state.modifiedClick.SELFCAST = true;
        check(not fired("F1"), "the self cast key cast " .. tostring(fired("F1")));
        reset();
    end);

    -- **An original that never reaches the key is not one that stands.** With the key handed on
    -- it is `omitted`, and unticked it only holds; a target the reader requires alive leaves no
    -- branch able to cast, and that has to be said on the row.
    test("every branch ruled out by the reader's own target row is an issue", function()
        druidWorld();
        for _, extra in ipairs({ { skipWhenUnusable = true }, {} }) do
            local a = { type = Constants.RESURRECT, key = "F1", seq = 1, unit = "target",
                conditions = { units = { target = { exists = true, dead = false } } } };
            for k, v in pairs(extra) do
                a[k] = v;
            end
            Bind({ a });
            check(DebindPrivate.GetBindingIssue(a) == Constants.BINDING_ISSUE_CONDITIONS_NEVER,
                "no issue, skip " .. tostring(a.skipWhenUnusable) .. ": "
                .. tostring(DebindPrivate.GetBindingIssue(a)));
        end
        reset();
    end);

    -- **"Every press is off" is about the reader's switches**, not about which tiers a resurrection
    -- has use for. With the Self Cast Key row left on, it is not every press.
    test("a resurrection with only the self cast key on is not every press off", function()
        druidWorld();
        local a = { type = Constants.RESURRECT, key = "F1", seq = 1,
            casting = { normalCast = false, focusCastKey = "skip" } };
        Bind({ a });
        check(DebindPrivate.GetBindingIssue(a) ~= Constants.BINDING_ISSUE_NOTHING_RUNS,
            "reported every press off");
        reset();
    end);

    -- **Every branch that aims at someone asks for a friend**, the battle one included
    -- (2026-09-23, owner): a dead enemy still targeted in combat is not somebody to raise.
    test("a dead enemy in combat is not resurrected", function()
        druidWorld();
        Bind({ action({ type = Constants.RESURRECT, key = "F1" }) });
        shim.world.units = { target = { id = "enemy", reaction = "harm", dead = true } };
        inCombat(true);
        check(fired("F1") == false, "a dead enemy in combat: " .. tostring(fired("F1")));
        shim.world.units = { target = DEAD_FRIEND };
        check(fired("F1") == "Rebirth", "a dead friend in combat: " .. tostring(fired("F1")));
        reset();
    end);

    -- **A branch the reader's own conditions rule out still stands as one that cannot**, so the
    -- row can say so. Dropped, a target required alive left only the original holding the key and
    -- no mark anywhere.
    test("a target required alive is an issue", function()
        druidWorld();
        local a = { type = Constants.RESURRECT, key = "F1", seq = 1,
            conditions = { units = { ["@"] = { exists = true, dead = false } } } };
        Bind({ a });
        check(DebindPrivate.GetBindingIssue(a) == Constants.BINDING_ISSUE_CONDITIONS_NEVER,
            "no issue: " .. tostring(DebindPrivate.GetBindingIssue(a)));
        reset();
    end);

    test("in combat with no battle resurrection is an issue", function()
        shim.world.spells[REVIVE] = { name = "Revive" };
        withSpells({ single = REVIVE }, function()
            local a = { type = Constants.RESURRECT, key = "F1", seq = 1,
                conditions = { combat = true } };
            Bind({ a });
            check(DebindPrivate.GetBindingIssue(a) == Constants.BINDING_ISSUE_CONDITIONS_NEVER,
                "no issue: " .. tostring(DebindPrivate.GetBindingIssue(a)));
        end);
        reset();
    end);

    -- **The self tier is only dropped where it aims at you.** An action with a unit picked keeps
    -- its twins aimed at that unit (`ActionHasPickedUnit`), so a held self cast key resurrects it.
    test("a picked unit is resurrected with the self cast key held", function()
        druidWorld();
        Bind({ action({ type = Constants.RESURRECT, key = "F1", unit = "party1" }) });
        shim.world.units = { party1 = DEAD_FRIEND };
        interp.state.modifiedClick.SELFCAST = true;
        check(fired("F1") == "Revive", "the self cast key: " .. tostring(fired("F1")));
        reset();
    end);

    --- The hover twins of the no-target branch, counted off the derived list.
    local function hoverNoTarget(casting)
        local a = action({ type = Constants.RESURRECT, key = "F1", casting = casting });
        local list = DebindPrivate.GetBindingsForAction(a);
        local standing, dead = 0, 0;
        for i = 1, #list do
            local b = list[i];
            local at = b.conditions and b.conditions.units and b.conditions.units["@"];
            if (b.hoverTwin and at == false and b.spellToCast) then
                if (b.dead) then
                    dead = dead + 1;
                else
                    standing = standing + 1;
                end
            end
        end
        return standing, dead;
    end

    -- **Aimed at the pointed unit, the hover tier cannot hold "no target"**, so that branch is not
    -- built there. Cast as usual aims the twin at the target instead, and there it can.
    test("the no-target branch is built in the hover tier only where it can stand", function()
        druidWorld();
        local standing, dead = hoverNoTarget({ hoverCast = "cast" });
        check(standing == 0 and dead == 0,
            "pointed: " .. standing .. " standing, " .. dead .. " dead");
        standing, dead = hoverNoTarget({ hoverCast = "usual" });
        check(standing == 1 and dead == 0,
            "as usual: " .. standing .. " standing, " .. dead .. " dead");
        reset();
    end);

    -- The menu offers the switches on this type alone, so a stored one anywhere else is taken off.
    test("the resurrection switches are kept on a resurrection and taken off a spell", function()
        local rez = { type = Constants.RESURRECT, key = "F1", seq = 1, noTargetMassRez = false,
            battleRezOutOfCombat = true };
        local spell = { type = Constants.SPELL, value = REGROWTH, key = "F2", seq = 1,
            noTargetMassRez = false, battleRezOutOfCombat = true };
        Bind({ rez, spell });
        DebindPrivate.CleanUpDB();
        check(rez.noTargetMassRez == false and rez.battleRezOutOfCombat,
            "taken off the resurrection");
        check(spell.noTargetMassRez == nil and spell.battleRezOutOfCombat == nil,
            "left on the spell");
        reset();
    end);

    return T;
end
