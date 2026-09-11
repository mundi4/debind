-- Smart Cast (`devdocs/adding-spec-resolved-actions.md` §10): the option on an action, the
-- branch buttons a rebuild stamps, and which of them a press picks.
--
-- The press is run through the DEBUG eval hook, the same text the click wrapper splices, and the
-- name it answers with is the button whose attributes the game would read. The living branches
-- go out to the insecure side through `CallMethod` and come back through an attribute on the
-- click frame, both of which `tests/restricted.lua` carries, so the whole round trip is here.
--
-- The shim's character is a druid: Balance by default, Restoration on index 4.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    --- The press is reached through the DEBUG eval hook, which the shipped shape does not carry
    --- (`eval_spec`); the checks that press a key stand down there and the rest still run.
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

    local GUID = "Player-1-TESTGUID";
    local interp;
    local seq = 0;

    --- A registered unit frame, so a mouse button has click-cast records at all. Registered before
    --- the first rebuild: the interpreter is stood up on everything recorded so far, and a
    --- registration after that would be in no window (`eval_spec`).
    local unitFrame = frames.newFrame("Button", nil, nil, "SecureUnitButtonTemplate");
    DebindPrivate.RegisterFrame(unitFrame, "group");
    unitFrame:SetAttribute("unit", "party1");

    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
        t.seq = seq;
        return t;
    end

    local function Bind(actions, options)
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
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

    local function record(key, index)
        local records = interp:recordsFor(key);
        check(records and records[index], key .. " has no record " .. index);
        return records[index];
    end

    local clickFrame = DebindPrivate.DefaultClickFrame;
    local function spellOn(button)
        -- **Through the real button**: a binding with a chosen target answers with the twin
        -- that turns automatic self-cast off, and the spell is on the one it clicks.
        return clickFrame:GetAttribute("*spell-" .. interp:actionButton(button));
    end

    local SPELLS = {
        [585] = "Renew", [50769] = "Revive", [212040] = "Revitalize", [20484] = "Rebirth",
        [2782] = "Remove Corruption", [88423] = "Nature's Cure", [1126] = "Mark of the Wild",
    };
    local function world()
        for id, name in pairs(SPELLS) do
            shim.world.spells[id] = { name = name };
        end
        shim.world.units.focus = { reaction = "help" };
    end

    ---------------------------------------------------------------------------
    -- The option
    ---------------------------------------------------------------------------

    test("off, the defaults, and chosen here", function()
        local off = DebindPrivate.SmartCastBranches({ type = Constants.SPELL, value = 585 });
        check(off == nil, "an action without the option has branches");

        local global = DebindPrivate.SmartCastBranches({ type = Constants.SPELL, value = 585, smartCast = "global" });
        check(global.rez == true and global.dispel == true and global.buff == true,
            "the defaults do not turn the three on");
        check(global.battleRez == false, "battle resurrection is on by default");

        local custom = DebindPrivate.SmartCastBranches({
            type = Constants.SPELL, value = 585, smartCast = "custom",
            smartCastRez = true, smartCastBattleRez = true,
        });
        check(custom.rez == true and custom.battleRez == true, "the chosen branches are off");
        check(custom.dispel == false and custom.buff == false, "an unchosen branch is on");

        local none = DebindPrivate.SmartCastBranches({ type = Constants.SPELL, value = 585, smartCast = "custom" });
        check(none == nil, "custom with nothing chosen has branches");

        local command = DebindPrivate.SmartCastBranches({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", smartCast = "global" });
        check(command == nil, "a command carries branches");

        local target = DebindPrivate.SmartCastBranches({ type = Constants.TARGET, value = "focus", smartCast = "global" });
        check(target == nil, "a target action carries branches");

        local switch = DebindPrivate.SmartCastBranches({ type = Constants.SETSTATE_TOGGLE, value = "$state1", smartCast = "global" });
        check(switch == nil, "a switch action carries branches");

        local pet = DebindPrivate.SmartCastBranches({ type = Constants.PETACTION, value = 1, smartCast = "global" });
        check(pet and pet.rez == true, "a pet action lost its branches");
    end);

    test("the account-wide default can be changed", function()
        Bind({});
        DebindPrivate.Options.smartCast = { battleRez = true, buff = false };
        local global = DebindPrivate.SmartCastBranches({ type = Constants.SPELL, value = 585, smartCast = "global" });
        check(global.battleRez == true and global.buff == false and global.rez == true,
            "the stored defaults were not read");
        DebindPrivate.Options.smartCast = nil;
    end);

    ---------------------------------------------------------------------------
    -- The buttons
    ---------------------------------------------------------------------------

    test("a rebuild stamps one button per branch this specialization can fill", function()
        world();
        shim.world.specIndex = 4;
        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "custom",
                smartCastRez = true, smartCastBattleRez = true, smartCastDispel = true, smartCastBuff = true }),
        });
        local smart = record("F1", 1).smart;
        check(smart, "the record carries no branch table");
        check(spellOn(smart.rez) == "Revive", "rez: " .. tostring(smart.rez and spellOn(smart.rez)));
        check(spellOn(smart.massRez) == "Revitalize", "mass rez: " .. tostring(smart.massRez));
        check(spellOn(smart.battleRez) == "Rebirth", "battle rez: " .. tostring(smart.battleRez));
        check(spellOn(smart.dispel) == "Nature's Cure", "dispel: " .. tostring(smart.dispel));
        check(spellOn(smart.buff) == "Mark of the Wild", "buff: " .. tostring(smart.buff));
        check(smart.buffSpell == 1126, "buff spell id: " .. tostring(smart.buffSpell));
        check(smart.dispelPet == nil, "a druid has an imp");

        -- Balance has no mass resurrection, and the branch is simply absent.
        shim.world.specIndex = 1;
        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "custom", smartCastRez = true }),
        });
        local balance = record("F1", 1).smart;
        check(balance.rez ~= nil and balance.massRez == nil, "balance has a mass resurrection");
        shim.world.specIndex = nil;
    end);

    -- The shim's character is a druid, which has a resurrection of its own and would never reach
    -- for the battle one, so the class that has only the battle resurrection (death knight,
    -- warlock) is stood up by swapping `Resolve` -- the way `specspells_spec` stands up the
    -- warlock, since `Constants.PLAYER_CLASS` is read once at load.
    test("the resurrection branch takes the battle one only where it was asked for", function()
        world();
        local SpecSpells = DebindPrivate.SpecSpells;
        local saved = SpecSpells.Resolve;
        SpecSpells.Resolve = function(out)
            out = saved(out);
            out.rez, out.massrez = nil, nil;
            return out;
        end

        local ok, err = pcall(function()
            Bind({
                action({ value = 585, key = "F1", unit = "focus", smartCast = "custom",
                    smartCastRez = true, smartCastRezWithBattleRez = true }),
            });
            local smart = record("F1", 1).smart;
            check(smart and smart.rez, "no resurrection branch was stamped");
            check(spellOn(smart.rez) == "Rebirth", "rez: " .. tostring(spellOn(smart.rez)));

            Bind({
                action({ value = 585, key = "F1", unit = "focus", smartCast = "custom",
                    smartCastRez = true }),
            });
            local without = record("F1", 1).smart;
            check(without == nil or without.rez == nil,
                "the resurrection branch was filled without the option");
        end);

        SpecSpells.Resolve = saved;
        if (not ok) then
            error(err, 0);
        end
    end);

    ---------------------------------------------------------------------------
    -- The press
    ---------------------------------------------------------------------------

    --- The button the press answers with, and what is on it.
    local function pressed(key)
        local _, button = interp:evalKey(key);
        check(button, key .. " picked nothing");
        return spellOn(button), button;
    end

    test("a dead friend gets the resurrection that fits", function()
        if (shipped) then
            return;
        end
        world();
        shim.world.specIndex = 4;
        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "custom",
                smartCastRez = true, smartCastBattleRez = true }),
        });

        shim.world.units.focus = { reaction = "help", dead = true };
        interp.state.combat = true;
        check(pressed("F1") == "Rebirth", "in combat: " .. tostring(pressed("F1")));

        interp.state.combat = false;
        shim.world.units.focus.inParty = true;
        check(pressed("F1") == "Revitalize", "grouped, out of combat: " .. tostring(pressed("F1")));

        shim.world.units.focus.inParty = nil;
        check(pressed("F1") == "Revive", "ungrouped, out of combat: " .. tostring(pressed("F1")));

        -- With only the battle resurrection chosen, out of combat nothing fits and the host fires.
        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "custom", smartCastBattleRez = true }),
        });
        check(pressed("F1") == "Renew", "the host did not fire: " .. tostring(pressed("F1")));
        shim.world.specIndex = nil;
    end);

    test("a living friend is dispelled or buffed out of combat, else the host fires", function()
        if (shipped) then
            return;
        end
        world();
        shim.world.specIndex = 4;
        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "global" }),
        });
        shim.world.units.focus = { reaction = "help" };
        interp.state.combat = false;

        -- Nothing on the unit at all: the raid buff is what is missing.
        shim.world.auras.focus = {};
        check(pressed("F1") == "Mark of the Wild", "nothing on the unit: " .. tostring(pressed("F1")));
        -- Bit 2 on: the buff is missing. Bit 1 off: nothing to dispel.
        check(clickFrame:GetAttribute("debind-aura") == 2,
            "the answer was not written: " .. tostring(clickFrame:GetAttribute("debind-aura")));

        shim.world.auras.focus = { { name = "Mark of the Wild", harmful = false } };
        check(pressed("F1") == "Renew", "buffed already: " .. tostring(pressed("F1")));
        check(clickFrame:GetAttribute("debind-aura") == 0,
            "the answer for a buffed unit: " .. tostring(clickFrame:GetAttribute("debind-aura")));

        shim.world.auras.focus = { { name = "Curse", harmful = true, dispellable = true } };
        check(pressed("F1") == "Nature's Cure", "dispellable: " .. tostring(pressed("F1")));

        shim.world.auras.focus = { { name = "Bleed", harmful = true, dispellable = false } };
        check(pressed("F1") == "Mark of the Wild", "not dispellable, buff missing: " .. tostring(pressed("F1")));

        -- Dispel ahead of buff where both apply.
        shim.world.auras.focus = { { name = "Curse", harmful = true, dispellable = true } };
        check(pressed("F1") == "Nature's Cure", "dispel did not come first: " .. tostring(pressed("F1")));

        -- In combat neither branch is asked and the host fires.
        interp.state.combat = true;
        clickFrame:SetAttribute("debind-aura", 3);
        check(pressed("F1") == "Renew", "in combat: " .. tostring(pressed("F1")));

        -- A hostile unit is nobody's business here.
        interp.state.combat = false;
        shim.world.units.focus = { reaction = "harm" };
        check(pressed("F1") == "Renew", "hostile: " .. tostring(pressed("F1")));
        shim.world.specIndex = nil;
        shim.world.auras.focus = nil;
    end);

    -- A unit-frame click hands its own click-cast record to the key-side wrapper as the winner, so
    -- that record has to carry the branches too. Here the hover twin on a mouse button is the
    -- click-cast record.
    test("a click-cast record carries the branches", function()
        world();
        Bind({
            action({ value = 585, key = "BUTTON3", preferHoverUnit = true, smartCast = "global" }),
        });
        -- A mouse button's list is filed under `ClickCastKeys[button][modifier]` rather than under
        -- a click-time button name.
        local records = interp.env.ClickCastKeys[3] and interp.env.ClickCastKeys[3][0];
        check(records and #records == 2, "BUTTON3 records: " .. tostring(records and #records));
        -- A false axis is left off the record, so "not holding the key" is the field being absent.
        check(records[1].isClickCast and not records[1].holdsKey,
            "the first record is not the click-cast twin");
        check(records[1].smart ~= nil, "the click-cast record carries no branches");
        check(records[2].holdsKey and records[2].smart ~= nil, "the key record carries no branches");
    end);

    test("a type outside the allow list keeps the option off the record", function()
        world();
        Bind({
            action({ type = Constants.TARGET, key = "F1", unit = "focus", smartCast = "global" }),
        });
        -- A druid resolves rez, dispel and buff, so the branches would stand here if the type
        -- were allowed to carry them (`Constants.TYPES_WITH_SMART_CAST`).
        check(record("F1", 1).smart == nil, "a target action carries branches");
    end);


    test("the account-wide master switch ignores every action's option", function()
        world();
        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "global" }),
        });
        check(record("F1", 1).smart ~= nil, "the record has no branches to begin with");

        local OFF = { smartCast = { enabled = false } };
        DebindPrivate.Options.smartCast = OFF.smartCast;
        check(DebindPrivate.SmartCastBranches({ type = Constants.SPELL, value = 585, smartCast = "global" }) == nil,
            "an action following the defaults kept its branches");
        check(DebindPrivate.SmartCastBranches({
            type = Constants.SPELL, value = 585, smartCast = "custom", smartCastRez = true,
        }) == nil, "an action that chose its own kept its branches");

        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "custom", smartCastRez = true }),
        }, OFF);
        check(record("F1", 1).smart == nil, "the record still carries a branch table");

        -- Off is not cleared: the action's own values are still there when the switch comes back.
        Bind({
            action({ value = 585, key = "F1", unit = "focus", smartCast = "custom", smartCastRez = true }),
        });
        local back = record("F1", 1).smart;
        check(back and back.rez ~= nil, "the branches did not come back");
    end);

    return T;
end
