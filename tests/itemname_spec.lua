-- **An `ITEM` action whose value is a name** (`importing-clique-profiles.md` §4).
--
-- The button's `*item-` takes what `/use` takes, so a name goes on it as it is. A number is our item
-- id and goes as `item:%d`. A string of digits is an inventory slot to `*item-`, which is what
-- Clique's `item = "13"` means, and it goes on as it is too.

return function(DebindPrivate, DebindStorage)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local castmod = require("castmod");

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

    local ITEM = Constants.ITEM;
    local ME = "Player-1-ITEMNAME";
    local HEALTHSTONE = 5512;

    local function installWorld()
        for k in pairs(shim.world.items) do
            shim.world.items[k] = nil;
        end
        shim.world.items[HEALTHSTONE] = { name = "Healthstone", icon = 538745 };
    end

    local function Bind(actions)
        _G.UnitGUID = function() return ME; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            shared = { GENERAL = actions, classes = { [Constants.PLAYER_CLASS] = {} } },
            characters = { [ME] = { layers = {}, switches = {} } },
            migrated = {},
            switches = {},
        };
        DebindPrivate.InitDB();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
    end

    local function ItemOn(key)
        local records = castmod.without(Constants, DebindPrivate.KeyMap[key]);
        local record = records and records[1];
        check(record, "nothing on " .. key);
        check(record.clickframe and record.clickbutton, "no button on " .. key);
        return record.clickframe:GetAttribute("*item-" .. record.clickbutton);
    end

    test("a name goes on the button as it is, an id as item:%d", function()
        installWorld();
        Bind({
            { type = ITEM, value = "Healthstone", key = "F1", seq = 1 },
            { type = ITEM, value = HEALTHSTONE, key = "F2", seq = 1 },
            { type = ITEM, value = "Unseen Trinket", key = "F3", seq = 1 },
        });
        check(ItemOn("F1") == "Healthstone", "name: " .. tostring(ItemOn("F1")));
        check(ItemOn("F2") == "item:5512", "id: " .. tostring(ItemOn("F2")));
        check(ItemOn("F3") == "Unseen Trinket", "uncached name: " .. tostring(ItemOn("F3")));
    end);

    -- **A string of digits is a slot and stays one**, as it was in Clique. Read as an id it would
    -- use item 13 instead of the trinket worn there.
    test("a string of digits goes on the button as the slot it names", function()
        installWorld();
        Bind({ { type = ITEM, value = "13", key = "F1", seq = 1 } });
        check(ItemOn("F1") == "13", "slot: " .. tostring(ItemOn("F1")));
    end);

    test("a name is drawn from the cache where it is there, and as itself where not", function()
        installWorld();
        local NameAndIcon = DebindPrivate.DebindUI.NameAndIconForAction;

        local _, icon, name = NameAndIcon({ type = ITEM, value = "Healthstone" });
        check(name == "Healthstone" and icon == 538745, "cached: " .. tostring(name) .. " / " .. tostring(icon));

        _, icon, name = NameAndIcon({ type = ITEM, value = "Unseen Trinket" });
        check(name == "Unseen Trinket" and icon == Constants.QUESTION_MARK_ICON,
            "uncached: " .. tostring(name) .. " / " .. tostring(icon));
    end);

    test("a name converts to /use with the name", function()
        installWorld();
        local function convert(value)
            local action = { type = ITEM, value = value };
            check(DebindPrivate.ConvertToMacroText(action), "the conversion refused " .. tostring(value));
            return action.value;
        end
        check(convert("Healthstone") == "/use Healthstone", "name: " .. convert("Healthstone"));
        check(convert(HEALTHSTONE) == "/use item:5512", "id: " .. convert(HEALTHSTONE));
    end);

    test("a payload holding an item name is taken in", function()
        installWorld();
        Bind({});
        local payload = {
            v = 1, class = Constants.PLAYER_CLASS,
            shared = { GENERAL = { { type = ITEM, value = "Healthstone", key = "F1", seq = 1 } } },
        };
        check(not DebindStorage.PayloadIsImpossible(payload), "the payload was refused");
        local placements = DebindStorage.PlanArrival(payload);
        check(#placements == 1 and placements[1].action.value == "Healthstone",
            "placements: " .. #placements);
    end);

    return T;
end
