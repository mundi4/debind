-- Every key that holds a key record is ours for good, and a press nothing answers does nothing
-- (`dropping-the-game-fallback.md` §2, §3). No WoW client needed.
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

    ---------------------------------------------------------------------------
    -- A key on a live layer whose every action the rebuild leaves out
    ---------------------------------------------------------------------------

    -- **What a rebuild skips because it already knows the answer must not hand the key back.**
    -- Baked, the binding would never win and the press would do nothing; skipped, the key used to
    -- leave the build and the game's own binding went out instead.
    --
    -- Each case asks `IsKeyOurs` beside the bound key, so the function and the key cannot part.
    local function checkOursAndSilent(key)
        check(IsOurs(key), "the key is not ours: " .. Bound(key));
        check(DebindPrivate.IsKeyOurs(key), "the key is bound to us and IsKeyOurs says no");
        check(interp:evalKey(key) == nil, "the press did something");
    end

    local function checkNotOurs(key)
        check(Bound(key) == "", "the key was bound: " .. Bound(key));
        check(not DebindPrivate.IsKeyOurs(key), "the key is not bound and IsKeyOurs says yes");
    end

    -- The shim plays specialization 1.
    local function OtherSpec()
        return { [select(3, UnitClass("player"))] = Constants.SpecIndexFlag(2) };
    end

    test("a key whose one action the specialization condition leaves out stays ours", function()
        Bind({ action({ value = 585, key = "F1", conditions = { specs = OtherSpec() } }) });
        checkOursAndSilent("F1");
    end);

    -- **The frame keeps its click and the key is still ours.** The hover action is click-cast only
    -- and holds nothing, so all that holds the key is the action the condition left out.
    test("a hover action on a mouse button does not stop a left-out action holding the key", function()
        Bind({
            action({ value = 585, key = "SHIFT-BUTTON2", conditions = { units = { unitframe = {} } } }),
            action({ value = 774, key = "SHIFT-BUTTON2", conditions = { specs = OtherSpec() } }),
        });
        checkOursAndSilent("SHIFT-BUTTON2");
    end);

    -- **Negative of the one above.** Without it that case also passes on a rebuild that takes
    -- every mouse button it sees.
    test("a hover action alone leaves its mouse button to the frame", function()
        Bind({ action({ value = 585, key = "SHIFT-BUTTON2", conditions = { units = { unitframe = {} } } }) });
        checkNotOurs("SHIFT-BUTTON2");
    end);

    -- A binding with no way to fire is dropped per key, which left a key holding nothing.
    test("a key whose one action has no way to fire stays ours", function()
        Bind({ action({ type = Constants.PETACTION, value = "PETNOSUCHCOMMAND", key = "F1" }) });
        checkOursAndSilent("F1");
    end);

    -- **An ERROR about the action keeps the key; one about the key lets it go.** Taking the game menu
    -- key would end Escape.
    test("a key the action may not be put on is not taken", function()
        shim.world.bindings = { { action = "TOGGLEGAMEMENU", keys = { "ESCAPE" } } };
        local ok, err = pcall(function()
            Bind({ action({ value = 585, key = "ESCAPE" }) });
            check(DebindPrivate.GetBindingIssue(DebindPrivate.CollectActionsForKey("ESCAPE")[1].action)
                    == Constants.BINDING_ISSUE_NOT_SUPPORTED_GAMEMENU_KEY, "the key carries no key issue");
            -- The game's own binding stays on it, so what is asked is that ours is not. **What is on
            -- it is the world's to say and not what the check reads**: the check is `ESCAPE` itself
            -- now, so this line measures the outcome rather than restating the rule.
            check(Bound("ESCAPE") == "TOGGLEGAMEMENU", "the key was bound: " .. Bound("ESCAPE"));
            check(not DebindPrivate.IsKeyOurs("ESCAPE"), "the key is not bound and IsKeyOurs says yes");
        end);
        shim.world.bindings = {};
        if (not ok) then
            error(err, 0);
        end
    end);

    -- **The bare left and right click are never taken** (`which-action-a-key-runs.md` §7),
    -- and no longer because of an issue: the action there runs over a unit frame or not at all.
    test("the bare left click is not taken", function()
        Bind({ action({ value = 585, key = "BUTTON1" }) });
        checkNotOurs("BUTTON1");
    end);

    return T;
end
