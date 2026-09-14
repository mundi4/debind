-- Every key that holds a key record is ours for good, and a press nothing answers does nothing
-- (`devdocs/dropping-the-game-fallback.md` §2, §3). No WoW client needed.
--
-- **Asked of the emission fixture too**, the one profile shaped to reach every branch of
-- `UpdateBindings.lua`, and not only of keys built to pass: a key that came out unbound there is a
-- key the game still answers for.

return function(DebindPrivate, _, ctx)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
    local frames = require("wow_frames");
    local restricted = require("restricted");

    local T = { passed = 0, failures = {} };

    -- The eval hook is DEBUG-only, and so is everything below that presses a key.
    if (ctx and ctx.shipped) then
        return T;
    end

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

    local function Rebuild()
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        if (not interp) then
            interp = restricted.new(DebindPrivate, shim.world);
        else
            interp:replay(frames.since(mark));
        end
        interp:resetState();
    end

    local seq = 0;
    local function action(t)
        seq = seq + 1;
        t.type = t.type or Constants.SPELL;
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
        Rebuild();
    end

    local function Bound(key)
        return _G.GetBindingAction(key, true) or "";
    end

    local function IsOurs(key)
        local bound = Bound(key);
        return bound:sub(1, 6) == "CLICK "
            and bound:match(":(.*)$") == Constants.CLICKTIME_BUTTON_PREFIX .. key;
    end

    ---------------------------------------------------------------------------
    -- The fixture
    ---------------------------------------------------------------------------

    -- Asked of `KeyMap` rather than of a list written here, so a key the fixture gains is asked too.
    -- A key whose every record is click-cast only holds no key record and is left to the frame.
    test("every key of the emission fixture that holds a key record is ours", function()
        local fixture = assert(loadfile(ctx.root .. "/emit_fixture.lua"))()(DebindPrivate, shim);
        fixture.install();
        Rebuild();

        local notOurs, asked = {}, 0;
        for key, bindings in pairs(DebindPrivate.KeyMap) do
            local holds = false;
            for i = 1, #bindings do
                holds = holds or bindings[i].holdsKey;
            end
            if (holds) then
                asked = asked + 1;
                if (not IsOurs(key)) then
                    notOurs[#notOurs + 1] = key .. "=" .. Bound(key);
                end
            end
        end
        table.sort(notOurs);
        check(asked > 30, "keys asked: " .. asked);
        check(#notOurs == 0, "not ours: " .. table.concat(notOurs, ", "));
    end);

    ---------------------------------------------------------------------------
    -- The three ways a key used to be handed back
    ---------------------------------------------------------------------------

    -- The gap after the last action. Both halves are asked, so a key that never moves cannot pass.
    test("a key with a gap stays ours and does nothing in the gap", function()
        Bind({ action({ value = 585, key = "F1", conditions = { combat = true } }) });

        check(IsOurs("F1"), "the key is not ours out of combat: " .. Bound("F1"));
        check(interp:evalKey("F1") == nil, "something fired in the gap");

        interp.state.combat = true;
        check(IsOurs("F1"), "the key is not ours in combat: " .. Bound("F1"));
        check(interp:evalKey("F1") ~= nil, "the action did not fire in combat");
        interp:resetState();
    end);

    test("an unused action holds the key and does nothing", function()
        Bind({
            action({ value = 585, key = "F1", conditions = { combat = true } }),
            action({ type = Constants.UNUSED, key = "F1" }),
            action({ value = 774, key = "F1" }),
        });

        check(IsOurs("F1"), "the key is not ours: " .. Bound("F1"));
        check(interp:evalKey("F1") == nil, "the action under the unused one fired");
    end);

    test("a command holds the key and does nothing", function()
        Bind({ action({ type = Constants.COMMAND, value = "TOGGLEWORLDMAP", key = "F1" }) });

        check(IsOurs("F1"), "the key is not ours: " .. Bound("F1"));
        check(interp:evalKey("F1") == nil, "the press did something");
    end);

    return T;
end
