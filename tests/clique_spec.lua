-- **A Clique profile turned into a payload** (`importing-clique-profiles.md` §6, one row a test).
--
-- The binding tables are Clique 5.0.14's shape (`.zzz/clique-savedvars.md`), and the first profile
-- below is a real one: the two bindings every new profile starts with, and one spell.

return function(DebindPrivate, DebindStorage)
    local Constants = DebindPrivate.Constants;

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

    local function Convert(bindings)
        local payload, count = DebindStorage.PayloadFromCliqueBindings(bindings);
        local actions = payload.shared.GENERAL;
        check(#actions == count, "count " .. tostring(count) .. " for " .. #actions .. " actions");
        return actions, payload;
    end

    --- The one action a binding list converts to.
    local function One(binding)
        local actions = Convert({ binding });
        check(#actions == 1, #actions .. " actions");
        return actions[1];
    end

    local function None(binding)
        local actions = Convert({ binding });
        check(#actions == 0, #actions .. " actions, expected none");
    end

    local function Spell(key, sets)
        return { type = "spell", spell = "Rejuvenation", key = key, sets = sets };
    end

    test("a new profile's two bindings are dropped and the spell stays", function()
        local actions = Convert({
            { sets = { default = true }, type = "target", key = "BUTTON1", unit = "mouseover" },
            { type = "menu", key = "BUTTON2", sets = { default = true } },
            { spell = "Mark of the Wild", key = "BUTTON3", sets = { default = true }, icon = 136078,
                type = "spell" },
        });
        check(#actions == 1, #actions .. " actions");
        local action = actions[1];
        check(action.type == Constants.SPELL and action.value == "Mark of the Wild",
            tostring(action.type) .. " / " .. tostring(action.value));
        check(action.key == "BUTTON3", "key " .. tostring(action.key));
        check(action.icon == nil, "a spell keeps no icon of its own");
        check(action.unit == nil, "the binding's unit is not read");
    end);

    test("the starting bindings stay once they carry anything else", function()
        local action = One({ type = "target", key = "BUTTON1", sets = { default = true, ooc = true } });
        check(action.type == Constants.TARGET, tostring(action.type));
    end);

    test("the frames are Hover Cast only, hovercast too, and global is the press beside them", function()
        local frames = One(Spell("F", { default = true }));
        check(frames.casting and frames.casting.hoverCast == "cast" and frames.casting.normalCast == false,
            "frames");
        check(frames.casting.hoverCastMode == nil, "no mode of its own");

        local hover = One(Spell("F", { hovercast = true }));
        check(hover.casting and hover.casting.hoverCast == "cast" and hover.casting.normalCast == false,
            "hovercast");

        local both = One(Spell("F", { default = true, global = true }));
        check(both.casting and both.casting.hoverCast == "cast" and both.casting.normalCast == nil,
            "frames and global");

        local global = One(Spell("F", { global = true }));
        check(global.casting == nil, "global alone is a plain key");
    end);

    -- `shouldApply`: any set but `global` and `hovercast` puts a binding on the frames.
    test("a set on its own puts the binding on the frames", function()
        local action = One(Spell("F", { friend = true }));
        check(action.casting and action.casting.hoverCast == "cast" and action.casting.normalCast == false,
            "friend alone");
    end);

    test("a binding with no sets reads as the frames", function()
        local action = One({ type = "spell", spell = "Rejuvenation", key = "F" });
        check(action.casting and action.casting.hoverCast == "cast", "no sets");
    end);

    test("the modifiers are put in our order", function()
        local action = One(Spell("META-ALT-CTRL-SHIFT-F", { global = true }));
        check(action.key == "ALT-CTRL-SHIFT-META-F", action.key);
        action = One(Spell("CTRL-SHIFT-BUTTON3", { default = true }));
        check(action.key == "CTRL-SHIFT-BUTTON3", action.key);
    end);

    test("a META click on the frames is dropped and off them it stays", function()
        None(Spell("META-BUTTON3", { default = true }));
        local action = One(Spell("META-BUTTON3", { default = true, global = true }));
        check(action.key == "META-BUTTON3" and action.casting == nil, "global part kept");
    end);

    test("the bare left and right click are not bound off the frames", function()
        None(Spell("BUTTON1", { hovercast = true }));
        None(Spell("BUTTON2", { global = true }));
        local modified = One(Spell("SHIFT-BUTTON1", { hovercast = true }));
        check(modified.key == "SHIFT-BUTTON1", "a modified click stays");
        local frames = One(Spell("BUTTON1", { default = true, hovercast = true }));
        check(frames.casting and frames.casting.hoverCast == "cast", "on the frames it stays");
    end);

    test("an ooc binding is out of combat and its partners on the key are in it", function()
        local actions = Convert({
            Spell("F", { default = true, ooc = true }),
            { type = "spell", spell = "Regrowth", key = "F", sets = { default = true } },
            { type = "spell", spell = "Regrowth", key = "G", sets = { default = true } },
        });
        check(#actions == 3, #actions .. " actions");
        check(actions[1].conditions and actions[1].conditions.combat == false, "ooc");
        check(actions[2].conditions and actions[2].conditions.combat == true, "partner");
        check(actions[3].conditions == nil, "another key");
        check(actions[1].seq == 1 and actions[2].seq == 2 and actions[3].seq == 1, "seq per key");
    end);

    test("friend and enemy ask the aimed unit, and friend wins over both", function()
        local friend = One(Spell("F", { default = true, friend = true }));
        local unit = friend.conditions and friend.conditions.units and friend.conditions.units["@"];
        check(unit and unit.exists == true and unit.reaction == Constants.REACTION_HELP, "friend");

        local enemy = One(Spell("F", { default = true, enemy = true }));
        unit = enemy.conditions.units["@"];
        check(unit.reaction == Constants.REACTION_HARM, "enemy");

        local both = One(Spell("F", { default = true, friend = true, enemy = true }));
        check(both.conditions.units["@"].reaction == Constants.REACTION_HELP, "both");
    end);

    test("the specialization numbers wait untranslated", function()
        local action = One(Spell("F", { default = true, spec1 = true, spec3 = true }));
        local u = action.untranslated;
        check(u and u.spec1 == true and u.spec3 == true and u.spec2 == nil, "spec sets");
        check(action.conditions == nil or action.conditions.specs == nil, "no specs condition yet");
    end);

    test("each action type lands on ours", function()
        check(One({ type = "target", key = "F", sets = { global = true } }).type == Constants.TARGET,
            "target");

        local menu = One({ type = "menu", key = "SHIFT-BUTTON2", sets = { hovercast = true } });
        check(menu.type == Constants.TOGGLEMENU and menu.casting.hoverCastMode == "unitframe", "menu");

        local body = One({ type = "macro", macrotext = "/cast Regrowth", icon = 136085, key = "F",
            sets = { global = true } });
        check(body.type == Constants.MACROTEXT and body.value == "/cast Regrowth" and body.icon == 136085,
            "macrotext");

        local stored = One({ type = "macro", macro = "Heal", key = "F", sets = { global = true } });
        check(stored.type == Constants.MACRO and stored.value == "Heal", "macro by name");

        local slot = One({ type = "item", item = "13", key = "F", sets = { global = true } });
        check(slot.type == Constants.USESLOT and slot.value == 13, "slot " .. tostring(slot.value));

        local named = One({ type = "item", item = "Healthstone", key = "F", sets = { global = true } });
        check(named.type == Constants.ITEM and named.value == "Healthstone", "item by name");

        None({ type = "item", item = "25", key = "F", sets = { global = true } });
        None({ type = "whatever", key = "F", sets = { global = true } });
        None({ type = "spell", key = "F", sets = { global = true } });
    end);

    test("the payload is General's, from Clique, with no class", function()
        local ME = "Player-1-CLIQUE";
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = {}, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();

        local _, payload = Convert({ Spell("F", { default = true, spec2 = true }) });
        check(payload.source == DebindStorage.SOURCE_CLIQUE, "source " .. tostring(payload.source));
        check(payload.class == nil, "class " .. tostring(payload.class));
        check(payload.dbver == Constants.DB_VERSION, "dbver");
        check(not DebindStorage.PayloadIsImpossible(payload), "refused");

        local placements = DebindStorage.PlanArrival(payload);
        check(#placements == 1 and placements[1].scope == "general", "placed");
        check(placements[1].action.untranslated and placements[1].action.untranslated.spec2 == true,
            "untranslated arrives");

        local filtered = DebindStorage.FilterPayload(payload, { [payload.shared.GENERAL[1]] = true });
        check(filtered.source == DebindStorage.SOURCE_CLIQUE, "a narrowed payload keeps its source");
    end);

    test("the profiles of a CliqueDB3 come with the characters that use them", function()
        local list = DebindStorage.CliqueProfiles({
            profileKeys = { ["Jancity - Fyrakk"] = "Healer", ["Arill - Fyrakk"] = "Healer",
                ["Feeraa - Fyrakk"] = "Feeraa - Fyrakk" },
            profiles = {
                ["Healer"] = { bindings = { Spell("F", { default = true }) } },
                ["Feeraa - Fyrakk"] = { bindings = {} },
                ["Unused"] = { bindings = {} },
            },
        });
        check(#list == 3, #list .. " profiles");
        check(list[1].name == "Feeraa - Fyrakk" and list[2].name == "Healer" and list[3].name == "Unused",
            "sorted");
        check(#list[2].characters == 2 and list[2].characters[1] == "Arill - Fyrakk", "users");
        check(#list[3].characters == 0, "nobody uses it");
        check(#DebindStorage.CliqueProfiles(nil) == 0, "no Clique");
    end);

    return T;
end
