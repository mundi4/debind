-- Bringing a payload's switches in, apart from its actions (`importing-switches-apart-from-actions.md`
-- 2-7). `DebindStorage/Import.lua`.
--
-- What has to hold: rows land on this character's addresses (this class's account cells, one
-- picked character's cells, nothing of another class), each row is told apart as new, the same as
-- mine, an overwrite or a fill, and writing takes exactly the ticked rows. A wrong row here changes
-- what the reader's existing actions do, which is the one thing this tab asks before doing.

return function(DebindPrivate, DebindStorage)
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
            error(msg or "assertion failed", 2);
        end
    end

    local Constants = DebindPrivate.Constants;
    local MODES = Constants.SWITCH_MODES;
    local CLASS = Constants.PLAYER_CLASS;
    local GUID = "Player-1-TESTGUID";
    local ALT = "Player-1-ALTDRUID";
    -- **A class the shim plays.** One it does not is turned away by `ImportAddress` before the
    -- class rule this file is about gets a say.
    local MAGE = "Player-1-SOMEMAGE";

    local function Row(mode, resetValue, expr)
        return { mode = mode, resetValue = resetValue, expr = expr };
    end

    --- Mine: `$burst` starting on, with a row on this class's first specialization.
    local function ResetProfile()
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = {} } }, [GUID] = { [CLASS] = {} } },
            characters = { [GUID] = { name = "Tester", class = CLASS } },
            switches = { account = {
                GENERAL = { [0] = { ["$burst"] = Row(MODES.MANUAL, true) } },
                [CLASS] = { [1] = { ["$burst"] = Row(MODES.MANUAL, false) } },
            } },
            migrated = {},
        };
        DebindPrivate.InitDB();
    end

    --- The sender's: `$burst` set differently at the root, the same on spec 1, new on spec 2 and on
    --- an alt of this class; `$fresh`, which this profile has no switch by; a mage's rows, which
    --- this character has no place for.
    local function Payload()
        return {
            v = DebindStorage.PAYLOAD_VERSION, dbver = Constants.DB_VERSION,
            layers = { account = { GENERAL = { [0] = {} } } },
            switches = {
                account = {
                    GENERAL = { [0] = {
                        ["$burst"] = Row(MODES.MANUAL, false),
                        ["$fresh"] = Row(MODES.MANUAL, true),
                    } },
                    [CLASS] = {
                        [0] = { ["$fresh"] = Row(MODES.EXPR, nil, "[combat]") },
                        [1] = { ["$burst"] = Row(MODES.MANUAL, false) },
                        [2] = { ["$burst"] = Row(MODES.IGNORE) },
                    },
                    MAGE = { [0] = { ["$burst"] = Row(MODES.IGNORE) } },
                },
                [ALT] = { [CLASS] = { [0] = { ["$burst"] = Row(MODES.IGNORE) } } },
                [MAGE] = { MAGE = { [0] = { ["$burst"] = Row(MODES.MANUAL, true) } } },
            },
            characters = {
                [ALT] = { name = "Alt", class = CLASS },
                [MAGE] = { name = "Mage", class = "MAGE" },
            },
        };
    end

    local function ItemNamed(items, name)
        for _, item in ipairs(items) do
            if (item.name == name) then
                return item;
            end
        end
    end

    local function RowAt(item, layerID)
        for _, row in ipairs(item.rows) do
            if (row.layerID == layerID) then
                return row;
            end
        end
    end

    local ROOT = 1;
    local CLASS0 = DebindPrivate.GetLayerID(0, false);
    local CLASS1 = DebindPrivate.GetLayerID(1, false);
    local CLASS2 = DebindPrivate.GetLayerID(2, false);
    local CHAR0 = DebindPrivate.GetLayerID(0, true);

    ---------------------------------------------------------------------------
    -- Whose rows
    ---------------------------------------------------------------------------

    test("the dropdown offers this class's characters, and picks the lone one", function()
        ResetProfile();
        local owners, picked = DebindStorage.SwitchImportOwners(Payload());
        check(#owners == 1 and owners[1] == ALT, "owners: " .. table.concat(owners, ","));
        check(picked == ALT, "picked " .. tostring(picked));
    end);

    test("this character's own key is picked over another", function()
        ResetProfile();
        local payload = Payload();
        payload.switches[GUID] = { [CLASS] = { [0] = { ["$burst"] = Row(MODES.IGNORE) } } };
        local owners, picked = DebindStorage.SwitchImportOwners(payload);
        check(#owners == 2, "owners " .. #owners);
        check(picked == GUID, "picked " .. tostring(picked));
    end);

    test("with no character picked, there are no character rows and no other class's", function()
        ResetProfile();
        local items = DebindStorage.BuildSwitchImport(Payload(), nil);
        local burst = ItemNamed(items, "$burst");
        check(burst, "no $burst");
        check(RowAt(burst, CHAR0) == nil, "a character row stood with no character picked");
        for _, row in ipairs(burst.rows) do
            check(row.layerID == ROOT or (row.layerID >= CLASS0 and row.layerID < CHAR0),
                "a row on layer " .. row.layerID);
        end
        local ids = {};
        for _, row in ipairs(burst.rows) do
            ids[#ids + 1] = row.layerID;
        end
        check(#burst.rows == 3, "$burst rows on layers " .. table.concat(ids, ","));
    end);

    test("the picked character's rows land on this character's layers", function()
        ResetProfile();
        local burst = ItemNamed(DebindStorage.BuildSwitchImport(Payload(), ALT), "$burst");
        local row = RowAt(burst, CHAR0);
        check(row and row.incoming.mode == MODES.IGNORE, "the alt's row is not on this character's layer");
    end);

    ---------------------------------------------------------------------------
    -- What each row is
    ---------------------------------------------------------------------------

    test("rows of a switch I have: overwrite and fill start unticked, the same stands ticked and locked", function()
        ResetProfile();
        local burst = ItemNamed(DebindStorage.BuildSwitchImport(Payload(), ALT), "$burst");
        check(not burst.isNew, "$burst read as new");
        local root, same, fill, char = RowAt(burst, ROOT), RowAt(burst, CLASS1), RowAt(burst, CLASS2), RowAt(burst, CHAR0);
        check(root.kind == "overwrite" and not root.checked and not root.locked, "root " .. root.kind);
        check(same.kind == "same" and same.checked and same.locked, "spec 1 " .. same.kind);
        check(fill.kind == "fill" and not fill.checked and not fill.locked, "spec 2 " .. fill.kind);
        check(char.kind == "fill" and not char.checked, "character " .. char.kind);
    end);

    test("rows of a switch I lack: the root ticked and locked, the rest ticked and free", function()
        ResetProfile();
        local fresh = ItemNamed(DebindStorage.BuildSwitchImport(Payload(), nil), "$fresh");
        check(fresh and fresh.isNew and fresh.included, "$fresh is not a new switch taken in");
        local root, class = RowAt(fresh, ROOT), RowAt(fresh, CLASS0);
        check(root.kind == "new" and root.checked and root.locked, "root " .. root.kind);
        check(class.kind == "new" and class.checked and not class.locked, "class " .. class.kind);
    end);

    -- `SetSwitchAnswer` leaves the other answer's fields on a row, so a row that switched from on to
    -- ignore keeps its `resetValue`. It still does what an ignore row does.
    test("a field the row's answer does not read does not make it different", function()
        ResetProfile();
        local db = DebindPrivate.db.global;
        db.switches.account[CLASS][2] = { ["$burst"] = { mode = MODES.IGNORE, resetValue = true, expr = "[combat]" } };
        local burst = ItemNamed(DebindStorage.BuildSwitchImport(Payload(), nil), "$burst");
        check(RowAt(burst, CLASS2).kind == "same", "spec 2 reads " .. RowAt(burst, CLASS2).kind);
    end);

    test("a character row with no layer to land on stands nowhere, and the root is left alone", function()
        ResetProfile();
        local guid = DebindPrivate.playerGUID;
        DebindPrivate.playerGUID = nil;
        local ok, err = pcall(function()
            local items = DebindStorage.BuildSwitchImport(Payload(), ALT);
            local burst = ItemNamed(items, "$burst");
            for _, row in ipairs(burst.rows) do
                check(row.layerID ~= CHAR0, "a character row stood with no character layer to write to");
                row.checked = true;
            end
            DebindStorage.ImportSwitches(items);
            local mode = DebindPrivate.GetSwitchAnswerAt("$burst", nil);
            check(mode ~= MODES.IGNORE, "the character row was written over the root");
        end);
        DebindPrivate.playerGUID = guid;
        check(ok, err);
    end);

    test("the switches come sorted by name and the rows by layer", function()
        ResetProfile();
        local items = DebindStorage.BuildSwitchImport(Payload(), ALT);
        check(items[1].name == "$burst" and items[2].name == "$fresh", "order " .. items[1].name);
        local last = 0;
        for _, row in ipairs(items[1].rows) do
            check(row.layerID > last, "rows out of order");
            last = row.layerID;
        end
    end);

    test("a malformed row and a name no switch can have are left out", function()
        ResetProfile();
        local payload = Payload();
        payload.switches.account.GENERAL[0]["$bad"] = { mode = "sideways" };
        payload.switches.account.GENERAL[0]["$Upper"] = Row(MODES.MANUAL, true);
        payload.switches.account.GENERAL[0]["no spaces"] = Row(MODES.MANUAL, true);
        local items = DebindStorage.BuildSwitchImport(payload, nil);
        check(ItemNamed(items, "$bad") == nil, "a row with a mode nothing knows stood");
        check(ItemNamed(items, "$Upper") == nil, "a name no switch is filed under stood");
        check(ItemNamed(items, "no spaces") == nil, "an invalid name stood");
    end);

    ---------------------------------------------------------------------------
    -- Writing
    ---------------------------------------------------------------------------

    test("writing takes the ticked rows and leaves the rest as mine", function()
        ResetProfile();
        local items = DebindStorage.BuildSwitchImport(Payload(), ALT);
        local burst = ItemNamed(items, "$burst");
        RowAt(burst, CLASS2).checked = true;
        DebindStorage.ImportSwitches(items);

        local mode, resetValue = DebindPrivate.GetSwitchAnswerAt("$burst", nil);
        check(mode == MODES.MANUAL and resetValue == true, "an unticked overwrite was written");
        check(DebindPrivate.GetSwitchAnswerAt("$burst", DebindPrivate.GetSwitchLayerKey(CLASS2)) == MODES.IGNORE,
            "the ticked fill was not written");
        check(DebindPrivate.GetSwitchAnswerAt("$burst", DebindPrivate.GetSwitchLayerKey(CHAR0)) == nil,
            "an unticked character row was written");
    end);

    test("overwriting a row with another answer keeps the expression typed on it", function()
        ResetProfile();
        local db = DebindPrivate.db.global;
        db.switches.account[CLASS][2] = { ["$burst"] = { mode = MODES.EXPR, expr = "[combat,nostealth]" } };
        local items = DebindStorage.BuildSwitchImport(Payload(), nil);
        RowAt(ItemNamed(items, "$burst"), CLASS2).checked = true;
        DebindStorage.ImportSwitches(items);
        local mode, _, expr = DebindPrivate.GetSwitchAnswerAt("$burst", DebindPrivate.GetSwitchLayerKey(CLASS2));
        check(mode == MODES.IGNORE, "the overwrite was not written");
        check(expr == "[combat,nostealth]", "the typed expression became " .. tostring(expr));
    end);

    test("a new switch comes in with its root and the rows left ticked", function()
        ResetProfile();
        local items = DebindStorage.BuildSwitchImport(Payload(), nil);
        DebindStorage.ImportSwitches(items);
        check(DebindPrivate.Switches["$fresh"], "the new switch was not made");
        local mode, resetValue = DebindPrivate.GetSwitchAnswerAt("$fresh", nil);
        check(mode == MODES.MANUAL and resetValue == true, "the root is not the sender's");
        local classMode, _, expr = DebindPrivate.GetSwitchAnswerAt("$fresh", DebindPrivate.GetSwitchLayerKey(CLASS0));
        check(classMode == MODES.EXPR and expr == "[combat]", "the class row is not the sender's");
    end);

    test("a new switch left out is not made", function()
        ResetProfile();
        local items = DebindStorage.BuildSwitchImport(Payload(), nil);
        ItemNamed(items, "$fresh").included = false;
        DebindStorage.ImportSwitches(items);
        check(DebindPrivate.Switches["$fresh"] == nil, "a switch left out was made");
    end);

    test("after writing, the rows read as the same as mine", function()
        ResetProfile();
        local items = DebindStorage.BuildSwitchImport(Payload(), nil);
        RowAt(ItemNamed(items, "$burst"), ROOT).checked = true;
        DebindStorage.ImportSwitches(items);
        local again = ItemNamed(DebindStorage.BuildSwitchImport(Payload(), nil), "$burst");
        check(RowAt(again, ROOT).kind == "same", "the written root reads " .. RowAt(again, ROOT).kind);
        local fresh = ItemNamed(DebindStorage.BuildSwitchImport(Payload(), nil), "$fresh");
        check(not fresh.isNew and RowAt(fresh, ROOT).kind == "same", "the made switch still reads as new");
    end);

    return T;
end
