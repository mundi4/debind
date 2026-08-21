-- The profile the emission golden is taken against, and the client facts it needs.
--
-- **One fixture, held apart from the spec that uses it.** The golden is a net for a refactor
-- (`devdocs/legacy/going-headless-outside-the-ui.md` §6): what it is worth is decided entirely by how
-- much of `UpdateBindings.lua` this profile drives, so the profile is the thing to read and to
-- add to, and burying it inside the comparison would hide that.
--
-- **Every entry earns its place by reaching a branch.** A second spell binding that differs only
-- in id costs a golden that is longer to read and catches nothing the first one does not.
--
-- The shim's world is a druid on specialization 1 (`wow_shim.lua`), so the class layer here is
-- `DRUID` and the character layers are that character's.

return function(DebindPrivate, shim)
    local Constants = DebindPrivate.Constants;
    local M = {};

    local GUID = "Player-1-TESTGUID";

    --- What the client is asked about while the rebuild runs. All of it is a query returning a
    --- value, so it is mocked rather than pushed out (§4) -- but the answers are written here
    --- rather than defaulted in the shim, because both branches of "did the name resolve" are
    --- paths `SetBindingAttributes` takes and a spec has to be able to stand in either.
    function M.installWorld()
        local world = shim.world;

        --- Resolves to a name, so the click frame gets `*spell-<button>` as a **name**.
        world.spells[585] = { name = "Renew", iconID = 135953 };
        --- Carries a subtext, which is appended in brackets. Two spells share a name across
        --- specializations and the subtext is what tells them apart.
        world.spells[8936] = { name = "Regrowth", iconID = 136085, subtext = "Restoration" };
        --- Press and hold. The only thing that bakes `*typerelease-` and `pressAndHold`.
        world.spells[271466] = { name = "Will of the Necropolis", pressAndHold = true };
        --- An override pointing back at a base id. `FindBaseSpellByID` answers with the base and
        --- the name that goes out is the base's, not the one the profile stored.
        world.spells[774] = { name = "Rejuvenation", iconID = 136081 };
        world.baseSpells[155777] = 774;
        --- **Deliberately absent from `spells`.** The name does not resolve, so the attribute goes
        --- out carrying the id instead -- the other half of that fork.
        --- (id 5176)

        --- A mount whose journal entry names a spell: it goes out as a spell.
        world.mounts[6] = { name = "Brown Horse", spellID = 458 };
        world.spells[458] = { name = "Brown Horse", iconID = 132261 };
        --- A mount with no spell id: it goes out as generated macro text instead.
        world.mounts[7] = { name = "Summoned Horse" };

        --- A flyout with slots in it. Flyout 900 is **not** here, and that absence is the point:
        --- `GetFlyoutOpener` answers nil for it and the binding is dropped for want of a way to
        --- fire at all.
        world.flyouts[66] = { name = "Call Pet", slots = { 883, 83242 } };
        world.spells[883] = { name = "Call Pet 1" };
        world.spells[83242] = { name = "Call Pet 2" };
    end

    --- `InitDB` reads exactly this shape. `switches` is account-wide and sits beside `shared`.
    function M.profile()
        return {
            dbver = Constants.DB_VERSION,
            shared = {
                GENERAL = M.generalLayer(),
                classes = { DRUID = { [0] = M.classLayer() } },
            },
            characters = { [GUID] = { layers = { [1] = M.characterLayer() }, switches = {} } },
            migrated = {},
            switches = {
                --- Manual: its stored value is put back into `States` at every rebuild.
                ["$burst"] = { mode = Constants.SWITCH_MODES.MANUAL, resetValue = true },
                --- Computed: emits a `SwitchExpressions` entry and a line in the state loop.
                ["$intent"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[combat,nostealth]" },
                --- Computed **from a macro conditional the parser can read**, which is the branch
                --- that turns the expression into a macro text binding instead of a fixed string.
                ["$echo"] = { mode = Constants.SWITCH_MODES.EXPR, expr = "[@$burst][$burst]" },
            },
        };
    end

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.seq = seq;
        return t;
    end

    ---------------------------------------------------------------------------
    -- The account layer
    ---------------------------------------------------------------------------

    function M.generalLayer()
        return {
            --- **One unconditional action on a key.** Nothing can take the key away, so this is
            --- the `alwaysOurs` shape: bound once here and never walked by the state loop.
            action({ type = Constants.SPELL, value = 585, key = "F1" }),

            --- **Three actions on one key, and the axes do not cover the space.** The key is
            --- state-driven: whether we hold it at all depends on what is measured.
            action({ type = Constants.SPELL, value = 8936, key = "F2",
                conditions = { combat = true } }),
            action({ type = Constants.ITEM, value = 6948, key = "F2",
                conditions = { stealth = true } }),
            action({ type = Constants.MACRO, value = "Trinkets", key = "F2",
                conditions = { groups = Constants.GROUP_PARTY } }),

            --- **Two axes covering their space between them**, which is the other way a key comes
            --- out `alwaysOurs` -- no unconditional action anywhere on it.
            action({ type = Constants.SPELL, value = 774, key = "F3",
                conditions = { petbattle = true } }),
            action({ type = Constants.SPELL, value = 155777, key = "F3",
                conditions = { petbattle = false } }),

            --- Macro text carrying both kinds of argument: a unit alias the parser rewrites, and
            --- a switch reference.
            action({ type = Constants.MACROTEXT, key = "F4",
                value = "/cast [@tank,$burst] Swiftmend\n/cast [no$intent] Rejuvenation" }),

            --- The three switch verbs. Each stamps an attribute naming the switch and a mode.
            action({ type = Constants.SETSTATE_TOGGLE, value = "$burst", key = "F5" }),
            action({ type = Constants.SETSTATE_ON, value = "$intent", key = "F6" }),
            action({ type = Constants.SETSTATE_OFF, value = "$echo", key = "F7" }),

            --- The types that carry no value at all, and the two that leave the click frame alone
            --- entirely -- a command binds itself and `unused` clears the key.
            action({ type = Constants.TARGET, value = nil, key = "F8", unit = "focus" }),
            action({ type = Constants.TOGGLEMENU, value = nil, key = "F9", unit = "player" }),
            action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "F10" }),
            action({ type = Constants.WORLDMARKER, value = 3, key = "F11" }),

            --- Both mount forks: one that resolves to a spell, one that falls through to
            --- generated macro text.
            action({ type = Constants.MOUNT, value = 6, key = "F12" }),
            action({ type = Constants.MOUNT, value = 7, key = "SHIFT-F12" }),
        };
    end

    ---------------------------------------------------------------------------
    -- The class layer
    ---------------------------------------------------------------------------

    function M.classLayer()
        return {
            --- Every remaining condition axis, one key each, so a change to one axis moves one
            --- block of the golden rather than all of them.
            action({ type = Constants.SPELL, value = 585, key = "CTRL-F1",
                conditions = { forms = 3 } }),
            action({ type = Constants.SPELL, value = 585, key = "CTRL-F2",
                conditions = { bonusbars = 5 } }),
            action({ type = Constants.SPELL, value = 585, key = "CTRL-F3",
                conditions = { specialbar = true } }),
            action({ type = Constants.SPELL, value = 585, key = "CTRL-F4",
                conditions = { extrabar = true } }),
            action({ type = Constants.SPELL, value = 585, key = "CTRL-F5",
                conditions = { pet = true } }),
            --- `known` bakes the whole macro conditional, brackets and all, and the value it names
            --- is the action's own.
            action({ type = Constants.SPELL, value = 8936, key = "CTRL-F6",
                conditions = { known = true } }),
            --- A switch as a condition rather than as a target.
            action({ type = Constants.SPELL, value = 585, key = "CTRL-F7",
                conditions = { ["$burst"] = true } }),

            --- **The unit axes.** `units` is where reaction and life live, and `"@"` means the
            --- action's own target -- the one key that has to be merged with an explicit condition
            --- on the same unit before anything is emitted.
            action({ type = Constants.SPELL, value = 585, key = "CTRL-F8", unit = "target",
                conditions = { units = { ["@"] = { reaction = Constants.REACTION_HELP } } } }),
            action({ type = Constants.SPELL, value = 8936, key = "CTRL-F9", unit = "target",
                conditions = { units = {
                    ["@"] = { reaction = Constants.REACTION_HELP + Constants.REACTION_OTHER },
                    target = { dead = false },
                } } }),
            --- A unit that has to exist, and one that has to be absent.
            action({ type = Constants.SPELL, value = 774, key = "CTRL-F10",
                conditions = { units = { focus = { reaction = Constants.REACTION_HARM } } } }),
            action({ type = Constants.SPELL, value = 774, key = "CTRL-F11",
                conditions = { units = { pet = false } } }),
            --- A role unit. Registering it is what turns the unit watch on.
            action({ type = Constants.SPELL, value = 8936, key = "CTRL-F12", unit = "healer" }),
        };
    end

    ---------------------------------------------------------------------------
    -- The character layer, on the specialization the shim is in
    ---------------------------------------------------------------------------

    function M.characterLayer()
        return {
            --- **Hover, three ways.** What makes a binding a hover binding is the condition
            --- `units.hover`, not the target -- `DeriveHoverFields` reads that one key and
            --- nothing else -- so each of these carries one.
            ---
            --- A keyboard key with a hover condition still holds the key: click-casting needs a
            --- mouse button to arrive on.
            action({ type = Constants.SPELL, value = 8936, key = "ALT-F1", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HELP } } } }),
            --- A frame type condition, which is the only thing that makes the hover **frame**
            --- worth re-deciding on: it sets `RebindOnHoverFrame` and the `unitframe` flag.
            action({ type = Constants.SPELL, value = 774, key = "ALT-F2", unit = "hover",
                conditions = {
                    frameTypes = Constants.FRAMETYPE_GROUP,
                    units = { hover = { reaction = Constants.REACTION_ALL } },
                } }),
            --- On a mouse button, the same condition makes the record click-cast instead: it
            --- arrives through the unit frame and holds no key.
            action({ type = Constants.SPELL, value = 585, key = "SHIFT-BUTTON2", unit = "hover",
                conditions = { units = { hover = { reaction = Constants.REACTION_HARM } } } }),
            --- Beside it on the same button, a record that holds the key rather than
            --- click-casting. The two are registered in different tables, which is the point of
            --- having them on one key.
            action({ type = Constants.SPELL, value = 8936, key = "SHIFT-BUTTON2" }),

            --- Press and hold, which is the only action that bakes `*typerelease-`.
            action({ type = Constants.SPELL, value = 271466, key = "ALT-F3" }),

            --- A spell whose name does not resolve: the attribute carries the id instead.
            action({ type = Constants.SPELL, value = 5176, key = "ALT-F4" }),

            --- **Unused, under a conditional action.** It takes the key back when the one above it
            --- does not match, which is the shape `unused` exists for.
            action({ type = Constants.SPELL, value = 585, key = "ALT-F5",
                conditions = { combat = true } }),
            action({ type = Constants.UNUSED, key = "ALT-F5" }),

            --- **The two ways a binding is dropped for having no way to fire**, which is the one
            --- outcome `SetBindingAttributes` reports through a DEBUG log line and nothing else.
            --- A flyout nothing learned, and a pet command with no slash command behind it.
            ---
            --- **Each is under a conditional action on the same key**, because the fault the drop
            --- exists to prevent is not the dropped binding going missing -- it is the whole key
            --- being taken and everything below it on that key going with it.
            action({ type = Constants.SPELL, value = 585, key = "ALT-F8",
                conditions = { combat = true } }),
            action({ type = Constants.FLYOUT, value = 900, key = "ALT-F8" }),
            action({ type = Constants.SPELL, value = 585, key = "ALT-F9",
                conditions = { combat = true } }),
            action({ type = Constants.PETACTION, value = "PETNOSUCHCOMMAND", key = "ALT-F9",
                unit = "target" }),

            --- And the two working forks beside them: a flyout that has slots, and a pet command
            --- that has a slash command. A pet command is turned into macro text carrying its
            --- target, which is why the target does not go out as a unit.
            action({ type = Constants.FLYOUT, value = 66, key = "ALT-F10" }),
            action({ type = Constants.PETACTION, value = "PETATTACK", key = "ALT-F11",
                unit = "target" }),

            --- A custom target, which is set by an action rather than measured.
            action({ type = Constants.SETCUSTOM, value = 1, key = "ALT-F6" }),
            --- ...and a binding that reads it back as a unit.
            action({ type = Constants.SPELL, value = 585, key = "ALT-F7", unit = "custom1" }),
        };
    end

    --- Stands the profile up and hands the addon a world to ask about. Returns nothing: everything
    --- it did is in `DebindPrivate.db` and the shim's globals.
    function M.install()
        M.installWorld();
        _G.DebindVars = M.profile();
        DebindPrivate.InitDB();
    end

    return M;
end
