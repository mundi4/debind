-- **Keys handed to the game while something else needs them** (`devdocs/giving-keys-back.md`).
--
-- The whole of the answer lives in the restricted environment, so the question this file asks is
-- the one `boundkey_spec.lua` opened: what does the client say the key is bound to. The body runs
-- through `UpdateGivenBackKeys`, `ClearBinding` and `SetBindingClick` write the override table, and
-- `GetBindingAction(key, true)` reads it back.
--
-- What is **not** here, and cannot be: whether the game's own binding really answers once ours is
-- off, and whether the transition arrives at all. Blizzard's manager resolves the driver, and no
-- manager runs here.

return function(DebindPrivate)
    local Constants = DebindPrivate.Constants;
    local shim = require("wow_shim");
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

    local GUID = "Player-1-GIVEBACK";
    local interp;

    --- The client's own bindings on the twelve action buttons. **Two keys on the first**, the way
    --- the probe found `ACTIONBUTTON1` on xptr, so "only the first key" has something to cut.
    local function BindingWorld()
        local bindings = {
            { action = "ACTIONBUTTON1", keys = { "1", "BUTTON3" } },
        };
        for i = 2, 12 do
            bindings[#bindings + 1] = { action = "ACTIONBUTTON" .. i, keys = { tostring(i) } };
        end
        shim.world.bindings = bindings;
    end

    --- One Debind action per action button key, so every key the body could hand over is one we
    --- hold. A key we do not hold is not in `BoundKeys` and the body has nothing to do with it.
    local function Actions()
        local actions = {};
        local keys = { "1", "BUTTON3", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" };
        for i = 1, #keys do
            actions[i] = { type = Constants.SPELL, value = 585, key = keys[i], seq = 1 };
        end
        return actions;
    end

    --- Puts the world back the way every case starts. **Also run before the rebuild**, because the
    --- rebuild ends by working the keys out again and would otherwise do it against whatever the
    --- case before left standing.
    local function ResetWorld()
        if (interp) then
            interp:resetState();
            interp.state.actionBarPage = 1;
        end
        _G.OverrideActionBar:Hide();
    end

    local function Bind(options)
        BindingWorld();
        ResetWorld();
        _G.UnitGUID = function() return GUID; end
        _G.DebindVars = {
            dbver = Constants.DB_VERSION,
            options = options,
            shared = { GENERAL = Actions(), classes = { [Constants.PLAYER_CLASS] = {} } },
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
        ResetWorld();
    end

    --- One pass of the body, which is what the driver's transition costs in the game.
    local function Pass()
        interp.driverHandle:RunAttribute("UpdateGivenBackKeys");
    end

    --- A rebuild on the profile already loaded, **with the state left as it is.** `Bind` resets it,
    --- and the case this is for is a rebuild that happens while a state is standing.
    local function Rebuild()
        local mark = frames.mark();
        check(DebindPrivate.UpdateBindings() == true, "the rebuild declined");
        interp:replay(frames.since(mark));
    end

    --- Is the key still ours. Every type this addon binds goes out through a click button, so the
    --- prefix is the whole of what being held looks like from outside (`boundkey_spec.lua`).
    local function IsOurs(key)
        return (_G.GetBindingAction(key, true) or ""):sub(1, 6) == "CLICK ";
    end

    local function GoneAndBack(key, msg)
        check(not IsOurs(key), msg .. ": the key did not go over");
        interp:resetState();
        _G.OverrideActionBar:Hide();
        Pass();
        check(IsOurs(key), msg .. ": the key did not come back");
    end

    ---------------------------------------------------------------------------
    -- Which buttons are live
    ---------------------------------------------------------------------------

    -- **Twelve on a bar with no skin**, which is the possession and the unskinned vehicle. The
    -- twelfth is the one that says the count is not six.
    test("an unskinned replaced bar hands over all twelve", function()
        Bind({ giveBackOnReplacedBar = true });
        interp.state.vehiclebar = true;
        Pass();

        check(not IsOurs("1"), "button 1's key stayed ours");
        check(not IsOurs("12"), "button 12's key stayed ours");
        GoneAndBack("6", "button 6");
    end);

    -- **Six on a skinned bar**, because `GetActionButtonForID` answers nil past
    -- `NUM_OVERRIDE_BUTTONS` and the game's own binding does nothing there. Handing 7 to 12 over
    -- would make those keys dead rather than useful.
    test("a skinned replaced bar stops at six", function()
        Bind({ giveBackOnReplacedBar = true });
        interp.state.overridebar = true;
        _G.OverrideActionBar:Show();
        Pass();

        check(not IsOurs("6"), "button 6's key stayed ours");
        check(IsOurs("7"), "button 7's key went over on a skinned bar");
        check(IsOurs("12"), "button 12's key went over on a skinned bar");

        _G.OverrideActionBar:Hide();
    end);

    -- **Five in a battle**, and the sixth is where the bar goes on past the abilities.
    test("a pet battle hands over the first five", function()
        Bind();
        interp.state.petbattle = true;
        Pass();

        check(not IsOurs("5"), "button 5's key stayed ours");
        check(IsOurs("6"), "button 6's key went over in a battle");
        GoneAndBack("1", "button 1");
    end);

    ---------------------------------------------------------------------------
    -- The rows and what narrows them
    ---------------------------------------------------------------------------

    -- **A row nobody turned on takes nothing.** The replaced bar row is off with the value absent,
    -- so this is the state every existing profile is in.
    test("the replaced bar row off leaves every key ours", function()
        Bind();
        interp.state.vehiclebar = true;
        Pass();

        check(IsOurs("1"), "button 1's key went over with the row off");
        check(IsOurs("12"), "button 12's key went over with the row off");
    end);

    -- **The pet battle row is the other way round**: on with the value absent, so it has to be
    -- turned off by hand. A battle ability cannot be reached from a key any other way.
    test("the pet battle row is on until the reader turns it off", function()
        Bind();
        interp.state.petbattle = true;
        Pass();
        check(not IsOurs("1"), "the row was not on with no value stored");

        Bind({ giveBackInPetBattle = false });
        interp.state.petbattle = true;
        Pass();
        check(IsOurs("1"), "button 1's key went over with the row off");
    end);

    -- **Every key a command has goes over, not one of them.** Which of the two the keybinding
    -- screen showed first is not kept across a reload (2026-09-18, measured), so holding one back
    -- would hold back a different key each login.
    test("both of a command's keys go over", function()
        Bind({ giveBackOnReplacedBar = true });
        interp.state.vehiclebar = true;
        Pass();

        check(not IsOurs("1"), "the first key stayed ours");
        check(not IsOurs("BUTTON3"), "the second key stayed ours");
    end);

    -- **An empty button is not worth a key.** The slot is the vehicle page's, which is where the
    -- body looks and not where the reader's own page is.
    test("an empty slot keeps its key when the reader asked for that", function()
        Bind({ giveBackOnReplacedBar = true, giveBackWhenActionExists = true });
        interp.state.vehiclebar = true;
        -- Page 16 (`GetVehicleBarIndex`), so button 3 is slot 3 + 15 * 12.
        interp.state.emptySlots[3 + 15 * 12] = true;
        Pass();

        check(IsOurs("3"), "the empty button's key went over");
        check(not IsOurs("4"), "a filled button's key stayed ours");
    end);

    -- **Without the narrowing it goes over anyway**, which is what makes the case above the
    -- option's doing rather than the slot's.
    test("an empty slot goes over while the narrowing is off", function()
        Bind({ giveBackOnReplacedBar = true });
        interp.state.vehiclebar = true;
        interp.state.emptySlots[3 + 15 * 12] = true;
        Pass();

        check(not IsOurs("3"), "the empty button's key stayed ours");
    end);

    ---------------------------------------------------------------------------
    -- Coming back
    ---------------------------------------------------------------------------

    -- **The reader can rebind a command in the middle of a fight**, and the key that went over is
    -- then no longer the key that command answers to. What comes back is worked out from the keys
    -- we hold rather than from the commands, so the old one is not left off for good.
    test("a key rebound while it was over still comes back", function()
        Bind({ giveBackOnReplacedBar = true });
        interp.state.vehiclebar = true;
        Pass();
        check(not IsOurs("4"), "button 4's key did not go over");

        shim.world.bindings[4].keys = { "F4" };
        interp:resetState();
        Pass();

        check(IsOurs("4"), "the key stayed off after the command moved");
    end);

    -- **A rebuild inside one of these states has to work the keys out again itself.** It takes
    -- every override off and puts them all back, and the driver does not fire: the manager writes
    -- the attribute only when the value moves, and the value has not moved. A pet battle is where
    -- this shows, since it is not a combat lockdown and a rebuild really does run inside one.
    test("a rebuild in the middle of a state hands the keys over again", function()
        Bind();
        interp.state.petbattle = true;
        Pass();
        check(not IsOurs("1"), "button 1's key did not go over");

        Rebuild();
        check(not IsOurs("1"), "the rebuild took the key back and never handed it over again");
        check(IsOurs("6"), "a key outside the battle's five did not come back");
    end);

    --- Counts the binding calls one pass makes. **Nothing else can see them**: they land in the
    --- override table rather than in the recording, so a pass that made none and a pass that made
    --- twelve leave the same table behind once the state has settled.
    local function BindingCalls()
        local handle = interp.driverHandle;
        local clear, set = handle.ClearBinding, handle.SetBindingClick;
        local calls = 0;
        handle.ClearBinding = function(...) calls = calls + 1; return clear(...); end
        handle.SetBindingClick = function(...) calls = calls + 1; return set(...); end
        Pass();
        handle.ClearBinding, handle.SetBindingClick = nil, nil;
        return calls;
    end

    -- **A pass that decides the same thing touches nothing.** One slot per key holds what is in
    -- force, which is the shape the addon opened with (`bindings.bound`, initial commit), and the
    -- driver fires on every transition whether or not this one moved anything.
    test("a second pass in the same state makes no binding call", function()
        Bind({ giveBackOnReplacedBar = true });
        interp.state.vehiclebar = true;
        -- Thirteen rather than twelve: `ACTIONBUTTON1` has two keys in this world.
        local first = BindingCalls();
        check(first == 13, "the first pass handed over " .. first .. " keys");
        local second = BindingCalls();
        check(second == 0, "a repeat pass made " .. second .. " binding calls");
    end);

    return T;
end
