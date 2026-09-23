-- **What the client layer hands the rest of the addon, on each client.** `Debind/Client/` is where
-- the two clients are asked for the same thing in different ways (`preparing-the-code-for-camelot.md`
-- §3), so every case here runs twice: once in the retail world and once in the camelot one, which
-- `run.lua` picks with the spec entry's `client`. A case states what both clients must end up with,
-- and the world decides what it takes to get there.

return function(DebindPrivate)
    local shim = require("wow_shim");
    local camelot = shim.world.client == "camelot";

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

    --- The class ids each world's client has, in its own order.
    local EXPECTED_CLASSES = camelot and { 1, 2, 3, 4, 5, 7, 8, 9, 11 } or { 1, 2, 8, 11 };

    local function Ids(list)
        local out = {};
        for i = 1, #list do
            out[i] = tostring(list[i]);
        end
        return table.concat(out, ",");
    end

    -- **The catalog is where a missing class shows**: the specialization menu, the class masks and
    -- "nothing is selected" all read it. On camelot `GetNumClasses()` is 9 and Druid is index 11,
    -- so a walk to the count stops before Druid.
    test("the class catalog holds every class the client has", function()
        local ids = {};
        for _, entry in ipairs(DebindPrivate.ClassSpecCatalog()) do
            ids[#ids + 1] = entry.id;
        end
        check(Ids(ids) == Ids(EXPECTED_CLASSES),
            "catalog " .. Ids(ids) .. ", client has " .. Ids(EXPECTED_CLASSES));
    end);

    test("a class the client has is one a specialization condition can hold", function()
        check(DebindPrivate.ClassSpecMask(11) ~= 0, "Druid's mask is 0");
    end);

    -- **Offset 5 is named after the skyriding flyout, which camelot does not have and raises for.**
    -- The tooltip line and the condition menu both build these labels on first use, so a raise
    -- there stops both.
    test("every bonus bar offset has a label", function()
        for offset = 0, DebindPrivate.Constants.MAX_BONUSBAR_OFFSET do
            local ok, label = pcall(DebindPrivate.BonusBarLabel, offset);
            check(ok, "offset " .. offset .. " raised: " .. tostring(label));
            check(type(label) == "string" and label:find("^%[bonusbar:" .. offset .. "%]"),
                "offset " .. offset .. " is labelled " .. tostring(label));
        end
    end);

    return T;
end
