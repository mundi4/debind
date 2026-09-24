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

        local filtered = DebindStorage.FilterPayload(payload, { [payload.shared.GENERAL[1]] = true });
        check(filtered.source == DebindStorage.SOURCE_CLIQUE, "a narrowed payload keeps its source");
    end);

    -- **Adding is where the layer and the class are known** (§3), so `PlanArrival` is where a
    -- Clique payload leaves General and its specialization numbers become a condition or go.
    local function FreshProfile()
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
    end

    local function Plan(options)
        FreshProfile();
        local _, payload = Convert({
            Spell("F", { default = true, spec1 = true, spec3 = true }),
            { type = "spell", spell = "Regrowth", key = "G", sets = { default = true, friend = true,
                spec2 = true } },
            { type = "spell", spell = "Regrowth", key = "H", sets = { default = true } },
        });
        local placements = DebindStorage.PlanArrival(payload, options);
        check(#placements == 3, #placements .. " placements");
        return placements;
    end

    local CLASS_ID = Constants.CLASS_IDS[Constants.PLAYER_CLASS];

    test("an added Clique payload lands in the layer picked", function()
        local placements = Plan({ layer = "general" });
        check(placements[1].scope == "general", "general: " .. tostring(placements[1].scope));

        placements = Plan({ layer = "class" });
        check(placements[1].scope == "class" and placements[1].class == Constants.PLAYER_CLASS
            and placements[1].spec == 0, "class: " .. tostring(placements[1].scope));

        placements = Plan({ layer = "character" });
        check(placements[1].scope == "character" and placements[1].spec == 0,
            "character: " .. tostring(placements[1].scope));
    end);

    test("the specialization numbers become this class's condition, or go", function()
        local placements = Plan({ layer = "class", specs = "convert" });
        local specs = placements[1].action.conditions and placements[1].action.conditions.specs;
        check(specs and specs[CLASS_ID] == Constants.SpecIndexFlag(1) + Constants.SpecIndexFlag(3),
            "converted: " .. tostring(specs and specs[CLASS_ID]));
        local second = placements[2].action.conditions;
        check(second.specs[CLASS_ID] == Constants.SpecIndexFlag(2), "beside another condition");
        check(second.units["@"].reaction == Constants.REACTION_HELP, "the other condition kept");
        check(placements[3].action.conditions == nil, "no numbers, no condition");

        placements = Plan({ layer = "character", specs = "drop" });
        check(placements[1].action.conditions == nil, "dropped");
        check(placements[2].action.conditions.specs == nil, "dropped beside another");
    end);

    -- A condition naming one class on a layer every class reads means nothing (§3).
    test("General drops the specialization numbers whatever is asked", function()
        local placements = Plan({ layer = "general", specs = "convert" });
        check(placements[1].action.conditions == nil, "general converted");
    end);

    --- `Plan`'s three actions with the first one's numbers swapped for `sets`.
    local function PlanFirst(sets, options)
        FreshProfile();
        local _, payload = Convert({ Spell("F", sets) });
        return DebindStorage.PlanArrival(payload, options), payload;
    end

    -- The shim's druid has four named specializations and an initial one at 5 (`wow_shim.lua`).
    test("every specialization of this class ticked is no condition at all", function()
        local all = { default = true, spec1 = true, spec2 = true, spec3 = true, spec4 = true };
        local placements, payload = PlanFirst(all, { layer = "class", specs = "convert" });
        check(#placements == 1 and placements[1].action.conditions == nil,
            "converted to a condition on every specialization");
        check(not DebindStorage.CliqueActionHasSpecs(payload.shared.GENERAL[1]), "still asked about");

        placements = PlanFirst(all, { layer = "character", specs = "layers" });
        check(#placements == 1 and placements[1].spec == 0, "spread over the specialization layers");

        local three = { default = true, spec1 = true, spec2 = true, spec3 = true };
        placements, payload = PlanFirst(three, { layer = "class", specs = "convert" });
        check(placements[1].action.conditions and placements[1].action.conditions.specs,
            "three of four read as all of them");
        check(DebindStorage.CliqueActionHasSpecs(payload.shared.GENERAL[1]), "three of four not asked about");
    end);

    test("each specialization's layer gets its own copy", function()
        local placements = PlanFirst({ default = true, spec1 = true, spec3 = true },
            { layer = "class", specs = "layers" });
        check(#placements == 2, #placements .. " placements");
        check(placements[1].scope == "class" and placements[1].class == Constants.PLAYER_CLASS
            and placements[1].spec == 1, "first: " .. tostring(placements[1].spec));
        check(placements[2].scope == "class" and placements[2].spec == 3,
            "second: " .. tostring(placements[2].spec));
        check(placements[1].action ~= placements[2].action, "one table in two layers");
        check(placements[1].action.arrivalID == placements[2].action.arrivalID, "two arrivals");
        for _, placement in ipairs(placements) do
            check(placement.action.conditions == nil, "a condition beside the layer");
            check(placement.action.untranslated == nil, "untranslated left on a copy");
        end

        placements = PlanFirst({ default = true, spec2 = true }, { layer = "character", specs = "layers" });
        check(#placements == 1 and placements[1].scope == "character" and placements[1].spec == 2,
            "character: " .. tostring(placements[1].scope) .. " " .. tostring(placements[1].spec));
    end);

    test("a specialization this class does not have has no layer", function()
        FreshProfile();
        local _, payload = Convert({ Spell("F", { default = true, spec5 = true }) });
        local placements, skipped = DebindStorage.PlanArrival(payload, { layer = "class", specs = "layers" });
        check(#placements == 0 and skipped == 1, #placements .. " placed, " .. tostring(skipped) .. " skipped");
    end);

    test("General takes no specialization layers either", function()
        local placements = PlanFirst({ default = true, spec1 = true, spec3 = true },
            { layer = "general", specs = "layers" });
        check(#placements == 1 and placements[1].scope == "general"
            and placements[1].action.conditions == nil, "general spread");
    end);

    test("nothing untranslated reaches the profile", function()
        for _, options in ipairs({ { layer = "general" }, { layer = "class", specs = "convert" },
                { layer = "character", specs = "drop" } }) do
            for _, placement in ipairs(Plan(options)) do
                check(placement.action.untranslated == nil, "left on an action under " .. options.layer);
            end
        end
    end);

    test("a payload from nowhere we know has its untranslated dropped", function()
        FreshProfile();
        local payload = {
            v = DebindStorage.EXPORT_SCHEMA_VERSION, dbver = Constants.DB_VERSION,
            shared = { GENERAL = { { type = Constants.SPELL, value = "Regrowth", key = "F", seq = 1,
                untranslated = { spec1 = true } } } },
        };
        local placements = DebindStorage.PlanArrival(payload);
        check(placements[1].action.untranslated == nil and placements[1].action.conditions == nil,
            "kept or read");
    end);

    -- **The shim has no deflate or JSON**, so these stand the three client calls in with a table of
    -- known answers. What they hold is the path: which prefix goes where, what each step's failure
    -- is called, and that what comes out is converted and kept. Whether the client reads a real
    -- `CL02:` is a question only the game can answer.
    local function WithEncoding(answers, fn)
        -- `rawget`: the shim reports every read of a global nothing defined, and this one is put
        -- back afterwards rather than used.
        local previous = rawget(_G, "C_EncodingUtil");
        _G.C_EncodingUtil = {
            DecodeHex = function(s)
                if (answers.hex[s] == nil) then error("bad hex"); end
                return answers.hex[s];
            end,
            DecompressString = function(s)
                if (answers.inflate[s] == nil) then error("bad deflate"); end
                return answers.inflate[s];
            end,
            DeserializeJSON = function(s)
                if (answers.json[s] == nil) then error("bad json"); end
                return answers.json[s];
            end,
        };
        local ok, err = pcall(fn);
        _G.C_EncodingUtil = previous;
        if (not ok) then error(err, 0); end
    end

    local CODE_ANSWERS = {
        hex = { ["AB"] = "deflated", ["CD"] = "junk", ["EF"] = "notjson" },
        inflate = { ["deflated"] = "json", ["notjson"] = "text" },
        json = { ["json"] = { Spell("F", { default = true, spec1 = true }) }, ["text"] = "a string" },
    };

    test("a CL02 share code becomes a Clique payload entry", function()
        FreshProfile();
        WithEncoding(CODE_ANSWERS, function()
            local entry, reason = DebindStorage.ImportEntry("  CL02:AB \n", "named");
            check(entry, "refused: " .. tostring(reason));
            check(entry.name == "named", "name " .. tostring(entry.name));
            check(entry.payload.source == DebindStorage.SOURCE_CLIQUE, "source");
            local action = entry.payload.shared.GENERAL[1];
            check(action and action.value == "Rejuvenation" and action.untranslated.spec1 == true,
                "converted");
        end);
    end);

    test("each step of a CL02 code that fails says which", function()
        FreshProfile();
        WithEncoding(CODE_ANSWERS, function()
            local _, reason = DebindStorage.ImportEntry("CL02:ZZ");
            check(reason == "BAD_ENCODING", "hex: " .. tostring(reason));
            _, reason = DebindStorage.ImportEntry("CL02:CD");
            check(reason == "BAD_COMPRESSION", "deflate: " .. tostring(reason));
            _, reason = DebindStorage.ImportEntry("CL02:EF");
            check(reason == "BAD_PAYLOAD", "json: " .. tostring(reason));
        end);
    end);

    -- **`CL01:` is the real thing here**: the libraries Clique made it with are the ones this addon
    -- ships, so the code below is what Clique's `GetExportString` wrote before `CL02:`. Loaded here
    -- rather than left to whichever spec registered them first.
    local repoRoot = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]run%.lua$") or ".";
    for _, path in ipairs({
        "/DebindStorage/Libs/LibDeflate/LibDeflate.lua",
        "/DebindStorage/Libs/LibSerialize/LibSerialize.lua",
    }) do
        assert(loadfile(repoRoot .. path), "could not read " .. path)();
    end

    test("a CL01 share code, as Clique wrote it, becomes a Clique payload entry", function()
        FreshProfile();
        local LibSerialize, LibDeflate = LibStub("LibSerialize"), LibStub("LibDeflate");
        local code = "CL01:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(
            LibSerialize:Serialize({ Spell("F", { default = true, spec2 = true }) })));
        local entry, reason = DebindStorage.ImportEntry(code);
        check(entry, "refused: " .. tostring(reason));
        local action = entry.payload.shared.GENERAL[1];
        check(action and action.value == "Rejuvenation" and action.untranslated.spec2 == true,
            "converted");

        local _;
        _, reason = DebindStorage.ImportEntry(code:sub(1, #code - 10));
        check(reason == "BAD_COMPRESSION" or reason == "BAD_ENCODING" or reason == "BAD_PAYLOAD",
            "a cut code: " .. tostring(reason));
    end);

    test("a Clique profile read off disk is kept as an entry", function()
        FreshProfile();
        local payload = DebindStorage.PayloadFromCliqueBindings({ Spell("F", { default = true }) });
        local entry = DebindStorage.StorePayload(payload, "Healer");
        check(entry and entry.name == "Healer" and entry.payload == payload, "kept");
        check(entry.character == nil, "not marked as made here");
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
